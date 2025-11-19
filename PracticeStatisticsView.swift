import SwiftUI
import SwiftData

// MARK: - PracticeStatisticsView
/// A comprehensive statistics dashboard showing lifetime practice performance.
///
/// This view provides detailed analytics across all practice sessions including:
/// - **Overall Performance**: Accuracy, session counts, and attempt metrics
/// - **Session Activity**: Total attempts, average duration, last practice date
/// - **Lifetime Note Trends**: Most common mistakes, consistently correct notes, notes needing practice
/// - **Note Performance Analysis**: Individual note accuracy sorted by performance
///
/// ## Features
/// ### Thumbnail Mode
/// The view supports an optional thumbnail mode that displays staff notation for each note.
/// This mode is:
/// - Automatically enabled on windows ≥900pt wide
/// - User-overridable via a toggle switch
/// - Stored in `@AppStorage` to persist across launches
///
/// ### Performance Cards
/// Statistics are organized into themed cards:
/// - **Overall Performance** - Accuracy, sessions, first-try correct, multiple attempts
/// - **Session Activity** - Total attempts, average duration, last practice date
/// - **Lifetime Trends** - Common mistakes, perfect notes, notes needing work
/// - **Note Analysis** - Detailed per-note accuracy breakdown
///
/// ### Debug Tools
/// In debug builds, the toolbar includes utilities for:
/// - Counting sessions in the database
/// - Creating test sessions
/// - Refreshing statistics
///
/// ## Example Usage
/// ```swift
/// NavigationView {
///     PracticeStatisticsView()
/// }
/// .modelContainer(for: PracticeSession.self)
/// ```
struct PracticeStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var practiceDataService: PracticeDataService?
    @State private var statistics: PracticeStatistics?
    @State private var notePerformance: [NotePerformance] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lifetimeIncorrectPlayedCounts: [(midi: Int, count: Int)] = []
    @State private var lifetimePlayedToMistakenTargets: [Int: [Int: Int]] = [:]

    @AppStorage("statsShowThumbnails") private var showThumbnails: Bool = false
    @AppStorage("statsUserOverrideThumbnails") private var userOverrodeThumbnailPref: Bool = false
    private let thumbnailAutoWidthThreshold: CGFloat = 900
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Toggle("Show Thumbnails", isOn: Binding(get: { showThumbnails }, set: { newValue in
                        showThumbnails = newValue
                        userOverrodeThumbnailPref = true
                    }))
                    .toggleStyle(.switch)
                    .padding(.bottom, 4)
                    Text("Automatically enabled on wide windows; you can override here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
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
            .onChange(of: width) { _, newWidth in
                if !userOverrodeThumbnailPref {
                    showThumbnails = newWidth >= thumbnailAutoWidthThreshold
                }
            }
            .onAppear {
                // Only apply width-based behavior if the user hasn't explicitly set a preference yet
                if !userOverrodeThumbnailPref {
                    // If window is wide enough, enable thumbnails; otherwise keep the saved value
                    if width >= thumbnailAutoWidthThreshold {
                        showThumbnails = true
                    }
                    // If width is small, keep whatever value is already in AppStorage (including false default)
                }
            }
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
        
        lifetimeTrendsCard
        
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
                    NotePerformanceRow(performance: performance, showThumbnail: showThumbnails)
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
    
    @ViewBuilder
    private var lifetimeTrendsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lifetime Note Trends")
                .font(.title2.bold())

            // Most common incorrect notes (played)
            VStack(alignment: .leading, spacing: 8) {
                Text("Most Common Incorrect Notes (All Time)")
                    .font(.headline)
                if lifetimeIncorrectPlayedCounts.isEmpty {
                    Text("No incorrect notes recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(lifetimeIncorrectPlayedCounts.prefix(10).enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 12) {
                                NoteOnStaffView(midi: item.midi, clef: suggestedClef(for: item.midi), accidental: accidentalForMidi(item.midi))
                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(noteName(from: item.midi)) — \(item.count) time\(item.count == 1 ? "" : "s")")
                                        .font(.title3)
                                        .bold()
                                    if let mistaken = lifetimePlayedToMistakenTargets[item.midi] {
                                        let sortedTargets = mistaken.sorted { $0.value > $1.value }
                                        let details = sortedTargets.prefix(3).map { "\(noteName(from: $0.key)) (\($0.value))" }.joined(separator: ", ")
                                        if !details.isEmpty {
                                            Text("Often mistaken for: \(details)")
                                                .font(.body)
                                                .bold()
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            // Consistently correct notes (100% accuracy)
            VStack(alignment: .leading, spacing: 8) {
                Text("Consistently Correct Notes (All Time)")
                    .font(.headline)
                let alwaysCorrect = notePerformance.filter { $0.accuracy == 1.0 }.sorted { $0.totalAttempts > $1.totalAttempts }
                if alwaysCorrect.isEmpty {
                    Text("No notes at 100% accuracy yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(alwaysCorrect.prefix(10)) { perf in
                            HStack(spacing: 12) {
                                NoteOnStaffView(midi: perf.midi, clef: perf.clef, accidental: perf.accidental)
                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(perf.noteName)
                                        .font(.title3)
                                        .bold()
                                    Text("\(perf.totalAttempts) attempt\(perf.totalAttempts == 1 ? "" : "s")")
                                        .font(.body)
                                        .bold()
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            // Notes needing practice (lowest accuracy)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes Needing Practice (All Time)")
                    .font(.headline)
                if notePerformance.isEmpty {
                    Text("No lifetime data available.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(notePerformance.prefix(10)) { perf in
                            HStack(spacing: 12) {
                                NoteOnStaffView(midi: perf.midi, clef: perf.clef, accidental: perf.accidental)
                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(perf.noteName)
                                        .font(.title3)
                                        .bold()
                                    Text("\(Int(perf.accuracy * 100))% accuracy")
                                        .font(.body)
                                        .bold()
                                        .foregroundStyle(perf.accuracy >= 0.8 ? .green : perf.accuracy >= 0.6 ? .orange : .red)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
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
                
                // Build lifetime incorrect note statistics (played vs mistaken targets)
                let allSessions = try dataService.fetchAllSessions()
                var allAttempts: [PracticeAttempt] = []
                for session in allSessions {
                    for pa in session.attempts {
                        allAttempts.append(
                            PracticeAttempt(
                                targetMidi: pa.targetMidi,
                                targetClef: pa.clefEnum,
                                targetAccidental: pa.targetAccidental,
                                playedMidi: pa.playedMidi,
                                timestamp: pa.timestamp,
                                outcome: pa.outcomeEnum
                            )
                        )
                    }
                }
                let counts = allAttempts.filter { $0.outcome == .incorrect }.reduce(into: [Int: Int]()) { dict, attempt in
                    dict[attempt.playedMidi, default: 0] += 1
                }
                lifetimeIncorrectPlayedCounts = counts.sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }.map { (key: Int, value: Int) in (midi: key, count: value) }
                var mapping: [Int: [Int: Int]] = [:]
                for a in allAttempts where a.outcome == .incorrect {
                    var inner = mapping[a.playedMidi, default: [:]]
                    inner[a.targetMidi, default: 0] += 1
                    mapping[a.playedMidi] = inner
                }
                lifetimePlayedToMistakenTargets = mapping
                
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
    
    private func suggestedClef(for midi: Int) -> Clef { midi < 60 ? .bass : .treble }
    private func accidentalForMidi(_ midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let flats = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
        let pc = midi % 12
        let raw = names[pc]
        let flatRaw = flats[pc]
        let useSharps = raw.count <= flatRaw.count
        let symbol = useSharps ? raw : flatRaw
        if symbol.contains("#") { return "♯" }
        if symbol.contains("b") { return "♭" }
        return ""
    }
    private func noteName(from midi: Int) -> String {
        let k = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard (0...127).contains(midi) else { return "—" }
        return k[midi % 12] + String((midi / 12) - 1)
    }
}

// MARK: - StatisticCard
/// A compact card view displaying a single statistic with icon and color theming.
///
/// Visual design:
/// - Icon and value aligned horizontally
/// - Color-coded to match the statistic type
/// - Rounded rectangle background
/// - Minimum height of 80pt for consistency
///
/// Used in grid layouts to create the dashboard-style statistics interface.
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

// MARK: - NotePerformanceRow
/// A detailed row displaying performance metrics for a single note.
///
/// Shows:
/// - Optional staff thumbnail (if enabled)
/// - Note name, clef, and accidental
/// - Correct/total attempt counts
/// - Accuracy percentage with color-coded badge
///   - Green: ≥80% accuracy
///   - Orange: 60-79% accuracy
///   - Red: <60% accuracy
struct NotePerformanceRow: View {
    let performance: NotePerformance
    var showThumbnail: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showThumbnail {
                NoteOnStaffView(midi: performance.midi, clef: performance.clef, accidental: performance.accidental)
                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
            }
            // Note information
            VStack(alignment: .leading, spacing: 2) {
                Text(performance.noteName)
                    .font(.title3)
                    .bold()
                
                HStack(spacing: 4) {
                    Image(systemName: performance.clef == .treble ? "music.note" : "music.note.list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(performance.clef == .treble ? "Treble" : "Bass")
                        .font(.body)
                        .bold()
                        .foregroundStyle(.primary)
                    
                    if !performance.accidental.isEmpty {
                        Text(performance.accidental)
                            .font(.body)
                            .bold()
                            .foregroundStyle(.primary)
                    }
                }
            }
            
            Spacer()
            
            // Performance metrics
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(performance.correctAttempts)/\(performance.totalAttempts)")
                    .font(.title3)
                    .bold()
                
                Text("\(performance.accuracy * 100, specifier: "%.0f")%")
                    .font(.body)
                    .bold()
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

// MARK: - NoteOnStaffView
/// A Canvas-based view that renders a musical note on a staff system.
///
/// This view is used throughout the statistics interface to provide visual
/// context for note performance data. It renders:
/// - Both treble and bass clefs (active clef opaque, inactive at 30% opacity)
/// - The target note at the correct vertical position
/// - Ledger lines for notes outside the staff
/// - Accidental symbols (♯, ♭, ♮)
///
/// ## Rendering Details
/// The view uses SwiftUI's `Canvas` API with:
/// - Coordinate transformation for centering
/// - Scaling to fit available space
/// - Same geometry constants as `PracticeNoteResultRow` for consistency
///
/// ## Example Usage
/// ```swift
/// NoteOnStaffView(midi: 60, clef: .treble, accidental: "")
///     .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
/// ```
struct NoteOnStaffView: View {
    let midi: Int
    let clef: Clef
    let accidental: String

    private let noteX: CGFloat = 166
    private let trebleStaffPoint = CGPoint(x: 155, y: 150)
    private let bassStaffPoint   = CGPoint(x: 155, y: 230)
    private let lineWidth: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            let baseHeight: CGFloat = 320
            let scale = min(size.height / baseHeight, 1.0)
            context.drawLayer { layer in
                layer.scaleBy(x: scale, y: scale)

                let virtualWidth = size.width / scale
                let virtualHeight = size.height / scale
                let centerX = virtualWidth / 2
                let centerY = virtualHeight / 2
                let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2
                let offsetX = centerX - noteX
                let offsetY = centerY - originalGroupMidY
                layer.translateBy(x: offsetX, y: offsetY)

                let vm = StaffViewModel()
                vm.setIncludeAccidentals(true)
                vm.setAllowedMIDIRange(nil)
                vm.currentClef = clef
                vm.currentNote = StaffNote(name: noteName(from: midi), midi: midi, accidental: accidental)

                let treble = MusicSymbol.trebleStaff.text()
                let bass = MusicSymbol.bassStaff.text()
                if clef == .treble {
                    layer.draw(treble, at: trebleStaffPoint)
                    layer.drawLayer { sub in
                        sub.opacity = 0.3
                        sub.draw(bass, at: bassStaffPoint)
                    }
                } else {
                    layer.drawLayer { sub in
                        sub.opacity = 0.3
                        sub.draw(treble, at: trebleStaffPoint)
                    }
                    layer.draw(bass, at: bassStaffPoint)
                }

                let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
                for y in ledgerYs {
                    var p = Path()
                    p.move(to: CGPoint(x: noteX - lineWidth/2, y: y))
                    p.addLine(to: CGPoint(x: noteX + lineWidth/2, y: y))
                    layer.stroke(p, with: .color(.primary), lineWidth: 1.2)
                }

                let acc = vm.currentNote.accidental
                let notePoint = CGPoint(x: noteX, y: vm.currentY)
                if acc == "♯" {
                    layer.draw(MusicSymbol.sharpSymbol.text(), at: CGPoint(x: noteX - 18, y: vm.currentY), anchor: .center)
                } else if acc == "♭" {
                    layer.draw(MusicSymbol.flatSymbol.text(), at: CGPoint(x: noteX - 18, y: vm.currentY), anchor: .center)
                } else if acc == "♮" {
                    layer.draw(MusicSymbol.naturalSymbol.text(), at: CGPoint(x: noteX - 18, y: vm.currentY), anchor: .center)
                }

                let noteText = MusicSymbol.quarterNoteUP.text()
                layer.draw(noteText, at: notePoint, anchor: .center)
            }
        }
    }

    private func noteName(from midi: Int) -> String {
        let k = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard (0...127).contains(midi) else { return "—" }
        return k[midi % 12] + String((midi / 12) - 1)
    }
}

#Preview {
    NavigationView {
        PracticeStatisticsView()
    }
    .modelContainer(for: PracticeSession.self, inMemory: true)
}

