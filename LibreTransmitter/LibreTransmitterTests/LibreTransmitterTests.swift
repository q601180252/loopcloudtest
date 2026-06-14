//
//  LibreTransmitterTests.swift
//  LibreTransmitterTests
//
//  Created by Nathan Racklyeft on 5/8/16.
//  Copyright © 2016 Mark Wilson. All rights reserved.
//

import XCTest
@testable import LibreTransmitter

class LibreTransmitterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testHistoryMeasurementsRejectValuesAboveCurrentSensorRange() {
        let calibration = SensorData.CalibrationInfo(
            i1: 1,
            i2: 1,
            i3: 1,
            i4: 1,
            i5: 1,
            i6: 1,
            isValidForFooterWithReverseCRCs: 1
        )
        calibration.extraSlope = 0
        calibration.extraOffset = 501

        let measurement = Measurement(
            date: Date(),
            rawGlucose: 1000,
            rawTemperature: 1000,
            rawTemperatureAdjustment: 1
        )

        let glucoses = LibreGlucose.fromHistoryMeasurements([measurement], nativeCalibrationData: calibration)

        XCTAssertTrue(glucoses.isEmpty)
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
