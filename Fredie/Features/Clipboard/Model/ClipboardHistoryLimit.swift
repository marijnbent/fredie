import Foundation

enum ClipboardHistoryLimit: Int, CaseIterable, Codable, Sendable {
    case oneDay = 1
    case sevenDays = 7
    case oneMonth = 30
    case sixMonths = 180

    var label: String {
        switch self {
        case .oneDay: return "1 day"
        case .sevenDays: return "7 days"
        case .oneMonth: return "1 month"
        case .sixMonths: return "6 months"
        }
    }

    var subtitle: String {
        switch self {
        case .oneDay: return "Last 24 hours"
        case .sevenDays: return "Last week"
        case .oneMonth: return "Last month"
        case .sixMonths: return "Last 6 months"
        }
    }

    func cutoffDate(relativeTo date: Date, calendar: Calendar) -> Date {
        switch self {
        case .oneDay:
            return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: date) ?? date
        }
    }

    static let defaultValue: ClipboardHistoryLimit = .sevenDays

    static func fromStoredValue(_ value: Int) -> ClipboardHistoryLimit? {
        if let limit = ClipboardHistoryLimit(rawValue: value) {
            return limit
        }

        switch value {
        case 100:
            return .sevenDays
        case 500:
            return .oneMonth
        case 1000:
            return .sixMonths
        default:
            return nil
        }
    }
}
