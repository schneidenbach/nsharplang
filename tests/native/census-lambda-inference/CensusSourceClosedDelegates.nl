namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic


// A DELEGATE CLOSED OVER A TYPE THIS COMPILATION IS STILL WRITING.
//
// `handler: Action<PriceArgs> = a => …` reported NL203 — "I can't figure out the type of lambda
// parameter 'a' — nothing here names the lambda's delegate type" — for a home that names its type
// exactly. The lambda walk read its expected signature off the CLR instantiation, and
// `Action<PriceArgs>` HAS no CLR instantiation while `PriceArgs` is a builder, so it read the
// signature off nothing and every parameter of the lambda was uninferable.
//
// `Func` was the one shape that escaped, and not for a reason about delegates: the PARSER spells
// `Func<…>` as N#'s own function type rather than as a generic name, so it never reached the read
// that failed. That made the gap look like an `Action` problem when it belonged to every generic
// delegate — `Predicate<T>`, `Comparison<T>`, `Converter<T, R>`, `EventHandler<T>` and a referenced
// assembly's own all reported the same NL203 over a source type argument.
//
// A generic delegate states its shape in the DEFINITION's `Invoke`, which exists whether or not the
// instantiation can be constructed; this instantiation's arguments substitute into the positions
// that definition spells as bare type parameters. Nothing here consults a delegate's NAME.
class PriceArgs {
    Symbol: string
    Price: int

    constructor(symbol: string, price: int) {
        Symbol = symbol
        Price = price
    }
}

struct PriceStamp {
    Ticks: int
}

// THE CENSUS SITE ITSELF: a delegate FIELD whose type closes over a sibling source class, assigned
// a block-bodied lambda.
//
// The handlers are wired in a METHOD rather than in the constructor deliberately: a lambda that
// captures `this` and is assigned to a field IN A CONSTRUCTOR declines at emit
// (`emit.statement.block-child`) for every delegate type, `Action<int>` included, so that shape is a
// different owner's gap and pinning it here would measure the wrong thing.
class PriceBoard {
    Log: List<string> = new List<string>()
    Handler: Action<PriceArgs>
    Pair: Action<PriceArgs, PriceArgs>
    Scorer: Func<PriceArgs, int>

    constructor() {
        Handler = args => {
            print args.Symbol
        }
        Pair = (first, second) => {
            print first.Symbol
        }
        Scorer = args => args.Price * 2
    }

    func Wire() {
        Handler = args => {
            Log.Add(args.Symbol + ":" + args.Price.ToString())
        }
        Pair = (first, second) => {
            Log.Add(first.Symbol + "/" + second.Symbol)
        }
    }
}

func SinkOverSourceClass(): Action<PriceArgs> {
    return args => {
        print args.Symbol
    }
}

func SinkOverSourceStruct(): Action<PriceStamp> {
    return stamp => {
        print stamp.Ticks
    }
}

func ExpensivePredicate(): Predicate<PriceArgs> {
    return args => args.Price > 100
}

func ByPriceDescending(): Comparison<PriceArgs> {
    return (left, right) => right.Price - left.Price
}

func SymbolOf(): Converter<PriceArgs, string> {
    return args => args.Symbol
}

func PriceOf(): Func<PriceArgs, int> {
    return args => args.Price
}

// A DELEGATE THE FRAMEWORK DECLARES WITH A SENDER POSITION, closed over a source class. Its `Invoke`
// is `(object, TEventArgs) -> void`, and the FIRST position is not a type argument at all — which is
// what the definition read gets right and a positional type-argument read could not.
func SenderHandler(sink: List<string>): EventHandler<PriceArgs> {
    return (sender, args) => {
        sink.Add(args.Symbol)
    }
}

// THE SAME TARGET SHAPE FOR A METHOD GROUP rather than a lambda: the expected signature the group is
// measured against comes from the same read.
class PriceRules {
    static func IsExpensive(args: PriceArgs): bool {
        return args.Price > 100
    }

    static func Announce(args: PriceArgs) {
        print args.Symbol
    }
}

func ExpensiveGroup(): Predicate<PriceArgs> {
    return PriceRules.IsExpensive
}

func AnnounceGroup(): Action<PriceArgs> {
    return PriceRules.Announce
}

func SamplePrices(): List<PriceArgs> {
    prices := new List<PriceArgs>()
    prices.Add(new PriceArgs("beta", 40))
    prices.Add(new PriceArgs("alpha", 150))
    return prices
}
