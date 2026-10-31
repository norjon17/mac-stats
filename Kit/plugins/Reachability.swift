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

public class Reachability {
    public private(set) var isReachable: Bool = false

    public var reachable: () -> Void = {}
    public var unreachable: () -> Void = {}

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
        self.isReachable = reachable
        if reachable {
            self.reachable()
        } else {
            self.unreachable()
        }
    }
}
