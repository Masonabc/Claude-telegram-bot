import SwiftUI

struct EditScheduleSheet: View {
    let task: ScheduledTask
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: String = ""
    @State private var cronExpr: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Task prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                }

                if task.scheduleType == "cron" {
                    Section("Cron Expression") {
                        TextField("*/15 * * * *", text: $cronExpr)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("Info") {
                    LabeledContent("Type", value: task.scheduleType)
                    LabeledContent("Run Count", value: "\(task.runCount)")
                    if !task.cwd.isEmpty {
                        LabeledContent("Working Dir", value: task.cwd)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.darkBg)
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.sessionLabel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateScheduledTask(
                            task.id,
                            prompt: prompt.isEmpty ? nil : prompt,
                            cronExpr: cronExpr.isEmpty ? nil : cronExpr,
                            runAt: nil
                        )
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentOrange)
                }
            }
            .onAppear {
                prompt = task.prompt
                cronExpr = task.cronExpr ?? ""
            }
        }
    }
}
