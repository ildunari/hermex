import Foundation
import Testing
@testable import HermesMobile

@Suite("App diagnostics", .serialized)
struct AppDiagnosticsReporterTests {
    @Test("MetricKit envelopes are deterministic and contain only diagnostic metadata")
    func envelopeIsDeterministic() throws {
        let raw = Data(#"{"crashDiagnostics":[{"signal":11}]}"#.utf8)
        let capture = MetricKitDiagnosticCapture(
            json: raw,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let first = try ClientDiagnosticEnvelopeBuilder.make(
            capture: capture,
            deviceModel: "iPhone"
        )
        let second = try ClientDiagnosticEnvelopeBuilder.make(
            capture: capture,
            deviceModel: "iPhone"
        )
        let body = try #require(JSONSerialization.jsonObject(with: first.data) as? [String: Any])

        #expect(first.reportID == second.reportID)
        #expect(first.reportID.hasPrefix("mx_"))
        #expect(body["kind"] as? String == "metrickit")
        #expect(body["payload"] is [String: Any])
        #expect(body["headers"] == nil)
        #expect(body["chat_content"] == nil)
    }

    @Test("Queue deduplicates reports and deletes only after upload succeeds")
    func queueDeduplicatesAndFlushes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        let recorder = UploadRecorder()
        let queue = AppDiagnosticsQueue(directory: directory) { data, server in
            await recorder.record(data: data, server: server)
        }
        let capture = MetricKitDiagnosticCapture(
            json: Data(#"{"hangDiagnostics":[{"duration":5}]}"#.utf8),
            capturedAt: .now
        )

        await queue.enqueue(capture)
        await queue.enqueue(capture)
        let pendingBefore = await queue.pendingCount()
        #expect(pendingBefore == 1)

        let server = try #require(URL(string: "https://hermes.example"))
        await queue.flush(to: server)

        let pendingAfter = await queue.pendingCount()
        let uploads = await recorder.uploads
        #expect(pendingAfter == 0)
        #expect(uploads.count == 1)
        #expect(uploads[0].server == server)
    }

    @Test("Failed uploads remain queued for a later foreground retry")
    func failedUploadRemainsQueued() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in
            throw StubUploadError.offline
        }
        await queue.enqueue(MetricKitDiagnosticCapture(
            json: Data(#"{"crashDiagnostics":[{}]}"#.utf8),
            capturedAt: .now
        ))

        let server = try #require(URL(string: "https://hermes.example"))
        await queue.flush(to: server)

        let pending = await queue.pendingCount()
        #expect(pending == 1)
    }

    @Test("Permanent rejection drops only the poison report and continues")
    func permanentRejectionDoesNotBlockLaterReports() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        let recorder = RejectFirstUploadRecorder()
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in
            if await recorder.nextAttemptShouldFail() {
                throw APIError.http(statusCode: 400, body: nil)
            }
        }
        for index in 0..<2 {
            await queue.enqueue(MetricKitDiagnosticCapture(
                json: Data("{\"crashDiagnostics\":[{\"index\":\(index)}]}".utf8),
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }

        let server = try #require(URL(string: "https://hermes.example"))
        await queue.flush(to: server)

        #expect(await recorder.attempts == 2)
        #expect(await queue.pendingCount() == 0)
    }

    @Test("Queue is bounded and disabled collection does not persist")
    func queueIsBoundedAndHonorsPreference() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in }

        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        await queue.enqueue(MetricKitDiagnosticCapture(
            json: Data(#"{"crashDiagnostics":[{"index":-1}]}"#.utf8),
            capturedAt: .now
        ))
        let disabledCount = await queue.pendingCount()
        #expect(disabledCount == 0)

        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        for index in 0..<(AppDiagnosticsQueue.maxPendingReports + 3) {
            await queue.enqueue(MetricKitDiagnosticCapture(
                json: Data("{\"crashDiagnostics\":[{\"index\":\(index)}]}".utf8),
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        let boundedCount = await queue.pendingCount()
        #expect(boundedCount == AppDiagnosticsQueue.maxPendingReports)
    }

    @Test("Opting out cancels upload and purges every queued report")
    func optOutCancelsAndPurges() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        defer {
            UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
            UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        }
        let recorder = CancellableUploadRecorder()
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in
            await recorder.markStarted()
            try await Task.sleep(for: .seconds(30))
            await recorder.markCompleted()
        }
        for index in 0..<2 {
            await queue.enqueue(MetricKitDiagnosticCapture(
                json: Data("{\"crashDiagnostics\":[{\"index\":\(index)}]}".utf8),
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        let reporter = AppDiagnosticsReporter(queue: queue)
        let server = try #require(URL(string: "https://hermes.example"))
        let upload = Task { await reporter.uploadPending(to: server) }

        while !(await recorder.started) {
            try await Task.sleep(for: .milliseconds(10))
        }
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.isEnabledKey)
        reporter.sharingPreferenceDidChange(isEnabled: false)
        await upload.value
        while (await queue.pendingCount()) != 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(await recorder.completed == 0)
        #expect(await queue.pendingCount() == 0)

        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        reporter.sharingPreferenceDidChange(isEnabled: true)
        await reporter.uploadPending(to: server)
        #expect(await recorder.completed == 0)
        #expect(await queue.pendingCount() == 0)
    }

    @Test("Failed purge keeps sharing disabled and the consent marker durable")
    func failedPurgeFailsClosed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        defer {
            UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
            UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        }
        let recorder = UploadRecorder()
        let queue = AppDiagnosticsQueue(
            directory: directory,
            remover: { _ in throw StubUploadError.cannotDelete }
        ) { data, server in
            await recorder.record(data: data, server: server)
        }
        await queue.enqueue(MetricKitDiagnosticCapture(
            json: Data(#"{"crashDiagnostics":[{}]}"#.utf8),
            capturedAt: .now
        ))

        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.needsPurgeKey)
        let didApply = await queue.applySharingPreference(true, generation: 1)
        let server = try #require(URL(string: "https://hermes.example"))
        await queue.flush(to: server)

        #expect(didApply == false)
        #expect(AppDiagnosticsPreference.needsPurge)
        #expect(await queue.pendingCount() == 1)
        #expect(await recorder.uploads.isEmpty)
    }

    @Test("Stale capture generation cannot cross a rapid disable and re-enable")
    func staleCaptureGenerationIsRejected() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in }
        let staleCapture = MetricKitDiagnosticCapture(
            json: Data(#"{"crashDiagnostics":[{"generation":0}]}"#.utf8),
            capturedAt: .now
        )
        let currentCapture = MetricKitDiagnosticCapture(
            json: Data(#"{"crashDiagnostics":[{"generation":2}]}"#.utf8),
            capturedAt: .now
        )

        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.isEnabledKey)
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.needsPurgeKey)
        _ = await queue.applySharingPreference(false, generation: 1)
        UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.isEnabledKey)
        _ = await queue.applySharingPreference(true, generation: 2)
        await queue.enqueue(staleCapture, consentGeneration: 0)
        await queue.enqueue(currentCapture, consentGeneration: 2)

        #expect(await queue.pendingCount() == 1)
    }

    @Test("Client diagnostics endpoint uses the authenticated WebUI route")
    func endpoint() {
        #expect(Endpoint.clientDiagnostics.path == "/api/client-diagnostics")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "HermexDiagnosticsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private actor UploadRecorder {
    struct Upload: Sendable {
        let data: Data
        let server: URL
    }

    private(set) var uploads: [Upload] = []

    func record(data: Data, server: URL) {
        uploads.append(Upload(data: data, server: server))
    }
}

private actor CancellableUploadRecorder {
    private(set) var started = false
    private(set) var completed = 0

    func markStarted() {
        started = true
    }

    func markCompleted() {
        completed += 1
    }
}

private actor RejectFirstUploadRecorder {
    private(set) var attempts = 0

    func nextAttemptShouldFail() -> Bool {
        attempts += 1
        return attempts == 1
    }
}

private enum StubUploadError: Error {
    case offline
    case cannotDelete
}
