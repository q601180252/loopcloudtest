//
//  GlucoseHistoryViewModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Combine
import LoopKit
import LoopKitUI
import UIKit

enum GlucoseHistoryRange: CaseIterable, Equatable, Identifiable {
    case sixHours
    case twelveHours
    case twentyFourHours

    var id: Self { self }

    var title: String {
        switch self {
        case .sixHours:
            return NSLocalizedString("6 Hours", comment: "Six hour glucose history range")
        case .twelveHours:
            return NSLocalizedString("12 Hours", comment: "Twelve hour glucose history range")
        case .twentyFourHours:
            return NSLocalizedString("24 Hours", comment: "Twenty-four hour glucose history range")
        }
    }

    var duration: TimeInterval {
        switch self {
        case .sixHours:
            return .hours(6)
        case .twelveHours:
            return .hours(12)
        case .twentyFourHours:
            return .hours(24)
        }
    }

    var xAxisLabelInterval: TimeInterval {
        switch self {
        case .sixHours:
            return .hours(1)
        case .twelveHours:
            return .hours(2)
        case .twentyFourHours:
            return .hours(4)
        }
    }
}

@MainActor
final class GlucoseHistoryViewModel: ObservableObject {
    typealias Loader = (
        Date,
        Date,
        @escaping (Result<[StoredGlucoseSample], Error>) -> Void
    ) -> Void

    @Published private(set) var selectedRange: GlucoseHistoryRange = .sixHours
    @Published private(set) var chartSamples: [StoredGlucoseSample] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorDescription: String?

    var listSamples: [StoredGlucoseSample] {
        Array(chartSamples.reversed())
    }

    var glucoseValues: [GlucoseValue] {
        chartSamples.map { $0 as GlucoseValue }
    }

    var isEmpty: Bool {
        !isLoading && errorDescription == nil && chartSamples.isEmpty
    }

    var chartDateInterval: DateInterval {
        let end = lastQueryEnd ?? now()
        return DateInterval(
            start: end.addingTimeInterval(-selectedRange.duration),
            end: end
        )
    }

    let chartManager: ChartsManager

    private let loader: Loader
    private let notificationCenter: NotificationCenter
    private let glucoseStoreNotificationObject: Any?
    private let now: () -> Date
    private var observerTokens: [NSObjectProtocol] = []
    private var requestGeneration: UInt = 0
    private var isObserving = false
    private var lastQueryEnd: Date?

    init(
        loader: @escaping Loader,
        notificationCenter: NotificationCenter = .default,
        glucoseStoreNotificationObject: Any? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.loader = loader
        self.notificationCenter = notificationCenter
        self.glucoseStoreNotificationObject = glucoseStoreNotificationObject
        self.now = now

        let chart = PredictedGlucoseChart(
            predictedGlucoseBounds: FeatureFlags.predictedGlucoseChartClampEnabled ? .default : nil,
            yAxisStepSizeMGDLOverride: FeatureFlags.predictedGlucoseChartClampEnabled ? 40 : nil
        )
        chart.glucoseDisplayRange = LoopConstants.glucoseChartDefaultDisplayRangeWide
        chartManager = ChartsManager(
            colors: .primary,
            settings: .default,
            charts: [chart],
            traitCollection: .current,
            xAxisLabelInterval: GlucoseHistoryRange.sixHours.xAxisLabelInterval
        )
    }

    func startObserving() {
        guard !isObserving else {
            return
        }

        isObserving = true
        observerTokens = [
            notificationCenter.addObserver(
                forName: GlucoseStore.glucoseSamplesDidChange,
                object: glucoseStoreNotificationObject,
                queue: .main
            ) { [weak self] _ in
                self?.refreshOnMain()
            },
            notificationCenter.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshOnMain()
            }
        ]
        refresh()
    }

    func stopObserving() {
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
        isObserving = false
        requestGeneration &+= 1
        isLoading = false
    }

    func selectRange(_ range: GlucoseHistoryRange) {
        guard range != selectedRange else {
            return
        }

        selectedRange = range
        chartManager.xAxisLabelInterval = range.xAxisLabelInterval
        chartSamples = []
        lastQueryEnd = nil
        errorDescription = nil
        if isObserving {
            refresh()
        }
    }

    func refresh() {
        guard isObserving else {
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        let end = now()
        let start = end.addingTimeInterval(-selectedRange.duration)
        isLoading = true
        errorDescription = nil

        loader(start, end) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.isObserving,
                      generation == self.requestGeneration
                else {
                    return
                }

                self.isLoading = false
                switch result {
                case .success(let samples):
                    self.lastQueryEnd = end
                    self.chartSamples = samples
                case .failure(let error):
                    self.errorDescription = error.localizedDescription
                }
            }
        }
    }

    private nonisolated func refreshOnMain() {
        Task { @MainActor [weak self] in
            self?.refresh()
        }
    }
}
