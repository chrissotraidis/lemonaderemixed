import CryptoKit
import Foundation

/// Owns the private Wine setup that runs the original game: creating it,
/// installing the game from the player's Setup.exe, launching it through the
/// helper, sound volume and shutdown.
public final class GameRuntime {
    public enum Failure: Error, CustomStringConvertible {
        case wrongInstaller, wineFailed(String), missingResource(String)
        public var description: String {
            switch self {
            case .wrongInstaller: return "That file isn't the supported Lemonade Tycoon Deluxe installer."
            case .wineFailed(let step): return "Setting up the game failed while \(step). See the log in Application Support."
            case .missingResource(let name): return "The app is missing \(name)."
            }
        }
    }

    /// Where the bundled pieces live: wine/, helper/ and agent/fmod.dll.
    public let resources: URL
    /// ~/Library/Application Support/Lemonade Remixed (or an override).
    public let support: URL

    public var prefix: URL { support.appendingPathComponent("wine") }
    public var gameDir: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Lemonade Tycoon Deluxe") }
    var helperDir: URL { prefix.appendingPathComponent("drive_c/remix/helper") }
    var logFile: URL { support.appendingPathComponent("wine.log") }
    /// Frames from the in-game agent's frame tap.
    public var framesFile: URL { gameDir.appendingPathComponent("remix-frames.bin") }
    var wine: URL { resources.appendingPathComponent("wine/bin/wine") }
    var wineserver: URL { resources.appendingPathComponent("wine/bin/wineserver") }

    static let gameDirWindows = #"C:\Program Files (x86)\Lemonade Tycoon Deluxe"#
    static let helperWindows = #"C:\remix\helper"#

    private var helper: Process?

    public init(resources: URL, support: URL) {
        self.resources = resources
        self.support = support
    }

    public var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: gameDir.appendingPathComponent("Lemonade.exe").path)
            && fm.fileExists(atPath: gameDir.appendingPathComponent("fmodreal.dll").path)
    }

    // MARK: - Install

    /// Checks the installer, creates the Wine setup and installs the game into it.
    public func install(setup: URL, progress: @escaping (String) -> Void) throws {
        progress("Checking the installer…")
        let data = try Data(contentsOf: setup)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == InstallerArchive.knownSHA256 else { throw Failure.wrongInstaller }
        let archive = try InstallerArchive(installer: data)

        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            progress("Preparing Windows support (first time only)…")
            // Without the Mac display driver, Wine's "updating" dialog can't appear.
            guard run(wine, ["wineboot", "-i"], display: false) == 0 else { throw Failure.wineFailed("preparing Wine") }
            _ = run(wineserver, ["-w"])
        }

        progress("Installing the game…")
        try archive.extract(to: gameDir)
        try installAgent()
        progress("Ready")
    }

    /// The game's fmod.dll becomes fmodreal.dll and our agent takes its
    /// place: it applies the volume from remix-volume.txt and writes frames
    /// to remix-frames.bin.
    private func installAgent() throws {
        let fm = FileManager.default
        let original = gameDir.appendingPathComponent("fmod.dll")
        let real = gameDir.appendingPathComponent("fmodreal.dll")
        let agent = resources.appendingPathComponent("agent/fmod.dll")
        guard fm.fileExists(atPath: agent.path) else { throw Failure.missingResource("the in-game agent") }
        if !fm.fileExists(atPath: real.path) { try fm.moveItem(at: original, to: real) }
        try? fm.removeItem(at: original)
        try fm.copyItem(at: agent, to: original)
    }

    /// Wine's headless display driver: the game's windows exist but are never
    /// shown, and Wine never appears in the Dock. Frames come from the agent.
    private func useHeadlessDisplay() {
        let userReg = prefix.appendingPathComponent("user.reg")
        if let text = try? String(contentsOf: userReg, encoding: .utf8), text.contains("\"Graphics\"=\"null\"") { return }
        _ = run(wine, ["reg", "add", #"HKCU\Software\Wine\Drivers"#, "/v", "Graphics", "/d", "null", "/f"], display: false)
        _ = run(wineserver, ["-w"])
    }

    /// Older setups linked Wine's Desktop, Documents and similar folders to
    /// the player's own. Replace those links (only the links) with empty
    /// folders so the game never reaches outside its own setup.
    private func isolateUserFolders() {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users")
        for user in (try? fm.contentsOfDirectory(atPath: users.path)) ?? [] {
            let dir = users.appendingPathComponent(user)
            for item in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let link = dir.appendingPathComponent(item)
                guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path),
                      !target.hasPrefix(support.path) else { continue }
                if unlink(link.path) == 0 { try? fm.createDirectory(at: link, withIntermediateDirectories: false) }
            }
        }
    }

    // MARK: - Run

    /// Starts the helper, which starts the game and serves the bridge.
    public func launch() throws {
        guard helper?.isRunning != true else { return }
        isolateUserFolders()   // before any Wine process can follow an old link
        try installHelper()
        try? installAgent()   // keep the agent current with the app
        useHeadlessDisplay()
        let p = makeProcess(wine, [Self.helperWindows + #"\python\pythonw.exe"#,
                                   Self.helperWindows + #"\winctl.py"#, "serve", Self.gameDirWindows])
        try p.run()
        helper = p
    }

    /// Copies the helper (Windows Python and scripts) into the Wine setup.
    private func installHelper() throws {
        let fm = FileManager.default
        let source = resources.appendingPathComponent("helper")
        guard fm.fileExists(atPath: source.appendingPathComponent("winctl.py").path) else { throw Failure.missingResource("the helper") }
        try? fm.removeItem(at: helperDir)
        try fm.createDirectory(at: helperDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: helperDir)
    }

    /// Player volume, 0 to 100, applied live by the audio proxy.
    /// Whether the helper (and so the game) is still running.
    public var isRunning: Bool { helper?.isRunning == true }

    /// Player volume, 0 to 100, applied live by the audio proxy.
    public func setVolume(_ volume: Int) {
        let v = max(0, min(100, volume))
        try? Data(String(v).utf8).write(to: gameDir.appendingPathComponent("remix-volume.txt"))
    }

    /// Asks the game to close, then shuts Wine down.
    public func stop() {
        _ = Bridge.request("quit", timeout: 2)
        Thread.sleep(forTimeInterval: 1.0)
        _ = run(wineserver, ["-k"])
        helper = nil
    }

    // MARK: - Processes

    private func makeProcess(_ exe: URL, _ args: [String], display: Bool = true) -> Process {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        // A private home folder: otherwise Wine links its Desktop, Documents
        // and other folders to the player's own, and macOS asks for access.
        let home = support.appendingPathComponent("home")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        env["HOME"] = home.path
        env["WINEDEBUG"] = "-all"
        env["REMIX_PORT"] = String(Bridge.port)
        env["WINEDLLOVERRIDES"] = "mscoree=;mshtml=;winemenubuilder.exe=d" + (display ? "" : ";winemac.drv=d")
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        // Output goes through a pipe: Windows Python under Wine refuses to
        // start when its output is a regular file.
        let fm = FileManager.default
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logFile.path) { fm.createFile(atPath: logFile.path, contents: nil) }
        if let log = try? FileHandle(forWritingTo: logFile) {
            log.seekToEndOfFile()
            let pipe = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { log.write(data) }
            }
            p.standardOutput = pipe
            p.standardError = pipe
        }
        return p
    }

    @discardableResult
    private func run(_ exe: URL, _ args: [String], display: Bool = true) -> Int32 {
        let p = makeProcess(exe, args, display: display)
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
