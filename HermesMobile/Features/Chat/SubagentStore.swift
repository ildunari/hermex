import Foundation
import Observation

@MainActor
@Observable
final class SubagentStore {
    private static let maximumRetainedChildren = 64
    private(set) var parentSessionID: String?
    private(set) var cursor: String?
    private(set) var children: [SubagentRun] = []
    private(set) var isSupported = true

    private var recordsByID: [String: SubagentRun] = [:]
    private var orderedIDs: [String] = []
    private var generation = 0

    var hasActiveChildren: Bool { children.contains { $0.lifecycle.isActive } }
    var failedCount: Int { children.count { $0.lifecycle.isFailure } }

    func reset(parentSessionID: String?) {
        generation += 1
        self.parentSessionID = parentSessionID
        cursor = nil
        children = []
        recordsByID = [:]
        orderedIDs = []
        isSupported = true
    }

    func loadSnapshot(client: APIClient, parentSessionID: String) async {
        if self.parentSessionID != parentSessionID {
            reset(parentSessionID: parentSessionID)
        }
        let loadGeneration = generation

        do {
            let snapshot = try await client.subagents(parentSessionID: parentSessionID)
            guard !Task.isCancelled,
                  loadGeneration == generation,
                  self.parentSessionID == parentSessionID else { return }
            replace(with: snapshot, expectedParentSessionID: parentSessionID)
        } catch APIError.http(let statusCode, _) where statusCode == 404 || statusCode == 405 {
            guard loadGeneration == generation else { return }
            isSupported = false
            children = []
            recordsByID = [:]
            orderedIDs = []
        } catch {
            // This surface is observational. A transient failure must not make
            // the transcript fail or create a reconnect loop; the next chat
            // stream upsert or appearance snapshot will reconcile it.
        }
    }

    func replace(with snapshot: SubagentSnapshotResponse, expectedParentSessionID: String) {
        guard snapshot.parentSessionID == nil || snapshot.parentSessionID == expectedParentSessionID,
              parentSessionID == expectedParentSessionID else { return }

        cursor = snapshot.cursor
        recordsByID.removeAll(keepingCapacity: true)
        orderedIDs.removeAll(keepingCapacity: true)
        for child in snapshot.children ?? [] {
            apply(child, expectedParentSessionID: expectedParentSessionID)
        }
        publish()
    }

    func apply(_ incoming: SubagentRun, expectedParentSessionID: String) {
        guard parentSessionID == expectedParentSessionID,
              incoming.parentSessionID == nil || incoming.parentSessionID == expectedParentSessionID else { return }

        let key = incoming.id
        if let existing = recordsByID[key] {
            if let existingSequence = existing.sequence,
               let incomingSequence = incoming.sequence,
               incomingSequence <= existingSequence {
                return
            }
            if existing.lifecycle.isTerminal, !incoming.lifecycle.isTerminal {
                return
            }
        } else {
            orderedIDs.append(key)
            if orderedIDs.count > Self.maximumRetainedChildren {
                let expiredID = orderedIDs.removeFirst()
                recordsByID.removeValue(forKey: expiredID)
            }
        }

        recordsByID[key] = incoming
        publish()
    }

    private func publish() {
        children = orderedIDs.compactMap { recordsByID[$0] }
    }
}
