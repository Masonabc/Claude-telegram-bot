import Foundation

@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.claudebot.settings", qos: .utility)

    var host: String {
        get { defaults.string(forKey: "host") ?? "100.118.238.103" }
        set { defaults.set(newValue, forKey: "host") }
    }

    var port: Int {
        get {
            let v = defaults.integer(forKey: "port")
            return v > 0 ? v : 8642
        }
        set { defaults.set(newValue, forKey: "port") }
    }

    var token: String {
        get { defaults.string(forKey: "token") ?? "" }
        set { defaults.set(newValue, forKey: "token") }
    }

    var wsLastSyncAt: Date {
        get {
            let ts = defaults.double(forKey: "ws_last_sync_at")
            return ts > 0 ? Date(timeIntervalSince1970: ts) : .distantPast
        }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "ws_last_sync_at") }
    }

    var wsLastError: String {
        get { defaults.string(forKey: "ws_last_error") ?? "" }
        set { defaults.set(newValue, forKey: "ws_last_error") }
    }

    var wsLastState: String {
        get { defaults.string(forKey: "ws_last_state") ?? "DISCONNECTED" }
        set { defaults.set(newValue, forKey: "ws_last_state") }
    }

    var lastSeq: Int {
        get { defaults.integer(forKey: "last_seq") }
        set {
            queue.sync {
                let current = defaults.integer(forKey: "last_seq")
                let next = max(current, newValue)
                if next != current {
                    defaults.set(next, forKey: "last_seq")
                }
            }
        }
    }

    var knownServerId: String {
        get { defaults.string(forKey: "known_server_id") ?? "" }
        set {
            queue.sync {
                let current = defaults.string(forKey: "known_server_id") ?? ""
                if current != newValue {
                    defaults.set(newValue, forKey: "known_server_id")
                }
            }
        }
    }

    var isConfigured: Bool { !host.isEmpty }

    func wsUrl() -> String {
        let base = "ws://\(host):\(port)/ws"
        return token.isEmpty ? base : "\(base)?token=\(token)"
    }

    func getWsState() -> (seq: Int, serverId: String) {
        queue.sync {
            let seq = defaults.integer(forKey: "last_seq")
            let serverId = defaults.string(forKey: "known_server_id") ?? ""
            return (seq, serverId)
        }
    }

    func updateWsState(seq: Int, serverId: String) {
        queue.sync {
            let currentSeq = defaults.integer(forKey: "last_seq")
            let currentServerId = defaults.string(forKey: "known_server_id") ?? ""
            let serverChanged = !serverId.isEmpty && currentServerId != serverId
            let nextSeq = serverChanged ? max(0, seq) : max(currentSeq, seq)
            if nextSeq == currentSeq && currentServerId == serverId {
                defaults.set(Date().timeIntervalSince1970, forKey: "ws_last_sync_at")
                return
            }
            defaults.set(nextSeq, forKey: "last_seq")
            defaults.set(serverId, forKey: "known_server_id")
            defaults.set(Date().timeIntervalSince1970, forKey: "ws_last_sync_at")
        }
    }
}
