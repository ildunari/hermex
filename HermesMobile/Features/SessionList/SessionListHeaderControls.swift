import SwiftUI

/// Bell + sort controls that sit to the right of the "Sessions" heading.
///
/// The bell reflects server-reported pending approval/clarify work and only
/// pulses for blocking approvals. The sort button opens the group/order/filter
/// menu and paints itself "engaged" whenever the view differs from the default.
struct SessionListHeaderControls: View {
    let attentionCount: Int
    let hasBlockingAttention: Bool
    let preferences: SessionSortPreferences
    let onTapBell: () -> Void
    let onUpdatePreferences: (SessionSortPreferences) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 14) {
            bellButton
            sortMenu
        }
    }

    // MARK: - Bell (mockup A)

    private var bellButton: some View {
        Button(action: onTapBell) {
            Image(systemName: attentionCount > 0 ? "bell.fill" : "bell")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(attentionCount > 0 ? Color.accentColor : Color.primary)
                .overlay(alignment: .topTrailing) {
                    if attentionCount > 0 {
                        badge
                            .alignmentGuide(.top) { $0[.top] + 3 }
                            .alignmentGuide(.trailing) { $0[.trailing] - 4 }
                    }
                }
                .scaleEffect(shouldPulse && isPulsing ? 1.08 : 1)
                .animation(
                    shouldPulse
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(attentionCount == 0)
        .opacity(attentionCount == 0 ? 0.55 : 1)
        .onAppear { isPulsing = shouldPulse }
        .onChange(of: shouldPulse) { _, newValue in isPulsing = newValue }
        .accessibilityIdentifier("sessionList.attentionBell")
        .accessibilityLabel(bellAccessibilityLabel)
    }

    /// Only blocking approvals animate. Clarify prompts and Reduce Motion get a
    /// static badge so the header does not twitch continuously.
    private var shouldPulse: Bool {
        attentionCount > 0 && hasBlockingAttention && !reduceMotion
    }

    private var badge: some View {
        Text(attentionCount > 9 ? "9+" : "\(attentionCount)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, attentionCount > 9 ? 4 : 0)
            .frame(minWidth: 15, minHeight: 15)
            .background(Circle().fill(Color.accentColor))
            .overlay(
                Circle().stroke(Color(.systemBackground), lineWidth: 1.5)
            )
            .offset(x: 6, y: -5)
    }

    private var bellAccessibilityLabel: Text {
        if attentionCount == 0 {
            Text("No sessions need attention")
        } else {
            Text("\(attentionCount) sessions need attention")
        }
    }

    // MARK: - Sort menu (mockup C)

    private var sortMenu: some View {
        Menu {
            Section("Group by") {
                ForEach(SessionGrouping.allCases) { grouping in
                    Button {
                        var updated = preferences
                        updated.grouping = grouping
                        onUpdatePreferences(updated)
                    } label: {
                        if preferences.grouping == grouping {
                            Label(grouping.title, systemImage: "checkmark")
                        } else {
                            Text(grouping.title)
                        }
                    }
                }
            }

            Section("Sort by") {
                ForEach(SessionOrdering.allCases) { ordering in
                    Button {
                        var updated = preferences
                        updated.ordering = ordering
                        onUpdatePreferences(updated)
                    } label: {
                        if preferences.ordering == ordering {
                            Label(ordering.title, systemImage: "checkmark")
                        } else {
                            Text(ordering.title)
                        }
                    }
                }
            }

            Section("Filter") {
                ForEach(SessionStatusFilter.allCases) { filter in
                    // Unread has no server field yet; keep the engine but hide
                    // the menu item so tapping it cannot empty the list.
                    if filter != .unread {
                        Button {
                            var updated = preferences
                            if updated.activeFilters.contains(filter) {
                                updated.activeFilters.remove(filter)
                            } else {
                                updated.activeFilters.insert(filter)
                            }
                            onUpdatePreferences(updated)
                        } label: {
                            if preferences.activeFilters.contains(filter) {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                }
                Button {
                    var updated = preferences
                    updated.includesArchived.toggle()
                    onUpdatePreferences(updated)
                } label: {
                    if preferences.includesArchived {
                        Label(String(localized: "Archived"), systemImage: "checkmark")
                    } else {
                        Text("Archived")
                    }
                }
            }

            if preferences.isModified {
                Section {
                    Button(role: .destructive) {
                        onUpdatePreferences(.default)
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(preferences.isModified ? Color.accentColor : Color.primary)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("sessionList.sortMenu")
        .accessibilityLabel("Sort and filter sessions")
    }
}
