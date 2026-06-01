namespace SystemsProofs.CsharpHotParserApi

import System
import System.Buffers.Binary

public struct Header {
    Version: ushort
    Length: uint
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

        return Ok(Header {
            Version: BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(0, 2)),
            Length: BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(2, 4))
        })
    }
}
