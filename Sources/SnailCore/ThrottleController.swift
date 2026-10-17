import Foundation

/// Runs a root shell script. The app uses `AdminPromptRunner`; `sudo snailctl` uses `RootShellRunner`.
public protocol PrivilegedRunner {
    func run(_ script: String) throws
}

/// Asks for an administrator password through the standard macOS dialog. Must be called on the main thread.
public struct AdminPromptRunner: PrivilegedRunner {
    public var prompt: String

    public init(prompt: String = "Snail needs your password to change the Wi‑Fi speed limit.") {
        self.prompt = prompt
    }

    public func run(_ script: String) throws {
        precondition(Thread.isMainThread, "NSAppleScript must run on the main thread")
        let source = ThrottleScript.appleScript(running: script, prompt: prompt)
        guard let appleScript = NSAppleScript(source: source) else {
            throw SnailError.commandFailed("Could not prepare the authorization request.")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw SnailError.cancelled }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SnailError.commandFailed(message)
        }
    }
}

/// Runs the script directly with /bin/sh. Requires the process to already be root.
public struct RootShellRunner: PrivilegedRunner {
    public init() {}

    public func run(_ script: String) throws {
        guard geteuid() == 0 else { throw SnailError.notRoot }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SnailError.commandFailed(message.isEmpty ? "Exited with status \(process.terminationStatus)." : message)
        }
    }
}

public struct ThrottleController {
    public var runner: PrivilegedRunner
    public var statePath: String

    public init(runner: PrivilegedRunner, statePath: String = ThrottleScript.statePath) {
        self.runner = runner
        self.statePath = statePath
    }

    public func apply(_ config: ThrottleConfig) throws {
        try runner.run(ThrottleScript.onScript(for: config))
    }

    public func remove() throws {
        try runner.run(ThrottleScript.offScript())
    }

    /// The config currently in force, read from the world-readable state file the root script writes.
    /// Returns nil when Snail isn't limiting anything (including after a reboot, since /var/run is cleared).
    public func activeConfig() -> ThrottleConfig? {
        guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
        return try? JSONDecoder().decode(ThrottleConfig.self, from: data)
    }

    /// Reads the saved config without a claim about live kernel state.
    public func recordedConfig() throws -> ThrottleConfig {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        } catch {
            let fileError = error as NSError
            if fileError.domain == NSCocoaErrorDomain,
               fileError.code == NSFileReadNoSuchFileError || fileError.code == NSFileNoSuchFileError {
                throw RecordedStateError.absent
            }
            throw RecordedStateError.unreadable(path: statePath, reason: error.localizedDescription)
        }
        do {
            let config = try JSONDecoder().decode(ThrottleConfig.self, from: data)
            _ = try config.validated()
            return config
        } catch {
            throw RecordedStateError.invalid(path: statePath)
        }
    }
}
