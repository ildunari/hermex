import Foundation
import SwiftUI

/// How session rows are bucketed into sections.
enum SessionGrouping: String, CaseIterable, Identifiable, Sendable {
    case date
    case project
    case status
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: String(localized: "Date")
        case .project: String(localized: "Project")
        case .status: String(localized: "Status")
        case .profile: String(localized: "Profile")
        }
    }
}

/// How rows are ordered inside each section.
enum SessionOrdering: String, CaseIterable, Identifiable, Sendable {
    case recent
    case created
    case status
    case tokens
    case cost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: String(localized: "Recent")
        case .created: String(localized: "Created")
        case .status: String(localized: "Status")
        case .tokens: String(localized: "Tokens")
        case .cost: String(localized: "Cost")
        }
    }
}

/// Optional row filters. Each is independent; enabling several narrows the list
/// to rows matching *any* enabled status filter, with `archived` handled
/// separately as an inclusion toggle.
enum SessionStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case needsInput
    case working
    case unread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsInput: String(localized: "Needs input")
        case .working: String(localized: "Working")
        case .unread: String(localized: "Unread")
        }
    }
}

/// Persisted sort/group/filter state for the session list.
///
/// Stored as primitives in `AppStorage` so the whole struct survives relaunch
/// without a custom codable container.
struct SessionSortPreferences: Equatable, Sendable {
    var grouping: SessionGrouping = .date
    var ordering: SessionOrdering = .recent
    var activeFilters: Set<SessionStatusFilter> = []
    var includesArchived: Bool = false

    static let `default` = SessionSortPreferences()

    /// True when anything differs from the default view, which drives the
    /// "engaged" treatment on the toolbar button.
    var isModified: Bool { self != Self.default }

    // MARK: - AppStorage keys

    enum StorageKey {
        static let grouping = "sessionList.grouping"
        static let ordering = "sessionList.ordering"
        static let filters = "sessionList.statusFilters"
        static let includesArchived = "sessionList.includesArchived"
    }

    /// Filters serialize as a stable comma-joined string so `AppStorage` can
    /// hold them without a transformable value.
    static func encodeFilters(_ filters: Set<SessionStatusFilter>) -> String {
        filters.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func decodeFilters(_ raw: String) -> Set<SessionStatusFilter> {
        Set(
            raw.split(separator: ",")
                .map(String.init)
                .compactMap(SessionStatusFilter.init(rawValue:))
        )
    }
}
