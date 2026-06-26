namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic

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
    public static func Create(targetFramework: string): IReadOnlyList<HotSummaryEntry> {
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
