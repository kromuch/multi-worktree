import Foundation

public enum LoginShellPath {
    public static let marker = "__MWT_PATH__"
    public static let defaultTimeout: Duration = .seconds(5)
    public static let script = "printf '\(marker)%s\(marker)' \"$PATH\""

    public static func userShell() -> String {
        if let entry = getpwuid(getuid()), let raw = entry.pointee.pw_shell {
            let shell = String(cString: raw)
            if FileManager.default.isExecutableFile(atPath: shell) { return shell }
        }
        return "/bin/zsh"
    }

    public static func extract(from output: String) -> [String]? {
        guard let start = output.range(of: marker),
              let end = output.range(of: marker, range: start.upperBound..<output.endIndex) else { return nil }
        let entries = output[start.upperBound..<end.lowerBound]
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
        return entries.isEmpty ? nil : entries
    }
}

public extension ToolEnvironment {
    static func resolveFromLoginShell(shell: String = LoginShellPath.userShell(),
                                      runner: any CommandRunning = ProcessRunner(),
                                      extraEnvironment: [String: String] = [:],
                                      timeout: Duration = LoginShellPath.defaultTimeout) -> ToolEnvironment {
        var environment = extraEnvironment
        environment["MWT_RESOLVING_PATH"] = "1"
        let result: CommandResult
        do {
            result = try runner.run(shell, ["-ilc", LoginShellPath.script],
                                    cwd: URL(fileURLWithPath: NSHomeDirectory()),
                                    extraEnvironment: environment, timeout: timeout)
        } catch let timedOut as CommandTimeout {
            return fallback("shell did not finish in \(CommandTimeout.format(timedOut.seconds)) s")
        } catch {
            return fallback("could not start \(shell): \(error.localizedDescription)")
        }
        guard let entries = LoginShellPath.extract(from: result.stdout) else {
            return fallback(result.succeeded
                ? "no PATH in shell output"
                : "shell exited with status \(result.status) and printed no PATH")
        }
        let merged = ToolPath.merge(primary: entries, fallback: fixed.entries)
        return ToolEnvironment(path: merged.joined(separator: ":"), source: .loginShell)
    }

    private static func fallback(_ reason: String) -> ToolEnvironment {
        ToolEnvironment(path: fixedPath, source: .fallback(reason: reason))
    }
}
