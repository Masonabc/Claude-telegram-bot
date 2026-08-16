import Foundation

struct FileChange: Identifiable, Hashable {
    let id = UUID()
    let type: String       // "edit", "write", "delete", "move", "bash", "read", "glob", "grep"
    let path: String
    let old: String
    let new: String
    let content: String

    init(type: String, path: String, old: String = "", new: String = "", content: String = "") {
        self.type = type
        self.path = path
        self.old = old
        self.new = new
        self.content = content
    }
}
