import CryptoKit
import Foundation
import MetricKit

enum AppDiagnosticsPreference {
    static let isEnabledKey = "appDiagnostics.shareWithServer"
    static let needsPurgeKey = "appDiagnostics.needsConsentPurge"

    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: isEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    static var needsPurge: Bool {
        UserDefaults.standard.bool(forKey: needsPurgeKey)
    }
}

struct MetricKitDiagnosticCapture: Sendable {
    let json: Data
    let capturedAt: Date
}

private final class DiagnosticsConsentState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func tokenIfEnabled() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return enabled ? generation : nil
    }

    func currentGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    func update(isEnabled: Bool) -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        enabled = isEnabled
        return generation
    }
}

private actor DiagnosticsUploadStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
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
    typealias Remover = @Sendable (_ reportURL: URL) throws -> Void

    static let maxPendingReports = 20
    static let maxReportBytes = 2 * 1024 * 1024

    private let directory: URL
    private let uploader: Uploader
    private let remover: Remover
    private var sharingEnabled: Bool
    private var consentGeneration = 0

    init(
        directory: URL = AppDiagnosticsQueue.defaultDirectory(),
        sharingEnabled: Bool = AppDiagnosticsPreference.isEnabled,
        remover: @escaping Remover = { try FileManager.default.removeItem(at: $0) },
        uploader: @escaping Uploader = { report, server in
            try await APIClient(baseURL: server).uploadClientDiagnostic(report)
        }
    ) {
        self.directory = directory
        self.sharingEnabled = sharingEnabled
        self.remover = remover
        self.uploader = uploader
    }

    func enqueue(_ capture: MetricKitDiagnosticCapture, consentGeneration: Int? = nil) {
        guard sharingEnabled,
              AppDiagnosticsPreference.isEnabled,
              !AppDiagnosticsPreference.needsPurge,
              consentGeneration == nil || consentGeneration == self.consentGeneration else { return }
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

    func flush(to server: URL, consentGeneration: Int? = nil) async {
        guard sharingEnabled,
              AppDiagnosticsPreference.isEnabled,
              !AppDiagnosticsPreference.needsPurge,
              consentGeneration == nil || consentGeneration == self.consentGeneration else { return }
        for url in pendingReportURLs() {
            guard sharingEnabled,
                  AppDiagnosticsPreference.isEnabled,
                  !AppDiagnosticsPreference.needsPurge,
                  consentGeneration == nil || consentGeneration == self.consentGeneration,
                  !Task.isCancelled else { return }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try await uploader(data, server)
                guard sharingEnabled,
                      AppDiagnosticsPreference.isEnabled,
                      !AppDiagnosticsPreference.needsPurge,
                      consentGeneration == nil || consentGeneration == self.consentGeneration,
                      !Task.isCancelled else { return }
                try? remover(url)
            } catch APIError.http(let statusCode, _) where statusCode == 400 || statusCode == 413 {
                // This exact envelope can never succeed unchanged. Drop only
                // permanent validation/size failures so one poison report does
                // not block every newer crash; retain auth, compatibility,
                // throttling, network, and server failures for retry.
                try? remover(url)
                continue
            } catch {
                // Preserve the report for the next foreground/connect attempt.
                return
            }
        }
    }

    @discardableResult
    func removeAll() -> Bool {
        var removedEverything = true
        for url in pendingReportURLs() {
            do {
                try remover(url)
            } catch {
                removedEverything = false
            }
        }
        return removedEverything && pendingReportURLs().isEmpty
    }

    @discardableResult
    func applySharingPreference(_ isEnabled: Bool, generation: Int) -> Bool {
        // Disable first, then purge, then optionally allow future callbacks.
        // This actor operation has no suspension point, so enqueue/flush cannot
        // slip through the consent boundary while files are being removed.
        guard generation >= consentGeneration else { return false }
        consentGeneration = generation
        sharingEnabled = false
        guard removeAll() else {
            UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.needsPurgeKey)
            return false
        }
        sharingEnabled = isEnabled
        if isEnabled {
            UserDefaults.standard.set(false, forKey: AppDiagnosticsPreference.needsPurgeKey)
        }
        return true
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
            try? remover(url)
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
    private let consentState: DiagnosticsConsentState
    private let subscriber: MetricKitDiagnosticSubscriber
    private let lock = NSLock()
    private var started = false
    private var initialCaptureTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var uploadGeneration = 0

    init(queue: AppDiagnosticsQueue = AppDiagnosticsQueue()) {
        let consentState = DiagnosticsConsentState(enabled: AppDiagnosticsPreference.isEnabled)
        self.queue = queue
        self.consentState = consentState
        self.subscriber = MetricKitDiagnosticSubscriber { captures in
            guard AppDiagnosticsPreference.isEnabled,
                  !AppDiagnosticsPreference.needsPurge,
                  let generation = consentState.tokenIfEnabled() else { return }
            Task {
                for capture in captures {
                    guard !Task.isCancelled else { return }
                    await queue.enqueue(capture, consentGeneration: generation)
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
        if AppDiagnosticsPreference.isEnabled, !AppDiagnosticsPreference.needsPurge {
            capturePastDiagnostics()
        } else {
            scheduleConsentTransition(
                isEnabled: AppDiagnosticsPreference.isEnabled,
                generation: consentState.currentGeneration()
            )
        }
    }

    func capturePastDiagnostics() {
        guard let generation = consentState.tokenIfEnabled(),
              !AppDiagnosticsPreference.needsPurge else { return }
        let captures = MXMetricManager.shared.pastDiagnosticPayloads.map {
            MetricKitDiagnosticCapture(json: $0.jsonRepresentation(), capturedAt: $0.timeStampEnd)
        }
        let previousTask = initialCaptureTaskSnapshot()
        let task = Task {
            await previousTask?.value
            for capture in captures {
                guard !Task.isCancelled else { return }
                await queue.enqueue(capture, consentGeneration: generation)
            }
        }
        lock.lock()
        initialCaptureTask = task
        lock.unlock()
    }

    func uploadPending(to server: URL) async {
        let consentTask = consentTaskSnapshot()
        await consentTask?.value
        let initialTask = initialCaptureTaskSnapshot()
        await initialTask?.value
        guard AppDiagnosticsPreference.isEnabled,
              !Task.isCancelled,
              let consentGeneration = consentState.tokenIfEnabled() else { return }

        let (task, gate, generation) = prepareUploadTask(
            to: server,
            consentGeneration: consentGeneration
        )
        await gate.open()
        await task.value
        clearUploadTask(ifGeneration: generation)
    }

    /// Applies the user's consent boundary immediately. Disabling cancels the
    /// active request and purges queued payloads. Re-enabling intentionally
    /// does not replay `pastDiagnosticPayloads`, which may cover the disabled
    /// interval; only future MetricKit callbacks are eligible.
    func sharingPreferenceDidChange(isEnabled: Bool) {
        if !isEnabled {
            // Persist this synchronously. If the process terminates before the
            // actor purge runs, the next launch/re-enable must purge before it
            // captures or uploads anything.
            UserDefaults.standard.set(true, forKey: AppDiagnosticsPreference.needsPurgeKey)
        }
        let generation = consentState.update(isEnabled: isEnabled)
        lock.lock()
        uploadGeneration += 1
        uploadTask?.cancel()
        uploadTask = nil
        initialCaptureTask?.cancel()
        lock.unlock()
        scheduleConsentTransition(isEnabled: isEnabled, generation: generation)
    }

    private func initialCaptureTaskSnapshot() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return initialCaptureTask
    }

    private var consentTask: Task<Void, Never>?

    private func consentTaskSnapshot() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return consentTask
    }

    private func scheduleConsentTransition(isEnabled: Bool, generation: Int) {
        lock.lock()
        let previous = consentTask
        let task = Task { [queue] in
            await previous?.value
            await queue.applySharingPreference(isEnabled, generation: generation)
        }
        consentTask = task
        lock.unlock()
    }

    private func prepareUploadTask(
        to server: URL,
        consentGeneration: Int
    ) -> (Task<Void, Never>, DiagnosticsUploadStartGate, Int) {
        lock.lock()
        defer { lock.unlock() }
        uploadTask?.cancel()
        uploadGeneration += 1
        let gate = DiagnosticsUploadStartGate()
        let task = Task { [queue] in
            await gate.wait()
            guard !Task.isCancelled else { return }
            await queue.flush(to: server, consentGeneration: consentGeneration)
        }
        uploadTask = task
        return (task, gate, uploadGeneration)
    }

    private func clearUploadTask(ifGeneration generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        if uploadGeneration == generation {
            uploadTask = nil
        }
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
