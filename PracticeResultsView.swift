import SwiftUI
// Uses StaffThumbnailSizing for consistent thumbnail sizes

// Helper struct to group practice attempts by target
struct PracticeTarget: Hashable {
    let midi: Int
    let clef: Clef
    let accidental: String
}

struct PracticeResultsView: View {
    let attempts: [PracticeAttempt]
    let settings: PracticeSettings
    let sessionStartDate: Date
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var isSaved: Bool = false
    @State private var saveError: Error?
    @State private var showStatistics: Bool = false

    private var groupedResults: [(target: PracticeTarget, attempts: [PracticeAttempt], firstTryCorrect: Bool)] {
        let grouped = Dictionary(grouping: attempts) { attempt in
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

    private var summary: (firstTryCorrect: Int, multipleAttempts: Int, totalAttempts: Int) {
        let firstTryCorrect = groupedResults.filter { $0.firstTryCorrect }.count
        let multipleAttempts = groupedResults.filter { !$0.firstTryCorrect }.count
        let totalAttempts = attempts.count
        return (firstTryCorrect, multipleAttempts, totalAttempts)
    }
    
    private func noteName(from midiNote: Int) -> String {
        guard (0...127).contains(midiNote) else { return "—" }
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let noteIndex = midiNote % 12
        let octave = (midiNote / 12) - 1
        return names[noteIndex] + String(octave)
    }
    
    // MARK: - Session Statistics (Trends)
    private var incorrectPlayedCounts: [(midi: Int, count: Int)] {
        let counts = attempts.filter { $0.outcome == .incorrect }.reduce(into: [Int: Int]()) { dict, attempt in
            dict[attempt.playedMidi, default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }.map { (key: Int, value: Int) in (midi: key, count: value) }
    }

    private var playedToMistakenTargets: [Int: [Int: Int]] {
        var mapping: [Int: [Int: Int]] = [:]
        for a in attempts where a.outcome == .incorrect {
            var inner = mapping[a.playedMidi, default: [:]]
            inner[a.targetMidi, default: 0] += 1
            mapping[a.playedMidi] = inner
        }
        return mapping
    }

    private var alwaysCorrectTargets: [PracticeTarget] {
        groupedResults.filter { group in
            // Always correct in this session means only one attempt and it was correct on first try
            group.firstTryCorrect && group.attempts.count == 1
        }.map { $0.target }
    }

    private var toughTargets: [(target: PracticeTarget, attempts: Int)] {
        groupedResults.filter { !$0.firstTryCorrect }.map { ($0.target, $0.attempts.count) }.sorted { lhs, rhs in
            if lhs.attempts == rhs.attempts { return lhs.target.midi < rhs.target.midi }
            return lhs.attempts > rhs.attempts
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Practice Results")
                    .font(.largeTitle.bold())
                
                Spacer()
                
                Button("Statistics") {
                    showStatistics = true
                }
                .buttonStyle(.bordered)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("First Try Correct: \(summary.firstTryCorrect)")
                        .foregroundStyle(.green)
                    Text("Multiple Attempts: \(summary.multipleAttempts)")
                        .foregroundStyle(.orange)
                }
                .font(.headline)
                
                Text("Total Attempts: \(summary.totalAttempts)")
                .font(.subheadline).bold(true)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(groupedResults.enumerated()), id: \.offset) { index, result in
                        PracticeNoteResultRow(
                            noteNumber: index + 1,
                            target: result.target,
                            attempts: result.attempts,
                            firstTryCorrect: result.firstTryCorrect
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .onAppear {
            savePracticeResults()
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsSheet(
                incorrectPlayedCounts: incorrectPlayedCounts,
                playedToMistakenTargets: playedToMistakenTargets,
                alwaysCorrectTargets: alwaysCorrectTargets,
                toughTargets: toughTargets,
                noteName: noteName
            )
#if os(iOS) || targetEnvironment(macCatalyst)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
#endif
#if os(macOS)
            .frame(minWidth: 820, minHeight: 600)
#endif
        }
    }
    
    // MARK: - Save Practice Results
    
    private func savePracticeResults() {
        guard !isSaved else { return } // Don't save twice
        
        Task {
            do {
                let dataService = PracticeDataService(modelContext: modelContext)
                try dataService.savePracticeSession(
                    startDate: sessionStartDate,
                    endDate: Date(),
                    settings: settings,
                    attempts: attempts
                )
                await MainActor.run {
                    isSaved = true
                }
                print("✅ Practice session saved successfully")
            } catch {
                await MainActor.run {
                    saveError = error
                }
                print("❌ Failed to save practice session: \(error)")
            }
        }
    }
}

struct StatisticsSheet: View {
    let incorrectPlayedCounts: [(midi: Int, count: Int)]
    let playedToMistakenTargets: [Int: [Int: Int]]
    let alwaysCorrectTargets: [PracticeTarget]
    let toughTargets: [(target: PracticeTarget, attempts: Int)]
    let noteName: (Int) -> String

    @AppStorage("statsShowThumbnails") private var showThumbnails: Bool = false
    @AppStorage("statsUserOverrideThumbnails") private var userOverrodeThumbnailPref: Bool = false
    private let thumbnailAutoWidthThreshold: CGFloat = 900

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var scope: Int = 0 // 0 = This Session, 1 = All Time
    @State private var isLoadingLifetime = false
    @State private var lifetimeError: String?
    @State private var lifetimeNotePerformance: [NotePerformance] = []
    @State private var lifetimeIncorrectPlayedCounts: [(midi: Int, count: Int)] = []
    @State private var lifetimePlayedToMistakenTargets: [Int: [Int: Int]] = [:]

    private func suggestedClef(for midi: Int) -> Clef { midi < 60 ? .bass : .treble }
    private func accidentalForMidi(_ midi: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let flats = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
        let pc = midi % 12
        let sharp = names[pc]
        let flat = flats[pc]
        let useSharps = sharp.count <= flat.count
        let raw = useSharps ? sharp : flat
        if raw.contains("#") { return "♯" }
        if raw.contains("b") { return "♭" }
        return ""
    }

    private func loadLifetime() {
        guard !isLoadingLifetime else { return }
        isLoadingLifetime = true
        lifetimeError = nil
        Task { @MainActor in
            do {
                let service = PracticeDataService(modelContext: modelContext)
                let notePerf = try service.analyzeNotePerformance()
                let sessions = try service.fetchAllSessions()
                // Flatten all attempts to transient PracticeAttempt for counting played notes
                var allAttempts: [PracticeAttempt] = []
                for session in sessions {
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
                // Compute incorrect played counts and mapping
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
                lifetimeNotePerformance = notePerf
                isLoadingLifetime = false
            } catch {
                lifetimeError = error.localizedDescription
                isLoadingLifetime = false
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let width = proxy.size.width
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Scope", selection: $scope) {
                            Text("This Session").tag(0)
                            Text("All Time").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: scope) { _, newValue in
                            if newValue == 1 { loadLifetime() }
                        }
                        
                        Toggle("Show Thumbnails", isOn: Binding(get: { showThumbnails }, set: { newValue in
                            showThumbnails = newValue
                            userOverrodeThumbnailPref = true
                        }))
                        .toggleStyle(.switch)
                        .padding(.top, 4)
                        
                        Text("Automatically enabled on wide windows; you can override here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if scope == 0 {
                            // Most common incorrect notes played
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Most Common Incorrect Notes Played")
                                    .font(.headline)
                                if incorrectPlayedCounts.isEmpty {
                                    Text("No incorrect notes in this session.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(incorrectPlayedCounts.prefix(5).enumerated()), id: \.offset) { _, item in
                                        let played = item.midi
                                        let count = item.count
                                        HStack(spacing: 12) {
                                            if showThumbnails {
                                                StaffThumbnailView(midi: played, clef: suggestedClef(for: played), accidental: accidentalForMidi(played))
                                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(noteName(played)) — \(count) time\(count == 1 ? "" : "s")")
                                                    .font(.title3)
                                                    .bold()
                                                if let mistakenTargets = playedToMistakenTargets[played] {
                                                    let sortedTargets = mistakenTargets.sorted { $0.value > $1.value }
                                                    let details = sortedTargets.prefix(3).map { "\(noteName($0.key)) (\($0.value))" }.joined(separator: ", ")
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
                                    }
                                }
                            }

                            // Always correct targets (first try only)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Always Correct (First Try)")
                                    .font(.headline)
                                if alwaysCorrectTargets.isEmpty {
                                    Text("No notes were always correct on first try in this session.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(alwaysCorrectTargets, id: \.self) { target in
                                        HStack(spacing: 12) {
                                            if showThumbnails {
                                                StaffThumbnailView(midi: target.midi, clef: target.clef, accidental: target.accidental)
                                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                            }
                                            Text(noteName(target.midi))
                                                .font(.title3)
                                                .bold()
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }

                            // Tough notes requiring multiple attempts
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tough Notes (Multiple Attempts)")
                                    .font(.headline)
                                if toughTargets.isEmpty {
                                    Text("No notes required multiple attempts in this session.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(toughTargets, id: \.target) { item in
                                        HStack(spacing: 12) {
                                            if showThumbnails {
                                                StaffThumbnailView(midi: item.target.midi, clef: item.target.clef, accidental: item.target.accidental)
                                                    .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                            }
                                            Text("\(noteName(item.target.midi)) — \(item.attempts) attempt\(item.attempts == 1 ? "" : "s")")
                                                .font(.title3)
                                                .bold()
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        } else {
                            if isLoadingLifetime {
                                ProgressView("Loading lifetime stats…")
                                    .frame(maxWidth: .infinity)
                            } else if let lifetimeError = lifetimeError {
                                Text(lifetimeError)
                                    .foregroundStyle(.red)
                            } else {
                                // Lifetime: Most common incorrect notes played
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Most Common Incorrect Notes (All Time)")
                                        .font(.headline)
                                    if lifetimeIncorrectPlayedCounts.isEmpty {
                                        Text("No incorrect notes recorded yet.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(Array(lifetimeIncorrectPlayedCounts.prefix(10).enumerated()), id: \.offset) { _, item in
                                            let played = item.midi
                                            let count = item.count
                                            HStack(spacing: 12) {
                                                if showThumbnails {
                                                    StaffThumbnailView(midi: played, clef: suggestedClef(for: played), accidental: accidentalForMidi(played))
                                                        .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                                }
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(noteName(played)) — \(count) time\(count == 1 ? "" : "s")")
                                                        .font(.title3)
                                                        .bold()
                                                    if let mistakenTargets = lifetimePlayedToMistakenTargets[played] {
                                                        let sortedTargets = mistakenTargets.sorted { $0.value > $1.value }
                                                        let details = sortedTargets.prefix(3).map { "\(noteName($0.key)) (\($0.value))" }.joined(separator: ", ")
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
                                        }
                                    }
                                }

                                // Lifetime: Always correct notes (100% accuracy)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Consistently Correct Notes (All Time)")
                                        .font(.headline)
                                    let alwaysCorrect = lifetimeNotePerformance.filter { $0.accuracy == 1.0 }.sorted { $0.totalAttempts > $1.totalAttempts }
                                    if alwaysCorrect.isEmpty {
                                        Text("No notes at 100% accuracy yet.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(alwaysCorrect.prefix(10)) { perf in
                                            HStack(spacing: 12) {
                                                if showThumbnails {
                                                    StaffThumbnailView(midi: perf.midi, clef: perf.clef, accidental: perf.accidental)
                                                        .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                                }
                                                Text("\(perf.noteName) — \(perf.totalAttempts) attempt\(perf.totalAttempts == 1 ? "" : "s")")
                                                    .font(.title3)
                                                    .bold()
                                                Spacer()
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }

                                // Lifetime: Notes needing practice (lowest accuracy)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes Needing Practice (All Time)")
                                        .font(.headline)
                                    if lifetimeNotePerformance.isEmpty {
                                        Text("No lifetime data available.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(lifetimeNotePerformance.prefix(10)) { perf in
                                            HStack(spacing: 12) {
                                                if showThumbnails {
                                                    StaffThumbnailView(midi: perf.midi, clef: perf.clef, accidental: perf.accidental)
                                                        .frame(width: StaffThumbnailSizing.width, height: StaffThumbnailSizing.height)
                                                }
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
                                            .padding(.vertical, 2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: width) { _, newWidth in
                    if !userOverrodeThumbnailPref {
                        showThumbnails = newWidth >= thumbnailAutoWidthThreshold
                    }
                }
                .onAppear {
                    // Preload if user lands in All Time
                    if scope == 1 { loadLifetime() }
                    
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
            .navigationTitle("Session Statistics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
            .navigationTitle("Session Statistics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
    }
}

struct StaffThumbnailView: View {
    let midi: Int
    let clef: Clef
    let accidental: String

    // Reuse the exact geometry used by PracticeNoteResultRow
    private let noteX: CGFloat = 166
    private let trebleStaffPoint = CGPoint(x: 155, y: 150)
    private let bassStaffPoint   = CGPoint(x: 155, y: 230)
    private let lineWidth: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            // Draw using the same coordinate system as PracticeNoteResultRow (320pt tall)
            // and scale to fit the available size so clefs and note placement match exactly.
            let baseHeight: CGFloat = 320
            let scale = min(size.height / baseHeight, 1.0)

            context.drawLayer { layerContext in
                // Scale first so our centering math uses the virtual (unscaled) coordinate space
                layerContext.scaleBy(x: scale, y: scale)

                // Compute centering in the virtual space
                let virtualWidth = size.width / scale
                let virtualHeight = size.height / scale
                let centerX = virtualWidth / 2
                let centerY = virtualHeight / 2
                let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2
                let offsetX = centerX - noteX
                let offsetY = centerY - originalGroupMidY
                layerContext.translateBy(x: offsetX, y: offsetY)

                let vm = StaffViewModel()
                vm.setIncludeAccidentals(true)
                vm.setAllowedMIDIRange(nil)
                vm.currentClef = clef
                vm.currentNote = StaffNote(name: noteName(from: midi), midi: midi, accidental: accidental)

                // Draw both staffs exactly like PracticeNoteResultRow
                let trebleStaff = MusicSymbol.trebleStaff.text()
                let bassStaff = MusicSymbol.bassStaff.text()

                if clef == .treble {
                    layerContext.draw(trebleStaff, at: trebleStaffPoint)
                    layerContext.drawLayer { sub in
                        sub.opacity = 0.3
                        sub.draw(bassStaff, at: bassStaffPoint)
                    }
                } else {
                    layerContext.drawLayer { sub in
                        sub.opacity = 0.3
                        sub.draw(trebleStaff, at: trebleStaffPoint)
                    }
                    layerContext.draw(bassStaff, at: bassStaffPoint)
                }

                // Ledger lines
                let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
                let strokeWidth: CGFloat = 1.2
                for y in ledgerYs {
                    var p = Path()
                    p.move(to: CGPoint(x: noteX - lineWidth/2, y: y))
                    p.addLine(to: CGPoint(x: noteX + lineWidth/2, y: y))
                    layerContext.stroke(p, with: .color(.primary), lineWidth: strokeWidth)
                }

                // Accidentals
                let acc = vm.currentNote.accidental
                let notePoint = CGPoint(x: noteX, y: vm.currentY)
                if acc == "♯" {
                    let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                    layerContext.draw(MusicSymbol.sharpSymbol.text(), at: accPoint, anchor: .center)
                } else if acc == "♭" {
                    let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                    layerContext.draw(MusicSymbol.flatSymbol.text(), at: accPoint, anchor: .center)
                } else if acc == "♮" {
                    let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                    layerContext.draw(MusicSymbol.naturalSymbol.text(), at: accPoint, anchor: .center)
                }

                // Notehead (match PracticeNoteResultRow default)
                let noteText = MusicSymbol.quarterNoteUP.text()
                layerContext.draw(noteText, at: notePoint, anchor: .center)
            }
        }
    }

    private func noteName(from midi: Int) -> String {
        let k = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        guard (0...127).contains(midi) else { return "—" }
        return k[midi % 12] + String((midi / 12) - 1)
    }
}

struct PracticeNoteResultRow: View {
    let noteNumber: Int
    let target: PracticeTarget
    let attempts: [PracticeAttempt]
    let firstTryCorrect: Bool

    private let noteX: CGFloat = 166
    private let trebleStaffPoint = CGPoint(x: 155, y: 150)
    private let bassStaffPoint   = CGPoint(x: 155, y: 230)
    private let lineWidth: CGFloat = 24
  
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static var debuggedTargets = Set<Int>()

  private func noteName(from midiNote: Int) -> String {
      guard (0...127).contains(midiNote) else {
          return "—"
      }
      
      let noteIndex = midiNote % 12
      let octave = (midiNote / 12) - 1
      
      return Self.noteNames[noteIndex] + String(octave)
  }

    private var statusText: String {
        if firstTryCorrect {
            return "✓ First Try"
        } else {
            return "↻ \(attempts.count) Attempts"
        }
    }
    
    private var statusColor: Color {
        if firstTryCorrect {
            return .green
        } else {
            return .red
        }
    }

    var body: some View {
        let targetNoteName = noteName(from: target.midi)
        let noteNameText = "Note \(noteNumber): \(targetNoteName)"
        
        VStack(alignment: .leading, spacing: 4) {
            headerRow(noteNameText: noteNameText)
            musicStaffCanvas
            if shouldShowIncorrectAttempts {
                incorrectAttemptsText
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(backgroundFill)
        .overlay(borderStroke)
    }
    
    private func headerRow(noteNameText: String) -> some View {
        HStack {
            Text(noteNameText)
                .font(.headline)
            
            Spacer()
            
            Text(statusText)
                .foregroundStyle(statusColor)
                .font(.subheadline.weight(.semibold))
        }
    }
    
    private var musicStaffCanvas: some View {
        Canvas { context, size in
            drawMusicStaff(context: context, size: size)
        }
        .frame(height: 320)
    }
    
    private var shouldShowIncorrectAttempts: Bool {
        !firstTryCorrect && attempts.count > 1
    }
    
    private var incorrectAttemptsText: some View {
        Text("Incorrect attempts: \(attempts.dropLast().map { noteName(from: $0.playedMidi) }.joined(separator: ", "))")
            .font(.callout.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }
    
    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(firstTryCorrect ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
    }
    
    private var borderStroke: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(firstTryCorrect ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
    }
    
    private func drawMusicStaff(context: GraphicsContext, size: CGSize) {
        // Use the same centering approach as ContentView
        let centerX = size.width / 2
        let centerY = size.height / 2
        let originalGroupMidY = (trebleStaffPoint.y + bassStaffPoint.y) / 2
        let offsetX = centerX - noteX
        let offsetY = centerY - originalGroupMidY

        context.drawLayer { layerContext in
            layerContext.translateBy(x: offsetX, y: offsetY)

            let vm = StaffViewModel()
            // Configure VM to the target note - ensure we create the note correctly
            vm.setIncludeAccidentals(true)
            vm.setAllowedMIDIRange(nil)
            // Important: Set clef first, then note
            vm.currentClef = target.clef
            vm.currentNote = StaffNote(name: noteName(from: target.midi), midi: target.midi, accidental: target.accidental)

            // Draw both staffs (same as ContentView), but highlight the active one
            let trebleStaff = MusicSymbol.trebleStaff.text()
            let bassStaff = MusicSymbol.bassStaff.text()
            
            if target.clef == .treble {
                layerContext.draw(trebleStaff, at: trebleStaffPoint)
                layerContext.drawLayer { sublayerContext in
                    sublayerContext.opacity = 0.3
                    sublayerContext.draw(bassStaff, at: bassStaffPoint)
                }
            } else {
                layerContext.drawLayer { sublayerContext in
                    sublayerContext.opacity = 0.3
                    sublayerContext.draw(trebleStaff, at: trebleStaffPoint)
                }
                layerContext.draw(bassStaff, at: bassStaffPoint)
            }

            // Draw ledger lines (same as ContentView)
            let ledgerYs = vm.ledgerLineYs(for: vm.currentNote.midi, clef: vm.currentClef)
            let ledgerLength: CGFloat = lineWidth
            let strokeWidth: CGFloat = 1.2
            for y in ledgerYs {
                var p = Path()
                p.move(to: CGPoint(x: noteX - ledgerLength/2, y: y))
                p.addLine(to: CGPoint(x: noteX + ledgerLength/2, y: y))
                layerContext.stroke(p, with: GraphicsContext.Shading.color(.primary), lineWidth: strokeWidth)
            }

            // Draw accidental and note (same as ContentView)
            let acc = vm.currentNote.accidental
            let notePoint = CGPoint(x: noteX, y: vm.currentY)
            let noteText = MusicSymbol.quarterNoteUP.text()
            
            // Use green color for target note if there were incorrect attempts
            let noteColor: Color = !firstTryCorrect ? .green : .primary
            
            if acc == "♯" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                layerContext.draw(MusicSymbol.sharpSymbol.text(), at: accPoint, anchor: .center)
            } else if acc == "♭" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                layerContext.draw(MusicSymbol.flatSymbol.text(), at: accPoint, anchor: .center)
            } else if acc == "♮" {
                let accPoint = CGPoint(x: noteX - 18, y: vm.currentY)
                layerContext.draw(MusicSymbol.naturalSymbol.text(), at: accPoint, anchor: .center)
            }
            
            // Draw target note with appropriate color
            if noteColor == .green {
                layerContext.drawLayer { sublayerContext in
                    var resolvedNote = sublayerContext.resolve(noteText)
                    resolvedNote.shading = .color(.green)
                    sublayerContext.draw(resolvedNote, at: notePoint, anchor: .center)
                }
            } else {
                layerContext.draw(noteText, at: notePoint, anchor: .center)
            }

            // Show incorrect attempts as smaller, faded red notes to the right
            if !firstTryCorrect {
                drawIncorrectAttempts(context: layerContext, vm: vm)
            }
        }
    }
    
    private func drawIncorrectAttempts(context: GraphicsContext, vm: StaffViewModel) {
        let incorrectAttempts = attempts.filter { $0.outcome == .incorrect }
        var offsetX: CGFloat = 28
        
        // Only print debug info once per target to reduce console noise
        let shouldDebug = !Self.debuggedTargets.contains(target.midi)
        if shouldDebug {
            print("DEBUG: Drawing \(incorrectAttempts.count) incorrect attempts for target \(target.midi) (\(noteName(from: target.midi)))")
            Self.debuggedTargets.insert(target.midi)
        }
        
        for (index, incorrectAttempt) in incorrectAttempts.enumerated() {
            // Show up to 6 incorrect attempts (increased from 3)
            guard index < 6 else { break }
            
            // Determine the appropriate clef for this specific incorrect note
            let incorrectNoteClef: Clef = incorrectAttempt.playedMidi < 60 ? .bass : .treble
            
            if shouldDebug {
                print("DEBUG: Incorrect attempt \(index + 1): MIDI \(incorrectAttempt.playedMidi) (\(noteName(from: incorrectAttempt.playedMidi))) using \(incorrectNoteClef) clef")
            }
            
            // Calculate the Y position using the appropriate clef for this note
            let playedY = vm.noteY(for: incorrectAttempt.playedMidi, clef: incorrectNoteClef)
            let playedPoint = CGPoint(x: noteX + offsetX, y: playedY)
            let playedSymbol = MusicSymbol.quarterNoteUP.text()
            
            // Use the VM to determine the proper accidental
            let (_, accidental) = displayNameAndAccidental(for: incorrectAttempt.playedMidi)
            
            if shouldDebug {
                print("DEBUG: Note \(noteName(from: incorrectAttempt.playedMidi)) has accidental: '\(accidental)'")
            }
            
            // Draw accidental for incorrect note if needed
            if accidental == "♯" {
                let accPoint = CGPoint(x: noteX + offsetX - 18, y: playedY)
                context.drawLayer { layerContext in
                    layerContext.opacity = 0.6
                    var resolvedAcc = layerContext.resolve(MusicSymbol.sharpSymbol.text())
                    resolvedAcc.shading = .color(.red)
                    layerContext.draw(resolvedAcc, at: accPoint, anchor: .center)
                }
            } else if accidental == "♭" {
                let accPoint = CGPoint(x: noteX + offsetX - 18, y: playedY)
                context.drawLayer { layerContext in
                    layerContext.opacity = 0.6
                    var resolvedAcc = layerContext.resolve(MusicSymbol.flatSymbol.text())
                    resolvedAcc.shading = .color(.red)
                    layerContext.draw(resolvedAcc, at: accPoint, anchor: .center)
                }
            } else if accidental == "♮" {
                let accPoint = CGPoint(x: noteX + offsetX - 18, y: playedY)
                context.drawLayer { layerContext in
                    layerContext.opacity = 0.6
                    var resolvedAcc = layerContext.resolve(MusicSymbol.naturalSymbol.text())
                    resolvedAcc.shading = .color(.red)
                    layerContext.draw(resolvedAcc, at: accPoint, anchor: .center)
                }
            }
            
            // Draw incorrect note in red with opacity
            context.drawLayer { layerContext in
                layerContext.opacity = 0.6
                // Draw the note symbol in red using resolve
                var resolvedSymbol = layerContext.resolve(playedSymbol)
                resolvedSymbol.shading = .color(.red)
                layerContext.draw(resolvedSymbol, at: playedPoint, anchor: .center)
            }

            // Ledger lines for played note (using the appropriate clef for this note)
            let ledgerYs = vm.ledgerLineYs(for: incorrectAttempt.playedMidi, clef: incorrectNoteClef)
            let incorrectLedgerLength: CGFloat = 32 // Longer ledger lines for incorrect notes
            for y in ledgerYs {
                var p = Path()
                p.move(to: CGPoint(x: (noteX + offsetX) - incorrectLedgerLength/2, y: y))
                p.addLine(to: CGPoint(x: (noteX + offsetX) + incorrectLedgerLength/2, y: y))
                context.stroke(p, with: GraphicsContext.Shading.color(Color.red.opacity(0.6)), lineWidth: 1.0)
            }
            
            offsetX += 20 // Stack incorrect attempts
        }
    }
    
    // Helper function to determine display name and accidental (copied from StaffViewModel logic)
    private func displayNameAndAccidental(for midi: Int) -> (String, String) {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        let flatNames = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
        let pc = midi % 12
        let octave = midi / 12 - 1
        let blackPCs: Set<Int> = [1, 3, 6, 8, 10]
        let useSharps: Bool
        if blackPCs.contains(pc) {
            // For practice results, let's be consistent and use the name from the note name function
            let noteName = self.noteName(from: midi)
            useSharps = noteName.contains("#")
        } else {
            // Naturals are always their natural spelling
            useSharps = true
        }
        let raw = useSharps ? names[pc] : flatNames[pc]
        let acc: String
        if raw.contains("#") { acc = "♯" }
        else if raw.contains("b") { acc = "♭" }
        else { acc = "" }
        return (raw + String(octave), acc)
    }
}

#Preview {
    let attempts: [PracticeAttempt] = [
        // Note 1: D4 (MIDI 62) on treble clef - should be below staff with ledger lines
        PracticeAttempt(targetMidi: 62, targetClef: .treble, targetAccidental: "", playedMidi: 64, timestamp: Date().addingTimeInterval(-10), outcome: .incorrect),
        PracticeAttempt(targetMidi: 62, targetClef: .treble, targetAccidental: "", playedMidi: 60, timestamp: Date().addingTimeInterval(-8), outcome: .incorrect),
        PracticeAttempt(targetMidi: 62, targetClef: .treble, targetAccidental: "", playedMidi: 62, timestamp: Date().addingTimeInterval(-6), outcome: .correct),
        
        // Note 2: E4 (MIDI 64) on treble clef - should be in first space
        PracticeAttempt(targetMidi: 64, targetClef: .treble, targetAccidental: "", playedMidi: 64, timestamp: Date().addingTimeInterval(-4), outcome: .correct),
        
        // Note 3: A6 (MIDI 93) on treble clef - should be above staff with ledger lines  
        PracticeAttempt(targetMidi: 93, targetClef: .treble, targetAccidental: "", playedMidi: 93, timestamp: Date().addingTimeInterval(-2), outcome: .correct)
    ]
    
    let settings = PracticeSettings(
        count: 3,
        includeAccidentals: false,
        allowedRange: 60...84,
        clefMode: .treble
    )
    
    return PracticeResultsView(
        attempts: attempts,
        settings: settings,
        sessionStartDate: Date().addingTimeInterval(-300) // 5 minutes ago
    )
}

