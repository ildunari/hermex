import SwiftUI
import SwiftData

struct HermexSceneActions {
    let canCreateNewChat: Bool
    let createNewChat: () -> Void
    let searchSessions: () -> Void
}

private struct HermexSceneActionsKey: FocusedValueKey {
    typealias Value = HermexSceneActions
}

extension FocusedValues {
    var hermexSceneActions: HermexSceneActions? {
        get { self[HermexSceneActionsKey.self] }
        set { self[HermexSceneActionsKey.self] = newValue }
    }
}

struct HermexCommands: Commands {
    @FocusedValue(\.hermexSceneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                actions?.createNewChat()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions?.canCreateNewChat != true)
        }

        CommandGroup(after: .newItem) {
            Button("Search Sessions") {
                actions?.searchSessions()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Launch argument hooks for deterministic, server-free visual QA.
            if ProcessInfo.processInfo.arguments.contains("--chat-theme-lab") {
                NavigationStack {
                    ChatThemeLabView()
                }
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            } else if ProcessInfo.processInfo.arguments.contains("--surface-gallery") {
                NavigationStack {
                    SurfaceGalleryView()
                }
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            } else if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack {
                    StreamingLabView()
                }
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            } else {
                ContentView(authManager: authManager)
                    .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
                    .task { await autoConnectIfRequested() }
            }
            #else
            ContentView(authManager: authManager)
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            #endif
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self])
        .commands {
            HermexCommands()
            SidebarCommands()
        }
    }

    #if DEBUG
    /// Connects to a real server from launch arguments, so simulator QA can be
    /// driven against live data without hand-typing credentials into the
    /// onboarding UI.
    ///
    /// `--auto-connect-server <url> --auto-connect-password <password>`
    ///
    /// DEBUG-only and opt-in: absent the arguments this does nothing, so the
    /// normal onboarding path is untouched. Intended for a local/tailnet
    /// server — the password is passed straight to the same `addServer` the
    /// Connect screen calls, and is not persisted anywhere new.
    private func autoConnectIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let urlIndex = arguments.firstIndex(of: "--auto-connect-server"),
              arguments.index(after: urlIndex) < arguments.endIndex
        else { return }
        // Already connected (relaunch against a warm container): don't re-add.
        if case .loggedIn = authManager.state { return }

        let serverURLString = arguments[arguments.index(after: urlIndex)]
        var password = ""
        if let passwordIndex = arguments.firstIndex(of: "--auto-connect-password"),
           arguments.index(after: passwordIndex) < arguments.endIndex {
            password = arguments[arguments.index(after: passwordIndex)]
        }

        let outcome = await authManager.addServer(
            serverURLString: serverURLString,
            password: password
        )
        // Result goes to the log so a scripted run can tell success from an ATS
        // block or a bad credential without screenshotting. Never logs the
        // password itself.
        NSLog("AUTOCONNECT: outcome=\(String(describing: outcome)) error=\(authManager.lastErrorMessage ?? "none")")
    }
    #endif
}
