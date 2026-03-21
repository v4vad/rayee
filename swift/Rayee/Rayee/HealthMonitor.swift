//
//  HealthMonitor.swift
//  Rayee
//
//  Monitors the Python server's health status.
//  Derives isServerOnline directly from ServerManager state — no polling needed.
//

import Foundation
import Combine

/// Monitors the Python server health and publishes its online status
class HealthMonitor: ObservableObject {
    /// Shared instance - one health monitor for the whole app
    static let shared = HealthMonitor()

    /// Whether the Python server is currently reachable
    @Published var isServerOnline: Bool = false

    private var cancellable: AnyCancellable?

    // MARK: - Initialization

    private init() {
        cancellable = ServerManager.shared.$state
            .map { $0 == .running }
            .assign(to: \.isServerOnline, on: self)
    }

    // MARK: - Public Methods (kept for call-site compatibility)

    func start() {}
    func stop() {}
    func checkHealth() {}
}
