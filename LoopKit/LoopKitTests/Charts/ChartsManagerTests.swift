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

    func testOneHourXAxisLabelIntervalIsPreservedForUnalignedSixHourRange() {
        assertXAxisLabelInterval(.hours(1), isPreservedForDuration: .hours(6))
    }

    func testTwoHourXAxisLabelIntervalIsPreservedForUnalignedTwelveHourRange() {
        assertXAxisLabelInterval(.hours(2), isPreservedForDuration: .hours(12))
    }

    func testFourHourXAxisLabelIntervalIsPreservedForUnalignedTwentyFourHourRange() {
        assertXAxisLabelInterval(.hours(4), isPreservedForDuration: .hours(24))
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

    private func assertXAxisLabelInterval(_ interval: TimeInterval, isPreservedForDuration duration: TimeInterval) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
            .addingTimeInterval(.hours(7))
            .addingTimeInterval(.minutes(30))
        let manager = makeManager(xAxisLabelInterval: interval)
        setRange(on: manager, start: start, duration: duration)

        manager.prerender()

        let dateValues = manager.xAxisValues?.compactMap { $0 as? ChartAxisValueDate } ?? []
        XCTAssertGreaterThan(dateValues.count, 1)
        for (current, next) in zip(dateValues, dateValues.dropFirst()) {
            XCTAssertEqual(next.date.timeIntervalSince(current.date), interval, accuracy: 0.001)
        }
    }
}
