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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original == nil ? "New group" : "Edit group").font(.headline)
            TextField("Group name", text: $name)
            ForEach(repos, id: \.path) { repo in
                HStack {
                    Toggle("Main", isOn: Binding(get: { repo.isMain }, set: { on in setMain(repo, on) }))
                        .toggleStyle(.checkbox)
                    Text(repo.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { repos.removeAll { $0.path == repo.path } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("/absolute/path/to/repo", text: $newPath)
                Button("Add") { add(path: newPath) }.disabled(newPath.isEmpty)
                Button("Choose…") { choose() }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            HStack {
                if let original {
                    Button("Delete group", role: .destructive) { model.deleteGroup(named: original.name) }
                }
                Spacer()
                Button("Cancel") { model.screen = .home }
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func setMain(_ repo: RepoEntry, _ on: Bool) {
        for index in repos.indices {
            repos[index].isMain = on && repos[index].path == repo.path
        }
    }

    private func add(path: String) {
        do {
            let normalized = try model.normalizedRepoPath(path.trimmingCharacters(in: .whitespaces))
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
