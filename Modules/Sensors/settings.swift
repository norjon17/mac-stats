//
//  settings.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 23/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v {
    private var updateIntervalValue: Int = 3
    private var widgets: [widget_t] = []

    public var callback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }
    public var selectedHandler: (String) -> Void = {_ in }

    private let title: String
    private var list: [Sensor_p] = []
    private var sensorsPrefs: PreferencesSection?
    private var selectedSensor: String = defaultSelectedSensor

    public init(_ module: ModuleType) {
        self.title = module.stringValue

        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin

        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)
        self.selectedSensor = Store.shared.string(key: "\(self.title)_sensor", defaultValue: self.selectedSensor)

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: ReaderUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))

        let sensorsPrefs = PreferencesSection([
            PreferencesRow(localizedString("Sensor to show"), id: "active_sensor", component: selectView(
                action: #selector(self.handleSelection),
                items: [],
                selected: self.selectedSensor)
            )
        ])
        self.sensorsPrefs = sensorsPrefs
        self.addArrangedSubview(sensorsPrefs)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        self.widgets = widgets
        let sensors = self.list
        guard !sensors.isEmpty else {
            return
        }

        self.subviews.filter({ $0.identifier == NSUserInterfaceItemIdentifier("sensor") }).forEach { v in
            v.removeFromSuperview()
        }

        var buttonList: [KeyValue_t] = []
        SensorGroup.ordered.forEach { (group: SensorGroup) in
            let inGroup = sensors.filter { $0.group == group }
            guard !inGroup.isEmpty else { return }

            let section = PreferencesSection(title: localizedString(group.rawValue))
            section.identifier = NSUserInterfaceItemIdentifier("sensor")

            inGroup.forEach { (s: Sensor_p) in
                let btn = switchView(
                    action: #selector(self.toggleSensor),
                    state: s.state
                )
                btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                section.add(PreferencesRow(localizedString(s.name), component: btn))
                buttonList.append(KeyValue_t(key: s.key, value: "\(localizedString(group.rawValue)) - \(s.name)"))
            }

            self.addArrangedSubview(section)
        }

        if let row = self.sensorsPrefs?.findRow("active_sensor") {
            self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini }))
            row.replaceComponent(with: selectView(
                action: #selector(self.handleSelection),
                items: buttonList,
                selected: self.selectedSensor
            ))
        }
    }

    public func setList(_ list: [Sensor_p]?) {
        guard let list else { return }
        self.list = list
        self.load(widgets: self.widgets)
    }

    @objc private func toggleSensor(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)", value: controlState(sender))
        self.callback()
    }
    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }
    @objc private func handleSelection(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.representedObject as? String else { return }
        self.selectedSensor = id
        Store.shared.set(key: "\(self.title)_sensor", value: self.selectedSensor)
        self.selectedHandler(self.selectedSensor)
    }
}
