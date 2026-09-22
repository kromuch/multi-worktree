import SwiftUI
import MWTKit

struct ReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(symbol: headerSymbol, title: title, tint: headerTint)

            if let report = model.lastReport {
                if let hardError = report.hardError {
                    InlineBanner(text: hardError, selectable: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.outcomes, id: \.repoPath) { outcome in
                        outcomeRow(outcome)
                    }
                }
                if !report.notes.isEmpty {
                    GroupedCard(spacing: 4) {
                        ForEach(report.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.lastReportKind == .spinUp, !report.openedClaude, report.hardError == nil,
                   let folder = model.lastMainWorktree {
                    Button { model.openClaude(at: folder) } label: {
                        Label("Open Claude anyway", systemImage: "sparkles")
                    }
                    .buttonStyle(.glass)
                }
            } else if let error = model.lastError {
                InlineBanner(text: error, selectable: true)
            }

            FooterBar {
                Spacer()
                Button { model.screen = .home } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var title: String {
        model.lastReportKind == .spinUp ? "Spin-up report" : "Tear-down report"
    }

    private var hasHardError: Bool {
        model.lastReport?.hardError != nil || (model.lastReport == nil && model.lastError != nil)
    }

    private var headerSymbol: String {
        hasHardError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    private var headerTint: Color {
        hasHardError ? .red : .green
    }

    private func outcomeRow(_ outcome: RepoOutcome) -> some View {
        GroupedCard(spacing: 4) {
            HStack(spacing: 6) {
                Text(URL(fileURLWithPath: outcome.repoPath).lastPathComponent)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 6)
                StatusChip(text: outcome.label.rawValue, color: color(for: outcome.label))
            }
            ForEach(outcome.reasons, id: \.self) { reason in
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
