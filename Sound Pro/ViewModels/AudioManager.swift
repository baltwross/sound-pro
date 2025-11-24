import SwiftUI
import CoreAudio
import Combine

// MARK: - AUDIO MANAGER
class AudioManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevices: [AudioDevice] = []
    @Published var deviceVolumes: [String: Float] = [:] // Keyed by UID for stability
    @Published var isSharing: Bool = false
    
    private var aggregateDeviceID: AudioDeviceID?
    private var previousDefaultDeviceID: AudioDeviceID?
    private var refreshTimer: Timer?
    
    // Constant UID for our aggregate device so we can filter it out
    private let aggregateUID = "com.soundpro.multioutput"
    
    init() {
        // Store original default device
        if let defaultID: AudioDeviceID = try? CoreAudioUtils.getProperty(
            id: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        ) {
            previousDefaultDeviceID = defaultID
        }
        
        refreshDevices()
        
        // Refresh device list periodically
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
        stopSharing()
    }
    
    func refreshDevices() {
        let devices = DeviceDiscovery.getAllDevices(excludingUID: aggregateUID)
        DispatchQueue.main.async {
            // Preserve selection by UID
            let selectedUIDs = Set(self.selectedDevices.map { $0.uid })
            self.availableDevices = devices
            
            // Update selectedDevices with fresh device objects (in case IDs changed)
            self.selectedDevices = devices.filter { selectedUIDs.contains($0.uid) }
            
            // Initialize volumes for new devices
            for device in devices {
                if self.deviceVolumes[device.uid] == nil {
                    // Read current volume from device
                    self.deviceVolumes[device.uid] = device.getCurrentVolume() ?? 0.5
                }
            }
        }
    }
    
    func toggleSelection(for device: AudioDevice) {
        if let index = selectedDevices.firstIndex(where: { $0.uid == device.uid }) {
            selectedDevices.remove(at: index)
        } else {
            selectedDevices.append(device)
        }
        updateSharingState()
    }
    
    func updateSharingState() {
        // Always destroy existing aggregate first
        if let aggID = aggregateDeviceID {
            print("[AudioManager] Destroying existing aggregate device: \(aggID)")
            AggregateBuilder.destroyAggregateDevice(id: aggID)
            aggregateDeviceID = nil
            
            // Small delay to let CoreAudio clean up
            usleep(100_000)
        }
        
        guard !selectedDevices.isEmpty else {
            // Restore original default if we had one
            if let prevID = previousDefaultDeviceID {
                try? AggregateBuilder.setDefaultOutputDevice(prevID)
            }
            isSharing = false
            return
        }
        
        if selectedDevices.count == 1 {
            // Single device - just set it as default
            let device = selectedDevices[0]
            do {
                try AggregateBuilder.setDefaultOutputDevice(device.id)
                isSharing = true
                print("[AudioManager] Set single device as default: \(device.name)")
            } catch {
                print("[AudioManager] Failed to set default device: \(error)")
                isSharing = false
            }
        } else {
            // Multiple devices - create multi-output aggregate
            do {
                let aggID = try AggregateBuilder.createMultiOutputDevice(
                    devices: selectedDevices,
                    uid: aggregateUID
                )
                aggregateDeviceID = aggID
                isSharing = true
                print("[AudioManager] Created multi-output device with \(selectedDevices.count) sub-devices")
                
                // Apply saved volumes to each device
                for device in selectedDevices {
                    if let vol = deviceVolumes[device.uid] {
                        device.setVolume(vol)
                    }
                }
            } catch {
                print("[AudioManager] Failed to create aggregate: \(error)")
                isSharing = false
            }
        }
    }
    
    func setVolume(_ vol: Float, for device: AudioDevice) {
        deviceVolumes[device.uid] = vol
        device.setVolume(vol)
    }
    
    func stopSharing() {
        if let aggID = aggregateDeviceID {
            AggregateBuilder.destroyAggregateDevice(id: aggID)
            aggregateDeviceID = nil
        }
        if let prevID = previousDefaultDeviceID {
            try? AggregateBuilder.setDefaultOutputDevice(prevID)
        }
        isSharing = false
    }
    
    func printDebugStatus() {
        print("\n========== SOUND PRO DEBUG ==========")
        print("Available Devices:")
        for d in availableDevices {
            print("  - \(d.name) | ID: \(d.id) | UID: \(d.uid) | Output: \(d.isOutput)")
        }
        print("\nSelected Devices:")
        for d in selectedDevices {
            let vol = deviceVolumes[d.uid] ?? -1
            print("  - \(d.name) | Volume: \(vol)")
        }
        print("\nAggregate Device ID: \(aggregateDeviceID ?? 0)")
        print("Is Sharing: \(isSharing)")
        
        // Get current default output
        if let defaultID: AudioDeviceID = try? CoreAudioUtils.getProperty(
            id: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        ) {
            let defaultName = (try? CoreAudioUtils.getStringProperty(id: defaultID, selector: kAudioDevicePropertyDeviceNameCFString)) ?? "Unknown"
            print("Current Default Output: \(defaultName) (ID: \(defaultID))")
        }
        print("======================================\n")
    }
}

