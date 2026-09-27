import SwiftUI
import MWTKit

struct UpdateBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let version = model.visibleUpdate {
            NoticeBanner(style: .info,
                         title: "MultiWorktree \(version) is available",
                         message: "You have \(KitInfo.version).") {
                Button("Download") { model.openReleasesPage() }
                Button("Later") { model.dismissUpdate() }
                Button("Skip this version") { model.skipUpdate(version) }
            }
        }
    }
}
