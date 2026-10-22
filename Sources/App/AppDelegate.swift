import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let demoMode: Bool
    private var store: TaskStore?
    private var windowController: PetWindowController?

    init(demoMode: Bool) {
        self.demoMode = demoMode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let store = TaskStore(demoMode: demoMode)
        if CommandLine.arguments.contains("--demo-expanded") {
            store.panelExpanded = true
        }
        let controller = PetWindowController(store: store)
        self.store = store
        self.windowController = controller
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.savePosition()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
