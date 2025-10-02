//
//  KwyBoardView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 10/1/25.
//

import AudioKit
import AudioKitEX
import AudioKitUI
import AVFoundation
import Combine
import Keyboard
import SoundpipeAudioKit
import SwiftUI
import Tonic

let evenSpacingInitialSpacerRatio: [Letter: CGFloat] = [
    .C: 0.0,
    .D: 2.0 / 12.0,
    .E: 4.0 / 12.0,
    .F: 0.0 / 12.0,
    .G: 1.0 / 12.0,
    .A: 3.0 / 12.0,
    .B: 5.0 / 12.0
]

let evenSpacingSpacerRatio: [Letter: CGFloat] = [
    .C: 7.0 / 12.0,
    .D: 7.0 / 12.0,
    .E: 7.0 / 12.0,
    .F: 7.0 / 12.0,
    .G: 7.0 / 12.0,
    .A: 7.0 / 12.0,
    .B: 7.0 / 12.0
]

let evenSpacingRelativeBlackKeyWidth: CGFloat = 7.0 / 12.0

class InstrumentEXSConductor: ObservableObject, HasAudioEngine {
    let engine = AudioEngine()
    var instrument = AppleSampler()
    
    func noteOn(pitch: Pitch, point: CGPoint) {
        // Map vertical position to velocity (0.0...1.0 -> 1...127)
        let raw = Int(point.y * 127)
        let vel = MIDIVelocity(max(1, min(127, raw)))
        instrument.play(noteNumber: MIDINoteNumber(pitch.midiNoteNumber), velocity: vel, channel: 0)
    }
    
    func noteOff(pitch: Pitch) {
        instrument.stop(noteNumber: MIDINoteNumber(pitch.midiNoteNumber), channel: 0)
    }
    
    func noteOn(midiNote: Int, velocity: Int) {
        let vel = MIDIVelocity(max(1, min(127, velocity)))
        instrument.play(noteNumber: MIDINoteNumber(midiNote), velocity: vel, channel: 0)
    }

    func noteOff(midiNote: Int) {
        instrument.stop(noteNumber: MIDINoteNumber(midiNote), channel: 0)
    }
    
    init() {
        engine.output = instrument
        
        // Load EXS file (you can also load SoundFonts and WAV files too using the AppleSampler Class)
        do {
            if let fileURL = Bundle.main.url(forResource: "Sounds/Sampler Instruments/sawPiano1", withExtension: "exs") {
                try instrument.loadInstrument(url: fileURL)
            } else {
                Log("Could not find file")
            }
        } catch {
            Log("Could not load instrument")
        }
    }
    
    func start() {
        do {
            try engine.start()
        } catch {
            Log("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
    }
}

struct KeyBoardView: View {
  @EnvironmentObject private var conductor: MIDIMonitorConductor
  @StateObject private var exsConductor = InstrumentEXSConductor()
  @State private var externalVelocities: [Int: Double] = [:] // midiNote -> 0.0...1.0
  
  @State var scaleIndex = Scale.allCases.firstIndex(of: .chromatic) ?? 0 {
    didSet {
      if scaleIndex >= Scale.allCases.count { scaleIndex = 0 }
      if scaleIndex < 0 { scaleIndex = Scale.allCases.count - 1 }
      scale = Scale.allCases[scaleIndex]
    }
  }
  
  @State var scale: Scale = .chromatic
  @State var root: NoteClass = .C
  @State var rootIndex = 0
  @Environment(\.colorScheme) var colorScheme
  
  @EnvironmentObject private var appData: AppData

  private var lowNote: Int {
    appData.calibratedRange?.lowerBound ?? 24
  }

  private var highNote: Int {
    appData.calibratedRange?.upperBound ?? 48
  }
  
  private func noteName(from midiNote: Int) -> String {
    guard (0...127).contains(midiNote) else { return "—" }
    let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    let octave = (midiNote / 12) - 1
    return names[midiNote % 12] + String(octave)
  }
  
  // Helper you can add inside KeyBoardView
  private func scientificLabel(for pitch: Pitch) -> String {
      let midi = pitch.intValue
      let octave = midi / 12 - 1  // MIDI 60 -> 4
      // Only label C keys; return empty for others
      return (midi % 12 == 0) ? "C\(octave)" : ""
  }
  
  var body: some View {
    HStack {
      VStack {
        
        // Display the current low note here
        Text("Lowest Note: \(noteName(from: lowNote)) (MIDI: \(lowNote))")
          .font(.headline)
        
        // Display the current high note here
        Text("Highest Note: \(noteName(from: highNote)) (MIDI: \(highNote))")
          .font(.headline)
        
        
//                Keyboard(layout: .piano(pitchRange: Pitch(intValue: lowNote) ... Pitch(intValue: highNote)),
//                         noteOn: noteOnWithVerticalVelocity(pitch:point:), noteOff: noteOff)
        Keyboard(
          layout: .piano(pitchRange: Pitch(intValue: lowNote) ... Pitch(intValue: highNote)),
          noteOn: exsConductor.noteOn(pitch:point:),
          noteOff: exsConductor.noteOff(pitch:)
        ) { pitch, isActivated in
          let midi = pitch.intValue
          let externallyOn = conductor.activeNotes.contains(midi)
          let externalIntensity = externalVelocities[midi] ?? 0.0
          let isBlack = [1, 3, 6, 8, 10].contains(midi % 12)
          let overlayColor: Color = isBlack ? .cyan : .blue
          ZStack {
            KeyboardKey(
              pitch: pitch,
              isActivated: isActivated || externallyOn,
              text: scientificLabel(for: pitch),
              alignment: .bottom
            )
            Rectangle()
              .fill(overlayColor)
              .opacity(externalIntensity)
              .allowsHitTesting(false)
          }
        }
                .frame(minWidth: 100, minHeight: 100)
              }
              .background(colorScheme == .dark ?
                          Color.clear : Color(red: 0.9, green: 0.9, blue: 0.9))
              .onAppear { exsConductor.start() }
              .onDisappear { exsConductor.stop() }
              .onChange(of: conductor.data.noteOn) { _, newValue in
                  // Respond to external MIDI Note On. Some devices send Note On with velocity 0 as Note Off
                  guard conductor.midiEventType == .noteOn else { return }
                  if conductor.data.velocity > 0 {
                      exsConductor.noteOn(midiNote: newValue, velocity: conductor.data.velocity)
                      let norm = max(0.0, min(1.0, Double(conductor.data.velocity) / 127.0))
                      externalVelocities[newValue] = norm
                  } else {
                      exsConductor.noteOff(midiNote: newValue)
                      externalVelocities.removeValue(forKey: newValue)
                  }
              }
              .onChange(of: conductor.data.noteOff) { _, newValue in
                  // Respond to external MIDI Note Off
                  guard conductor.midiEventType == .noteOff else { return }
                  exsConductor.noteOff(midiNote: newValue)
                  externalVelocities.removeValue(forKey: newValue)
              }
    }
  }
}

//#Preview {
//  let data = AppData()
//  data.minMIDINote = 24
//  data.maxMIDINote = 48
//  KeyBoardView()
//    .environmentObject(data)
//}

