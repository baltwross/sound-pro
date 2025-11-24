import Foundation
import CoreAudio

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

