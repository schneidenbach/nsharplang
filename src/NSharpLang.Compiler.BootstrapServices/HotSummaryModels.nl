namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import System.IO
import System.Text.Json
import NSharpLang.Compiler

public class HotSummaryDocument {
    schemaVersionValue: int = 1
    entriesValue: List<HotSummaryEntry> = new List<HotSummaryEntry>()

    SchemaVersion: int {
        get {
            return schemaVersionValue
        }
        set {
            schemaVersionValue = value
        }
    }

    Entries: List<HotSummaryEntry> {
        get {
            return entriesValue
        }
        set {
            entriesValue = value
        }
    }
}

public class HotSummaryEntry {
    schemaVersionValue: int = 1
    assemblyIdentityValue: string = ""
    publicKeyTokenValue: string?
    packageIdValue: string?
    packageVersionValue: string?
    targetFrameworkValue: string = "*"
    runtimeIdentifierValue: string?
    methodValue: string = ""
    genericArityValue: int
    bodyIdentityValue: string?
    effectsValue: HotSummaryEffects = new HotSummaryEffects()
    genericConditionsValue: List<string> = new List<string>()
    preconditionsValue: List<string> = new List<string>()
    hotReadinessRequirementsValue: List<string> = new List<string>()
    sourceValue: string = HotSummarySource.Compiler

    public static None: HotSummaryEntry => new HotSummaryEntry()

    SchemaVersion: int {
        get {
            return schemaVersionValue
        }
        set {
            schemaVersionValue = value
        }
    }

    AssemblyIdentity: string {
        get {
            return assemblyIdentityValue
        }
        set {
            assemblyIdentityValue = value
        }
    }

    PublicKeyToken: string? {
        get {
            return publicKeyTokenValue
        }
        set {
            publicKeyTokenValue = value
        }
    }

    PackageId: string? {
        get {
            return packageIdValue
        }
        set {
            packageIdValue = value
        }
    }

    PackageVersion: string? {
        get {
            return packageVersionValue
        }
        set {
            packageVersionValue = value
        }
    }

    TargetFramework: string {
        get {
            return targetFrameworkValue
        }
        set {
            targetFrameworkValue = value
        }
    }

    RuntimeIdentifier: string? {
        get {
            return runtimeIdentifierValue
        }
        set {
            runtimeIdentifierValue = value
        }
    }

    Method: string {
        get {
            return methodValue
        }
        set {
            methodValue = value
        }
    }

    GenericArity: int {
        get {
            return genericArityValue
        }
        set {
            genericArityValue = value
        }
    }

    BodyIdentity: string? {
        get {
            return bodyIdentityValue
        }
        set {
            bodyIdentityValue = value
        }
    }

    Effects: HotSummaryEffects {
        get {
            return effectsValue
        }
        set {
            effectsValue = value
        }
    }

    GenericConditions: List<string> {
        get {
            return genericConditionsValue
        }
        set {
            genericConditionsValue = value
        }
    }

    Preconditions: List<string> {
        get {
            return preconditionsValue
        }
        set {
            preconditionsValue = value
        }
    }

    HotReadinessRequirements: List<string> {
        get {
            return hotReadinessRequirementsValue
        }
        set {
            hotReadinessRequirementsValue = value
        }
    }

    Source: string {
        get {
            return sourceValue
        }
        set {
            sourceValue = value
        }
    }

    IsSidecar: bool => string.Equals(Source, HotSummarySource.Sidecar, StringComparison.OrdinalIgnoreCase)

    public func IsAotSafeFor(target: string): bool {
        if !Effects.AotSafe {
            return false
        }

        targets := Effects.AotSafeTargets
        if targets.Count == 0 {
            return true
        }

        i := 0
        while i < targets.Count {
            if string.Equals(targets[i], target, StringComparison.OrdinalIgnoreCase) {
                return true
            }

            i = i + 1
        }

        return false
    }
}

public class HotSummaryEffects {
    allocatesValue: bool
    boxesValue: bool
    constructsDelegateValue: bool
    capturesClosureValue: bool
    usesRuntimeDispatchValue: bool
    usesReflectionValue: bool
    usesDynamicCodeValue: bool
    throwsValue: bool
    hasImplicitTrapObligationValue: bool
    usesUnknownExternalCallValue: bool
    usesResourceValue: bool
    usesPoolValue: bool
    usesConcurrencyPrimitiveValue: bool
    requiresWarmupValue: bool
    aotSafeValue: bool = true
    trimSafeValue: bool = true
    aotSafeTargetsValue: List<string> = new List<string>()

    Allocates: bool {
        get {
            return allocatesValue
        }
        set {
            allocatesValue = value
        }
    }

    Boxes: bool {
        get {
            return boxesValue
        }
        set {
            boxesValue = value
        }
    }

    ConstructsDelegate: bool {
        get {
            return constructsDelegateValue
        }
        set {
            constructsDelegateValue = value
        }
    }

    CapturesClosure: bool {
        get {
            return capturesClosureValue
        }
        set {
            capturesClosureValue = value
        }
    }

    UsesRuntimeDispatch: bool {
        get {
            return usesRuntimeDispatchValue
        }
        set {
            usesRuntimeDispatchValue = value
        }
    }

    UsesReflection: bool {
        get {
            return usesReflectionValue
        }
        set {
            usesReflectionValue = value
        }
    }

    UsesDynamicCode: bool {
        get {
            return usesDynamicCodeValue
        }
        set {
            usesDynamicCodeValue = value
        }
    }

    Throws: bool {
        get {
            return throwsValue
        }
        set {
            throwsValue = value
        }
    }

    HasImplicitTrapObligation: bool {
        get {
            return hasImplicitTrapObligationValue
        }
        set {
            hasImplicitTrapObligationValue = value
        }
    }

    UsesUnknownExternalCall: bool {
        get {
            return usesUnknownExternalCallValue
        }
        set {
            usesUnknownExternalCallValue = value
        }
    }

    UsesResource: bool {
        get {
            return usesResourceValue
        }
        set {
            usesResourceValue = value
        }
    }

    UsesPool: bool {
        get {
            return usesPoolValue
        }
        set {
            usesPoolValue = value
        }
    }

    UsesConcurrencyPrimitive: bool {
        get {
            return usesConcurrencyPrimitiveValue
        }
        set {
            usesConcurrencyPrimitiveValue = value
        }
    }

    RequiresWarmup: bool {
        get {
            return requiresWarmupValue
        }
        set {
            requiresWarmupValue = value
        }
    }

    AotSafe: bool {
        get {
            return aotSafeValue
        }
        set {
            aotSafeValue = value
        }
    }

    TrimSafe: bool {
        get {
            return trimSafeValue
        }
        set {
            trimSafeValue = value
        }
    }

    AotSafeTargets: List<string> {
        get {
            return aotSafeTargetsValue
        }
        set {
            aotSafeTargetsValue = value
        }
    }
}

public class BclHotSummaryPack {
    public static func Create(targetFramework: string): List<HotSummaryEntry> {
        entries := new List<HotSummaryEntry>()

        Add(entries, targetFramework, "BinaryPrimitives.*")
        Add(entries, targetFramework, "System.Buffers.Binary.BinaryPrimitives.*")
        Add(entries, targetFramework, "MemoryExtensions.*")
        Add(entries, targetFramework, "System.MemoryExtensions.*")
        Add(entries, targetFramework, "MemoryMarshal.*")
        Add(entries, targetFramework, "System.Runtime.InteropServices.MemoryMarshal.*")
        Add(entries, targetFramework, "Buffer.MemoryCopy")
        Add(entries, targetFramework, "System.Buffer.MemoryCopy")
        Add(entries, targetFramework, "BitOperations.*")
        Add(entries, targetFramework, "System.Numerics.BitOperations.*")
        Add(entries, targetFramework, "Vector.*")
        Add(entries, targetFramework, "System.Numerics.Vector.*")
        Add(entries, targetFramework, "Math.*")
        Add(entries, targetFramework, "System.Math.*")
        Add(entries, targetFramework, "MathF.*")
        Add(entries, targetFramework, "System.MathF.*")
        Add(entries, targetFramework, "Span.*")
        Add(entries, targetFramework, "ReadOnlySpan.*")
        Add(entries, targetFramework, "String.get_Length")
        Add(entries, targetFramework, "Array.get_Length")
        Add(entries, targetFramework, "Slice")
        Add(entries, targetFramework, "AsSpan")
        Add(entries, targetFramework, "CopyTo")
        Add(entries, targetFramework, "Clear")
        Add(entries, targetFramework, "Fill")
        Add(entries, targetFramework, "Length")
        Add(entries, targetFramework, "LibraryImport")
        Add(entries, targetFramework, "System.Runtime.InteropServices.LibraryImportAttribute")

        AddConcurrencyPrimitive(entries, targetFramework, "Volatile.Read")
        AddConcurrencyPrimitive(entries, targetFramework, "Volatile.Write")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Volatile.Read")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Volatile.Write")
        AddConcurrencyPrimitive(entries, targetFramework, "Interlocked.Exchange")
        AddConcurrencyPrimitive(entries, targetFramework, "Interlocked.CompareExchange")
        AddConcurrencyPrimitive(entries, targetFramework, "Interlocked.Increment")
        AddConcurrencyPrimitive(entries, targetFramework, "Interlocked.Decrement")
        AddConcurrencyPrimitive(entries, targetFramework, "Interlocked.Add")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Interlocked.Exchange")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Interlocked.CompareExchange")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Interlocked.Increment")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Interlocked.Decrement")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Interlocked.Add")
        AddConcurrencyPrimitive(entries, targetFramework, "Thread.MemoryBarrier")
        AddConcurrencyPrimitive(entries, targetFramework, "System.Threading.Thread.MemoryBarrier")

        rentArrayEffects := new HotSummaryEffects()
        rentArrayEffects.UsesPool = true
        rentArrayEffects.RequiresWarmup = true
        Add(entries, targetFramework, "ArrayPool.*.Rent", rentArrayEffects)

        returnArrayEffects := new HotSummaryEffects()
        returnArrayEffects.UsesPool = true
        Add(entries, targetFramework, "ArrayPool.*.Return", returnArrayEffects)

        rentMemoryEffects := new HotSummaryEffects()
        rentMemoryEffects.UsesPool = true
        rentMemoryEffects.RequiresWarmup = true
        Add(entries, targetFramework, "MemoryPool.*.Rent", rentMemoryEffects)

        memoryOwnerDisposeEffects := new HotSummaryEffects()
        memoryOwnerDisposeEffects.UsesPool = true
        memoryOwnerDisposeEffects.UsesResource = true
        Add(entries, targetFramework, "IMemoryOwner.*.Dispose", memoryOwnerDisposeEffects)

        return entries
    }

    static func AddConcurrencyPrimitive(entries: List<HotSummaryEntry>, targetFramework: string, method: string) {
        effects := new HotSummaryEffects()
        effects.UsesConcurrencyPrimitive = true
        Add(entries, targetFramework, method, effects)
    }

    static func Add(
        entries: List<HotSummaryEntry>,
        targetFramework: string,
        method: string,
        effects: HotSummaryEffects? = null) {
        entry := new HotSummaryEntry()
        entry.SchemaVersion = 1
        entry.AssemblyIdentity = "System.Private.CoreLib"
        entry.TargetFramework = targetFramework
        entry.Method = method
        entry.Source = HotSummarySource.BclPack
        if effects == null {
            entry.Effects = new HotSummaryEffects()
        } else {
            entry.Effects = effects
        }
        entry.BodyIdentity = "nsharp-bcl-pack-v1"
        entries.Add(entry)
    }
}

public class HotSummaryCatalog {
    entriesValue: List<HotSummaryEntry>

    constructor(entries: List<HotSummaryEntry>) {
        entriesValue = entries
    }

    public static func Load(projectRoot: string, config: ProjectConfig): HotSummaryCatalog {
        entries := new List<HotSummaryEntry>()
        bclEntries := BclHotSummaryPack.Create(config.TargetFramework)
        i := 0
        while i < bclEntries.Count {
            entries.Add(bclEntries[i])
            i = i + 1
        }

        sidecars := config.Language.Systems.HotSummaryFiles
        sidecarIndex := 0
        while sidecarIndex < sidecars.Count {
            sidecar := sidecars[sidecarIndex]
            path := sidecar
            if !Path.IsPathRooted(sidecar) {
                path = Path.Combine(projectRoot, sidecar)
            }

            if File.Exists(path) {
                document := JsonDocument.Parse(File.ReadAllText(path))
                AddSidecarEntries(entries, document.RootElement, config.TargetFramework)
                document.Dispose()
            }

            sidecarIndex = sidecarIndex + 1
        }

        return new HotSummaryCatalog(entries)
    }

    public func TryResolve(target: string, targetFramework: string, out entry: HotSummaryEntry): bool {
        i := 0
        while i < entriesValue.Count {
            candidate := entriesValue[i]
            if TargetFrameworkMatches(candidate.TargetFramework, targetFramework) {
                if MethodMatches(candidate.Method, target) {
                    entry = candidate
                    return true
                }
            }

            i = i + 1
        }

        entry = HotSummaryEntry.None
        return false
    }

    public func HasReceiverSummary(receiver: string, targetFramework: string): bool {
        i := 0
        while i < entriesValue.Count {
            entry := entriesValue[i]
            if TargetFrameworkMatches(entry.TargetFramework, targetFramework) {
                method := entry.Method
                if method.StartsWith(receiver + ".", StringComparison.Ordinal) {
                    return true
                }

                if method.StartsWith("System." + receiver + ".", StringComparison.Ordinal) {
                    return true
                }

                if method.StartsWith(receiver + "*", StringComparison.Ordinal) {
                    return true
                }
            }

            i = i + 1
        }

        return false
    }

    static func AddSidecarEntries(entries: List<HotSummaryEntry>, root: JsonElement, targetFramework: string) {
        if root.ValueKind != JsonValueKind.Object {
            return
        }

        documentSchemaVersion := ReadIntProperty(root, "schemaVersion", 1)
        entriesElement := new JsonElement()
        if !TryGetJsonProperty(root, "entries", out entriesElement) {
            return
        }

        if entriesElement.ValueKind != JsonValueKind.Array {
            return
        }

        entryEnumerator := entriesElement.EnumerateArray()
        while entryEnumerator.MoveNext() {
            entryElement := entryEnumerator.Current
            if entryElement.ValueKind != JsonValueKind.Object {
                continue
            }

            entry := ParseHotSummaryEntry(entryElement)
            if entry.SchemaVersion == 0 {
                if documentSchemaVersion == 0 {
                    entry.SchemaVersion = 1
                } else {
                    entry.SchemaVersion = documentSchemaVersion
                }
            }

            if string.IsNullOrWhiteSpace(entry.Source) {
                entry.Source = HotSummarySource.Sidecar
            }

            if string.IsNullOrWhiteSpace(entry.TargetFramework) {
                entry.TargetFramework = targetFramework
            }

            entries.Add(entry)
        }
    }

    static func ParseHotSummaryEntry(element: JsonElement): HotSummaryEntry {
        entry := new HotSummaryEntry()
        entry.SchemaVersion = ReadIntProperty(element, "schemaVersion", entry.SchemaVersion)
        entry.AssemblyIdentity = ReadStringProperty(element, "assemblyIdentity", entry.AssemblyIdentity)
        entry.PublicKeyToken = ReadNullableStringProperty(element, "publicKeyToken", entry.PublicKeyToken)
        entry.PackageId = ReadNullableStringProperty(element, "packageId", entry.PackageId)
        entry.PackageVersion = ReadNullableStringProperty(element, "packageVersion", entry.PackageVersion)
        entry.TargetFramework = ReadStringProperty(element, "targetFramework", entry.TargetFramework)
        entry.RuntimeIdentifier = ReadNullableStringProperty(element, "runtimeIdentifier", entry.RuntimeIdentifier)
        entry.Method = ReadStringProperty(element, "method", entry.Method)
        entry.GenericArity = ReadIntProperty(element, "genericArity", entry.GenericArity)
        entry.BodyIdentity = ReadNullableStringProperty(element, "bodyIdentity", entry.BodyIdentity)
        entry.Source = ReadStringProperty(element, "source", entry.Source)
        entry.GenericConditions = ReadStringListProperty(element, "genericConditions")
        entry.Preconditions = ReadStringListProperty(element, "preconditions")
        entry.HotReadinessRequirements = ReadStringListProperty(element, "hotReadinessRequirements")

        effectsElement := new JsonElement()
        if TryGetJsonProperty(element, "effects", out effectsElement) {
            if effectsElement.ValueKind == JsonValueKind.Object {
                entry.Effects = ParseHotSummaryEffects(effectsElement)
            }
        }

        return entry
    }

    static func ParseHotSummaryEffects(element: JsonElement): HotSummaryEffects {
        effects := new HotSummaryEffects()
        effects.Allocates = ReadBoolProperty(element, "allocates", effects.Allocates)
        effects.Boxes = ReadBoolProperty(element, "boxes", effects.Boxes)
        effects.ConstructsDelegate = ReadBoolProperty(element, "constructsDelegate", effects.ConstructsDelegate)
        effects.CapturesClosure = ReadBoolProperty(element, "capturesClosure", effects.CapturesClosure)
        effects.UsesRuntimeDispatch = ReadBoolProperty(element, "usesRuntimeDispatch", effects.UsesRuntimeDispatch)
        effects.UsesReflection = ReadBoolProperty(element, "usesReflection", effects.UsesReflection)
        effects.UsesDynamicCode = ReadBoolProperty(element, "usesDynamicCode", effects.UsesDynamicCode)
        effects.Throws = ReadBoolProperty(element, "throws", effects.Throws)
        effects.HasImplicitTrapObligation = ReadBoolProperty(element, "hasImplicitTrapObligation", effects.HasImplicitTrapObligation)
        effects.UsesUnknownExternalCall = ReadBoolProperty(element, "usesUnknownExternalCall", effects.UsesUnknownExternalCall)
        effects.UsesResource = ReadBoolProperty(element, "usesResource", effects.UsesResource)
        effects.UsesPool = ReadBoolProperty(element, "usesPool", effects.UsesPool)
        effects.UsesConcurrencyPrimitive = ReadBoolProperty(element, "usesConcurrencyPrimitive", effects.UsesConcurrencyPrimitive)
        effects.RequiresWarmup = ReadBoolProperty(element, "requiresWarmup", effects.RequiresWarmup)
        effects.AotSafe = ReadBoolProperty(element, "aotSafe", effects.AotSafe)
        effects.TrimSafe = ReadBoolProperty(element, "trimSafe", effects.TrimSafe)
        effects.AotSafeTargets = ReadStringListProperty(element, "aotSafeTargets")
        return effects
    }

    static func TryGetJsonProperty(element: JsonElement, name: string, out value: JsonElement): bool {
        value = new JsonElement()
        if element.ValueKind != JsonValueKind.Object {
            return false
        }

        if element.TryGetProperty(name, out value) {
            return true
        }

        objectEnumerator := element.EnumerateObject()
        while objectEnumerator.MoveNext() {
            property := objectEnumerator.Current
            if string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase) {
                value = property.Value
                return true
            }
        }

        return false
    }

    static func ReadIntProperty(element: JsonElement, name: string, fallback: int): int {
        property := new JsonElement()
        if !TryGetJsonProperty(element, name, out property) {
            return fallback
        }

        if property.ValueKind != JsonValueKind.Number {
            return fallback
        }

        return property.GetInt32()
    }

    static func ReadStringProperty(element: JsonElement, name: string, fallback: string): string {
        value := ReadNullableStringProperty(element, name, fallback)
        return value ?? fallback
    }

    static func ReadNullableStringProperty(element: JsonElement, name: string, fallback: string?): string? {
        property := new JsonElement()
        if !TryGetJsonProperty(element, name, out property) {
            return fallback
        }

        if property.ValueKind == JsonValueKind.Null {
            return null
        }

        if property.ValueKind != JsonValueKind.String {
            return fallback
        }

        return property.GetString()
    }

    static func ReadBoolProperty(element: JsonElement, name: string, fallback: bool): bool {
        property := new JsonElement()
        if !TryGetJsonProperty(element, name, out property) {
            return fallback
        }

        if property.ValueKind == JsonValueKind.True {
            return true
        }

        if property.ValueKind == JsonValueKind.False {
            return false
        }

        return fallback
    }

    static func ReadStringListProperty(element: JsonElement, name: string): List<string> {
        result := new List<string>()
        property := new JsonElement()
        if !TryGetJsonProperty(element, name, out property) {
            return result
        }

        if property.ValueKind != JsonValueKind.Array {
            return result
        }

        arrayEnumerator := property.EnumerateArray()
        while arrayEnumerator.MoveNext() {
            item := arrayEnumerator.Current
            if item.ValueKind == JsonValueKind.String {
                value := item.GetString()
                if value != null {
                    result.Add(value)
                }
            }
        }

        return result
    }

    static func TargetFrameworkMatches(summaryTfm: string?, targetFramework: string): bool {
        summary := summaryTfm ?? ""
        if string.IsNullOrWhiteSpace(summary) {
            return true
        }

        if string.Equals(summary, targetFramework, StringComparison.OrdinalIgnoreCase) {
            return true
        }

        return string.Equals(summary, "*", StringComparison.Ordinal)
    }

    static func MethodMatches(pattern: string, target: string): bool {
        if string.IsNullOrWhiteSpace(pattern) {
            return false
        }

        if pattern.IndexOf('*') >= 0 && !pattern.EndsWith(".*", StringComparison.Ordinal) {
            if GlobMatches(pattern, target) {
                return true
            }

            return GlobMatches(pattern, "System." + target)
        }

        if pattern.EndsWith(".*", StringComparison.Ordinal) {
            prefix := pattern.Substring(0, pattern.Length - 1)
            if target.StartsWith(prefix, StringComparison.Ordinal) {
                return true
            }

            return target.EndsWith("." + prefix, StringComparison.Ordinal)
        }

        if string.Equals(pattern, target, StringComparison.Ordinal) {
            return true
        }

        return target.EndsWith("." + pattern, StringComparison.Ordinal)
    }

    static func GlobMatches(pattern: string, target: string): bool {
        parts := pattern.Split('*')
        position := 0
        i := 0
        while i < parts.Length {
            part := parts[i]
            if part.Length != 0 {
                found := target.IndexOf(part, position, StringComparison.Ordinal)
                if found < 0 {
                    return false
                }

                if position == 0 && !pattern.StartsWith("*", StringComparison.Ordinal) && found != 0 {
                    return false
                }

                position = found + part.Length
            }

            i = i + 1
        }

        if pattern.EndsWith("*", StringComparison.Ordinal) {
            return true
        }

        return position == target.Length
    }
}
