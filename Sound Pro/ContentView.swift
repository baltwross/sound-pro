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
                ForEach(audioManager.availableDevices, id: \.self) { device in
                    DeviceRow(
                        device: device,
                        isSelected: audioManager.selectedDevices.contains(device),
                        volume: Binding(
                            get: { audioManager.deviceVolumes[device.id] ?? 0.5 },
                            set: { audioManager.setVolume($0, for: device) }
                        ),
                        onToggle: {
                            audioManager.toggleSelection(for: device)
                        }
                    )
                    
                    if device != audioManager.availableDevices.last {
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
                Image(systemName: "headphones") // Dynamic icon could be added
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
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
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
}

// MARK: - AUDIO MANAGER
class AudioManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevices: Set<AudioDevice> = []
    @Published var deviceVolumes: [AudioDeviceID: Float] = [:]
    @Published var isSharing: Bool = false
    
    private var aggregateDeviceID: AudioDeviceID?
    private var previousDefaultDeviceID: AudioDeviceID?
    
    init() {
        refreshDevices()
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.refreshDevices()
        }
    }
    
    func refreshDevices() {
        let devices = DeviceDiscovery.getAllDevices()
        DispatchQueue.main.async {
            self.availableDevices = devices
            // Clean up disconnected devices from selection
            let currentIDs = Set(devices.map { $0.id })
            self.selectedDevices = self.selectedDevices.filter { currentIDs.contains($0.id) }
        }
    }
    
    func toggleSelection(for device: AudioDevice) {
        if selectedDevices.contains(device) {
            selectedDevices.remove(device)
        } else {
            selectedDevices.insert(device)
        }
        updateSharingState()
    }
    
    func updateSharingState() {
        // Stop current sharing first
        if let aggID = aggregateDeviceID {
            if let prevID = previousDefaultDeviceID {
                try? AggregateBuilder.setDefaultOutputDevice(prevID)
            }
            AggregateBuilder.destroyAggregateDevice(id: aggID)
            aggregateDeviceID = nil
        }
        
        guard !selectedDevices.isEmpty else {
            isSharing = false
            return
        }
        
        // Start sharing with new selection
        // Save current default if we haven't already (and we aren't the default)
        if previousDefaultDeviceID == nil, let defaultID: AudioDeviceID = try? CoreAudioUtils.getProperty(id: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice) {
            previousDefaultDeviceID = defaultID
        }
        
        let devicesList = Array(selectedDevices)
        if devicesList.count == 1 {
            // Single device? Just set it as default
            try? AggregateBuilder.setDefaultOutputDevice(devicesList[0].id)
            isSharing = true
        } else {
            // Multiple devices -> Aggregate
            do {
                let aggID = try AggregateBuilder.createAggregateDevice(devices: devicesList)
                aggregateDeviceID = aggID
                isSharing = true
                
                // Restore volumes
                for device in devicesList {
                    if let vol = deviceVolumes[device.id] {
                        try? device.setVolume(vol)
                    }
                }
            } catch {
                print("Error creating aggregate: \(error)")
                isSharing = false
            }
        }
    }
    
    func setVolume(_ vol: Float, for device: AudioDevice) {
        deviceVolumes[device.id] = vol
        try? device.setVolume(vol)
    }
}

// MARK: - CORE AUDIO ENGINE

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    
    init(id: AudioDeviceID) throws {
        self.id = id
        self.name = try CoreAudioUtils.getStringProperty(id: id, selector: kAudioDevicePropertyDeviceNameCFString)
        self.uid = try CoreAudioUtils.getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID)
    }
    
    var isOutput: Bool {
        // Check if device has output streams
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeOutput, mElement: 0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        
        let bufList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufList) == noErr else { return false }
        
        let buffers = UnsafeMutableAudioBufferListPointer(bufList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
    
    func setVolume(_ volume: Float) throws {
        var vol = volume
        // Try setting volume on Main, Left, and Right channels.
        // We ignore errors because some devices (like AirPods) might only accept Master (0) or only Channels (1/2).
        
        var success = false
        
        // Try Master (0)
        if (try? CoreAudioUtils.setProperty(id: id, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 0, value: &vol)) != nil {
            success = true
        }
        
        // Try Left (1)
        if (try? CoreAudioUtils.setProperty(id: id, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 1, value: &vol)) != nil {
            success = true
        }
        
        // Try Right (2)
        if (try? CoreAudioUtils.setProperty(id: id, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 2, value: &vol)) != nil {
            success = true
        }
        
        if !success {
             print("Warning: Failed to set volume for device \(name) (ID: \(id))")
        }
    }
}

class AggregateBuilder {
    static func createAggregateDevice(devices: [AudioDevice]) throws -> AudioDeviceID {
        guard !devices.isEmpty else { throw CoreAudioUtils.CoreAudioError.operationFailed(-1) }
        
        let masterDevice = devices[0]
        
        // Build the sub-device list with Drift Compensation
        // CRITICAL: Non-master devices MUST have drift compensation enabled or they may be silent/out of sync.
        let subDevicesDicts = devices.enumerated().map { (index, device) -> [String: Any] in
            var subDict: [String: Any] = [
                kAudioSubDeviceUIDKey: device.uid
            ]
            // Enable drift compensation (1) for all devices except the master (index 0)
            if index > 0 {
                subDict[kAudioSubDeviceDriftCompensationKey] = 1
            }
            return subDict
        }
        
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Audio Share",
            kAudioAggregateDeviceUIDKey: "com.audioshare.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceMasterSubDeviceKey: masterDevice.uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevicesDicts,
            kAudioAggregateDeviceIsStackedKey: 0 // 0 = Mirror/Multi-Output, 1 = Aggregate/Stacked
        ]
        
        var aggregateID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregateID)
        
        if status != noErr {
            print("Error creating aggregate device: \(status)")
            throw CoreAudioUtils.CoreAudioError.operationFailed(status)
        }
        
        print("Successfully created Aggregate Device ID: \(aggregateID)")
        
        // Wait for device registration
        usleep(200000)
        
        // Set as default output
        try setDefaultOutputDevice(aggregateID)
        return aggregateID
    }
    
    static func destroyAggregateDevice(id: AudioDeviceID) {
        AudioHardwareDestroyAggregateDevice(id)
    }
    
    static func setDefaultOutputDevice(_ id: AudioDeviceID) throws {
        var deviceID = id
        // CoreAudioUtils.setProperty is now void-returning, so we don't need to capture its result or return value closure
        try CoreAudioUtils.setProperty(id: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, value: &deviceID)
    }
}

class DeviceDiscovery {
    static func getAllDevices() -> [AudioDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        
        let devices = ids.compactMap { try? AudioDevice(id: $0) }
        
        // Debug: Print all devices found
        // print("Debug: Found \(devices.count) devices total.")
        // for dev in devices { print("- \(dev.name) (Output: \(dev.isOutput))") }
        
        return devices.filter { $0.isOutput }
    }
}

class CoreAudioUtils {
    enum CoreAudioError: Error { case operationFailed(OSStatus) }
    
    static func getProperty<T>(id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = 0) throws -> T {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, value)
        guard status == noErr else { throw CoreAudioError.operationFailed(status) }
        return value.pointee
    }
    
    static func setProperty<T>(id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = 0, value: inout T) throws {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let status = withUnsafePointer(to: &value) { ptr in
            AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), ptr)
        }
        guard status == noErr else { throw CoreAudioError.operationFailed(status) }
    }
    
    static func getStringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)
        var ref: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        
        let status = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        
        guard status == noErr, let str = ref as String? else { throw CoreAudioError.operationFailed(-1) }
        return str
    }
}

