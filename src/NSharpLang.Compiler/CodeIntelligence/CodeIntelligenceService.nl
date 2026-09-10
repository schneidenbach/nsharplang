namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler

// The public compiler-service surface is deliberately a thin N# boundary over the Core owners.
// Project loading and every query stay in N# so callers do not need a second implementation path.
class CodeIntelligenceService {
    func LoadProject(projectRoot: string): ProjectSnapshot {
        return LoadProject(projectRoot, null)
    }

    func LoadProject(projectRoot: string, sourceTextOverrides: IReadOnlyDictionary<string, string>?): ProjectSnapshot {
        config := ProjectFileParser.ParseFromDirectory(projectRoot)
        return LoadProject(projectRoot, config, sourceTextOverrides)
    }

    func LoadProject(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>? = null): ProjectSnapshot {
        compiler := new MultiFileCompiler(projectRoot, config, sourceTextOverrides)
        compiler.CompileForAnalysis()

        return new ProjectSnapshot(
            projectRoot,
            compiler.CompilationUnits,
            compiler.SemanticModels,
            compiler.AllErrors,
            compiler.SourceFiles,
            compiler.ProjectIndex,
            compiler.SourceTexts,
            compiler.PerformanceFacts,
            compiler.SystemsReport)
    }

    func GetSymbols(snapshot: ProjectSnapshot, fileName: string? = null, kind: SymbolKind? = null): List<SymbolResult> {
        if kind == null {
            return CodeIntelligenceQueries.Symbols(snapshot, fileName)
        }

        return CodeIntelligenceQueries.SymbolsOfKind(snapshot, fileName, kind.Value)
    }

    func GetOutline(snapshot: ProjectSnapshot, fileName: string): OutlineResult {
        return CodeIntelligenceQueries.Outline(snapshot, fileName)
    }

    func GetOutlineSingleFile(filePath: string): OutlineResult {
        return CodeIntelligenceQueries.OutlineSingleFile(filePath)
    }

    func GetDiagnostics(snapshot: ProjectSnapshot, fileName: string? = null): List<DiagnosticResult> {
        return CodeIntelligenceQueries.Diagnostics(snapshot, fileName)
    }

    func GetTypeAtPosition(snapshot: ProjectSnapshot, fileName: string, line: int, col: int): TypeResult? {
        return CodeIntelligenceNavigation.TypeAtPosition(snapshot, fileName, line, col)
    }

    func FindDefinition(snapshot: ProjectSnapshot, fileName: string, line: int, col: int): DefinitionResult? {
        return CodeIntelligenceQueries.Definition(snapshot, fileName, line, col)
    }

    func FindReferences(snapshot: ProjectSnapshot, fileName: string, line: int, col: int): List<ReferenceResult> {
        return CodeIntelligenceQueries.References(snapshot, fileName, line, col)
    }

    func FindStrictReferences(snapshot: ProjectSnapshot, fileName: string, line: int, col: int): List<ReferenceResult> {
        return CodeIntelligenceQueries.References(snapshot, fileName, line, col)
    }

    func GetHoverInfo(snapshot: ProjectSnapshot, fileName: string, line: int, col: int): HoverResult? {
        return CodeIntelligenceQueries.HoverInfo(snapshot, fileName, line, col)
    }

    func GetCallGraph(snapshot: ProjectSnapshot, functionName: string?, limit: int = 100): CallGraphResult {
        return CodeIntelligenceQueries.CallGraph(snapshot, functionName, limit)
    }

    func GetImplementors(snapshot: ProjectSnapshot, interfaceName: string): ImplementorsResult {
        return CodeIntelligenceQueries.Implementors(snapshot, interfaceName)
    }
}
