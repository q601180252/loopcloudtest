import os.log

extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "org.loopkit.MicroTechCGM", category: category)
    }
}
