namespace NSharpLang.CensusFlowRules.Tests

import System
import NSharpLang.Compiler.Columnar

func CensusVersions(): Version[] {
    versions := new Version[](3)
    versions[0] = new Version(8, 0, 4)
    versions[1] = new Version(10, 0, 5)
    versions[2] = new Version(10, 0, 1)
    return versions
}

// The CONSTRUCTOR half of §6: `ColumnarDeclineReason` declares
// `(siteId, message, spanStart, spanLength, memberName, sourceFileId: int = 0, hasSourceFileId: bool = false)`
// and this omits both defaults.
func CensusReason(): ColumnarDeclineReason {
    return new ColumnarDeclineReason("emit.call", "a call could not be emitted", 0, 1, "f")
}

func CensusReasonWithFileId(): ColumnarDeclineReason {
    return new ColumnarDeclineReason("emit.call", "a call could not be emitted", 0, 1, "f", 7, true)
}

test "an int? crosses an assembly boundary in both directions" {
    versions := CensusVersions()

    // A value: the highest 8.x is index 0, the highest 10.x is index 1.
    assert HighestFrameworkIndexFor(versions, 8) == 0
    assert HighestFrameworkIndexFor(versions, 10) == 1
    assert HighestFrameworkIndexViaLocal(versions, 8) == 0

    // No value: every candidate matches, so the highest overall wins.
    assert HighestFrameworkIndexFor(versions, null) == 1
    assert HighestFrameworkIndexForAnyMajor(versions) == 1
}

test "a string array matches an N#-emitted string array parameter" {
    fromLiteral := new int[](2)
    assert SummarizeRemoveArgumentsFromLiteral(fromLiteral) == 0
    assert fromLiteral[0] == 1
    assert fromLiteral[1] == 1

    args := new string[](2)
    args[0] = "pkg"
    args[1] = "-h"
    fromParameter := new int[](2)
    assert SummarizeRemoveArguments(args, fromParameter) == 0
    assert fromParameter[0] == 0
    assert fromParameter[1] == 1
}

test "a constructor's omitted defaulted arguments are filled from its own metadata" {
    // The two omitted defaults are the callee's (0, false) and not something invented at the call
    // site, which is only observable by reading them back.
    bare := CensusReason()
    assert bare.SourceFileId == 0
    assert !bare.HasSourceFileId

    supplied := CensusReasonWithFileId()
    assert supplied.SourceFileId == 7
    assert supplied.HasSourceFileId
}

test "an omitted defaulted argument is filled from the callee's metadata" {
    reason := CensusReason()
    bare := "Declined at emit.call: a call could not be emitted in 'f'."

    // The reference default and both value defaults, omitted one at a time. The formatter only
    // appends a location when the file, the line AND the column are all present, so every partly
    // omitted call has to produce the bare text — which is only true if the filled-in defaults are
    // the callee's own (null, 0, 0) and not something invented here.
    assert DetailWithNoLocation(reason) == bare
    assert DetailWithFileOnly(reason) == bare
    assert DetailWithFileAndLine(reason) == bare
    assert DetailWithEverything(reason) == "Declined at emit.call: a call could not be emitted in 'f' (a.nl:3:4)."
}
