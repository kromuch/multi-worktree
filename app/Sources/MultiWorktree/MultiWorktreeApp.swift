import SwiftUI
import AppKit
import MWTKit

@main
struct MultiWorktreeApp: App {
    private static let isPreview = ProcessInfo.processInfo.environment["MWT_PREVIEW"] == "1"
    @State private var model = AppModel(checksDependencies: !MultiWorktreeApp.isPreview,
                                        checksForUpdates: !MultiWorktreeApp.isPreview)
    #if DEBUG
    @NSApplicationDelegateAdaptor(PreviewDelegate.self) private var previewDelegate
    #endif

    var body: some Scene {
        MenuBarExtra("MultiWorktree", systemImage: "arrow.triangle.branch") {
            ContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

#if DEBUG
@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        guard env["MWT_PREVIEW"] == "1" else { return }
        switch env["MWT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let home = env["MWT_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let canned = env["MWT_DEPS"].flatMap(PreviewDependencies.report(named:))
        let model = AppModel(home: home, checksDependencies: canned == nil, checksForUpdates: false)
        if let canned { model.dependencies = .checked(canned) }
        model.previewFeatureName = env["MWT_FEATURE"]
        if env["MWT_UPDATE"] == "available", let current = AppVersion(KitInfo.version) {
            model.applyUpdate(.available(AppVersion(major: current.major, minor: current.minor + 1, patch: 0)))
        }
        let window = env["MWT_CHROMELESS"] == "1"
            ? chromelessWindow(model: model)
            : titledWindow(model: model, height: env["MWT_H"].flatMap { Double($0) } ?? 660)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("MWT_WINDOW_ID=\(window.windowNumber)")
            fflush(stdout)
        }
    }

    private func titledWindow(model: AppModel, height: Double) -> NSWindow {
        let host = NSHostingController(rootView: PreviewHarness(chromeless: false).environment(model))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Preview"
        window.setContentSize(NSSize(width: 360, height: height))
        return window
    }

    private func chromelessWindow(model: AppModel) -> NSWindow {
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 388, height: 400),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let root = PreviewHarness(chromeless: true) { [weak window] size in
            window?.setContentSize(size)
        }
        window.contentView = NSHostingView(rootView: root.environment(model))
        return window
    }
}

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum PreviewDependencies {
    static func report(named name: String) -> DependencyReport? {
        let shell = ToolEnvironment(path: "/Users/me/.nvm/versions/node/v22.12.0/bin:\(ToolEnvironment.fixedPath)",
                                    source: .loginShell)
        let homebrewGit = GitStatus.ready(path: "/opt/homebrew/bin/git", version: GitVersion(major: 2, minor: 54, patch: 0))
        switch name {
        case "ok":
            return DependencyReport(environment: shell, git: homebrewGit, claudeInstalled: true)
        case "noclt":
            return DependencyReport(environment: shell, git: .needsCommandLineTools, claudeInstalled: true)
        case "oldgit":
            return DependencyReport(environment: shell,
                                    git: .tooOld(path: "/usr/local/bin/git", version: GitVersion(major: 2, minor: 24, patch: 3)),
                                    claudeInstalled: true)
        case "broken":
            return DependencyReport(environment: shell,
                                    git: .broken(path: "/opt/homebrew/bin/git",
                                                 message: "dyld: Library not loaded: /opt/homebrew/opt/pcre2/lib/libpcre2-8.0.dylib"),
                                    claudeInstalled: true)
        case "noclaude":
            return DependencyReport(environment: shell, git: homebrewGit, claudeInstalled: false)
        case "fallback":
            return DependencyReport(environment: ToolEnvironment(path: ToolEnvironment.fixedPath,
                                                                 source: .fallback(reason: "shell did not finish in 5 s")),
                                    git: homebrewGit, claudeInstalled: true)
        default:
            return nil
        }
    }
}

struct PreviewHarness: View {
    @Environment(AppModel.self) private var model
    let chromeless: Bool
    var onSize: @MainActor (CGSize) -> Void = { _ in }

    var body: some View {
        if chromeless {
            ContentView()
                .fixedSize(horizontal: false, vertical: true)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(\.controlActiveState, .key)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
                .onAppear { applyScreen() }
        } else {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(.regularMaterial)
                .onAppear { applyScreen() }
        }
    }

    private func applyScreen() {
        switch ProcessInfo.processInfo.environment["MWT_SCREEN"] ?? "home" {
        case "newGroup":
            model.screen = .editGroup(nil)
        case "editGroup":
            if let group = model.groups.first { model.screen = .editGroup(group) }
        case "spinUp":
            if let group = model.groups.first { model.screen = .spinUp(group) }
        case "tearDown":
            if let feature = model.features.first { model.screen = .tearDown(feature) }
        case "report":
            let code = "/Users/Shared/mwt-demo/code"
            var report = RunReport()
            report.outcomes = [
                RepoOutcome(repoPath: "\(code)/acme-web", label: .created,
                            reasons: ["new branch feature/gift-cards from origin/main", "copied 1 .worktreeinclude file(s)"]),
                RepoOutcome(repoPath: "\(code)/acme-api", label: .created,
                            reasons: ["new branch feature/gift-cards from origin/main"]),
                RepoOutcome(repoPath: "\(code)/acme-design-system", label: .reused,
                            reasons: ["worktree already exists on branch feature/gift-cards"]),
            ]
            report.notes = ["added to info/exclude: .claude/settings.local.json, CLAUDE.local.md"]
            report.openedClaude = true
            model.lastReport = report
            model.lastReportKind = .spinUp
            model.screen = .report
        default:
            model.screen = .home
        }
    }
}
#endif
