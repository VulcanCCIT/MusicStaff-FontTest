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
  case singleLine
  case doubleLine
  case tripleLine
  case quadLine
  case quinLine
  case sextLine
  case sevenLine
  case eightLine
  case nineLine
  case wholeNote
  case halfNoteUP
  case halfNoteDown
  case quarterNoteUP
  case quarterNoteDown
  

  var codepoint: String {
    switch self {
      case .trebleStaff:
        return "\u{0054}\u{0043}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}"
      case .bassStaff:
        return "\u{0042}\u{0043}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}\u{004C}"
      case .singleLine:
        return "\u{E016}"
      case .doubleLine:
        return "\u{E017}"
      case .tripleLine:
        return "\u{E018}"
      case .quadLine:
        return "\u{E019}"
      case .quinLine:
        return "\u{E01A}"
      case .sextLine:
        return "\u{E01B}"
      case .sevenLine:
        return "\u{E016}"
      case .eightLine:
        return "\u{E016}"
      case .nineLine:
        return "\u{E016}"
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
        
  }
  }

  var fontName: String {
    switch self {
      case .bassStaff, .trebleStaff:
      return "MusGlyphs"
      case .singleLine, .doubleLine, .tripleLine, .quadLine, .quinLine, .sextLine, .sevenLine, .eightLine, .nineLine, .wholeNote, .halfNoteUP, .halfNoteDown, .quarterNoteUP, .quarterNoteDown:
      return "Bravura"
    }
  }

  var defaultSize: CGFloat {
    switch self {
      case .bassStaff, .trebleStaff:
      return 70 //was 60
    case .singleLine:
      return 30
      case .wholeNote, .doubleLine, .tripleLine, .quadLine, .quinLine, .sextLine, .sevenLine, .eightLine, .nineLine, .halfNoteUP, .halfNoteDown, .quarterNoteUP, .quarterNoteDown:
      return 40
    }
  }

  func text(size: CGFloat? = nil) -> Text {
    Text(codepoint).font(.custom(fontName, size: size ?? defaultSize))
  }
}
