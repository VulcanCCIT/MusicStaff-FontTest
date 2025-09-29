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
    @Published var data = MIDIMonitorData()
    @Published var isShowingMIDIReceived: Bool = false
    @Published var isToggleOn: Bool = false
    @Published var oldControllerValue: Int = 0
    @Published var midiEventType: MIDIEventType = .none

    init() {}

    func start() {
        midi.openInput(name: "Bluetooth")
        midi.openInput()
        midi.addListener(self)
    }

    func stop() {
        midi.closeAllInputs()
    }

    func receivedMIDINoteOn(noteNumber: MIDINoteNumber,
                            velocity: MIDIVelocity,
                            channel: MIDIChannel,
                            portID _: MIDIUniqueID?,
                            timeStamp _: MIDITimeStamp?)
    {
        print("noteNumber \(noteNumber) \(noteNumber)")
        print("velocity \(velocity) \(velocity)")
        DispatchQueue.main.async {
            self.midiEventType = .noteOn
            self.isShowingMIDIReceived = true
            self.data.noteOn = Int(noteNumber)
            self.data.velocity = Int(velocity)
            self.data.channel = Int(channel)
            if self.data.velocity == 0 {
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
        print("noteNumber \(noteNumber) \(noteNumber)")
        print("velocity \(velocity) \(velocity)")
        DispatchQueue.main.async {
            self.midiEventType = .noteOff
            self.isShowingMIDIReceived = false
            self.data.noteOff = Int(noteNumber)
            self.data.velocity = Int(velocity)
            self.data.channel = Int(channel)
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
}


private let kNoteNames: [String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

private func noteName(from midiNote: Int) -> String {
    guard (0...127).contains(midiNote) else { return "—" }
    let name = kNoteNames[midiNote % 12]
    let octave = (midiNote / 12) - 1
    return "\(name)\(octave)"
}

struct ContentView: View {
  @EnvironmentObject private var appData: AppData

  let trebleStaff = MusicSymbol.trebleStaff.text()
  let bassStaff = MusicSymbol.bassStaff.text()
  let singleLine = MusicSymbol.singleLine.text()
  let doubleLine = MusicSymbol.doubleLine.text()
  let tripleLine = MusicSymbol.tripleLine.text()
  let quadLine = MusicSymbol.quadLine.text()
  let quinLine = MusicSymbol.quinLine.text()
  let sextLine = MusicSymbol.sextLine.text()
  let sevenLine = MusicSymbol.sevenLine.text()
  let eightLine = MusicSymbol.eightLine.text()
  let nineLine = MusicSymbol.nineLine.text()

  let sharedX: CGFloat = 166
  let noteX: CGFloat = 166

  @StateObject private var vm = StaffViewModel()
  @StateObject private var conductor = MIDIMonitorConductor()
  @State private var advanceWorkItem: DispatchWorkItem?
  // Removed: private let autoAdvanceDebounce: TimeInterval = 0.25

  @State private var showingCalibration = false

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
    VStack(spacing: 16) {
      midiReceivedIndicator

      
      // Staff and note drawing
      Canvas { context, size in
        // Center the entire staff/note drawing within the canvas
        let centerX = size.width / 2
        let centerY = size.height / 2
        let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2 // 190 based on current anchors
        let offsetX = centerX - noteX
        let offsetY = centerY - originalGroupMidY
        context.translateBy(x: offsetX, y: offsetY)

        let showDebug = false //turns on debug positioning lines.

        // Draw both staffs
        context.draw(trebleStaff, at: trebleStaffPoint)
        context.draw(bassStaff, at: bassStaffPoint)

        if showDebug {
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
            let stroke: CGFloat = 0.75
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
        let ledgerLength: CGFloat = lineWidth // reuse approximate glyph width as the visual length
        let strokeWidth: CGFloat = 1.2
        for y in ledgerYs {
          var p = Path()
          p.move(to: CGPoint(x: noteX - ledgerLength/2, y: y))
          p.addLine(to: CGPoint(x: noteX + ledgerLength/2, y: y))
          context.stroke(p, with: .color(.primary), lineWidth: strokeWidth)
        }

        // Draw the current note
        let notePoint = CGPoint(x: noteX, y: vm.currentY)
        let noteText = currentNoteSymbol.text()
        context.draw(noteText, at: notePoint, anchor: .center)
        
      }
      .frame(height: 420)
      .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1), value: vm.currentY)


      // Labels for clef, note name and MIDI code
      HStack(spacing: 12) {
        Text("Clef:")
        Text(vm.currentClef == .treble ? "Treble" : "Bass")
        Text("Note:")
        Text(vm.currentNote.name).monospaced() //ToDo look for this note with midiKit
        Text("MIDI:")
        Text(String(vm.currentNote.midi)).monospaced()
      }
      
      // Received values from MIDI to compare with the random note above
      HStack(spacing: 12) {
        Text("Received Clef:")
        Text(conductor.data.noteOn == 0 ? "—" : (conductor.data.noteOn < 60 ? "Bass" : (conductor.data.noteOn > 60 ? "Treble" : "Both")))
        Text("Received Note:")
        Text(noteName(from: conductor.data.noteOn))
          .monospaced()
          .foregroundColor(conductor.data.noteOn == 0 ? .secondary : (conductor.data.noteOn == vm.currentNote.midi ? .green : .red))
        Text("Received MIDI:")
        Text(String(conductor.data.noteOn))
          .monospaced()
          .foregroundColor(conductor.data.noteOn == 0 ? .secondary : (conductor.data.noteOn == vm.currentNote.midi ? .green : .red))
        if conductor.data.noteOn != 0 {
          Image(systemName: (conductor.data.noteOn == vm.currentNote.midi) ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle((conductor.data.noteOn == vm.currentNote.midi) ? .green : .red)
        }
      }

      // Button to get a new random note on a random clef (only one clef at a time)
      Button("New Note") {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)) {
          randomizeNoteRespectingCalibration()
        }
      }
      .buttonStyle(.borderedProminent)
    }//vstack
    .onAppear {
      vm.setAllowedMIDIRange(appData.calibratedRange)
      randomizeNoteRespectingCalibration()
      conductor.start()
    }
    .onChange(of: appData.minMIDINote) { _ in
      vm.setAllowedMIDIRange(appData.calibratedRange)
      randomizeNoteRespectingCalibration()
    }
    .onChange(of: appData.maxMIDINote) { _ in
      vm.setAllowedMIDIRange(appData.calibratedRange)
      randomizeNoteRespectingCalibration()
    }
    .onChange(of: conductor.data.noteOn) { newValue in
      // Only respond to real Note On events (some devices send Note On with velocity 0 as Note Off)
      guard conductor.midiEventType == .noteOn, conductor.data.velocity > 0 else { return }
      // If the played note matches the current target note, schedule a debounced auto-advance
      guard newValue == vm.currentNote.midi else { return }
      // Cancel any pending advance and schedule a new one
      advanceWorkItem?.cancel()
      let work = DispatchWorkItem {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)) {
          randomizeNoteRespectingCalibration()
        }
      }
      advanceWorkItem = work
      DispatchQueue.main.asyncAfter(deadline: .now() + appData.autoAdvanceDebounce, execute: work)
    }
    .onDisappear {
      advanceWorkItem?.cancel()
    }
    .padding()
  }
  var midiReceivedIndicator: some View {
      HStack(alignment: .center) {
          // Left-aligned MIDI In indicator
          HStack(spacing: 15) {
              Text("MIDI In")
                  .fontWeight(.medium)
              Circle()
                  .strokeBorder(.blue.opacity(0.5), lineWidth: 1)
                  .background(Circle().fill(conductor.isShowingMIDIReceived ? .blue : .blue.opacity(0.2)))
                  .frame(maxWidth: 20, maxHeight: 20)
          }

          Spacer()

          // Centered Note style picker (no overlay, so nothing can overlap it)
          HStack(spacing: 8) {
              Text("Note")
              Picker("Note", selection: $appData.noteHeadStyle) {
                  Text("Whole").tag(NoteHeadStyle.whole)
                  Text("Half").tag(NoteHeadStyle.half)
                  Text("Quarter").tag(NoteHeadStyle.quarter)
              }
              .labelsHidden()
              .pickerStyle(.segmented)
              .frame(width: 320)
          }

          Spacer()

          // Right-aligned controls
          HStack(spacing: 12) {
              // Debounce control (label fixed width)
              HStack(spacing: 6) {
                  Image(systemName: "timer")
                  .foregroundStyle(.blue)
                      .foregroundStyle(.secondary)
                  Text("Debounce:")
                  .font(.headline)
                      .foregroundStyle(.blue)
                      .frame(width: 85)
                     // .padding(.trailing, 2)
                  Picker("Debounce", selection: $appData.autoAdvanceDebounce) {
                      Text("Off").tag(0.0)
                      Text("0.15s").tag(0.15)
                      Text("0.25s").tag(0.25)
                      Text("0.5s").tag(0.5)
                      Text("1.0s").tag(1.0)
                  }
                  .labelsHidden()
                  .pickerStyle(.menu)
                  .frame(width: 110)
                  .help("Time to wait before auto-advancing after a correct note.")
              }

              Text(calibrationDisplayText)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)

              Button("Calibrate") { showingCalibration = true }
                  .buttonStyle(.bordered)
          }
      }
      .padding([.top, .horizontal], 20)
      .frame(maxWidth: .infinity, maxHeight: 60, alignment: .center)
      .sheet(isPresented: $showingCalibration) {
          CalibrationWizardView(isPresented: $showingCalibration)
              .environmentObject(appData)
      }
  }

  // Staff drawing control (positions match your previous staff anchors)
  private let trebleStaffPoint = CGPoint(x: 155, y: 150)
  private let bassStaffPoint   = CGPoint(x: 155, y: 230)
  private let lineWidth: CGFloat = 24 // approximate width of a ledger line glyph

}

#Preview("Whole") {
    let data = AppData()
    data.noteHeadStyle = .whole
    return ContentView()
        .environmentObject(data)
}

#Preview("Half") {
    let data = AppData()
    data.noteHeadStyle = .half
    return ContentView()
        .environmentObject(data)
}

#Preview("Quarter") {
    let data = AppData()
    data.noteHeadStyle = .quarter
    return ContentView()
        .environmentObject(data)
}

