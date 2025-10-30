import SwiftUI

// Helper struct to group practice attempts by target
struct PracticeTarget: Hashable {
    let midi: Int
    let clef: Clef
    let accidental: String
}

struct PracticeResultsView: View {
    let attempts: [PracticeAttempt]
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Practice Results")
                    .font(.largeTitle.bold())
                
                Spacer()
                
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
            let (displayName, accidental) = displayNameAndAccidental(for: incorrectAttempt.playedMidi)
            
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
    return PracticeResultsView(attempts: attempts)
}
