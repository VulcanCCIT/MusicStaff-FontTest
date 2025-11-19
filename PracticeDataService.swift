import Foundation
import SwiftData
import Observation

// MARK: - PracticeDataService
/// A service class that manages persistence and retrieval of practice session data using SwiftData.
///
/// This service provides a comprehensive API for:
/// - Saving completed practice sessions with all attempts
/// - Fetching sessions with various filtering options
/// - Deleting individual or bulk sessions
/// - Exporting data to CSV format
/// - Computing statistics and analytics
/// - Managing database size and cleanup
///
/// ## Topics
/// ### Session Management
/// - ``savePracticeSession(startDate:endDate:settings:attempts:)``
/// - ``fetchAllSessions()``
/// - ``fetchRecentSessions(limit:)``
/// - ``fetchSessions(from:to:)``
///
/// ### Data Cleanup
/// - ``deleteSession(_:)``
/// - ``deleteAllSessions()``
/// - ``deleteSessionsOlderThan(days:)``
///
/// ### Analytics
/// - ``getOverallStatistics()``
/// - ``getStatistics(from:to:)``
/// - ``analyzeNotePerformance()``
///
/// ### Export & Utilities
/// - ``exportToCSV()``
/// - ``getDatabaseSize()``
///
/// ## Example Usage
/// ```swift
/// let service = PracticeDataService(modelContext: modelContext)
///
/// // Save a session
/// try await service.savePracticeSession(
///     startDate: sessionStart,
///     endDate: Date(),
///     settings: practiceSettings,
///     attempts: attempts
/// )
///
/// // Fetch recent sessions
/// let recentSessions = try await service.fetchRecentSessions(limit: 10)
///
/// // Get analytics
/// let stats = try await service.getOverallStatistics()
/// let notePerformance = try await service.analyzeNotePerformance()
/// ```
@Observable
final class PracticeDataService {
    /// The SwiftData model context used for all database operations.
    private var modelContext: ModelContext
    
    /// Initializes a new practice data service with the specified model context.
    ///
    /// - Parameter modelContext: The SwiftData context for database operations.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Save Practice Session
    
    /// Saves a completed practice session to persistent storage.
    ///
    /// This method converts transient practice data into persistent models and
    /// saves them to the SwiftData store. The session includes:
    /// - Start and end timestamps
    /// - Practice configuration settings
    /// - All individual practice attempts with outcomes
    ///
    /// - Parameters:
    ///   - startDate: When the practice session began.
    ///   - endDate: When the practice session completed.
    ///   - settings: The configuration used for this session (note count, clef mode, etc.).
    ///   - attempts: All practice attempts made during the session.
    ///
    /// - Throws: SwiftData errors if the save operation fails.
    ///
    /// - Note: This method must be called from the main actor.
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
    
    /// Fetches all practice sessions from the database, sorted by date (most recent first).
    ///
    /// - Returns: An array of all stored practice sessions.
    /// - Throws: SwiftData errors if the fetch operation fails.
    @MainActor
    func fetchAllSessions() throws -> [PracticeSession] {
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches the most recent practice sessions up to a specified limit.
    ///
    /// - Parameter limit: Maximum number of sessions to return (default: 10).
    /// - Returns: An array of the most recent sessions, sorted by date (newest first).
    /// - Throws: SwiftData errors if the fetch operation fails.
    @MainActor
    func fetchRecentSessions(limit: Int = 10) throws -> [PracticeSession] {
        var descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }
    
    /// Fetches practice sessions within a specific date range.
    ///
    /// - Parameters:
    ///   - startDate: The earliest date to include (inclusive).
    ///   - endDate: The latest date to include (inclusive).
    /// - Returns: Array of sessions within the date range, sorted by date (newest first).
    /// - Throws: SwiftData errors if the fetch operation fails.
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
    
    /// Deletes a specific practice session from the database.
    ///
    /// - Parameter session: The session to delete.
    /// - Throws: SwiftData errors if the delete operation fails.
    @MainActor
    func deleteSession(_ session: PracticeSession) throws {
        modelContext.delete(session)
        try modelContext.save()
        print("🗑️ Deleted practice session from \(session.startDate)")
    }
    
    /// Deletes all practice sessions from the database.
    ///
    /// Use this method carefully as it permanently removes all practice history.
    /// Useful for testing or implementing a "reset all data" feature.
    ///
    /// - Throws: SwiftData errors if the delete operation fails.
    @MainActor
    func deleteAllSessions() throws {
        let sessions = try fetchAllSessions()
        for session in sessions {
            modelContext.delete(session)
        }
        try modelContext.save()
        print("🗑️ Deleted all \(sessions.count) practice sessions")
    }
    
    /// Deletes practice sessions older than a specified number of days.
    ///
    /// This method is useful for implementing data retention policies or automatic
    /// cleanup of old practice data.
    ///
    /// - Parameter days: The age threshold in days. Sessions older than this are deleted.
    /// - Returns: The number of sessions that were deleted.
    /// - Throws: SwiftData errors if the operation fails.
    @MainActor
    func deleteSessionsOlderThan(days: Int) throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { session in
                session.startDate < cutoffDate
            }
        )
        
        let oldSessions = try modelContext.fetch(descriptor)
        let count = oldSessions.count
        
        for session in oldSessions {
            modelContext.delete(session)
        }
        
        try modelContext.save()
        print("🗑️ Deleted \(count) practice sessions older than \(days) days")
        return count
    }
    
    /// Calculates the approximate storage size of the SwiftData database.
    ///
    /// This method checks the size of:
    /// - The main SQLite database file
    /// - The write-ahead log (-wal file)
    /// - The shared memory file (-shm file)
    ///
    /// - Returns: A human-readable string representing the total database size (e.g., "2.5 MB").
    @MainActor
    func getDatabaseSize() -> String {
        // SwiftData stores in a SQLite file in the app's container
        guard let storeURL = modelContext.container.configurations.first?.url else {
            return "Unknown"
        }
        
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        // Check main database file
        if let attrs = try? fileManager.attributesOfItem(atPath: storeURL.path),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }
        
        // Check for -wal and -shm files (SQLite write-ahead log)
        let walURL = storeURL.appendingPathExtension("wal")
        let shmURL = storeURL.appendingPathExtension("shm")
        
        if let walAttrs = try? fileManager.attributesOfItem(atPath: walURL.path),
           let walSize = walAttrs[.size] as? Int64 {
            totalSize += walSize
        }
        
        if let shmAttrs = try? fileManager.attributesOfItem(atPath: shmURL.path),
           let shmSize = shmAttrs[.size] as? Int64 {
            totalSize += shmSize
        }
        
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Exports all practice sessions to CSV format for external analysis.
    ///
    /// The CSV includes the following columns:
    /// - Date, Time, Duration (seconds)
    /// - Total Notes, First Try Correct, Multiple Attempts, Accuracy
    /// - Clef Mode, Accidentals, MIDI Range
    ///
    /// - Returns: A CSV-formatted string containing all session data.
    /// - Throws: SwiftData errors if fetching sessions fails.
    @MainActor
    func exportToCSV() throws -> String {
        let sessions = try fetchAllSessions()
        
        var csv = "Date,Time,Duration (seconds),Total Notes,First Try Correct,Multiple Attempts,Accuracy,Clef Mode,Accidentals,MIDI Range\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        for session in sessions {
            let date = dateFormatter.string(from: session.startDate)
            let time = timeFormatter.string(from: session.startDate)
            let duration = Int(session.duration)
            let totalNotes = session.totalAttempts
            let firstTry = session.firstTryCorrect
            let multiple = session.multipleAttempts
            let accuracy = totalNotes > 0 ? (Double(firstTry) / Double(firstTry + multiple)) * 100 : 0
            let clefMode = session.settings.clefModeEnum.rawValue
            let accidentals = session.settings.includeAccidentals ? "Yes" : "No"
            let range = session.settings.allowedRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "Full"
            
            csv += "\(date),\(time),\(duration),\(totalNotes),\(firstTry),\(multiple),\(String(format: "%.1f%%", accuracy)),\(clefMode),\(accidentals),\(range)\n"
        }
        
        return csv
    }
    
    // MARK: - Statistics and Analysis
    
    /// Computes overall statistics across all practice sessions.
    ///
    /// - Returns: A `PracticeStatistics` object containing aggregate metrics.
    /// - Throws: SwiftData errors if fetching sessions fails.
    @MainActor
    func getOverallStatistics() throws -> PracticeStatistics {
        let sessions = try fetchAllSessions()
        return calculateStatistics(from: sessions)
    }
    
    /// Computes statistics for sessions within a specific date range.
    ///
    /// - Parameters:
    ///   - startDate: The earliest date to include.
    ///   - endDate: The latest date to include.
    /// - Returns: A `PracticeStatistics` object for the specified time period.
    /// - Throws: SwiftData errors if fetching sessions fails.
    @MainActor
    func getStatistics(from startDate: Date, to endDate: Date) throws -> PracticeStatistics {
        let sessions = try fetchSessions(from: startDate, to: endDate)
        return calculateStatistics(from: sessions)
    }
    
    /// Helper method that calculates statistics from a collection of sessions.
    ///
    /// - Parameter sessions: The sessions to analyze.
    /// - Returns: Computed `PracticeStatistics` object.
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
    
    /// Analyzes note-by-note performance across all practice sessions.
    ///
    /// This method computes accuracy statistics for each unique note (MIDI + clef + accidental)
    /// by analyzing first-try success rates across all sessions.
    ///
    /// - Returns: An array of `NotePerformance` objects sorted by accuracy (worst performing first).
    /// - Throws: SwiftData errors if fetching sessions fails.
    ///
    /// ## Performance Calculation
    /// For each unique note target, the method:
    /// 1. Groups all attempts across all sessions
    /// 2. Determines if the first attempt in each group was correct
    /// 3. Calculates accuracy as: (first-try correct count) / (total appearances)
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

/// Statistics computed across one or more practice sessions.
///
/// This struct provides aggregate metrics including session counts, attempt counts,
/// accuracy rates, and temporal information about practice history.
struct PracticeStatistics {
    /// Total number of practice sessions analyzed.
    let totalSessions: Int
    
    /// Total number of individual attempts across all sessions.
    let totalAttempts: Int
    
    /// Number of notes answered correctly on the first try.
    let totalFirstTryCorrect: Int
    
    /// Number of notes requiring multiple attempts.
    let totalMultipleAttempts: Int
    
    /// Average duration of practice sessions in seconds.
    let averageSessionDuration: TimeInterval
    
    /// The most recently completed practice session, if any.
    let mostRecentSession: PracticeSession?
    
    /// The oldest recorded practice session, if any.
    let oldestSession: PracticeSession?
    
    /// Computed overall accuracy as a percentage (0.0-1.0).
    ///
    /// Calculated as: firstTryCorrect / (firstTryCorrect + multipleAttempts)
    var overallAccuracy: Double {
        guard totalAttempts > 0 else { return 0.0 }
        return Double(totalFirstTryCorrect) / Double(totalFirstTryCorrect + totalMultipleAttempts)
    }
}

/// Performance metrics for a specific note across all practice sessions.
///
/// Tracks how well the user performs on a particular note (defined by MIDI number,
/// clef, and accidental) across all recorded practice sessions.
struct NotePerformance: Identifiable {
    /// Unique identifier for SwiftUI list rendering.
    let id = UUID()
    
    /// The MIDI note number (0-127).
    let midi: Int
    
    /// The clef context (treble or bass).
    let clef: Clef
    
    /// The accidental symbol (♯, ♭, ♮, or empty).
    let accidental: String
    
    /// Number of times this note was answered correctly on the first try.
    let correctAttempts: Int
    
    /// Total number of times this note appeared in practice.
    let totalAttempts: Int
    
    /// Accuracy rate as a decimal (0.0-1.0).
    ///
    /// Calculated as: correctAttempts / totalAttempts
    let accuracy: Double
    
    /// Human-readable note name with octave (e.g., "C4", "F#5").
    var noteName: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        guard (0...127).contains(midi) else { return "—" }
        
        let noteIndex = midi % 12
        let octave = (midi / 12) - 1
        return noteNames[noteIndex] + String(octave)
    }
}
