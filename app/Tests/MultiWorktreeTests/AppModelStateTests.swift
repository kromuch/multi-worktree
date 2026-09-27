import Foundation
import Testing
import MWTKit
@testable import MultiWorktree

enum TestTempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "mwt-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
@Suite struct AppModelStateTests {
    static let shell = ToolEnvironment(path: "/Users/me/.nvm/versions/node/v22.12.0/bin:\(ToolEnvironment.fixedPath)",
                                       source: .loginShell)
    static let ready = GitStatus.ready(path: "/opt/homebrew/bin/git", version: GitVersion(major: 2, minor: 54, patch: 0))

    static let nonReadyStatuses: [GitStatus] = [
        .needsCommandLineTools,
        .missing,
        .tooOld(path: "/usr/local/bin/git", version: GitVersion(major: 2, minor: 24, patch: 3)),
        .broken(path: "/opt/homebrew/bin/git", message: "dyld: Library not loaded"),
    ]

    static func report(git: GitStatus, environment: ToolEnvironment = shell, claudeInstalled: Bool = true) -> DependencyReport {
        DependencyReport(environment: environment, git: git, claudeInstalled: claudeInstalled)
    }

    func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let home = try TestTempDir.make()
        let name = "mwt-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: home)
        }
        let model = AppModel(home: home, checksDependencies: false, checksForUpdates: false, defaults: defaults)
        try body(model, defaults)
    }

    @Test func gitReadyReflectsStatus() throws {
        try withModel { model, _ in
            #expect(model.gitReady == false)
            model.apply(Self.report(git: Self.ready))
            #expect(model.gitReady == true)
            for status in Self.nonReadyStatuses {
                model.apply(Self.report(git: status))
                #expect(model.gitReady == false)
            }
        }
    }

    @Test func claudeAvailableReflectsReport() throws {
        try withModel { model, _ in
            #expect(model.claudeAvailable == false)
            model.apply(Self.report(git: Self.ready, claudeInstalled: true))
            #expect(model.claudeAvailable == true)
            model.apply(Self.report(git: Self.ready, claudeInstalled: false))
            #expect(model.claudeAvailable == false)
        }
    }

    @Test func gitFooterText() throws {
        try withModel { model, _ in
            #expect(model.gitFooterText == "git · checking…")
            model.apply(Self.report(git: Self.ready))
            #expect(model.gitFooterText == "git 2.54.0 · /opt/homebrew/bin/git")
            for status in Self.nonReadyStatuses {
                model.apply(Self.report(git: status))
                #expect(model.gitFooterText == "git · unavailable")
            }
        }
    }

    @Test func pathFooter() throws {
        try withModel { model, _ in
            #expect(model.pathFooter == nil)

            model.apply(Self.report(git: Self.ready, environment: Self.shell))
            #expect(model.pathFooter?.text == "PATH · login shell")
            #expect(model.pathFooter?.help == Self.shell.path)

            let fallback = ToolEnvironment(path: ToolEnvironment.fixedPath, source: .fallback(reason: "shell did not finish in 5 s"))
            model.apply(Self.report(git: Self.ready, environment: fallback))
            #expect(model.pathFooter?.text == "PATH · fallback")
            #expect(model.pathFooter?.help == fallback.path)

            model.apply(Self.report(git: Self.ready, environment: .fixed))
            #expect(model.pathFooter?.text == "PATH · fixed")
            #expect(model.pathFooter?.help == ToolEnvironment.fixed.path)
        }
    }

    @Test func applyReadyReportRebuildsGit() throws {
        try withModel { model, _ in
            let report = Self.report(git: Self.ready)
            model.apply(report)
            #expect(model.dependencies == .checked(report))
            #expect(model.git.gitPath == "/opt/homebrew/bin/git")
            let runner = model.git.runner as? ProcessRunner
            #expect(runner?.environment == report.environment)
        }
    }

    @Test func applyNonReadyReportKeepsGitPath() throws {
        try withModel { model, _ in
            let original = model.git.gitPath
            for status in Self.nonReadyStatuses {
                let report = Self.report(git: status)
                model.apply(report)
                #expect(model.dependencies == .checked(report))
                #expect(model.git.gitPath == original)
            }
        }
    }

    @Test func updateNoticeVisibilityAndSkip() throws {
        let standardBefore = UserDefaults.standard.object(forKey: AppModel.skippedUpdateKey) as? String
        try withModel { model, defaults in
            let v030 = AppVersion(major: 0, minor: 3, patch: 0)
            #expect(model.visibleUpdate == nil)

            model.applyUpdate(.available(v030))
            #expect(model.visibleUpdate == v030)

            model.dismissUpdate()
            #expect(model.visibleUpdate == nil)

            model.applyUpdate(.available(v030))
            #expect(model.visibleUpdate == v030)

            model.skipUpdate(v030)
            #expect(model.visibleUpdate == nil)
            #expect(defaults.string(forKey: AppModel.skippedUpdateKey) == "0.3.0")

            let home = try TestTempDir.make()
            defer { try? FileManager.default.removeItem(at: home) }
            let reopened = AppModel(home: home, checksDependencies: false, checksForUpdates: false, defaults: defaults)
            #expect(reopened.skippedUpdateVersion == "0.3.0")
            reopened.applyUpdate(.available(v030))
            #expect(reopened.visibleUpdate == nil)
            reopened.applyUpdate(.available(AppVersion(major: 0, minor: 4, patch: 0)))
            #expect(reopened.visibleUpdate == AppVersion(major: 0, minor: 4, patch: 0))

            model.applyUpdate(.upToDate)
            #expect(model.visibleUpdate == nil)
            model.applyUpdate(.failed("HTTP 403"))
            #expect(model.visibleUpdate == nil)
        }
        #expect(UserDefaults.standard.object(forKey: AppModel.skippedUpdateKey) as? String == standardBefore)
    }

    @Test func updateHelpText() throws {
        try withModel { model, defaults in
            #expect(model.updateHelp == "Checking for updates…")
            model.applyUpdate(.upToDate)
            #expect(model.updateHelp == "Up to date")
            model.applyUpdate(.available(AppVersion(major: 0, minor: 3, patch: 0)))
            #expect(model.updateHelp == "MultiWorktree 0.3.0 is available")
            model.applyUpdate(.failed("HTTP 403"))
            #expect(model.updateHelp == "Update check failed: HTTP 403")

            defaults.set(false, forKey: AppModel.checkForUpdatesKey)
            #expect(model.updateHelp == "Update checks are off")
            model.applyUpdate(.upToDate)
            #expect(model.updateHelp == "Update checks are off")
        }
    }
}
