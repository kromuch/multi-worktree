import SwiftUI
import AppKit
import MWTKit

@main
struct MultiWorktreeApp: App {
    @State private var model = AppModel()
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
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["MWT_PREVIEW"] == "1" else { return }
        let model = AppModel()
        let host = NSHostingController(rootView: PreviewHarness().environment(model))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Preview"
        let height = (ProcessInfo.processInfo.environment["MWT_H"]).flatMap { Double($0) } ?? 660
        window.setContentSize(NSSize(width: 360, height: height))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct PreviewHarness: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.regularMaterial)
            .onAppear { applyScreen() }
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
            var report = RunReport()
            report.outcomes = [
                RepoOutcome(repoPath: "/Users/dev/platform-jira-observability",
                            label: .created, reasons: ["Worktree created from origin/main"]),
                RepoOutcome(repoPath: "/Users/dev/platform-service-versions",
                            label: .reused, reasons: ["Existing worktree reused"]),
                RepoOutcome(repoPath: "/Users/dev/hrzn-ai-tools",
                            label: .warned, reasons: ["Local branch is ahead of origin"]),
            ]
            report.notes = ["Additional directories wired into the main worktree"]
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
