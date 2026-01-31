//
//  HealthMonitor.swift
//  Rayee
//
//  Monitors the Python server's health status.
//  Checks periodically and publishes whether the server is online.
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

    // MARK: - Initialization

    init(pythonBridge: PythonBridge = PythonBridge()) {
        self.pythonBridge = pythonBridge
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Start monitoring server health
    /// Performs an immediate check, then checks periodically
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Check immediately
        checkHealth()

        // Then check periodically
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

    /// Perform a single health check (useful for manual refresh)
    func checkHealth() {
        Task { @MainActor in
            let isOnline = await pythonBridge.checkHealth()
            self.isServerOnline = isOnline
        }
    }
}
