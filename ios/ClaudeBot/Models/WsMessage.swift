import Foundation

struct WsMessage {
    let type: String           // "message", "edit", "error", "status", "stream", "active_session", "schedule"
    let messageId: Int?
    let text: String
    let session: String
    let seq: Int
    let isReplay: Bool
    let buttons: [[InlineButton]]
    // Status fields
    let mode: String
    let phase: String
    let step: Int
    let active: Bool
    let task: String
    let started: Int64
    let paused: Bool
    // Stream fields
    let op: String             // "start", "append", "tool", "done", "skip"
    let tool: String
    let path: String
    let cancelled: Bool
    let fileChanges: [[String: String]]

    init(json: [String: Any], seq: Int) {
        self.type = json["type"] as? String ?? ""
        self.text = json["text"] as? String ?? ""
        self.session = json["session"] as? String ?? ""
        self.seq = seq
        self.isReplay = json["is_replay"] as? Bool ?? false

        if let mid = json["message_id"] as? Int {
            self.messageId = mid
        } else {
            self.messageId = nil
        }

        // Parse inline keyboard buttons
        var parsedButtons: [[InlineButton]] = []
        if let markup = json["reply_markup"] as? [String: Any],
           let keyboard = markup["inline_keyboard"] as? [[Any]] {
            for row in keyboard {
                var rowButtons: [InlineButton] = []
                for item in row {
                    if let btn = item as? [String: Any] {
                        let text = btn["text"] as? String ?? ""
                        let data = btn["callback_data"] as? String ?? ""
                        rowButtons.append(InlineButton(text: text, callbackData: data))
                    }
                }
                parsedButtons.append(rowButtons)
            }
        }
        self.buttons = parsedButtons

        // Status fields
        self.mode = json["mode"] as? String ?? ""
        self.phase = json["phase"] as? String ?? ""
        self.step = json["step"] as? Int ?? 0
        self.active = json["active"] as? Bool ?? false
        self.task = json["task"] as? String ?? ""
        self.started = json["started"] as? Int64 ?? 0
        self.paused = json["paused"] as? Bool ?? false

        // Stream fields
        self.op = json["op"] as? String ?? ""
        self.tool = json["tool"] as? String ?? ""
        self.path = json["path"] as? String ?? ""
        self.cancelled = json["cancelled"] as? Bool ?? false

        // Parse file changes
        var parsedChanges: [[String: String]] = []
        if let fcArr = json["file_changes"] as? [[String: Any]] {
            for fc in fcArr {
                var map: [String: String] = [:]
                for (key, value) in fc {
                    map[key] = "\(value)"
                }
                parsedChanges.append(map)
            }
        }
        self.fileChanges = parsedChanges
    }
}
