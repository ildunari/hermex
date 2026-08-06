import SwiftUI
import XCTest
@testable import HermesMobile

/// Display-pacing tests for issue #212: buffered streamed tokens are revealed
/// word-by-word at an adaptive cadence, while completion paths flush instantly.
final class ChatViewModelStreamingPaceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    @MainActor
    func testBufferedBurstRevealsWordByWordAtCadence() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        // 60s lag bound keeps the quota at one word per tick for this backlog.
        let viewModel = try makeViewModel(
            streamClient: streamClient,
            wordCadenceNanoseconds: 200_000_000,
            maxLagNanoseconds: 60_000_000_000
        )

        let didStart = await viewModel.sendMessage("Stream a reply")
        XCTAssertTrue(didStart)

        streamClient.emit(.token("alpha beta gamma delta"))

        let target = "alpha beta gamma delta"
        let observed = try await observeAssistantContent(viewModel, until: target)

        XCTAssertEqual(observed.first, "alpha ")
        XCTAssertEqual(observed.last, target)
        XCTAssertGreaterThanOrEqual(
            observed.count, 3,
            "burst should reveal progressively across cadence ticks, not at once; observed: \(observed)"
        )
        for (earlier, later) in zip(observed, observed.dropFirst()) {
            XCTAssertTrue(
                later.hasPrefix(earlier),
                "paced reveal must only append: \(earlier) → \(later)"
            )
        }

        // The drain loop must re-arm for tokens arriving after the buffer emptied.
        streamClient.emit(.token(" epsilon"))
        _ = try await observeAssistantContent(viewModel, until: target + " epsilon")
        XCTAssertEqual(assistantContent(of: viewModel), target + " epsilon")
    }

    @MainActor
    func testLargeBacklogCatchesUpWithinLagBound() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        // 60 words × 100ms cadence = 6s of backlog; the 300ms lag bound forces a
        // ~20-word quota per tick, so convergence inside the 4s observation window
        // proves catch-up scaling (steady one-word cadence would time out).
        let viewModel = try makeViewModel(
            streamClient: streamClient,
            wordCadenceNanoseconds: 100_000_000,
            maxLagNanoseconds: 300_000_000
        )

        let didStart = await viewModel.sendMessage("Stream a reply")
        XCTAssertTrue(didStart)

        let words = (0..<60).map { "w\($0) " }
        for word in words {
            streamClient.emit(.token(word))
        }

        let target = words.joined()
        let observed = try await observeAssistantContent(viewModel, until: target)

        XCTAssertEqual(observed.last, target)
        XCTAssertGreaterThanOrEqual(
            observed.count, 2,
            "catch-up should drain in scaled chunks, not one dump; observed counts: \(observed.map(\.count))"
        )
    }

    @MainActor
    func testDoneEventFlushesRemainingBufferImmediately() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeStalledDrainViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Stream a reply")
        XCTAssertTrue(didStart)

        streamClient.emit(.token("alpha beta gamma"))
        _ = try await observeAssistantContent(viewModel, until: "alpha ")
        XCTAssertEqual(assistantContent(of: viewModel), "alpha ")

        streamClient.emit(.done(DoneStreamEvent()))
        XCTAssertEqual(assistantContent(of: viewModel), "alpha beta gamma")

        // Nothing may trickle in after completion.
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(assistantContent(of: viewModel), "alpha beta gamma")
    }

    @MainActor
    func testCancelledEventFlushesRemainingBufferImmediately() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeStalledDrainViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Stream a reply")
        XCTAssertTrue(didStart)

        streamClient.emit(.token("alpha beta gamma"))
        _ = try await observeAssistantContent(viewModel, until: "alpha ")
        XCTAssertEqual(assistantContent(of: viewModel), "alpha ")

        streamClient.emit(.cancelled)
        XCTAssertEqual(assistantContent(of: viewModel), "alpha beta gamma")

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(assistantContent(of: viewModel), "alpha beta gamma")
    }

    @MainActor
    func testPacedContentConvergesByteIdenticalToUnpacedJoin() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeViewModel(
            streamClient: streamClient,
            wordCadenceNanoseconds: 1_000_000,
            maxLagNanoseconds: 50_000_000
        )

        let didStart = await viewModel.sendMessage("Stream a reply")
        XCTAssertTrue(didStart)

        // Awkward chunk boundaries: ZWJ family, flag, CRLF, tabs, doubled spaces,
        // and a combining mark split across chunks ("cafe" + U+0301).
        let chunks = [
            "The 👩‍👩‍👧‍👦 family ",
            "and 🇫🇷 flag met.\r\n",
            "tabs\tand  doubles ",
            "cafe",
            "\u{301} fin"
        ]
        for chunk in chunks {
            streamClient.emit(.token(chunk))
        }

        let target = chunks.joined()
        _ = try await observeAssistantContent(viewModel, until: target)
        let content = try XCTUnwrap(assistantContent(of: viewModel))
        XCTAssertEqual(
            Array(content.utf8),
            Array(target.utf8),
            "paced content must converge byte-identical to the unpaced concatenation"
        )
    }

    // MARK: - Helpers

    /// 60s cadence with a far larger lag bound keeps the quota at one word per
    /// tick: the first tick reveals one word, then the drain effectively stalls
    /// so completion-path flushes are observable.
    @MainActor
    private func makeStalledDrainViewModel(
        streamClient: PacingSpySSEStreamingClient
    ) throws -> ChatViewModel {
        try makeViewModel(
            streamClient: streamClient,
            wordCadenceNanoseconds: 60_000_000_000,
            maxLagNanoseconds: 3_600_000_000_000
        )
    }

    @MainActor
    private func makeViewModel(
        streamClient: PacingSpySSEStreamingClient,
        wordCadenceNanoseconds: UInt64,
        maxLagNanoseconds: UInt64
    ) throws -> ChatViewModel {
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/chat/start":
                return apiTestJSONResponse(
                    #"{"session_id": "session-abc", "stream_id": "stream-123"}"#,
                    for: request
                )
            default:
                return apiTestJSONResponse(
                    #"{"session": {"session_id": "session-abc", "title": "Pacing", "messages": []}}"#,
                    for: request
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        let client = APIClient(baseURL: server, session: urlSession)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(
            SessionSummary.self,
            from: Data(
                #"{"session_id": "session-abc", "title": "Pacing", "workspace": "/tmp/workspace"}"#.utf8
            )
        )

        return ChatViewModel(
            session: summary,
            server: server,
            client: client,
            streamClient: streamClient,
            approvalStreamClient: PacingSpySSEStreamingClient(),
            clarifyStreamClient: PacingSpySSEStreamingClient(),
            streamingScrollCoalescingDelayNanoseconds: 1_000_000,
            streamingWordRevealCadenceNanoseconds: wordCadenceNanoseconds,
            streamingMaxRevealLagNanoseconds: maxLagNanoseconds
        )
    }

    @MainActor
    private func assistantContent(of viewModel: ChatViewModel) -> String? {
        viewModel.messages.last(where: { $0.role == "assistant" })?.content
    }

    /// Polls assistant content every 5ms until it equals `target` (or times out),
    /// returning every distinct non-empty value observed in order.
    @MainActor
    private func observeAssistantContent(
        _ viewModel: ChatViewModel,
        until target: String,
        timeoutNanoseconds: UInt64 = 4_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String] {
        let pollNanoseconds: UInt64 = 5_000_000
        var observed: [String] = []
        var elapsed: UInt64 = 0
        while elapsed <= timeoutNanoseconds {
            if let content = assistantContent(of: viewModel), !content.isEmpty,
               observed.last != content {
                observed.append(content)
            }
            if observed.last == target {
                return observed
            }

            try await Task.sleep(nanoseconds: pollNanoseconds)
            elapsed += pollNanoseconds
        }

        XCTFail(
            "timed out waiting for \(target); observed: \(observed)",
            file: file,
            line: line
        )
        return observed
    }
}

/// Reasoning/tool activity (session-view polish). Two layers under test:
/// `StreamActivitySignal` is micro-liveness (bump + decay after silence), and
/// `TurnPhase` is the semantic step model that actually drives the capsules —
/// "Thinking" holds through intra-step token pauses and only settles when the
/// stream moves on to a tool call or the final answer.
final class StreamActivitySignalTests: XCTestCase {
    @MainActor
    func testBumpActivatesImmediatelyAndDecaysAfterSilence() async throws {
        let signal = StreamActivitySignal(decayInterval: 0.1)
        XCTAssertFalse(signal.isActive)

        signal.bump()
        XCTAssertTrue(signal.isActive, "rising edge must have no debounce")

        try await waitFor(timeoutNanoseconds: 2_000_000_000) { signal.isActive == false }
        XCTAssertFalse(signal.isActive, "signal must decay after the silence window")
    }

    @MainActor
    func testRepeatedBumpsExtendTheDeadline() async throws {
        let signal = StreamActivitySignal(decayInterval: 0.15)

        signal.bump()
        // Keep bumping at intervals shorter than the decay window; the signal
        // must stay active the whole time (single coalesced expiry task).
        for _ in 0..<4 {
            try await Task.sleep(nanoseconds: 60_000_000)
            XCTAssertTrue(signal.isActive, "activity within the window must keep the signal alive")
            signal.bump()
        }

        try await waitFor(timeoutNanoseconds: 2_000_000_000) { signal.isActive == false }
        XCTAssertFalse(signal.isActive)
    }

    @MainActor
    func testResetDeactivatesImmediately() async throws {
        let signal = StreamActivitySignal(decayInterval: 60)

        signal.bump()
        XCTAssertTrue(signal.isActive)

        signal.reset()
        XCTAssertFalse(signal.isActive, "reset must not wait for the decay window")

        // Reactivation after reset works (fresh expiry task).
        signal.bump()
        XCTAssertTrue(signal.isActive)
        signal.reset()
        XCTAssertFalse(signal.isActive)
    }

    @MainActor
    func testViewModelBumpsOnlyForContributingReasoningDeltas() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Think about it")
        XCTAssertTrue(didStart)
        XCTAssertFalse(viewModel.reasoningActivity.isActive, "turn start alone must not activate the orb")

        streamClient.emit(.reasoning("Considering the request"))
        XCTAssertTrue(viewModel.reasoningActivity.isActive, "a live reasoning delta must activate the signal")

        // Tool activity is independent of reasoning activity.
        XCTAssertFalse(viewModel.toolActivity.isActive)
    }

    @MainActor
    func testViewModelToolEventsBumpToolActivity() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Run a tool")
        XCTAssertTrue(didStart)
        XCTAssertFalse(viewModel.toolActivity.isActive)

        streamClient.emit(
            .toolStarted(
                ToolStreamEvent(
                    eventType: "tool_started",
                    name: "exec",
                    preview: "ls",
                    args: nil,
                    duration: nil,
                    isError: nil
                )
            )
        )
        XCTAssertTrue(viewModel.toolActivity.isActive, "tool start must activate the tool signal")
    }

    // MARK: - Turn phase model

    @MainActor
    func testTurnPhaseFollowsReasoningToolTextAndDoneTransitions() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        XCTAssertEqual(viewModel.turnPhase, .idle)

        let didStart = await viewModel.sendMessage("Think, then act")
        XCTAssertTrue(didStart)
        XCTAssertEqual(viewModel.turnPhase, .idle, "turn start alone must not enter a phase")

        streamClient.emit(.reasoning("Considering"))
        XCTAssertEqual(viewModel.turnPhase, .reasoning)
        XCTAssertTrue(viewModel.isReasoningPhaseActive)

        let tool = ToolStreamEvent(
            eventType: "tool_started",
            name: "exec",
            preview: "ls",
            args: nil,
            duration: nil,
            isError: nil,
            stableID: "tool-1"
        )
        streamClient.emit(.toolStarted(tool))
        XCTAssertEqual(viewModel.turnPhase, .toolCalling)
        XCTAssertFalse(viewModel.isReasoningPhaseActive, "tool start ends the thinking step")
        XCTAssertTrue(viewModel.isToolPhaseActive)

        // Completing the tool keeps the tool step open — the model composes
        // its next move in silence, and the capsule must not stall out.
        streamClient.emit(
            .toolCompleted(
                ToolStreamEvent(
                    eventType: "tool_completed",
                    name: "exec",
                    preview: "ls",
                    args: nil,
                    duration: 0.2,
                    isError: false,
                    stableID: "tool-1"
                )
            )
        )
        XCTAssertEqual(viewModel.turnPhase, .toolCalling)
        XCTAssertTrue(viewModel.isToolPhaseActive)

        streamClient.emit(.token("The answer"))
        XCTAssertEqual(viewModel.turnPhase, .respondingText)
        XCTAssertFalse(viewModel.isToolPhaseActive)

        streamClient.emit(.done(DoneStreamEvent()))
        XCTAssertEqual(viewModel.turnPhase, .idle, "done must settle every capsule")
    }

    @MainActor
    func testReasoningPhaseHoldsAcrossTokenSilence() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Think hard")
        XCTAssertTrue(didStart)

        streamClient.emit(.reasoning("Step one"))
        XCTAssertEqual(viewModel.turnPhase, .reasoning)

        // 3s of silence — twice the StreamActivitySignal decay window. The
        // micro-liveness signal decays but the semantic phase (which drives
        // the capsule) must hold: the thinking step has not ended.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertFalse(
            viewModel.reasoningActivity.isActive,
            "micro-liveness decays after the silence window (unchanged behavior)"
        )
        XCTAssertEqual(viewModel.turnPhase, .reasoning, "the thinking step is still open")
        XCTAssertTrue(
            viewModel.isReasoningPhaseActive,
            "the capsule keeps animating through intra-step pauses"
        )

        // Resumed reasoning keeps the same phase; the final answer ends it.
        streamClient.emit(.reasoning(" and step two"))
        XCTAssertEqual(viewModel.turnPhase, .reasoning)
        streamClient.emit(.token("Answer"))
        XCTAssertEqual(viewModel.turnPhase, .respondingText)
        XCTAssertFalse(viewModel.isReasoningPhaseActive)
    }

    @MainActor
    func testInterimAssistantEntersReasoningPhase() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Narrate your work")
        XCTAssertTrue(didStart)

        streamClient.emit(
            .interimAssistant(InterimAssistantStreamEvent(text: "Looking at the repo", alreadyStreamed: nil))
        )
        XCTAssertEqual(
            viewModel.turnPhase, .reasoning,
            "interim prose renders in the reasoning block, so it opens the thinking step"
        )
    }

    @MainActor
    func testStreamEndResetsPhaseWithoutDoneEvent() async throws {
        let streamClient = PacingSpySSEStreamingClient()
        let viewModel = try makeActivityViewModel(streamClient: streamClient)

        let didStart = await viewModel.sendMessage("Think")
        XCTAssertTrue(didStart)
        streamClient.emit(.reasoning("Working on it"))
        XCTAssertEqual(viewModel.turnPhase, .reasoning)

        // Errors / cancels route through stream end without a `done` payload.
        streamClient.emit(.streamEnd)
        XCTAssertEqual(viewModel.turnPhase, .idle, "stream end must settle the capsules")
    }

    @MainActor
    private func makeActivityViewModel(
        streamClient: PacingSpySSEStreamingClient
    ) throws -> ChatViewModel {
        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/chat/start":
                return apiTestJSONResponse(
                    #"{"session_id": "session-abc", "stream_id": "stream-123"}"#,
                    for: request
                )
            default:
                return apiTestJSONResponse(
                    #"{"session": {"session_id": "session-abc", "title": "Activity", "messages": []}}"#,
                    for: request
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let server = try XCTUnwrap(URL(string: "https://example.test"))
        let client = APIClient(baseURL: server, session: urlSession)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(
            SessionSummary.self,
            from: Data(
                #"{"session_id": "session-abc", "title": "Activity", "workspace": "/tmp/workspace"}"#.utf8
            )
        )

        return ChatViewModel(
            session: summary,
            server: server,
            client: client,
            streamClient: streamClient,
            approvalStreamClient: PacingSpySSEStreamingClient(),
            clarifyStreamClient: PacingSpySSEStreamingClient()
        )
    }

    @MainActor
    private func waitFor(
        timeoutNanoseconds: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws {
        let pollNanoseconds: UInt64 = 10_000_000
        var elapsed: UInt64 = 0
        while elapsed <= timeoutNanoseconds {
            if condition() { return }
            try await Task.sleep(nanoseconds: pollNanoseconds)
            elapsed += pollNanoseconds
        }
        XCTFail("timed out waiting for condition", file: file, line: line)
    }
}

/// Issue #214: the streaming bottom-follow scroll and active-row growth share
/// one short cadence-synced animation, disabled entirely under Reduce Motion.
final class ChatStreamingMotionTests: XCTestCase {
    func testStreamingFollowUsesShortEaseOut() {
        XCTAssertEqual(
            ChatMotion.streamingFollow(reduceMotion: false),
            .easeOut(duration: 0.15)
        )
    }

    func testStreamingFollowIsDisabledUnderReduceMotion() {
        XCTAssertNil(ChatMotion.streamingFollow(reduceMotion: true))
    }

    func testStreamingFollowIsShorterThanRegularFollowScroll() {
        // The streaming curve must stay snappier than the regular follow scroll
        // so per-flush retargeting keeps up with the word reveal cadence.
        XCTAssertNotEqual(
            ChatMotion.streamingFollow(reduceMotion: false),
            ChatMotion.scrollToLatest(reduceMotion: false)
        )
    }
}

private final class PacingSpySSEStreamingClient: SSEStreamingClient {
    private(set) var lastEventID: String?
    private var onEvent: (@MainActor (SSEEvent) -> Void)?

    func start(url: URL, onEvent: @escaping @MainActor (SSEEvent) -> Void) {
        lastEventID = nil
        self.onEvent = onEvent
    }

    func stop() {}

    @MainActor
    func emit(_ event: SSEEvent) {
        onEvent?(event)
    }
}
