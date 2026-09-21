import SwiftUI
import MWTKit

struct TearDownView: View {
    @Environment(AppModel.self) private var model
    @State private var manifest: FeatureManifest
    @State private var confirmed: Set<String> = []
    @State private var kept: [RepoOutcome] = []

    init(manifest: FeatureManifest) {
        _manifest = State(initialValue: manifest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tear down · \(manifest.feature)").font(.headline)
            ForEach(manifest.repos.filter { $0.status != .removed }, id: \.path) { repo in
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(fileURLWithPath: repo.path).lastPathComponent).bold()
                    Text(repo.worktree).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let outcome = kept.first(where: { $0.repoPath == repo.path }) {
                        ForEach(outcome.reasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.orange)
                        }
                        Toggle("Discard changes and remove", isOn: Binding(
                            get: { confirmed.contains(repo.path) },
                            set: { on in
                                if on { confirmed.insert(repo.path) } else { confirmed.remove(repo.path) }
                            }))
                    }
                }
            }
            Text("Branches are deleted only when fully pushed or when they carry no commits beyond the default branch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Back") { model.screen = .home }
                Spacer()
                Button(model.isBusy ? "Working…" : (confirmed.isEmpty ? "Tear down" : "Discard and tear down")) {
                    Task { await run() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
            }
        }
    }

    private func run() async {
        guard let result = await model.tearDown(segment: manifest.segment, confirmed: confirmed) else {
            model.screen = .report
            return
        }
        kept = result.report.outcomes.filter { $0.label == .kept }
        if let remaining = result.manifest, !kept.isEmpty {
            manifest = remaining
        } else {
            model.screen = .report
        }
    }
}
