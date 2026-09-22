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
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(symbol: "trash.fill", title: "Tear down", subtitle: manifest.feature,
                         tint: .red, onBack: { model.screen = .home })

            VStack(alignment: .leading, spacing: 8) {
                ForEach(manifest.repos.filter { $0.status != .removed }, id: \.path) { repo in
                    repoRow(repo)
                }
            }

            HintText("Branches are deleted only when fully pushed, or when they carry no commits beyond the default branch.",
                     symbol: "info.circle")

            FooterBar {
                Spacer()
                Button { Task { await run() } } label: {
                    Label(model.isBusy ? "Working…" : (confirmed.isEmpty ? "Tear down" : "Discard & tear down"),
                          systemImage: "trash.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
            }
        }
    }

    private func repoRow(_ repo: ManifestRepo) -> some View {
        GroupedCard(spacing: 5) {
            Text(URL(fileURLWithPath: repo.path).lastPathComponent).font(.callout.weight(.semibold))
            Text(repo.worktree)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if let outcome = kept.first(where: { $0.repoPath == repo.path }) {
                ForEach(outcome.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle(isOn: Binding(
                    get: { confirmed.contains(repo.path) },
                    set: { on in
                        if on { confirmed.insert(repo.path) } else { confirmed.remove(repo.path) }
                    })) {
                    Text("Discard changes and remove").font(.caption)
                }
                .toggleStyle(.checkbox)
                .tint(.red)
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
