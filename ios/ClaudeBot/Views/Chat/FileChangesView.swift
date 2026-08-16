import SwiftUI

struct FileChangesView: View {
    let changes: [FileChange]
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("File Operations (\(changes.count))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.accentOrangeLight)
                Spacer()
                Text(expanded ? "\u{25B2}" : "\u{25BC}")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.sessionLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expanded.toggle() } }

            if expanded {
                ForEach(changes) { change in
                    FileChangeItem(change: change)
                }
            }
        }
        .background(AppColors.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.botBubbleBorder, lineWidth: 1)
        )
    }
}

struct FileChangeItem: View {
    let change: FileChange
    @State private var showDiff = false
    @State private var showCopiedPath = false

    private var icon: String {
        switch change.type {
        case "edit": return "\u{270F}\u{FE0F}"
        case "write": return "\u{1F4DD}"
        case "delete": return "\u{1F5D1}\u{FE0F}"
        case "move": return "\u{1F4E6}"
        case "bash": return "\u{26A1}"
        case "read": return "\u{1F4D6}"
        case "glob": return "\u{1F50D}"
        case "grep": return "\u{1F50E}"
        default: return "\u{1F4C4}"
        }
    }

    private var displayPath: String {
        let parts = change.path.split(separator: "/")
        if parts.count > 3 {
            return ".../" + parts.suffix(3).joined(separator: "/")
        }
        return change.path.isEmpty ? "(empty)" : change.path
    }

    private var hasDiff: Bool {
        !change.old.isEmpty || !change.new.isEmpty || !change.content.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 12))

                Text(showCopiedPath ? "Copied!" : displayPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(showCopiedPath ? AppColors.connectedGreen : AppColors.botText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        if hasDiff { withAnimation { showDiff.toggle() } }
                    }
                    .onLongPressGesture {
                        UIPasteboard.general.string = change.path
                        showCopiedPath = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedPath = false }
                    }

                if hasDiff {
                    Text(showDiff ? "\u{25B2}" : "\u{25BC}")
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.sessionLabel)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            if showDiff {
                switch change.type {
                case "edit":
                    DiffView(old: change.old, new: change.new)
                case "write":
                    NewFileView(content: change.content)
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct DiffView: View {
    let old: String
    let new: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(old.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text("- \(line)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.diffRemovedText)
                        .lineSpacing(2)
                }
                ForEach(Array(new.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text("+ \(line)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.diffAddedText)
                        .lineSpacing(2)
                }
                if old.count >= 2990 || new.count >= 2990 {
                    Text("(truncated)")
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.sessionLabel)
                }
            }
            .padding(8)
        }
        .background(AppColors.codeBlockBg)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

struct NewFileView: View {
    let content: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text("+ \(line)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AppColors.diffAddedText)
                        .lineSpacing(2)
                }
                if content.count >= 2990 {
                    Text("(truncated)")
                        .font(.system(size: 9))
                        .foregroundColor(AppColors.sessionLabel)
                }
            }
            .padding(8)
        }
        .background(AppColors.codeBlockBg)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}
