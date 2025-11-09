# Stuck Note Prevention System

## Problem
When using Bluetooth MIDI, packet loss or interference can cause "Note Off" messages to be lost, resulting in keys appearing stuck in the "pressed" state even after the physical key has been released. This is a common issue with wireless MIDI connections.

## Solution
The app now includes a multi-layered stuck note prevention system:

### 1. Automatic Timeout (Background Protection)
- **How it works**: Every time a MIDI note is received, the system records the timestamp
- **Monitoring**: A background timer checks every 2 seconds for notes that have been "on" too long
- **Auto-release**: Any note held for more than 10 seconds is automatically released
- **User impact**: Completely transparent - users won't even notice stuck notes anymore

### 2. Manual Panic Button (User Control)
- **Location**: MIDI Settings → Actions → "Clear Stuck Notes (Panic)"
- **When to use**: If a note gets stuck (rare, but possible)
- **What it does**: Immediately releases all active notes and clears visual state

### 3. Connection Recovery (Automatic Cleanup)
- **When**: Bluetooth connection drops or reconnects
- **What happens**: All active notes are cleared to prevent orphaned states

## Technical Implementation

### Key Components

#### MIDIMonitorConductor (ContentView.swift)
```swift
// Tracks when each note was turned on
private var noteOnTimestamps: [Int: Date] = [:]

// Maximum note duration before auto-release
private let stuckNoteTimeout: TimeInterval = 10.0

// Background monitoring
private var stuckNoteTimer: Timer?
```

#### Note Tracking Flow
1. **Note On received** → Record timestamp in `noteOnTimestamps[note]`
2. **Note Off received** → Remove from `noteOnTimestamps[note]`
3. **Timer checks** → If note held > 10 seconds → Auto-release
4. **Visual update** → `noteOffSubject.send(note)` → UI updates via Combine

#### Manual Recovery
```swift
func clearAllNotes() {
    // Force-release all active notes
    // User-initiated via Panic button
}

func forceNoteOff(noteNumber: Int) {
    // Release a specific note
    // Used by both auto-timeout and manual panic
}
```

## User Experience

### Before (Problem Scenario)
1. User plays C5 via Bluetooth keyboard
2. Bluetooth interference causes Note Off packet loss
3. Key remains green/highlighted forever
4. User confusion - "Is the app broken?"

### After (With Prevention)
1. User plays C5 via Bluetooth keyboard
2. Bluetooth interference causes Note Off packet loss
3. After 10 seconds, app automatically releases the note
4. If needed, user can tap "Clear Stuck Notes" in settings
5. Seamless, reliable experience

## Configuration

### Adjusting Timeout Duration
In `ContentView.swift`, modify:
```swift
private let stuckNoteTimeout: TimeInterval = 10.0  // Change to desired seconds
```

**Recommendations:**
- **Too short** (< 5s): May cut off legitimate long notes (organ, sustained piano)
- **Too long** (> 15s): User waits too long for auto-recovery
- **Sweet spot**: 8-12 seconds (current: 10s)

### Adjusting Check Frequency
In `startStuckNoteMonitoring()`:
```swift
stuckNoteTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { ... }
```

**Recommendations:**
- **Too frequent** (< 1s): Unnecessary CPU/battery usage
- **Too infrequent** (> 5s): Delayed recovery
- **Sweet spot**: 2-3 seconds (current: 2s)

## Testing

### Simulating Stuck Notes
1. Enable Bluetooth MIDI keyboard
2. Play a note and hold it
3. While holding, quickly disconnect Bluetooth
4. Note should auto-release after 10 seconds
5. Verify console logs: `⚠️ Auto-releasing stuck note: XX`

### Testing Panic Button
1. Simulate multiple stuck notes (or just play several notes)
2. Go to Settings → MIDI Devices → Actions
3. Tap "Clear Stuck Notes (Panic)"
4. All visual highlights should clear immediately
5. Verify console logs: `🧹 Clearing all active notes (panic button)`

## Future Enhancements (Optional)

### Connection Quality Monitoring
- Track Note On/Off pairs to detect packet loss rate
- Display connection quality indicator
- Auto-suggest wired connection if too many dropped packets

### User-Configurable Timeout
- Add setting: "Auto-release stuck notes after: [5s/10s/15s/Never]"
- Allow power users to disable if desired

### Shake-to-Clear Gesture
- On iOS/iPadOS, detect device shake to trigger panic button
- Quick physical gesture for emergency recovery

### Visual Warning
- If auto-timeout triggers, show brief toast: "🔧 Auto-released stuck note"
- Helps users understand what happened

## Related Files
- `ContentView.swift` - MIDIMonitorConductor class (core logic)
- `KeyBoardView.swift` - Visual keyboard state management
- `BluetoothMIDIManager.swift` - Device management & panic button UI

## Logging
Look for these console messages when debugging:
- `🎹 MIDI Note ON received: note=XX` - Normal note on
- `⚠️ Auto-releasing stuck note: XX (held for 10.0s)` - Auto-timeout triggered
- `🧹 Clearing all active notes (panic button)` - Manual panic button used
