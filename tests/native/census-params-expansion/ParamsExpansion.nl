namespace NSharpLang.CensusParamsExpansion.Tests

import System.Collections.Generic
import Microsoft.Extensions.Logging
import Microsoft.Extensions.Logging.Abstractions
import OmniSharp.Extensions.LanguageServer.Protocol.Models


// A `params` TAIL PACKS AT THE CALL SITE. Every shape below writes fewer arguments than the
// declaration has parameters, or more, and the packed array is what the callee receives.

// `Container<T>`'s `params T[]` constructor: the contents and their ORDER are read back by
// enumerating the constructed value, so the array these rows assert on is the one the call site
// built.
func RenderContainer(items: Container<string>): string {
    rendered := ""
    for item in items {
        rendered = rendered + "[" + item + "]"
    }

    return rendered
}

func ThreePacked(): string {
    return RenderContainer(new Container<string>(".", ":", " "))
}

func OnePacked(): string {
    return RenderContainer(new Container<string>("only"))
}

func NonePacked(): string {
    return RenderContainer(new Container<string>())
}

// THE NORMAL FORM STILL WINS. One argument that already IS the declared array type passes straight
// through without being packed into an array of arrays, which is what the `[a][b]` rendering below
// says: a packed answer would render one element whose text is the array's.
func ArrayPassedThrough(): string {
    values := new string[](2)
    values[0] = "a"
    values[1] = "b"
    return RenderContainer(new Container<string>(values))
}

// A sequence is not an array, so it selects the `IEnumerable<T>` constructor rather than either
// form of the `params` one.
func SequencePassedThrough(): string {
    values := new List<string>()
    values.Add("p")
    values.Add("q")
    return RenderContainer(new Container<string>(values))
}

// `LoggerExtensions.LogDebug/LogInformation/LogWarning/LogError` are static extensions on the
// external INTERFACE `ILogger` whose tail is `params object?[] args`. Every one of them was
// invisible to extension resolution while a `params` tail kept the whole declaration out of the
// index — which is what declined every logging call in the language server.
func LogAtEveryArity(logger: ILogger): int {
    logger.LogDebug("no packed arguments")
    logger.LogInformation("one packed {A}", "x")
    logger.LogWarning("two packed {A} {B}", "y", 7)
    logger.LogError("three packed {A} {B} {C}", "z", 8, true)
    return 4
}

func LogThroughNullLogger(): int {
    return LogAtEveryArity(NullLogger.Instance)
}

// The same extension reached through a receiver typed with THIS compilation's own type argument,
// which is the shape every handler holds (`ILogger<TheHandlerItself>`).
class ParamsExpansionHandler {
    readonly logger: ILogger<ParamsExpansionHandler>

    public constructor(logger: ILogger<ParamsExpansionHandler>) {
        this.logger = logger
    }

    func Handle(): bool {
        logger.LogDebug("handling {A}", "request")
        logger.LogInformation("handled {A} {B}", "request", 1)
        return logger.IsEnabled(LogLevel.Debug)
    }
}

// `NullLogger<T>` reports every level disabled, so the returned `false` is the real answer of the
// receiver these rows hold — what the row asserts is that both packed calls above ran and the
// interface member behind them dispatched.
func HandleThroughNullLogger(): bool {
    handler := new ParamsExpansionHandler(NullLogger<ParamsExpansionHandler>.Instance)
    return handler.Handle()
}

// An already-built array handed to the `params` slot of an EXTENSION binds in normal form, exactly
// as it does for the constructor above.
func LogWithBuiltArray(logger: ILogger): int {
    values := new object[](2)
    values[0] = "x"
    values[1] = 7
    logger.LogInformation("two packed {A} {B}", values)
    return 1
}

func LogWithBuiltArrayThroughNullLogger(): int {
    return LogWithBuiltArray(NullLogger.Instance)
}

// ── THE ORDINARY STATIC/INSTANCE CALL DOOR ──────────────────────────────────────────────────────
//
// The extension and constructor doors were wired to the shared packing owner first; this is the
// third and by far the most-travelled one. `ColumnarOrdinaryRuntimeDirectCallResolver` refused ANY
// `params` parameter outright, so `string.Join(sep, a, b, c)` was "not modeled" while
// `Path.Combine(a, b, c)` emitted — not because params worked, but because `Path.Combine` happens to
// declare a FIXED four-argument overload and `string.Join` does not.

// A recorder, so the evaluation ORDER of a packed call is a fact and not an assumption.
class OrdinaryPackOrder {
    static Trace: string

    static func Reset() {
        Trace = ""
    }

    static func Mark(value: string): string {
        Trace = Trace + value
        return value
    }
}

func JoinFourStrings(): string {
    return string.Join(",", "x", "y", "z")
}

func JoinOneString(): string {
    return string.Join("|", "only")
}

// ZERO PACKED ARGUMENTS IS STILL A PACKED CALL: the callee receives a fresh empty array. Written
// through `AppendFormat`, because `string.Join(sep)` alone is a genuine C# ambiguity between the
// `string?[]` and `object?[]` tails and the analyzer says so.
func AppendFormatNoHoles(): string {
    builder := new System.Text.StringBuilder()
    builder.AppendFormat("plain")
    return builder.ToString()
}

func CombineFivePathSegments(): string {
    return System.IO.Path.Combine("a", "b", "c", "d", "e")
}

func FormatFourHoles(): string {
    return string.Format("{0}-{1}-{2}-{3}", 1, 2, 3, 4)
}

// NORMAL FORM STILL BEATS EXPANDED: one argument that already IS the declared array is passed
// straight through, with no `newarr` at the call site.
func JoinWithBuiltArray(): string {
    parts: string[] = ["m", "n"]
    return string.Join("+", parts)
}

func PackedArgumentsRunInWrittenOrder(): string {
    OrdinaryPackOrder.Reset()
    joined := string.Join(OrdinaryPackOrder.Mark("s"), OrdinaryPackOrder.Mark("a"), OrdinaryPackOrder.Mark("b"), OrdinaryPackOrder.Mark("c"))
    return OrdinaryPackOrder.Trace + "=" + joined
}

// The INSTANCE half of the same door: `StringBuilder.AppendFormat(string, params object[])`.
func AppendFormatThreeHoles(): string {
    builder := new System.Text.StringBuilder()
    builder.AppendFormat("{0}/{1}/{2}", 7, 8, 9)
    return builder.ToString()
}
