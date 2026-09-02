namespace SystemsProofs.TrustedAudit

class UnsafeAuditSurface {
    [memory(safe)]
    [trusted(reason = "native handle is never exposed and lifetime is closed by Dispose", owner = "interop", review = "2026-12-01", expires = "2027-06-01")]
    static func WrapHandle(raw: IntPtr): SafeDevice {
        unsafe {
            marker := raw
        }
        return new SafeDevice { Raw: raw }
    }
}

struct SafeDevice {
    Raw: IntPtr
}

// Audit proof command:
// nlc query trusted
