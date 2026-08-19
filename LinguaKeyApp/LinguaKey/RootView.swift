import SwiftUI
import StudyKit

/// Three screens, no more.
///
/// Today is what the experiment produced, Library is how it gets debugged, and
/// Setup is the two things that can be broken on this device: the language pack
/// and the staged tables.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") { TodayView() }
            Tab("Library", systemImage: "books.vertical") { LibraryView() }
            Tab("Setup", systemImage: "gearshape") { SetupView() }
        }
        .overlay { blocker }
    }

    /// The two states where nothing else can work, said plainly rather than as an
    /// empty screen that looks like a bug.
    @ViewBuilder
    private var blocker: some View {
        switch model.readiness {
        case .noAppGroup:
            ContentUnavailableView(
                "No App Group",
                systemImage: "exclamationmark.triangle",
                description: Text("""
                    The app and the share extension share one container and it is \
                    not reachable. Check that both targets carry the same App Group \
                    entitlement and that Local.xcconfig sets your team.
                    """))
            .background(.background)
        case .noTables(let why):
            ContentUnavailableView(
                "Tables not staged",
                systemImage: "tray",
                description: Text("""
                    Run tools/stage-data.sh and make sure build/LinguaKeyData is in \
                    the app target as a folder reference.

                    \(why)
                    """))
            .background(.background)
        case .loading, .ready:
            EmptyView()
        }
    }
}
