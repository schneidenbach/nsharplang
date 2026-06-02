namespace SystemsProofs.CsharpHotParserApi

import System
import System.Buffers.Binary

public struct Header {
    Version: ushort
    Length: uint

    constructor(version: ushort, length: uint) {
        Version = version
        Length = length
    }
}

public enum HeaderError {
    Short
}

public class PacketApi {
    [hot]
    public static func ParseHeader(bytes: ReadOnlySpan<byte>): Result<Header, HeaderError> {
        if bytes.Length < 6 {
            return Err(HeaderError.Short)
        }

        version := BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(0, 2))
        length := BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(2, 4))
        header := new Header(version, length)
        return Ok(header)
    }
}
