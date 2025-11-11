# Debugging: Bluetooth MIDI Shows Red Instead of Green for Correct Notes

## Problem Description
When pressing the **correct note** on a Bluetooth MIDI keyboard, the key shows **red** instead of **green**.
However, when pressing the same note on-screen (with mouse/touch), it correctly shows **green**.

## Hypothesis
There's a logic inversion or timing issue in how correctness is evaluated for Bluetooth MIDI input vs. simulated (on-screen) input.

## Key Code Locations

### 1. Color Determination Logic (KeyBoardView.swift, lines ~786-800 and ~913-927)

```swift
let persisted: Bool? = pressedCorrectness[midi]
let effectiveCorrect: Bool = {
    if isPressed, let persisted {
        return persisted  // Use saved correctness value
    } else {
        return isCorrect(midi)  // Check if note matches target
    }
}()

if isPressed {
    let pressedColor: Color = effectiveCorrect ? .green : .red
    context.fill(keyTop, with: .color(pressedColor))
}
```

**Logic:**
- If key is pressed AND we saved correctness at note-on → use saved value
- Otherwise → check current target note
- Green if correct (true), Red if incorrect (false)

### 2. Correctness Persistence (KeyBoardView.swift, line ~247)

```swift
.onReceive(conductor.noteOnSubject) { (note, velocity) in
    externalVelocities[note] = norm
    let correctness = isCorrect(note)
    pressedCorrectness[note] = correctness  // Save correctness at note-on time
    print("🎹 KeyBoardView: Note \(note) pressed, isCorrect=\(correctness)")
}
```

This fires for BOTH:
- Bluetooth MIDI → via `receivedMIDINoteOn` → `noteOnSubject.send()`
- On-screen → via `simulateNoteOn` → `noteOnSubject.send()`

### 3. isCorrect Function (ContentView.swift, line ~949)

```swift
KeyBoardView(isCorrect: { midi in
    midi == vm.currentNote.midi  // Returns true if pressed note matches target
}, docked: true)
```

## Debug Logging Added

### A. Note Press Logging (KeyBoardView.swift)
```swift
print("🎹 KeyBoardView: Note \(note) pressed, isCorrect=\(correctness)")
```
**What to check:**
- Does this print the **same value** for on-screen vs. Bluetooth?
- Is the note number correct?

### B. Rendering Logging (KeyBoardView.swift)
```swift
print("🎨 WHITE key \(midi): persisted=\(persisted), effectiveCorrect=\(effectiveCorrect)")
print("🎨 BLACK key \(midi): persisted=\(persisted), effectiveCorrect=\(effectiveCorrect)")
```
**What to check:**
- What is the `persisted` value? Should match the value from 🎹 log above
- What is `effectiveCorrect`? This determines the actual color

## Testing Steps

### Test 1: Bluetooth Correct Note
1. Open Console and filter for "🎹" or "🎨"
2. Note the target (e.g., "C5" = MIDI 72)
3. Press C5 on Bluetooth keyboard
4. Check logs:
   ```
   🎹 KeyBoardView: Note 72 pressed, isCorrect=???
   🎨 WHITE key 72: persisted=Optional(???), effectiveCorrect=???
   ```
5. **Expected**: `isCorrect=true`, `persisted=Optional(true)`, `effectiveCorrect=true` → Green
6. **If bug exists**: `isCorrect=false` or `effectiveCorrect=false` → Red

### Test 2: On-Screen Correct Note
1. Same target (C5 = MIDI 72)
2. Click/touch C5 on screen
3. Check logs (same format as above)
4. **Expected**: All values should be `true` → Green
5. Compare with Test 1 results

### Test 3: Bluetooth Incorrect Note
1. Target is C5 (MIDI 72)
2. Press D5 (MIDI 74) on Bluetooth
3. **Expected**: `isCorrect=false`, Red color → This should work correctly

### Test 4: Timing Check
1. Press and hold a Bluetooth note for 2+ seconds
2. Check if multiple 🎨 logs appear (Canvas redraws)
3. Verify `persisted` value stays consistent
4. Check if `effectiveCorrect` ever changes while held

## Possible Root Causes

### Hypothesis 1: Logic Inversion
**Symptom**: Colors are backwards (red ↔ green swapped)
**Check**: Line with `let pressedColor: Color = effectiveCorrect ? .green : .red`
**Fix**: Swap to `.red : .green` (but this doesn't explain why on-screen works!)

### Hypothesis 2: MIDI Note Number Mismatch
**Symptom**: Bluetooth reports different MIDI number than expected
**Check**: 🎹 log shows note number - does it match what you pressed?
**Example**: You press C5 (60) but Bluetooth sends C4 (48) due to octave transpose
**Fix**: Check keyboard settings, or adjust `isCorrect` logic

### Hypothesis 3: Timing/Race Condition
**Symptom**: `isCorrect(note)` evaluated before target updates
**Check**: Does target note update between on-screen and Bluetooth tests?
**Fix**: Ensure `vm.currentNote` is stable when testing

### Hypothesis 4: State Persistence Issue
**Symptom**: `persisted` value is nil or wrong
**Check**: 🎨 log shows `persisted=nil` even though 🎹 log set it
**Cause**: Dictionary not updating, or MIDI number mismatch
**Fix**: Verify note numbers match exactly

### Hypothesis 5: Multiple Note-On Events
**Symptom**: Bluetooth sends duplicate Note-On with different behavior
**Check**: Count how many 🎹 logs appear for single press
**Fix**: Deduplicate or handle running status properly

## Expected Console Output (Correct Scenario)

### Bluetooth Press (Target = C5/72)
```
🎹 KeyBoardView: Note 72 pressed, isCorrect=true
🎨 WHITE key 72: persisted=Optional(true), effectiveCorrect=true
[Key should be GREEN]
```

### On-Screen Press (Target = C5/72)
```
🎹 KeyBoardView: Note 72 pressed, isCorrect=true
🎨 WHITE key 72: persisted=Optional(true), effectiveCorrect=true
[Key should be GREEN]
```

### Incorrect Note (Target = C5/72, Press D5/74)
```
🎹 KeyBoardView: Note 74 pressed, isCorrect=false
🎨 WHITE key 74: persisted=Optional(false), effectiveCorrect=false
[Key should be RED]
```

## Next Steps After Testing

1. **Run tests above** and capture console output
2. **Share logs** showing:
   - One Bluetooth correct note press
   - One on-screen correct note press
   - The target note at the time
3. **Based on logs**, we can identify:
   - If `isCorrect()` is returning wrong value
   - If `persisted` is not being set/retrieved
   - If note numbers don't match expectations
   - If there's a timing issue

## Temporary Workaround (If Urgent)

If you need to test other functionality while debugging this:

```swift
// In KeyBoardView.swift, line ~247, force all notes to show as correct:
.onReceive(conductor.noteOnSubject) { (note, velocity) in
    externalVelocities[note] = norm
    pressedCorrectness[note] = true  // Force green for testing
    print("🎹 KeyBoardView: Note \(note) pressed, FORCED correct")
}
```

This will make all keys green (but breaks the game logic - only for debugging!).

## Remove Debug Logging Later

Once fixed, remove or comment out:
1. Line ~247: `print("🎹 KeyBoardView: Note ...")` 
2. Line ~796: `print("🎨 WHITE key ...")`
3. Line ~926: `print("🎨 BLACK key ...")`

Or wrap in `#if DEBUG` for conditional compilation.
