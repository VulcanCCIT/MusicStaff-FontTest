//
//  KeyBoardView.swift
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

#if os(macOS)
import AppKit
#endif

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
  @EnvironmentObject private var conductor: MIDIMonitorConductor
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
        
//        // Display the current low note here
//        Text("Lowest Note: \(noteName(from: lowNote)) (MIDI: \(lowNote))")
//          .font(.headline)
//        
//        // Display the current high note here
//        Text("Highest Note: \(noteName(from: highNote)) (MIDI: \(highNote))")
//          .font(.headline)
        
        
        // Full-width control panel above the keyboard (knobs and meter on one line)
        HStack(alignment: .center, spacing: 24) {
          KnobImage()
          KnobImage()
          Spacer()
          NodeOutputView(conductor.instrument, color: .red)
            .frame(height: 52)
            .frame(maxWidth: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
          Spacer()
          ZStack(alignment: .topTrailing) {
            KnobImage()
            Image("redled2")
              .resizable()
              .interpolation(.high)
              .antialiased(true)
              .frame(width: 36, height: 36)
              .offset(x: 32, y: -16)
              .accessibilityHidden(true)
          }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color("MeterPanelColor"))
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
        

        Keyboard(
          layout: .piano(pitchRange: Pitch(intValue: lowNote) ... Pitch(intValue: highNote)),
          noteOn: { pitch, point in
            // Map vertical position to MIDI velocity and notify conductor (audio is triggered in conductor)
            let raw = Int(point.y * 127)
            let vel = max(1, min(127, raw))
            conductor.simulateNoteOn(noteNumber: pitch.intValue, velocity: vel)
          },
          noteOff: { pitch in
            // Notify conductor of note off (audio is triggered in conductor)
            conductor.simulateNoteOff(noteNumber: pitch.intValue)
          }
        ) { pitch, isActivated in
          let midi = pitch.intValue
          let externallyOn = conductor.activeNotes.contains(midi)
          //let externalIntensity = externalVelocities[midi] ?? 0.0
          //let isBlack = [1, 3, 6, 8, 10].contains(midi % 12)
          //let overlayColor: Color = isBlack ? .cyan : .blue
          ZStack {
            KeyboardKey(
              pitch: pitch,
              isActivated: isActivated || externallyOn,
              text: scientificLabel(for: pitch),
              alignment: .bottom
            )
//            Rectangle()
//              .fill(overlayColor)
//              .opacity(externalIntensity)
//              .allowsHitTesting(false)
          }
        }
                .frame(minWidth: 100, minHeight: 100)
//                .overlay(alignment: .top) {
//                  Rectangle()
//                    .fill(Color.blue)
//                    .frame(height: 15)
//                    .cornerRadius(3)
//                    //.padding(.horizontal, 6)
//                    .allowsHitTesting(false)
//                }
              }
      //.background(Color.clear)
      .background(colorScheme == .dark ?
                  Color.clear : Color("MeterPanelColor"))
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 18,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 18,
          style: .continuous
        )
      )
              .onReceive(conductor.noteOnSubject) { (note, velocity) in
                  // Update visual intensity; audio already triggered in conductor
                  let boosted = min(127, Int(round(Double(velocity) * 2.25)))
                  let norm = max(0.0, min(1.0, Double(boosted) / 127.0))
                  externalVelocities[note] = norm
              }
              .onReceive(conductor.noteOffSubject) { note in
                  // Remove visual intensity; audio already triggered in conductor
                  externalVelocities.removeValue(forKey: note)
              }
    }
  }
}

struct KnobImage: View {
  var body: some View {
    Group {
      #if os(macOS)
      if NSImage(named: "Knob2") != nil {
        Image("Knob2")
          .resizable()
          .interpolation(.high)
          .antialiased(true)
      } else {
        Image(systemName: "dial.max")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      #else
      if UIImage(named: "knob2") != nil {
        Image("knob2")
          .resizable()
          .interpolation(.high)
          .antialiased(true)
      } else {
        Image(systemName: "dial.max")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      #endif
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(width: 46, height: 46)
    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    .accessibilityHidden(true)
  }
}

//#Preview {
//  let data = AppData()
//  data.minMIDINote = 24
//  data.maxMIDINote = 48
//  KeyBoardView()
//    .environmentObject(data)
//}

