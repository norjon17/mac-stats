//
//  notifications.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 25/01/2025
//  Using Swift 6.0
//  Running on macOS 15.1
//
//  Copyright © 2025 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

class Notifications: NotificationsWrapper {
    private let connectionID: String = "connection"
    private let interfaceID: String = "interface"
    private let localID: String = "localIP"
    private let uploadID: String = "upload"
    private let downloadID: String = "download"

    private var connectionState: Bool = false
    private var connectionThreshold: Int = 2
    private var interfaceState: Bool = false
    private var localIPState: Bool = false
    private var uploadState: Bool = false
    private var uploadThreshold: Int = 10
    private var uploadThresholdSize: SizeUnit = .MB
    private var downloadState: Bool = false
    private var downloadThreshold: Int = 10
    private var downloadThresholdSize: SizeUnit = .MB

    private var connection: Bool?
    private var connectionCount: Int = 0
    private var interface: String?
    private var localIP: String?

    private var localIPCount: Int = 0
    private var localIPThreshold: Int = 3

    private var interfaceInit: Bool = false
    private var localIPInit: Bool = false

    public init(_ module: ModuleType) {
        super.init(module, [self.connectionID, self.interfaceID, self.localID, self.uploadID, self.downloadID])

        self.connectionState = Store.shared.bool(key: "\(self.module)_notifications_connection_state", defaultValue: self.connectionState)
        self.connectionThreshold = Store.shared.int(key: "\(self.module)_notifications_connection_threshold", defaultValue: self.connectionThreshold)
        self.interfaceState = Store.shared.bool(key: "\(self.module)_notifications_interface_state", defaultValue: self.interfaceState)
        self.localIPState = Store.shared.bool(key: "\(self.module)_notifications_localIP_state", defaultValue: self.localIPState)
        self.uploadState = Store.shared.bool(key: "\(self.module)_notifications_upload_state", defaultValue: self.uploadState)
        self.uploadThreshold = Store.shared.int(key: "\(self.module)_notifications_upload_threshold", defaultValue: self.uploadThreshold)
        self.uploadThresholdSize = SizeUnit.fromString(Store.shared.string(key: "\(self.module)_notifications_upload_size", defaultValue: self.uploadThresholdSize.key))
        self.downloadState = Store.shared.bool(key: "\(self.module)_notifications_download_state", defaultValue: self.downloadState)
        self.downloadThreshold = Store.shared.int(key: "\(self.module)_notifications_download_threshold", defaultValue: self.downloadThreshold)
        self.downloadThresholdSize = SizeUnit.fromString(Store.shared.string(key: "\(self.module)_notifications_download_size", defaultValue: self.downloadThresholdSize.key))

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Status"), component: PreferencesSwitch(
                action: self.toggleConnectionState, state: self.connectionState, with: StepperInput(
                    self.connectionThreshold, range: NSRange(location: 1, length: 9), visibileUnit: false,
                    callback: self.changeWidgetConnectionThreshold
                )
            )),
            PreferencesRow(localizedString("Network interface"), component: switchView(
                action: #selector(self.toggleInterfaceState),
                state: self.interfaceState
            )),
            PreferencesRow(localizedString("Local IP"), component: switchView(
                action: #selector(self.toggleLocalIPState),
                state: self.localIPState
            ))
        ]))

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Upload speed"), component: PreferencesSwitch(
                action: self.toggleUploadState, state: self.uploadState, with: StepperInput(
                    self.uploadThreshold, range: NSRange(location: 1, length: 1023),
                    unit: self.uploadThresholdSize.key, units: SizeUnit.allCases,
                    callback: self.changeUploadThreshold, unitCallback: self.changeUploadThresholdSize
                )
            )),
            PreferencesRow(localizedString("Download speed"), component: PreferencesSwitch(
                action: self.toggleDownloadState, state: self.downloadState, with: StepperInput(
                    self.downloadThreshold, range: NSRange(location: 1, length: 1023),
                    unit: self.downloadThresholdSize.key, units: SizeUnit.allCases,
                    callback: self.changeDownloadThreshold, unitCallback: self.changeDownloadThresholdSize
                )
            ))
        ]))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal func usageCallback(_ value: Network_Usage) {
        if !self.interfaceInit {
            if let name = value.interface?.BSDName {
                self.interface = name
                self.interfaceInit = true
            }
        }
        if !self.localIPInit {
            if let ip = self.validLocalIP(value.laddr) {
                self.localIP = ip
                self.localIPInit = true
            }
        }

        if self.connectionState {
            self.checkConnection(value.status)
        }

        if self.interfaceState {
            if let name = value.interface?.BSDName, name != self.interface {
                self.newNotification(id: self.interfaceID, title: localizedString("Network interface changed"), subtitle: nil)
                self.interface = name
            }
        }

        if self.localIPState {
            let addr = self.validLocalIP(value.laddr)
            if let addr, addr != self.localIP {
                self.localIPCount += 1
                if self.localIPCount >= self.localIPThreshold {
                    var subtitle = localizedString("New IP", addr)
                    if let prev = self.localIP {
                        subtitle = localizedString("Previous IP", prev) + "\n" + subtitle
                    }
                    self.newNotification(id: self.localID, title: localizedString("Local IP changed"), subtitle: subtitle)
                    self.localIP = addr
                    self.localIPCount = 0
                }
            } else if addr == self.localIP {
                self.localIPCount = 0
            }
        }

        if self.uploadState {
            let threshold = Double(self.uploadThresholdSize.toBytes(self.uploadThreshold))
            let subtitle = "\(localizedString("Upload")): \(Units(bytes: value.bandwidth.upload).getReadableSpeed())"
            self.checkDouble(id: self.uploadID, value: Double(value.bandwidth.upload), threshold: threshold, title: localizedString("Upload speed threshold"), subtitle: subtitle)
        }

        if self.downloadState {
            let threshold = Double(self.downloadThresholdSize.toBytes(self.downloadThreshold))
            let subtitle = "\(localizedString("Download")): \(Units(bytes: value.bandwidth.download).getReadableSpeed())"
            self.checkDouble(id: self.downloadID, value: Double(value.bandwidth.download), threshold: threshold, title: localizedString("Download speed threshold"), subtitle: subtitle)
        }
    }

    private func validLocalIP(_ addr: Network_addr) -> String? {
        if let v4 = addr.v4, !v4.isEmpty {
            return v4
        }
        if let v6 = addr.v6, !v6.isEmpty, !v6.hasPrefix("fe80::") {
            return v6
        }
        return nil
    }

    private func checkConnection(_ status: Bool) {
        if self.connection == nil {
            self.connection = status
            return
        }

        if self.connection != status {
            self.connectionCount += 1
        } else {
            self.connectionCount = 0
        }

        if self.connectionCount >= self.connectionThreshold {
            let title: String = status ? localizedString("Internet connection established") : localizedString("Internet connection lost")
            self.newNotification(id: self.connectionID, title: title, subtitle: nil)
            self.connection = status
            self.connectionCount = 0
        }
    }

    @objc private func toggleConnectionState(_ sender: NSControl) {
        self.connectionState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_connection_state", value: self.connectionState)
    }
    @objc private func changeWidgetConnectionThreshold(_ newValue: Int) {
        self.connectionThreshold = newValue
        Store.shared.set(key: "\(self.module)_notifications_connection_threshold", value: newValue)
    }
    @objc private func toggleInterfaceState(_ sender: NSControl) {
        self.interfaceState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_interface_state", value: self.interfaceState)
    }
    @objc private func toggleLocalIPState(_ sender: NSControl) {
        self.localIPState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_localIP_state", value: self.localIPState)
    }
    @objc private func toggleUploadState(_ sender: NSControl) {
        self.uploadState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_upload_state", value: self.uploadState)
    }
    @objc private func changeUploadThreshold(_ newValue: Int) {
        self.uploadThreshold = newValue
        Store.shared.set(key: "\(self.module)_notifications_upload_threshold", value: newValue)
    }
    private func changeUploadThresholdSize(_ newValue: KeyValue_p) {
        guard let unit = newValue as? SizeUnit else { return }
        self.uploadThresholdSize = unit
        Store.shared.set(key: "\(self.module)_notifications_upload_size", value: unit.key)
    }
    @objc private func toggleDownloadState(_ sender: NSControl) {
        self.downloadState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_download_state", value: self.downloadState)
    }
    @objc private func changeDownloadThreshold(_ newValue: Int) {
        self.downloadThreshold = newValue
        Store.shared.set(key: "\(self.module)_notifications_download_threshold", value: newValue)
    }
    private func changeDownloadThresholdSize(_ newValue: KeyValue_p) {
        guard let unit = newValue as? SizeUnit else { return }
        self.downloadThresholdSize = unit
        Store.shared.set(key: "\(self.module)_notifications_download_size", value: unit.key)
    }
}
