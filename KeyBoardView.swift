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

// MARK: - Layout Constants

/// Spacing ratios for positioning white keys with even visual spacing.
///
/// These ratios determine the initial horizontal offset for each white key
/// to account for the visual interruption caused by black keys. The values
/// are expressed as fractions of a semitone (1/12 of an octave).
///
/// For example, C has 0.0 offset because there's no black key to its left,
/// while D has a 2.0/12.0 offset to account for C# being to its left.
let evenSpacingInitialSpacerRatio: [Letter: CGFloat] = [
    .C: 0.0,
    .D: 2.0 / 12.0,
    .E: 4.0 / 12.0,
    .F: 0.0 / 12.0,
    .G: 1.0 / 12.0,
    .A: 3.0 / 12.0,
    .B: 5.0 / 12.0
]

/// Spacing ratios for the gaps between white keys.
///
/// All white keys use the same spacing ratio of 7/12 of a semitone,
/// creating consistent visual gaps between keys regardless of whether
/// there's a black key between them.
let evenSpacingSpacerRatio: [Letter: CGFloat] = [
    .C: 7.0 / 12.0,
    .D: 7.0 / 12.0,
    .E: 7.0 / 12.0,
    .F: 7.0 / 12.0,
    .G: 7.0 / 12.0,
    .A: 7.0 / 12.0,
    .B: 7.0 / 12.0
]

/// Relative width of black keys compared to white keys.
///
/// Black keys are 7/12 (approximately 58%) the width of white keys,
/// matching the proportions of a real piano keyboard.
let evenSpacingRelativeBlackKeyWidth: CGFloat = 7.0 / 12.0


// MARK: - Main Keyboard View

/// A 3D piano keyboard view with realistic rendering and MIDI support.
///
/// `KeyBoardView` creates a visually sophisticated virtual piano keyboard with:
/// - Realistic 3D rendering with perspective, shadows, and depth
/// - Full MIDI input support (Bluetooth and USB)
/// - Touch/mouse interaction for playing notes
/// - Visual feedback for correct/incorrect notes
/// - Scientific pitch notation labels (C4, D5, etc.)
/// - Decorative control panel with vintage synth aesthetics
///
/// ## View Hierarchy
///
/// The view is composed of several layers (top to bottom):
/// 1. **Control Panel** - Decorative knobs and LED indicator
/// 2. **Piano Rail** - Glossy black separator with chrome stanchions
/// 3. **3D Keyboard** - Perspective-rendered piano keys
/// 4. **Chassis** - Rounded blue background enclosure
///
/// ## State Management
///
/// The view tracks:
/// - External MIDI velocities for visual intensity
/// - Correctness state for each pressed note (green/red feedback)
/// - Scale and root note (currently unused, retained for future features)
///
/// ## Usage
///
/// ```swift
/// KeyBoardView(
///     isCorrect: { midiNote in
///         return midiNote == targetNote // Highlight correct answer
///     },
///     docked: false
/// )
/// .environmentObject(conductor)
/// .environmentObject(appData)
/// ```
struct KeyBoardView: View {
  // MARK: - Environment & State
  
  /// The MIDI conductor that handles note on/off events and audio playback.
  @EnvironmentObject private var conductor: MIDIMonitorConductor
  
  /// Maps MIDI note numbers to velocity (0.0...1.0) for visual intensity.
  ///
  /// Updated when external MIDI events are received. The velocity affects
  /// how brightly the key highlights when pressed.
  @State private var externalVelocities: [Int: Double] = [:]
  
  /// Stores whether each currently-pressed note was correct at the moment of note-on.
  ///
  /// This prevents a race condition where the target note changes after a correct
  /// answer, causing the second evaluation to be wrong. The correctness is
  /// "frozen" at note-on time.
  @State private var pressedCorrectness: [Int: Bool] = [:]
  
  /// Index into the Scale.allCases array (currently unused).
  ///
  /// Retained for potential future scale-highlighting feature.
  @State var scaleIndex = Scale.allCases.firstIndex(of: .chromatic) ?? 0 {
    didSet {
      if scaleIndex >= Scale.allCases.count { scaleIndex = 0 }
      if scaleIndex < 0 { scaleIndex = Scale.allCases.count - 1 }
      scale = Scale.allCases[scaleIndex]
    }
  }
  
  /// The current musical scale (currently unused).
  @State var scale: Scale = .chromatic
  
  /// The root note class (currently unused).
  @State var root: NoteClass = .C
  
  /// Index for cycling through root notes (currently unused).
  @State var rootIndex = 0
  
  /// The current color scheme (light/dark mode).
  @Environment(\.colorScheme) var colorScheme
  
  /// App-wide data including MIDI range calibration and settings.
  @EnvironmentObject private var appData: AppData
  
  /// Closure that determines if a given MIDI note should be highlighted as correct.
  ///
  /// This is typically provided by a parent view implementing a music learning game
  /// or quiz. Return `true` for the target note(s).
  var isCorrect: (Int) -> Bool = { _ in false }
  
  /// Whether the keyboard is docked at the bottom of the screen.
  ///
  /// When `true`, adjusts spacing and adds a top border to integrate with
  /// safe area insets.
  var docked: Bool = false

  // MARK: - Computed Properties
  
  /// The lowest MIDI note to display on the keyboard.
  ///
  /// Defaults to MIDI note 24 (C1) if no calibration is set.
  private var lowNote: Int {
    appData.calibratedRange?.lowerBound ?? 24
  }

  /// The highest MIDI note to display on the keyboard.
  ///
  /// Defaults to MIDI note 48 (C3) if no calibration is set.
  private var highNote: Int {
    appData.calibratedRange?.upperBound ?? 48
  }
  
  // MARK: - Helper Methods
  
  /// Converts a MIDI note number to scientific pitch notation.
  ///
  /// - Parameter midiNote: MIDI note number (0-127)
  /// - Returns: Note name with octave (e.g., "C4", "A#5") or "—" if invalid
  ///
  /// ## Examples
  /// ```swift
  /// noteName(from: 60) // "C4"
  /// noteName(from: 69) // "A4"
  /// noteName(from: 61) // "C#4"
  /// ```
  private func noteName(from midiNote: Int) -> String {
    guard (0...127).contains(midiNote) else { return "—" }
    let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    let octave = (midiNote / 12) - 1
    return names[midiNote % 12] + String(octave)
  }
  
  /// Generates a label for natural notes only (no sharps/flats).
  ///
  /// This is used to label white keys on the keyboard without cluttering
  /// the view with labels on black keys.
  ///
  /// - Parameter pitch: The pitch object from the Tonic library
  /// - Returns: Scientific notation label for natural notes, empty string for accidentals
  private func scientificLabel(for pitch: Pitch) -> String {
      let midi = pitch.intValue
      // Build a musical name (e.g., A3, D6) using the existing helper
      let name = noteName(from: midi)
      // Only label natural notes on white keys to avoid clutter
      return name.contains("#") ? "" : name
  }
  
  // MARK: - Body
  
  var body: some View {
    HStack {
      VStack {
        
        // MARK: Control Panel
        // Decorative panel with knobs and LED that sits above the keyboard
        ZStack {
          HStack(alignment: .center, spacing: 24) {
            // Left section: Two decorative knobs
            KnobImage()
            KnobImage()
            Spacer()
            
            // Right section: Two more knobs with LED centered above them
            HStack(spacing: 24) {
              KnobImage()
              KnobImage()
            }
            .overlay(alignment: .top) {
              // Red LED indicator centered between the right two knobs
              Image("redled2")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 30, height: 30)
                .offset(x: 0, y: -12) // Positioned above the knobs
                .accessibilityHidden(true)
            }
          }
        }
        .overlay(alignment: .center) {
          NodeOutputView(conductor.instrument, color: .red)
            .frame(height: 48)
            .frame(width: 240)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(GlassReflection(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        // Platform-specific vertical padding
        // macOS: Smaller padding for compact display
        // iOS/iPadOS: Larger padding for touch targets
#if os(macOS)
        .padding(.vertical, 10)
#else
        .padding(.vertical, 16)
#endif
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
          // 3D styled background with gradients and shadows
          Panel3DBackground()
        )
        .padding(.horizontal)
        .padding(.bottom, 8) // Gap between control panel and piano rail
        
        // MARK: Piano Rail
        // Glossy black separator bar with chrome stanchions (vertical bars)
        PianoRail()
          .frame(height: 14)
          .padding(.horizontal, 22)
          // Negative top padding tucks the rail under the control panel
          // Bottom padding creates space above the keyboard
          .padding(.top, -6)
          .padding(.bottom, 4)

        // MARK: 3D Keyboard
        // The main keyboard rendering with white and black keys
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
        }
        .padding(.horizontal, 12) // Minimal side padding
        // Platform-specific vertical padding for the keyboard chassis
        // macOS: More compact
        // iOS/iPadOS: Slightly more spacious
#if os(macOS)
        .padding(.vertical, 20)
#else
        .padding(.vertical, 15)
#endif
        .background(
          // MARK: Keyboard Chassis Background
          // Styled blue rounded rectangle that acts as the keyboard's enclosure
          ZStack {
            // Base chassis color (custom blue from asset catalog)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(Color("MeterPanelColor"))

            // Subtle vertical sheen for depth and gloss
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(LinearGradient(colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.08)], startPoint: .top, endPoint: .bottom))
              .blendMode(.softLight)

            // Subtle purple tint to match overall design language
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(LinearGradient(colors: [Color.purple.opacity(0.04), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
              .blendMode(.plusLighter)
          }
        )
        .overlay(
          // MARK: Edge Highlights
          // Top-to-bottom edge highlight for 3D depth
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .blendMode(.overlay)
        )
        .overlay(
          // Diagonal edge highlight for additional dimension
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
              LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                             startPoint: .topLeading, endPoint: .bottomTrailing),
              lineWidth: 1
            )
            .blendMode(.screen)
            .opacity(0.9)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 6) // Drop shadow for chassis
        // Platform-specific bottom padding
        // Adjusts space below keyboard based on docked vs floating state
        #if os(macOS)
        .padding(.bottom, docked ? 6 : 28)
        #else
        .padding(.bottom, docked ? 10 : 10)
        #endif
      }
      .overlay(alignment: .top) {
          // Add subtle top border when docked to separate from content above
          if docked {
              Rectangle()
                  .fill(Color.black.opacity(0.15))
                  .frame(height: 1)
          }
      }
      .clipShape(
        // Clip to rounded rectangle with square bottom corners when docked
        UnevenRoundedRectangle(
          topLeadingRadius: 18,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 18,
          style: .continuous
        )
      )
      // MARK: MIDI Event Handlers
      .onReceive(conductor.noteOnSubject) { (note, velocity) in
          // Update visual intensity; audio already triggered in conductor
          // Apply velocity boost for more dramatic visual feedback
          let boosted = min(127, Int(round(Double(velocity) * 2.25)))
          let norm = max(0.0, min(1.0, Double(boosted) / 127.0))
          externalVelocities[note] = norm
          
          // CRITICAL FIX: Only set correctness if not already set
          // This prevents a race condition where the target note changes after
          // a correct answer, causing the second evaluation to be wrong
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
    }
  }
}

// MARK: - Decorative Knob Image

/// A decorative knob image for the control panel.
///
/// Displays either a custom "Knob2" image asset or falls back to a system symbol
/// if the asset is not found. The view handles platform differences between
/// macOS (NSImage) and iOS (UIImage).
///
/// ## Visual Specifications
/// - Size: 38×38 points
/// - High-quality interpolation for smooth rendering
/// - Subtle shadow for depth
struct KnobImage: View {
  var body: some View {
    Group {
      #if os(macOS)
      // macOS: Check for NSImage in assets
      if NSImage(named: "Knob2") != nil {
        Image("Knob2")
          .resizable()
          .interpolation(.high)
          .antialiased(true)
      } else {
        // Fallback to SF Symbol
        Image(systemName: "dial.max")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      #else
      // iOS/iPadOS: Check for UIImage in assets
      if UIImage(named: "Knob2") != nil {
        Image("Knob2")
          .resizable()
          .interpolation(.high)
          .antialiased(true)
      } else {
        // Fallback to SF Symbol
        Image(systemName: "dial.max")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      #endif
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(width: 38, height: 38)
    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    .accessibilityHidden(true) // Decorative only, no interactive functionality
  }
}

// MARK: - Panel 3D Background

/// A sophisticated 3D-styled background for the control panel.
///
/// This view creates a realistic "tilted panel" effect using multiple layers:
/// 1. Base color fill
/// 2. Vertical sheen gradient
/// 3. Inner shadows at the top edge
/// 4. Top highlight edge
/// 5. Angled sheen using Canvas for custom geometry
/// 6. Corner highlights and shadows
///
/// The result looks like a physical panel tilted toward the user with
/// lighting from the top-left, giving depth and dimension.
struct Panel3DBackground: View {
  var body: some View {
    GeometryReader { proxy in
      let corner: CGFloat = 18
      ZStack {
        // Layer 1: Base panel color
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .fill(Color("MeterPanelColor"))

        // Layer 2: Subtle vertical sheen for a glassy/plastic look
        // Creates highlight at top, shadow at bottom
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

        // Layer 3: Inner shadow (top) to suggest thickness
        // Darkens the top edge as if recessed
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
          .blur(radius: 2)
          .offset(y: 1)
          .mask(
            // Only show shadow at the top half
            RoundedRectangle(cornerRadius: corner, style: .continuous)
              .fill(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
          )

        // Layer 4: Top highlight edge
        // Bright line at the top for "edge catching light"
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
          .blendMode(.overlay)
        
        // Layer 5: Angled sheen and inner edge to suggest panel tilt
        // Uses Canvas for custom trapezoid geometry
        GeometryReader { g in
          Canvas { context, size in
            // Calculate inset for trapezoid shape
            let inset: CGFloat = max(10, size.height * 0.08)
            
            // Create a trapezoid path (wider at bottom, narrower at top)
            var trapezoid = Path()
            trapezoid.move(to: CGPoint(x: inset * 1.3, y: inset * 0.7))
            trapezoid.addLine(to: CGPoint(x: size.width - inset * 0.9, y: inset * 0.3))
            trapezoid.addLine(to: CGPoint(x: size.width - inset * 0.6, y: size.height - inset * 0.9))
            trapezoid.addLine(to: CGPoint(x: inset, y: size.height - inset * 0.6))
            trapezoid.closeSubpath()

            // Fill with diagonal gradient (soft angled sheen)
            context.fill(
              trapezoid,
              with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06), .clear]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
              )
            )

            // Stroke inner edge with dark line for depth
            let innerEdge = trapezoid
            context.stroke(innerEdge, with: .color(Color.black.opacity(0.16)), lineWidth: 2)
          }
        }
        
        // Layer 6: Top-left sweep highlight
        // Diagonal highlight from top-left corner
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(
            LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.18), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.2
          )
          .blendMode(.overlay)

        // Layer 7: Bottom-right sweep shadow
        // Diagonal shadow toward bottom-right corner
        RoundedRectangle(cornerRadius: corner, style: .continuous)
          .stroke(
            LinearGradient(colors: [.clear, Color.black.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 3
          )
          .opacity(0.8)
      }
      .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4) // Outer drop shadow
    }
  }
}

// MARK: - Glass Reflection (Unused)

/// A reusable glass reflection effect (currently unused but retained for potential future use).
///
/// Creates a glossy "glass" appearance with:
/// - Top gloss highlight
/// - Edge highlights
///
/// Can be applied to any rounded rectangle shape.
struct GlassReflection: View {
  /// Corner radius to match the shape being styled.
  let cornerRadius: CGFloat
  
  var body: some View {
    ZStack {
      // Top gloss - bright at top, fading to middle
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .center
          )
        )
        .blendMode(.screen)

      // Edge highlight - bright line around perimeter
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(
          LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
          lineWidth: 0.8
        )
        .blendMode(.overlay)
    }
  }
}

// MARK: - Piano Rail

/// The glossy black separator rail between the control panel and keyboard.
///
/// This view creates a realistic piano-style rail with:
/// - Glossy black gradient base
/// - Top highlight for shine
/// - Subtle purple tint
/// - Chrome stanchions (vertical support bars)
///
/// The rail serves both aesthetic and structural purposes, visually
/// connecting the control panel to the keyboard below.
struct PianoRail: View {
    var body: some View {
      ZStack {
        // Base glossy black rail with vertical gradient
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(LinearGradient(colors: [Color.black.opacity(0.95), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))

        // Top highlight for glossy appearance
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
          .blendMode(.overlay)

        // Subtle purple glow hint from legacy design
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(LinearGradient(colors: [Color.purple.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
          .blendMode(.plusLighter)
      }
      .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
      .background(
        // Chrome stanchions that extend above and below the rail
        ChromeStanchions(upLength: 16, downLength: 24, barWidth: 8, spacing: 54)
          .padding(.vertical, -20) // Negative padding allows bars to extend beyond rail bounds
      )
    }
  }

// MARK: - Chrome Stanchions

/// Decorative chrome support bars for the piano rail.
///
/// Creates four vertical metallic bars with realistic chrome gradients:
/// - Two outer bars at the edges
/// - Two center bars symmetrically spaced
///
/// The bars extend both above and below the rail, simulating physical
/// supports that connect the control panel to the keyboard chassis.
struct ChromeStanchions: View {
    /// Length of bar extending upward from the rail.
    var upLength: CGFloat = 14
    
    /// Length of bar extending downward from the rail.
    var downLength: CGFloat = 18
    
    /// Width of each individual bar.
    var barWidth: CGFloat = 6
    
    /// Spacing between the two center bars.
    var spacing: CGFloat = 44
    
    /// Inset from left/right edges for outer bars.
    var edgeInset: CGFloat = 28

    /// Helper to create a single chrome bar with gradient and highlight.
    private func barPath(fill colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: barWidth/2, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: barWidth, height: upLength + downLength)
            .overlay(
                // Edge highlight for chrome shine
                RoundedRectangle(cornerRadius: barWidth/2, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    var body: some View {
        GeometryReader { geo in
            // Calculate bar positions
            let centerX = geo.size.width / 2
            let leftCenterX = centerX - spacing/2
            let rightCenterX = centerX + spacing/2
            let outerLeftX = max(edgeInset, barWidth/2 + 2)
            let outerRightX = geo.size.width - max(edgeInset, barWidth/2 + 2)

            // Chrome gradient: white → gray → dark gray → white
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
        .allowsHitTesting(false) // Bars are decorative only
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

/// The core 3D keyboard rendering and interaction view.
///
/// This view handles all aspects of the virtual piano keyboard:
/// - Renders white and black keys with realistic 3D perspective
/// - Applies lighting, shadows, and gradients for depth
/// - Handles touch/mouse interaction with velocity sensitivity
/// - Shows visual feedback for correct/incorrect notes
/// - Displays scientific notation labels on white keys
///
/// ## Implementation Details
///
/// The keyboard is rendered using SwiftUI's `Canvas` for high-performance
/// custom drawing. Keys are drawn in two passes:
/// 1. White keys (back to front for proper depth layering)
/// 2. Black keys (on top of white keys)
///
/// ## Perspective System
///
/// The keyboard uses a realistic overhead perspective with:
/// - **Vanishing point**: Keys converge toward a center point at the back
/// - **Vertical tilt**: Back edge appears higher than front edge
/// - **Depth perception**: Keys become visually narrower toward the back
///
/// This creates the illusion of viewing a real keyboard from a seated position.
///
/// ## Touch Handling
///
/// Touches are converted to MIDI note numbers by:
/// 1. Checking black key hit areas first (elevated above white keys)
/// 2. Falling back to white key detection
/// 3. Mapping Y-position to velocity (distance determines volume)
/// 4. Handling drag gestures to slide between keys
struct Keyboard3DView: View {
    // MARK: - Input Parameters
    
    /// Lowest MIDI note to display (typically C1 = 24).
    let lowNote: Int
    
    /// Highest MIDI note to display (typically C3 = 48 or higher).
    let highNote: Int
    
    /// Reference to the MIDI conductor for triggering notes.
    let conductor: MIDIMonitorConductor
    
    /// Closure to determine if a note should be highlighted as correct.
    let isCorrect: (Int) -> Bool
    
    /// Binding to track correctness state for currently pressed notes.
    @Binding var pressedCorrectness: [Int: Bool]
    
    /// Binding to track velocities for visual intensity (0.0-1.0).
    @Binding var externalVelocities: [Int: Double]
    
    /// Function to generate labels for natural notes (C4, D5, etc.).
    let scientificLabel: (Pitch) -> String
    
    /// Whether to show note name labels on keys.
    let showHints: Bool
    
    // MARK: - State
    
    @Environment(\.colorScheme) var colorScheme
    
    /// Set of MIDI notes currently being pressed via touch/mouse.
    @State private var keyPresses: Set<Int> = []
    
    /// The last MIDI note triggered by dragging (used to detect key changes).
    @State private var lastMidi: Int? = nil

    // MARK: - Layout Constants
    
    /// Scale factor for back edge relative to front (0.90 = 10% narrower at back).
    ///
    /// Controls how aggressively the keyboard tapers toward the back edge.
    /// Lower values create more dramatic perspective.
    private let backScale: CGFloat = 0.90
    
    /// Height of the keyboard case/chassis (unused in current design).
    private let caseHeight: CGFloat = 26
    
    /// Height of white key front face (vertical surface you see).
    private let whiteFrontHeight: CGFloat = 24
    
    /// Height of black key front face.
    private let blackFrontHeight: CGFloat = 12
    
    /// Vertical offset for black keys (negative = higher than white keys).
    private let blackKeyElevation: CGFloat = -8
    
    // MARK: - 3D Appearance Settings
    
    /// Viewing angle in degrees from horizontal (35° = typical overhead view).
    private let viewingAngle: Double = 35.0
    
    /// Physical depth of keyboard from front to back (points).
    private let keyboardDepth: CGFloat = 120.0
    
    /// White key length (unused - depth calculated dynamically).
    private let whiteKeyHeight: CGFloat = 140.0
    
    /// Black key length (unused - depth calculated dynamically).
    private let blackKeyHeight: CGFloat = 90.0
    
    /// Key thickness for 3D rendering (unused in current implementation).
    private let keyThickness: CGFloat = 2.0

    /// Perspective distortion strength (0.15 = 15% size reduction from front to back).
    ///
    /// Controls how much keys taper toward the vanishing point at the back.
    private let vanishFactor: CGFloat = 0.15
    
    /// Vertical tilt factor (0.08 = 8% additional height at edges vs center).
    ///
    /// Creates the illusion that the back edge "lifts" away from the viewer,
    /// with more pronounced lift at the horizontal edges.
    private let tiltBias: CGFloat = 0.08

    // MARK: - Hit Testing Constants
    
    /// Front guard zone ratio where only white keys can be triggered.
    ///
    /// The front 10% of the keyboard depth is reserved for white keys only,
    /// preventing accidental black key hits when reaching for white keys.
    private let whiteFrontGuardRatio: CGFloat = 0.10
    
    /// Reserve factor for front face visibility.
    ///
    /// Ensures the front vertical face of keys remains visible by reserving
    /// 28% of the height for the front face before calculating key depth.
    private let frontFaceReserveFactor: CGFloat = 0.28

    // MARK: - Perspective Transformation
    
    /// Calculates the X-coordinate at the back edge for a given front X-coordinate.
    ///
    /// This creates the horizontal tapering effect where keys appear narrower
    /// at the back edge, converging toward a center vanishing point.
    ///
    /// - Parameters:
    ///   - x: The X-coordinate at the front edge
    ///   - totalWidth: Total width of the keyboard view
    /// - Returns: The transformed X-coordinate at the back edge
    ///
    /// ## Example
    /// If front edge is 100 points wide and `vanishFactor` is 0.15:
    /// - A key at the left edge (x=0) will be at x=7.5 at the back
    /// - A key at the right edge (x=100) will be at x=92.5 at the back
    /// - The keyboard is now 85 points wide at the back (15% reduction)
    private func backX(forFrontX x: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let centerX = totalWidth / 2
        let offsetFromCenter = x - centerX
        // Stronger convergence toward center for more dramatic perspective
        let tapered = centerX + offsetFromCenter * (1.0 - vanishFactor)
        return tapered
    }

    /// Calculates the Y-coordinate at the back edge with tilt effect.
    ///
    /// This creates vertical "lifting" where the back edge appears higher
    /// than the front, especially at the horizontal edges. This simulates
    /// the natural perspective of viewing a keyboard from a seated position.
    ///
    /// - Parameters:
    ///   - baseY: The Y-coordinate at the back edge without tilt
    ///   - totalWidth: Total width of the keyboard view
    ///   - x: The X-coordinate (for calculating distance from center)
    /// - Returns: The transformed Y-coordinate with tilt applied
    ///
    /// ## Tilt Calculation
    /// The tilt increases linearly from center (0%) to edges (100%):
    /// - Center keys: minimal lift
    /// - Edge keys: maximum lift (creates "curved" back edge)
    private func backY(baseY: CGFloat, totalWidth: CGFloat, atFrontX x: CGFloat) -> CGFloat {
        let centerX = totalWidth / 2
        let distanceFromCenter = abs(x - centerX) / (totalWidth / 2) // 0.0 at center, 1.0 at edges
        
        // Add both tilt and "lift" effect - keyboard appears to lift away from viewer
        let tiltOffset = distanceFromCenter * tiltBias * 25 // Tilt scaled by distance from center
        let liftOffset = 15.0 // Constant lift to make back edge appear higher
        
        return baseY - tiltOffset - liftOffset
    }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent background allows parent view styling to show through
                Color.clear
                
                // Canvas for high-performance custom drawing
                Canvas { context, size in
                    drawRealistic3DKeyboard(context: context, size: size)
                }
            }
            // MARK: Touch/Mouse Gesture Handling
            .gesture(
                // Drag gesture with 0 minimum distance acts like both tap and drag
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convert touch location to MIDI note number
                        let newMidi = midiFromLocation(value.location, in: geometry.size)

                        // STEP 1: Handle key transitions
                        // If finger moved to a different key, send noteOff for previous
                        if let prev = lastMidi, prev != newMidi {
                            if keyPresses.contains(prev) {
                                keyPresses.remove(prev)
                                conductor.simulateNoteOff(noteNumber: prev)
                            }
                        }

                        // STEP 2: Trigger new note if not already active
                        if !keyPresses.contains(newMidi) {
                            keyPresses.insert(newMidi)
                            
                            // STEP 3: Calculate velocity based on Y-position
                            // Use the same layout math as drawing for consistent velocity mapping
                            let a: CGFloat = 0.20 / 0.72  // Aspect ratio for depth calculation
                            let s = scaleFor(size: geometry.size)  // Dynamic scale factor
                            let whiteFrontH = whiteFrontHeight * s
                            
                            // Calculate keyboard depth with height constraints
                            let preferredDepth = geometry.size.height // Allow full height if possible
                            let maxDepthByHeight = max(60, (geometry.size.height - whiteFrontH * frontFaceReserveFactor - 2) / (1 + a))
                            let keyDepth = min(preferredDepth, maxDepthByHeight)
                            let keyY = keyDepth * a  // Starting Y position for keys
                            
                            // Clamp touch Y to valid key area
                            let clampedY = min(max(value.location.y, keyY), keyY + keyDepth)
                            
                            // Convert Y position to relative depth (0.0 = far, 1.0 = near)
                            let relative = (keyY + keyDepth - clampedY) / keyDepth
                            let norm = max(0.0, min(1.0, relative))
                            
                            // Apply curve for more natural velocity response
                            // Square root gives bias toward louder velocities (feels more responsive)
                            let curved = pow(norm, 0.5)
                            
                            // Convert to MIDI velocity (120-127 range for on-screen taps)
                            // Raised minimum from 64 to 120 for better perceived loudness
                            let velocity = max(120, min(127, Int(curved * 127)))
                            
                            // Trigger note on event
                            conductor.simulateNoteOn(noteNumber: newMidi, velocity: velocity)
                        }

                        // Remember last key for tracking transitions
                        lastMidi = newMidi
                    }
                    .onEnded { value in
                        // STEP 4: Clean up when touch/click ends
                        
                        // Send note off for the last touched key
                        if let prev = lastMidi {
                            conductor.simulateNoteOff(noteNumber: prev)
                        }
                        
                        // Safety: turn off any remaining active notes we tracked
                        // (Handles edge cases where note-offs might have been missed)
                        for note in keyPresses {
                            conductor.simulateNoteOff(noteNumber: note)
                        }
                        
                        // Clear all tracking state
                        keyPresses.removeAll()
                        lastMidi = nil
                    }
            )
        }
        // Minimum size constraints to prevent layout issues
        .frame(minWidth: 100, minHeight: 100)
    }
    
    // MARK: - Main Drawing Function
    
    /// Draws the complete 3D keyboard with perspective, lighting, and shadows.
    ///
    /// This method orchestrates the entire rendering process:
    /// 1. Calculate layout dimensions and scaling
    /// 2. Draw keyboard case/background (currently empty)
    /// 3. Draw subtle shadow overlay for depth
    /// 4. Draw all white keys (back to front)
    /// 5. Draw groove lines between white keys
    /// 6. Draw all black keys (on top layer)
    ///
    /// ## Layout Algorithm
    ///
    /// The keyboard layout uses a sophisticated calculation to fit keys properly:
    /// - Reserves space at bottom for note labels
    /// - Applies platform-specific perspective ratios (macOS vs iOS)
    /// - Calculates keyboard depth to fill available space
    /// - Positions keyboard Y-coordinate to account for perspective
    ///
    /// ## Drawing Order
    ///
    /// Keys must be drawn in specific order for correct depth perception:
    /// 1. Background elements (furthest back)
    /// 2. White keys (middle layer)
    /// 3. Separators and details
    /// 4. Black keys (frontmost layer)
    ///
    /// - Parameters:
    ///   - context: The Canvas graphics context for drawing
    ///   - size: The available drawing size
    private func drawRealistic3DKeyboard(context: GraphicsContext, size: CGSize) {
        let totalWidth = size.width
        let totalHeight = size.height

        // Apply dynamic scaling based on view height
        let s = scaleFor(size: size)
        let whiteFrontH = whiteFrontHeight * s
        let blackFrontH = blackFrontHeight * s
        let caseH = caseHeight * s
        let elevation = blackKeyElevation * s

        // STEP 1: Calculate keyboard dimensions
        // Count white keys to determine key width
        let whiteCount = max(1, (lowNote...highNote).filter { ![1,3,6,8,10].contains($0 % 12) }.count)
        let keyWidth = totalWidth / CGFloat(whiteCount)
        
        // Reserve space for note labels at bottom - scales with key size
        let labelReserve = min(25, whiteFrontH * 1.2)
        
        // Platform-specific perspective ratio
        // macOS: Less overhead space (keys appear higher in frame)
        // iOS/iPadOS: More overhead space for better touch ergonomics
#if os(macOS)
        let perspectiveRatio: CGFloat = 0.16
#else
        let perspectiveRatio: CGFloat = 0.22
#endif
        let usableHeight = totalHeight - labelReserve
        let keyboardDepth = usableHeight * (1.0 - perspectiveRatio)
        let keyboardY = usableHeight * perspectiveRatio

        // STEP 2: Draw keyboard case/background (currently a no-op)
        drawPerspectiveKeyboardCase(context: context, size: size, keyboardY: keyboardY, depth: keyboardDepth, caseHeight: caseH)

        // STEP 3: Calculate perspective-transformed back edge coordinates
        let backLeftX = backX(forFrontX: 0, totalWidth: totalWidth)
        let backRightX = backX(forFrontX: totalWidth, totalWidth: totalWidth)
        let backBaseY = keyboardY
        let backLeftY = backY(baseY: backBaseY, totalWidth: totalWidth, atFrontX: 0)
        let backRightY = backY(baseY: backBaseY, totalWidth: totalWidth, atFrontX: totalWidth)

        // STEP 4: Create white key background area (not drawn, just defined for reference)
        var whiteKeyArea = Path()
        whiteKeyArea.move(to: CGPoint(x: 0, y: keyboardY + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: totalWidth, y: keyboardY + keyboardDepth))
        whiteKeyArea.addLine(to: CGPoint(x: backRightX, y: backRightY))
        whiteKeyArea.addLine(to: CGPoint(x: backLeftX, y: backLeftY))
        whiteKeyArea.closeSubpath()
        
        // STEP 5: Add subtle radial shadow overlay for depth illusion
        // Creates a soft vignette effect that makes the keyboard appear 3D
        var shadowOverlay = Path()
        shadowOverlay.move(to: CGPoint(x: 0, y: keyboardY + keyboardDepth))
        shadowOverlay.addLine(to: CGPoint(x: totalWidth, y: keyboardY + keyboardDepth))
        shadowOverlay.addLine(to: CGPoint(x: backRightX, y: backRightY))
        shadowOverlay.addLine(to: CGPoint(x: backLeftX, y: backLeftY))
        shadowOverlay.closeSubpath()
        
        // Radial gradient from center (lighter) to edges (darker)
        let shadowGradient: GraphicsContext.Shading = .radialGradient(
            Gradient(colors: [Color.black.opacity(0.02), Color.black.opacity(0.08), Color.black.opacity(0.02)]),
            center: CGPoint(x: totalWidth/2, y: keyboardY + keyboardDepth/2),
            startRadius: 0,
            endRadius: totalWidth * 0.8
        )
        context.fill(shadowOverlay, with: shadowGradient)

        // STEP 6: Separate keys into white and black for rendering
        let whiteKeys = (lowNote...highNote).filter { !isBlackKey($0) }
        let blackKeys = (lowNote...highNote).filter { isBlackKey($0) }
        let keySpacing = totalWidth / CGFloat(max(1, whiteKeys.count))
        
        // Calculate black key depth ratio (they're shorter than white keys)
        let bdr = blackDepthRatio(for: size)

        // STEP 7: Draw all white keys
        // Drawn back-to-front for proper depth perception
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
    
    /// Draws the keyboard case/enclosure (currently disabled).
    ///
    /// This method is retained but currently does nothing. Originally drew a
    /// dark case around the keyboard, but removed for cleaner appearance.
    ///
    /// - Parameters:
    ///   - context: Graphics context for drawing
    ///   - size: Total view size
    ///   - keyboardY: Y-coordinate where keyboard starts
    ///   - depth: Depth of the keyboard from back to front
    ///   - caseHeight: Height of the case border (unused)
    private func drawPerspectiveKeyboardCase(context: GraphicsContext, size: CGSize, keyboardY: CGFloat, depth: CGFloat, caseHeight: CGFloat) {
        // Intentionally empty - case drawing removed for cleaner aesthetic
        // Parent view's blue chassis provides the enclosure
    }
    
    // MARK: - Individual Key Drawing
    
    /// Draws a single white piano key with realistic 3D perspective and lighting.
    ///
    /// This method renders a white key with multiple surfaces:
    /// - **Top surface**: The horizontal surface you see from above (with perspective taper)
    /// - **Front face**: The vertical surface facing the player
    /// - **Right side**: The visible right edge (for depth)
    /// - **Highlights**: Subtle reflections on top surface when not pressed
    /// - **Label**: Optional note name (C4, D5, etc.) when showHints is true
    ///
    /// ## Visual Feedback
    ///
    /// Keys change color based on state:
    /// - Normal: Off-white gradient with realistic shading
    /// - Pressed & Correct: Green fill
    /// - Pressed & Incorrect: Red fill
    ///
    /// ## Rendering Details
    ///
    /// Each key is drawn as a series of paths with gradients:
    /// 1. Top surface - trapezoid shape for perspective
    /// 2. Front face - rectangle at the front edge
    /// 3. Right side - trapezoid connecting front to back
    /// 4. Highlight overlay - subtle shine when unpressed
    /// 5. Outlines - thin strokes for definition
    /// 6. Label - centered at front edge
    ///
    /// - Parameters:
    ///   - context: Canvas graphics context
    ///   - midi: MIDI note number for this key
    ///   - x: Left edge X-coordinate
    ///   - width: Key width
    ///   - keyboardY: Y-coordinate of keyboard back edge
    ///   - keyboardDepth: Depth from back to front
    ///   - viewDistance: View distance (unused in current implementation)
    ///   - whiteFrontHeight: Height of the front vertical face
    ///   - totalWidth: Total keyboard width (for scaling calculations)
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
        // Check if key is currently pressed
        let isPressed = conductor.activeNotes.contains(midi)
        let pressDepth: CGFloat = isPressed ? 10 : 0  // Keys "sink" 10 points when pressed

        // Calculate key Y positions with press depth applied
        let keyStartY = keyboardY + pressDepth
        let keyEndY = keyboardY + keyboardDepth + pressDepth
        let keyHeight: CGFloat = whiteFrontHeight

        // Apply subtle horizontal scaling based on distance from center
        // This creates a slight "barrel distortion" for more realistic appearance
        // 5% maximum variation from center to edges
        let keyScale = 1.0 - (abs(x + width/2 - totalWidth/2) / (totalWidth/2)) * 0.05
        let scaledWidth = width * keyScale
        let scaledX = x + (width - scaledWidth) / 2  // Center the scaled key
        
        // Define key corners (kept rectangular at back edge, no perspective taper on individual keys)
        let xL = scaledX               // Left edge at front
        let xR = scaledX + scaledWidth // Right edge at front
        let backXL = xL                // Left edge at back (same as front)
        let backXR = xR                // Right edge at back (same as front)
        let backYL = keyStartY         // Back edge Y (same across key)
        let backYR = keyStartY         // Back edge Y (same across key)

        // Determine if this key should be highlighted as correct
        // Check persisted correctness first to prevent state changes during held notes
        let persisted: Bool? = pressedCorrectness[midi]
        let effectiveCorrect: Bool = {
            if isPressed, let persisted {
                return persisted  // Use frozen correctness from note-on time
            } else {
                return isCorrect(midi)  // Check current correctness
            }
        }()

        // SURFACE 1: Top surface (horizontal plane)
        var keyTop = Path()
        keyTop.move(to: CGPoint(x: xL, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: xR, y: keyEndY))
        keyTop.addLine(to: CGPoint(x: backXR, y: backYR))
        keyTop.addLine(to: CGPoint(x: backXL, y: backYL))
        keyTop.closeSubpath()
        
        // Realistic white key gradient (warm whites, darker toward back)
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

        // Black keys should align their back edge with white keys' back edge
        // The elevation is negative (e.g., -8), which was lifting them UP too much
        // We want them at the same back edge, just elevated slightly for 3D effect on the front face
        let keyStartY = keyboardY + pressDepth // Start at same back edge as white keys
        let keyEndY = keyStartY + blackKeyDepth // Black keys end earlier than white keys
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
        
        // SIMPLIFIED - Match the drawing code's layout calculation exactly
        let whiteFrontH = whiteFrontHeight * scaleFor(size: size)
        let labelReserve = min(25, whiteFrontH * 1.2)
#if os(macOS)
        let perspectiveRatio: CGFloat = 0.16
#else
        let perspectiveRatio: CGFloat = 0.16 //.22
#endif
        let usableHeight = size.height - labelReserve
        let keyboardDepth = usableHeight * (1.0 - perspectiveRatio)
        let keyboardY = usableHeight * perspectiveRatio

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
        return 0.58 + 0.02 * min(max(s, 0.6), 1.0) // 0.58 ... 0.60 (realistic piano proportions)
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

