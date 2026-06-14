import Foundation

// MARK: - 保留时间选项

enum RetentionOption: Int, CaseIterable {
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
    case thirtyDays = 30
    case unlimited = -1

    var label: String {
        switch self {
        case .oneDay: return "1 天"
        case .threeDays: return "3 天"
        case .sevenDays: return "7 天"
        case .thirtyDays: return "30 天"
        case .unlimited: return "无限制"
        }
    }

    static var allCases: [RetentionOption] {
        [.oneDay, .threeDays, .sevenDays, .thirtyDays, .unlimited]
    }
}

// MARK: - 最大条目数选项

enum MaxItemsOption: Int, CaseIterable {
    case fifty = 50
    case hundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case unlimited = -1

    var label: String {
        switch self {
        case .fifty: return "50 条"
        case .hundred: return "100 条"
        case .twoHundred: return "200 条"
        case .fiveHundred: return "500 条"
        case .unlimited: return "无限制"
        }
    }

    static var allCases: [MaxItemsOption] {
        [.fifty, .hundred, .twoHundred, .fiveHundred, .unlimited]
    }
}

// MARK: - UserDefaults Keys

enum SettingsKey {
    static let retentionDays = "settings_retentionDays"
    static let maxItems = "settings_maxItems"
}