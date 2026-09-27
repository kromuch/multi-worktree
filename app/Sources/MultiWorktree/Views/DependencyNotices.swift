import SwiftUI
import MWTKit

struct DependencyNotices: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .checked(let report) = model.dependencies, Self.hasNotices(report) {
            VStack(alignment: .leading, spacing: 8) {
                gitNotice(report.git)
                if !report.claudeInstalled {
                    NoticeBanner(style: .warning,
                                 title: "Claude desktop app not found",
                                 message: "Spin up works, but Claude sessions can't be opened until Claude is installed.") {
                        Button("Download Claude") { model.openClaudeDownloadPage() }
                        checkAgain
                    }
                }
                if case .fallback(let reason) = report.environment.source {
                    NoticeBanner(style: .warning,
                                 title: "Couldn't read PATH from your login shell",
                                 message: "\(reason). Repository hooks that need tools outside Homebrew may fail.") {
                        checkAgain
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gitNotice(_ status: GitStatus) -> some View {
        switch status {
        case .ready:
            EmptyView()
        case .needsCommandLineTools, .missing:
            NoticeBanner(style: .blocking,
                         title: "Command Line Tools required",
                         message: "MultiWorktree uses git from Apple's Command Line Tools or Homebrew.") {
                Button("Install Command Line Tools") { model.installCommandLineTools() }
                checkAgain
            }
        case .tooOld(let path, let version):
            NoticeBanner(style: .blocking,
                         title: "git \(version) is too old",
                         message: "\(path) is older than \(GitVersion.minimum). Install a newer git, e.g. brew install git.") {
                Button("Copy command") { model.copyToPasteboard("brew install git") }
                checkAgain
            }
        case .broken(let path, let message):
            NoticeBanner(style: .blocking, title: "git doesn't work", message: "\(path): \(message)") {
                checkAgain
            }
        }
    }

    static func hasNotices(_ report: DependencyReport) -> Bool {
        if !report.git.isReady || !report.claudeInstalled { return true }
        if case .fallback = report.environment.source { return true }
        return false
    }

    private var checkAgain: some View {
        Button("Check again") { model.checkDependencies() }
    }
}
