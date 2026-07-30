import Foundation
import os.log

extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "org.loopkit.MicroTechCGM", category: category)
    }
}

enum MicroTechDiagnosticLog {
    static func dataFields(lengthName: String, hexName: String, data: Data) -> String {
        "\(lengthName)=\(data.count) \(hexName)=\(data.microTechHexadecimalString)"
    }

    static func errorFields(_ error: Error?) -> String {
        guard let error else {
            return "errorDomain=nil errorCode=nil errorDescription=nil"
        }

        let nsError = error as NSError
        return "errorDomain=\(nsError.domain) errorCode=\(nsError.code) errorDescription=\(nsError.localizedDescription)"
    }
}
