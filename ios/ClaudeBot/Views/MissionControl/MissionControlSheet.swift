import SwiftUI

struct MissionControlSheet: View {
    @Bindable var viewModel: ChatViewModel
    @State private var selectedTab = 0
    @State private var showAddSchedule = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Active (\(viewModel.activeTasks.count))").tag(0)
                    Text("Scheduled (\(viewModel.scheduledTasks.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if selectedTab == 0 {
                    activeTasksList
                } else {
                    scheduledTasksList
                }
            }
            .background(AppColors.darkBg)
            .navigationTitle("Mission Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showAddSchedule = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(AppColors.accentOrange)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSchedule) {
                AddScheduleSheet(viewModel: viewModel)
            }
        }
    }

    private var activeTasksList: some View {
        ScrollView {
            if viewModel.activeTasks.isEmpty {
                Text("No active tasks")
                    .foregroundColor(AppColors.sessionLabel)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(viewModel.activeTasks.values).sorted(by: { $0.started > $1.started })) { task in
                        ActiveTaskRow(task: task, viewModel: viewModel)
                    }
                }
                .padding(16)
            }
        }
    }

    private var scheduledTasksList: some View {
        ScrollView {
            if viewModel.scheduledTasks.isEmpty {
                Text("No scheduled tasks")
                    .foregroundColor(AppColors.sessionLabel)
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.scheduledTasks) { task in
                        ScheduledTaskRow(task: task, viewModel: viewModel)
                    }
                }
                .padding(16)
            }
        }
    }
}
