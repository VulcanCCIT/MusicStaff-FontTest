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
  @AppStorage("keyboardIs3DMode") private var is3DMode: Bool = false
  
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
      let octave = midi / 12 - 1  // MIDI 60 -> 4
      // Only label C keys; return empty for others
      return (midi % 12 == 0) ? "C\(octave)" : ""
  }
  
  var body: some View {
    HStack {
      VStack {
        
        // Full-width control panel above the keyboard (knobs, meter, and 3D toggle on one line)
        ZStack {
          HStack(alignment: .center, spacing: 24) {
            KnobImage()
            KnobImage()
            Spacer()
            
            // 3D Toggle Button - Enhanced visibility
            Button(action: {
              withAnimation(.easeInOut(duration: 0.3)) {
                is3DMode.toggle()
              }
            }) {
              HStack(spacing: 8) {
                Image(systemName: is3DMode ? "cube.fill" : "rectangle.fill")
                  .font(.system(size: 18, weight: .semibold))
                Text(is3DMode ? "3D" : "2D")
                  .font(.system(size: 16, weight: .semibold))
              }
              .foregroundColor(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(
                RoundedRectangle(cornerRadius: 10)
                  .fill(is3DMode ? 
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [.gray, .secondary], startPoint: .leading, endPoint: .trailing)
                  )
                  .shadow(color: is3DMode ? .blue.opacity(0.4) : .gray.opacity(0.3), radius: 4)
              )
            }
            .buttonStyle(.plain)
            
            ZStack(alignment: .topTrailing) {
              KnobImage()
              Image("redled2")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 36, height: 36)
                .offset(x: 22, y: -17)
                .accessibilityHidden(true)
            }
          }
        }
        .overlay(alignment: .center) {
          NodeOutputView(conductor.instrument, color: .red)
            .frame(height: 52)
            .frame(width: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(GlassReflection(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
          Panel3DBackground()
        )
        .padding(.horizontal)
        
        // Piano rail separator tying panel and keyboard together
        PianoRail(is3D: is3DMode)
          .frame(height: 14)
          .padding(.horizontal, 22)
          .padding(.top, -4)
          .padding(.bottom, 2)

        // Keyboard View (2D or 3D)
        GeometryReader { proxy in
          let whiteCount = max(1, (lowNote...highNote).filter { ![1,3,6,8,10].contains($0 % 12) }.count)
          let keyWidth = proxy.size.width / CGFloat(whiteCount)
          let lengthFactor: CGFloat = is3DMode ? 5.6 : 3.4
          let idealHeight = keyWidth * lengthFactor
          let responsiveHeight = is3DMode ? idealHeight.clamped(to: 170...350) : idealHeight.clamped(to: 170...320)
          let chassisCorner3D: CGFloat = {
              // Map height 170...320 -> radius 32...18 (clamped)
              let minH: CGFloat = 170
              let maxH: CGFloat = 320
              let minR: CGFloat = 32
              let maxR: CGFloat = 18
              let t = ((responsiveHeight - minH) / (maxH - minH)).clamped(to: 0...1)
              return (minR + (maxR - minR) * t).clamped(to: 18...32)
          }()
          
          if is3DMode {
            ZStack {
              Keyboard3DView(
                lowNote: lowNote,
                highNote: highNote,
                conductor: conductor,
                isCorrect: isCorrect,
                pressedCorrectness: $pressedCorrectness,
                externalVelocities: $externalVelocities,
                scientificLabel: scientificLabel
              )
              // Clip the 3D content so the border is visible and clean
              .clipShape(RoundedRectangle(cornerRadius: chassisCorner3D, style: .continuous))
              .frame(height: responsiveHeight)
            }
            .padding(.horizontal, 8) // thinner left/right bezel to match 2D
            .padding(.bottom, 10)
            .background(
              ZStack {
                // Unified chassis color to match the top panel (same as 2D)
                RoundedRectangle(cornerRadius: chassisCorner3D, style: .continuous)
                  .fill(Color("MeterPanelColor"))

                // Subtle vertical sheen similar to Panel3DBackground (same as 2D)
                RoundedRectangle(cornerRadius: chassisCorner3D, style: .continuous)
                  .fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                  .blendMode(.softLight)

                // Inner bottom lip for depth (same as 2D)
                VStack {
                  Spacer()
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 8)
                    .padding(.horizontal, 8)
                    .opacity(0.9)
                }
                .padding(.vertical, 6)
              }
            )
            .overlay(
              // Edge highlight (same as 2D)
              RoundedRectangle(cornerRadius: chassisCorner3D, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .blendMode(.overlay)
            )
            .overlay(
              RoundedRectangle(cornerRadius: chassisCorner3D, style: .continuous)
                .stroke(
                  LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                  lineWidth: 1
                )
                .blendMode(.screen)
                .opacity(0.9)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 6)
            .frame(height: responsiveHeight + 18)
          } else {
            ZStack {
              // Dark keybed background constrained to keyboard height
              KeybedBackground()
                .frame(height: responsiveHeight)
                .clipped()

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
                ZStack {
                  let midi = pitch.intValue
                  // Persist correctness from note-on until note-off so color doesn't flip while held
                  let persisted: Bool? = pressedCorrectness[midi]
                  let isActive = isActivated || externallyOn
                  let effectiveCorrect: Bool = {
                    if isActive, let persisted {
                      return persisted
                    } else {
                      return isCorrect(midi)
                    }
                  }()
                  let color: Color = effectiveCorrect ? .green : .red
                  
                  KeyboardKey(
                    pitch: pitch,
                    isActivated: isActivated || externallyOn,
                    text: scientificLabel(for: pitch),
                    pressedColor: color,
                    alignment: .bottom
                  )
                }
              }
            }
            .padding(.horizontal, 8) // thinner left/right bezel
            .padding(.bottom, 10)
            .background(
              ZStack {
                // Unified chassis color to match the top panel
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .fill(Color("MeterPanelColor"))

                // Subtle vertical sheen similar to Panel3DBackground
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                  .blendMode(.softLight)

                // Inner bottom lip for depth
                VStack {
                  Spacer()
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 8)
                    .padding(.horizontal, 8)
                    .opacity(0.9)
                }
                .padding(.vertical, 6)
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
            .frame(height: responsiveHeight + 18)
          }
        }
        .frame(minHeight: 170)
        .padding(.bottom, docked ? 0 : (is3DMode ? 40 : 28))
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
          pressedCorrectness[note] = isCorrect(note)
      }
      .onReceive(conductor.noteOffSubject) { note in
          // Remove visual intensity; audio already triggered in conductor
          externalVelocities.removeValue(forKey: note)
          pressedCorrectness.removeValue(forKey: note)
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

        // Bottom lip inside the panel (gives a recessed look for the keyboard slot)
        VStack {
          Spacer()
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.10)], startPoint: .top, endPoint: .bottom))
            .frame(height: max(6, proxy.size.height * 0.06))
            .padding(.horizontal, 8)
            .opacity(0.8)
        }
        .padding(.vertical, 6)
        
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
            var innerEdge = trapezoid
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
    var is3D: Bool = false
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
        ChromeStanchions(upLength: 16, downLength: is3D ? 26 : 20, barWidth: 8, spacing: 54)
          .padding(.vertical, is3D ? -12 : -8) // let bars extend above and below the rail
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

  struct KeybedBackground: View {
    var body: some View {
      GeometryReader { size in
        ZStack {
          // Backplate behind keys
          LinearGradient(colors: [Color.black, Color.black.opacity(0.92), Color.black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
          // Subtle top lip shadow right under the rail
          VStack(spacing: 0) {
            Rectangle()
              .fill(Color.black.opacity(0.70))
              .frame(height: 2)
            Rectangle()
              .fill(Color.white.opacity(0.04))
              .frame(height: 1)
            Spacer()
          }
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

// MARK: - 3D Keyboard View
struct Keyboard3DView: View {
    let lowNote: Int
    let highNote: Int
    let conductor: MIDIMonitorConductor
    let isCorrect: (Int) -> Bool
    @Binding var pressedCorrectness: [Int: Bool]
    @Binding var externalVelocities: [Int: Double]
    let scientificLabel: (Pitch) -> String
    
    @Environment(\.colorScheme) var colorScheme
    @State private var keyPresses: Set<Int> = [] // active MIDI notes
    @State private var lastMidi: Int? = nil

    // Shared layout constants so drawing and hit-testing always match
// CHANGED here:
    private let backScale: CGFloat = 0.80              // Back edge is 80% of front width (changed from 0.85)
    private let caseHeight: CGFloat = 26               // changed from 36
    private let whiteFrontHeight: CGFloat = 24          // changed from 22
    private let blackFrontHeight: CGFloat = 18          // changed from 16
    private let blackKeyElevation: CGFloat = -18        // changed from -14
    
    // 3D appearance settings - realistic overhead perspective
    private let viewingAngle: Double = 35.0         // Degrees from horizontal
    private let keyboardDepth: CGFloat = 120.0      // Physical depth of keyboard in points
    private let whiteKeyHeight: CGFloat = 140.0     // White key length
    private let blackKeyHeight: CGFloat = 90.0      // Black key length  
    private let keyThickness: CGFloat = 2.0         // Key thickness for 3D effect

    // Hit-testing / depth defaults
    private let whiteFrontGuardRatio: CGFloat = 0.10 // front 10% is always white-only for taps
    private let frontFaceReserveFactor: CGFloat = 0.28
    // Removed: private let blackKeyDepthRatio: CGFloat = 0.76

    private func scaleFor(size: CGSize) -> CGFloat {
        // Designed around ~220pt height; clamp to keep proportions sane
        let baseline: CGFloat = 220
        let s = size.height / baseline
        return min(max(s, 0.6), 1.4)
    }
    
    private func blackDepthRatio(for size: CGSize) -> CGFloat {
        let s = scaleFor(size: size) // ~0.6 ... 1.4
        return 0.62 + 0.06 * min(max(s, 0.6), 1.0) // 0.62 ... 0.68
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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Much darker background for dramatic contrast
                LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.85), Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
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
        let whiteShadowOffset = 8 * s
        let blackShadowOffset = 9 * s

        // Inserted bottom margin constant
        let bottomMargin = max(16, whiteFrontH * 1.25) // larger reserve so front faces never clip

        // Subtle perspective and placement similar to the reference photo
        // Show more depth while still guaranteeing the white-key front faces are visible
        let a: CGFloat = 0.20 / 0.72 // relationship between keyboardY and depth
        let preferredDepth = totalHeight // allow as much depth as available; clamp below prevents clipping
        let maxDepthByHeight = max(60, (totalHeight - whiteFrontH * frontFaceReserveFactor - bottomMargin - 2) / (1 + a))
        let keyboardDepth: CGFloat = min(preferredDepth, maxDepthByHeight)

        // Keyboard case/background
        drawPerspectiveKeyboardCase(context: context, size: size, keyboardY: keyboardDepth * 0.20 / 0.72, depth: keyboardDepth, caseHeight: caseH)

        // Under-panel shadow to increase overhang
// CHANGED here:
        var underShadow = Path()
        underShadow.move(to: CGPoint(x: 0, y: keyboardDepth * 0.20 / 0.72 + keyboardDepth + caseH * 0.02))
        underShadow.addLine(to: CGPoint(x: totalWidth, y: keyboardDepth * 0.20 / 0.72 + keyboardDepth + caseH * 0.02))
        context.stroke(underShadow, with: .color(Color.black.opacity(0.45)), lineWidth: max(1.5, caseH * 0.10))

        // Fill white key area to avoid gaps (uses the backScale constant)
        let backWidth = totalWidth * backScale
        let backXOffset = (totalWidth - backWidth) / 2

        var whiteKeyArea = Path()
        whiteKeyArea.move(to: CGPoint(x: 0, y: keyboardDepth * 0.20 / 0.72 + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: totalWidth, y: keyboardDepth * 0.20 / 0.72 + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: backXOffset + backWidth, y: keyboardDepth * 0.20 / 0.72))
        whiteKeyArea.addLine(to: CGPoint(x: backXOffset, y: keyboardDepth * 0.20 / 0.72))
        whiteKeyArea.closeSubpath()
        context.fill(whiteKeyArea, with: .color(Color.white))

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
                width: keySpacing - 0.5,
                keyboardY: keyboardDepth * 0.20 / 0.72,
                keyboardDepth: keyboardDepth,
                viewDistance: 200,
                whiteFrontHeight: whiteFrontH,
                shadowOffset: whiteShadowOffset
            )
        }

        // Subtle separators on the top surface between white keys
        for index in 1..<whiteKeys.count {
            let x = CGFloat(index) * keySpacing - 0.25
            let frontPoint = CGPoint(x: x, y: keyboardDepth * 0.20 / 0.72 + keyboardDepth)
            let backRatio = (x - backXOffset) / totalWidth
            let backX = backXOffset + backWidth * backRatio
            let backPoint = CGPoint(x: backX, y: keyboardDepth * 0.20 / 0.72)
            var separator = Path()
            separator.move(to: frontPoint)
            separator.addLine(to: backPoint)
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
                    keyboardY: keyboardDepth * 0.20 / 0.72,
                    keyboardDepth: keyboardDepth,
                    viewDistance: 200,
                    blackFrontHeight: blackFrontH,
                    elevation: elevation,
                    blackDepthRatio: bdr,
                    shadowOffset: blackShadowOffset
                )
            }
        }

        // Draw grooves on the vertical faces between white keys (like the photo)
        // We draw these last so they sit on top of the front faces
        for index in 1..<whiteKeys.count {
            let x = CGFloat(index) * keySpacing
            let frontY = keyboardDepth * 0.20 / 0.72 + keyboardDepth
            let grooveHeight = whiteFrontH
            var groove = Path()
            groove.move(to: CGPoint(x: x, y: frontY))
            groove.addLine(to: CGPoint(x: x, y: frontY + grooveHeight))
            context.stroke(groove, with: .color(Color.black.opacity(0.32)), lineWidth: 0.6)
        }
    }
    
    private func drawPerspectiveKeyboardCase(context: GraphicsContext, size: CGSize, keyboardY: CGFloat, depth: CGFloat, caseHeight: CGFloat) {
        let caseColor = Color.black

        let backWidth = size.width * backScale
        let backXOffset = (size.width - backWidth) / 2

        // Main case body
        var caseBody = Path()
        caseBody.move(to: CGPoint(x: 0, y: keyboardY + depth))
        caseBody.addLine(to: CGPoint(x: size.width, y: keyboardY + depth))
        caseBody.addLine(to: CGPoint(x: backXOffset + backWidth, y: keyboardY))
        caseBody.addLine(to: CGPoint(x: backXOffset, y: keyboardY))
        caseBody.closeSubpath()
        context.fill(caseBody, with: .color(caseColor))

        // Rim
        var caseFrame = Path()
        caseFrame.move(to: CGPoint(x: 0, y: keyboardY + depth + caseHeight))
        caseFrame.addLine(to: CGPoint(x: size.width, y: keyboardY + depth + caseHeight))
        caseFrame.addLine(to: CGPoint(x: backXOffset + backWidth, y: keyboardY + caseHeight))
        caseFrame.addLine(to: CGPoint(x: backXOffset, y: keyboardY + caseHeight))
        caseFrame.closeSubpath()
        context.fill(caseFrame, with: .linearGradient(
            Gradient(colors: [Color(red: 0.18, green: 0.18, blue: 0.18), Color(red: 0.10, green: 0.10, blue: 0.10)]),
            startPoint: CGPoint(x: 0, y: keyboardY + depth + caseHeight),
            endPoint: CGPoint(x: 0, y: keyboardY + caseHeight)
        ))

        // Thin gap shadow to separate panel from keys
        var gap = Path()
        gap.move(to: CGPoint(x: 0, y: keyboardY + depth + caseHeight + 1))
        gap.addLine(to: CGPoint(x: size.width, y: keyboardY + depth + caseHeight + 1))
        context.stroke(gap, with: .color(Color.black.opacity(0.35)), lineWidth: 1)

        // Sides
        var leftSide = Path()
        leftSide.move(to: CGPoint(x: 0, y: keyboardY + depth))
        leftSide.addLine(to: CGPoint(x: backXOffset, y: keyboardY))
        leftSide.addLine(to: CGPoint(x: backXOffset, y: keyboardY + caseHeight))
        leftSide.addLine(to: CGPoint(x: 0, y: keyboardY + depth + caseHeight))
        leftSide.closeSubpath()

        var rightSide = Path()
        rightSide.move(to: CGPoint(x: size.width, y: keyboardY + depth))
        rightSide.addLine(to: CGPoint(x: backXOffset + backWidth, y: keyboardY))
        rightSide.addLine(to: CGPoint(x: backXOffset + backWidth, y: keyboardY + caseHeight))
        rightSide.addLine(to: CGPoint(x: size.width, y: keyboardY + depth + caseHeight))
        rightSide.closeSubpath()

        context.fill(leftSide, with: .color(Color(red: 0.12, green: 0.12, blue: 0.12)))
        context.fill(rightSide, with: .color(Color(red: 0.08, green: 0.08, blue: 0.08)))

        // Corner vignettes for perspective
        var leftVignette = Path()
        leftVignette.addRoundedRect(in: CGRect(x: 0, y: keyboardY + depth, width: max(24, size.width * 0.04), height: caseHeight + 8), cornerSize: CGSize(width: 12, height: 12))
        context.fill(leftVignette, with: .linearGradient(
          Gradient(colors: [Color.black.opacity(0.18), .clear]),
          startPoint: CGPoint(x: 0, y: keyboardY + depth + caseHeight/2),
          endPoint: CGPoint(x: max(24, size.width * 0.04), y: keyboardY + depth + caseHeight/2)
        ))

        var rightVignette = Path()
        rightVignette.addRoundedRect(in: CGRect(x: size.width - max(24, size.width * 0.04), y: keyboardY + depth, width: max(24, size.width * 0.04), height: caseHeight + 8), cornerSize: CGSize(width: 12, height: 12))
        context.fill(rightVignette, with: .linearGradient(
          Gradient(colors: [.clear, Color.black.opacity(0.18)]),
          startPoint: CGPoint(x: size.width - max(24, size.width * 0.04), y: keyboardY + depth + caseHeight/2),
          endPoint: CGPoint(x: size.width, y: keyboardY + depth + caseHeight/2)
        ))
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
        shadowOffset: CGFloat
    ) {
        let isPressed = conductor.activeNotes.contains(midi)
        let pressDepth: CGFloat = isPressed ? 10 : 0

        // Subtle perspective
        let backWidth = width * backScale
        let backXOffset = (width - backWidth) / 2

        let keyStartY = keyboardY + pressDepth
        let keyEndY = keyboardY + keyboardDepth + pressDepth
        let keyHeight: CGFloat = whiteFrontHeight

        // State coloring (tint when pressed and correctness known)
        let persisted: Bool? = pressedCorrectness[midi]
        let effectiveCorrect: Bool = {
            if isPressed, let persisted { return persisted } else { return isCorrect(midi) }
        }()

        // Base colors
        let baseWhiteTop = Color(white: 0.98)
        let baseWhiteFront = Color(white: 0.86)
        let baseWhiteSide = Color(white: 0.80)

        // Removed tintTop, tintFront, tintSide declarations
        
        // Shadows
        var shadow = Path()
        shadow.move(to: CGPoint(x: x + shadowOffset, y: keyEndY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + width + shadowOffset, y: keyEndY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + backXOffset + backWidth + shadowOffset, y: keyStartY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + backXOffset + shadowOffset, y: keyStartY + keyHeight + shadowOffset))
        shadow.closeSubpath()
        context.fill(shadow, with: .color(Color.black.opacity(0.35)))

        // Top surface
        var keyTop = Path()
        keyTop.move(to: CGPoint(x: x, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: x + width, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY))
        keyTop.addLine(to: CGPoint(x: x + backXOffset, y: keyStartY))
        keyTop.closeSubpath()
        let topFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [baseWhiteTop, Color(white: 0.92)]),
            startPoint: CGPoint(x: x, y: keyEndY),
            endPoint: CGPoint(x: x, y: keyStartY)
        )
        if isPressed {
            let pressedColor: Color = effectiveCorrect ? .green : .red
            context.fill(keyTop, with: .color(pressedColor))
        } else {
            context.fill(keyTop, with: topFill)
        }

        // Front face
        var keyFront = Path()
        keyFront.move(to: CGPoint(x: x, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: x + width, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: x + width, y: keyEndY + keyHeight))
        keyFront.addLine(to: CGPoint(x: x, y: keyEndY + keyHeight))
        keyFront.closeSubpath()
        let frontFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [baseWhiteFront, Color(white: 0.72)]),
            startPoint: CGPoint(x: x, y: keyEndY),
            endPoint: CGPoint(x: x, y: keyEndY + keyHeight)
        )
        context.fill(keyFront, with: frontFill)
        // Removed tintFront fill line here

        // Right side
        var keyRight = Path()
        keyRight.move(to: CGPoint(x: x + width, y: keyEndY))
        keyRight.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY))
        keyRight.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY + keyHeight))
        keyRight.addLine(to: CGPoint(x: x + width, y: keyEndY + keyHeight))
        keyRight.closeSubpath()
        let sideFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [baseWhiteSide, Color(white: 0.70)]),
            startPoint: CGPoint(x: x + width, y: keyEndY),
            endPoint: CGPoint(x: x + backXOffset + backWidth, y: keyStartY + keyHeight)
        )
        context.fill(keyRight, with: sideFill)
        // Removed tintSide fill line here

        // Subtle highlight on top
        var highlight = Path()
        let inset: CGFloat = width * 0.08
        highlight.move(to: CGPoint(x: x + inset, y: keyEndY - 2))
        highlight.addLine(to: CGPoint(x: x + width - inset, y: keyEndY - 2))
        highlight.addLine(to: CGPoint(x: x + backXOffset + backWidth - inset/3, y: keyStartY - 2))
        highlight.addLine(to: CGPoint(x: x + backXOffset + inset/3, y: keyStartY - 2))
        highlight.closeSubpath()
        if !isPressed {
            context.fill(highlight, with: .color(Color.white.opacity(0.25)))
        }

        // Outlines
        context.stroke(keyTop, with: .color(Color.black.opacity(0.12)), lineWidth: 0.5)
        context.stroke(keyFront, with: .color(Color.black.opacity(0.18)), lineWidth: 0.5)
        context.stroke(keyRight, with: .color(Color.black.opacity(0.15)), lineWidth: 0.5)

        // Note: front faces are guaranteed visible by depth clamp above
        // Label (only C's)
        let pitch = Pitch(intValue: midi)
        let label = scientificLabel(pitch)
        if !label.isEmpty {
            let labelPoint = CGPoint(x: x + width/2, y: keyEndY - 16)
            let labelText = Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.secondary)
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
        shadowOffset: CGFloat
    ) {
        let isPressed = conductor.activeNotes.contains(midi)
        let pressDepth: CGFloat = isPressed ? 7 : 0

        let blackKeyDepth = keyboardDepth * blackDepthRatio
        let elevationOffset: CGFloat = elevation

        let backWidth = width * backScale
        let backXOffset = (width - backWidth) / 2

        let keyStartY = keyboardY + elevationOffset + pressDepth
        let keyEndY = keyboardY + blackKeyDepth + elevationOffset + pressDepth
        let keyHeight: CGFloat = blackFrontHeight

        let persisted: Bool? = pressedCorrectness[midi]
        let effectiveCorrect: Bool = {
            if isPressed, let persisted { return persisted } else { return isCorrect(midi) }
        }()

        // Base blacks
        let topBase = Color(white: 0.10)
        let sideBase = Color(white: 0.06)
        let frontBase = Color(white: 0.04)

        // Removed tintTop, tintSide, tintFront declarations

        // Shadow
        var shadow = Path()
        shadow.move(to: CGPoint(x: x + shadowOffset, y: keyEndY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + width + shadowOffset, y: keyEndY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + backXOffset + backWidth + shadowOffset, y: keyStartY + keyHeight + shadowOffset))
        shadow.addLine(to: CGPoint(x: x + backXOffset + shadowOffset, y: keyStartY + keyHeight + shadowOffset))
        shadow.closeSubpath()
        context.fill(shadow, with: .color(Color.black.opacity(0.55)))

        // Top
        var keyTop = Path()
        keyTop.move(to: CGPoint(x: x, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: x + width, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY))
        keyTop.addLine(to: CGPoint(x: x + backXOffset, y: keyStartY))
        keyTop.closeSubpath()
        let topFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [Color(white: 0.18), topBase]),
            startPoint: CGPoint(x: x, y: keyEndY),
            endPoint: CGPoint(x: x, y: keyStartY)
        )
        if isPressed {
            let pressedColor: Color = effectiveCorrect ? .green : .red
            context.fill(keyTop, with: .color(pressedColor))
        } else {
            context.fill(keyTop, with: topFill)
        }

        // Front
        var keyFront = Path()
        keyFront.move(to: CGPoint(x: x, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: x + width, y: keyEndY))
        keyFront.addLine(to: CGPoint(x: x + width, y: keyEndY + keyHeight))
        keyFront.addLine(to: CGPoint(x: x, y: keyEndY + keyHeight))
        keyFront.closeSubpath()
        let frontFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [frontBase, Color(white: 0.02)]),
            startPoint: CGPoint(x: x, y: keyEndY),
            endPoint: CGPoint(x: x, y: keyEndY + keyHeight)
        )
        context.fill(keyFront, with: frontFill)
        // Removed tintFront fill line here

        // Right side
        var keyRight = Path()
        keyRight.move(to: CGPoint(x: x + width, y: keyEndY))
        keyRight.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY))
        keyRight.addLine(to: CGPoint(x: x + backXOffset + backWidth, y: keyStartY + keyHeight))
        keyRight.addLine(to: CGPoint(x: x + width, y: keyEndY + keyHeight))
        keyRight.closeSubpath()
        let sideFill: GraphicsContext.Shading = .linearGradient(
            Gradient(colors: [sideBase, Color(white: 0.03)]),
            startPoint: CGPoint(x: x + width, y: keyEndY),
            endPoint: CGPoint(x: x + backXOffset + backWidth, y: keyStartY + keyHeight)
        )
        context.fill(keyRight, with: sideFill)
        // Removed tintSide fill line here

        // Left side
        var keyLeft = Path()
        keyLeft.move(to: CGPoint(x: x, y: keyEndY))
        keyLeft.addLine(to: CGPoint(x: x + backXOffset, y: keyStartY))
        keyLeft.addLine(to: CGPoint(x: x + backXOffset, y: keyStartY + keyHeight))
        keyLeft.addLine(to: CGPoint(x: x, y: keyEndY + keyHeight))
        keyLeft.closeSubpath()
        context.fill(keyLeft, with: sideFill)

        // Soft highlight when not pressed
        if !isPressed {
            var highlight = Path()
            highlight.move(to: CGPoint(x: x + width * 0.15, y: keyEndY - 1.5))
            highlight.addLine(to: CGPoint(x: x + width * 0.85, y: keyEndY - 1.5))
            highlight.addLine(to: CGPoint(x: x + backXOffset + backWidth * 0.85, y: keyStartY - 1.5))
            highlight.addLine(to: CGPoint(x: x + backXOffset + backWidth * 0.15, y: keyStartY - 1.5))
            highlight.closeSubpath()
            context.fill(highlight, with: .color(Color.white.opacity(0.06)))
        }

        // Outlines
        context.stroke(keyTop, with: .color(Color.white.opacity(0.18)), lineWidth: 0.4)
        context.stroke(keyFront, with: .color(Color.white.opacity(0.14)), lineWidth: 0.4)
        context.stroke(keyRight, with: .color(Color.white.opacity(0.12)), lineWidth: 0.4)
        context.stroke(keyLeft, with: .color(Color.white.opacity(0.10)), lineWidth: 0.3)
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

        // Inserted bottom margin constant
        let bottomMargin = max(16, whiteFrontH * 1.25)

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

// REPLACED BLOCK START
//                // Check right-side black key above this white key
//                let rightBlack = whiteKeyMidi + 1
//                if isBlackKey(rightBlack) && rightBlack <= highNote {
//                    let baseX = CGFloat(keyIndex) * keySpacing
//                    let offsetX = getBlackKeyOffset(midi: rightBlack)
//                    let bx = baseX + offsetX * keySpacing - keySpacing * 0.3
//                    let bxRight = bx + blackWidth * 1.14
//                    if clampedX >= bx - blackWidth * 0.14 && clampedX <= bxRight { return rightBlack }
//                }
                // Check right-side black key above this white key (centered over the gap)
                let rightBlack = whiteKeyMidi + 1
                if isBlackKey(rightBlack) && rightBlack <= highNote {
                    let baseX = CGFloat(keyIndex) * keySpacing // left white key of the pair
                    let centerX = baseX + keySpacing              // center at the seam between the two white keys
                    let halfWidth = blackWidth / 2
                    if clampedX >= centerX - halfWidth && clampedX <= centerX + halfWidth { return rightBlack }
                }
// REPLACED BLOCK END

// REPLACED BLOCK START
//                // Check left-side black key above the previous white key
//                if keyIndex > 0 {
//                    let leftWhite = whiteKeys[keyIndex - 1]
//                    let leftBlack = leftWhite + 1
//                    if isBlackKey(leftBlack) && leftBlack <= highNote {
//                        let baseX = CGFloat(keyIndex - 1) * keySpacing
//                        let offsetX = getBlackKeyOffset(midi: leftBlack)
//                        let bx = baseX + offsetX * keySpacing - keySpacing * 0.3
//                        let bxRight = bx + blackWidth * 1.14
//                        if clampedX >= bx - blackWidth * 0.14 && clampedX <= bxRight { return leftBlack }
//                    }
//                }
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
// REPLACED BLOCK END
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
}

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

