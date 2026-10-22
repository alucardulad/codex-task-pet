import AppKit
import SwiftUI

@MainActor
struct PetInteractionView: NSViewRepresentable {
    let store: TaskStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> PetInteractionNSView {
        let view = PetInteractionNSView()
        let coordinator = context.coordinator
        coordinator.view = view

        view.onPrimaryMouseDown = { [weak coordinator] in
            coordinator?.primaryMouseDown()
        }
        view.onHoverChanged = { [weak coordinator] hovering in
            coordinator?.setHovering(hovering)
        }
        view.onClick = { [weak coordinator] in
            coordinator?.primaryMouseUp()
        }
        view.onDoubleClick = { [weak coordinator] in
            coordinator?.doubleClick()
        }
        view.onDragBegan = { [weak coordinator] in
            coordinator?.beginDrag()
        }
        view.onDragMoved = { [weak coordinator] point in
            coordinator?.movePet(to: point)
        }
        view.onDragEnded = { [weak coordinator] in
            coordinator?.endDrag()
        }
        view.onContextMenu = { [weak coordinator, weak view] event in
            guard let coordinator, let view else { return }
            coordinator.showMenu(for: event, in: view)
        }
        view.toolTip = "拖动移动 · 单击任务 · 双击回应 · 右键设置"
        return view
    }

    func updateNSView(_ nsView: PetInteractionNSView, context: Context) {
        context.coordinator.store = store
    }

    @MainActor
    final class Coordinator: NSObject {
        var store: TaskStore
        weak var view: PetInteractionNSView?
        private var panelWasExpandedOnMouseDown = false

        init(store: TaskStore) {
            self.store = store
        }

        func primaryMouseDown() {
            panelWasExpandedOnMouseDown = store.panelExpanded
            if panelWasExpandedOnMouseDown {
                store.closePanel()
            }
        }

        func primaryMouseUp() {
            defer { panelWasExpandedOnMouseDown = false }
            guard !panelWasExpandedOnMouseDown else { return }
            store.togglePanel()
        }

        func setHovering(_ hovering: Bool) {
            store.setHoveringPet(hovering)
        }

        func doubleClick() {
            panelWasExpandedOnMouseDown = false
            store.triggerDoubleClick()
        }

        func beginDrag() {
            PetWindowController.shared?.beginWindowDrag()
        }

        func movePet(to origin: NSPoint) {
            PetWindowController.shared?.movePetWindow(to: origin)
        }

        func endDrag() {
            panelWasExpandedOnMouseDown = false
            PetWindowController.shared?.endWindowDrag()
            PetWindowController.shared?.savePosition()
        }

        func showMenu(for event: NSEvent, in view: NSView) {
            if store.panelExpanded {
                store.closePanel()
            }
            let menu = makeMenu()
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            addItem(
                to: menu,
                title: store.panelExpanded ? "收起任务面板" : "查看 Agent 任务",
                action: #selector(togglePanelAction)
            )

            menu.addItem(.separator())
            addItem(
                to: menu,
                title: store.isSleeping ? "叫醒鲸鱼娘" : "让她睡一会儿",
                action: #selector(toggleSleepAction)
            )
            addItem(to: menu, title: "喂一碗大白饭", action: #selector(feedRiceAction))
            addItem(
                to: menu,
                title: store.patrolEnabled ? "停止自动巡视" : "自动巡视桌面",
                action: #selector(togglePatrolAction)
            )

            menu.addItem(.separator())
            let currentPercent = Int((store.petScale * 100).rounded())
            let sizeItem = NSMenuItem(
                title: "鲸鱼娘大小（当前 \(currentPercent)%）",
                action: nil,
                keyEquivalent: ""
            )
            sizeItem.submenu = makeSizeMenu()
            menu.addItem(sizeItem)

            let scaleDownItem = addItem(to: menu, title: "缩小 10%", action: #selector(scaleDown))
            scaleDownItem.isEnabled = store.petScale > TaskStore.minimumPetScale + 0.001
            let scaleUpItem = addItem(to: menu, title: "放大 10%", action: #selector(scaleUp))
            scaleUpItem.isEnabled = store.petScale < TaskStore.maximumPetScale - 0.001

            menu.addItem(.separator())
            addItem(
                to: menu,
                title: store.soundEnabled ? "关闭完成提示音" : "开启完成提示音",
                action: #selector(toggleSound)
            )
            addItem(
                to: menu,
                title: store.launchAtLogin ? "关闭开机自动启动" : "开机自动启动",
                action: #selector(toggleLaunchAtLogin)
            )

            menu.addItem(.separator())
            addItem(to: menu, title: "移动回屏幕右下角", action: #selector(resetPosition))
            addItem(to: menu, title: "退出任务宠物", action: #selector(quitApp))
            return menu
        }

        private func makeSizeMenu() -> NSMenu {
            let sizeMenu = NSMenu(title: "大小")
            sizeMenu.autoenablesItems = false

            for percent in stride(from: 100, through: 10, by: -10) {
                let scale = CGFloat(percent) / 100
                let item = NSMenuItem(
                    title: "\(percent)%",
                    action: #selector(selectScale(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: Double(scale))
                item.state = abs(store.petScale - scale) < 0.01 ? .on : .off
                sizeMenu.addItem(item)
            }

            return sizeMenu
        }

        @discardableResult
        private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }

        private func addDisabledItem(to menu: NSMenu, title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        @objc private func togglePanelAction() {
            store.togglePanel()
        }

        @objc private func toggleSleepAction() {
            store.toggleSleep()
        }

        @objc private func feedRiceAction() {
            store.feedRice()
        }

        @objc private func togglePatrolAction() {
            store.togglePatrol()
        }

        @objc private func selectScale(_ sender: NSMenuItem) {
            guard let number = sender.representedObject as? NSNumber else { return }
            store.setPetScale(CGFloat(number.doubleValue))
        }

        @objc private func scaleDown() {
            store.adjustPetScale(by: -TaskStore.petScaleStep)
        }

        @objc private func scaleUp() {
            store.adjustPetScale(by: TaskStore.petScaleStep)
        }

        @objc private func toggleSound() {
            store.toggleSound()
        }

        @objc private func toggleLaunchAtLogin() {
            store.toggleLaunchAtLogin()
        }

        @objc private func resetPosition() {
            PetWindowController.shared?.resetPosition()
        }

        @objc private func quitApp() {
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
final class PetInteractionNSView: NSView {
    var onPrimaryMouseDown: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    private var mouseDownLocation: NSPoint?
    private var windowOrigin: NSPoint?
    private var isDragging = false
    private var trackingArea: NSTrackingArea?
    private var pendingSingleClick: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onPrimaryMouseDown?()
        mouseDownLocation = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation, let windowOrigin else { return }

        let current = NSEvent.mouseLocation
        let distance = hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y)
        if !isDragging && distance > 2.5 {
            isDragging = true
            onDragBegan?()
        }
        guard isDragging else { return }

        let proposedOrigin = NSPoint(
            x: windowOrigin.x + current.x - mouseDownLocation.x,
            y: windowOrigin.y + current.y - mouseDownLocation.y
        )
        onDragMoved?(proposedOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?()
        } else if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick?()
        } else {
            pendingSingleClick?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.pendingSingleClick = nil
                self?.onClick?()
            }
            pendingSingleClick = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NSEvent.doubleClickInterval,
                execute: workItem
            )
        }
        resetDragState()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    private func resetDragState() {
        mouseDownLocation = nil
        windowOrigin = nil
        isDragging = false
    }
}
