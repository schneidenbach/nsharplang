namespace NSharpLang.Build.Tasks

import System
import System.Collections
import System.Collections.Generic
import System.IO
import Microsoft.Build.Framework
import Microsoft.Build.Utilities
import Mono.Cecil
import NSharpLang.Cli
import NSharpLang.Compiler

/// <summary>
/// Drives N# IL emission from the SDK and owns the reference-assembly scope rewrite.
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
        index := 0
        while index < references.Length {
            referencePath: string = references[index].ItemSpec
            if !string.IsNullOrWhiteSpace(referencePath) {
                fullPath := Path.GetFullPath(referencePath)
                if !IsOwnOutput(fullPath) && CompilationReferenceResolverKernels.ShouldAddDllReference(config.Dependencies, fullPath) {
                    config.Dependencies.Add(new Reference { Dll: fullPath })
                }
            }
            index = index + 1
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

        let ownerNames: Dictionary<string, AssemblyNameDefinition> = null
        owners := BuildReferenceTypeOwners(out ownerNames)
        if SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(owners) {
            File.Copy(assemblyPath, referenceAssemblyPath, true)
            return
        }

        readerParameters := new ReaderParameters()
        readerParameters.ReadingMode = ReadingMode.Immediate
        readerParameters.InMemory = true
        assembly := AssemblyDefinition.ReadAssembly(assemblyPath, readerParameters)
        try {
            module := assembly.MainModule
            typeReferences := MaterializeTypeReferences(module)

            typeReferenceIndex := 0
            while typeReferenceIndex < typeReferences.Count {
                typeReference := typeReferences[typeReferenceIndex]
                owner := owners.Resolve(typeReference.FullName)
                if SdkEmitTaskKernels.ShouldRescopeTypeReference(ScopeName(typeReference), owner != null) {
                    ownerKey: string = owner
                    typeReference.Scope = GetOrAddAssemblyReference(module, ownerNames[ownerKey])
                }
                typeReferenceIndex = typeReferenceIndex + 1
            }

            RemoveUnusedCoreLibAssemblyReference(module)
            assembly.Write(referenceAssemblyPath)
        } finally {
            assembly.Dispose()
        }
    }

    private static func MaterializeTypeReferences(module: ModuleDefinition): List<Mono.Cecil.TypeReference> {
        typeReferences := new List<Mono.Cecil.TypeReference>()
        typeReferenceSequence := module.GetTypeReferences()
        typeReferenceEnumerator := typeReferenceSequence.GetEnumerator()
        typeReferenceMovement := typeReferenceEnumerator as IEnumerator
        try {
            while typeReferenceMovement.MoveNext() {
                typeReferences.Add(typeReferenceEnumerator.get_Current())
            }
        } finally {
            typeReferenceDisposable := typeReferenceEnumerator as IDisposable
            if typeReferenceDisposable != null {
                typeReferenceDisposable.Dispose()
            }
        }
        return typeReferences
    }

    private func BuildReferenceTypeOwners(out ownerNames: Dictionary<string, AssemblyNameDefinition>): ReferenceTypeOwners {
        owners := new ReferenceTypeOwners()
        ownerNames = new Dictionary<string, AssemblyNameDefinition>(StringComparer.Ordinal)
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        references := References
        referenceIndex := 0
        while referenceIndex < references.Length {
            referencePath: string = references[referenceIndex].ItemSpec
            if !string.IsNullOrWhiteSpace(referencePath) {
                fullPath := Path.GetFullPath(referencePath)
                referenceExists := File.Exists(referencePath)
                ownOutput := IsOwnOutput(fullPath)
                if SdkEmitTaskKernels.ShouldScanReferenceForOwners(fullPath, referenceExists, ownOutput) && seen.Add(fullPath) {
                    ScanReferenceAssembly(fullPath, owners, ownerNames)
                }
            }
            referenceIndex = referenceIndex + 1
        }

        return owners
    }

    private static func ScanReferenceAssembly(fullPath: string, owners: ReferenceTypeOwners, ownerNames: Dictionary<string, AssemblyNameDefinition>) {
        let referenceAssembly: AssemblyDefinition? = null
        try {
            readParameters := new ReaderParameters()
            readParameters.ReadingMode = ReadingMode.Deferred
            openedReferenceAssembly := AssemblyDefinition.ReadAssembly(fullPath, readParameters)
            referenceAssembly = openedReferenceAssembly
            RecordReferenceAssembly(owners, ownerNames, openedReferenceAssembly)
        } catch (BadImageFormatException) {
            return
        } catch (IOException) {
            return
        } finally {
            if referenceAssembly != null {
                referenceAssembly.Dispose()
            }
        }
    }

    private static func RecordReferenceAssembly(owners: ReferenceTypeOwners, ownerNames: Dictionary<string, AssemblyNameDefinition>, referenceAssembly: AssemblyDefinition) {
        ownerNameForKey := referenceAssembly.Name
        ownerKey := ownerNameForKey.FullName
        ownerNamesForAdd := ownerNames
        ownerNameForMap := referenceAssembly.Name
        ownerNamesForAdd.TryAdd(ownerKey, ownerNameForMap)

        definitionModule := referenceAssembly.MainModule
        RecordModuleDefinedTypes(owners, ownerKey, definitionModule)

        forwarderModule := referenceAssembly.MainModule
        RecordModuleForwarders(owners, ownerKey, forwarderModule)
    }

    private static func RecordModuleDefinedTypes(owners: ReferenceTypeOwners, ownerKey: string, module: ModuleDefinition) {
        types := module.Types
        typeSequence: IEnumerable<TypeDefinition> = types
        typeEnumerator := typeSequence.GetEnumerator()
        typeMovement := typeEnumerator as IEnumerator
        try {
            while typeMovement.MoveNext() {
                RecordDefinedTypes(owners, ownerKey, typeEnumerator.get_Current())
            }
        } finally {
            typeDisposable := typeEnumerator as IDisposable
            if typeDisposable != null {
                typeDisposable.Dispose()
            }
        }
    }

    private static func RecordModuleForwarders(owners: ReferenceTypeOwners, ownerKey: string, module: ModuleDefinition) {
        exportedTypes := module.ExportedTypes
        exportedSequence: IEnumerable<ExportedType> = exportedTypes
        exportedEnumerator := exportedSequence.GetEnumerator()
        exportedMovement := exportedEnumerator as IEnumerator
        try {
            while exportedMovement.MoveNext() {
                exportedType := exportedEnumerator.get_Current()
                owners.RecordForwarder(exportedType.FullName, ownerKey)
            }
        } finally {
            exportedDisposable := exportedEnumerator as IDisposable
            if exportedDisposable != null {
                exportedDisposable.Dispose()
            }
        }
    }

    private static func RecordDefinedTypes(owners: ReferenceTypeOwners, ownerKey: string, typeDefinition: TypeDefinition) {
        owners.RecordDefinition(typeDefinition.FullName, ownerKey)
        nestedTypes := typeDefinition.NestedTypes
        nestedSequence: IEnumerable<TypeDefinition> = nestedTypes
        nestedEnumerator := nestedSequence.GetEnumerator()
        nestedMovement := nestedEnumerator as IEnumerator
        try {
            while nestedMovement.MoveNext() {
                RecordDefinedTypes(owners, ownerKey, nestedEnumerator.get_Current())
            }
        } finally {
            nestedDisposable := nestedEnumerator as IDisposable
            if nestedDisposable != null {
                nestedDisposable.Dispose()
            }
        }
    }

    private static func GetOrAddAssemblyReference(module: ModuleDefinition, owner: AssemblyNameDefinition): AssemblyNameReference {
        assemblyReferences := module.AssemblyReferences
        referenceSequence: IEnumerable<AssemblyNameReference> = assemblyReferences
        referenceEnumerator := referenceSequence.GetEnumerator()
        referenceMovement := referenceEnumerator as IEnumerator
        let existing: AssemblyNameReference? = null
        try {
            while referenceMovement.MoveNext() {
                reference := referenceEnumerator.get_Current()
                if SdkEmitTaskKernels.AssemblyReferenceMatches(
                    reference.Name,
                    VersionText(reference.Version),
                    owner.Name,
                    VersionText(owner.Version)
                ) {
                    existing = reference
                    break
                }
            }
        } finally {
            referenceDisposable := referenceEnumerator as IDisposable
            if referenceDisposable != null {
                referenceDisposable.Dispose()
            }
        }
        if existing != null {
            return existing
        }

        assemblyReference := new AssemblyNameReference(owner.Name, owner.Version)
        assemblyReference.Culture = owner.Culture
        assemblyReference.PublicKeyToken = owner.PublicKeyToken
        module.AssemblyReferences.Add(assemblyReference)
        return assemblyReference
    }

    private static func RemoveUnusedCoreLibAssemblyReference(module: ModuleDefinition) {
        hasCoreLibTypeReference := false
        typeReferenceSequence := module.GetTypeReferences()
        typeReferenceEnumerator := typeReferenceSequence.GetEnumerator()
        typeReferenceMovement := typeReferenceEnumerator as IEnumerator
        try {
            while typeReferenceMovement.MoveNext() {
                if SdkEmitTaskKernels.IsImplementationCoreLibrary(ScopeName(typeReferenceEnumerator.get_Current())) {
                    hasCoreLibTypeReference = true
                    break
                }
            }
        } finally {
            typeReferenceDisposable := typeReferenceEnumerator as IDisposable
            if typeReferenceDisposable != null {
                typeReferenceDisposable.Dispose()
            }
        }

        if !SdkEmitTaskKernels.ShouldRemoveCoreLibraryReference(hasCoreLibTypeReference) {
            return
        }

        removable := new List<AssemblyNameReference>()
        assemblyReferences := module.AssemblyReferences
        referenceSequence: IEnumerable<AssemblyNameReference> = assemblyReferences
        referenceEnumerator := referenceSequence.GetEnumerator()
        referenceMovement := referenceEnumerator as IEnumerator
        try {
            while referenceMovement.MoveNext() {
                reference := referenceEnumerator.get_Current()
                if SdkEmitTaskKernels.IsImplementationCoreLibrary(reference.Name) {
                    removable.Add(reference)
                }
            }
        } finally {
            referenceDisposable := referenceEnumerator as IDisposable
            if referenceDisposable != null {
                referenceDisposable.Dispose()
            }
        }

        index := 0
        while index < removable.Count {
            module.AssemblyReferences.Remove(removable[index])
            index = index + 1
        }
    }

    private static func ScopeName(typeReference: Mono.Cecil.TypeReference): string? {
        scopeValue: object = typeReference.Scope
        scope := scopeValue as AssemblyNameReference
        if scope == null {
            return null
        }
        return scope.Name
    }

    private static func VersionText(version: Version?): string {
        if version == null {
            return ""
        }
        versionObject: object = version
        return versionObject.ToString()
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
