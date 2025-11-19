import Foundation
import SwiftData

// MARK: - SwiftData Practice Models

/// SwiftData models for persisting practice session results and history.
///
/// These models enable long-term storage of practice data using SwiftData's
/// modern persistence framework. Data is automatically synced across devices
/// via iCloud (when enabled).
///
/// ## Model Hierarchy
///
/// - ``PracticeSession``: Top-level container for a complete practice session
///   - ``PersistedPracticeAttempt``: Individual note attempts within the session
///   - ``PracticeSessionSettings``: Configuration used for the session
///
/// ## Design Notes
///
/// Enums are stored as strings since SwiftData doesn't natively support enum types.
/// Computed properties provide convenient conversion to/from enum types.

// MARK: - Practice Session

/// A complete practice session with metadata, settings, and all attempts.
///
/// Each session represents one continuous practice period from start to finish.
/// Sessions track:
/// - Duration
/// - Total attempts
/// - Success metrics (first-try correct, multiple attempts needed)
/// - Settings used
@Model
final class PracticeSession {
    /// Unique identifier for this session.
    var id: UUID
    
    /// When the practice session started.
    var startDate: Date
    
    /// When the practice session ended.
    var endDate: Date
    
    /// Settings and configuration used for this session.
    var settings: PracticeSessionSettings
    
    /// All note attempts made during this session.
    var attempts: [PersistedPracticeAttempt]
    
    // MARK: - Computed Properties
    
    /// Duration of the practice session in seconds.
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    /// Total number of note attempts made.
    var totalAttempts: Int {
        attempts.count
    }
    
    /// Number of notes answered correctly on the first try.
    ///
    /// Groups attempts by target note and checks if the first attempt
    /// for each unique target was correct.
    var firstTryCorrect: Int {
        let groupedResults = Dictionary(grouping: attempts) { attempt in
            "\(attempt.targetMidi)_\(attempt.targetClef)_\(attempt.targetAccidental)"
        }
        
        return groupedResults.values.compactMap { attempts in
            let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
            return sortedAttempts.first?.outcome == PracticeOutcome.correct.rawValue
        }.filter { $0 }.count
    }
    
    /// Number of notes that required multiple attempts to answer correctly.
    ///
    /// Groups attempts by target note and checks if the first attempt
    /// was incorrect (requiring additional tries).
    var multipleAttempts: Int {
        let groupedResults = Dictionary(grouping: attempts) { attempt in
            "\(attempt.targetMidi)_\(attempt.targetClef)_\(attempt.targetAccidental)"
        }
        
        return groupedResults.values.compactMap { attempts in
            let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
            return sortedAttempts.first?.outcome != PracticeOutcome.correct.rawValue
        }.filter { $0 }.count
    }
    
    /// Initialize a new practice session.
    ///
    /// - Parameters:
    ///   - startDate: Session start time
    ///   - endDate: Session end time
    ///   - settings: Configuration used
    ///   - attempts: All attempts made during session
    init(startDate: Date, endDate: Date, settings: PracticeSessionSettings, attempts: [PersistedPracticeAttempt]) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.settings = settings
        self.attempts = attempts
    }
}

// MARK: - Persisted Practice Attempt

/// A single note attempt within a practice session.
///
/// Records everything needed to analyze practice performance:
/// - What note was shown (target)
/// - What note was played
/// - When it happened
/// - Whether it was correct
@Model
final class PersistedPracticeAttempt {
    /// Unique identifier for this attempt.
    var id: UUID
    
    /// MIDI note number of the target note (what should have been played).
    var targetMidi: Int
    
    /// Clef the target was displayed in (stored as string for SwiftData).
    var targetClef: String
    
    /// Accidental symbol for the target ("", "♯", "♭").
    var targetAccidental: String
    
    /// MIDI note number that was actually played.
    var playedMidi: Int
    
    /// When this attempt occurred.
    var timestamp: Date
    
    /// Outcome of the attempt (stored as string for SwiftData).
    var outcome: String
    
    // MARK: - Enum Conversions
    
    /// Convert clef string to enum for easier use in code.
    var clefEnum: Clef {
        get { Clef(rawValue: targetClef) ?? .treble }
        set { targetClef = newValue.rawValue }
    }
    
    /// Convert outcome string to enum for easier use in code.
    var outcomeEnum: PracticeOutcome {
        get { PracticeOutcome(rawValue: outcome) ?? .incorrect }
        set { outcome = newValue.rawValue }
    }
    
    /// Initialize a new persisted attempt.
    ///
    /// - Parameters:
    ///   - targetMidi: Target MIDI note number
    ///   - targetClef: Clef the note was displayed in
    ///   - targetAccidental: Accidental symbol
    ///   - playedMidi: MIDI note number that was played
    ///   - timestamp: When the attempt occurred
    ///   - outcome: Whether it was correct
    init(targetMidi: Int, targetClef: Clef, targetAccidental: String, playedMidi: Int, timestamp: Date, outcome: PracticeOutcome) {
        self.id = UUID()
        self.targetMidi = targetMidi
        self.targetClef = targetClef.rawValue
        self.targetAccidental = targetAccidental
        self.playedMidi = playedMidi
        self.timestamp = timestamp
        self.outcome = outcome.rawValue
    }
    
    /// Create a persisted attempt from a transient `PracticeAttempt`.
    ///
    /// Convenience initializer for converting in-memory attempts to persistent storage.
    convenience init(from attempt: PracticeAttempt) {
        self.init(
            targetMidi: attempt.targetMidi,
            targetClef: attempt.targetClef,
            targetAccidental: attempt.targetAccidental,
            playedMidi: attempt.playedMidi,
            timestamp: attempt.timestamp,
            outcome: attempt.outcome
        )
    }
}

// MARK: - Practice Session Settings

/// Configuration settings for a practice session.
///
/// Stores all the parameters that define how a practice session operates:
/// - Number of questions
/// - Whether accidentals are included
/// - MIDI range restrictions
/// - Clef mode
@Model
final class PracticeSessionSettings {
    /// Number of notes in the practice session.
    var count: Int
    
    /// Whether accidentals (sharps/flats) are included.
    var includeAccidentals: Bool
    
    /// Lower bound of allowed MIDI range (nil = no restriction).
    var allowedRangeStart: Int?
    
    /// Upper bound of allowed MIDI range (nil = no restriction).
    var allowedRangeEnd: Int?
    
    /// Clef mode (stored as string for SwiftData).
    var clefMode: String
    
    // MARK: - Computed Properties
    
    /// Allowed MIDI range as a `ClosedRange` if both bounds are set.
    var allowedRange: ClosedRange<Int>? {
        get {
            guard let start = allowedRangeStart, let end = allowedRangeEnd else { return nil }
            return start...end
        }
        set {
            if let range = newValue {
                allowedRangeStart = range.lowerBound
                allowedRangeEnd = range.upperBound
            } else {
                allowedRangeStart = nil
                allowedRangeEnd = nil
            }
        }
    }
    
    /// Convert clef mode string to enum for easier use in code.
    var clefModeEnum: ClefMode {
        get { ClefMode(rawValue: clefMode) ?? .treble }
        set { clefMode = newValue.rawValue }
    }
    
    /// Initialize new practice session settings.
    ///
    /// - Parameters:
    ///   - count: Number of notes in session
    ///   - includeAccidentals: Whether to include sharps/flats
    ///   - allowedRange: Optional MIDI range restriction
    ///   - clefMode: Which clef(s) to use
    init(count: Int, includeAccidentals: Bool, allowedRange: ClosedRange<Int>?, clefMode: ClefMode) {
        self.count = count
        self.includeAccidentals = includeAccidentals
        if let range = allowedRange {
            self.allowedRangeStart = range.lowerBound
            self.allowedRangeEnd = range.upperBound
        } else {
            self.allowedRangeStart = nil
            self.allowedRangeEnd = nil
        }
        self.clefMode = clefMode.rawValue
    }
    
    /// Create settings from a transient `PracticeSettings` object.
    ///
    /// Convenience initializer for converting in-memory settings to persistent storage.
    convenience init(from settings: PracticeSettings) {
        self.init(
            count: settings.count,
            includeAccidentals: settings.includeAccidentals,
            allowedRange: settings.allowedRange,
            clefMode: settings.clefMode
        )
    }
}

// MARK: - RawRepresentable Extensions

/// Make `PracticeOutcome` storable in SwiftData via string representation.
extension PracticeOutcome: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .correct:
            return "correct"
        case .incorrect:
            return "incorrect"
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case "correct":
            self = .correct
        case "incorrect":
            self = .incorrect
        default:
            return nil
        }
    }
}

/// Make `Clef` storable in SwiftData via string representation.
extension Clef: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .treble:
            return "treble"
        case .bass:
            return "bass"
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case "treble":
            self = .treble
        case "bass":
            self = .bass"
        default:
            return nil
        }
    }
}

/// Make `ClefMode` storable in SwiftData via string representation.
extension ClefMode: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .treble:
            return "treble"
        case .bass:
            return "bass"
        case .random:
            return "random"
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case "treble":
            self = .treble
        case "bass":
            self = .bass
        case "random":
            self = .random
        default:
            return nil
        }
    }
}