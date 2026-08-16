import Foundation

struct SessionInfo: Identifiable {
    var id: String { name }
    let name: String
    let busy: Bool
    let isActive: Bool
    let lastCli: String
}
