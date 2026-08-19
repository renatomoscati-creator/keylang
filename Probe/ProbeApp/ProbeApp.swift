import SwiftUI

@main
struct ProbeApp: App {

    init() {
        // Subscribe before P2 runs so the memory-limit kill is reported.
        // Payloads arrive asynchronously, usually within 24 hours, so run P2
        // and come back to the app the next day.
        if #available(iOS 27.0, *) {
            MemoryDiagnostics.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
