//
//  values.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Kit
import Cocoa

/// Sensor shown by the Mini widget until the user picks another one.
internal let defaultSelectedSensor = "Average CPU"

public enum SensorGroup: String, Codable {
    case CPU = "CPU"
    case GPU = "GPU"
    case system = "Systems"
    case sensor = "Sensors"

    /// Display order: CPU and GPU first.
    public static let ordered: [SensorGroup] = [.CPU, .GPU, .system, .sensor]
}

public enum SensorType: String, Codable {
    case temperature = "Temperature"
}

public protocol Sensor_p {
    var key: String { get }
    var name: String { get }
    var value: Double { get set }
    var state: Bool { get }
    var popupState: Bool { get }
    var notificationThreshold: String { get }

    var group: SensorGroup { get }
    var type: SensorType { get }
    var isComputed: Bool { get }
    var average: Bool { get }

    var localValue: Double { get }
    var unit: String { get }
    var miniUnit: String { get }
    var formattedValue: String { get }
    var formattedMiniValue: String { get }
    var formattedPopupValue: String { get }
}

public class Sensors_List: Codable {
    private var queue: DispatchQueue = DispatchQueue(label: "eu.exelban.Stats.Sensors.SynchronizedArray", attributes: .concurrent)

    private var list: [Sensor_p] = []
    public var sensors: [Sensor_p] {
        get {
            self.queue.sync{ self.list }
        }
        set {
            self.queue.async(flags: .barrier) {
                self.list = newValue
            }
        }
    }

    public func update(_ transform: ([Sensor_p]) -> [Sensor_p]) {
        self.queue.sync(flags: .barrier) {
            self.list = transform(self.list)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sensors
    }

    public init() {}

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.sensors.compactMap { $0 as? Sensor }, forKey: .sensors)
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sensors = try container.decode([Sensor].self, forKey: .sensors)
    }
}

public struct Sensor: Sensor_p, Codable {
    public var key: String
    public var name: String

    public var value: Double = 0

    public var group: SensorGroup
    public var type: SensorType = .temperature
    public var platforms: [Platform]
    public var isComputed: Bool = false
    public var average: Bool = false

    public var unit: String { UnitTemperature.current.symbol }
    public var miniUnit: String { "°" }

    public var formattedValue: String {
        temperature(self.value)
    }
    public var formattedPopupValue: String {
        temperature(self.value, fractionDigits: 1)
    }
    public var formattedMiniValue: String {
        temperature(self.value).replacingOccurrences(of: "C", with: "").replacingOccurrences(of: "F", with: "")
    }
    public var localValue: Double {
        Double(self.formattedMiniValue.digits) ?? self.value
    }

    /// Shown in the menu bar (stack widget) when enabled in the module settings.
    public var state: Bool {
        Store.shared.bool(key: "sensor_\(self.key)", defaultValue: false)
    }
    /// Shown in the popup; on by default.
    public var popupState: Bool {
        Store.shared.bool(key: "sensor_\(self.key)_popup", defaultValue: true)
    }
    public var notificationThreshold: String {
        Store.shared.string(key: "sensor_\(self.key)_notification", defaultValue: "")
    }

    public func copy() -> Sensor {
        Sensor(
            key: self.key,
            name: self.name,
            group: self.group,
            type: self.type,
            platforms: self.platforms,
            isComputed: self.isComputed,
            average: self.average
        )
    }
}

// Temperature keys only. Entries are matched against the keys the SMC actually
// exposes, then probed once; only keys that return a plausible temperature survive.
// List of keys: https://github.com/acidanthera/VirtualSMC/blob/master/Docs/SMCSensorKeys.txt
internal let SensorsList: [Sensor] = [
    Sensor(key: "TA%P", name: "Ambient %", group: .sensor, platforms: Platform.all),
    Sensor(key: "TZ%C", name: "Thermal zone %", group: .sensor, platforms: Platform.all),

    Sensor(key: "TC0D", name: "CPU diode", group: .CPU, platforms: Platform.all),
    Sensor(key: "TC0E", name: "CPU diode virtual", group: .CPU, platforms: Platform.all),
    Sensor(key: "TC0F", name: "CPU diode filtered", group: .CPU, platforms: Platform.all),
    Sensor(key: "TC0H", name: "CPU heatsink", group: .CPU, platforms: Platform.all),
    Sensor(key: "TC0P", name: "CPU proximity", group: .CPU, platforms: Platform.all),
    Sensor(key: "TCAD", name: "CPU package", group: .CPU, platforms: Platform.all),

    Sensor(key: "TC%c", name: "CPU core %", group: .CPU, platforms: Platform.all, average: true),
    Sensor(key: "TC%C", name: "CPU Core %", group: .CPU, platforms: Platform.all, average: true),

    Sensor(key: "TCGC", name: "GPU Intel Graphics", group: .GPU, platforms: Platform.all),
    Sensor(key: "TG0D", name: "GPU diode", group: .GPU, platforms: Platform.all),
    Sensor(key: "TGDD", name: "GPU AMD Radeon", group: .GPU, platforms: Platform.all),
    Sensor(key: "TG0H", name: "GPU heatsink", group: .GPU, platforms: Platform.all),
    Sensor(key: "TG0P", name: "GPU proximity", group: .GPU, platforms: Platform.all),

    Sensor(key: "Tm0P", name: "Mainboard", group: .system, platforms: Platform.all),
    Sensor(key: "TW0P", name: "Airport", group: .system, platforms: Platform.all),
    Sensor(key: "TL0P", name: "Display", group: .system, platforms: Platform.all),
    Sensor(key: "TI%P", name: "Thunderbolt %", group: .system, platforms: Platform.all),
    Sensor(key: "TH%A", name: "Disk % (A)", group: .system, platforms: Platform.all),
    Sensor(key: "TH%B", name: "Disk % (B)", group: .system, platforms: Platform.all),
    Sensor(key: "TH%C", name: "Disk % (C)", group: .system, platforms: Platform.all),

    Sensor(key: "TTLD", name: "Thunderbolt left", group: .system, platforms: Platform.all),
    Sensor(key: "TTRD", name: "Thunderbolt right", group: .system, platforms: Platform.all),

    Sensor(key: "TN0D", name: "Northbridge diode", group: .system, platforms: Platform.all),
    Sensor(key: "TN0H", name: "Northbridge heatsink", group: .system, platforms: Platform.all),
    Sensor(key: "TN0P", name: "Northbridge proximity", group: .system, platforms: Platform.all),

    // M1
    Sensor(key: "Tp09", name: "CPU efficiency core 1", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0T", name: "CPU efficiency core 2", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 3", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0H", name: "CPU performance core 4", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0L", name: "CPU performance core 5", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0P", name: "CPU performance core 6", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 7", group: .CPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 8", group: .CPU, platforms: Platform.m1Gen, average: true),

    Sensor(key: "Tg05", name: "GPU 1", group: .GPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0D", name: "GPU 2", group: .GPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0L", name: "GPU 3", group: .GPU, platforms: Platform.m1Gen, average: true),
    Sensor(key: "Tg0T", name: "GPU 4", group: .GPU, platforms: Platform.m1Gen, average: true),

    Sensor(key: "Tm02", name: "Memory 1", group: .sensor, platforms: Platform.m1Gen),
    Sensor(key: "Tm06", name: "Memory 2", group: .sensor, platforms: Platform.m1Gen),
    Sensor(key: "Tm08", name: "Memory 3", group: .sensor, platforms: Platform.m1Gen),
    Sensor(key: "Tm09", name: "Memory 4", group: .sensor, platforms: Platform.m1Gen),

    // M2
    Sensor(key: "Tp1h", name: "CPU efficiency core 1", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1t", name: "CPU efficiency core 2", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1p", name: "CPU efficiency core 3", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp1l", name: "CPU efficiency core 4", group: .CPU, platforms: Platform.m2Gen, average: true),

    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp09", name: "CPU performance core 3", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 4", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 5", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 6", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0f", name: "CPU performance core 7", group: .CPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tp0j", name: "CPU performance core 8", group: .CPU, platforms: Platform.m2Gen, average: true),

    Sensor(key: "Tg0f", name: "GPU 1", group: .GPU, platforms: Platform.m2Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 2", group: .GPU, platforms: Platform.m2Gen, average: true),

    // M3
    Sensor(key: "Te05", name: "CPU efficiency core 1", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0L", name: "CPU efficiency core 2", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0P", name: "CPU efficiency core 3", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Te0S", name: "CPU efficiency core 4", group: .CPU, platforms: Platform.m3Gen, average: true),

    Sensor(key: "Tf04", name: "CPU performance core 1", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf09", name: "CPU performance core 2", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0A", name: "CPU performance core 3", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0B", name: "CPU performance core 4", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0D", name: "CPU performance core 5", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf0E", name: "CPU performance core 6", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf44", name: "CPU performance core 7", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf49", name: "CPU performance core 8", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4A", name: "CPU performance core 9", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4B", name: "CPU performance core 10", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4D", name: "CPU performance core 11", group: .CPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf4E", name: "CPU performance core 12", group: .CPU, platforms: Platform.m3Gen, average: true),

    Sensor(key: "Tf14", name: "GPU 1", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf18", name: "GPU 2", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf19", name: "GPU 3", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf1A", name: "GPU 4", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf24", name: "GPU 5", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf28", name: "GPU 6", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf29", name: "GPU 7", group: .GPU, platforms: Platform.m3Gen, average: true),
    Sensor(key: "Tf2A", name: "GPU 8", group: .GPU, platforms: Platform.m3Gen, average: true),

    // M4
    Sensor(key: "Te05", name: "CPU efficiency core 1", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te0S", name: "CPU efficiency core 2", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te09", name: "CPU efficiency core 3", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Te0H", name: "CPU efficiency core 4", group: .CPU, platforms: Platform.m4Gen, average: true),

    Sensor(key: "Tp01", name: "CPU performance core 1", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 2", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp09", name: "CPU performance core 3", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 4", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0V", name: "CPU performance core 5", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0Y", name: "CPU performance core 6", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 7", group: .CPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tp0e", name: "CPU performance core 8", group: .CPU, platforms: Platform.m4Gen, average: true),

    Sensor(key: "Tg0G", name: "GPU 1", group: .GPU, platforms: [.m4], average: true),
    Sensor(key: "Tg0H", name: "GPU 2", group: .GPU, platforms: [.m4], average: true),
    Sensor(key: "Tg1U", name: "GPU 1", group: .GPU, platforms: [.m4Pro, .m4Max], average: true),
    Sensor(key: "Tg1k", name: "GPU 2", group: .GPU, platforms: [.m4Pro, .m4Max], average: true),

    Sensor(key: "Tg0K", name: "GPU 3", group: .GPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0L", name: "GPU 4", group: .GPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0d", name: "GPU 5", group: .GPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0e", name: "GPU 6", group: .GPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 7", group: .GPU, platforms: Platform.m4Gen, average: true),
    Sensor(key: "Tg0k", name: "GPU 8", group: .GPU, platforms: Platform.m4Gen, average: true),

    Sensor(key: "Tm0p", name: "Memory Proximity 1", group: .sensor, platforms: Platform.m4Gen),
    Sensor(key: "Tm1p", name: "Memory Proximity 2", group: .sensor, platforms: Platform.m4Gen),
    Sensor(key: "Tm2p", name: "Memory Proximity 3", group: .sensor, platforms: Platform.m4Gen),

    // M5
    Sensor(key: "Tp00", name: "CPU super core 1", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp04", name: "CPU super core 2", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp08", name: "CPU super core 3", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0C", name: "CPU super core 4", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0G", name: "CPU super core 5", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0K", name: "CPU super core 6", group: .CPU, platforms: Platform.m5Gen, average: true),

    Sensor(key: "Tp0O", name: "CPU performance core 1", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0R", name: "CPU performance core 2", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0U", name: "CPU performance core 3", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0X", name: "CPU performance core 4", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0a", name: "CPU performance core 5", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0d", name: "CPU performance core 6", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0g", name: "CPU performance core 7", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0j", name: "CPU performance core 8", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0m", name: "CPU performance core 9", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0p", name: "CPU performance core 10", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0u", name: "CPU performance core 11", group: .CPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tp0y", name: "CPU performance core 12", group: .CPU, platforms: Platform.m5Gen, average: true),

    Sensor(key: "Tg0U", name: "GPU 1", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0X", name: "GPU 2", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0d", name: "GPU 3", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0g", name: "GPU 4", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg0j", name: "GPU 5", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1Y", name: "GPU 6", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1c", name: "GPU 7", group: .GPU, platforms: Platform.m5Gen, average: true),
    Sensor(key: "Tg1g", name: "GPU 8", group: .GPU, platforms: Platform.m5Gen, average: true),

    // M6
    Sensor(key: "Tp0j", name: "CPU super core 1", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0g", name: "CPU super core 2", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp09", name: "CPU super core 3", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp07", name: "CPU super core 4", group: .CPU, platforms: Platform.m6Gen, average: true),

    Sensor(key: "Tp0m", name: "CPU performance core 1", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0L", name: "CPU performance core 2", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0I", name: "CPU performance core 3", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0d", name: "CPU performance core 4", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0E", name: "CPU performance core 5", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0G", name: "CPU performance core 6", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp0b", name: "CPU performance core 7", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tp05", name: "CPU performance core 8", group: .CPU, platforms: Platform.m6Gen, average: true),

    Sensor(key: "Te07", name: "CPU efficiency core 1", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Te08", name: "CPU efficiency core 2", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Te09", name: "CPU efficiency core 3", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Te0c", name: "CPU efficiency core 4", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Te0h", name: "CPU efficiency core 5", group: .CPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Te0i", name: "CPU efficiency core 6", group: .CPU, platforms: Platform.m6Gen, average: true),

    Sensor(key: "Tg1e", name: "GPU 1", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg0d", name: "GPU 2", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg0c", name: "GPU 3", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg0b", name: "GPU 4", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg1c", name: "GPU 5", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg1d", name: "GPU 6", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg07", name: "GPU 7", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg1f", name: "GPU 8", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg09", name: "GPU 9", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg0a", name: "GPU 10", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg1g", name: "GPU 11", group: .GPU, platforms: Platform.m6Gen, average: true),
    Sensor(key: "Tg1h", name: "GPU 12", group: .GPU, platforms: Platform.m6Gen, average: true),

    // A18 Pro
    Sensor(key: "Te05", name: "CPU efficiency core 1", group: .CPU, platforms: [Platform.a18Pro], average: true),
    Sensor(key: "Te0S", name: "CPU efficiency core 2", group: .CPU, platforms: [Platform.a18Pro], average: true),

    Sensor(key: "Tp05", name: "CPU performance core 1", group: .CPU, platforms: [Platform.a18Pro], average: true),
    Sensor(key: "Tp0D", name: "CPU performance core 2", group: .CPU, platforms: [Platform.a18Pro], average: true),

    Sensor(key: "Tg05", name: "GPU 1", group: .GPU, platforms: [Platform.a18Pro], average: true),
    Sensor(key: "Tg0D", name: "GPU 2", group: .GPU, platforms: [Platform.a18Pro], average: true),
    Sensor(key: "Tg0L", name: "GPU 3", group: .GPU, platforms: [Platform.a18Pro], average: true),
    Sensor(key: "Tg0e", name: "GPU 4", group: .GPU, platforms: [Platform.a18Pro], average: true),

    // Apple Silicon, all generations
    Sensor(key: "TaLP", name: "Airflow left", group: .sensor, platforms: Platform.apple),
    Sensor(key: "TaRF", name: "Airflow right", group: .sensor, platforms: Platform.apple),

    Sensor(key: "TH0x", name: "NAND", group: .system, platforms: Platform.apple),
    Sensor(key: "TB1T", name: "Battery 1", group: .system, platforms: Platform.apple),
    Sensor(key: "TB2T", name: "Battery 2", group: .system, platforms: Platform.apple),
    Sensor(key: "TW0P", name: "Airport", group: .system, platforms: Platform.apple)
]
