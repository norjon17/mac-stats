//
//  main.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public class Sensors: Module {
    private var sensorsReader: SensorsReader?
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications

    private var selectedSensor: String

    public init() {
        self.settingsView = Settings(.sensors)
        self.popupView = Popup()
        self.portalView = Portal(.sensors)
        self.notificationsView = Notifications(.sensors)
        self.selectedSensor = Store.shared.string(key: "\(ModuleType.sensors.stringValue)_sensor", defaultValue: defaultSelectedSensor)

        super.init(
            moduleType: .sensors,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }

        self.sensorsReader = SensorsReader { [weak self] value in
            self?.usageCallback(value)
        }

        self.settingsView.setList(self.sensorsReader?.list.sensors)
        self.popupView.setup(self.sensorsReader?.list.sensors)
        self.portalView.setup(self.sensorsReader?.list.sensors)
        self.notificationsView.setup(self.sensorsReader?.list.sensors)

        self.settingsView.callback = { [weak self] in
            DispatchQueue.global(qos: .utility).async {
                self?.sensorsReader?.read()
            }
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.sensorsReader?.setInterval(value)
        }
        self.settingsView.selectedHandler = { [weak self] value in
            self?.selectedSensor = value
            DispatchQueue.global(qos: .utility).async {
                self?.sensorsReader?.read()
            }
        }
        self.popupView.visibilityCallback = { [weak self] visible in
            self?.sensorsReader?.setPopupVisible(visible)
        }

        self.setReaders([self.sensorsReader])
    }

    private func usageCallback(_ raw: Sensors_List?) {
        guard let value = raw, self.enabled else { return }

        self.popupView.usageCallback(value.sensors)
        self.portalView.usageCallback(value.sensors)
        self.notificationsView.usageCallback(value.sensors)

        let activeWidgets = self.menuBar.widgets.filter{ $0.isActive }
        self.sensorsReader?.sleepMode(state: activeWidgets.contains(where: {$0.item is Label}) && activeWidgets.count == 1)

        activeWidgets.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                if let active = value.sensors.first(where: { $0.key == self.selectedSensor }) {
                    let value: Double = active.localValue/100
                    widget.setValue(value)
                    widget.setSuffix(value > 999 ? "" : active.miniUnit)
                }
            case let widget as StackWidget:
                let list: [Stack_t] = value.sensors
                    .filter { $0.state }
                    .map { Stack_t(key: $0.key, value: $0.formattedMiniValue) }
                widget.setValues(list)
            default: break
            }
        }
    }
}
