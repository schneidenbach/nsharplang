enum DeviceError {
    Failed
}

[boundary]
func OpenDevice(): Result<int, DeviceError> {
    return Ok(1)
}

[hot]
func UseDevice(handle: int): int {
    return handle
}
