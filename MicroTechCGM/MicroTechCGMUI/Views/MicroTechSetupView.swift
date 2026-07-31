import Foundation
import SwiftUI
import LoopKitUI
import MicroTechCGM

struct MicroTechSetupView: View {
    var didContinue: ((MicroTechCGMConnectionMode) -> Void)?
    var didCancel: (() -> Void)?

    @Environment(\.appName) private var appName
    @State private var connectionMode: MicroTechCGMConnectionMode = .direct

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Spacer()

            Text(LocalizedString("MicroTech LinX", comment: "Title on MicroTech setup view"))
                .font(.largeTitle)
                .fontWeight(.semibold)
                .accessibilityIdentifier("microtech.setup.title")

            Text(String(format: LocalizedString("%1$@ can read MicroTech LinX CGM data after the sensor is connected.", comment: "Description on MicroTech setup view (1: appName)"), appName))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)

            Picker(LocalizedString("Connection Mode", comment: "Picker label for MicroTech connection mode"), selection: $connectionMode) {
                Text(LocalizedString("直接连接", comment: "Direct MicroTech LinX connection mode"))
                    .tag(MicroTechCGMConnectionMode.direct)
                Text(LocalizedString("广播数据", comment: "Broadcast MicroTech LinX data mode"))
                    .tag(MicroTechCGMConnectionMode.broadcast)
            }
            .pickerStyle(SegmentedPickerStyle())
            .accessibilityIdentifier("microtech.setup.connectionMode")

            Spacer()

            Button(action: { didContinue?(connectionMode) }) {
                Text(LocalizedString("Search Nearby Devices", comment: "Button title for starting nearby MicroTech device search"))
                    .actionButtonStyle(.primary)
            }
            .accessibilityIdentifier("microtech.setup.continue")

            Button(action: { didCancel?() }) {
                Text(LocalizedString("Cancel", comment: "Button title for cancelling setup"))
                    .padding(.top, 20)
            }
            .accessibilityIdentifier("microtech.setup.cancel")
        }
        .padding()
        .environment(\.horizontalSizeClass, .compact)
        .navigationBarTitle("")
        .navigationBarHidden(true)
    }
}
