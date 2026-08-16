import SwiftUI

private struct BotCommand {
    let cmd: String
    let desc: String
    let needsArgs: Bool
}

private let commands: [BotCommand] = [
    BotCommand(cmd: "/claude", desc: "Run Claude task", needsArgs: true),
    BotCommand(cmd: "/codex", desc: "Run Codex task", needsArgs: true),
    BotCommand(cmd: "/gemini", desc: "Run Gemini task", needsArgs: true),
    BotCommand(cmd: "/justdoit", desc: "Autonomous implementation", needsArgs: true),
    BotCommand(cmd: "/omni", desc: "Multi-agent engineering", needsArgs: true),
    BotCommand(cmd: "/deepreview", desc: "Multi-phase code review", needsArgs: false),
    BotCommand(cmd: "/new", desc: "New session in ~/project", needsArgs: true),
    BotCommand(cmd: "/resume", desc: "Pick a session to resume", needsArgs: false),
    BotCommand(cmd: "/sessions", desc: "List all sessions", needsArgs: false),
    BotCommand(cmd: "/switch", desc: "Switch session by name", needsArgs: true),
    BotCommand(cmd: "/status", desc: "Show current status", needsArgs: false),
    BotCommand(cmd: "/cancel", desc: "Cancel current task", needsArgs: false),
    BotCommand(cmd: "/plan", desc: "Enter plan mode", needsArgs: false),
    BotCommand(cmd: "/approve", desc: "Approve current plan", needsArgs: false),
    BotCommand(cmd: "/reject", desc: "Reject current plan", needsArgs: false),
    BotCommand(cmd: "/reset", desc: "Clear conversation history", needsArgs: false),
    BotCommand(cmd: "/end", desc: "End current session", needsArgs: false),
    BotCommand(cmd: "/delete", desc: "Delete a session", needsArgs: true),
    BotCommand(cmd: "/help", desc: "Show all commands", needsArgs: false),
]

private let shortcuts = ["commit and push", "deploy", "fix it", "run tests", "review", "continue"]

struct InputBarView: View {
    let onSend: (String) -> Void
    var enabled: Bool = true
    var currentSession: String = ""
    var isBusy: Bool = false
    var onCancel: () -> Void = {}

    @State private var text = ""
    @State private var showMenu = false
    @State private var showShortcuts = false
    @FocusState private var isFocused: Bool

    private var suggestions: [BotCommand] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard typed.hasPrefix("/"), !typed.contains(" ") else { return [] }
        return commands.filter { $0.cmd.lowercased().hasPrefix(typed.lowercased()) && $0.cmd != typed }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Command autocomplete
            if !suggestions.isEmpty {
                commandList(suggestions)
            }

            // Full command menu
            if showMenu {
                commandList(commands)
                    .frame(maxHeight: 300)
            }

            // Quick shortcuts
            if showShortcuts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shortcuts, id: \.self) { shortcut in
                            Text(shortcut)
                                .font(.caption)
                                .foregroundColor(AppColors.accentOrange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppColors.inputBorder, lineWidth: 1)
                                )
                                .onTapGesture {
                                    onSend(shortcut)
                                    showShortcuts = false
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background(AppColors.inputBg)
            }

            // Input row
            HStack(spacing: 8) {
                // Command menu button
                Button {
                    showMenu.toggle()
                    showShortcuts = false
                } label: {
                    Text("/")
                        .font(.headline)
                        .foregroundColor(showMenu ? AppColors.userBubbleText : AppColors.accentOrange)
                        .frame(width: 36, height: 36)
                        .background(showMenu ? AppColors.accentOrange : AppColors.darkSurfaceVariant)
                        .clipShape(Circle())
                }
                .disabled(!enabled)

                // Shortcuts toggle
                Button {
                    showShortcuts.toggle()
                    showMenu = false
                } label: {
                    Text("\u{26A1}")
                        .font(.callout)
                        .frame(width: 36, height: 36)
                }
                .disabled(!enabled)

                // Text field
                TextField(currentSession.isEmpty ? "Message or /command..." : currentSession, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.botText)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.darkSurfaceVariant)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(isFocused ? AppColors.inputBorderFocused : AppColors.inputBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .focused($isFocused)
                    .disabled(!enabled)
                    .onChange(of: text) { _, newValue in
                        if newValue.hasPrefix("/") { showMenu = false }
                    }

                // Send / Cancel button
                if isBusy && text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        onCancel()
                    } label: {
                        Text("\u{25A0}")
                            .font(.headline)
                            .foregroundColor(AppColors.userBubbleText)
                            .frame(width: 40, height: 40)
                            .background(AppColors.disconnectedRed)
                            .clipShape(Circle())
                    }
                } else {
                    Button {
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSend(trimmed)
                        text = ""
                        isFocused = false
                    } label: {
                        Text("\u{2191}")
                            .font(.headline)
                            .foregroundColor(enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.userBubbleText : AppColors.placeholderText)
                            .frame(width: 40, height: 40)
                            .background(enabled && !text.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.accentOrange : AppColors.darkSurfaceVariant)
                            .clipShape(Circle())
                    }
                    .disabled(!enabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(AppColors.inputBg)
        }
    }

    private func commandList(_ cmds: [BotCommand]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cmds, id: \.cmd) { cmd in
                    HStack {
                        Text(cmd.cmd)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.accentOrange)
                        Spacer().frame(width: 12)
                        Text(cmd.desc)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.sessionLabel)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showMenu = false
                        if cmd.needsArgs {
                            text = "\(cmd.cmd) "
                            isFocused = true
                        } else {
                            text = ""
                            onSend(cmd.cmd)
                            isFocused = false
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 200)
        .background(AppColors.darkSurface)
    }
}
