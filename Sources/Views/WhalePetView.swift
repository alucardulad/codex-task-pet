import AppKit
import ImageIO
import SwiftUI

@MainActor
private enum WhaleAssetStore {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 6 * 1024 * 1024
        return cache
    }()
    private static var missingStates = Set<WhalePetState>()

    static func image(for state: WhalePetState) -> NSImage? {
        let key = state.rawValue as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard !missingStates.contains(state) else { return nil }

        let candidates: [URL?] = [
            packagedResourceURL(for: state),
            Bundle.main.url(forResource: state.assetName, withExtension: "png", subdirectory: "Whale"),
            Bundle.main.url(forResource: state.assetName, withExtension: "png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/Resources/Whale/\(state.assetName).png")
        ]

        for case let url? in candidates {
            if let image = loadImage(from: url) {
                let cost = Int(image.size.width * image.size.height * 4)
                cache.setObject(image, forKey: key, cost: cost)
                return image
            }
        }
        missingStates.insert(state)
        return nil
    }

    private static func packagedResourceURL(for state: WhalePetState) -> URL? {
        let bundleURLs = [
            Bundle.main.bundleURL.appendingPathComponent("CodexTaskPet_AgentPet.bundle"),
            Bundle.main.resourceURL?.appendingPathComponent("CodexTaskPet_AgentPet.bundle"),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("CodexTaskPet_AgentPet.bundle")
        ].compactMap { $0 }

        for bundleURL in bundleURLs {
            guard let resourceBundle = Bundle(url: bundleURL) else { continue }
            if let url = resourceBundle.url(
                forResource: state.assetName,
                withExtension: "png",
                subdirectory: "Whale"
            ) ?? resourceBundle.url(forResource: state.assetName, withExtension: "png") {
                return url
            }
        }

        return nil
    }

    private static func loadImage(from url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }
}

struct WhalePetView: View {
    let state: WhalePetState
    var isFlipped = false
    var isAnimating = true

    @State private var breathing = false
    @State private var glowExpanded = false

    private var image: NSImage? {
        WhaleAssetStore.image(for: state)
    }

    private var supportsBreathing: Bool {
        isAnimating && (state == .standby || state == .working)
    }

    private var breathScale: CGFloat {
        guard supportsBreathing else { return 1 }
        return breathing ? 1.004 : 0.999
    }

    private var bounceOffset: CGFloat {
        state == .doubleClick ? -9 : 0
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .id(state)
                    .transition(.opacity)
                    .scaleEffect(x: isFlipped ? -1 : 1, y: 1, anchor: .bottom)
                    .scaleEffect(breathScale, anchor: .bottom)
                    .offset(y: bounceOffset)
            }

            if state == .doubleClick {
                doubleClickGlow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.16), value: state)
        .animation(.spring(response: 0.34, dampingFraction: 0.56), value: state)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { updateBreathing() }
        .onChange(of: isAnimating) { _, _ in updateBreathing() }
        .onChange(of: state) { _, newState in
            updateBreathing()
            guard newState == .doubleClick else {
                glowExpanded = false
                return
            }
            glowExpanded = false
            withAnimation(.easeOut(duration: 0.72)) {
                glowExpanded = true
            }
        }
    }

    private func updateBreathing() {
        guard supportsBreathing else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                breathing = false
            }
            return
        }
        guard !breathing else { return }
        withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }

    private var doubleClickGlow: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.72), Color.cyan.opacity(0.26), Color.clear],
                        center: .center,
                        startRadius: 3,
                        endRadius: 66
                    )
                )
                .frame(width: 138, height: 138)
                .blur(radius: 8)
                .scaleEffect(glowExpanded ? 1.16 : 0.58)
                .opacity(glowExpanded ? 0.12 : 0.92)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.cyan.opacity(0.58), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 132, height: 132)
                .scaleEffect(glowExpanded ? 1.28 : 0.72)
                .opacity(glowExpanded ? 0 : 0.78)
        }
        .offset(y: -14)
        .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        switch state {
        case .standby: return "鲸鱼娘桌宠，待命中"
        case .working: return "鲸鱼娘桌宠，正在处理任务"
        case .happy: return "鲸鱼娘桌宠，开心地回应任务完成"
        case .angry: return "鲸鱼娘桌宠，因为任务异常而生气"
        case .sleep: return "鲸鱼娘桌宠，正在睡觉"
        case .eatRice: return "鲸鱼娘桌宠，正在吃白饭"
        case .hover: return "鲸鱼娘桌宠，好奇地看向鼠标"
        case .doubleClick: return "鲸鱼娘桌宠，回应双击互动"
        case .drag: return "鲸鱼娘桌宠，正在被拖动"
        case .patrol: return "鲸鱼娘桌宠，正在桌面巡视"
        }
    }
}
