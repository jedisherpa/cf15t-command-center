import Cocoa

final class AgentAndTaskMonitor {
    static let shared = AgentAndTaskMonitor()

    private init() {}

    struct ProcessRow {
        let pid: pid_t
        let cpu: Double
        let rssKB: Double
        let commandName: String
        let fullArgs: String
    }

    func scanPlatformsAndTasks(openWindows: [MonitoredWindow]) -> (agents: [AgentStatusSnapshot], tasks: [RunningTaskItem]) {
        let processRows = fetchProcessTable()
        let runningApps = NSWorkspace.shared.runningApplications

        var agentSnapshots: [AgentStatusSnapshot] = []

        for platform in AgentPlatform.allCases {
            // Match running NSRunningApplications
            let matchedApps = runningApps.filter { app in
                let bundle = (app.bundleIdentifier ?? "").lowercased()
                let name = (app.localizedName ?? "").lowercased()
                let path = (app.bundleURL?.path ?? "").lowercased()
                return platform.processMatchKeywords.contains { kw in
                    bundle.contains(kw) || name.contains(kw) || path.contains(kw)
                }
            }

            // Match process rows from ps
            let matchedProcs = processRows.filter { row in
                let haystack = "\(row.commandName) \(row.fullArgs)".lowercased()
                return platform.processMatchKeywords.contains { kw in
                    haystack.contains(kw)
                }
            }

            // Match open windows
            let platformWindows = openWindows.filter { $0.platform == platform }

            let totalCPU = matchedProcs.reduce(0.0) { $0 + $1.cpu }
            let totalMemMB = matchedProcs.reduce(0.0) { $0 + ($1.rssKB / 1024.0) }
            let procCount = max(matchedApps.count, matchedProcs.count)

            let isRunning = !matchedApps.isEmpty || !matchedProcs.isEmpty || !platformWindows.isEmpty
            let state: AgentExecutionState
            if !isRunning {
                state = .offline
            } else if totalCPU >= 3.5 {
                state = .working
            } else {
                state = .idle
            }

            let activeWinTitle = platformWindows.first(where: { !$0.windowTitle.isEmpty })?.windowTitle
                ?? matchedApps.first?.localizedName

            let topSubtask: String? = {
                if let busyProc = matchedProcs.sorted(by: { $0.cpu > $1.cpu }).first, busyProc.cpu >= 1.0 {
                    return "\(busyProc.commandName) (\(String(format: "%.1f%% CPU", busyProc.cpu)))"
                }
                if let win = platformWindows.first, !win.windowTitle.isEmpty {
                    return win.windowTitle
                }
                if isRunning {
                    return "\(procCount) process\(procCount == 1 ? "" : "es") active"
                }
                return "Tap Launch to start"
            }()

            let icon: NSImage? = matchedApps.first?.icon ?? loadInstalledAppIcon(for: platform)

            let snapshot = AgentStatusSnapshot(
                platform: platform,
                state: state,
                cpuPercent: totalCPU,
                memoryMB: totalMemMB,
                processCount: procCount,
                activeWindowTitle: activeWinTitle,
                activeSubtaskSummary: topSubtask,
                primaryPID: matchedApps.first?.processIdentifier ?? matchedProcs.first?.pid,
                appIcon: icon
            )
            agentSnapshots.append(snapshot)
        }

        // Build top running tasks list
        var taskItems: [RunningTaskItem] = []
        if !processRows.isEmpty {
            let sorted = processRows
                .filter { $0.cpu >= 0.4 || isInterestingDeveloperTask($0) }
                .sorted { $0.cpu > $1.cpu }
                .prefix(24)

            for row in sorted {
                let detectedPlatform = AgentPlatform.allCases.first { plat in
                    let hay = "\(row.commandName) \(row.fullArgs)".lowercased()
                    return plat.processMatchKeywords.contains { hay.contains($0) }
                }
                taskItems.append(RunningTaskItem(
                    id: row.pid,
                    pid: row.pid,
                    commandName: row.commandName,
                    fullCommand: row.fullArgs,
                    cpuPercent: row.cpu,
                    memoryMB: row.rssKB / 1024.0,
                    platform: detectedPlatform
                ))
            }
        } else {
            // Fallback using NSWorkspace running applications if ps is blocked
            let regularApps = runningApps.filter { $0.activationPolicy == .regular }
            for app in regularApps {
                let name = app.localizedName ?? "App"
                let bundle = app.bundleIdentifier ?? ""
                let detectedPlatform = AgentPlatform.allCases.first { plat in
                    let hay = "\(name) \(bundle)".lowercased()
                    return plat.processMatchKeywords.contains { hay.contains($0) }
                }
                taskItems.append(RunningTaskItem(
                    id: app.processIdentifier,
                    pid: app.processIdentifier,
                    commandName: name,
                    fullCommand: app.bundleURL?.path ?? bundle,
                    cpuPercent: app.isActive ? 2.5 : 0.2,
                    memoryMB: 0,
                    platform: detectedPlatform
                ))
            }
        }

        return (agentSnapshots, taskItems)
    }

    private func isInterestingDeveloperTask(_ row: ProcessRow) -> Bool {
        let lower = "\(row.commandName) \(row.fullArgs)".lowercased()
        let keywords = ["claude", "codex", "grok", "ollama", "node", "python", "swift", "cargo", "rustc", "antigravity", "docker"]
        return keywords.contains { lower.contains($0) }
    }

    private func loadInstalledAppIcon(for platform: AgentPlatform) -> NSImage? {
        for path in platform.appPaths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }

    private func fetchProcessTable() -> [ProcessRow] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid=,pcpu=,rss=,comm=,args="]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return []
        }

        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 4,
                  let pid = pid_t(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Double(parts[2]) else {
                continue
            }
            let commPath = String(parts[3])
            let commName = URL(fileURLWithPath: commPath).lastPathComponent
            let args = parts.count >= 5 ? String(parts[4]) : commPath
            rows.append(ProcessRow(pid: pid, cpu: cpu, rssKB: rss, commandName: commName, fullArgs: args))
        }
        return rows
    }
}
