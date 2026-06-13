import os.log
import LoopKitUI
import MicroTechCGM
import MicroTechCGMUI

public class MicroTechCGMPlugin: NSObject, CGMManagerUIPlugin {
    private let log = OSLog(subsystem: "org.loopkit.MicroTechCGMPlugin", category: "MicroTechCGMPlugin")

    public var cgmManagerType: CGMManagerUI.Type? {
        MicroTechCGMManager.self
    }

    public override init() {
        super.init()
        os_log("Instantiated", log: log, type: .default)
    }
}
