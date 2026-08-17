import Foundation

struct ChatComposerConfigState: Equatable, Sendable {
    var currentWorkspace: String?
    var currentModel: String?
    var currentModelProvider: String?
    var currentProfile: String?
    var selectedProfileName: String?
    var selectedReasoningEffort: String?
    /// Model-aware effort vocabulary (`supported_efforts`); `nil` on older
    /// servers → composer falls back to the full static list (issue #18).
    var supportedReasoningEfforts: [String]?
    /// `supports_reasoning_effort`; `false` hides the effort control, `nil`
    /// (older servers) keeps it visible.
    var supportsReasoningEffort: Bool?
    var modelCatalogGroups: [ModelCatalogGroup]
    var agentCommands: [AgentCommand]
    var workspaceRoots: [WorkspaceRoot]
    var workspaceSuggestions: [String]
    var profileOptions: [ProfileSummary]
    var isSingleProfileMode: Bool

    init(
        currentWorkspace: String? = nil,
        currentModel: String? = nil,
        currentModelProvider: String? = nil,
        currentProfile: String? = nil,
        selectedProfileName: String? = nil,
        selectedReasoningEffort: String? = nil,
        supportedReasoningEfforts: [String]? = nil,
        supportsReasoningEffort: Bool? = nil,
        modelCatalogGroups: [ModelCatalogGroup] = [],
        agentCommands: [AgentCommand] = [],
        workspaceRoots: [WorkspaceRoot] = [],
        workspaceSuggestions: [String] = [],
        profileOptions: [ProfileSummary] = [],
        isSingleProfileMode: Bool = false
    ) {
        self.currentWorkspace = currentWorkspace
        self.currentModel = currentModel
        self.currentModelProvider = currentModelProvider
        self.currentProfile = currentProfile
        self.selectedProfileName = selectedProfileName
        self.selectedReasoningEffort = selectedReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.supportsReasoningEffort = supportsReasoningEffort
        self.modelCatalogGroups = modelCatalogGroups
        self.agentCommands = agentCommands
        self.workspaceRoots = workspaceRoots
        self.workspaceSuggestions = workspaceSuggestions
        self.profileOptions = profileOptions
        self.isSingleProfileMode = isSingleProfileMode
    }
}

struct ChatComposerConfigLoadResult: Sendable {
    let state: ChatComposerConfigState
    let configurationError: Error?
}

/// Loads everything the composer needs (profile, model, provider, reasoning
/// effort, workspaces, commands) for one chat.
///
/// ## Ordering contract — why this is not a flat fan-out
///
/// Hydration is strictly **read-only with respect to the server's active
/// profile**. It never calls `/api/profile/switch`: switching mutates global
/// state every other client observes, and a chat the user opens and immediately
/// abandons must not leave the server switched to that chat's profile. The
/// session's own profile rides each send through chat-start's `profile` field,
/// so `/api/profiles` is only read to resolve the selected profile name and its
/// default model/provider.
///
/// What can overlap (all issued together at the top):
/// - `/api/commands` is a static `hermes_cli` registry with no profile scoping.
/// - `/api/models` and `/api/workspaces` resolve against the server's *current*
///   active profile, which is stable during a read-only load, so they overlap
///   `/api/profiles`.
/// - `/api/reasoning` waits for the catalog because its scope is the resolved
///   model+provider *and* the session id (so the read reflects this chat's
///   retained effort, not another session's override).
///
/// Each endpoint owns its own error handling: a failing `/api/models` no
/// longer abandons workspaces and commands (which previously left the composer
/// with no workspace list until a full reload).
struct ChatComposerConfigLoader {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func loadConfiguration(
        from initialState: ChatComposerConfigState,
        sessionID: String? = nil
    ) async -> ChatComposerConfigLoadResult {
        var state = initialState
        var configurationError: Error?
        // Surface the first failure, matching the previous single-`catch`
        // behavior where the earliest throw won.
        func record(_ error: Error) {
            if configurationError == nil { configurationError = error }
        }

        // Profile-independent endpoints overlap the whole chain. No
        // `/api/profile/switch` is issued here: hydration must never mutate the
        // server's global active profile (a side effect every other client
        // observes). The session's profile rides each send through chat-start's
        // `profile` field, so the composer only needs a read-only resolution.
        async let commandsResult: CommandsResponse? = try? await client.commands()
        async let modelsResult: Result<ModelsResponse, Error> = await Self.capture {
            try await client.models(freshness: .sessionVisit)
        }
        async let workspacesResult: Result<WorkspacesResponse, Error> = await Self.capture {
            try await client.workspaces()
        }

        // ── Phase 1: read-only profile resolution ──
        do {
            let profilesResponse = try await client.profiles()
            state.profileOptions = profilesResponse.profiles ?? []
            state.isSingleProfileMode = profilesResponse.singleProfileMode ?? false
            state.selectedProfileName = Self.nonEmpty(state.currentProfile)
                ?? Self.nonEmpty(profilesResponse.active)
                ?? profilesResponse.effectiveDefaultProfileName
        } catch {
            record(error)
        }

        let selectedProfile = Self.profileSummary(
            matching: state.selectedProfileName,
            in: state.profileOptions
        )
        if state.currentModel == nil {
            state.currentModel = Self.nonEmpty(selectedProfile?.model)
        }
        if Self.nonEmpty(state.currentModelProvider) == nil {
            state.currentModelProvider = Self.nonEmpty(selectedProfile?.provider)
        }

        // ── Phase 2: apply the catalog, then scope reasoning to the resolved
        // model/provider *and* session. The catalog can only change the model
        // when it is still unresolved, so the reasoning read waits for it. ──
        switch await modelsResult {
        case .success(let modelsResponse):
            state.modelCatalogGroups = modelsResponse.catalogGroups
            if state.currentModel == nil {
                state.currentModel = modelsResponse.defaultModel
            }
            if Self.nonEmpty(state.currentModelProvider) == nil {
                state.currentModelProvider = Self.uniqueProvider(
                    for: state.currentModel,
                    in: state.modelCatalogGroups
                )
            }
        case .failure(let error):
            record(error)
        }

        // Scope the query to the session's resolved model/provider *and* its
        // session id so the effort read reflects this chat's retained effort,
        // never another session's override or the global config default.
        let reasoningResult = await Self.capture {
            try await client.reasoning(
                model: Self.nonEmpty(state.currentModel),
                provider: Self.nonEmpty(state.currentModelProvider),
                sessionID: Self.nonEmpty(sessionID)
            )
        }
        switch reasoningResult {
        case .success(let reasoningResponse):
            state.selectedReasoningEffort = reasoningResponse.effectiveEffort
            state.supportedReasoningEfforts = reasoningResponse.normalizedSupportedEfforts
            state.supportsReasoningEffort = reasoningResponse.supportsReasoningEffort
        case .failure(let error):
            record(error)
        }

        switch await workspacesResult {
        case .success(let workspaceResponse):
            state.workspaceRoots = workspaceResponse.workspaces ?? []
            if state.currentWorkspace == nil {
                state.currentWorkspace = workspaceResponse.last ?? state.workspaceRoots.compactMap(\.path).first
            }
            state.workspaceSuggestions = state.workspaceRoots.compactMap(\.path)
        case .failure(let error):
            record(error)
        }

        state.agentCommands = (await commandsResult)?.commands ?? []

        return ChatComposerConfigLoadResult(
            state: state,
            configurationError: configurationError
        )
    }

    /// `async let` cannot bind a `throws` expression without forcing the error
    /// to the awaiting site, which would re-serialize the very calls we are
    /// overlapping. Capturing into a `Result` keeps each endpoint's failure
    /// isolated to its own branch.
    private static func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private static func profileSummary(
        matching profileName: String?,
        in profileOptions: [ProfileSummary]
    ) -> ProfileSummary? {
        guard let profileName = nonEmpty(profileName) else { return nil }
        return profileOptions.first { $0.normalizedName == profileName }
    }

    private static func uniqueProvider(
        for modelID: String?,
        in groups: [ModelCatalogGroup]
    ) -> String? {
        guard let modelID = nonEmpty(modelID) else { return nil }
        let providers = Set(
            groups
                .flatMap(\.slashAutocompleteModels)
                .filter { $0.id == modelID }
                .compactMap { nonEmpty($0.providerID) }
        )
        return providers.count == 1 ? providers.first : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
