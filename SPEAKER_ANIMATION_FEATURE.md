# Studio Monitor Speaker Animation Feature

## Overview
Added realistic studio monitor speakers on either side of the music staff that animate when notes are played, creating a more immersive practice experience.

## Files Created
- **SpeakerView.swift**: Custom SwiftUI view that renders a detailed studio monitor speaker with animation capabilities

## Recent Updates (v5)
- **Optimized speaker size**: Reduced from 147×240pt to **95×155pt** for better proportions relative to staff
- **Balanced woofer diameter**: Adjusted to **49%** of cabinet width (middle ground between 46% and 52%)
- **Maintained animation scale**: Kept at 5% expansion with smaller overall size for perfect containment

## Earlier Updates (v4)
- **Reduced woofer diameter**: Scaled down all woofer components by ~20% for better proportions
  - Rim lighting: 92px → 75px
  - Surround: 90px → 74px  
  - Cone: 70px → 56px
  - Dust cap: 24px → 19px
  - Mounting screws repositioned closer
- **Restored animation scale**: Back to 8% maximum expansion (proper size now prevents overflow)
- **Increased speaker size**: Cabinet enlarged by 1/3 (110×180pt → 147×240pt) for more presence

## Earlier Updates (v3)
- **Lightened front baffle**: Dark background around speakers brightened by ~20% for better visibility
- **Added baffle edge highlight**: Subtle white gradient stroke on inner edge for depth
- **Enhanced bass ports**: Lightened colors and added top-edge highlights for studio lighting effect
- **Overall lighting coherence**: All components now have consistent top-left light source

## Earlier Updates (v2)
- **Enhanced drop shadow**: Cabinet now has `.shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)` for prominent depth
- **Repositioned speakers**: Using `Spacer()` views with max 120pt to position speakers closer to staff
- **Lightened wood tone**: Cabinet colors brightened by ~30% for warmer, more visible appearance
- **Added rim lighting**: White gradient stroke around woofer edge for contrast against dark baffle
- **Specular highlights**: Added light reflections on cone and dust cap for realistic 3D appearance
- **Surround highlight**: Subtle arc highlight on rubber surround suggests studio lighting
- **Enhanced contrast**: Woofer components now pop against the black background with realistic lighting

## Features

### Visual Design
The `SpeakerView` recreates the look of a professional studio monitor with:
- **Wooden side panels** with realistic gradient textures and drop shadow
- **Horn tweeter** at the top (the distinctive X-shaped compression driver)
- **Main woofer cone** with:
  - Realistic depth and radial gradient shading
  - Rubber surround (suspension ring)
  - Dust cap (center dome)
  - Mounting screws at cardinal points
  - Textured concentric rings
- **Dual bass reflex ports** at the bottom (tuned ports for low frequencies)
- **Dark front baffle** for the mounting surface

### Animation System
The speakers respond to MIDI input with two synchronized animations:

1. **Woofer Pumping** (`.wooferScale`)
   - The woofer cone scales outward when a note is played
   - Animation intensity scales with MIDI velocity (0-127)
   - Uses `repeatCount(3, autoreverses: true)` for realistic cone movement
   - Duration: 0.15s × animation intensity

2. **Cabinet Vibration** (`.vibrationOffset`)
   - Subtle horizontal offset simulates speaker cabinet vibration
   - Offset scales with velocity: `0.5 * animationIntensity`
   - Uses `repeatCount(4, autoreverses: true)` for natural oscillation
   - Duration: 0.08s per cycle

### Integration Points
The speakers are integrated into `ContentView.swift` with:

```swift
// Staff and note drawing with speakers
HStack(alignment: .center, spacing: 0) {
  // Left speaker with spacer positioning
  Spacer()
  
  SpeakerView(
    isPlaying: conductor.isShowingMIDIReceived && conductor.data.velocity > 0,
    velocity: conductor.data.velocity
  )
  .frame(width: 110, height: 180)
  
  Spacer()
  
  // Staff in the middle
  VStack(spacing: 16) {
    // ... existing staff drawing code ...
  }
  
  Spacer()
  
  // Right speaker with spacer positioning
  SpeakerView(
    isPlaying: conductor.isShowingMIDIReceived && conductor.data.velocity > 0,
    velocity: conductor.data.velocity
  )
  .frame(width: 110, height: 180)
  
  Spacer()
}
```

### Animation Triggers
Speakers animate when:
- `conductor.isShowingMIDIReceived` is `true` (MIDI event received)
- `conductor.data.velocity > 0` (not a note-off event)
- Animation intensity scales with `conductor.data.velocity` (0-127)

### Velocity Mapping
MIDI velocity is mapped to animation intensity:
```swift
private var animationIntensity: Double {
    // Map MIDI velocity (0-127) to animation scale (0.5 - 1.0)
    Double(velocity) / 127.0 * 0.5 + 0.5
}
```

- Soft notes (velocity ~40): Subtle animation
- Medium notes (velocity ~80): Moderate movement  
- Loud notes (velocity 127): Maximum animation intensity

## Technical Details

### Component Sizing (Relative to Cabinet)
- **Front baffle padding**: 8% of width
- **Horn tweeter**: 45% width × 20% height
- **Woofer**: 49% of cabinet width (circular) - balanced for visibility and containment
- **Bass ports**: 16% of cabinet width (circular)
- **Animation scale**: Maximum 5% expansion (at velocity 127) to stay within bounds
- **Overall cabinet**: 95pt wide × 155pt tall

### Custom Shapes
- **Diamond**: Custom `Shape` for the horn tweeter's X-pattern waveguide

### Gradients Used
- **LinearGradient**: Wooden enclosure sides, front baffle, horn tweeter
- **RadialGradient**: Woofer cone, surround, dust cap, bass ports, mounting screws

### Shadow Effects
- **Cabinet shadow**: `radius: 12, x: 0, y: 6, opacity: 0.6` for prominent, realistic depth against background

### Performance Optimizations
- Uses `@State` for animation properties to minimize view updates
- Animations use `.onChange(of: isPlaying)` to trigger only on state changes
- Stops animations gracefully with `.easeOut(duration: 0.2)` transition

## Preview Options
Three preview configurations are provided:
1. **Idle Speaker**: No animation, resting state
2. **Playing Speaker (Soft)**: velocity = 40, subtle movement
3. **Playing Speaker (Loud)**: velocity = 127, maximum intensity
4. **Both Speakers**: Shows stereo pair on background matching the app theme

## Customization Ideas
Future enhancements could include:
- Different speaker models (bookshelf, tower, nearfield)
- LED status indicators
- Volume meter displays
- Frequency-based animations (different movement for bass vs treble notes)
- Color-coded woofer glow based on note correctness (green/red)
- Separate left/right channel animations for stereo MIDI
