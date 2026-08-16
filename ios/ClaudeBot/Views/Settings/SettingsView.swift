import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var token: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        TextField("Tailscale IP", text: $host)
                            .textFieldStyle(AppTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Port", text: $port)
                            .textFieldStyle(AppTextFieldStyle())
                            .keyboardType(.numberPad)

                        TextField("API Token (optional)", text: $token)
                            .textFieldStyle(AppTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Button(action: save) {
                        Text("Save & Connect")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(host.isEmpty ? AppColors.darkSurfaceVariant : AppColors.accentOrange)
                            .foregroundColor(host.isEmpty ? AppColors.placeholderText : AppColors.userBubbleText)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(host.isEmpty)

                    if !host.isEmpty {
                        let p = Int(port) ?? 8642
                        Text("ws://\(host):\(p)/ws")
                            .font(.caption)
                            .foregroundColor(AppColors.timestampColor)
                    }

                    Divider().overlay(AppColors.botBubbleBorder)

                    DiagnosticsCard(viewModel: viewModel)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(AppColors.darkBg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.topBarBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { viewModel.showSettings = false }
                        .foregroundColor(AppColors.accentOrange)
                }
            }
        }
        .onAppear {
            host = viewModel.settings.host
            port = String(viewModel.settings.port)
            token = viewModel.settings.token
        }
    }

    private func save() {
        viewModel.settings.host = host.trimmingCharacters(in: .whitespaces)
        viewModel.settings.port = Int(port) ?? 8642
        viewModel.settings.token = token.trimmingCharacters(in: .whitespaces)
        viewModel.reconnect()
        viewModel.showSettings = false
    }
}

struct DiagnosticsCard: View {
    let viewModel: ChatViewModel
    @State private var tick = 0

    var body: some View {
        let _ = tick // force refresh
        VStack(alignment: .leading, spacing: 6) {
            Text("Connection Diagnostics")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.accentOrangeLight)

            DiagRow(label: "State", value: viewModel.connectionState.rawValue)
            DiagRow(label: "Last Sync", value: formatSync())
            DiagRow(label: "Last Seq", value: "\(viewModel.settings.lastSeq)")
            DiagRow(label: "Server ID", value: viewModel.settings.knownServerId.isEmpty ? "(none)" : viewModel.settings.knownServerId)

            let err = viewModel.settings.wsLastError
            Text("Last Error: \(err.isEmpty ? "(none)" : err)")
                .font(.caption)
                .foregroundColor(err.isEmpty ? AppColors.timestampColor : AppColors.accentOrange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.darkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                tick += 1
            }
        }
    }

    private func formatSync() -> String {
        let lastSync = viewModel.settings.wsLastSyncAt
        guard lastSync != .distantPast else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let ts = formatter.string(from: lastSync)
        let age = Int(Date().timeIntervalSince(lastSync))
        return "\(ts) (\(age)s ago)"
    }
}

struct DiagRow: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(label): \(value)")
            .font(.caption)
            .foregroundColor(AppColors.botText)
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(AppColors.darkSurfaceVariant)
            .foregroundColor(AppColors.botText)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.inputBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
