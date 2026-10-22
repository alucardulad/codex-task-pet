import SwiftUI

struct TaskPanelPopoverContent: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        TaskPanelView(store: store)
            .frame(
                width: PetLayout.taskPanelWindowSize.width,
                height: PetLayout.taskPanelWindowSize.height
            )
            .background(Color.clear)
    }
}

struct TaskPanelView: View {
    @ObservedObject var store: TaskStore

    private let uiScale = PetLayout.taskPanelDisplayScale

    private func s(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))

            if let completion = store.currentCompletion {
                completionBanner(completion)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: s(9)) {
                    if store.activeTasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.activeTasks) { task in
                            TaskCardView(task: task, uiScale: uiScale) {
                                store.openTask(id: task.id)
                            }
                        }
                    }

                    if !store.recentTasks.isEmpty {
                        HStack {
                            Text("最近完成")
                                .font(.system(size: s(11), weight: .semibold, design: .rounded))
                                .foregroundStyle(PetPalette.secondaryText)
                            Spacer()
                        }
                        .padding(.top, s(7))
                        .padding(.horizontal, s(3))

                        ForEach(store.recentTasks) { task in
                            TaskCardView(task: task, uiScale: uiScale) {
                                store.openTask(id: task.id)
                            }
                        }
                    }
                }
                .padding(s(12))
            }
        }
        .frame(
            width: PetLayout.taskPanelWindowSize.width,
            height: PetLayout.taskPanelWindowSize.height
        )
        .petPanel(cornerRadius: s(24))
    }

    private var header: some View {
        HStack(spacing: s(10)) {
            ZStack {
                Circle()
                    .fill(store.activeCount > 0 ? PetPalette.mint.opacity(0.16) : Color.white.opacity(0.06))
                    .frame(width: s(31), height: s(31))
                Image(systemName: store.activeCount > 0 ? "waveform.path.ecg" : "moon.zzz.fill")
                    .font(.system(size: s(13), weight: .bold))
                    .foregroundStyle(store.activeCount > 0 ? PetPalette.mint : PetPalette.secondaryText)
            }

            VStack(alignment: .leading, spacing: s(1)) {
                Text(store.activeCount > 0 ? "\(store.activeCount) 个 Agent 正在工作" : "任务宠物")
                    .font(.system(size: s(14), weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.text)
                Text(store.activeCount > 0 ? "点击任意任务可直接回到 Codex" : "现在没有正在运行的任务")
                    .font(.system(size: s(10.5), weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.secondaryText)
            }

            Spacer()

            Button(action: store.closePanel) {
                Image(systemName: "xmark")
                    .font(.system(size: s(10), weight: .bold))
                    .foregroundStyle(PetPalette.secondaryText)
                    .frame(width: s(26), height: s(26))
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, s(15))
        .padding(.vertical, s(13))
    }

    private var emptyState: some View {
        HStack(spacing: s(10)) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: s(17), weight: .medium))
                .foregroundStyle(PetPalette.amber.opacity(0.9))
            VStack(alignment: .leading, spacing: s(2)) {
                Text("现在可以休息一下")
                    .font(.system(size: s(12.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(PetPalette.text)
                Text("有新的 Agent 开始工作后，我会出现在这里。")
                    .font(.system(size: s(10.5), design: .rounded))
                    .foregroundStyle(PetPalette.secondaryText)
            }
            Spacer()
        }
        .padding(s(13))
        .background(
            RoundedRectangle(cornerRadius: s(14), style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func completionBanner(_ event: CompletionEvent) -> some View {
        HStack(spacing: s(10)) {
            Image(systemName: event.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: s(19), weight: .bold))
                .foregroundStyle(event.status == .completed ? PetPalette.mint : PetPalette.red)

            VStack(alignment: .leading, spacing: s(2)) {
                Text(event.headline)
                    .font(.system(size: s(12), weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.text)
                Text(event.title)
                    .font(.system(size: s(10.5), weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button("查看") {
                store.openCurrentCompletion()
            }
            .font(.system(size: s(10.5), weight: .bold, design: .rounded))
            .buttonStyle(.plain)
            .foregroundStyle(PetPalette.ink)
            .padding(.horizontal, s(10))
            .padding(.vertical, s(5))
            .background(Capsule().fill(PetPalette.mint))

            Button(action: store.dismissCurrentCompletion) {
                Image(systemName: "xmark")
                    .font(.system(size: s(9), weight: .bold))
                    .foregroundStyle(PetPalette.secondaryText)
                    .frame(width: s(23), height: s(23))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, s(14))
        .padding(.vertical, s(10))
        .background(
            Rectangle()
                .fill(event.status == .completed ? PetPalette.mint.opacity(0.075) : PetPalette.red.opacity(0.08))
        )
    }
}

private struct TaskCardView: View {
    let task: AgentTask
    let uiScale: CGFloat
    let action: () -> Void

    private func s(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    private var statusColor: Color {
        switch task.status {
        case .inProgress: return PetPalette.mint
        case .completed: return PetPalette.mintDeep
        case .failed: return PetPalette.red
        case .interrupted: return PetPalette.amber
        }
    }

    var body: some View {
        Button(action: action) {
            cardContent
                .padding(s(11))
                .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: s(8)) {
            titleRow
            metadataRow

            if !task.preview.isEmpty && task.status == .inProgress {
                previewRow
            }

            if task.status == .inProgress {
                progressBar
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: s(8)) {
            Circle()
                .fill(statusColor)
                .frame(width: s(7), height: s(7))
                .shadow(color: statusColor.opacity(0.65), radius: s(4))

            Text(task.title)
                .font(.system(size: s(12.5), weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.text)
                .lineLimit(1)

            Spacer(minLength: s(4))

            if task.isSubagent {
                Text("子 Agent")
                    .font(.system(size: s(9.5), weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.amber)
                    .padding(.horizontal, s(6))
                    .padding(.vertical, s(3))
                    .background(Capsule().fill(PetPalette.amber.opacity(0.11)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: s(8), weight: .bold))
                .foregroundStyle(Color.white.opacity(0.24))
        }
    }

    private var metadataRow: some View {
        HStack(spacing: s(8)) {
            Label(task.projectName, systemImage: "folder.fill")
                .lineLimit(1)
            Text("·")
            Text(task.currentAction)
            Spacer()
            Text(task.elapsedText)
        }
        .font(.system(size: s(9.5), weight: .medium, design: .rounded))
        .foregroundStyle(PetPalette.secondaryText)
    }

    private var previewRow: some View {
        Text(task.preview)
            .font(.system(size: s(9.5), weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.43))
            .lineLimit(1)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.055))
                Capsule()
                    .fill(LinearGradient(colors: [PetPalette.mint.opacity(0.3), PetPalette.mint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * 0.38)
                    .blur(radius: s(0.3))
            }
        }
        .frame(height: s(2))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: s(14), style: .continuous)
            .fill(task.status == .inProgress ? PetPalette.panelRaised : Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: s(14), style: .continuous)
                    .stroke(
                        task.status == .inProgress ? PetPalette.mint.opacity(0.11) : Color.white.opacity(0.045),
                        lineWidth: s(1)
                    )
            )
    }
}

struct CompletionSpeechBubble: View {
    @ObservedObject var store: TaskStore
    let event: CompletionEvent

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: event.status == .completed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(event.status == .completed ? PetPalette.mint : PetPalette.red)
                        Text(event.headline)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalette.text)
                        Spacer()
                    }

                    Text(event.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalette.text)
                        .lineLimit(1)

                    Text(event.message)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalette.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        Text(event.projectName)
                        Text("· 点击打开 Codex")
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalette.mint.opacity(0.82))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.openCurrentCompletion()
                }

                Button(action: store.dismissCurrentCompletion) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(PetPalette.secondaryText)
                        .frame(width: 23, height: 23)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .padding(7)
            }
            .frame(width: 306)
            .background(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(PetPalette.panel.opacity(0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [(event.status == .completed ? PetPalette.mint : PetPalette.red).opacity(0.45), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.34), radius: 16, y: 8)
            )

            BubbleTail()
                .fill(PetPalette.panel.opacity(0.97))
                .frame(width: 28, height: 11)
                .overlay(alignment: .top) {
                    Rectangle().fill(PetPalette.mint.opacity(0.18)).frame(height: 1)
                }
        }
        .overlay(alignment: .topLeading) {
            if store.pendingCompletionCount > 0 {
                Text("还有 \(store.pendingCompletionCount) 条")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(PetPalette.amber))
                    .offset(x: -7, y: -9)
            }
        }
    }
}

struct RunningStatusPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array([0.42, 0.68, 1.0].enumerated()), id: \.offset) { _, opacity in
                    Circle()
                        .fill(PetPalette.mint.opacity(opacity))
                        .frame(width: 4, height: 4)
                }
            }
            Text("\(count) 个 Agent 正在运行")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("点击查看")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalette.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(PetPalette.panel.opacity(0.92))
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)
        )
    }
}

struct IdleStatusPill: View {
    let hasError: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(hasError ? PetPalette.red : PetPalette.secondaryText.opacity(0.65))
                .frame(width: 6, height: 6)
            Text(hasError ? "暂时读不到 Codex 任务" : "待命中")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PetPalette.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: hasError ? 244 : 116)
        .background(Capsule().fill(PetPalette.panel.opacity(0.84)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .zIndex(5)
    }
}
