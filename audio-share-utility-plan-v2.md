# Audio Share Utility Plan v2

## 1. Project Setup
- **Frameworks:** SwiftUI (UI), CoreAudio (Logic).
- **Target:** macOS 14.0+ (Modern Swift).
- **Entitlements:** Disable "App Sandbox" (Required for `AudioHardwareCreateAggregateDevice` and modifying system audio settings).
- **Permissions:** Microphone/Audio usage description (though strictly output, some audio APIs trigger this).

## 2. Core Logic: CoreAudioManager (Swift + C Interop)

We will use the **Core Audio HAL (Hardware Abstraction Layer)** directly. There is no high-level Swift "replacement" for creating system-wide aggregate devices.

### API Requirements & Strategy

1.  **Device Discovery**
    -   **API:** `AudioObjectGetPropertyData`
    -   **Target:** `kAudioObjectSystemObject`
    -   **Property:** `kAudioHardwarePropertyDevices`
    -   **Logic:** Iterate through all `AudioDeviceID`s. Get `kAudioDevicePropertyDeviceName` and `kAudioDevicePropertyDeviceUID`. Filter for output devices (`kAudioDevicePropertyStreamConfiguration` > 0 output channels).

2.  **Aggregate Device Creation**
    -   **API:** `AudioHardwareCreateAggregateDevice(CFDictionaryRef, AudioObjectID*)`
    -   **Details:** This C-API is the standard method. We must construct a `CFDictionary` describing the device.
    -   **Configuration Dictionary Keys:**
        -   `kAudioAggregateDeviceNameKey`: "Audio Share"
        -   `kAudioAggregateDeviceUIDKey`: A unique string (e.g., "com.myapp.audioshare")
        -   `kAudioAggregateDeviceSubDeviceListKey`: Array of `[UID1, UID2]` (The two AirPods).
        -   `kAudioAggregateDeviceMasterSubDeviceKey`: UID of the first AirPods (Clock Source).
    -   **Drift Correction:**
        -   We must explicitly enable drift correction for the second device.
        -   **API:** `AudioObjectSetPropertyData` on the *Aggregate Device ID*.
        -   **Property:** `kAudioAggregateDevicePropertyDriftCompensation` (pass the `UID` of the secondary device).

3.  **Routing Audio**
    -   **API:** `AudioObjectSetPropertyData`
    -   **Target:** `kAudioObjectSystemObject`
    -   **Property:** `kAudioHardwarePropertyDefaultOutputDevice`
    -   **Value:** The `AudioDeviceID` of our new Aggregate Device.

4.  **Independent Volume Control (The "Secret Sauce")**
    -   **Challenge:** Aggregate devices usually lock their master volume.
    -   **Solution:** We do NOT control the aggregate device's volume. We control the **Constituent Devices** directly.
    -   **API:** `AudioObjectSetPropertyData`
    -   **Target:** The `AudioDeviceID` of *AirPods 1* and *AirPods 2* (individually).
    -   **Property:** `kAudioDevicePropertyVolumeScalar`
    -   **Scope:** `kAudioObjectPropertyScopeOutput`
    -   **Element:** `kAudioObjectPropertyElementMain` (or 0).

## 3. Device Management (State Machine)

-   **DeviceWatcher:** Observe `kAudioHardwarePropertyDevices` to detect when AirPods connect/disconnect.
-   **Connection Manager:**
    -   `startSharing(device1, device2)`: Creates aggregate -> Sets Default.
    -   `stopSharing()`: Destroys aggregate -> Restores previous default.
    -   Handle "Device Lost": If an AirPod disconnects, auto-stop sharing and revert to the remaining device.

## 4. User Interface (MenuBarExtra)

-   **Type:** `MenuBarExtra` (SwiftUI)
-   **Views:**
    -   `DeviceSelectorView`: Two `Picker`s filtering for "AirPods" or Bluetooth devices.
    -   `VolumeControlView`: Two `Slider`s.
        -   Slider 1 binds to `CoreAudioManager.setVolume(for: device1)`.
        -   Slider 2 binds to `CoreAudioManager.setVolume(for: device2)`.
    -   **Visuals:**
        -   "Start" button (Green) when ready.
        -   "Stop" button (Red) when active.
        -   Status Text: "Active: Audio Share" or "Idle".

## 5. Verification & Testing Plan

-   **Verify Creation:** Use "Audio MIDI Setup" app to visually confirm the "Audio Share" device appears with 2 sub-devices.
-   **Verify Drift:** Play a click track. Ensure no echo after 1 minute.
-   **Verify Volume:**
    -   Open "Audio MIDI Setup".
    -   Move App Slider 1.
    -   Confirm the *Master* slider of the specific AirPod device moves in Audio MIDI Setup.
    -   Confirm Aggregate Master slider does *not* move (or doesn't matter).

## 6. Implementation Steps

1.  **CoreAudioUtils.swift:** Helper wrappers for `AudioObjectGetPropertyData` (generic T).
2.  **AudioDevice.swift:** Struct wrapper for `AudioDeviceID` with `name`, `uid`, `volume` properties.
3.  **AggregateBuilder.swift:** The `createAggregate(_ uids: [String])` function.
4.  **AppModel.swift:** Main ViewModel holding the state.
5.  **MenuBar.swift:** The SwiftUI view.

