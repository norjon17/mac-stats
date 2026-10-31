//
//  AppDelegate.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 28.05.2019.
//  Copyright © 2019 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

import Kit
import UserNotifications

import CPU
import RAM
import Sensors
import Net

var modules: [Module] = [
    CPU(),
    RAM(),
    Sensors(),
    Network()
]

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    internal var settingsWindow: SettingsWindow?

    internal var menuBarItem: NSStatusItem? = nil
    internal var combinedView: CombinedView = CombinedView()
    internal var modulesMounted: Bool = false

    internal var clickInNotification: Bool = false

    internal var pauseState: Bool {
        Store.shared.bool(key: "pause", defaultValue: false)
    }

    private var startTS: Date?
    private var launchStart: Date?

    static func main() {
        let launchStart = Date()
        Store.migrateDefaults(from: "eu.exelban.Stats")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        NextLog.startSession("Stats \(version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.launchStart = launchStart
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let startingPoint = self.launchStart ?? Date()
        
        info("Hardware: \(SystemKit.shared.device.info.cpu?.name ?? "unknown CPU"), \(SystemKit.shared.device.model.name)")
        HealthMonitor.shared.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        self.suppressStatusBarTilingConstraintUpdates()
        self.parseArguments()
        self.parseVersion()
        self.setup {
            modules.reversed().forEach{ $0.mount() }
            self.modulesMounted = true
            self.showSettingsIfNoActiveWidgets()
        }
        self.defaultValues()
        self.icon()

        NotificationCenter.default.addObserver(self, selector: #selector(listenForAppPause), name: .pause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleSettings), name: .toggleSettings, object: nil)

        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        info("mac-stats started in \((startingPoint.timeIntervalSinceNow * -1).rounded(toPlaces: 4)) seconds")
        self.startTS = Date()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        info("mac-stats terminating, \(HealthMonitor.shared.snapshot())")
        HealthMonitor.shared.stop()
        modules.forEach{ $0.terminate() }
    }
    
    @objc private func handleWillSleep() {
        info("System will sleep, \(HealthMonitor.shared.snapshot())")
    }
    
    @objc private func handleDidWake() {
        info("System did wake")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if self.clickInNotification {
            self.clickInNotification = false
            return true
        }
        guard let startTS = self.startTS, Date().timeIntervalSince(startTS) > 2 else { return false }

        let window = self.ensureSettingsWindow()
        if flag {
            window.makeKeyAndOrderFront(self)
        } else {
            window.setIsVisible(true)
        }

        return true
    }

    @objc private func handleToggleSettings(_ notification: Notification) {
        let module = notification.userInfo?["module"] as? String
        self.ensureSettingsWindow().open(module: module)
    }

    private func showSettingsIfNoActiveWidgets() {
        if self.pauseState { return }
        let hasActive = modules.contains(where: { $0.enabled != false && $0.available != false && !$0.menuBar.widgets.filter({ $0.isActive }).isEmpty })
        if hasActive { return }
        self.ensureSettingsWindow().setIsVisible(true)
    }

    internal func ensureSettingsWindow() -> SettingsWindow {
        if let w = self.settingsWindow { return w }
        let w = SettingsWindow()
        w.onClose = { [weak self] in
            self?.settingsWindow = nil
        }
        self.settingsWindow = w
        return w
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        self.clickInNotification = true
        completionHandler()
    }
}
