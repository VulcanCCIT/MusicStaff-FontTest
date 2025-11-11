//import Testing
//import SwiftData
//@testable import MusicStaff_FontTest
//
//@Suite("Practice Data Models Tests")
//struct PracticeDataModelsTests {
//    
//    @Test("PracticeAttempt conversion to PersistedPracticeAttempt")
//    func testPracticeAttemptConversion() async throws {
//        // Given
//        let originalAttempt = PracticeAttempt(
//            targetMidi: 60,
//            targetClef: .treble,
//            targetAccidental: "♯",
//            playedMidi: 62,
//            timestamp: Date(),
//            outcome: .correct
//        )
//        
//        // When
//        let persistedAttempt = PersistedPracticeAttempt(from: originalAttempt)
//        
//        // Then
//        #expect(persistedAttempt.targetMidi == originalAttempt.targetMidi)
//        #expect(persistedAttempt.clefEnum == originalAttempt.targetClef)
//        #expect(persistedAttempt.targetAccidental == originalAttempt.targetAccidental)
//        #expect(persistedAttempt.playedMidi == originalAttempt.playedMidi)
//        #expect(persistedAttempt.outcomeEnum == originalAttempt.outcome)
//    }
//    
//    @Test("PracticeSettings conversion to PracticeSessionSettings")
//    func testPracticeSettingsConversion() async throws {
//        // Given
//        let originalSettings = PracticeSettings(
//            count: 10,
//            includeAccidentals: true,
//            allowedRange: 60...72,
//            clefMode: .treble
//        )
//        
//        // When
//        let persistedSettings = PracticeSessionSettings(from: originalSettings)
//        
//        // Then
//        #expect(persistedSettings.count == originalSettings.count)
//        #expect(persistedSettings.includeAccidentals == originalSettings.includeAccidentals)
//        #expect(persistedSettings.allowedRange == originalSettings.allowedRange)
//        #expect(persistedSettings.clefModeEnum == originalSettings.clefMode)
//    }
//    
//    @Test("PracticeSession calculations")
//    func testPracticeSessionCalculations() async throws {
//        // Given
//        let startDate = Date()
//        let endDate = startDate.addingTimeInterval(300) // 5 minutes later
//        
//        let attempts = [
//            PersistedPracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: startDate.addingTimeInterval(1), outcome: .correct),
//            PersistedPracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 62, timestamp: startDate.addingTimeInterval(2), outcome: .incorrect),
//            PersistedPracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: startDate.addingTimeInterval(3), outcome: .correct),
//            PersistedPracticeAttempt(targetMidi: 64, targetClef: .treble, targetAccidental: "", playedMidi: 64, timestamp: startDate.addingTimeInterval(4), outcome: .correct)
//        ]
//        
//        let settings = PracticeSessionSettings(count: 2, includeAccidentals: false, allowedRange: nil, clefMode: .treble)
//        
//        // When
//        let session = PracticeSession(startDate: startDate, endDate: endDate, settings: settings, attempts: attempts)
//        
//        // Then
//        #expect(session.duration == 300.0)
//        #expect(session.totalAttempts == 4)
//        #expect(session.firstTryCorrect == 2) // C4 first attempt was correct, E4 first attempt was correct
//        #expect(session.multipleAttempts == 0) // No notes required multiple attempts to get right on first try
//    }
//}
//
//@Suite("Practice Data Service Tests")
//struct PracticeDataServiceTests {
//    
//    @Test("Save and fetch practice session")
//    func testSaveAndFetchSession() async throws {
//        // Given - Create in-memory model container
//        let config = ModelConfiguration(isStoredInMemoryOnly: true)
//        let container = try ModelContainer(for: PracticeSession.self, configurations: config)
//        let context = ModelContext(container)
//        let dataService = PracticeDataService(modelContext: context)
//        
//        let settings = PracticeSettings(count: 3, includeAccidentals: false, allowedRange: nil, clefMode: .random)
//        let attempts = [
//            PracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: Date(), outcome: .correct),
//            PracticeAttempt(targetMidi: 64, targetClef: .treble, targetAccidental: "", playedMidi: 62, timestamp: Date().addingTimeInterval(1), outcome: .incorrect),
//            PracticeAttempt(targetMidi: 64, targetClef: .treble, targetAccidental: "", playedMidi: 64, timestamp: Date().addingTimeInterval(2), outcome: .correct)
//        ]
//        
//        let startDate = Date().addingTimeInterval(-300)
//        let endDate = Date()
//        
//        // When - Save session
//        try await dataService.savePracticeSession(
//            startDate: startDate,
//            endDate: endDate,
//            settings: settings,
//            attempts: attempts
//        )
//        
//        // Then - Fetch and verify
//        let sessions = try await dataService.fetchAllSessions()
//        #expect(sessions.count == 1)
//        
//        let session = sessions.first!
//        #expect(session.totalAttempts == 3)
//        #expect(session.settings.count == 3)
//        #expect(session.attempts.count == 3)
//    }
//    
//    @Test("Note performance analysis")
//    func testNotePerformanceAnalysis() async throws {
//        // Given - Create in-memory model container with test data
//        let config = ModelConfiguration(isStoredInMemoryOnly: true)
//        let container = try ModelContainer(for: PracticeSession.self, configurations: config)
//        let context = ModelContext(container)
//        let dataService = PracticeDataService(modelContext: context)
//        
//        // Create attempts where C4 is always correct, D4 needs multiple attempts
//        let attempts = [
//            PracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: Date(), outcome: .correct), // C4 correct
//            PracticeAttempt(targetMidi: 62, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: Date().addingTimeInterval(1), outcome: .incorrect), // D4 wrong
//            PracticeAttempt(targetMidi: 62, targetClef: .treble, targetAccidental: "", playedMidi: 62, timestamp: Date().addingTimeInterval(2), outcome: .correct), // D4 correct
//            PracticeAttempt(targetMidi: 60, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: Date().addingTimeInterval(3), outcome: .correct) // C4 correct again
//        ]
//        
//        let settings = PracticeSettings(count: 2, includeAccidentals: false, allowedRange: nil, clefMode: .treble)
//        
//        // Save the session
//        try await dataService.savePracticeSession(
//            startDate: Date().addingTimeInterval(-300),
//            endDate: Date(),
//            settings: settings,
//            attempts: attempts
//        )
//        
//        // When - Analyze note performance
//        let notePerformance = try await dataService.analyzeNotePerformance()
//        
//        // Then - D4 should have lower accuracy than C4
//        #expect(notePerformance.count == 2)
//        
//        let c4Performance = notePerformance.first { $0.midi == 60 }
//        let d4Performance = notePerformance.first { $0.midi == 62 }
//        
//        #expect(c4Performance != nil)
//        #expect(d4Performance != nil)
//        
//        #expect(c4Performance!.accuracy == 1.0) // 100% - both attempts were correct on first try
//        #expect(d4Performance!.accuracy == 0.0) // 0% - first attempt was incorrect
//        
//        // D4 should appear first in the sorted list (worst performing first)
//        #expect(notePerformance.first?.midi == 62)
//    }
//}
