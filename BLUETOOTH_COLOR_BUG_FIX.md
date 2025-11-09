# Bluetooth MIDI Color Bug - FIXED ✅

## Problem Summary
When pressing the **correct note** via Bluetooth MIDI keyboard, the key would sometimes display **red** instead of **green**, even though the note was correct. On-screen presses with mouse/touch always worked correctly.

## Root Cause
A **race condition** caused by duplicate evaluation of note correctness:

1. User presses correct note (e.g., E3 = MIDI 40) via Bluetooth
2. `noteOnSubject` fires → KeyBoardView evaluates `isCorrect(40) = true` ✓
3. `conductor.noteOnEventID` changes → triggers `onChange` handler in ContentView
4. ContentView detects correct answer → calls `randomizeNoteRespectingCalibration()`
5. **Target note changes** from E3 to next random note
6. SwiftUI re-renders → `noteOnSubject` fires AGAIN (duplicate)
7. KeyBoardView re-evaluates `isCorrect(40) = false` ✗ (target changed!)
8. Overwrites correctness → Key turns **RED**

### Why It Was Intermittent
The bug depended on timing:
- **Fast render cycle**: Persisted value used before target changed → GREEN ✓
- **Slow Bluetooth/busy UI**: Target changed before second render → RED ✗

### Why Duplicate Events?
Bluetooth MIDI sends every event **twice**:
```
[MIDIMonitor] 🎹 MIDI Note ON received: note=43, velocity=41, channel=0
[MIDIMonitor] 🎹 MIDI Note ON received: note=43, velocity=41, channel=0
```

This happens because:
- Multiple MIDI endpoints ("Bluetooth" + "Session 1")
- AudioKit receiving from both
- Each fires `noteOnSubject`

## The Fix

**Location**: `KeyBoardView.swift`, line ~242-253

**Solution**: Only evaluate correctness **once** when note is first pressed, ignore subsequent evaluations.

### Before (Buggy):
```swift
.onReceive(conductor.noteOnSubject) { (note, velocity) in
    externalVelocities[note] = norm
    pressedCorrectness[note] = isCorrect(note)  // ← Always overwrites!
}
```

### After (Fixed):
```swift
.onReceive(conductor.noteOnSubject) { (note, velocity) in
    externalVelocities[note] = norm
    
    // CRITICAL FIX: Only set correctness if not already set
    if pressedCorrectness[note] == nil {
        let correctness = isCorrect(note)
        pressedCorrectness[note] = correctness  // ← Set once, never overwrite
    }
}
```

## Verification
Console logs confirm the fix:
```
🎹 KeyBoardView: Note 43 pressed, isCorrect=true [FIRST evaluation]
🎹 KeyBoardView: Note 43 pressed AGAIN, keeping previous correctness: true [DUPLICATE ignored]
🎨 WHITE key 43: persisted=Optional(true), effectiveCorrect=true
```

Keys now consistently show:
- 🟢 **Green** for correct notes
- 🔴 **Red** for incorrect notes

## Related Fixes
As part of this investigation, we also implemented:
- **Stuck note prevention** (auto-release after 10s timeout)
- **Panic button** in MIDI Settings to manually clear stuck notes
- **Enhanced logging** for MIDI event debugging

## Files Modified
1. **KeyBoardView.swift** - Fixed duplicate evaluation bug
2. **ContentView.swift** - Added stuck note prevention
3. **BluetoothMIDIManager.swift** - Added panic button UI

## Testing Results
✅ Correct notes via Bluetooth → **Green**  
✅ Incorrect notes via Bluetooth → **Red**  
✅ On-screen presses → **Green** (still works)  
✅ No more stuck notes (auto-release works)  
✅ Panic button clears any stuck notes  

## Additional Observations

### Duplicate MIDI Events
The Bluetooth keyboard sends every event twice. This is visible in logs:
- 2× Note On per physical press
- 2× Note Off per physical release

This is caused by having multiple MIDI endpoints active:
- "Bluetooth" endpoint (iOS system)
- "Session 1" endpoint (your Mac or network MIDI)

**This is harmless** now that we ignore duplicates, but could be optimized by:
- Deduplicating in the conductor
- Only opening one MIDI endpoint
- Filtering by port ID

### Why On-Screen Worked
On-screen keyboard calls `simulateNoteOn()`, which:
- Sends `noteOnSubject` immediately (synchronously)
- No duplicate events
- Target hasn't changed yet when evaluated
- Always showed correct color by luck of timing

Bluetooth events go through CoreMIDI → async dispatch → more chances for race conditions.

## Prevention for Future
This bug pattern can occur anytime:
1. A value is evaluated and persisted
2. The source of truth changes
3. Re-evaluation occurs using new source of truth

**Pattern to use**:
```swift
if myDictionary[key] == nil {
    myDictionary[key] = evaluate()  // Only set once
}
```

**Not**:
```swift
myDictionary[key] = evaluate()  // Always overwrites
```

## Performance Impact
Minimal. The fix adds one dictionary lookup (`pressedCorrectness[note] == nil`) per note event, which is O(1) and negligible.

## Backwards Compatibility
No breaking changes. The fix only affects internal state management and doesn't change any public APIs.

## Date Fixed
November 9, 2025

---

**Status**: ✅ RESOLVED  
**Severity**: Medium (visual bug affecting user experience)  
**Affected Platforms**: iOS/iPadOS with Bluetooth MIDI  
**Workaround**: None needed (fixed in code)
