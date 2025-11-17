//
//  ContentView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import AudioKit
import AudioKitEX
import AudioKitUI
import Combine
import CoreMIDI
import SwiftUI
import AVFAudio

#if os(macOS)
import CoreAudio
#endif

// Simple logging function
fileprivate func Log(_ message: String) {
    print("[MIDIMonitor] \(message)")
}

// struct representing last data received of each type

struct MIDIMonitorData {
    var noteOn = 0
    var velocity = 0
    var noteOff = 0
    var channel = 0
    var afterTouch = 0
    var afterTouchNoteNumber = 0
    var programChange = 0
    var pitchWheelValue = 0
    var controllerNumber = 0
    var controllerValue = 0
}

enum MIDIEventType {
    case none
    case noteOn
    case noteOff
    case continuousControl
    case programChange
}

class MIDIMonitorConductor: ObservableObject, MIDIListener {
    let midi = AudioKit.MIDI()
    // Audio engine and instrument (Option B)
    let engine = AudioEngine()
    var instrument = AppleSampler()
    private var engineStarted = false
    private var instrumentLoaded = false

    // Scale external MIDI velocities to match on-screen loudness
    @Published var externalVelocityBoost: Double = 2.25

    @Published var data = MIDIMonitorData()
    @Published var isShowingMIDIReceived: Bool = false
    @Published var isToggleOn: Bool = false
    @Published var oldControllerValue: Int = 0
    @Published var midiEventType: MIDIEventType = .none
    @Published var activeNotes = Set<Int>()
    @Published var noteOnEventID = UUID()
    @Published var lastEventWasSimulated: Bool = false

    // Per-event publishers (Option A): emit exact payloads for immediate handling
    let noteOnSubject = PassthroughSubject<(Int, Int), Never>()
    let noteOffSubject = PassthroughSubject<Int, Never>()
    
    // Bluetooth MIDI manager (optional, for enhanced device management)
    lazy var bluetoothManager: BluetoothMIDIManager = {
        BluetoothMIDIManager(midi: self.midi)
    }()
    
    #if os(macOS)
    private var defaultDeviceListenerInstalled = false
    #endif
    
    // MARK: - Stuck Note Prevention
    /// Track when each note was turned on to detect stuck notes
    private var noteOnTimestamps: [Int: Date] = [:]
    /// Maximum duration a note can be held before being automatically released (10 seconds)
    private let stuckNoteTimeout: TimeInterval = 10.0
    /// Timer for checking stuck notes
    private var stuckNoteTimer: Timer?

    #if os(iOS)
    /// Configure AVAudioSession for playback (required on iOS/iPadOS to enable AirPlay/HomePod routing)
    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Use .playback to allow AirPlay output; add .mixWithOthers if you want to mix with other apps
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            Log("AVAudioSession configured for playback")
        } catch {
            Log("Failed to set up AVAudioSession: \(error)")
        }
    }
    #endif

    init() {
        // Configure audio chain
        engine.output = instrument
        loadInstrument()
        startStuckNoteMonitoring()
        
        // Observe AVAudioEngine configuration changes (all platforms)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        
        // Observe default output device changes (macOS)
        #if os(macOS)
        installDefaultOutputDeviceListenerIfNeeded()
        #endif
        
        // Observe AVAudioSession route changes (iOS/iPadOS)
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.restartAudioEngineAfterChange(reason: "AVAudioSessionRouteChange")
        }
        #endif
    }
    
    deinit {
        stopStuckNoteMonitoring()
    }
    
    private func loadInstrument() {
        // Load the instrument (SoundFont) - safe to call multiple times
        guard !instrumentLoaded else { return }
        
        do {
            if let url = Bundle.main.url(forResource: "Sounds/YDP-GrandPiano", withExtension: "sf2") {
                try instrument.loadInstrument(url: url)
                instrumentLoaded = true
                Log("Loaded instrument Successfully!")
            } else {
                Log("Could not find SoundFont file")
            }
        } catch {
            Log("Could not load instrument: \(error.localizedDescription)")
        }
    }
    
    /// Force-reload the instrument SoundFont on the sampler. Useful after engine/device changes.
    private func reloadInstrument() {
        do {
            if let url = Bundle.main.url(forResource: "Sounds/YDP-GrandPiano", withExtension: "sf2") {
                try instrument.loadInstrument(url: url)
                instrumentLoaded = true
                Log("Reloaded instrument successfully after device/engine change")
            } else {
                Log("Could not find SoundFont file during reload")
            }
        } catch {
            Log("Could not reload instrument: \(error.localizedDescription)")
        }
    }

    func start() {
        // Ensure audio session allows AirPlay/HomePod routing on iPad
        #if os(iOS)
        configureAudioSessionForPlayback()
        #endif

        // Ensure instrument is loaded (idempotent)
        loadInstrument()
        // Ensure correct preset applied even if engine was reconfigured earlier
        
        Log("🎵 Opening MIDI inputs...")
        midi.openInput(name: "Bluetooth")
        midi.openInput()
        midi.addListener(self)
        Log("🎵 MIDI listener registered. Available inputs: \(midi.inputNames)")

        if !engineStarted {
            do {
                try engine.start()
                engineStarted = true
                Log("Audio engine started successfully")
            } catch {
                Log("Audio engine failed to start: \(error.localizedDescription)")
            }
        } else {
            // Engine already running - this is fine, we just needed to ensure instrument is loaded
            Log("Audio engine already running")
        }
    }

    func stop() {
        midi.closeAllInputs()

        if engineStarted {
            engine.stop()
            engineStarted = false
            Log("Audio engine stopped")
        }
    }
    
    // MARK: - Stuck Note Prevention
    
    /// Start monitoring for stuck notes that remain "on" too long
    private func startStuckNoteMonitoring() {
        // Check every 2 seconds for stuck notes
        stuckNoteTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForStuckNotes()
        }
    }
    
    /// Stop stuck note monitoring
    private func stopStuckNoteMonitoring() {
        stuckNoteTimer?.invalidate()
        stuckNoteTimer = nil
    }
    
    /// Check for and automatically release notes that have been on too long
    private func checkForStuckNotes() {
        let now = Date()
        var stuckNotes: [Int] = []
        
        for (note, timestamp) in noteOnTimestamps {
            let duration = now.timeIntervalSince(timestamp)
            if duration > stuckNoteTimeout {
                stuckNotes.append(note)
            }
        }
        
        // Release stuck notes
        for note in stuckNotes {
            Log("⚠️ Auto-releasing stuck note: \(note) (held for \(String(format: "%.1f", stuckNoteTimeout))s)")
            forceNoteOff(noteNumber: note)
        }
    }
    
    /// Force a note off, bypassing normal MIDI flow (for stuck note recovery)
    func forceNoteOff(noteNumber: Int) {
        // Stop audio
        instrument.stop(noteNumber: MIDINoteNumber(noteNumber), channel: 0)
        
        // Clear from tracking
        noteOnTimestamps.removeValue(forKey: noteNumber)
        
        // Emit note off subject
        DispatchQueue.main.async {
            self.noteOffSubject.send(noteNumber)
            self.activeNotes.remove(noteNumber)
        }
    }
    
    /// Manually clear all stuck notes (can be called from UI)
    func clearAllNotes() {
        Log("🧹 Clearing all active notes (panic button)")
        let currentNotes = Array(activeNotes)
        for note in currentNotes {
            forceNoteOff(noteNumber: note)
        }
        noteOnTimestamps.removeAll()
    }
    
    @objc private func handleEngineConfigurationChange(_ note: Notification) {
        restartAudioEngineAfterChange(reason: "AVAudioEngineConfigurationChange")
    }

    private func restartAudioEngineAfterChange(reason: String) {
        Log("Audio: restarting engine due to \(reason)")
        do {
            // Stop the engine if it's currently running. AudioKit's AudioEngine doesn't expose `isRunning`,
            // so prefer checking the underlying AVAudioEngine when available, otherwise use our own flag.
            let currentlyRunning: Bool
            #if canImport(AVFAudio)
            currentlyRunning = engine.avEngine.isRunning
            #else
            currentlyRunning = engineStarted
            #endif
            if currentlyRunning {
                engine.stop()
                engineStarted = false
            }
            // Ensure instrument remains loaded and connected
            loadInstrument()
            engine.output = instrument

            // Force-reload the sampler's SoundFont; route changes can drop the loaded preset
            reloadInstrument()

            #if os(macOS)
            // Rebind output AU to current default device if possible
            if let outputAU = engine.avEngine.outputNode.audioUnit {
                var deviceID = getCurrentDefaultOutputDeviceID()
                var size = UInt32(MemoryLayout<AudioDeviceID>.size)
                let status = AudioUnitSetProperty(
                    outputAU,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    size
                )
                if status != noErr {
                    Log("Audio: failed to set current device on output AU: \(status)")
                }
            }
            #endif

            try engine.start()
            engineStarted = true
            Log("Audio: engine restarted successfully")
        } catch {
            Log("Audio: failed to restart engine: \(error)")
        }
    }

    #if os(macOS)
    private func installDefaultOutputDeviceListenerIfNeeded() {
        guard !defaultDeviceListenerInstalled else { return }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.restartAudioEngineAfterChange(reason: "DefaultOutputDeviceChanged")
        }

        if status == noErr {
            defaultDeviceListenerInstalled = true
        } else {
            Log("Audio: failed to install default output device listener: \(status)")
        }
    }

    private func getCurrentDefaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &deviceID
        )
        if status != noErr {
            Log("Audio: failed to query default output device: \(status)")
        }
        return deviceID
    }
    #endif

    func receivedMIDINoteOn(noteNumber: MIDINoteNumber,
                            velocity: MIDIVelocity,
                            channel: MIDIChannel,
                            portID _: MIDIUniqueID?,
                            timeStamp _: MIDITimeStamp?)
    {
        Log("🎹 MIDI Note ON received: note=\(noteNumber), velocity=\(velocity), channel=\(channel)")
        
        // Trigger audio immediately and emit payload (avoid SwiftUI state coalescing)
        let note = Int(noteNumber)
        let vel  = Int(velocity)
        if vel > 0 {
            let boosted = min(127, Int(round(Double(vel) * externalVelocityBoost)))
            instrument.play(noteNumber: MIDINoteNumber(note), velocity: MIDIVelocity(boosted), channel: 0)
            
            // Track when this note was turned on (for stuck note detection)
            noteOnTimestamps[note] = Date()
            
            DispatchQueue.main.async {
                self.noteOnSubject.send((note, boosted))
            }
        } else {
            // Treat Note On with velocity 0 as Note Off
            instrument.stop(noteNumber: MIDINoteNumber(note), channel: 0)
            noteOnTimestamps.removeValue(forKey: note)
            DispatchQueue.main.async {
                self.noteOffSubject.send(note)
            }
        }
        DispatchQueue.main.async {
            self.lastEventWasSimulated = false
            self.midiEventType = .noteOn
            self.noteOnEventID = UUID()
            self.isShowingMIDIReceived = true
            self.data.noteOn = Int(noteNumber)
            self.data.velocity = Int(velocity)
            self.data.channel = Int(channel)
            if velocity > 0 {
                self.activeNotes.insert(Int(noteNumber))
            } else {
                // Treat Note On with velocity 0 as Note Off
                self.activeNotes.remove(Int(noteNumber))
                withAnimation(.easeOut(duration: 0.4)) {
                    self.isShowingMIDIReceived = false
                }
            }
        }
    }

    func receivedMIDINoteOff(noteNumber: MIDINoteNumber,
                             velocity: MIDIVelocity,
                             channel: MIDIChannel,
                             portID _: MIDIUniqueID?,
                             timeStamp _: MIDITimeStamp?)
    {
        // Trigger audio immediately and emit payload
        let note = Int(noteNumber)
        instrument.stop(noteNumber: MIDINoteNumber(note), channel: 0)
        
        // Clear stuck note tracking
        noteOnTimestamps.removeValue(forKey: note)
        
        DispatchQueue.main.async {
            self.noteOffSubject.send(note)
        }
        DispatchQueue.main.async {
            self.lastEventWasSimulated = false
            self.midiEventType = .noteOff
            self.isShowingMIDIReceived = false
            self.data.noteOff = Int(noteNumber)
            self.data.velocity = Int(velocity)
            self.data.channel = Int(channel)
            self.activeNotes.remove(Int(noteNumber))
        }
    }

    func receivedMIDIController(_ controller: MIDIByte,
                                value: MIDIByte,
                                channel: MIDIChannel,
                                portID _: MIDIUniqueID?,
                                timeStamp _: MIDITimeStamp?)
    {
        print("controller \(controller) \(value)")
        DispatchQueue.main.async {
            self.midiEventType = .continuousControl
            self.isShowingMIDIReceived = true
            self.data.controllerNumber = Int(controller)
            self.data.controllerValue = Int(value)
            self.oldControllerValue = Int(value)
            self.data.channel = Int(channel)
            if self.oldControllerValue == Int(value) {
                // Fade out the MIDI received indicator.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.4)) {
                        self.isShowingMIDIReceived = false
                    }
                }
            }
            // Show the solid color indicator when the CC value is toggled from 0 to 127
            // Otherwise toggle it off when the CC value is toggled from 127 to 0
            // Useful for stomp box and on/off UI toggled states
            if value == 127 {
                DispatchQueue.main.async {
                    self.isToggleOn = true
                }
            } else {
                // Fade out the Toggle On indicator.
                DispatchQueue.main.async {
                    self.isToggleOn = false
                }
            }
        }
    }

    func receivedMIDIAftertouch(_ pressure: MIDIByte,
                                channel: MIDIChannel,
                                portID _: MIDIUniqueID?,
                                timeStamp _: MIDITimeStamp?)
    {
        print("received after touch")
        DispatchQueue.main.async {
            self.data.afterTouch = Int(pressure)
            self.data.channel = Int(channel)
        }
    }

    func receivedMIDIAftertouch(noteNumber: MIDINoteNumber,
                                pressure: MIDIByte,
                                channel: MIDIChannel,
                                portID _: MIDIUniqueID?,
                                timeStamp _: MIDITimeStamp?)
    {
        print("recv'd after touch \(noteNumber)")
        DispatchQueue.main.async {
            self.data.afterTouchNoteNumber = Int(noteNumber)
            self.data.afterTouch = Int(pressure)
            self.data.channel = Int(channel)
        }
    }

    func receivedMIDIPitchWheel(_ pitchWheelValue: MIDIWord,
                                channel: MIDIChannel,
                                portID _: MIDIUniqueID?,
                                timeStamp _: MIDITimeStamp?)
    {
        print("midi wheel \(pitchWheelValue)")
        DispatchQueue.main.async {
            self.data.pitchWheelValue = Int(pitchWheelValue)
            self.data.channel = Int(channel)
        }
    }

    func receivedMIDIProgramChange(_ program: MIDIByte,
                                   channel: MIDIChannel,
                                   portID _: MIDIUniqueID?,
                                   timeStamp _: MIDITimeStamp?)
    {
        print("Program change \(program)")
        DispatchQueue.main.async {
            self.midiEventType = .programChange
            self.isShowingMIDIReceived = true
            self.data.programChange = Int(program)
            self.data.channel = Int(channel)
            // Fade out the MIDI received indicator, since program changes don't have a MIDI release/note off.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.isShowingMIDIReceived = false
                }
            }
        }
    }

    func receivedMIDISystemCommand(_: [MIDIByte],
                                   portID _: MIDIUniqueID?,
                                   timeStamp _: MIDITimeStamp?)
    {
//        print("sysex")
    }

    func receivedMIDISetupChange() {
        // Do nothing
    }

    func receivedMIDIPropertyChange(propertyChangeInfo _: MIDIObjectPropertyChangeNotification) {
        // Do nothing
    }

    func receivedMIDINotification(notification _: MIDINotification) {
        // Do nothing
    }

    // MARK: - Simulated events for on-screen keyboard
    func simulateNoteOn(noteNumber: Int, velocity: Int, channel: Int = 0) {
        // Trigger audio immediately and emit payload
        instrument.play(noteNumber: MIDINoteNumber(noteNumber), velocity: MIDIVelocity(velocity), channel: 0)
        
        // Send subject notification immediately (doesn't trigger @Published)
        noteOnSubject.send((noteNumber, velocity))

        // Batch state updates to reduce view churn
        DispatchQueue.main.async {
            // Only update active notes (minimal state change)
            if velocity > 0 {
                self.activeNotes.insert(noteNumber)
            } else {
                self.activeNotes.remove(noteNumber)
            }
            
            // Only update these properties if they're actually being displayed
            // (i.e., not during rapid note dragging)
            self.lastEventWasSimulated = true
            self.noteOnEventID = UUID()
            self.midiEventType = .noteOn
            self.isShowingMIDIReceived = true
            self.data.noteOn = noteNumber
            self.data.velocity = velocity
            self.data.channel = channel
            
            if velocity == 0 {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.isShowingMIDIReceived = false
                }
            }
        }
    }

    func simulateNoteOff(noteNumber: Int, velocity: Int = 0, channel: Int = 0) {
        // Trigger audio immediately and emit payload
        instrument.stop(noteNumber: MIDINoteNumber(noteNumber), channel: 0)
        
        // Send subject notification immediately (doesn't trigger @Published)
        noteOffSubject.send(noteNumber)

        // Batch state updates to reduce view churn
        DispatchQueue.main.async {
            // Only update active notes (minimal state change)
            self.activeNotes.remove(noteNumber)
            
            // Only update these properties if needed for display
            self.lastEventWasSimulated = true
            self.midiEventType = .noteOff
            self.isShowingMIDIReceived = false
            self.data.noteOff = noteNumber
            self.data.velocity = velocity
            self.data.channel = channel
        }
    }
}


private let kNoteNames: [String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

private func noteName(from midiNote: Int) -> String {
    guard (0...127).contains(midiNote) else { return "—" }
    let name = kNoteNames[midiNote % 12]
    let octave = (midiNote / 12) - 1
    return "\(name)\(octave)"
}

enum NavigationDestination: Hashable {
    case calibration
    case history
    case midiSettings
}

struct ContentView: View {
  @EnvironmentObject private var appData: AppData
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  
  let trebleStaff = MusicSymbol.trebleStaff.text()
  let bassStaff = MusicSymbol.bassStaff.text()
  
  let sharpText = MusicSymbol.sharpSymbol.text()
  let flatText = MusicSymbol.flatSymbol.text()
  let naturalText = MusicSymbol.naturalSymbol.text()
  
  let braceText = MusicSymbol.brace.text()
  let barlineText = MusicSymbol.barline.text()
  
  let sharedX: CGFloat = 166
  let noteX: CGFloat = 166
  
  @StateObject private var vm = StaffViewModel()
  @EnvironmentObject private var conductor: MIDIMonitorConductor
  @EnvironmentObject private var bluetoothManager: BluetoothMIDIManager
  
  // Removed: @State private var advanceWorkItem: DispatchWorkItem?
  // Removed: private let autoAdvanceDebounce: TimeInterval = 0.25
  
  @State private var feedbackMessage: String = "Waiting for note…"
  @State private var feedbackColor: Color = .secondary
  @State private var isCorrect: Bool? = nil
  
  @State private var navigationPath = NavigationPath()
  @State private var showDebugOverlays = false
  
  // Practice mode state
  @State private var practiceCount: Int = 5
  @State private var showingPractice: Bool = false
  @State private var isPracticeMode: Bool = false
  @State private var practiceAttempts: [PracticeAttempt] = []
  @State private var practiceTargets: [(midi: Int, clef: Clef, accidental: String)] = []
  @State private var currentPracticeIndex: Int = 0
  @State private var showingResults: Bool = false
  @State private var practiceStartDate: Date = Date()
  @State private var practiceSettings: PracticeSettings = PracticeSettings(
    count: 5,
    includeAccidentals: false,
    allowedRange: nil,
    clefMode: .random
  )
  
  // Track orientation with @State to prevent rapid re-renders during rotation
  @State private var stableIsPortrait: Bool = {
    #if os(iOS)
    let screenBounds = UIScreen.main.bounds
    return screenBounds.height > screenBounds.width
    #else
    return false
    #endif
  }()
  
  // Computed property to determine current orientation (for detecting changes)
  private var currentOrientation: Bool {
    #if os(iOS)
    let screenBounds = UIScreen.main.bounds
    return screenBounds.height > screenBounds.width
    #else
    return false
    #endif
  }
  
  // Use the stable version throughout the view
  private var isPortrait: Bool {
    stableIsPortrait
  }
  
  // Removed isWaitingForNote and receivedBlankDelay
  
  // Staff drawing control (positions match your previous staff anchors)
  private let trebleStaffPoint = CGPoint(x: 155, y: 150)
  private let bassStaffPoint   = CGPoint(x: 155, y: 230)
  private let lineWidth: CGFloat = 24 // approximate width of a ledger line glyph
  
  private var currentNoteSymbol: MusicSymbol {
    // Determine stem direction relative to the middle staff line
    let step = vm.step(for: vm.currentNote.midi, clef: vm.currentClef)
    let stemUp = step > 0 // above middle line => stem up; below => stem down; middle (0) can default to down
    
    switch appData.noteHeadStyle {
      case .whole:
        return .wholeNote
      case .half:
        return stemUp ? .halfNoteUP : .halfNoteDown
      case .quarter:
        return stemUp ? .quarterNoteUP : .quarterNoteDown
    }
  }
  
  private func isInCalibratedRange(_ midi: Int) -> Bool {
    guard let range = appData.calibratedRange else { return true }
    return range.contains(midi)
  }
  
  private func randomizeNoteRespectingCalibration(maxAttempts: Int = 12) {
    // Ensure StaffViewModel knows the allowed range
    vm.setAllowedMIDIRange(appData.calibratedRange)
    var attempts = 0
    repeat {
      vm.randomizeNote()
      attempts += 1
      if isInCalibratedRange(vm.currentNote.midi) { break }
    } while attempts < maxAttempts
  }
  
  // MARK: - Practice Mode Functions
  private func startPractice() {
    isPracticeMode = true
    practiceStartDate = Date() // Capture the start time
    
    // Create practice settings
    practiceSettings = PracticeSettings(
      count: practiceCount,
      includeAccidentals: appData.includeAccidentals,
      allowedRange: appData.calibratedRange,
      clefMode: .random // For now, using random as default
    )
    
    practiceAttempts.removeAll()
    generatePracticeTargets()
    currentPracticeIndex = 0
    setCurrentPracticeTarget()
    
    feedbackMessage = "Practice Mode: Play note 1 of \(practiceCount)"
    feedbackColor = .blue
  }
  
  private func generatePracticeTargets() {
    practiceTargets.removeAll()
    
    for _ in 0..<practiceCount {
      // Use the main VM to generate practice targets the same way as free play
      let tempVM = StaffViewModel()
      tempVM.setAllowedMIDIRange(appData.calibratedRange)
      tempVM.setIncludeAccidentals(appData.includeAccidentals)
      tempVM.randomizeNote() // This handles both clef and note selection properly
      
      practiceTargets.append((
        midi: tempVM.currentNote.midi,
        clef: tempVM.currentClef, // Use the clef that the VM selected, not a random one
        accidental: tempVM.currentNote.accidental
      ))
    }
  }
  
  private func setCurrentPracticeTarget() {
    guard currentPracticeIndex < practiceTargets.count else {
      // Practice complete!
      isPracticeMode = false
      showingResults = true
      feedbackMessage = "🎉 Practice Complete!"
      feedbackColor = .green
      return
    }
    
    let target = practiceTargets[currentPracticeIndex]
    
    // Update the main VM with the practice target
    vm.currentClef = target.clef
    vm.currentNote = StaffNote(
      name: noteName(from: target.midi),
      midi: target.midi,
      accidental: target.accidental
    )
    
    feedbackMessage = "Practice: Play note \(currentPracticeIndex + 1) of \(practiceCount)"
    feedbackColor = .blue
  }
  
  private func handlePracticeInput(_ playedMidi: Int) {
    guard isPracticeMode && currentPracticeIndex < practiceTargets.count else { return }
    
    let target = practiceTargets[currentPracticeIndex]
    let correct = (playedMidi == target.midi)
    
    // Record the attempt
    practiceAttempts.append(
      PracticeAttempt(
        targetMidi: target.midi,
        targetClef: target.clef,
        targetAccidental: target.accidental,
        playedMidi: playedMidi,
        timestamp: Date(),
        outcome: correct ? .correct : .incorrect
      )
    )
    
    if correct {
      feedbackMessage = "Correct! \(noteName(from: playedMidi))"
      feedbackColor = .green
      
      // Move to next note after a short delay
      currentPracticeIndex += 1
      
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        setCurrentPracticeTarget()
      }
    } else {
      feedbackMessage = "Try again. You played \(noteName(from: playedMidi)), target is \(noteName(from: target.midi))"
      feedbackColor = .red
    }
  }
  
  private func exitPracticeMode() {
    isPracticeMode = false
    practiceAttempts.removeAll()
    practiceTargets.removeAll()
    currentPracticeIndex = 0
    
    // Return to free play mode
    randomizeNoteRespectingCalibration()
    feedbackMessage = "Waiting for note…"
    feedbackColor = .secondary
  }
  
  private var calibrationDisplayText: String {
    if let range = appData.calibratedRange {
      let lo = range.lowerBound
      let hi = range.upperBound
      let size = range.count
      if lo == 0 && hi == 127 {
        return "Uncalibrated"
      } else {
        return "\(noteName(from: lo))–\(noteName(from: hi)) (\(size) keys)"
      }
    } else {
      return "Uncalibrated"
    }
  }
  
  var body: some View {
    GeometryReader { outerGeometry in
      NavigationStack(path: $navigationPath) {
        ZStack(alignment: stableIsPortrait ? .top : .center) { // Align to top in portrait
        // Subtle, adaptive background (unified gradient for both light and dark modes)
        Group {
          LinearGradient(
            colors: [
              Color(red: 0.36, green: 0.10, blue: 0.11), // unified top (opaque dark red)
              Color(red: 0.28, green: 0.07, blue: 0.08)  // unified bottom (opaque dark red)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        }
        .ignoresSafeArea()
        // Subtle bottom lift to brighten behind the keyboard with a feathered blend (applies to both modes)
        .overlay(
          LinearGradient(
            colors: [
              Color.red.opacity(0.00),
              Color.red.opacity(0.02),
              Color.red.opacity(0.05),
              Color.red.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
          .ignoresSafeArea()
          .mask(
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.35),
                .init(color: .black.opacity(0.6), location: 0.55),
                .init(color: .black, location: 1.0)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .mask(
              VStack { Spacer(); Rectangle().frame(height: 260) }
            )
          )
        )
        
        // Existing content
        VStack(spacing: 0) {
          midiReceivedIndicator
          
          Spacer()
            .frame(height: isPortrait ? 8 : 20) // Minimal spacing in portrait
          
          // In portrait, add large flexible spacer at top to push all content down
          if isPortrait {
            Spacer()
              .frame(minHeight: 80, idealHeight: 200) // LARGE spacer at top - pushes everything down
          }
          
          // Removed inline KeyBoardView here per instructions
          
          // Staff and note drawing with speakers
          HStack(alignment: .top, spacing: 0) {
            Spacer()
              .frame(maxWidth: isPortrait ? 40 : 120) // Even more reduced side margins in portrait
            
            // Left speaker - centered with staff
            SpeakerView(
              isPlaying: conductor.isShowingMIDIReceived && conductor.data.velocity > 0,
              velocity: conductor.data.velocity
            )
            #if os(macOS)
            .frame(width: 115, height: 155)
            #else
            .frame(width: isPortrait ? 150 : 135, height: isPortrait ? 200 : 180) // BIGGER speakers in portrait
            #endif
            .padding(.top, isPortrait ? 12 : 40) // Very reduced top padding in portrait
            
            if isPortrait {
              Spacer()
                .frame(maxWidth: 16) // Very compact spacer in portrait
            } else {
              Spacer()
            }
            
            // Staff in the middle
            VStack(spacing: isPortrait ? 12 : 16) { // Spacing between staff and labels
              Canvas { context, size in
              // Center the entire staff/note drawing within the canvas
              let centerX = size.width / 2
              let centerY = size.height / 2
              let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2 // 190 based on current anchors
              
              // Platform-specific scaling to accommodate full 88-key range with note tails
              // Larger staff sizes that adapt to available screen space
              #if os(macOS)
              // Mac: adaptive scaling based on available width
              let baseScale: CGFloat = 1.05 // Larger base scale (was 0.78)
              let widthFactor = min(size.width / 800, 1.3) // Scale up to 30% larger on wide screens
              let scale = baseScale * widthFactor
              let verticalShift: CGFloat = 20 // Shift staff down for more top clearance
              context.translateBy(x: centerX, y: centerY + verticalShift)
              context.scaleBy(x: scale, y: scale)
              context.translateBy(x: -noteX, y: -originalGroupMidY)
              #else
              // iPad: larger staff with adaptive scaling based on screen size and orientation
              let baseScale: CGFloat = isPortrait ? 1.65 : 1.04 // Portrait: MUCH MUCH BIGGER, Landscape: smaller to fit full range (was 1.08)
              let widthFactor = min(size.width / 700, 1.4) // Scale up to 40% larger on wide iPads
              let scale = baseScale * widthFactor
              let verticalShift: CGFloat = isPortrait ? 8 : 8 // Portrait: 8, Landscape: 8 (centered)
              context.translateBy(x: centerX, y: centerY + verticalShift)
              context.scaleBy(x: scale, y: scale)
              context.translateBy(x: -noteX, y: -originalGroupMidY)
              #endif
              
              // Add subtle shadow to improve contrast on dark background
              if colorScheme == .dark {
                context.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1))
              } else {
                context.addFilter(.shadow(color: .black.opacity(0.10), radius: 0.8, x: 0, y: 0.5))
              }
              
              // Draw both staffs
              context.draw(trebleStaff, at: trebleStaffPoint)
              context.draw(bassStaff, at: bassStaffPoint)
              
              // Draw brace and barline to connect the two staffs
              // Calculate exact Y positions: top of treble staff to bottom of bass staff
              let trebleYs = vm.staffLineYs(for: .treble)
              let bassYs = vm.staffLineYs(for: .bass)
              let topY = trebleYs.first ?? trebleStaffPoint.y // Top line of treble staff
              let bottomY = bassYs.last ?? bassStaffPoint.y   // Bottom line of bass staff
              
              // Shift the center point down to align top with treble and bottom with bass
              let braceMidY = (topY + bottomY) / 2 + 66 // Shift down by 66 points (nudged up 1 point from 67)
              
              let staffLeftEdge = noteX - 120
              
              // Save the context state before transforming
              var braceContext = context
              var barlineContext = context
              
              // Position the barline further left so it doesn't overlap the staff lines
              let barlineX = staffLeftEdge - 3 // Move barline 3 points to the left of staff edge
              
              // Draw the vertical barline with vertical scaling only
              braceContext.translateBy(x: barlineX, y: braceMidY)
              braceContext.scaleBy(x: 1.0, y: 1.31) // Stretch vertically by 1.31x (fine-tuned)
              braceContext.translateBy(x: -barlineX, y: -braceMidY)
              let barlinePoint = CGPoint(x: barlineX, y: braceMidY)
              braceContext.draw(barlineText, at: barlinePoint, anchor: .center)
              
              // Draw the brace with vertical scaling only
              let braceX = barlineX - 7 // Position brace to the left of the barline
              barlineContext.translateBy(x: braceX, y: braceMidY)
              barlineContext.scaleBy(x: 1.0, y: 1.31) // Stretch vertically by 1.31x (fine-tuned)
              barlineContext.translateBy(x: -braceX, y: -braceMidY)
              let bracePoint = CGPoint(x: braceX, y: braceMidY)
              barlineContext.draw(braceText, at: bracePoint, anchor: .center)
              
              // Draw the right barline at the edge of the staff (no gap)
              let staffRightEdge = noteX + 120 // Right edge of staff glyph
              
              // Draw right barline (scaled to match left barline, slightly wider to cover bass staff overhang)
              // The staff lines themselves end well before the glyph edge, so move significantly left
              var rightBarlineContext = context
                let rightBarlineX = staffRightEdge - 18 // Position to align with staff line endings
              rightBarlineContext.translateBy(x: rightBarlineX, y: braceMidY)
              rightBarlineContext.scaleBy(x: 1.18, y: 1.315) // Scale horizontally by 1.15x to cover bass staff overhang, vertically by 1.31x
              rightBarlineContext.translateBy(x: -rightBarlineX, y: -braceMidY)
              rightBarlineContext.draw(barlineText, at: CGPoint(x: rightBarlineX, y: braceMidY), anchor: .center)
              
              // Draw thin barline at right edge - 24
              var thinBarlineContext = context
              let thinBarlineX = staffRightEdge - 24
              thinBarlineContext.translateBy(x: thinBarlineX, y: braceMidY)
              thinBarlineContext.scaleBy(x: 0.4, y: 1.305) // Scale horizontally to 0.4x (about 1/3 thickness), vertically by 1.305x (reduced from 1.315)
              thinBarlineContext.translateBy(x: -thinBarlineX, y: -braceMidY)
              thinBarlineContext.draw(barlineText, at: CGPoint(x: thinBarlineX, y: braceMidY), anchor: .center)
              
              if showDebugOverlays {
                // Draw staff line guides (green) for both staffs
                let stroke: CGFloat = 0.5
                let trebleYs = vm.staffLineYs(for: .treble)
                for y in trebleYs {
                  let rect = CGRect(x: noteX - 120, y: y - stroke/2, width: 240, height: stroke)
                  context.fill(Path(rect), with: .color(.green.opacity(0.8)))
                }
                let bassYs = vm.staffLineYs(for: .bass)
                for y in bassYs {
                  let rect = CGRect(x: noteX - 120, y: y - stroke/2, width: 240, height: stroke)
                  context.fill(Path(rect), with: .color(.green.opacity(0.8)))
                }
                
                // Draw computed ledger line positions (red), centered on Y
                let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
                for y in ledgerYs {
                  let stroke: CGFloat = 1.1
                  let rect = CGRect(x: noteX - 40, y: y - stroke/2, width: 80, height: stroke)
                  context.fill(Path(rect), with: .color(.red.opacity(0.7)))
                }
                
                // Draw the computed note center (blue crosshair)
                let ny = vm.currentY
                let crossW: CGFloat = 10
                let crossH: CGFloat = 10
                let hPath = Path(CGRect(x: noteX - crossW/2, y: ny, width: crossW, height: 0.75))
                let vPath = Path(CGRect(x: noteX, y: ny - crossH/2, width: 0.75, height: crossH))
                context.stroke(hPath, with: .color(.blue.opacity(0.7)), lineWidth: 0.75)
                context.stroke(vPath, with: .color(.blue.opacity(0.7)), lineWidth: 0.75)
              }
              
              // Draw ledger lines (if any) as vector strokes for pixel-perfect alignment
              let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
              let isDark = colorScheme == .dark
              let ledgerStroke: CGFloat = isDark ? 1.6 : 1.4
              let ledgerColor: Color = .white.opacity(0.85)
              let ledgerLength: CGFloat = lineWidth * 0.85
              for y in ledgerYs {
                var p = Path()
                p.move(to: CGPoint(x: noteX - ledgerLength/2, y: y))
                p.addLine(to: CGPoint(x: noteX + ledgerLength/2, y: y))
                context.stroke(p, with: .color(ledgerColor), lineWidth: ledgerStroke)
              }
              
              // Draw accidental if needed just to the left of the note
              let acc = vm.currentNote.accidental
              let notePoint = CGPoint(x: noteX, y: vm.currentY)
              let noteText = currentNoteSymbol.text()
              if acc == "♯" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                context.draw(sharpText, at: accPoint, anchor: .center)
              } else if acc == "♭" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                context.draw(flatText, at: accPoint, anchor: .center)
              } else if acc == "♮" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                context.draw(naturalText, at: accPoint, anchor: .center)
              }
              context.draw(noteText, at: notePoint, anchor: .center)
            }
            #if os(macOS)
            .frame(height: 400) // Mac: increased to accommodate larger staff (was 320)
            #else
            .frame(height: isPortrait ? 520 : 420) // Portrait: MASSIVE staff (was 450), Landscape: same
            #endif
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1), value: vm.currentY)
            .foregroundStyle(.white)
            
            // Labels for clef, note name and MIDI code
            HStack(spacing: Platform.labelSpacing) {
              Spacer()
              
              // Show hints only if enabled
              if appData.showHints {
                Text("Clef:")
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .fontWeight(.semibold)
                  .fixedSize()
                Text(vm.currentClef == .treble ? "Treble" : "Bass")
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .frame(minWidth: Platform.clefWidth, alignment: .leading)
                Text("Note:")
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .fontWeight(.semibold)
                  .fixedSize()
                Text(vm.currentNote.name)
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .monospaced()
                  .frame(minWidth: Platform.noteWidth, alignment: .leading)
                Text("MIDI:")
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .fontWeight(.semibold)
                  .fixedSize()
                Text(String(vm.currentNote.midi))
                  .font(Platform.labelFont(isPortrait: isPortrait))
                  .monospaced()
                  .frame(minWidth: Platform.midiWidth, alignment: .leading)
              }
              
              // New Note button centered with the text
              if !isPracticeMode {
                Button("New Note") {
                  withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)) {
                    randomizeNoteRespectingCalibration()
                  }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .controlSize(isPortrait ? .small : .regular) // Smaller in portrait
                .fixedSize() // Prevent button from stretching
              }
              
              Spacer()
            }
            
            // Received values from MIDI to compare with the random note above
            HStack(spacing: Platform.labelSpacing) {
              Spacer()
              
              Text("Received Clef:")
                .font(Platform.labelFont(isPortrait: isPortrait))
                .fixedSize()
              Text(conductor.data.noteOn == 0 ? "—" : (conductor.data.noteOn < 60 ? "Bass" : (conductor.data.noteOn > 60 ? "Treble" : "Both")))
                .font(Platform.labelFont(isPortrait: isPortrait))
                .frame(minWidth: Platform.clefWidth, alignment: .leading)
              
              Text("Received Note:")
                .font(Platform.labelFont(isPortrait: isPortrait))
                .fixedSize()
              Text(conductor.data.noteOn == 0 ? "—" : noteName(from: conductor.data.noteOn))
                .font(Platform.labelFont(isPortrait: isPortrait))
                .monospaced()
                .frame(minWidth: Platform.noteWidth, alignment: .leading)
              
              Text("Received MIDI:")
                .font(Platform.labelFont(isPortrait: isPortrait))
                .fixedSize()
              Text(String(conductor.data.noteOn))
                .font(Platform.labelFont(isPortrait: isPortrait))
                .monospaced()
                .frame(minWidth: Platform.midiWidth, alignment: .leading)
              
              Spacer()
            }
          } // End staff VStack
          
          if isPortrait {
            Spacer()
              .frame(maxWidth: 16) // Very compact spacer in portrait
          } else {
            Spacer()
          }
          
          // Right speaker - centered with staff
          SpeakerView(
            isPlaying: conductor.isShowingMIDIReceived && conductor.data.velocity > 0,
            velocity: conductor.data.velocity
          )
          #if os(macOS)
          .frame(width: 115, height: 155)
          #else
          .frame(width: isPortrait ? 150 : 135, height: isPortrait ? 200 : 180) // BIGGER speakers in portrait
          #endif
          .padding(.top, isPortrait ? 12 : 40) // Very reduced top padding in portrait
          
          Spacer()
            .frame(maxWidth: isPortrait ? 40 : 120) // Even more reduced side margins in portrait
        } // End HStack with speakers
        .padding(.horizontal, isPortrait ? 8 : 20) // Minimal horizontal padding in portrait
        .foregroundStyle(.white)
        
        // In portrait, add spacing between text/buttons and practice controls (~1 inch)
        if isPortrait {
          Spacer()
            .frame(height: 48) // Reduced gap (was 72) - bring controls closer to labels
        }
          
          // Practice mode controls or free play button
          if isPracticeMode {
            HStack(spacing: 12) {
              Text("Practice Mode")
                .fontWeight(.semibold)
                .font(isPortrait ? .caption : .body)
              
              Text("Note \(currentPracticeIndex + 1) of \(practiceCount)")
                .monospaced()
                .font(isPortrait ? .caption : .body)
              
              Button("Exit Practice") {
                exitPracticeMode()
              }
              .buttonStyle(.borderedProminent)
              .tint(.white)
              .foregroundStyle(.red)
              .controlSize(isPortrait ? .small : .regular)
            }
            .foregroundStyle(.white)
            .frame(height: isPortrait ? 40 : 56) // Smaller in portrait
          } else {
            // Practice mode controls only (New Note button is now in clef HStack above)
            HStack(spacing: 12) {
              Text("Practice")
                .foregroundColor(.white)
                .font(isPortrait ? .caption : .body)
              
              CustomNumberPicker("Count:", value: $practiceCount, in: 5...100, step: 5)
              
              Button("Start Practice") {
                startPractice()
              }
              .buttonStyle(.borderedProminent)
              .tint(.white)
              .foregroundStyle(.black)
              .controlSize(isPortrait ? .small : .regular)
            }
            .foregroundStyle(.white)
            .tint(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
            .frame(height: isPortrait ? 40 : 56) // Smaller in portrait
          }
          
          // In portrait, add flexible spacer to keep keyboard at bottom
          if isPortrait {
            Spacer(minLength: 20) // Small flexible spacer - just fills remaining space
          } else {
            Spacer()
              .frame(minHeight: 8, maxHeight: 20)
          }
          
          // Add fixed spacing in portrait to keep practice controls above keyboard
          if isPortrait {
            Spacer()
              .frame(height: 100) // Fixed ~1.5" gap between practice controls and keyboard
          }
          
          // Keyboard removed from here - now always in safeAreaInset below
        } // VStack
        .safeAreaInset(edge: .bottom) {
          // Always use safeAreaInset for keyboard (both portrait and landscape)
          // This prevents structural changes during rotation
          KeyBoardView(isCorrect: { midi in
            midi == vm.currentNote.midi
          }, docked: true)
          .environmentObject(appData)
          .environmentObject(conductor)
          .frame(height: isPortrait ? 320 : nil) // Fixed height in portrait only
        }
        .padding(.horizontal, 8)
        .onAppear {
          vm.setAllowedMIDIRange(appData.calibratedRange)
          vm.setIncludeAccidentals(appData.includeAccidentals)
          randomizeNoteRespectingCalibration()
        }
        .onChange(of: appData.minMIDINote) { _, _ in
          vm.setAllowedMIDIRange(appData.calibratedRange)
          randomizeNoteRespectingCalibration()
        }
        .onChange(of: appData.maxMIDINote) { _, _ in
          vm.setAllowedMIDIRange(appData.calibratedRange)
          randomizeNoteRespectingCalibration()
        }
        .onChange(of: appData.includeAccidentals) { _, newValue in
          vm.setIncludeAccidentals(newValue)
          randomizeNoteRespectingCalibration()
        }
        .onChange(of: conductor.noteOnEventID) { _, _ in
          // Read the latest note value for this event (fires even for repeated same MIDI note)
          let newValue = conductor.data.noteOn
          // Only respond to real Note On events (some devices send Note On with velocity 0 as Note Off)
          guard conductor.midiEventType == .noteOn, conductor.data.velocity > 0 else { return }
          
          if isPracticeMode {
            // Handle practice mode input
            handlePracticeInput(newValue)
          } else {
            // Handle free play mode input
            let playedName = noteName(from: newValue)
            let correct = (newValue == vm.currentNote.midi)
            isCorrect = correct
            
            // Build feedback message and color
            if correct {
              feedbackMessage = "You played \(playedName). That is correct! Try the next note now."
              feedbackColor = .green
            } else {
              feedbackMessage = "You played \(playedName). That is incorrect, try again."
              feedbackColor = .red
            }
            
            // Auto-advance immediately if the played note matches the current target note
            guard correct else { return }
            
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)) {
              // Advance to the next target; keep last feedback visible
              randomizeNoteRespectingCalibration()
            }
          }
        }
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
            case .calibration:
              CalibrationWizardView(navigationPath: $navigationPath)
                .environmentObject(appData)
                .environmentObject(conductor)
            case .history:
              PracticeHistoryView(navigationPath: $navigationPath)
            case .midiSettings:
              MIDIDeviceSettingsView(bluetoothManager: bluetoothManager, conductor: conductor)
          }
        }
        .sheet(isPresented: $showingResults) {
          PracticeResultsView(
            attempts: practiceAttempts,
            settings: practiceSettings,
            sessionStartDate: practiceStartDate
          )
        }
      } // ZStack
    } // NavigationStack
    .onChange(of: outerGeometry.size) { oldSize, newSize in
      // Detect orientation change (width/height relationship flips)
      let newIsPortrait = newSize.height > newSize.width
      
      // Only update if orientation actually changed
      if newIsPortrait != stableIsPortrait {
        // Debounce to wait for rotation animation to complete
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 300_000_000) // 300ms - wait for rotation to finish
          
          // Verify size is still stable (rotation completed)
          if outerGeometry.size == newSize {
            stableIsPortrait = newIsPortrait
          }
        }
      }
    }
  } // GeometryReader
} // body
  
  var midiReceivedIndicator: some View {
    VStack(spacing: 8) {
      // Top row: MIDI In, Note Type, and Toggles
      HStack(alignment: .center, spacing: Platform.menuBarSpacing) {
        // Left-aligned MIDI In indicator
        HStack(spacing: Platform.innerSpacing) {
          Text("MIDI In")
            .font(Platform.menuFont)
            .fontWeight(.semibold)
            .fixedSize()
          Circle()
            .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
            .background(Circle().fill(conductor.isShowingMIDIReceived ? .blue : .blue.opacity(0.2)))
            .frame(width: 16, height: 16)
        }
        
        if Platform.isMac {
          Spacer()
        }
        
        // Note style picker (custom segmented control)
        HStack(spacing: Platform.innerSpacing) {
          if Platform.isMac {
            Text("Note Type:")
              .font(.callout)
              .fontWeight(.semibold)
              .fixedSize()
          }
          HStack(spacing: 0) {
            ForEach([NoteHeadStyle.whole, .half, .quarter], id: \.self) { style in
              let isSelected = appData.noteHeadStyle == style
              Button(action: { appData.noteHeadStyle = style }) {
                Text({
                  switch style {
                    case .whole: return "Whole"
                    case .half: return "Half"
                    case .quarter: return "Quarter"
                  }
                }())
                .font(Platform.buttonFont)
                .frame(width: Platform.buttonWidth, height: Platform.buttonHeight)
                .fontWeight(.medium)
                .contentShape(Rectangle())
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .background(
                  Group {
                    if isSelected {
                      RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white)
                    } else {
                      Color.clear
                    }
                  }
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(3)
          .background(Color.white.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          
          Toggle("Sharps/Flats", isOn: $appData.includeAccidentals)
            .toggleStyle(CustomToggleStyle())
            .fixedSize()
          
          Toggle("Show Hints", isOn: $appData.showHints)
            .toggleStyle(CustomToggleStyle())
            .fixedSize()
        }
        
        if Platform.isMac {
          Spacer()
        }
        
        // Right-aligned controls
        HStack(spacing: 8) {
          // Show Bluetooth indicator if connected
          if bluetoothManager.hasBluetoothDevice {
            Image(systemName: "antenna.radiowaves.left.and.right")
              .foregroundStyle(.blue)
              .font(.caption)
              .help("Bluetooth MIDI device connected")
          }
          
          #if os(iOS)
          // AirPlay route picker for selecting HomePod and other AirPlay targets on iPad
          AirPlayRoutePicker()
            .frame(width: 32, height: 32)
            .help("Select AirPlay output")
          #endif
          
          Text(calibrationDisplayText)
            .font(Platform.calibrationFont)
            .foregroundColor(.white)
            .fixedSize()
            .lineLimit(1)
            .frame(minWidth: Platform.calibrationWidth)
          
          Button("MIDI") {
            navigationPath.append(NavigationDestination.midiSettings)
          }
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(.black)
          .controlSize(Platform.buttonControlSize)
          .help("Configure MIDI devices")
          
          Button("History") {
            navigationPath.append(NavigationDestination.history)
          }
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(.black)
          .controlSize(Platform.buttonControlSize)
          
          Button("Calibrate") {
            navigationPath.append(NavigationDestination.calibration)
          }
          .buttonStyle(.borderedProminent)
          .tint(.white)
          .foregroundStyle(.black)
          .controlSize(Platform.buttonControlSize)
        }
      }
    }
    .padding(.top, Platform.isMac ? 16 : (isPortrait ? 4 : 8)) // Reduced top padding in portrait
    .padding(.horizontal, Platform.horizontalPadding)
    .frame(maxWidth: .infinity)
    .shadow(color: colorScheme == .dark ? .clear : .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
    .foregroundStyle(.white)
    .tint(.white.opacity(0.9))
  }
  
  // Helper struct for platform-specific values
  private struct Platform {
    #if os(macOS)
    static let isMac = true
    static let menuBarSpacing: CGFloat = 12
    static let innerSpacing: CGFloat = 6
    static let menuFont: Font = .callout
    static let buttonFont: Font = .callout
    static let buttonWidth: CGFloat = 190/3
    static let buttonHeight: CGFloat = 28
    static let toggleSize: ControlSize = .small
    static let calibrationFont: Font = .caption
    static let calibrationWidth: CGFloat = 80
    static let buttonControlSize: ControlSize = .small
    static let horizontalPadding: CGFloat = 16
    // Label sizing for staff area
    static func labelFont(isPortrait: Bool) -> Font { .body }
    static let labelSpacing: CGFloat = 12
    static let clefWidth: CGFloat = 50
    static let noteWidth: CGFloat = 40
    static let midiWidth: CGFloat = 30
    #else
    static let isMac = false
    static let menuBarSpacing: CGFloat = 10
    static let innerSpacing: CGFloat = 8
    static let menuFont: Font = .caption
    static let buttonFont: Font = .caption2
    static let buttonWidth: CGFloat = 140/3
    static let buttonHeight: CGFloat = 24
    static let toggleSize: ControlSize = .mini
    static let calibrationFont: Font = .caption2
    static let calibrationWidth: CGFloat = 60
    static let buttonControlSize: ControlSize = .mini
    static let horizontalPadding: CGFloat = 8
    // Label sizing for staff area - BIGGER in portrait mode
    static func labelFont(isPortrait: Bool) -> Font { isPortrait ? .body : .caption }
    static let labelSpacing: CGFloat = 6
    static let clefWidth: CGFloat = 42
    static let noteWidth: CGFloat = 32
    static let midiWidth: CGFloat = 24
    #endif
  }
} // ContentView
  
  #Preview("Whole") {
    let data = AppData()
    data.noteHeadStyle = .whole
    let conductor = MIDIMonitorConductor()
    return ContentView()
      .environmentObject(data)
      .environmentObject(conductor)
      .environmentObject(conductor.bluetoothManager)
      .frame(width: 900, height: 900)
  }
  
  #Preview("Half") {
    let data = AppData()
    data.noteHeadStyle = .half
    let conductor = MIDIMonitorConductor()
    return ContentView()
      .environmentObject(data)
      .environmentObject(conductor)
      .environmentObject(conductor.bluetoothManager)
      .frame(width: 900, height: 900)
  }
  
  #Preview("Quarter") {
    let data = AppData()
    data.noteHeadStyle = .quarter
    let conductor = MIDIMonitorConductor()
    return ContentView()
      .environmentObject(data)
      .environmentObject(conductor)
      .environmentObject(conductor.bluetoothManager)
      .frame(width: 900, height: 900)
  }

#if os(iOS)
import AVKit
struct AirPlayRoutePicker: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.prioritizesVideoDevices = false
    return view
  }
  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - Custom Wheel Picker (Works on both platforms)
struct CustomNumberPicker: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  let step: Int
  let label: String
  
  @State private var showingPicker = false
  
  init(
    _ label: String,
    value: Binding<Int>,
    in range: ClosedRange<Int>,
    step: Int = 1
  ) {
    self.label = label
    self._value = value
    self.range = range
    self.step = step
  }
  
  var body: some View {
    HStack(spacing: 8) {
      Text(label)
        .foregroundColor(.white)
      
      Button(action: {
        showingPicker.toggle()
      }) {
        HStack(spacing: 4) {
          Text("\(value)")
            .font(.system(.body, design: .monospaced))
            .fontWeight(.medium)
            .foregroundColor(.white)
          
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.6))
        }
        .frame(width: 80, height: platformHeight)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
      }
      .buttonStyle(.plain)
      #if os(macOS)
      .popover(
        isPresented: $showingPicker,
        arrowEdge: .top
      ) {
        pickerContent
      }
      #else
      .popover(
        isPresented: $showingPicker,
        attachmentAnchor: .point(.top),
        arrowEdge: .bottom
      ) {
        pickerContent
          .presentationCompactAdaptation(.popover)
      }
      #endif
      .fixedSize()
    }
  }
  
  private var pickerContent: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { number in
              Button(action: {
                value = number
                showingPicker = false
              }) {
                Text("\(number)")
                  .font(.system(.body, design: .monospaced))
                  .fontWeight(number == value ? .semibold : .regular)
                  .foregroundColor(number == value ? .white : .primary)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                  .padding(.horizontal, 20)
                  .background(number == value ? Color.accentColor : Color.clear)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .id(number)
              
              if number != range.upperBound {
                Divider()
              }
            }
          }
        }
        .frame(width: 100, height: 250)
        .onAppear {
          proxy.scrollTo(value, anchor: .center)
        }
      }
    }
    #if os(macOS)
    .background(Color(nsColor: .controlBackgroundColor))
    #else
    .background(Color(uiColor: .systemBackground))
    #endif
  }
  
  private var platformHeight: CGFloat {
    #if os(macOS)
    return 28
    #else
    return 32 // Slightly taller for easier touch on iPad
    #endif
  }
}

// MARK: - Custom Toggle Style
struct CustomToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      // Custom checkbox with better visibility
      ZStack {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(configuration.isOn ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
          )
          .frame(width: checkboxSize, height: checkboxSize)
        
        if configuration.isOn {
          Image(systemName: "checkmark")
            .font(.system(size: checkmarkSize, weight: .bold))
            .foregroundColor(.white)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        configuration.isOn.toggle()
      }
      
      configuration.label
        .foregroundColor(.white)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      configuration.isOn.toggle()
    }
  }
  
  // Platform-specific sizing
  private var checkboxSize: CGFloat {
    #if os(macOS)
    return 16
    #else
    return 18 // Slightly larger on iPad for easier touch targets
    #endif
  }
  
  private var checkmarkSize: CGFloat {
    #if os(macOS)
    return 11
    #else
    return 12 // Slightly larger on iPad
    #endif
  }
}

// MARK: - View Extension
private extension View {
  @ViewBuilder
  func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}

