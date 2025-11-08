import Combine
import SwiftUI

// User-selectable note head styles
enum NoteHeadStyle: String, CaseIterable, Identifiable, Hashable {
    case whole
    case half
    case quarter

    var id: String { rawValue }
}

// Centralized app data for user preferences
final class AppData: ObservableObject {
    // MARK: - Keyboard Calibration
    @Published var minMIDINote: Int {
        didSet { UserDefaults.standard.set(minMIDINote, forKey: Self.minMIDINoteKey) }
    }
    @Published var maxMIDINote: Int {
        didSet { UserDefaults.standard.set(maxMIDINote, forKey: Self.maxMIDINoteKey) }
    }

    static let minMIDINoteKey = "minMIDINote"
    static let maxMIDINoteKey = "maxMIDINote"

    /// Returns the calibrated MIDI range if valid (min <= max), otherwise nil.
    var calibratedRange: ClosedRange<Int>? {
        guard minMIDINote <= maxMIDINote else { return nil }
        return minMIDINote...maxMIDINote
    }

    /// Returns the number of keys in the calibrated range, if valid.
    var keyboardSize: Int? {
        guard let range = calibratedRange else { return nil }
        return range.count
    }

    /// Reset calibration to defaults (61-key range: C2 to C7)
    func clearCalibration() {
        minMIDINote = 36  // C2
        maxMIDINote = 96  // C7 (61 keys total)
    }

    @Published var noteHeadStyle: NoteHeadStyle {
        didSet {
            UserDefaults.standard.set(noteHeadStyle.rawValue, forKey: Self.noteHeadStyleKey)
        }
    }

    private static let noteHeadStyleKey = "noteHeadStyle"

    @Published var includeAccidentals: Bool {
        didSet {
            UserDefaults.standard.set(includeAccidentals, forKey: Self.includeAccidentalsKey)
        }
    }

    private static let includeAccidentalsKey = "includeAccidentals"

    init() {
        // Note head style
        let raw = UserDefaults.standard.string(forKey: Self.noteHeadStyleKey)
            ?? NoteHeadStyle.whole.rawValue
        self.noteHeadStyle = NoteHeadStyle(rawValue: raw) ?? .whole
        self.includeAccidentals = UserDefaults.standard.object(forKey: Self.includeAccidentalsKey) as? Bool ?? false

        // Calibration defaults: 61-key range (C2 to C7) unless previously set
        // This matches a standard 61-key keyboard with proper sound mapping
        let savedMin = UserDefaults.standard.object(forKey: Self.minMIDINoteKey) as? Int
        let savedMax = UserDefaults.standard.object(forKey: Self.maxMIDINoteKey) as? Int
        self.minMIDINote = savedMin ?? 36  // C2
        self.maxMIDINote = savedMax ?? 96  // C7 (61 keys total)
    }
}

