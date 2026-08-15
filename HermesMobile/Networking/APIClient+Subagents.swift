import Foundation

extension APIClient {
    func subagents(parentSessionID: String) async throws -> SubagentSnapshotResponse {
        let data = try await sendData(
            endpoint: .subagents(parentSessionID: parentSessionID),
            method: "GET"
        )
        do {
            return try JSONDecoder().decode(SubagentSnapshotResponse.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }
}
