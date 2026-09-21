import SwiftUI
import MWTKit

struct ReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.lastReportKind == .spinUp ? "Spin-up report" : "Tear-down report").font(.headline)
            if let report = model.lastReport {
                if let hardError = report.hardError {
                    Text(hardError).foregroundStyle(.red)
                }
                ForEach(report.outcomes, id: \.repoPath) { outcome in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(URL(fileURLWithPath: outcome.repoPath).lastPathComponent).bold()
                            Text(outcome.label.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .background(color(for: outcome.label).opacity(0.25))
                                .clipShape(Capsule())
                        }
                        ForEach(outcome.reasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(report.notes, id: \.self) { note in
                    Text("• \(note)").font(.caption)
                }
                if model.lastReportKind == .spinUp, !report.openedClaude, report.hardError == nil, let folder = model.lastMainWorktree {
                    Button("Open Claude anyway") { model.openClaude(at: folder) }
                }
            } else if let error = model.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Done") { model.screen = .home }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func color(for label: OutcomeLabel) -> Color {
        switch label {
        case .created, .reused, .removed: return .green
        case .failed: return .red
        case .kept, .warned: return .orange
        case .skipped: return .gray
        }
    }
}
