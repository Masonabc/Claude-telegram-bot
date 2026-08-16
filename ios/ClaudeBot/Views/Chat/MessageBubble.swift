import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var onButtonClick: ((InlineButton) -> Void)?

    @State private var showCopied = false
    @Environment(\.openURL) private var openURL

    private var isBot: Bool { message.isFromBot }

    var body: some View {
        VStack(alignment: isBot ? .leading : .trailing, spacing: 2) {
            // Session label
            if isBot && !message.session.isEmpty {
                Text(message.session)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.accentOrangeLight)
                    .padding(.leading, 4)
            }

            // Message bubble
            bubbleContent
                .frame(maxWidth: 320, alignment: isBot ? .leading : .trailing)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isBot ? AppColors.botBubble : AppColors.userBubble)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isBot ? (showCopied ? AppColors.accentOrange : AppColors.botBubbleBorder) : Color.clear, lineWidth: isBot ? 1 : 0)
                )
                .clipShape(bubbleShape)
                .contextMenu {
                    Button("Copy") {
                        UIPasteboard.general.string = message.text
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                    }
                }

            // File changes
            if !message.fileChanges.isEmpty {
                FileChangesView(changes: message.fileChanges)
                    .frame(maxWidth: 320)
            }

            // Inline buttons
            if !message.buttons.isEmpty, let onButtonClick {
                VStack(spacing: 4) {
                    ForEach(Array(message.buttons.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            ForEach(row) { button in
                                Button(button.text) {
                                    onButtonClick(button)
                                }
                                .font(.system(size: 13))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.botBubbleBorder, lineWidth: 1)
                                )
                                .foregroundColor(AppColors.accentOrange)
                            }
                        }
                    }
                }
                .frame(maxWidth: 320)
            }

            // Timestamp row
            HStack(spacing: 4) {
                if message.isReplay {
                    Text("replayed")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.accentOrangeLight)
                }
                Text(formatTime(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.timestampColor)
                if showCopied {
                    Text("Copied")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.connectedGreen)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: isBot ? .leading : .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isBot {
            let segments = parseMarkdown(message.text)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(segments) { segment in
                    switch segment {
                    case .text(let attributed):
                        Text(attributed)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.botText)
                            .lineSpacing(4)
                            .textSelection(.enabled)

                    case .codeBlock(let code, let language):
                        VStack(spacing: 0) {
                            // Code block header
                            HStack {
                                Text(language.isEmpty ? "code" : language)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(AppColors.sessionLabel)
                                Spacer()
                                CopyButton(text: code)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.botBubbleBorder)

                            // Code content
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(code)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(AppColors.codeBlockText)
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                                    .padding(10)
                            }
                        }
                        .background(AppColors.codeBlockBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.botBubbleBorder, lineWidth: 1)
                        )
                        .padding(.vertical, 3)
                    }
                }
            }
        } else {
            Text(message.text)
                .font(.system(size: 14))
                .foregroundColor(AppColors.userBubbleText)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private var bubbleShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: 16, bottomLeadingRadius: isBot ? 4 : 16,
            bottomTrailingRadius: isBot ? 16 : 4, topTrailingRadius: 16
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : "Copy") {
            UIPasteboard.general.string = text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
        .font(.system(size: 10))
        .foregroundColor(copied ? AppColors.connectedGreen : AppColors.accentOrange)
    }
}
