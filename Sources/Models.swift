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
            return ["/Applications/ChatGPT.app"]
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
        case .dot: return ["chatgpt", "com.openai.codex", "com.openai.chat", "dot"]
        case .claude: return ["claude", "anthropic"]
        case .codex: return ["codex project picker", "codex"]
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

// MARK: - Simplified Live App Display Digest (Messages / AI Threads / Content)

enum DigestPresentationStyle: String, Equatable {
    case messagingChat   // Signal, WhatsApp, Messages, Slack, Discord, Telegram
    case aiAgentThread   // ChatGPT (Dot), Grok Bot, Claude, Antigravity, Codex, Ollama
    case browserDocument // Google Chrome, Safari, Arc, Brave
    case mediaNowPlaying // Music, Spotify, Podcasts
    case systemInspector // Finder, Terminal, System Settings, Generic App

    var badgeLabel: String {
        switch self {
        case .messagingChat: return "💬 LIVE MESSAGES"
        case .aiAgentThread: return "🧠 RESPONSE THREAD"
        case .browserDocument: return "🌐 ACTIVE PAGE"
        case .mediaNowPlaying: return "🎵 NOW PLAYING"
        case .systemInspector: return "📂 LIVE VIEW"
        }
    }
}

struct DigestFeedLine: Identifiable, Equatable {
    let id: String
    let speakerOrTag: String?   // e.g. "YOU", "DOT", "GROK", "MSG", "TOOL", "ANTIGRAVITY"
    let text: String
    let isIncomingOrAgent: Bool // true = left/agent/incoming, false = right/user prompt
    let isHighlighted: Bool     // newest message or active streaming response
}

struct WindowLiveDigest: Equatable {
    let style: DigestPresentationStyle
    let contextTitle: String    // Active conversation partner, thread title, or page title
    let statusBadge: String     // e.g. "4 RECENT MSGS", "LIVE THREAD", "ACTIVE"
    let lines: [DigestFeedLine]
}

enum TileContentViewMode: String, CaseIterable, Identifiable, Codable {
    case splitVisualAndFeed = "Split: Live Screen + Feed"
    case liveSmartZoom = "Live Screen (Active Crop)"
    case simplifiedReader = "Large-Text Reader Feed"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .splitVisualAndFeed: return "Split View"
        case .liveSmartZoom: return "Live Screen"
        case .simplifiedReader: return "Text Feed"
        }
    }
}

enum ProgramSelectionMode: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic (Show Open Programs)"
    case customDefaults = "Custom Defaults (Only Checked Programs)"

    var id: String { rawValue }
}

struct SelectableProgramEntry: Identifiable, Equatable {
    let id: String          // Normalized app name key (e.g. "signal", "chatgpt", "grok bot")
    let displayName: String // e.g. "Signal", "ChatGPT (Dot)", "Grok Bot", "Antigravity"
    let categoryLabel: String
    let isCurrentlyOpen: Bool
    let openWindowCount: Int
    let appIcon: NSImage?
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
    var focusedContentImage: NSImage? = nil
    var liveDigest: WindowLiveDigest? = nil

    var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    static func == (lhs: MonitoredWindow, rhs: MonitoredWindow) -> Bool {
        lhs.id == rhs.id &&
        lhs.windowTitle == rhs.windowTitle &&
        lhs.bounds == rhs.bounds &&
        lhs.liveDigest == rhs.liveDigest
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
        subtitle: "ChatGPT Agent",
        targetAppName: "ChatGPT",
        appBundlePath: "/Applications/ChatGPT.app",
        urlSchemeOrWebURL: "codex://",
        micShortcut: .spaceBar,
        isMicEnabled: false,
        accentHex: "#33DBA6"
    )
}

// MARK: - Window Tiling Layout Modes

enum TilingLayoutMode: String, CaseIterable, Identifiable {
    case centerStageBorder = "Center Stage (62%) + Border Ring"
    case goldenFibonacciSpiral = "Golden φ-Spiral (Ranked by Size)"
    case leftStagePerimeter = "Left Stage (62%) + Right Stack"
    case equalSimultaneousGrid = "Equal Matrix Grid (Uniform 1/N)"
    case dualVoiceSplit = "Dual Voice Split (Grok 50% ⇄ Dot 50%)"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .centerStageBorder: return "viewfinder.rectangular"
        case .goldenFibonacciSpiral: return "hurricane"
        case .leftStagePerimeter: return "sidebar.right"
        case .equalSimultaneousGrid: return "square.grid.2x2.fill"
        case .dualVoiceSplit: return "rectangle.split.2x1.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .centerStageBorder: return "Focus + Border"
        case .goldenFibonacciSpiral: return "Golden φ-Spiral"
        case .leftStagePerimeter: return "62/38 Split"
        case .equalSimultaneousGrid: return "Equal Grid"
        case .dualVoiceSplit: return "Grok ⇄ Dot 50/50"
        }
    }

    var geometryExplanation: String {
        switch self {
        case .centerStageBorder:
            return "Main window gets 62% (φ⁻¹) in Center Stage · All other windows form a perimeter watch-ring"
        case .goldenFibonacciSpiral:
            return "Fibonacci Golden Spiral · Windows ranked #1 → #N, each scaled by 1/φ (38% → 24% → 15% → 9%)"
        case .leftStagePerimeter:
            return "Golden Section Split · Main window on Left (62% width) · Remaining windows stacked on Right (38%)"
        case .equalSimultaneousGrid:
            return "Uniform Matrix Lattice · Every open window gets equal 1/N screen area for side-by-side comparison"
        case .dualVoiceSplit:
            return "50/50 Voice Split · Grok Bot on Left half · Dot (ChatGPT) on Right half"
        }
    }
}

enum TargetDisplayMode: String, CaseIterable, Identifiable {
    case primaryDisplay = "Main Mac Screen"
    case externalDisplay = "CF15T / External Screen"
    case windowCurrentDisplay = "Window's Current Screen"

    var id: String { rawValue }
}
