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

private struct ProfileScopeChangedDuringLoad: LocalizedError, Sendable {
    var errorDescription: String? {
        String(localized: "The server's active profile changed while loading this chat. Profile-scoped model and workspace choices were withheld to avoid showing another profile's configuration.")
    }
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
/// What can overlap:
/// - `/api/commands` is a static `hermes_cli` registry with no profile scoping.
/// - `/api/models` and `/api/workspaces` overlap only after `/api/profiles`
///   confirms the session profile matches the server's current active profile.
///   A second profile read validates that the scope did not change in flight;
///   otherwise both responses are discarded rather than mislabeled.
/// - `/api/reasoning` waits until the session model/provider are resolved and
///   then scopes the read by those values plus the session id, so it remains
///   safe even when a profile-scoped catalog response is withheld.
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

        // Profile-independent: this can overlap the entire read-only load.
        async let commandsResult: CommandsResponse? = try? await client.commands()

        // Resolve the session profile without mutating the server-global active
        // profile. `/api/models` and `/api/workspaces` are active-profile scoped,
        // so they are only safe when the session profile matches the active
        // profile observed before *and after* those reads.
        var activeProfileBeforeScopedReads: String?
        var canReadProfileScopedEndpoints = false
        do {
            let profilesResponse = try await client.profiles()
            state.profileOptions = profilesResponse.profiles ?? []
            state.isSingleProfileMode = profilesResponse.singleProfileMode ?? false
            activeProfileBeforeScopedReads = Self.nonEmpty(profilesResponse.active)
            state.selectedProfileName = Self.nonEmpty(state.currentProfile)
                ?? activeProfileBeforeScopedReads
                ?? profilesResponse.effectiveDefaultProfileName
            canReadProfileScopedEndpoints = Self.nonEmpty(state.currentProfile) == nil
                || Self.nonEmpty(state.currentProfile) == activeProfileBeforeScopedReads
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

        var modelsResult: Result<ModelsResponse, Error>?
        var workspacesResult: Result<WorkspacesResponse, Error>?
        if canReadProfileScopedEndpoints {
            async let scopedModels = Self.capture {
                try await client.models(freshness: .sessionVisit)
            }
            async let scopedWorkspaces = Self.capture {
                try await client.workspaces()
            }
            modelsResult = await scopedModels
            workspacesResult = await scopedWorkspaces

            // Another client can switch the global active profile while these
            // requests are in flight. Re-read it and discard both responses if
            // the scope moved; showing no catalog is safer than showing another
            // profile's models as though they belonged to this session.
            do {
                let activeAfter = Self.nonEmpty(try await client.profiles().active)
                if activeAfter != activeProfileBeforeScopedReads {
                    canReadProfileScopedEndpoints = false
                    modelsResult = nil
                    workspacesResult = nil
                    record(ProfileScopeChangedDuringLoad())
                }
            } catch {
                canReadProfileScopedEndpoints = false
                modelsResult = nil
                workspacesResult = nil
                record(error)
            }
        } else if Self.nonEmpty(state.currentProfile) != nil {
            record(ProfileScopeChangedDuringLoad())
        }

        if canReadProfileScopedEndpoints {
            switch modelsResult {
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
            case nil:
                break
            }
        }

        // The reasoning endpoint is explicitly scoped by model/provider/session,
        // so it remains safe even when the profile-global catalog was discarded.
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

        if canReadProfileScopedEndpoints {
            switch workspacesResult {
            case .success(let workspaceResponse):
                state.workspaceRoots = workspaceResponse.workspaces ?? []
                if state.currentWorkspace == nil {
                    state.currentWorkspace = workspaceResponse.last ?? state.workspaceRoots.compactMap(\.path).first
                }
                state.workspaceSuggestions = state.workspaceRoots.compactMap(\.path)
            case .failure(let error):
                record(error)
            case nil:
                break
            }
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
