//
//  popup.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 24/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private var uploadContainerView: NSView? = nil
    private var uploadView: NSView? = nil
    private var uploadValue: Int64 = 0
    private var uploadValueField: NSTextField? = nil
    private var uploadUnitField: NSTextField? = nil
    private var uploadStateView: ColorView? = nil

    private var downloadContainerView: NSView? = nil
    private var downloadView: NSView? = nil
    private var downloadValue: Int64 = 0
    private var downloadValueField: NSTextField? = nil
    private var downloadUnitField: NSTextField? = nil
    private var downloadStateView: ColorView? = nil

    private var downloadColorView: NSView? = nil
    private var uploadColorView: NSView? = nil

    private var totalUploadLabel: LabelField? = nil
    private var totalUploadField: ValueField? = nil
    private var totalDownloadLabel: LabelField? = nil
    private var totalDownloadField: ValueField? = nil
    private var statusField: StatusBadgeView? = nil

    private var interfaceView: NSStackView? = nil
    private var interfaceField: ValueField? = nil
    private var interfaceStatusField: StatusBadgeView? = nil
    private var macAddressField: ValueField? = nil
    private var localIPField: ValueField? = nil

    private var interfaceDetailsState: Bool = false
    private var connectionTypeView: NSView? = nil
    private var connectionTypeField: ValueField? = nil
    private var interfaceSpeedView: NSView? = nil
    private var interfaceSpeedField: ValueField? = nil

    private var chart: NetworkChartView? = nil
    private var reverseOrderState: Bool = false
    private var chartHistory: Int = 180
    private var chartScale: Scale = .none
    private var chartFixedScale: Int = 12
    private var chartFixedScaleSize: SizeUnit = .MB
    private var chartPrefSection: PreferencesSection? = nil

    private let usageCache = PopupCache<Network_Usage>()

    private var lastReset: Date = Date()

    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.title)_base", defaultValue: "byte")) ?? .byte
    }
    private var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(self.title)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }

    private var downloadColorState: SColor = .secondBlue
    private var downloadColor: NSColor {
        var value = NSColor.systemBlue
        if let color = self.downloadColorState.additional as? NSColor {
            value = color
        }
        return value
    }
    private var uploadColorState: SColor = .secondRed
    private var uploadColor: NSColor {
        var value = NSColor.systemRed
        if let color = self.uploadColorState.additional as? NSColor {
            value = color
        }
        return value
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = 0
        self.orientation = .vertical

        self.downloadColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_downloadColor", defaultValue: self.downloadColorState.key))
        self.uploadColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_uploadColor", defaultValue: self.uploadColorState.key))
        self.reverseOrderState = Store.shared.bool(key: "\(self.title)_reverseOrder", defaultValue: self.reverseOrderState)
        self.chartHistory = Store.shared.int(key: "\(self.title)_chartHistory", defaultValue: self.chartHistory)
        self.chartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_chartScale", defaultValue: self.chartScale.key))
        self.chartFixedScale = Store.shared.int(key: "\(self.title)_chartFixedScale", defaultValue: self.chartFixedScale)
        self.chartFixedScaleSize = SizeUnit.fromString(Store.shared.string(key: "\(self.title)_chartFixedScaleSize", defaultValue: self.chartFixedScaleSize.key))
        self.interfaceDetailsState = Store.shared.bool(key: "\(self.title)_interfaceDetails", defaultValue: self.interfaceDetailsState)

        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initInterface())

        self.recalculateHeight()

        NotificationCenter.default.addObserver(self, selector: #selector(self.resetTotalNetworkUsageCallback), name: .resetTotalNetworkUsage, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .resetTotalNetworkUsage, object: nil)
    }

    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                h += v.arrangedSubviews.map({ $0.bounds.height }).reduce(0, +)
            } else {
                h += v.bounds.height
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    // MARK: - views

    private func initDashboard() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 90))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true

        let leftPart: NSView = NSView(frame: NSRect(x: isRTL ? view.frame.width / 2 : 0, y: 0, width: view.frame.width / 2, height: view.frame.height))
        let downloadFields = self.topValueView(leftPart, title: localizedString("Downloading"), color: self.downloadColor)
        self.downloadContainerView = leftPart
        self.downloadView = downloadFields.0
        self.downloadValueField = downloadFields.1
        self.downloadUnitField = downloadFields.2
        self.downloadStateView = downloadFields.3

        let rightPart: NSView = NSView(frame: NSRect(x: isRTL ? 0 : view.frame.width / 2, y: 0, width: view.frame.width / 2, height: view.frame.height))
        let uploadFields = self.topValueView(rightPart, title: localizedString("Uploading"), color: self.uploadColor)
        self.uploadContainerView = rightPart
        self.uploadView = uploadFields.0
        self.uploadValueField = uploadFields.1
        self.uploadUnitField = uploadFields.2
        self.uploadStateView = uploadFields.3

        view.addSubview(leftPart)
        view.addSubview(rightPart)

        return view
    }

    private func initChart() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 90 + Constants.Popup.separatorHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true

        let separator = separatorView(localizedString("Usage history"), origin: NSPoint(x: 0, y: 90), width: self.frame.width)
        let container: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = Constants.Popup.radius

        let chart = NetworkChartView(
            frame: NSRect(x: 0, y: 1, width: container.frame.width, height: container.frame.height - 2),
            num: self.chartHistory, reversedOrder: self.reverseOrderState, outColor: self.uploadColor, inColor: self.downloadColor,
            scale: self.chartScale,
            fixedScale: Double(self.chartFixedScaleSize.toBytes(self.chartFixedScale))
        )
        chart.setBase(self.base)
        chart.setSpeedUnit(self.speedUnit)
        container.addSubview(chart)
        self.chart = chart

        view.addSubview(separator)
        view.addSubview(container)

        return view
    }

    private func initDetails() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0

        view.addArrangedSubview(SeparatorView(
            label: localizedString("Details"),
            button: PopupButton(toolTip: localizedString("Reset"), icon: "arrow.clockwise") { [weak self] in
                self?.resetTotalNetworkUsage()
            }
        ))

        let totalUpload = popupWithColorRow(view, color: self.uploadColor, title: "\(localizedString("Total upload")):", value: "0")
        let totalDownload = popupWithColorRow(view, color: self.downloadColor, title: "\(localizedString("Total download")):", value: "0")

        self.uploadColorView = totalUpload.0
        self.totalUploadLabel = totalUpload.1
        self.totalUploadField = totalUpload.2

        self.downloadColorView = totalDownload.0
        self.totalDownloadLabel = totalDownload.1
        self.totalDownloadField = totalDownload.2

        self.statusField = popupBadgeRow(view, title: "\(localizedString("Status")):").1

        return view
    }

    private func initInterface() -> NSView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0

        view.addArrangedSubview(SeparatorView(
            label: localizedString("Interface"),
            button: PopupButton(toolTip: localizedString("Details"), state: interfaceDetailsState) { [weak self] in
                self?.toggleInterfaceDetails()
            }
        ))

        self.interfaceField = popupRow(view, title: "\(localizedString("Interface")):", value: localizedString("Unknown")).1
        self.interfaceStatusField = popupBadgeRow(view, title: "\(localizedString("Status")):").1
        self.localIPField = popupRow(view, title: "\(localizedString("Local IP")):", value: localizedString("Unknown")).1
        self.localIPField?.isSelectable = true
        self.macAddressField = popupRow(view, title: "\(localizedString("Physical address")):", value: localizedString("Unknown")).1
        self.macAddressField?.isSelectable = true

        let type = popupRow(view, title: "\(localizedString("Connection type")):", value: localizedString("Unknown"))
        let speed = popupRow(view, title: "\(localizedString("Speed")):", value: localizedString("Unknown"))

        self.connectionTypeField = type.1
        self.connectionTypeView = type.2
        self.interfaceSpeedField = speed.1
        self.interfaceSpeedView = speed.2

        if !self.interfaceDetailsState {
            self.connectionTypeView?.removeFromSuperview()
            self.interfaceSpeedView?.removeFromSuperview()
        }

        self.interfaceView = view
        return view
    }

    // MARK: - callbacks

    public override func appear() {
        self.replay(self.usageCache, render: self.renderUsage)
    }

    public func usageCallback(_ value: Network_Usage) {
        self.apply(value, to: self.usageCache, render: self.renderUsage)

        if let chart = self.chart {
            chart.setBase(self.base)
            chart.setSpeedUnit(self.speedUnit)
            chart.addValue(upload: Double(value.bandwidth.upload), download: Double(value.bandwidth.download))
        }
    }

    private func renderUsage(_ value: Network_Usage) {
        self.uploadValue = value.bandwidth.upload
        self.downloadValue = value.bandwidth.download
        self.setUploadDownloadFields()

        self.totalUploadField?.stringValue = Units(bytes: value.total.upload).getReadableMemory()
        self.totalDownloadField?.stringValue = Units(bytes: value.total.download).getReadableMemory()

        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]

        if let duration = form.string(from: self.lastReset, to: Date()) {
            self.totalUploadLabel?.toolTip = localizedString("Last reset", duration)
            self.totalDownloadLabel?.toolTip = localizedString("Last reset", duration)
        }

        if let interface = value.interface {
            self.interfaceField?.stringValue = "\(interface.displayName) (\(interface.BSDName))"
            self.interfaceStatusField?.setStatus(interface.status)
            self.macAddressField?.stringValue = interface.address
            self.interfaceSpeedField?.stringValue = interface.transmitRate > 0 ? "\(Int(interface.transmitRate.rounded())) Mbps" : localizedString("Unknown")
        } else {
            self.interfaceField?.stringValue = localizedString("Unknown")
            self.interfaceStatusField?.setStatus(nil)
            self.macAddressField?.stringValue = localizedString("Unknown")
            self.interfaceSpeedField?.stringValue = localizedString("Unknown")
        }

        self.connectionTypeField?.stringValue = value.connectionType?.rawValue.capitalized ?? localizedString("Unknown")

        var privateIP = localizedString("Unknown")
        if let v4 = value.laddr.v4, !v4.isEmpty {
            privateIP = v4
        } else if let v6 = value.laddr.v6, !v6.isEmpty {
            privateIP = v6
        }
        if self.localIPField?.stringValue != privateIP {
            self.localIPField?.stringValue = privateIP
        }

        self.statusField?.setStatus(value.status)

        self.chart?.display()
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
            PreferencesRow(localizedString("Color of download"), component: colorSelectView(
                action: #selector(self.toggleDownloadColor),
                items: SColor.allColors,
                selected: self.downloadColorState.key
            )),
            PreferencesRow(localizedString("Color of upload"), component: colorSelectView(
                action: #selector(self.toggleUploadColor),
                items: SColor.allColors,
                selected: self.uploadColorState.key
            ))
        ]))

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Reverse order"), component: switchView(
                action: #selector(self.toggleReverseOrder),
                state: self.reverseOrderState
            ))
        ]))

        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.togglechartHistory),
                items: LineChartHistory,
                selected: "\(self.chartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: selectView(
                action: #selector(self.toggleChartScale),
                items: Scale.allCases,
                selected: self.chartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: StepperInput(
                self.chartFixedScale, range: NSRange(location: 1, length: 1023),
                unit: self.chartFixedScaleSize.key, units: SizeUnit.allCases,
                callback: self.toggleFixedScale, unitCallback: self.toggleFixedScaleSize
            ))
        ])
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(2, newState: self.chartScale == .fixed)

        return view
    }

    @objc private func toggleUploadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.uploadColorState = SColor.fromString(key, defaultValue: self.uploadColorState)
        Store.shared.set(key: "\(self.title)_uploadColor", value: self.uploadColorState.key)
        if let color = self.uploadColorState.additional as? NSColor {
            self.uploadColorView?.layer?.backgroundColor = color.cgColor
            self.uploadStateView?.setColor(color)
            self.chart?.setColors(out: color)
        }
    }
    @objc private func toggleDownloadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.downloadColorState = SColor.fromString(key, defaultValue: self.downloadColorState)
        Store.shared.set(key: "\(self.title)_downloadColor", value: self.downloadColorState.key)
        if let color = self.downloadColorState.additional as? NSColor {
            self.downloadColorView?.layer?.backgroundColor = color.cgColor
            self.downloadStateView?.setColor(color)
            self.chart?.setColors(in: color)
        }
    }
    @objc private func toggleReverseOrder(_ sender: NSControl) {
        self.reverseOrderState = controlState(sender)
        self.chart?.setReverseOrder(self.reverseOrderState)
        Store.shared.set(key: "\(self.title)_reverseOrder", value: self.reverseOrderState)
        self.display()
    }
    @objc private func togglechartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.chartHistory = value
        Store.shared.set(key: "\(self.title)_chartHistory", value: value)
        self.chart?.reinit(self.chartHistory)
    }
    @objc private func toggleChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartScale = value
        self.chart?.setScale(self.chartScale, Double(self.chartFixedScaleSize.toBytes(self.chartFixedScale)))
        self.chartPrefSection?.setRowVisibility(2, newState: self.chartScale == .fixed)
        Store.shared.set(key: "\(self.title)_chartScale", value: key)
        self.display()
    }
    @objc private func toggleFixedScale(_ newValue: Int) {
        self.chart?.setScale(self.chartScale, Double(self.chartFixedScaleSize.toBytes(newValue)))
        Store.shared.set(key: "\(self.title)_chartFixedScale", value: newValue)
    }
    private func toggleFixedScaleSize(_ newValue: KeyValue_p) {
        guard let newUnit = newValue as? SizeUnit else { return }
        self.chartFixedScaleSize = newUnit
        Store.shared.set(key: "\(self.title)_chartFixedScaleSize", value: self.chartFixedScaleSize.key)
        self.display()
    }
    @objc private func toggleInterfaceDetails() {
        self.interfaceDetailsState = !self.interfaceDetailsState
        Store.shared.set(key: "\(self.title)_interfaceDetails", value: self.interfaceDetailsState)

        if !self.interfaceDetailsState {
            self.connectionTypeView?.removeFromSuperview()
            self.interfaceSpeedView?.removeFromSuperview()
        } else {
            if let view = self.connectionTypeView, view.superview == nil {
                self.interfaceView?.addArrangedSubview(view)
            }
            if let view = self.interfaceSpeedView, view.superview == nil {
                self.interfaceView?.addArrangedSubview(view)
            }
        }

        self.recalculateHeight()
    }

    // MARK: - helpers

    private func topValueView(_ view: NSView, title: String, color: NSColor) -> (NSView, NSTextField, NSTextField, ColorView) {
        let topHeight: CGFloat = 30
        let titleHeight: CGFloat = 15

        view.setAccessibilityElement(true)
        view.toolTip = title

        let valueWidth = "0".widthOfString(usingFont: .systemFont(ofSize: 26, weight: .light)) + 5
        let unitWidth = "KB/s".widthOfString(usingFont: .systemFont(ofSize: 13, weight: .light)) + 5
        let topPartWidth = valueWidth + unitWidth

        let topView: NSView = NSView(frame: NSRect(
            x: (view.frame.width-topPartWidth)/2,
            y: (view.frame.height - topHeight - titleHeight)/2 + titleHeight,
            width: topPartWidth,
            height: topHeight
        ))

        let valueField = LabelField(frame: NSRect(x: 0, y: 0, width: valueWidth, height: 30), "0")
        valueField.font = NSFont.systemFont(ofSize: 26, weight: .light)
        valueField.textColor = .textColor
        valueField.alignment = .right

        let unitField = LabelField(frame: NSRect(x: valueField.frame.width, y: 4, width: unitWidth, height: 15), "KB/s")
        unitField.font = NSFont.systemFont(ofSize: 13, weight: .light)
        unitField.textColor = .labelColor
        unitField.alignment = .left

        let titleWidth: CGFloat = title.widthOfString(usingFont: NSFont.systemFont(ofSize: 11, weight: .regular))+8
        let iconSize: CGFloat = 12
        let bottomWidth: CGFloat = titleWidth+iconSize
        let bottomView: NSView = NSView(frame: NSRect(
            x: (view.frame.width-bottomWidth)/2,
            y: topView.frame.origin.y - titleHeight - 2,
            width: bottomWidth,
            height: titleHeight
        ))

        let colorBlock: ColorView = ColorView(frame: NSRect(x: 0, y: 2, width: iconSize, height: iconSize), color: color, radius: 4)
        let titleField = LabelField(frame: NSRect(x: iconSize, y: 0, width: titleWidth, height: titleHeight), title)
        titleField.alignment = .center
        titleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        topView.addSubview(valueField)
        topView.addSubview(unitField)

        bottomView.addSubview(colorBlock)
        bottomView.addSubview(titleField)

        view.addSubview(topView)
        view.addSubview(bottomView)

        return (topView, valueField, unitField, colorBlock)
    }

    private func setUploadDownloadFields() {
        let upload = Units(bytes: self.uploadValue).getReadableTuple(base: self.base, unit: self.speedUnit)
        let download = Units(bytes: self.downloadValue).getReadableTuple(base: self.base, unit: self.speedUnit)

        self.uploadContainerView?.toolTip = "\(localizedString("Uploading")): \(upload.0)\(upload.1)"
        self.downloadContainerView?.toolTip = "\(localizedString("Downloading")): \(download.0)\(download.1)"

        var valueWidth = "\(upload.0)".widthOfString(usingFont: .systemFont(ofSize: 26, weight: .light)) + 5
        var unitWidth = upload.1.widthOfString(usingFont: .systemFont(ofSize: 13, weight: .light)) + 5
        var topPartWidth = valueWidth + unitWidth

        self.uploadView?.setFrameSize(NSSize(width: topPartWidth, height: self.uploadView!.frame.height))
        self.uploadView?.setFrameOrigin(NSPoint(x: ((self.frame.width/2)-topPartWidth)/2, y: self.uploadView!.frame.origin.y))

        self.uploadValueField?.setFrameSize(NSSize(width: valueWidth, height: self.uploadValueField!.frame.height))
        self.uploadValueField?.stringValue = "\(upload.0)"
        self.uploadUnitField?.setFrameSize(NSSize(width: unitWidth, height: self.uploadUnitField!.frame.height))
        self.uploadUnitField?.setFrameOrigin(NSPoint(x: self.uploadValueField!.frame.width, y: self.uploadUnitField!.frame.origin.y))
        self.uploadUnitField?.stringValue = upload.1

        valueWidth = "\(download.0)".widthOfString(usingFont: .systemFont(ofSize: 26, weight: .light)) + 5
        unitWidth = download.1.widthOfString(usingFont: .systemFont(ofSize: 13, weight: .light)) + 5
        topPartWidth = valueWidth + unitWidth

        self.downloadView?.setFrameSize(NSSize(width: topPartWidth, height: self.downloadView!.frame.height))
        self.downloadView?.setFrameOrigin(NSPoint(x: ((self.frame.width/2)-topPartWidth)/2, y: self.downloadView!.frame.origin.y))

        self.downloadValueField?.setFrameSize(NSSize(width: valueWidth, height: self.downloadValueField!.frame.height))
        self.downloadValueField?.stringValue = "\(download.0)"
        self.downloadUnitField?.setFrameSize(NSSize(width: unitWidth, height: self.downloadUnitField!.frame.height))
        self.downloadUnitField?.setFrameOrigin(NSPoint(x: self.downloadValueField!.frame.width, y: self.downloadUnitField!.frame.origin.y))
        self.downloadUnitField?.stringValue = download.1

        self.uploadStateView?.setState(self.uploadValue != 0)
        self.downloadStateView?.setState(self.downloadValue != 0)
    }

    @objc private func resetTotalNetworkUsage() {
        NotificationCenter.default.post(name: .resetTotalNetworkUsage, object: nil, userInfo: nil)
        self.totalUploadField?.stringValue = Units(bytes: 0).getReadableMemory()
        self.totalDownloadField?.stringValue = Units(bytes: 0).getReadableMemory()
        self.lastReset = Date()
    }

    @objc private func resetTotalNetworkUsageCallback() {
        self.lastReset = Date()
    }
}
