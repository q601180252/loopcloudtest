//
//  ChartsManagerTests.swift
//  LoopKitTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import SwiftCharts
import UIKit
import XCTest
@testable import LoopKitUI

final class ChartsManagerTests: XCTestCase {

    private let colors = ChartColorPalette(
        axisLine: .black,
        axisLabel: .black,
        grid: .lightGray,
        glucoseTint: .blue,
        insulinTint: .orange,
        carbTint: .green
    )

    func testDefaultXAxisLabelIntervalIsOneHour() {
        let manager = makeManager()

        XCTAssertEqual(manager.xAxisLabelInterval, .hours(1))
    }

    func testFourHourXAxisLabelIntervalGeneratesSevenValuesForTwentyFourHours() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let manager = makeManager(xAxisLabelInterval: .hours(4))
        setRange(on: manager, start: start, duration: .hours(24))

        manager.prerender()

        let xAxisValues = manager.xAxisValues
        XCTAssertEqual(xAxisValues?.count, 7)
        XCTAssertEqual((xAxisValues?.first as? ChartAxisValueDate)?.date, start)
        XCTAssertEqual((xAxisValues?.last as? ChartAxisValueDate)?.date, start.addingTimeInterval(.hours(24)))
    }

    func testChangingXAxisLabelIntervalClearsAndRegeneratesValues() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let manager = makeManager()
        setRange(on: manager, start: start, duration: .hours(12))
        manager.prerender()
        XCTAssertEqual(manager.xAxisValues?.count, 13)

        manager.xAxisLabelInterval = .hours(2)

        XCTAssertNil(manager.xAxisValues)
        manager.prerender()
        XCTAssertEqual(manager.xAxisValues?.count, 7)
    }

    private func makeManager() -> ChartsManager {
        return ChartsManager(
            colors: colors,
            settings: .default,
            charts: [],
            traitCollection: .current
        )
    }

    private func makeManager(xAxisLabelInterval: TimeInterval) -> ChartsManager {
        return ChartsManager(
            colors: colors,
            settings: .default,
            charts: [],
            traitCollection: .current,
            xAxisLabelInterval: xAxisLabelInterval
        )
    }

    private func setRange(on manager: ChartsManager, start: Date, duration: TimeInterval) {
        manager.startDate = start
        manager.maxEndDate = start.addingTimeInterval(duration)
        manager.updateEndDate(manager.maxEndDate)
    }
}
