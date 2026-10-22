import AppKit
import SwiftUI

struct PetRootView: View {
    @ObservedObject var store: TaskStore

    private var visualState: WhalePetState {
        if store.isDraggingPet { return .drag }
        if store.isDoubleClicking { return .doubleClick }
        if store.isSleeping { return .sleep }
        if store.isEatingRice { return .eatRice }

        if let completion = store.currentCompletion {
            return completion.status == .completed ? .happy : .angry
        }
        if store.monitorError != nil { return .angry }
        if store.patrolEnabled { return .patrol }
        if store.isHoveringPet { return .hover }
        if store.hasRunningWork { return .working }
        return .standby
    }

    private var windowSize: NSSize {
        PetLayout.windowSize(
            hasCompletion: store.currentCompletion != nil,
            activeCount: store.activeCount,
            hasError: store.monitorError != nil,
            petScale: store.petScale
        )
    }

    private var accessorySize: NSSize {
        PetLayout.accessorySize(
            hasCompletion: store.currentCompletion != nil,
            activeCount: store.activeCount,
            hasError: store.monitorError != nil
        )
    }

    private var petSize: NSSize {
        PetLayout.petSize(for: store.petScale)
    }

    var body: some View {
        VStack(spacing: PetLayout.itemSpacing) {
            accessory
                .frame(width: accessorySize.width, height: accessorySize.height, alignment: .bottom)
                .zIndex(4)

            ScaledWhalePetView(
                state: visualState,
                patrolDirection: store.patrolDirection,
                petScale: store.petScale,
                isAnimating: !store.isDraggingPet && !store.panelExpanded
            )
            .frame(width: petSize.width, height: petSize.height)
            .overlay {
                PetInteractionView(store: store)
            }
        }
        .padding(.horizontal, PetLayout.horizontalPadding)
        .padding(.vertical, PetLayout.verticalPadding)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .bottom)
        .background(Color.clear)
    }

    @ViewBuilder
    private var accessory: some View {
        if let completion = store.currentCompletion {
            CompletionSpeechBubble(store: store, event: completion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else if store.activeCount > 0 {
            RunningStatusPill(count: store.activeCount)
        } else {
            IdleStatusPill(hasError: store.monitorError != nil)
        }
    }
}

private struct ScaledWhalePetView: View {
    let state: WhalePetState
    let patrolDirection: CGFloat
    let petScale: CGFloat
    let isAnimating: Bool

    private var displaySize: NSSize {
        PetLayout.petSize(for: petScale)
    }

    var body: some View {
        GeometryReader { proxy in
            WhalePetView(
                state: state,
                isFlipped: state == .patrol && patrolDirection < 0,
                isAnimating: isAnimating
            )
            .frame(width: PetLayout.petBaseSize.width, height: PetLayout.petBaseSize.height)
            .scaleEffect(petScale * PetLayout.petVisualScale, anchor: .bottom)
            .position(
                x: proxy.size.width / 2,
                y: proxy.size.height - PetLayout.petBaseSize.height / 2
            )
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }
}
