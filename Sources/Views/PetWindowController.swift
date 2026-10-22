import AppKit
import Combine
import SwiftUI

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetWindowController: NSObject {
    static var shared: PetWindowController?

    private(set) var window: PetWindow?
    private let store: TaskStore
    private var cancellables = Set<AnyCancellable>()
    private var resizeScheduled = false
    private var dragInProgress = false
    private var resizeDeferred = false
    private var taskPopover: NSPopover?
    private var patrolTimer: Timer?
    private var lastPatrolPositionSave = Date.distantPast
    // Keep resizing anchored to the pet's bottom center, even if AppKit
    // temporarily resizes the hosting view before our layout pass runs.
    private var frameAnchor: NSPoint?

    private let positionXKey = "AgentPet.positionX"
    private let positionYKey = "AgentPet.positionY"

    init(store: TaskStore) {
        self.store = store
        super.init()
        PetWindowController.shared = self
        createWindow()
        observeChanges()
        syncTaskPopover(expanded: store.panelExpanded)
    }

    private func createWindow() {
        let size = desiredSize()
        let origin = restoredOrigin(for: size)
        let window = PetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.title = "Codex 任务宠物"

        let hostingView = NSHostingView(rootView: PetRootView(store: store))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView

        self.window = window
        frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)
        window.orderFrontRegardless()
    }

    private func observeChanges() {
        Publishers.CombineLatest4(
            store.$currentCompletion,
            store.$activeTasks,
            store.$monitorError,
            store.$petScale
        )
        .dropFirst()
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleResize()
            }
        }
        .store(in: &cancellables)

        store.$panelExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                MainActor.assumeIsolated {
                    self?.syncTaskPopover(expanded: expanded)
                }
            }
            .store(in: &cancellables)

        store.$patrolEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if enabled {
                        self.startPatrolTimer()
                    } else {
                        self.stopPatrolTimer()
                        self.savePosition()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startPatrolTimer() {
        guard patrolTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.patrolTick()
            }
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        patrolTimer = timer
    }

    private func stopPatrolTimer() {
        patrolTimer?.invalidate()
        patrolTimer = nil
    }

    private func patrolTick() {
        guard let window,
              store.patrolEnabled,
              !dragInProgress,
              !store.panelExpanded,
              !store.isDraggingPet,
              !store.isDoubleClicking,
              !store.isSleeping,
              !store.isEatingRice,
              store.currentCompletion == nil,
              store.monitorError == nil,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visible = screen.visibleFrame.insetBy(dx: 6, dy: 0)
        let minimumX = visible.minX
        let maximumX = visible.maxX - window.frame.width
        guard maximumX > minimumX else { return }

        var direction = store.patrolDirection
        if window.frame.minX <= minimumX + 0.5 {
            direction = 1
        } else if window.frame.minX >= maximumX - 0.5 {
            direction = -1
        }
        store.setPatrolDirection(direction)

        let step = 2.0
        let nextX = min(max(window.frame.minX + direction * step, minimumX), maximumX)
        if abs(nextX - window.frame.minX) > 0.01 {
            window.setFrameOrigin(NSPoint(x: nextX, y: window.frame.minY))
            frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)

            let now = Date()
            if now.timeIntervalSince(lastPatrolPositionSave) >= 5 {
                lastPatrolPositionSave = now
                savePosition()
            }
        }
    }

    private func scheduleResize() {
        if dragInProgress {
            resizeDeferred = true
            return
        }
        guard !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.resizeScheduled = false
            self?.updateWindowSize()
        }
    }

    private func updateWindowSize() {
        guard let window else { return }
        let targetSize = desiredSize()
        let currentFrame = window.frame
        let anchor = frameAnchor ?? NSPoint(x: currentFrame.midX, y: currentFrame.minY)
        var newFrame = NSRect(
            x: anchor.x - targetSize.width / 2,
            y: anchor.y,
            width: targetSize.width,
            height: targetSize.height
        )

        if let screen = screen(containing: NSPoint(x: newFrame.midX, y: newFrame.midY)) {
            let visible = screen.visibleFrame
            newFrame.origin.x = min(max(visible.minX, newFrame.origin.x), visible.maxX - newFrame.width)
            newFrame.origin.y = min(max(visible.minY, newFrame.origin.y), visible.maxY - newFrame.height)
        }

        // AppKit may resize an NSHostingView before this pass. Only skip after applying
        // the stored anchor so the pet never drifts vertically during scale changes.
        if abs(currentFrame.width - newFrame.width) <= 1,
           abs(currentFrame.height - newFrame.height) <= 1,
           abs(currentFrame.minX - newFrame.minX) <= 1,
           abs(currentFrame.minY - newFrame.minY) <= 1 {
            frameAnchor = NSPoint(x: newFrame.midX, y: newFrame.minY)
            return
        }

        // The hosting view contains continuously animated SwiftUI content. Animating the
        // transparent borderless window at the same time causes the whole pet to jitter.
        window.setFrame(newFrame, display: true, animate: false)
        frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)
        savePosition()
    }

    private func desiredSize() -> NSSize {
        PetLayout.windowSize(
            hasCompletion: store.currentCompletion != nil,
            activeCount: store.activeCount,
            hasError: store.monitorError != nil,
            petScale: store.petScale
        )
    }

    private func syncTaskPopover(expanded: Bool) {
        if expanded {
            showTaskPopover()
        } else if let popover = taskPopover {
            // 关闭后释放 SwiftUI 弹窗和其图层，避免闲置时长期占用内存。
            popover.delegate = nil
            popover.performClose(nil)
            taskPopover = nil
        }
    }

    private func showTaskPopover() {
        guard let window, let contentView = window.contentView, window.isVisible else {
            return
        }
        if taskPopover?.isShown == true { return }

        let popover = taskPopover ?? makeTaskPopover()
        taskPopover = popover
        let petSize = PetLayout.petSize(for: store.petScale)
        let anchorWidth = min(petSize.width, max(48, window.frame.width - 24))
        let anchorRect = NSRect(
            x: (contentView.bounds.width - anchorWidth) / 2,
            y: PetLayout.verticalPadding,
            width: anchorWidth,
            height: max(48, petSize.height - PetLayout.verticalPadding)
        )
        popover.show(
            relativeTo: anchorRect,
            of: contentView,
            preferredEdge: preferredPopoverEdge(for: window)
        )
    }

    private func preferredPopoverEdge(for window: NSWindow) -> NSRectEdge {
        guard let screen = window.screen ?? NSScreen.main else { return .minX }
        let leftSpace = window.frame.minX - screen.visibleFrame.minX
        let rightSpace = screen.visibleFrame.maxX - window.frame.maxX
        return rightSpace > leftSpace ? .maxX : .minX
    }

    private func makeTaskPopover() -> NSPopover {
        let popover = NSPopover()
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.contentSize = PetLayout.taskPanelWindowSize
        let hostingController = NSHostingController(
            rootView: TaskPanelPopoverContent(store: store)
        )
        hostingController.view.wantsLayer = true
        popover.contentViewController = hostingController
        return popover
    }

    func beginWindowDrag() {
        dragInProgress = true
        stopPatrolTimer()
        if taskPopover?.isShown == true {
            store.closePanel()
        }
    }

    func endWindowDrag() {
        dragInProgress = false
        store.setDraggingPet(false)
        if store.patrolEnabled {
            startPatrolTimer()
        }
        if resizeDeferred {
            resizeDeferred = false
            scheduleResize()
        }
    }

    func movePetWindow(to proposedOrigin: NSPoint) {
        guard let window else { return }
        let targetCenter = NSPoint(
            x: proposedOrigin.x + window.frame.width / 2,
            y: proposedOrigin.y + window.frame.height / 2
        )
        guard let screen = screen(containing: targetCenter) else {
            window.setFrameOrigin(proposedOrigin)
            frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)
            return
        }

        let visible = screen.visibleFrame
        let next = NSPoint(
            x: min(max(visible.minX, proposedOrigin.x), visible.maxX - window.frame.width),
            y: min(max(visible.minY, proposedOrigin.y), visible.maxY - window.frame.height)
        )
        window.setFrameOrigin(next)
        frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? window?.screen
            ?? NSScreen.main
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: positionXKey) != nil,
           defaults.object(forKey: positionYKey) != nil {
            let point = NSPoint(
                x: defaults.double(forKey: positionXKey),
                y: defaults.double(forKey: positionYKey)
            )
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -12, dy: -12).contains(point) }) {
                return clampedOrigin(point, size: size)
            }
        }
        return defaultOrigin(for: size)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 38)
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2))
        }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(visible.minX, origin.x), visible.maxX - size.width),
            y: min(max(visible.minY, origin.y), visible.maxY - size.height)
        )
    }

    func savePosition() {
        guard let window else { return }
        let defaults = UserDefaults.standard
        defaults.set(window.frame.origin.x, forKey: positionXKey)
        defaults.set(window.frame.origin.y, forKey: positionYKey)
    }

    func resetPosition() {
        guard let window else { return }
        store.closePanel()
        let size = desiredSize()
        let origin = defaultOrigin(for: size)
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        frameAnchor = NSPoint(x: window.frame.midX, y: window.frame.minY)
        savePosition()
    }
}

extension PetWindowController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        taskPopover = nil
        if store.panelExpanded {
            store.closePanel()
        }
    }
}
