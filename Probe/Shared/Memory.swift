import Foundation
import os

/// Memory instrumentation.
///
/// `task_vm_info.phys_footprint` is the trusted instrument. Apple documents
/// `os_proc_available_memory()` as returning 0 when the calling process is not
/// an app, and a keyboard extension is not an app, so whether it works here is
/// itself one of the probes. Treat a 0 as "unusable", never as "out of memory".
enum Memory {

    /// Resident footprint in MB, or nil if the kernel call failed.
    static func physFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Apple's per-process headroom API. Returns 0 outside an app, per the docs.
    static func availableMB() -> Double {
        Double(os_proc_available_memory()) / 1_048_576
    }

    static func formatted(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return String(format: "%.1f", value)
    }
}
