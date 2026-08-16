import SwiftUI

struct ScheduledTaskRow: View {
    let task: ScheduledTask
    let viewModel: ChatViewModel
    @State private var showEdit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.scheduleType.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.accentOrangeLight)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.accentOrangeLight.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let cronExpr = task.cronExpr {
                    Text(cronExpr)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColors.timestampColor)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { task.enabled },
                    set: { viewModel.toggleScheduledTask(task.id, enabled: $0) }
                ))
                .labelsHidden()
                .tint(AppColors.accentOrange)
            }

            Text(task.prompt)
                .font(.system(size: 12))
                .foregroundColor(AppColors.botText)
                .lineLimit(3)

            HStack(spacing: 8) {
                if let nextRun = task.nextRun, nextRun > 0 {
                    Text("Next: \(formatEpoch(nextRun))")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.timestampColor)
                }
                if task.runCount > 0 {
                    Text("Runs: \(task.runCount)")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.timestampColor)
                }
                Spacer()
            }

            if let lastResult = task.lastResult, !lastResult.isEmpty {
                Text("Last: \(lastResult)")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.sessionLabel)
                    .lineLimit(1)
            }

            // Controls
            HStack(spacing: 12) {
                Button("Run Now") {
                    viewModel.triggerScheduledTask(task.id)
                }
                .font(.system(size: 12))
                .foregroundColor(AppColors.accentOrange)

                Button("Edit") {
                    showEdit = true
                }
                .font(.system(size: 12))
                .foregroundColor(AppColors.sessionLabel)

                Button("Delete") {
                    viewModel.deleteScheduledTask(task.id)
                }
                .font(.system(size: 12))
                .foregroundColor(AppColors.disconnectedRed)
            }
        }
        .padding(12)
        .background(AppColors.darkSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.botBubbleBorder, lineWidth: 1)
        )
        .sheet(isPresented: $showEdit) {
            EditScheduleSheet(task: task, viewModel: viewModel)
        }
    }

    private func formatEpoch(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter.string(from: date)
    }
}
