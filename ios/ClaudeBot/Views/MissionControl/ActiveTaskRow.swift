import SwiftUI

struct ActiveTaskRow: View {
    let task: ActiveTask
    let viewModel: ChatViewModel

    private var elapsed: String {
        guard task.started > 0 else { return "" }
        let seconds = Int(Date().timeIntervalSince1970) - Int(task.started)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.mode.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.accentOrange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.accentOrange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(task.session)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.botText)

                Spacer()

                if task.paused {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.reconnectingYellow)
                }
            }

            if !task.task.isEmpty {
                Text(task.task)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.sessionLabel)
                    .lineLimit(2)
            }

            HStack {
                if !task.phase.isEmpty {
                    Text("\(task.phase) \u{2022} Step \(task.step)")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.timestampColor)
                }
                if !elapsed.isEmpty {
                    Text(elapsed)
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.timestampColor)
                }
                Spacer()
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    viewModel.viewTaskSession(task.session)
                } label: {
                    Text("View")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.accentOrange)
                }

                if task.paused {
                    Button {
                        viewModel.resumeTask(task.session)
                    } label: {
                        Text("Resume")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.connectedGreen)
                    }
                } else {
                    Button {
                        viewModel.pauseTask(task.session)
                    } label: {
                        Text("Pause")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.reconnectingYellow)
                    }
                }

                Button {
                    viewModel.cancelTask(task.session)
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.disconnectedRed)
                }
            }
        }
        .padding(12)
        .background(AppColors.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.botBubbleBorder, lineWidth: 1)
        )
    }
}
