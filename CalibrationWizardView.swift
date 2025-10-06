//
//  CalibrationWizardView.swift
//  MusicStaff-FontTest
//
//  Created by Chuck Condron on 9/29/25.
//
import SwiftUI

private let kWizardNoteNames: [String] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

private func midiNoteName(_ midi: Int) -> String {
    guard (0...127).contains(midi) else { return "—" }
    let name = kWizardNoteNames[midi % 12]
    let octave = (midi / 12) - 1
    return "\(name)\(octave)"
}

/// A SwiftUI wizard that guides the user through calibrating the playable MIDI note range of a connected keyboard.
///
/// The wizard walks the user through three steps:
/// 1) Press the lowest key,
/// 2) Press the highest key,
/// 3) Review and confirm the detected range.
///
/// The view listens for incoming MIDI note-on events from a `MIDIMonitorConductor` and captures the first
/// note received in each step. When both endpoints are captured, the user can confirm and persist the range
/// to `AppData`. The UI also shows the detected keyboard size (inclusive key count) and allows restarting
/// the process.
///
/// Usage:
/// ```swift
/// CalibrationWizardView(isPresented: $isCalibrating)
///     .environmentObject(appData)
///     .environmentObject(conductor)
/// ```
///
/// Requirements:
/// - `AppData` must expose writable `minMIDINote` and `maxMIDINote` properties (Int MIDI note numbers).
/// - `MIDIMonitorConductor` must expose a `data.noteOn` integer that updates with the most recent note-on.
/// - The view should be presented modally (sheet, popover, or window) and dismissed by toggling `isPresented`.
///
/// Notes:
/// - Only the first note received in each capture step is recorded; additional presses are ignored until the next step.
/// - The view rejects saving if both captured notes are identical.
/// - MIDI note names are rendered via a helper that formats values in the 0...127 range; out-of-range values display "—".
/// - UI layout targets a compact panel with a header, content area, and footer actions.
///
/// See also: `AppData`, `MIDIMonitorConductor`.
///
/// - Important: This view uses `@EnvironmentObject` dependencies. Ensure both objects are injected in the environment
///   of any parent that presents `CalibrationWizardView`.
///
/// - Warning: If no MIDI input is available or `data.noteOn` never updates, the wizard will remain in a waiting state.

/// Shared application model used to persist the finalized MIDI range.
/// Inject an instance that provides writable `minMIDINote` and `maxMIDINote` properties.
///
/// - SeeAlso: `saveAndDismiss()`

/// MIDI event source that the wizard observes for incoming note-on values.
/// The view subscribes to `conductor.data.noteOn` via `onChange` and reacts when the value is greater than zero.
///
/// - Note: Velocity-zero "note off" events should not advance the wizard because they are filtered out.

/// Binding that controls presentation of the wizard.
/// The view sets this value to `false` when the user cancels or successfully saves.

/// Internal state machine for the wizard flow.
/// - `pressLowest`: Waiting for the lowest key press.
/// - `pressHighest`: Waiting for the highest key press.
/// - `review`: Showing captured values and allowing the user to confirm.

/// The current wizard step. Defaults to `.pressLowest`.

/// The captured lowest MIDI note number (0...127). `nil` until recorded.
///
/// - Note: The value is the raw MIDI note number; its display name is derived separately.

/// The captured highest MIDI note number (0...127). `nil` until recorded.
///
/// - Note: The value is the raw MIDI note number; its display name is derived separately.

/// The primary view hierarchy for the wizard.
///
/// Layout:
/// - Header: Title and a Cancel button.
/// - Content: Step instructions, captured note boxes (lowest/highest), and a detected size label.
/// - Footer: "Start Over" and either a progress indicator (while capturing) or a "Save" button (on review).
///
/// Behavior:
/// - Advances automatically as notes are captured.
/// - Shows a spinner while waiting for input.
/// - Enables "Save" only when both endpoints are captured and not equal.
///
/// - Important: The view registers `onChange` for `conductor.data.noteOn` and calls `handleIncoming(note:)`
///   when a positive value is observed.
///
/// - Accessibility: Uses clear titles, semantic text styles, and sufficient contrast for the info boxes.

/// The inclusive number of keys between the captured endpoints (e.g., C3...C4 yields 13).
///
/// Returns `nil` until both endpoints are captured. Values are normalized so the result is independent
/// of the order in which the user pressed the keys.
///
/// - Returns: An integer count of keys, or `nil` if the range is incomplete.

/// Indicates whether the "Save" action is currently valid.
///
/// Returns `true` only when both endpoints are captured and not equal.
///
/// - Returns: A Boolean that enables the Save button.

/// Resets the wizard to its initial state, clearing any captured values and returning to the first step.
///
/// - Effects: Sets `capturedMin` and `capturedMax` to `nil` and `step` to `.pressLowest`.

/// Handles an incoming MIDI note number for the current step.
///
/// - Parameter note: The raw MIDI note number (typically 0...127).
///
/// Behavior:
/// - In `.pressLowest`, records the first note as `capturedMin` and advances to `.pressHighest`.
/// - In `.pressHighest`, records the first note as `capturedMax` and advances to `.review`.
/// - In `.review`, ignores additional input.
///
/// - Important: Only the first note per step is captured; further presses in the same step are ignored.

/// Persists the captured MIDI range into `AppData` and dismisses the wizard.
///
/// The two captured values are normalized so that `minMIDINote <= maxMIDINote` regardless of press order.
///
/// - Effects:
///   - Updates `appData.minMIDINote` and `appData.maxMIDINote`.
///   - Sets `isPresented` to `false` to dismiss.
///
/// - Precondition: Both `capturedMin` and `capturedMax` must be non-`nil`.

/// Renders a labeled box displaying a captured note in both musical name (e.g., "C4") and raw MIDI number.
///
/// - Parameters:
///   - title: A short label displayed above the box (e.g., "Lowest" or "Highest").
///   - value: The optional MIDI note number to display. If `nil`, a placeholder is shown.
///   - color: A tint used for the box border and background accent.
///
/// - Note: The musical name is derived from the MIDI value using a helper that formats 0...127 into
///   note name plus octave. Values outside that range display "—".
struct CalibrationWizardView: View {
    @EnvironmentObject private var appData: AppData
    @EnvironmentObject private var conductor: MIDIMonitorConductor
    @Binding var isPresented: Bool

    private enum Step { case pressLowest, pressHighest, review }
    @State private var step: Step = .pressLowest
    @State private var capturedMin: Int? = nil
    @State private var capturedMax: Int? = nil

    private enum Mode: String, CaseIterable { case midi = "MIDI", manual = "Manual" }
    @State private var mode: Mode = .midi

    // Manual calibration state
    @State private var selectedSize: Int = 61
    private let manualSizes: [Int] = [37, 49, 61, 76, 88]

    private let sizeToStandardRange: [Int: ClosedRange<Int>] = [
        37: 36...72,   // C2–C5
        49: 36...84,   // C2–C6
        61: 36...96,   // C2–C7
        76: 28...103,  // E1–G7
        88: 21...108   // A0–C8
    ]

    private var manualComputedRange: ClosedRange<Int> {
        sizeToStandardRange[selectedSize] ?? 36...96
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header with Cancel
            HStack {
                Text("Keyboard Calibration")
                    .font(.title2).bold()
                Spacer()
                Button("Cancel") { isPresented = false }
            }

            // Mode picker
            Picker("Calibration Mode", selection: $mode) {
                Text("MIDI Keyboard").tag(Mode.midi)
                Text("Manual").tag(Mode.manual)
            }
            .pickerStyle(.segmented)

            if mode == .midi {
                // Instructions and captured values (existing MIDI wizard)
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

                // Footer actions for MIDI mode
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
            } else {
                // Manual calibration UI (Option 2)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Configure your keyboard without MIDI")
                        .font(.headline)

                    // Size picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard size")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Keyboard size", selection: $selectedSize) {
                            ForEach(manualSizes, id: \.self) { size in
                                Text("\(size) keys").tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Text("Starting and ending notes are fixed to industry‑standard ranges for each size.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    // Preview of the resulting range
                    let lo = manualComputedRange.lowerBound
                    let hi = manualComputedRange.upperBound
                    Text("Result: \(midiNoteName(lo)) – \(midiNoteName(hi)) (\(selectedSize) keys)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Footer actions for Manual mode
                HStack {
                    Spacer()
                    Button("Save") {
                        appData.minMIDINote = manualComputedRange.lowerBound
                        appData.maxMIDINote = manualComputedRange.upperBound
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .onChange(of: conductor.data.noteOn) { _, newValue in
            // Only capture MIDI input when in MIDI mode
            guard mode == .midi else { return }
            guard newValue > 0 else { return }
            handleIncoming(note: newValue)
        }
        .frame(minWidth: 360, minHeight: 380)
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
    let conductor = MIDIMonitorConductor()
    return CalibrationWizardView(isPresented: .constant(true))
        .environmentObject(data)
        .environmentObject(conductor)
}
