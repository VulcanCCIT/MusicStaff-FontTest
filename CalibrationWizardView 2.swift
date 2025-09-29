#if false
import SwiftUI

private let kWizardNoteNames: [String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

private func noteName(from midi: Int) -> String {
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
        NavigationStack {
            VStack(spacing: 24) {
                header
                content
                Spacer()
                footer
            }
            .padding()
            .navigationTitle("Keyboard Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .onAppear { conductor.start() }
        .onDisappear { conductor.stop() }
        .onChange(of: conductor.data.noteOn) { newValue in
            guard newValue > 0 else { return }
            handleIncoming(note: newValue)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            switch step {
            case .pressLowest:
                Text("Step 1 of 2").font(.footnote).foregroundStyle(.secondary)
                Text("Press the lowest key on your MIDI keyboard")
                    .font(.headline)
            case .pressHighest:
                Text("Step 2 of 2").font(.footnote).foregroundStyle(.secondary)
                Text("Press the highest key on your MIDI keyboard")
                    .font(.headline)
            case .review:
                Text("Review").font(.footnote).foregroundStyle(.secondary)
                Text("Confirm your keyboard range")
                    .font(.headline)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                VStack {
                    Text("Lowest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.06)))
                        VStack(spacing: 6) {
                            Text(capturedMin.map(noteName(from:)) ?? "—")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .monospaced()
                            Text(capturedMin.map(String.init) ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        .frame(minWidth: 120)
                    }
                }
                VStack {
                    Text("Highest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.green.opacity(0.3), lineWidth: 1)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.06)))
                        VStack(spacing: 6) {
                            Text(capturedMax.map(noteName(from:)) ?? "—")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .monospaced()
                            Text(capturedMax.map(String.init) ?? "—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        .frame(minWidth: 120)
                    }
                }
            }

            if let size = currentSize {
                Text("Detected size: \(size) keys")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch step {
            case .pressLowest:
                Text("Waiting for lowest key…")
                    .foregroundStyle(.secondary)
            case .pressHighest:
                Text("Waiting for highest key…")
                    .foregroundStyle(.secondary)
            case .review:
                Text("If these look correct, tap Save. You can also Start Over to capture again.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
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

    private var currentSize: Int? {
        guard let lo = capturedMin, let hi = capturedMax else { return nil }
        guard lo <= hi else { return (hi...lo).count }
        return (lo...hi).count
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
            capturedMin = note
            step = .pressHighest
        case .pressHighest:
            capturedMax = note
            step = .review
        case .review:
            // ignore further input
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
}

#Preview {
    let data = AppData()
    return CalibrationWizardView(isPresented: .constant(true))
        .environmentObject(data)
}
#endif
