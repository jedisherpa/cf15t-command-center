import Cocoa

/// Works out which connected screen is which, and which one the Command Center should live on.
///
/// Supports:
/// - the 15.6" CF15T touchscreen (1920×1080, SiS touch controller)
/// - a 12.3" wide "bar" touchscreen (about half as tall, e.g. 1920×720)
/// - either one alone, or both plugged in at once (pick which one shows the Command Center)
final class DisplayTargetManager {
    static let shared = DisplayTargetManager()
    static let autoKey = "auto"

    private let defaultsKey = "cf15t.display.preferredScreenKey"

    private init() {}

    // MARK: - Preference

    /// "auto", or a stable key ("Name|WxH") for the screen the user picked.
    var preferredScreenKey: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? Self.autoKey }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    // MARK: - Screen facts

    /// When the laptop lid is open and an external touchscreen (such as Z1-2 1280×480 or CF15T 1920×1080)
    /// is plugged in, macOS may default to hardware mirroring, shrinking the laptop screen.
    /// Automatically un-mirror so the laptop stays at full Retina resolution and the touchscreen is an independent display.
    func ensureExtendedDesktopIfLidOpen() {
        guard !KeepAwakeWorker.shared.isLaptopLidClosed() else { return }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 1 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return }

        let mirroredIDs = ids.filter { CGDisplayMirrorsDisplay($0) != kCGNullDirectDisplay }
        guard !mirroredIDs.isEmpty else { return }

        var config: CGDisplayConfigRef? = nil
        if CGBeginDisplayConfiguration(&config) == .success, let cfg = config {
            for id in mirroredIDs {
                CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
            }
            CGCompleteDisplayConfiguration(cfg, .permanently)
        }
    }

    func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = displayID(of: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// A screen at least twice as wide as it is tall (the 12.3" bar screen).
    func isWideBar(_ screen: NSScreen) -> Bool {
        let f = screen.frame
        return f.width / max(1, f.height) >= 2.0
    }

    func key(for screen: NSScreen) -> String {
        let f = screen.frame
        return "\(screen.localizedName)|\(Int(f.width))x\(Int(f.height))"
    }

    var externalScreens: [NSScreen] {
        NSScreen.screens.filter { !isBuiltIn($0) }
    }

    func friendlyName(for screen: NSScreen) -> String {
        let f = screen.frame
        let shape: String
        if isBuiltIn(screen) {
            shape = "laptop"
        } else if isWideBar(screen) {
            shape = "wide · 12.3-inch style"
        } else {
            shape = "standard · 15.6-inch style"
        }
        return "\(screen.localizedName) — \(Int(f.width))×\(Int(f.height)) (\(shape))"
    }

    // MARK: - Which screen is which

    /// The 15.6" CF15T screen. `strict` = only return a screen that really looks like the CF15T.
    func cf15tScreen(strict: Bool = false) -> NSScreen? {
        let ext = externalScreens
        if let named = ext.first(where: { $0.localizedName.localizedCaseInsensitiveContains("CF15T") }) {
            return named
        }
        if let fhd = ext.first(where: { !isWideBar($0) && Int($0.frame.width) == 1920 && Int($0.frame.height) == 1080 }) {
            return fhd
        }
        if strict { return nil }
        if let standard = ext.first(where: { !isWideBar($0) }) { return standard }
        return ext.first ?? NSScreen.screens.first
    }

    /// The 12.3" wide bar screen, if one is plugged in.
    func wideBarScreen() -> NSScreen? {
        externalScreens.first(where: { isWideBar($0) })
    }

    /// The screen the Command Center window should be on.
    func commandCenterScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let pref = preferredScreenKey
        if pref != Self.autoKey, let picked = screens.first(where: { key(for: $0) == pref }) {
            return picked
        }
        // Automatic: CF15T first, then any other external screen (e.g. the 12.3" bar), then the laptop.
        if let cf = cf15tScreen(strict: true) { return cf }
        if let ext = externalScreens.first { return ext }
        return screens.first
    }

    /// The screen that non-SiS touchscreens (e.g. the 12.3" bar's touch panel) belong to.
    func secondaryTouchScreen() -> NSScreen? {
        if let bar = wideBarScreen() { return bar }
        let cf = cf15tScreen(strict: true)
        if let other = externalScreens.first(where: { $0 != cf }) { return other }
        return commandCenterScreen()
    }

    /// Global Quartz (top-left origin) bounds of a screen, for CGEvent / cursor warping.
    func quartzBounds(of screen: NSScreen) -> CGRect {
        if let id = displayID(of: screen) {
            return CGDisplayBounds(id)
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
    }

    /// The area the Command Center fills on a screen. Launch with `--args -cf15t.debug.forceHeight 690`
    /// to preview the 12.3" wide layout on a taller screen.
    func usableFrame(for screen: NSScreen) -> NSRect {
        var vis = screen.visibleFrame
        let forced = UserDefaults.standard.double(forKey: "cf15t.debug.forceHeight")
        if forced > 200 && forced < vis.height {
            vis.origin.y = vis.maxY - forced
            vis.size.height = forced
        }
        return vis
    }

    // MARK: - Moving between screens

    /// Picks the next screen (external screens first) and remembers it as the preference.
    @discardableResult
    func cycleToNextScreen() -> NSScreen? {
        let pool = externalScreens.isEmpty ? NSScreen.screens : externalScreens
        guard !pool.isEmpty else { return nil }
        let current = commandCenterScreen()
        let idx = pool.firstIndex(where: { $0 == current }) ?? -1
        let next = pool[(idx + 1) % pool.count]
        preferredScreenKey = key(for: next)
        return next
    }
}
