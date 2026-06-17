import Foundation
import SwiftUI
import LoopKitUI

struct MicroTechSetupView: View {
    var didContinue: (() -> Void)?
    var didCancel: (() -> Void)?

    @Environment(\.appName) private var appName

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

            Spacer()

            Button(action: { didContinue?() }) {
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
