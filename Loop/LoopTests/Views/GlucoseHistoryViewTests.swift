//
//  GlucoseHistoryViewTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import XCTest
@testable import Loop

@MainActor
final class GlucoseHistoryViewTests: XCTestCase {
    private static let now = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testRowContentUsesCurrentDisplayPreferenceAndSampleMetadata() {
        let sample = glucoseSample(
            value: 180,
            date: Self.now,
            trend: .up,
            wasUserEntered: true
        )
        let preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)

        let milligramsRow = GlucoseHistoryRowContent(
            sample: sample,
            displayGlucosePreference: preference
        )

        XCTAssertEqual(milligramsRow.formattedValue, preference.format(sample.quantity))
        XCTAssertEqual(milligramsRow.trend, .up)
        XCTAssertTrue(milligramsRow.isManual)

        preference.unitDidChange(to: .millimolesPerLiter)
        let millimolesRow = GlucoseHistoryRowContent(
            sample: sample,
            displayGlucosePreference: preference
        )

        XCTAssertNotEqual(millimolesRow.formattedValue, milligramsRow.formattedValue)
        XCTAssertEqual(millimolesRow.formattedValue, preference.format(sample.quantity))
    }

    func testPageContentUsesViewModelDataAndRangeAction() async {
        let loader = GlucoseHistoryViewTestLoader()
        let viewModel = makeViewModel(loader: loader)
        let preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        let samples = [
            glucoseSample(value: 101, date: Self.now - .hours(2)),
            glucoseSample(value: 142, date: Self.now - .hours(1), trend: .up)
        ]
        viewModel.startObserving()
        loader.completeRequest(at: 0, with: .success(samples))
        await drainMainQueue()

        let content = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        XCTAssertEqual(content.ranges.map(\.title), ["6 Hours", "12 Hours", "24 Hours"])
        XCTAssertEqual(content.selectedRange, .sixHours)
        XCTAssertEqual(content.chartSamples, samples)
        XCTAssertEqual(
            content.glucoseValues.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) },
            [101, 142]
        )
        XCTAssertEqual(content.rows.map(\.sample), Array(samples.reversed()))
        XCTAssertEqual(content.rows.map(\.sample), viewModel.listSamples)
        XCTAssertEqual(GlucoseHistoryViewContent.chartHeight, 220)
        XCTAssertFalse(content.isLoading)
        XCTAssertFalse(content.isEmpty)

        content.selectRange(.twelveHours)

        XCTAssertEqual(viewModel.selectedRange, .twelveHours)
        XCTAssertEqual(loader.requests.count, 2)
        XCTAssertEqual(loader.requests[1].start, Self.now - .hours(12))
        XCTAssertEqual(loader.requests[1].end, Self.now)
        viewModel.stopObserving()
    }

    func testRebuildingPageContentAfterUnitChangeReformatsRows() async {
        let loader = GlucoseHistoryViewTestLoader()
        let viewModel = makeViewModel(loader: loader)
        let preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        let sample = glucoseSample(value: 180, date: Self.now)
        viewModel.startObserving()
        loader.completeRequest(at: 0, with: .success([sample]))
        await drainMainQueue()

        let milligramsContent = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )
        preference.unitDidChange(to: .millimolesPerLiter)
        let millimolesContent = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        XCTAssertNotEqual(
            millimolesContent.rows[0].formattedValue,
            milligramsContent.rows[0].formattedValue
        )
        XCTAssertEqual(
            millimolesContent.rows[0].formattedValue,
            preference.format(sample.quantity)
        )
        viewModel.stopObserving()
    }

    func testErrorContentCanRetryUsingViewModelLoader() async {
        let loader = GlucoseHistoryViewTestLoader()
        let viewModel = makeViewModel(loader: loader)
        let preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        viewModel.startObserving()
        loader.completeRequest(
            at: 0,
            with: .failure(NSError(domain: "GlucoseHistoryViewTests", code: 1))
        )
        await drainMainQueue()

        let content = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        XCTAssertNotNil(content.errorDescription)
        XCTAssertTrue(content.canRetry)
        XCTAssertFalse(content.isLoading)
        XCTAssertFalse(content.isEmpty)

        content.retry()

        XCTAssertEqual(loader.requests.count, 2)
        viewModel.stopObserving()
    }

    func testLoadingAndEmptyContentExposeCompletePageState() async {
        let loader = GlucoseHistoryViewTestLoader()
        let viewModel = makeViewModel(loader: loader)
        let preference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        viewModel.startObserving()

        let loadingContent = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )
        XCTAssertEqual(loadingContent.selectedRange, .sixHours)
        XCTAssertTrue(loadingContent.isLoading)
        XCTAssertFalse(loadingContent.isEmpty)
        XCTAssertNil(loadingContent.errorDescription)
        XCTAssertFalse(loadingContent.canRetry)

        loader.completeRequest(at: 0, with: .success([]))
        await drainMainQueue()
        let emptyContent = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: preference
        )

        XCTAssertFalse(emptyContent.isLoading)
        XCTAssertTrue(emptyContent.isEmpty)
        XCTAssertNil(emptyContent.errorDescription)
        XCTAssertFalse(emptyContent.canRetry)
        viewModel.stopObserving()
    }

    private func makeViewModel(loader: GlucoseHistoryViewTestLoader) -> GlucoseHistoryViewModel {
        GlucoseHistoryViewModel(
            loader: loader.load,
            notificationCenter: NotificationCenter(),
            now: { Self.now }
        )
    }

    private func glucoseSample(
        value: Double,
        date: Date,
        trend: GlucoseTrend? = nil,
        wasUserEntered: Bool = false
    ) -> StoredGlucoseSample {
        StoredGlucoseSample(
            uuid: UUID(),
            startDate: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value),
            trend: trend,
            wasUserEntered: wasUserEntered
        )
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

private final class GlucoseHistoryViewTestLoader {
    struct Request {
        let start: Date
        let end: Date
        let completion: (Result<[StoredGlucoseSample], Error>) -> Void
    }

    private(set) var requests: [Request] = []

    func load(
        start: Date,
        end: Date,
        completion: @escaping (Result<[StoredGlucoseSample], Error>) -> Void
    ) {
        requests.append(Request(start: start, end: end, completion: completion))
    }

    func completeRequest(at index: Int, with result: Result<[StoredGlucoseSample], Error>) {
        requests[index].completion(result)
    }
}
