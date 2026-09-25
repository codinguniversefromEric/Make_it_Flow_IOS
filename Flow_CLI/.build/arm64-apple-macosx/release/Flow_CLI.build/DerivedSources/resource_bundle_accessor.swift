import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("Flow_CLI_Flow_CLI.bundle").path
        let buildPath = "/Users/giyoshimiken/Documents/Make_it_Flow_IOS/Flow_CLI/.build/arm64-apple-macosx/release/Flow_CLI_Flow_CLI.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}