import Foundation
import CoreAudio

// MARK: - AGGREGATE BUILDER
class AggregateBuilder {
    
    /// Creates a Multi-Output Device (stacked aggregate) that mirrors audio to all sub-devices
    static func createMultiOutputDevice(devices: [AudioDevice], uid: String) throws -> AudioDeviceID {
        guard devices.count >= 2 else {
            throw CoreAudioUtils.CoreAudioError.operationFailed(-1)
        }
        
        let masterDevice = devices[0]
        
        // Build sub-device list with drift compensation for non-master devices
        // CRITICAL: Drift compensation prevents audio sync issues with Bluetooth
        var subDeviceList: [[String: Any]] = []
        for (index, device) in devices.enumerated() {
            var subDict: [String: Any] = [
                kAudioSubDeviceUIDKey: device.uid
            ]
            // Enable drift compensation for all devices except master (index 0)
            if index > 0 {
                subDict[kAudioSubDeviceDriftCompensationKey] = 1
            }
            subDeviceList.append(subDict)
        }
        
        // Configuration dictionary for the aggregate device
        // CRITICAL: kAudioAggregateDeviceIsStackedKey = 1 makes this a MULTI-OUTPUT device
        // (same audio sent to all outputs) vs = 0 which is an AGGREGATE device
        // (channels are stacked/combined into one big device)
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sound Pro Multi-Output",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceMasterSubDeviceKey: masterDevice.uid,
            kAudioAggregateDeviceIsStackedKey: 1,  // ← THIS IS THE KEY FIX: 1 = Multi-Output
            kAudioAggregateDeviceIsPrivateKey: 0   // Make it visible in Audio MIDI Setup for debugging
        ]
        
        print("[AggregateBuilder] Creating multi-output device with config:")
        print("  Master: \(masterDevice.name) (\(masterDevice.uid))")
        for (i, device) in devices.enumerated() {
            let drift = i > 0 ? "drift=ON" : "drift=OFF (master)"
            print("  Sub-device \(i): \(device.name) [\(drift)]")
        }
        
        var aggregateID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &aggregateID)
        
        if status != noErr {
            print("[AggregateBuilder] Error creating aggregate device: OSStatus \(status)")
            throw CoreAudioUtils.CoreAudioError.operationFailed(status)
        }
        
        print("[AggregateBuilder] Successfully created aggregate device ID: \(aggregateID)")
        
        // Wait for device to be fully registered in the audio system
        usleep(300_000) // 300ms
        
        // Set as the system's default output device
        try setDefaultOutputDevice(aggregateID)
        
        return aggregateID
    }
    
    static func destroyAggregateDevice(id: AudioDeviceID) {
        let status = AudioHardwareDestroyAggregateDevice(id)
        if status != noErr {
            print("[AggregateBuilder] Warning: Failed to destroy aggregate device \(id): OSStatus \(status)")
        } else {
            print("[AggregateBuilder] Destroyed aggregate device \(id)")
        }
    }
    
    static func setDefaultOutputDevice(_ id: AudioDeviceID) throws {
        var deviceID = id
        try CoreAudioUtils.setProperty(
            id: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            value: &deviceID
        )
        print("[AggregateBuilder] Set default output device to ID: \(id)")
    }
}

