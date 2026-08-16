import Foundation

struct ChatMessage: Identifiable {
    let id: String
    let messageId: Int
    var text: String
    let isFromBot: Bool
    var session: String
    var isReplay: Bool
    let timestamp: Date
    var buttons: [[InlineButton]]
    var fileChanges: [FileChange]

    init(
        messageId: Int,
        text: String,
        isFromBot: Bool,
        session: String = "",
        isReplay: Bool = false,
        timestamp: Date = Date(),
        buttons: [[InlineButton]] = [],
        fileChanges: [FileChange] = []
    ) {
        self.id = "\(messageId)_\(timestamp.timeIntervalSince1970)"
        self.messageId = messageId
        self.text = text
        self.isFromBot = isFromBot
        self.session = session
        self.isReplay = isReplay
        self.timestamp = timestamp
        self.buttons = buttons
        self.fileChanges = fileChanges
    }
}
