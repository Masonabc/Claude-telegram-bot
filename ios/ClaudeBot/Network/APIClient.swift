import Foundation
import OSLog

private let logger = Logger(subsystem: "com.claudebot", category: "API")

actor APIClient {
    private let session = URLSession.shared
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var baseURL: String {
        "http://\(settings.host):\(settings.port)"
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        if !settings.token.isEmpty {
            req.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await session.data(for: req)
        return data
    }

    // MARK: - Messages

    func sendMessage(_ text: String) async {
        do {
            _ = try await request("/api/message", method: "POST", body: ["text": text])
        } catch {
            logger.error("sendMessage failed: \(error.localizedDescription)")
        }
    }

    func sendCallback(data callbackData: String, messageId: Int) async {
        do {
            _ = try await request("/api/callback", method: "POST", body: [
                "data": callbackData,
                "message_id": messageId,
                "chat_id": 0
            ])
        } catch {
            logger.error("sendCallback failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sessions

    func fetchSessions() async -> [SessionInfo] {
        do {
            let data = try await request("/api/sessions/0")
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["sessions"] as? [[String: Any]] else { return [] }
            return arr.map { s in
                SessionInfo(
                    name: s["name"] as? String ?? "",
                    busy: s["busy"] as? Bool ?? false,
                    isActive: s["is_active"] as? Bool ?? false,
                    lastCli: s["last_cli"] as? String ?? ""
                )
            }
        } catch {
            logger.error("fetchSessions failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Active Tasks

    func fetchActiveTasks() async -> [String: ActiveTask] {
        do {
            let data = try await request("/api/active-tasks/0")
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["tasks"] as? [[String: Any]] else { return [:] }
            var tasks: [String: ActiveTask] = [:]
            for t in arr {
                let session = t["session"] as? String ?? ""
                guard !session.isEmpty else { continue }
                tasks[session] = ActiveTask(
                    mode: t["mode"] as? String ?? "",
                    session: session,
                    task: t["task"] as? String ?? "",
                    phase: t["phase"] as? String ?? "",
                    step: t["step"] as? Int ?? 0,
                    started: t["started"] as? Int64 ?? 0,
                    paused: t["paused"] as? Bool ?? false
                )
            }
            return tasks
        } catch {
            logger.error("fetchActiveTasks failed: \(error.localizedDescription)")
            return [:]
        }
    }

    func cancelTask(session: String) async {
        do {
            _ = try await request("/api/cancel-task", method: "POST", body: ["session": session])
        } catch {
            logger.error("cancelTask failed: \(error.localizedDescription)")
        }
    }

    func pauseTask(session: String) async {
        do {
            _ = try await request("/api/pause-task", method: "POST", body: ["session": session])
        } catch {
            logger.error("pauseTask failed: \(error.localizedDescription)")
        }
    }

    func resumeTask(session: String) async {
        do {
            _ = try await request("/api/resume-task", method: "POST", body: ["session": session])
        } catch {
            logger.error("resumeTask failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Scheduled Tasks

    func fetchScheduledTasks() async -> [ScheduledTask] {
        do {
            let data = try await request("/api/scheduled-tasks/0")
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.map { t in
                ScheduledTask(
                    id: t["id"] as? String ?? "",
                    cwd: t["cwd"] as? String ?? "",
                    prompt: t["prompt"] as? String ?? "",
                    scheduleType: t["schedule_type"] as? String ?? "",
                    cronExpr: t["cron_expr"] as? String,
                    runAt: t["run_at"] as? String,
                    enabled: t["enabled"] as? Bool ?? true,
                    nextRun: t["next_run"] as? Int64,
                    lastRun: t["last_run"] as? Int64,
                    lastResult: t["last_result"] as? String,
                    runCount: t["run_count"] as? Int ?? 0
                )
            }
        } catch {
            logger.error("fetchScheduledTasks failed: \(error.localizedDescription)")
            return []
        }
    }

    func createScheduledTask(sessionName: String, prompt: String, scheduleType: String, cronExpr: String?, runAt: String?) async {
        var body: [String: Any] = [
            "session_name": sessionName,
            "prompt": prompt,
            "schedule_type": scheduleType
        ]
        if let cronExpr { body["cron_expr"] = cronExpr }
        if let runAt { body["run_at"] = runAt }
        do {
            _ = try await request("/api/schedule-task", method: "POST", body: body)
        } catch {
            logger.error("createScheduledTask failed: \(error.localizedDescription)")
        }
    }

    func toggleScheduledTask(id: String, enabled: Bool) async {
        do {
            _ = try await request("/api/schedule-task/\(id)", method: "PUT", body: ["enabled": enabled])
        } catch {
            logger.error("toggleScheduledTask failed: \(error.localizedDescription)")
        }
    }

    func updateScheduledTask(id: String, prompt: String?, cronExpr: String?, runAt: String?) async {
        var body: [String: Any] = [:]
        if let prompt { body["prompt"] = prompt }
        if let cronExpr { body["cron_expr"] = cronExpr }
        if let runAt { body["run_at"] = runAt }
        do {
            _ = try await request("/api/schedule-task/\(id)", method: "PUT", body: body)
        } catch {
            logger.error("updateScheduledTask failed: \(error.localizedDescription)")
        }
    }

    func triggerScheduledTask(id: String) async {
        do {
            _ = try await request("/api/schedule-task/\(id)/trigger", method: "POST")
        } catch {
            logger.error("triggerScheduledTask failed: \(error.localizedDescription)")
        }
    }

    func deleteScheduledTask(id: String) async {
        do {
            _ = try await request("/api/schedule-task/\(id)", method: "DELETE")
        } catch {
            logger.error("deleteScheduledTask failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Crash Reporting

    func reportCrash(stackTrace: String) async {
        do {
            _ = try await request("/api/crash", method: "POST", body: ["stack_trace": stackTrace])
        } catch {
            logger.error("reportCrash failed: \(error.localizedDescription)")
        }
    }
}
