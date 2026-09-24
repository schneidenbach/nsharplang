namespace NSharpLang.Build.Tasks

import System
import System.Collections
import System.Collections.Generic
import System.IO
import Microsoft.Build.Framework
import Microsoft.Build.Utilities
import NSharpLang.Cli
import NSharpLang.Compiler

/// <summary>
/// Drives N# IL emission from the SDK and places the compiler's reference assembly where MSBuild asked for it.
/// </summary>
class EmitIlAssembly: Microsoft.Build.Utilities.Task {
    private sourcesValue: ITaskItem[]
    private referencesValue: ITaskItem[]
    private projectRootValue: string
    private projectFileValue: string?
    private targetAssemblyPathValue: string
    private targetReferenceAssemblyPathValue: string?
    private assemblyVersionValue: string?
    private configurationValue: string?
    private defineConstantsValue: string?
    private validateWithLegacyAnalysisValue: bool

    [Microsoft.Build.Framework.Required]
    Sources: ITaskItem[] {
        get {
            return sourcesValue
        }
        set {
            sourcesValue = value
        }
    }

    References: ITaskItem[] {
        get {
            return referencesValue
        }
        set {
            referencesValue = value
        }
    }

    [Microsoft.Build.Framework.Required]
    ProjectRoot: string {
        get {
            return projectRootValue
        }
        set {
            projectRootValue = value
        }
    }

    ProjectFile: string? {
        get {
            return projectFileValue
        }
        set {
            projectFileValue = value
        }
    }

    [Microsoft.Build.Framework.Required]
    TargetAssemblyPath: string {
        get {
            return targetAssemblyPathValue
        }
        set {
            targetAssemblyPathValue = value
        }
    }

    TargetReferenceAssemblyPath: string? {
        get {
            return targetReferenceAssemblyPathValue
        }
        set {
            targetReferenceAssemblyPathValue = value
        }
    }

    AssemblyVersion: string? {
        get {
            return assemblyVersionValue
        }
        set {
            assemblyVersionValue = value
        }
    }

    Configuration: string? {
        get {
            return configurationValue
        }
        set {
            configurationValue = value
        }
    }

    DefineConstants: string? {
        get {
            return defineConstantsValue
        }
        set {
            defineConstantsValue = value
        }
    }

    ValidateWithLegacyAnalysis: bool {
        get {
            return validateWithLegacyAnalysisValue
        }
        set {
            validateWithLegacyAnalysisValue = value
        }
    }

    constructor() {
        sourcesValue = Array.Empty<ITaskItem>()
        referencesValue = Array.Empty<ITaskItem>()
        projectRootValue = ""
        projectFileValue = null
        targetAssemblyPathValue = ""
        targetReferenceAssemblyPathValue = null
        assemblyVersionValue = null
        configurationValue = null
        defineConstantsValue = null
        validateWithLegacyAnalysisValue = SdkEmitTaskKernels.ValidatesWithLegacyAnalysisByDefault()
    }

    override func Execute(): bool {
        try {
            sourceItems := Sources
            if sourceItems == null {
                throw new ArgumentNullException("source")
            }
            sourceFiles := new string[](sourceItems.Length)
            sourceIndex := 0
            while sourceIndex < sourceItems.Length {
                sourceItem := sourceItems[sourceIndex]
                sourceItemSpec: string = sourceItem.ItemSpec
                sourceFiles[sourceIndex] = sourceItemSpec
                sourceIndex = sourceIndex + 1
            }

            config := ProjectFileParser.Parse(ProjectFile)
            config.Version = SdkEmitTaskKernels.ResolveProjectVersion(config.Version, AssemblyVersion)
            SdkEmitTaskKernels.ApplyMsBuildDefines(config, Configuration, DefineConstants)
            AddResolvedDllReferences(config)

            compiler := new MultiFileCompiler(sourceFiles, ProjectRoot, config)
            compiler.EmitReferenceAssembly = SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly(TargetReferenceAssemblyPath, true)
            result := compiler.CompileToIlAssembly(
                config.EffectiveName,
                TargetAssemblyPath,
                false,
                ValidateWithLegacyAnalysis
            )

            LogCompilerDiagnostics(result.Errors)

            if !result.Success {
                return false
            }

            SynchronizeReferenceAssembly()
            logger: Microsoft.Build.Utilities.TaskLoggingHelper = get_Log()
            importance: MessageImportance = MessageImportance.High
            emittedMessage: string = SdkEmitTaskKernels.GetEmittedAssemblyMessage(TargetAssemblyPath)
            messageArguments: object[] = Array.Empty<object>()
            logger.LogMessage(importance, emittedMessage, messageArguments)
            return true
        } catch ex: Exception {
            emptyProjectFile: string? = null
            get_Log().LogErrorFromException(ex, true, false, emptyProjectFile)
            return false
        }
    }

    private func AddResolvedDllReferences(config: ProjectConfig) {
        references := References
        for reference in references {
            referencePath: string = reference.ItemSpec
            if !string.IsNullOrWhiteSpace(referencePath) {
                fullPath := Path.GetFullPath(referencePath)
                if !IsOwnOutput(fullPath) && CompilationReferenceResolverKernels.ShouldAddDllReference(config.Dependencies, fullPath) {
                    config.Dependencies.Add(new Reference { Dll: fullPath })
                }
            }
        }
    }

    private func IsOwnOutput(fullPath: string): bool {
        if SdkEmitTaskKernels.IsSameOutputPath(fullPath, Path.GetFullPath(TargetAssemblyPath)) {
            return true
        }

        targetReferencePathForWhitespace := TargetReferenceAssemblyPath
        if string.IsNullOrWhiteSpace(targetReferencePathForWhitespace) {
            return false
        }
        targetReferencePathForNormalization := TargetReferenceAssemblyPath
        return SdkEmitTaskKernels.IsSameOutputPath(fullPath, Path.GetFullPath(targetReferencePathForNormalization))
    }

    // THE TASK COPIES A FINISHED FILE. It used to READ the implementation assembly back with Cecil
    // and rewrite its reference table into `refint/`, which is why that file carried every method
    // body the implementation carried and changed whenever any of them did. The surface is the
    // compiler's output now (`ColumnarReferenceAssemblyWriter`), so all that is left here is the
    // copy MSBuild asked for.
    private func SynchronizeReferenceAssembly() {
        targetReferencePathForDecision := TargetReferenceAssemblyPath
        targetPathForExistence := TargetAssemblyPath
        if !SdkEmitTaskKernels.ShouldSynchronizeReferenceAssembly(targetReferencePathForDecision, File.Exists(targetPathForExistence)) {
            return
        }

        assemblyPath := Path.GetFullPath(TargetAssemblyPath)
        referenceAssemblyPath := Path.GetFullPath(TargetReferenceAssemblyPath)
        if SdkEmitTaskKernels.IsSameOutputPath(assemblyPath, referenceAssemblyPath) {
            return
        }

        referenceAssemblyDirectory := Path.GetDirectoryName(referenceAssemblyPath)
        if !string.IsNullOrEmpty(referenceAssemblyDirectory) {
            Directory.CreateDirectory(referenceAssemblyDirectory)
        }

        emittedReferenceAssembly := MultiFileCompiler.ReferenceAssemblyPathFor(assemblyPath)
        if !File.Exists(emittedReferenceAssembly) {
            // Nothing to copy means the compiler declined to write a surface; the implementation is
            // the only honest answer, and it is what this task produced before this change.
            CopyReferenceAssemblyIfChanged(assemblyPath, referenceAssemblyPath)
            return
        }

        CopyReferenceAssemblyIfChanged(emittedReferenceAssembly, referenceAssemblyPath)
    }

    // THE COPY IS SKIPPED WHEN THE SURFACE IS THE SAME SURFACE, AND THAT SKIP IS THE WHOLE OF THE
    // INCREMENTALITY.
    //
    // `Sdk.targets` feeds the emit target's up-to-date check `@(ReferencePathWithRefAssemblies)`,
    // which for a project reference is that project's `obj/…/ref/<Asm>.dll`. MSBuild compares
    // TIMESTAMPS, so that file must not be rewritten when nothing about the surface changed.
    // `CopyFilesToOutputDirectory` gets it there by running Roslyn's `CopyRefAssembly` from
    // `refint/` — and that task is not the guard it looks like: its `MvidReader` reads the module
    // version id out of a dedicated `.mvid` PE SECTION that only Roslyn's `/refout` emits, so for
    // any other producer it logs "Could not extract the MVID" and copies unconditionally. What it
    // does do is `File.Copy`, which preserves the source's last-write time. So leaving `refint`
    // alone leaves `ref` alone, and the dependent stays up to date.
    private func CopyReferenceAssemblyIfChanged(sourcePath: string, destinationPath: string) {
        if File.Exists(destinationPath) {
            existing := File.ReadAllBytes(destinationPath)
            candidate := File.ReadAllBytes(sourcePath)
            if SdkEmitTaskKernels.ReferenceAssembliesAreIdentical(existing, candidate) {
                return
            }
        }

        File.Copy(sourcePath, destinationPath, true)
    }

    private func LogCompilerDiagnostics(errors: IEnumerable<CompilerError>) {
        errorEnumerator := errors.GetEnumerator()
        errorMovement := errorEnumerator as IEnumerator
        try {
            while errorMovement.MoveNext() {
                LogCompilerDiagnostic(errorEnumerator.get_Current())
            }
        } finally {
            errorDisposable := errorEnumerator as IDisposable
            if errorDisposable != null {
                errorDisposable.Dispose()
            }
        }
    }

    private func LogCompilerDiagnostic(error: CompilerError) {
        emptyText: string? = null
        if error.Severity == ErrorSeverity.Error {
            logger := get_Log()
            diagnosticId := error.DiagnosticId
            fileName := error.FileName ?? ""
            lineNumber := error.Line
            columnNumber := error.Column
            endLineNumber := error.Line
            endColumnNumber := error.MsBuildEndColumn
            message := error.FormatForMsBuild()
            messageArguments := Array.Empty<object>()
            logger.LogError(
                emptyText,
                diagnosticId,
                emptyText,
                fileName,
                lineNumber,
                columnNumber,
                endLineNumber,
                endColumnNumber,
                message,
                messageArguments
            )
        } else if error.Severity == ErrorSeverity.Warning {
            logger := get_Log()
            diagnosticId := error.DiagnosticId
            fileName := error.FileName ?? ""
            lineNumber := error.Line
            columnNumber := error.Column
            endLineNumber := error.Line
            endColumnNumber := error.MsBuildEndColumn
            message := error.FormatForMsBuild()
            messageArguments := Array.Empty<object>()
            logger.LogWarning(
                emptyText,
                diagnosticId,
                emptyText,
                fileName,
                lineNumber,
                columnNumber,
                endLineNumber,
                endColumnNumber,
                message,
                messageArguments
            )
        }
    }
}
