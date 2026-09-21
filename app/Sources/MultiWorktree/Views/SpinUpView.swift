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
        VStack(alignment: .leading, spacing: 12) {
            Text("Spin up · \(group.name)").font(.headline)
            HStack {
                TextField("Feature name (branch)", text: $featureText).onSubmit { check() }
                    .disabled(checking)
                Button(checking ? "Checking…" : "Check") { check() }
                    .disabled(featureText.isEmpty || checking)
            }
            if let validationError {
                Text(validationError).foregroundStyle(.red).font(.caption)
            }
            ForEach(group.repos, id: \.path) { repo in
                repoRow(repo)
            }
            Toggle("Open Claude when done", isOn: $openClaude)
            HStack {
                Button("Back") { model.screen = .home }
                Spacer()
                Button(model.isBusy ? "Working…" : "Spin up") { Task { await run() } }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(repo.basename).bold()
                if repo.isMain { Text("main").font(.caption).foregroundStyle(.secondary) }
            }
            switch preflights[repo.path] {
            case .success(let p)?:
                Picker("Base", selection: Binding(get: { choices[repo.path] ?? .defaultBranch }, set: { choices[repo.path] = $0 })) {
                    Text("\(p.remote)/\(p.defaultBranch) (clean default)").tag(BaseChoice.defaultBranch)
                    if p.offersCurrentBranchBase, let current = p.currentBranch {
                        Text("\(current) (current branch, local tip)").tag(BaseChoice.currentBranch)
                    }
                }
                .pickerStyle(.menu)
                ForEach(p.notices, id: \.self) { notice in
                    Text("Warning: \(notice)").font(.caption).foregroundStyle(.orange)
                }
            case .failure(let error)?:
                Text("Failed: \(String(describing: error))").font(.caption).foregroundStyle(.red)
            case nil:
                if checking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter a feature name and press Check.").font(.caption).foregroundStyle(.secondary)
                }
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
