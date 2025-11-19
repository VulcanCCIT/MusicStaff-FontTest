//
//  MusicStaff_FontTestApp.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI
import SwiftData

/// The main entry point for the MusicStaff-FontTest application.
///
/// This app provides a music learning environment with:
/// - Interactive 3D piano keyboard
/// - MIDI input support (Bluetooth and USB)
/// - Practice session tracking with SwiftData persistence
/// - Staff notation display and note recognition exercises
///
/// ## Architecture
///
/// The app uses a SwiftUI + SwiftData architecture:
/// - **SwiftUI**: Declarative UI with environment objects for state management
/// - **SwiftData**: Persistent storage for practice sessions and history
/// - **AudioKit**: MIDI and audio synthesis
///
/// ## State Management
///
/// Two main `@StateObject` instances are created at the app level and injected
/// as environment objects throughout the view hierarchy:
/// - ``AppData``: App-wide settings and calibration data
/// - ``MIDIMonitorConductor``: MIDI event handling and audio playback
@main
struct MusicStaff_FontTestApp: App {
    /// App-wide data including MIDI range calibration and user preferences.
    @StateObject private var appData = AppData()
    
    /// MIDI conductor that handles note events and audio synthesis.
    @StateObject private var conductor = MIDIMonitorConductor()
    
    /// SwiftData model container for persistent storage.
    ///
    /// Stores:
    /// - ``PracticeSession``: Individual practice sessions with metadata
    /// - ``PersistedPracticeAttempt``: Individual note attempts within sessions
    /// - ``PracticeSessionSettings``: Configuration for practice modes
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PracticeSession.self,
            PersistedPracticeAttempt.self,
            PracticeSessionSettings.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject environment objects for access throughout view hierarchy
                .environmentObject(appData)
                .environmentObject(conductor)
                .environmentObject(conductor.bluetoothManager)
                .onAppear {
                    // Start MIDI monitoring and audio engine when app launches
                    conductor.start()
                }
        }
        // Attach SwiftData model container to the scene
        .modelContainer(sharedModelContainer)
    }
}

