import SwiftUI
import AppKit
import MWTKit

struct GroupEditorView: View {
    @Environment(AppModel.self) private var model
    let original: RepoGroup?
    @State private var name: String
    @State private var repos: [RepoEntry]
    @State private var newPath = ""
    @State private var error: String?

    init(original: RepoGroup?) {
        self.original = original
        _name = State(initialValue: original?.name ?? "")
        _repos = State(initialValue: original?.repos ?? [])
    }

    private var isEditing: Bool { original != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(symbol: isEditing ? "square.and.pencil" : "folder.badge.plus",
                         title: isEditing ? "Edit group" : "New group",
                         onBack: { model.screen = .home })

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Group name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Repositories")
                if repos.isEmpty {
                    CardRow(interactive: false) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder").foregroundStyle(.tertiary)
                            Text("Add at least one repository, then mark one as main.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(repos, id: \.path) { repo in
                        repoRow(repo)
                    }
                }
                HStack(spacing: 8) {
                    TextField("/absolute/path/to/repo", text: $newPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add(path: newPath) }
                    Button { add(path: newPath) } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.glass)
                    .disabled(newPath.isEmpty)
                    Button { choose() } label: {
                        Label("Choose…", systemImage: "folder")
                    }
                    .buttonStyle(.glass)
                }
            }

            if let error {
                InlineBanner(text: error)
            }

            FooterBar {
                if isEditing, let original {
                    Button(role: .destructive) { model.deleteGroup(named: original.name) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                    .controlSize(.small)
                }
                Spacer()
                Button { save() } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func repoRow(_ repo: RepoEntry) -> some View {
        CardRow {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { repo.isMain }, set: { on in setMain(repo, on) })) {}
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Set as main worktree")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(repo.basename).font(.callout.weight(.semibold))
                        if repo.isMain { StatusChip(text: "main", color: .accentColor) }
                    }
                    Text(repo.path)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Button { repos.removeAll { $0.path == repo.path } } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.borderless)
                .help("Remove repository")
            }
        }
    }

    private func setMain(_ repo: RepoEntry, _ on: Bool) {
        for index in repos.indices {
            repos[index].isMain = on && repos[index].path == repo.path
        }
    }

    private func add(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let normalized = try model.normalizedRepoPath(trimmed)
            guard !repos.contains(where: { $0.path == normalized }) else { return }
            repos.append(RepoEntry(path: normalized, isMain: repos.isEmpty))
            newPath = ""
            error = nil
        } catch {
            self.error = "Not a git repository: \(path)"
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            add(path: url.path)
        }
    }

    private func save() {
        let group = RepoGroup(name: name.trimmingCharacters(in: .whitespaces), repos: repos)
        do {
            try group.validate()
            error = nil
            model.saveGroup(group, replacing: original?.name)
        } catch {
            self.error = String(describing: error)
        }
    }
}
