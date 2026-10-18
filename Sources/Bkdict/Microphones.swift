import CoreAudio
import Foundation

/// The audio input devices, and which one to record from.
///
/// Recording from a Bluetooth headset's microphone switches it from its music profile to its call profile: the
/// sound drops to phone quality and most players pause. So, by default, a Bluetooth microphone is swapped for the
/// Mac's built-in one, and the headphones keep playing.
enum Microphones {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        /// Stable across reboots and reconnections, unlike `id`; this is what the settings store.
        let uid: String
        let name: String
        let transport: UInt32

        var isBluetooth: Bool {
            transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        }
        var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    }

    /// The value stored in `Settings.microphone` for the automatic choice.
    static let automatic = "auto"

    static var inputs: [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInput).compactMap(device)
    }

    /// The device to record from for a setting: a chosen microphone if it is still connected, otherwise the
    /// system default, unless that is Bluetooth and the Mac has a built-in microphone.
    static func resolve(_ setting: String) -> Device? {
        let inputs = inputs
        if setting != automatic, let chosen = inputs.first(where: { $0.uid == setting }) { return chosen }
        let system = defaultInput.flatMap { id in inputs.first { $0.id == id } }
        if let system, system.isBluetooth, let builtIn = inputs.first(where: \.isBuiltIn) { return builtIn }
        return system
    }

    private static var defaultInput: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func device(_ id: AudioDeviceID) -> Device? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return Device(id: id, uid: uid, name: name, transport: transport)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
