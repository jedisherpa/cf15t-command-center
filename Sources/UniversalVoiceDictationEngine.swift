import Cocoa
import Speech
import AVFoundation
import ApplicationServices

/// Universal Whisper-Flow & Speech Dictation Engine for CF15T Command Center.
/// Gives EVERY program tile (Signal, Antigravity, ChatGPT/Dot, Grok Bot, Google Chrome, Claude, Codex, etc.)
/// a 1-tap Microphone button that records speech, transcribes it via local Whisper (`/opt/homebrew/bin/whisper-clip`)
/// + live macOS Speech Recognition, and flows the text straight into that program's prompt window.
@MainActor
final class UniversalVoiceDictationEngine: ObservableObject {
    static let shared = UniversalVoiceDictationEngine()

    @Published var isRecording: Bool = false
    @Published var isTranscribingWhisper: Bool = false
    @Published var targetWindowID: CGWindowID? = nil
    @Published var targetAppName: String = ""
    @Published var liveTranscript: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var statusText: String = "Tap any tile's 🎙️ WHISPER MIC button to speak into that program's prompt"
    @Published var autoSendOnSilence: Bool = false
    @Published var autoPressReturnOnSend: Bool = true
    @Published var speechAuthGranted: Bool = false

    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioFileWriter: AVAudioFile?
    private let tempWavPath = "/tmp/cf15t-whisper-dictation.wav"
    private var silenceTimer: Timer?
    private var targetWindowSnapshot: MonitoredWindow?

    var onDictationSent: ((MonitoredWindow, String) -> Void)?

    private init() {
        checkSpeechAuthorization()
    }

    func checkSpeechAuthorization() {
        let status = SFSpeechRecognizer.authorizationStatus()
        speechAuthGranted = (status == .authorized)
    }

    func requestSpeechAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized {
            speechAuthGranted = true
            completion(true)
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                let granted = (status == .authorized)
                self.speechAuthGranted = granted
                completion(granted)
            }
        }
    }

    // MARK: - Toggle / Start / Stop Whisper Dictation for Any Program Tile

    func toggleDictation(for window: MonitoredWindow) {
        if isRecording && targetWindowID == window.id {
            // Second tap on the active mic button finishes recording and flows text into the target app!
            stopAndSendDictation(pressReturn: autoPressReturnOnSend)
        } else {
            startDictation(for: window)
        }
    }

    func startDictation(for window: MonitoredWindow) {
        if isRecording {
            stopAudioCaptureOnly()
        }

        // Ensure hardware microphone is unmuted when starting voice dictation
        if CoreAudioMicManager.shared.isSystemMicMuted() {
            CoreAudioMicManager.shared.setSystemMicMuted(false)
        }

        targetWindowSnapshot = window
        targetWindowID = window.id
        targetAppName = window.appName
        liveTranscript = ""
        statusText = "🎙️ Whisper Listening for \(window.appName)... Speak now, tap again to flow into prompt"

        // Always start AVAudioEngine capture (writes WAV for local Whisper + feeds SFSpeechRecognizer if authorized)
        beginAudioAndWhisperCapture(for: window)

        requestSpeechAuthorizationIfNeeded { [weak self] granted in
            guard let self = self, self.isRecording else { return }
            if granted, let req = self.recognitionRequest, let recognizer = self.speechRecognizer, recognizer.isAvailable {
                self.startLiveSpeechTask(with: req, recognizer: recognizer)
            }
        }
    }

    private func beginAudioAndWhisperCapture(for window: MonitoredWindow) {
        stopAudioCaptureOnly()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.channelCount > 0 else {
            isRecording = true
            statusText = "No audio input channel available"
            return
        }

        // Prepare WAV file for local Whisper (`/opt/homebrew/bin/whisper-clip`)
        try? FileManager.default.removeItem(atPath: tempWavPath)
        let wavURL = URL(fileURLWithPath: tempWavPath)
        audioFileWriter = try? AVAudioFile(forWriting: wavURL, settings: recordingFormat.settings)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            try? self?.audioFileWriter?.write(from: buffer)

            // Compute RMS audio level for live visual waveform meter
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                if frameLength > 0 {
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = channelData[i]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    let normalized = min(1.0, max(0.05, rms * 8.5))
                    Task { @MainActor [weak self] in
                        self?.audioLevel = normalized
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            statusText = "🔴 WHISPER LISTENING FOR \(window.appName.uppercased()) — Speak now, then tap SEND ⏎"
        } catch {
            isRecording = true
            statusText = "Audio capture error: \(error.localizedDescription)"
        }
    }

    private func startLiveSpeechTask(with request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer) {
        recognitionTask?.cancel()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        self.liveTranscript = text
                        self.resetSilenceTimerIfNeeded()
                    }
                }
            }
        }
    }

    private func resetSilenceTimerIfNeeded() {
        silenceTimer?.invalidate()
        guard autoSendOnSilence else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isRecording, !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                self.stopAndSendDictation(pressReturn: self.autoPressReturnOnSend)
            }
        }
    }

    func stopAndSendDictation(pressReturn: Bool = true) {
        let currentLiveText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetWin = targetWindowSnapshot
        stopAudioCaptureOnly()
        isRecording = false
        audioLevel = 0.0

        guard let win = targetWin else {
            targetWindowID = nil
            return
        }

        // If we already have a live transcript from speech recognition or user typing, send immediately,
        // otherwise run local `/opt/homebrew/bin/whisper-clip -f /tmp/cf15t-whisper-dictation.wav`!
        if !currentLiveText.isEmpty {
            statusText = "Whisper flowing into \(win.appName): \"\(currentLiveText)\""
            deliverInstructionToWindow(currentLiveText, window: win, pressReturn: pressReturn)
            liveTranscript = ""
            targetWindowID = nil
        } else {
            isTranscribingWhisper = true
            statusText = "Transcribing with Local Whisper for \(win.appName)..."
            let wavFile = tempWavPath
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let whisperResult = Self.runLocalWhisperClip(wavPath: wavFile)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isTranscribingWhisper = false
                    let finalStr = whisperResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalStr.isEmpty {
                        self.statusText = "Whisper flowed into \(win.appName): \"\(finalStr)\""
                        self.deliverInstructionToWindow(finalStr, window: win, pressReturn: pressReturn)
                    } else {
                        self.statusText = "No speech detected for \(win.appName)"
                    }
                    self.liveTranscript = ""
                    self.targetWindowID = nil
                }
            }
        }
    }

    nonisolated private static func runLocalWhisperClip(wavPath: String) -> String {
        guard FileManager.default.fileExists(atPath: wavPath) else { return "" }

        // 1. Try user's `/opt/homebrew/bin/whisper-clip -f <wavPath>` (Local Whisper / Ollama / Pillar bridge)
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-clip") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-clip")
            proc.arguments = ["-f", wavPath]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        return text
                    }
                }
            } catch {}
        }

        // 2. Fallback to `/opt/homebrew/bin/whisper-cli` if a local ggml model exists
        let ggmlCandidates = [
            "/opt/homebrew/Cellar/whisper-cpp/1.8.4/share/whisper-cpp/for-tests-ggml-tiny.bin"
        ]
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/whisper-cli"),
           let modelPath = ggmlCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
            proc.arguments = ["-m", modelPath, "-f", wavPath, "-nt"]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    return text
                }
            } catch {}
        }

        return ""
    }

    func cancelDictation() {
        stopAudioCaptureOnly()
        isRecording = false
        isTranscribingWhisper = false
        audioLevel = 0.0
        liveTranscript = ""
        targetWindowID = nil
        statusText = "Dictation canceled"
    }

    private func stopAudioCaptureOnly() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFileWriter = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Flow Dictated Text Directly Into Target App's Open Prompt Window (Background-Safe: Never Leaves Zoom)

    func deliverInstructionToWindow(_ text: String, window: MonitoredWindow, pressReturn: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetPID = resolveTargetPID(for: window)

        // 1. Copy text to NSPasteboard as a convenience backup
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)

        // 2. Focus the editable prompt field inside the target window via Accessibility WITHOUT activating
        //    the app or raising its window, so Zoom (or any frontmost app on the laptop) stays untouched.
        _ = focusEditableTextElementInBackground(pid: targetPID, windowTitle: window.windowTitle)

        // 3. Stream the text and optional Return key directly to targetPID's event queue in the background
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let src = CGEventSource(stateID: .hidSystemState)
            let utf16Units = Array(trimmed.utf16)
            let chunkSize = 18
            var offset = 0
            while offset < utf16Units.count {
                let end = min(offset + chunkSize, utf16Units.count)
                var slice = Array(utf16Units[offset..<end])
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                   let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                    up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                    down.postToPid(targetPID)
                    up.postToPid(targetPID)
                }
                offset = end
            }

            if pressReturn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    if let retDown = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true),
                       let retUp = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false) {
                        retDown.flags = []
                        retUp.flags = []
                        retDown.postToPid(targetPID)
                        retUp.postToPid(targetPID)
                    }
                    self.onDictationSent?(window, trimmed)
                }
            } else {
                self.onDictationSent?(window, trimmed)
            }
        }
    }

    private func resolveTargetPID(for window: MonitoredWindow) -> pid_t {
        if window.id == 999_999 {
            let hostKeywords = ["antigravity", "cursor", "code", "windsurf"]
            if let hostApp = NSWorkspace.shared.runningApplications.first(where: { app in
                let name = (app.localizedName ?? "").lowercased()
                let bundle = (app.bundleIdentifier ?? "").lowercased()
                return hostKeywords.contains(where: { name.contains($0) || bundle.contains($0) })
            }) {
                return hostApp.processIdentifier
            }
        }
        return window.ownerPID
    }

    @discardableResult
    private func focusEditableTextElementInBackground(pid: pid_t, windowTitle: String) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.08)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement],
              !axWindows.isEmpty else {
            return false
        }

        let targetWin: AXUIElement = {
            if !windowTitle.isEmpty {
                for w in axWindows {
                    var tRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tRef) == .success,
                       let t = tRef as? String,
                       (t == windowTitle || t.localizedCaseInsensitiveContains(windowTitle)) {
                        return w
                    }
                }
            }
            return axWindows[0]
        }()

        return focusEditableTextElement(in: targetWin, depth: 0)
    }

    @discardableResult
    private func focusEditableTextElement(in element: AXUIElement, depth: Int) -> Bool {
        guard depth <= 9 else { return false }

        var roleRef: CFTypeRef?
        let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
            ? (roleRef as? String ?? "")
            : ""

        if role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return true
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children.reversed().prefix(24) {
                if focusEditableTextElement(in: child, depth: depth + 1) {
                    return true
                }
            }
        }
        return false
    }
}
