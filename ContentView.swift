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

    init() {
        // Configure audio chain
        engine.output = instrument
        // Try loading the instrument (SoundFont)
        do {
            if let url = Bundle.main.url(forResource: "Sounds/YDP-GrandPiano", withExtension: "sf2") {
                try instrument.loadInstrument(url: url)
                Log("Loaded instrument Successfully!")
            } else {
                Log("Could not find file")
            }
        } catch {
            Log("Could not load instrument")
        }
    }

    func start() {
        midi.openInput(name: "Bluetooth")
        midi.openInput()
        midi.addListener(self)

        if !engineStarted {
            do {
                try engine.start()
                engineStarted = true
            } catch {
                Log("Audio engine failed to start: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        midi.closeAllInputs()

        if engineStarted {
            engine.stop()
            engineStarted = false
        }
    }

    func receivedMIDINoteOn(noteNumber: MIDINoteNumber,
                            velocity: MIDIVelocity,
                            channel: MIDIChannel,
                            portID _: MIDIUniqueID?,
                            timeStamp _: MIDITimeStamp?)
    {
        // Trigger audio immediately and emit payload (avoid SwiftUI state coalescing)
        let note = Int(noteNumber)
        let vel  = Int(velocity)
        if vel > 0 {
            let boosted = min(127, Int(round(Double(vel) * externalVelocityBoost)))
            instrument.play(noteNumber: MIDINoteNumber(note), velocity: MIDIVelocity(boosted), channel: 0)
            DispatchQueue.main.async {
                self.noteOnSubject.send((note, boosted))
            }
        } else {
            // Treat Note On with velocity 0 as Note Off
            instrument.stop(noteNumber: MIDINoteNumber(note), channel: 0)
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
        DispatchQueue.main.async {
            self.noteOnSubject.send((noteNumber, velocity))
        }

        DispatchQueue.main.async {
            self.lastEventWasSimulated = true
            self.noteOnEventID = UUID()
            self.midiEventType = .noteOn
            self.isShowingMIDIReceived = true
            self.data.noteOn = noteNumber
            self.data.velocity = velocity
            self.data.channel = channel
            if velocity > 0 {
                self.activeNotes.insert(noteNumber)
            } else {
                // Treat Note On with velocity 0 as Note Off
                self.activeNotes.remove(noteNumber)
                withAnimation(.easeOut(duration: 0.4)) {
                    self.isShowingMIDIReceived = false
                }
            }
        }
    }

    func simulateNoteOff(noteNumber: Int, velocity: Int = 0, channel: Int = 0) {
        // Trigger audio immediately and emit payload
        instrument.stop(noteNumber: MIDINoteNumber(noteNumber), channel: 0)
        DispatchQueue.main.async {
            self.noteOffSubject.send(noteNumber)
        }

        DispatchQueue.main.async {
            self.lastEventWasSimulated = true
            self.midiEventType = .noteOff
            self.isShowingMIDIReceived = false
            self.data.noteOff = noteNumber
            self.data.velocity = velocity
            self.data.channel = channel
            self.activeNotes.remove(noteNumber)
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
}

struct ContentView: View {
  @EnvironmentObject private var appData: AppData
  @Environment(\.colorScheme) private var colorScheme
  
  let trebleStaff = MusicSymbol.trebleStaff.text()
  let bassStaff = MusicSymbol.bassStaff.text()
  
  let sharpText = MusicSymbol.sharpSymbol.text()
  let flatText = MusicSymbol.flatSymbol.text()
  let naturalText = MusicSymbol.naturalSymbol.text()
  
  let sharedX: CGFloat = 166
  let noteX: CGFloat = 166
  
  @StateObject private var vm = StaffViewModel()
  @EnvironmentObject private var conductor: MIDIMonitorConductor
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
    NavigationStack(path: $navigationPath) {
      ZStack {
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
            .frame(height: 20)
          
          // Removed inline KeyBoardView here per instructions
          
          // Staff and note drawing (panel removed)
          VStack(spacing: 16) {
            Canvas { context, size in
              // Center the entire staff/note drawing within the canvas
              let centerX = size.width / 2
              let centerY = size.height / 2
              let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2 // 190 based on current anchors
              let offsetX = centerX - noteX
              let offsetY = centerY - originalGroupMidY
              context.translateBy(x: offsetX, y: offsetY)
              
              // Add subtle shadow to improve contrast on dark background
              if colorScheme == .dark {
                context.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1))
              } else {
                context.addFilter(.shadow(color: .black.opacity(0.10), radius: 0.8, x: 0, y: 0.5))
              }
              
              // Draw both staffs
              context.draw(trebleStaff, at: trebleStaffPoint)
              context.draw(bassStaff, at: bassStaffPoint)
              
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
            .frame(height: 280)
            .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1), value: vm.currentY)
            .foregroundStyle(.white)
            
            // Labels for clef, note name and MIDI code
            HStack(spacing: 12) {
              Spacer()
              
              Text("Clef:")
              Text(vm.currentClef == .treble ? "Treble" : "Bass")
              Text("Note:")
              Text(vm.currentNote.name).monospaced()
              Text("MIDI:")
              Text(String(vm.currentNote.midi)).monospaced()
              
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
                .controlSize(.regular)
              }
              
              Spacer()
            }
            
            // Received values from MIDI to compare with the random note above
            HStack(spacing: 12) {
              Text("Received Clef:")
              Text(conductor.data.noteOn == 0 ? "—" : (conductor.data.noteOn < 60 ? "Bass" : (conductor.data.noteOn > 60 ? "Treble" : "Both")))
              Text("Received Note:")
              Text(noteName(from: conductor.data.noteOn))
                .monospaced()
              Text("Received MIDI:")
              Text(String(conductor.data.noteOn))
                .monospaced()
            }
          }
          .padding(.horizontal, 20)
          .foregroundStyle(.white)
          
          // Practice mode controls or free play button
          if isPracticeMode {
            HStack(spacing: 12) {
              Text("Practice Mode")
                .fontWeight(.semibold)
              
              Text("Note \(currentPracticeIndex + 1) of \(practiceCount)")
                .monospaced()
              
              Button("Exit Practice") {
                exitPracticeMode()
              }
              .buttonStyle(.borderedProminent)
              .tint(.white)
              .foregroundStyle(.red)
              .controlSize(.regular)
            }
            .foregroundStyle(.white)
            .frame(height: 56)
          } else {
            // Practice mode controls only (New Note button is now in clef HStack above)
            HStack(spacing: 12) {
              Text("Practice")
              HStack(spacing: 8) {
                Text("Count:")
                Text("\(practiceCount)")
                  .monospaced()
                
                HStack(spacing: 6) {
                  Button {
                    practiceCount = max(5, practiceCount - 5)
                  } label: {
                    Image(systemName: "chevron.down")
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundStyle(.white)
                      .padding(6)
                      .background(Color.white.opacity(0.12))
                      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                  }
                  .buttonStyle(.plain)
                  
                  Button {
                    practiceCount = min(100, practiceCount + 5)
                  } label: {
                    Image(systemName: "chevron.up")
                      .font(.system(size: 12, weight: .semibold))
                      .foregroundStyle(.white)
                      .padding(6)
                      .background(Color.white.opacity(0.12))
                      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                  }
                  .buttonStyle(.plain)
                }
              }
              .foregroundStyle(.white)
              
              Button("Start Practice") {
                startPractice()
              }
              .buttonStyle(.borderedProminent)
              .tint(.white)
              .foregroundStyle(.black)
              .controlSize(.regular)
            }
            .foregroundStyle(.white)
            .tint(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
            .frame(height: 56)
          }
          
          Spacer()
            .frame(minHeight: 8, maxHeight: 20)
        } // VStack
        .safeAreaInset(edge: .bottom) {
          KeyBoardView(isCorrect: { midi in
            midi == vm.currentNote.midi
          }, docked: true)
          .environmentObject(appData)
          .environmentObject(conductor)
        }
        .padding(.horizontal, 8)
        .onAppear {
          vm.setAllowedMIDIRange(appData.calibratedRange)
          vm.setIncludeAccidentals(appData.includeAccidentals)
          randomizeNoteRespectingCalibration()
          conductor.start()
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
        .onDisappear {
          conductor.stop()
        }
        .navigationDestination(for: NavigationDestination.self) { destination in
          switch destination {
            case .calibration:
              CalibrationWizardView(navigationPath: $navigationPath)
                .environmentObject(appData)
                .environmentObject(conductor)
            case .history:
              PracticeHistoryView(navigationPath: $navigationPath)
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
  } // body
  
  var midiReceivedIndicator: some View {
    HStack(alignment: .center, spacing: 16) {
      // Left-aligned MIDI In indicator
      HStack(spacing: 8) {
        Text("MIDI In")
          .font(.callout)
          .fontWeight(.semibold)
          .fixedSize()
        Circle()
          .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
          .background(Circle().fill(conductor.isShowingMIDIReceived ? .blue : .blue.opacity(0.2)))
          .frame(width: 20, height: 20)
      }
      
      Spacer()
      
      // Centered Note style picker (custom segmented control)
      HStack(spacing: 12) {
        Text("Note Type:")
          .font(.callout)
          .fontWeight(.semibold)
          .fixedSize()
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
              .font(.callout)
              .fontWeight(.medium)
              .frame(width: 200/3, height: 28)
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
          .controlSize(.small)
          .fixedSize()
      }
      
      Spacer()
      
      // Right-aligned controls
      HStack(spacing: 10) {
        Text(calibrationDisplayText)
          .font(.subheadline)
          .foregroundColor(.white)
          .fixedSize()
          .frame(minWidth: 120)
        
        Button("History") {
          navigationPath.append(NavigationDestination.history)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .controlSize(.regular)
        
        Button("Calibrate") {
          navigationPath.append(NavigationDestination.calibration)
        }
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .controlSize(.regular)
      }
    }
    #if os(macOS)
    .padding([.top, .horizontal], 20)
    #else
    .padding(.horizontal, 16)
    .padding(.top, 90)
    #endif
    .frame(maxWidth: .infinity)
    .shadow(color: colorScheme == .dark ? .clear : .white.opacity(0.35), radius: 0.5, x: 0, y: 1)
    .foregroundStyle(.white)
    .tint(.white.opacity(0.9))
  }
} // ContentView
  
  #Preview("Whole") {
    let data = AppData()
    data.noteHeadStyle = .whole
    return ContentView()
      .environmentObject(data)
      .environmentObject(MIDIMonitorConductor())
      .frame(width: 900, height: 900)
  }
  
  #Preview("Half") {
    let data = AppData()
    data.noteHeadStyle = .half
    return ContentView()
      .environmentObject(data)
      .environmentObject(MIDIMonitorConductor())
      .frame(width: 900, height: 900)
  }
  
  #Preview("Quarter") {
    let data = AppData()
    data.noteHeadStyle = .quarter
    return ContentView()
      .environmentObject(data)
      .environmentObject(MIDIMonitorConductor())
      .frame(width: 900, height: 900)
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

