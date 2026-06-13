import Foundation

extension Bundle {
    var bundleDisplayName: String {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Loop"
    }
}
