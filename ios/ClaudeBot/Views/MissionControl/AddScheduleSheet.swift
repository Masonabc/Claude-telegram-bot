import SwiftUI

struct AddScheduleSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var scheduleType = "cron"
    @State private var cronExpr = ""
    @State private var runAt = Date().addingTimeInterval(3600)
    @State private var selectedPreset: String?

    private let cronPresets: [(String, String)] = [
        ("Every 5 min", "*/5 * * * *"),
        ("Every 15 min", "*/15 * * * *"),
        ("Every hour", "0 * * * *"),
        ("Every 6 hours", "0 */6 * * *"),
        ("Daily 9am", "0 9 * * *"),
        ("Daily midnight", "0 0 * * *"),
        ("Weekdays 9am", "0 9 * * 1-5"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Schedule Type") {
                    Picker("Type", selection: $scheduleType) {
                        Text("Recurring (Cron)").tag("cron")
                        Text("One-time").tag("once")
                    }
                    .pickerStyle(.segmented)
                }

                if scheduleType == "cron" {
                    Section("Cron Expression") {
                        TextField("*/15 * * * *", text: $cronExpr)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(cronPresets, id: \.1) { preset in
                                    Button(preset.0) {
                                        cronExpr = preset.1
                                        selectedPreset = preset.1
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(cronExpr == preset.1 ? AppColors.accentOrange.opacity(0.2) : AppColors.darkSurfaceVariant)
                                    .foregroundColor(AppColors.accentOrange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                } else {
                    Section("Run At") {
                        DatePicker("Date & Time", selection: $runAt, in: Date()...)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.darkBg)
            .navigationTitle("New Scheduled Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.sessionLabel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let session = viewModel.effectiveSession
                        let cron = scheduleType == "cron" ? cronExpr : nil
                        let runAtStr: String? = scheduleType == "once" ? ISO8601DateFormatter().string(from: runAt) : nil
                        viewModel.createScheduledTask(
                            sessionName: session,
                            prompt: prompt,
                            scheduleType: scheduleType,
                            cronExpr: cron,
                            runAt: runAtStr
                        )
                        dismiss()
                    }
                    .foregroundColor(AppColors.accentOrange)
                    .disabled(prompt.isEmpty || (scheduleType == "cron" && cronExpr.isEmpty))
                }
            }
        }
    }
}
