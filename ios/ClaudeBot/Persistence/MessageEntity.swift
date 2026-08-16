import Foundation
import SwiftData

@Model
final class MessageEntity {
    var messageId: Int
    var text: String
    var isFromBot: Bool
    var session: String
    var timestamp: Date
    var buttons: String  // JSON-encoded buttons

    init(messageId: Int, text: String, isFromBot: Bool, session: String = "", timestamp: Date = Date(), buttons: String = "") {
        self.messageId = messageId
        self.text = text
        self.isFromBot = isFromBot
        self.session = session
        self.timestamp = timestamp
        self.buttons = buttons
    }

    func toChatMessage() -> ChatMessage {
        var btns: [[InlineButton]] = []
        if !buttons.isEmpty, let data = buttons.data(using: .utf8) {
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                for row in arr {
                    var rowButtons: [InlineButton] = []
                    for item in row {
                        if let obj = item as? [String: Any] {
                            let text = obj["text"] as? String ?? ""
                            let cbData = obj["data"] as? String ?? ""
                            rowButtons.append(InlineButton(text: text, callbackData: cbData))
                        }
                    }
                    btns.append(rowButtons)
                }
            }
        }
        return ChatMessage(
            messageId: messageId,
            text: text,
            isFromBot: isFromBot,
            session: session,
            timestamp: timestamp,
            buttons: btns
        )
    }

    static func from(_ msg: ChatMessage) -> MessageEntity {
        MessageEntity(
            messageId: msg.messageId,
            text: msg.text,
            isFromBot: msg.isFromBot,
            session: msg.session,
            timestamp: msg.timestamp,
            buttons: buttonsToJson(msg.buttons)
        )
    }

    static func buttonsToJson(_ buttons: [[InlineButton]]) -> String {
        guard !buttons.isEmpty else { return "" }
        var arr: [[Any]] = []
        for row in buttons {
            var rowArr: [[String: String]] = []
            for btn in row {
                rowArr.append(["text": btn.text, "data": btn.callbackData])
            }
            arr.append(rowArr)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }
}
