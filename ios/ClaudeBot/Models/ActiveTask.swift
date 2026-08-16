import Foundation

struct ActiveTask: Identifiable {
    var id: String { session }
    let mode: String
    let session: String
    var task: String
    var phase: String
    var step: Int
    var started: Int64
    var paused: Bool
}
