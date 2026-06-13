import UIKit
import LoopKit
import LoopKitUI
import MicroTechCGM

public struct MicroTechDeviceStatusHighlight: DeviceStatusHighlight, Equatable {
    public let localizedMessage: String
    public let imageName: String
    public let state: DeviceStatusHighlightState

    public init(localizedMessage: String, imageName: String, state: DeviceStatusHighlightState) {
        self.localizedMessage = localizedMessage
        self.imageName = imageName
        self.state = state
    }
}

extension MicroTechCGMManager: CGMManagerUI {
    public static var onboardingImage: UIImage? {
        nil
    }

    public var smallImage: UIImage? {
        nil
    }

    public static func setupViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool, prefersToSkipUserInteraction: Bool) -> SetupUIResult<CGMManagerViewController, CGMManagerUI> {
        .userInteractionRequired(MicroTechUICoordinator(colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference, allowDebugFeatures: allowDebugFeatures))
    }

    public func settingsViewController(bluetoothProvider: BluetoothProvider, displayGlucosePreference: DisplayGlucosePreference, colorPalette: LoopUIColorPalette, allowDebugFeatures: Bool) -> CGMManagerViewController {
        MicroTechUICoordinator(cgmManager: self, colorPalette: colorPalette, displayGlucosePreference: displayGlucosePreference, allowDebugFeatures: allowDebugFeatures)
    }

    public var cgmStatusHighlight: DeviceStatusHighlight? {
        let state = self.state
        guard state.sensorSerial != nil else {
            return nil
        }

        if state.lastReadingDate.map({ Date().timeIntervalSince($0) <= 15 * 60 }) != true {
            return MicroTechDeviceStatusHighlight(
                localizedMessage: LocalizedString("Signal\nLoss", comment: "MicroTech status highlight text for signal loss"),
                imageName: "exclamationmark.circle.fill",
                state: .warning
            )
        }

        return nil
    }

    public var cgmLifecycleProgress: DeviceLifecycleProgress? {
        nil
    }

    public var cgmStatusBadge: DeviceStatusBadge? {
        nil
    }
}
