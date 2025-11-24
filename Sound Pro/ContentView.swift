import SwiftUI
import CoreAudio
import Combine

// MARK: - UI VIEW
struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "airpods.pro")
                Text("Audio Share")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            .padding(.horizontal)
            
            // Device List
            VStack(spacing: 0) {
                ForEach(audioManager.availableDevices, id: \.uid) { device in
                    DeviceRow(
                        device: device,
                        isSelected: audioManager.selectedDevices.contains(where: { $0.uid == device.uid }),
                        volume: Binding(
                            get: { audioManager.deviceVolumes[device.uid] ?? 0.5 },
                            set: { audioManager.setVolume($0, for: device) }
                        ),
                        onToggle: {
                            audioManager.toggleSelection(for: device)
                        }
                    )
                    
                    if device.uid != audioManager.availableDevices.last?.uid {
                        Divider()
                            .padding(.leading, 44)
                            .opacity(0.3)
                    }
                }
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            
            if audioManager.isSharing {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .symbolEffect(.pulse)
                        .foregroundStyle(.green)
                    Text("Sharing Audio to \(audioManager.selectedDevices.count) Devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            // Debug button (can be removed later)
            Button("Print Debug Info") {
                audioManager.printDebugStatus()
            }
            .font(.caption2)
            .padding(.top, 4)
        }
        .padding(.vertical)
        .frame(width: 320)
        .background(.regularMaterial)
    }
}

struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    @Binding var volume: Float
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: deviceIcon)
                    .font(.title3)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            
            if isSelected {
                HStack {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var deviceIcon: String {
        let lowercasedName = device.name.lowercased()
        if lowercasedName.contains("airpods") {
            if lowercasedName.contains("pro") {
                return "airpodspro"
            } else if lowercasedName.contains("max") {
                return "airpodsmax"
            }
            return "airpods"
        } else if lowercasedName.contains("headphone") {
            return "headphones"
        } else if lowercasedName.contains("speaker") || lowercasedName.contains("macbook") {
            return "hifispeaker"
        }
        return "headphones"
    }
}

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

// MARK: - AUDIO DEVICE
struct AudioDevice: Identifiable, Hashable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    
    // Hashable/Equatable based on UID only (stable across reconnects)
    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
    
    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.uid == rhs.uid
    }
    
    init(id: AudioDeviceID) throws {
        self.id = id
        
        // Get device name
        let nameResult = try? CoreAudioUtils.getStringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
        self.name = nameResult ?? "Unknown Device \(id)"
        
        // Get device UID (critical for aggregate device creation)
        guard let uidResult = try? CoreAudioUtils.getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) else {
            throw CoreAudioUtils.CoreAudioError.operationFailed(-1)
        }
        self.uid = uidResult
    }
    
    var isOutput: Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 0
        )
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        
        let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufList) == noErr else { return false }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
    
    func getCurrentVolume() -> Float? {
        // Try to read volume from master channel first, then L/R
        for element: UInt32 in [0, 1, 2] {
            if let vol: Float = try? CoreAudioUtils.getProperty(
                id: id,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            ) {
                return vol
            }
        }
        return nil
    }
    
    func setVolume(_ volume: Float) {
        var vol = max(0, min(1, volume))
        var success = false
        
        // Try Master (element 0)
        if (try? CoreAudioUtils.setProperty(
            id: id,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 0,
            value: &vol
        )) != nil {
            success = true
        }
        
        // Try Left channel (element 1)
        if (try? CoreAudioUtils.setProperty(
            id: id,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 1,
            value: &vol
        )) != nil {
            success = true
        }
        
        // Try Right channel (element 2)
        if (try? CoreAudioUtils.setProperty(
            id: id,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: 2,
            value: &vol
        )) != nil {
            success = true
        }
        
        if !success {
            print("[AudioDevice] Warning: Could not set volume for \(name)")
        }
    }
}

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

// MARK: - CORE AUDIO UTILITIES
class CoreAudioUtils {
    enum CoreAudioError: Error {
        case operationFailed(OSStatus)
        
        var localizedDescription: String {
            switch self {
            case .operationFailed(let status):
                return "Core Audio operation failed with status: \(status)"
            }
        }
    }
    
    static func getProperty<T>(
        id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = 0
    ) throws -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value)
        guard status == noErr else {
            throw CoreAudioError.operationFailed(status)
        }
        return value.pointee
    }
    
    static func setProperty<T>(
        id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = 0,
        value: inout T
    ) throws {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let status = withUnsafePointer(to: &value) { ptr in
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), ptr)
        }
        guard status == noErr else {
            throw CoreAudioError.operationFailed(status)
        }
    }
    
    static func getStringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )
        var ref: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        
        let status = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        
        guard status == noErr, let str = ref as String? else {
            throw CoreAudioError.operationFailed(status)
        }
        return str
    }
}
