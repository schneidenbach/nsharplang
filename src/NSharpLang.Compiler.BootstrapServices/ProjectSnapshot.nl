namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Performance


// THE IMMUTABLE ANSWER-SHEET EVERY CODE-INTELLIGENCE QUESTION IS ASKED AGAINST.
//
// `CodeIntelligenceService.LoadProject` compiles a project for analysis and freezes the result
// here; the CLI's `nlc query`, the daemon, the playground and the language server's
// `DocumentManager` then ask their questions of this object and of nothing else. It holds no
// policy at all — it is nine readings of one compilation, plus one convenience accessor.
//
// THE TENTH MEMBER IS GONE, AND ITS DELETION IS WHY THIS TYPE COULD MOVE. Until slice 21 the
// snapshot also carried `public Analyzer SharedAnalyzer`, and the C# `Analyzer` lives in the
// assembly that DEPENDS on this one, so a reference the other way would have been a cycle. It was
// declared once, assigned once and READ NOWHERE: a dead carrier, not a dependency. A NAME-based
// sweep could not see that, because `MultiFileCompiler` declares a `SharedAnalyzer` too and the two
// members share one name — the reads a grep finds are all of the other one. It took a
// RECEIVER-TYPED census, over IL rather than text, to tell them apart.
//
// THE NAME, THE NAMESPACE AND EVERY SIGNATURE ARE THE C#'s, MEMBER FOR MEMBER, so every consumer
// binds to this type with no source change: `DocumentManager`, `BatchQueryRunner`, `QueryCommand`,
// `DaemonServer`, the rename/references/prepare-rename handlers, `CompletionEngine`, the playground
// and the tests all keep their text.
//
// `Index` IS NULLABLE AND `Bindings` ANSWERS NULL THROUGH IT. A snapshot built without a full
// analysis pass — which is what the tests do — has no `ProjectIndex` and therefore no bindings, and
// that is a legitimate state rather than an error. `SystemsReport` instead SUBSTITUTES an empty
// report for a missing one, so no JSON writer has to special-case a null.
//
// `sourceTexts` IS REQUIRED WHERE THE C# DEFAULTED IT, AND THAT IS A MEASURED CONSEQUENCE RATHER
// THAN A PREFERENCE. The C# wrote `sourceTexts ?? new Dictionary<string, string>()`; N# cannot
// spell that, because `Dictionary<K, V>` does not widen to `IReadOnlyDictionary<K, V>` in ANY
// position — return, argument or field assignment — while `List<T>` widens to `IReadOnlyList<T>` in
// all three. So a read-only dictionary can be RECEIVED here but never CREATED here, and the honest
// resolution is to make the caller say it has none rather than to fake one. Exactly one call site
// relied on the default and it is a test.
class ProjectSnapshot {
    projectRootValue: string
    compilationUnitsValue: IReadOnlyDictionary<string, CompilationUnit>
    semanticModelsValue: IReadOnlyDictionary<string, SemanticModel>
    allErrorsValue: IReadOnlyList<CompilerError>
    sourceFilesValue: IReadOnlyList<string>
    sourceTextsValue: IReadOnlyDictionary<string, string>
    performanceFactsValue: PerformanceFactStore?
    systemsReportValue: SystemsReport
    indexValue: ProjectIndex?

    ProjectRoot: string => projectRootValue
    CompilationUnits: IReadOnlyDictionary<string, CompilationUnit> => compilationUnitsValue
    SemanticModels: IReadOnlyDictionary<string, SemanticModel> => semanticModelsValue
    AllErrors: IReadOnlyList<CompilerError> => allErrorsValue
    SourceFiles: IReadOnlyList<string> => sourceFilesValue
    SourceTexts: IReadOnlyDictionary<string, string> => sourceTextsValue
    PerformanceFacts: PerformanceFactStore? => performanceFactsValue
    SystemsReport: SystemsReport => systemsReportValue

    // The project-level semantic index: merged BindingMap plus type-declaration-to-file mapping.
    // Null when the snapshot was constructed without a full analysis pass (e.g. in tests).
    Index: ProjectIndex? => indexValue

    // Convenience accessor for the merged BindingMap. Null when Index is null.
    Bindings: BindingMap? => IndexBindings(indexValue)

    constructor(projectRoot: string, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, semanticModels: IReadOnlyDictionary<string, SemanticModel>, allErrors: IReadOnlyList<CompilerError>, sourceFiles: IReadOnlyList<string>, index: ProjectIndex?, sourceTexts: IReadOnlyDictionary<string, string>, performanceFacts: PerformanceFactStore? = null, systemsReport: SystemsReport? = null) {
        projectRootValue = projectRoot
        compilationUnitsValue = compilationUnits
        semanticModelsValue = semanticModels
        allErrorsValue = allErrors
        sourceFilesValue = sourceFiles
        indexValue = index
        sourceTextsValue = sourceTexts
        performanceFactsValue = performanceFacts
        systemsReportValue = systemsReport ?? ProjectSnapshotDefaults.EmptySystemsReport()
    }

    // The null-conditional `Index?.Bindings` the C# wrote, spelled as a call because a getter is an
    // expression here. A snapshot with no index has no bindings, and that answer is null rather than
    // an empty map: `FindReferences` distinguishes "there is no binding information" from "there are
    // no references", and an empty map would collapse the two.
    static func IndexBindings(index: ProjectIndex?): BindingMap? {
        if index == null {
            return null
        }

        return index.Bindings
    }
}

// THE SUBSTITUTED DEFAULT LIVES OUTSIDE THE SNAPSHOT, AND THE REASON IS A LANGUAGE FACT WORTH
// STATING: a property whose NAME equals its TYPE's name shadows that type inside its own class, so
// `SystemsReport.Empty(...)` written inside `ProjectSnapshot` resolves to the PROPERTY and the emit
// declines. The C# `public SystemsReport SystemsReport { get; }` is unambiguous and the property
// name is part of the signature this type must keep, so the static call moves out rather than the
// property being renamed.
class ProjectSnapshotDefaults {
    static func EmptySystemsReport(): SystemsReport {
        return SystemsReport.Empty(null)
    }
}
