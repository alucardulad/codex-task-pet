import AppKit
import Darwin
import Foundation

let arguments = CommandLine.arguments

if arguments.contains("--snapshot") {
    do {
        let database = try CodexDatabase()
        try database.debugSnapshot()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let demoMode = arguments.contains("--demo") || arguments.contains("--demo-expanded")
let delegate = MainActor.assumeIsolated {
    let delegate = AppDelegate(demoMode: demoMode)
    app.delegate = delegate
    return delegate
}
app.run()
