import SwiftUI
import Combine

public struct StaffNote {
    public let name: String
    public let midi: Int
}

public enum Clef { case treble, bass }

public final class StaffViewModel: ObservableObject {
    @Published public var currentClef: Clef = .treble
    @Published public var currentNote: StaffNote = StaffNote(name: "", midi: 60)

    public init() {}

    // MARK: - Public API
    public func randomizeNote() {
        currentClef = Bool.random() ? .treble : .bass
        let range = midiRange(for: currentClef)
        let candidates = Array(range).filter(isNatural)
        if let midi = candidates.randomElement() {
            currentNote = StaffNote(name: noteName(for: midi), midi: midi)
        }
    }

    public struct StaffMetrics {
        public let middleLineY: CGFloat
        public let lineSpacing: CGFloat
    }

    public func metrics(for clef: Clef) -> StaffMetrics {
        // Assumptions:
        // - The staff glyph is drawn centered on the middle line (B4 for treble, D3 for bass).
        // - lineSpacing is the distance (in points) between adjacent staff lines.
        switch clef {
        case .treble:
            return StaffMetrics(middleLineY: 150, lineSpacing: 12.0)
        case .bass:
            return StaffMetrics(middleLineY: 220, lineSpacing: 12.0)
        }
    }

    public func y(for midi: Int, clef: Clef) -> CGFloat {
        let m = metrics(for: clef)
        let positionStep = m.lineSpacing / 2.0 // line <-> space distance
        let step = staffStep(for: midi, clef: clef)
        return m.middleLineY - CGFloat(step) * positionStep
    }

    public var currentY: CGFloat {
        y(for: currentNote.midi, clef: currentClef)
    }

    public func ledgerLineYs(for midi: Int, clef: Clef) -> [CGFloat] {
        let m = metrics(for: clef)
        let positionStep = m.lineSpacing / 2.0
        let step = staffStep(for: midi, clef: clef)
        let steps = ledgerLineSteps(for: step)
        return steps.map { s in m.middleLineY - CGFloat(s) * positionStep }
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
