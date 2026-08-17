import XCTest
@testable import HermesMobile

/// Thread-safe request recorder. The loader now issues several endpoints
/// concurrently, so a bare `var [String]` captured by the stub handler would be
/// a data race (and would trip TSan) rather than a reliable assertion target.
final class RequestPathRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    private var switchIsInFlight = false
    private var barrierViolations: [String] = []
    private var profileRequestCount = 0

    func record(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
    }

    /// Marks `/api/profile/switch` as unresolved. Any profile-scoped request
    /// observed before `endProfileSwitch()` is a barrier violation: the server
    /// resolves `/api/models` and `/api/workspaces` against the ACTIVE profile,
    /// so issuing them mid-switch returns the previous profile's data.
    func beginProfileSwitch() {
        lock.lock()
        defer { lock.unlock() }
        switchIsInFlight = true
    }

    func endProfileSwitch() {
        lock.lock()
        defer { lock.unlock() }
        switchIsInFlight = false
    }

    func noteProfileScopedRequest(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        if switchIsInFlight {
            barrierViolations.append(path)
        }
    }

    func nextProfileRequestIndex() -> Int {
        lock.lock()
        defer { lock.unlock() }
        profileRequestCount += 1
        return profileRequestCount
    }

    var violations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return barrierViolations
    }

    var value: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }
}

final class ChatComposerConfigLoaderTests: APIClientTestCase {
    func testLoadPinnedInactiveProfileFailsClosedWithoutGlobalSwitch() async throws {
        let openRouterModel = "deepseek/deepseek-chat-v3-0324:free"
        let requestPaths = RequestPathRecorder()
        let client = makeClient { request in
            requestPaths.record(request.url?.path ?? "")

            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "default",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai", "is_default": true},
                    {"name": "work", "model": "\(openRouterModel)", "provider": "openrouter"}
                  ]
                }
                """, for: request)
            case "/api/profile/switch":
                XCTFail("Opening a session must never call /api/profile/switch")
                throw URLError(.badURL)
            case "/api/models":
                return apiTestJSONResponse("""
                {
                  "default_model": "\(openRouterModel)",
                  "groups": [
                    {
                      "name": "OpenRouter",
                      "provider_id": "openrouter",
                      "models": [
                        {"id": "\(openRouterModel)", "name": "DeepSeek Chat v3 Free"}
                      ]
                    }
                  ]
                }
                """, for: request)
            case "/api/reasoning":
                return apiTestJSONResponse(#"{"reasoning_effort": "medium"}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [{"path": "/tmp/workspace"}], "last": "/tmp/workspace"}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": [{"name": "status", "description": "Show status"}]}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState(currentProfile: "work")
        )

        XCTAssertNotNil(result.configurationError)
        XCTAssertEqual(result.state.selectedProfileName, "work")
        XCTAssertEqual(result.state.currentProfile, "work")
        // Read-only resolution still gets the session's default model/provider
        // from the profile list, but withholds profile-scoped catalog/workspaces
        // because the server's ACTIVE profile is "default".
        XCTAssertEqual(result.state.currentModel, openRouterModel)
        XCTAssertEqual(result.state.currentModelProvider, "openrouter")
        XCTAssertNil(result.state.currentWorkspace)
        XCTAssertEqual(result.state.selectedReasoningEffort, "medium")
        // Older server: no supported_efforts / supports_reasoning_effort fields.
        XCTAssertNil(result.state.supportedReasoningEfforts)
        XCTAssertNil(result.state.supportsReasoningEffort)
        XCTAssertTrue(result.state.workspaceSuggestions.isEmpty)
        XCTAssertEqual(result.state.agentCommands.map(\.name), ["status"])

        // Hydration is read-only and fail-closed: it neither switches profiles
        // nor labels the active default profile's catalog/workspaces as "work".
        let paths = requestPaths.value
        XCTAssertFalse(paths.contains("/api/profile/switch"))
        XCTAssertEqual(Set(paths), [
            "/api/profiles",
            "/api/reasoning",
            "/api/commands"
        ])
    }

    func testLoadDiscardsScopedResponsesWhenActiveProfileChangesInFlight() async throws {
        let requests = RequestPathRecorder()
        let client = makeClient { request in
            requests.record(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/profiles":
                let active = requests.nextProfileRequestIndex() == 1 ? "work" : "default"
                return apiTestJSONResponse("""
                {
                  "active": "\(active)",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai"},
                    {"name": "work", "model": "work/model", "provider": "openrouter"}
                  ]
                }
                """, for: request)
            case "/api/models":
                return apiTestJSONResponse(#"{"default_model":"work/model","groups":[{"name":"Work","provider_id":"openrouter","models":[{"id":"work/model","name":"Work Model"}]}]}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces":[{"path":"/tmp/work"}],"last":"/tmp/work"}"#, for: request)
            case "/api/reasoning":
                return apiTestJSONResponse(#"{"reasoning_effort":"high"}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands":[]}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState(currentProfile: "work"),
            sessionID: "session-work"
        )

        XCTAssertNotNil(result.configurationError)
        XCTAssertEqual(result.state.currentModel, "work/model")
        XCTAssertEqual(result.state.currentModelProvider, "openrouter")
        XCTAssertTrue(result.state.modelCatalogGroups.isEmpty)
        XCTAssertTrue(result.state.workspaceSuggestions.isEmpty)
        XCTAssertEqual(result.state.selectedReasoningEffort, "high")
        XCTAssertEqual(requests.value.filter { $0 == "/api/profiles" }.count, 2)
        XCTAssertFalse(requests.value.contains("/api/profile/switch"))
    }

    func testLoadKeepsSessionModelOverrideWhenProfileHasDifferentDefault() async throws {
        let sessionModel = "@openai:gpt-5.5"
        let profileDefault = "deepseek/deepseek-chat-v3-0324:free"
        var reasoningQueryItems: [String: String?] = [:]
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "work",
                  "profiles": [
                    {"name": "work", "model": "\(profileDefault)", "provider": "openrouter", "is_active": true}
                  ]
                }
                """, for: request)
            case "/api/models":
                return apiTestJSONResponse("""
                {
                  "default_model": "\(profileDefault)",
                  "groups": [
                    {
                      "name": "OpenRouter",
                      "provider_id": "openrouter",
                      "models": [{"id": "\(profileDefault)", "name": "DeepSeek Chat v3 Free"}]
                    },
                    {
                      "name": "OpenAI",
                      "provider_id": "openai",
                      "models": [{"id": "\(sessionModel)", "name": "GPT 5.5"}]
                    }
                  ]
                }
                """, for: request)
            case "/api/reasoning":
                let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                reasoningQueryItems = Dictionary(
                    uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) }
                )
                return apiTestJSONResponse("""
                {
                  "reasoning_effort": "high",
                  "supported_efforts": ["low", "medium", "high"],
                  "supports_reasoning_effort": true
                }
                """, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [{"path": "/tmp/workspace"}]}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": []}"#, for: request)
            case "/api/default-model":
                XCTFail("Composer configuration loading must not save profile defaults.")
                throw URLError(.badURL)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState(
                currentWorkspace: "/tmp/workspace",
                currentModel: sessionModel,
                currentModelProvider: "openai",
                currentProfile: "work"
            ),
            sessionID: "session-abc"
        )

        XCTAssertNil(result.configurationError)
        XCTAssertEqual(result.state.currentModel, sessionModel)
        XCTAssertEqual(result.state.currentModelProvider, "openai")
        XCTAssertEqual(result.state.selectedProfileName, "work")
        XCTAssertEqual(result.state.selectedReasoningEffort, "high")
        // The reasoning query is scoped to the session's model/provider AND its
        // session id so the gating fields are model-accurate (issue #18) and
        // the read reflects this chat's retained effort.
        XCTAssertEqual(reasoningQueryItems["model"], sessionModel)
        XCTAssertEqual(reasoningQueryItems["provider"], "openai")
        XCTAssertEqual(reasoningQueryItems["session_id"], "session-abc")
        XCTAssertEqual(result.state.supportedReasoningEfforts, ["low", "medium", "high"])
        XCTAssertEqual(result.state.supportsReasoningEffort, true)
    }

    func testLoadReturnsPartialStateAndStillRefreshesCommandsWhenConfigurationFails() async throws {
        let requestPaths = RequestPathRecorder()
        let client = makeClient { request in
            requestPaths.record(request.url?.path ?? "")

            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "default",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai", "is_default": true}
                  ]
                }
                """, for: request)
            case "/api/models":
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                return (try XCTUnwrap(response), Data(#"{"error":"models unavailable"}"#.utf8))
            case "/api/reasoning":
                return apiTestJSONResponse(#"{"reasoning_effort": "low"}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [{"path": "/tmp/ws"}], "last": "/tmp/ws"}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": [{"name": "status"}]}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState()
        )

        XCTAssertNotNil(result.configurationError)
        XCTAssertEqual(result.state.selectedProfileName, "default")
        XCTAssertEqual(result.state.profileOptions.map(\.name), ["default"])
        XCTAssertEqual(result.state.currentModel, "gpt-5.4")
        // The profile supplies the provider even though the catalog failed.
        XCTAssertEqual(result.state.currentModelProvider, "openai")
        XCTAssertEqual(result.state.agentCommands.map(\.name), ["status"])

        // Regression: a failing `/api/models` used to abandon every remaining
        // request in the same do/catch, leaving the composer with no workspace
        // list and no reasoning vocabulary until a full reload. Each endpoint
        // now owns its own failure.
        XCTAssertEqual(result.state.workspaceSuggestions, ["/tmp/ws"])
        XCTAssertEqual(result.state.currentWorkspace, "/tmp/ws")
        XCTAssertEqual(result.state.selectedReasoningEffort, "low")
        XCTAssertEqual(Set(requestPaths.value), [
            "/api/profiles",
            "/api/models",
            "/api/reasoning",
            "/api/workspaces",
            "/api/commands"
        ])
    }

    /// Without a resolved active profile, profile-scoped catalog/workspace
    /// responses cannot be attributed safely and must not be requested.
    func testLoadFailsClosedWhenProfileResolutionFails() async throws {
        let requestPaths = RequestPathRecorder()
        let client = makeClient { request in
            requestPaths.record(request.url?.path ?? "")

            switch request.url?.path {
            case "/api/profiles":
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                return (try XCTUnwrap(response), Data(#"{"error":"profiles unavailable"}"#.utf8))
            case "/api/models":
                return apiTestJSONResponse(#"{"default_model": "gpt-5.4", "groups": []}"#, for: request)
            case "/api/reasoning":
                return apiTestJSONResponse(#"{"reasoning_effort": "low"}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [{"path": "/tmp/ws"}], "last": "/tmp/ws"}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": [{"name": "status"}]}"#, for: request)
            case "/api/profile/switch":
                XCTFail("Opening a session must never call /api/profile/switch")
                throw URLError(.badURL)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState(currentProfile: "work")
        )

        XCTAssertNotNil(result.configurationError)
        XCTAssertEqual(Set(requestPaths.value), [
            "/api/profiles",
            "/api/reasoning",
            "/api/commands"
        ])
        XCTAssertEqual(result.state.modelCatalogGroups.count, 0)
        XCTAssertTrue(result.state.workspaceSuggestions.isEmpty)
        XCTAssertEqual(result.state.selectedReasoningEffort, "low")
    }

    /// A session that already pins model+provider lets `/api/reasoning` overlap
    /// `/api/models` — but the resolved scope must be identical to the
    /// serialized path, since the catalog cannot override an explicit pin.
    func testReasoningStaysScopedToPinnedSessionModelWhenOverlappingCatalog() async throws {
        let sessionModel = "@openai:gpt-5.5"
        let reasoningQuery = RequestPathRecorder()
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "work",
                  "profiles": [
                    {"name": "work", "model": "other/model", "provider": "openrouter", "is_active": true}
                  ]
                }
                """, for: request)
            case "/api/models":
                return apiTestJSONResponse("""
                {
                  "default_model": "other/model",
                  "groups": [
                    {
                      "name": "OpenRouter",
                      "provider_id": "openrouter",
                      "models": [{"id": "other/model", "name": "Other"}]
                    }
                  ]
                }
                """, for: request)
            case "/api/reasoning":
                let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                let model = (components?.queryItems ?? []).first { $0.name == "model" }?.value
                let provider = (components?.queryItems ?? []).first { $0.name == "provider" }?.value
                let sessionID = (components?.queryItems ?? []).first { $0.name == "session_id" }?.value
                reasoningQuery.record("\("\(model ?? "nil")|\(provider ?? "nil")|\(sessionID ?? "nil")")")
                return apiTestJSONResponse(#"{"reasoning_effort": "high"}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": []}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": []}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState(
                currentModel: sessionModel,
                currentModelProvider: "openai",
                currentProfile: "work"
            ),
            sessionID: "session-abc"
        )

        XCTAssertNil(result.configurationError)
        XCTAssertEqual(reasoningQuery.value, ["\(sessionModel)|openai|session-abc"])
        XCTAssertEqual(result.state.currentModel, sessionModel)
        XCTAssertEqual(result.state.currentModelProvider, "openai")
        XCTAssertEqual(result.state.selectedReasoningEffort, "high")
    }

    /// A/B independent hydration: two different sessions each read their own
    /// retained effort, and the reasoning GET carries the matching session id,
    /// so switching among sessions never leaks one chat's override into another.
    func testLoadHydratesIndependentEffortPerSession() async throws {
        let queries = RequestPathRecorder()
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "default",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai", "is_default": true}
                  ]
                }
                """, for: request)
            case "/api/models":
                return apiTestJSONResponse(#"{"default_model": "gpt-5.4", "groups": []}"#, for: request)
            case "/api/reasoning":
                let components = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
                let sessionID = (components?.queryItems ?? []).first { $0.name == "session_id" }?.value
                queries.record(sessionID ?? "nil")
                let effort = sessionID == "session-a" ? "high" : "low"
                return apiTestJSONResponse(
                    #"{"reasoning_effort": "\#(effort)"}"#,
                    for: request
                )
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [], "last": null}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": []}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let loader = ChatComposerConfigLoader(client: client)
        let sessionA = await loader.loadConfiguration(
            from: ChatComposerConfigState(),
            sessionID: "session-a"
        )
        let sessionB = await loader.loadConfiguration(
            from: ChatComposerConfigState(),
            sessionID: "session-b"
        )

        XCTAssertNil(sessionA.configurationError)
        XCTAssertNil(sessionB.configurationError)
        XCTAssertEqual(sessionA.state.selectedReasoningEffort, "high")
        XCTAssertEqual(sessionB.state.selectedReasoningEffort, "low")
        // MockURLProtocol is process-global, so unrelated configuration tests may
        // issue an unscoped reasoning request while this async test is running.
        // Assert this loader's two session-scoped requests without treating that
        // unrelated traffic as part of the A/B contract.
        XCTAssertEqual(
            queries.value.filter { $0 == "session-a" || $0 == "session-b" },
            ["session-a", "session-b"]
        )
    }

    /// `/api/profile/switch` mutates the server's ACTIVE profile, which every
    /// other client observes. Now that the load starts as soon as the chat
    /// appears, a chat opened and immediately abandoned must not leave the
    /// server switched to that chat's profile.
    func testCancelledLoadDoesNotSwitchServerProfile() async throws {
        let requestPaths = RequestPathRecorder()
        let client = makeClient { request in
            requestPaths.record(request.url?.path ?? "")

            switch request.url?.path {
            case "/api/profiles":
                // Stall so the surrounding task is cancelled before the loader
                // would have reached any profile-dependent work.
                Thread.sleep(forTimeInterval: 0.2)
                return apiTestJSONResponse("""
                {
                  "active": "default",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai", "is_default": true},
                    {"name": "work", "model": "other/model", "provider": "openrouter"}
                  ]
                }
                """, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": []}"#, for: request)
            default:
                return apiTestJSONResponse(#"{}"#, for: request)
            }
        }

        let task = Task {
            await ChatComposerConfigLoader(client: client).loadConfiguration(
                from: ChatComposerConfigState(currentProfile: "work")
            )
        }
        // Let the loader start its first request, then abandon the chat.
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        _ = await task.value

        XCTAssertFalse(
            requestPaths.value.contains("/api/profile/switch"),
            "an abandoned chat open must not mutate the server's active profile"
        )
    }

    func testLoadStoresSingleProfileModeFromProfilesResponse() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/profiles":
                return apiTestJSONResponse("""
                {
                  "active": "default",
                  "profiles": [
                    {"name": "default", "model": "gpt-5.4", "provider": "openai", "is_default": true, "is_active": true}
                  ],
                  "single_profile_mode": true
                }
                """, for: request)
            case "/api/models":
                XCTAssertEqual(
                    URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                        .queryItems?
                        .first(where: { $0.name == "freshness" })?
                        .value,
                    "session_visit"
                )
                return apiTestJSONResponse(#"{"default_model": "gpt-5.4", "groups": []}"#, for: request)
            case "/api/reasoning":
                return apiTestJSONResponse(#"{"reasoning_effort": "medium"}"#, for: request)
            case "/api/workspaces":
                return apiTestJSONResponse(#"{"workspaces": [], "last": null}"#, for: request)
            case "/api/commands":
                return apiTestJSONResponse(#"{"commands": []}"#, for: request)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let result = await ChatComposerConfigLoader(client: client).loadConfiguration(
            from: ChatComposerConfigState()
        )

        XCTAssertNil(result.configurationError)
        XCTAssertTrue(result.state.isSingleProfileMode)
    }
}

/// Pure gating logic for the composer reasoning-effort menu (issue #18):
/// building the option list from `supported_efforts` and deciding whether
/// the control is shown at all.
final class ReasoningEffortGatingTests: XCTestCase {
    func testOptionsFallBackToStaticListWithoutServerVocabulary() {
        XCTAssertEqual(
            ReasoningEffortOption.options(forSupportedEfforts: nil).map(\.id),
            ["none", "minimal", "low", "medium", "high", "xhigh"]
        )
        // Defensive: an empty list also falls back (the control is hidden
        // before this is rendered because supports_reasoning_effort is false).
        XCTAssertEqual(
            ReasoningEffortOption.options(forSupportedEfforts: []).map(\.id),
            ["none", "minimal", "low", "medium", "high", "xhigh"]
        )
    }

    func testOptionsFilterToServerVocabularyPreservingServerOrder() {
        let options = ReasoningEffortOption.options(forSupportedEfforts: ["high", "low"])
        XCTAssertEqual(options.map(\.id), ["high", "low"])
        XCTAssertEqual(options.map(\.title), ["High", "Low"])
    }

    func testOptionsNormalizeAndKeepUnknownServerEfforts() {
        let options = ReasoningEffortOption.options(forSupportedEfforts: [" Low ", "low", "", "turbo"])
        XCTAssertEqual(options.map(\.id), ["low", "turbo"])
        XCTAssertEqual(options.map(\.title), ["Low", "Turbo"])
    }

    func testShowsEffortControlFollowsServerFlag() {
        XCTAssertFalse(ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: false,
            supportedEfforts: ["low"]
        ))
        XCTAssertTrue(ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: true,
            supportedEfforts: []
        ))
    }

    func testShowsEffortControlInfersFromEffortsWhenFlagMissing() {
        XCTAssertFalse(ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: nil,
            supportedEfforts: []
        ))
        XCTAssertTrue(ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: nil,
            supportedEfforts: ["low"]
        ))
        // Older servers send neither field: keep today's behavior (visible).
        XCTAssertTrue(ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: nil,
            supportedEfforts: nil
        ))
    }
}
