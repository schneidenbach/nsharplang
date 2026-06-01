namespace SystemsProofs.TrustedAudit

import System

public class UnsafeAuditSurface {
    [memory(safe)]
    [trusted(
        reason: "native handle is never exposed and lifetime is closed by Dispose",
        owner: "interop",
        review: "2026-12-01",
        expires: "2027-06-01"
    )]
    public static func WrapHandle(raw: IntPtr): SafeDevice {
        unsafe {
            return SafeDevice { Raw: raw }
        }
    }
}

public struct SafeDevice {
    Raw: IntPtr
}

// Audit proof command:
// nlc query trusted
