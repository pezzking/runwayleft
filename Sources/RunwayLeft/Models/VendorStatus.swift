import Foundation

// MARK: - Vendors

enum StatusVendor: String, CaseIterable {
    case claude
    case openai

    var displayName: String {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        }
    }

    var summaryURL: URL {
        switch self {
        case .claude: return URL(string: "https://status.claude.com/api/v2/summary.json")!
        case .openai: return URL(string: "https://status.openai.com/api/v2/summary.json")!
        }
    }

    var pageURL: URL {
        switch self {
        case .claude: return URL(string: "https://status.claude.com")!
        case .openai: return URL(string: "https://status.openai.com")!
        }
    }

    var pageHost: String {
        pageURL.host ?? pageURL.absoluteString
    }

    /// Components that matter for the tool this app tracks. Everything else on
    /// the status page is still listed when it is degraded, but these drive the
    /// headline pill.
    func isRelevantComponent(named name: String) -> Bool {
        let lower = name.lowercased()
        switch self {
        case .claude:
            return lower == "claude code" || lower.hasPrefix("claude api")
        case .openai:
            return lower.contains("codex") || lower.contains("vs code extension")
        }
    }
}

// MARK: - Severity

/// Normalized severity shared by page indicators and component states.
enum StatusLevel: Int, Comparable {
    case unknown = -1
    case operational = 0
    case maintenance = 1
    case degraded = 2
    case partialOutage = 3
    case majorOutage = 4

    static func < (lhs: StatusLevel, rhs: StatusLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .operational: return "Operational"
        case .maintenance: return "Maintenance"
        case .degraded: return "Degraded"
        case .partialOutage: return "Partial outage"
        case .majorOutage: return "Major outage"
        }
    }

    var isProblem: Bool {
        self >= .degraded
    }
}

// MARK: - Statuspage Enums (tolerant decoding)

enum StatusIndicator: String, Codable {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = StatusIndicator(rawValue: raw.lowercased()) ?? .unknown
    }

    var level: StatusLevel {
        switch self {
        case .none: return .operational
        case .maintenance: return .maintenance
        case .minor: return .degraded
        case .major: return .partialOutage
        case .critical: return .majorOutage
        case .unknown: return .unknown
        }
    }
}

enum ComponentStatus: String, Codable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ComponentStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    var level: StatusLevel {
        switch self {
        case .operational: return .operational
        case .underMaintenance: return .maintenance
        case .degradedPerformance: return .degraded
        case .partialOutage: return .partialOutage
        case .majorOutage: return .majorOutage
        case .unknown: return .unknown
        }
    }
}

// MARK: - Statuspage Payload

struct StatusComponent: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: ComponentStatus
    let group: Bool?
    let groupId: String?
    let onlyShowIfDegraded: Bool?
    let updatedAt: String?

    init(
        id: String,
        name: String,
        status: ComponentStatus,
        group: Bool? = nil,
        groupId: String? = nil,
        onlyShowIfDegraded: Bool? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.group = group
        self.groupId = groupId
        self.onlyShowIfDegraded = onlyShowIfDegraded
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Unnamed component"
        status = (try? c.decode(ComponentStatus.self, forKey: .status)) ?? .unknown
        group = try? c.decodeIfPresent(Bool.self, forKey: .group)
        groupId = try? c.decodeIfPresent(String.self, forKey: .groupId)
        onlyShowIfDegraded = try? c.decodeIfPresent(Bool.self, forKey: .onlyShowIfDegraded)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var isGroup: Bool { group ?? false }
}

struct StatusIncidentUpdate: Codable, Equatable {
    let body: String?
    let status: String?
    let updatedAt: String?
}

struct StatusIncident: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String?
    let impact: String?
    let shortlink: String?
    let createdAt: String?
    let updatedAt: String?
    let incidentUpdates: [StatusIncidentUpdate]?

    var latestUpdate: StatusIncidentUpdate? {
        incidentUpdates?.first
    }

    var link: URL? {
        shortlink.flatMap(URL.init(string:))
    }

    var impactLevel: StatusLevel {
        switch (impact ?? "").lowercased() {
        case "none": return .operational
        case "maintenance": return .maintenance
        case "minor": return .degraded
        case "major": return .partialOutage
        case "critical": return .majorOutage
        default: return .unknown
        }
    }
}

struct StatusMaintenance: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String?
    let impact: String?
    let shortlink: String?
    let scheduledFor: String?
    let scheduledUntil: String?

    var link: URL? {
        shortlink.flatMap(URL.init(string:))
    }
}

struct StatusPageSummary: Codable {
    struct Page: Codable {
        let id: String?
        let name: String?
        let url: String?
    }

    struct Status: Codable {
        let indicator: StatusIndicator
        let description: String?
    }

    let page: Page?
    let status: Status?
    let components: [StatusComponent]?
    let incidents: [StatusIncident]?
    let scheduledMaintenances: [StatusMaintenance]?
}

// MARK: - App-facing Vendor Status

struct VendorStatus {
    let vendor: StatusVendor
    var indicator: StatusIndicator = .unknown
    var description: String = ""
    var components: [StatusComponent] = []
    var incidents: [StatusIncident] = []
    var maintenances: [StatusMaintenance] = []
    var fetchedAt: Date? = nil
    var errorMessage: String? = nil

    init(vendor: StatusVendor) {
        self.vendor = vendor
    }

    init(vendor: StatusVendor, summary: StatusPageSummary, fetchedAt: Date) {
        self.vendor = vendor
        self.indicator = summary.status?.indicator ?? .unknown
        self.description = summary.status?.description ?? ""
        self.components = summary.components ?? []
        self.incidents = summary.incidents ?? []
        self.maintenances = summary.scheduledMaintenances ?? []
        self.fetchedAt = fetchedAt
        self.errorMessage = nil
    }

    var isLoaded: Bool {
        fetchedAt != nil && errorMessage == nil
    }

    var pageURL: URL { vendor.pageURL }

    /// Components that drive the headline for this app (e.g. "Claude Code").
    var relevantComponents: [StatusComponent] {
        components.filter { !$0.isGroup && vendor.isRelevantComponent(named: $0.name) }
    }

    /// Every non-operational component, relevant or not.
    var affectedComponents: [StatusComponent] {
        components.filter { !$0.isGroup && $0.status.level != .operational }
    }

    /// Non-operational components that are not already in the relevant list.
    var otherAffectedComponents: [StatusComponent] {
        let relevantIds = Set(relevantComponents.map { $0.id })
        return affectedComponents.filter { !relevantIds.contains($0.id) }
    }

    /// Worst state across the relevant components; falls back to the page-level
    /// indicator when no relevant component is listed.
    var effectiveLevel: StatusLevel {
        guard isLoaded else { return .unknown }
        let relevant = relevantComponents
        if !relevant.isEmpty {
            return relevant.map { $0.status.level }.max() ?? indicator.level
        }
        return indicator.level
    }

    /// Short label for pills: relevant components first, else the page description.
    var headline: String {
        guard isLoaded else {
            return errorMessage == nil ? "Checking…" : "Status unavailable"
        }
        let level = effectiveLevel
        if level == .operational {
            return relevantComponents.isEmpty ? "Operational" : "All systems go"
        }
        return level.label
    }

    var activeIncidents: [StatusIncident] {
        incidents.filter { ($0.status ?? "").lowercased() != "resolved" }
    }
}
