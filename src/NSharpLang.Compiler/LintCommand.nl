namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import NSharpLang.Cli
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

// The lint command owns the complete discovery -> analysis -> lint -> output route.
//
// LINT ANALYSES THE PROJECT BEFORE IT LINTS, AND TWO RULES EXIST ONLY BECAUSE OF IT. NL010 ("this
// import is not used") and NL002 ("this name has no import") are answered by what a source unit
// BOUND — which namespace supplied each name it wrote — and those facts live on the unit the
// ANALYZER walked, not on one that was merely parsed. A lint command that parsed each source on its
// own reported SILENCE for both: `nlc check` printed two NL010 rows for a source with two dead
// imports and `nlc lint` on the same source said "no issues". `nlc fix` already loads the project
// for exactly this reason; lint now reads the same analysed units, so the three commands report one
// set of rules rather than three different subsets of it.
//
// THE PARSE GATE STAYS IN FRONT OF THE ANALYSIS AND THAT ORDER IS A CONTRACT. A source whose text
// the parser refuses (NL111's nesting bound, for one) is reported as a `PARSE` row and never linted,
// and that answer must not depend on whether a project snapshot could be loaded at all. Analysis is
// therefore best-effort: a project that fails to load leaves every source on its parsed unit, which
// is exactly what this command did before — the binding rules go quiet, and nothing else changes.
class LintCommand {
    static func Execute(args: string[]): int {
        options := LintCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            Console.WriteLine(LintCommandKernels.GetHelpText())
            return 0
        }

        useJson := LintCommandKernels.GetEffectiveOutputMode(options.UseText, options.UseJson) == 1
        projectRoot := CommandOutputKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory())
        positionalFiles := LintCommandKernels.GetFileArgs(args)

        if !Directory.Exists(projectRoot) {
            return EmitError(useJson, LintCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot), projectRoot)
        }

        sw := Stopwatch.StartNew()
        try {
            sourcePaths := DiscoverSourcePaths(projectRoot, positionalFiles)
            if sourcePaths.Count == 0 {
                if useJson {
                    Console.Write(OutputFormatter.LintToJson(new List<DiagnosticResult>(), projectRoot, 0))
                    return 0
                }

                Console.WriteLine(LintCommandKernels.GetNoFilesFoundMessage())
                return 0
            }

            analyzedUnits := AnalyzedUnitsFor(projectRoot)
            allDiagnostics := new List<DiagnosticResult>()
            lintedFileCount := 0
            hadErrors := false

            for sourcePath in sourcePaths {
                outcome := LintOneSource(projectRoot, sourcePath, useJson, analyzedUnits)
                allDiagnostics.AddRange(outcome.Diagnostics)
                for message in outcome.Messages {
                    Console.Error.WriteLine(message)
                }

                if outcome.Linted {
                    lintedFileCount = lintedFileCount + 1
                }

                if outcome.HadError {
                    hadErrors = true
                }
            }

            summary := OutputFormatter.SummarizeDiagnostics(allDiagnostics)
            if useJson {
                Console.Write(OutputFormatter.LintToJson(allDiagnostics, projectRoot, lintedFileCount))
            } else if allDiagnostics.Count == 0 {
                Console.Error.WriteLine(LintCommandKernels.GetNoIssuesMessage(
                    lintedFileCount,
                    ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)
                ))
            } else {
                writer := Console.Error
                writer.Write(OutputFormatter.DiagnosticsToText(allDiagnostics))
                writer.WriteLine(LintCommandKernels.GetLintedInMessage(ProgramCommandKernels.FormatElapsedMilliseconds(sw.ElapsedMilliseconds)))
            }

            return LintCommandKernels.GetExitCode(hadErrors, summary.Errors)
        } catch ex: Exception {
            return EmitError(useJson, LintCommandKernels.GetFailedMessage(ex.Message), projectRoot)
        }
    }

    // ONE SOURCE, PARSED THEN LINTED. The two output modes disagree about where a failure goes and
    // the disagreement is the published contract: `--json` turns an unreadable source or a parse
    // refusal into a `LINT` or `PARSE` result row so a machine reading the envelope sees it, while
    // `--text` writes a sentence to stderr and prints no row at all. Both are collected here rather
    // than written from inside the walk, so the caller keeps one place that touches the console.
    private static func LintOneSource(
        projectRoot: string,
        sourcePath: string,
        useJson: bool,
        analyzedUnits: IReadOnlyDictionary<string, CompilationUnit>?
    ): LintSourceOutcome {
        outcome := new LintSourceOutcome()
        relativePath := LintCommandKernels.GetRelativePath(projectRoot, sourcePath)

        if !File.Exists(sourcePath) {
            outcome.HadError = true
            if useJson {
                outcome.Diagnostics.Add(LintCommandKernels.ToCommandDiagnosticResult(
                    LintCommandKernels.GetLintDiagnosticCode(),
                    CommandOutputKernels.GetFileNotFoundMessage(relativePath),
                    relativePath
                ))
            } else {
                outcome.Messages.Add(CommandOutputKernels.GetFileNotFoundMessage(sourcePath))
            }

            return outcome
        }

        try {
            source := File.ReadAllText(sourcePath)
            parseResult := ColumnarParserRecovery.ParseFileAst(source, sourcePath)
            parseErrors := CompilerErrorSeverityFilter.Filter(parseResult.Errors, ErrorSeverity.Error)

            if parseErrors.Count > 0 {
                outcome.HadError = true
                if useJson {
                    for parseError in parseErrors {
                        outcome.Diagnostics.Add(LintCommandKernels.ToParseDiagnosticResult(
                            parseError,
                            relativePath,
                            CodeIntelligenceSourceDoor.SourceLine(source, parseError.Line)
                        ))
                    }
                } else {
                    outcome.Messages.Add(LintCommandKernels.GetParseErrorsMessage(
                        sourcePath,
                        LintCommandKernels.JoinParseErrorMessages(CompilerErrorMessages(parseResult.Errors))
                    ))
                }

                return outcome
            }

            // THE ANALYSED UNIT IS PREFERRED AND THE PARSED ONE IS THE FALLBACK. A source the project
            // does not list — a positional argument outside it, or a directory with no `project.yml`
            // the analysis could read — is still linted for every rule that reads the tree alone.
            unit := AnalyzedUnitFor(analyzedUnits, sourcePath) ?? parseResult.CompilationUnit
            if unit == null {
                return outcome
            }

            linter := new Linter(LinterConfig.FromEditorConfig(LintCommandKernels.GetFileDirectory(projectRoot, sourcePath)))
            diagnostics := linter.Lint(unit, sourcePath, source)
            outcome.Linted = true

            for diagnostic in diagnostics {
                location := diagnostic.Location
                snippet := CodeIntelligenceSourceDoor.SourceLine(source, location.Line)
                outcome.Diagnostics.Add(LintCommandKernels.ToLintDiagnosticResult(diagnostic, relativePath, snippet))
            }
        } catch ex: Exception {
            outcome.HadError = true
            if useJson {
                outcome.Diagnostics.Add(LintCommandKernels.ToCommandDiagnosticResult(
                    LintCommandKernels.GetLintDiagnosticCode(),
                    LintCommandKernels.GetErrorLintingDiagnosticMessage(ex.Message),
                    relativePath
                ))
            } else {
                outcome.Messages.Add(LintCommandKernels.GetErrorLintingFileMessage(sourcePath, ex.Message))
            }
        }

        return outcome
    }

    // The source list, which is the project's own when nothing was named on the command line. It
    // excludes `*.tests.nl` exactly as `nlc fix` does — lint reports on the shipped surface — while
    // the analysis below still COMPILES the test sources so the binding rules see the whole program.
    private static func DiscoverSourcePaths(projectRoot: string, positionalFiles: string[]): List<string> {
        sourcePaths := new List<string>()
        if positionalFiles.Length == 0 {
            config := ProjectFileParser.ParseFromDirectory(projectRoot)
            if config == null {
                config = ProjectFileParser.CreateDefault(null)
            }

            for sourceFile in config.GetSourceFiles(projectRoot, false) {
                sourcePaths.Add(LintCommandKernels.GetSourceFilePath(sourceFile))
            }

            return sourcePaths
        }

        index := 0
        while index < positionalFiles.Length {
            sourcePaths.Add(LintCommandKernels.ResolveFilePath(projectRoot, positionalFiles[index]))
            index = index + 1
        }

        return sourcePaths
    }

    // Every source of the project, analysed, keyed by full path. A project that cannot be loaded at
    // all answers with nothing and the binding rules go quiet for every source, which is the same
    // answer a unit with no binding facts already gives rather than a guess.
    private static func AnalyzedUnitsFor(projectRoot: string): IReadOnlyDictionary<string, CompilationUnit>? {
        try {
            projectConfig := ProjectFileParser.ParseFromDirectory(projectRoot)
            if projectConfig != null {
                CompilationReferenceResolver.AddResolvedDllReferences(projectRoot, projectConfig, new ReferenceResolutionOptions("Debug", true, true, true, false))
            }

            service := new CodeIntelligenceService()
            snapshot := service.LoadProjectIncludingTests(projectRoot, projectConfig, null)
            return snapshot.CompilationUnits
        } catch {
            return null
        }
    }

    private static func AnalyzedUnitFor(units: IReadOnlyDictionary<string, CompilationUnit>?, sourcePath: string): CompilationUnit? {
        table := units
        if table == null {
            return null
        }

        found: CompilationUnit? = null
        if table.TryGetValue(Path.GetFullPath(sourcePath), out found) {
            return found
        }

        return null
    }

    private static func CompilerErrorMessages(errors: IReadOnlyList<CompilerError>): string[] {
        messages := new string[](errors.Count)
        index := 0
        while index < errors.Count {
            messages[index] = errors[index].Message
            index = index + 1
        }

        return messages
    }

    private static func EmitError(useJson: bool, message: string, projectRoot: string?): int {
        if !useJson {
            Console.Error.WriteLine(message)
        } else {
            Console.Write(OutputFormatter.ErrorToJson(LintCommandKernels.GetCommandName(), message, projectRoot, null, null))
        }

        return 1
    }
}

// What linting ONE source produced: the rows, the stderr sentences, whether a rule actually ran on
// it (which is what `lintedFiles` counts), and whether anything failed (which is half of the exit
// code — the other half is the error-severity row count).
internal class LintSourceOutcome {
    Diagnostics: List<DiagnosticResult>
    Messages: List<string>
    Linted: bool
    HadError: bool

    constructor() {
        Diagnostics = new List<DiagnosticResult>()
        Messages = new List<string>()
        Linted = false
        HadError = false
    }
}
