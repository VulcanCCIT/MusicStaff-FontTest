import Foundation
import SwiftData
import Observation

@Observable
final class PracticeDataService {
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Save Practice Session
    
    /// Saves a completed practice session with all attempts
    @MainActor
    func savePracticeSession(
        startDate: Date,
        endDate: Date,
        settings: PracticeSettings,
        attempts: [PracticeAttempt]
    ) throws {
        let sessionSettings = PracticeSessionSettings(from: settings)
        let persistedAttempts = attempts.map { PersistedPracticeAttempt(from: $0) }
        
        let session = PracticeSession(
            startDate: startDate,
            endDate: endDate,
            settings: sessionSettings,
            attempts: persistedAttempts
        )
        
        modelContext.insert(session)
        try modelContext.save()
        
        print("✅ Saved practice session with \(attempts.count) attempts")
    }
    
    // MARK: - Fetch Practice Sessions
    
    /// Fetches all practice sessions, sorted by date (most recent first)
    @MainActor
    func fetchAllSessions() throws -> [PracticeSession] {
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches recent practice sessions (last N sessions)
    @MainActor
    func fetchRecentSessions(limit: Int = 10) throws -> [PracticeSession] {
        var descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches practice sessions from a specific date range
    @MainActor
    func fetchSessions(from startDate: Date, to endDate: Date) throws -> [PracticeSession] {
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { session in
                session.startDate >= startDate && session.startDate <= endDate
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    // MARK: - Delete Practice Sessions
    
    /// Deletes a specific practice session
    @MainActor
    func deleteSession(_ session: PracticeSession) throws {
        modelContext.delete(session)
        try modelContext.save()
        print("🗑️ Deleted practice session from \(session.startDate)")
    }
    
    /// Deletes all practice sessions (useful for testing or reset functionality)
    @MainActor
    func deleteAllSessions() throws {
        let sessions = try fetchAllSessions()
        for session in sessions {
            modelContext.delete(session)
        }
        try modelContext.save()
        print("🗑️ Deleted all practice sessions")
    }
    
    // MARK: - Statistics and Analysis
    
    /// Gets basic statistics across all sessions
    @MainActor
    func getOverallStatistics() throws -> PracticeStatistics {
        let sessions = try fetchAllSessions()
        return calculateStatistics(from: sessions)
    }
    
    /// Gets statistics for a specific time period
    @MainActor
    func getStatistics(from startDate: Date, to endDate: Date) throws -> PracticeStatistics {
        let sessions = try fetchSessions(from: startDate, to: endDate)
        return calculateStatistics(from: sessions)
    }
    
    private func calculateStatistics(from sessions: [PracticeSession]) -> PracticeStatistics {
        guard !sessions.isEmpty else {
            return PracticeStatistics(
                totalSessions: 0,
                totalAttempts: 0,
                totalFirstTryCorrect: 0,
                totalMultipleAttempts: 0,
                averageSessionDuration: 0,
                mostRecentSession: nil,
                oldestSession: nil
            )
        }
        
        let totalSessions = sessions.count
        let totalAttempts = sessions.reduce(0) { $0 + $1.totalAttempts }
        let totalFirstTryCorrect = sessions.reduce(0) { $0 + $1.firstTryCorrect }
        let totalMultipleAttempts = sessions.reduce(0) { $0 + $1.multipleAttempts }
        let averageSessionDuration = sessions.reduce(0.0) { $0 + $1.duration } / Double(totalSessions)
        let mostRecentSession = sessions.min { $0.startDate > $1.startDate }
        let oldestSession = sessions.max { $0.startDate > $1.startDate }
        
        return PracticeStatistics(
            totalSessions: totalSessions,
            totalAttempts: totalAttempts,
            totalFirstTryCorrect: totalFirstTryCorrect,
            totalMultipleAttempts: totalMultipleAttempts,
            averageSessionDuration: averageSessionDuration,
            mostRecentSession: mostRecentSession,
            oldestSession: oldestSession
        )
    }
    
    /// Analyzes note-specific performance across all sessions
    @MainActor
    func analyzeNotePerformance() throws -> [NotePerformance] {
        let sessions = try fetchAllSessions()
        var noteStats: [String: (correct: Int, total: Int, clef: Clef, accidental: String)] = [:]
        
        for session in sessions {
            let groupedResults = Dictionary(grouping: session.attempts) { attempt in
                "\(attempt.targetMidi)_\(attempt.targetClef)_\(attempt.targetAccidental)"
            }
            
            for (key, attempts) in groupedResults {
                let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
                let firstTryCorrect = sortedAttempts.first?.outcome == PracticeOutcome.correct.rawValue

                // Derive metadata from the first attempt in this group
                let first = sortedAttempts.first!
                let clef = first.clefEnum
                let accidental = first.targetAccidental

                if noteStats[key] == nil {
                    noteStats[key] = (correct: 0, total: 0, clef: clef, accidental: accidental)
                }
                noteStats[key]!.total += 1
                if firstTryCorrect {
                    noteStats[key]!.correct += 1
                }
            }
        }
        
        return noteStats.compactMap { key, stats in
            // Key format: "<midi>_<clefString>_<accidental>" — we only trust MIDI from the key; clef/accidental come from stats
            let components = key.split(separator: "_")
            guard let midi = components.first.flatMap({ Int($0) }) else { return nil }
            let accuracy = Double(stats.correct) / Double(stats.total)
            return NotePerformance(
                midi: midi,
                clef: stats.clef,
                accidental: stats.accidental,
                correctAttempts: stats.correct,
                totalAttempts: stats.total,
                accuracy: accuracy
            )
        }.sorted { $0.accuracy < $1.accuracy } // Worst performing notes first
    }
}

// MARK: - Supporting Data Structures

struct PracticeStatistics {
    let totalSessions: Int
    let totalAttempts: Int
    let totalFirstTryCorrect: Int
    let totalMultipleAttempts: Int
    let averageSessionDuration: TimeInterval
    let mostRecentSession: PracticeSession?
    let oldestSession: PracticeSession?
    
    var overallAccuracy: Double {
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalFirstTryCorrect) / Double(totalFirstTryCorrect + totalMultipleAttempts)
    }
}

struct NotePerformance: Identifiable {
    let id = UUID()
    let midi: Int
    let clef: Clef
    let accidental: String
    let correctAttempts: Int
    let totalAttempts: Int
    let accuracy: Double
    
    var noteName: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        guard (0...127).contains(midi) else { return "—" }
        
        let noteIndex = midi % 12
        let octave = (midi / 12) - 1
        return noteNames[noteIndex] + String(octave)
    }
}
