//
//  readers.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

/// Reads temperature sensors straight from the SMC over IOKit.
///
/// Discovery happens once: every candidate key is probed and only keys that return a
/// plausible temperature are kept. Each tick reads only the sensors something is
/// actually showing (menu bar widgets, notifications, and, while the popup is open,
/// everything), plus the per-core inputs of any displayed "Average"/"Hottest" value.
/// A sensor that fails three ticks in a row is left alone for 60 seconds, then retried once.
internal class SensorsReader: Reader<Sensors_List> {
    internal var list: Sensors_List = Sensors_List()

    private static let minTemperature: Double = 0
    private static let maxTemperature: Double = 150
    private static let failuresBeforeSuspend = 3
    private static let suspendInterval: TimeInterval = 60

    private let stateLock = NSLock()
    private var _popupVisible: Bool = false
    private var failures: [String: Int] = [:]
    private var suspendedUntil: [String: TimeInterval] = [:]

    init(callback: @escaping (T?) -> Void = {_ in }) {
        super.init(.sensors, callback: callback)
        self.list.sensors = self.discover()
    }

    /// Called by the popup when it is shown or hidden. While visible, every kept sensor is read.
    public func setPopupVisible(_ state: Bool) {
        self.stateLock.lock()
        self._popupVisible = state
        self.stateLock.unlock()
    }

    private var popupVisible: Bool {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return self._popupVisible
    }

    private static func isPlausible(_ value: Double?) -> Bool {
        guard let value, value.isFinite else { return false }
        return value > SensorsReader.minTemperature && value < SensorsReader.maxTemperature
    }

    // MARK: - discovery

    private func discover() -> [Sensor_p] {
        var available: Set<String> = Set(SMC.shared.getAllKeys().filter { $0.hasPrefix("T") })
        var candidates: [Sensor] = []
        var sensorsList = SensorsList

        if let platform = SystemKit.shared.device.platform {
            sensorsList = sensorsList.filter({ $0.platforms.contains(platform) })
        }

        sensorsList.filter { !$0.key.contains("%") }.forEach { (s: Sensor) in
            if available.remove(s.key) != nil {
                candidates.append(s)
            }
        }
        sensorsList.filter { $0.key.contains("%") }.forEach { (s: Sensor) in
            var index = 1
            for i in 0..<10 {
                let key = s.key.replacingOccurrences(of: "%", with: "\(i)")
                if available.remove(key) != nil {
                    var sensor = s.copy()
                    sensor.key = key
                    sensor.name = s.name.replacingOccurrences(of: "%", with: "\(index)")
                    candidates.append(sensor)
                    index += 1
                }
            }
        }

        // Probe each candidate exactly once; keep only keys that answer with a real temperature.
        var kept: [Sensor_p] = []
        for var sensor in candidates {
            let value = SMC.shared.getValue(sensor.key)
            guard SensorsReader.isPlausible(value), let value else { continue }
            sensor.value = value
            kept.append(sensor)
        }

        debug("Found \(kept.count) temperature sensors out of \(candidates.count) candidates", log: self.log)

        kept = self.initCalculatedSensors(kept) + kept
        return kept.sorted { (a, b) in
            let ga = SensorGroup.ordered.firstIndex(of: a.group) ?? SensorGroup.ordered.count
            let gb = SensorGroup.ordered.firstIndex(of: b.group) ?? SensorGroup.ordered.count
            if ga != gb { return ga < gb }
            if a.isComputed != b.isComputed { return a.isComputed }
            return false
        }
    }

    private func initCalculatedSensors(_ sensors: [Sensor_p]) -> [Sensor_p] {
        var list: [Sensor_p] = []

        let cpuSensors = sensors.filter({ $0.group == .CPU && $0.average }).map{ $0.value }
        let gpuSensors = sensors.filter({ $0.group == .GPU && $0.average }).map{ $0.value }

        if !cpuSensors.isEmpty {
            let value = cpuSensors.reduce(0, +) / Double(cpuSensors.count)
            list.append(Sensor(key: "Average CPU", name: "Average CPU", value: value, group: .CPU, platforms: Platform.all, isComputed: true))
            if let max = cpuSensors.max() {
                list.append(Sensor(key: "Hottest CPU", name: "Hottest CPU", value: max, group: .CPU, platforms: Platform.all, isComputed: true))
            }
        }
        if !gpuSensors.isEmpty {
            let value = gpuSensors.reduce(0, +) / Double(gpuSensors.count)
            list.append(Sensor(key: "Average GPU", name: "Average GPU", value: value, group: .GPU, platforms: Platform.all, isComputed: true))
            if let max = gpuSensors.max() {
                list.append(Sensor(key: "Hottest GPU", name: "Hottest GPU", value: max, group: .GPU, platforms: Platform.all, isComputed: true))
            }
        }

        return list
    }

    // MARK: - read

    public override func read() {
        var sensors = self.list.sensors
        guard !sensors.isEmpty else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let popupVisible = self.popupVisible
        let selected = Store.shared.string(key: "\(ModuleType.sensors.stringValue)_sensor", defaultValue: defaultSelectedSensor)

        // A sensor is wanted when something displays it or watches it.
        func wanted(_ s: Sensor_p) -> Bool {
            popupVisible || s.state || s.key == selected || !s.notificationThreshold.isEmpty
        }

        // Displayed aggregates need their per-core inputs.
        var needCPU = false
        var needGPU = false
        for s in sensors where s.isComputed && wanted(s) {
            if s.group == .CPU { needCPU = true }
            if s.group == .GPU { needGPU = true }
        }

        var healthy: Set<String> = []

        for i in sensors.indices {
            let s = sensors[i]
            guard !s.isComputed else { continue }

            let required = wanted(s) || (s.average && ((s.group == .CPU && needCPU) || (s.group == .GPU && needGPU)))
            guard required else { continue }

            if let until = self.suspendedUntil[s.key] {
                if now < until { continue }
                self.suspendedUntil.removeValue(forKey: s.key)
            }

            let value = SMC.shared.getValue(s.key)
            if SensorsReader.isPlausible(value), let value {
                sensors[i].value = value
                self.failures[s.key] = 0
                healthy.insert(s.key)
            } else {
                let count = (self.failures[s.key] ?? 0) + 1
                if count >= SensorsReader.failuresBeforeSuspend {
                    // Back off for a minute. The counter is left one short of the threshold so that
                    // the single retry after the pause re-suspends on failure, or clears on success.
                    self.suspendedUntil[s.key] = now + SensorsReader.suspendInterval
                    self.failures[s.key] = SensorsReader.failuresBeforeSuspend - 1
                } else {
                    self.failures[s.key] = count
                }
            }
        }

        if needCPU {
            self.updateAggregates(&sensors, group: .CPU, healthy: healthy)
        }
        if needGPU {
            self.updateAggregates(&sensors, group: .GPU, healthy: healthy)
        }

        let updated = Dictionary(sensors.map{ ($0.key, $0) }, uniquingKeysWith: { (first, _) in first })
        self.list.update { current in
            var list = current
            for i in list.indices {
                if let sensor = updated[list[i].key] {
                    list[i] = sensor
                }
            }
            return list
        }

        self.callback(self.list)
    }

    private func updateAggregates(_ sensors: inout [Sensor_p], group: SensorGroup, healthy: Set<String>) {
        let values = sensors
            .filter({ $0.group == group && $0.average && !$0.isComputed && healthy.contains($0.key) })
            .map{ $0.value }
        guard !values.isEmpty else { return }

        if let idx = sensors.firstIndex(where: { $0.key == "Average \(group.rawValue)" }) {
            sensors[idx].value = values.reduce(0, +) / Double(values.count)
        }
        if let max = values.max(), let idx = sensors.firstIndex(where: { $0.key == "Hottest \(group.rawValue)" }) {
            sensors[idx].value = max
        }
    }
}
