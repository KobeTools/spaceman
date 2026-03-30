//
//  AppDelegate.swift
//  Spaceman
//
//  Created by Sasindu Jayasinghe on 23/11/20.
//

import SwiftUI
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {

    @AppStorage("autoShrink") private var autoShrink = false
    @AppStorage("layoutMode") private var layoutMode = LayoutMode.medium

    private var iconCreator: IconCreator!
    private var statusBar: StatusBar!
    private var spaceObserver: SpaceObserver!
    private var currentSpaces: [Space] = []

    // Auto-shrink state
    private var effectiveLayoutMode: LayoutMode?
    private var lastSpaces: [Space] = []
    private var occlusionObserver: NSObjectProtocol?
    private var shrinkDebounceWorkItem: DispatchWorkItem?
    private var safetyTimer: Timer?

    static var activeSpaceIDs: Set<String> = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Legacy settings migration - can be removed in future versions
        Self.performLegacyMigrations()

        iconCreator = IconCreator()

        statusBar = StatusBar()
        statusBar.iconCreator = iconCreator

        spaceObserver = SpaceObserver()
        spaceObserver.delegate = self
        spaceObserver.updateSpaceInformation()

        NSApp.activate(ignoringOtherApps: true)
        KeyboardShortcuts.onKeyUp(for: .refresh) { [] in
            self.spaceObserver.updateSpaceInformation()
        }
        KeyboardShortcuts.onKeyUp(for: .preferences) { [] in
            self.statusBar.showPreferencesWindow(self)
        }

        // Listen for AppleScript "open preferences" notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPreferencesFromScript),
            name: NSNotification.Name("OpenPreferences"),
            object: nil)

        // Auto-shrink: set up occlusion observer after a short delay
        // (the status bar window may not exist yet at launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupOcclusionObserver()
            self.shrinkIfEvicted()
            self.safetyTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.shrinkIfEvicted()
            }
        }

        // Reset auto-shrink overrides when settings change
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ButtonPressed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.effectiveLayoutMode != nil {
                self.effectiveLayoutMode = nil
                self.renderIcon(for: self.lastSpaces)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    // MARK: - Public Methods for Scripts/Shortcuts
    public func showPreferencesWindow() {
        statusBar.showPreferencesWindow(self)
    }

    @objc private func openPreferencesFromScript() {
        statusBar.showPreferencesWindow(self)
    }

    // MARK: - AppleScript Properties

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        return key == "currentSpaceNumber" || key == "currentSpaceName"
    }

    @objc var currentSpaceNumber: Int {
        return currentSpaceOnFrontmostDisplay()?.spaceNumber ?? 0
    }

    @objc var currentSpaceName: String {
        return currentSpaceOnFrontmostDisplay()?.spaceName ?? ""
    }

    private func currentSpaceOnFrontmostDisplay() -> Space? {
        let activeSpaces = currentSpaces.filter { $0.isCurrentSpace }
        guard !activeSpaces.isEmpty else { return nil }
        if activeSpaces.count == 1 { return activeSpaces.first }

        if let mainScreen = NSScreen.main,
           let screenNumber = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let mainDisplayID = CGDirectDisplayID(screenNumber.uint32Value)
            for space in activeSpaces {
                let uuid = CFUUIDCreateFromString(kCFAllocatorDefault, space.displayID as CFString)
                let did = CGDisplayGetDisplayIDFromUUID(uuid)
                if did == mainDisplayID {
                    return space
                }
            }
        }

        return activeSpaces.first
    }

    // MARK: - Auto-shrink

    private func renderIcon(for spaces: [Space]) {
        let buttonAppearance = statusBar.getButtonAppearance()
        let icon = iconCreator.getIcon(for: spaces, appearance: buttonAppearance,
                                        layoutModeOverride: effectiveLayoutMode)
        statusBar.updateStatusBar(withIcon: icon, withSpaces: spaces)

        if occlusionObserver == nil {
            setupOcclusionObserver()
        }
    }

    private func setupOcclusionObserver() {
        guard occlusionObserver == nil,
              let window = statusBar.statusBarWindow() else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.shrinkIfEvicted()
        }
    }

    private func shrinkIfEvicted() {
        guard autoShrink, !statusBar.isIconVisible() else { return }

        shrinkDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performShrink()
        }
        shrinkDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func performShrink() {
        guard autoShrink, !statusBar.isIconVisible() else { return }

        let currentLayout = effectiveLayoutMode ?? layoutMode

        if currentLayout == .dualRows {
            effectiveLayoutMode = .narrow
        } else if let smaller = currentLayout.smaller {
            effectiveLayoutMode = smaller
        } else {
            return // already at smallest
        }

        renderIcon(for: lastSpaces)
    }

    // MARK: - Legacy Settings Migration
    /// Removes the keys that `performLegacyMigrations()` migrates *to*.
    /// Call this before restoring a backup and re-running migrations, so the
    /// migration guards (`if object(forKey:) == nil`) don't skip over old-format
    /// keys present in the backup. Must be kept in sync with `performLegacyMigrations()`.
    static func resetMigratedKeys() {
        let keys = [
            "visibleSpacesMode", "restartNumberingByDisplay", "horizontalDirection",
            "useVariableWidth", "decorationActive", "decorationInactive"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func performLegacyMigrations() {
        // Remove obsolete UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "spaceNameCache")

        // Migrate legacy hideInactiveSpaces to visibleSpacesMode
        if UserDefaults.standard.object(forKey: "visibleSpacesMode") == nil {
            let hideInactiveSpaces = UserDefaults.standard.bool(forKey: "hideInactiveSpaces")
            let newValue: Int = hideInactiveSpaces
                ? VisibleSpacesMode.currentOnly.rawValue
                : VisibleSpacesMode.all.rawValue
            UserDefaults.standard.set(newValue, forKey: "visibleSpacesMode")
        }
        UserDefaults.standard.removeObject(forKey: "hideInactiveSpaces")

        // Migrate restartNumberingByDesktop to restartNumberingByDisplay
        if UserDefaults.standard.object(forKey: "restartNumberingByDisplay") == nil {
            let oldValue = UserDefaults.standard.bool(forKey: "restartNumberingByDesktop")
            UserDefaults.standard.set(oldValue, forKey: "restartNumberingByDisplay")
            UserDefaults.standard.removeObject(forKey: "restartNumberingByDesktop")
        }

        // Migrate reverseDisplayOrder to horizontalDirection
        if UserDefaults.standard.object(forKey: "horizontalDirection") == nil {
            let oldReverseDisplayOrder = UserDefaults.standard.bool(forKey: "reverseDisplayOrder")
            let newValue: Int = oldReverseDisplayOrder
                ? HorizontalDirection.reverseOrder.rawValue
                : HorizontalDirection.defaultOrder.rawValue
            UserDefaults.standard.set(newValue, forKey: "horizontalDirection")
            UserDefaults.standard.removeObject(forKey: "reverseDisplayOrder")
        }

        // Migrate useMinIconWidth (inverted bool) to useVariableWidth
        if UserDefaults.standard.object(forKey: "useVariableWidth") == nil,
           let oldValue = UserDefaults.standard.object(forKey: "useMinIconWidth") as? Bool {
            UserDefaults.standard.set(!oldValue, forKey: "useVariableWidth")
            UserDefaults.standard.removeObject(forKey: "useMinIconWidth")
        }

        // Migrate displayStyle + inactiveStyle → decoration
        if UserDefaults.standard.object(forKey: "decorationActive") == nil {
            let oldIconText = UserDefaults.standard.integer(forKey: "displayStyle")
            let oldInactiveStyle = UserDefaults.standard.integer(forKey: "inactiveStyle")

            if oldIconText == 1 {
                // Old "bare numbers" (raw value 1) → bare text decoration + numbers display style
                UserDefaults.standard.set(IconStyle.noDecoration.rawValue, forKey: "decorationActive")
                UserDefaults.standard.set(IconStyle.noDecoration.rawValue, forKey: "decorationInactive")
                UserDefaults.standard.set(IconText.numbers.rawValue, forKey: "displayStyle")
            } else {
                UserDefaults.standard.set(IconStyle.filledRounded.rawValue, forKey: "decorationActive")
                if oldInactiveStyle == 0 { // bordered
                    UserDefaults.standard.set(IconStyle.borderedRounded.rawValue, forKey: "decorationInactive")
                } else { // dimmed (1) or default
                    UserDefaults.standard.set(IconStyle.filledRounded.rawValue, forKey: "decorationInactive")
                }
            }
            UserDefaults.standard.removeObject(forKey: "inactiveStyle")
        }
    }
}

extension AppDelegate: SpaceObserverDelegate {
    func didUpdateSpaces(spaces: [Space]) {
        currentSpaces = spaces
        lastSpaces = spaces

        // Reset auto-shrink override on each space update
        effectiveLayoutMode = nil
        renderIcon(for: spaces)

        AppDelegate.activeSpaceIDs = Set(spaces.map { $0.spaceID })
        NotificationCenter.default.post(name: NSNotification.Name("ActiveSpacesChanged"), object: nil)
    }
}

@main
struct SpacemanApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Note:
    // - This is SwiftUI's SceneBuilder (var body: some Scene).
    // - Some toolchain combinations do not support runtime control flow (e.g., if/#available)
    //   inside the SceneBuilder closure, which may trigger:
    //   "closure containing control flow statement cannot be used with result builder 'SceneBuilder'".
    // - To maximize compatibility, return a single expression here and move availability checks
    //   into a regular function.
    var body: some Scene {
        makeSettingsScene()
    }

    // Note:
    // - Perform the #available(macOS 15) check in a regular function rather than inside
    //   the SceneBuilder closure to avoid result‑builder control‑flow limitations.
    // - Apply .defaultLaunchBehavior(.suppressed) only on macOS 15+.
    private func makeSettingsScene() -> some Scene {
        if #available(macOS 15.0, *) {
            return Settings {
                SettingsView()
            }
            .defaultLaunchBehavior(.suppressed)
        } else {
            return Settings {
                SettingsView()
            }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        PreferencesView(parentWindow: nil)
    }
}
