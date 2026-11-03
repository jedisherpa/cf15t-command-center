import Cocoa
import ApplicationServices
import Vision

final class AppContentFeedExtractor {
    static let shared = AppContentFeedExtractor()

    private var enabledManualAXPIDs: Set<pid_t> = []
    private var cachedDigests: [CGWindowID: (timestamp: TimeInterval, digest: WindowLiveDigest)] = [:]
    private let cacheTTL: TimeInterval = 2.0

    // Noise UI labels to ignore when extracting real conversation / thread content
    private let ignoredChromeLabels: Set<String> = [
        "close", "minimize", "zoom", "full screen", "back", "forward", "reload",
        "search", "send", "attach", "emoji", "voice", "mute", "unmute", "settings",
        "new chat", "today", "yesterday", "pinned", "archived", "all", "unread",
        "groups", "calls", "chats", "status", "channels", "communities", "type a message",
        "message", "ask anything", "reply", "copy", "regenerate", "share", "edit",
        "cancel", "ok", "done", "file", "view", "window", "help", "history", "bookmarks",
        "temporary chat", "chatgpt", "grok bot", "signal", "whatsapp", "note to self"
    ]

    private init() {}

    // MARK: - 1. Smart Active-Conversation Crop (Zooms into the Active Thread / Last Messages)

    func cropActiveConversationImage(from fullImage: NSImage?, for window: MonitoredWindow) -> NSImage? {
        guard let fullImage = fullImage,
              let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 120, h > 90 else { return fullImage }

        let style = classifyStyle(for: window)
        let appLower = window.appName.lowercased()

        // Determine the active region (in top-left pixel coordinates of cgImage)
        var cropX: CGFloat = 0
        var cropY: CGFloat = h * 0.07
        var cropW: CGFloat = w
        var cropH: CGFloat = h * 0.88

        switch style {
        case .messagingChat:
            // Signal, WhatsApp, Messages: Left ~28% is the contact list sidebar; bottom-right 72% is the active chat!
            if w > 520 {
                cropX = w * 0.27
                cropW = w * 0.72
            }
            cropY = h * 0.16
            cropH = h * 0.78

        case .aiAgentThread:
            // ChatGPT, Claude, Grok Bot: Skip left history sidebar if wide, focus on active response area
            if w > 760 && (appLower.contains("chatgpt") || appLower.contains("claude")) {
                cropX = w * 0.22
                cropW = w * 0.76
            } else {
                cropX = w * 0.03
                cropW = w * 0.94
            }
            cropY = h * 0.14
            cropH = h * 0.80

        case .browserDocument:
            // Skip browser tab bar & address bar at top 11%
            cropX = w * 0.02
            cropW = w * 0.96
            cropY = h * 0.11
            cropH = h * 0.85

        case .mediaNowPlaying, .systemInspector:
            if w > 580 {
                cropX = w * 0.20
                cropW = w * 0.78
            }
            cropY = h * 0.08
            cropH = h * 0.88
        }

        let safeRect = CGRect(
            x: max(0, min(w - 40, floor(cropX))),
            y: max(0, min(h - 40, floor(cropY))),
            width: max(40, min(w - floor(cropX), floor(cropW))),
            height: max(40, min(h - floor(cropY), floor(cropH)))
        )

        guard let croppedCG = cgImage.cropping(to: safeRect) else {
            return fullImage
        }
        return NSImage(cgImage: croppedCG, size: NSSize(width: croppedCG.width, height: croppedCG.height))
    }

    // MARK: - 2. Public Digest Extraction Entry Point

    func extractLiveDigest(for window: MonitoredWindow, forceRefresh: Bool = false) -> WindowLiveDigest {
        let now = Date().timeIntervalSinceReferenceDate
        if !forceRefresh,
           let cached = cachedDigests[window.id],
           (now - cached.timestamp) < cacheTTL,
           !cached.digest.lines.isEmpty {
            return cached.digest
        }

        let style = classifyStyle(for: window)

        // 1. Direct Live Transcript Reader for Antigravity
        if window.platform == .antigravity ||
           window.appName.localizedCaseInsensitiveContains("Antigravity") ||
           window.windowTitle.localizedCaseInsensitiveContains("Antigravity") {
            if let agyDigest = buildAntigravityLiveDigest(window: window) {
                cachedDigests[window.id] = (now, agyDigest)
                return agyDigest
            }
        }

        // 2. Harvest live text blocks from macOS Accessibility tree (AXUIElement)
        let axBlocks = harvestAXTextBlocks(for: window).filter { blk in
            let lower = blk.text.lowercased()
            return lower != window.appName.lowercased() && lower != window.windowTitle.lowercased()
        }

        // 3. Always run Apple Vision OCR on the active cropped conversation image if AX returned < 3 real lines
        var finalBlocks = axBlocks
        if finalBlocks.count < 3 {
            let sourceImage = window.focusedContentImage ?? cropActiveConversationImage(from: window.previewImage, for: window) ?? window.previewImage
            if let img = sourceImage {
                let ocrBlocks = extractVisionOCRBlocks(from: img, windowBounds: window.bounds)
                if ocrBlocks.count >= finalBlocks.count {
                    finalBlocks = ocrBlocks
                }
            }
        }

        let digest = formatBlocksIntoDigest(
            blocks: finalBlocks,
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
                                text: "Executing: \(toolNames.joined(separator: ", "))",
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
        return deduplicateAndFilterSpatialBlocks(collected, windowBounds: window.bounds, alreadyCropped: false)
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

    // MARK: - Layer 3: Apple Vision OCR on Active Cropped Conversation Image

    private func extractVisionOCRBlocks(from image: NSImage, windowBounds: CGRect) -> [SpatialTextBlock] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 60,
              cgImage.height > 40 else {
            return []
        }

        var blocks: [SpatialTextBlock] = []
        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let topCandidate = obs.topCandidates(1).first else { continue }
                let cleaned = self.sanitizeExtractedText(topCandidate.string)
                guard self.isMeaningfulContentLine(cleaned) else { continue }

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
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return deduplicateAndFilterSpatialBlocks(blocks, windowBounds: windowBounds, alreadyCropped: true)
    }

    // MARK: - Spatial Filtering & Paragraph Grouping

    private func sanitizeExtractedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: " ")
           .replacingOccurrences(of: "\n", with: " ")
           .replacingOccurrences(of: "  ", with: " ")
           .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isMeaningfulContentLine(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        let lower = text.lowercased()
        if ignoredChromeLabels.contains(lower) { return false }

        let timestampPattern = #"^\d{1,2}:\d{2}(\s?[APap][Mm])?$"#
        if text.range(of: timestampPattern, options: .regularExpression) != nil {
            return false
        }

        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount >= 3
    }

    private func deduplicateAndFilterSpatialBlocks(
        _ blocks: [SpatialTextBlock],
        windowBounds: CGRect,
        alreadyCropped: Bool
    ) -> [SpatialTextBlock] {
        guard !blocks.isEmpty else { return [] }

        let chosenPool: [SpatialTextBlock]
        if alreadyCropped {
            chosenPool = blocks
        } else {
            let minY = windowBounds.minY + 34
            let validYBlocks = blocks.filter { $0.frame.minY >= minY }
            let mainPaneSplitX = windowBounds.minX + windowBounds.width * 0.25
            let mainPaneBlocks = validYBlocks.filter { $0.frame.minX >= mainPaneSplitX }
            chosenPool = (windowBounds.width > 540 && mainPaneBlocks.count >= 2) ? mainPaneBlocks : validYBlocks
        }

        let sorted = chosenPool.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) < 12 {
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

            // Group vertically consecutive lines that belong to the same message bubble or response paragraph
            if let last = merged.last,
               (block.frame.minY - last.frame.maxY) < 22,
               abs(block.frame.minX - last.frame.minX) < 65,
               last.text.count < 115 {
                let combinedText = "\(last.text) \(block.text)"
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
        let mainPaneMidX = window.bounds.minX + window.bounds.width * 0.56

        let selectedBlocks: [SpatialTextBlock] = {
            switch style {
            case .messagingChat, .aiAgentThread:
                return Array(blocks.suffix(5))
            case .browserDocument, .mediaNowPlaying, .systemInspector:
                return Array(blocks.prefix(5))
            }
        }()

        if selectedBlocks.isEmpty {
            let fallbackLine = DigestFeedLine(
                id: "\(window.id)-title",
                speakerOrTag: style == .aiAgentThread ? "THREAD" : "WINDOW",
                text: window.windowTitle.isEmpty ? "\(window.appName) — Live Window View Active" : window.windowTitle,
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

            let clippedText = blk.text.count > 175 ? String(blk.text.prefix(172)) + "…" : blk.text
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
                return "LIVE PAGE (\(lines.count))"
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
