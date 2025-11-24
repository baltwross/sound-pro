import Foundation
import CoreAudio

// MARK: - DEVICE DISCOVERY
class DeviceDiscovery {
    
    static func getAllDevices(excludingUID: String? = nil) -> [AudioDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            print("[DeviceDiscovery] Failed to get device list size")
            return []
        }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            print("[DeviceDiscovery] Failed to get device list")
            return []
        }
        
        var devices: [AudioDevice] = []
        
        for id in ids {
            do {
                let device = try AudioDevice(id: id)
                
                // Skip non-output devices
                guard device.isOutput else { continue }
                
                // Skip our own aggregate device
                if let excludeUID = excludingUID, device.uid.hasPrefix(excludeUID) {
                    continue
                }
                
                // Skip devices with "Audio Share" or "Sound Pro" in the name (our aggregates)
                if device.name.contains("Audio Share") || device.name.contains("Sound Pro") {
                    continue
                }
                
                devices.append(device)
            } catch {
                // Skip devices that fail to initialize (e.g., virtual devices without proper UIDs)
                continue
            }
        }
        
        print("[DeviceDiscovery] Found \(devices.count) output devices")
        return devices
    }
}

