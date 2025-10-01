//
//  KwyBoardView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 10/1/25.
//

import Keyboard
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

struct KeyBoardView: View {
  @ObservedObject var conductor: MIDIMonitorConductor
  
  func noteOn(pitch: Pitch, point: CGPoint) {
    print("note on \(pitch)")
  }
  
  func noteOff(pitch: Pitch) {
    print("note off \(pitch)")
  }
  
  func noteOnWithVerticalVelocity(pitch: Pitch, point: CGPoint) {
    print("note on \(pitch), midiVelocity: \(Int(point.y * 127))")
  }
  
  func noteOnWithReversedVerticalVelocity(pitch: Pitch, point: CGPoint) {
    print("note on \(pitch), midiVelocity: \(Int((1.0 - point.y) * 127))")
  }
  
  var randomColors: [Color] = (0 ... 12).map { _ in
    Color(red: Double.random(in: 0 ... 1),
          green: Double.random(in: 0 ... 1),
          blue: Double.random(in: 0 ... 1), opacity: 1)
  }
  
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
          noteOn: noteOnWithVerticalVelocity(pitch:point:),
          noteOff: noteOff
        ) { pitch, isActivated in
          let midi = pitch.intValue
          let externallyOn = conductor.activeNotes.contains(midi)
          KeyboardKey(
            pitch: pitch,
            isActivated: isActivated || externallyOn,
            text: scientificLabel(for: pitch),
            //flatTop: true,
            alignment: .bottom
          )
        }
                .frame(minWidth: 100, minHeight: 100)
              }
              .background(colorScheme == .dark ?
                          Color.clear : Color(red: 0.9, green: 0.9, blue: 0.9))
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

