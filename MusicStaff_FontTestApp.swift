//
//  MusicStaff_FontTestApp.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI
import SwiftData

@main
struct MusicStaff_FontTestApp: App {
    @StateObject private var appData = AppData()
    @StateObject private var conductor = MIDIMonitorConductor()
    
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
                .environmentObject(appData)
                .environmentObject(conductor)
                .onAppear {
                    // Ensure conductor is started when the app launches
                    conductor.start()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
