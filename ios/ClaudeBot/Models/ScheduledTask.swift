import Foundation

struct ScheduledTask: Identifiable {
    let id: String
    let cwd: String
    let prompt: String
    let scheduleType: String   // "cron" | "once"
    let cronExpr: String?
    let runAt: String?
    var enabled: Bool
    let nextRun: Int64?
    let lastRun: Int64?
    let lastResult: String?
    let runCount: Int
}
