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

  
    var body: some View {
      VStack {
        HStack {
          Canvas{ context, size in
            context.draw(trebleStaff, at: CGPoint(x: 155, y: 150))
            context.draw(bassStaff, at: CGPoint(x: 155, y: 220))

            func drawAtX(_ x: CGFloat, _ text: Text, y: CGFloat) {
              context.draw(text, at: CGPoint(x: x, y: y))
              
            }

            drawAtX(sharedX, sextLine, y: sextLineY)
            drawAtX(sharedX, sevenLine, y: sevenLineY)
            drawAtX(sharedX, eightLine, y: eightLineY)
            drawAtX(sharedX, nineLine, y: nineLineY)
            drawAtX(noteX, wholeNote, y: C8noteY)
           }
        }
      }

        .padding()
    }
}

#Preview {
    ContentView()
}

