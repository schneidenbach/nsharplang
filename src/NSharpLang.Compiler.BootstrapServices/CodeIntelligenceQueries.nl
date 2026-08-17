namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


// EVERY QUESTION `nlc query` AND THE LANGUAGE SERVER CAN ASK OF A PROJECT SNAPSHOT.
//
// The projections, the walks and the result shapes were already N# — `CodeIntelligenceDiagnostics`,
// `CodeIntelligenceDeclarationProjection`, `CodeIntelligenceCallGraph`,
// `CodeIntelligenceImplementors`, `CodeIntelligenceReferenceResults` — and what stayed in C# was the
// last thing that could not cross: the SNAPSHOT READS. Nine of them per question, on a type the
// owners' assembly could not reference. With `ProjectSnapshot` itself in N#, the questions come
// home and `CodeIntelligenceService` keeps only what genuinely cannot move.
//
// WHAT GENUINELY CANNOT MOVE IS EXACTLY ONE THING, AND IT IS A DIRECTION OF DEPENDENCY RATHER THAN
// A SHAPE. `LoadProject` constructs a `MultiFileCompiler`, which lives in the assembly that DEPENDS
// on this one; a reference back would be a cycle. So the service is the project LOADER and nothing
// else, and every ANSWER is here.
//
// THE SYMBOL FILTER IS TWO FILTERS IN A FIXED ORDER AND THAT ORDER IS OBSERVABLE. The FILE filter
// runs per unit, before projection, so a file that does not match is never walked; the KIND filter
// runs once at the end, over the whole result, because a kind is a property of the projected symbol
// rather than of the declaration it came from. Swapping them would change nothing about the answer
// and a great deal about the cost.
//
// AN OUTLINE HAS A FAST PATH THAT SKIPS ANALYSIS ENTIRELY. `OutlineSingleFile` parses one file with
// the recovery parser and never loads a project, because a document outline is a syntactic question
// and the editor asks it on every keystroke. It reports the path it was GIVEN, not a relative one,
// because it has no project root to be relative to.
//
// HOVER IS THE ONLY ANSWER ASSEMBLED FROM TWO OTHERS, and the merge order is the policy: the
// DEFINITION's kind and name beat the TYPE's, because a definition is a stronger statement about
// what the user is pointing at than an inferred type is. The documentation is fetched last and only
// when the definition site is known, because the source text can only be read once the absolute
// path is resolved — and a definition on line 1 is a synthetic position rather than a real site, so
// it is not asked for.
class CodeIntelligenceQueries {

    // ── Symbols ─────────────────────────────────────────────────────────
    // TWO ARITIES RATHER THAN ONE NULLABLE ENUM, and the reason is a measured emitter limit rather
    // than a preference: a `SymbolKind?` STATIC PARAMETER declines at
    // `emit.declaration.method-param`. The service's public signature keeps its optional
    // `SymbolKind?` and chooses the arity, which is a nullable-lowering adapter and not a decision —
    // both arms are this file's, and the FILTER itself never leaves N#.
    static func Symbols(snapshot: ProjectSnapshot, queryFile: string?): List<SymbolResult> {
        results := new List<SymbolResult>()

        for entry in snapshot.CompilationUnits {
            if queryFile != null && !CodeIntelligenceResultKernels.MatchesFilePath(entry.Key, queryFile) {
                continue
            }

            relativeFile := CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, entry.Key)
            projected := CodeIntelligenceDeclarationProjection.Symbols(entry.Value.Declarations, relativeFile)
            projectedIndex := 0
            while projectedIndex < projected.Count {
                results.Add(projected[projectedIndex])
                projectedIndex = projectedIndex + 1
            }
        }

        return results
    }

    // The KIND filter runs ONCE at the end, over the whole result, because a kind is a property of
    // the projected symbol rather than of the declaration it came from.
    static func SymbolsOfKind(snapshot: ProjectSnapshot, queryFile: string?, kind: SymbolKind): List<SymbolResult> {
        return CodeIntelligenceSymbolKernels.FilterSymbolsByKind(Symbols(snapshot, queryFile), kind)
    }

    // ── Outline ─────────────────────────────────────────────────────────
    static func Outline(snapshot: ProjectSnapshot, queryFile: string): OutlineResult {
        unitMatch := CodeIntelligenceNavigation.FindCompilationUnit(snapshot, queryFile)
        cu := unitMatch.Unit
        if cu == null {
            return new OutlineResult(queryFile, new string[](0), new OutlineEntry[](0))
        }

        relativeFile := CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, unitMatch.FilePath)
        return new OutlineResult(relativeFile, ImportNamespaces(cu), CodeIntelligenceDeclarationProjection.OutlineEntries(cu.Declarations))
    }

    static func OutlineSingleFile(filePath: string): OutlineResult {
        source := File.ReadAllText(filePath)
        parseResult := ColumnarParserRecovery.ParseFileAst(source, filePath)
        cu := parseResult.CompilationUnit
        if cu == null {
            return new OutlineResult(filePath, new string[](0), new OutlineEntry[](0))
        }

        return new OutlineResult(filePath, ImportNamespaces(cu), CodeIntelligenceDeclarationProjection.OutlineEntries(cu.Declarations))
    }

    static func ImportNamespaces(cu: CompilationUnit): string[] {
        imports := cu.Imports
        namespaces := new string[](imports.Count)
        index := 0
        while index < imports.Count {
            namespaces[index] = imports[index].Namespace
            index = index + 1
        }

        return namespaces
    }

    // ── Diagnostics ─────────────────────────────────────────────────────
    // The snapshot's own collections cross unchanged; nothing is rebuilt per call, which is what the
    // published `IReadOnlyDictionary` catalog row bought on the language server's publish path.
    static func Diagnostics(snapshot: ProjectSnapshot, queryFile: string?): List<DiagnosticResult> {
        return CodeIntelligenceDiagnostics.Build(snapshot.ProjectRoot, snapshot.AllErrors, snapshot.SourceFiles, snapshot.CompilationUnits, snapshot.SourceTexts, queryFile)
    }

    // ── Definition and references ───────────────────────────────────────
    static func Definition(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): DefinitionResult? {
        declaration := CodeIntelligenceNavigation.DefinitionSymbolAtPosition(snapshot, queryFile, line, col)
        if declaration == null {
            return null
        }

        return CodeIntelligenceReferenceResults.ToDefinition(snapshot.ProjectRoot, declaration)
    }

    // BOTH REFERENCE ENTRY POINTS ARE THE SAME ANSWER, and they are two names because the CLI has
    // two commands. Each refuses before it looks when the snapshot carries no binding map at all —
    // "the project was never analysed" and "this symbol has no references" are different facts, and
    // the empty list is only the second one.
    static func References(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): List<ReferenceResult> {
        unitMatch := CodeIntelligenceNavigation.FindCompilationUnit(snapshot, queryFile)
        bindings := snapshot.Bindings
        if unitMatch.Unit == null || bindings == null {
            return new List<ReferenceResult>()
        }

        declaration := CodeIntelligenceNavigation.StrictReferenceDeclaration(snapshot, unitMatch.FilePath, line, col)
        if declaration == null {
            return new List<ReferenceResult>()
        }

        return CodeIntelligenceReferenceResults.FromDeclaration(snapshot.ProjectRoot, snapshot.SourceTexts, bindings, declaration)
    }

    // ── Hover ───────────────────────────────────────────────────────────
    static func HoverInfo(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): HoverResult? {
        typeResult := CodeIntelligenceNavigation.TypeAtPosition(snapshot, queryFile, line, col)
        definition := Definition(snapshot, queryFile, line, col)
        if typeResult == null && definition == null {
            return null
        }

        kindCandidate: string? = null
        nameCandidate: string? = null
        definedIn: string? = null
        definitionLine := 0
        if definition != null {
            kindCandidate = definition.Kind
            nameCandidate = definition.Name
            definedIn = definition.File
            definitionLine = definition.Line
        }

        resolvedType: string? = null
        if typeResult != null {
            if kindCandidate == null {
                kindCandidate = typeResult.Kind
            }

            if nameCandidate == null {
                nameCandidate = typeResult.Name
            }

            resolvedType = typeResult.ResolvedType
        }

        kind := kindCandidate ?? "unknown"
        name := nameCandidate ?? "unknown"

        signature := CodeIntelligenceSignatureKernels.GetFallbackSignatureText(kind, name, resolvedType)

        documentation: string? = null
        if definedIn != null && definitionLine > 1 {
            docPath := CodeIntelligenceSourceDoor.ResolveAbsolutePath(UnitPaths(snapshot), definedIn)
            if docPath != null {
                documentation = CodeIntelligenceSourceDoor.DocComment(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, docPath), definitionLine)
            }
        }

        return new HoverResult(signature, documentation, definedIn, kind)
    }

    // ── Call graph and implementors ─────────────────────────────────────
    // Both walk every unit and both need the unit paired with its RELATIVE file name, so the pairing
    // loop is written once and the two builders differ only in what they are asked.
    static func CallGraph(snapshot: ProjectSnapshot, functionName: string?, limit: int): CallGraphResult {
        units := new List<CompilationUnit>()
        relativeFiles := new List<string>()
        CollectUnits(snapshot, units, relativeFiles)
        return CodeIntelligenceCallGraph.Build(units, relativeFiles, functionName, limit)
    }

    static func Implementors(snapshot: ProjectSnapshot, interfaceName: string): ImplementorsResult {
        units := new List<CompilationUnit>()
        relativeFiles := new List<string>()
        CollectUnits(snapshot, units, relativeFiles)
        return CodeIntelligenceImplementors.Build(units, relativeFiles, interfaceName)
    }

    // The C# handed `snapshot.CompilationUnits.Keys` straight to the door. The key sequence of an
    // `IReadOnlyDictionary<string, V>` reads as `IEnumerable<string?>` here, so the paths are
    // materialised in dictionary order — the same set the door walked, in the same order, which is
    // what "the first absolute path whose tail matches" depends on.
    static func UnitPaths(snapshot: ProjectSnapshot): List<string> {
        paths := new List<string>()
        for entry in snapshot.CompilationUnits {
            paths.Add(entry.Key)
        }

        return paths
    }

    static func CollectUnits(snapshot: ProjectSnapshot, units: List<CompilationUnit>, relativeFiles: List<string>) {
        for entry in snapshot.CompilationUnits {
            units.Add(entry.Value)
            relativeFiles.Add(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, entry.Key))
        }
    }
}
