#if DEBUG
import SwiftUI

/// Debug-only gallery of the surfaces touched by the palette work, rendered
/// with fixture data so they can be inspected without a server. Reachable via
/// the `--surface-gallery` launch argument.
///
/// Each section deliberately composes the same primitives the production
/// screens use, so a screenshot of this gallery reflects real surface colors
/// rather than a mock-up.
struct SurfaceGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Settings card") {
                    galleryCard(title: "Appearance") {
                        galleryRow(icon: "circle.lefthalf.filled", title: "Theme", value: "System")
                        galleryDivider()
                        galleryRow(icon: "paintpalette", title: "Chat Palette", value: "Warm")
                        galleryDivider()
                        galleryRow(icon: "textformat", title: "Serif Responses", value: "Off")
                    }
                }

                section("Session row") {
                    VStack(spacing: 0) {
                        sessionRow(title: "Chat theme v2", subtitle: "12 messages · 2h ago")
                        sessionRow(title: "Palette consistency sweep", subtitle: "48 messages · now")
                    }
                    .background(galleryPalette.chatBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                section("File browser rows") {
                    VStack(spacing: 0) {
                        fileRow(name: "HermesMobile", isDirectory: true)
                        fileRow(name: "ChatPalette.swift", isDirectory: false)
                    }
                    .padding(.vertical, 4)
                    .background(galleryPalette.chatBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                section("Diff rows") {
                    VStack(spacing: 0) {
                        diffRow(gutter: "42", text: "  let palette = ChatPalette(", kind: .context)
                        diffRow(gutter: "43", text: "+     temperature: .warm", kind: .addition)
                        diffRow(gutter: "44", text: "-     Color(.secondarySystemBackground)", kind: .deletion)
                        diffRow(gutter: "45", text: "  )", kind: .context)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                section("Inset chips & cards") {
                    HStack(spacing: 10) {
                        chip("Sonnet 4.5")
                        chip("Coding")
                        chip("main")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("File changes")
                            .font(AppFont.caption(weight: .semibold))
                        Text("3 files · +48 −12")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurfaceBackground(.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(galleryPalette.chatBackground)
        .navigationTitle("Surface Gallery")
        .navigationBarTitleDisplayMode(.inline)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var galleryPalette: ChatPalette {
        ChatPalette.appChrome(colorScheme: colorScheme)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(AppFont.caption2(weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func galleryCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurfaceBackground(.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func galleryRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(AppFont.subheadline())
    }

    private func galleryDivider() -> some View {
        Rectangle()
            .fill(galleryPalette.tableRule)
            .frame(height: 0.5)
    }

    private func sessionRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheadline(weight: .semibold))
                Text(subtitle).font(AppFont.caption()).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fileRow(name: String, isDirectory: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDirectory ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(isDirectory ? galleryPalette.surfaceInset : galleryPalette.surface)
                )
            Text(name).font(AppFont.subheadline())
            Spacer()
            if isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private enum GalleryDiffKind {
        case addition, deletion, context
    }

    private func diffRow(gutter: String, text: String, kind: GalleryDiffKind) -> some View {
        let rowFill: Color = {
            switch kind {
            case .addition: Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.16)
            case .deletion: Color(red: 0.95, green: 0.25, blue: 0.25).opacity(0.16)
            case .context: galleryPalette.codeSlab
            }
        }()
        let gutterFill: Color = {
            switch kind {
            case .addition: Color(red: 0.20, green: 0.68, blue: 0.32).opacity(0.24)
            case .deletion: Color(red: 0.86, green: 0.20, blue: 0.20).opacity(0.24)
            case .context: galleryPalette.surface
            }
        }()

        return HStack(spacing: 0) {
            Text(gutter)
                .font(AppFont.mono(style: .caption))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)
                .background(gutterFill)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(kind == .context ? .secondary : .primary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 19)
        .background(rowFill)
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(AppFont.caption(weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .appSurfaceBackground(.inset, opacity: 0.5, in: Capsule())
    }
}
#endif
