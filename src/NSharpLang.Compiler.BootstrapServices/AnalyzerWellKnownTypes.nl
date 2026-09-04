namespace NSharpLang.Compiler

import System
import System.IO
import System.Reflection


// The analyzer's WELL-KNOWN-TYPE fact bag.
//
// One instance is built per analysis from the analyzer's MetadataLoadContext and caches every CLR
// type the semantic phase compares against or constructs generics over. Holding these as metadata
// types rather than `typeof(...)` runtime types is what lets the analyzer reason about a project's
// own reference set instead of the compiler's; do not replace a field here with a `typeof`.
//
// The core assembly is PASSED IN rather than read off the context: `MetadataLoadContext`'s
// `CoreAssembly` property is not part of the columnar front end's external binding surface, and
// extending that surface is a compiler-capability change requiring a two-stage bootstrap. The single
// construction site reads it and hands it over, which is a mechanical argument and not policy.
//
// Required types throw when absent — an analyzer that cannot see `System.Int32` cannot produce
// trustworthy diagnostics, so failing loudly at construction is deliberate. Optional types stay null
// and every consumer is written to tolerate that.
//
// Do not reintroduce this type in C#, and do not put POLICY here: this class only resolves and
// holds. The tables that read it live in `AnalyzerWellKnownTypeFacts`.
class AnalyzerWellKnownTypes {
    Int32: Type
    Int64: Type
    Single: Type
    Double: Type
    Decimal: Type
    Byte: Type
    SByte: Type
    Int16: Type
    UInt16: Type
    UInt32: Type
    UInt64: Type
    Char: Type
    Boolean: Type
    String: Type
    Void: Type
    Object: Type

    SystemType: Type
    Delegate: Type

    NullableOpen: Type?

    ListOpen: Type?
    IEnumerableOpen: Type?
    IQueryableOpen: Type?
    ICollectionOpen: Type?
    IListOpen: Type?
    DictionaryOpen: Type?
    IDictionaryOpen: Type?

    TaskOpen: Type?
    ValueTaskOpen: Type?

    JsonTypeInfoOpen: Type?

    Action: Type?
    Action1: Type?
    Action2: Type?
    Action3: Type?
    Action4: Type?
    Func1: Type?
    Func2: Type?
    Func3: Type?
    Func4: Type?
    Func5: Type?

    context: MetadataLoadContext
    coreAssembly: Assembly
    coreLibraryAssembly: Assembly?
    runtimeTypesResolved: bool
    runtimeUnionOpen: Type?
    runtimeResultOpen: Type?

    constructor(metadataContext: MetadataLoadContext, core: Assembly) {
        context = metadataContext
        coreAssembly = core
        coreLibraryAssembly = null
        runtimeTypesResolved = false
        runtimeUnionOpen = null
        runtimeResultOpen = null

        try {
            coreLibraryAssembly = metadataContext.LoadFromAssemblyName("System.Private.CoreLib")
        } catch {
        }

        Int32 = ResolveRequired("System.Int32")
        Int64 = ResolveRequired("System.Int64")
        Single = ResolveRequired("System.Single")
        Double = ResolveRequired("System.Double")
        Decimal = ResolveRequired("System.Decimal")
        Byte = ResolveRequired("System.Byte")
        SByte = ResolveRequired("System.SByte")
        Int16 = ResolveRequired("System.Int16")
        UInt16 = ResolveRequired("System.UInt16")
        UInt32 = ResolveRequired("System.UInt32")
        UInt64 = ResolveRequired("System.UInt64")
        Char = ResolveRequired("System.Char")
        Boolean = ResolveRequired("System.Boolean")
        String = ResolveRequired("System.String")
        Void = ResolveRequired("System.Void")
        Object = ResolveRequired("System.Object")
        Delegate = ResolveRequired("System.Delegate")
        SystemType = ResolveRequired("System.Type")

        NullableOpen = Resolve("System.Nullable`1")
        Action = Resolve("System.Action")
        Action1 = Resolve("System.Action`1")
        Action2 = Resolve("System.Action`2")
        Action3 = Resolve("System.Action`3")
        Action4 = Resolve("System.Action`4")
        Func1 = Resolve("System.Func`1")
        Func2 = Resolve("System.Func`2")
        Func3 = Resolve("System.Func`3")
        Func4 = Resolve("System.Func`4")
        Func5 = Resolve("System.Func`5")

        jsonAssembly := metadataContext.LoadFromAssemblyName("System.Text.Json")
        JsonTypeInfoOpen = jsonAssembly.GetType("System.Text.Json.Serialization.Metadata.JsonTypeInfo`1")

        collectionsAssembly := metadataContext.LoadFromAssemblyName("System.Collections")
        ListOpen = FromCollections(collectionsAssembly, "System.Collections.Generic.List`1")
        ICollectionOpen = FromCollections(collectionsAssembly, "System.Collections.Generic.ICollection`1")
        IListOpen = FromCollections(collectionsAssembly, "System.Collections.Generic.IList`1")
        DictionaryOpen = FromCollections(collectionsAssembly, "System.Collections.Generic.Dictionary`2")
        IDictionaryOpen = FromCollections(collectionsAssembly, "System.Collections.Generic.IDictionary`2")

        IEnumerableOpen = Resolve("System.Collections.Generic.IEnumerable`1")

        expressionsAssembly := metadataContext.LoadFromAssemblyName("System.Linq.Expressions")
        IQueryableOpen = expressionsAssembly.GetType("System.Linq.IQueryable`1")

        TaskOpen = Resolve("System.Threading.Tasks.Task`1")
        ValueTaskOpen = Resolve("System.Threading.Tasks.ValueTask`1")
        if TaskOpen == null || ValueTaskOpen == null {
            threadingAssembly := metadataContext.LoadFromAssemblyName("System.Threading.Tasks")
            if TaskOpen == null {
                TaskOpen = threadingAssembly.GetType("System.Threading.Tasks.Task`1")
            }

            if ValueTaskOpen == null {
                ValueTaskOpen = threadingAssembly.GetType("System.Threading.Tasks.ValueTask`1")
            }
        }
    }

    // `NSharpLang.Runtime.Union<,>`, resolved on first read. The runtime assembly is optional — a
    // project that does not reference it simply never constructs a runtime union — so a missing
    // assembly is absorbed and the answer stays null for the rest of the analysis.
    func GetRuntimeUnionOpen(): Type? {
        EnsureRuntimeTypes()
        return runtimeUnionOpen
    }

    // `NSharpLang.Runtime.Result<,>`, resolved on first read under the same rules.
    func GetRuntimeResultOpen(): Type? {
        EnsureRuntimeTypes()
        return runtimeResultOpen
    }

    func EnsureRuntimeTypes() {
        if runtimeTypesResolved {
            return
        }

        runtimeTypesResolved = true

        try {
            runtimeAssembly := context.LoadFromAssemblyName("NSharpLang.Runtime")
            runtimeUnionOpen = runtimeAssembly.GetType("NSharpLang.Runtime.Union`2")
            runtimeResultOpen = runtimeAssembly.GetType("NSharpLang.Runtime.Result`2")
        } catch notFound: FileNotFoundException {
        }
    }

    // The core assembly first, then the split core library. Two probes are needed because the
    // reference set may split the framework across `System.Runtime` facades and
    // `System.Private.CoreLib` implementations.
    func Resolve(fullName: string): Type? {
        fromCore := coreAssembly.GetType(fullName)
        if fromCore != null {
            return fromCore
        }

        if coreLibraryAssembly == null {
            return null
        }

        return coreLibraryAssembly.GetType(fullName)
    }

    func ResolveRequired(fullName: string): Type {
        resolved := Resolve(fullName)
        if resolved == null {
            throw new InvalidOperationException("AnalyzerWellKnownTypes requires '" + fullName + "' in the metadata load context's core assembly, and neither it nor the core library defines it.")
        }

        return resolved
    }

    // The generic collection types are probed in `System.Collections` first and fall back to the
    // core probe, because a trimmed or facade-only reference set can carry them in either place.
    func FromCollections(collectionsAssembly: Assembly, fullName: string): Type? {
        fromCollections := collectionsAssembly.GetType(fullName)
        if fromCollections != null {
            return fromCollections
        }

        return Resolve(fullName)
    }
}
