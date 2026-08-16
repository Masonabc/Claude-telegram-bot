import Foundation

struct InlineButton: Identifiable, Codable, Hashable {
    var id: String { "\(text)|\(callbackData)" }
    let text: String
    let callbackData: String

    enum CodingKeys: String, CodingKey {
        case text
        case callbackData = "data"
    }
}
