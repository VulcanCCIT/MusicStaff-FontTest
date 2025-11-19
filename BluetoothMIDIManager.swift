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

// MARK: - Logging

/// Simple logging function for debugging MIDI device discovery and connection issues.
///
/// All log messages are prefixed with `[BluetoothMIDI]` for easy filtering in the console.
///
/// - Parameter message: The message to log to the console
private func Log(_ message: String) {
    print("[BluetoothMIDI] \(message)")
}

// MARK: - MIDI Input Source

/// Represents a single MIDI input source detected by the system.
///
/// This structure encapsulates both Bluetooth and USB MIDI devices, providing
/// a unified interface for device discovery and selection. Each device is uniquely
/// identified by its CoreMIDI `MIDIUniqueID`.
///
/// ## Topics
/// ### Device Identification
/// - ``id`` - Unique identifier from CoreMIDI
/// - ``name`` - Human-readable device name
/// - ``displayName`` - Formatted name with icon prefix
///
/// ### Device Properties
/// - ``isBluetooth`` - Whether this is a Bluetooth MIDI device
/// - ``isConnected`` - Current connection status
struct MIDIInputSource: Identifiable, Hashable, Equatable {
    /// The unique identifier assigned by CoreMIDI to this input source.
    ///
    /// This ID persists across app launches and can be used to remember user preferences.
    let id: MIDIUniqueID
    
    /// The human-readable name of the MIDI device.
    ///
    /// This is extracted from CoreMIDI's device properties, preferring display names
    /// and model information over generic names like "Bluetooth" or "Network Session".
    let name: String
    
    /// Indicates whether this device uses Bluetooth MIDI protocol.
    ///
    /// Bluetooth devices are identified by checking the CoreMIDI driver owner property
    /// or by matching common Bluetooth naming patterns.
    let isBluetooth: Bool
    
    /// Current connection status of the device.
    ///
    /// `true` if the device is currently online and available for MIDI communication.
    /// This is determined by checking CoreMIDI's `kMIDIPropertyOffline` property.
    let isConnected: Bool
    
    /// A formatted display name with an icon prefix.
    ///
    /// Returns the device name prefixed with:
    /// - 🔵 for Bluetooth devices
    /// - 🔌 for USB/wired devices
    var displayName: String {
        isBluetooth ? "🔵 \(name)" : "🔌 \(name)"
    }
    
    /// Custom equality comparison for MIDI input sources.
    ///
    /// Two sources are considered equal if all their properties match.
    static func == (lhs: MIDIInputSource, rhs: MIDIInputSource) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.isBluetooth == rhs.isBluetooth &&
               lhs.isConnected == rhs.isConnected
    }
}

// MARK: - Bluetooth MIDI Manager

/// Manages discovery, connection, and monitoring of MIDI input devices.
///
/// `BluetoothMIDIManager` provides a SwiftUI-friendly interface for working with
/// both Bluetooth and USB MIDI devices. It automatically discovers available devices,
/// monitors their connection status, and manages AudioKit's MIDI input configuration.
///
/// ## Usage
///
/// Create an instance by passing in an AudioKit MIDI object:
///
/// ```swift
/// let midi = AudioKit.MIDI()
/// let bluetoothManager = BluetoothMIDIManager(midi: midi)
/// ```
///
/// The manager automatically starts monitoring for device changes and publishes
/// updates through SwiftUI's `@Published` properties.
///
/// ## Topics
/// ### Device Discovery
/// - ``availableInputs`` - List of all detected MIDI devices
/// - ``updateAvailableInputs()`` - Manually trigger a device scan
///
/// ### Connection Management
/// - ``openSelectedInputs()`` - Open connections to selected devices
/// - ``closeAllInputs()`` - Close all MIDI connections
/// - ``toggleInput(_:)`` - Toggle a specific device on/off
///
/// ### Status Monitoring
/// - ``hasBluetoothDevice`` - Whether any Bluetooth devices are detected
/// - ``bluetoothDeviceCount`` - Number of Bluetooth devices found
/// - ``statusMessage`` - User-friendly status description
class BluetoothMIDIManager: ObservableObject {
    // MARK: - Published Properties
    
    /// All MIDI input devices currently detected by the system.
    ///
    /// This array is updated automatically every 5 seconds and whenever
    /// ``updateAvailableInputs()`` is called. Devices are sorted with
    /// Bluetooth devices first, then alphabetically by name.
    @Published var availableInputs: [MIDIInputSource] = []
    
    /// Set of unique IDs for devices the user has selected.
    ///
    /// Currently not actively used since all devices are connected automatically,
    /// but retained for potential future filtering functionality.
    @Published var selectedInputIDs: Set<MIDIUniqueID> = []
    
    /// Indicates whether at least one Bluetooth MIDI device is available.
    ///
    /// This is useful for showing connection status indicators in your UI.
    @Published var hasBluetoothDevice: Bool = false
    
    /// The total number of Bluetooth MIDI devices detected.
    ///
    /// USB and network MIDI devices are not included in this count.
    @Published var bluetoothDeviceCount: Int = 0
    
    // MARK: - Private Properties
    
    /// Reference to the AudioKit MIDI instance used for actual MIDI I/O.
    private let midi: AudioKit.MIDI
    
    /// Timer that triggers periodic device scans every 5 seconds.
    private var updateTimer: Timer?
    
    /// Cached device count from the last scan, used to detect changes.
    private var lastDeviceCount: Int = 0
    
    // MARK: - Initialization
    
    /// Creates a new MIDI manager with the given AudioKit MIDI instance.
    ///
    /// Device monitoring begins immediately upon initialization.
    ///
    /// - Parameter midi: The AudioKit MIDI object to use for device I/O
    init(midi: AudioKit.MIDI) {
        self.midi = midi
        startMonitoring()
    }
    
    /// Cleanup when the manager is deallocated.
    ///
    /// Stops the monitoring timer to prevent memory leaks.
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Monitoring Control
    
    /// Begin periodic monitoring for MIDI device changes.
    ///
    /// This method:
    /// 1. Performs an initial device scan
    /// 2. Sets up a timer to scan every 5 seconds
    ///
    /// Monitoring is started automatically on init, but can be called again
    /// after ``stopMonitoring()`` if needed.
    func startMonitoring() {
        // Initial scan
        updateAvailableInputs()
        
        // Set up periodic updates to detect device changes (every 5 seconds)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateAvailableInputs()
        }
    }
    
    /// Stop monitoring for device changes and invalidate the timer.
    ///
    /// Call this if you need to temporarily pause monitoring, though this
    /// is handled automatically in `deinit`.
    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Device Discovery
    
    /// Scan the system for available MIDI input devices and update published properties.
    ///
    /// This method performs a comprehensive scan of all CoreMIDI sources, extracting
    /// device names from multiple properties to find the most user-friendly name available.
    ///
    /// ## Implementation Details
    ///
    /// The scan process:
    /// 1. Queries CoreMIDI for the total number of sources via `MIDIGetNumberOfSources()`
    /// 2. For each source, retrieves properties from three levels:
    ///    - **Endpoint**: The actual MIDI input endpoint
    ///    - **Entity**: The logical grouping of endpoints (e.g., a device with multiple ports)
    ///    - **Device**: The physical hardware device
    /// 3. Prioritizes display names and model names over generic names like "Bluetooth"
    /// 4. Determines if the device uses Bluetooth by checking driver and name properties
    /// 5. Checks connection status via the `kMIDIPropertyOffline` property
    /// 6. Updates `@Published` properties on the main thread for SwiftUI updates
    /// 7. Triggers ``openSelectedInputs()`` if device count changed (new device connected)
    ///
    /// Devices are sorted with Bluetooth devices first, then alphabetically by name.
    func updateAvailableInputs() {
        var inputs: [MIDIInputSource] = []
        var bluetoothCount = 0
        
        // Get all MIDI inputs from the system
        let inputCount = MIDIGetNumberOfSources()
        
        Log("🔍 Scanning \(inputCount) MIDI source(s)...")
        
        // Iterate through each MIDI source
        for i in 0..<inputCount {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            
            // Get unique ID for this source
            var uniqueID: MIDIUniqueID = 0
            let uniqueIDErr = MIDIObjectGetIntegerProperty(src, kMIDIPropertyUniqueID, &uniqueID)
            guard uniqueIDErr == noErr else {
                Log("⚠️ Failed to get uniqueID for source \(i)")
                continue
            }
            
            // Helper function to safely extract string properties from CoreMIDI objects
            func getString(_ obj: MIDIObjectRef, _ prop: CFString) -> String? {
                var ref: Unmanaged<CFString>?
                guard MIDIObjectGetStringProperty(obj, prop, &ref) == noErr,
                      let s = ref?.takeRetainedValue() as String?, !s.isEmpty else { return nil }
                return s
            }

            // Extract properties from the endpoint level
            let endpoint = src
            let endpointName = getString(endpoint, kMIDIPropertyName) ?? ""
            let endpointDisplay = getString(endpoint, kMIDIPropertyDisplayName)
            let endpointModel = getString(endpoint, kMIDIPropertyModel)

            // Extract properties from the entity level (if available)
            var entity: MIDIEntityRef = 0
            if MIDIEndpointGetEntity(endpoint, &entity) != noErr { entity = 0 }
            let entityName = entity != 0 ? getString(entity, kMIDIPropertyName) : nil
            let entityDisplay = entity != 0 ? getString(entity, kMIDIPropertyDisplayName) : nil
            let entityModel = entity != 0 ? getString(entity, kMIDIPropertyModel) : nil

            // Extract properties from the device level (if available)
            var device: MIDIDeviceRef = 0
            if entity != 0 {
                if MIDIEntityGetDevice(entity, &device) != noErr { device = 0 }
            }
            let deviceName = device != 0 ? getString(device, kMIDIPropertyName) : nil
            let deviceDisplay = device != 0 ? getString(device, kMIDIPropertyDisplayName) : nil
            let deviceModel = device != 0 ? getString(device, kMIDIPropertyModel) : nil
            let deviceManufacturer = device != 0 ? getString(device, kMIDIPropertyManufacturer) : nil

            // Debug logging to understand what names are available
            Log("🧭 Name props - endpoint: name='\(endpointName)', display='\(endpointDisplay ?? "—")', model='\(endpointModel ?? "—")'")
            if entity != 0 {
                Log("🧭 Name props - entity: name='\(entityName ?? "—")', display='\(entityDisplay ?? "—")', model='\(entityModel ?? "—")'")
            }
            if device != 0 {
                Log("🧭 Name props - device: name='\(deviceName ?? "—")', display='\(deviceDisplay ?? "—")', model='\(deviceModel ?? "—")', mfr='\(deviceManufacturer ?? "—")'")
            }

            // Helper to identify generic/unhelpful names
            func isGeneric(_ s: String) -> Bool {
                let l = s.lowercased().trimmingCharacters(in: .whitespaces)
                if l == "bluetooth" { return true }
                if l == "network" { return true }
                if l.hasPrefix("session") { return true }
                if l.hasPrefix("network session") { return true }
                return false
            }

            // Build a list of name candidates in priority order
            var nameCandidates: [String] = []
            // Prefer explicit display names first (most user-friendly)
            if let s = endpointDisplay, !s.isEmpty { nameCandidates.append(s) }
            if let s = deviceDisplay, !s.isEmpty { nameCandidates.append(s) }
            if let s = entityDisplay, !s.isEmpty { nameCandidates.append(s) }
            // Then model names (technical but specific)
            if let s = deviceModel, !s.isEmpty { nameCandidates.append(s) }
            if let s = entityModel, !s.isEmpty { nameCandidates.append(s) }
            if let s = endpointModel, !s.isEmpty { nameCandidates.append(s) }
            // Finally plain names as fallbacks
            if let s = deviceName, !s.isEmpty { nameCandidates.append(s) }
            if let s = entityName, !s.isEmpty { nameCandidates.append(s) }
            if !endpointName.isEmpty { nameCandidates.append(endpointName) }

            // Choose the first non-generic name from our candidates
            var name = nameCandidates.first(where: { !isGeneric($0) }) ?? (nameCandidates.first ?? "Unknown Device")
            Log("🏷️ Chosen name: '\(name)'")
            
            // Determine if this is a Bluetooth device
            let isBluetooth = name.lowercased().contains("bluetooth") ||
                            name.lowercased().contains("ble") ||
                            isBluetoothMIDIEndpoint(src)
            
            if isBluetooth {
                bluetoothCount += 1
                Log("📱 Found Bluetooth device: '\(name)' (ID: \(uniqueID))")
            } else {
                Log("🔌 Found USB/Network device: '\(name)' (ID: \(uniqueID))")
            }
            
            // Check if the device is currently connected (not offline)
            var isConnected = false
            var offline: Int32 = 0
            let offlineErr = MIDIObjectGetIntegerProperty(src, kMIDIPropertyOffline, &offline)
            if offlineErr == noErr {
                isConnected = (offline == 0) // 0 means online
            }
            
            // Create the input source model
            let input = MIDIInputSource(
                id: uniqueID,
                name: name,
                isBluetooth: isBluetooth,
                isConnected: isConnected
            )
            inputs.append(input)
        }
        
        // Update published properties on main thread for SwiftUI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Sort devices: Bluetooth first, then alphabetically by name
            let sorted = inputs.sorted { first, second in
                if first.isBluetooth != second.isBluetooth {
                    return first.isBluetooth
                }
                return first.name < second.name
            }
            
            // Manually trigger objectWillChange to ensure SwiftUI updates
            self.objectWillChange.send()
            
            // Update all published properties
            self.availableInputs = sorted
            self.bluetoothDeviceCount = bluetoothCount
            self.hasBluetoothDevice = bluetoothCount > 0
            
            // Debug: Log what we're publishing to the UI
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
    
    // MARK: - Bluetooth Detection
    
    /// Determines whether a CoreMIDI endpoint is a Bluetooth MIDI device.
    ///
    /// This method checks multiple properties to identify Bluetooth devices:
    /// 1. The `kMIDIPropertyDriverOwner` property for Apple's Bluetooth MIDI driver
    /// 2. The manufacturer name for Bluetooth-related keywords
    ///
    /// - Parameter endpoint: The CoreMIDI endpoint reference to check
    /// - Returns: `true` if the endpoint appears to be a Bluetooth device
    private func isBluetoothMIDIEndpoint(_ endpoint: MIDIEndpointRef) -> Bool {
        // Check the driver owner property
        var driverRef: Unmanaged<CFString>?
        let driverErr = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDriverOwner, &driverRef)
        
        if driverErr == noErr, let driver = driverRef?.takeRetainedValue() as String? {
            // Apple's Bluetooth MIDI driver identifier
            if driver.contains("AppleMIDIBluetoothDriver") ||
               driver.contains("Bluetooth") ||
               driver.contains("com.apple.bluetooth") {
                return true
            }
        }
        
        // Also check the manufacturer property - some Bluetooth devices set this
        var manufacturerRef: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &manufacturerRef) == noErr,
           let manufacturer = manufacturerRef?.takeRetainedValue() as String? {
            // Common Bluetooth MIDI indicators in manufacturer field
            if manufacturer.lowercased().contains("bluetooth") ||
               manufacturer.lowercased().contains("ble") {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Connection Management
    
    /// Open connections to all MIDI input devices.
    ///
    /// This method:
    /// 1. Closes any existing MIDI connections via `midi.closeAllInputs()`
    /// 2. Opens a generic input that receives from all devices via `midi.openInput()`
    /// 3. Opens a specific "Bluetooth" named input for legacy iOS device consolidation
    /// 4. Triggers a device refresh via ``updateAvailableInputs()``
    ///
    /// The generic `openInput()` call with no parameters typically catches all devices,
    /// making individual device selection unnecessary in most cases.
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
    
    /// Close all MIDI input connections and clear selection.
    ///
    /// This will stop receiving MIDI events from all devices.
    /// The ``selectedInputIDs`` set is also cleared.
    func closeAllInputs() {
        midi.closeAllInputs()
        selectedInputIDs.removeAll()
        Log("🔌 All MIDI inputs closed")
    }
    
    /// Toggle a specific MIDI input device on or off.
    ///
    /// This updates the ``selectedInputIDs`` set and reopens inputs.
    /// Note: Since ``openSelectedInputs()`` currently opens all devices
    /// regardless of selection, this doesn't actually filter devices yet.
    ///
    /// - Parameter input: The device to toggle
    func toggleInput(_ input: MIDIInputSource) {
        if selectedInputIDs.contains(input.id) {
            selectedInputIDs.remove(input.id)
        } else {
            selectedInputIDs.insert(input.id)
        }
        openSelectedInputs()
    }
    
    // MARK: - Status
    
    /// A user-friendly status message describing the current MIDI device state.
    ///
    /// Returns:
    /// - "✅ X Bluetooth device(s) available" if Bluetooth devices are present
    /// - "🔌 X USB MIDI device(s) available" if only USB devices are present
    /// - "⚠️ No MIDI devices detected" if no devices are found
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

// MARK: - MIDI Device Settings View

/// A SwiftUI view for displaying and managing MIDI device connections.
///
/// This view provides a user interface for:
/// - Viewing connection status
/// - Listing all available MIDI devices (Bluetooth and USB)
/// - Refreshing device discovery
/// - Reconnecting devices
/// - Clearing stuck MIDI notes (panic button)
///
/// ## Usage
///
/// Present this view as a sheet or push it onto a navigation stack:
///
/// ```swift
/// .sheet(isPresented: $showingSettings) {
///     NavigationStack {
///         MIDIDeviceSettingsView(
///             bluetoothManager: bluetoothManager,
///             conductor: conductor
///         )
///     }
/// }
/// ```
///
/// ## View Structure
///
/// The view is organized into three main sections:
/// 1. **Connection Status** - Shows a summary of detected devices
/// 2. **Available MIDI Devices** - Lists all devices or shows empty state
/// 3. **Actions** - Buttons for refreshing, reconnecting, and panic
struct MIDIDeviceSettingsView: View {
    /// The Bluetooth manager instance that handles device discovery and connections.
    @ObservedObject var bluetoothManager: BluetoothMIDIManager
    
    /// Optional MIDI conductor for accessing the panic/clear notes function.
    var conductor: MIDIMonitorConductor?
    
    /// SwiftUI environment value for dismissing this view.
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            // Section 1: Connection Status Header
            // Shows a checkmark or warning icon with device count
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
                // Refresh device list when the view appears to ensure up-to-date info
                bluetoothManager.updateAvailableInputs()
            }
            
            // Section 2: Device List
            // Shows all available devices or an empty state if none found
            Section {
                if bluetoothManager.availableInputs.isEmpty {
                    // Empty state with icon and helpful message
                    ContentUnavailableView(
                        "No MIDI Devices Found",
                        systemImage: "pianokeys.inverse",
                        description: Text("Connect a Bluetooth MIDI keyboard or USB MIDI device")
                    )
                } else {
                    // List each device with its connection status
                    ForEach(bluetoothManager.availableInputs) { input in
                        MIDIInputRow(input: input)
                    }
                }
            } header: {
                Text("Available MIDI Devices")
            } footer: {
                Text("All detected devices are automatically connected. Bluetooth MIDI keyboards usually appear with their product name (e.g., \"XKEY Air 37 BLE\"). On iOS, multiple devices can still be consolidated under a single \"Bluetooth\" endpoint.")
            }
            
            // Section 3: Actions
            // Buttons for manual device management
            Section {
                // Refresh button - triggers a new device scan
                Button(action: {
                    bluetoothManager.updateAvailableInputs()
                }) {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                
                // Reconnect button - closes and reopens all connections
                Button(action: {
                    bluetoothManager.closeAllInputs()
                    bluetoothManager.openSelectedInputs()
                }) {
                    Label("Reconnect All Devices", systemImage: "arrow.triangle.2.circlepath")
                }
                
                // Panic button - only shown if conductor is available
                if let conductor = conductor {
                    Button(role: .destructive, action: {
                        conductor.clearAllNotes()
                    }) {
                        Label("Clear Stuck Notes (Panic)", systemImage: "exclamationmark.triangle.fill")
                    }
                }
            } header: {
                Text("Actions")
            } footer: {
                if conductor != nil {
                    Text("Use 'Clear Stuck Notes' if a key remains highlighted after you've released it. This can happen due to Bluetooth interference.")
                } else {
                    Text("Refresh devices to detect newly connected MIDI hardware.")
                }
            }
        }
        .navigationTitle("MIDI Devices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        // macOS uses large titles by default, no modifier needed
        #endif
    }
}

// MARK: - MIDI Input Row View

/// A row view displaying information about a single MIDI input device.
///
/// This view shows:
/// - Device icon (antenna for Bluetooth, cable for USB)
/// - Device name
/// - Connection status indicator (green/red dot)
/// - Connection status text
/// - Device type badge (for Bluetooth devices)
///
/// ## Visual Layout
///
/// ```
/// [Icon] Device Name          [Connection Status]
///        • Connected • Bluetooth
/// ```
struct MIDIInputRow: View {
    /// The MIDI input source to display information for.
    let input: MIDIInputSource
    
    var body: some View {
        HStack(spacing: 12) {
            // Device type icon (left side)
            // Bluetooth devices show radio waves, USB devices show a cable connector
            Image(systemName: input.isBluetooth ? "antenna.radiowaves.left.and.right" : "cable.connector")
                .font(.title2)
                .foregroundStyle(input.isBluetooth ? .blue : .secondary)
                .frame(width: 30)
            
            // Device information (center)
            VStack(alignment: .leading, spacing: 2) {
                // Device name (bold)
                Text(input.name)
                    .font(.body)
                    .fontWeight(.medium)
                
                // Status indicators row
                HStack(spacing: 8) {
                    // Connection status dot (green = connected, red = offline)
                    Circle()
                        .fill(input.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    // Connection status text
                    Text(input.isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Bluetooth badge (only shown for Bluetooth devices)
                    if input.isBluetooth {
                        Text("• Bluetooth")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // Push content to the left, leaving right side empty
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    // Create a preview with mock MIDI manager
    let midi = AudioKit.MIDI()
    let manager = BluetoothMIDIManager(midi: midi)
    
    // Add some mock data for preview after a short delay
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

