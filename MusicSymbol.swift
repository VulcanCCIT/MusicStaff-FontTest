//
//  MusicSymbol.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI

enum MusicSymbol {
  case trebleStaff
  case bassStaff
//  case singleLine
//  case doubleLine
//  case tripleLine
//  case quadLine
//  case quinLine
//  case sextLine
//  case sevenLine
//  case eightLine
//  case nineLine
  case wholeNote
  case halfNoteUP
  case halfNoteDown
  case quarterNoteUP
  case quarterNoteDown
  case sharpSymbol
  case naturalSymbol
  case flatSymbol
  case brace
  case barline
  

  var codepoint: String {
    switch self {
      case .trebleStaff:
        return "\u{0054}\u{0043}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}"
      case .bassStaff:
        return "\u{0042}\u{0043}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}"
      case .wholeNote:
      return "\u{E1D2}"
      case .halfNoteUP:
        return "\u{E1D3}"
      case .halfNoteDown:
        return "\u{E1D4}"
        case .quarterNoteUP:
        return "\u{E1D5}"
      case .quarterNoteDown:
        return "\u{E1D6}"
      case .flatSymbol:
        return "\u{E260}"
      case .naturalSymbol:
        return "\u{E261}"
      case .sharpSymbol:
        return "\u{E262}"
      case .brace:
        return "\u{E000}"
      case .barline:
        return "\u{E030}"
  }
  }

  var fontName: String {
    switch self {
      case .bassStaff, .trebleStaff:
      return "MusGlyphs"
      case .wholeNote, .halfNoteUP, .halfNoteDown, .quarterNoteUP, .quarterNoteDown, .flatSymbol, .naturalSymbol, .sharpSymbol, .brace, .barline:
      return "Bravura"
    }
  }

  var defaultSize: CGFloat {
    switch self {
      case .bassStaff, .trebleStaff:
      return 70 //was 60
      case .wholeNote, .halfNoteUP, .halfNoteDown, .quarterNoteUP, .quarterNoteDown, .flatSymbol, .naturalSymbol, .sharpSymbol:
      return 40
      case .brace:
      return 100 // Thinner base size
      case .barline:
      return 100 // Thinner base size
    }
  }

  func text(size: CGFloat? = nil) -> Text {
    Text(codepoint).font(.custom(fontName, size: size ?? defaultSize))
  }
}

