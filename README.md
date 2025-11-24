# Sound Pro

A macOS menu bar application that enables simultaneous audio output to multiple devices. Share your audio to multiple AirPods, headphones, or speakers at the same time with independent volume control for each device.

## Features

- 🎧 **Multi-Device Audio Sharing**: Route audio to multiple output devices simultaneously
- 🔊 **Independent Volume Control**: Adjust volume for each device individually
- 🔄 **Automatic Device Discovery**: Automatically detects and lists available audio output devices
- 🎯 **Real-Time Updates**: Device list refreshes automatically as devices connect/disconnect
- 🖥️ **Menu Bar Integration**: Clean, accessible interface from your macOS menu bar
- ⚡ **Low Latency**: Built on CoreAudio HAL for optimal performance

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building from source)
- Swift 5.9+

## Installation

### Building from Source

1. Clone this repository:
```bash
git clone https://github.com/yourusername/sound-pro.git
cd sound-pro
```

2. Open the project in Xcode:
```bash
open "Sound Pro.xcodeproj"
```

3. Build and run the project (⌘R) or create an archive for distribution.

### Permissions

Sound Pro requires access to modify system audio settings. The app is configured with the necessary entitlements (App Sandbox disabled) to allow:
- Creating aggregate audio devices
- Setting the default output device
- Controlling individual device volumes

## Usage

1. Launch Sound Pro from your Applications folder or build and run from Xcode
2. Click the headphones icon in your menu bar
3. Select one or more audio output devices from the list
4. Adjust individual volume sliders for each selected device
5. Audio will automatically route to all selected devices

### Tips

- The app automatically restores your previous default output device when you stop sharing
- Selected devices are remembered by their unique identifier (UID), so they'll remain selected even if they disconnect and reconnect
- For best results with Bluetooth devices, ensure drift compensation is enabled (handled automatically)

## How It Works

Sound Pro uses macOS CoreAudio's Hardware Abstraction Layer (HAL) to:

1. **Discover Devices**: Scans for all available audio output devices using `AudioObjectGetPropertyData`
2. **Create Aggregate Device**: Uses `AudioHardwareCreateAggregateDevice` to create a multi-output aggregate device
3. **Route Audio**: Sets the aggregate device as the system's default output device
4. **Control Volumes**: Independently adjusts volume on each constituent device using `kAudioDevicePropertyVolumeScalar`

The aggregate device is configured as a "stacked" device (`kAudioAggregateDeviceIsStackedKey = 1`), which means the same audio signal is sent to all outputs simultaneously, rather than combining channels.

## Architecture

- **ContentView.swift**: Main SwiftUI interface and device list
- **AudioManager**: Manages device discovery, selection, and aggregate device lifecycle
- **AggregateBuilder**: Handles creation and destruction of CoreAudio aggregate devices
- **DeviceDiscovery**: Scans and filters available audio output devices
- **CoreAudioUtils**: Low-level CoreAudio property access utilities

## Troubleshooting

### Devices Not Appearing
- Ensure devices are connected and powered on
- Check System Settings > Sound to verify devices are recognized by macOS
- Try disconnecting and reconnecting Bluetooth devices

### Audio Sync Issues
- The app automatically enables drift compensation for non-master devices
- If you experience echo or sync issues, try selecting a different device as the master (first selected device)

### Volume Control Not Working
- Some devices may not support software volume control
- Check Audio MIDI Setup to verify device capabilities
- Volume changes are applied directly to the device, not the aggregate

## Development

### Project Structure

```
Sound Pro/
├── Sound_ProApp.swift      # App entry point and menu bar setup
├── ContentView.swift       # Main UI and audio management logic
└── Sound_Pro.entitlements  # App entitlements (sandbox disabled)
```

### Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **CoreAudio**: Low-level audio system access
- **Combine**: Reactive state management

## License

[Add your license here]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

Built using macOS CoreAudio HAL APIs. Inspired by the need for flexible multi-device audio routing on macOS.

