//
//  readers.swift
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

internal class UsageReader: Reader<Network_Usage> {
    private var reachability: Reachability = Reachability(start: true)
    private let variablesQueue = DispatchQueue(label: "eu.exelban.NetworkUsageReader")
    private var _usage: Network_Usage = Network_Usage()
    public var usage: Network_Usage {
        get { self.variablesQueue.sync { self._usage } }
        set { self.variablesQueue.sync { self._usage = newValue } }
    }

    private let virtualInterfacePrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "wg"]

    /// Interval for every lookup that leaves the process (configd / SystemConfiguration / CFNetwork).
    private let cacheTTL: TimeInterval = 15

    // primary-interface autodetection cache (SCDynamicStoreCopyValue is a configd XPC call)
    private var _cachedPrimaryInterface: String = ""
    private var _primaryInterfaceTS: Date = .distantPast

    // VPN detection cache (CFNetworkCopySystemProxySettings is a configd XPC call)
    private var _cachedVPNConnection: Bool = false
    private var _vpnConnectionTS: Date = .distantPast

    private var lastInterfaceID: String = ""

    // inbound-source fallback (see routeStats.swift): the ifnet inbound counters can be dead
    // while a transparent-proxy system extension owns the receive path.
    private var inboundSourceSetting: String = "auto"
    private var routeStats: RouteStatsReader? = nil
    private var routeInboundActive: Bool = false
    private var deadInboundTicks: Int = 0
    private var lastRawCounters: Bandwidth? = nil
    private let deadInboundTickThreshold = 5

    private var VPNMode: Bool {
        get { Store.shared.bool(key: "Network_VPNMode", defaultValue: false) }
    }

    private var usageResetInterval: AppUpdateInterval? {
        AppUpdateInterval(rawValue: Store.shared.string(key: "Network_usageReset", defaultValue: AppUpdateInterval.never.rawValue))
    }
    private var nextUsageResetDate: Date? {
        get {
            let ts = Store.shared.int(key: "Network_usageReset_next", defaultValue: 0)
            return ts == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(ts))
        }
        set {
            if let newValue {
                Store.shared.set(key: "Network_usageReset_next", value: Int(newValue.timeIntervalSince1970))
            } else {
                Store.shared.remove("Network_usageReset_next")
            }
        }
    }

    private var lastDetailsReadTS: Date = .distantPast

    private let detailsQueue = DispatchQueue(label: "eu.exelban.NetworkDetailsReader")
    private var _detailsInProgress: Bool = false
    private var detailsInProgress: Bool {
        get { self.variablesQueue.sync { self._detailsInProgress } }
        set { self.variablesQueue.sync { self._detailsInProgress = newValue } }
    }

    // MARK: - lifecycle

    public override func setup() {
        self.reachability.reachable = { [weak self] in
            guard let self, self.active else { return }
            self.invalidateCaches()
            self.requestDetails(self.currentInterfaceID())
        }
        self.reachability.unreachable = { [weak self] in
            guard let self, self.active else { return }
            self.usage.reset()
            self.callback(self.usage)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(resetTotalNetworkUsage), name: .resetTotalNetworkUsage, object: nil)

        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.active else { return }
            self.requestDetails(self.currentInterfaceID())
        }

        if let usage = self.value {
            self.usage = usage
            self.usage.bandwidth = Bandwidth()
        }

        self.checkUsageReset()
    }

    public override func terminate() {
        self.reachability.stop()
        self.reachability.reachable = {}
        self.reachability.unreachable = {}
        NotificationCenter.default.removeObserver(self, name: .resetTotalNetworkUsage, object: nil)
        self.routeStats?.stop()
    }

    /// Called from settings when the interface selection changes: drop every cache and re-read immediately.
    public func refresh() {
        self.invalidateCaches()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.read()
        }
    }

    private func invalidateCaches() {
        self.variablesQueue.sync {
            self._primaryInterfaceTS = .distantPast
            self._vpnConnectionTS = .distantPast
        }
        self.lastDetailsReadTS = .distantPast
    }

    // MARK: - per-tick read

    public override func read() {
        self.checkUsageReset()

        // Store is read exactly once per tick; autodetection only runs when no interface is pinned.
        let interfaceID = self.currentInterfaceID()
        if interfaceID != self.lastInterfaceID {
            self.lastInterfaceID = interfaceID
            self.variablesQueue.sync {
                self._usage.bandwidth = Bandwidth()
                self._usage.interface = nil
                self._usage.connectionType = nil
                self._usage.laddr = Network_addr()
            }
            self.lastDetailsReadTS = .distantPast
            self.resetInboundSource()
        }

        self.requestDetails(interfaceID)

        // single sysctl: byte counters, link flags and negotiated link rate come from the same buffer
        let sample = self.readInterfaceCounters(interfaceID)
        var current = sample?.bandwidth ?? Bandwidth()
        if let sample, self.useRouteInbound(sample.bandwidth, interfaceID) {
            current.download = self.routeStats?.counters(interface: interfaceID)?.rx ?? 0
        }

        self.variablesQueue.sync {
            guard let sample, self._usage.interface?.BSDName == interfaceID else { return }
            self._usage.interface?.status = sample.status
            if sample.transmitRate > 0 {
                self._usage.interface?.transmitRate = sample.transmitRate
            }
        }

        // allows to reset the value to 0 when first read
        if self.usage.bandwidth.upload != 0 {
            self.usage.bandwidth.upload = current.upload - self.usage.bandwidth.upload
        }
        if self.usage.bandwidth.download != 0 {
            self.usage.bandwidth.download = current.download - self.usage.bandwidth.download
        }

        self.usage.bandwidth.upload = max(self.usage.bandwidth.upload, 0) // prevent negative upload value
        self.usage.bandwidth.download = max(self.usage.bandwidth.download, 0) // prevent negative download value

        // drop one-shot counter jumps that no link can deliver (100 Gbps). The negotiated link
        // rate must NOT be used here: Wi-Fi reports a PHY rate that real throughput can exceed.
        let interval = self.interval ?? 1
        let maxDelta = Int64(12_500_000_000 * interval)
        if self.usage.bandwidth.upload > maxDelta { self.usage.bandwidth.upload = 0 }
        if self.usage.bandwidth.download > maxDelta { self.usage.bandwidth.download = 0 }

        self.usage.total.upload += self.usage.bandwidth.upload
        self.usage.total.download += self.usage.bandwidth.download

        self.usage.status = self.reachability.isReachable

        // VPNMode is a plain Store read; the proxy lookup only runs when the option is on, and at most once per cacheTTL
        if self.VPNMode && self.vpnConnection() {
            self.usage.bandwidth.upload /= 2
            self.usage.bandwidth.download /= 2
        }

        self.callback(self.usage)

        self.usage.bandwidth.upload = current.upload
        self.usage.bandwidth.download = current.download

        if self.routeInboundActive {
            self.routeStats?.poll() // result lands in the snapshot before the next tick
        }
    }

    // MARK: - inbound source selection

    private var storedInboundSource: String {
        Store.shared.string(key: "Network_inboundSource", defaultValue: "auto")
    }

    private func resetInboundSource() {
        self.routeInboundActive = false
        self.deadInboundTicks = 0
        self.lastRawCounters = nil
        self.routeStats?.stop()
    }

    /// Decides where this tick's download counter comes from. Returns true when the route
    /// statistics replace the (dead) ifnet inbound counter; `raw` are the sysctl values.
    private func useRouteInbound(_ raw: Bandwidth, _ interfaceID: String) -> Bool {
        let setting = self.storedInboundSource
        if setting != self.inboundSourceSetting {
            self.inboundSourceSetting = setting
            self.resetInboundSource()
        }

        switch setting {
        case "interface":
            return false
        case "route":
            if !self.routeInboundActive {
                self.activateRouteInbound(interfaceID, reason: "selected in settings")
            }
            return self.routeInboundActive
        default:
            break
        }

        if self.routeInboundActive {
            return true
        }

        defer { self.lastRawCounters = raw }
        var dead = raw.download == 0 && raw.upload > 0 // nothing received since boot while sending works
        if !dead, let last = self.lastRawCounters {
            if raw.download == last.download && raw.upload > last.upload {
                self.deadInboundTicks += 1
                dead = self.deadInboundTicks >= self.deadInboundTickThreshold
            } else {
                self.deadInboundTicks = 0
            }
        }
        if dead {
            self.activateRouteInbound(interfaceID, reason: "inbound interface counters are dead")
        }
        return self.routeInboundActive
    }

    private func activateRouteInbound(_ interfaceID: String, reason: String) {
        guard RouteStatsReader.isAvailable else {
            // nothing better than the dead counter: stay on sysctl, stop re-evaluating
            self.deadInboundTicks = 0
            self.lastRawCounters = nil
            return
        }
        if self.routeStats == nil {
            self.routeStats = RouteStatsReader()
        }
        guard let routeStats = self.routeStats, routeStats.start() else { return }

        self.routeInboundActive = true
        self.deadInboundTicks = 0
        // the stored counter now refers to a different source: skip one delta (shows 0 for a tick)
        self.usage.bandwidth.download = 0
        routeStats.poll()
        self.log.log(level: .info, message: "\(reason) on \(interfaceID), using route statistics for download")
    }

    // MARK: - interface selection

    private func currentInterfaceID() -> String {
        let stored = Store.shared.string(key: "Network_interface", defaultValue: "")
        if !stored.isEmpty {
            return stored
        }
        return self.primaryInterface()
    }

    private func primaryInterface() -> String {
        let now = Date()
        let cached: String? = self.variablesQueue.sync {
            now.timeIntervalSince(self._primaryInterfaceTS) < self.cacheTTL ? self._cachedPrimaryInterface : nil
        }
        if let cached {
            return cached
        }

        var name = ""
        if let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString), let primary = global["PrimaryInterface"] as? String {
            name = primary
            if self.isVirtualInterface(primary), let physical = self.physicalInterface() {
                name = physical
            }
        }

        self.variablesQueue.sync {
            self._cachedPrimaryInterface = name
            self._primaryInterfaceTS = now
        }
        return name
    }

    private func isVirtualInterface(_ name: String) -> Bool {
        return self.virtualInterfacePrefixes.contains(where: { name.hasPrefix($0) })
    }

    private func physicalInterface() -> String? {
        if let setup = SCDynamicStoreCopyValue(nil, "Setup:/Network/Global/IPv4" as CFString), let order = setup["ServiceOrder"] as? [String] {
            for serviceID in order {
                guard let service = SCDynamicStoreCopyValue(nil, "State:/Network/Service/\(serviceID)/IPv4" as CFString) as? [String: Any],
                      service["Router"] != nil, let name = service["InterfaceName"] as? String, !self.isVirtualInterface(name) else {
                    continue
                }
                return name
            }
        }

        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&interfaceAddresses) == 0 else { return nil }
        defer { freeifaddrs(interfaceAddresses) }

        var pointer = interfaceAddresses
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let name = String(cString: current.pointee.ifa_name)
            if !self.isVirtualInterface(name) {
                return name
            }
        }

        return nil
    }

    private func vpnConnection() -> Bool {
        let now = Date()
        let cached: Bool? = self.variablesQueue.sync {
            now.timeIntervalSince(self._vpnConnectionTS) < self.cacheTTL ? self._cachedVPNConnection : nil
        }
        if let cached {
            return cached
        }

        var result = false
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any], let scopes = settings["__SCOPED__"] as? [String: Any] {
            result = !scopes.filter({ $0.key.contains("tap") || $0.key.contains("tun") || $0.key.contains("ppp") || $0.key.contains("ipsec") }).isEmpty
        }

        self.variablesQueue.sync {
            self._cachedVPNConnection = result
            self._vpnConnectionTS = now
        }
        return result
    }

    // MARK: - counters (one sysctl per tick, no XPC)

    private struct InterfaceSample {
        let bandwidth: Bandwidth
        let status: Bool
        let transmitRate: Double // Mbps, 0 when unknown
    }

    private func readInterfaceCounters(_ interfaceID: String) -> InterfaceSample? {
        let index = if_nametoindex(interfaceID)
        guard index != 0 else { return nil }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var size: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }

        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            var header = if_msghdr()
            buffer.withUnsafeBytes { src in
                _ = memcpy(&header, src.baseAddress?.advanced(by: offset), MemoryLayout<if_msghdr>.size)
            }
            guard header.ifm_msglen > 0 else { return nil }

            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= size {
                var header2 = if_msghdr2()
                buffer.withUnsafeBytes { src in
                    _ = memcpy(&header2, src.baseAddress?.advanced(by: offset), MemoryLayout<if_msghdr2>.size)
                }
                if UInt32(header2.ifm_index) == index {
                    let baud = UInt64(header2.ifm_data.ifi_baudrate)
                    let transmitRate = (baud > 0 && baud < UInt64(UInt32.max)) ? Double(baud) / 1_000_000.0 : 0
                    return InterfaceSample(
                        bandwidth: Bandwidth(
                            upload: Int64(clamping: header2.ifm_data.ifi_obytes),
                            download: Int64(clamping: header2.ifm_data.ifi_ibytes)
                        ),
                        status: (header2.ifm_flags & IFF_UP) != 0,
                        transmitRate: transmitRate
                    )
                }
            }

            offset += Int(header.ifm_msglen)
        }

        return nil
    }

    // MARK: - details (SystemConfiguration + getifaddrs, at most once per cacheTTL)

    private func requestDetails(_ interfaceID: String) {
        guard interfaceID != "", !self.detailsInProgress else { return }
        if Date().timeIntervalSince(self.lastDetailsReadTS) < self.cacheTTL { return }

        self.detailsInProgress = true
        self.detailsQueue.async { [weak self] in
            guard let self else { return }
            self.getDetails(interfaceID)
            self.detailsInProgress = false
        }
    }

    private func getDetails(_ interfaceID: String) {
        guard interfaceID != "" else { return }

        var found = false
        var displayName = ""
        var address = ""
        var connectionType: Network_t = .other
        var mediaRate: Double? = nil

        for interface in SCNetworkInterfaceCopyAll() as NSArray {
            let interface = interface as! SCNetworkInterface
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface), bsdName as String == interfaceID,
                  let type = SCNetworkInterfaceGetInterfaceType(interface),
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface),
                  let mac = SCNetworkInterfaceGetHardwareAddressString(interface) else {
                continue
            }

            found = true
            displayName = name as String
            address = mac as String

            switch type {
            case kSCNetworkInterfaceTypeEthernet:
                connectionType = .ethernet
                mediaRate = self.ethernetMediaRate(interface)
            case kSCNetworkInterfaceTypeIEEE80211, kSCNetworkInterfaceTypeWWAN:
                connectionType = .wifi
            case kSCNetworkInterfaceTypeBluetooth:
                connectionType = .bluetooth
            default:
                connectionType = .other
            }
            break
        }

        guard found else {
            self.variablesQueue.sync {
                self._usage.interface = nil
                self._usage.connectionType = nil
                self._usage.laddr = Network_addr()
            }
            self.lastDetailsReadTS = Date()
            return
        }

        let laddr = self.localAddresses(interfaceID)

        self.variablesQueue.sync {
            if self._usage.interface?.BSDName != interfaceID {
                self._usage.interface = Network_interface(BSDName: interfaceID)
            }
            self._usage.interface?.displayName = displayName
            self._usage.interface?.address = address
            if let mediaRate, mediaRate > 0, (self._usage.interface?.transmitRate ?? 0) == 0 {
                self._usage.interface?.transmitRate = mediaRate
            }
            self._usage.connectionType = connectionType
            self._usage.laddr = laddr
        }

        self.lastDetailsReadTS = Date()
    }

    private func ethernetMediaRate(_ interface: SCNetworkInterface) -> Double? {
        var active: Unmanaged<CFDictionary>?
        guard SCNetworkInterfaceCopyMediaOptions(interface, nil, &active, nil, false),
              let media = active?.takeRetainedValue() as? [String: Any],
              let subType = media[kSCPropNetEthernetMediaSubType as String] as? String else {
            return nil
        }
        return self.ethernetTransmitRate(from: subType)
    }

    private func ethernetTransmitRate(from mediaSubType: String) -> Double? {
        let components = mediaSubType.lowercased().components(separatedBy: "base")
        guard components.count == 2, !components[1].isEmpty else { return nil }

        let gigabits = components[0].hasSuffix("g")
        let value = gigabits ? String(components[0].dropLast()) : components[0]
        guard let rate = Double(value), rate.isFinite, rate > 0 else { return nil }

        return rate * (gigabits ? 1_000 : 1)
    }

    private func localAddresses(_ interfaceID: String) -> Network_addr {
        var result = Network_addr()

        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&interfaceAddresses) == 0 else { return result }
        defer { freeifaddrs(interfaceAddresses) }

        var pointer = interfaceAddresses
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard String(cString: current.pointee.ifa_name) == interfaceID, let ifaAddr = current.pointee.ifa_addr else { continue }
            let family = ifaAddr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var ip = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len), &ip, socklen_t(ip.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 else { continue }

            let ipStr = String(cString: ip)
            guard !ipStr.isEmpty else { continue }

            if family == UInt8(AF_INET) {
                if result.v4 == nil {
                    result.v4 = ipStr
                }
            } else if result.v6 == nil || ((result.v6?.hasPrefix("fe80") ?? false) && !ipStr.hasPrefix("fe80")) {
                result.v6 = ipStr // prefer a routable v6 over the link-local one
            }
        }

        return result
    }

    // MARK: - usage reset

    private func nextUsageReset(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self.usageResetInterval {
        case .oncePerDay:
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))
        case .oncePerWeek:
            guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
            return cal.date(byAdding: .weekOfYear, value: 1, to: start)
        case .oncePerMonth:
            guard let start = cal.dateInterval(of: .month, for: date)?.start else { return nil }
            return cal.date(byAdding: .month, value: 1, to: start)
        default:
            return nil
        }
    }

    private func checkUsageReset() {
        switch self.usageResetInterval {
        case .oncePerDay, .oncePerWeek, .oncePerMonth: break
        default: return
        }

        guard let next = self.nextUsageResetDate else {
            self.nextUsageResetDate = self.nextUsageReset(after: Date())
            return
        }

        if Date() >= next {
            self.resetTotalNetworkUsage()
        }
    }

    @objc func resetTotalNetworkUsage() {
        self.usage.total = Bandwidth()
        self.value = self.usage
        self.nextUsageResetDate = self.nextUsageReset(after: Date())
    }
}
