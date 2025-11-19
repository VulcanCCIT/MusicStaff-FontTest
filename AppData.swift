import Combine
import SwiftUI

// MARK: - Note Head Style

/// Visual style options for musical note heads displayed on the staff.
///
/// Different note styles are used in music notation to indicate different durations,
/// though in this app they're primarily aesthetic choices for practice mode.
enum NoteHeadStyle: String, CaseIterable, Identifiable, Hashable {
    /// Whole note (open circle) - typically indicates 4 beats
    case whole
    
    /// Half note (open circle with stem) - typically indicates 2 beats
    case half
    
    /// Quarter note (filled circle with stem) - typically indicates 1 beat
    case quarter

    var id: String { rawValue }
}

// MARK: - History Retention Period

/// Time periods for automatic cleanup of old practice session data.
///
/// Users can choose how long to retain practice history before automatic deletion.
/// This helps manage storage and keep the history view focused on recent practice.
enum HistoryRetentionPeriod: String, CaseIterable, Identifiable {
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"
    case threeMonths = "3 Months"
    case oneYear = "1 Year"
    case forever = "Forever"
    
    var id: String { rawValue }
    
    /// Number of days to retain data, or `nil` for forever.
    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .threeMonths: return 90
        case .oneYear: return 365
        case .forever: return nil
        }
    }
    
    /// Human-readable name for display in UI.
    var displayName: String { rawValue }
}

// MARK: - App Data

/// Centralized storage for app-wide user preferences and settings.
///
/// `AppData` manages all persistent user preferences using `UserDefaults`
/// and publishes changes via `@Published` properties for SwiftUI reactivity.
///
/// ## Categories of Settings
///
/// ### Keyboard Calibration
/// - MIDI note range (min/max) for the virtual keyboard
/// - Automatically saved when changed
/// - Can be reset to defaults (36-96, C2-C7, 61 keys)
///
/// ### Visual Preferences
/// - Note head style (whole, half, quarter)
/// - Whether to include accidentals (sharps/flats) in practice
/// - Whether to show note name hints on keys
///
/// ### Practice History
/// - Retention period for automatic cleanup
/// - Last cleanup date tracking
///
/// ## Usage
///
/// Create once at app launch and inject as an environment object:
/// ```swift
/// @StateObject private var appData = AppData()
/// // ...
/// .environmentObject(appData)
/// ```
final class AppData: ObservableObject {
    // MARK: - Keyboard Calibration
    
    /// Lowest MIDI note number in the calibrated keyboard range.
    ///
    /// Default: 36 (C2). Automatically persisted to UserDefaults on change.
    @Published var minMIDINote: Int {
        didSet { UserDefaults.standard.set(minMIDINote, forKey: Self.minMIDINoteKey) }
    }
    
    /// Highest MIDI note number in the calibrated keyboard range.
    ///
    /// Default: 96 (C7). Automatically persisted to UserDefaults on change.
    @Published var maxMIDINote: Int {
        didSet { UserDefaults.standard.set(maxMIDINote, forKey: Self.maxMIDINoteKey) }
    }

    private static let minMIDINoteKey = "minMIDINote"
    private static let maxMIDINoteKey = "maxMIDINote"

    /// The calibrated MIDI range if valid (min ≤ max), otherwise `nil`.
    ///
    /// Returns a `ClosedRange<Int>` representing the playable keyboard range.
    /// Returns `nil` if calibration is invalid (min > max).
    var calibratedRange: ClosedRange<Int>? {
        guard minMIDINote <= maxMIDINote else { return nil }
        return minMIDINote...maxMIDINote
    }

    /// Number of keys in the calibrated range, or `nil` if range is invalid.
    ///
    /// For example, a 61-key keyboard (C2-C7) returns 61.
    var keyboardSize: Int? {
        guard let range = calibratedRange else { return nil }
        return range.count
    }

    /// Reset calibration to defaults (61-key range: C2 to C7).
    ///
    /// This matches a standard 61-key MIDI keyboard and provides good
    /// coverage of the musical range used in most practice scenarios.
    func clearCalibration() {
        minMIDINote = 36  // C2 (MIDI note 36)
        maxMIDINote = 96  // C7 (MIDI note 96) - 61 keys total
    }

    // MARK: - Visual Preferences
    
    /// The visual style to use for note heads on the musical staff.
    ///
    /// Options: whole, half, or quarter note appearance.
    /// Automatically persisted to UserDefaults on change.
    @Published var noteHeadStyle: NoteHeadStyle {
        didSet {
            UserDefaults.standard.set(noteHeadStyle.rawValue, forKey: Self.noteHeadStyleKey)
        }
    }

    private static let noteHeadStyleKey = "noteHeadStyle"

    /// Whether to include accidentals (sharps/flats) in practice mode.
    ///
    /// When `true`, practice sessions may include notes with sharps or flats.
    /// When `false`, only natural notes (white keys) are used.
    @Published var includeAccidentals: Bool {
        didSet {
            UserDefaults.standard.set(includeAccidentals, forKey: Self.includeAccidentalsKey)
        }
    }

    private static let includeAccidentalsKey = "includeAccidentals"

    /// Whether to show note name hints (C4, D5, etc.) on piano keys.
    ///
    /// When `true`, white keys display their scientific pitch notation.
    /// Helps beginners learn note positions.
    @Published var showHints: Bool {
        didSet {
            UserDefaults.standard.set(showHints, forKey: Self.showHintsKey)
        }
    }

    private static let showHintsKey = "showHints"
    
    // MARK: - Practice History Management
    
    /// How long to retain practice session data before automatic cleanup.
    ///
    /// Cleanup runs automatically once per day when the app launches.
    /// Set to `.forever` to disable automatic cleanup.
    @Published var historyRetentionPeriod: HistoryRetentionPeriod {
        didSet {
            UserDefaults.standard.set(historyRetentionPeriod.rawValue, forKey: Self.historyRetentionKey)
        }
    }
    
    private static let historyRetentionKey = "historyRetentionPeriod"
    private static let lastCleanupDateKey = "lastHistoryCleanupDate"
    
    /// Date when practice history was last cleaned up.
    var lastCleanupDate: Date? {
        get {
            UserDefaults.standard.object(forKey: Self.lastCleanupDateKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lastCleanupDateKey)
        }
    }
    
    /// Determines if automatic cleanup should run based on last cleanup date.
    ///
    /// Returns `true` if:
    /// - Retention period is not set to "forever"
    /// - Never been cleaned up before, OR
    /// - At least 1 day has passed since last cleanup
    ///
    /// - Returns: `true` if cleanup should be performed
    func shouldPerformAutoCleanup() -> Bool {
        guard historyRetentionPeriod != .forever else { return false }
        
        guard let lastCleanup = lastCleanupDate else {
            return true // Never cleaned up before
        }
        
        // Run cleanup once per day
        let daysSinceLastCleanup = Calendar.current.dateComponents([.day], from: lastCleanup, to: Date()).day ?? 0
        return daysSinceLastCleanup >= 1
    }

    // MARK: - Initialization
    
    /// Initialize AppData with values from UserDefaults or sensible defaults.
    init() {
        // Load note head style preference
        let raw = UserDefaults.standard.string(forKey: Self.noteHeadStyleKey)
            ?? NoteHeadStyle.whole.rawValue
        self.noteHeadStyle = NoteHeadStyle(rawValue: raw) ?? .whole
        
        // Load accidentals preference (default: false)
        self.includeAccidentals = UserDefaults.standard.object(forKey: Self.includeAccidentalsKey) as? Bool ?? false
        
        // Load hints preference (default: true - show hints for beginners)
        self.showHints = UserDefaults.standard.object(forKey: Self.showHintsKey) as? Bool ?? true

        // Load keyboard calibration (default: 61-key range from C2 to C7)
        // This matches a standard 61-key keyboard with proper sound mapping
        let savedMin = UserDefaults.standard.object(forKey: Self.minMIDINoteKey) as? Int
        let savedMax = UserDefaults.standard.object(forKey: Self.maxMIDINoteKey) as? Int
        self.minMIDINote = savedMin ?? 36  // C2 (MIDI note 36)
        self.maxMIDINote = savedMax ?? 96  // C7 (MIDI note 96, 61 keys total)
        
        // Load history retention period preference
        let retentionRaw = UserDefaults.standard.string(forKey: Self.historyRetentionKey)
            ?? HistoryRetentionPeriod.forever.rawValue
        self.historyRetentionPeriod = HistoryRetentionPeriod(rawValue: retentionRaw) ?? .forever
    }
}

