//
//  ContentView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI

struct ContentView: View {

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
  let wholeNote = MusicSymbol.wholeNote.text()
  
  let sharedX: CGFloat = 166
  let noteX: CGFloat = 166

  let C4noteY: CGFloat = 190
  let D4noteY: CGFloat = 182
  let E4noteY: CGFloat = 175
  let F4noteY: CGFloat = 170
  let G4noteY: CGFloat = 165
  let A4noteY: CGFloat = 160
  let B4noteY: CGFloat = 154
  let C5noteY: CGFloat = 149
  let D5noteY: CGFloat = 144
  let E5noteY: CGFloat = 138
  let F5noteY: CGFloat = 133
  let G5noteY: CGFloat = 126  //noLine
  let A5noteY: CGFloat = 123 //singleLine
  let B5noteY: CGFloat = 117 //singleLine
  let C6noteY: CGFloat = 112 //doubleLine
  let D6noteY: CGFloat = 106 //doubleLine
  let E6noteY: CGFloat = 102 //tripleLine
  let F6noteY: CGFloat = 96 //tripleLine
  let G6noteY: CGFloat = 93 //quadLine
  let A6noteY: CGFloat = 87 //quadLine
  let B6noteY: CGFloat = 81 //quinLine
  let C7noteY: CGFloat = 75 //sextLine
  let D7noteY: CGFloat = 71 //sextLine
  let E7noteY: CGFloat = 65 //sextLine
  let F7noteY: CGFloat = 63 //sevenLine
  let G7noteY: CGFloat = 56 //sevenLine
  let A7noteY: CGFloat = 55 //eightLine
  let B7noteY: CGFloat = 48 //eightLine
  let C8noteY: CGFloat = 46 //nineLine


  let C4LineY: CGFloat = 205 //C4singleLine
  let singleLineY: CGFloat = 135 //singleLine
  let doubleLineY: CGFloat = 137 //doubleLine
  let tripleLineY: CGFloat = 132 //tripleLine
  let quadLineY: CGFloat = 128 //quadLine
  let quinLineY: CGFloat = 121 //quinLine
  let sextLineY: CGFloat = 116 //sextLine
  let sevenLineY: CGFloat = 83 //sevenLine
  let eightLineY: CGFloat = 75 //eightLine
  let nineLineY: CGFloat = 66 //nineLine


  struct StaffNote {
    let name: String
    let midi: Int
    let y: CGFloat
  }

  enum Clef { case treble, bass }

  @State private var currentClef: Clef = .treble
  @State private var currentNote: StaffNote = StaffNote(name: "", midi: 60, y: 0)

  // MARK: - Note generation helpers
  private func midiRange(for clef: Clef) -> ClosedRange<Int> {
    switch clef {
    case .treble:
      return 60...108 // C4..C8
    case .bass:
      return 21...60  // A0..C4
    }
  }

  private func isNatural(_ midi: Int) -> Bool {
    // C, D, E, F, G, A, B
    return [0, 2, 4, 5, 7, 9, 11].contains(midi % 12)
  }

  private func noteName(for midi: Int) -> String {
    let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    let octave = midi / 12 - 1
    return names[midi % 12] + String(octave)
  }

  private func yForMidi(_ midi: Int) -> CGFloat {
    // Anchor at your provided C4 position and use an approximate semitone step.
    // This keeps lower bass notes visible and aligns reasonably with your treble constants.
    let semitoneStep: CGFloat = -3.25 // pixels per semitone (upwards is negative y)
    return C4noteY + CGFloat(midi - 60) * semitoneStep
  }

  private func randomizeNote() {
    currentClef = Bool.random() ? .treble : .bass
    let range = midiRange(for: currentClef)
    let candidates = Array(range).filter(isNatural)
    if let midi = candidates.randomElement() {
      currentNote = StaffNote(name: noteName(for: midi), midi: midi, y: yForMidi(midi))
    }
  }

  var body: some View {
    VStack(spacing: 16) {
      // Staff and note drawing
      Canvas { context, size in
        switch currentClef {
        case .treble:
          context.draw(trebleStaff, at: CGPoint(x: 155, y: 150))
        case .bass:
          context.draw(bassStaff, at: CGPoint(x: 155, y: 220))
        }

        // Draw the current note
        context.draw(wholeNote, at: CGPoint(x: noteX, y: currentNote.y))
      }
      .frame(height: 360)

      // Labels for note name and MIDI code
      Text("Note: \(currentNote.name)    MIDI: \(currentNote.midi)")
        .font(.headline)

      // Button to get a new random note on a random clef (only one clef at a time)
      Button("New Note") {
        randomizeNote()
      }
      .buttonStyle(.borderedProminent)
    }
    .onAppear { randomizeNote() }
    .padding()
  }
}

#Preview {
    ContentView()
}
