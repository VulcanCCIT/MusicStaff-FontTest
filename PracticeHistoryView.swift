import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PracticeHistoryView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appData: AppData
    
    @State private var practiceDataService: PracticeDataService?
    @State private var sessions: [PracticeSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: PracticeSession?
    @State private var showingStatistics = false
    @State private var selectedSession: PracticeSession?
    @State private var showingDataManagement = false
    @State private var showingClearAllAlert = false
    @State private var showingExportSheet = false
    @State private var exportedCSV: String = ""
    @State private var databaseSize: String = "Calculating..."
    
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
                Menu {
                    Button(action: { showingStatistics = true }) {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                    
                    Button(action: { showingDataManagement = true }) {
                        Label("Data Management", systemImage: "gearshape.fill")
                    }
                    
                    Divider()
                    
                    Button(action: { exportData() }) {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: { showingClearAllAlert = true }) {
                        Label("Clear All History", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        .alert("Clear All History", isPresented: $showingClearAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all \(sessions.count) practice sessions. This cannot be undone.")
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [exportedCSV])
        }
        .onAppear {
            setupDataService()
            loadSessions()
            updateDatabaseSize()
            performAutoCleanupIfNeeded()
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
        .sheet(isPresented: $showingDataManagement) {
            NavigationView {
                DataManagementView(
                    databaseSize: databaseSize,
                    sessionCount: sessions.count,
                    onClearAll: {
                        showingDataManagement = false
                        showingClearAllAlert = true
                    },
                    onExport: {
                        showingDataManagement = false
                        exportData()
                    },
                    onCleanupOld: { days in
                        showingDataManagement = false
                        cleanupOldSessions(days: days)
                    }
                )
                .environmentObject(appData)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showingDataManagement = false
                        }
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 500)
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
                updateDatabaseSize()
                print("🗑️ Deleted session from \(session.startDate)")
            } catch {
                print("❌ Failed to delete session: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func clearAllHistory() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                try dataService.deleteAllSessions()
                sessions.removeAll()
                selectedSession = nil
                updateDatabaseSize()
                print("🗑️ Cleared all practice history")
            } catch {
                print("❌ Failed to clear history: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func cleanupOldSessions(days: Int) {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                let deletedCount = try dataService.deleteSessionsOlderThan(days: days)
                
                if deletedCount > 0 {
                    loadSessions() // Reload to reflect changes
                    updateDatabaseSize()
                    print("🗑️ Cleaned up \(deletedCount) old sessions")
                }
            } catch {
                print("❌ Failed to cleanup old sessions: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func exportData() {
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                exportedCSV = try dataService.exportToCSV()
                showingExportSheet = true
            } catch {
                print("❌ Failed to export data: \(error)")
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func updateDatabaseSize() {
        Task { @MainActor in
            guard let dataService = practiceDataService else { return }
            databaseSize = dataService.getDatabaseSize()
        }
    }
    
    private func performAutoCleanupIfNeeded() {
        guard appData.shouldPerformAutoCleanup() else { return }
        guard let days = appData.historyRetentionPeriod.days else { return }
        
        Task { @MainActor in
            do {
                guard let dataService = practiceDataService else { return }
                let deletedCount = try dataService.deleteSessionsOlderThan(days: days)
                
                if deletedCount > 0 {
                    print("🧹 Auto-cleanup: Deleted \(deletedCount) sessions older than \(days) days")
                    loadSessions() // Reload to reflect changes
                }
                
                appData.lastCleanupDate = Date()
            } catch {
                print("❌ Auto-cleanup failed: \(error)")
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
            .environmentObject(AppData())
    }
}

// MARK: - Data Management View

/// A view that provides data management options for practice history
///
/// This view allows users to:
/// - View storage information (session count and database size)
/// - Configure automatic cleanup retention periods
/// - Export practice data to CSV
/// - Manually delete old sessions
/// - Clear all practice history
///
/// Layout improvements:
/// - Uses `.fixedSize(horizontal: false, vertical: true)` to prevent text truncation
/// - Applies `.formStyle(.grouped)` on macOS for better visual hierarchy
/// - Uses VStack layout for retention period picker to avoid label cutoff
struct DataManagementView: View {
    @EnvironmentObject private var appData: AppData
    let databaseSize: String
    let sessionCount: Int
    let onClearAll: () -> Void
    let onExport: () -> Void
    let onCleanupOld: (Int) -> Void
    
    @State private var showingCleanupConfirmation = false
    @State private var cleanupDays: Int = 30
    
    var body: some View {
        Form {
            // Storage Information Section
            Section {
                HStack {
                    Text("Practice Sessions")
                        .fixedSize(horizontal: false, vertical: true) // Prevents text truncation
                    Spacer()
                    Text("\(sessionCount)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Storage Used")
                        .fixedSize(horizontal: false, vertical: true) // Prevents text truncation
                    Spacer()
                    Text(databaseSize)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Storage Information")
            }
            
            // Automatic Cleanup Section
            Section {
                // Use VStack to prevent picker label from being cut off
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retention Period")
                        .font(.subheadline)
                    
                    Picker("", selection: $appData.historyRetentionPeriod) {
                        ForEach(HistoryRetentionPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                
                if appData.historyRetentionPeriod != .forever {
                    Text("Older sessions will be automatically deleted daily.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true) // Allows text to wrap properly
                }
            } header: {
                Text("Automatic Cleanup")
            } footer: {
                Text("Select how long to keep your practice history. Older sessions will be automatically removed.")
                    .fixedSize(horizontal: false, vertical: true) // Ensures footer text wraps instead of truncating
            }
            
            // Data Management Actions Section
            Section {
                Button(action: onExport) {
                    Label("Export to CSV", systemImage: "square.and.arrow.up")
                }
                
                Button(action: {
                    cleanupDays = 30
                    showingCleanupConfirmation = true
                }) {
                    Label("Delete Sessions Older Than...", systemImage: "calendar.badge.minus")
                        .fixedSize(horizontal: false, vertical: true) // Prevents label truncation
                }
            } header: {
                Text("Data Management")
            }
            
            // Danger Zone Section
            Section {
                Button(role: .destructive, action: onClearAll) {
                    Label("Clear All Practice History", systemImage: "trash.fill")
                        .fixedSize(horizontal: false, vertical: true) // Prevents label truncation
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Clearing all history will permanently delete all \(sessionCount) practice sessions. This cannot be undone.")
                    .fixedSize(horizontal: false, vertical: true) // Ensures footer text wraps properly
            }
        }
        #if os(macOS)
        .formStyle(.grouped) // Provides better spacing and visual hierarchy on macOS
        #endif
        .navigationTitle("Data Management")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Delete Old Sessions", isPresented: $showingCleanupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onCleanupOld(cleanupDays)
            }
            
            // Picker for days
            Picker("Older than", selection: $cleanupDays) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }
        } message: {
            Text("Delete practice sessions older than \(cleanupDays) days?")
        }
    }
}

// MARK: - Share Sheet Helper

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Create a temporary file for the CSV
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PracticeHistory.csv")
        
        if let csvString = items.first as? String {
            try? csvString.write(to: tempURL, atomically: true, encoding: .utf8)
            return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        }
        
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet: NSViewRepresentable {
    let items: [Any]
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            // Create a temporary file for the CSV
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PracticeHistory.csv")
            
            if let csvString = items.first as? String {
                try? csvString.write(to: tempURL, atomically: true, encoding: .utf8)
                
                let picker = NSSavePanel()
                picker.allowedContentTypes = [.commaSeparatedText]
                picker.nameFieldStringValue = "PracticeHistory.csv"
                
                picker.begin { response in
                    if response == .OK, let url = picker.url {
                        try? FileManager.default.copyItem(at: tempURL, to: url)
                    }
                }
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif