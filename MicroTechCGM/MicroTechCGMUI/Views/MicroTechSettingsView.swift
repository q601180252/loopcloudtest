import Foundation
import SwiftUI
import LoopKitUI

struct MicroTechSettingsView: View {
    var didFinish: (() -> Void)
    var deleteCGM: (() -> Void)
    @ObservedObject var viewModel: MicroTechSettingsViewModel

    @State private var showingDeletionSheet = false

    var body: some View {
        List {
            Section(LocalizedString("Device", comment: "MicroTech settings device section title")) {
                LabeledValueView(label: LocalizedString("Name", comment: "MicroTech settings device name label"),
                                 value: viewModel.deviceName ?? LocalizedString("MicroTech LinX", comment: "Default MicroTech device name"))
                LabeledValueView(label: LocalizedString("Sensor Serial", comment: "MicroTech settings sensor serial label"),
                                 value: viewModel.sensorSerial)
            }

            Section(LocalizedString("Last Reading", comment: "MicroTech settings last reading section title")) {
                LabeledDateView(label: LocalizedString("Time", comment: "MicroTech settings last reading time label"),
                                date: viewModel.lastReadingDate,
                                dateFormatter: viewModel.dateFormatter)
                LabeledValueView(label: LocalizedString("Glucose", comment: "MicroTech settings glucose label"),
                                 value: viewModel.lastGlucoseString)
            }

            Section(LocalizedString("Configuration", comment: "MicroTech settings configuration section title")) {
                TextField(
                    LocalizedString("AiDEX-222227HAUZ or sensor serial", comment: "MicroTech device name or serial placeholder"),
                    text: $viewModel.deviceNameOrSerialInput
                )
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)

                Button(LocalizedString("Save and Scan", comment: "MicroTech save sensor and scan button label")) {
                    _ = viewModel.saveSensorAndScan()
                }
                .disabled(viewModel.deviceNameOrSerialInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Toggle(LocalizedString("Upload Readings", comment: "MicroTech settings upload toggle label"),
                       isOn: $viewModel.uploadReadings)
            }

            Section {
                Button(viewModel.scanButtonTitle) {
                    viewModel.scanForSensor()
                }

                if viewModel.isScanning {
                    HStack {
                        Text(LocalizedString("Scanning", comment: "MicroTech settings scanning status label"))
                        Spacer()
                        ProgressView()
                    }
                }

                deleteCGMButton
            }
        }
        .insetGroupedListStyle()
        .navigationBarItems(trailing: doneButton)
        .navigationBarTitle(LocalizedString("MicroTech LinX", comment: "Navigation title for MicroTech settings"))
        .onAppear {
            viewModel.refresh()
        }
    }

    private var doneButton: some View {
        Button(LocalizedString("Done", comment: "Button title to close MicroTech settings")) {
            didFinish()
        }
    }

    private var deleteCGMButton: some View {
        Button(action: {
            showingDeletionSheet = true
        }, label: {
            Text(LocalizedString("Delete CGM", comment: "Button label for removing MicroTech CGM"))
                .foregroundColor(.red)
        })
        .actionSheet(isPresented: $showingDeletionSheet) {
            ActionSheet(
                title: Text(LocalizedString("Are you sure you want to delete this CGM?", comment: "MicroTech delete CGM confirmation title")),
                buttons: [
                    .destructive(Text(LocalizedString("Delete CGM", comment: "MicroTech delete CGM confirmation button"))) {
                        deleteCGM()
                    },
                    .cancel(),
                ]
            )
        }
    }
}
