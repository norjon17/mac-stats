//
//  readers.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 10/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class LoadReader: Reader<CPU_Load> {
    private var cpuInfo: processor_info_array_t!
    private var prevCpuInfo: processor_info_array_t?
    private var numCpuInfo: mach_msg_type_number_t = 0
    private var numPrevCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: uint = 0
    private let CPUUsageLock: NSLock = NSLock()
    private var previousInfo = host_cpu_load_info()
    private var hasHyperthreadingCores = false
    
    private var response: CPU_Load = CPU_Load()
    private var numCPUsU: natural_t = 0
    private var usagePerCore: [Double] = []
    private var cores: [core_s]? = nil
    
    public override func setup() {
        self.hasHyperthreadingCores = sysctlByName("hw.physicalcpu") != sysctlByName("hw.logicalcpu")
        [CTL_HW, HW_NCPU].withUnsafeBufferPointer { mib in
            var sizeOfNumCPUs: size_t = MemoryLayout<uint>.size
            let status = sysctl(processor_info_array_t(mutating: mib.baseAddress), 2, &numCPUs, &sizeOfNumCPUs, nil, 0)
            if status != 0 {
                self.numCPUs = 1
            }
        }
        self.cores = SystemKit.shared.device.info.cpu?.cores
    }
    
    public override func read() {
        self.CPUUsageLock.lock()
        
        let result: kern_return_t = host_processor_info(machHostPort, PROCESSOR_CPU_LOAD_INFO, &self.numCPUsU, &self.cpuInfo, &self.numCpuInfo)
        if result == KERN_SUCCESS {
            self.usagePerCore = []
            
            if let prevCpuInfo = self.prevCpuInfo {
                for i in 0 ..< Int32(self.numCPUs) {
                    let user = UInt32(bitPattern: self.cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)])
                        &- UInt32(bitPattern: prevCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)])
                    let system = UInt32(bitPattern: self.cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)])
                        &- UInt32(bitPattern: prevCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)])
                    let nice = UInt32(bitPattern: self.cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)])
                        &- UInt32(bitPattern: prevCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)])
                    let idle = UInt32(bitPattern: self.cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)])
                        &- UInt32(bitPattern: prevCpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)])
                    
                    let inUse = UInt64(user) + UInt64(system) + UInt64(nice)
                    let total = inUse + UInt64(idle)
                    if total != 0 {
                        self.usagePerCore.append(min(1, Double(inUse) / Double(total)))
                    }
                }
            }
            let showHyperthratedCores = Store.shared.bool(key: "CPU_hyperhreading", defaultValue: false)
            if showHyperthratedCores || !self.hasHyperthreadingCores {
                self.response.usagePerCore = self.usagePerCore
            } else {
                var i = 0
                var a = 0
                
                self.response.usagePerCore = []
                while i < Int(self.usagePerCore.count/2) {
                    a = i*2
                    if self.usagePerCore.indices.contains(a) && self.usagePerCore.indices.contains(a+1) {
                        self.response.usagePerCore.append((Double(self.usagePerCore[a]) + Double(self.usagePerCore[a+1])) / 2)
                    }
                    i += 1
                }
            }
            
            if let prevCpuInfo = self.prevCpuInfo {
                let prevCpuInfoSize: size_t = MemoryLayout<integer_t>.stride * Int(self.numPrevCpuInfo)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevCpuInfo), vm_size_t(prevCpuInfoSize))
            }
            
            self.prevCpuInfo = self.cpuInfo
            self.numPrevCpuInfo = self.numCpuInfo
            
            self.cpuInfo = nil
            self.numCpuInfo = 0
        } else {
            error("host_processor_info(): \(String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error")", log: self.log)
        }
        
        let cpuInfo = hostCPULoadInfo()
        if cpuInfo == nil {
            self.CPUUsageLock.unlock()
            self.callback(nil)
            return
        }
        
        let userDiff = Double(cpuInfo!.cpu_ticks.0 &- self.previousInfo.cpu_ticks.0)
        let sysDiff  = Double(cpuInfo!.cpu_ticks.1 &- self.previousInfo.cpu_ticks.1)
        let idleDiff = Double(cpuInfo!.cpu_ticks.2 &- self.previousInfo.cpu_ticks.2)
        let niceDiff = Double(cpuInfo!.cpu_ticks.3 &- self.previousInfo.cpu_ticks.3)
        let totalTicks = sysDiff + userDiff + niceDiff + idleDiff
        
        let system = sysDiff / totalTicks
        let user = userDiff / totalTicks
        let idle = idleDiff / totalTicks
        
        if !system.isNaN {
            self.response.systemLoad  = system
        }
        if !user.isNaN {
            self.response.userLoad = user
        }
        if !idle.isNaN {
            self.response.idleLoad = idle
        }
        self.previousInfo = cpuInfo!
        self.response.totalUsage = self.response.systemLoad + self.response.userLoad
        
        if let cores = self.cores {
            let eCoresList: [Double] = cores.filter({ $0.type == .efficiency }).enumerated().compactMap { (i, c) -> Double? in
                if self.response.usagePerCore.indices.contains(Int(c.id)) {
                    return self.response.usagePerCore[Int(c.id)]
                }
                return i < self.usagePerCore.count ? self.usagePerCore[i] : 0
            }
            let pCoresList: [Double] = cores.filter({ $0.type == .performance }).enumerated().compactMap { (i, c) -> Double? in
                if self.response.usagePerCore.indices.contains(Int(c.id)) {
                    return self.response.usagePerCore[Int(c.id)]
                }
                return i < self.usagePerCore.count ? self.usagePerCore[i] : 0
            }
            let sCoresList: [Double] = cores.filter({ $0.type == .super }).enumerated().compactMap { (i, c) -> Double? in
                if self.response.usagePerCore.indices.contains(Int(c.id)) {
                    return self.response.usagePerCore[Int(c.id)]
                }
                return i < self.usagePerCore.count ? self.usagePerCore[i] : 0
            }
            
            if !eCoresList.isEmpty {
                self.response.usageECores = eCoresList.reduce(0, +)/Double(eCoresList.count)
            }
            if !pCoresList.isEmpty {
                self.response.usagePCores = pCoresList.reduce(0, +)/Double(pCoresList.count)
            }
            if !sCoresList.isEmpty {
                self.response.usageSCores = sCoresList.reduce(0, +)/Double(sCoresList.count)
            }
        }
        
        let response = self.response
        self.CPUUsageLock.unlock()
        self.callback(response)
    }
    
    private func hostCPULoadInfo() -> host_cpu_load_info? {
        let count = MemoryLayout<host_cpu_load_info>.stride/MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(count)
        var cpuLoadInfo = host_cpu_load_info()
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: count) {
                host_statistics(machHostPort, HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if result != KERN_SUCCESS {
            error("kern_result_t: \(result)", log: self.log)
            return nil
        }
        
        return cpuLoadInfo
    }
}

public class TemperatureReader: Reader<Double> {
    /// SMC keys selected once in setup() for the current chip generation.
    private var keys: [String] = []
    /// Consecutive nil reads per key; a key is dropped for the session after two misses.
    private var misses: [String: Int] = [:]
    
    private static let m5Keys: [String] = ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
    
    public override func setup() {
        self.popup = true
        switch SystemKit.shared.device.platform {
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            self.keys = ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            self.keys = ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            self.keys = ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case .m4, .m4Pro, .m4Max:
            self.keys = ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            self.keys = TemperatureReader.m5Keys
        default:
            // Unknown or newer chip: start from the M5 list; dead keys are pruned after two misses.
            self.keys = TemperatureReader.m5Keys
        }
        self.misses = [:]
    }
    
    public override func read() {
        var total: Double = 0
        var counter: Double = 0
        var dead: [String] = []
        
        for key in self.keys {
            guard let value = SMC.shared.getValue(key) else {
                let n = (self.misses[key] ?? 0) + 1
                self.misses[key] = n
                if n >= 2 {
                    dead.append(key)
                }
                continue
            }
            self.misses[key] = 0
            if value >= 10 && value <= 120 {
                total += value
                counter += 1
            }
        }
        
        if !dead.isEmpty {
            self.keys.removeAll(where: { dead.contains($0) })
            dead.forEach { self.misses.removeValue(forKey: $0) }
        }
        
        self.callback(counter != 0 ? total / counter : nil)
    }
}
