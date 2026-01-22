//
//  RayeeApp.swift
//  Rayee
//
//  Main entry point for the Rayee menu bar app.
//  This file creates the app and puts a waveform icon in your menu bar.
//

import SwiftUI

@main
struct RayeeApp: App {
    // The shared app state - tracks status, transcribed text, etc.
    @StateObject private var appState = AppState()

    var body: some Scene {
        // MenuBarExtra creates the menu bar icon and popup
        // Instead of a regular window, this app lives in the menu bar
        MenuBarExtra {
            // This is what appears when you click the menu bar icon
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // The icon that appears in the menu bar
            // Changes based on current status
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)  // Shows a popup window instead of a dropdown menu
    }
}
