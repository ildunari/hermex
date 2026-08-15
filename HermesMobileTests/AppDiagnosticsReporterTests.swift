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

    @Test("Queue is bounded and disabled collection does not persist")
    func queueIsBoundedAndHonorsPreference() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = AppDiagnosticsQueue(directory: directory) { _, _ in }

        UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.isEnabledKey)
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

private enum StubUploadError: Error {
    case offline
}
