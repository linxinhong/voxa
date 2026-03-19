//
//  VoxaApp.swift
//  Voxa
//
//  Main entry point for the application.
//

import SwiftUI
import AppKit

@main
struct VoxaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene - all UI handled by AppDelegate
        Settings {
            Text("Voxa 设置")
                .frame(width: 300, height: 200)
        }
    }
}
