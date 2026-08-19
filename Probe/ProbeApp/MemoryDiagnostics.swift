import Foundation
import MetricKit

/// iOS 27's answer to the silent jetsam kill.
///
/// Before iOS 27 an extension terminated for exceeding its memory limit produced
/// no crash dialog and no crash log: the user was bounced to their previous
/// keyboard mid-sentence and you learned nothing. iOS 27 adds
/// `MemoryExceptionDiagnostic`, available "when your app or app extension is
/// terminated for exceeding its memory limit", which turns P2's inferred ceiling
/// into Apple's own reported number.
///
/// This is only reachable because the project builds against the iOS 27 SDK.
/// Diagnostics arrive asynchronously, typically within 24 hours of the kill, so
/// run P2, then come back to ProbeApp the next day and tap Refresh.
@available(iOS 27.0, *)
final class MemoryDiagnostics: NSObject, MXMetricManagerSubscriber {

    static let shared = MemoryDiagnostics()

    func start() {
        MXMetricManager.shared.add(self)
        ProbeLog.write("P2", "metrickit.subscribed", "ok", "awaiting diagnostic payloads")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Apple's own report of the memory-limit kill.
            for diagnostic in payload.memoryExceptionDiagnostics ?? [] {
                ProbeLog.write("P2", "metrickit.peak_memory_mb",
                               "\(diagnostic.peakMemory)",
                               "\(diagnostic.peakMemoryUnit) reported by MetricKit")
                ProbeLog.write("P2", "metrickit.exception_meta",
                               diagnostic.metaData.jsonRepresentation()
                                   .base64EncodedString().prefix(120).description,
                               "truncated metadata")
            }
            // terminationCategory is new in iOS 27 and distinguishes a
            // memory-limit kill from every other reason a process died.
            for diagnostic in payload.crashDiagnostics ?? [] {
                ProbeLog.write("P2", "metrickit.termination_category",
                               "\(String(describing: diagnostic.terminationCategory))",
                               "crash diagnostic")
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Not used. Metric payloads are aggregate daily stats, not kill reports.
    }
}
