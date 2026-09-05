import Foundation

/// Shared `yyyy-MM-dd` formatting. DateFormatter is expensive to create and
/// thread-safe to use, so keep one per calendar/time zone.
enum DayFormat {
    private static let lock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(for calendar: Calendar = .current) -> DateFormatter {
        let key = "\(calendar.identifier)|\(calendar.timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        cache[key] = formatter
        return formatter
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        formatter(for: calendar).string(from: date)
    }

    static func date(from string: String, calendar: Calendar = .current) -> Date? {
        formatter(for: calendar).date(from: string)
    }

    static var today: String {
        string(from: Date())
    }
}
