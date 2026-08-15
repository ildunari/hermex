import CryptoKit
import Foundation
import MetricKit

enum AppDiagnosticsPreference {
    static let isEnabledKey = "appDiagnostics.shareWithServer"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: isEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: isEnabledKey)
    }
}

struct MetricKitDiagnosticCapture: Sendable {
    let json: Data
    let capturedAt: Date
}

enum ClientDiagnosticEnvelopeBuilder {
    struct Result: Sendable {
        let reportID: String
        let data: Data
    }

    static func make(
        capture: MetricKitDiagnosticCapture,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        deviceModel: String = "iPhone"
    ) throws -> Result {
        let payload = try JSONSerialization.jsonObject(with: capture.json)
        guard let payload = payload as? [String: Any] else {
            throw ClientDiagnosticEnvelopeError.payloadIsNotObject
        }

        let digest = SHA256.hash(data: capture.json)
        let reportID = "mx_" + digest.map { String(format: "%02x", $0) }.joined()
        let envelope: [String: Any] = [
            "version": 1,
            "report_id": reportID,
            "kind": "metrickit",
            "captured_at": ISO8601DateFormatter().string(from: capture.capturedAt),
            "platform": "iOS",
            "os_version": processInfo.operatingSystemVersionString,
            "device_model": deviceModel,
            "app": [
                "bundle_id": bundle.bundleIdentifier ?? "unknown",
                "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            ],
            "payload": payload
        ]
        return Result(
            reportID: reportID,
            data: try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        )
    }
}

enum ClientDiagnosticEnvelopeError: Error {
    case payloadIsNotObject
}

actor AppDiagnosticsQueue {
    typealias Uploader = @Sendable (_ report: Data, _ server: URL) async throws -> Void

    static let maxPendingReports = 20
    static let maxReportBytes = 2 * 1024 * 1024

    private let directory: URL
    private let uploader: Uploader

    init(
        directory: URL = AppDiagnosticsQueue.defaultDirectory(),
        uploader: @escaping Uploader = { report, server in
            try await APIClient(baseURL: server).uploadClientDiagnostic(report)
        }
    ) {
        self.directory = directory
        self.uploader = uploader
    }

    func enqueue(_ capture: MetricKitDiagnosticCapture) {
        guard AppDiagnosticsPreference.isEnabled else { return }
        do {
            let report = try ClientDiagnosticEnvelopeBuilder.make(capture: capture)
            guard report.data.count <= Self.maxReportBytes else { return }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let url = directory.appending(path: "\(report.reportID).json")
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            try report.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            prune()
        } catch {
            // Diagnostics are strictly best-effort and must never destabilize launch.
        }
    }

    func flush(to server: URL) async {
        guard AppDiagnosticsPreference.isEnabled else { return }
        for url in pendingReportURLs() {
            guard !Task.isCancelled else { return }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try await uploader(data, server)
                try? FileManager.default.removeItem(at: url)
            } catch {
                // Preserve the report for the next foreground/connect attempt.
                return
            }
        }
    }

    func pendingCount() -> Int {
        pendingReportURLs().count
    }

    private func pendingReportURLs() -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
                return lhs < rhs
            }
    }

    private func prune() {
        let urls = pendingReportURLs()
        guard urls.count > Self.maxPendingReports else { return }
        for url in urls.prefix(urls.count - Self.maxPendingReports) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static func defaultDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appending(path: "HermexDiagnostics", directoryHint: .isDirectory)
    }
}

private final class MetricKitDiagnosticSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    let onPayloads: @Sendable ([MetricKitDiagnosticCapture]) -> Void

    init(onPayloads: @escaping @Sendable ([MetricKitDiagnosticCapture]) -> Void) {
        self.onPayloads = onPayloads
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        onPayloads(payloads.map {
            MetricKitDiagnosticCapture(json: $0.jsonRepresentation(), capturedAt: $0.timeStampEnd)
        })
    }
}

final class AppDiagnosticsReporter: @unchecked Sendable {
    static let shared = AppDiagnosticsReporter()

    private let queue: AppDiagnosticsQueue
    private let subscriber: MetricKitDiagnosticSubscriber
    private let lock = NSLock()
    private var started = false
    private var initialCaptureTask: Task<Void, Never>?

    init(queue: AppDiagnosticsQueue = AppDiagnosticsQueue()) {
        self.queue = queue
        self.subscriber = MetricKitDiagnosticSubscriber { captures in
            Task {
                for capture in captures {
                    await queue.enqueue(capture)
                }
            }
        }
    }

    func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        MXMetricManager.shared.add(subscriber)
        capturePastDiagnostics()
    }

    func capturePastDiagnostics() {
        let captures = MXMetricManager.shared.pastDiagnosticPayloads.map {
            MetricKitDiagnosticCapture(json: $0.jsonRepresentation(), capturedAt: $0.timeStampEnd)
        }
        let previousTask = initialCaptureTaskSnapshot()
        let task = Task {
            await previousTask?.value
            for capture in captures {
                await queue.enqueue(capture)
            }
        }
        lock.lock()
        initialCaptureTask = task
        lock.unlock()
    }

    func uploadPending(to server: URL) async {
        let initialTask = initialCaptureTaskSnapshot()
        await initialTask?.value
        await queue.flush(to: server)
    }

    private func initialCaptureTaskSnapshot() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return initialCaptureTask
    }
}

extension APIClient {
    func uploadClientDiagnostic(_ report: Data) async throws {
        _ = try await sendData(
            endpoint: .clientDiagnostics,
            method: "POST",
            encodedBody: report,
            timeout: 15
        )
    }
}
