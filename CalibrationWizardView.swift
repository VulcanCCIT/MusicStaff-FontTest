import SwiftUI

private let kWizardNoteNames: [String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

private func midiNoteName(_ midi: Int) -> String {
    guard (0...127).contains(midi) else { return "—" }
    let name = kWizardNoteNames[midi % 12]
    let octave = (midi / 12) - 1
    return "\(name)\(octave)"
}

struct CalibrationWizardView: View {
    @EnvironmentObject private var appData: AppData
    @Binding var isPresented: Bool

    @StateObject private var conductor = MIDIMonitorConductor()

    private enum Step { case pressLowest, pressHighest, review }
    @State private var step: Step = .pressLowest
    @State private var capturedMin: Int? = nil
    @State private var capturedMax: Int? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Header with Cancel
            HStack {
                Text("Keyboard Calibration")
                    .font(.title2).bold()
                Spacer()
                Button("Cancel") { isPresented = false }
            }

            // Instructions and captured values
            VStack(spacing: 16) {
                switch step {
                case .pressLowest:
                    Text("Press the lowest key on your MIDI keyboard")
                        .font(.headline)
                case .pressHighest:
                    Text("Press the highest key on your MIDI keyboard")
                        .font(.headline)
                case .review:
                    Text("Confirm your keyboard range")
                        .font(.headline)
                }

                HStack(spacing: 24) {
                    capturedBox(title: "Lowest", value: capturedMin, color: .blue)
                    capturedBox(title: "Highest", value: capturedMax, color: .green)
                }

                if let size = currentSize {
                    Text("Detected size: \(size) keys")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                switch step {
                case .pressLowest:
                    Text("Waiting for lowest key…").foregroundStyle(.secondary)
                case .pressHighest:
                    Text("Waiting for highest key…").foregroundStyle(.secondary)
                case .review:
                    Text("If these look correct, tap Save. You can also Start Over to capture again.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Footer actions
            HStack {
                Button("Start Over") { startOver() }
                    .buttonStyle(.bordered)
                Spacer()
                switch step {
                case .pressLowest, .pressHighest:
                    ProgressView().progressViewStyle(.circular)
                case .review:
                    Button("Save") { saveAndDismiss() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
        }
        .padding()
        .onAppear { conductor.start() }
        .onDisappear { conductor.stop() }
        .onChange(of: conductor.data.noteOn) { _, newValue in
            guard newValue > 0 else { return }
            handleIncoming(note: newValue)
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    // MARK: - Helpers
    private var currentSize: Int? {
        guard let lo = capturedMin, let hi = capturedMax else { return nil }
        let lower = min(lo, hi)
        let upper = max(lo, hi)
        return (lower...upper).count
    }

    private var canSave: Bool {
        guard let lo = capturedMin, let hi = capturedMax else { return false }
        return lo != hi
    }

    private func startOver() {
        capturedMin = nil
        capturedMax = nil
        step = .pressLowest
    }

    private func handleIncoming(note: Int) {
        switch step {
        case .pressLowest:
            if capturedMin == nil { capturedMin = note; step = .pressHighest }
        case .pressHighest:
            if capturedMax == nil { capturedMax = note; step = .review }
        case .review:
            break
        }
    }

    private func saveAndDismiss() {
        guard let a = capturedMin, let b = capturedMax else { return }
        let lo = min(a, b)
        let hi = max(a, b)
        appData.minMIDINote = lo
        appData.maxMIDINote = hi
        isPresented = false
    }

    @ViewBuilder
    private func capturedBox(title: String, value: Int?, color: Color) -> some View {
        VStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.06)))
                VStack(spacing: 6) {
                    Text(value.map(midiNoteName) ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospaced()
                    Text(value.map(String.init) ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
                .frame(minWidth: 120)
            }
        }
    }
}

#Preview {
    let data = AppData()
    return CalibrationWizardView(isPresented: .constant(true))
        .environmentObject(data)
}
