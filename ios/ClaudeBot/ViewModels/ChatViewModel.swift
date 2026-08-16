import Foundation
import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.claudebot", category: "ChatVM")

struct TaskStatus {
    var mode: String = ""
    var phase: String = ""
    var step: Int = 0
    var active: Bool = false
}

struct PendingAction: Equatable {
    let text: String
    let buttons: [[InlineButton]]
    let messageId: Int

    static func == (lhs: PendingAction, rhs: PendingAction) -> Bool {
        lhs.messageId == rhs.messageId
    }
}

@MainActor @Observable
final class ChatViewModel {
    // MARK: - State

    var messages: [ChatMessage] = []
    var connectionState: ConnectionState = .disconnected
    var currentSession: String = ""
    var showSettings: Bool = false
    var scrollTrigger: Int = 0
    var taskStatus = TaskStatus()
    var isBotBusy = false
    var activeTasks: [String: ActiveTask] = [:]
    var scheduledTasks: [ScheduledTask] = []
    var isSwitchingSession = false
    var pendingAction: PendingAction?
    var sessionList: [SessionInfo] = []
    var sessionFilter: String?
    var availableSessions: [String] = []
    var isLoadingMore = false
    var allLoaded = false
    var searchQuery = ""
    var searchResults: [ChatMessage] = []
    var isSearching = false
    var searchHasMore = false

    // MARK: - Computed

    var effectiveSession: String {
        sessionFilter ?? currentSession
    }

    var isViewingOtherSession: Bool {
        guard let filter = sessionFilter else { return false }
        return filter != currentSession
    }

    // MARK: - Private

    let settings: SettingsStore
    private let wsManager = WebSocketManager()
    private(set) var apiClient: APIClient!
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    private var idToIndex: [Int: Int] = [:]
    private var localIdCounter = -1
    private var dbOffset = 0
    private var searchOffset = 0
    private var filterGeneration = 0

    private var streamingMessageIds = Set<Int>()
    private var pendingIncomingMessageIds = Set<Int>()
    private var persistedMessageIds = Set<Int>()
    private var finalizedMessageIds = Set<Int>()
    private var lastStreamPersist: [Int: Date] = [:]
    private let streamPersistInterval: TimeInterval = 2.0

    private static let pageSize = 50
    private static let searchPageSize = 30

    // MARK: - Init

    init(settings: SettingsStore) {
        self.settings = settings
        self.apiClient = APIClient(settings: settings)
        self.showSettings = !settings.isConfigured

        // Setup SwiftData
        do {
            let schema = Schema([MessageEntity.self])
            let config = ModelConfiguration(schema: schema)
            let container = try ModelContainer(for: schema, configurations: [config])
            self.modelContainer = container
            self.modelContext = ModelContext(container)
        } catch {
            logger.error("SwiftData init failed: \(error.localizedDescription)")
        }

        // Configure WS callbacks
        Task {
            await wsManager.configure(
                onMessage: { [weak self] msg in self?.handleWsMessage(msg) },
                onStateChange: { [weak self] state in self?.handleStateChange(state) },
                onServerRestart: { [weak self] in self?.handleServerRestart() },
                onSeqUpdate: { [weak self] seq, serverId in
                    self?.settings.updateWsState(seq: seq, serverId: serverId)
                },
                onError: { [weak self] message in
                    self?.settings.wsLastError = message
                }
            )

            // Load persisted data
            await loadPersistedIds()
            await loadInitialMessages()
            await fetchLocalSessions()
            if messages.count > 0 { scrollTrigger += 1 }

            if settings.isConfigured {
                let (lastSeq, serverId) = settings.getWsState()
                await wsManager.restoreState(seq: lastSeq, serverId: serverId)
                connect()
            }
        }
    }

    // MARK: - Connection

    func connect() {
        guard settings.isConfigured else { return }
        Task { await wsManager.connect(wsUrl: settings.wsUrl()) }
    }

    func disconnect() {
        Task { await wsManager.disconnect() }
    }

    func reconnect() {
        disconnect()
        connect()
    }

    private func handleStateChange(_ state: ConnectionState) {
        connectionState = state
        settings.wsLastState = state.rawValue
        if state == .connected {
            settings.wsLastError = ""
            fetchActiveTasks()
            fetchSessions()
        }
    }

    private func handleServerRestart() {
        isBotBusy = false
        taskStatus = TaskStatus()
        activeTasks.removeAll()
        isSwitchingSession = false
    }

    // MARK: - Messages

    func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        let localId = localIdCounter
        localIdCounter -= 1

        let msg = ChatMessage(messageId: localId, text: text, isFromBot: false)
        messages.append(msg)
        if localId != 0 { idToIndex[localId] = messages.count - 1 }
        scrollTrigger += 1

        // Persist locally
        persistMessage(msg)
        dbOffset += 1

        // Session-changing commands
        let cmd = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let isSessionCmd = ["/switch", "/new", "/resume", "/end", "/delete"].contains(cmd)
        if isSessionCmd { isSwitchingSession = true }

        Task {
            await apiClient.sendMessage(text)
            if isSessionCmd {
                await MainActor.run { self.isSwitchingSession = false }
            }
        }
    }

    func pressButton(messageId: Int, button: InlineButton) {
        // Clear pending action if matching
        if pendingAction?.messageId == messageId { pendingAction = nil }
        // Remove buttons from message
        if let idx = findMessageIndex(messageId), idx < messages.count {
            messages[idx].buttons = []
            updateMessageInDB(messages[idx])
        }
        Task { await apiClient.sendCallback(data: button.callbackData, messageId: messageId) }
    }

    func dismissPendingAction() {
        pendingAction = nil
    }

    // MARK: - Session Management

    func fetchSessions() {
        Task {
            let sessions = await apiClient.fetchSessions()
            let active = sessions.first(where: { $0.isActive })?.name
            sessionList = sessions
            if let active, !active.isEmpty {
                currentSession = active
            }
        }
    }

    func switchSession(_ name: String) {
        sendMessage("/switch \(name)")
    }

    func setSessionFilter(_ session: String?) {
        sessionFilter = session
        let viewing = session ?? currentSession
        isBotBusy = !viewing.isEmpty && activeTasks[viewing] != nil
        filterGeneration += 1
        let gen = filterGeneration
        messages.removeAll()
        idToIndex.removeAll()
        dbOffset = 0
        allLoaded = false
        isLoadingMore = false

        Task {
            let loaded = await loadMessagesFromDB(session: session, offset: 0)
            guard gen == filterGeneration else { return }
            messages = loaded.reversed()
            rebuildIndex()
            dbOffset = loaded.count
            if loaded.count < Self.pageSize { allLoaded = true }
            if !messages.isEmpty { scrollTrigger += 1 }
        }
    }

    func viewTaskSession(_ sessionName: String) {
        setSessionFilter(sessionName)
    }

    func quickSwitchToFilteredSession() {
        guard let target = sessionFilter else { return }
        switchSession(target)
        setSessionFilter(nil)
    }

    func clearSessionFilter() {
        setSessionFilter(nil)
    }

    func fetchLocalSessions() async {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.session != "" },
            sortBy: [SortDescriptor(\.session)]
        )
        if let entities = try? ctx.fetch(descriptor) {
            let sessions = Set(entities.map(\.session)).sorted()
            availableSessions = sessions
        }
    }

    // MARK: - Pagination

    func loadMore() {
        guard !isLoadingMore, !allLoaded else { return }
        isLoadingMore = true
        let gen = filterGeneration
        let filter = sessionFilter
        let currentOffset = dbOffset

        Task {
            let loaded = await loadMessagesFromDB(session: filter, offset: currentOffset)
            guard gen == filterGeneration else {
                isLoadingMore = false
                return
            }
            if loaded.isEmpty {
                allLoaded = true
            } else {
                let older = loaded.reversed()
                messages.insert(contentsOf: older, at: 0)
                dbOffset += loaded.count
                rebuildIndex()
                if loaded.count < Self.pageSize { allLoaded = true }
            }
            isLoadingMore = false
        }
    }

    // MARK: - Search

    func search(_ query: String) {
        searchQuery = query
        guard !query.isEmpty else {
            searchResults.removeAll()
            isSearching = false
            return
        }
        isSearching = true
        searchOffset = 0
        Task {
            let results = await searchDB(query: query, offset: 0)
            searchResults = results.map { $0.toChatMessage() }
            searchOffset = results.count
            searchHasMore = results.count >= Self.searchPageSize
            isSearching = false
        }
    }

    func searchMore() {
        guard !isSearching, searchHasMore, !searchQuery.isEmpty else { return }
        isSearching = true
        Task {
            let results = await searchDB(query: searchQuery, offset: searchOffset)
            searchResults.append(contentsOf: results.map { $0.toChatMessage() })
            searchOffset += results.count
            searchHasMore = results.count >= Self.searchPageSize
            isSearching = false
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults.removeAll()
        isSearching = false
        searchHasMore = false
    }

    // MARK: - Active Tasks

    func fetchActiveTasks() {
        Task {
            let tasks = await apiClient.fetchActiveTasks()
            let stale = Set(activeTasks.keys).subtracting(tasks.keys)
            for key in stale { activeTasks.removeValue(forKey: key) }
            activeTasks.merge(tasks) { _, new in new }
            let viewing = effectiveSession
            isBotBusy = !viewing.isEmpty && tasks[viewing] != nil
        }
    }

    func cancelTask(_ sessionName: String) {
        activeTasks.removeValue(forKey: sessionName)
        Task { await apiClient.cancelTask(session: sessionName) }
    }

    func pauseTask(_ sessionName: String) {
        if var task = activeTasks[sessionName] {
            task.paused = true
            activeTasks[sessionName] = task
        }
        Task { await apiClient.pauseTask(session: sessionName) }
    }

    func resumeTask(_ sessionName: String) {
        if var task = activeTasks[sessionName] {
            task.paused = false
            activeTasks[sessionName] = task
        }
        Task { await apiClient.resumeTask(session: sessionName) }
    }

    // MARK: - Scheduled Tasks

    func fetchScheduledTasks() {
        Task {
            let tasks = await apiClient.fetchScheduledTasks()
            scheduledTasks = tasks
        }
    }

    func createScheduledTask(sessionName: String, prompt: String, scheduleType: String, cronExpr: String?, runAt: String?) {
        Task {
            await apiClient.createScheduledTask(sessionName: sessionName, prompt: prompt, scheduleType: scheduleType, cronExpr: cronExpr, runAt: runAt)
        }
    }

    func toggleScheduledTask(_ taskId: String, enabled: Bool) {
        if let idx = scheduledTasks.firstIndex(where: { $0.id == taskId }) {
            scheduledTasks[idx].enabled = enabled
        }
        Task { await apiClient.toggleScheduledTask(id: taskId, enabled: enabled) }
    }

    func updateScheduledTask(_ taskId: String, prompt: String?, cronExpr: String?, runAt: String?) {
        Task {
            await apiClient.updateScheduledTask(id: taskId, prompt: prompt, cronExpr: cronExpr, runAt: runAt)
            fetchScheduledTasks()
        }
    }

    func triggerScheduledTask(_ taskId: String) {
        Task { await apiClient.triggerScheduledTask(id: taskId) }
    }

    func deleteScheduledTask(_ taskId: String) {
        scheduledTasks.removeAll { $0.id == taskId }
        Task { await apiClient.deleteScheduledTask(id: taskId) }
    }

    // MARK: - WS Message Handling

    private func handleWsMessage(_ msg: WsMessage) {
        switch msg.type {
        case "stream":
            handleStreamEvent(msg)
        case "message":
            handleMessageEvent(msg)
        case "edit":
            handleEditEvent(msg)
        case "status":
            handleStatusEvent(msg)
        case "active_session":
            if !msg.session.isEmpty { currentSession = msg.session }
        case "schedule":
            fetchScheduledTasks()
        default:
            break
        }
    }

    private func handleMessageEvent(_ msg: WsMessage) {
        let mid = msg.messageId ?? 0
        if mid > 0 && streamingMessageIds.contains(mid) { return }
        if mid > 0 && findMessageIndex(mid) != nil { return }
        if mid > 0 && msg.isReplay && persistedMessageIds.contains(mid) { return }
        if mid > 0 && pendingIncomingMessageIds.contains(mid) { return }

        let chatMsg = ChatMessage(
            messageId: mid, text: msg.text, isFromBot: true,
            session: msg.session, isReplay: msg.isReplay,
            buttons: msg.buttons
        )

        let showInUi = matchesSessionFilter(msg.session)
        if showInUi {
            messages.append(chatMsg)
            if mid > 0 { idToIndex[mid] = messages.count - 1 }
            scrollTrigger += 1
        }
        if mid > 0 {
            persistedMessageIds.insert(mid)
            pendingIncomingMessageIds.insert(mid)
        }

        // Pending action
        let actionable = !msg.buttons.flatMap({ $0 }).isEmpty
        if actionable && showInUi {
            pendingAction = PendingAction(text: msg.text, buttons: msg.buttons, messageId: mid)
        }

        if !msg.session.isEmpty && !availableSessions.contains(msg.session) {
            availableSessions.append(msg.session)
        }

        // Persist
        persistMessage(chatMsg, upsert: mid > 0)
        if showInUi { dbOffset += 1 }
        if mid > 0 { pendingIncomingMessageIds.remove(mid) }
    }

    private func handleEditEvent(_ msg: WsMessage) {
        guard let mid = msg.messageId else { return }
        if streamingMessageIds.contains(mid) { return }

        if let idx = findMessageIndex(mid) {
            messages[idx].text = msg.text
            if !msg.session.isEmpty { messages[idx].session = msg.session }
            messages[idx].isReplay = messages[idx].isReplay || msg.isReplay
            if idx == messages.count - 1 { scrollTrigger += 1 }
            updateMessageInDB(messages[idx])
        } else {
            if msg.isReplay && persistedMessageIds.contains(mid) { return }
            let chatMsg = ChatMessage(
                messageId: mid, text: msg.text, isFromBot: true,
                session: msg.session, isReplay: msg.isReplay
            )
            persistedMessageIds.insert(mid)
            if matchesSessionFilter(msg.session) {
                messages.append(chatMsg)
                idToIndex[mid] = messages.count - 1
                scrollTrigger += 1
                dbOffset += 1
            }
            persistMessage(chatMsg, upsert: true)
        }
    }

    private func handleStatusEvent(_ msg: WsMessage) {
        let isCurrentSession = msg.session.isEmpty || msg.session == effectiveSession
        if msg.mode == "busy" {
            if isCurrentSession { isBotBusy = msg.active }
            fetchActiveTasks()
        } else {
            if isCurrentSession {
                taskStatus = TaskStatus(mode: msg.mode, phase: msg.phase, step: msg.step, active: msg.active)
                isBotBusy = msg.active
            }
            let sessionName = msg.session
            if !sessionName.isEmpty && ["omni", "justdoit", "deepreview"].contains(msg.mode) {
                if msg.active {
                    let existing = activeTasks[sessionName]
                    activeTasks[sessionName] = ActiveTask(
                        mode: msg.mode, session: sessionName,
                        task: msg.task.isEmpty ? (existing?.task ?? "") : msg.task,
                        phase: msg.phase, step: msg.step,
                        started: msg.started > 0 ? msg.started : (existing?.started ?? 0),
                        paused: msg.paused
                    )
                } else {
                    activeTasks.removeValue(forKey: sessionName)
                }
            }
        }
    }

    private func handleStreamEvent(_ msg: WsMessage) {
        guard let mid = msg.messageId else { return }

        switch msg.op {
        case "start":
            streamingMessageIds.insert(mid)
            if let existing = findMessageIndex(mid) {
                if messages[existing].text.contains("———") {
                    streamingMessageIds.remove(mid)
                    return
                }
                messages[existing].text = ""
                messages[existing].isReplay = messages[existing].isReplay || msg.isReplay
                if existing == messages.count - 1 { scrollTrigger += 1 }
                return
            }
            if msg.isReplay && finalizedMessageIds.contains(mid) {
                streamingMessageIds.remove(mid)
                return
            }
            let chatMsg = ChatMessage(messageId: mid, text: "", isFromBot: true, session: msg.session, isReplay: msg.isReplay)
            persistedMessageIds.insert(mid)
            if !msg.session.isEmpty && !availableSessions.contains(msg.session) {
                availableSessions.append(msg.session)
            }
            if matchesSessionFilter(msg.session) {
                messages.append(chatMsg)
                idToIndex[mid] = messages.count - 1
                scrollTrigger += 1
            }
            persistMessage(chatMsg, upsert: true)
            lastStreamPersist[mid] = Date()

        case "skip":
            streamingMessageIds.insert(mid)

        case "append":
            if !streamingMessageIds.contains(mid) { streamingMessageIds.insert(mid) }
            var idx = findMessageIndex(mid)
            if idx == nil {
                if msg.isReplay && finalizedMessageIds.contains(mid) { return }
                guard matchesSessionFilter(msg.session) else { return }
                let chatMsg = ChatMessage(messageId: mid, text: "", isFromBot: true, session: msg.session, isReplay: msg.isReplay)
                messages.append(chatMsg)
                idToIndex[mid] = messages.count - 1
                persistedMessageIds.insert(mid)
                persistMessage(chatMsg, upsert: true)
                lastStreamPersist[mid] = Date()
                idx = messages.count - 1
            }
            guard let appendIdx = idx else { return }
            if messages[appendIdx].text.contains("———") {
                streamingMessageIds.remove(mid)
                lastStreamPersist.removeValue(forKey: mid)
                finalizedMessageIds.insert(mid)
                return
            }
            // Strip tool status line
            var currentText = messages[appendIdx].text
            if currentText.hasSuffix("\u{200B}") {
                if let lastNl = currentText.dropLast().lastIndex(of: "\n") {
                    currentText = String(currentText[currentText.startIndex..<lastNl])
                } else {
                    currentText = ""
                }
            }
            let newText = currentText + msg.text
            messages[appendIdx].text = newText
            messages[appendIdx].isReplay = messages[appendIdx].isReplay || msg.isReplay
            if appendIdx == messages.count - 1 { scrollTrigger += 1 }
            // Debounced persist
            let now = Date()
            let lastPersist = lastStreamPersist[mid] ?? .distantPast
            if now.timeIntervalSince(lastPersist) >= streamPersistInterval {
                lastStreamPersist[mid] = now
                updateMessageInDB(messages[appendIdx])
            }

        case "tool":
            if let idx = findMessageIndex(mid) {
                var currentText = messages[idx].text
                if currentText.hasSuffix("\u{200B}") {
                    if let lastNl = currentText.dropLast().lastIndex(of: "\n") {
                        currentText = String(currentText[currentText.startIndex..<lastNl])
                    } else {
                        currentText = ""
                    }
                }
                let toolLine = formatToolStatus(tool: msg.tool, path: msg.path)
                messages[idx].text = currentText + "\n" + toolLine + "\u{200B}"
                if idx == messages.count - 1 { scrollTrigger += 1 }
            }

        case "done":
            streamingMessageIds.remove(mid)
            lastStreamPersist.removeValue(forKey: mid)
            let doneExisting = findMessageIndex(mid)
            if let existIdx = doneExisting, messages[existIdx].text.contains("———") { return }
            let parsedChanges = msg.fileChanges.map { fc in
                FileChange(type: fc["type"] ?? "", path: fc["path"] ?? "", old: fc["old"] ?? "", new: fc["new"] ?? "", content: fc["content"] ?? "")
            }
            let status = msg.cancelled ? "\u{26A0}\u{FE0F} _cancelled_" : "\u{2713} _complete_"
            let finalText = "\(msg.text)\n\n\u{2014}\u{2014}\u{2014}\n\(status)"

            if let idx = doneExisting {
                messages[idx].text = finalText
                if !msg.session.isEmpty { messages[idx].session = msg.session }
                messages[idx].isReplay = messages[idx].isReplay || msg.isReplay
                messages[idx].fileChanges = parsedChanges
                if idx == messages.count - 1 { scrollTrigger += 1 }
                persistedMessageIds.insert(mid)
                finalizedMessageIds.insert(mid)
                updateMessageInDB(messages[idx])
            } else {
                if msg.isReplay && finalizedMessageIds.contains(mid) { return }
                let chatMsg = ChatMessage(
                    messageId: mid, text: finalText, isFromBot: true,
                    session: msg.session, isReplay: msg.isReplay,
                    fileChanges: parsedChanges
                )
                persistedMessageIds.insert(mid)
                finalizedMessageIds.insert(mid)
                if !msg.session.isEmpty && !availableSessions.contains(msg.session) {
                    availableSessions.append(msg.session)
                }
                if matchesSessionFilter(msg.session) {
                    messages.append(chatMsg)
                    idToIndex[mid] = messages.count - 1
                    scrollTrigger += 1
                }
                persistMessage(chatMsg, upsert: true)
            }

        default:
            break
        }
    }

    // MARK: - Helpers

    private func matchesSessionFilter(_ session: String) -> Bool {
        guard let filter = sessionFilter else { return true }
        return session == filter
    }

    private func findMessageIndex(_ messageId: Int) -> Int? {
        guard messageId != 0 else { return nil }
        if let idx = idToIndex[messageId], idx < messages.count, messages[idx].messageId == messageId {
            return idx
        }
        if let fallback = messages.lastIndex(where: { $0.messageId == messageId }) {
            idToIndex[messageId] = fallback
            return fallback
        }
        idToIndex.removeValue(forKey: messageId)
        return nil
    }

    private func rebuildIndex() {
        idToIndex.removeAll()
        for (idx, msg) in messages.enumerated() {
            if msg.messageId != 0 { idToIndex[msg.messageId] = idx }
        }
    }

    private func formatToolStatus(tool: String, path: String) -> String {
        let shortPath = path.count > 60 ? "..." + path.suffix(57) : path
        switch tool {
        case "bash": return "\u{1F527} Running: `\(shortPath)`"
        case "write": return "\u{1F527} Writing: `\(shortPath)`"
        case "edit": return "\u{1F527} Editing: `\(shortPath)`"
        case "read": return "\u{1F527} Reading: `\(shortPath)`"
        case "glob", "grep": return "\u{1F50D} Searching: `\(shortPath)`"
        default: return "\u{1F527} \(tool): `\(shortPath)`"
        }
    }

    // MARK: - Persistence

    private func loadPersistedIds() async {
        guard let ctx = modelContext else { return }
        let allDesc = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.messageId > 0 }
        )
        if let entities = try? ctx.fetch(allDesc) {
            persistedMessageIds = Set(entities.map(\.messageId))
            finalizedMessageIds = Set(entities.filter { $0.text.contains("———") }.map(\.messageId))
        }
    }

    private func loadInitialMessages() async {
        let loaded = await loadMessagesFromDB(session: nil, offset: 0)
        messages = loaded.reversed()
        rebuildIndex()
        dbOffset = loaded.count
        if loaded.count < Self.pageSize { allLoaded = true }
    }

    private func loadMessagesFromDB(session: String?, offset: Int) async -> [ChatMessage] {
        guard let ctx = modelContext else { return [] }
        var descriptor: FetchDescriptor<MessageEntity>
        if let session {
            descriptor = FetchDescriptor<MessageEntity>(
                predicate: #Predicate { $0.session == session },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.messageId, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<MessageEntity>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.messageId, order: .reverse)]
            )
        }
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = Self.pageSize
        guard let entities = try? ctx.fetch(descriptor) else { return [] }
        return entities.map { $0.toChatMessage() }
    }

    private func searchDB(query: String, offset: Int) async -> [MessageEntity] {
        guard let ctx = modelContext else { return [] }
        let searchTerm = query
        var descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.text.localizedStandardContains(searchTerm) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = Self.searchPageSize
        return (try? ctx.fetch(descriptor)) ?? []
    }

    private func persistMessage(_ msg: ChatMessage, upsert: Bool = false) {
        guard let ctx = modelContext else { return }
        if upsert && msg.messageId > 0 {
            // Try to find existing
            let mid = msg.messageId
            let descriptor = FetchDescriptor<MessageEntity>(
                predicate: #Predicate { $0.messageId == mid && $0.messageId > 0 }
            )
            if let existing = try? ctx.fetch(descriptor).first {
                existing.text = msg.text
                existing.session = msg.session
                existing.buttons = MessageEntity.buttonsToJson(msg.buttons)
                try? ctx.save()
                return
            }
        }
        ctx.insert(MessageEntity.from(msg))
        try? ctx.save()
    }

    private func updateMessageInDB(_ msg: ChatMessage) {
        guard let ctx = modelContext, msg.messageId > 0 else { return }
        let mid = msg.messageId
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.messageId == mid && $0.messageId > 0 }
        )
        if let existing = try? ctx.fetch(descriptor).first {
            existing.text = msg.text
            existing.session = msg.session
            existing.buttons = MessageEntity.buttonsToJson(msg.buttons)
            try? ctx.save()
        }
    }
}
