//
//  preview.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/05/2026
//  Using Swift 6.0
//  Running on macOS 26.4
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Preview: PreviewWrapper {
    private var chart: NetworkChartView? = nil

    private var downloadValueField: NSTextField? = nil
    private var downloadUnitField: NSTextField? = nil
    private var downloadStateView: ColorView? = nil

    private var uploadValueField: NSTextField? = nil
    private var uploadUnitField: NSTextField? = nil
    private var uploadStateView: ColorView? = nil

    private var totalUploadField: ValueField? = nil
    private var totalDownloadField: ValueField? = nil
    private var statusField: StatusBadgeView? = nil
    private var localIPField: ValueField? = nil

    private var interfaceField: ValueField? = nil
    private var interfaceStatusField: StatusBadgeView? = nil
    private var macAddressField: ValueField? = nil
    private var connectionTypeField: ValueField? = nil
    private var speedField: ValueField? = nil

    private var initialized: Bool = false

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

    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.module.stringValue)_base", defaultValue: "byte")) ?? .byte
    }
    private var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(self.module.stringValue)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }

    public init(_ module: ModuleType) {
        super.init(type: module)

        self.loadColors()

        self.addArrangedSubview(PreferencesSection([self.usageView()]))
        self.addArrangedSubview(PreferencesSection([self.historyView()]))

        let splitView = NSStackView()
        splitView.orientation = .horizontal
        splitView.distribution = .fillEqually
        splitView.alignment = .top
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("Details"), [self.detailsView()]))
        splitView.addArrangedSubview(PreferencesSection(title: localizedString("Interface"), [self.interfaceView()]))

        self.addArrangedSubview(splitView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadColors() {
        self.downloadColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_downloadColor", defaultValue: self.downloadColorState.key))
        self.uploadColorState = SColor.fromString(Store.shared.string(key: "\(self.module.stringValue)_uploadColor", defaultValue: self.uploadColorState.key))
    }

    private func usageView() -> NSView {
        let view = NSStackView()
        view.distribution = .fillEqually
        view.orientation = .horizontal
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 90).isActive = true
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        view.spacing = Constants.Settings.margin

        let download = self.usageValueView(title: localizedString("Downloading"), color: self.downloadColor)
        let upload = self.usageValueView(title: localizedString("Uploading"), color: self.uploadColor)

        self.downloadValueField = download.1
        self.downloadUnitField = download.2
        self.downloadStateView = download.3

        self.uploadValueField = upload.1
        self.uploadUnitField = upload.2
        self.uploadStateView = upload.3

        view.addArrangedSubview(download.0)
        view.addArrangedSubview(upload.0)

        return view
    }

    private func historyView() -> NSView {
        let view: NSStackView = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Settings.margin*2
        view.heightAnchor.constraint(equalToConstant: 140).isActive = true

        let chart = NetworkChartView(num: 600)
        self.chart = chart
        chart.setColors(in: self.downloadColor, out: self.uploadColor)
        chart.setLegend(x: true, y: false)
        view.addArrangedSubview(chart)

        return view
    }

    private func detailsView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = 2

        self.totalUploadField = previewRow(view, color: self.uploadColor, title: "\(localizedString("Total upload")):", value: "0")
        self.totalDownloadField = previewRow(view, color: self.downloadColor, title: "\(localizedString("Total download")):", value: "0")
        self.statusField = previewBadgeRow(view, title: "\(localizedString("Status")):")
        self.localIPField = previewRow(view, title: "\(localizedString("Local IP")):", value: localizedString("Unknown"))
        self.localIPField?.isSelectable = true

        return view
    }

    private func interfaceView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = 2

        self.interfaceField = previewRow(view, title: "\(localizedString("Interface")):", value: localizedString("Unknown"))
        self.interfaceStatusField = previewBadgeRow(view, title: "\(localizedString("Status")):")
        self.connectionTypeField = previewRow(view, title: "\(localizedString("Connection type")):", value: localizedString("Unknown"))
        self.macAddressField = previewRow(view, title: "\(localizedString("Physical address")):", value: localizedString("Unknown"))
        self.macAddressField?.isSelectable = true
        self.speedField = previewRow(view, title: "\(localizedString("Speed")):", value: localizedString("Unknown"))

        return view
    }

    public func usageCallback(_ value: Network_Usage) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                let upload = Units(bytes: value.bandwidth.upload).getReadableTuple(base: self.base, unit: self.speedUnit)
                let download = Units(bytes: value.bandwidth.download).getReadableTuple(base: self.base, unit: self.speedUnit)

                self.uploadValueField?.stringValue = "\(upload.0)"
                self.uploadUnitField?.stringValue = upload.1

                self.downloadValueField?.stringValue = "\(download.0)"
                self.downloadUnitField?.stringValue = download.1

                self.uploadStateView?.setState(value.bandwidth.upload != 0)
                self.downloadStateView?.setState(value.bandwidth.download != 0)

                self.totalUploadField?.stringValue = Units(bytes: value.total.upload).getReadableMemory()
                self.totalDownloadField?.stringValue = Units(bytes: value.total.download).getReadableMemory()

                self.statusField?.setStatus(value.status)

                if let interface = value.interface {
                    self.interfaceField?.stringValue = "\(interface.displayName) (\(interface.BSDName))"
                    self.interfaceStatusField?.setStatus(interface.status)
                    self.macAddressField?.stringValue = interface.address
                    self.speedField?.stringValue = interface.transmitRate > 0 ? "\(Int(interface.transmitRate.rounded())) Mbps" : localizedString("Unknown")
                } else {
                    self.interfaceField?.stringValue = localizedString("Unknown")
                    self.interfaceStatusField?.setStatus(nil)
                    self.macAddressField?.stringValue = localizedString("Unknown")
                    self.speedField?.stringValue = localizedString("Unknown")
                }

                self.connectionTypeField?.stringValue = value.connectionType?.rawValue.capitalized ?? localizedString("Unknown")

                var localIP = localizedString("Unknown")
                if let v4 = value.laddr.v4, !v4.isEmpty {
                    localIP = v4
                } else if let v6 = value.laddr.v6, !v6.isEmpty {
                    localIP = v6
                }
                self.localIPField?.stringValue = localIP

                self.initialized = true
            }

            if let chart = self.chart {
                chart.setBase(self.base)
                chart.setSpeedUnit(self.speedUnit)
                chart.addValue(upload: Double(value.bandwidth.upload), download: Double(value.bandwidth.download))
            }
        })
    }

    // MARK: - helpers

    private func usageValueView(title: String, color: NSColor) -> (NSView, NSTextField, NSTextField, ColorView) {
        let view = NSView()

        let container = NSStackView()
        container.distribution = .fill
        container.orientation = .vertical
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSStackView()
        valueView.distribution = .fill
        valueView.orientation = .horizontal
        valueView.alignment = .lastBaseline
        valueView.spacing = 0
        valueView.translatesAutoresizingMaskIntoConstraints = false

        let valueField = LabelField()
        valueField.font = NSFont.systemFont(ofSize: 26, weight: .light)
        valueField.textColor = .textColor
        valueField.alignment = .right
        valueField.stringValue = "0"

        let unitField = LabelField()
        unitField.font = NSFont.systemFont(ofSize: 13, weight: .light)
        unitField.textColor = .labelColor
        unitField.alignment = .left
        unitField.stringValue = "KB/s"

        valueView.addArrangedSubview(valueField)
        valueView.addArrangedSubview(unitField)

        let labelView = NSStackView()
        labelView.distribution = .fill
        labelView.orientation = .horizontal
        labelView.spacing = 0
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let colorBlock: ColorView = ColorView(frame: NSRect(x: 0, y: 0, width: 12, height: 12), color: color, radius: 4)
        colorBlock.widthAnchor.constraint(equalToConstant: 12).isActive = true
        colorBlock.heightAnchor.constraint(equalToConstant: 12).isActive = true
        let titleField = LabelField(title)
        titleField.alignment = .center

        labelView.addArrangedSubview(colorBlock)
        labelView.addArrangedSubview(titleField)

        container.addArrangedSubview(valueView)
        container.addArrangedSubview(labelView)

        view.addSubview(container)

        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return (view, valueField, unitField, colorBlock)
    }
}
