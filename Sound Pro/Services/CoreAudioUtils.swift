import Foundation
import CoreAudio

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

