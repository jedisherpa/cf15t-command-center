import Cocoa
import ApplicationServices
import Vision

final class AppContentFeedExtractor {
    static let shared = AppContentFeedExtractor()

    private var enabledManualAXPIDs: Set<pid_t> = []
    private var cachedDigests: [CGWindowID: (timestamp: TimeInterval, digest: WindowLiveDigest)] = [:]
    private let cacheTTL: TimeInterval = 2.2

    // Noise UI labels to ignore when extracting real conversation / thread content
    private let ignoredChromeLabels: Set<String> = [
        "close", "minimize", "zoom", "full screen", "back", "forward", "reload",
        "search", "send", "attach", "emoji", "voice", "mute", "unmute", "settings",
        "new chat", "today", "yesterday", "pinned", "archived", "all", "unread",
        "groups", "calls", "chats", "status", "channels", "communities", "type a message",
        "message", "ask anything", "reply", "copy", "regenerate", "share", "edit",
        "cancel", "ok", "done", "file", "view", "window", "help", "history", "bookmarks"
    ]

    private init() {}

    // MARK: - Public Entry Point

    func extractLiveDigest(for window: MonitoredWindow, forceRefresh: Bool = false) -> WindowLiveDigest {
        let now = Date().timeIntervalSinceReferenceDate
        if !forceRefresh,
           let cached = cachedDigests[window.id],
           (now - cached.timestamp) < cacheTTL,
           !cached.digest.lines.isEmpty {
            return cached.digest
        }

        let style = classifyStyle(for: window)

        // 1. Special fast-path if this window is Antigravity (or shows Antigravity brain workspace)
        if window.platform == .antigravity ||
           window.appName.localizedCaseInsensitiveContains("Antigravity") ||
           window.windowTitle.localizedCaseInsensitiveContains("Antigravity") {
            if let agyDigest = buildAntigravityLiveDigest(window: window) {
                cachedDigests[window.id] = (now, agyDigest)
                return agyDigest
            }
        }

        // 2. Harvest live text blocks from macOS Accessibility tree (AXUIElement)
        var extractedBlocks = harvestAXTextBlocks(for: window)

        // 3. Fallback / Augmentation via Apple Vision OCR on the live window snapshot if AX returned < 2 blocks
        if extractedBlocks.count < 2, let preview = window.previewImage {
            let ocrBlocks = extractVisionOCRBlocks(from: preview, windowBounds: window.bounds)
            if ocrBlocks.count > extractedBlocks.count {
                extractedBlocks = ocrBlocks
            }
        }

        // 4. If this is a known AI agent (e.g. Claude / Codex / Grok / ChatGPT) and still empty, check process CLI / Antigravity transcript
        if extractedBlocks.isEmpty && window.platform == .antigravity {
            if let agyDigest = buildAntigravityLiveDigest(window: window) {
                cachedDigests[window.id] = (now, agyDigest)
                return agyDigest
            }
        }

        let digest = formatBlocksIntoDigest(
            blocks: extractedBlocks,
            window: window,
            style: style
        )
        cachedDigests[window.id] = (now, digest)
        return digest
    }

    // MARK: - Classify App Display Style

    func classifyStyle(for window: MonitoredWindow) -> DigestPresentationStyle {
        let app = window.appName.lowercased()
        let title = window.windowTitle.lowercased()

        if app.contains("signal") || app.contains("whatsapp") || app.contains("messages") ||
           app.contains("telegram") || app.contains("slack") || app.contains("discord") {
            return .messagingChat
        }

        if window.platform != nil ||
           app.contains("chatgpt") || app.contains("grok") || app.contains("claude") ||
           app.contains("codex") || app.contains("antigravity") || app.contains("cursor") ||
           app.contains("ollama") || title.contains("chatgpt") || title.contains("claude") {
            return .aiAgentThread
        }

        if app.contains("music") || app.contains("spotify") || app.contains("podcasts") {
            return .mediaNowPlaying
        }

        if app.contains("chrome") || app.contains("safari") || app.contains("arc") ||
           app.contains("brave") || app.contains("firefox") {
            return .browserDocument
        }

        return .systemInspector
    }

    // MARK: - Spatial Text Block Model

    private struct SpatialTextBlock {
        let text: String
        let frame: CGRect
        let role: String
    }

    // MARK: - Layer 1: Antigravity Live Brain Transcript Reader

    func buildAntigravityLiveDigest(window: MonitoredWindow?) -> WindowLiveDigest? {
        let brainRoot = "/Users/paulcooper/.gemini/antigravity/brain"
        let fm = FileManager.default
        guard let convDirs = try? fm.contentsOfDirectory(atPath: brainRoot) else { return nil }

        var newestTranscriptPath: String?
        var newestDate: Date = .distantPast

        for dir in convDirs {
            let candidate = "\(brainRoot)/\(dir)/.system_generated/logs/transcript.jsonl"
            if let attrs = try? fm.attributesOfItem(atPath: candidate),
               let modDate = attrs[.modificationDate] as? Date,
               modDate > newestDate {
                newestDate = modDate
                newestTranscriptPath = candidate
            }
        }

        guard let path = newestTranscriptPath,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readBytes: UInt64 = min(fileSize, 48_000)
        if fileSize > readBytes {
            try? handle.seek(toOffset: fileSize - readBytes)
        } else {
            try? handle.seek(toOffset: 0)
        }

        guard let data = try? handle.readToEnd(),
              let rawString = String(data: data, encoding: .utf8) else { return nil }

        let jsonLines = rawString.components(separatedBy: .newlines).suffix(30)
        var feedLines: [DigestFeedLine] = []

        for (idx, line) in jsonLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let stepType = (obj["type"] as? String) ?? ""
            let content = (obj["content"] as? String) ?? ""

            if stepType == "USER_INPUT" {
                let clean = cleanUserRequestString(content)
                if clean.count >= 4 {
                    feedLines.append(
                        DigestFeedLine(
                            id: "agy-u-\(idx)",
                            speakerOrTag: "YOU",
                            text: clean,
                            isIncomingOrAgent: false,
                            isHighlighted: false
                        )
                    )
                }
            } else if stepType == "PLANNER_RESPONSE" {
                if let toolCalls = obj["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    let toolNames = toolCalls.compactMap { $0["name"] as? String }
                        .map { $0.replacingOccurrences(of: "default_api:", with: "") }
                    if !toolNames.isEmpty {
                        feedLines.append(
                            DigestFeedLine(
                                id: "agy-t-\(idx)",
                                speakerOrTag: "TOOL",
                                text: "Running: \(toolNames.joined(separator: ", "))",
                                isIncomingOrAgent: true,
                                isHighlighted: false
                            )
                        )
                    }
                }

                let cleanResp = cleanMarkdownString(content)
                if cleanResp.count >= 6 {
                    feedLines.append(
                        DigestFeedLine(
                            id: "agy-r-\(idx)",
                            speakerOrTag: "ANTIGRAVITY",
                            text: cleanResp,
                            isIncomingOrAgent: true,
                            isHighlighted: true
                        )
                    )
                }
            }
        }

        guard !feedLines.isEmpty else { return nil }
        var tail = Array(feedLines.suffix(5))
        if !tail.isEmpty {
            for i in 0..<(tail.count - 1) {
                tail[i] = DigestFeedLine(
                    id: tail[i].id,
                    speakerOrTag: tail[i].speakerOrTag,
                    text: tail[i].text,
                    isIncomingOrAgent: tail[i].isIncomingOrAgent,
                    isHighlighted: false
                )
            }
            let last = tail[tail.count - 1]
            tail[tail.count - 1] = DigestFeedLine(
                id: last.id,
                speakerOrTag: last.speakerOrTag,
                text: last.text,
                isIncomingOrAgent: last.isIncomingOrAgent,
                isHighlighted: true
            )
        }

        return WindowLiveDigest(
            style: .aiAgentThread,
            contextTitle: window?.displayTitle ?? "Antigravity Live Agent Session",
            statusBadge: "LIVE AGENT STREAM",
            lines: tail
        )
    }

    private func cleanUserRequestString(_ raw: String) -> String {
        var s = raw
        if let startRange = s.range(of: "<USER_REQUEST>"),
           let endRange = s.range(of: "</USER_REQUEST>") {
            s = String(s[startRange.upperBound..<endRange.lowerBound])
        }
        if s.contains("<SYSTEM_MESSAGE>") { return "" }
        return s
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanMarkdownString(_ raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "### ", with: "")
                  .replacingOccurrences(of: "## ", with: "")
                  .replacingOccurrences(of: "**", with: "")
                  .replacingOccurrences(of: "`", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") }
        return lines.prefix(3).joined(separator: " · ")
    }

    // MARK: - Layer 2: macOS Accessibility (AXUIElement) Live Tree Harvester

    private func harvestAXTextBlocks(for window: MonitoredWindow) -> [SpatialTextBlock] {
        guard AXIsProcessTrusted() else { return [] }

        let appRef = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(appRef, 0.10)

        // Wake up Electron / Chromium / Catalyst accessibility trees (Signal, Grok Bot, ChatGPT, WhatsApp, Chrome)
        if !enabledManualAXPIDs.contains(window.ownerPID) {
            enabledManualAXPIDs.insert(window.ownerPID)
            AXUIElementSetAttributeValue(appRef, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appRef, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            return []
        }

        // Match the specific AXWindow by title or closest position
        let targetAXWindow: AXUIElement = {
            if !window.windowTitle.isEmpty {
                for axWin in axWindows {
                    var titleVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleVal) == .success,
                       let t = titleVal as? String,
                       (t == window.windowTitle || t.localizedCaseInsensitiveContains(window.windowTitle)) {
                        return axWin
                    }
                }
            }
            let idx = min(window.windowIndexInApp, axWindows.count - 1)
            return axWindows[max(0, idx)]
        }()

        var collected: [SpatialTextBlock] = []
        var visitedNodes = 0
        let maxNodes = 360

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 13 && visitedNodes < maxNodes else { return }
            visitedNodes += 1

            var roleRef: CFTypeRef?
            let role = (AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success)
                ? ((roleRef as? String) ?? "")
                : ""

            // Extract text from StaticText, TextArea, Heading, Cell, Row, or Group description
            if role == kAXStaticTextRole as String ||
               role == kAXTextAreaRole as String ||
               role == kAXTextFieldRole as String ||
               role == "AXHeading" ||
               role == kAXCellRole as String ||
               role == kAXRowRole as String {

                var textCandidate: String?
                var valRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valRef) == .success,
                   let s = valRef as? String, !s.isEmpty {
                    textCandidate = s
                } else {
                    var titleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let s = titleRef as? String, !s.isEmpty {
                        textCandidate = s
                    } else {
                        var descRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
                           let s = descRef as? String, !s.isEmpty {
                            textCandidate = s
                        }
                    }
                }

                if let raw = textCandidate {
                    let cleaned = sanitizeExtractedText(raw)
                    if isMeaningfulContentLine(cleaned) {
                        let frame = axFrame(of: element) ?? window.bounds
                        collected.append(SpatialTextBlock(text: cleaned, frame: frame, role: role))
                    }
                }
            }

            // Traverse visible children first, fallback to children
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &childrenRef) == .success,
               let visChildren = childrenRef as? [AXUIElement], !visChildren.isEmpty {
                for child in visChildren.prefix(35) {
                    walk(child, depth: depth + 1)
                    if visitedNodes >= maxNodes { break }
                }
            } else if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                      let children = childrenRef as? [AXUIElement] {
                for child in children.prefix(35) {
                    walk(child, depth: depth + 1)
                    if visitedNodes >= maxNodes { break }
                }
            }
        }

        walk(targetAXWindow, depth: 0)
        return deduplicateAndFilterSpatialBlocks(collected, windowBounds: window.bounds)
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pVal = posRef,
              let sVal = sizeRef else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(pVal as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sVal as! AXValue, .cgSize, &sz)
        guard sz.width > 4, sz.height > 4 else { return nil }
        return CGRect(origin: pt, size: sz)
    }

    // MARK: - Layer 3: Fast Apple Vision OCR on Live Window Snapshot (For Canvas / Electron / Non-AX Windows)

    private func extractVisionOCRBlocks(from image: NSImage, windowBounds: CGRect) -> [SpatialTextBlock] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 80,
              cgImage.height > 60 else {
            return []
        }

        var blocks: [SpatialTextBlock] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let topCandidate = obs.topCandidates(1).first else { continue }
                let cleaned = self.sanitizeExtractedText(topCandidate.string)
                guard self.isMeaningfulContentLine(cleaned) else { continue }

                // Convert Vision normalized bottom-left coordinates (0..1) to top-down window coordinates
                let bbox = obs.boundingBox
                let x = windowBounds.minX + bbox.minX * windowBounds.width
                let y = windowBounds.minY + (1.0 - bbox.maxY) * windowBounds.height
                let w = bbox.width * windowBounds.width
                let h = bbox.height * windowBounds.height

                blocks.append(
                    SpatialTextBlock(
                        text: cleaned,
                        frame: CGRect(x: x, y: y, width: w, height: h),
                        role: "OCR"
                    )
                )
            }
        }
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return deduplicateAndFilterSpatialBlocks(blocks, windowBounds: windowBounds)
    }

    // MARK: - Spatial Filtering, Sidebar Separation & Message Formatting

    private func sanitizeExtractedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: " ")
           .replacingOccurrences(of: "\n", with: " ")
           .replacingOccurrences(of: "  ", with: " ")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isMeaningfulContentLine(_ text: String) -> Bool {
        guard text.count >= 3 else { return false }
        let lower = text.lowercased()
        if ignoredChromeLabels.contains(lower) { return false }

        // Ignore bare timestamps like "10:42 AM", "19:14", or bare numbers/percentages
        let timestampPattern = #"^\d{1,2}:\d{2}(\s?[APap][Mm])?$"#
        if text.range(of: timestampPattern, options: .regularExpression) != nil {
            return false
        }

        // Require at least 2 letters so punctuation/icon glyphs are ignored
        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount >= 2
    }

    private func deduplicateAndFilterSpatialBlocks(_ blocks: [SpatialTextBlock], windowBounds: CGRect) -> [SpatialTextBlock] {
        guard !blocks.isEmpty else { return [] }

        // Ignore top 36px window titlebar chrome
        let minY = windowBounds.minY + 34
        let validYBlocks = blocks.filter { $0.frame.minY >= minY }

        // If window has a left sidebar (width > 540) and there are enough blocks in the right 74% main pane,
        // prioritize the main conversation/thread pane over the left chat-list sidebar!
        let mainPaneSplitX = windowBounds.minX + windowBounds.width * 0.25
        let mainPaneBlocks = validYBlocks.filter { $0.frame.minX >= mainPaneSplitX }
        let chosenPool = (windowBounds.width > 540 && mainPaneBlocks.count >= 2) ? mainPaneBlocks : validYBlocks

        // Sort top-to-bottom by Y coordinate (merging adjacent fragments on the same horizontal row)
        let sorted = chosenPool.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) < 10 {
                return a.frame.minX < b.frame.minX
            }
            return a.frame.minY < b.frame.minY
        }

        var merged: [SpatialTextBlock] = []
        var seenNorm: Set<String> = []

        for block in sorted {
            let norm = block.text.lowercased()
            if seenNorm.contains(norm) { continue }
            seenNorm.insert(norm)

            // If on the same visual line (delta Y < 9px) as previous block and short, merge them
            if let last = merged.last,
               abs(block.frame.minY - last.frame.minY) < 9,
               last.text.count < 90 {
                let combinedText = "\(last.text) · \(block.text)"
                let unionFrame = last.frame.union(block.frame)
                merged[merged.count - 1] = SpatialTextBlock(text: combinedText, frame: unionFrame, role: last.role)
            } else {
                merged.append(block)
            }
        }

        return merged
    }

    private func formatBlocksIntoDigest(
        blocks: [SpatialTextBlock],
        window: MonitoredWindow,
        style: DigestPresentationStyle
    ) -> WindowLiveDigest {
        let fallbackContext = window.displayTitle
        let mainPaneMidX = window.bounds.minX + window.bounds.width * 0.60

        // Take the bottom-most (most recent) 6 lines for messaging & AI threads, or top-most 6 for browsers/finder
        let selectedBlocks: [SpatialTextBlock] = {
            switch style {
            case .messagingChat, .aiAgentThread:
                return Array(blocks.suffix(6))
            case .browserDocument, .mediaNowPlaying, .systemInspector:
                return Array(blocks.prefix(6))
            }
        }()

        if selectedBlocks.isEmpty {
            // Provide informative fallback from window title & state if window is minimized or empty
            let fallbackLine = DigestFeedLine(
                id: "\(window.id)-title",
                speakerOrTag: style == .aiAgentThread ? "THREAD" : "WINDOW",
                text: window.windowTitle.isEmpty ? "\(window.appName) is open and active" : window.windowTitle,
                isIncomingOrAgent: true,
                isHighlighted: true
            )
            return WindowLiveDigest(
                style: style,
                contextTitle: fallbackContext,
                statusBadge: style.badgeLabel,
                lines: [fallbackLine]
            )
        }

        var lines: [DigestFeedLine] = []
        for (idx, blk) in selectedBlocks.enumerated() {
            let isLast = (idx == selectedBlocks.count - 1)
            let isRightSide = blk.frame.midX > mainPaneMidX

            let speakerTag: String? = {
                switch style {
                case .messagingChat:
                    return isRightSide ? "YOU" : "MSG"
                case .aiAgentThread:
                    if blk.text.count < 70 && idx < selectedBlocks.count - 1 && isRightSide {
                        return "YOU"
                    }
                    let agentLabel = window.platform?.rawValue.uppercased() ?? window.appName.uppercased()
                    return isLast ? agentLabel : "THREAD"
                case .browserDocument:
                    return idx == 0 ? "HEADLINE" : "PAGE"
                case .mediaNowPlaying:
                    return idx == 0 ? "TRACK" : "AUDIO"
                case .systemInspector:
                    return "ITEM"
                }
            }()

            let clippedText = blk.text.count > 165 ? String(blk.text.prefix(162)) + "…" : blk.text
            lines.append(
                DigestFeedLine(
                    id: "\(window.id)-\(idx)-\(clippedText.prefix(16).hashValue)",
                    speakerOrTag: speakerTag,
                    text: clippedText,
                    isIncomingOrAgent: !isRightSide,
                    isHighlighted: isLast
                )
            )
        }

        let badge: String = {
            switch style {
            case .messagingChat:
                return "\(lines.count) LIVE MSGS"
            case .aiAgentThread:
                return "LIVE THREAD (\(lines.count))"
            case .browserDocument:
                return "LIVE DOM (\(lines.count))"
            case .mediaNowPlaying:
                return "NOW PLAYING"
            case .systemInspector:
                return "\(lines.count) ITEMS"
            }
        }()

        return WindowLiveDigest(
            style: style,
            contextTitle: fallbackContext,
            statusBadge: badge,
            lines: lines
        )
    }
}
