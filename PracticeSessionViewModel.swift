import Foundation
import SwiftUI
import Combine

enum PracticeOutcome {
    case correct
    case incorrect
}

struct PracticeAttempt: Identifiable {
    let id = UUID()
    let targetMidi: Int
    let targetClef: Clef
    let targetAccidental: String
    let playedMidi: Int
    let timestamp: Date
    let outcome: PracticeOutcome
}

enum ClefMode {
    case treble
    case bass
    case random
}

struct PracticeSettings {
    var count: Int
    var includeAccidentals: Bool
    var allowedRange: ClosedRange<Int>?
    var clefMode: ClefMode
}

final class PracticeSessionViewModel: ObservableObject {
    @Published var settings: PracticeSettings
    @Published var currentIndex: Int = 0
    @Published var isComplete: Bool = false
    @Published var attempts: [PracticeAttempt] = []

    // Current target (for drawing)
    @Published private(set) var currentTargetMidi: Int = 60
    @Published private(set) var currentTargetClef: Clef = .treble
    @Published private(set) var currentTargetAccidental: String = ""

    // Feedback for live session
    @Published var feedbackMessage: String = "Waiting for note…"
    @Published var feedbackColor: Color = .secondary

    private let conductor: MIDIMonitorConductor
    private let appData: AppData
    private var cancellables = Set<AnyCancellable>()

    // Track target notes for the session
    private var targetNotes: [(midi: Int, clef: Clef, accidental: String)] = []
    private var currentNoteIndex: Int = 0

    // Dedicated StaffViewModel for session drawing
    let staffVM = StaffViewModel()

    init(settings: PracticeSettings, appData: AppData, conductor: MIDIMonitorConductor) {
        self.settings = settings
        self.appData = appData
        self.conductor = conductor

        // Configure drawing model
        staffVM.setAllowedMIDIRange(settings.allowedRange)
        staffVM.setIncludeAccidentals(settings.includeAccidentals)

        // Generate all target notes for the session upfront
        generateTargetNotes()
        setCurrentTarget()

        // Subscribe to MIDI note on events
        conductor.noteOnSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (playedMidi, _) in
                self?.handlePlayed(playedMidi)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        print("DEBUG DEINIT: PracticeSessionViewModel deallocated")
    }

    // Convert MIDI note number to a human-readable note name (e.g., C4, F#3)
    private func noteName(from midi: Int) -> String {
        // Clamp to a sane MIDI range
        let m = max(0, min(127, midi))
        let noteNamesSharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = m % 12
        let octave = (m / 12) - 1
        let name = noteNamesSharp[noteIndex]
        return "\(name)\(octave)"
    }

    private func generateTargetNotes() {
        targetNotes.removeAll()
        
        // Configure staffVM for note generation
        staffVM.setAllowedMIDIRange(settings.allowedRange)
        staffVM.setIncludeAccidentals(settings.includeAccidentals)
        
        for _ in 0..<settings.count {
            // Select clef
            let selectedClef: Clef
            switch settings.clefMode {
            case .treble:
                selectedClef = Clef.treble
            case .bass:
                selectedClef = Clef.bass
            case .random:
                selectedClef = (Bool.random() ? Clef.treble : Clef.bass)
            }
            
            // Generate a random note using the staff view model
            staffVM.randomizeNote()
            
            targetNotes.append((
                midi: staffVM.currentNote.midi,
                clef: selectedClef,
                accidental: staffVM.currentNote.accidental
            ))
        }
    }
    
    private func setCurrentTarget() {
        print("DEBUG: setCurrentTarget called - currentNoteIndex: \(currentNoteIndex), total notes: \(targetNotes.count)")
        
        // This should only be called when we know there are more notes
        guard currentNoteIndex < targetNotes.count else {
            print("ERROR: setCurrentTarget called but no more notes! currentNoteIndex: \(currentNoteIndex), total notes: \(targetNotes.count)")
            return
        }
        
        let target = targetNotes[currentNoteIndex]
        currentTargetMidi = target.midi
        currentTargetClef = target.clef
        currentTargetAccidental = target.accidental
        
        print("DEBUG: Set target \(currentNoteIndex + 1) of \(targetNotes.count): MIDI \(target.midi) (\(noteName(from: target.midi))) on \(target.clef) clef")
        print("DEBUG: isComplete is now: \(isComplete)")
        
        // Update staffVM for drawing purposes
        staffVM.currentClef = target.clef
        staffVM.currentNote = StaffNote(name: noteName(from: target.midi), midi: target.midi, accidental: target.accidental)
        
        // Update progress indicator
        currentIndex = currentNoteIndex + 1
        
        feedbackMessage = "Play note \(currentIndex) of \(settings.count)"
        feedbackColor = .secondary
    }

    private func handlePlayed(_ played: Int) {
        guard !isComplete else { return }
        
        let correct = (played == currentTargetMidi)

        // Always record the attempt
        attempts.append(
            PracticeAttempt(
                targetMidi: currentTargetMidi,
                targetClef: currentTargetClef,
                targetAccidental: currentTargetAccidental,
                playedMidi: played,
                timestamp: Date(),
                outcome: correct ? .correct : .incorrect
            )
        )

        if correct {
            feedbackMessage = "Correct! \(noteName(from: played))"
            feedbackColor = .green
            
            // Move to the next target note IMMEDIATELY - but check for completion AFTER incrementing
            currentNoteIndex += 1
            
            // Check if we've completed all notes
            if currentNoteIndex >= targetNotes.count {
                isComplete = true
                feedbackMessage = "🎉 Practice Complete! View your results."
                feedbackColor = .green
                return
            }
            
            // Still have more notes, set the next target
            setCurrentTarget()
            
            // Small delay only for clearing the "Correct!" feedback message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                if let self = self, !self.isComplete {
                    self.feedbackMessage = "Play note \(self.currentIndex) of \(self.settings.count)"
                    self.feedbackColor = .secondary
                }
            }
        } else {
            feedbackMessage = "Try again. You played \(noteName(from: played)), but the target is \(noteName(from: currentTargetMidi))"
            feedbackColor = .red
        }
    }
}
