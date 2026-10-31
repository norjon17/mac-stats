//
//  portal.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 14/01/2024
//  Using Swift 5.0
//  Running on macOS 14.3
//
//  Copyright © 2024 Serhiy Mytrovtsiy. All rights reserved.
//

import AppKit
import Kit

public class Portal: PortalWrapper {
    private var container: ScrollableStackView = ScrollableStackView()

    private var list: [String: ValueSensorView] = [:]

    public override func load() {
        self.container.stackView.spacing = 0
        self.body.addArrangedSubview(self.container)
    }

    public func setup(_ values: [Sensor_p]? = nil) {
        guard let values else { return }
        let list = values.filter{ $0.popupState }

        if !self.list.isEmpty {
            self.container.stackView.subviews.forEach({ $0.removeFromSuperview() })
            self.list = [:]
        }

        let width: CGFloat = Constants.Popup.width - self.body.edgeInsets.left - self.body.edgeInsets.right
        list.forEach { s in
            let v = ValueSensorView(s, width: width, callback: {})
            v.update(s.formattedPopupValue)
            self.container.stackView.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: self.container.stackView.widthAnchor).isActive = true
            self.list[s.key] = v
        }
    }

    public func usageCallback(_ values: [Sensor_p]) {
        DispatchQueue.main.async(execute: {
            if self.window?.isVisible ?? false {
                values.forEach { (s: Sensor_p) in
                    self.list[s.key]?.update(s.formattedPopupValue)
                }
            }
        })
    }
}
