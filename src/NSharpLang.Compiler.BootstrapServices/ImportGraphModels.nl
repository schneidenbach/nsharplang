namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

public enum ImportVisitState {
    Visiting,
    Visited
}

public class ImportEdge {
    SourceFile: string
    TargetFile: string
    ImportPath: string
    Line: int
    Column: int
    Length: int

    constructor(sourceFile: string, targetFile: string, importPath: string, line: int, column: int, length: int) {
        this.SourceFile = sourceFile
        this.TargetFile = targetFile
        this.ImportPath = importPath
        this.Line = line
        this.Column = column
        this.Length = length
    }
}

public class FileImportGraphEntry {
    SourceFile: string
    ImportPath: string
    Line: int
    Column: int
    Length: int

    constructor(sourceFile: string, importPath: string, line: int, column: int, length: int) {
        this.SourceFile = sourceFile
        this.ImportPath = importPath
        this.Line = line
        this.Column = column
        this.Length = length
    }
}

public class ImportGraphBuildResult {
    EdgesByFile: Dictionary<string, List<ImportEdge> >
    ResolvedDiagnosticKeys: List<string>

    constructor(edgesByFile: Dictionary<string, List<ImportEdge> >, resolvedDiagnosticKeys: List<string>) {
        this.EdgesByFile = edgesByFile
        this.ResolvedDiagnosticKeys = resolvedDiagnosticKeys
    }
}

public class ImportGraphBuilder {
    public static func Build(
        sourceFiles: List<string>,
        fileImports: List<FileImportGraphEntry>,
        projectRoot: string): ImportGraphBuildResult {
        graph := new Dictionary<string, List<ImportEdge> >(StringComparer.OrdinalIgnoreCase)
        resolvedDiagnosticKeys := new List<string>()
        sourceFileByFullPath := BuildSourceFileMap(sourceFiles)

        i := 0
        while i < fileImports.Count {
            fileImport := fileImports[i]
            resolver := new FileResolver(projectRoot, fileImport.SourceFile)
            resolvedPath := ResolveImportedCompilationUnitPath(resolver, fileImport.ImportPath, sourceFileByFullPath)
            if resolvedPath != null {
                edges := new List<ImportEdge>()
                if !graph.TryGetValue(fileImport.SourceFile, out edges) {
                    edges = new List<ImportEdge>()
                    graph[fileImport.SourceFile] = edges
                }

                resolvedDiagnosticKeys.Add(BuildFileImportDiagnosticKey(fileImport.SourceFile, fileImport.Line, fileImport.Column))
                edges.Add(new ImportEdge(
                    fileImport.SourceFile,
                    resolvedPath,
                    fileImport.ImportPath,
                    fileImport.Line,
                    fileImport.Column,
                    fileImport.Length))
            }

            i = i + 1
        }

        return new ImportGraphBuildResult(graph, resolvedDiagnosticKeys)
    }

    static func BuildSourceFileMap(sourceFiles: List<string>): Dictionary<string, string> {
        sourceFileByFullPath := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < sourceFiles.Count {
            fullPath := Path.GetFullPath(sourceFiles[i])
            existing := ""
            if !sourceFileByFullPath.TryGetValue(fullPath, out existing) {
                sourceFileByFullPath[fullPath] = sourceFiles[i]
            }

            i = i + 1
        }

        return sourceFileByFullPath
    }

    static func ResolveImportedCompilationUnitPath(
        resolver: FileResolver,
        importPath: string,
        sourceFileByFullPath: Dictionary<string, string>): string? {
        resolvedPath := Path.GetFullPath(resolver.ResolveFilePath(importPath))
        sourceFile := ""
        if sourceFileByFullPath.TryGetValue(resolvedPath, out sourceFile) {
            return sourceFile
        }

        return null
    }

    public static func BuildFileImportDiagnosticKey(filePath: string, line: int, column: int): string {
        return Path.GetFullPath(filePath) + ":" + line.ToString() + ":" + column.ToString()
    }
}

public class ImportGraphDiagnosticSuppressor {
    public static func ShouldSuppressAnalyzerDiagnostic(
        error: CompilerError,
        filesInReportedImportCycles: HashSet<string>,
        resolvedFileImportDiagnosticKeys: HashSet<string>): bool {
        if error.Code == ErrorCode.CircularImport &&
            error.FileName != null &&
            filesInReportedImportCycles.Contains(Path.GetFullPath(error.FileName)) {
            return true
        }

        if error.Code == ErrorCode.ImportNotFound &&
            error.FileName != null &&
            resolvedFileImportDiagnosticKeys.Contains(ImportGraphBuilder.BuildFileImportDiagnosticKey(error.FileName, error.Line, error.Column)) {
            return true
        }

        return false
    }
}

public class ImportTraversalFrame {
    SourceFile: string
    Edges: List<ImportEdge>
    NextEdgeIndex: int

    constructor(sourceFile: string, edges: List<ImportEdge>) {
        this.SourceFile = sourceFile
        this.Edges = edges
        this.NextEdgeIndex = 0
    }
}

public class ImportCycle {
    Edge: ImportEdge
    Path: List<string>
    DisplayPath: string
    CanonicalKey: string

    constructor(edge: ImportEdge, path: List<string>, displayPath: string, canonicalKey: string) {
        this.Edge = edge
        this.Path = path
        this.DisplayPath = displayPath
        this.CanonicalKey = canonicalKey
    }
}

public class ImportGraphCycleDetector {
    public static func Detect(
        sourceFiles: List<string>,
        edgesByFile: Dictionary<string, List<ImportEdge> >,
        projectRoot: string,
        maxDisplayedNodes: int): List<ImportCycle> {
        orderedSourceFiles := CopySortedStrings(sourceFiles)
        visitState := new Dictionary<string, ImportVisitState>(StringComparer.OrdinalIgnoreCase)
        cycles := new List<ImportCycle>()
        reportedCycleKeys := new HashSet<string>(StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < orderedSourceFiles.Count {
            VisitImportGraph(
                orderedSourceFiles[i],
                edgesByFile,
                projectRoot,
                maxDisplayedNodes,
                visitState,
                cycles,
                reportedCycleKeys)
            i = i + 1
        }

        return cycles
    }

    static func VisitImportGraph(
        sourceFile: string,
        edgesByFile: Dictionary<string, List<ImportEdge> >,
        projectRoot: string,
        maxDisplayedNodes: int,
        visitState: Dictionary<string, ImportVisitState>,
        cycles: List<ImportCycle>,
        reportedCycleKeys: HashSet<string>) {
        existingState := ImportVisitState.Visiting
        if visitState.TryGetValue(sourceFile, out existingState) && existingState == ImportVisitState.Visited {
            return
        }

        pathStack := new List<string>()
        pathIndexByFile := new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        traversalStack := new List<ImportTraversalFrame>()

        visitState[sourceFile] = ImportVisitState.Visiting
        pathIndexByFile[sourceFile] = 0
        pathStack.Add(sourceFile)
        traversalStack.Add(new ImportTraversalFrame(sourceFile, GetSortedImportEdges(sourceFile, edgesByFile)))

        while traversalStack.Count > 0 {
            frame := traversalStack[traversalStack.Count - 1]
            if frame.NextEdgeIndex >= frame.Edges.Count {
                traversalStack.RemoveAt(traversalStack.Count - 1)
                pathIndexByFile.Remove(frame.SourceFile)
                pathStack.RemoveAt(pathStack.Count - 1)
                visitState[frame.SourceFile] = ImportVisitState.Visited
            } else {
                edge := frame.Edges[frame.NextEdgeIndex]
                frame.NextEdgeIndex = frame.NextEdgeIndex + 1

                cycleStartIndex := 0
                if pathIndexByFile.TryGetValue(edge.TargetFile, out cycleStartIndex) {
                    cyclePath := CopyCyclePath(pathStack, cycleStartIndex, edge.TargetFile)
                    canonicalKey := CanonicalizeCycle(cyclePath)
                    if reportedCycleKeys.Add(canonicalKey) {
                        cycles.Add(new ImportCycle(
                            edge,
                            cyclePath,
                            FormatCyclePath(cyclePath, projectRoot, maxDisplayedNodes),
                            canonicalKey))
                    }
                } else {
                    targetState := ImportVisitState.Visiting
                    alreadyVisited := visitState.TryGetValue(edge.TargetFile, out targetState) && targetState == ImportVisitState.Visited
                    if !alreadyVisited {
                        visitState[edge.TargetFile] = ImportVisitState.Visiting
                        pathIndexByFile[edge.TargetFile] = pathStack.Count
                        pathStack.Add(edge.TargetFile)
                        traversalStack.Add(new ImportTraversalFrame(edge.TargetFile, GetSortedImportEdges(edge.TargetFile, edgesByFile)))
                    }
                }
            }
        }
    }

    static func GetSortedImportEdges(
        sourceFile: string,
        edgesByFile: Dictionary<string, List<ImportEdge> >): List<ImportEdge> {
        sourceEdges := new List<ImportEdge>()
        if !edgesByFile.TryGetValue(sourceFile, out sourceEdges) {
            return new List<ImportEdge>()
        }

        result := new List<ImportEdge>(sourceEdges.Count)
        i := 0
        while i < sourceEdges.Count {
            result.Add(sourceEdges[i])
            i = i + 1
        }

        SortEdgesByTargetFile(result)
        return result
    }

    static func CopyCyclePath(pathStack: List<string>, startIndex: int, targetFile: string): List<string> {
        result := new List<string>()
        i := startIndex
        while i < pathStack.Count {
            result.Add(pathStack[i])
            i = i + 1
        }

        result.Add(targetFile)
        return result
    }

    static func FormatCyclePath(cyclePath: List<string>, projectRoot: string, maxDisplayedNodes: int): string {
        displayNodes := new List<string>()
        i := 0
        while i < cyclePath.Count {
            displayNodes.Add(GetProjectRelativeDisplayPath(projectRoot, cyclePath[i]))
            i = i + 1
        }

        if displayNodes.Count <= maxDisplayedNodes {
            return string.Join(" -> ", displayNodes)
        }

        headCount := 6
        tailCount := 3
        omittedCount := displayNodes.Count - headCount - tailCount
        boundedNodes := new List<string>()

        i = 0
        while i < headCount && i < displayNodes.Count {
            boundedNodes.Add(displayNodes[i])
            i = i + 1
        }

        boundedNodes.Add("... (" + omittedCount.ToString() + " more imports)")

        tailStart := displayNodes.Count - tailCount
        if tailStart < headCount {
            tailStart = headCount
        }

        i = tailStart
        while i < displayNodes.Count {
            boundedNodes.Add(displayNodes[i])
            i = i + 1
        }

        return string.Join(" -> ", boundedNodes)
    }

    static func GetProjectRelativeDisplayPath(projectRoot: string, filePath: string): string {
        try {
            relativePath := Path.GetRelativePath(projectRoot, filePath)
            return relativePath.Replace('\\', '/')
        } catch {
            return Path.GetFileName(filePath) ?? filePath
        }
    }

    static func CanonicalizeCycle(cyclePath: List<string>): string {
        nodeCount := cyclePath.Count - 1
        if nodeCount <= 0 {
            return ""
        }

        normalizedNodes := new List<string>(nodeCount)
        i := 0
        while i < nodeCount {
            normalizedNodes.Add(Path.GetFullPath(cyclePath[i]))
            i = i + 1
        }

        best := BuildCycleRotationKey(normalizedNodes, 0)
        rotation := 1
        while rotation < normalizedNodes.Count {
            candidate := BuildCycleRotationKey(normalizedNodes, rotation)
            if String.Compare(candidate, best, StringComparison.OrdinalIgnoreCase) < 0 {
                best = candidate
            }

            rotation = rotation + 1
        }

        return best
    }

    static func BuildCycleRotationKey(nodes: List<string>, startIndex: int): string {
        parts := new List<string>(nodes.Count)
        i := 0
        while i < nodes.Count {
            index := startIndex + i
            if index >= nodes.Count {
                index = index - nodes.Count
            }

            parts.Add(nodes[index])
            i = i + 1
        }

        return string.Join("->", parts)
    }

    static func CopySortedStrings(sourceFiles: List<string>): List<string> {
        result := new List<string>(sourceFiles.Count)
        i := 0
        while i < sourceFiles.Count {
            result.Add(sourceFiles[i])
            i = i + 1
        }

        SortStringsOrdinalIgnoreCase(result)
        return result
    }

    static func SortStringsOrdinalIgnoreCase(values: List<string>) {
        i := 1
        while i < values.Count {
            current := values[i]
            j := i - 1
            while j >= 0 && String.Compare(values[j], current, StringComparison.OrdinalIgnoreCase) > 0 {
                values[j + 1] = values[j]
                j = j - 1
            }

            values[j + 1] = current
            i = i + 1
        }
    }

    static func SortEdgesByTargetFile(edges: List<ImportEdge>) {
        i := 1
        while i < edges.Count {
            current := edges[i]
            j := i - 1
            while j >= 0 && String.Compare(edges[j].TargetFile, current.TargetFile, StringComparison.OrdinalIgnoreCase) > 0 {
                edges[j + 1] = edges[j]
                j = j - 1
            }

            edges[j + 1] = current
            i = i + 1
        }
    }
}
