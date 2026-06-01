namespace SystemsProofs.ColdFailureLogging

import System

enum ParseError {
    Short
    BadMagic
}

class Logger {
    Enabled: bool

    func Debug(message: string) {
        print message
    }
}

[hot]
func ParseMagic(buf: ReadOnlySpan<byte>, log: Logger): Result<int, ParseError> {
    if buf.Length < 2 {
        if log.Enabled {
            allow(alloc, reason: "cold diagnostic path after parse failure") {
                log.Debug(alloc $"short packet: {buf.Length}")
            }
        }

        return Err(ParseError.Short)
    }

    if buf[0] != 78 || buf[1] != 35 {
        return Err(ParseError.BadMagic)
    }

    return Ok(2)
}

func Main() {
    log := new Logger()
    _ = ParseMagic(new byte[] { 78, 35 }, log)
}
