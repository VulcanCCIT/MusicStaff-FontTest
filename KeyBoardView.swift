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
  
  @State private var pressedCorrectness: [Int: Bool] = [:] // midi -> was-correct at noteOn
  
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
  var isCorrect: (Int) -> Bool = { _ in false }
  var docked: Bool = false

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
      // Build a musical name (e.g., A3, D6) using the existing helper
      let name = noteName(from: midi)
      // Only label natural notes on white keys to avoid clutter
      return name.contains("#") ? "" : name
  }
  
  var body: some View {
    HStack {
      VStack {
        
        // Full-width control panel above the keyboard (knobs and meter)
        ZStack {
          HStack(alignment: .center, spacing: 24) {
            KnobImage()
            KnobImage()
            Spacer()
            
            HStack(spacing: 24) {
              KnobImage()
              KnobImage()
            }
            .overlay(alignment: .top) {
              Image("redled2")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 30, height: 30)
                .offset(x: 0, y: -12) // Centered between the two knobs
                .accessibilityHidden(true)
            }
          }
        }
        .overlay(alignment: .center) {
          NodeOutputView(conductor.instrument, color: .red)
            .frame(height: 42)
            .frame(width: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(GlassReflection(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .padding(.vertical, 8) //3DPanel Padding
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
          Panel3DBackground()
        )
        .padding(.horizontal)
        .padding(.bottom, 8) // Add gap between control panel and piano rail
        
        // Piano rail separator tying panel and keyboard together
        PianoRail()
          .frame(height: 14)
          .padding(.horizontal, 22)
          .padding(.top, -8)
          .padding(.bottom, 8)

        // 3D Keyboard View
        GeometryReader { proxy in
          let whiteCount = max(1, (lowNote...highNote).filter { ![1,3,6,8,10].contains($0 % 12) }.count)
          let keyWidth = proxy.size.width / CGFloat(whiteCount)
          let lengthFactor: CGFloat = 5.6
          let idealHeight = keyWidth * lengthFactor
          
          // Platform-specific and docked-mode-aware height calculation
          #if os(macOS)
          let responsiveHeight = idealHeight.clamped(to: 170...350)
          #else
          // iPad needs much smaller keyboard when docked to avoid clipping
          let dockedScaleFactor: CGFloat = docked ? 0.65 : 1.0 // 35% smaller when docked
          let scaledIdealHeight = idealHeight * dockedScaleFactor
          let responsiveHeight = scaledIdealHeight.clamped(to: 120...180)
          #endif
          
          ZStack {
            Keyboard3DView(
              lowNote: lowNote,
              highNote: highNote,
              conductor: conductor,
              isCorrect: isCorrect,
              pressedCorrectness: $pressedCorrectness,
              externalVelocities: $externalVelocities,
              scientificLabel: scientificLabel,
              showHints: appData.showHints
            )
            .frame(height: responsiveHeight)
          }
          .padding(.horizontal, 8) // thinner left/right bezel
          .padding(.bottom, 10)
          .background(
            // Add the same styled background
            ZStack {
              // Unified chassis color to match the top panel
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color("MeterPanelColor"))

              // Subtle vertical sheen similar to Panel3DBackground
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .blendMode(.softLight)

              // Add subtle purple tint to match design language (reduced intensity) 
              RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.purple.opacity(0.04), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                .blendMode(.plusLighter)
            }
          )
          .overlay(
            // Edge highlight
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
              .blendMode(.overlay)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1
              )
              .blendMode(.screen)
              .opacity(0.9)
          )
          .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 6)
          .frame(height: responsiveHeight)
        }
        #if os(macOS)
        .frame(minHeight: 170)
        #else
        .frame(minHeight: docked ? 120 : 140, maxHeight: docked ? 180 : 220) // Much smaller when docked on iPad
        #endif
        #if os(macOS)
        .padding(.bottom, docked ? 0 : 40)
        #else
        // iPad bottom padding for comfortable spacing
        .padding(.bottom, docked ? 38 : 40)
        #endif
      }
      .background(
        docked ? Color.clear : (colorScheme == .dark ? Color.clear : Color("MeterPanelColor"))
      )
      .overlay(alignment: .top) {
          if docked {
              Rectangle()
                  .fill(Color.black.opacity(0.15))
                  .frame(height: 1)
          }
      }
      #if os(iOS)
      // Critical: Add safe area padding at the bottom on iPad to prevent clipping
      .safeAreaPadding(.bottom, docked ? 140 : 0) // Increased to 60 for comfortable spacing from iPad edge
      #endif
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
          
          // CRITICAL FIX: Only set correctness if not already set (prevents race condition
          // where target note changes after correct answer, causing second evaluation to be wrong)
          if pressedCorrectness[note] == nil {
              let correctness = isCorrect(note)
              pressedCorrectness[note] = correctness
          }
      }
      .onReceive(conductor.noteOffSubject) { note in
          // Remove visual intensity; audio already triggered in conductor
          externalVelocities.removeValue(forKey: note)
          pressedCorrectness.removeValue(forKey: note)
      }
//    .background(
//      // Sophisticated background gradient behind everything
//      LinearGradient(
//        colors: [
//          Color(red: 0.12, green: 0.10, blue: 0.16), // Deep purple-gray at top
//          Color(red: 0.08, green: 0.08, blue: 0.12), // Darker blue-gray in middle
//          Color(red: 0.06, green: 0.06, blue: 0.10)  // Near black at bottom
//        ],
//        startPoint: .top,
//        endPoint: .bottom
//      )
//      .ignoresSafeArea(.all) // Fill entire canvas
//    )
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
      if UIImage(named: "Knob2") != nil {
        Image("Knob2")
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
    .frame(width: 38, height: 38)
    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    .accessibilityHidden(true)
  }
}

struct Panel3DBackground: View {
  var body: some View {
    GeometryReader { proxy in
      let corner: CGFloat = 18
      ZStack {
        // Base panel
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .fill(Color("MeterPanelColor"))

        // Subtle vertical sheen for a glassy/plastic look
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.10),
                .clear,
                Color.black.opacity(0.08)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .blendMode(.softLight)

        // Inner shadow (top) to suggest thickness
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
          .blur(radius: 2)
          .offset(y: 1)
          .mask(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
              .fill(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
          )

        // Top highlight edge
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
          .blendMode(.overlay)
        
        // Angled sheen and inner edge to suggest panel tilt
        GeometryReader { g in
          Canvas { context, size in
            let inset: CGFloat = max(10, size.height * 0.08)
            var trapezoid = Path()
            trapezoid.move(to: CGPoint(x: inset * 1.3, y: inset * 0.7))
            trapezoid.addLine(to: CGPoint(x: size.width - inset * 0.9, y: inset * 0.3))
            trapezoid.addLine(to: CGPoint(x: size.width - inset * 0.6, y: size.height - inset * 0.9))
            trapezoid.addLine(to: CGPoint(x: inset, y: size.height - inset * 0.6))
            trapezoid.closeSubpath()

            // Soft angled sheen across the panel
            context.fill(
              trapezoid,
              with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06), .clear]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
              )
            )

            // Inner shadow along the lower-right edge
            let innerEdge = trapezoid
            context.stroke(innerEdge, with: .color(Color.black.opacity(0.16)), lineWidth: 2)
          }
        }
        
        // Top-left sweep highlight
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(
            LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.2
          )
          .blendMode(.overlay)

        // Bottom-right sweep shadow
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(
            LinearGradient(colors: [.clear, Color.black.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 3
          )
          .opacity(0.8)
      }
      .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
  }
}

struct GlassReflection: View {
  let cornerRadius: CGFloat
  var body: some View {
    ZStack {
      // Top gloss
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .center
          )
        )
        .blendMode(.screen)

      // Edge highlight
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(
          LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
          lineWidth: 0.8
        )
        .blendMode(.overlay)
    }
  }
}

struct PianoRail: View {
    var body: some View {
      ZStack {
        // Base glossy black rail
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(LinearGradient(colors: [Color.black.opacity(0.95), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))

        // Top highlight
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
          .blendMode(.overlay)

        // Subtle inner glow hinting a purple tint from legacy design
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(LinearGradient(colors: [Color.purple.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
          .blendMode(.plusLighter)
      }
      .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
      .background(
        ChromeStanchions(upLength: 16, downLength: 24, barWidth: 8, spacing: 54)
          .padding(.vertical, -20) // let bars extend above and below the rail
      )
    }
  }

struct ChromeStanchions: View {
    var upLength: CGFloat = 14
    var downLength: CGFloat = 18
    var barWidth: CGFloat = 6
    var spacing: CGFloat = 44 // distance between the two center bars
    var edgeInset: CGFloat = 28 // inset from left/right edges for outer bars

    private func barPath(fill colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: barWidth/2, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: barWidth, height: upLength + downLength)
            .overlay(
                RoundedRectangle(cornerRadius: barWidth/2, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    var body: some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let leftCenterX = centerX - spacing/2
            let rightCenterX = centerX + spacing/2
            let outerLeftX = max(edgeInset, barWidth/2 + 2)
            let outerRightX = geo.size.width - max(edgeInset, barWidth/2 + 2)

            let chromeColors = [Color.white.opacity(0.85), Color(white: 0.7), Color(white: 0.45), Color(white: 0.85)]

            ZStack {
                // Outer left bar
                barPath(fill: chromeColors)
                    .position(x: outerLeftX, y: geo.size.height/2)

                // Inner left (centered pair)
                barPath(fill: chromeColors)
                    .position(x: leftCenterX, y: geo.size.height/2)

                // Inner right (centered pair)
                barPath(fill: chromeColors)
                    .position(x: rightCenterX, y: geo.size.height/2)

                // Outer right bar
                barPath(fill: chromeColors)
                    .position(x: outerRightX, y: geo.size.height/2)
            }
        }
        .allowsHitTesting(false)
    }
}

//#Preview {
//  let data = AppData()
//  data.minMIDINote = 24
//  data.maxMIDINote = 48
//  KeyBoardView()
//    .environmentObject(data)
//}

// MARK: - 3D Keyboard View
struct Keyboard3DView: View {
    let lowNote: Int
    let highNote: Int
    let conductor: MIDIMonitorConductor
    let isCorrect: (Int) -> Bool
    @Binding var pressedCorrectness: [Int: Bool]
    @Binding var externalVelocities: [Int: Double]
    let scientificLabel: (Pitch) -> String
    let showHints: Bool
    
    @Environment(\.colorScheme) var colorScheme
    @State private var keyPresses: Set<Int> = [] // active MIDI notes
    @State private var lastMidi: Int? = nil

    // Shared layout constants so drawing and hit-testing always match
// CHANGED here:
    private let backScale: CGFloat = 0.90              // Less aggressive perspective (changed from 0.80)
    private let caseHeight: CGFloat = 26               // changed from 36
    private let whiteFrontHeight: CGFloat = 24          // changed from 22
    private let blackFrontHeight: CGFloat = 12          // changed from 18
    private let blackKeyElevation: CGFloat = -8        // changed from -18
    
    // 3D appearance settings - realistic overhead perspective
    private let viewingAngle: Double = 35.0         // Degrees from horizontal
    private let keyboardDepth: CGFloat = 120.0      // Physical depth of keyboard in points
    private let whiteKeyHeight: CGFloat = 140.0     // White key length
    private let blackKeyHeight: CGFloat = 90.0      // Black key length  
    private let keyThickness: CGFloat = 2.0         // Key thickness for 3D effect

// CHANGED here: More dramatic perspective settings to match reference image
    private let vanishFactor: CGFloat = 0.15   // Strong perspective distortion for dramatic tapering
    private let tiltBias: CGFloat = 0.08       // More pronounced vertical tilt across back edge

    // Hit-testing / depth defaults
    private let whiteFrontGuardRatio: CGFloat = 0.10 // front 10% is always white-only for taps
    private let frontFaceReserveFactor: CGFloat = 0.28

    // Perspective transformation for more realistic "sitting in front of keyboard" view
    private func backX(forFrontX x: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let centerX = totalWidth / 2
        let offsetFromCenter = x - centerX
        // Stronger convergence toward center for more dramatic perspective
        let tapered = centerX + offsetFromCenter * (1.0 - vanishFactor)
        return tapered
    }

    // Enhanced vertical transformation for realistic viewing angle
    private func backY(baseY: CGFloat, totalWidth: CGFloat, atFrontX x: CGFloat) -> CGFloat {
        let centerX = totalWidth / 2
        let distanceFromCenter = abs(x - centerX) / (totalWidth / 2) // 0.0 at center, 1.0 at edges
        
        // Add both tilt and "lift" effect - keyboard appears to lift away from viewer
        let tiltOffset = distanceFromCenter * tiltBias * 25 // Increased tilt scaling
        let liftOffset = 15.0 // Constant lift to make back edge appear higher
        
        return baseY - tiltOffset - liftOffset
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Changed from dark gradient background to clear
                Color.clear
                
                Canvas { context, size in
                    drawRealistic3DKeyboard(context: context, size: size)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newMidi = midiFromLocation(value.location, in: geometry.size)

                        // If finger moved to a different key, send noteOff for previous
                        if let prev = lastMidi, prev != newMidi {
                            if keyPresses.contains(prev) {
                                keyPresses.remove(prev)
                                conductor.simulateNoteOff(noteNumber: prev)
                            }
                        }

                        // Send noteOn if this key wasn't already active
                        if !keyPresses.contains(newMidi) {
                            keyPresses.insert(newMidi)
                            // Use the same layout math as drawing for consistent velocity mapping
                            let a: CGFloat = 0.20 / 0.72
                            let s = scaleFor(size: geometry.size)
                            let whiteFrontH = whiteFrontHeight * s
                            let preferredDepth = geometry.size.height // allow deeper keys; clamp below
                            let maxDepthByHeight = max(60, (geometry.size.height - whiteFrontH * frontFaceReserveFactor - 2) / (1 + a))
                            let keyDepth = min(preferredDepth, maxDepthByHeight)
                            let keyY = keyDepth * a
                            let clampedY = min(max(value.location.y, keyY), keyY + keyDepth)
                            let relative = (keyY + keyDepth - clampedY) / keyDepth
                            let norm = max(0.0, min(1.0, relative))
                            let curved = pow(norm, 0.5) // bias louder
                            let velocity = max(64, min(127, Int(curved * 127)))
                            conductor.simulateNoteOn(noteNumber: newMidi, velocity: velocity)
                        }

                        lastMidi = newMidi
                    }
                    .onEnded { value in
                        // Note off for the last touched key
                        if let prev = lastMidi {
                            conductor.simulateNoteOff(noteNumber: prev)
                        }
                        // Safety: turn off any remaining active notes we tracked
                        for note in keyPresses { conductor.simulateNoteOff(noteNumber: note) }
                        keyPresses.removeAll()
                        lastMidi = nil
                    }
            )
        }
        .frame(minWidth: 100, minHeight: 100)
    }
    
    private func drawRealistic3DKeyboard(context: GraphicsContext, size: CGSize) {
        let totalWidth = size.width
        let totalHeight = size.height

        let s = scaleFor(size: size)
        let whiteFrontH = whiteFrontHeight * s
        let blackFrontH = blackFrontHeight * s
        let caseH = caseHeight * s
        let elevation = blackKeyElevation * s
        // Shadow variables removed - no longer needed

        // Inserted bottom margin constant - platform specific to prevent clipping
        #if os(macOS)
        let bottomMargin = max(16, whiteFrontH * 1.25) // Mac reserve
        #else
        let bottomMargin = max(32, whiteFrontH * 1.5) // iPad needs more reserve to prevent clipping
        #endif

        // Enhanced perspective for "sitting at keyboard" viewing angle
        // Show more depth while still guaranteeing the white-key front faces are visible
        let a: CGFloat = 0.25 / 0.75 // Increased relationship between keyboardY and depth for more dramatic angle
        let preferredDepth = totalHeight // allow as much depth as available; clamp below prevents clipping
        let maxDepthByHeight = max(80, (totalHeight - whiteFrontH * frontFaceReserveFactor - bottomMargin - 2) / (1 + a))
        let keyboardDepth: CGFloat = min(preferredDepth, maxDepthByHeight)
        let keyboardY = keyboardDepth * a // This positions the back edge higher up

        // Keyboard case/background
        drawPerspectiveKeyboardCase(context: context, size: size, keyboardY: keyboardY, depth: keyboardDepth, caseHeight: caseH)

        // Removed under-panel shadow line as it was too prominent

        // Fill white key area with perspective gradient (keeps background tapered while keys stay rectangular)
        let backLeftX = backX(forFrontX: 0, totalWidth: totalWidth)
        let backRightX = backX(forFrontX: totalWidth, totalWidth: totalWidth)
        let backBaseY = keyboardY
        let backLeftY = backY(baseY: backBaseY, totalWidth: totalWidth, atFrontX: 0)
        let backRightY = backY(baseY: backBaseY, totalWidth: totalWidth, atFrontX: totalWidth)

        var whiteKeyArea = Path()
        whiteKeyArea.move(to: CGPoint(x: 0, y: keyboardY + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: totalWidth, y: keyboardY + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: backRightX, y: backRightY))
        whiteKeyArea.addLine(to: CGPoint(x: backLeftX, y: backLeftY))
        whiteKeyArea.closeSubpath()
        
        // Add perspective shadow overlay to enhance depth illusion
        var shadowOverlay = Path()
        shadowOverlay.move(to: CGPoint(x: 0, y: keyboardY + keyboardDepth))
        shadowOverlay.addLine(to: CGPoint(x: totalWidth, y: keyboardY + keyboardDepth))
        shadowOverlay.addLine(to: CGPoint(x: backRightX, y: backRightY))
        shadowOverlay.addLine(to: CGPoint(x: backLeftX, y: backLeftY))
        shadowOverlay.closeSubpath()
        
        let shadowGradient: GraphicsContext.Shading = .radialGradient(
            Gradient(colors: [Color.black.opacity(0.02), Color.black.opacity(0.08), Color.black.opacity(0.02)]),
            center: CGPoint(x: totalWidth/2, y: keyboardY + keyboardDepth/2),
            startRadius: 0,
            endRadius: totalWidth * 0.8
        )
        context.fill(shadowOverlay, with: shadowGradient)

        // Draw white keys first (back to front for proper layering)
        let whiteKeys = (lowNote...highNote).filter { !isBlackKey($0) }
        let blackKeys = (lowNote...highNote).filter { isBlackKey($0) }
        let keySpacing = totalWidth / CGFloat(max(1, whiteKeys.count))
        
        let bdr = blackDepthRatio(for: size)

        for (index, midi) in whiteKeys.enumerated() {
            let x = CGFloat(index) * keySpacing
            drawPerspective3DWhiteKey(
                context: context,
                midi: midi,
                x: x,
                width: keySpacing - 1.0, // Ensure there's always a gap between keys
                keyboardY: keyboardY,
                keyboardDepth: keyboardDepth,
                viewDistance: 200,
                whiteFrontHeight: whiteFrontH,
                totalWidth: totalWidth
            )
        }

        // Subtle separators on the top surface between white keys
        for index in 1..<whiteKeys.count {
            let x = CGFloat(index) * keySpacing - 0.25
            let frontPoint = CGPoint(x: x, y: keyboardY + keyboardDepth)
            let backXSep = backX(forFrontX: x, totalWidth: totalWidth)
            let backYSep = backY(baseY: keyboardY, totalWidth: totalWidth, atFrontX: x)
            var separator = Path()
            separator.move(to: frontPoint)
            separator.addLine(to: CGPoint(x: backXSep, y: backYSep))
            context.stroke(separator, with: .color(Color.black.opacity(0.06)), lineWidth: 0.35)
        }

        // Draw black keys on top with perspective
        for midi in blackKeys {
            if let whiteIndex = getBlackKeyPosition(midi: midi, whiteKeys: whiteKeys) {
                let baseX = CGFloat(whiteIndex) * keySpacing // left white key of the pair
                let blackWidth = keySpacing * 0.56
                let centerX = baseX + keySpacing              // center at the seam between the two white keys
                let x = centerX - blackWidth / 2             // left edge of the black key
                drawPerspective3DBlackKey(
                    context: context,
                    midi: midi,
                    x: x,
                    width: blackWidth,
                    keyboardY: keyboardY,
                    keyboardDepth: keyboardDepth,
                    viewDistance: 200,
                    blackFrontHeight: blackFrontH,
                    elevation: elevation,
                    blackDepthRatio: bdr,
                    totalWidth: totalWidth
                )
            }
        }

        // Draw grooves on the vertical faces between white keys (like the photo)
        // We draw these last so they sit on top of the front faces
        for index in 1..<whiteKeys.count {
            let x = CGFloat(index) * keySpacing
            let frontY = keyboardY + keyboardDepth
            let grooveHeight = whiteFrontH
            var groove = Path()
            groove.move(to: CGPoint(x: x, y: frontY))
            groove.addLine(to: CGPoint(x: x, y: frontY + grooveHeight))
            context.stroke(groove, with: .color(Color.black.opacity(0.32)), lineWidth: 0.6)
        }
    }
    
    private func drawPerspectiveKeyboardCase(context: GraphicsContext, size: CGSize, keyboardY: CGFloat, depth: CGFloat, caseHeight: CGFloat) {
        // Remove the dark keyboard case - make it transparent or very light
        // No case drawing needed
    }
    
    private func drawPerspective3DWhiteKey(
        context: GraphicsContext,
        midi: Int,
        x: CGFloat,
        width: CGFloat,
        keyboardY: CGFloat,
        keyboardDepth: CGFloat,
        viewDistance: CGFloat,
        whiteFrontHeight: CGFloat,
        totalWidth: CGFloat
    ) {
        let isPressed = conductor.activeNotes.contains(midi)
        let pressDepth: CGFloat = isPressed ? 10 : 0

        let keyStartY = keyboardY + pressDepth
        let keyEndY = keyboardY + keyboardDepth + pressDepth
        let keyHeight: CGFloat = whiteFrontHeight

        // Keep keys rectangular to avoid artifacts - only apply subtle scaling
        let keyScale = 1.0 - (abs(x + width/2 - totalWidth/2) / (totalWidth/2)) * 0.05 // 5% max scale variation
        let scaledWidth = width * keyScale
        let scaledX = x + (width - scaledWidth) / 2 // center the scaled key
        
        let xL = scaledX
        let xR = scaledX + scaledWidth
        let backXL = xL  // Keep keys rectangular
        let backXR = xR  // Keep keys rectangular  
        let backYL = keyStartY  // Keep keys rectangular
        let backYR = keyStartY  // Keep keys rectangular

        // State coloring (tint when pressed and correctness known)
        let persisted: Bool? = pressedCorrectness[midi]
        let effectiveCorrect: Bool = {
            if isPressed, let persisted {
                return persisted
            } else {
                return isCorrect(midi)
            }
        }()

        // Skip shadows for now - they're causing visual artifacts due to perspective distortion

        // Top surface (tapered) - improved shading
        var keyTop = Path()
        keyTop.move(to: CGPoint(x: xL, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: xR, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: backXR, y: backYR))
        keyTop.addLine(to: CGPoint(x: backXL, y: backYL))
        keyTop.closeSubpath()
        
        // More realistic white key top gradient - slightly warmer whites
        let topFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.99), Color(white: 0.96), Color(white: 0.92)]),
            startPoint: CGPoint(x: xL, y: keyEndY),
            endPoint: CGPoint(x: backXL, y: backYL)
        )
        
        if isPressed {
            let pressedColor: Color = effectiveCorrect ? .green : .red
            context.fill(keyTop, with: .color(pressedColor))
        } else {
            context.fill(keyTop, with: topFill)
        }

        // Front face - enhanced gradient for better 3D depth
        var keyFront = Path()
        keyFront.move(to: CGPoint(x: xL, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: xR, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: xR, y: keyEndY + keyHeight))
        keyFront.addLine(to: CGPoint(x: xL, y: keyEndY + keyHeight))
        keyFront.closeSubpath()
        
        // More dramatic front face gradient for better 3D appearance
        let frontFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.98), Color(white: 0.85), Color(white: 0.72), Color(white: 0.78)]),
            startPoint: CGPoint(x: xL, y: keyEndY),
            endPoint: CGPoint(x: xL, y: keyEndY + keyHeight)
        )
        context.fill(keyFront, with: frontFill)

        // Right side (tapered) - more realistic shading
        var keyRight = Path()
        keyRight.move(to: CGPoint(x: xR, y: keyEndY))
        keyRight.addLine(to: CGPoint(x: backXR, y: backYR))
        keyRight.addLine(to: CGPoint(x: backXR, y: backYR + keyHeight))
        keyRight.addLine(to: CGPoint(x: xR, y: keyEndY + keyHeight))
        keyRight.closeSubpath()
        
        // Darker side to show depth and dimension
        let sideFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.82), Color(white: 0.75), Color(white: 0.68)]),
            startPoint: CGPoint(x: xR, y: keyEndY),
            endPoint: CGPoint(x: backXR, y: backYR + keyHeight)
        )
        context.fill(keyRight, with: sideFill)

        // Subtle highlight on top - more realistic
        var highlight = Path()
        let inset: CGFloat = width * 0.12
        highlight.move(to: CGPoint(x: xL + inset, y: keyEndY - 1))
        highlight.addLine(to: CGPoint(x: xR - inset, y: keyEndY - 1))
        highlight.addLine(to: CGPoint(x: backXR - inset * 0.5, y: backYR - 1))
        highlight.addLine(to: CGPoint(x: backXL + inset * 0.5, y: backYL - 1))
        highlight.closeSubpath()
        if !isPressed {
            context.fill(highlight, with: .color(Color.white.opacity(0.15))) // More subtle
        }

        // More realistic outlines
        context.stroke(keyTop, with: .color(Color.black.opacity(0.08)), lineWidth: 0.4)
        context.stroke(keyFront, with: .color(Color.black.opacity(0.12)), lineWidth: 0.4)
        context.stroke(keyRight, with: .color(Color.black.opacity(0.10)), lineWidth: 0.3)

        // Note: front faces are guaranteed visible by depth clamp above
        // Label (only C's) - positioned fully above the shadow line with fixed offset
        let pitch = Pitch(intValue: midi)
        let label = scientificLabel(pitch)
        if !label.isEmpty && showHints {
            // Position 6 points above the top edge to clear the shadow line
            let labelPoint = CGPoint(x: xL + width/2, y: keyEndY - 6)
            // Scale font size based on key width to prevent labels from touching edges on 88-key keyboards
            let fontSize = min(12, width * 0.65) // Cap at 12pt but scale down for narrow keys
            // Calculate kerning based on key width - tighter spacing for narrower keys
            let kerning = width < 15 ? -1.5 : (width < 20 ? -1.0 : -0.5)
            let labelText = Text(label)
                .font(.system(size: fontSize, weight: .bold))
                .kerning(kerning) // Tighten character spacing, especially on narrow keys
                .foregroundColor(.black)
            context.draw(labelText, at: labelPoint)
        }
    }
    
    private func drawPerspective3DBlackKey(
        context: GraphicsContext,
        midi: Int,
        x: CGFloat,
        width: CGFloat,
        keyboardY: CGFloat,
        keyboardDepth: CGFloat,
        viewDistance: CGFloat,
        blackFrontHeight: CGFloat,
        elevation: CGFloat,
        blackDepthRatio: CGFloat,
        totalWidth: CGFloat
    ) {
        let isPressed = conductor.activeNotes.contains(midi)
        let pressDepth: CGFloat = isPressed ? 5 : 0

        let blackKeyDepth = keyboardDepth * blackDepthRatio
        let elevationOffset: CGFloat = elevation

        let keyStartY = keyboardY + elevationOffset + pressDepth
        let keyEndY = keyboardY + blackKeyDepth + elevationOffset + pressDepth
        let keyHeight: CGFloat = blackFrontHeight

        // Keep black keys rectangular to avoid artifacts - only apply subtle scaling  
        let keyScale = 1.0 - (abs(x + width/2 - totalWidth/2) / (totalWidth/2)) * 0.08 // Slightly more scaling for black keys
        let scaledWidth = width * keyScale
        let scaledX = x + (width - scaledWidth) / 2 // center the scaled key
        
        let xL = scaledX
        let xR = scaledX + scaledWidth
        let backXL = xL  // Keep keys rectangular
        let backXR = xR  // Keep keys rectangular
        let backYL = keyStartY  // Keep keys rectangular  
        let backYR = keyStartY  // Keep keys rectangular

        let persisted: Bool? = pressedCorrectness[midi]
        let effectiveCorrect: Bool = {
            if isPressed, let persisted {
                return persisted
            } else {
                return isCorrect(midi)
            }
        }()

        // Skip shadows for now - they're causing visual artifacts due to perspective distortion

        // Top - improved black key shading
        var keyTop = Path()
        keyTop.move(to: CGPoint(x: xL, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: xR, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: backXR, y: backYR))
        keyTop.addLine(to: CGPoint(x: backXL, y: backYL))
        keyTop.closeSubpath()
        
        // More realistic black key top - subtle gradient
        let topFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.15), Color(white: 0.08), Color(white: 0.05)]),
            startPoint: CGPoint(x: xL, y: keyEndY),
            endPoint: CGPoint(x: backXL, y: backYL)
        )
        
        if isPressed {
            let pressedColor: Color = effectiveCorrect ? .green : .red
            context.fill(keyTop, with: .color(pressedColor))
        } else {
            context.fill(keyTop, with: topFill)
        }

        // Front - enhanced black front face with better shading
        var keyFront = Path()
        keyFront.move(to: CGPoint(x: xL, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: xR, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: xR, y: keyEndY + keyHeight))
        keyFront.addLine(to: CGPoint(x: xL, y: keyEndY + keyHeight))
        keyFront.closeSubpath()
        
        // More dramatic black key front gradient for better 3D depth
        let frontFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.12), Color(white: 0.06), Color(white: 0.02), Color(white: 0.04)]),
            startPoint: CGPoint(x: xL, y: keyEndY),
            endPoint: CGPoint(x: xL, y: keyEndY + keyHeight)
        )
        context.fill(keyFront, with: frontFill)

        // Right side - darker for depth
        var keyRight = Path()
        keyRight.move(to: CGPoint(x: xR, y: keyEndY))
        keyRight.addLine(to: CGPoint(x: backXR, y: backYR))
        keyRight.addLine(to: CGPoint(x: backXR, y: backYR + keyHeight))
        keyRight.addLine(to: CGPoint(x: xR, y: keyEndY + keyHeight))
        keyRight.closeSubpath()
        
        let sideFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.05), Color(white: 0.02), Color(white: 0.01)]),
            startPoint: CGPoint(x: xR, y: keyEndY),
            endPoint: CGPoint(x: backXR, y: backYR + keyHeight)
        )
        context.fill(keyRight, with: sideFill)

        // Left side - also add left side for better definition
        var keyLeft = Path()
        keyLeft.move(to: CGPoint(x: xL, y: keyEndY))
        keyLeft.addLine(to: CGPoint(x: backXL, y: backYL))
        keyLeft.addLine(to: CGPoint(x: backXL, y: backYL + keyHeight))
        keyLeft.addLine(to: CGPoint(x: xL, y: keyEndY + keyHeight))
        keyLeft.closeSubpath()
        
        // Slightly lighter left side for subtle lighting difference
        let leftSideFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.06), Color(white: 0.03), Color(white: 0.02)]),
            startPoint: CGPoint(x: xL, y: keyEndY),
            endPoint: CGPoint(x: backXL, y: backYL + keyHeight)
        )
        context.fill(keyLeft, with: leftSideFill)

        // Subtle highlight when not pressed - more realistic
        if !isPressed {
            var highlight = Path()
            let highlightInset = width * 0.2
            highlight.move(to: CGPoint(x: xL + highlightInset, y: keyEndY - 1))
            highlight.addLine(to: CGPoint(x: xR - highlightInset, y: keyEndY - 1))
            highlight.addLine(to: CGPoint(x: backXR - highlightInset * 0.6, y: backYR - 1))
            highlight.addLine(to: CGPoint(x: backXL + highlightInset * 0.6, y: backYL - 1))
            highlight.closeSubpath()
            context.fill(highlight, with: .color(Color.white.opacity(0.04))) // More subtle
        }

        // More subtle outlines for realistic look
        context.stroke(keyTop, with: .color(Color.white.opacity(0.08)), lineWidth: 0.3)
        context.stroke(keyFront, with: .color(Color.white.opacity(0.06)), lineWidth: 0.3)
        context.stroke(keyRight, with: .color(Color.white.opacity(0.05)), lineWidth: 0.25)
        context.stroke(keyLeft, with: .color(Color.white.opacity(0.04)), lineWidth: 0.2)
    }
    
    private func getBlackKeyPosition(midi: Int, whiteKeys: [Int]) -> Int? {
        // Find which white key this black key should be positioned relative to
        let note = midi % 12
        let octave = midi / 12
        
        // Find the base note for this octave
        let baseC = octave * 12
        
        switch note {
        case 1: // C#
            if let cIndex = whiteKeys.firstIndex(where: { $0 == baseC }) {
                return cIndex
            }
        case 3: // D#
            if let dIndex = whiteKeys.firstIndex(where: { $0 == baseC + 2 }) {
                return dIndex
            }
        case 6: // F#
            if let fIndex = whiteKeys.firstIndex(where: { $0 == baseC + 5 }) {
                return fIndex
            }
        case 8: // G#
            if let gIndex = whiteKeys.firstIndex(where: { $0 == baseC + 7 }) {
                return gIndex
            }
        case 10: // A#
            if let aIndex = whiteKeys.firstIndex(where: { $0 == baseC + 9 }) {
                return aIndex
            }
        default:
            break
        }
        
        return nil
    }
    
    private func getBlackKeyOffset(midi: Int) -> CGFloat {
        // Position black keys correctly between white keys
        let note = midi % 12
        switch note {
        case 1: return 0.62  // C# - a touch left from center between C and D
        case 3: return 0.38  // D# - a touch right from center between D and E  
        case 6: return 0.62  // F#
        case 8: return 0.50  // G#
        case 10: return 0.38 // A#
        default: return 0.50
        }
    }
    
    private func midiFromLocation(_ location: CGPoint, in size: CGSize) -> Int {
        let whiteKeys = (lowNote...highNote).filter { !isBlackKey($0) }
        let keySpacing = size.width / CGFloat(max(1, whiteKeys.count))
        let blackWidth = keySpacing * 0.56
        
        let clampedX = min(max(location.x, 0), size.width - 0.0001)
        
        // Mirror the drawing proportions and compute keyboardY from depth so hit-testing matches visuals
        let a: CGFloat = 0.20 / 0.72
        let whiteFrontH = whiteFrontHeight * scaleFor(size: size)

        // Inserted bottom margin constant - platform specific
        #if os(macOS)
        let bottomMargin = max(16, whiteFrontH * 1.25) // Mac reserve
        #else
        let bottomMargin = max(32, whiteFrontH * 1.5) // iPad needs more reserve
        #endif

        let preferredDepth = size.height // allow deeper keys; clamp below
        let maxDepthByHeight = max(60, (size.height - whiteFrontH * frontFaceReserveFactor - bottomMargin - 2) / (1 + a))
        let keyboardDepth = min(preferredDepth, maxDepthByHeight)
        let keyboardY = keyboardDepth * a

        // White-only guard strip at the very front to avoid accidental black key hits
        let whiteOnlyGuardHeight = keyboardDepth * whiteFrontGuardRatio
        if location.y >= keyboardY + keyboardDepth - whiteOnlyGuardHeight {
            let keyIndex = Int(clampedX / keySpacing)
            let idx = min(max(keyIndex, 0), whiteKeys.count - 1)
            return whiteKeys[idx]
        }

        // Adjusted hitBlackDepth per instructions
        let blackKeyDepth = keyboardDepth * blackDepthRatio(for: size)
        let hitBlackDepth = blackKeyDepth * 1.05 + (scaleFor(size: size) * 10)
        
        let elevation = blackKeyElevation * scaleFor(size: size)
        let blackKeyStartY = keyboardY + elevation
        let blackKeyEndY = keyboardY + hitBlackDepth + elevation
        
        if location.y >= blackKeyStartY && location.y <= blackKeyEndY {
            let keyIndex = Int(clampedX / keySpacing)
            if keyIndex >= 0 && keyIndex < whiteKeys.count {
                let whiteKeyMidi = whiteKeys[keyIndex]

                // Check right-side black key above this white key (centered over the gap)
                let rightBlack = whiteKeyMidi + 1
                if isBlackKey(rightBlack) && rightBlack <= highNote {
                    let baseX = CGFloat(keyIndex) * keySpacing // left white key of the pair
                    let centerX = baseX + keySpacing              // center at the seam between the two white keys
                    let halfWidth = blackWidth / 2
                    if clampedX >= centerX - halfWidth && clampedX <= centerX + halfWidth { return rightBlack }
                }

                // Check left-side black key above the previous white key (centered over the gap)
                if keyIndex > 0 {
                    let leftWhite = whiteKeys[keyIndex - 1]
                    let leftBlack = leftWhite + 1
                    if isBlackKey(leftBlack) && leftBlack <= highNote {
                        let baseX = CGFloat(keyIndex - 1) * keySpacing // left white key of the pair
                        let centerX = baseX + keySpacing              // center at the seam between the two white keys
                        let halfWidth = blackWidth / 2
                        if clampedX >= centerX - halfWidth && clampedX <= centerX + halfWidth { return leftBlack }
                    }
                }
            }
        }
        
        let nearestIndex = min(max(Int(round(clampedX / keySpacing)), 0), whiteKeys.count - 1)

        // White keys
        let whiteKeyStartY = keyboardY
        let whiteKeyEndY = keyboardY + keyboardDepth
        if location.y >= whiteKeyStartY && location.y <= whiteKeyEndY {
            let keyIndex = Int(clampedX / keySpacing)
            if keyIndex >= 0 && keyIndex < whiteKeys.count { return whiteKeys[keyIndex] }
        }
        return whiteKeys[nearestIndex]
    }
    
    private func scaleFor(size: CGSize) -> CGFloat {
        // Designed around ~220pt height; clamp to keep proportions sane
        let baseline: CGFloat = 220
        let s = size.height / baseline
        return min(max(s, 0.6), 1.4)
    }
    
    private func blackDepthRatio(for size: CGSize) -> CGFloat {
        let s = scaleFor(size: size) // ~0.6 ... 1.4
        return 0.58 + 0.06 * min(max(s, 0.6), 1.0) // 0.58 ... 0.64
    }
    
    private func isBlackKey(_ midi: Int) -> Bool {
        let note = midi % 12
        return [1, 3, 6, 8, 10].contains(note) // C#, D#, F#, G#, A#
    }
    
    private func noteName(from midiNote: Int) -> String {
        guard (0...127).contains(midiNote) else { return "—" }
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let octave = (midiNote / 12) - 1
        return names[midiNote % 12] + String(octave)
    }
}

// MARK: - Comparable Extension
extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}

#Preview {
    let data = AppData()
    data.minMIDINote = 60
    data.maxMIDINote = 72
    return KeyBoardView(isCorrect: { midi in
        return midi == 64 // E4 is "correct"
    })
    .environmentObject(data)
    .environmentObject(MIDIMonitorConductor())
    .frame(height: 220)
}

#Preview("Docked Keyboard") {
    let data = AppData()
    data.minMIDINote = 60
    data.maxMIDINote = 72
    return VStack {
        Spacer()
        Text("Main Content Above")
            .padding()
    }
    .environmentObject(data)
    .environmentObject(MIDIMonitorConductor())
    .safeAreaInset(edge: .bottom) {
        KeyBoardView(isCorrect: { _ in false }, docked: true)
            .environmentObject(data)
            .environmentObject(MIDIMonitorConductor())
    }
}

