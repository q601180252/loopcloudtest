import Foundation
import SwiftUI
import LoopKitUI

struct MicroTechSetupView: View {
    var didContinue: ((String) -> Void)?
    var didCancel: (() -> Void)?

    @Environment(\.appName) private var appName
    @State private var deviceNameOrSerial = ""

    private var normalizedDeviceNameOrSerial: String {
        deviceNameOrSerial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

            TextField(
                LocalizedString("AiDEX-222227HAUZ or sensor serial", comment: "MicroTech setup device name or serial placeholder"),
                text: $deviceNameOrSerial
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .accessibilityIdentifier("microtech.setup.deviceNameOrSerial")

            Spacer()

            Button(action: { didContinue?(normalizedDeviceNameOrSerial) }) {
                Text(LocalizedString("Continue", comment: "Button title for starting setup"))
                    .actionButtonStyle(.primary)
            }
            .disabled(normalizedDeviceNameOrSerial.isEmpty)
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
