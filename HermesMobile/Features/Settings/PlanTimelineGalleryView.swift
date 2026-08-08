#if DEBUG
import SwiftUI

/// Debug gallery for the plan surface (`--surface-gallery-page 11`), plus an
/// auto-toggling motion lab (`page 12`) that drives the expand/collapse cycle
/// on a timer so a screen recording captures the same reveal every run.
struct PlanTimelineGalleryView: View {
    var page: Int = 11

    var body: some View {
        if page == 12 {
            PlanMotionLabView()
        } else {
            states
        }
    }

    private var states: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                specimen(
                    "COLLAPSED · IN PROGRESS",
                    "Default state. Ring fills as steps resolve.",
                    state: Self.midRun,
                    expanded: false
                )

                specimen(
                    "EXPANDED · IN PROGRESS",
                    "Two done, one running, two pending.",
                    state: Self.midRun,
                    expanded: true
                )

                specimen(
                    "EXPANDED · ALL COMPLETE",
                    "Pill swaps the ring for a check.",
                    state: Self.finished,
                    expanded: true
                )

                specimen(
                    "EXPANDED · WITH CANCELLED",
                    "Cancelled reads as resolved-but-not-done.",
                    state: Self.withCancelled,
                    expanded: true
                )

                specimen(
                    "EXPANDED · WRAPPED ROW",
                    "Long step wraps; sweep stands down, dimming carries it.",
                    state: Self.wrapped,
                    expanded: true
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func specimen(
        _ title: String,
        _ subtitle: String,
        state: TodoState,
        expanded: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            PlanTimelineView(state: state, isExpanded: .constant(expanded))
        }
    }

    // MARK: - Fixtures

    static let midRun = TodoState(todos: [
        TodoItem(rawID: "1", content: "Review the project requirements", status: .completed),
        TodoItem(rawID: "2", content: "Sketch the initial approach", status: .completed),
        TodoItem(rawID: "3", content: "Build the first draft", status: .inProgress),
        TodoItem(rawID: "4", content: "Test the main workflow", status: .pending),
        TodoItem(rawID: "5", content: "Polish and deliver the result", status: .pending)
    ])

    static let finished = TodoState(todos: [
        TodoItem(rawID: "1", content: "Review the project requirements", status: .completed),
        TodoItem(rawID: "2", content: "Sketch the initial approach", status: .completed),
        TodoItem(rawID: "3", content: "Build the first draft", status: .completed),
        TodoItem(rawID: "4", content: "Test the main workflow", status: .completed),
        TodoItem(rawID: "5", content: "Polish and deliver the result", status: .completed)
    ])

    static let withCancelled = TodoState(todos: [
        TodoItem(rawID: "1", content: "Audit the palette tokens", status: .completed),
        TodoItem(rawID: "2", content: "Migrate the legacy renderer", status: .cancelled),
        TodoItem(rawID: "3", content: "Wire the settings toggle", status: .inProgress),
        TodoItem(rawID: "4", content: "Capture before/after renders", status: .pending)
    ])

    static let wrapped = TodoState(todos: [
        TodoItem(rawID: "1", content: "Trace the todo_state contract through streaming and cold load so the panel never disagrees with the agent", status: .completed),
        TodoItem(rawID: "2", content: "Reconcile snapshots by timestamp", status: .inProgress)
    ])
}

/// Drives the plan card open and closed on a fixed cadence, and advances the
/// steps, so a screen recording captures the reveal and the per-row status
/// changes deterministically.
private struct PlanMotionLabView: View {
    @State private var isExpanded = true
    @State private var completedCount = 1

    private let steps = [
        "Review the project requirements",
        "Sketch the initial approach",
        "Build the first draft",
        "Test the main workflow",
        "Polish and deliver the result"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("PLAN · MOTION LAB")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer()

            PlanTimelineView(state: state, isExpanded: $isExpanded)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
        }
        .task {
            // Advance a step, then toggle, on a loop. Slow enough that each
            // phase of the reveal is legible frame by frame in the recording.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation { completedCount = (completedCount % steps.count) + 1 }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(ChatMotion.cardExpand(reduceMotion: false)) { isExpanded.toggle() }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(ChatMotion.cardExpand(reduceMotion: false)) { isExpanded.toggle() }
            }
        }
    }

    private var state: TodoState {
        TodoState(todos: steps.enumerated().map { index, content in
            let status: TodoItem.Status
            if index < completedCount {
                status = .completed
            } else if index == completedCount {
                status = .inProgress
            } else {
                status = .pending
            }
            return TodoItem(rawID: "\(index)", content: content, status: status)
        })
    }
}
#endif
