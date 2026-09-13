namespace NSharpLang.CensusLambdaInference.Tests

import System
import System.Collections.Generic


// ── a generic delegate closed over a SOURCE type ──────────────────────────────────────────────
test "a void generic delegate over a source class takes a lambda and runs it" {
    board := new PriceBoard()
    board.Wire()
    board.Handler(new PriceArgs("alpha", 12))
    assert board.Log.Count == 1
    assert board.Log[0] == "alpha:12"

    board.Pair(new PriceArgs("a", 1), new PriceArgs("b", 2))
    assert board.Log.Count == 2
    assert board.Log[1] == "a/b"

    // The value-returning sibling is the shape that already worked, and answers the same.
    assert board.Scorer(new PriceArgs("c", 21)) == 42
}

test "the delegate a source-closed lambda builds IS the delegate the annotation named" {
    assert SinkOverSourceClass().GetType() == typeof(Action<PriceArgs>)
    assert SinkOverSourceStruct().GetType() == typeof(Action<PriceStamp>)
    assert ExpensivePredicate().GetType() == typeof(Predicate<PriceArgs>)
    assert ByPriceDescending().GetType() == typeof(Comparison<PriceArgs>)
    assert SymbolOf().GetType() == typeof(Converter<PriceArgs, string>)
    assert PriceOf().GetType() == typeof(Func<PriceArgs, int>)
}

test "the delegate's own Invoke carries the SOURCE type, read back through reflection" {
    invoke := must typeof(Action<PriceArgs>).GetMethod("Invoke")
    parameters := invoke.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].ParameterType == typeof(PriceArgs)
    assert invoke.ReturnType.FullName == "System.Void"
}

test "a source-closed delegate really runs, through the framework method that takes it" {
    prices := SamplePrices()

    found := must prices.Find(ExpensivePredicate())
    assert found.Symbol == "alpha"
    assert prices.FindIndex(ExpensivePredicate()) == 1

    prices.Sort(ByPriceDescending())
    assert prices[0].Symbol == "alpha"
    assert prices[1].Symbol == "beta"

    // `Converter<T, R>` is the same read one more time, invoked directly rather than handed to a
    // framework method.
    naming := SymbolOf()
    assert naming(prices[0]) == "alpha"
    assert naming(prices[1]) == "beta"
}

// The sender position of `EventHandler<T>` is `object`, not a type argument — a shape a positional
// read of the type arguments would get wrong and the definition's own `Invoke` gets right.
test "a delegate whose Invoke has a non-type-argument position converts over a source type" {
    sink := new List<string>()
    handler := SenderHandler(sink)
    assert handler.GetType() == typeof(EventHandler<PriceArgs>)

    handler(null, new PriceArgs("gamma", 3))
    assert sink.Count == 1
    assert sink[0] == "gamma"

    handlerInvoke := must typeof(EventHandler<PriceArgs>).GetMethod("Invoke")
    handlerParameters := handlerInvoke.GetParameters()
    assert handlerParameters.Length == 2
    assert handlerParameters[0].ParameterType == typeof(object)
    assert handlerParameters[1].ParameterType == typeof(PriceArgs)
}

test "a METHOD GROUP reaches a source-closed delegate by the same read" {
    expensive := ExpensiveGroup()
    assert expensive.GetType() == typeof(Predicate<PriceArgs>)
    assert expensive(new PriceArgs("alpha", 150))
    assert !expensive(new PriceArgs("beta", 40))

    assert AnnounceGroup().GetType() == typeof(Action<PriceArgs>)
}
