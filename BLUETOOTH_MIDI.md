# Bluetooth MIDI Integration

## Overview

The app now includes comprehensive Bluetooth MIDI support through AudioKit, allowing users to connect wireless MIDI keyboards and devices seamlessly.

## Features

### 1. **Automatic Device Discovery**
- The app automatically detects all connected MIDI devices (Bluetooth and USB)
- Bluetooth devices are identified with a 🔵 indicator
- Real-time monitoring of device connection status

### 2. **MIDI Device Settings View**
- Access via the "MIDI" button in the main interface
- Shows all available MIDI input devices
- Displays connection status for each device
- Distinguishes between Bluetooth and USB devices

### 3. **Visual Indicators**
- Blue antenna icon (📡) appears when a Bluetooth device is connected
- Device list shows connection status with colored indicators:
  - 🟢 Green = Connected
  - 🔴 Red = Offline

### 4. **Device Management**
- **Refresh Devices**: Manually scan for new devices
- **Reconnect All**: Re-establish connections to all available devices
- Automatic reconnection on app launch

## How to Use

### Connecting a Bluetooth MIDI Keyboard

1. **Enable Bluetooth MIDI on your keyboard**
   - Consult your keyboard's manual for Bluetooth pairing instructions
   - Most keyboards have a Bluetooth button or menu option

2. **Pair with your device**
   - On iOS/iPadOS: Go to Settings → Bluetooth → Connect to your keyboard
   - On macOS: Open Audio MIDI Setup → MIDI Studio → Bluetooth Configuration → Connect

3. **Launch the app**
   - The keyboard should be automatically detected
   - You'll see a blue antenna icon 📡 if connected
   - Click "MIDI" to see detailed device information

4. **Start playing**
   - Notes played on your Bluetooth keyboard will appear on the staff
   - Audio feedback is provided through the built-in piano sound
   - Works in both practice mode and free play

## Supported Devices

The app supports:
- **Bluetooth MIDI keyboards** (using Apple's Bluetooth MIDI protocol)
- **USB MIDI keyboards** (connected directly or via adapter)
- **Multiple simultaneous devices** (all connected devices work together)

## Common Bluetooth MIDI Keyboards

These popular keyboards are known to work well:
- Yamaha P-125, P-45, P-515 (with Bluetooth adapter)
- Roland FP-10, FP-30, FP-90
- Casio Privia PX-S1000, PX-S3000
- Korg B2SP, D1
- CME Xkey Air, Xkey 37
- ROLI Seaboard
- Arturia KeyLab Essential
- Any keyboard with Apple Bluetooth MIDI support

## Technical Details

### Implementation
- Uses AudioKit's `MIDI()` class for device management
- CoreMIDI integration for low-level device access
- Automatic polling every 2 seconds for device changes
- `BluetoothMIDIManager` handles device discovery and status monitoring

### Audio Pipeline
- MIDI input → AudioKit MIDI Manager → Apple Sampler → Audio Engine
- Velocity scaling for external keyboards (adjustable via `externalVelocityBoost`)
- Low-latency audio playback with Grand Piano SoundFont

### Files
- **BluetoothMIDIManager.swift**: Device discovery and management
- **ContentView.swift**: MIDI setup and integration
- **MIDIMonitorConductor**: MIDI event handling

## Troubleshooting

### Device Not Detected
1. Ensure Bluetooth is enabled on your device
2. Check that the keyboard is in pairing mode
3. Restart the app
4. Click "Refresh Devices" in the MIDI settings

### Connection Drops
1. Check battery level on wireless keyboards
2. Reduce distance between device and keyboard
3. Close other apps using Bluetooth
4. Use "Reconnect All Devices" button

### No Sound from Keyboard
1. Verify device appears in MIDI settings as "Connected"
2. Check device volume/mute settings
3. Try playing the on-screen keyboard to verify audio works
4. Restart the app

### Latency Issues
- USB connections generally have lower latency than Bluetooth
- Adjust your device's Bluetooth settings if available
- Consider using a USB MIDI adapter for performance-critical scenarios

## Privacy & Permissions

- **No special permissions required**: Uses standard CoreMIDI APIs
- **No data collection**: All MIDI processing happens locally
- **Bluetooth pairing**: Handled by the operating system

## Future Enhancements

Potential improvements for future versions:
- MIDI device preferences (filter specific devices)
- Custom velocity curves
- MIDI channel filtering
- Sustain pedal support
- MIDI recording and playback
- Network MIDI support

## Support

For issues or questions about Bluetooth MIDI:
1. Check device compatibility with Apple's Bluetooth MIDI
2. Consult your keyboard's documentation
3. Test with Apple's "Audio MIDI Setup" app (macOS) to verify system-level connectivity
