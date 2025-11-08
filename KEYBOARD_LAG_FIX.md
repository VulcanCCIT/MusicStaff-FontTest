# 2D Keyboard Lag Fix

## Problem
The 2D keyboard had noticeable lag when dragging the mouse/finger across keys, while the 3D keyboard was responsive. This occurred even though a bare AudioKit keyboard in a test project worked fine.

## Root Cause
The lag was caused by **excessive view re-rendering** in the 2D keyboard implementation:

1. **Closure-based rendering**: The AudioKit `Keyboard` view uses a closure for each key that gets called whenever *any* state changes
2. **Over-publishing**: The `MIDIMonitorConductor` was updating too many `@Published` properties on every note event
3. **No view diffing**: Each key was re-computing its state (correctness, colors, labels) on every update, even if nothing changed for that specific key

### Why 3D Keyboard Didn't Have This Issue
The 3D keyboard uses:
- A single `DragGesture` handler instead of per-key closures
- `Canvas` rendering (more efficient than individual SwiftUI views)
- Minimal state updates (only `activeNotes` changes)

## Solutions Implemented

### 1. Optimized Key Rendering (Primary Fix)
Created `OptimizedKeyView` with `Equatable` conformance:

```swift
struct OptimizedKeyView: View, Equatable {
  // Pre-computed properties
  let pitch: Pitch
  let isActivated: Bool
  let midi: Int
  let externallyOn: Bool
  let persisted: Bool?
  let isCorrectValue: Bool
  let label: String
  
  static func == (lhs: OptimizedKeyView, rhs: OptimizedKeyView) -> Bool {
    // Only re-render if these specific properties change
    lhs.midi == rhs.midi &&
    lhs.isActivated == rhs.isActivated &&
    lhs.externallyOn == rhs.externallyOn &&
    lhs.persisted == rhs.persisted &&
    lhs.isCorrectValue == rhs.isCorrectValue
  }
  
  // ... rest of implementation
}
```

**Benefits:**
- SwiftUI only re-renders keys whose properties actually changed
- State calculations are done once per update, not on every render pass
- Significant reduction in CPU usage during key dragging

### 2. Reduced State Updates in Conductor
Optimized `simulateNoteOn` and `simulateNoteOff` to:
- Send subject notifications *immediately* (doesn't trigger @Published)
- Batch UI state updates in a single `DispatchQueue.main.async` block
- Prioritize the critical `activeNotes` update

**Before:**
```swift
func simulateNoteOn(noteNumber: Int, velocity: Int, channel: Int = 0) {
    instrument.play(...)
    DispatchQueue.main.async {
        self.noteOnSubject.send((noteNumber, velocity))
    }
    DispatchQueue.main.async {
        self.lastEventWasSimulated = true
        self.noteOnEventID = UUID()
        // ... many more @Published updates
    }
}
```

**After:**
```swift
func simulateNoteOn(noteNumber: Int, velocity: Int, channel: Int = 0) {
    instrument.play(...)
    noteOnSubject.send((noteNumber, velocity)) // No dispatch - immediate
    
    DispatchQueue.main.async {
        // Only update active notes first (critical for keyboard rendering)
        self.activeNotes.insert(noteNumber)
        // Then batch other updates
        self.lastEventWasSimulated = true
        // ...
    }
}
```

**Benefits:**
- Fewer dispatch queue hops
- Audio feedback remains immediate
- UI state updates are batched together

## Testing
After implementing these fixes:
- ✅ Dragging across keys should feel as responsive as the 3D keyboard
- ✅ Audio playback remains immediate with no latency
- ✅ Visual feedback (key colors, pressed states) updates correctly
- ✅ External MIDI input continues to work properly

## Performance Notes
The original implementation was re-rendering **all keys** (potentially 88 keys on a full keyboard) on every note event. With these optimizations:
- Only the **specific keys** that changed state are re-rendered
- State calculations are done once and cached in the view's properties
- The number of @Published updates per note event is minimized

This brings the 2D keyboard's performance in line with the more efficient 3D implementation.
