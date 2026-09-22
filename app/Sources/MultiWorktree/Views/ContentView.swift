import SwiftUI
import AppKit
import MWTKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PopoverRoot {
            switch model.screen {
            case .home:
                HomeView()
            case .editGroup(let group):
                GroupEditorView(original: group)
            case .spinUp(let group):
                SpinUpView(group: group)
            case .tearDown(let manifest):
                TearDownView(manifest: manifest)
            case .report:
                ReportView()
            }
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: MWT.sectionSpacing) {
            ScreenHeader(symbol: "arrow.triangle.branch",
                         title: "MultiWorktree",
                         subtitle: "Coordinated git worktrees")

            groupsSection
            featuresSection

            if let error = model.lastError {
                InlineBanner(text: error, selectable: true)
            }

            footer
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Groups") {
                Button { model.screen = .editGroup(nil) } label: {
                    Label("New group", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            if model.groups.isEmpty {
                emptyRow("No groups yet.", symbol: "tray")
            } else {
                ForEach(model.groups, id: \.name) { group in
                    groupRow(group)
                }
            }
        }
    }

    private func groupRow(_ group: RepoGroup) -> some View {
        CardRow {
            HStack(spacing: 10) {
                IconBadge(symbol: "square.stack.3d.up.fill", size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.callout.weight(.semibold))
                    Text(group.repos.map(\.basename).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Button { model.screen = .spinUp(group) } label: {
                    Label("Spin up", systemImage: "bolt.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                Button { model.screen = .editGroup(group) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Edit group")
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Features") {
                Button { model.reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            if model.features.isEmpty {
                emptyRow("Nothing spun up.", symbol: "moon.zzz")
            } else {
                ForEach(model.features, id: \.segment) { manifest in
                    featureRow(manifest)
                }
            }
        }
    }

    private func featureRow(_ manifest: FeatureManifest) -> some View {
        let active = manifest.repos.filter { $0.status != .removed }.count
        return CardRow {
            HStack(spacing: 10) {
                IconBadge(symbol: "arrow.triangle.branch", tint: .teal, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.feature).font(.callout.weight(.semibold))
                    Text("\(manifest.group) · \(active) worktree\(active == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button { model.openClaude(at: URL(fileURLWithPath: manifest.mainWorktree)) } label: {
                    Label("Open", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Open Claude in the main worktree")
                Button { model.screen = .tearDown(manifest) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.red)
                .help("Tear down")
            }
        }
    }

    private func emptyRow(_ text: String, symbol: String) -> some View {
        CardRow(interactive: false) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.tertiary)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        FooterBar {
            VStack(alignment: .leading, spacing: 1) {
                Text("MultiWorktree \(KitInfo.version)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("git · \(model.git.gitPath)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}
