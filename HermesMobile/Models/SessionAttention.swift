import Foundation

/// Pending approval or clarify work attached to a session row.
///
/// The WebUI list endpoint (`/api/sessions`) injects this payload per row after
/// its field allowlist runs, so it is available on list rows even though it is
/// not part of the allowlist itself. Detail responses never carry it.
struct SessionAttention: Decodable, Equatable, Hashable {
    /// What kind of work is waiting. Unknown server values decode as `.unknown`
    /// rather than failing the whole row.
    enum Kind: String, Decodable, Equatable, Hashable {
        case approval
        case clarify
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    /// Server severity. `critical` marks blocking approvals; `question` marks
    /// clarify prompts.
    enum Severity: String, Decodable, Equatable, Hashable {
        case critical
        case question
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Severity(rawValue: raw) ?? .unknown
        }
    }

    let kind: Kind
    let count: Int
    let severity: Severity

    init(kind: Kind, count: Int, severity: Severity) {
        self.kind = kind
        self.count = count
        self.severity = severity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .unknown
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case count
        case severity
    }

    /// A row only counts as needing attention when the server reported real
    /// pending work. A zero count is treated as "nothing waiting".
    var isActionable: Bool { count > 0 }

    /// Blocking approvals are louder than clarify questions, which drives both
    /// badge colour and the pulse animation.
    var isBlocking: Bool { severity == .critical || kind == .approval }
}

extension SessionSummary {
    /// True when the server reported pending approval/clarify work for this row.
    var needsAttention: Bool { attention?.isActionable == true }

    /// Number of pending items, or zero when nothing is waiting.
    var attentionCount: Int { attention?.isActionable == true ? (attention?.count ?? 0) : 0 }
}
