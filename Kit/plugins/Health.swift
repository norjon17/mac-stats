//
//  Health.swift
//  Kit
//
//  Periodic self-report of the app's own resource usage, written at info level
//  so a long run can be traced from the log file alone:
//
//    health rss=74.2MB cpu=12.4s threads=12 uptime=2h10m
//
//  Costs one task_info and one getrusage call per interval.
//

import Foundation
import Darwin

public final class HealthMonitor {
    public static let shared = HealthMonitor()

    private let queue = DispatchQueue(label: "eu.exelban.Stats.health", qos: .utility)
    private var timer: DispatchSourceTimer? = nil
    private let started = Date()
    private let log = NextLog.shared.copy(category: "health")

    private init() {}

    /// Starts the heartbeat. `interval` defaults to 10 minutes.
    public func start(interval: TimeInterval = 600) {
        self.queue.sync {
            guard self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 60, repeating: interval, leeway: .seconds(5))
            t.setEventHandler { [weak self] in self?.report() }
            t.resume()
            self.timer = t
        }
    }

    public func stop() {
        self.queue.sync {
            self.timer?.cancel()
            self.timer = nil
        }
    }

    /// Writes one health line now.
    public func report() {
        info(self.snapshot(), log: self.log)
    }

    public func snapshot() -> String {
        var rssMB: Double = -1
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            rssMB = Double(taskInfo.resident_size) / 1024 / 1024
        }

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000

        var threadCount = 0
        var threads: thread_act_array_t? = nil
        var threadNum: mach_msg_type_number_t = 0
        if task_threads(mach_task_self_, &threads, &threadNum) == KERN_SUCCESS, let list = threads {
            threadCount = Int(threadNum)
            for i in 0..<Int(threadNum) { mach_port_deallocate(mach_task_self_, list[i]) }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(threadNum) * MemoryLayout<thread_act_t>.stride))
        }

        let up = Int(Date().timeIntervalSince(self.started))
        let uptime = up >= 3600 ? "\(up / 3600)h\((up % 3600) / 60)m" : "\(up / 60)m"

        return String(format: "health rss=%.1fMB cpu=%.1fs threads=%d uptime=%@", rssMB, cpu, threadCount, uptime)
    }
}
