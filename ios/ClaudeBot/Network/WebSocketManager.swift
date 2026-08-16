import Foundation
import OSLog

private let logger = Logger(subsystem: "com.claudebot", category: "WS")

actor WebSocketManager {
    private static let replayGapFastForward = 200

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var baseUrl: String = ""
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?

    /// Last delivered sequence number
    private(set) var lastSeq: Int = 0
    /// Next expected seq
    private var expectedSeq: Int = 1
    /// Out-of-order buffer
    private var pendingBuffer: [Int: WsMessage] = [:]
    /// Whether we've already requested a resend for the current gap
    private var resendRequested = false
    /// Server boot ID
    private var knownServerId: String?

    // Callbacks (set once, called on MainActor)
    private var onMessage: (@MainActor (WsMessage) -> Void)?
    private var onStateChange: (@MainActor (ConnectionState) -> Void)?
    private var onServerRestart: (@MainActor () -> Void)?
    private var onSeqUpdate: ((Int, String) -> Void)?
    private var onError: ((String) -> Void)?

    func configure(
        onMessage: @escaping @MainActor (WsMessage) -> Void,
        onStateChange: @escaping @MainActor (ConnectionState) -> Void,
        onServerRestart: @escaping @MainActor () -> Void,
        onSeqUpdate: @escaping (Int, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onMessage = onMessage
        self.onStateChange = onStateChange
        self.onServerRestart = onServerRestart
        self.onSeqUpdate = onSeqUpdate
        self.onError = onError
    }

    func restoreState(seq: Int, serverId: String) {
        lastSeq = seq
        expectedSeq = seq + 1
        knownServerId = serverId.isEmpty ? nil : serverId
    }

    func connect(wsUrl: String) {
        logger.info("connect() url=\(wsUrl)")
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        baseUrl = wsUrl
        shouldReconnect = true
        reconnectAttempt = 0
        doConnect()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocket?.cancel(with: .normalClosure, reason: "User disconnect".data(using: .utf8))
        webSocket = nil
        pendingBuffer.removeAll()
        resendRequested = false
        let cb = onStateChange
        Task { @MainActor in cb?(.disconnected) }
    }

    private func doConnect() {
        guard shouldReconnect else { return }
        let state: ConnectionState = reconnectAttempt == 0 ? .connecting : .reconnecting
        let cb = onStateChange
        Task { @MainActor in cb?(state) }

        var connectUrl = baseUrl
        if lastSeq > 0 {
            let sep = baseUrl.contains("?") ? "&" : "?"
            connectUrl = "\(baseUrl)\(sep)last_seq=\(lastSeq)"
        }

        logger.info("doConnect() url=\(connectUrl) attempt=\(self.reconnectAttempt)")

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        self.urlSession = session

        guard let url = URL(string: connectUrl) else {
            logger.error("Invalid URL: \(connectUrl)")
            return
        }
        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()

        // Connection opened — reset state
        reconnectAttempt = 0
        pendingBuffer.removeAll()
        resendRequested = false
        expectedSeq = lastSeq == 0 ? 0 : lastSeq + 1

        let connectedCb = onStateChange
        Task { @MainActor in connectedCb?(.connected) }

        // Start receive loop
        Task { [weak self] in
            await self?.receiveLoop(ws)
        }
    }

    private func receiveLoop(_ ws: URLSessionWebSocketTask) async {
        while ws.state == .running {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await handleText(text, ws: ws)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleText(text, ws: ws)
                    }
                @unknown default:
                    break
                }
            } catch {
                let nsError = error as NSError
                // 57 = socket not connected (normal close)
                if nsError.code == 57 || nsError.code == -999 {
                    logger.info("WS closed normally")
                } else {
                    logger.error("WS receive error: \(error.localizedDescription)")
                    onError?(error.localizedDescription)
                }
                await scheduleReconnect()
                return
            }
        }
    }

    private func handleText(_ text: String, ws: URLSessionWebSocketTask) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle server_hello
        if json["type"] as? String == "server_hello" {
            let serverId = json["server_id"] as? String ?? ""
            let changed = knownServerId != serverId
            if changed && knownServerId != nil {
                let cb = onServerRestart
                Task { @MainActor in cb?() }
            }
            if changed {
                expectedSeq = 0
                lastSeq = 0
                pendingBuffer.removeAll()
                resendRequested = false
                onSeqUpdate?(0, serverId)
            }
            knownServerId = serverId
            return
        }

        let seq = json["seq"] as? Int ?? 0
        let msg = WsMessage(json: json, seq: seq)

        if seq == 0 {
            let cb = onMessage
            Task { @MainActor in cb?(msg) }
            return
        }

        // First message after server change
        if expectedSeq == 0 {
            expectedSeq = seq
            lastSeq = seq - 1
        }

        // Detect server restart: seq jumped back
        if seq < expectedSeq && expectedSeq - seq > 100 {
            pendingBuffer.removeAll()
            resendRequested = false
            expectedSeq = seq
            lastSeq = seq - 1
        }

        if seq < expectedSeq {
            // Duplicate — discard
        } else if seq == expectedSeq {
            deliver(msg)
            flushPending()
        } else {
            // Out of order — buffer
            pendingBuffer[seq] = msg
            if !resendRequested {
                resendRequested = true
                let resendReq: [String: Any] = ["type": "resend", "from_seq": expectedSeq]
                if let data = try? JSONSerialization.data(withJSONObject: resendReq),
                   let str = String(data: data, encoding: .utf8) {
                    try? await ws.send(.string(str))
                }
            }
            // Fast-forward if replay gap is too large
            if msg.isReplay && (seq - expectedSeq) > Self.replayGapFastForward {
                if let first = pendingBuffer.keys.sorted().first {
                    logger.warning("Large replay gap (\(seq - self.expectedSeq)); fast-forwarding to \(first)")
                    expectedSeq = first
                    lastSeq = first - 1
                    resendRequested = false
                    flushPending()
                }
            }
        }
    }

    private func deliver(_ msg: WsMessage) {
        lastSeq = msg.seq
        expectedSeq = msg.seq + 1
        let cb = onMessage
        Task { @MainActor in cb?(msg) }
        onSeqUpdate?(lastSeq, knownServerId ?? "")
    }

    private func flushPending() {
        while let msg = pendingBuffer.removeValue(forKey: expectedSeq) {
            deliver(msg)
        }
        if pendingBuffer.isEmpty {
            resendRequested = false
        }
    }

    private func scheduleReconnect() async {
        guard shouldReconnect else {
            let cb = onStateChange
            Task { @MainActor in cb?(.disconnected) }
            return
        }
        let cb = onStateChange
        Task { @MainActor in cb?(.reconnecting) }
        reconnectAttempt += 1
        let delay = min(1000 * (1 << min(reconnectAttempt, 5)), 30_000)
        logger.info("scheduleReconnect attempt=\(self.reconnectAttempt) delay=\(delay)ms")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.doConnect()
        }
    }
}
