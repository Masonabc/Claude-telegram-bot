import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var showSearch = false
    @State private var showSessions = false
    @State private var showOutline = false
    @State private var showFilterMenu = false
    @State private var showMissionControl = false
    @State private var stickToBottom = true
    @State private var newMessageCount = 0
    @State private var sizeBeforeLoad = 0
    @State private var lastScrollTrigger = 0
    @State private var keyboardTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Session dropdown
                    if showSessions {
                        SessionDropdown(viewModel: viewModel, showSessions: $showSessions)
                    }

                    // Session mismatch banner
                    if viewModel.isViewingOtherSession {
                        SessionMismatchBanner(viewModel: viewModel)
                    }

                    // Search mode
                    if showSearch {
                        SearchView(viewModel: viewModel, showSearch: $showSearch)
                    } else {
                        // Message list
                        messageList

                        // Pending action bar
                        if let action = viewModel.pendingAction {
                            PendingActionBar(action: action, viewModel: viewModel)
                        }

                        // Input bar
                        InputBarView(
                            onSend: { viewModel.sendMessage($0) },
                            enabled: viewModel.connectionState == .connected && !viewModel.isSwitchingSession,
                            currentSession: viewModel.effectiveSession,
                            isBusy: viewModel.isBotBusy,
                            onCancel: { viewModel.sendMessage("/cancel") }
                        )
                    }
                }

                // Scroll-to-bottom button
                if !stickToBottom && !showSearch {
                    scrollToBottomButton
                        .padding(.bottom, 130)
                }
            }
            .background(AppColors.darkBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.topBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showMissionControl) {
                MissionControlSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showOutline) {
                OutlineSheet(messages: viewModel.messages)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(AppColors.accentOrange)
                            .padding()
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message) { button in
                            viewModel.pressButton(messageId: message.messageId, button: button)
                        }
                        .id(message.id)
                        .onAppear {
                            // Load more when near top
                            if index <= 3 && !viewModel.isLoadingMore && !viewModel.allLoaded {
                                sizeBeforeLoad = viewModel.messages.count
                                viewModel.loadMore()
                            }
                            // Track bottom
                            if index >= viewModel.messages.count - 3 {
                                stickToBottom = true
                                newMessageCount = 0
                            }
                        }
                        .onDisappear {
                            if index >= viewModel.messages.count - 3 {
                                stickToBottom = false
                            }
                        }
                    }

                    // Invisible anchor at bottom
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .refreshable { viewModel.reconnect() }
            .onChange(of: viewModel.scrollTrigger) { _, trigger in
                guard trigger > 0, !viewModel.messages.isEmpty else { return }
                if stickToBottom {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    newMessageCount += 1
                }
            }
            .onChange(of: viewModel.isLoadingMore) { wasLoading, isLoading in
                if wasLoading && !isLoading && sizeBeforeLoad > 0 {
                    let added = viewModel.messages.count - sizeBeforeLoad
                    if added > 0, added < viewModel.messages.count {
                        proxy.scrollTo(viewModel.messages[added].id, anchor: .top)
                    }
                    sizeBeforeLoad = 0
                }
            }
            .onAppear {
                if !viewModel.messages.isEmpty {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: keyboardTrigger) { _, _ in
                if stickToBottom && !viewModel.messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardTrigger += 1
            }
        }
    }

    // MARK: - Scroll to Bottom Button

    private var scrollToBottomButton: some View {
        Button {
            stickToBottom = true
            newMessageCount = 0
        } label: {
            HStack(spacing: 4) {
                Text("\u{2193}")
                    .font(.headline)
                if newMessageCount > 0 {
                    Text("\(newMessageCount)")
                        .font(.caption.bold())
                }
            }
            .foregroundColor(AppColors.userBubbleText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.accentOrange)
            .clipShape(Capsule())
            .shadow(radius: 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                showSessions.toggle()
                if showSessions { viewModel.fetchSessions() }
            } label: {
                HStack(spacing: 8) {
                    connectionDot
                    VStack(alignment: .leading, spacing: 1) {
                        let session = viewModel.sessionFilter ?? viewModel.currentSession
                        Text(session.isEmpty ? "Claude Bot" : session)
                            .font(.headline)
                            .foregroundColor(AppColors.topBarTitle)
                            .lineLimit(1)

                        if viewModel.taskStatus.active {
                            Text("\(viewModel.taskStatus.mode) \u{2022} \(viewModel.taskStatus.phase)")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.accentOrangeLight)
                                .lineLimit(1)
                        }
                    }
                    Text(showSessions ? "\u{25B2}" : "\u{25BC}")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.sessionLabel)
                }
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if viewModel.connectionState == .disconnected {
                Button("Connect") { viewModel.connect() }
                    .font(.caption)
                    .foregroundColor(AppColors.accentOrange)
            }

            // Session filter
            if viewModel.availableSessions.count > 1 {
                Menu {
                    Button("All Sessions") {
                        viewModel.setSessionFilter(nil)
                    }
                    ForEach(viewModel.availableSessions, id: \.self) { session in
                        Button(session) {
                            viewModel.setSessionFilter(session)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(viewModel.sessionFilter != nil ? AppColors.accentOrange : AppColors.sessionLabel)
                }
            }

            // Mission Control
            Button {
                showMissionControl = true
                viewModel.fetchActiveTasks()
                viewModel.fetchScheduledTasks()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Text("\u{26A1}")
                    if !viewModel.activeTasks.isEmpty {
                        Text("\(viewModel.activeTasks.count)")
                            .font(.system(size: 9).bold())
                            .foregroundColor(AppColors.darkBg)
                            .frame(width: 16, height: 16)
                            .background(AppColors.accentOrange)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }

            // Tools menu
            Menu {
                Button { showSearch = true } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                Button { showOutline = true } label: {
                    Label("Outline", systemImage: "list.bullet")
                }
                Button { viewModel.showSettings = true } label: {
                    Label("Settings", systemImage: "gear")
                }
            } label: {
                Text("\u{22EF}")
                    .font(.title3)
                    .foregroundColor(AppColors.sessionLabel)
            }
        }
    }

    @ViewBuilder
    private var connectionDot: some View {
        let color: Color = {
            switch viewModel.connectionState {
            case .connected: return AppColors.connectedGreen
            case .connecting, .reconnecting: return AppColors.reconnectingYellow
            case .disconnected: return AppColors.disconnectedRed
            }
        }()
        let isPulsing = viewModel.connectionState == .connecting || viewModel.connectionState == .reconnecting

        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(isPulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isPulsing)
    }
}

// MARK: - Session Dropdown

struct SessionDropdown: View {
    let viewModel: ChatViewModel
    @Binding var showSessions: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.sessionList.isEmpty {
                Text("No sessions")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.sessionLabel)
                    .padding(16)
            } else {
                ForEach(viewModel.sessionList) { session in
                    HStack {
                        if session.isActive {
                            Circle()
                                .fill(AppColors.accentOrange)
                                .frame(width: 6, height: 6)
                        }
                        Text(session.name)
                            .font(.system(size: 14))
                            .foregroundColor(session.isActive ? AppColors.accentOrange : AppColors.botText)
                        Spacer()
                        if session.busy {
                            Text("\u{1F504}")
                                .font(.system(size: 12))
                        }
                        Text(session.lastCli)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.sessionLabel)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(session.isActive ? AppColors.darkSurfaceVariant : AppColors.darkSurface)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showSessions = false
                        if !session.isActive {
                            viewModel.switchSession(session.name)
                        }
                    }
                }
            }
        }
        .background(AppColors.darkSurface)
    }
}

// MARK: - Session Mismatch Banner

struct SessionMismatchBanner: View {
    let viewModel: ChatViewModel

    var body: some View {
        HStack {
            Text("Viewing \(viewModel.sessionFilter ?? "") (not active session)")
                .font(.system(size: 12))
                .foregroundColor(AppColors.accentOrangeLight)
            Spacer()
            Button("Switch") { viewModel.quickSwitchToFilteredSession() }
                .font(.system(size: 12).bold())
                .foregroundColor(AppColors.accentOrange)
            Button("Clear") { viewModel.clearSessionFilter() }
                .font(.system(size: 12))
                .foregroundColor(AppColors.sessionLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColors.darkSurface)
    }
}

// MARK: - Pending Action Bar

struct PendingActionBar: View {
    let action: PendingAction
    let viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\u{25B2} Tap to view full message")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.accentOrangeLight)
                Spacer()
                Button("Dismiss") { viewModel.dismissPendingAction() }
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            ScrollView {
                Text(action.text)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.botText)
            }
            .frame(maxHeight: 120)

            HStack(spacing: 8) {
                ForEach(action.buttons.flatMap { $0 }) { btn in
                    let isApprove = btn.text.localizedCaseInsensitiveContains("approve")
                    let isReject = btn.text.localizedCaseInsensitiveContains("reject")
                    Button(btn.text) {
                        viewModel.pressButton(messageId: action.messageId, button: btn)
                    }
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isApprove ? AppColors.connectedGreen : Color.clear)
                    .foregroundColor(isApprove ? AppColors.userBubbleText : isReject ? AppColors.disconnectedRed : AppColors.accentOrange)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isApprove ? Color.clear : isReject ? AppColors.disconnectedRed : AppColors.botBubbleBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(AppColors.darkSurface)
    }
}

// MARK: - Search View

struct SearchView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var showSearch: Bool
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Button {
                    showSearch = false
                    viewModel.clearSearch()
                } label: {
                    Text("\u{2190}")
                        .font(.title3)
                        .foregroundColor(AppColors.sessionLabel)
                }

                TextField("Search messages...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.botText)
                    .padding(10)
                    .background(AppColors.darkSurfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onChange(of: query) { _, newValue in
                        if newValue.count >= 2 {
                            viewModel.search(newValue)
                        } else if newValue.isEmpty {
                            viewModel.clearSearch()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.topBarBg)

            // Results
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.searchResults) { msg in
                        MessageBubble(message: msg)
                    }
                    if viewModel.searchHasMore {
                        Button("Load more") { viewModel.searchMore() }
                            .foregroundColor(AppColors.accentOrange)
                            .padding()
                    }
                    if viewModel.isSearching {
                        ProgressView().tint(AppColors.accentOrange).padding()
                    }
                }
            }
        }
    }
}

// MARK: - Outline Sheet

struct OutlineSheet: View {
    let messages: [ChatMessage]

    private var userMessages: [ChatMessage] {
        messages.filter { !$0.isFromBot }
    }

    var body: some View {
        NavigationStack {
            List(userMessages) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    Text(msg.text)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.botText)
                        .lineLimit(2)

                    let formatter = DateFormatter()
                    Text({
                        formatter.dateFormat = "HH:mm"
                        return formatter.string(from: msg.timestamp)
                    }())
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.timestampColor)
                }
                .listRowBackground(AppColors.darkSurface)
            }
            .listStyle(.plain)
            .background(AppColors.darkBg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Outline")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
