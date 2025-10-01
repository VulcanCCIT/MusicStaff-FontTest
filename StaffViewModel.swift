//
//  StaffViewModel.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/20/25.
//

import SwiftUI
import Combine

public typealias MIDI = Int

public struct StaffNote {
    public let name: String
    public let midi: Int
}

public enum Clef { case treble, bass }

public final class StaffViewModel: ObservableObject {
    @Published public var currentClef: Clef = .treble
    @Published public var currentNote: StaffNote = StaffNote(name: "", midi: 60)

    // Optional externally-provided MIDI range to constrain randomization (e.g., from calibration)
    private var allowedMIDIRange: ClosedRange<Int>? = nil

    /// Provide an allowed MIDI range (inclusive) to constrain random note generation.
    public func setAllowedMIDIRange(_ range: ClosedRange<Int>?) {
        allowedMIDIRange = range
    }

    public init() {}

    // MARK: - Public API
    public func randomizeNote() {
        currentClef = Bool.random() ? .treble : .bass
        let baseRange = midiRange(for: currentClef)
        let effectiveRange: ClosedRange<Int>
        if let allowed = allowedMIDIRange {
            let lower = max(baseRange.lowerBound, allowed.lowerBound)
            let upper = min(baseRange.upperBound, allowed.upperBound)
            if lower <= upper {
                effectiveRange = lower...upper
            } else {
                // If no overlap, fall back to baseRange to avoid empty candidates
                effectiveRange = baseRange
            }
        } else {
            effectiveRange = baseRange
        }
        let candidates = Array(effectiveRange).filter(isNatural)
        if let midi = candidates.randomElement() {
            currentNote = StaffNote(name: noteName(for: midi), midi: midi)
        }
    }

    public struct StaffMetrics {
        public let middleLineY: CGFloat        // visual Y for the middle staff line
        public let lineSpacing: CGFloat        // distance between adjacent staff lines
        public let staffCenterYOffset: CGFloat // tweak if the glyph's visual center isn't exactly on the middle line
        public let noteCenterYOffset: CGFloat  // tweak so staff/ledger line intersects note head center
        public let ledgerCenterYOffset: CGFloat// tweak to vertically center the ledger line glyph on the intended line
    }

    public func metrics(for clef: Clef) -> StaffMetrics {
        // Assumptions:
        // - Staff glyph is drawn with anchor .center at the provided point.
        // - middleLineY should correspond to the visual Y of the middle line.
        // - lineSpacing is the distance (in points) between adjacent staff lines.
        // - Offsets allow visual fine-tuning to match the font's metrics.
        switch clef {
        case .treble:
            return StaffMetrics(
                middleLineY: 160, //was 150
                lineSpacing: 12.5, //was 12
                staffCenterYOffset: -4.7, //was 0
                noteCenterYOffset: -0.2, //was -0.5
                ledgerCenterYOffset: 0 // vector strokes are centered, no glyph offset needed
            )
        case .bass:
            return StaffMetrics(
                middleLineY: 230,
                lineSpacing: 12.5,
                staffCenterYOffset: 4.7,
                noteCenterYOffset: 0.5,
                ledgerCenterYOffset: 0.0
            )
        }
    }

    // Debug helpers
    public func staffLineYs(for clef: Clef) -> [CGFloat] {
        // Returns Y positions for the five staff lines: steps -4, -2, 0, 2, 4
        let m = metrics(for: clef)
        let baseY = m.middleLineY + m.staffCenterYOffset
        let positionStep = m.lineSpacing / 2.0
        let lineSteps = [-4, -2, 0, 2, 4]
        return lineSteps.map { s in baseY - CGFloat(s) * positionStep }
    }

    public func step(for midi: Int, clef: Clef) -> Int {
        // Exposes the internal step calculation for debugging
        return staffStep(for: midi, clef: clef)
    }

    public func y(for midi: Int, clef: Clef) -> CGFloat {
        let m = metrics(for: clef)
        let positionStep = m.lineSpacing / 2.0 // line <-> space distance
        let step = staffStep(for: midi, clef: clef)
        return (m.middleLineY + m.staffCenterYOffset) - CGFloat(step) * positionStep
    }

    public func noteY(for midi: Int, clef: Clef) -> CGFloat {
        let m = metrics(for: clef)
        return y(for: midi, clef: clef) + m.noteCenterYOffset
    }

    public var currentY: CGFloat {
        noteY(for: currentNote.midi, clef: currentClef)
    }

    public func ledgerLineYs(for midi: Int, clef: Clef) -> [CGFloat] {
        // Compute ledger lines relative to the note so a line-step note (even step)
        // always gets a ledger line drawn through its visual center.
        let m = metrics(for: clef)
        let positionStep = m.lineSpacing / 2.0
        let step = staffStep(for: midi, clef: clef)
        // Only draw ledger lines for notes strictly beyond the staff bounds
        guard abs(step) > 4 else { return [] }
        let noteY = noteY(for: midi, clef: clef)
        let evenSteps = ledgerLineSteps(for: step) // e.g., 6,8,... or -6,-8,... including `step` when even
        let candidates = evenSteps.map { t -> CGFloat in
            let deltaSteps = step - t
            return noteY + CGFloat(deltaSteps) * positionStep + m.ledgerCenterYOffset
        }
        // Compute staff bounds (top and bottom staff lines)
        let baseY = m.middleLineY + m.staffCenterYOffset
        let topStaffY = baseY - 2 * m.lineSpacing
        let bottomStaffY = baseY + 2 * m.lineSpacing
        let epsilon: CGFloat = 0.5 // small tolerance
        return candidates.filter { y in y < topStaffY - epsilon || y > bottomStaffY + epsilon }
    }

    // MARK: - Internals
    private func midiRange(for clef: Clef) -> ClosedRange<Int> {
        switch clef {
        case .treble: return 60...108 // C4..C8
        case .bass:   return 21...60  // A0..C4
        }
    }

    private func isNatural(_ midi: Int) -> Bool {
        // C, D, E, F, G, A, B
        [0, 2, 4, 5, 7, 9, 11].contains(midi % 12)
    }

    private func noteName(for midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let octave = midi / 12 - 1
        return names[midi % 12] + String(octave)
    }

    private func referenceMidi(for clef: Clef) -> Int {
        switch clef {
        case .treble: return 71 // B4 (middle line)
        case .bass:   return 50 // D3 (middle line)
        }
    }

    private func diatonicIndex(for midi: Int) -> Int {
        let pc = midi % 12
        let octave = midi / 12 - 1
        // Natural letter mapping: C=0, D=1, E=2, F=3, G=4, A=5, B=6
        let map: [Int:Int] = [0:0, 2:1, 4:2, 5:3, 7:4, 9:5, 11:6]
        guard let letter = map[pc] else {
            // Fallback to C if accidental; in this app we pick naturals only.
            return octave * 7
        }
        return octave * 7 + letter
    }

    private func staffStep(for midi: Int, clef: Clef) -> Int {
        diatonicIndex(for: midi) - diatonicIndex(for: referenceMidi(for: clef))
    }

    private func ledgerLineSteps(for step: Int) -> [Int] {
        // Staff lines are at steps: ... -4, -2, 0, 2, 4 ... relative to the middle line (0)
        // Draw ledger lines at every line step beyond the staff bounds.
        if step > 4 {
            return Array(stride(from: 6, through: step, by: 2))
        } else if step < -4 {
            return Array(stride(from: -6, through: step, by: -2))
        } else {
            return []
        }
    }
}
