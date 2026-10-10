namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Collections.Generic
import NSharpLang.Cli
import NSharpLang.Cli.Commands
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar


// CENSUS §4, §5 AND §6 — THREE WAYS A CALL ACROSS AN ASSEMBLY BOUNDARY FAILED TO BIND.
//
// The compiler's own assemblies are the fixture, and deliberately so: every member called below is
// compiled by N# and read back through reflection, which is exactly the round trip the three gaps
// were in. A hand-written stub would have proved nothing, because the question is what the metadata
// says and what the reader makes of it.
//
// §4 — `Nullable<T>` DID NOT MATCH `Nullable<T>`. An `int?` argument refused an `int?` parameter,
// with the NL402 hint printing the two halves of one type as `SymbolKind?` and `Nullable<SymbolKind>`
// in the same sentence. 71 sites in the converted CLI, all one call.
//
// §5 — AN ARRAY OF A NON-NULL REFERENCE TYPE DID NOT MATCH ITSELF. An N#-emitted `string[]` parameter
// reads back as `string![]!` — oblivious, because the assembly carries no nullable context — and a
// `string[]` argument refused it, from a literal and from a parameter alike, while the same method's
// `string` and `int[]` parameters both resolved.
//
// §6 — AN OMITTED DEFAULTED ARGUMENT WAS NOT EMITTED. Analysis accepted it; emission declined,
// because the only default it could write was the null reference.

// §4 — `SelectSharedFrameworkCandidateIndex(versions: Version[], targetMajor: int?)`, called with an
// `int?` local, an `int?` parameter and a bare `null`.
func HighestFrameworkIndexFor(versions: Version[], targetMajor: int?): int {
    return CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, targetMajor)
}

func HighestFrameworkIndexForAnyMajor(versions: Version[]): int {
    return CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, null)
}

func HighestFrameworkIndexViaLocal(versions: Version[], major: int): int {
    target: int? = major
    return CompilationReferenceResolverKernels.SelectSharedFrameworkCandidateIndex(versions, target)
}

// §5 — `RemoveArgumentSummaryInto(args: string[], resultIndices: int[])`, whose `string[]` parameter
// reads back as `string![]!`. The array arrives as a literal and as a parameter.
func SummarizeRemoveArgumentsFromLiteral(indices: int[]): int {
    return RemoveCommandKernels.RemoveArgumentSummaryInto(["--help", "pkg"], indices)
}

func SummarizeRemoveArguments(args: string[], indices: int[]): int {
    return RemoveCommandKernels.RemoveArgumentSummaryInto(args, indices)
}

// §6 — `FormatDetail(reason, fileName: string? = null, line: int = 0, column: int = 0)`: a reference
// default and two VALUE defaults, omitted one at a time.
func DetailWithNoLocation(reason: ColumnarDeclineReason): string {
    return ColumnarDeclineReasonFacts.FormatDetail(reason)
}

func DetailWithFileOnly(reason: ColumnarDeclineReason): string {
    return ColumnarDeclineReasonFacts.FormatDetail(reason, "a.nl")
}

func DetailWithFileAndLine(reason: ColumnarDeclineReason): string {
    return ColumnarDeclineReasonFacts.FormatDetail(reason, "a.nl", 3)
}

func DetailWithEverything(reason: ColumnarDeclineReason): string {
    return ColumnarDeclineReasonFacts.FormatDetail(reason, "a.nl", 3, 4)
}

// CENSUS §CONV/3 — `null` DID NOT REACH A REFLECTED NULLABLE GENERIC-INTERFACE PARAMETER.
//
// `CodeIntelligenceDiagnostics.FromCompilerError(error, projectRoot, sourceTexts)` is compiled by N#
// and its third parameter is declared `IReadOnlyDictionary<string, string>?`. Read back through
// reflection the annotation is gone — an N#-emitted assembly carries no nullable context, so the
// parameter is OBLIVIOUS, `IReadOnlyDictionary<string!, string!>!` — and a `null` argument was
// refused with NL402 "No overload of 'FromCompilerError' accepts 3 arguments with these types" (11
// sites in the converted CLI), while the same call to a SOURCE-declared method bound.
//
// The `null` arm of assignability asks one question — is `null` one of this type's values — and the
// predicate behind it answered FALSE for every closed generic instantiation and for every oblivious
// shell. A closed instantiation now answers from its DEFINITION and the shell is transparent, which
// is what these two calls prove across a real assembly boundary.
//
// A NULL DICTIONARY IS NOT AN EMPTY ONE, and that is the contract being exercised rather than just
// the binding: the callee skips the snippet lookup entirely when the dictionary is null, so a
// blank-but-present snippet survives, where an empty dictionary would blank it.
func DiagnosticFromErrorWithoutSources(error: CompilerError, projectRoot: string): DiagnosticResult {
    return CodeIntelligenceDiagnostics.FromCompilerError(error, projectRoot, null)
}

func DiagnosticFromErrorWithSources(error: CompilerError, projectRoot: string, sourceTexts: IReadOnlyDictionary<string, string>?): DiagnosticResult {
    return CodeIntelligenceDiagnostics.FromCompilerError(error, projectRoot, sourceTexts)
}
