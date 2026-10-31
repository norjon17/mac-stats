//
//  popup.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let dashboardHeight: CGFloat = 90
    private let chartHeight: CGFloat = 120 + Constants.Popup.separatorHeight + Constants.Popup.spacing*2
    private var detailsHeight: CGFloat {
        get {
            var count: CGFloat = 4
            if SystemKit.shared.device.info.cpu?.eCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.sCores != nil {
                count += 1
            }
            if SystemKit.shared.device.info.cpu?.pCores != nil {
                count += 1
            }
            return (22*count) + Constants.Popup.separatorHeight
        }
    }
    
    private var systemField: NSTextField? = nil
    private var userField: NSTextField? = nil
    private var idleField: NSTextField? = nil
    private var eCoresField: NSTextField? = nil
    private var pCoresField: NSTextField? = nil
    private var sCoresField: NSTextField? = nil
    private var uptimeField: NSTextField? = nil
    
    private var systemColorView: NSView? = nil
    private var userColorView: NSView? = nil
    private var idleColorView: NSView? = nil
    private var eCoresColorView: NSView? = nil
    private var pCoresColorView: NSView? = nil
    private var sCoresColorView: NSView? = nil
    
    private var chartPrefSection: PreferencesSection? = nil
    private var sliderView: NSView? = nil
    
    private var lineChart: LineChartView? = nil
    private var columnChart: ColumnChartView? = nil
    private var circle: PieChartView? = nil
    private var temperatureCircle: PieChartView? = nil
    
    private let loadCache = PopupCache<CPU_Load>()
    private let temperatureCache = PopupCache<Double>()
    
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    
    private var systemColorState: SColor = .secondRed
    private var systemColor: NSColor { self.systemColorState.additional as? NSColor ?? NSColor.systemRed }
    private var userColorState: SColor = .secondBlue
    private var userColor: NSColor { self.userColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var idleColorState: SColor = .lightGray
    private var idleColor: NSColor { self.idleColorState.additional as? NSColor ?? NSColor.lightGray }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor { self.chartColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var eCoresColorState: SColor = .teal
    private var eCoresColor: NSColor { self.eCoresColorState.additional as? NSColor ?? NSColor.systemTeal }
    private var pCoresColorState: SColor = .indigo
    private var pCoresColor: NSColor { self.pCoresColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var sCoresColorState: SColor = .orange
    private var sCoresColor: NSColor { self.sCoresColorState.additional as? NSColor ?? NSColor.systemOrange }
    
    private var uptimeValue: String {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        var value = localizedString("Unknown")
        if let bootDate = SystemKit.shared.device.bootDate {
            if let duration = form.string(from: bootDate, to: Date()) {
                value = duration
            }
        }
        return value
    }
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.spacing = 0
        self.orientation = .vertical
        
        self.systemColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_systemColor", defaultValue: self.systemColorState.key))
        self.userColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_userColor", defaultValue: self.userColorState.key))
        self.idleColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_idleColor", defaultValue: self.idleColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.eCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_eCoresColor", defaultValue: self.eCoresColorState.key))
        self.pCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_pCoresColor", defaultValue: self.pCoresColorState.key))
        self.sCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_sCoresColor", defaultValue: self.sCoresColorState.key))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.lineChartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale = Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100)) / 100
        
        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateLayer() {
        self.lineChart?.display()
    }
    
    public override func appear() {
        self.uptimeField?.stringValue = self.uptimeValue
        self.replay(self.loadCache, render: self.renderLoad)
        self.replay(self.temperatureCache, render: self.renderTemperature)
    }
    
    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                h += v.arrangedSubviews.map({ $0.bounds.height + v.spacing }).reduce(0, +)
            } else {
                h += v.bounds.height
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    private func initDashboard() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        
        let usageSize = self.dashboardHeight-20
        let usageX = (view.frame.width - usageSize)/2
        
        let usage = NSView(frame: NSRect(x: usageX, y: (view.frame.height - usageSize)/2, width: usageSize, height: usageSize))
        let temperature = NSView(frame: NSRect(x: (usageX - 50)/2, y: (view.frame.height - 50)/2 - 3, width: 50, height: 50))
        
        self.circle = PieChartView(frame: NSRect(x: 0, y: 0, width: usage.frame.width, height: usage.frame.height), segments: [], drawValue: true)
        self.circle!.toolTip = localizedString("CPU usage")
        usage.addSubview(self.circle!)
        
        self.temperatureCircle = PieChartView(frame: NSRect(x: 0, y: 0, width: temperature.frame.width, height: temperature.frame.height))
        self.temperatureCircle!.toolTip = localizedString("CPU temperature")
        (self.temperatureCircle! as NSView).isHidden = true
        temperature.addSubview(self.temperatureCircle!)
        
        view.addSubview(temperature)
        view.addSubview(usage)
        
        return view
    }
    
    private func initChart() -> NSView {
        let view: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .vertical
        view.spacing = Constants.Popup.spacing
        
        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: 0), width: self.frame.width)
        
        let lineChartContainer: NSView = {
            let box: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 70))
            box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
            box.layer?.cornerRadius = Constants.Popup.radius
            
            let chartFrame = NSRect(x: 1, y: 0, width: box.frame.width - 2, height: box.frame.height)
            self.lineChart = LineChartView(frame: chartFrame, num: self.lineChartHistory, scale: self.lineChartScale, fixedScale: self.lineChartFixedScale)
            self.lineChart?.setColor(self.chartColor)
            box.addSubview(self.lineChart!)
            
            return box
        }()
        
        view.addArrangedSubview(separator)
        view.addArrangedSubview(lineChartContainer)
        
        if let cores = SystemKit.shared.device.info.cpu?.logicalCores {
            let barChartContainer: NSView = {
                let box: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 50))
                box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
                box.wantsLayer = true
                box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
                box.layer?.cornerRadius = 3
                
                let chart = ColumnChartView(frame: NSRect(
                    x: Constants.Popup.spacing,
                    y: Constants.Popup.spacing,
                    width: view.frame.width - (Constants.Popup.spacing*2),
                    height: box.frame.height - (Constants.Popup.spacing*2)
                ), num: Int(cores))
                self.columnChart = chart
                
                box.addSubview(chart)
                
                return box
            }()
            view.addArrangedSubview(barChartContainer)
        }
        
        return view
    }
    
    private func initDetails() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("Details"), origin: NSPoint(
            x: 0,
            y: self.detailsHeight-Constants.Popup.separatorHeight
        ), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        (self.systemColorView, _, self.systemField) = popupWithColorRow(container, color: self.systemColor, title: "\(localizedString("System")):", value: "")
        (self.userColorView, _, self.userField) = popupWithColorRow(container, color: self.userColor, title: "\(localizedString("User")):", value: "")
        (self.idleColorView, _, self.idleField) = popupWithColorRow(container, color: self.idleColor.withAlphaComponent(0.5), title: "\(localizedString("Idle")):", value: "")
        
        if SystemKit.shared.device.info.cpu?.eCores != nil {
            (self.eCoresColorView, _, self.eCoresField) = popupWithColorRow(container, color: self.eCoresColor, title: "\(localizedString("Efficiency cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.pCores != nil {
            (self.pCoresColorView, _, self.pCoresField) = popupWithColorRow(container, color: self.pCoresColor, title: "\(localizedString("Performance cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.sCores != nil {
            (self.sCoresColorView, _, self.sCoresField) = popupWithColorRow(container, color: self.sCoresColor, title: "\(localizedString("Super cores")):", value: "")
        }
        
        self.uptimeField = popupRow(container, title: "\(localizedString("Uptime")):", value: self.uptimeValue).1
        self.uptimeField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    public func loadCallback(_ value: CPU_Load) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        self.lineChart?.addValue(value.totalUsage)
    }
    
    private func renderLoad(_ value: CPU_Load) {
        self.systemField?.stringValue = "\(Int(value.systemLoad.rounded(toPlaces: 2) * 100))%"
        self.userField?.stringValue = "\(Int(value.userLoad.rounded(toPlaces: 2) * 100))%"
        self.idleField?.stringValue = "\(Int(value.idleLoad.rounded(toPlaces: 2) * 100))%"
        
        self.circle?.toolTip = "\(localizedString("CPU usage")): \(Int(value.totalUsage.rounded(toPlaces: 2) * 100))%"
        self.circle?.setValue(value.totalUsage)
        self.circle?.setSegments([
            ColorValue(value.systemLoad, color: self.systemColor),
            ColorValue(value.userLoad, color: self.userColor)
        ])
        self.circle?.setNonActiveSegmentColor(self.idleColor)
        self.circle?.display()
        
        if let field = self.eCoresField, let usage = value.usageECores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.pCoresField, let usage = value.usagePCores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.sCoresField, let usage = value.usageSCores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        
        var usagePerCore: [ColorValue] = []
        if let cores = SystemKit.shared.device.info.cpu?.cores, !cores.isEmpty {
            for i in 0..<value.usagePerCore.count {
                let core = cores.first(where: { $0.id == i })
                let color = core?.type == .efficiency ? self.eCoresColor : core?.type == .super ? self.sCoresColor : self.pCoresColor
                usagePerCore.append(ColorValue(value.usagePerCore[i], color: color))
            }
        } else {
            for i in 0..<value.usagePerCore.count {
                usagePerCore.append(ColorValue(value.usagePerCore[i], color: NSColor.systemBlue))
            }
        }
        self.columnChart?.setValues(usagePerCore)
        self.columnChart?.display()
        
        self.lineChart?.display()
    }
    
    public func temperatureCallback(_ value: Double?) {
        guard let value else { return }
        self.apply(value, to: self.temperatureCache, render: self.renderTemperature)
    }
    
    private func renderTemperature(_ value: Double) {
        if let view = self.temperatureCircle, (view as NSView).isHidden {
            view.isHidden = false
        }
        
        self.temperatureCircle?.toolTip = "\(localizedString("CPU temperature")): \(temperature(value))"
        self.temperatureCircle?.setValue(value/100)
        self.temperatureCircle?.setText(temperature(value))
        self.temperatureCircle?.display()
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("System color"), component: colorSelectView(
                action: #selector(self.toggleSystemColor),
                items: SColor.allColors,
                selected: self.systemColorState.key
            )),
            PreferencesRow(localizedString("User color"), component: colorSelectView(
                action: #selector(self.toggleUserColor),
                items: SColor.allColors,
                selected: self.userColorState.key
            )),
            PreferencesRow(localizedString("Idle color"), component: colorSelectView(
                action: #selector(self.toggleIdleColor),
                items: SColor.allColors,
                selected: self.idleColorState.key
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Efficiency cores color"), component: colorSelectView(
                action: #selector(self.toggleECoresColor),
                items: SColor.allColors,
                selected: self.eCoresColorState.key
            )),
            PreferencesRow(localizedString("Performance cores color"), component: colorSelectView(
                action: #selector(self.togglePCoresColor),
                items: SColor.allColors,
                selected: self.pCoresColorState.key
            )),
            PreferencesRow(localizedString("Super cores color"), component: colorSelectView(
                action: #selector(self.toggleSCoresColor),
                items: SColor.allColors,
                selected: self.sCoresColorState.key
            ))
        ]))
        
        self.sliderView = sliderView(
            action: #selector(self.toggleLineChartFixedScale),
            value: Int(self.lineChartFixedScale * 100),
            initialValue: "\(Int(self.lineChartFixedScale * 100)) %"
        )
        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart color"), component: colorSelectView(
                action: #selector(self.toggleChartColor),
                items: SColor.allColors,
                selected: self.chartColorState.key
            )),
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.toggleLineChartHistory),
                items: LineChartHistory,
                selected: "\(self.lineChartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: selectView(
                action: #selector(self.toggleLineChartScale),
                items: Scale.allCases,
                selected: self.lineChartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: self.sliderView!)
        ])
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)
        
        return view
    }
    
    @objc private func toggleSystemColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.systemColorState = SColor.fromString(key, defaultValue: self.systemColorState)
        Store.shared.set(key: "\(self.title)_systemColor", value: self.systemColorState.key)
        self.systemColorView?.layer?.backgroundColor = (self.systemColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleUserColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.userColorState = SColor.fromString(key, defaultValue: self.userColorState)
        Store.shared.set(key: "\(self.title)_userColor", value: self.userColorState.key)
        self.userColorView?.layer?.backgroundColor = (self.userColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleIdleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.idleColorState = SColor.fromString(key, defaultValue: self.idleColorState)
        Store.shared.set(key: "\(self.title)_idleColor", value: self.idleColorState.key)
        self.idleColorView?.layer?.backgroundColor = (self.idleColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.chartColorState = SColor.fromString(key, defaultValue: self.chartColorState)
        Store.shared.set(key: "\(self.title)_chartColor", value: self.chartColorState.key)
        if let color = self.chartColorState.additional as? NSColor {
            self.lineChart?.setColor(color)
        }
    }
    @objc private func toggleECoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.eCoresColorState = SColor.fromString(key, defaultValue: self.eCoresColorState)
        Store.shared.set(key: "\(self.title)_eCoresColor", value: self.eCoresColorState.key)
        if let color = (self.eCoresColorState.additional as? NSColor) {
            self.eCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func togglePCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.pCoresColorState = SColor.fromString(key, defaultValue: self.pCoresColorState)
        Store.shared.set(key: "\(self.title)_pCoresColor", value: self.pCoresColorState.key)
        if let color = (self.pCoresColorState.additional as? NSColor) {
            self.pCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleSCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.sCoresColorState = SColor.fromString(key, defaultValue: self.sCoresColorState)
        Store.shared.set(key: "\(self.title)_sCoresColor", value: self.sCoresColorState.key)
        if let color = (self.sCoresColorState.additional as? NSColor) {
            self.sCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.lineChart?.reinit(self.lineChartHistory)
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
        self.display()
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)
        
        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }), let view = field as? NSTextField {
            view.stringValue = "\(value) %"
        }
        
        self.lineChartFixedScale = sender.doubleValue / 100
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
