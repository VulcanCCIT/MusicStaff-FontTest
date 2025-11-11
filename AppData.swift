import Combine
import SwiftUI

// User-selectable note head styles
enum NoteHeadStyle: String, CaseIterable, Identifiable, Hashable {
    case whole
    case half
    case quarter

    var id: String { rawValue }
}

// User-selectable practice history retention periods
enum HistoryRetentionPeriod: String, CaseIterable, Identifiable {
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"
    case threeMonths = "3 Months"
    case oneYear = "1 Year"
    case forever = "Forever"
    
    var id: String { rawValue }
    
    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .threeMonths: return 90
        case .oneYear: return 365
        case .forever: return nil
        }
    }
    
    var displayName: String { rawValue }
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

    @Published var showHints: Bool {
        didSet {
            UserDefaults.standard.set(showHints, forKey: Self.showHintsKey)
        }
    }

    private static let showHintsKey = "showHints"
    
    // MARK: - Practice History Management
    @Published var historyRetentionPeriod: HistoryRetentionPeriod {
        didSet {
            UserDefaults.standard.set(historyRetentionPeriod.rawValue, forKey: Self.historyRetentionKey)
        }
    }
    
    private static let historyRetentionKey = "historyRetentionPeriod"
    private static let lastCleanupDateKey = "lastHistoryCleanupDate"
    
    var lastCleanupDate: Date? {
        get {
            UserDefaults.standard.object(forKey: Self.lastCleanupDateKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lastCleanupDateKey)
        }
    }
    
    /// Check if automatic cleanup should run (once per day)
    func shouldPerformAutoCleanup() -> Bool {
        guard historyRetentionPeriod != .forever else { return false }
        
        guard let lastCleanup = lastCleanupDate else {
            return true // Never cleaned up before
        }
        
        // Run cleanup once per day
        let daysSinceLastCleanup = Calendar.current.dateComponents([.day], from: lastCleanup, to: Date()).day ?? 0
        return daysSinceLastCleanup >= 1
    }

    init() {
        // Note head style
        let raw = UserDefaults.standard.string(forKey: Self.noteHeadStyleKey)
            ?? NoteHeadStyle.whole.rawValue
        self.noteHeadStyle = NoteHeadStyle(rawValue: raw) ?? .whole
        self.includeAccidentals = UserDefaults.standard.object(forKey: Self.includeAccidentalsKey) as? Bool ?? false
        self.showHints = UserDefaults.standard.object(forKey: Self.showHintsKey) as? Bool ?? true // Default to showing hints

        // Calibration defaults: 61-key range (C2 to C7) unless previously set
        // This matches a standard 61-key keyboard with proper sound mapping
        let savedMin = UserDefaults.standard.object(forKey: Self.minMIDINoteKey) as? Int
        let savedMax = UserDefaults.standard.object(forKey: Self.maxMIDINoteKey) as? Int
        self.minMIDINote = savedMin ?? 36  // C2
        self.maxMIDINote = savedMax ?? 96  // C7 (61 keys total)
        
        // History retention period
        let retentionRaw = UserDefaults.standard.string(forKey: Self.historyRetentionKey)
            ?? HistoryRetentionPeriod.forever.rawValue
        self.historyRetentionPeriod = HistoryRetentionPeriod(rawValue: retentionRaw) ?? .forever
    }
}

