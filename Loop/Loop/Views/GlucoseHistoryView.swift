//
//  GlucoseHistoryView.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

struct GlucoseHistoryRowContent {
    let sample: StoredGlucoseSample
    let formattedValue: String
    let trend: GlucoseTrend?
    let isManual: Bool

    init(
        sample: StoredGlucoseSample,
        displayGlucosePreference: DisplayGlucosePreference
    ) {
        self.sample = sample
        self.formattedValue = displayGlucosePreference.format(sample.quantity)
        self.trend = sample.trend
        self.isManual = sample.wasUserEntered
    }
}

@MainActor
struct GlucoseHistoryViewContent {
    static let chartHeight: CGFloat = 220

    let ranges: [GlucoseHistoryRange]
    let selectedRange: GlucoseHistoryRange
    let chartSamples: [StoredGlucoseSample]
    let glucoseValues: [GlucoseValue]
    let rows: [GlucoseHistoryRowContent]
    let isLoading: Bool
    let errorDescription: String?
    let canRetry: Bool
    let isEmpty: Bool
    let selectRange: (GlucoseHistoryRange) -> Void
    let retry: () -> Void

    var terminalStateAccessibilityIdentifier: String? {
        guard !isLoading else {
            return nil
        }

        return "glucoseHistory.terminal.\(selectedRange.accessibilityIdentifierComponent)"
    }

    init(
        viewModel: GlucoseHistoryViewModel,
        displayGlucosePreference: DisplayGlucosePreference
    ) {
        ranges = GlucoseHistoryRange.allCases
        selectedRange = viewModel.selectedRange
        chartSamples = viewModel.chartSamples
        glucoseValues = viewModel.glucoseValues
        rows = viewModel.listSamples.map {
            GlucoseHistoryRowContent(
                sample: $0,
                displayGlucosePreference: displayGlucosePreference
            )
        }
        isLoading = viewModel.isLoading
        errorDescription = viewModel.errorDescription
        canRetry = viewModel.errorDescription != nil
        isEmpty = viewModel.isEmpty
        selectRange = { viewModel.selectRange($0) }
        retry = { viewModel.refresh() }
    }
}

struct GlucoseHistoryView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @ObservedObject var viewModel: GlucoseHistoryViewModel

    @State private var isInteractingWithChart = false

    var body: some View {
        let page = GlucoseHistoryViewContent(
            viewModel: viewModel,
            displayGlucosePreference: displayGlucosePreference
        )

        VStack(spacing: 0) {
            rangePicker(page: page)
            chart(page: page)
            Divider()
            ZStack {
                detail(page: page)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                page.terminalStateAccessibilityIdentifier ?? "glucoseHistory.loading"
            )
        }
        .navigationTitle(Text("Glucose History", comment: "Title for the glucose history screen"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startObserving()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }

    private func rangePicker(page: GlucoseHistoryViewContent) -> some View {
        Picker(
            selection: Binding(
                get: { page.selectedRange },
                set: page.selectRange
            ),
            label: Text("History Range", comment: "Label for the glucose history range picker")
        ) {
            ForEach(page.ranges) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .accessibilityIdentifier("glucoseHistory.range")
    }

    private func chart(page: GlucoseHistoryViewContent) -> some View {
        ZStack(alignment: .topTrailing) {
            PredictedGlucoseChartView(
                chartManager: viewModel.chartManager,
                glucoseUnit: displayGlucosePreference.unit,
                glucoseValues: page.glucoseValues,
                predictedGlucoseValues: [],
                targetGlucoseSchedule: nil,
                preMealOverride: nil,
                scheduleOverride: nil,
                dateInterval: viewModel.chartDateInterval,
                isInteractingWithChart: $isInteractingWithChart
            )

            if page.isLoading {
                ProgressView()
                    .padding(12)
            }
        }
        .frame(height: GlucoseHistoryViewContent.chartHeight)
        .accessibilityIdentifier("glucoseHistory.chart")
    }

    @ViewBuilder
    private func detail(page: GlucoseHistoryViewContent) -> some View {
        if let errorDescription = page.errorDescription {
            VStack(spacing: 16) {
                Spacer()
                Text(errorDescription)
                    .multilineTextAlignment(.center)

                if page.canRetry {
                    Button(action: page.retry) {
                        Label(
                            "Retry",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .accessibilityIdentifier("glucoseHistory.retry")
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("glucoseHistory.error")
        } else if page.rows.isEmpty {
            if page.isLoading {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(
                    "No glucose data in this period",
                    comment: "Message shown when a glucose history range contains no readings"
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .accessibilityIdentifier("glucoseHistory.empty")
            }
        } else {
            List {
                Section(
                    header: Text(
                        "Readings",
                        comment: "Section title for glucose history readings"
                    )
                ) {
                    ForEach(Array(page.rows.enumerated()), id: \.offset) { offset, row in
                        readingRow(row)
                            .accessibilityIdentifier("glucoseHistory.row.\(offset)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("glucoseHistory.list")
        }
    }

    private func readingRow(_ row: GlucoseHistoryRowContent) -> some View {
        HStack {
            Text(row.sample.startDate, style: .time)

            if row.isManual {
                Text("Manual", comment: "Label for a manually entered glucose reading")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(row.formattedValue)
                .monospacedDigit()

            if let trend = row.trend {
                trend.filledImage
                    .accessibilityLabel(Text(trend.localizedDescription))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(row.formattedValue))
    }
}
