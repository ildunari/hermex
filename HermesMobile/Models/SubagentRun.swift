import Foundation

enum SubagentLifecycle: Equatable, Hashable, Sendable {
    case queued
    case running
    case finalizing
    case completed
    case failed
    case interrupted
    case cancelled
    case timedOut
    case stalled
    case unknown(String?)

    init(serverValue: String?) {
        let normalized = serverValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "queued", "starting", "spawn_requested": self = .queued
        case "running", "started": self = .running
        case "finalizing", "finishing": self = .finalizing
        case "completed", "complete", "success", "succeeded": self = .completed
        case "failed", "error": self = .failed
        case "interrupted": self = .interrupted
        case "cancelled", "canceled": self = .cancelled
        case "timed_out", "timeout": self = .timedOut
        case "stalled": self = .stalled
        default: self = .unknown(normalized)
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .running, .finalizing: true
        default: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .interrupted, .cancelled, .timedOut, .stalled: true
        default: false
        }
    }

    var isFailure: Bool {
        switch self {
        case .failed, .timedOut, .stalled: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .queued: String(localized: "Starting")
        case .running: String(localized: "Running")
        case .finalizing: String(localized: "Finalizing")
        case .completed: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .interrupted: String(localized: "Interrupted")
        case .cancelled: String(localized: "Cancelled")
        case .timedOut: String(localized: "Timed out")
        case .stalled: String(localized: "Stalled")
        case .unknown: String(localized: "Unknown")
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "circle.dotted"
        case .running: "circle.fill"
        case .finalizing: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .failed, .timedOut, .stalled: "exclamationmark.circle.fill"
        case .interrupted, .cancelled: "stop.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct SubagentUsage: Decodable, Equatable, Sendable {
    let inputTokens: Int64?
    let outputTokens: Int64?
    let reasoningTokens: Int64?
    let costUsd: Double?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case costUsd = "cost_usd"
    }
}

struct SubagentRun: Decodable, Equatable, Identifiable, Sendable {
    let version: Int?
    let subagentID: String
    let parentSessionID: String?
    let parentRunID: String?
    let parentSubagentID: String?
    let delegationGroupID: String?
    let taskIndex: Int?
    let taskCount: Int?
    let prompt: String?
    let shortLabel: String?
    let lifecycle: SubagentLifecycle
    let rawLifecycle: String?
    let model: String?
    let provider: String?
    let reasoningEffort: String?
    let startedAt: TimeInterval?
    let updatedAt: TimeInterval?
    let completedAt: TimeInterval?
    let currentTool: String?
    let toolCount: Int?
    let usage: SubagentUsage?
    let error: String?
    let sequence: Int?

    var id: String { "\(parentRunID ?? "run"):\(subagentID)" }

    var displayLabel: String {
        nonempty(shortLabel) ?? nonempty(prompt) ?? String(localized: "Delegated agent")
    }

    func duration(at now: Date = Date()) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, (completedAt ?? updatedAt ?? now.timeIntervalSince1970) - startedAt)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case subagentID = "subagent_id"
        case parentSessionID = "parent_session_id"
        case parentRunID = "parent_run_id"
        case parentSubagentID = "parent_subagent_id"
        case delegationGroupID = "delegation_group_id"
        case taskIndex = "task_index"
        case taskCount = "task_count"
        case prompt
        case shortLabel = "short_label"
        case lifecycle
        case rawLifecycle = "raw_lifecycle"
        case model, provider
        case reasoningEffort = "reasoning_effort"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case currentTool = "current_tool"
        case toolCount = "tool_count"
        case usage, error, sequence
    }

    init(
        version: Int? = 1,
        subagentID: String,
        parentSessionID: String? = nil,
        parentRunID: String? = nil,
        parentSubagentID: String? = nil,
        delegationGroupID: String? = nil,
        taskIndex: Int? = nil,
        taskCount: Int? = nil,
        prompt: String? = nil,
        shortLabel: String? = nil,
        lifecycle: SubagentLifecycle,
        rawLifecycle: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        reasoningEffort: String? = nil,
        startedAt: TimeInterval? = nil,
        updatedAt: TimeInterval? = nil,
        completedAt: TimeInterval? = nil,
        currentTool: String? = nil,
        toolCount: Int? = nil,
        usage: SubagentUsage? = nil,
        error: String? = nil,
        sequence: Int? = nil
    ) {
        self.version = version
        self.subagentID = subagentID
        self.parentSessionID = parentSessionID
        self.parentRunID = parentRunID
        self.parentSubagentID = parentSubagentID
        self.delegationGroupID = delegationGroupID
        self.taskIndex = taskIndex
        self.taskCount = taskCount
        self.prompt = prompt
        self.shortLabel = shortLabel
        self.lifecycle = lifecycle
        self.rawLifecycle = rawLifecycle
        self.model = model
        self.provider = provider
        self.reasoningEffort = reasoningEffort
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.currentTool = currentTool
        self.toolCount = toolCount
        self.usage = usage
        self.error = error
        self.sequence = sequence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let identifier = container.decodeLossyStringIfPresent(forKey: .subagentID),
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .subagentID,
                in: container,
                debugDescription: "subagent_id is required"
            )
        }
        subagentID = identifier
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
        parentSessionID = try? container.decodeIfPresent(String.self, forKey: .parentSessionID)
        parentRunID = try? container.decodeIfPresent(String.self, forKey: .parentRunID)
        parentSubagentID = try? container.decodeIfPresent(String.self, forKey: .parentSubagentID)
        delegationGroupID = try? container.decodeIfPresent(String.self, forKey: .delegationGroupID)
        taskIndex = try? container.decodeIfPresent(Int.self, forKey: .taskIndex)
        taskCount = try? container.decodeIfPresent(Int.self, forKey: .taskCount)
        prompt = try? container.decodeIfPresent(String.self, forKey: .prompt)
        shortLabel = try? container.decodeIfPresent(String.self, forKey: .shortLabel)
        let raw = (try? container.decodeIfPresent(String.self, forKey: .lifecycle)) ?? nil
        rawLifecycle = (try? container.decodeIfPresent(String.self, forKey: .rawLifecycle)) ?? raw
        lifecycle = SubagentLifecycle(serverValue: raw ?? rawLifecycle)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        provider = try? container.decodeIfPresent(String.self, forKey: .provider)
        reasoningEffort = try? container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        startedAt = try? container.decodeIfPresent(Double.self, forKey: .startedAt)
        updatedAt = try? container.decodeIfPresent(Double.self, forKey: .updatedAt)
        completedAt = try? container.decodeIfPresent(Double.self, forKey: .completedAt)
        currentTool = try? container.decodeIfPresent(String.self, forKey: .currentTool)
        toolCount = try? container.decodeIfPresent(Int.self, forKey: .toolCount)
        usage = try? container.decodeIfPresent(SubagentUsage.self, forKey: .usage)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        sequence = try? container.decodeIfPresent(Int.self, forKey: .sequence)
    }

    private func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SubagentSnapshotResponse: Decodable, Equatable, Sendable {
    let version: Int?
    let parentSessionID: String?
    let cursor: String?
    let children: [SubagentRun]?

    enum CodingKeys: String, CodingKey {
        case version
        case parentSessionID = "parent_session_id"
        case cursor, children
    }
}
