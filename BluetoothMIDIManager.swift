//
//  BluetoothMIDIManager.swift
//  MusicStaff-FontTest
//
//  Enhanced Bluetooth MIDI support with device discovery and status monitoring
//

import AudioKit
import CoreMIDI
import SwiftUI
import Combine

/// Simple logging function - replace with your actual logging if available
private func Log(_ message: String) {
    print("[BluetoothMIDI] \(message)")
}

/// Represents a MIDI input source (Bluetooth or USB)
struct MIDIInputSource: Identifiable, Hashable {
    let id: MIDIUniqueID
    let name: String
    let isBluetooth: Bool
    let isConnected: Bool
    
    var displayName: String {
        isBluetooth ? "🔵 \(name)" : "🔌 \(name)"
    }
}

/// Manages Bluetooth and USB MIDI connections with device discovery
class BluetoothMIDIManager: ObservableObject {
    @Published var availableInputs: [MIDIInputSource] = []
    @Published var selectedInputIDs: Set<MIDIUniqueID> = []
    @Published var hasBluetoothDevice: Bool = false
    @Published var bluetoothDeviceCount: Int = 0
    
    private let midi: AudioKit.MIDI
    private var updateTimer: Timer?
    private var lastDeviceCount: Int = 0
    
    init(midi: AudioKit.MIDI) {
        self.midi = midi
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Start monitoring for MIDI device changes
    func startMonitoring() {
        // Initial scan
        updateAvailableInputs()
        
        // Set up periodic updates to detect device changes (every 5 seconds)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateAvailableInputs()
        }
    }
    
    /// Stop monitoring for device changes
    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// Scan for available MIDI input devices
    func updateAvailableInputs() {
        var inputs: [MIDIInputSource] = []
        var bluetoothCount = 0
        
        // Get all MIDI inputs from the system
        let inputCount = MIDIGetNumberOfSources()
        
        for i in 0..<inputCount {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            
            // Get unique ID
            var uniqueID: MIDIUniqueID = 0
            let uniqueIDErr = MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &uniqueID)
            guard uniqueIDErr == noErr else { continue }
            
            // Get device name
            var nameRef: Unmanaged<CFString>?
            let nameErr = MIDIObjectGetStringProperty(src, kMIDIPropertyName, &nameRef)
            let name = (nameErr == noErr && nameRef != nil) ? (nameRef!.takeRetainedValue() as String) : "Unknown Device"
            
            // Check if it's a Bluetooth device
            let isBluetooth = name.lowercased().contains("bluetooth") || 
                            name.lowercased().contains("ble") ||
                            isBluetoothMIDIEndpoint(src)
            
            if isBluetooth {
                bluetoothCount += 1
            }
            
            // Check connection status
            var isConnected = false
            var offline: Int32 = 0
            let offlineErr = MIDIObjectGetIntegerProperty(src, kMIDIPropertyOffline, &offline)
            if offlineErr == noErr {
                isConnected = (offline == 0)
            }
            
            let input = MIDIInputSource(
                id: uniqueID,
                name: name,
                isBluetooth: isBluetooth,
                isConnected: isConnected
            )
            inputs.append(input)
        }
        
        // Update published properties on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let sorted = inputs.sorted { first, second in
                // Sort by: Bluetooth first, then by name
                if first.isBluetooth != second.isBluetooth {
                    return first.isBluetooth
                }
                return first.name < second.name
            }
            
            // Manually trigger objectWillChange to ensure SwiftUI updates
            self.objectWillChange.send()
            
            self.availableInputs = sorted
            self.bluetoothDeviceCount = bluetoothCount
            self.hasBluetoothDevice = bluetoothCount > 0
            
            // Debug: Log what we're publishing
            Log("📋 Publishing \(sorted.count) device(s) to UI:")
            for device in sorted {
                Log("   \(device.displayName) - Connected: \(device.isConnected)")
            }
            
            // If device count changed, reopen MIDI inputs to catch new devices
            if sorted.count != self.lastDeviceCount {
                Log("🔄 Device count changed (\(self.lastDeviceCount) → \(sorted.count)), reopening MIDI inputs...")
                self.lastDeviceCount = sorted.count
                self.openSelectedInputs()
            }
        }
    }
    
    /// Check if a MIDI endpoint is a Bluetooth MIDI device
    private func isBluetoothMIDIEndpoint(_ endpoint: MIDIEndpointRef) -> Bool {
        // Check the driver owner property
        var driverRef: Unmanaged<CFString>?
        let driverErr = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDriverOwner, &driverRef)
        
        if driverErr == noErr, let driver = driverRef?.takeRetainedValue() as String? {
            // Apple's Bluetooth MIDI driver identifier
            return driver.contains("AppleMIDIBluetoothDriver") || 
                   driver.contains("Bluetooth")
        }
        
        return false
    }
    
    /// Open all selected MIDI inputs
    func openSelectedInputs() {
        midi.closeAllInputs()
        
        // Open the generic inputs (catches all devices if none specifically selected)
        midi.openInput()
        midi.openInput(name: "Bluetooth")
        
        // Log opened inputs for debugging
        let inputNames = midi.inputNames
        Log("✅ MIDI inputs opened (Bluetooth + all devices)")
        Log("📝 AudioKit reports \(inputNames.count) input(s): \(inputNames)")
        
        updateAvailableInputs()
    }
    
    /// Close all MIDI inputs
    func closeAllInputs() {
        midi.closeAllInputs()
        selectedInputIDs.removeAll()
        Log("🔌 All MIDI inputs closed")
    }
    
    /// Toggle a specific MIDI input on/off
    func toggleInput(_ input: MIDIInputSource) {
        if selectedInputIDs.contains(input.id) {
            selectedInputIDs.remove(input.id)
        } else {
            selectedInputIDs.insert(input.id)
        }
        openSelectedInputs()
    }
    
    /// Get a user-friendly status message
    var statusMessage: String {
        if bluetoothDeviceCount > 0 {
            return "✅ \(bluetoothDeviceCount) Bluetooth device(s) available"
        } else {
            let totalDevices = availableInputs.count
            if totalDevices > 0 {
                return "🔌 \(totalDevices) USB MIDI device(s) available"
            } else {
                return "⚠️ No MIDI devices detected"
            }
        }
    }
}

/// SwiftUI view for displaying MIDI device settings
struct MIDIDeviceSettingsView: View {
    @ObservedObject var bluetoothManager: BluetoothMIDIManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: bluetoothManager.hasBluetoothDevice ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(bluetoothManager.hasBluetoothDevice ? .green : .orange)
                    Text(bluetoothManager.statusMessage)
                        .font(.subheadline)
                }
            } header: {
                Text("Connection Status")
            }
            .onAppear {
                // Refresh devices when view appears
                bluetoothManager.updateAvailableInputs()
            }
            
            Section {
                if bluetoothManager.availableInputs.isEmpty {
                    ContentUnavailableView(
                        "No MIDI Devices Found",
                        systemImage: "pianokeys.inverse",
                        description: Text("Connect a Bluetooth MIDI keyboard or USB MIDI device")
                    )
                } else {
                    ForEach(bluetoothManager.availableInputs) { input in
                        MIDIInputRow(input: input)
                    }
                }
            } header: {
                Text("Available MIDI Devices")
            } footer: {
                Text("All detected devices are automatically connected. Bluetooth MIDI keyboards appear as \"Bluetooth\" (iOS combines all Bluetooth MIDI devices under one endpoint).")
            }
            
            Section {
                Button(action: {
                    bluetoothManager.updateAvailableInputs()
                }) {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                
                Button(action: {
                    bluetoothManager.closeAllInputs()
                    bluetoothManager.openSelectedInputs()
                }) {
                    Label("Reconnect All Devices", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Actions")
            }
        }
        .navigationTitle("MIDI Devices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        // No additional modifiers needed for macOS
        #endif
    }
}

/// Row view for a single MIDI input device
struct MIDIInputRow: View {
    let input: MIDIInputSource
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: input.isBluetooth ? "antenna.radiowaves.left.and.right" : "cable.connector")
                .font(.title2)
                .foregroundStyle(input.isBluetooth ? .blue : .secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(input.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(input.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(input.isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if input.isBluetooth {
                        Text("• Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    // Create a preview with mock MIDI manager
    let midi = AudioKit.MIDI()
    let manager = BluetoothMIDIManager(midi: midi)
    
    // Add some mock data for preview
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        manager.availableInputs = [
            MIDIInputSource(id: 1, name: "Bluetooth MIDI Keyboard", isBluetooth: true, isConnected: true),
            MIDIInputSource(id: 2, name: "USB MIDI Controller", isBluetooth: false, isConnected: true),
            MIDIInputSource(id: 3, name: "Virtual MIDI Bus", isBluetooth: false, isConnected: false)
        ]
        manager.bluetoothDeviceCount = 1
        manager.hasBluetoothDevice = true
    }
    
    return MIDIDeviceSettingsView(bluetoothManager: manager)
}
