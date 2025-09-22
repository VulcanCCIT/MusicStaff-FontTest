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

  @StateObject private var vm = StaffViewModel()

  // Staff drawing control (positions match your previous staff anchors)
  private let trebleStaffPoint = CGPoint(x: 155, y: 150)
  private let bassStaffPoint   = CGPoint(x: 155, y: 220)
  private let lineWidth: CGFloat = 24 // approximate width of a ledger line glyph

  var body: some View {
    VStack(spacing: 16) {
      // Staff and note drawing
      Canvas { context, size in
        // Choose staff
        let staffPoint = (vm.currentClef == .treble) ? trebleStaffPoint : bassStaffPoint
        let staffText  = (vm.currentClef == .treble) ? trebleStaff : bassStaff
        context.draw(staffText, at: staffPoint)

        // Draw ledger lines (if any)
        let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
        for y in ledgerYs {
          // Centered at noteX, using singleLine glyph for a short ledger line
          context.draw(singleLine, at: CGPoint(x: noteX, y: y))
        }

        // Draw the current note
        let notePoint = CGPoint(x: noteX, y: vm.currentY)
        context.draw(wholeNote, at: notePoint)
      }
      .frame(height: 360)

      // Labels for clef, note name and MIDI code
      HStack(spacing: 12) {
        Text("Clef:")
        Text(vm.currentClef == .treble ? "Treble" : "Bass")
        Text("Note:")
        Text(vm.currentNote.name).monospaced()
        Text("MIDI:")
        Text(String(vm.currentNote.midi)).monospaced()
      }

      // Button to get a new random note on a random clef (only one clef at a time)
      Button("New Note") {
        vm.randomizeNote()
      }
      .buttonStyle(.borderedProminent)
    }
    .onAppear { vm.randomizeNote() }
    .padding()
  }
}

#Preview {
    ContentView()
}
