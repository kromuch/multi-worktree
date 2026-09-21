import SwiftUI
import AppKit
import MWTKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
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
        .frame(width: 440)
        .padding()
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Groups").font(.headline)
                Spacer()
                Button("New group") { model.screen = .editGroup(nil) }
            }
            if model.groups.isEmpty {
                Text("No groups yet.").foregroundStyle(.secondary)
            }
            ForEach(model.groups, id: \.name) { group in
                HStack {
                    VStack(alignment: .leading) {
                        Text(group.name).bold()
                        Text(group.repos.map(\.basename).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Spin up…") { model.screen = .spinUp(group) }
                    Button("Edit") { model.screen = .editGroup(group) }
                }
            }
            Divider()
            HStack {
                Text("Features").font(.headline)
                Spacer()
                Button("Refresh") { model.reload() }
            }
            if model.features.isEmpty {
                Text("Nothing spun up.").foregroundStyle(.secondary)
            }
            ForEach(model.features, id: \.segment) { manifest in
                HStack {
                    VStack(alignment: .leading) {
                        Text(manifest.feature).bold()
                        Text("\(manifest.group) · \(manifest.repos.filter { $0.status != .removed }.count) worktree(s)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Claude") { model.openClaude(at: URL(fileURLWithPath: manifest.mainWorktree)) }
                    Button("Tear down…") { model.screen = .tearDown(manifest) }
                }
            }
            if let error = model.lastError {
                Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled)
            }
            Divider()
            HStack {
                Text("MultiWorktree \(KitInfo.version) · git: \(model.git.gitPath)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }
}
