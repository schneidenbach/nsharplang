namespace NSharpLang.AnalyzerEventSubscription.Tests

import System
import System.Collections


// THE ANALYZER'S `on`/`off` EVENT DIAGNOSTICS, IN N#.
//
// These replace the ANALYSIS HALF of `tests/EventSubscriptionTests.cs`, which task 020 slice 24
// deletes. That file's ten `[Fact]`s split cleanly in two by SUBJECT: five ask only what
// `ColumnarParserRecovery.ParseFileAst` builds and moved into the estate as
// `ColumnarParserEventSubscription.tests.nl`, and the five recorded here run the whole production
// analyzer and read `AnalysisResult.Errors` / `AnalysisResult.HasErrors`.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT, MEASURED RATHER THAN ASSUMED. The
// diagnostics themselves are N# and live in the estate — `AnalyzerAssignment.nl` reports
// `EventRequiresOnOff`, `AnalyzerExpressionStatements.nl` reports `InvalidEventSubscription` — but
// the thing the deleted `[Fact]`s drove is `Analyzer`, the C# class in `Compiler.dll` that walks the
// tree and calls them, and `Compiler.dll` depends on `NSharpLang.Compiler.BootstrapServices` rather
// than the other way round. A `.tests.nl` inside the estate cannot reach it in any spelling. The
// route is REFLECTION through `object`, which slice 23 measured to be a constraint of the emitter's
// type resolution rather than a style choice: naming a referenced assembly's type in a local, an
// argument or a `new` declines columnar emission for `dll:`, `nuget:` and project references alike.
//
// WHAT THE ESTATE ALREADY COVERED, SWEPT BEFORE THIS FILE WAS WRITTEN. `InvalidEventSubscription`
// appears in exactly ONE estate contract — `AnalyzerLambdaAnalysis.tests.nl`, over a KERNEL harness
// with a stand-in subscription root, for the `on`-target-is-not-an-event arm. `EventRequiresOnOff`
// appears in NO estate contract at all, and neither does the `off`-on-a-non-subscription arm. So
// every contract below is the only coverage its arm has that runs the real analyzer over real .NET
// reflection, and the deleted C# was the only thing holding them.
//
// FIVE THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//   (a) THE SECOND DIAGNOSTIC. `Assert.Single(result.Errors, e => e.Code == ErrorCode.X)` is a claim
//       about the rows carrying ONE code and is silent about every other row. Both rejecting
//       fixtures report TWO errors, not one: the event diagnostic AND an `NL203` on the handler's
//       first lambda parameter, which nothing named the delegate type of. The census below is the
//       WHOLE list, in recording order.
//   (b) THE DIAGNOSTIC ID AND THE SPAN. `NL317` covers the 35 columns of the whole event access and
//       `NL318` the single column of the `off` operand; neither was ever asserted.
//   (c) THE GUIDANCE. The C# read `error.Message` once, for a substring. Each message AND each
//       `Suggestion` is stated in full here, and `+=` and `-=` are shown to differ in BOTH while
//       agreeing on code and span — the subscribe form points at `on`, the unsubscribe form points
//       at capturing the subscription and passing it to `off`.
//   (d) THAT `off` IS NOT REJECTED WHOLESALE. A real `sub := on <event> handler` followed by
//       `off sub` analyses CLEANLY, so `NL318` is about the operand and not about the keyword.
//   (e) THAT `+=` IS NOT REJECTED WHOLESALE. `x := 5` followed by `x += 1` analyses cleanly, so
//       `NL317` is about the .NET event and not about the operator.
func SetEventObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// The estate models both fields and property accessors, and `FileParseAst.CompilationUnit` is a
// FIELD while `AnalysisResult.Errors` is a property, so every read tries both.
func EventMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no '" + memberName + "' member.")
}

func EventRequiredMember(owner: object, memberName: string): object {
    value := EventMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func EventText(owner: object, memberName: string): string {
    value := EventMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

// The production recovery parser, asked with a NULL file name — exactly as the deleted `Analyze`
// helper asked it, and the reason every diagnostic below carries no file.
func EventParse(source: string): object {
    parserType := Type.GetType("NSharpLang.Compiler.Columnar.ColumnarParserRecovery, NSharpLang.Compiler.BootstrapServices")
    if parserType == null {
        throw new InvalidOperationException("The production recovery parser was not loadable.")
    }

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(string)
    parseParameterTypes[1] = typeof(string)
    parseMethod := parserType.GetMethod("ParseFileAst", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production ParseFileAst entry point was not found.")
    }

    parseArguments := new object?[](2)
    SetEventObject(parseArguments, 0, source)
    SetEventObject(parseArguments, 1, null)
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

func EventParseUnit(source: string): object {
    return EventRequiredMember(EventParse(source), "CompilationUnit")
}

// Every PARSE diagnostic of a fixture, in recording order. The deleted `Analyze` helper discarded
// this list entirely; pinning it EMPTY is what makes every row in the analysis census below provably
// the ANALYZER's own rather than a recovery artefact carried in from the parse.
func EventParseCensus(source: string): string {
    errors := EventRequiredMember(EventParse(source), "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + EventText(entry, "DiagnosticId") + "@" + EventText(entry, "Line") + ":" + EventText(entry, "Column") + "+" + EventText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

// The production analysis — `new Analyzer()`, `LoadSystemAssemblies()` and the SINGLE-ARGUMENT
// `Analyze(unit)`, which is the overload the deleted helper called, with the analyzer disposed
// afterwards.
func EventAnalyze(source: string): object {
    unit := EventParseUnit(source)

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    analyzerConstructor := analyzerType.GetConstructor(new Type[](0))
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    analyzer := analyzerConstructor.Invoke(new object?[](0))

    loadParameterTypes := new Type[](0)
    loadMethod := analyzerType.GetMethod("LoadSystemAssemblies", loadParameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadArguments := new object?[](0)
    loadMethod.Invoke(analyzer, loadArguments)

    analyzeParameterTypes := new Type[](1)
    analyzeParameterTypes[0] = unitType
    analyzeMethod := analyzerType.GetMethod("Analyze", analyzeParameterTypes)
    if analyzeMethod == null {
        throw new InvalidOperationException("The production single-argument Analyze entry point was not found.")
    }

    analyzeArguments := new object?[](1)
    SetEventObject(analyzeArguments, 0, unit)
    analysis := analyzeMethod.Invoke(analyzer, analyzeArguments)

    disposeParameterTypes := new Type[](0)
    disposeMethod := analyzerType.GetMethod("Dispose", disposeParameterTypes)
    if disposeMethod != null {
        disposeArguments := new object?[](0)
        disposeMethod.Invoke(analyzer, disposeArguments)
    }

    if analysis == null {
        throw new InvalidOperationException("The production analyzer returned no result.")
    }

    return analysis
}

// EVERY diagnostic's id, code name and span, in recording order. Empty when analysis is silent, and
// non-empty in a way that no `Assert.Single` over a single code could be.
func EventCensus(analysis: object): string {
    errors := EventRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + EventText(entry, "DiagnosticId") + ":" + EventText(entry, "Code") + "@" + EventText(entry, "Line") + ":" + EventText(entry, "Column") + "+" + EventText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func EventHasErrors(analysis: object): string {
    return EventText(analysis, "HasErrors")
}

func EventRowMember(analysis: object, codeName: string, memberName: string): string {
    errors := EventRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null && EventText(entry, "Code") == codeName {
            return EventText(entry, memberName)
        }

        index = index + 1
    }

    return "<no-such-code>"
}

func EventMessage(analysis: object, codeName: string): string {
    return EventRowMember(analysis, codeName, "Message")
}

func EventSuggestion(analysis: object, codeName: string): string {
    return EventRowMember(analysis, codeName, "Suggestion")
}

// ---- contracts ----

test "020 s24 event diagnostics: `+=` on a .NET event is rejected as NL317 over the whole 35-column event access, with guidance naming the `on` form — and the fixture reports a SECOND diagnostic the deleted Assert.Single could not see (was EventSubscriptionTests.Analyze_EventPlusEquals_IsRejectedWithOnOffGuidance)" {
    source := "\nimport System\n\nfunc main() {\n    AppDomain.CurrentDomain.ProcessExit += (sender, args) => {\n        print \"exiting\"\n    }\n}"
    assert EventParseCensus(source) == ""
    analysis := EventAnalyze(source)

    assert EventCensus(analysis) == "NL317:EventRequiresOnOff@5:5+35;NL203:CannotInferType@5:45+6;"
    assert EventHasErrors(analysis) == "True"
    assert EventMessage(analysis, "EventRequiresOnOff") == "'ProcessExit' is a .NET event — it can't be subscribed to with '+='"
    assert EventSuggestion(analysis, "EventRequiresOnOff") == "Subscribe with `on AppDomain.CurrentDomain.ProcessExit (sender, args) => { ... }`; it returns a subscription you can later pass to `off`."
}

test "020 s24 event diagnostics: `-=` on a .NET event is rejected as the SAME NL317 over the SAME span, and carries the same second diagnostic (was EventSubscriptionTests.Analyze_EventMinusEquals_IsRejected)" {
    source := "\nimport System\n\nfunc main() {\n    AppDomain.CurrentDomain.ProcessExit -= (sender, args) => {\n        print \"exiting\"\n    }\n}"
    assert EventParseCensus(source) == ""
    analysis := EventAnalyze(source)

    assert EventCensus(analysis) == "NL317:EventRequiresOnOff@5:5+35;NL203:CannotInferType@5:45+6;"
    assert EventHasErrors(analysis) == "True"
    assert EventMessage(analysis, "EventRequiresOnOff") == "'ProcessExit' is a .NET event — it can't be unsubscribed with '-='"
    assert EventSuggestion(analysis, "EventRequiresOnOff") == "Capture the subscription when you subscribe (`sub := on AppDomain.CurrentDomain.ProcessExit handler`), then detach it with `off sub`."
}

test "020 s24 event diagnostics: the subscribe and unsubscribe rejections agree on code and span and DIFFER in both the message and the guidance — a comparison the deleted pair never made, since one read a substring and the other read nothing" {
    subscribing := EventAnalyze("\nimport System\n\nfunc main() {\n    AppDomain.CurrentDomain.ProcessExit += (sender, args) => {\n        print \"exiting\"\n    }\n}")
    unsubscribing := EventAnalyze("\nimport System\n\nfunc main() {\n    AppDomain.CurrentDomain.ProcessExit -= (sender, args) => {\n        print \"exiting\"\n    }\n}")

    assert EventCensus(unsubscribing) == EventCensus(subscribing)
    assert EventMessage(unsubscribing, "EventRequiresOnOff") != EventMessage(subscribing, "EventRequiresOnOff")
    assert EventSuggestion(unsubscribing, "EventRequiresOnOff") != EventSuggestion(subscribing, "EventRequiresOnOff")
}

test "020 s24 event diagnostics: the `on` form over the same event analyses with an EMPTY diagnostic list, which is strictly more than the deleted HasErrors claim (was EventSubscriptionTests.Analyze_OnSubscriptionToEvent_HasNoErrors)" {
    source := "\nimport System\n\nfunc main() {\n    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {\n        print \"exiting\"\n    }\n    print \"ok\"\n}"
    assert EventParseCensus(source) == ""
    analysis := EventAnalyze(source)

    assert EventCensus(analysis) == ""
    assert EventHasErrors(analysis) == "False"
}

test "020 s24 event diagnostics: `+=` between two Func fields is a real delegate combine and analyses with an EMPTY diagnostic list (was EventSubscriptionTests.Analyze_DelegateFieldPlusEquals_IsAllowed)" {
    source := "\nimport System\n\nfunc main() {\n    f: Func<int, int> = x => x + 1\n    g: Func<int, int> = x => x + 2\n    f += g\n}"
    assert EventParseCensus(source) == ""
    analysis := EventAnalyze(source)

    assert EventCensus(analysis) == ""
    assert EventHasErrors(analysis) == "False"
}

test "020 s24 event diagnostics: `off` over a plain local is rejected as NL318 at the OPERAND's single column, with guidance naming the capture form (was EventSubscriptionTests.Analyze_OffOnNonSubscription_IsRejected)" {
    source := "\nfunc main() {\n    x := 5\n    off x\n}"
    assert EventParseCensus(source) == ""
    analysis := EventAnalyze(source)

    assert EventCensus(analysis) == "NL318:InvalidEventSubscription@4:9+1;"
    assert EventHasErrors(analysis) == "True"
    assert EventMessage(analysis, "InvalidEventSubscription") == "`off` expects a subscription returned by `on`"
    assert EventSuggestion(analysis, "InvalidEventSubscription") == "Capture the subscription first (`sub := on <object>.<Event> handler`), then detach it with `off sub`."
}

test "020 s24 event diagnostics: NEITHER rejection is a ban on its keyword or its operator — a captured subscription passed to `off` analyses cleanly, and `+=` over a plain int local analyses cleanly; the deleted file asked for neither, so both diagnostics were pinned only in the rejecting direction" {
    detaching := EventAnalyze("\nimport System\n\nfunc main() {\n    sub := on AppDomain.CurrentDomain.ProcessExit (sender, args) => {\n        print \"exiting\"\n    }\n    off sub\n}")
    incrementing := EventAnalyze("\nfunc main() {\n    x := 5\n    x += 1\n}")

    assert EventCensus(detaching) == ""
    assert EventHasErrors(detaching) == "False"
    assert EventCensus(incrementing) == ""
    assert EventHasErrors(incrementing) == "False"
}
