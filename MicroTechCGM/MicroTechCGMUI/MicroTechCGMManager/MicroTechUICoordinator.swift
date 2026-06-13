import UIKit
import LoopKitUI
import MicroTechCGM

class MicroTechUICoordinator: UINavigationController, CGMManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {
    var cgmManagerOnboardingDelegate: CGMManagerOnboardingDelegate?
    var completionDelegate: CompletionDelegate?
    var cgmManager: MicroTechCGMManager?
    var displayGlucosePreference: DisplayGlucosePreference
    var colorPalette: LoopUIColorPalette

    init(cgmManager: MicroTechCGMManager? = nil,
         colorPalette: LoopUIColorPalette,
         displayGlucosePreference: DisplayGlucosePreference,
         allowDebugFeatures: Bool)
    {
        self.cgmManager = cgmManager
        self.colorPalette = colorPalette
        self.displayGlucosePreference = displayGlucosePreference
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

    private func completeSetup() {
        let manager = MicroTechCGMManager()
        cgmManager = manager
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didCreateCGMManager: manager)
        cgmManagerOnboardingDelegate?.cgmManagerOnboarding(didOnboardCGMManager: manager)
        completionDelegate?.completionNotifyingDidComplete(self)
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
