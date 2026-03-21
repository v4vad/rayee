//
//  HealthMonitor.swift
//  Rayee
//
//  Monitors the Python server's health status.
//  Uses ServerManager state for instant updates, plus periodic socket checks
//  to detect manually-started servers (development mode).
//

import Foundation
import Combine

/// Monitors the Python server health and publishes its online status
class HealthMonitor: ObservableObject {
    /// Shared instance - one health monitor for the whole app
    static let shared = HealthMonitor()

    /// Whether the Python server is currently reachable
    @Published var isServerOnline: Bool = false

    /// Bridge for making health check requests
    private let pythonBridge: PythonBridge

    /// Timer for periodic health checks
    private var healthCheckTimer: Timer?

    /// Whether monitoring is active
    private var isMonitoring = false

    /// Combine subscription for ServerManager state
    private var cancellable: AnyCancellable?

    // MARK: - Initialization

    init(pythonBridge: PythonBridge = PythonBridge()) {
        self.pythonBridge = pythonBridge

        // Instantly set online when ServerManager reports running
        cancellable = ServerManager.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .running {
                    self?.isServerOnline = true
                }
            }
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Start monitoring server health
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        checkHealth()

        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: Config.healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkHealth()
        }
    }

    /// Stop monitoring server health
    func stop() {
        isMonitoring = false
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    /// Perform a single health check
    func checkHealth() {
        Task { @MainActor in
            let isOnline = await pythonBridge.checkHealth()
            self.isServerOnline = isOnline
        }
    }
}
