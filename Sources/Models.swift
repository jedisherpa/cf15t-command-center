import Cocoa
import SwiftUI

// MARK: - AI Agent Platforms

enum AgentPlatform: String, CaseIterable, Identifiable, Codable {
    case grokBot = "Grok Bot"
    case dot = "Dot"
    case claude = "Claude"
    case codex = "Codex"
    case antigravity = "Antigravity"
    case chatGPT = "ChatGPT"
    case cubedCode = "Cubed Code"
    case bombCode = "Bomb Code"
    case ollama = "Ollama"
    case prism = "Prism / Pillar"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .grokBot: return "waveform.circle.fill"
        case .dot: return "smallcircle.filled.circle.fill"
        case .claude: return "sparkles.rectangle.stack.fill"
        case .codex: return "terminal.fill"
        case .antigravity: return "atom"
        case .chatGPT: return "bubble.left.and.bubble.right.fill"
        case .cubedCode: return "cube.transparent.fill"
        case .bombCode: return "bolt.horizontal.circle.fill"
        case .ollama: return "server.rack"
        case .prism: return "pyramid.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .grokBot: return Color(red: 1.0, green: 0.38, blue: 0.18)      // Vibrant Orange-Red
        case .dot: return Color(red: 0.20, green: 0.86, blue: 0.65)         // Mint Emerald
        case .claude: return Color(red: 0.88, green: 0.56, blue: 0.34)      // Warm Terracotta
        case .codex: return Color(red: 0.32, green: 0.65, blue: 1.0)        // Electric Blue
        case .antigravity: return Color(red: 0.68, green: 0.45, blue: 1.0)  // Violet
        case .chatGPT: return Color(red: 0.16, green: 0.78, blue: 0.58)     // OpenAI Teal
        case .cubedCode: return Color(red: 0.25, green: 0.82, blue: 0.96)   // Cyan
        case .bombCode: return Color(red: 0.98, green: 0.78, blue: 0.22)    // Amber
        case .ollama: return Color(red: 0.75, green: 0.80, blue: 0.88)      // Silver
        case .prism: return Color(red: 0.95, green: 0.42, blue: 0.72)       // Pink
        }
    }

    var appPaths: [String] {
        switch self {
        case .grokBot:
            return ["/Applications/Grok Bot.app"]
        case .dot:
            return ["/Applications/Dot.app", "/Applications/Claude.app", "/Applications/ChatGPT.app"]
        case .claude:
            return ["/Applications/Claude.app"]
        case .codex:
            return ["/Applications/Codex Project Picker.app", "/Applications/Codex.app"]
        case .antigravity:
            return ["/Applications/Antigravity.app"]
        case .chatGPT:
            return ["/Applications/ChatGPT.app"]
        case .cubedCode:
            return ["/Applications/Cubed Code GPUI.app"]
        case .bombCode:
            return ["/Applications/Bomb Code.app"]
        case .ollama:
            return ["/Applications/Ollama.app"]
        case .prism:
            return ["/Applications/Prism GT Chat Live.app", "/Applications/Prism GT.app", "/Applications/Pillar.app"]
        }
    }

    var processMatchKeywords: [String] {
        switch self {
        case .grokBot: return ["grok bot", "com.anysphere.sand", "grokbot"]
        case .dot: return ["dot.app", "new.computer", "dot "]
        case .claude: return ["claude", "anthropic"]
        case .codex: return ["codex"]
        case .antigravity: return ["antigravity", "language_server_macos"]
        case .chatGPT: return ["chatgpt", "com.openai.chat"]
        case .cubedCode: return ["cubed code"]
        case .bombCode: return ["bomb code"]
        case .ollama: return ["ollama"]
        case .prism: return ["prism", "pillar"]
        }
    }
}

// MARK: - Agent Activity State

enum AgentExecutionState: String, Codable {
    case working = "WORKING"
    case idle = "READY"
    case offline = "OFFLINE"

    var badgeColor: Color {
        switch self {
        case .working: return Color(red: 0.18, green: 0.92, blue: 0.52)
        case .idle: return Color(red: 0.35, green: 0.68, blue: 1.0)
        case .offline: return Color.white.opacity(0.28)
        }
    }
}

struct AgentStatusSnapshot: Identifiable {
    let platform: AgentPlatform
    var id: String { platform.id }
    var state: AgentExecutionState
    var cpuPercent: Double
    var memoryMB: Double
    var processCount: Int
    var activeWindowTitle: String?
    var activeSubtaskSummary: String?
    var primaryPID: pid_t?
    var appIcon: NSImage?
}

// MARK: - Running System / CLI Task

struct RunningTaskItem: Identifiable {
    let id: pid_t
    let pid: pid_t
    let commandName: String
    let fullCommand: String
    let cpuPercent: Double
    let memoryMB: Double
    let platform: AgentPlatform?
}

// MARK: - Monitored macOS Window

struct MonitoredWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerPID: pid_t
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let bounds: CGRect
    let windowIndexInApp: Int
    let platform: AgentPlatform?
    var appIcon: NSImage?
    var previewImage: NSImage?

    var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    static func == (lhs: MonitoredWindow, rhs: MonitoredWindow) -> Bool {
        lhs.id == rhs.id &&
        lhs.windowTitle == rhs.windowTitle &&
        lhs.bounds == rhs.bounds
    }
}

// MARK: - Voice Assistant Slot (Grok Bot / Dot / Configurable)

enum MicShortcutPreset: String, CaseIterable, Identifiable, Codable {
    case systemHardwareOnly = "System CoreAudio Mic Only"
    case spaceBar = "Spacebar (Push/Toggle)"
    case cmdShiftM = "⌘⇧M (Mute Shortcut)"
    case cmdM = "⌘M"
    case optionSpace = "⌥Space (Voice Bar)"
    case enterKey = "Return / Enter"

    var id: String { rawValue }

    var keyCode: CGKeyCode? {
        switch self {
        case .systemHardwareOnly: return nil
        case .spaceBar: return 49
        case .cmdShiftM, .cmdM: return 46
        case .optionSpace: return 49
        case .enterKey: return 36
        }
    }

    var modifiers: CGEventFlags {
        switch self {
        case .systemHardwareOnly, .spaceBar, .enterKey:
            return []
        case .cmdShiftM:
            return [.maskCommand, .maskShift]
        case .cmdM:
            return [.maskCommand]
        case .optionSpace:
            return [.maskAlternate]
        }
    }
}

struct VoiceAssistantConfig: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var subtitle: String
    var targetAppName: String
    var appBundlePath: String
    var urlSchemeOrWebURL: String
    var micShortcut: MicShortcutPreset
    var isMicEnabled: Bool
    var accentHex: String

    static let defaultSlotA = VoiceAssistantConfig(
        id: "slotA",
        displayName: "Grok Bot",
        subtitle: "Primary Voice & Agent",
        targetAppName: "Grok Bot",
        appBundlePath: "/Applications/Grok Bot.app",
        urlSchemeOrWebURL: "grokbot://",
        micShortcut: .spaceBar,
        isMicEnabled: false,
        accentHex: "#FF612E"
    )

    static let defaultSlotB = VoiceAssistantConfig(
        id: "slotB",
        displayName: "Dot",
        subtitle: "Secondary Voice / Assistant",
        targetAppName: "Claude",
        appBundlePath: "/Applications/Claude.app",
        urlSchemeOrWebURL: "https://new.computer",
        micShortcut: .spaceBar,
        isMicEnabled: false,
        accentHex: "#33DBA6"
    )
}

// MARK: - Window Tiling Layout Modes

enum TilingLayoutMode: String, CaseIterable, Identifiable {
    case centerStageBorder = "Center Stage + Border"
    case leftStagePerimeter = "Big Left + Right/Bottom Border"
    case equalSimultaneousGrid = "Equal Multi-Window Grid"
    case dualVoiceSplit = "50/50 Voice Split (A | B)"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .centerStageBorder: return "rectangle.center.inset.filled"
        case .leftStagePerimeter: return "sidebar.right"
        case .equalSimultaneousGrid: return "square.grid.2x2.fill"
        case .dualVoiceSplit: return "rectangle.split.2x1.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .centerStageBorder: return "Center + Border"
        case .leftStagePerimeter: return "Stage + Perimeter"
        case .equalSimultaneousGrid: return "Equal Grid"
        case .dualVoiceSplit: return "50/50 Split"
        }
    }
}

enum TargetDisplayMode: String, CaseIterable, Identifiable {
    case primaryDisplay = "Main Mac Screen"
    case externalDisplay = "CF15T / External Screen"
    case windowCurrentDisplay = "Window's Current Screen"

    var id: String { rawValue }
}
