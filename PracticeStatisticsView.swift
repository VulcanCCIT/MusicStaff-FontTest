import SwiftUI
import SwiftData

struct PracticeStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var practiceDataService: PracticeDataService?
    @State private var statistics: PracticeStatistics?
    @State private var notePerformance: [NotePerformance] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView("Analyzing your practice data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let errorMessage = errorMessage {
                    errorStateView(errorMessage)
                } else if let stats = statistics {
                    statisticsContent(stats)
                } else {
                    emptyStateView
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("Practice Statistics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Debug: Count Sessions") {
                        debugCountSessions()
                    }
                    Button("Debug: Create Test Session") {
                        debugCreateTestSession()
                    }
                    Button("Refresh") {
                        isLoading = true
                        errorMessage = nil
                        statistics = nil
                        notePerformance = []
                        loadStatistics()
                    }
                } label: {
                    Image(systemName: "gear")
                }
            }
            #endif
        }
        .onAppear {
            setupDataService()
            loadStatistics()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Statistics Available")
                .font(.title2.bold())
            
            Text("Complete some practice sessions to see your performance statistics.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Error Loading Statistics")
                .font(.title2.bold())
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                isLoading = true
                errorMessage = nil
                loadStatistics()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private func statisticsContent(_ stats: PracticeStatistics) -> some View {
        // Overall Performance Card
        overallPerformanceCard(stats)
        
        // Session Activity Card
        sessionActivityCard(stats)
        
        // Note Performance Analysis
        if !notePerformance.isEmpty {
            notePerformanceCard
        }
    }
    
    @ViewBuilder
    private func overallPerformanceCard(_ stats: PracticeStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overall Performance")
                .font(.title2.bold())
            
            // Debug: Let's see what values we have
            Text("Debug: Sessions=\(stats.totalSessions), Accuracy=\(stats.overallAccuracy), FirstTry=\(stats.totalFirstTryCorrect)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                StatisticCard(
                    title: "Accuracy",
                    value: String(format: "%.1f%%", stats.overallAccuracy * 100),
                    icon: "target",
                    color: stats.overallAccuracy >= 0.8 ? .green : stats.overallAccuracy >= 0.6 ? .orange : .red
                )
                
                StatisticCard(
                    title: "Total Sessions",
                    value: "\(stats.totalSessions)",
                    icon: "music.note.list",
                    color: .blue
                )
                
                StatisticCard(
                    title: "First Try Correct",
                    value: "\(stats.totalFirstTryCorrect)",
                    icon: "checkmark.circle",
                    color: .green
                )
                
                StatisticCard(
                    title: "Multiple Attempts",
                    value: "\(stats.totalMultipleAttempts)",
                    icon: "arrow.clockwise",
                    color: .orange
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func sessionActivityCard(_ stats: PracticeStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Activity")
                .font(.title2.bold())
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                StatisticCard(
                    title: "Total Attempts",
                    value: "\(stats.totalAttempts)",
                    icon: "music.note",
                    color: .purple
                )
                
                StatisticCard(
                    title: "Avg. Duration",
                    value: formatDuration(stats.averageSessionDuration),
                    icon: "clock",
                    color: .teal
                )
            }
            
            if let mostRecent = stats.mostRecentSession {
                HStack {
                    Text("Last Practice:")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(for: mostRecent.startDate, relativeTo: Date()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var notePerformanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Note Performance Analysis")
                .font(.title2.bold())
            
            Text("Notes that need more practice (lowest accuracy first):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            LazyVStack(spacing: 8) {
                ForEach(notePerformance.prefix(10)) { performance in
                    NotePerformanceRow(performance: performance)
                }
            }
            
            if notePerformance.count > 10 {
                Text("Showing top 10 notes needing practice. Total notes analyzed: \(notePerformance.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func setupDataService() {
        practiceDataService = PracticeDataService(modelContext: modelContext)
    }
    
    private func loadStatistics() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { 
                    errorMessage = "Data service not initialized"
                    isLoading = false
                    return 
                }
                
                print("📊 Loading statistics...")
                let stats = try dataService.getOverallStatistics()
                let noteStats = try dataService.analyzeNotePerformance()
                
                print("📊 Statistics loaded:")
                print("  - Total Sessions: \(stats.totalSessions)")
                print("  - Total Attempts: \(stats.totalAttempts)")
                print("  - First Try Correct: \(stats.totalFirstTryCorrect)")
                print("  - Multiple Attempts: \(stats.totalMultipleAttempts)")
                print("  - Overall Accuracy: \(stats.overallAccuracy)")
                print("  - Notes Analyzed: \(noteStats.count)")
                
                statistics = stats
                notePerformance = noteStats
                isLoading = false
                
                if stats.totalSessions == 0 {
                    print("⚠️ No practice sessions found in database")
                }
            } catch {
                print("❌ Failed to load statistics: \(error)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    #if DEBUG
    private func debugCountSessions() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                let sessions = try dataService.fetchAllSessions()
                print("🔍 DEBUG: Found \(sessions.count) practice sessions in database")
                
                for (index, session) in sessions.enumerated() {
                    print("🔍 Session \(index + 1): \(session.startDate) - \(session.attempts.count) attempts")
                }
            } catch {
                print("🔍 DEBUG ERROR: \(error)")
            }
        }
    }
    
    private func debugCreateTestSession() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                
                // Create a test session with some mock data
                let testSettings = PracticeSettings(
                    count: 3,
                    includeAccidentals: false,
                    allowedRange: 60...72,
                    clefMode: .treble
                )
                
                let testAttempts = [
                    PracticeAttempt(
                        targetMidi: 60, targetClef: .treble, targetAccidental: "",
                        playedMidi: 60, timestamp: Date(), outcome: .correct
                    ),
                    PracticeAttempt(
                        targetMidi: 64, targetClef: .treble, targetAccidental: "",
                        playedMidi: 65, timestamp: Date(), outcome: .incorrect
                    ),
                    PracticeAttempt(
                        targetMidi: 64, targetClef: .treble, targetAccidental: "",
                        playedMidi: 64, timestamp: Date(), outcome: .correct
                    )
                ]
                
                try dataService.savePracticeSession(
                    startDate: Date().addingTimeInterval(-300), // 5 minutes ago
                    endDate: Date(),
                    settings: testSettings,
                    attempts: testAttempts
                )
                
                print("✅ DEBUG: Created test practice session")
                
                // Refresh the view
                isLoading = true
                errorMessage = nil
                statistics = nil
                notePerformance = []
                loadStatistics()
                
            } catch {
                print("❌ DEBUG ERROR creating test session: \(error)")
            }
        }
    }
    #endif
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                
                Spacer()
                
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(color)
            }
            
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
        }
        .padding(12)
        .frame(minHeight: 80)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            print("🔍 StatisticCard for '\(title)' with value '\(value)'")
        }
    }
}

struct NotePerformanceRow: View {
    let performance: NotePerformance
    
    var body: some View {
        HStack {
            // Note information
            VStack(alignment: .leading, spacing: 2) {
                Text(performance.noteName)
                    .font(.subheadline.weight(.semibold))
                
                HStack(spacing: 4) {
                    Image(systemName: performance.clef == .treble ? "music.note" : "music.note.list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(performance.clef == .treble ? "Treble" : "Bass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !performance.accidental.isEmpty {
                        Text(performance.accidental)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Performance metrics
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(performance.correctAttempts)/\(performance.totalAttempts)")
                    .font(.subheadline.weight(.medium))
                
                Text("\(performance.accuracy * 100, specifier: "%.0f")%")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        performance.accuracy >= 0.8 ? Color.green.opacity(0.2) :
                        performance.accuracy >= 0.6 ? Color.orange.opacity(0.2) : Color.red.opacity(0.2)
                    )
                    .foregroundStyle(
                        performance.accuracy >= 0.8 ? .green :
                        performance.accuracy >= 0.6 ? .orange : .red
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationView {
        PracticeStatisticsView()
    }
    .modelContainer(for: PracticeSession.self, inMemory: true)
}