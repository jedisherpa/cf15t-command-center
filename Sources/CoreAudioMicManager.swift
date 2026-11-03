import Cocoa
import CoreAudio
import AudioToolbox

final class CoreAudioMicManager {
    static let shared = CoreAudioMicManager()

    private var savedNonZeroVolume: Float32 = 0.85

    private init() {
        let current = getInputVolumeScalar()
        if current > 0.05 {
            savedNonZeroVolume = current
        }
    }

    // MARK: - Default Input Device ID

    func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    func defaultInputDeviceName() -> String {
        guard let deviceID = defaultInputDeviceID() else { return "Built-in Microphone" }
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        if status == noErr {
            return name as String
        }
        return "System Microphone"
    }

    // MARK: - Hardware Mute + Input Volume Scalar

    func isSystemMicMuted() -> Bool {
        if let deviceID = defaultInputDeviceID() {
            var muteVal: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &address) {
                let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteVal)
                if status == noErr && muteVal == 1 {
                    return true
                }
            }
        }
        return getInputVolumeScalar() <= 0.01
    }

    func getInputVolumeScalar() -> Float32 {
        if let deviceID = defaultInputDeviceID() {
            for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
                var volume: Float32 = 0.0
                var size = UInt32(MemoryLayout<Float32>.size)
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeInput,
                    mElement: element
                )
                if AudioObjectHasProperty(deviceID, &address) {
                    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
                    if status == noErr {
                        return max(0.0, min(1.0, volume))
                    }
                }
            }
        }
        return 0.85
    }

    func setSystemMicMuted(_ muted: Bool) {
        if !muted {
            // Unmute and restore volume
            let targetVol = max(0.25, savedNonZeroVolume)
            setHardwareMuteProperty(false)
            setHardwareInputVolumeScalar(targetVol)
            setAppleScriptInputVolume(Int(targetVol * 100))
        } else {
            let current = getInputVolumeScalar()
            if current > 0.05 {
                savedNonZeroVolume = current
            }
            setHardwareMuteProperty(true)
            setHardwareInputVolumeScalar(0.0)
            setAppleScriptInputVolume(0)
        }
    }

    func setInputVolume(_ scalar: Float32) {
        let clamped = max(0.0, min(1.0, scalar))
        if clamped > 0.05 {
            savedNonZeroVolume = clamped
            setHardwareMuteProperty(false)
        } else if clamped <= 0.01 {
            setHardwareMuteProperty(true)
        }
        setHardwareInputVolumeScalar(clamped)
        setAppleScriptInputVolume(Int(clamped * 100))
    }

    private func setHardwareMuteProperty(_ muted: Bool) {
        guard let deviceID = defaultInputDeviceID() else { return }
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                var settable: DarwinBoolean = false
                AudioObjectIsPropertySettable(deviceID, &address, &settable)
                if settable.boolValue {
                    var val: UInt32 = muted ? 1 : 0
                    let size = UInt32(MemoryLayout<UInt32>.size)
                    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
                }
            }
        }
    }

    private func setHardwareInputVolumeScalar(_ volume: Float32) {
        guard let deviceID = defaultInputDeviceID() else { return }
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(deviceID, &address) {
                var settable: DarwinBoolean = false
                AudioObjectIsPropertySettable(deviceID, &address, &settable)
                if settable.boolValue {
                    var val: Float32 = volume
                    let size = UInt32(MemoryLayout<Float32>.size)
                    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val)
                }
            }
        }
    }

    private func setAppleScriptInputVolume(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        DispatchQueue.global(qos: .userInitiated).async {
            let script = NSAppleScript(source: "set volume input volume \(clamped)")
            var errorDict: NSDictionary?
            script?.executeAndReturnError(&errorDict)
        }
    }

    // MARK: - Send App-Level Voice Toggle Shortcut or Click In-App AX Mic Button

    func triggerVoiceShortcut(for slot: VoiceAssistantConfig, activateAppFirst: Bool) {
        if activateAppFirst {
            activateOrLaunchAssistant(slot)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + (activateAppFirst ? 0.16 : 0.02)) {
            // 1. Try clicking an explicit in-app Microphone/Mute button via Accessibility if available
            if self.tryClickInAppMicButton(for: slot) {
                return
            }

            // 2. Fallback to keyboard shortcut
            guard let keyCode = slot.micShortcut.keyCode else { return }
            let flags = slot.micShortcut.modifiers
            guard let src = CGEventSource(stateID: .hidSystemState) else { return }
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
                keyDown.flags = flags
                keyUp.flags = flags
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    private func tryClickInAppMicButton(for slot: VoiceAssistantConfig) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let runningApps = NSWorkspace.shared.runningApplications
        guard let match = runningApps.first(where: { app in
            guard let name = app.localizedName else { return false }
            return name.localizedCaseInsensitiveContains(slot.targetAppName) ||
                   name.localizedCaseInsensitiveContains(slot.displayName) ||
                   (app.bundleURL?.path.lowercased() == slot.appBundlePath.lowercased())
        }) else {
            return false
        }

        let axApp = AXUIElementCreateApplication(match.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        for win in windows {
            if let micButton = findMicButton(in: win, depth: 0) {
                AXUIElementPerformAction(micButton, kAXPressAction as CFString)
                return true
            }
        }
        return false
    }

    private func findMicButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 7 else { return nil }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "")
            : ""

        if role == kAXButtonRole as String || role == kAXCheckBoxRole as String || role == kAXRadioButtonRole as String {
            var titleRef: CFTypeRef?
            var descRef: CFTypeRef?
            var helpRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            _ = AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef)

            let combined = "\(titleRef as? String ?? "") \(descRef as? String ?? "") \(helpRef as? String ?? "")".lowercased()
            let micKeywords = ["microphone", "mute", "unmute", "voice", "dictat", "start talking", "stop talking", "mic"]
            if micKeywords.contains(where: { combined.contains($0) }) {
                return element
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findMicButton(in: child, depth: depth + 1) {
                    return found
                }
            }
        }
        return nil
    }

    @discardableResult
    func activateOrLaunchAssistant(_ slot: VoiceAssistantConfig) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications

        // 1. Match by localizedName or bundle path
        if let match = runningApps.first(where: { app in
            guard let name = app.localizedName else { return false }
            return name.localizedCaseInsensitiveContains(slot.targetAppName) ||
                   name.localizedCaseInsensitiveContains(slot.displayName) ||
                   (app.bundleURL?.path.lowercased() == slot.appBundlePath.lowercased())
        }) {
            NSApp.yieldActivation(to: match)
            match.unhide()
            match.activate(options: [.activateAllWindows])
            if let bundleURL = match.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
            }
            return true
        }

        // 2. Launch from bundle path if installed
        if FileManager.default.fileExists(atPath: slot.appBundlePath) {
            let url = URL(fileURLWithPath: slot.appBundlePath)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
            return true
        }

        // 3. Fallback to URL scheme or web URL
        if !slot.urlSchemeOrWebURL.isEmpty, let url = URL(string: slot.urlSchemeOrWebURL) {
            NSWorkspace.shared.open(url)
            return true
        }

        return false
    }
}
