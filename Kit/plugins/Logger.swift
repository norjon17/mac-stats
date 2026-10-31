//
//  Logger.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 24/06/2021.
//  Copyright © 2021 Serhiy Mytrovtsiy. All rights reserved.
//
//  Trimmed fork: every line goes to a rotating file in ~/Library/Logs/Stats/
//  and to stderr; info and error lines are mirrored to the unified log
//  (subsystem com.ronjoncapul.macstats) so Console.app shows them too.
//
//  Levels:
//    debug  written only when launched with --debug or Store key debug_logging = true
//    info   always written
//    error  always written, rate limited to one line per 60 s per call site
//

import Darwin
import Foundation
import os

public enum LogLevel: String {
    case debug = "DBG"
    case info  = "INF"
    case error = "ERR"
}

public enum LogOption: Int {
    case timestamp
    case level
    case file
    case line

    public static func new() -> [LogOption] {
        return [timestamp, file, line, level]
    }
}

public protocol Writer: AnyObject {
    func write(_ string: String, level: LogLevel, category: String?)
}

public class NextLog {
    public static let shared = NextLog()

    /// Directory that holds stats.log and its rotated copies.
    public static let logDirectoryURL: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        return base.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("mac-stats", isDirectory: true)
    }()
    public static let logFileURL: URL = logDirectoryURL.appendingPathComponent("stats.log")

    private static let sink: Writer = CompositeWriter([
        StderrWriter(),
        RotatingFileWriter(url: NextLog.logFileURL, maxBytes: 5 * 1024 * 1024, keep: 3),
        UnifiedLogWriter()
    ])

    private var category: String? = nil

    public init() {}

    public func copy(category: String? = nil) -> NextLog {
        let logger = NextLog()
        logger.category = category
        return logger
    }

    public func log(level: LogLevel, options: [LogOption] = LogOption.new(), message: String, file: String = #file, line: UInt = #line) {
        switch level {
        case .debug:
            guard NextLog.debugEnabled else { return }
            NextLog.sink.write(self.prefix(level, options, file, line) + " " + message + "\n", level: level, category: self.category)
        case .info:
            NextLog.sink.write(self.prefix(level, options, file, line) + " " + message + "\n", level: level, category: self.category)
        case .error:
            guard let released = NextLog.rateLimiter.admit(file: file, line: line) else { return }
            var text = self.prefix(level, options, file, line) + " " + message
            if released > 0 {
                text += " (suppressed \(released) repeats)"
            }
            text += "\n"
            NextLog.sink.write(text, level: level, category: self.category)
        }
    }

    /// Writes a session header. Call once at launch.
    public static func startSession(_ description: String) {
        let line = "==== \(description) pid=\(getpid()) debug=\(NextLog.debugEnabled) log=\(NextLog.logFileURL.path)\n"
        NextLog.sink.write(line, level: .info, category: nil)
    }

    private func prefix(_ level: LogLevel, _ options: [LogOption], _ file: String = #file, _ line: UInt = #line) -> String {
        var prefix = ""

        if options.contains(.timestamp) {
            self.space(&prefix, NextLog.timestampFormatter.string(from: Date()))
        }

        if options.contains(.file) {
            if let f = file.split(separator: "/").last {
                self.space(&prefix, String(f))
            }
            if options.contains(.line) {
                prefix += ":\(line)"
            }
        } else if options.contains(.line) {
            self.space(&prefix, "\(line)")
        }

        if options.contains(.level) {
            self.space(&prefix, level.rawValue)
        }

        if let category = self.category {
            self.space(&prefix, "[\(category)]")
        }

        return prefix
    }

    private func space(_ origin: inout String, _ str: String) {
        if origin.last != " " && !origin.isEmpty {
            origin += " "
        }
        origin += str
    }
}

extension NextLog {
    /// Debug output is enabled by launching with `--debug` or by the `debug_logging` Store key.
    /// Evaluated once on first use and cached for the lifetime of the process.
    public static let debugEnabled: Bool = {
        if CommandLine.arguments.contains("--debug") {
            return true
        }
        return Store.shared.bool(key: "debug_logging", defaultValue: false)
    }()

    /// Per call-site (file + line) rate limiter for error level logs:
    /// at most one line per `window` seconds per site. Repeats inside the
    /// window are counted and reported when the next line is released.
    fileprivate static let rateLimiter = RateLimiter(window: 60)

    fileprivate final class RateLimiter {
        private struct Site: Hashable {
            let file: String
            let line: UInt
        }
        private struct State {
            var lastEmitted: TimeInterval
            var suppressed: Int
        }

        private let window: TimeInterval
        private let lock = NSLock()
        private var sites: [Site: State] = [:]

        init(window: TimeInterval) {
            self.window = window
        }

        /// Returns nil when the line must be suppressed, otherwise the number
        /// of lines that were suppressed at this site since the last release.
        func admit(file: String, line: UInt) -> Int? {
            let site = Site(file: file, line: line)
            let now = ProcessInfo.processInfo.systemUptime

            self.lock.lock()
            defer { self.lock.unlock() }

            if var state = self.sites[site] {
                if now - state.lastEmitted < self.window {
                    state.suppressed &+= 1
                    self.sites[site] = state
                    return nil
                }
                let released = state.suppressed
                state.lastEmitted = now
                state.suppressed = 0
                self.sites[site] = state
                return released
            }

            self.sites[site] = State(lastEmitted: now, suppressed: 0)
            return 0
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    // MARK: - Writers

    private final class CompositeWriter: Writer {
        private let writers: [Writer]
        init(_ writers: [Writer]) { self.writers = writers }
        func write(_ string: String, level: LogLevel, category: String?) {
            for w in self.writers { w.write(string, level: level, category: category) }
        }
    }

    private final class StderrWriter: Writer {
        func write(_ string: String, level: LogLevel, category: String?) {
            fputs(string, stderr)
        }
    }

    /// Mirrors info and error lines into the unified log so they show up in
    /// Console.app and `log show --predicate 'subsystem == "com.ronjoncapul.macstats"'`.
    private final class UnifiedLogWriter: Writer {
        private let lock = NSLock()
        private var loggers: [String: os.Logger] = [:]

        func write(_ string: String, level: LogLevel, category: String?) {
            guard level != .debug else { return }
            let logger = self.logger(for: category ?? "app")
            let text = string.trimmingCharacters(in: .newlines)
            switch level {
            case .error: logger.error("\(text, privacy: .public)")
            default: logger.info("\(text, privacy: .public)")
            }
        }

        private func logger(for category: String) -> os.Logger {
            self.lock.lock()
            defer { self.lock.unlock() }
            if let l = self.loggers[category] { return l }
            let l = os.Logger(subsystem: "com.ronjoncapul.macstats", category: category)
            self.loggers[category] = l
            return l
        }
    }

    /// Appends to `url`, rotating to url.1 ... url.<keep> when the file passes `maxBytes`.
    /// All I/O happens on a serial utility queue so reader threads never block on disk.
    private final class RotatingFileWriter: Writer {
        private let url: URL
        private let maxBytes: UInt64
        private let keep: Int
        private let queue = DispatchQueue(label: "eu.exelban.Stats.log", qos: .utility)
        private var handle: FileHandle? = nil
        private var size: UInt64 = 0

        init(url: URL, maxBytes: UInt64, keep: Int) {
            self.url = url
            self.maxBytes = maxBytes
            self.keep = keep
            self.queue.async { self.open() }
        }

        deinit {
            try? self.handle?.close()
        }

        func write(_ string: String, level: LogLevel, category: String?) {
            guard let data = string.data(using: .utf8) else { return }
            self.queue.async {
                guard let handle = self.handle else { return }
                if self.size + UInt64(data.count) > self.maxBytes {
                    self.rotate()
                }
                guard let h = self.handle ?? handle as FileHandle? else { return }
                do {
                    try h.write(contentsOf: data)
                    self.size += UInt64(data.count)
                } catch {
                    fputs("log write failed: \(error)\n", stderr)
                }
            }
        }

        private func open() {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: self.url.path) {
                    fm.createFile(atPath: self.url.path, contents: nil)
                }
                let h = try FileHandle(forWritingTo: self.url)
                self.size = try h.seekToEnd()
                self.handle = h
            } catch {
                fputs("log file unavailable (\(self.url.path)): \(error)\n", stderr)
                self.handle = nil
            }
        }

        private func rotate() {
            try? self.handle?.close()
            self.handle = nil
            let fm = FileManager.default
            let base = self.url.path
            // stats.log.3 is dropped, .2 -> .3, .1 -> .2, stats.log -> .1
            try? fm.removeItem(atPath: "\(base).\(self.keep)")
            if self.keep > 1 {
                for i in stride(from: self.keep - 1, through: 1, by: -1) {
                    let from = "\(base).\(i)", to = "\(base).\(i + 1)"
                    if fm.fileExists(atPath: from) { try? fm.moveItem(atPath: from, toPath: to) }
                }
            }
            try? fm.moveItem(atPath: base, toPath: "\(base).1")
            self.open()
        }
    }
}

public func debug(_ message: String, log: NextLog = NextLog.shared, file: String = #file, line: UInt = #line) {
    log.log(level: .debug, message: message, file: file, line: line)
}

public func info(_ message: String, log: NextLog = NextLog.shared, file: String = #file, line: UInt = #line) {
    log.log(level: .info, message: message, file: file, line: line)
}

public func error(_ message: String, log: NextLog = NextLog.shared, file: String = #file, line: UInt = #line) {
    log.log(level: .error, message: message, file: file, line: line)
}

public func error_msg(_ message: String, log: NextLog = NextLog.shared, file: String = #file, line: UInt = #line) {
    log.log(level: .error, message: message, file: file, line: line)
}
