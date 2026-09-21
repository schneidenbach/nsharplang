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
