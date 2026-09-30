namespace NSharpLang.CensusPipelines.Tests

import System
import System.IO.Pipelines
import System.Text
import System.Threading.Tasks


// CENSUS — `System.IO.Pipelines`, EXECUTED.
//
// No type from this assembly could be emitted: `import System.IO.Pipelines` reported NL704 "namespace
// not found", and a fully-qualified `new System.IO.Pipelines.Pipe()` passed `check` and then
// declined at emit with nothing the scan could resolve. The assembly was simply not in the one
// common-assembly table the analyzer and the columnar scan share — `new StringBuilder()` and `new
// JsonSerializerOptions()` emitted in the same project because THEIR assemblies are. It is in the
// table now, so the rows below run.
//
// The pipe is what a long-running stdio server pumps stdin through so that EOF on its input
// terminates it, which is the language server's "must not outlive its client" behaviour.
class Pipelines {
    static func ConstructedWithOptions(): string {
        pipe := new Pipe(new PipeOptions())
        return (pipe.Reader == null ? "no-reader" : "reader") + ":" + (pipe.Writer == null ? "no-writer" : "writer")
    }

    static func InlineSchedulerIsTheSameInstance(): bool {
        first := PipeScheduler.Inline
        second := PipeScheduler.Inline
        return first != null && Object.ReferenceEquals(first, second)
    }

    // A REAL ROUND TRIP: the bytes written to one end come back out of the other, so the emitted IL
    // drives the assembly rather than merely naming it.
    static async func RoundTrip(text: string): Task<string> {
        pipe := new Pipe()
        bytes := Encoding.UTF8.GetBytes(text)
        memory := pipe.Writer.GetMemory(bytes.Length)
        span := memory.Span
        index := 0
        while index < bytes.Length {
            span[index] = bytes[index]
            index = index + 1
        }
        pipe.Writer.Advance(bytes.Length)
        await pipe.Writer.FlushAsync()
        pipe.Writer.Complete()

        result := await pipe.Reader.ReadAsync()
        buffer := result.Buffer
        decoded := Encoding.UTF8.GetString(buffer.FirstSpan)
        pipe.Reader.AdvanceTo(buffer.End)
        pipe.Reader.Complete()
        return decoded
    }
}
