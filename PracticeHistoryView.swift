import SwiftUI
import SwiftData

struct PracticeHistoryView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    
    @State private var practiceDataService: PracticeDataService?
    @State private var sessions: [PracticeSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: PracticeSession?
    @State private var showingStatistics = false
    @State private var selectedSession: PracticeSession?
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading practice history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    errorStateView(errorMessage)
                } else if sessions.isEmpty {
                    emptyStateView
                } else {
                    practiceSessionsList
                }
            }
            .frame(minWidth: 350, maxWidth: 500, minHeight: 400)
            .navigationTitle("Practice History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                print("🔍 PracticeHistoryView appeared - isLoading: \(isLoading), sessions.count: \(sessions.count), errorMessage: \(errorMessage ?? "nil")")
            }
            .onChange(of: sessions) { oldValue, newValue in
                print("🔍 Sessions changed from \(oldValue.count) to \(newValue.count)")
            }
            .onChange(of: isLoading) { oldValue, newValue in
                print("🔍 Loading changed from \(oldValue) to \(newValue)")
            }
        } detail: {
            // Show selected session detail or placeholder
            if let session = selectedSession {
                PracticeSessionDetailView(session: session)
            } else {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Select a Practice Session")
                        .font(.title2.bold())
                    
                    Text("Click on a session from the list to view detailed results.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    navigationPath.removeLast()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Statistics") {
                    showingStatistics = true
                }
                .buttonStyle(.bordered)
            }
        }
        .alert("Delete Session", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            if let session = sessionToDelete {
                Text("Are you sure you want to delete the practice session from \(session.startDate, style: .date) at \(session.startDate, style: .time)?")
            }
        }
        .onAppear {
            setupDataService()
            loadSessions()
        }
        .sheet(isPresented: $showingStatistics) {
            NavigationView {
                PracticeStatisticsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingStatistics = false
                            }
                        }
                    }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Practice Sessions")
                .font(.title2.bold())
            
            Text("Complete a practice session to see your results here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Error Loading History")
                .font(.title2.bold())
            
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                isLoading = true
                errorMessage = nil
                loadSessions()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var practiceSessionsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions (\(sessions.count))")
                    .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.quaternary)
            
            List(selection: $selectedSession) {
                ForEach(sessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.startDate, style: .date)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(session.startDate, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                
                                let accuracy = session.totalAttempts > 0 ? 
                                    (Double(session.firstTryCorrect) / Double(session.firstTryCorrect + session.multipleAttempts)) * 100 : 0
                                Text("\(accuracy, specifier: "%.0f")%")
                                    .font(.headline.bold())
                                    .foregroundStyle(accuracy >= 80 ? .green : accuracy >= 60 ? .orange : .red)
                            }
                            
                            HStack(spacing: 12) {
                                HStack(spacing: 2) {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text("\(session.attempts.count)")
                                        .font(.caption)
                                }
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                    Text("\(session.firstTryCorrect)")
                                        .font(.caption)
                                }
                                
                                if session.multipleAttempts > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        Text("\(session.multipleAttempts)")
                                            .font(.caption)
                                    }
                                }
                                
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(session)
                }
                .onDelete(perform: deleteSessions)
            }
            .listStyle(SidebarListStyle())
        }
        .onAppear {
            print("🔍 practiceSessionsList appeared with \(sessions.count) sessions")
            for (index, session) in sessions.enumerated() {
                print("🔍 Session \(index): \(session.startDate) - \(session.attempts.count) attempts")
            }
        }
    }
    
    private func setupDataService() {
        practiceDataService = PracticeDataService(modelContext: modelContext)
    }
    
    private func loadSessions() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else {
                    errorMessage = "Data service not initialized"
                    isLoading = false
                    return
                }
                
                print("📚 Loading practice sessions...")
                let loadedSessions = try dataService.fetchAllSessions()
                print("📚 Found \(loadedSessions.count) practice sessions")
                
                sessions = loadedSessions
                isLoading = false
                
                if loadedSessions.isEmpty {
                    print("⚠️ No practice sessions found in database")
                }
            } catch {
                print("❌ Failed to load sessions: \(error)")
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func deleteSessions(offsets: IndexSet) {
        for index in offsets {
            sessionToDelete = sessions[index]
            showingDeleteAlert = true
            break // Only handle one deletion at a time for confirmation
        }
    }
    
    private func deleteSession() {
        guard let session = sessionToDelete else { return }
        
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                try dataService.deleteSession(session)
                
                // Clear selected session if it's the one being deleted
                if selectedSession?.id == session.id {
                    selectedSession = nil
                }
                
                sessions.removeAll { $0.id == session.id }
                sessionToDelete = nil
                print("🗑️ Deleted session from \(session.startDate)")
            } catch {
                print("❌ Failed to delete session: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PracticeSessionRowView: View {
    let session: PracticeSession
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startDate)
    }
    
    private var durationText: String {
        let minutes = Int(session.duration / 60)
        let seconds = Int(session.duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formattedDate)
                    .font(.headline)
                
                Spacer()
                
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.blue)
                    Text("\(session.totalAttempts)")
                        .font(.subheadline.weight(.medium))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("\(session.firstTryCorrect)")
                        .font(.subheadline.weight(.medium))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.orange)
                    Text("\(session.multipleAttempts)")
                        .font(.subheadline.weight(.medium))
                }
                
                Spacer()
                
                // Accuracy percentage
                let accuracy = session.totalAttempts > 0 ? 
                    (Double(session.firstTryCorrect) / Double(session.firstTryCorrect + session.multipleAttempts)) * 100 : 0
                Text("\(accuracy, specifier: "%.0f")%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accuracy >= 80 ? .green : accuracy >= 60 ? .orange : .red)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct PracticeSessionDetailView: View {
    let session: PracticeSession
    @Environment(\.dismiss) private var dismiss
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: session.startDate)
    }
    
    private var durationText: String {
        let minutes = Int(session.duration / 60)
        let seconds = Int(session.duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes) minutes, \(seconds) seconds"
        } else {
            return "\(seconds) seconds"
        }
    }
    
    // Convert persisted attempts back to PracticeAttempt for reuse
    private var practiceAttempts: [PracticeAttempt] {
        session.attempts.map { persistedAttempt in
            PracticeAttempt(
                targetMidi: persistedAttempt.targetMidi,
                targetClef: persistedAttempt.clefEnum,
                targetAccidental: persistedAttempt.targetAccidental,
                playedMidi: persistedAttempt.playedMidi,
                timestamp: persistedAttempt.timestamp,
                outcome: persistedAttempt.outcomeEnum
            )
        }
    }
    
    var body: some View {
        List {
            Section {
                // Session header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Practice Session Details")
                        .font(.title.bold())
                    
                    Text(formattedDate)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Duration: \(durationText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                
                // Session statistics
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("First Try Correct: \(session.firstTryCorrect)")
                            .foregroundStyle(.green)
                        Text("Multiple Attempts: \(session.multipleAttempts)")
                            .foregroundStyle(.orange)
                    }
                    .font(.headline)
                    
                    Text("Total Attempts: \(session.totalAttempts)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    // Settings used
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Practice Settings:")
                            .font(.subheadline.weight(.semibold))
                        
                        Text("• Note Count: \(session.settings.count)")
                        Text("• Accidentals: \(session.settings.includeAccidentals ? "Included" : "Excluded")")
                        Text("• Clef Mode: \(session.settings.clefModeEnum.rawValue.capitalized)")
                        
                        if let range = session.settings.allowedRange {
                            Text("• MIDI Range: \(range.lowerBound)-\(range.upperBound)")
                        } else {
                            Text("• Range: Full keyboard")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                .listRowBackground(Color.clear)
            }
            
            Section {
                // Header for detailed results
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note-by-Note Results")
                        .font(.title2.bold())
                    
                    Text("Shows each note you practiced with clef information and attempt details:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                
                if groupedResults.isEmpty {
                    Text("No detailed results available for this session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(groupedResults.enumerated()), id: \.offset) { index, result in
                        PracticeNoteResultRow(
                            noteNumber: index + 1,
                            target: result.target,
                            attempts: result.attempts,
                            firstTryCorrect: result.firstTryCorrect
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .onAppear {
            print("🔍 Session detail view appeared for session with \(session.attempts.count) attempts")
            print("🔍 Grouped into \(groupedResults.count) unique notes")
        }
    }
    
    private var groupedResults: [(target: PracticeTarget, attempts: [PracticeAttempt], firstTryCorrect: Bool)] {
        let grouped = Dictionary(grouping: practiceAttempts) { attempt in
            PracticeTarget(midi: attempt.targetMidi, clef: attempt.targetClef, accidental: attempt.targetAccidental)
        }
        
        return grouped.map { key, attempts in
            let sortedAttempts = attempts.sorted { $0.timestamp < $1.timestamp }
            let firstTryCorrect = sortedAttempts.first?.outcome == .correct
            return (
                target: key,
                attempts: sortedAttempts,
                firstTryCorrect: firstTryCorrect
            )
        }.sorted { lhs, rhs in
            // Sort by the timestamp of the first attempt for each note
            lhs.attempts.first?.timestamp ?? Date.distantPast < rhs.attempts.first?.timestamp ?? Date.distantPast
        }
    }
}

#Preview {
    NavigationStack {
        PracticeHistoryView(navigationPath: .constant(NavigationPath()))
            .modelContainer(for: PracticeSession.self, inMemory: true)
    }
}