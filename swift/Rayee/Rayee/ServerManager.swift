//
//  ServerManager.swift
//  Rayee
//
//  Manages the lifecycle of the bundled Python transcription server.
//  When the app launches, this starts the Python server automatically.
//  When the app quits, it shuts down the server cleanly.
//

import Foundation

/// Manages the Python transcription server lifecycle
class ServerManager: ObservableObject {
    /// Shared instance (only one server manager needed)
    static let shared = ServerManager()

    /// Current state of the server
    @Published var state: ServerState = .notStarted

    /// Error message if server failed to start
    @Published var errorMessage: String?

    /// The server process
    private var serverProcess: Process?

    /// File handle for logging server output
    private var logFileHandle: FileHandle?

    /// Timer to check if server is responsive
    private var healthCheckTimer: Timer?

    /// How many times we've tried to restart after a crash
    private var restartAttempts = 0

    /// Bridge for checking startup status
    private let pythonBridge = PythonBridge()

    /// Possible states for the server
    enum ServerState: String {
        case notStarted = "Not Started"
        case starting = "Starting..."
        case downloadingModels = "Downloading AI models..."
        case running = "Running"
        case failed = "Failed"
        case stopped = "Stopped"
    }

    private init() {}

    // MARK: - Public Methods

    /// Start the Python server
    /// Call this when the app launches
    func start() {
        // Don't start if already running
        guard state != .starting && state != .running else {
            print("[ServerManager] Server already starting or running")
            return
        }

        state = .starting
        errorMessage = nil
        restartAttempts = 0

        AppLogger.logServer("Starting Python server...")

        // Run on background thread so we don't block the UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.launchServer()
        }
    }

    /// Stop the Python server
    /// Call this when the app quits
    func stop() {
        print("[ServerManager] Stopping server...")
        AppLogger.logServer("Stopping Python server...")
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        if let process = serverProcess, process.isRunning {
            // Send SIGTERM for graceful shutdown
            process.terminate()

            // Wait briefly for it to stop
            DispatchQueue.global().async {
                self.serverProcess?.waitUntilExit()
                print("[ServerManager] Server stopped")
                AppLogger.logServer("Server stopped gracefully")
            }
        }

        logFileHandle?.closeFile()
        logFileHandle = nil

        DispatchQueue.main.async {
            self.state = .stopped
        }
    }

    // MARK: - Private Methods

    /// Find the path to the bundled Python server executable
    private func findServerExecutable() -> URL? {
        // In development, server won't be bundled - return nil
        // In production, it's in: Rayee.app/Contents/Resources/RayeeServer/RayeeServer

        guard let resourcesPath = Bundle.main.resourcePath else {
            print("[ServerManager] Could not find app resources path")
            return nil
        }

        let serverPath = URL(fileURLWithPath: resourcesPath)
            .appendingPathComponent("RayeeServer")
            .appendingPathComponent("RayeeServer")

        // Check if the executable exists
        if FileManager.default.fileExists(atPath: serverPath.path) {
            print("[ServerManager] Found bundled server at: \(serverPath.path)")
            return serverPath
        }

        print("[ServerManager] Bundled server not found at: \(serverPath.path)")
        return nil
    }

    /// Create the log directory and file
    private func setupLogging() -> FileHandle? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let rayeeDir = homeDir.appendingPathComponent(".rayee")
        let logFile = rayeeDir.appendingPathComponent("server.log")

        // Create ~/.rayee directory if needed
        do {
            try fileManager.createDirectory(at: rayeeDir, withIntermediateDirectories: true)
        } catch {
            print("[ServerManager] Could not create log directory: \(error)")
            return nil
        }

        // Create or clear the log file
        fileManager.createFile(atPath: logFile.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: logFile)
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let header = "=== Rayee Server Log - \(timestamp) ===\n"
            handle.write(header.data(using: .utf8)!)
            print("[ServerManager] Logging to: \(logFile.path)")
            return handle
        } catch {
            print("[ServerManager] Could not open log file: \(error)")
            return nil
        }
    }

    /// Actually launch the server process
    private func launchServer() {
        guard let serverPath = findServerExecutable() else {
            // In development mode, server isn't bundled
            // User needs to run it manually
            DispatchQueue.main.async {
                self.state = .notStarted
                self.errorMessage = "Development mode: Start server manually with 'python run_server.py'"
                print("[ServerManager] No bundled server - development mode")
            }
            return
        }

        // Set up logging
        logFileHandle = setupLogging()

        // Create the process
        let process = Process()
        process.executableURL = serverPath

        // Set working directory to where the server is
        process.currentDirectoryURL = serverPath.deletingLastPathComponent()

        // Set up environment for the bundled Python
        var env = ProcessInfo.processInfo.environment
        // Clear PYTHONHOME and PYTHONPATH to avoid conflicts
        env.removeValue(forKey: "PYTHONHOME")
        env.removeValue(forKey: "PYTHONPATH")
        process.environment = env

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Log output in background
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.logFileHandle?.write(data)
                if let text = String(data: data, encoding: .utf8) {
                    print("[Server] \(text)", terminator: "")
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.logFileHandle?.write(data)
                if let text = String(data: data, encoding: .utf8) {
                    print("[Server Error] \(text)", terminator: "")
                }
            }
        }

        // Handle process termination
        process.terminationHandler = { [weak self] process in
            guard let self = self else { return }

            let exitCode = process.terminationStatus
            print("[ServerManager] Server exited with code: \(exitCode)")
            AppLogger.logServer("Server exited with code: \(exitCode)")

            DispatchQueue.main.async {
                // If we didn't intentionally stop it and haven't exceeded restart attempts
                if self.state == .running && self.restartAttempts < Config.maxServerRestartAttempts {
                    self.restartAttempts += 1
                    let message = "Server crashed, attempting restart \(self.restartAttempts)/\(Config.maxServerRestartAttempts)"
                    print("[ServerManager] \(message)")
                    AppLogger.logServer(message)
                    self.state = .starting

                    // Wait a moment before restarting
                    DispatchQueue.global().asyncAfter(deadline: .now() + Config.serverRestartDelay) {
                        self.launchServer()
                    }
                } else if self.state != .stopped {
                    self.state = .failed
                    self.errorMessage = "Server crashed (exit code: \(exitCode))"
                    AppLogger.logError("Server crashed permanently (exit code: \(exitCode))")
                }
            }
        }

        // Launch the process
        do {
            try process.run()
            serverProcess = process
            print("[ServerManager] Server process started (PID: \(process.processIdentifier))")
            AppLogger.logServer("Server process started (PID: \(process.processIdentifier))")

            // Start health checks to confirm server is responsive
            DispatchQueue.main.async {
                self.startHealthChecks()
            }

        } catch {
            DispatchQueue.main.async {
                self.state = .failed
                self.errorMessage = "Failed to start server: \(error.localizedDescription)"
                print("[ServerManager] Failed to start: \(error)")
                AppLogger.logError("Failed to start server", error: error)
            }
        }
    }

    /// Periodically check if the server is responsive
    private func startHealthChecks() {
        // Check frequently until server is confirmed running
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: Config.healthCheckIntervalDuringStartup, repeats: true) { [weak self] _ in
            self?.checkServerHealth()
        }

        // Also check immediately
        checkServerHealth()
    }

    private func checkServerHealth() {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = Config.healthCheckIntervalDuringStartup

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                // Server is healthy - now check startup status
                Task {
                    await self.checkStartupStatus()
                }
            } else {
                DispatchQueue.main.async {
                    if self.state == .running {
                        // Was running but now isn't responding - might be restarting
                        print("[ServerManager] Health check failed, server may be restarting")
                    }
                }
            }
        }.resume()
    }

    /// Check the startup status to see if models are still downloading
    private func checkStartupStatus() async {
        guard let status = await pythonBridge.getStartupStatus() else {
            return
        }

        await MainActor.run {
            switch status.state {
            case "downloading_vad", "downloading_whisper":
                // Models are downloading
                if self.state == .starting || self.state == .downloadingModels {
                    self.state = .downloadingModels
                    print("[ServerManager] \(status.message)")
                }

            case "ready":
                // All models loaded, server is fully ready
                if self.state != .running {
                    self.state = .running
                    self.restartAttempts = 0
                    print("[ServerManager] Server is now running and healthy")

                    // Slow down health checks now that it's running
                    self.healthCheckTimer?.invalidate()
                    self.healthCheckTimer = Timer.scheduledTimer(
                        withTimeInterval: Config.healthCheckIntervalWhenRunning, repeats: true
                    ) { [weak self] _ in
                        self?.checkServerHealth()
                    }
                }

            case "failed":
                // Model loading failed
                self.state = .failed
                self.errorMessage = status.error ?? status.message
                print("[ServerManager] Model loading failed: \(status.error ?? "unknown")")

            default:
                // not_started or unknown - keep checking
                break
            }
        }
    }
}
