//
//  Kit.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 04/07/2026.
//  Using Swift 6.0.
//  Running on macOS 26.5.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import Kit

class KitTests: XCTestCase {
    func testUnitsGetReadableSpeed_byte() throws {
        XCTAssertEqual(Units(bytes: 0).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 999).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 1_000).getReadableSpeed(base: .byte), "1 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte), "500 KB/s")
        XCTAssertEqual(Units(bytes: 2_500_000).getReadableSpeed(base: .byte), "2.5 MB/s")
        XCTAssertEqual(Units(bytes: 150_000_000).getReadableSpeed(base: .byte), "150 MB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000).getReadableSpeed(base: .byte), "2.0 GB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000_000).getReadableSpeed(base: .byte), "2.0 TB/s")
        XCTAssertEqual(Units(bytes: -5).getReadableSpeed(base: .byte), "0 KB/s")
    }
    
    func testUnitsGetReadableSpeed_bit() throws {
        XCTAssertEqual(Units(bytes: 100).getReadableSpeed(base: .bit), "0 Kb/s")
        XCTAssertEqual(Units(bytes: 50_000).getReadableSpeed(base: .bit), "400 Kb/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit), "4.0 Mb/s")
        XCTAssertEqual(Units(bytes: 200_000_000).getReadableSpeed(base: .bit), "1.6 Gb/s")
        XCTAssertEqual(Units(bytes: 200_000_000_000).getReadableSpeed(base: .bit), "1.6 Tb/s")
    }
    
    func testUnitsGetReadableSpeed_fixedUnit() throws {
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "KB"), "500.00 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "MB"), "0.50 MB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit, unit: "MB"), "4.00 Mb/s")
        XCTAssertEqual(Units(bytes: 1_250_000_000).getReadableSpeed(base: .byte, unit: "GB"), "1.25 GB/s")
        XCTAssertEqual(Units(bytes: 1_250_000_000_000).getReadableSpeed(base: .byte, unit: "TB"), "1.25 TB/s")
    }
    
    func testUnitsGetReadableSpeed_fixedUnitZero() throws {
        for unit in ["KB", "MB", "GB", "TB"] {
            for base in [DataSizeBase.byte, .bit] {
                XCTAssertEqual(Units(bytes: 0).getReadableSpeed(base: base, unit: unit, omitUnits: true), "0.00")
                XCTAssertEqual(Units(bytes: 1).getReadableSpeed(base: base, unit: unit, omitUnits: true), base == .bit && unit == "KB" ? "0.01" : "0.00")
            }
        }
    }
    
    func testUnitsGetReadableSpeed_fixedUnitPrecision() throws {
        XCTAssertEqual(Units(bytes: 4_900).getReadableSpeed(unit: "MB"), "0.00 MB/s")
        XCTAssertEqual(Units(bytes: 5_100).getReadableSpeed(unit: "MB"), "0.01 MB/s")
        XCTAssertEqual(Units(bytes: 10_000).getReadableSpeed(unit: "MB"), "0.01 MB/s")
        XCTAssertEqual(Units(bytes: 350_000).getReadableSpeed(unit: "MB"), "0.35 MB/s")
        XCTAssertEqual(Units(bytes: 1_260_000).getReadableSpeed(unit: "MB"), "1.26 MB/s")
        XCTAssertEqual(Units(bytes: 9_999_000).getReadableSpeed(unit: "MB"), "10.00 MB/s")
        XCTAssertEqual(Units(bytes: 12_340_000).getReadableSpeed(unit: "MB"), "12.34 MB/s")
        XCTAssertEqual(Units(bytes: 99_999_000).getReadableSpeed(unit: "MB"), "100.00 MB/s")
        XCTAssertEqual(Units(bytes: 123_450_000).getReadableSpeed(unit: "MB"), "123.45 MB/s")
        XCTAssertEqual(Units(bytes: 1_000_000_000).getReadableSpeed(unit: "KB"), "1000000.00 KB/s")
    }
}
