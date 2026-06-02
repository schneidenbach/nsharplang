namespace SystemsProofs.NativeDeviceHandle

import System.Runtime.InteropServices

enum DeviceError {
    OpenFailed
}

struct DeviceHandle {
    fd: int
}

static class NativeMethods {
    [LibraryImport("c", EntryPoint = "open")]
    static func Open(path: string, flags: int): int

    [LibraryImport("c", EntryPoint = "close")]
    static func Close(fd: int): int
}

[boundary]
func OpenDevice(path: string): Result<DeviceHandle, DeviceError> {
    fd := NativeMethods.Open(path, 0)
    if fd < 0 {
        return Err(DeviceError.OpenFailed)
    }

    return Ok(new DeviceHandle { fd: fd })
}

[boundary]
func CloseDevice(handle: DeviceHandle) {
    _ = NativeMethods.Close(handle.fd)
}

func Main() {
    device := OpenDevice("/dev/null")
    print device
}
