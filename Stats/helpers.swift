//
//  helpers.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 13/07/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

extension AppDelegate {
    internal func parseArguments() {
        let args = CommandLine.arguments
        
        if args.contains("--reset") {
            debug("Receive --reset argument. Resetting store (UserDefaults)...")
            Store.shared.reset()
        }
        
        if let disableIndex = args.firstIndex(of: "--disable") {
            if args.indices.contains(disableIndex+1) {
                let disableModules = args[disableIndex+1].split(separator: ",")
                
                disableModules.forEach { (moduleName: Substring) in
                    if let module = modules.first(where: { $0.config.name.lowercased() == moduleName.lowercased()}) {
                        module.unmount()
                    }
                }
            }
        }
    }
    
    internal func parseVersion() {
        let key = "version"
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        
        if !Store.shared.exist(key: key) {
            debug("Previous version not detected. Current version (\(currentVersion) set")
        } else {
            let prevVersion = Store.shared.string(key: key, defaultValue: "")
            if prevVersion == currentVersion {
                return
            }
            debug("Detected previous version \(prevVersion). Current version (\(currentVersion) set")
        }
        
        Store.shared.set(key: key, value: currentVersion)
    }
    
    internal func defaultValues() {
        if Store.shared.exist(key: "dockIcon") {
            let dockIconStatus = Store.shared.bool(key: "dockIcon", defaultValue: false) ? NSApplication.ActivationPolicy.regular : NSApplication.ActivationPolicy.accessory
            NSApp.setActivationPolicy(dockIconStatus)
        }
    }
    
    internal func setup(completion: @escaping () -> Void) {
        completion()
    }
    
    @objc internal func listenForAppPause() {
        for m in modules {
            if self.pauseState && m.enabled {
                m.disable()
            } else if !self.pauseState && !m.enabled && Store.shared.bool(key: "\(m.config.name)_state", defaultValue: m.config.defaultState) {
                m.enable()
            }
        }
        self.icon()
    }
    
    internal func icon() {
        if self.pauseState {
            guard self.menuBarItem == nil else { return }
            
            self.menuBarItem = NSStatusBar.system.statusItem(withLength: AppIcon.size.width)
            DispatchQueue.main.async(execute: {
                self.menuBarItem?.autosaveName = "Stats"
            })
            self.menuBarItem?.button?.addSubview(AppIcon())
            
            self.menuBarItem?.button?.target = self
            self.menuBarItem?.button?.action = #selector(self.openSettings)
            self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        } else {
            if let item = self.menuBarItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            self.menuBarItem = nil
        }
    }
    
    @objc internal func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
    }
    
    internal func handleKeyEvent(_ event: NSEvent) {
        var keyCodes: [UInt16] = []
        if event.modifierFlags.contains(.control) { keyCodes.append(59) }
        if event.modifierFlags.contains(.shift) { keyCodes.append(60) }
        if event.modifierFlags.contains(.command) { keyCodes.append(55) }
        if event.modifierFlags.contains(.option) { keyCodes.append(58) }
        keyCodes.append(event.keyCode)
        
        guard !keyCodes.isEmpty,
              let module = modules.first(where: { $0.enabled && $0.popupKeyboardShortcut == keyCodes }),
              let widget = module.menuBar.widgets.filter({ $0.isActive }).first,
              let window = widget.item.window else { return }
        
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: [
            "module": module.name,
            "widget": widget.type,
            "origin": window.frame.origin,
            "center": window.frame.width/2
        ])
    }
    
    // Workaround for the WindowServer "Invalid window" log spam on macOS Tahoe (#3212, #2829).
    //
    // On Tahoe every layout pass on an NSStatusBarWindow schedules a tiling-constraints sync
    // (-[NSWindow(NSFullScreen) _refreshTilingConstraints:]) that calls
    // SLSPackagesSetWindowConstraints with the window number. A status bar window has no regular
    // server-side window on Tahoe (the low 32 bits of its windowNumber are zero), so WindowServer
    // rejects every call and logs "_CGXPackagesSetWindowConstraints: Invalid window" on each
    // widget update. The gate (-[NSWindow(NSFullScreen) _needsTilingConstraintUpdate]) returns
    // true whenever the app is inactive, which for a menu bar app is almost always.
    //
    // Overriding the gate on NSStatusBarWindow only (a status bar window can never be tiled)
    // stops the sync from ever being scheduled; all other windows keep the default behavior.
    internal func suppressStatusBarTilingConstraintUpdates() {
        guard #available(macOS 26.0, *) else { return }
        let selector = NSSelectorFromString("_needsTilingConstraintUpdate")
        guard let cls = NSClassFromString("NSStatusBarWindow"),
              let method = class_getInstanceMethod(cls, selector) else { return }
        let block: @convention(block) (AnyObject) -> Bool = { _ in false }
        class_addMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }
}
