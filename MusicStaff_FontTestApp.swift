//
//  MusicStaff_FontTestApp.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI

@main
struct MusicStaff_FontTestApp: App {
    @StateObject private var appData = AppData()
    @StateObject private var conductor = MIDIMonitorConductor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
                .environmentObject(conductor)
        }
    }
}
