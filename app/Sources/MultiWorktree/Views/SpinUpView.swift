import SwiftUI
import MWTKit

struct SpinUpView: View {
    @Environment(AppModel.self) private var model
    let group: RepoGroup
    @State private var featureText = ""
    @State private var feature: FeatureName?
    @State private var validationError: String?
    @State private var preflights: [String: Result<RepoPreflight, PreflightError>] = [:]
    @State private var choices: [String: BaseChoice] = [:]
    @State private var checking = false
    @State private var openClaude = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(symbol: "bolt.fill", title: "Spin up", subtitle: group.name,
                         onBack: { model.screen = .home })

            HStack(spacing: 8) {
                TextField("Feature name (branch)", text: $featureText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { check() }
                    .disabled(checking)
                Button { check() } label: {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check")
                    }
                }
                .buttonStyle(.glass)
                .disabled(featureText.isEmpty || checking)
            }

            if let validationError {
                InlineBanner(text: validationError)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.repos, id: \.path) { repo in
                    repoRow(repo)
                }
            }

            Toggle(isOn: $openClaude) {
                Label("Open Claude when done", systemImage: "sparkles")
            }
            .toggleStyle(.switch)

            FooterBar {
                Spacer()
                Button { Task { await run() } } label: {
                    Label(model.isBusy ? "Working…" : "Spin up", systemImage: "bolt.fill")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(feature == nil || preflights.isEmpty || model.isBusy || mainPreflightFailed)
            }
        }
    }

    private var mainPreflightFailed: Bool {
        guard let main = group.main, case .success? = preflights[main.path] else { return true }
        return false
    }

    @ViewBuilder
    private func repoRow(_ repo: RepoEntry) -> some View {
        GroupedCard(spacing: 6) {
            HStack(spacing: 6) {
                Text(repo.basename).font(.callout.weight(.semibold))
                if repo.isMain {
                    StatusChip(text: "main", color: .accentColor)
                }
                Spacer(minLength: 6)
                statusIcon(for: repo)
            }
            content(for: repo)
        }
    }

    @ViewBuilder
    private func statusIcon(for repo: RepoEntry) -> some View {
        switch preflights[repo.path] {
        case .success?:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure?:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case nil:
            if checking {
                ProgressView().controlSize(.small)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(for repo: RepoEntry) -> some View {
        switch preflights[repo.path] {
        case .success(let p)?:
            Picker("Base", selection: Binding(
                get: { choices[repo.path] ?? .defaultBranch },
                set: { choices[repo.path] = $0 }
            )) {
                Text("\(p.remote)/\(p.defaultBranch) — clean default").tag(BaseChoice.defaultBranch)
                if p.offersCurrentBranchBase, let current = p.currentBranch {
                    Text("\(current) — current branch, local tip").tag(BaseChoice.currentBranch)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            ForEach(p.notices, id: \.self) { notice in
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        case .failure(let error)?:
            Label("Failed: \(String(describing: error))", systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red)
        case nil:
            if checking {
                HintText("Checking…")
            } else {
                HintText("Enter a feature name and press Check.", symbol: "arrow.up")
            }
        }
    }

    private func check() {
        do {
            feature = try FeatureName.parse(featureText)
            validationError = nil
        } catch {
            feature = nil
            preflights = [:]
            validationError = "Invalid feature name: \(error)"
            return
        }
        guard let feature else { return }
        preflights = [:]
        checking = true
        Task {
            preflights = await model.preflight(group: group, feature: feature)
            checking = false
        }
    }

    private func run() async {
        guard let feature else { return }
        await model.spinUp(group: group, feature: feature, choices: choices, preflights: preflights, openClaude: openClaude)
    }
}
