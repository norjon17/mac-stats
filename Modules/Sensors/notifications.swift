//
//  notifications.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 05/12/2023
//  Using Swift 5.0
//  Running on macOS 14.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

class Notifications: NotificationsWrapper {
    private var temperatureLevels: [KeyValue_t] = [
        KeyValue_t(key: "", value: "Disabled")
    ]
    private let temperatureList: [String] = ["30", "35", "40", "45", "50", "55", "60", "65", "70", "75", "80", "85", "90", "96", "100", "105", "110"]

    public init(_ module: ModuleType) {
        super.init(module)
        for p in self.temperatureList {
            if let v = Double(p) {
                self.temperatureLevels.append(KeyValue_t(key: p, value: temperature(v)))
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func setup(_ values: [Sensor_p]? = nil) {
        guard let values else { return }
        self.subviews.forEach({ $0.removeFromSuperview() })
        self.initIDs(values.map{$0.key})

        SensorGroup.ordered.forEach { (group: SensorGroup) in
            let inGroup = values.filter { $0.group == group }
            guard !inGroup.isEmpty else { return }

            let section = PreferencesSection(title: localizedString(group.rawValue))
            inGroup.forEach { (s: Sensor_p) in
                let btn = selectView(
                    action: #selector(self.changeSensorNotificaion),
                    items: self.temperatureLevels,
                    selected: s.notificationThreshold
                )
                btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                section.add(PreferencesRow(localizedString(s.name), component: btn))
            }
            self.addArrangedSubview(section)
        }
    }

    internal func usageCallback(_ values: [Sensor_p]) {
        let sensors = values.filter({ !$0.notificationThreshold.isEmpty })
        let title = localizedString("Sensor threshold")

        for s in sensors {
            if let threshold = Double(s.notificationThreshold) {
                let subtitle = localizedString("\(localizedString(s.name)): \(s.formattedPopupValue)")
                self.checkDouble(id: s.key, value: s.value, threshold: threshold, title: title, subtitle: subtitle)
            }
        }
    }

    @objc private func changeSensorNotificaion(_ sender: NSMenuItem) {
        guard let id = sender.identifier, let key = sender.representedObject as? String else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)_notification", value: key)
    }
}
