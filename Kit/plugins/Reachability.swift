//
//  Reachability.swift
//  Kit
//
//  Network reachability backed by NWPathMonitor. Replaces the SCNetworkReachability
//  implementation (deprecated in macOS 14.4). Same public surface: `isReachable`,
//  `reachable`/`unreachable` callbacks, `start()`, `stop()`.
//

import Foundation
import Network

// @unchecked: every mutable member is only touched while holding lock.
public final class Reachability: @unchecked Sendable {
    public var isReachable: Bool { self.lock.withLock { self._isReachable } }

    public var reachable: () -> Void {
        get { self.lock.withLock { self._reachable } }
        set { self.lock.withLock { self._reachable = newValue } }
    }
    public var unreachable: () -> Void {
        get { self.lock.withLock { self._unreachable } }
        set { self.lock.withLock { self._unreachable = newValue } }
    }

    private var _isReachable: Bool = false
    private var _reachable: () -> Void = {}
    private var _unreachable: () -> Void = {}

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "eu.exelban.ReachabilityQueue")
    private let lock = NSLock()

    public init(start: Bool = false) {
        if start {
            self.start()
        }
    }

    deinit {
        self.stop()
    }

    public func start() {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.monitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path.status == .satisfied)
        }
        monitor.start(queue: self.queue)
        self.monitor = monitor
    }

    public func stop() {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let monitor = self.monitor else { return }
        monitor.pathUpdateHandler = nil
        monitor.cancel()
        self.monitor = nil
    }

    private func update(_ reachable: Bool) {
        // Callback runs outside the lock so it may touch this object.
        let callback: () -> Void = self.lock.withLock {
            self._isReachable = reachable
            return reachable ? self._reachable : self._unreachable
        }
        callback()
    }
}
