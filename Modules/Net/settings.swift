//
//  settings.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 06/07/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import SystemConfiguration

var textWidgetHelp = """
<h2>Description</h2>
You can use a combination of any of the variables. There is only one limitation: there must be a space between each variable.
<h3>Examples:</h3>
<ul>
<li>$addr.private - $status</li>
<li>$interface.displayName - $download / $upload</li>
</ul>
<h2>Available variables</h2>
<ul>
<li><b>$addr.private</b>: <small>Private/local IP address.</small></li>
<li><b>$addr.privateV4</b>: <small>Private/local IPv4 address.</small></li>
<li><b>$addr.privateV6</b>: <small>Private/local IPv6 address.</small></li>
<li><b>$interface.displayName</b>: <small>Network interface name.</small></li>
<li><b>$interface.BSDName</b>: <small>BSD name of the network interface.</small></li>
<li><b>$interface.address</b>: <small>MAC address of the network interface.</small></li>
<li><b>$interface.transmitRate</b>: <small>Negotiated link rate of the interface in Mbps.</small></li>
<li><b>$status</b>: <small>Status of the network connection. "UP" if active, "DOWN" if inactive.</small></li>
<li><b>$upload.total</b>: <small>Total amount of data uploaded over the connection.</small></li>
<li><b>$upload</b>: <small>Current upload bandwidth used.</small></li>
<li><b>$download.total</b>: <small>Total amount of data downloaded over the connection.</small></li>
<li><b>$download</b>: <small>Current download bandwidth used.</small></li>
<li><b>$type</b>: <small>Type of network connection (e.g., Ethernet, Wi-Fi, Bluetooth).</small></li>
</ul>
"""

internal class Settings: NSStackView, Settings_v, NSTextFieldDelegate {
    private var usageReset: String = AppUpdateInterval.never.rawValue
    private var VPNModeState: Bool = false
    private var widgetActivationThresholdState: Bool = false
    private var widgetActivationThreshold: Int = 0
    private var widgetActivationThresholdSize: SizeUnit = .MB
    private var baseValue: String = "byte"
    private var speedUnitValue: String = NetworkSpeedUnitAuto
    private var textValue: String = "$addr.private - $status"

    public var callback: (() -> Void) = {}
    public var usageResetCallback: (() -> Void) = {}

    private let title: String
    private var widgetThresholdSection: PreferencesSection? = nil
    private let textWidgetHelpPanel: HelpHUD = HelpHUD(textWidgetHelp)

    private var list: [Network_interface] = []

    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.usageReset = Store.shared.string(key: "\(self.title)_usageReset", defaultValue: self.usageReset)
        self.VPNModeState = Store.shared.bool(key: "\(self.title)_VPNMode", defaultValue: self.VPNModeState)
        self.widgetActivationThresholdState = Store.shared.bool(key: "\(self.title)_widgetActivationThresholdState", defaultValue: self.widgetActivationThresholdState)
        self.widgetActivationThreshold = Store.shared.int(key: "\(self.title)_widgetActivationThreshold", defaultValue: self.widgetActivationThreshold)
        self.widgetActivationThresholdSize = SizeUnit.fromString(Store.shared.string(key: "\(self.title)_widgetActivationThresholdSize", defaultValue: self.widgetActivationThresholdSize.key))
        self.baseValue = Store.shared.string(key: "\(self.title)_base", defaultValue: self.baseValue)
        self.speedUnitValue = networkSpeedUnit(from: Store.shared.string(key: "\(self.title)_speedUnit", defaultValue: self.speedUnitValue)).key
        self.textValue = Store.shared.string(key: "\(self.title)_textWidgetValue", defaultValue: self.textValue)

        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin

        for interface in SCNetworkInterfaceCopyAll() as NSArray {
            if  let bsdName = SCNetworkInterfaceGetBSDName(interface as! SCNetworkInterface),
                let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface as! SCNetworkInterface) {
                self.list.append(Network_interface(displayName: displayName as String, BSDName: bsdName as String))
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        self.subviews.forEach{ $0.removeFromSuperview() }

        let interfaces = selectView(
            action: #selector(self.handleSelection),
            items: [],
            selected: ""
        )
        let selectedInterface = Store.shared.string(key: "\(self.title)_interface", defaultValue: "")
        let menu = NSMenu()
        let autodetection = NSMenuItem(title: localizedString("Autodetection"), action: nil, keyEquivalent: "")
        autodetection.identifier = NSUserInterfaceItemIdentifier(rawValue: "autodetection")
        autodetection.tag = 128
        menu.addItem(autodetection)
        menu.addItem(NSMenuItem.separator())
        self.list.forEach { (interface: Network_interface) in
            let interfaceMenu = NSMenuItem(title: "\(interface.displayName) (\(interface.BSDName))", action: nil, keyEquivalent: "")
            interfaceMenu.identifier = NSUserInterfaceItemIdentifier(rawValue: interface.BSDName)
            menu.addItem(interfaceMenu)
            if selectedInterface != "" && selectedInterface == interface.BSDName {
                interfaceMenu.state = .on
            }
        }
        interfaces.menu = menu
        interfaces.sizeToFit()
        if selectedInterface == "" {
            interfaces.selectItem(withTag: 128)
        }

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Network interface"), component: interfaces),
            PreferencesRow(localizedString("Base"), component: selectView(
                action: #selector(self.toggleBase),
                items: SpeedBase,
                selected: self.baseValue
            )),
            PreferencesRow(localizedString("Units"), component: selectView(
                action: #selector(self.toggleSpeedUnit),
                items: NetworkSpeedUnits,
                selected: self.speedUnitValue
            )),
            PreferencesRow(localizedString("Reset data usage"), component: selectView(
                action: #selector(self.toggleUsageReset),
                items: AppUpdateIntervals.filter({ $0.key != "Silent" }),
                selected: self.usageReset
            )),
            PreferencesRow(localizedString("VPN mode"), component: switchView(
                action: #selector(self.toggleVPNMode),
                state: self.VPNModeState
            ))
        ]))

        self.widgetThresholdSection = PreferencesSection([
            PreferencesRow(localizedString("Widget activation threshold"), component: PreferencesSwitch(
                action: self.toggleWidgetActivationThreshold, state: self.widgetActivationThresholdState, with: StepperInput(
                    self.widgetActivationThreshold, range: NSRange(location: 1, length: 1023),
                    unit: self.widgetActivationThresholdSize.key, units: SizeUnit.allCases,
                    callback: self.changeWidgetActivationThreshold, unitCallback: self.toggleWidgetActivationThresholdSize
                )
            ))
        ])
        self.addArrangedSubview(self.widgetThresholdSection!)
        self.widgetThresholdSection?.setRowVisibility(1, newState: self.widgetActivationThresholdState)

        if widgets.contains(where: { $0 == .text }) {
            let textField = self.inputField(id: "text", value: self.textValue, placeholder: localizedString("This will be visible in the text widget"))
            self.addArrangedSubview(PreferencesSection([
                PreferencesRow(localizedString("Text widget value"), component: textField) { [weak self] in
                    self?.textWidgetHelpPanel.show()
                }
            ]))
        }
    }

    private func inputField(id: String, value: String, placeholder: String) -> NSTextField {
        let field: NSTextField = NSTextField()
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.widthAnchor.constraint(equalToConstant: 250).isActive = true
        field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        field.textColor = .textColor
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.focusRingType = .none
        field.stringValue = value
        field.delegate = self
        field.placeholderString = placeholder
        return field
    }

    @objc private func handleSelection(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.identifier?.rawValue else { return }

        if id == "autodetection" {
            Store.shared.remove("\(self.title)_interface")
        } else {
            Store.shared.set(key: "\(self.title)_interface", value: id)
        }

        self.callback()
    }
    @objc private func toggleUsageReset(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.usageReset = key
        Store.shared.set(key: "\(self.title)_usageReset", value: key)
        Store.shared.remove("\(self.title)_usageReset_next")
        self.usageResetCallback()
    }
    @objc func toggleVPNMode(_ sender: NSControl) {
        self.VPNModeState = controlState(sender)
        Store.shared.set(key: "\(self.title)_VPNMode", value: self.VPNModeState)
    }
    @objc func toggleWidgetActivationThreshold(_ sender: NSControl) {
        self.widgetActivationThresholdState = controlState(sender)
        Store.shared.set(key: "\(self.title)_widgetActivationThresholdState", value: self.widgetActivationThresholdState)
        self.widgetThresholdSection?.setRowVisibility(1, newState: self.widgetActivationThresholdState)
    }
    @objc private func changeWidgetActivationThreshold(_ newValue: Int) {
        self.widgetActivationThreshold = newValue
        Store.shared.set(key: "\(self.title)_widgetActivationThreshold", value: newValue)
    }
    private func toggleWidgetActivationThresholdSize(_ newValue: KeyValue_p) {
        guard let newUnit = newValue as? SizeUnit else { return }
        self.widgetActivationThresholdSize = newUnit
        Store.shared.set(key: "\(self.title)_widgetActivationThresholdSize", value: self.widgetActivationThresholdSize.key)
        self.display()
    }

    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? NSTextField, field.identifier == NSUserInterfaceItemIdentifier("text") {
            self.textValue = field.stringValue
            Store.shared.set(key: "\(self.title)_textWidgetValue", value: self.textValue)
        }
    }

    @objc private func toggleBase(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.baseValue = key
        Store.shared.set(key: "\(self.title)_base", value: self.baseValue)
    }
    @objc private func toggleSpeedUnit(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.speedUnitValue = networkSpeedUnit(from: key).key
        Store.shared.set(key: "\(self.title)_speedUnit", value: self.speedUnitValue)
    }
}
