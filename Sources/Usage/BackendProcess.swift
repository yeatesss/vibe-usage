import Darwin
import Foundation

/// Spawns and supervises the bundled `vibeusage-backend` binary so the .app
/// is self-contained. In `make dev` mode the backend is already running and
/// has written runtime.json — we detect that and skip the spawn.
@MainActor
final class BackendProcess {
    private var process: Process?

    func ensureRunning() {
        if isBackendAlive() { return }
        guard let bin = bundledBinary() else {
            FileHandle.standardError.write(Data("[BackendProcess] no bundled binary, skipping spawn\n".utf8))
            return
        }
        spawn(bin)
    }

    func terminate() {
        process?.terminate()
        process = nil
    }

    // MARK: - Internals

    private func bundledBinary() -> URL? {
        guard let url = Bundle.main.url(forResource: "vibeusage-backend", withExtension: nil) else {
            return nil
        }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func isBackendAlive() -> Bool {
        let runtimePath = UsageAPI.defaultDataDir.appendingPathComponent("runtime.json")
        guard let data = try? Data(contentsOf: runtimePath),
              let info = try? JSONDecoder().decode(BackendRuntimeInfo.self, from: data) else {
            return false
        }
        return kill(pid_t(info.pid), 0) == 0
    }

    private func spawn(_ binary: URL) {
        let p = Process()
        p.executableURL = binary
        p.arguments = ["--data-dir", UsageAPI.defaultDataDir.path]
        // Forward backend stderr/stdout to the app's stderr so users running
        // from a terminal can see crash diagnostics; in production these get
        // discarded by launchd, which is fine because the backend itself
        // already writes a structured log under data_dir/logs.
        p.standardOutput = FileHandle.standardError
        p.standardError  = FileHandle.standardError
        do {
            try p.run()
            self.process = p
        } catch {
            FileHandle.standardError.write(Data("[BackendProcess] spawn failed: \(error)\n".utf8))
        }
    }
}
