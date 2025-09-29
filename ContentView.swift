//
//  ContentView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI

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

  var body: some View {
    VStack(spacing: 16) {
      // Staff and note drawing
      Canvas { context, size in
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
      .frame(height: 360)
      .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1), value: vm.currentY)

      // Note style picker
      Picker("Note", selection: $appData.noteHeadStyle) {
        Text("Whole").tag(NoteHeadStyle.whole)
        Text("Half").tag(NoteHeadStyle.half)
        Text("Quarter").tag(NoteHeadStyle.quarter)
      }
      .pickerStyle(.segmented)

      // Labels for clef, note name and MIDI code
      HStack(spacing: 12) {
        Text("Clef:")
        Text(vm.currentClef == .treble ? "Treble" : "Bass")
        Text("Note:")
        Text(vm.currentNote.name).monospaced() //ToDo look for this note with midiKit
        Text("MIDI:")
        Text(String(vm.currentNote.midi)).monospaced()
      }

      // Button to get a new random note on a random clef (only one clef at a time)
      Button("New Note") {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.1)) {
          vm.randomizeNote()
        }
      }
      .buttonStyle(.borderedProminent)
    }
    .onAppear { vm.randomizeNote() }
    .padding()
  }
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
