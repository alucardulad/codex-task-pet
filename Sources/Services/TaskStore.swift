import AppKit
import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var activeTasks: [AgentTask] = []
    @Published private(set) var recentTasks: [AgentTask] = []
    @Published private(set) var currentCompletion: CompletionEvent?
    @Published private(set) var monitorError: String?
    @Published var panelExpanded = false
    @Published private(set) var soundEnabled: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var petScale: CGFloat
    @Published private(set) var isDraggingPet = false
    @Published private(set) var isHoveringPet = false
    @Published private(set) var isDoubleClicking = false
    @Published private(set) var isSleeping = false
    @Published private(set) var isEatingRice = false
    @Published private(set) var patrolEnabled = false
    @Published private(set) var patrolDirection: CGFloat = 1

    private let database: CodexDatabase?
    private let demoMode: Bool
    private var timer: Timer?
    private var randomBehaviorTimer: Timer?
    private var randomSleepTimer: Timer?
    private var lastCompletionPoll = Date()
    private var lastDataVersion: CodexDataVersion?
    private var seenCompletionIDs = Set<String>()
    private var completionQueue: [CompletionEvent] = []
    private var consecutiveErrors = 0
    private var doubleClickTimer: Timer?
    private var riceTimer: Timer?
    private var isRandomSleeping = false
    private var isRandomEating = false
    private let soundDefaultsKey = "AgentPet.soundEnabled"
    private let scaleDefaultsKey = "AgentPet.petScale"

    static let minimumPetScale: CGFloat = 0.1
    static let maximumPetScale: CGFloat = 1.0
    static let petScaleStep: CGFloat = 0.1

    init(demoMode: Bool = false) {
        self.demoMode = demoMode
        self.database = try? CodexDatabase()
        self.soundEnabled = UserDefaults.standard.object(forKey: soundDefaultsKey) as? Bool ?? true
        self.launchAtLogin = LaunchAtLogin.isEnabled
        let savedScale = UserDefaults.standard.double(forKey: scaleDefaultsKey)
        let initialScale = savedScale > 0 ? CGFloat(savedScale) : 1
        self.petScale = min(max(initialScale, Self.minimumPetScale), Self.maximumPetScale)
        if demoMode {
            loadDemoData()
        }
    }

    deinit {
        timer?.invalidate()
        randomBehaviorTimer?.invalidate()
        randomSleepTimer?.invalidate()
        doubleClickTimer?.invalidate()
        riceTimer?.invalidate()
    }

    var pendingCompletionCount: Int {
        max(0, completionQueue.count - 1)
    }

    var activeCount: Int {
        activeTasks.count
    }

    var hasRunningWork: Bool {
        !activeTasks.isEmpty
    }

    func start() {
        guard !demoMode else { return }
        guard database != nil else {
            monitorError = "找不到本机 Codex 任务数据"
            return
        }

        refresh(notifyCompletions: false)
        lastCompletionPoll = Date()

        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            // Timer 已加入主 RunLoop，直接在当前主线程刷新，避免额外调度任务和线程。
            MainActor.assumeIsolated {
                self?.refresh(notifyCompletions: true)
            }
        }
        timer.tolerance = 0.75
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduleNextRandomBehavior(delay: Double.random(in: 35...75))
    }

    func refresh(notifyCompletions: Bool = true) {
        guard let database else { return }
        let dataVersion = database.dataVersion()
        let now = Date()

        guard dataVersion != lastDataVersion else {
            // 面板打开时只需低频刷新运行时长文本，不必重复查询 SQLite。
            if panelExpanded && !activeTasks.isEmpty {
                objectWillChange.send()
            }
            return
        }

        do {
            let tasks = try database.fetchTasks(now: now)
            let nextActiveTasks = tasks.filter { $0.status == .inProgress }
            let nextRecentTasks = Array(tasks.filter { $0.status != .inProgress }.prefix(5))

            // 面板展开时刷新计时文本；平时只发布真正变化的数据，避免宠物反复重绘。
            if activeTasks != nextActiveTasks || (panelExpanded && !nextActiveTasks.isEmpty) {
                activeTasks = nextActiveTasks
            }
            if recentTasks != nextRecentTasks {
                recentTasks = nextRecentTasks
            }

            if notifyCompletions {
                let events = try database.fetchCompletions(since: lastCompletionPoll, through: now)
                enqueue(events)
                lastCompletionPoll = now
            }

            if !nextActiveTasks.isEmpty || currentCompletion != nil {
                interruptRandomBehaviorForActivity()
            }

            lastDataVersion = dataVersion
            consecutiveErrors = 0
            if monitorError != nil {
                monitorError = nil
            }
        } catch {
            consecutiveErrors += 1
            if consecutiveErrors >= 3, monitorError == nil {
                monitorError = "暂时读不到 Codex 任务"
                interruptRandomBehaviorForActivity()
            }
        }
    }

    func togglePanel() {
        panelExpanded.toggle()
        if panelExpanded {
            interruptRandomBehaviorForActivity()
        }
    }

    func closePanel() {
        panelExpanded = false
    }

    func dismissCurrentCompletion() {
        if !completionQueue.isEmpty {
            completionQueue.removeFirst()
        }
        currentCompletion = completionQueue.first
    }

    func openCurrentCompletion() {
        guard let event = currentCompletion else { return }
        openTask(id: event.taskID)
        dismissCurrentCompletion()
    }

    func openTask(id: String) {
        if let url = URL(string: "codex://threads/\(id)") {
            NSWorkspace.shared.open(url)
        }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .first?
            .activate(options: [.activateAllWindows])
    }

    func toggleSound() {
        soundEnabled.toggle()
        UserDefaults.standard.set(soundEnabled, forKey: soundDefaultsKey)
        if soundEnabled {
            playCompletionSound()
        }
    }

    func setPetScale(_ scale: CGFloat) {
        let clamped = min(max(scale, Self.minimumPetScale), Self.maximumPetScale)
        guard abs(clamped - petScale) > 0.001 else { return }
        petScale = clamped
        UserDefaults.standard.set(Double(clamped), forKey: scaleDefaultsKey)
    }

    func adjustPetScale(by delta: CGFloat) {
        setPetScale(petScale + delta)
    }

    func setDraggingPet(_ dragging: Bool) {
        guard isDraggingPet != dragging else { return }
        if dragging {
            interruptRandomBehaviorForActivity()
        }
        isDraggingPet = dragging
    }

    func setHoveringPet(_ hovering: Bool) {
        guard isHoveringPet != hovering else { return }
        isHoveringPet = hovering
    }

    func triggerDoubleClick() {
        interruptRandomBehaviorForActivity()
        doubleClickTimer?.invalidate()
        isDoubleClicking = true
        let timer = Timer(timeInterval: 0.82, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isDoubleClicking = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        doubleClickTimer = timer
    }

    func toggleSleep() {
        if isSleeping {
            isSleeping = false
            if isRandomSleeping {
                randomSleepTimer?.invalidate()
                randomSleepTimer = nil
                isRandomSleeping = false
            }
            scheduleNextRandomBehavior(delay: Double.random(in: 45...90))
        } else {
            cancelRandomBehaviorScheduling()
            cancelRandomSleep()
            cancelRice()
            isSleeping = true
            stopPatrol()
        }
    }

    func feedRice() {
        cancelRandomBehaviorScheduling()
        cancelRandomSleep()
        isSleeping = false
        stopPatrol()
        startRice(duration: 4.2, random: false)
    }

    func togglePatrol() {
        patrolEnabled.toggle()
        if patrolEnabled {
            cancelRandomBehaviorScheduling()
            cancelRandomSleep()
            isSleeping = false
            isHoveringPet = false
            cancelRice()
            patrolDirection = 1
        } else {
            scheduleNextRandomBehavior(delay: Double.random(in: 35...75))
        }
    }

    func stopPatrol() {
        guard patrolEnabled else { return }
        patrolEnabled = false
    }

    func setPatrolDirection(_ direction: CGFloat) {
        let normalized: CGFloat = direction < 0 ? -1 : 1
        guard patrolDirection != normalized else { return }
        patrolDirection = normalized
    }

    private func cancelRice() {
        riceTimer?.invalidate()
        riceTimer = nil
        isRandomEating = false
        isEatingRice = false
    }

    private func startRice(duration: TimeInterval, random: Bool) {
        riceTimer?.invalidate()
        isRandomEating = random
        isEatingRice = true

        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEatingRice else { return }
                let wasRandom = self.isRandomEating
                self.riceTimer = nil
                self.isRandomEating = false
                self.isEatingRice = false
                if wasRandom {
                    self.scheduleNextRandomBehavior(delay: Double.random(in: 75...150))
                }
            }
        }
        timer.tolerance = min(0.35, duration * 0.06)
        RunLoop.main.add(timer, forMode: .common)
        riceTimer = timer
    }

    private func scheduleNextRandomBehavior(delay: TimeInterval? = nil) {
        guard !demoMode, database != nil else { return }
        randomBehaviorTimer?.invalidate()

        let wait = delay ?? Double.random(in: 45...90)
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.randomBehaviorTimer = nil
                self.attemptRandomBehavior()
            }
        }
        timer.tolerance = min(5, wait * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        randomBehaviorTimer = timer
    }

    private var canStartRandomBehavior: Bool {
        !demoMode
            && activeTasks.isEmpty
            && currentCompletion == nil
            && monitorError == nil
            && !isDraggingPet
            && !isHoveringPet
            && !isDoubleClicking
            && !panelExpanded
            && !patrolEnabled
            && !isSleeping
            && !isEatingRice
    }

    private func attemptRandomBehavior() {
        guard canStartRandomBehavior else {
            // 忙碌或正在交互时不做高频轮询，稍后再检查一次。
            scheduleNextRandomBehavior(delay: Double.random(in: 45...90))
            return
        }

        if Bool.random() {
            startRandomSleep()
        } else {
            startRandomRice()
        }
    }

    private func startRandomSleep() {
        cancelRice()
        isSleeping = true
        isRandomSleeping = true
        let duration = Double.random(in: 25...45)
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRandomSleeping else { return }
                self.randomSleepTimer = nil
                self.isRandomSleeping = false
                self.isSleeping = false
                self.scheduleNextRandomBehavior(delay: Double.random(in: 75...150))
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        randomSleepTimer = timer
    }

    private func startRandomRice() {
        startRice(duration: Double.random(in: 4.5...6.0), random: true)
    }

    private func cancelRandomSleep() {
        randomSleepTimer?.invalidate()
        randomSleepTimer = nil
        isRandomSleeping = false
    }

    private func cancelRandomBehaviorScheduling() {
        randomBehaviorTimer?.invalidate()
        randomBehaviorTimer = nil
    }

    private func interruptRandomBehaviorForActivity() {
        guard isRandomSleeping || isRandomEating else { return }
        if isRandomSleeping {
            cancelRandomSleep()
            isSleeping = false
        }
        if isRandomEating {
            cancelRice()
        }
        scheduleNextRandomBehavior(delay: Double.random(in: 75...150))
    }

    func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!launchAtLogin)
            launchAtLogin.toggle()
        } catch {
            monitorError = error.localizedDescription
        }
    }

    private func enqueue(_ events: [CompletionEvent]) {
        var addedEvent = false
        for event in events where !seenCompletionIDs.contains(event.id) {
            seenCompletionIDs.insert(event.id)
            completionQueue.append(event)
            addedEvent = true
            if seenCompletionIDs.count > 300 {
                seenCompletionIDs = Set(seenCompletionIDs.suffix(200))
            }
        }

        if currentCompletion == nil {
            currentCompletion = completionQueue.first
        }
        if addedEvent && soundEnabled {
            playCompletionSound()
        }
    }

    private func playCompletionSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func loadDemoData() {
        let now = Date()
        activeTasks = [
            AgentTask(
                id: "demo-1",
                title: "开发任务进度桌面插件",
                projectName: "Codex",
                status: .inProgress,
                currentAction: "修改文件",
                preview: "WhalePetView.swift",
                startedAt: now.addingTimeInterval(-252),
                completedAt: nil,
                latestActivity: now,
                isSubagent: false
            ),
            AgentTask(
                id: "demo-2",
                title: "检查三个 scheme 的部署版本",
                projectName: "iosCode",
                status: .inProgress,
                currentAction: "执行命令",
                preview: "归档配置与版本号",
                startedAt: now.addingTimeInterval(-86),
                completedAt: nil,
                latestActivity: now,
                isSubagent: true
            ),
            AgentTask(
                id: "demo-3",
                title: "整理有声小说第三集",
                projectName: "语音合成",
                status: .inProgress,
                currentAction: "思考中",
                preview: "检查时间轴与配音清单",
                startedAt: now.addingTimeInterval(-38),
                completedAt: nil,
                latestActivity: now,
                isSubagent: false
            )
        ]
        recentTasks = [
            AgentTask(
                id: "demo-4",
                title: "查找安卓测试安装包",
                projectName: "Codex",
                status: .completed,
                currentAction: "已完成",
                preview: "已整理安装包与校验结果",
                startedAt: now.addingTimeInterval(-1200),
                completedAt: now.addingTimeInterval(-84),
                latestActivity: now.addingTimeInterval(-84),
                isSubagent: false
            )
        ]
        currentCompletion = CompletionEvent(
            id: "demo-event",
            taskID: "demo-4",
            title: "查找安卓测试安装包",
            projectName: "Codex",
            status: .completed,
            message: "安装包已经整理好，并附上了版本与校验结果。",
            completedAt: now,
            isSubagent: false
        )
        completionQueue = currentCompletion.map { [$0] } ?? []
    }

#if DEBUG
    func debugPrepareRandomBehaviorTest() {
        activeTasks = []
        recentTasks = []
        currentCompletion = nil
        completionQueue = []
        monitorError = nil
        panelExpanded = false
        isDraggingPet = false
        isHoveringPet = false
        isDoubleClicking = false
        isSleeping = false
        isEatingRice = false
        patrolEnabled = false
    }

    func debugScheduleRandomBehavior(after delay: TimeInterval) {
        scheduleNextRandomBehavior(delay: delay)
    }

    func debugStartRandomSleep() {
        startRandomSleep()
    }
#endif
}
