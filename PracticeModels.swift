import Foundation
import SwiftData

// SwiftData models for persisting practice results

@Model
final class PracticeSession {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var settings: PracticeSessionSettings
    var attempts: [PersistedPracticeAttempt]
    
    // Computed properties for convenience
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var totalAttempts: Int {
        attempts.count
    }
    
    var firstTryCorrect: Int {
        let groupedResults = Dictionary(grouping: attempts) { attempt in
            "\(attempt.targetMidi)_\(attempt.targetClef)_\(attempt.targetAccidental)"
        }
        
        return groupedResults.values.compactMap { attempts in
            let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
            return sortedAttempts.first?.outcome == PracticeOutcome.correct.rawValue
        }.filter { $0 }.count
    }
    
    var multipleAttempts: Int {
        let groupedResults = Dictionary(grouping: attempts) { attempt in
            "\(attempt.targetMidi)_\(attempt.targetClef)_\(attempt.targetAccidental)"
        }
        
        return groupedResults.values.compactMap { attempts in
            let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
            return sortedAttempts.first?.outcome != PracticeOutcome.correct.rawValue
        }.filter { $0 }.count
    }
    
    init(startDate: Date, endDate: Date, settings: PracticeSessionSettings, attempts: [PersistedPracticeAttempt]) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.settings = settings
        self.attempts = attempts
    }
}

@Model
final class PersistedPracticeAttempt {
    var id: UUID
    var targetMidi: Int
    var targetClef: String // Store as String since SwiftData doesn't handle enums directly
    var targetAccidental: String
    var playedMidi: Int
    var timestamp: Date
    var outcome: String // Store as String since SwiftData doesn't handle enums directly
    
    // Helper computed properties to convert to/from enums
    var clefEnum: Clef {
        get { Clef(rawValue: targetClef) ?? .treble }
        set { targetClef = newValue.rawValue }
    }
    
    var outcomeEnum: PracticeOutcome {
        get { PracticeOutcome(rawValue: outcome) ?? .incorrect }
        set { outcome = newValue.rawValue }
    }
    
    init(targetMidi: Int, targetClef: Clef, targetAccidental: String, playedMidi: Int, timestamp: Date, outcome: PracticeOutcome) {
        self.id = UUID()
        self.targetMidi = targetMidi
        self.targetClef = targetClef.rawValue
        self.targetAccidental = targetAccidental
        self.playedMidi = playedMidi
        self.timestamp = timestamp
        self.outcome = outcome.rawValue
    }
    
    // Convenience initializer from PracticeAttempt
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

@Model
final class PracticeSessionSettings {
    var count: Int
    var includeAccidentals: Bool
    var allowedRangeStart: Int?
    var allowedRangeEnd: Int?
    var clefMode: String // Store as String since SwiftData doesn't handle enums directly
    
    // Helper computed properties
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
    
    var clefModeEnum: ClefMode {
        get { ClefMode(rawValue: clefMode) ?? .treble }
        set { clefMode = newValue.rawValue }
    }
    
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
    
    // Convenience initializer from PracticeSettings
    convenience init(from settings: PracticeSettings) {
        self.init(
            count: settings.count,
            includeAccidentals: settings.includeAccidentals,
            allowedRange: settings.allowedRange,
            clefMode: settings.clefMode
        )
    }
}

// Extension to make PracticeOutcome RawRepresentable for easier SwiftData storage
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

// Extension to make Clef RawRepresentable for easier SwiftData storage
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
            self = .bass
        default:
            return nil
        }
    }
}

// Extension to make ClefMode RawRepresentable for easier SwiftData storage
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