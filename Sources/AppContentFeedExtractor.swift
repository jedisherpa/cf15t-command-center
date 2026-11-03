import Cocoa
import ApplicationServices
import Vision

final class AppContentFeedExtractor {
    static let shared = AppContentFeedExtractor()

    private var enabledManualAXPIDs: Set<pid_t> = []
    private var cachedDigests: [CGWindowID: (timestamp: TimeInterval, digest: WindowLiveDigest)] = [:]
    private let cacheTTL: TimeInterval = 1.6

    // Noise UI labels to ignore when extracting real conversation / thread content
    private let ignoredChromeLabels: Set<String> = [
        "close", "minimize", "zoom", "full screen", "back", "forward", "reload",
        "search", "send", "attach", "emoji", "voice", "mute", "unmute", "settings",
        "new chat", "today", "yesterday", "pinned", "archived", "all", "unread",
        "groups", "calls", "chats", "status", "channels", "communities", "type a message",
        "message", "ask anything", "reply", "copy", "regenerate", "share", "edit",
        "cancel", "ok", "done", "file", "view", "window", "help", "history", "bookmarks",
        "temporary chat", "chatgpt", "grok bot", "signal", "whatsapp", "note to self",
        "write a message", "send a message", "search or start new chat"
    ]

    private init() {}

    // MARK: - 1. Smart Active-Conversation Crop (Preserves the Full Main Content Pane)

    func cropActiveConversationImage(from fullImage: NSImage?, for window: MonitoredWindow) -> NSImage? {
        guard let fullImage = fullImage,
              let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        guard w > 160, h > 120 else { return fullImage }

        let style = classifyStyle(for: window)
        let appLower = window.appName.lowercased()

        var cropX: CGFloat = 0
        var cropY: CGFloat = h * 0.05
        var cropW: CGFloat = w
        var cropH: CGFloat = h * 0.92

        switch style {
        case .messagingChat:
            // Signal, WhatsApp, Messages: Left ~26% is contact list sidebar when window is wide
            if w > 640 {
                cropX = w * 0.25
                cropW = w * 0.75
            }
            cropY = h * 0.06
            cropH = h * 0.90

        case .aiAgentThread:
            // ChatGPT, Claude, Grok Bot, Antigravity: Skip left sidebar only if very wide
            if w > 880 && (appLower.contains("chatgpt") || appLower.contains("claude") || appLower.contains("signal")) {
                cropX = w * 0.20
                cropW = w * 0.80
            } else {
                cropX = w * 0.01
                cropW = w * 0.98
            }
            cropY = h * 0.05
            cropH = h * 0.92

        case .browserDocument:
            // Skip browser tab bar at top 8%
            cropX = w * 0.01
            cropW = w * 0.98
            cropY = h * 0.08
            cropH = h * 0.90

        case .mediaNowPlaying, .systemInspector:
            cropX = 0
            cropW = w
            cropY = h * 0.04
            cropH = h * 0.94
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

        // 2. Harvest live text blocks from macOS Accessibility tree (Main-Pane-First Deep Walk)
        let axBlocks = harvestAXTextBlocks(for: window).filter { blk in
            let lower = blk.text.lowercased()
            return lower != window.appName.lowercased() && lower != window.windowTitle.lowercased()
        }

        // 3. Fuse with Apple Vision OCR on the live window image whenever AX has fewer than 6 substantive lines
        var finalBlocks = axBlocks
        let substantiveAXCount = axBlocks.filter { $0.text.count >= 18 }.count
        if substantiveAXCount < 5 {
            let sourceImage = window.focusedContentImage ?? cropActiveConversationImage(from: window.previewImage, for: window) ?? window.previewImage
            if let img = sourceImage {
                let ocrBlocks = extractVisionOCRBlocks(from: img, windowBounds: window.bounds)
                if ocrBlocks.count > finalBlocks.count || substantiveAXCount < 2 {
                    finalBlocks = mergeAXAndOCRBlocks(axBlocks: axBlocks, ocrBlocks: ocrBlocks)
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

    private func mergeAXAndOCRBlocks(axBlocks: [SpatialTextBlock], ocrBlocks: [SpatialTextBlock]) -> [SpatialTextBlock] {
        if axBlocks.isEmpty { return ocrBlocks }
        if ocrBlocks.isEmpty { return axBlocks }
        // Prefer whichever source yielded richer multi-word content, supplemented by non-duplicate lines
        let primary = (ocrBlocks.reduce(0) { $0 + $1.text.count } >= axBlocks.reduce(0) { $0 + $1.text.count }) ? ocrBlocks : axBlocks
        let secondary = (primary.count == ocrBlocks.count) ? axBlocks : ocrBlocks
        var combined = primary
        var seen = Set(primary.map { $0.text.lowercased() })
        for blk in secondary {
            let key = blk.text.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                combined.append(blk)
            }
        }
        return combined.sorted { $0.frame.minY < $1.frame.minY }
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
           app.contains("cubed") || app.contains("ollama") || title.contains("chatgpt") || title.contains("claude") {
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
        let hasExplicitFrame: Bool
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
        let readBytes: UInt64 = min(fileSize, 64_000)
        if fileSize > readBytes {
            try? handle.seek(toOffset: fileSize - readBytes)
        } else {
            try? handle.seek(toOffset: 0)
        }

        guard let data = try? handle.readToEnd(),
              let rawString = String(data: data, encoding: .utf8) else { return nil }

        let jsonLines = rawString.components(separatedBy: .newlines).suffix(40)
        var feedLines: [DigestFeedLine] = []
        var latestActionSummary: String = "Active Coding & UI Session"

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
                    latestActionSummary = "Responding to: \"\(clean.prefix(75))\""
                    feedLines.append(
                        DigestFeedLine(
                            id: "agy-u-\(idx)",
                            speakerOrTag: "🗣️ YOUR GOAL",
                            text: clean,
                            isIncomingOrAgent: false,
                            isHighlighted: false
                        )
                    )
                }
            } else if stepType == "PLANNER_RESPONSE" {
                if let toolCalls = obj["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    var stepDescriptions: [String] = []
                    for tc in toolCalls {
                        let rawName = (tc["name"] as? String ?? "").replacingOccurrences(of: "default_api:", with: "")
                        if let args = tc["arguments"] as? [String: Any] {
                            if let summary = args["toolSummary"] as? String, !summary.isEmpty {
                                stepDescriptions.append(summary)
                            } else if let filePath = args["Path"] as? String {
                                let base = (filePath as NSString).lastPathComponent
                                stepDescriptions.append("\(rawName) → \(base)")
                            } else {
                                stepDescriptions.append(rawName)
                            }
                        } else {
                            stepDescriptions.append(rawName)
                        }
                    }
                    if !stepDescriptions.isEmpty {
                        let joined = stepDescriptions.joined(separator: " · ")
                        latestActionSummary = "Working: \(joined)"
                        feedLines.append(
                            DigestFeedLine(
                                id: "agy-t-\(idx)",
                                speakerOrTag: "⚙️ ACTION",
                                text: joined,
                                isIncomingOrAgent: true,
                                isHighlighted: false
                            )
                        )
                    }
                }

                let cleanResp = cleanMarkdownString(content)
                if cleanResp.count >= 6 {
                    latestActionSummary = "Completed step — Ready for your next instruction"
                    feedLines.append(
                        DigestFeedLine(
                            id: "agy-r-\(idx)",
                            speakerOrTag: "🤖 ANTIGRAVITY",
                            text: cleanResp,
                            isIncomingOrAgent: true,
                            isHighlighted: true
                        )
                    )
                }
            }
        }

        guard !feedLines.isEmpty else { return nil }
        var tail = Array(feedLines.suffix(7))
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
            contextTitle: latestActionSummary,
            statusBadge: "🟢 LIVE AI SESSION",
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
        return lines.prefix(5).joined(separator: " • ")
    }

    // MARK: - Layer 2: macOS Accessibility (AXUIElement) Deep Main-Pane Harvester

    private func harvestAXTextBlocks(for window: MonitoredWindow) -> [SpatialTextBlock] {
        guard AXIsProcessTrusted() else { return [] }

        let appRef = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(appRef, 0.12)

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
        let maxNodes = 1400

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 26 && visitedNodes < maxNodes else { return }
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
               role == kAXRowRole as String ||
               role == "AXLink" {

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
                        let explicit = axFrame(of: element)
                        let fallbackY = window.bounds.minY + 60 + CGFloat(collected.count * 26)
                        let fallbackX = window.bounds.minX + window.bounds.width * 0.45
                        let frame = explicit ?? CGRect(x: fallbackX, y: fallbackY, width: 320, height: 22)
                        collected.append(
                            SpatialTextBlock(
                                text: cleaned,
                                frame: frame,
                                hasExplicitFrame: explicit != nil,
                                role: role
                            )
                        )
                    }
                }
            }

            var childrenRef: CFTypeRef?
            let childList: [AXUIElement]? = {
                if AXUIElementCopyAttributeValue(element, kAXVisibleChildrenAttribute as CFString, &childrenRef) == .success,
                   let vis = childrenRef as? [AXUIElement], !vis.isEmpty {
                    return vis
                }
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let all = childrenRef as? [AXUIElement], !all.isEmpty {
                    return all
                }
                return nil
            }()

            if let children = childList {
                // At shallow depths (split groups / main panes), traverse in reverse order so the right-hand
                // main conversation/content pane is visited BEFORE the left-hand navigation sidebar!
                let orderedChildren = (depth <= 5 && children.count >= 2) ? Array(children.reversed()) : children
                for child in orderedChildren.prefix(60) {
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
                        hasExplicitFrame: true,
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
            let minY = windowBounds.minY + 28
            let validYBlocks = blocks.filter { !$0.hasExplicitFrame || $0.frame.minY >= minY }
            let mainPaneSplitX = windowBounds.minX + windowBounds.width * 0.24
            let mainPaneBlocks = validYBlocks.filter { !$0.hasExplicitFrame || $0.frame.midX >= mainPaneSplitX }
            chosenPool = (windowBounds.width > 560 && mainPaneBlocks.count >= 3) ? mainPaneBlocks : validYBlocks
        }

        let sorted = chosenPool.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) < 14 {
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
               last.hasExplicitFrame && block.hasExplicitFrame,
               (block.frame.minY - last.frame.maxY) < 26,
               abs(block.frame.minX - last.frame.minX) < 85,
               last.text.count < 240 {
                let combinedText = "\(last.text) \(block.text)"
                let unionFrame = last.frame.union(block.frame)
                merged[merged.count - 1] = SpatialTextBlock(
                    text: combinedText,
                    frame: unionFrame,
                    hasExplicitFrame: true,
                    role: last.role
                )
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
        let mainPaneMidX = window.bounds.minX + window.bounds.width * 0.56

        let selectedBlocks: [SpatialTextBlock] = {
            switch style {
            case .messagingChat, .aiAgentThread:
                return Array(blocks.suffix(7))
            case .browserDocument, .mediaNowPlaying, .systemInspector:
                return Array(blocks.prefix(7))
            }
        }()

        if selectedBlocks.isEmpty {
            let titleText = window.windowTitle.isEmpty
                ? "\(window.appName) is open and ready for your input."
                : window.windowTitle
            let fallbackLine = DigestFeedLine(
                id: "\(window.id)-title",
                speakerOrTag: "📍 CURRENT SCREEN",
                text: titleText,
                isIncomingOrAgent: true,
                isHighlighted: true
            )
            return WindowLiveDigest(
                style: style,
                contextTitle: titleText,
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
                    return isRightSide ? "🗣️ YOU" : "💬 MESSAGE"
                case .aiAgentThread:
                    if blk.text.count < 75 && idx < selectedBlocks.count - 1 && isRightSide {
                        return "🗣️ YOU"
                    }
                    let agentLabel = window.platform?.rawValue.uppercased() ?? window.appName.uppercased()
                    return isLast ? "🤖 \(agentLabel) (LATEST)" : "🤖 \(agentLabel)"
                case .browserDocument:
                    return idx == 0 ? "🌐 PAGE HEADING" : "📄 PAGE CONTENT"
                case .mediaNowPlaying:
                    return idx == 0 ? "🎵 NOW PLAYING" : "🎧 TRACK INFO"
                case .systemInspector:
                    return "📂 ON SCREEN"
                }
            }()

            let clippedText = blk.text.count > 310 ? String(blk.text.prefix(307)) + "…" : blk.text
            lines.append(
                DigestFeedLine(
                    id: "\(window.id)-\(idx)-\(clippedText.prefix(20).hashValue)",
                    speakerOrTag: speakerTag,
                    text: clippedText,
                    isIncomingOrAgent: !isRightSide,
                    isHighlighted: isLast
                )
            )
        }

        // Build a clear, plain-language "WHAT IS GOING ON" headline summary
        let newestSnippet = lines.last?.text ?? window.displayTitle
        let plainSummary: String = {
            if !window.windowTitle.isEmpty && window.windowTitle.lowercased() != window.appName.lowercased() {
                return window.windowTitle
            }
            return String(newestSnippet.prefix(95))
        }()

        let badge: String = {
            switch style {
            case .messagingChat:
                return "💬 \(lines.count) MESSAGES"
            case .aiAgentThread:
                return "🧠 \(lines.count) THREAD STEPS"
            case .browserDocument:
                return "🌐 LIVE WEB PAGE"
            case .mediaNowPlaying:
                return "🎵 NOW PLAYING"
            case .systemInspector:
                return "📂 \(lines.count) ITEMS ON SCREEN"
            }
        }()

        return WindowLiveDigest(
            style: style,
            contextTitle: plainSummary,
            statusBadge: badge,
            lines: lines
        )
    }
}
