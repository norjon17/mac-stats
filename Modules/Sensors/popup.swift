//
//  popup.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 22/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private var list: [String: SensorView] = [:]

    private var sensors: [Sensor_p] = []
    private let settingsView: NSStackView = NSStackView()
    private let sensorsCache = PopupCache<[Sensor_p]>()

    /// Reports popup visibility to the reader so it can widen or narrow what it polls.
    public var visibilityCallback: ((Bool) -> Void)? = nil

    public init() {
        super.init(ModuleType.sensors, frame: NSRect( x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.spacing = 0
        self.translatesAutoresizingMaskIntoConstraints = false

        self.settingsView.orientation = .vertical
        self.settingsView.spacing = Constants.Settings.margin

        self.settingsView.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func setup(_ values: [Sensor_p]? = nil, reload: Bool = false) {
        guard let values = reload ? self.sensors : values else { return }

        self.subviews.forEach({ $0.removeFromSuperview() })
        self.list = [:]
        if !reload {
            self.settingsView.subviews.filter({ $0.identifier == NSUserInterfaceItemIdentifier("sensor") }).forEach { v in
                v.removeFromSuperview()
            }
        }

        SensorGroup.ordered.forEach { (group: SensorGroup) in
            let inGroup = values.filter { $0.group == group }
            guard !inGroup.isEmpty else { return }

            if !reload {
                let section = PreferencesSection(title: localizedString(group.rawValue))
                section.identifier = NSUserInterfaceItemIdentifier("sensor")
                inGroup.forEach { (s: Sensor_p) in
                    let btn = switchView(
                        action: #selector(self.toggleSensor),
                        state: s.popupState
                    )
                    btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                    section.add(PreferencesRow(localizedString(s.name), component: btn))
                }
                self.settingsView.addArrangedSubview(section)
            }

            let visible = inGroup.filter { $0.popupState }
            guard !visible.isEmpty else { return }

            self.addArrangedSubview(separatorView(localizedString(group.rawValue), width: self.frame.width))
            visible.forEach { (s: Sensor_p) in
                let sensor = SensorView(s, width: self.frame.width) { [weak self] in
                    self?.recalculateHeight()
                }
                self.addArrangedSubview(sensor)
                self.list[s.key] = sensor
            }
        }

        if !reload {
            self.sensors = values
        }
        self.recalculateHeight()
    }

    internal func usageCallback(_ values: [Sensor_p]) {
        DispatchQueue.main.async(execute: {
            let visible = self.window?.isVisible ?? false
            // Self-correcting: if appear/disappear was missed, the next tick still fixes the reader's view.
            self.visibilityCallback?(visible)

            values.forEach { (s: Sensor_p) in
                if let sensor = self.list[s.key] {
                    sensor.addHistoryPoint(s)
                }
            }

            self.sensorsCache.apply(values, visible: visible, render: self.renderSensors)
        })
    }

    private func renderSensors(_ values: [Sensor_p]) {
        values.forEach { (s: Sensor_p) in
            self.list[s.key]?.update(s)
        }
    }

    public override func appear() {
        self.visibilityCallback?(true)
        self.replay(self.sensorsCache, render: self.renderSensors)
    }

    public override func disappear() {
        self.visibilityCallback?(false)
    }

    private func recalculateHeight() {
        let h = self.arrangedSubviews.map({ $0.bounds.height + self.spacing }).reduce(0, +) - self.spacing
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    // MARK: - Settings

    public override func settings() -> NSView? {
        self.settingsView
    }

    @objc private func toggleSensor(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)_popup", value: controlState(sender))
        self.setup(reload: true)
    }
}

// MARK: - Sensor view

internal class SensorView: NSStackView {
    public var sizeCallback: (() -> Void)

    private var valueView: ValueSensorView!
    private var chartView: ChartSensorView!

    private var openned: Bool = false

    public init(_ sensor: Sensor_p, width: CGFloat, toggleable: Bool = true, callback: @escaping (() -> Void)) {
        self.sizeCallback = callback

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))

        self.orientation = .vertical
        self.distribution = .fillProportionally
        self.spacing = 0

        self.valueView = ValueSensorView(sensor, width: width, toggleable: toggleable, callback: { [weak self] in
            self?.open()
        })
        self.chartView = ChartSensorView(width: width, suffix: sensor.unit)

        self.addArrangedSubview(self.valueView)

        NSLayoutConstraint.activate([
            self.valueView.widthAnchor.constraint(equalTo: self.widthAnchor),
            self.widthAnchor.constraint(equalToConstant: self.bounds.width)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ sensor: Sensor_p) {
        self.valueView.update(sensor.formattedPopupValue)
    }

    public func addHistoryPoint(_ sensor: Sensor_p) {
        self.chartView.update(sensor.localValue, sensor.unit)
    }

    private func open() {
        if self.openned {
            self.chartView.removeFromSuperview()
        } else {
            self.addArrangedSubview(self.chartView)
        }
        self.openned = !self.openned

        let h = self.arrangedSubviews.map({ $0.bounds.height }).reduce(0, +)
        self.setFrameSize(NSSize(width: self.frame.width, height: h))
        self.sizeCallback()
    }
}

internal class ValueSensorView: NSStackView {
    public var callback: (() -> Void)

    private var labelView: LabelField = {
        let view = LabelField(frame: NSRect.zero)
        view.cell?.truncatesLastVisibleLine = true
        return view
    }()
    private var valueView: ValueField = ValueField(frame: NSRect.zero)

    private let isToggleable: Bool

    public init(_ sensor: Sensor_p, width: CGFloat, toggleable: Bool = true, callback: @escaping (() -> Void)) {
        self.callback = callback
        self.isToggleable = toggleable
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))

        self.wantsLayer = true
        self.orientation = .horizontal
        self.distribution = .fillProportionally
        self.spacing = 0
        self.layer?.cornerRadius = 3

        self.labelView.stringValue = sensor.name
        self.labelView.toolTip = sensor.key
        self.valueView.stringValue = sensor.formattedValue

        self.addArrangedSubview(self.labelView)
        self.addArrangedSubview(self.valueView)

        if self.isToggleable {
            self.addTrackingArea(NSTrackingArea(
                rect: NSRect(x: 0, y: 0, width: self.frame.width, height: 22),
                options: [NSTrackingArea.Options.activeAlways, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInActiveApp],
                owner: self,
                userInfo: nil
            ))
        }

        NSLayoutConstraint.activate([
            self.labelView.heightAnchor.constraint(equalToConstant: 16),
            self.heightAnchor.constraint(equalToConstant: self.bounds.height)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ value: String) {
        self.valueView.stringValue = value
    }

    override func mouseDown(with theEvent: NSEvent) {
        guard self.isToggleable else { return }
        self.callback()
    }

    public override func mouseEntered(with: NSEvent) {
        guard self.isToggleable else { return }
        self.layer?.backgroundColor = .init(gray: 0.01, alpha: 0.05)
    }

    public override func mouseExited(with: NSEvent) {
        guard self.isToggleable else { return }
        self.layer?.backgroundColor = .none
    }
}

internal class ChartSensorView: NSStackView {
    private var chart: LineChartView? = nil
    private var currentSuffix: String

    public init(width: CGFloat, suffix: String) {
        self.currentSuffix = suffix
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 60))

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        self.orientation = .horizontal
        self.distribution = .fillProportionally
        self.spacing = 0
        self.layer?.cornerRadius = 3

        self.chart = LineChartView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height), num: 120, scale: .linear)
        self.chart?.setSuffix(suffix)

        if let view = self.chart {
            self.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: self.bounds.width),
            self.heightAnchor.constraint(equalToConstant: self.bounds.height)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.chart?.display()
    }

    public func update(_ value: Double, _ suffix: String) {
        guard let chart = self.chart else { return }
        if self.currentSuffix != suffix {
            self.currentSuffix = suffix
            chart.setSuffix(suffix)
        }
        chart.addValue(value/100)
    }
}
