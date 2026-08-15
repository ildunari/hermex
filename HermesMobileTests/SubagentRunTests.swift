import XCTest
@testable import HermesMobile

@MainActor
final class SubagentRunTests: APIClientTestCase {
    func testDecoderNormalizesLifecycleAndToleratesUnknownFields() throws {
        let run = try decodeRun(
            lifecycle: "timeout",
            sequence: 7,
            extra: #", "future": {"nested": true}"#
        )

        XCTAssertEqual(run.subagentID, "sa-1")
        XCTAssertEqual(run.lifecycle, .timedOut)
        XCTAssertEqual(run.rawLifecycle, "timeout")
        XCTAssertEqual(run.usage?.inputTokens, 12_400)
        XCTAssertEqual(run.usage?.outputTokens, 2_100)
    }

    func testUnknownLifecycleStaysUnknownInsteadOfClaimingRunning() throws {
        let run = try decodeRun(lifecycle: "future_state", sequence: 1)
        XCTAssertEqual(run.lifecycle, .unknown("future_state"))
        XCTAssertFalse(run.lifecycle.isActive)
        XCTAssertFalse(run.lifecycle.isTerminal)
    }

    func testDecoderCoversEveryNormalizedLifecycle() throws {
        let cases: [(String, SubagentLifecycle)] = [
            ("queued", .queued),
            ("running", .running),
            ("finalizing", .finalizing),
            ("completed", .completed),
            ("failed", .failed),
            ("interrupted", .interrupted),
            ("cancelled", .cancelled),
            ("timed_out", .timedOut),
            ("stalled", .stalled),
        ]

        for (raw, expected) in cases {
            XCTAssertEqual(try decodeRun(lifecycle: raw, sequence: 1).lifecycle, expected)
        }
    }

    func testDecoderAcceptsMissingOptionalMetadata() throws {
        let data = Data(#"{"subagent_id":"sa-minimal","lifecycle":"running"}"#.utf8)
        let run = try JSONDecoder().decode(SubagentRun.self, from: data)

        XCTAssertEqual(run.subagentID, "sa-minimal")
        XCTAssertEqual(run.lifecycle, .running)
        XCTAssertNil(run.model)
        XCTAssertNil(run.reasoningEffort)
        XCTAssertNil(run.toolCount)
        XCTAssertNil(run.usage)
    }

    func testReducerRejectsStaleUpdateAndTerminalReopen() throws {
        let store = SubagentStore()
        store.reset(parentSessionID: "parent")
        store.apply(try decodeRun(lifecycle: "completed", sequence: 4), expectedParentSessionID: "parent")
        store.apply(try decodeRun(lifecycle: "running", sequence: 5), expectedParentSessionID: "parent")
        store.apply(try decodeRun(lifecycle: "failed", sequence: 3), expectedParentSessionID: "parent")

        XCTAssertEqual(store.children.count, 1)
        XCTAssertEqual(store.children.first?.lifecycle, .completed)
        XCTAssertEqual(store.children.first?.sequence, 4)
    }

    func testReducerPreservesFirstSeenOrderAndClearsOnParentSwitch() throws {
        let store = SubagentStore()
        store.reset(parentSessionID: "parent")
        store.apply(try decodeRun(id: "sa-2", lifecycle: "running", sequence: 1), expectedParentSessionID: "parent")
        store.apply(try decodeRun(id: "sa-1", lifecycle: "running", sequence: 1), expectedParentSessionID: "parent")
        store.apply(try decodeRun(id: "sa-2", lifecycle: "completed", sequence: 2), expectedParentSessionID: "parent")
        XCTAssertEqual(store.children.map(\.subagentID), ["sa-2", "sa-1"])

        store.reset(parentSessionID: "other")
        XCTAssertTrue(store.children.isEmpty)
        XCTAssertEqual(store.parentSessionID, "other")
    }

    func testReducerBoundsRetainedChildren() throws {
        let store = SubagentStore()
        store.reset(parentSessionID: "parent")

        for index in 0..<70 {
            store.apply(
                try decodeRun(id: "sa-\(index)", lifecycle: "completed", sequence: 1),
                expectedParentSessionID: "parent"
            )
        }

        XCTAssertEqual(store.children.count, 64)
        XCTAssertEqual(store.children.first?.subagentID, "sa-6")
        XCTAssertEqual(store.children.last?.subagentID, "sa-69")
    }

    func testSnapshotEndpointEncodesParentAsOnePathSegment() async throws {
        let client = makeClient { request in
            XCTAssertEqual(
                request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath },
                "/api/sessions/parent%2F%2E%2E%2Fchild/subagents"
            )
            return apiTestJSONResponse(
                #"{"version":1,"parent_session_id":"parent/../child","cursor":"run:2","children":[{"subagent_id":"sa-api","parent_session_id":"parent/../child","parent_run_id":"run","lifecycle":"running","sequence":2}]}"#,
                for: request
            )
        }

        let response = try await client.subagents(parentSessionID: "parent/../child")
        XCTAssertEqual(response.parentSessionID, "parent/../child")
        XCTAssertEqual(response.children?.first?.subagentID, "sa-api")
    }

    func testSSEDecoderAcceptsNormalizedUpsert() throws {
        let json = runJSON(lifecycle: "running", sequence: 2)
        guard case .subagentUpsert(let run) = SSEEventDecoder.decode(
            eventType: "subagent.upsert",
            data: json
        ) else {
            return XCTFail("Expected subagent upsert")
        }
        XCTAssertEqual(run.subagentID, "sa-1")
        XCTAssertEqual(run.lifecycle, .running)
    }

    private func decodeRun(
        id: String = "sa-1",
        lifecycle: String,
        sequence: Int,
        extra: String = ""
    ) throws -> SubagentRun {
        try JSONDecoder().decode(
            SubagentRun.self,
            from: Data(runJSON(id: id, lifecycle: lifecycle, sequence: sequence, extra: extra).utf8)
        )
    }

    private func runJSON(
        id: String = "sa-1",
        lifecycle: String,
        sequence: Int,
        extra: String = ""
    ) -> String {
        """
        {
          "version": 1,
          "subagent_id": "\(id)",
          "parent_session_id": "parent",
          "parent_run_id": "run-1",
          "task_index": 0,
          "prompt": "Inspect the lifecycle contract",
          "lifecycle": "\(lifecycle)",
          "raw_lifecycle": "\(lifecycle)",
          "started_at": 100,
          "updated_at": 110,
          "completed_at": 112,
          "tool_count": 8,
          "usage": {"input_tokens": 12400, "output_tokens": 2100},
          "sequence": \(sequence)\(extra)
        }
        """
    }
}
