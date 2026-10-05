namespace NSharpLang.Cli.Daemon

import System
import System.Collections.Generic
import System.IO
import System.Text

// EVERYTHING ONE COMMAND NEEDS FROM THE PROCESS THAT ASKED FOR IT.
//
// A command run in-process reads its arguments, its current directory, its environment, its culture
// and whether its streams are terminals from its own process. A command run by the workspace server
// reads each of them from here instead, so the server reproduces the client's process exactly.
class DaemonExecRequest {
    ProtocolVersion: int
    Identity: string
    Args: string[]
    CommandLineArgs: string[]
    WorkingDirectory: string
    EnvironmentNames: string[]
    EnvironmentValues: string[]
    Culture: string
    UiCulture: string
    StdoutRedirected: bool
    StderrRedirected: bool
    StdinRedirected: bool
    ClientProcessId: int

    constructor(
        protocolVersion: int,
        identity: string,
        args: string[],
        commandLineArgs: string[],
        workingDirectory: string,
        environmentNames: string[],
        environmentValues: string[],
        culture: string,
        uiCulture: string,
        stdoutRedirected: bool,
        stderrRedirected: bool,
        stdinRedirected: bool,
        clientProcessId: int
    ) {
        ProtocolVersion = protocolVersion
        Identity = identity
        Args = args
        CommandLineArgs = commandLineArgs
        WorkingDirectory = workingDirectory
        EnvironmentNames = environmentNames
        EnvironmentValues = environmentValues
        Culture = culture
        UiCulture = uiCulture
        StdoutRedirected = stdoutRedirected
        StderrRedirected = stderrRedirected
        StdinRedirected = stdinRedirected
        ClientProcessId = clientProcessId
    }
}

// One frame off the wire: a kind byte and its payload.
class DaemonFrame {
    Kind: byte
    Payload: byte[]

    constructor(kind: byte, payload: byte[]) {
        Kind = kind
        Payload = payload
    }
}

// The exec wire's byte layout. A frame is `[kind: 1 byte][length: int32 little-endian][payload]`.
// Strings travel as `BinaryWriter` writes them (a 7-bit-encoded length, then UTF-8), which is the
// cheapest encoding a cold client can produce — no serializer, no reflection, nothing to JIT but this.
class DaemonExecWire {
    static func EncodeRequest(request: DaemonExecRequest): byte[] {
        using buffer := new MemoryStream()
        using writer := new BinaryWriter(buffer, new UTF8Encoding(false), true)
        writer.Write(request.ProtocolVersion)
        writer.Write(request.Identity)
        WriteStrings(writer, request.Args)
        WriteStrings(writer, request.CommandLineArgs)
        writer.Write(request.WorkingDirectory)
        WriteStrings(writer, request.EnvironmentNames)
        WriteStrings(writer, request.EnvironmentValues)
        writer.Write(request.Culture)
        writer.Write(request.UiCulture)
        writer.Write(request.StdoutRedirected)
        writer.Write(request.StderrRedirected)
        writer.Write(request.StdinRedirected)
        writer.Write(request.ClientProcessId)
        writer.Flush()
        return buffer.ToArray()
    }

    static func DecodeRequest(payload: byte[]): DaemonExecRequest {
        using buffer := new MemoryStream(payload)
        using reader := new BinaryReader(buffer, new UTF8Encoding(false), true)
        protocolVersion := reader.ReadInt32()
        identity := reader.ReadString()
        args := ReadStrings(reader)
        commandLineArgs := ReadStrings(reader)
        workingDirectory := reader.ReadString()
        environmentNames := ReadStrings(reader)
        environmentValues := ReadStrings(reader)
        culture := reader.ReadString()
        uiCulture := reader.ReadString()
        stdoutRedirected := reader.ReadBoolean()
        stderrRedirected := reader.ReadBoolean()
        stdinRedirected := reader.ReadBoolean()
        clientProcessId := reader.ReadInt32()
        if environmentNames.Length != environmentValues.Length {
            throw new InvalidDataException("Exec request environment names and values differ in length.")
        }

        return new DaemonExecRequest(
            protocolVersion,
            identity,
            args,
            commandLineArgs,
            workingDirectory,
            environmentNames,
            environmentValues,
            culture,
            uiCulture,
            stdoutRedirected,
            stderrRedirected,
            stdinRedirected,
            clientProcessId
        )
    }

    // The launch directive `nlc run` sends back to the client: the arguments for `dotnet` and the
    // directory to start it in (empty for "the client's own").
    static func EncodeLaunch(arguments: string, workingDirectory: string?): byte[] {
        using buffer := new MemoryStream()
        using writer := new BinaryWriter(buffer, new UTF8Encoding(false), true)
        writer.Write(arguments)
        writer.Write(workingDirectory ?? "")
        writer.Flush()
        return buffer.ToArray()
    }

    static func DecodeLaunchArguments(payload: byte[]): string {
        using buffer := new MemoryStream(payload)
        using reader := new BinaryReader(buffer, new UTF8Encoding(false), true)
        return reader.ReadString()
    }

    static func DecodeLaunchWorkingDirectory(payload: byte[]): string {
        using buffer := new MemoryStream(payload)
        using reader := new BinaryReader(buffer, new UTF8Encoding(false), true)
        reader.ReadString()
        return reader.ReadString()
    }

    // Little-endian, as `BitConverter` writes it on every platform .NET runs this CLI on.
    static func EncodeInt32(value: int): byte[] {
        return BitConverter.GetBytes(value)
    }

    static func DecodeInt32(bytes: byte[], offset: int): int {
        return BitConverter.ToInt32(bytes, offset)
    }

    static func EncodeString(value: string): byte[] {
        return Encoding.UTF8.GetBytes(value)
    }

    static func DecodeString(bytes: byte[]): string {
        return Encoding.UTF8.GetString(bytes)
    }

    // Writes one whole frame. Callers that share a stream between threads hold their own lock around
    // this call; a frame is never interleaved with another.
    static func WriteFrame(stream: Stream, kind: byte, payload: byte[], offset: int, count: int) {
        header := new byte[](5)
        header[0] = kind
        Array.Copy(EncodeInt32(count), 0, header, 1, 4)
        stream.Write(header, 0, 5)
        if count > 0 {
            stream.Write(payload, offset, count)
        }

        stream.Flush()
    }

    // The next frame, or null at a clean end of stream. A stream that ends inside a frame, or a
    // length past the cap, is corrupt and throws.
    static func ReadFrame(stream: Stream): DaemonFrame? {
        header := new byte[](5)
        if !ReadExactly(stream, header, 5, true) {
            return null
        }

        length := DecodeInt32(header, 1)
        if length < 0 || length > DaemonExecKernels.GetMaxFramePayloadBytes() {
            throw new InvalidDataException("Exec frame length " + length.ToString() + " is out of range.")
        }

        payload := new byte[](length)
        if length > 0 {
            ReadExactly(stream, payload, length, false)
        }

        return new DaemonFrame(header[0], payload)
    }

    // Fills `buffer[0..count)`. At a clean end of stream before the first byte, answers false when
    // `allowEmpty` is set; any other short read throws.
    static func ReadExactly(stream: Stream, buffer: byte[], count: int, allowEmpty: bool): bool {
        filled := 0
        while filled < count {
            received := stream.Read(buffer, filled, count - filled)
            if received <= 0 {
                if filled == 0 && allowEmpty {
                    return false
                }

                throw new EndOfStreamException("Exec stream ended inside a frame.")
            }

            filled = filled + received
        }

        return true
    }

    static func WriteStrings(writer: BinaryWriter, values: string[]) {
        writer.Write(values.Length)
        for value in values {
            writer.Write(value)
        }
    }

    static func ReadStrings(reader: BinaryReader): string[] {
        count := reader.ReadInt32()
        if count < 0 || count > 1048576 {
            throw new InvalidDataException("Exec request string count " + count.ToString() + " is out of range.")
        }

        values := new string[](count)
        index := 0
        while index < count {
            values[index] = reader.ReadString()
            index = index + 1
        }

        return values
    }
}
