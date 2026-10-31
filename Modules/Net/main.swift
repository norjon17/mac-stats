//
//  main.swift
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
import SystemConfiguration

public enum Network_t: String, Codable {
    case wifi
    case ethernet
    case bluetooth
    case other
}

public struct Network_interface: Codable {
    var status: Bool = false
    var displayName: String = ""
    var BSDName: String = ""
    var address: String = ""
    var transmitRate: Double = 0
}

public struct Network_addr: Codable {
    var v4: String? = nil
    var v6: String? = nil
}

public struct Bandwidth: Codable {
    var upload: Int64 = 0
    var download: Int64 = 0
}

public struct Network_Usage: Codable {
    var bandwidth: Bandwidth = Bandwidth()
    var total: Bandwidth = Bandwidth()

    var laddr: Network_addr = Network_addr() // local ip

    var interface: Network_interface? = nil
    var connectionType: Network_t? = nil
    var status: Bool = false

    mutating func reset() {
        self.bandwidth = Bandwidth()
        self.laddr = Network_addr()
        self.interface = nil
        self.connectionType = nil
    }
}

public class Network: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    private let previewView: Preview

    private var usageReader: UsageReader? = nil

    private var widgetActivationThresholdState: Bool {
        Store.shared.bool(key: "\(self.config.name)_widgetActivationThresholdState", defaultValue: false)
    }
    private var widgetActivationThreshold: Int {
        Store.shared.int(key: "\(self.config.name)_widgetActivationThreshold", defaultValue: 0)
    }
    private var widgetActivationThresholdSize: SizeUnit {
        SizeUnit.fromString(Store.shared.string(key: "\(self.name)_widgetActivationThresholdSize", defaultValue: SizeUnit.MB.key))
    }
    private var textValue: String {
        Store.shared.string(key: "\(self.name)_textWidgetValue", defaultValue: "$addr.private - $status")
    }

    public init() {
        self.settingsView = Settings(.network)
        self.popupView = Popup(.network)
        self.portalView = Portal(.network, height: 90)
        self.notificationsView = Notifications(.network)
        self.previewView = Preview(.network)

        super.init(
            moduleType: .network,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView,
            preview: self.previewView
        )
        guard self.available else { return }

        self.usageReader = UsageReader(.network) { [weak self] value in
            self?.usageCallback(value)
        }

        self.settingsView.callback = { [weak self] in
            self?.usageReader?.refresh()
        }
        self.settingsView.usageResetCallback = { [weak self] in
            self?.setUsageReset()
        }

        self.setReaders([self.usageReader])
        self.setUsageReset()
    }

    public override func isAvailable() -> Bool {
        var list: [String] = []
        for interface in SCNetworkInterfaceCopyAll() as NSArray {
            if let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface as! SCNetworkInterface) {
                list.append(displayName as String)
            }
        }
        return !list.isEmpty
    }

    private func usageCallback(_ raw: Network_Usage?) {
        guard let value = raw, self.enabled else { return }

        self.popupView.usageCallback(value)
        self.portalView.usageCallback(value)
        self.notificationsView.usageCallback(value)
        self.previewView.usageCallback(value)

        var upload: Int64 = value.bandwidth.upload
        var download: Int64 = value.bandwidth.download
        if self.widgetActivationThresholdState {
            upload = 0
            download = 0
            let threshold = self.widgetActivationThresholdSize.toBytes(self.widgetActivationThreshold)
            if value.bandwidth.upload >= threshold || value.bandwidth.download >= threshold {
                upload = value.bandwidth.upload
                download = value.bandwidth.download
            }
        }

        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as SpeedWidget: widget.setValue(input: download, output: upload)
            case let widget as NetworkChart: widget.setValue(upload: Double(upload), download: Double(download))
            case let widget as DotWidget:
                let color = value.status ? SColor.secondGreen : SColor.secondRed
                widget.setValue(color.additional as? NSColor ?? .systemGray)
            case let widget as TextWidget:
                var text = self.textValue
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$addr":
                        switch pair.value {
                        case "private": replacement = value.laddr.v4 ?? value.laddr.v6 ?? "-"
                        case "privateV4": replacement = value.laddr.v4 ?? "-"
                        case "privateV6": replacement = value.laddr.v6 ?? "-"
                        default: return
                        }
                    case "$interface":
                        switch pair.value {
                        case "displayName": replacement = value.interface?.displayName ?? "-"
                        case "BSDName": replacement = value.interface?.BSDName ?? "-"
                        case "address": replacement = value.interface?.address ?? "-"
                        case "transmitRate": replacement = "\(value.interface?.transmitRate ?? 0)"
                        default: return
                        }
                    case "$status":
                        replacement = localizedString(value.status ? "UP" : "DOWN")
                    case "$upload":
                        switch pair.value {
                        case "total": replacement = Units(bytes: value.total.upload).getReadableMemory()
                        default: replacement = Units(bytes: value.bandwidth.upload).getReadableMemory()
                        }
                    case "$download":
                        switch pair.value {
                        case "total": replacement = Units(bytes: value.total.download).getReadableMemory()
                        default: replacement = Units(bytes: value.bandwidth.download).getReadableMemory()
                        }
                    case "$type":
                        replacement = value.connectionType?.rawValue ?? "-"
                    default: return
                    }

                    if let replacement {
                        let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                        text = text.replacingOccurrences(of: key, with: replacement)
                    }
                }
                widget.setValue(text)
            default: break
            }
        }
    }

    private func setUsageReset() {
        if AppUpdateInterval(rawValue: Store.shared.string(key: "\(self.config.name)_usageReset", defaultValue: AppUpdateInterval.never.rawValue)) == .atStart {
            NotificationCenter.default.post(name: .resetTotalNetworkUsage, object: nil, userInfo: nil)
        }
    }
}
