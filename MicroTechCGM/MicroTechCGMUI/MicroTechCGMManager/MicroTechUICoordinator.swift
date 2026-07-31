import UIKit
import LoopKit
import LoopKitUI
import MicroTechCGM

class MicroTechUICoordinator: UINavigationController, CGMManagerOnboarding, CGMManagerOnboardingDeviceLogging, CompletionNotifying, UINavigationControllerDelegate {
    var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    var onboardingDeviceLogHandler: CGMManagerOnboardingDeviceLogHandler? {
        didSet {
            configureOnboardingDeviceLogging(on: cgmManager)
        }
    }
    var completionDelegate: CompletionDelegate?
    var cgmManager: MicroTechCGMManager?
    var displayGlucosePreference: DisplayGlucosePreference
    var colorPalette: LoopUIColorPalette
    private let makeCGMManager: () -> MicroTechCGMManager
    private var didFinishOnboarding = false

    init(cgmManager: MicroTechCGMManager? = nil,
         colorPalette: LoopUIColorPalette,
         displayGlucosePreference: DisplayGlucosePreference,
         allowDebugFeatures: Bool,
         makeCGMManager: @escaping () -> MicroTechCGMManager = { MicroTechCGMManager() })
    {
        self.cgmManager = cgmManager
        self.colorPalette = colorPalette
        self.displayGlucosePreference = displayGlucosePreference
        self.makeCGMManager = makeCGMManager
        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        navigationBar.prefersLargeTitles = true
        setViewControllers([initialView()], animated: false)
    }

    private func initialView() -> UIViewController {
        if let cgmManager = cgmManager {
            let view = MicroTechSettingsView(
                didFinish: { [weak self] in
                    guard let self = self else {
                        return
                    }
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                },
                deleteCGM: { [weak self] in
                    self?.deleteCGM()
                },
                viewModel: MicroTechSettingsViewModel(cgmManager: cgmManager, displayGlucosePreference: displayGlucosePreference)
            )
            return DismissibleHostingController(content: view, colorPalette: colorPalette)
        } else {
            let view = MicroTechSetupView(
                didContinue: { [weak self] in
                    self?.completeSetup()
                },
                didCancel: { [weak self] in
                    guard let self = self else {
                        return
                    }
                    self.completionDelegate?.completionNotifyingDidComplete(self)
                }
            )
            .environment(\.appName, Bundle.main.bundleDisplayName)

            let hostingController = DismissibleHostingController(content: view, colorPalette: colorPalette)
            hostingController.navigationItem.largeTitleDisplayMode = .never
            hostingController.title = nil
            return hostingController
        }
    }

    func completeSetup() {
        let manager = makeCGMManager()
        manager.configureConnectionMode(.direct)
        configureOnboardingDeviceLogging(on: manager)
        cgmManager = manager
        manager.addStatusObserver(self, queue: .main)
        manager.scanForSensor()
        finishOnboardingIfReady()
        setViewControllers([initialView()], animated: true)
    }

    private func configureOnboardingDeviceLogging(on manager: MicroTechCGMManager?) {
        manager?.onboardingDeviceLogHandler = onboardingDeviceLogHandler.map { handler in
            { deviceIdentifier, type, message in
                handler(MicroTechCGMManager.pluginIdentifier, deviceIdentifier, type, message)
            }
        }
    }

    private func finishOnboardingIfReady() {
        guard !didFinishOnboarding,
              let manager = cgmManager,
              manager.cgmManagerStatus.hasValidSensorSession else {
            return
        }

        didFinishOnboarding = true
        manager.removeStatusObserver(self)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didCreateCGMManager: manager)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didOnboardCGMManager: manager)
    }

    private func deleteCGM() {
        cgmManager?.delete { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.completionDelegate?.completionNotifyingDidComplete(self)
                self.dismiss(animated: true)
            }
        }
    }
}

extension MicroTechUICoordinator: CGMManagerStatusObserver {
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        guard status.hasValidSensorSession,
              let microTechManager = manager as? MicroTechCGMManager,
              microTechManager === cgmManager else {
            return
        }

        finishOnboardingIfReady()
    }
}
