import Foundation

enum LaunchAtLogin {
    static let label = "com.codex.agentpet"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let executable = Bundle.main.executablePath else {
                throw NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到应用可执行文件"])
            }

            let directory = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
                "LimitLoadToSessionType": "Aqua"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)

            runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
            let result = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
            if result.status != 0 {
                // 某些系统会在已注册时返回错误，但文件已经存在，仍可工作。
                if !FileManager.default.fileExists(atPath: plistURL.path) {
                    throw NSError(domain: label, code: 2, userInfo: [NSLocalizedDescriptionKey: "无法注册开机启动"])
                }
            }
        } else {
            runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
