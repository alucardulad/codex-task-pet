import Foundation

enum AgentStatus: String, Codable {
    case inProgress
    case completed
    case failed
    case interrupted

    var label: String {
        switch self {
        case .inProgress: return "运行中"
        case .completed: return "已完成"
        case .failed: return "执行失败"
        case .interrupted: return "已中断"
        }
    }
}

struct AgentTask: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let projectName: String
    let status: AgentStatus
    let currentAction: String
    let preview: String
    let startedAt: Date?
    let completedAt: Date?
    let latestActivity: Date
    let isSubagent: Bool

    var elapsedText: String {
        guard status == .inProgress, let startedAt else { return status.label }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        return "\(seconds / 3600) 小时 \((seconds % 3600) / 60) 分"
    }

    var agentKindLabel: String {
        isSubagent ? "子 Agent" : "Agent"
    }
}

struct CompletionEvent: Identifiable, Codable {
    let id: String
    let taskID: String
    let title: String
    let projectName: String
    let status: AgentStatus
    let message: String
    let completedAt: Date
    let isSubagent: Bool

    var headline: String {
        switch status {
        case .completed: return isSubagent ? "子 Agent 已完成" : "任务完成了"
        case .failed: return "任务执行失败"
        case .interrupted: return "任务已中断"
        case .inProgress: return "收到新进展"
        }
    }
}

enum WhalePetState: String, Equatable {
    case standby
    case working
    case happy
    case angry
    case sleep
    case eatRice
    case hover
    case doubleClick
    case drag
    case patrol

    var assetName: String {
        switch self {
        case .standby: return "standby"
        case .working: return "working"
        case .happy: return "happy"
        case .angry: return "angry"
        case .sleep: return "sleep"
        case .eatRice: return "eat_rice"
        case .hover: return "hover"
        case .doubleClick: return "double_click"
        case .drag: return "drag"
        case .patrol: return "patrol"
        }
    }
}


enum PetLayout {
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 9
    static let itemSpacing: CGFloat = 9

    static let petBaseSize = NSSize(width: 256, height: 256)
    static let petVisualScale: CGFloat = 0.84

    static let taskPanelBaseSize = NSSize(width: 352, height: 342)
    static let taskPanelDisplayScale: CGFloat = 1.5
    static var taskPanelWindowSize: NSSize {
        NSSize(
            width: taskPanelBaseSize.width * taskPanelDisplayScale,
            height: taskPanelBaseSize.height * taskPanelDisplayScale
        )
    }

    static let completionAccessorySize = NSSize(width: 306, height: 136)
    static let runningAccessorySize = NSSize(width: 252, height: 44)
    static let idleAccessorySize = NSSize(width: 180, height: 44)
    static let errorAccessorySize = NSSize(width: 270, height: 44)

    static func petSize(for petScale: CGFloat) -> NSSize {
        let visualScale = petScale * petVisualScale
        return NSSize(
            width: petBaseSize.width * visualScale,
            height: petBaseSize.height * visualScale
        )
    }

    static func accessorySize(
        hasCompletion: Bool,
        activeCount: Int,
        hasError: Bool
    ) -> NSSize {
        if hasCompletion { return completionAccessorySize }
        if activeCount > 0 { return runningAccessorySize }
        return hasError ? errorAccessorySize : idleAccessorySize
    }

    static func windowSize(
        hasCompletion: Bool,
        activeCount: Int,
        hasError: Bool,
        petScale: CGFloat
    ) -> NSSize {
        let accessory = accessorySize(
            hasCompletion: hasCompletion,
            activeCount: activeCount,
            hasError: hasError
        )
        let pet = petSize(for: petScale)
        var width = max(
            accessory.width + horizontalPadding * 2,
            pet.width + horizontalPadding * 2
        )
        if hasCompletion {
            width = max(width, 340)
        }
        return NSSize(
            width: width,
            height: accessory.height + itemSpacing + pet.height + verticalPadding * 2
        )
    }
}
