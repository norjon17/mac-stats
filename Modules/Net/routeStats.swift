//
//  routeStats.swift
//  Net
//
//  Fallback byte counters built on the private NetworkStatistics framework (the provider
//  behind `nettop -m route`). Used when the per-interface ifnet counters stop moving, which
//  happens on macOS 26 when a transparent-proxy system extension (e.g. an antivirus) takes
//  over the inbound path: ifi_ibytes stays at 0 while the route statistics keep counting.
//
//  The framework is loaded with dlopen/dlsym so there is no link-time dependency; when it is
//  missing or any symbol is absent the reader simply reports nothing.
//
//  Route sources form a tree: cloned host routes report their bytes into their parent
//  (the default route, the link route, ...), so only top-level routes (parentID == 0) are
//  kept; every child is removed as soon as its description arrives. That keeps the manager
//  at ~50 sources instead of ~1300 and one update query at well under 1 ms of CPU.
//

import Foundation

internal final class RouteStatsReader {
    private typealias Ref = UnsafeMutableRawPointer
    private typealias ManagerCallback = @convention(block) (Ref?, UnsafeMutableRawPointer?) -> Void
    private typealias DictBlock = @convention(block) (CFDictionary?) -> Void
    private typealias VoidBlock = @convention(block) () -> Void

    private struct API {
        let managerCreate: @convention(c) (CFAllocator?, DispatchQueue, @escaping ManagerCallback) -> Ref?
        let managerDestroy: @convention(c) (Ref) -> Void
        let addAllRoutes: @convention(c) (Ref) -> Int32
        let queryAllSourcesUpdate: @convention(c) (Ref, @escaping VoidBlock) -> Int32
        let setDescriptionBlock: @convention(c) (Ref, @escaping DictBlock) -> Void
        let setCountsBlock: @convention(c) (Ref, @escaping DictBlock) -> Void
        let setRemovedBlock: @convention(c) (Ref, @escaping VoidBlock) -> Void
        let sourceRemove: @convention(c) (Ref) -> Void

        let keyRxBytes: CFString
        let keyTxBytes: CFString
        let keyInterface: CFString
        let keyRouteParentID: CFString

        static func load() -> API? {
            guard let handle = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics", RTLD_NOW) else {
                return nil
            }
            func fn<T>(_ name: String, _ type: T.Type) -> T? {
                guard let symbol = dlsym(handle, name) else { return nil }
                return unsafeBitCast(symbol, to: type)
            }
            func key(_ name: String) -> CFString? {
                guard let symbol = dlsym(handle, name) else { return nil }
                return symbol.assumingMemoryBound(to: Unmanaged<CFString>.self).pointee.takeUnretainedValue()
            }
            guard let managerCreate = fn("NStatManagerCreate", (@convention(c) (CFAllocator?, DispatchQueue, @escaping ManagerCallback) -> Ref?).self),
                  let managerDestroy = fn("NStatManagerDestroy", (@convention(c) (Ref) -> Void).self),
                  let addAllRoutes = fn("NStatManagerAddAllRoutes", (@convention(c) (Ref) -> Int32).self),
                  let queryAllSourcesUpdate = fn("NStatManagerQueryAllSourcesUpdate", (@convention(c) (Ref, @escaping VoidBlock) -> Int32).self),
                  let setDescriptionBlock = fn("NStatSourceSetDescriptionBlock", (@convention(c) (Ref, @escaping DictBlock) -> Void).self),
                  let setCountsBlock = fn("NStatSourceSetCountsBlock", (@convention(c) (Ref, @escaping DictBlock) -> Void).self),
                  let setRemovedBlock = fn("NStatSourceSetRemovedBlock", (@convention(c) (Ref, @escaping VoidBlock) -> Void).self),
                  let sourceRemove = fn("NStatSourceRemove", (@convention(c) (Ref) -> Void).self),
                  let keyRxBytes = key("kNStatSrcKeyRxBytes"),
                  let keyTxBytes = key("kNStatSrcKeyTxBytes"),
                  let keyInterface = key("kNStatSrcKeyInterface"),
                  let keyRouteParentID = key("kNStatSrcKeyRouteParentID") else {
                return nil
            }
            return API(
                managerCreate: managerCreate, managerDestroy: managerDestroy, addAllRoutes: addAllRoutes,
                queryAllSourcesUpdate: queryAllSourcesUpdate, setDescriptionBlock: setDescriptionBlock,
                setCountsBlock: setCountsBlock, setRemovedBlock: setRemovedBlock, sourceRemove: sourceRemove,
                keyRxBytes: keyRxBytes, keyTxBytes: keyTxBytes, keyInterface: keyInterface, keyRouteParentID: keyRouteParentID
            )
        }
    }

    private static let api: API? = API.load()

    /// False when the private framework (or one of the symbols used here) is not present.
    public static var isAvailable: Bool { api != nil }

    private struct Counts {
        var ifindex: UInt32
        var rx: UInt64
        var tx: UInt64
    }

    /// Every NStat callback and all mutable state below runs on this serial queue.
    private let queue = DispatchQueue(label: "eu.exelban.NetworkRouteStats")
    private var manager: Ref? = nil
    private var sources: [Ref: Counts] = [:]
    private var retired: [UInt32: (rx: UInt64, tx: UInt64)] = [:]
    private var updateInFlight: Bool = false

    /// Latest per-ifindex totals, rebuilt after every completed update; read by `counters` without blocking on the queue.
    private let snapshotLock = NSLock()
    private var snapshot: [UInt32: (rx: Int64, tx: Int64)] = [:]

    deinit {
        self.stop()
    }

    public var isRunning: Bool {
        self.queue.sync { self.manager != nil }
    }

    /// Creates the manager and subscribes to all route sources. Returns false when the framework is unavailable.
    @discardableResult
    public func start() -> Bool {
        guard let api = RouteStatsReader.api else { return false }
        return self.queue.sync {
            if self.manager != nil { return true }

            let callback: ManagerCallback = { [weak self] source, _ in
                guard let self, let source else { return }
                self.attach(source, api)
            }
            guard let manager = api.managerCreate(nil, self.queue, callback) else { return false }
            guard api.addAllRoutes(manager) != 0 else {
                api.managerDestroy(manager)
                return false
            }

            self.manager = manager
            self.sources = [:]
            self.retired = [:]
            self.updateInFlight = false
            self.snapshotLock.lock()
            self.snapshot = [:]
            self.snapshotLock.unlock()
            return true
        }
    }

    public func stop() {
        guard let api = RouteStatsReader.api else { return }
        let manager: Ref? = self.queue.sync {
            let m = self.manager
            self.manager = nil
            self.sources = [:]
            self.retired = [:]
            self.updateInFlight = false
            return m
        }
        if let manager {
            api.managerDestroy(manager)
        }
        self.snapshotLock.lock()
        self.snapshot = [:]
        self.snapshotLock.unlock()
    }

    /// Asks the kernel for fresh counts of every subscribed source. Non-blocking: the snapshot is
    /// refreshed on the reader queue once the update completes, typically within a millisecond.
    public func poll() {
        guard let api = RouteStatsReader.api else { return }
        self.queue.async { [weak self] in
            guard let self, let manager = self.manager, !self.updateInFlight else { return }
            self.updateInFlight = true
            let rc = api.queryAllSourcesUpdate(manager) { [weak self] in
                guard let self else { return }
                self.queue.async {
                    self.updateInFlight = false
                    self.rebuildSnapshot()
                }
            }
            if rc == 0 {
                self.updateInFlight = false
            }
        }
    }

    /// Latest totals (bytes since boot for live routes, plus everything retired routes had reported)
    /// over all top-level routes bound to `interface`. nil when nothing has been received for it yet.
    public func counters(interface: String) -> (rx: Int64, tx: Int64)? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        self.snapshotLock.lock()
        defer { self.snapshotLock.unlock() }
        return self.snapshot[index]
    }

    // MARK: - queue-only helpers

    private func attach(_ source: Ref, _ api: API) {
        let handler: DictBlock = { [weak self] dictionary in
            guard let self, let dictionary, self.manager != nil else { return }
            let parent = RouteStatsReader.number(dictionary, api.keyRouteParentID)
            if parent != 0 {
                // cloned host route: its bytes are already accounted in the parent
                self.sources[source] = nil
                api.sourceRemove(source)
                return
            }
            self.sources[source] = Counts(
                ifindex: UInt32(truncatingIfNeeded: RouteStatsReader.number(dictionary, api.keyInterface)),
                rx: RouteStatsReader.number(dictionary, api.keyRxBytes),
                tx: RouteStatsReader.number(dictionary, api.keyTxBytes)
            )
        }
        api.setDescriptionBlock(source, handler)
        api.setCountsBlock(source, handler)
        api.setRemovedBlock(source) { [weak self] in
            guard let self, let last = self.sources.removeValue(forKey: source) else { return }
            var acc = self.retired[last.ifindex] ?? (0, 0)
            acc.rx &+= last.rx
            acc.tx &+= last.tx
            self.retired[last.ifindex] = acc
        }
    }

    private func rebuildSnapshot() {
        var totals: [UInt32: (rx: Int64, tx: Int64)] = [:]
        for (ifindex, acc) in self.retired {
            totals[ifindex] = (Int64(clamping: acc.rx), Int64(clamping: acc.tx))
        }
        for counts in self.sources.values {
            var acc = totals[counts.ifindex] ?? (0, 0)
            acc.rx &+= Int64(clamping: counts.rx)
            acc.tx &+= Int64(clamping: counts.tx)
            totals[counts.ifindex] = acc
        }
        self.snapshotLock.lock()
        self.snapshot = totals
        self.snapshotLock.unlock()
    }

    private static func number(_ dictionary: CFDictionary, _ key: CFString) -> UInt64 {
        guard let raw = CFDictionaryGetValue(dictionary, Unmanaged.passUnretained(key).toOpaque()) else { return 0 }
        let object = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
        guard CFGetTypeID(object) == CFNumberGetTypeID() else { return 0 }
        var value: Int64 = 0
        CFNumberGetValue((object as! CFNumber), .sInt64Type, &value)
        return UInt64(bitPattern: value)
    }
}
