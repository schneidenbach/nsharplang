using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using System.Text.Json;
using YamlDotNet.Core.Events;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;
using YamlEmitter = YamlDotNet.Core.IEmitter;
using YamlExceptionType = YamlDotNet.Core.YamlException;
using YamlParser = YamlDotNet.Core.IParser;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// A user-defined struct being emitted: its <see cref="TypeBuilder"/> (a <see cref="System.ValueType"/>-based value
/// type) plus its field-name → <see cref="FieldBuilder"/> map (so construction and field access emit ldfld/stfld
/// against the builder handles directly — never <c>GetField</c>, which throws on an un-finalized TypeBuilder). Built
/// in PASS 0 of <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>.
/// </summary>
internal sealed class ColumnarStructDef
{
    internal ColumnarStructDef(TypeBuilder builder, string[] fieldOrder, Dictionary<string, FieldBuilder> fields, bool isReference, bool isRecord = false)
    {
        Builder = builder;
        FieldOrder = fieldOrder;
        Fields = fields;
        IsReference = isReference;
        IsRecord = isRecord;
    }

    internal TypeBuilder Builder { get; }
    internal string[] FieldOrder { get; private set; }
    internal Dictionary<string, FieldBuilder> Fields { get; }
    internal HashSet<string> NullableFields { get; } = new(StringComparer.Ordinal);
    internal void SetFieldOrder(string[] fieldOrder) => FieldOrder = fieldOrder;
    // Generic type parameters declared on this type (`class Box<T>` → "T" → its builder), or null for a
    // non-generic type. Member signatures and bodies resolve these names FIRST (before registries/builtins);
    // closed instantiations (`Box<int>`) MakeGenericType the Builder and rebind member tokens via
    // TypeBuilder.GetField/GetConstructor/GetMethod (reflection member queries throw on
    // TypeBuilderInstantiation — the same machinery the previous parity baseline uses).
    internal Dictionary<string, Type>? GenericParameters { get; set; }
    // True for a RECORD or CLASS (a reference type). For a record, DefaultCtor is its parameterless ctor (newobj target).
    internal bool IsReference { get; }
    // True for a RECORD specifically — records can never be BASE types (the legacy emitter emits them sealed) and record
    // inheritance is unmodelled; PASS 0a' declines both shapes.
    internal bool IsRecord { get; }
    // True for a synthesized NEWTYPE record struct (`type X = newtype T`): call-style
    // construction (`X(42)`) resolves to its single-parameter constructor — newtypes only,
    // matching the legacy emitter's RecordsTopLevelNewtypeNames gate.
    internal bool IsNewtype { get; init; }
    // True for an INTERFACE (defined Public|Interface|Abstract; Methods hold its ABSTRACT member
    // declarations; no fields/ctors). Living in the struct registry makes interface-typed
    // locals/params/returns resolve and `iface.Method(args)` dispatch (ldloc+callvirt) through the
    // EXISTING machinery; object-init declines via the null DefaultCtor, PASS 0d/0e skip it.
    internal bool IsInterface { get; init; }
    // Interfaces this interface EXTENDS. For an implementer, ImplementedInterfaces records the directly named
    // interfaces and this list lets lookup/completeness/upcasts walk inherited interface slots without duplicating
    // those MethodBuilders on the derived interface.
    internal List<ColumnarStructDef> InterfaceBases { get; } = new();
    // Direct interfaces this type IMPLEMENTS (`class C: IShape, IDisposable` — colon-list names reclassified in
    // PASS 0a' when they resolve to interface defs). Every direct and inherited interface member must be matched
    // by name+signature (completeness checked in PASS 0b — the pipeline emits an UNLOADABLE assembly for missing
    // members, known defect #26, so columnar declines instead) and the matching methods get Virtual|Final|NewSlot
    // + DefineMethodOverride, mirroring the legacy emitter's DeclareMethod.
    internal List<ColumnarStructDef> ImplementedInterfaces { get; } = new();
    internal List<Type> ExternalInterfaces { get; } = new();
    // Interface method names declared with a default body. Implementers are not required to override these slots;
    // if they do, override binding still wires the implementing method to the interface method.
    internal HashSet<string> DefaultInterfaceMethodNames { get; } = new(StringComparer.Ordinal);
    // The synthesized public parameterless constructor (the object-init `newobj` target) for a reference type with
    // NO user constructors — chains to object (no base) or to the base's parameterless ctor. Set in PASS 0d (after
    // user ctors are declared, so a derived default ctor can chain to a base USER 0-param ctor); null for a value
    // type or a type with user ctors.
    internal ConstructorBuilder? DefaultCtor { get; set; }
    // The declared BASE class's def (`class D: Base`), or null. Reference types only; set in PASS 0a'. Member
    // resolution (fields/methods/properties) walks this chain, nearest declaration first (modelling method hiding).
    internal ColumnarStructDef? BaseDef { get; set; }
    // Instance methods declared on this struct. Methods keeps the first declaration for name-existence checks and
    // non-overloaded interface helpers; MethodOverloads carries the full overload set for receiver call binding.
    // Populated in PASS 0; lets `receiver.Method(args)` resolve the instance call (ldloca receiver; <args>; call).
    internal Dictionary<string, (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)> Methods { get; } = new(StringComparer.Ordinal);
    internal Dictionary<string, List<(MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)>> MethodOverloads { get; } = new(StringComparer.Ordinal);
    // STATIC methods declared on this type, by name -> the declared overloads (distinct PARAM COUNT only; the N#
    // struct parser declines same-name/same-arity static overload sets before rows reach this pass). Resolved by
    // `TypeName.Method(args)` (chain-walked, nearest declaration first) and by bare calls inside this type's own
    // member bodies (after locals/params and sibling top-level functions — the empirically pinned N# order).
    internal Dictionary<string, List<(MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)>> StaticMethods { get; } = new(StringComparer.Ordinal);
    // STATIC fields declared on this type, by name -> the FieldBuilder. CLR-static (ldsfld/stsfld); excluded from
    // FieldOrder/Fields so object-init and positional construction never see them. Resolved by `TypeName.field`
    // (chain-walked) and by bare names inside INSTANCE member bodies only (the pipeline's pinned asymmetry).
    internal Dictionary<string, FieldBuilder> StaticFields { get; } = new(StringComparer.Ordinal);
    // STATIC computed properties, by name -> (static get_Name, static set_Name or null, property type). Resolved
    // by `TypeName.Name` reads (`call get_Name`) / writes (`call set_Name`, chain-walked) and by bare READS inside
    // INSTANCE member bodies (after instance members and static fields).
    internal Dictionary<string, (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType)> StaticProperties { get; } = new(StringComparer.Ordinal);
    // User CONSTRUCTORS (reference types this slice): each declared ConstructorBuilder, its param types, and any
    // default-argument literals captured from the declaration. Positional construction `new T(args)` matches a ctor by
    // provided args plus trailing defaults. Empty when the type has no user ctor (then DefaultCtor drives object-init).
    // A type with >=1 user ctor has NO DefaultCtor (object-init on it declines).
    internal List<(ConstructorBuilder Builder, Type[] ParamTypes, int[] DefaultKinds, string?[] DefaultTexts)> Constructors { get; } = new();
    // Private instance method synthesized from instance field initializers. Constructors call this immediately after
    // the base/sibling constructor chain, before the user body. It is never a public construction candidate.
    internal MethodBuilder? InstanceInitializerMethod { get; set; }
    // Own fields definitely assigned by the synthesized instance-initializer method. Reference constructor validation
    // treats these like top-level constructor assignments because every non-delegating constructor calls the method
    // before user body emission, and delegating constructors call a sibling that does.
    internal HashSet<string> InstanceInitializerFields { get; } = new(StringComparer.Ordinal);
    // Computed PROPERTIES, by name -> (the get_Name getter MethodBuilder, the set_Name setter MethodBuilder or null,
    // the property type). A `receiver.Name` read resolves to `callvirt get_Name`; a `receiver.Name = v` write (when a
    // setter exists) to `callvirt set_Name`.
    internal Dictionary<string, (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType)> Properties { get; } = new(StringComparer.Ordinal);
    // The SYNTHESIZED value-semantics members on a RECORD (the legacy emitter generates them only on records — a class
    // `.Equals` is its NL103): Equals(object) (null-check + isinst + per-field EqualityComparer<T>.Default),
    // GetHashCode (the 17/23 accumulator), and the `<Clone>$` MemberwiseClone wrapper `with` lowers through.
    // Null when the record's fields prevent the synthesis (builder-typed/generic field types) or the type is
    // generic — `.Equals`/`.GetHashCode`/`with` then decline.
    internal MethodBuilder? RecordEquals { get; set; }
    internal MethodBuilder? RecordGetHashCode { get; set; }
    internal MethodBuilder? RecordClone { get; set; }
}

/// <summary>
/// COLUMNAR PIPELINE — stage 4 SPIKE (docs/design/roadmap-to-done.md). Proof that the columnar node tables can
/// drive IL emission END-TO-END with no object AST: for a single trivial function it emits a real .NET assembly
/// (one static method) whose body IL is generated DIRECTLY from the columnar statement/expression tables, then
/// returns the assembly bytes so a caller can load + invoke it. This is the de-risking spike for Stage 4 — the
    /// emit primitives (<c>ldarg</c> / <c>ldc.i4</c> / arithmetic / <c>ret</c>) are exactly what the full columnar
    /// codegen emits as the supported surface grows.
///
/// Deliberately narrow: top-level <c>func</c> with INT params/return only (mixed-type arithmetic would need
/// conversions this spike does not emit). Statements: <c>:=</c> int locals, a simple <c>local = expr</c>
/// assignment, Return (value required), an <c>if</c>/<c>else</c> where BOTH branches always return (no
/// fall-through), and a <c>while</c> loop whose body does not always return. Value expressions: a parameter, a
/// <c>:=</c> local, an int literal, a parenthesized expr, an int unary <c>-</c>/<c>~</c>, or an int +/-/* binary.
/// <c>if</c> conditions are an
/// int comparison (<c>&lt; &gt; &lt;= &gt;= == !=</c>) only. Anything else returns false (the adapter declines
/// → the N# backend path is unaffected).
/// </summary>
internal sealed class ColumnarIlEmitter
{
    private readonly ColumnarNodeTable _nodes;
    private readonly string _source;
    private readonly Dictionary<string, int> _paramOrdinals;
    private readonly IReadOnlyDictionary<string, Type> _paramTypes;
    private readonly Type _returnType;
    // Tuple ELEMENT NAMES per tuple-typed variable (`t.x` -> ItemN): seeded from named param annotations,
    // grown at `:=`/typed-local declarations whose initializers/annotations carry names. The CLR erases
    // tuple names (ValueTuple<> is positional), so this is the only name source at member-access time.
    private readonly Dictionary<string, string?[]> _tupleNamesByVariable = new(StringComparer.Ordinal);
    // Sibling functions' RETURN tuple element names (for `mk().x` and `t := mk()` name derivation).
    private readonly IReadOnlyDictionary<string, string?[]>? _siblingReturnTupleNames;
    // Exceptions E2: while emitting INSIDE a protected region (try/catch bodies), `return` may not emit
    // `ret` — it stores the value into ProtectedResult (value functions) and `leave`s to ProtectedDone;
    // EmitBody appends the single `done: [ldloc result;] ret` tail when any leave-return occurred. One
    // shared pair per body (every try in the body leaves to the same tail). Spike-proven (/tmp/try-spike).
    private LocalBuilder? _protectedResult;
    private Label _protectedDone;
    private bool _protectedDoneCreated;
    private bool _inProtectedRegion;
    // ASYNC (synchronous lowering; real state machines deferred): non-null = this body's
    // WRAPPED CLR return (ValueTask/ValueTask<T>; Task/Task<T>
    // for `main`). _returnType holds the INNER declared type so every return-value check works
    // unchanged; returns WRAP before storing into the protected slot; the whole body runs inside
    // the fault guard (EmitBody) whose catch converts the exception to a faulted task.
    private readonly Type? _asyncReturnType;
    private readonly Type? _asyncResultType;
    private readonly bool _asyncReturnsValueTask;
    // True when the async unit-ness came from an EXPLICIT `: Task`/`: ValueTask` annotation — a
    // bare `return` is then a pipeline NL305 (the unit-task exemption covers fall-through only).
    private readonly bool _asyncBareReturnDeclines;
    // Set while a FINALLY handler's statements emit: control transfers OUT of a finally (return, or
    // break/continue to a loop outside it) are illegal IL. The analyzer now rejects those shapes with
    // NL319 (known defect #20 fixed front-door), so they cannot reach any emitter on the production
    // path — the declines below remain as this emitter's own contract guards. Loops OPENED inside the
    // finally still break/continue freely.
    private bool _inFinallyRegion;
    // Set by kind-57 checked/unchecked expression wrappers while their child emits. Checked arithmetic swaps the
    // integral +, -, and * opcodes to their overflow-checking variants; nested unchecked restores wrapping behavior.
    private bool _overflowCheckingEnabled;
    private readonly ILGenerator _il;
    // Sibling top-level functions callable from this body, by name -> (declared method, param types, return
    // type). All are declared (pass 1) before any body is emitted (pass 2), so a forward/self call resolves to
    // a MethodBuilder whose body is not yet emitted — the token is baked at CreateType/Save. Includes this
    // function itself, so direct recursion works. Param/return types are carried (rather than reflected) because
    // MethodBuilder.GetParameters()/ReturnType is unsupported before the type is created — and a Call checks each
    // argument's type against the callee's param types (int and bool are both i4, so a mismatch would otherwise
    // produce verifiable-but-wrong IL rather than declining).
    private readonly IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)> _siblings;
    // User-defined enums in this program, by name -> (finalized enum Type, member->value). Lets member access
    // `Enum.Member` and enum match patterns resolve their underlying-int constant, and types resolve `Color` to a
    // baked type that can close runtime generics.
    private readonly IReadOnlyDictionary<string, ColumnarEnumDef> _enumRegistry;
    // User-defined structs in this program, by name -> (TypeBuilder, field->FieldBuilder). Lets object-initializer
    // construction and field access resolve their FieldBuilders, and types resolve `Point` to its TypeBuilder.
    private readonly IReadOnlyDictionary<string, ColumnarStructDef> _structRegistry;
    // User-defined unions in this program, by name -> (abstract base + cases). Lets `Union` resolve to its base type
    // (the match-scrutinee / param type) and the exhaustiveness check enumerate the cases.
    private readonly IReadOnlyDictionary<string, ColumnarUnionDef> _unionRegistry;
    // Union CASES by qualified "Union.Case" name -> case. Lets object-initializer construction (`new Union.Case {…}`)
    // and union-case patterns (`Union.Case { f }`) resolve a case's ctor/fields/base directly by its dotted name.
    private readonly IReadOnlyDictionary<string, ColumnarUnionCaseDef> _unionCaseRegistry;
    private readonly IReadOnlyList<string>? _referenceAssemblyPaths;
    // When emitting a struct INSTANCE method body, the struct whose fields are accessible by BARE name (resolved to
    // `ldarg.0; ldfld`, since `this` is arg 0). Null for top-level functions (no implicit `this`/fields).
    private readonly ColumnarStructDef? _currentStruct;
    // The struct/record/class whose MEMBER body (instance method, STATIC method, constructor, or accessor) is being
    // emitted — null for a top-level function body. Unlike `_currentStruct` (the INSTANCE-context marker, null in a
    // static method so no implicit-`this` path can fire), this is set for static bodies too: it anchors bare
    // STATIC-method resolution (`Seven()` inside any member of the type resolves on the type's own chain).
    private readonly ColumnarStructDef? _enclosingType;
    // `:=` locals declared so far, by name. Each local's type is its LocalBuilder.LocalType (inferred from the
    // initializer), so the type-aware emitter checks assignments and reads against it.
    private readonly Dictionary<string, LocalBuilder> _locals = new(StringComparer.Ordinal);
    // Enclosing loops' break/continue targets (innermost on top). `break` branches to the loop's end label,
    // `continue` to its condition-check label. A break/continue outside any loop declines.
    // Loop branch targets, plus WHERE the loop was entered relative to exception regions: a break/continue
    // from INSIDE a protected region whose loop began OUTSIDE it crosses the region boundary — `br` is
    // invalid IL there; it must `leave` (which also runs an intervening finally). A loop wholly inside the
    // region branches with a plain `br` (probe-pinned both ways against the fixed legacy emitter). A branch out of
    // a FINALLY is illegal IL entirely — those decline.
    private readonly Stack<(Label Break, Label Continue, bool InProtectedRegion, bool InFinallyRegion)> _loopLabels = new();

    private static MethodInfo ResolveSimdReductionHelper(string name) =>
        typeof(NSharpLang.Runtime.SimdReductions).GetMethod(name)
        ?? throw new InvalidOperationException($"NSharpLang.Runtime.SimdReductions.{name} not found.");

    private static readonly MethodInfo s_sumInt32Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.SumInt32));
    private static readonly MethodInfo s_sumUInt32Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.SumUInt32));
    private static readonly MethodInfo s_sumInt64Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.SumInt64));
    private static readonly MethodInfo s_sumUInt64Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.SumUInt64));
    private static readonly MethodInfo s_countInRangeInt32 =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.CountInRangeInt32));
    private static readonly MethodInfo s_minInt32Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.MinInt32));
    private static readonly MethodInfo s_maxInt32Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.MaxInt32));
    private static readonly MethodInfo s_minMaxInt32Reduction =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.MinMaxInt32));
    private static readonly MethodInfo s_countTransitionsInt32 =
        ResolveSimdReductionHelper(nameof(NSharpLang.Runtime.SimdReductions.CountTransitionsInt32));
    private static readonly FieldInfo s_valueTupleItem1 =
        typeof(ValueTuple<int, int>).GetField("Item1")
        ?? throw new InvalidOperationException("ValueTuple<int,int>.Item1 not found.");
    private static readonly FieldInfo s_valueTupleItem2 =
        typeof(ValueTuple<int, int>).GetField("Item2")
        ?? throw new InvalidOperationException("ValueTuple<int,int>.Item2 not found.");

    private const int NSharpModifierOverride = 65536;

    private bool Decline(string siteId, string message, int nodeIdx = -1)
        => DeclineMember(siteId, message, nodeIdx, string.Empty);

    private bool DeclineMember(string siteId, string message, int nodeIdx, string memberName)
    {
        var spanStart = -1;
        var spanLength = 0;
        if (nodeIdx >= 0)
        {
            spanStart = _nodes.SpanStart(nodeIdx);
            spanLength = _nodes.SpanLength(nodeIdx);
        }

        ColumnarDeclineTrace.Record(siteId, message, spanStart, spanLength, memberName);
        return false;
    }

    private static bool DeclineStatic(string siteId, string message, string memberName = "", int spanStart = -1, int spanLength = 0)
    {
        ColumnarDeclineTrace.Record(siteId, message, spanStart, spanLength, memberName);
        return false;
    }

    // True when this emitter is producing a CONSTRUCTOR body. In a VALUE-TYPE ctor, `this` (arg 0)
    // is the managed pointer to the caller's storage (newobj passes the new value's address), so
    // bare field WRITES are correct there — unlike struct METHODS, whose receiver is a spilled
    // temp copy (mutation would write the copy; those stay declined).
    private readonly bool _isConstructorBody;
    // True only for the constructor body synthesized from a primary class/record/struct declaration. Its
    // generated assignments are `Field = parameter`; when the field and parameter share a name, the left side
    // must bind to the field even though ordinary explicit-constructor assignments keep parameter shadowing.
    private readonly bool _isSynthesizedInitializerBody;

    private ColumnarIlEmitter(
        ColumnarNodeTable nodes, string source,
        Dictionary<string, int> paramOrdinals, IReadOnlyDictionary<string, Type> paramTypes, Type returnType,
        ILGenerator il,
        IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)> siblings,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef> structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef> unionRegistry,
        IReadOnlyDictionary<string, ColumnarUnionCaseDef> unionCaseRegistry,
        ColumnarStructDef? currentStruct,
        ColumnarStructDef? enclosingType = null,
        bool isConstructorBody = false,
        bool isSynthesizedInitializerBody = false,
        TypeBuilder? programType = null,
        int[]? lambdaCounter = null,
        List<TypeBuilder>? displayClasses = null,
        Dictionary<string, (FieldBuilder BoxField, Type ValueType)>? boxedCaptures = null,
        Dictionary<string, (MethodBuilder Method, Type[] ParamTypes, Type ReturnType)>? localFuncs = null,
        Dictionary<int, string>? declaredLocalFuncNodes = null,
        IEnumerable<string>? visibleLocalFuncs = null,
        IReadOnlyDictionary<string, string?[]>? siblingReturnTupleNames = null,
        IReadOnlyDictionary<string, string?[]>? paramTupleNames = null,
        HashSet<string>? enclosingBindingNames = null,
        Type? asyncReturnType = null,
        bool asyncBareReturnDeclines = false,
        IReadOnlyList<string>? referenceAssemblyPaths = null)
    {
        _isConstructorBody = isConstructorBody;
        _isSynthesizedInitializerBody = isSynthesizedInitializerBody;
        _asyncReturnType = asyncReturnType;
        _asyncBareReturnDeclines = asyncBareReturnDeclines;
        if (asyncReturnType != null)
        {
            _asyncResultType = returnType == typeof(void) ? null : returnType;
            _asyncReturnsValueTask = asyncReturnType == typeof(System.Threading.Tasks.ValueTask)
                || (asyncReturnType.IsGenericType
                    && asyncReturnType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.ValueTask<>));
        }
        _enclosingBindingNames = enclosingBindingNames ?? s_noEnclosingBindings;
        _nodes = nodes;
        _source = source;
        _paramOrdinals = paramOrdinals;
        _paramTypes = paramTypes;
        _returnType = returnType;
        _siblingReturnTupleNames = siblingReturnTupleNames;
        if (paramTupleNames != null)
        {
            foreach (var (tupleParamName, tupleParamElementNames) in paramTupleNames)
                _tupleNamesByVariable[tupleParamName] = tupleParamElementNames;
        }
        _il = il;
        _siblings = siblings;
        _enumRegistry = enumRegistry;
        _structRegistry = structRegistry;
        _unionRegistry = unionRegistry;
        _unionCaseRegistry = unionCaseRegistry;
        _referenceAssemblyPaths = referenceAssemblyPaths;
        _currentStruct = currentStruct;
        _enclosingType = enclosingType ?? currentStruct;
        _programType = programType;
        _lambdaCounter = lambdaCounter;
        _displayClasses = displayClasses;
        _boxedCaptures = boxedCaptures;
        _localFuncs = localFuncs;
        _declaredLocalFuncNodes = declaredLocalFuncNodes;
        if (visibleLocalFuncs != null)
            _visibleLocalFuncs.UnionWith(visibleLocalFuncs);
    }

    // LAMBDA support (L1b): the Program TypeBuilder hosts synthesized `<Lambda>_{n}` static methods (null in
    // contexts that do not model lambdas, e.g. the single-function wrapper — a kind-39 node then declines);
    // the counter is a one-element box SHARED across every emitter instance of one program so names never
    // collide (a lambda body's sub-emitter can itself synthesize nested lambdas).
    private readonly TypeBuilder? _programType;
    private readonly int[]? _lambdaCounter;
    // CAPTURING lambdas (L3a): display-class TypeBuilders collected here bake BEFORE the Program type at
    // finalization (the legacy emitter's closure-types-first order). Shared across the program's emitter instances
    // like the counter; null in contexts that do not model lambdas.
    private readonly List<TypeBuilder>? _displayClasses;
    // The current body's root statement (set by EmitBody) — anchors the L3a never-mutated capture scan.
    private int _bodyRoot = -1;
    // NL316 ACROSS NESTED-BODY BOUNDARIES: every binding name visible in the ENCLOSING function at the point
    // this nested body (lambda / local function) was reached. The pipeline rejects ANY nested binding —
    // lambda param, local-func param, `:=`/typed local, foreach var, deconstruction name, catch var — that
    // shadows an enclosing binding ("'e' shadows an existing 'e' from an enclosing scope"), but a nested
    // sub-emitter's own maps cannot see the parent's names, so every binding site must ALSO check this set
    // (probe-found over-accepts: lambda locals/params, local-func locals/params, catch vars all compiled
    // pipeline-rejected NL316 programs). Lambdas get the parent's LIVE snapshot (textual visibility); local
    // functions get the parent's STRUCTURAL superset (their bodies emit after the parent's — extra declines
    // are safe under-acceptance). Empty for top-level bodies.
    private readonly HashSet<string> _enclosingBindingNames;
    private static readonly HashSet<string> s_noEnclosingBindings = new(StringComparer.Ordinal);

    // Whether `name` is bound ANYWHERE visible to code in this body — its own locals/params/lifted/boxed
    // tiers plus every enclosing binding. Declaring it again is the pipeline's NL316 — decline.
    private bool IsVisibleBindingName(string name)
        => _locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name) || _liftedLocals.ContainsKey(name)
           || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name))
           || _enclosingBindingNames.Contains(name);

    // The set a nested body created RIGHT NOW must treat as enclosing bindings (this emitter's live
    // visibility plus its own enclosing set — transitive for nested-in-nested chains).
    private HashSet<string> VisibleBindingNamesSnapshot()
    {
        var names = new HashSet<string>(_enclosingBindingNames, StringComparer.Ordinal);
        names.UnionWith(_locals.Keys);
        names.UnionWith(_paramOrdinals.Keys);
        names.UnionWith(_liftedLocals.Keys);
        if (_boxedCaptures != null)
            names.UnionWith(_boxedCaptures.Keys);
        return names;
    }

    // Every name any statement in a body table BINDS (`:=` 24, typed-local 40 name child, foreach 29 var,
    // deconstruction 30 names, catch-clause 50 vars) — the STRUCTURAL superset used for local-function
    // bodies, which emit after their parent body finished (no live snapshot exists). Type subtrees are safe
    // to recurse: type-kernel kinds are 0-7, disjoint from these binding kinds.
    private static void CollectBindingNames(ColumnarNodeTable nodes, string source, int node, HashSet<string> names)
    {
        switch (nodes.Kind(node))
        {
            case 24:
            case 29:
                if (nodes.ValueStart(node) >= 0)
                    names.Add(nodes.Text(source, node));
                break;
            case 30:
                for (var n = 0; n < nodes.ChildCount(node) - 1; n++)
                {
                    var child = nodes.Child(node, n);
                    if (nodes.Kind(child) == 6 && nodes.ValueStart(child) >= 0)
                        names.Add(nodes.Text(source, child));
                }

                break;
            case 40:
            case 50:
                if (nodes.ChildCount(node) == 2)
                {
                    var nameChild = nodes.Child(node, 0);
                    if (nodes.Kind(nameChild) == 6 && nodes.ValueStart(nameChild) >= 0)
                        names.Add(nodes.Text(source, nameChild));
                }

                break;
        }
        for (var c = 0; c < nodes.ChildCount(node); c++)
            CollectBindingNames(nodes, source, nodes.Child(node, c), names);
    }
    // MUTATED captures (L3b): names that are captured by some lambda in this body AND mutated via
    // bare-identifier assignment get LIFTED into a shared StrongBox<T> (the legacy emitter's box-lift model) —
    // the box reference is what closures snapshot, so mutation is shared in both directions.
    // _liftedCandidates is the EmitBody pre-scan verdict (drives DECLARATION shape); _liftedLocals holds
    // the live boxes (drives every read/write — checked BEFORE locals/params). Structural writes
    // (foreach vars, deconstructions) and member/index-receiver uses are NOT lifted: those names simply
    // never enter _liftedLocals, and their capture or usage declines exactly as in L3a.
    private HashSet<string>? _liftedCandidates;
    private readonly Dictionary<string, (LocalBuilder Box, Type ValueType)> _liftedLocals = new(StringComparer.Ordinal);
    // LOCAL FUNCTIONS (L4-i): name -> the synthesized `<parent>g__{n}` static (declared before the body
    // emits, so self/mutual recursion and parent calls all forward-reference MethodBuilders that bake at
    // Save). Checked in the bare-call order BEFORE siblings — a local function SHADOWS a same-named
    // sibling (probe-pinned: the pipeline calls the local). _declaredLocalFuncNodes holds the kind-41
    // body-node indices that were declared; any other kind-41 (a nested-block declaration) declines.
    private readonly Dictionary<string, (MethodBuilder Method, Type[] ParamTypes, Type ReturnType)>? _localFuncs;
    private readonly Dictionary<int, string>? _declaredLocalFuncNodes;
    // Local-function VISIBILITY is strictly TEXTUAL (probe-pinned: the pipeline NL412s a call before the
    // declaration, in the parent AND between locals — so true mutual recursion is impossible; only
    // self-recursion and backward calls). A name enters this set when its kind-41 statement is reached;
    // the call tier requires it. Local bodies start pre-populated with declarations up to themselves.
    private readonly HashSet<string> _visibleLocalFuncs = new(StringComparer.Ordinal);
    // In a CLOSURE emitter: captured-and-lifted names -> the display field holding the shared box. Reads
    // emit `ldarg.0; ldfld boxField; ldfld Value`, writes `ldarg.0; ldfld boxField; <v>; stfld Value` —
    // checked before every other resolution tier (a boxed name is never also a lambda param or local).
    private readonly Dictionary<string, (FieldBuilder BoxField, Type ValueType)>? _boxedCaptures;

    // The types the type-aware emitter currently handles: int/bool/long/uint/ulong scalars, plus a
    // single-dimension ARRAY of a supported element type (e.g. int[], uint[], long[], ulong[]). (Mixed
    // arithmetic — implicit widening — is not modelled; an expression's operands must share one type.) ulong is
    // u8 on the stack like long (i8), but its arithmetic uses the UNSIGNED opcodes (Shr_Un/Div_Un/Rem_Un and
    // unsigned compares) — see the binary/comparison cases.
    private static bool IsSupportedType(Type t) =>
        t == typeof(int) || t == typeof(bool) || t == typeof(long) || t == typeof(ulong)
        || t == typeof(string) || t == typeof(char) || t == typeof(double) || t == typeof(float)
        || t == typeof(byte) || t == typeof(sbyte) || t == typeof(short) || t == typeof(ushort)
        || t == typeof(uint)                      // small ints + uint (SC-4): i4-slot scalars; arithmetic
                                                  // promotes small ints to INT (ECMA §12.4.7), uint runs native u4
        || t == typeof(decimal)                   // decimal (SC-6): a baked VALUE struct — arithmetic and
                                                  // comparisons call System.Decimal's op_* methods
        || IsSupportedNullable(t)                 // Nullable<T> over a baked value scalar (null N2)
        || t == typeof(object)
        || t == typeof(Stream)
        || t == typeof(StreamReader)
        || t == typeof(StringComparer)
        || t == typeof(TextWriter)
        || t == typeof(System.Text.StringBuilder)
        || t == typeof(DateTime)
        || t == typeof(TimeSpan)
        || t == typeof(System.Threading.CancellationToken)
        || t == typeof(Random)
        || ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(t)
        || IsSupportedTaskType(t)
        || typeof(Exception).IsAssignableFrom(t)
        || t == typeof(IList)
        || t == typeof(Type)
        || t == typeof(Version)
        || t == typeof(Assembly)
        || t == typeof(PropertyInfo)
        || t == typeof(FieldInfo)
        || t == typeof(LocalBuilder)
        || t == typeof(FieldBuilder)
        || t == typeof(TypeBuilder)
        || t == typeof(MethodBuilder)
        || t == typeof(MethodInfo)
        || t == typeof(ConstructorBuilder)
        || t == typeof(ILGenerator)
        || IsSupportedJsonType(t)
        || IsSupportedExternalType(t)
        || IsEnumType(t)                          // a user-defined enum — its own i4-underlying value type
        || t is TypeBuilder                       // a user-defined struct (value type) OR record (reference type);
                                                  // only those reach here as a resolved type — the Program type never does
        || t is GenericTypeParameterBuilder       // a generic type/method parameter (T) — valid member/param/local type
        || IsClosedUserGenericInstantiation(t)    // Box<int> over a user generic definition (TypeBuilderInstantiation)
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!))
        || IsSupportedValueTuple(t)
        || IsSupportedDelegateType(t)             // a closed System.Func/Action over baked runtime types (L1a)
        || IsSupportedCollectionType(t);          // a closed List<T>/Dictionary<K,V>/HashSet<T> over supported runtime types

    // By-ref types are valid only in PARAMETER slots for this slice. The element type must already be part of the
    // supported value/reference surface so ref/out locals can be loaded by the same addressability paths as writes.
    private static bool IsSupportedParameterType(Type t) =>
        IsSupportedType(t)
        || (t.IsByRef && IsSupportedByRefElementType(t.GetElementType()!));

    private static bool IsEnumType(Type t)
    {
        if (t is EnumBuilder)
            return true;
        if (t is TypeBuilder builder)
        {
            try
            {
                return builder.BaseType == typeof(Enum);
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }
        try
        {
            return t.IsEnum;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private static bool IsSupportedExternalType(Type t) =>
        t.Assembly == typeof(IYamlTypeConverter).Assembly
        || IsSupportedAspNetExternalReferenceType(t);

    private static bool IsSupportedAspNetExternalReferenceType(Type t)
    {
        if (t.IsValueType || t.IsByRef || t.IsPointer || t.ContainsGenericParameters)
            return false;

        var ns = t.Namespace ?? string.Empty;
        return ns.StartsWith("Microsoft.AspNetCore.", StringComparison.Ordinal)
               || ns.StartsWith("Microsoft.Extensions.Hosting", StringComparison.Ordinal);
    }

    private static bool IsSupportedTaskType(Type t)
    {
        if (t == typeof(System.Threading.Tasks.Task) || t == typeof(System.Threading.Tasks.ValueTask))
            return true;
        if (!t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        var definition = t.GetGenericTypeDefinition();
        if (definition != typeof(System.Threading.Tasks.Task<>) && definition != typeof(System.Threading.Tasks.ValueTask<>))
            return false;
        return IsSupportedType(t.GetGenericArguments()[0]);
    }

    private static bool IsSupportedJsonType(Type t) =>
        t == typeof(JsonElement)
        || t == typeof(JsonDocument)
        || t == typeof(JsonValueKind)
        || t == typeof(JsonSerializerOptions)
        || t == typeof(JsonNamingPolicy)
        || t == typeof(JsonElement.ArrayEnumerator)
        || t == typeof(JsonElement.ObjectEnumerator)
        || t == typeof(JsonProperty);

    private static void TryRegisterEnumAlias(Dictionary<string, ColumnarEnumDef> registry, string name, ColumnarEnumDef def)
    {
        var shortName = ColumnarTypeCanonicalizer.UnqualifiedTypeName(name);
        if (!registry.ContainsKey(shortName))
            registry[shortName] = def;
    }

    private static void TryRegisterStructAlias(Dictionary<string, ColumnarStructDef> registry, string name, ColumnarStructDef def)
    {
        var shortName = ColumnarTypeCanonicalizer.UnqualifiedTypeName(name);
        if (!registry.ContainsKey(shortName))
            registry[shortName] = def;
    }

    private static void TryRegisterUnionAlias(Dictionary<string, ColumnarUnionDef> registry, string name, ColumnarUnionDef def)
    {
        var shortName = ColumnarTypeCanonicalizer.UnqualifiedTypeName(name);
        if (!registry.ContainsKey(shortName))
            registry[shortName] = def;
    }

    private static string UnqualifyGenericHead(string canonical, int genericOpen)
    {
        var head = canonical.Substring(0, genericOpen);
        var shortHead = ColumnarTypeCanonicalizer.UnqualifiedTypeName(head);
        return string.Equals(head, shortHead, StringComparison.Ordinal)
            ? canonical
            : shortHead + canonical.Substring(genericOpen);
    }

    private static string ShortUnionCaseKey(string qualifiedCase)
    {
        var lastDot = qualifiedCase.LastIndexOf('.');
        if (lastDot <= 0 || lastDot + 1 >= qualifiedCase.Length)
            return qualifiedCase;
        var unionName = qualifiedCase.Substring(0, lastDot);
        var caseName = qualifiedCase.Substring(lastDot + 1);
        return ColumnarTypeCanonicalizer.UnqualifiedTypeName(unionName) + "." + caseName;
    }

    private static bool IsSupportedByRefElementType(Type t) =>
        !t.IsByRef && IsSupportedType(t);

    // A closed KeyValuePair<K,V> — the Dictionary foreach loop variable's type (only that path produces
    // it; .Key/.Value resolve via the case-8 KVP arms). Builder-bound instantiations (KeyValuePair over a
    // TypeBuilder value) qualify: GetGenericTypeDefinition works on a TypeBuilderInstantiation (spike-proven)
    // and the getters rebind.
    private static bool IsSupportedKeyValuePairType(Type t)
        => t.IsGenericType && !t.IsGenericTypeDefinition && t is not TypeBuilder
           && t.GetGenericTypeDefinition() == typeof(KeyValuePair<,>);

    // A closed BCL List<T>/Dictionary<K,V>/HashSet<T>. Type arguments may be baked runtime types OR builder-bound
    // (a user TypeBuilder element / a generic function's own T) — TryResolveType's collection branches
    // gate WHICH arguments are admissible; member binding routes through ResolveClosedGenericMethod/Ctor
    // so builder-bound instantiations rebind from the open definition.
    private static bool IsSupportedCollectionType(Type t)
    {
        if (t is TypeBuilder || t is EnumBuilder || !t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        Type def;
            def = t.GetGenericTypeDefinition();
        return def == typeof(List<>)
            || def == typeof(Dictionary<,>)
            || def == typeof(HashSet<>)
            || def == typeof(Stack<>)
            || def == typeof(IReadOnlyList<>)
            || def == typeof(IReadOnlyCollection<>)
            || def == typeof(IReadOnlySet<>)
            || def == typeof(IEnumerable<>);
    }

    private static bool IsSupportedIndexableCollectionType(Type t)
    {
        if (!IsSupportedCollectionType(t))
            return false;
        var def = t.GetGenericTypeDefinition();
        return def == typeof(List<>) || def == typeof(Dictionary<,>);
    }

    private static bool TryResolveCollectionCountGetter(Type t, out MethodInfo getter)
    {
        getter = null!;
        if (!IsSupportedCollectionType(t))
            return false;
        var def = t.GetGenericTypeDefinition();
        if (def == typeof(IEnumerable<>))
            return false;
        var countOwner = t;
        if (def == typeof(IReadOnlyList<>) || def == typeof(IReadOnlySet<>))
            countOwner = typeof(IReadOnlyCollection<>).MakeGenericType(t.GetGenericArguments()[0]);
        var openGetter = countOwner.GetGenericTypeDefinition().GetProperty("Count")?.GetGetMethod();
        if (openGetter == null)
            return false;
        getter = ResolveClosedGenericMethod(countOwner, openGetter);
        return true;
    }

    // True when a type carries a Reflection.Emit builder-shaped type anywhere in its shape: a TypeBuilder/EnumBuilder/
    // generic type parameter itself, an array over one, or a generic instantiation any of whose arguments
    // does (List<Pt>, Dictionary<string,T>, KeyValuePair<string,Pt>, IEnumerable<Pt>, ...). Plain
    // reflection member lookups (GetMethod/GetProperty/GetConstructor/GetField) throw NotSupportedException
    // on such closed instantiations — members must REBIND from the open runtime definition. NOTE (spike-
    // proven): neither `Module is ModuleBuilder` nor `Assembly is AssemblyBuilder` nor
    // ContainsGenericParameters detects these — a BCL-headed TypeBuilderInstantiation reports the OPEN
    // definition's CoreLib module/assembly, and ContainsGenericParameters is false even over an open T.
    // Baked Reflection.Emit enums still surface as TypeBuilderImpl, so they stay builder-bound for member-token
    // rebind purposes even though they are admissible as enum keys/elements.
    private static bool ContainsBuilderBoundType(Type t)
    {
        if (t is TypeBuilder || t is EnumBuilder || t.IsGenericParameter)
            return true;
        if (t.IsSZArray)
            return ContainsBuilderBoundType(t.GetElementType()!);
        if (!t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        Type def;
            def = t.GetGenericTypeDefinition();
        if (def is TypeBuilder)
            return true; // a USER-headed closed instantiation (Box<int>): its very DEFINITION is un-baked
                         // — every handle on it (and TypeHandle itself) is builder-bound even when all
                         // arguments are baked (adversarial-review finding: the argument-only recursion
                         // reported Box<int> as baked and routed it into the GetMethodFromHandle branch).
        foreach (var arg in t.GetGenericArguments())
        {
            if (ContainsBuilderBoundType(arg))
                return true;
        }
        return false;
    }

    // Key/equality admissibility uses a stricter question than member-token resolution: baked emitted enums are
    // stable i4 values, but records/struct builders and generic parameters still make hashing/equality depend on
    // generated type behavior that has separate parity gates.
    private static bool ContainsNonEnumBuilderBoundType(Type t)
    {
        if (t is EnumBuilder)
            return true;
        if (IsEnumType(t))
            return false;
        if (t is TypeBuilder || t.IsGenericParameter)
            return true;
        if (t.IsSZArray)
            return ContainsNonEnumBuilderBoundType(t.GetElementType()!);
        if (!t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        Type def;
            def = t.GetGenericTypeDefinition();
        if (def is TypeBuilder)
            return true;
        foreach (var arg in t.GetGenericArguments())
        {
            if (ContainsNonEnumBuilderBoundType(arg))
                return true;
        }
        return false;
    }

    // ASYNC return shape (the legacy emitter's GetDeclaredFunctionReturnType + WrapAsyncReturnType): the
    // declared canonical resolves to the INNER type (`void` for unit); the METHOD's CLR return is
    // the wrap — ValueTask/ValueTask<T> by default, Task/Task<T> for `main` (case-insensitive, the
    // legacy emitter's IsEntryPointFunction rule). An EXPLICIT task-like annotation keeps its declared
    // family with its declared inner. Unresolvable/unsupported inners decline.
    private static bool TryComputeAsyncReturnShape(string name, string canonical,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry,
        out Type inner, out Type wrapped)
    {
        inner = typeof(void);
        wrapped = null!;
        var isEntryPoint = string.Equals(name, "main", StringComparison.OrdinalIgnoreCase);
        if (canonical == "Task")
        {
            wrapped = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (canonical == "ValueTask")
        {
            wrapped = typeof(System.Threading.Tasks.ValueTask);
            return true;
        }
        if (canonical.StartsWith("Task<", StringComparison.Ordinal) && canonical[^1] == '>')
        {
            if (!TryResolveType(canonical.Substring(5, canonical.Length - 6), enumRegistry, structRegistry, unionRegistry, out inner)
                || !IsSupportedType(inner))
                return false;
            wrapped = typeof(System.Threading.Tasks.Task<>).MakeGenericType(inner);
            return true;
        }
        if (canonical.StartsWith("ValueTask<", StringComparison.Ordinal) && canonical[^1] == '>')
        {
            if (!TryResolveType(canonical.Substring(10, canonical.Length - 11), enumRegistry, structRegistry, unionRegistry, out inner)
                || !IsSupportedType(inner))
                return false;
            wrapped = typeof(System.Threading.Tasks.ValueTask<>).MakeGenericType(inner);
            return true;
        }
        if (canonical == "void")
        {
            wrapped = isEntryPoint ? typeof(System.Threading.Tasks.Task) : typeof(System.Threading.Tasks.ValueTask);
            return true;
        }
        if (!TryResolveType(canonical, enumRegistry, structRegistry, unionRegistry, out inner)
            || !IsSupportedType(inner))
            return false;
        wrapped = isEntryPoint
            ? typeof(System.Threading.Tasks.Task<>).MakeGenericType(inner)
            : typeof(System.Threading.Tasks.ValueTask<>).MakeGenericType(inner);
        return true;
    }

    // The production pipeline REJECTS closed-generic uses of `List<...>`/`Dictionary<...>`/`HashSet<...>` whenever a USER
    // type with that name is also declared — NL207 for a non-generic user type, and for a user GENERIC
    // List<T>/HashSet<T> the analyzer binds the BCL collection and rejects its members (NL303, probe-pinned) — so neither
    // the BCL collection arms nor the user-generic resolution may claim these heads: decline the canonical
    // entirely so this backend never accepts a source shape the analyzer rejected.
    private static bool IsCollectionHeadShadowedByUserType(string headName,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry)
        => (headName == "List" || headName == "Dictionary" || headName == "HashSet" || headName == "Stack")
           && ((enumRegistry?.ContainsKey(headName) ?? false)
               || (structRegistry?.ContainsKey(headName) ?? false)
               || (unionRegistry?.ContainsKey(headName) ?? false));

    // Resolve a member of a CLOSED BCL generic instantiation from its OPEN definition's member handle:
    // builder-bound instantiations rebind via TypeBuilder.GetMethod/GetConstructor (the only legal member
    // resolution on a TypeBuilderInstantiation — the legacy emitter's TryGetDeclaredGeneratedRuntimeMethod /
    // BindRuntimeConstructorCall idiom); fully baked instantiations resolve the closed runtime handle.
    private static MethodInfo ResolveClosedGenericMethod(Type closedType, MethodInfo openMethod)
        => ContainsBuilderBoundType(closedType)
            ? TypeBuilder.GetMethod(closedType, openMethod)
            : (MethodInfo)MethodBase.GetMethodFromHandle(openMethod.MethodHandle, closedType.TypeHandle)!;

    private static ConstructorInfo ResolveClosedGenericCtor(Type closedType, ConstructorInfo openCtor)
        => ContainsBuilderBoundType(closedType)
            ? TypeBuilder.GetConstructor(closedType, openCtor)
            : (ConstructorInfo)MethodBase.GetMethodFromHandle(openCtor.MethodHandle, closedType.TypeHandle)!;

    // The element/value types a collection may close over (the builder-element rebind rung):
    // - a user TypeBuilder (record/class/struct under construction) — members rebind, probe-pinned working;
    // - a nested admissible collection (List<List<Pt>>, List<HashSet<int>>) — its own resolution already vetted the inner args;
    // - the BAKED surface (scalars/string/enums/baked closed generics) exactly as before.
    // PINNED DECLINES (legacy-emitter accepted, flip in later rungs): user-headed closed generics (List<Box<int>>),
    // builder-bound key/equality shapes, and tuples/delegates over builders.
    private static bool IsAdmissibleCollectionElement(Type t)
    {
        if (t is EnumBuilder)
            return false;
        if (IsEnumType(t))
            return true;
        if (t is TypeBuilder)
            return true;
        if (t.IsGenericType && !t.IsGenericTypeDefinition)
        {
            Type def;
                def = t.GetGenericTypeDefinition();
            if (def == typeof(List<>) || def == typeof(Dictionary<,>) || def == typeof(HashSet<>) || def == typeof(Stack<>))
                return true;
            if (ContainsBuilderBoundType(t))
                return false;
        }
        return IsSupportedType(t) && !ContainsBuilderBoundType(t);
    }

    // HashSet<T> elements are keys: accepting builder-bound elements would make lookup behavior depend on
    // generated Equals/GetHashCode synthesis before that key path has parity evidence.
    private static bool IsAdmissibleHashSetElement(Type t)
        => IsAdmissibleCollectionElement(t) && !ContainsNonEnumBuilderBoundType(t);

    // A closed System.Func/Action delegate over BAKED runtime types (the L1a delegate surface), or the bare
    // System.Action — valid as a param/return/local so delegate-typed parameters can be received and invoked
    // (`t(v)` -> callvirt Invoke). Builder-arg instantiations are excluded: ctor/Invoke resolution throws on
    // a runtime generic closed over an un-baked builder type (the same rule the tuple elements apply).
    private static bool IsSupportedDelegateType(Type t)
        => TryGetSupportedDelegateSignature(t, allowBuilderBoundArguments: false, out _, out _, out _);

    private static bool IsSupportedContextualDelegateType(Type t)
        => TryGetSupportedDelegateSignature(t, allowBuilderBoundArguments: true, out _, out _, out _);

    private static bool TryGetSupportedDelegateSignature(
        Type t, bool allowBuilderBoundArguments, out Type returnType, out Type[] parameterTypes, out ConstructorInfo delegateCtor)
    {
        returnType = null!;
        parameterTypes = System.Array.Empty<Type>();
        delegateCtor = null!;

        if (t == typeof(Action))
        {
            returnType = typeof(void);
            delegateCtor = typeof(Action).GetConstructor(new[] { typeof(object), typeof(IntPtr) })!;
            return delegateCtor != null;
        }

        if (t is TypeBuilder || t is EnumBuilder || !t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        Type def;
            def = t.GetGenericTypeDefinition();
        var args = t.GetGenericArguments();

        if (def == typeof(Action<>) || def == typeof(Action<,>) || def == typeof(Action<,,>) || def == typeof(Action<,,,>))
        {
            returnType = typeof(void);
            parameterTypes = args;
        }
        else if (def == typeof(Func<>) || def == typeof(Func<,>) || def == typeof(Func<,,>) || def == typeof(Func<,,,>)
                 || def == typeof(Func<,,,,>))
        {
            returnType = args[^1];
            parameterTypes = new Type[args.Length - 1];
            System.Array.Copy(args, parameterTypes, args.Length - 1);
        }
        else
        {
            return false;
        }

        foreach (var arg in args)
        {
            // Stored delegate slots keep the original baked-only guarantee. Contextual lambdas passed directly to
            // modeled calls may close over builder-bound N# types because the synthesized method is emitted in the
            // same module and the delegate never has to be reflected as a stable product API surface.
            if (!allowBuilderBoundArguments && (arg.Assembly is AssemblyBuilder || ContainsBuilderBoundType(arg)))
                return false;
            if (!IsSupportedType(arg))
                return false;
        }

        var openCtor = def.GetConstructor(new[] { typeof(object), typeof(IntPtr) });
        if (openCtor == null)
            return false;
        delegateCtor = ContainsBuilderBoundType(t) ? TypeBuilder.GetConstructor(t, openCtor) : t.GetConstructor(new[] { typeof(object), typeof(IntPtr) })!;
        return delegateCtor != null;
    }

    // A closed instantiation of a USER generic type (Box<int> where Box is an uncreated TypeBuilder).
    // Reflection member queries throw on these — member access goes through the open definition's
    // bookkeeping with rebound tokens, mirroring the previous parity baseline's closed-generic machinery.
    private static bool IsClosedUserGenericInstantiation(Type t)
    {
        if (t is TypeBuilder || !t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
            return t.GetGenericTypeDefinition() is TypeBuilder;
    }

    private static Type? OpenValueTupleType(int arity) => arity switch
    {
        2 => typeof(ValueTuple<,>),
        3 => typeof(ValueTuple<,,>),
        4 => typeof(ValueTuple<,,,>),
        5 => typeof(ValueTuple<,,,,>),
        6 => typeof(ValueTuple<,,,,,>),
        7 => typeof(ValueTuple<,,,,,,>),
        _ => null,
    };

    // A positional System.ValueTuple of arity 2-7 whose every element is itself a supported type. (1-tuples and
    // the >7 nested-TRest form are not modelled.) Admits a tuple as a `:=` local / value, NOT as an array element.
    private static bool IsSupportedValueTuple(Type t)
    {
        if (!t.IsGenericType)
            return false;
        var def = t.GetGenericTypeDefinition();
        if (def != typeof(ValueTuple<,>) && def != typeof(ValueTuple<,,>) && def != typeof(ValueTuple<,,,>)
            && def != typeof(ValueTuple<,,,,>) && def != typeof(ValueTuple<,,,,,>) && def != typeof(ValueTuple<,,,,,,>))
            return false;
        foreach (var arg in t.GetGenericArguments())
        {
            // Exclude enum elements and user-struct TypeBuilder elements: enum-in-tuple remains outside this slice
            // (value-comparison parity across independently emitted enum types needs its own proof), and a
            // ValueTuple<…> instantiated over a builder type cannot resolve its ctor/ItemN fields via plain
            // reflection (GetConstructor/GetField throw NotSupportedException at emit). Keep both as clean declines,
            // consistent with the array-element decline. Enums and structs are modelled as scalars/locals only.
            // Delegates are likewise excluded from tuple elements (the L1a delegate surface is params/locals only).
            // CLOSED user-generic instantiations (Box<int>, Opt<int> — TypeBuilderInstantiation, not TypeBuilder)
            // have the identical reflection-throw behavior, so they are excluded by the same rule (adversarial-
            // review hardening — an uncaught NotSupportedException is a compiler crash, not a clean decline).
            // Builder-bound COLLECTION elements ((int, List<Pt>)) are excluded by the same rule: the
            // ValueTuple closed over them is a TypeBuilderInstantiation whose ctor/ItemN lookups throw.
            if (IsEnumType(arg) || arg is TypeBuilder || IsClosedUserGenericInstantiation(arg)
                || IsSupportedDelegateType(arg) || ContainsBuilderBoundType(arg) || !IsSupportedType(arg))
                return false;
        }

        return true;
    }

    // The parameterless constructor a derived type may chain to on `def`: the synthesized default ctor (PASS 0d)
    // when the type has no user ctors, else a USER 0-param ctor if one was declared (PASS 0c). Null when the type
    // has only parameterized user ctors — an implicit (or explicit `: base()`) chain to it is impossible.
    private static ConstructorBuilder? ResolveParameterlessCtor(ColumnarStructDef def)
    {
        if (def.DefaultCtor != null)
            return def.DefaultCtor;
        foreach (var (builder, paramTypes, _, _) in def.Constructors)
        {
            if (paramTypes.Length == 0)
                return builder;
        }
        return null;
    }

    private static bool IsZeroParamSynthesizedInitializer(ColumnarConstructorInput ctor)
        => ctor.IsSynthesizedInitializer && ctor.Body.ParamNames.Length == 0;

    private static void CollectTopLevelFieldInitializerAssignments(ColumnarFunctionInput body, string source, HashSet<string> fieldNames)
    {
        var nodes = body.BodyNodes;
        var bodyRoot = body.BodyRoot;
        if (bodyRoot < 0 || nodes.Kind(bodyRoot) != 25)
            return;
        for (var n = 0; n < nodes.ChildCount(bodyRoot); n++)
        {
            var stmt = nodes.Child(bodyRoot, n);
            if (nodes.Kind(stmt) != 23 || nodes.ChildCount(stmt) != 1)
                continue;
            var expr = nodes.Child(stmt, 0);
            if (nodes.Kind(expr) != 14 || nodes.Text(source, expr) != "=" || nodes.ChildCount(expr) != 2)
                continue;
            var target = nodes.Child(expr, 0);
            if (nodes.Kind(target) == 6 && nodes.ValueStart(target) >= 0)
                fieldNames.Add(nodes.Text(source, target));
        }
    }

    private static bool HasCallableConstructor(ColumnarStructInput st)
    {
        foreach (var ctor in st.Constructors)
        {
            if (!IsZeroParamSynthesizedInitializer(ctor))
                return true;
        }
        return false;
    }

    private static void EmitCtorBaseChain(ILGenerator il, ColumnarStructDef def, ConstructorInfo objectCtor)
    {
        if (def.BaseDef != null)
        {
            var baseParameterless = ResolveParameterlessCtor(def.BaseDef)
                ?? throw new InvalidOperationException("base has only parameterized constructors");
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, baseParameterless);
        }
        else
        {
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Call, objectCtor);
        }
    }

    private static void EmitInstanceInitializerCall(ILGenerator il, ColumnarStructDef def)
    {
        if (def.InstanceInitializerMethod == null)
            return;
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Call, def.InstanceInitializerMethod);
    }

    // Chain-walking member resolution: find `name` on `def` or any base on its chain, NEAREST declaration first —
    // exactly the N# pipeline's resolution order (a derived method HIDING a base method resolves to the derived
    // one; field/property shadowing never reaches here — PASS 0b'' declined it). Null/false when no declaration
    // on the whole chain carries the name.
    private static bool TryFindFieldOnChain(ColumnarStructDef def, string name, out FieldBuilder field)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.Fields.TryGetValue(name, out field!))
                return true;
        }
        field = null!;
        return false;
    }

    private static void AddInstanceMethod(
        ColumnarStructDef def,
        string name,
        (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        if (!def.Methods.ContainsKey(name))
            def.Methods[name] = method;
        if (!def.MethodOverloads.TryGetValue(name, out var overloads))
        {
            overloads = new List<(MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)>();
            def.MethodOverloads[name] = overloads;
        }
        overloads.Add(method);
    }

    private static bool TryFindMethodOnChain(ColumnarStructDef def, string name, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.Methods.TryGetValue(name, out method))
                return true;
            if (d.IsInterface && TryFindMethodOnInterfaceBases(d, name, out method))
                return true;
        }
        method = default;
        return false;
    }

    private static bool TryFindMethodOnChain(ColumnarStructDef def, string name, int argCount, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.MethodOverloads.TryGetValue(name, out var overloads))
            {
                foreach (var candidate in overloads)
                {
                    if (candidate.ParamTypes.Length == argCount)
                    {
                        method = candidate;
                        return true;
                    }
                }
            }
            if (d.IsInterface && TryFindMethodOnInterfaceBases(d, name, argCount, out method))
                return true;
        }
        method = default;
        return false;
    }

    private static bool TryFindMethodOnInterfaceBases(
        ColumnarStructDef def, string name, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        foreach (var baseInterface in def.InterfaceBases)
        {
            if (baseInterface.Methods.TryGetValue(name, out method))
                return true;
            if (TryFindMethodOnInterfaceBases(baseInterface, name, out method))
                return true;
        }
        method = default;
        return false;
    }

    private static bool TryFindMethodOnInterfaceBases(
        ColumnarStructDef def, string name, int argCount, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        foreach (var baseInterface in def.InterfaceBases)
        {
            if (baseInterface.MethodOverloads.TryGetValue(name, out var overloads))
            {
                foreach (var candidate in overloads)
                {
                    if (candidate.ParamTypes.Length == argCount)
                    {
                        method = candidate;
                        return true;
                    }
                }
            }
            if (TryFindMethodOnInterfaceBases(baseInterface, name, argCount, out method))
                return true;
        }
        method = default;
        return false;
    }

    private static bool TryFindObjectOverrideTarget(string name, Type returnType, Type[] paramTypes, out MethodInfo target)
    {
        target = null!;

        if (name == "ToString" && returnType == typeof(string) && paramTypes.Length == 0)
        {
            target = typeof(object).GetMethod(nameof(ToString), Type.EmptyTypes)!;
            return true;
        }

        if (name == "Equals" && returnType == typeof(bool) && paramTypes.Length == 1 && paramTypes[0] == typeof(object))
        {
            target = typeof(object).GetMethod(nameof(Equals), new[] { typeof(object) })!;
            return true;
        }

        if (name == "GetHashCode" && returnType == typeof(int) && paramTypes.Length == 0)
        {
            target = typeof(object).GetMethod(nameof(GetHashCode), Type.EmptyTypes)!;
            return true;
        }

        return false;
    }

    private static bool TryFindPropertyOnChain(ColumnarStructDef def, string name, out (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType) property)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.Properties.TryGetValue(name, out property))
                return true;
        }
        property = default;
        return false;
    }

    // Emit the LOAD of a static-field initializer's single-token literal into a .cctor IL stream, validating that
    // the literal agrees with the declared field type (mismatch declines — the legacy emitter's implicit numeric
    // conversions are not modelled). Mirrors the expression emitter's literal cases EXACTLY: int suffix
    // classification (L/UL), float suffixes (f/d; m declines), RAW string literals (Trim('"'), no escape decode —
    // matching the N# backend path's GetStringLiteralRuntimeValue), char escape decode, true/false. The text may carry a
    // leading `-` for numeric literals (the kernel admits it only there).
    private static bool TryEmitStaticFieldInitializerLoad(ILGenerator il, Type fieldType, int initKind, string text)
    {
        switch (initKind)
        {
            case 1: // IntLiteral (optionally negated): int, long, or ulong by suffix — must match the field type.
            {
                var negated = text.StartsWith("-", StringComparison.Ordinal);
                var body = negated ? text.Substring(1).TrimStart() : text;
                var end = body.Length;
                var sawU = false;
                var sawL = false;
                while (end > 0 && (body[end - 1] is 'u' or 'U' or 'l' or 'L'))
                {
                    if (body[end - 1] is 'u' or 'U') sawU = true; else sawL = true;
                    end--;
                }
                var digits = body.Substring(0, end);
                if (sawU && sawL)
                {
                    // ulong: a negated ulong literal is invalid — decline.
                    if (negated || fieldType != typeof(ulong) || !ulong.TryParse(digits, out var ulongValue))
                        return false;
                    il.Emit(OpCodes.Ldc_I8, unchecked((long)ulongValue));
                    return true;
                }
                if (sawU)
                    return false; // bare uint — not modelled.
                if (sawL)
                {
                    if (fieldType != typeof(long) || !long.TryParse(digits, out var longValue))
                        return false;
                    il.Emit(OpCodes.Ldc_I8, negated ? -longValue : longValue);
                    return true;
                }
                if (fieldType != typeof(int) || !int.TryParse(digits, out var intValue))
                    return false;
                il.Emit(OpCodes.Ldc_I4, negated ? -intValue : intValue);
                return true;
            }
            case 2: // FloatLiteral (optionally negated): double or float by suffix; m (decimal) declines.
            {
                var negated = text.StartsWith("-", StringComparison.Ordinal);
                var body = negated ? text.Substring(1).TrimStart() : text;
                var last = body.Length > 0 ? body[body.Length - 1] : '\0';
                if (last == 'm' || last == 'M')
                    return false;
                var isFloatLiteral = last == 'f' || last == 'F';
                if (isFloatLiteral || last == 'd' || last == 'D')
                    body = body.Substring(0, body.Length - 1);
                if (!TryParseFloatingLiteralBody(body, out var doubleValue))
                    return false;
                if (negated)
                    doubleValue = -doubleValue;
                if (isFloatLiteral)
                {
                    if (fieldType != typeof(float))
                        return false;
                    il.Emit(OpCodes.Ldc_R4, (float)doubleValue);
                    return true;
                }
                if (fieldType != typeof(double))
                    return false;
                il.Emit(OpCodes.Ldc_R8, doubleValue);
                return true;
            }
            case 3: // CharLiteral: strip quotes, decode escapes, single code point.
            {
                if (fieldType != typeof(char))
                    return false;
                var raw = text;
                if (raw.Length >= 2 && raw[0] == '\'' && raw[raw.Length - 1] == '\'')
                    raw = raw.Substring(1, raw.Length - 2);
                if (!NSharpLang.Compiler.StringLiteralDecoder.TryDecodeBody(raw, out var charValue) || charValue.Length != 1)
                    return false;
                il.Emit(OpCodes.Ldc_I4, (int)charValue[0]);
                return true;
            }
            case 4: // StringLiteral — decodes the shared escape set (the strings slice changed PLAIN string
                    // semantics; the legacy emitter's static-init path routes through the rewired literal sites, so
                    // keeping Trim here would diverge). An INTERPOLATED initializer ($-prefixed) declines.
                if (fieldType != typeof(string))
                    return false;
                if (text.Length > 0 && text[0] == '$')
                    return false;
                il.Emit(OpCodes.Ldstr, NSharpLang.Compiler.StringLiteralDecoder.Decode(text));
                return true;
            case 44: // true
                if (fieldType != typeof(bool))
                    return false;
                il.Emit(OpCodes.Ldc_I4_1);
                return true;
            case 45: // false
                if (fieldType != typeof(bool))
                    return false;
                il.Emit(OpCodes.Ldc_I4_0);
                return true;
            default:
                return false;
        }
    }

    // Emit a NON-CAPTURING expression-bodied LAMBDA literal (kind 39 — L1b) against its expected delegate
    // type: synthesize a Private|Static `<Lambda>_{n}` method on the Program type whose signature comes from
    // the delegate's Invoke (lambda params are UNTYPED by grammar — typing is purely contextual, exactly the
    // legacy emitter's GetLambdaSignature), emit the body through a SUB-emitter whose scope holds ONLY the lambda
    // parameters — an identifier reaching for an enclosing local/param fails to resolve and DECLINES, which
    // is precisely the no-captures rule (sibling function calls are not captures and keep working) — then
    // construct the delegate at the use site: `ldnull; ldftn <Lambda>_{n}; newobj <delegate>(object, IntPtr)`
    // (the legacy emitter's EmitStaticDelegate minus the per-callsite cache, which is unobservable). Interleaved
    // DefineMethod + forward-ldftn baking on PersistedAssemblyBuilder are spike-proven. A VOID-returning
    // delegate requires a void body expression (a discarded non-void body is a later rung — decline).
    private bool TryEmitLambdaLiteral(int lambdaIdx, Type expectedDelegateType)
    {
        if (_programType == null || _lambdaCounter == null
            || !TryGetSupportedDelegateSignature(
                expectedDelegateType, allowBuilderBoundArguments: true, out var delegateReturnType, out var delegateParamTypes, out var delegateCtor))
            return false;
        var paramCount = _nodes.ChildCount(lambdaIdx) - 1;
        if (paramCount != delegateParamTypes.Length)
            return false;
        var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
        var paramTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
        var signatureTypes = new Type[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            var paramNode = Child(lambdaIdx, p);
            if (_nodes.Kind(paramNode) != 6)
                return false;
            var paramName = Text(paramNode);
            if (!ordinals.TryAdd(paramName, p))
                return false; // duplicate parameter names are malformed — decline.
            if (IsVisibleBindingName(paramName))
                return false; // a lambda param shadowing an ENCLOSING binding is the pipeline's NL316.
            signatureTypes[p] = delegateParamTypes[p];
            paramTypeMap[paramName] = signatureTypes[p];
        }
        var bodyNode = Child(lambdaIdx, paramCount);

        // CAPTURE SET (L3a): kind-6 identifiers in the body that resolve in the ENCLOSING scope and are not
        // bound by this (or a nested) lambda's parameters. Empty -> the L1b static lowering below.
        var captures = new SortedSet<string>(StringComparer.Ordinal);
        CollectLambdaCaptures(bodyNode, new HashSet<string>(ordinals.Keys, StringComparer.Ordinal), captures);

        if (captures.Count == 0)
        {
            // THIS-capture detection (bare-field/instance-member references in an INSTANCE method's lambda):
            // a kind-6 name that is neither bound nor a sibling but resolves on the enclosing type's chain
            // means the lambda needs `this`. The legacy emitter's this-only path binds the delegate DIRECTLY to the
            // current instance — the lambda becomes an instance method ON THE ENCLOSING TYPE, no display
            // class, true reference capture (field mutation inside the lambda hits the real object, exactly
            // the legacy emitter's semantics). REFERENCE types only: a value-type `this` would bind a copy with
            // different semantics (the legacy emitter routes those through display-class copies) — decline.
            if (_currentStruct != null
                && BodyReferencesEnclosingChain(bodyNode, new HashSet<string>(ordinals.Keys, StringComparer.Ordinal)))
            {
                if (!_currentStruct.IsReference || _isConstructorBody)
                    return false;
                var instanceLambda = _currentStruct.Builder.DefineMethod(
                    "<Lambda>_" + _lambdaCounter[0]++,
                    MethodAttributes.Private | MethodAttributes.HideBySig, delegateReturnType, signatureTypes);
                var instanceIl = instanceLambda.GetILGenerator();
                var instanceOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                foreach (var pair in ordinals)
                    instanceOrdinals[pair.Key] = pair.Value + 1;
                var instanceEmitter = new ColumnarIlEmitter(
                    _nodes, _source, instanceOrdinals, paramTypeMap, delegateReturnType, instanceIl, _siblings,
                    _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: _currentStruct,
                    programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
                    enclosingBindingNames: VisibleBindingNamesSnapshot(),
                    referenceAssemblyPaths: _referenceAssemblyPaths);
                if (!EmitLambdaBody(instanceEmitter, instanceIl, bodyNode, delegateReturnType))
                    return DeclineMember("emit.body", "instance lambda body emission declined", bodyNode, "lambda");
                _il.Emit(OpCodes.Ldarg_0);
                _il.Emit(OpCodes.Ldftn, instanceLambda);
                _il.Emit(OpCodes.Newobj, delegateCtor);
                return true;
            }
            var lambdaMethod = _programType.DefineMethod(
                "<Lambda>_" + _lambdaCounter[0]++,
                MethodAttributes.Private | MethodAttributes.Static, delegateReturnType, signatureTypes);
            var lambdaIl = lambdaMethod.GetILGenerator();
            var subEmitter = new ColumnarIlEmitter(
                _nodes, _source, ordinals, paramTypeMap, delegateReturnType, lambdaIl, _siblings,
                _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: null,
                programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
                enclosingBindingNames: VisibleBindingNamesSnapshot(),
                referenceAssemblyPaths: _referenceAssemblyPaths);
            if (!EmitLambdaBody(subEmitter, lambdaIl, bodyNode, delegateReturnType))
                return DeclineMember("emit.body", "lambda body emission declined", bodyNode, "lambda");
            _il.Emit(OpCodes.Ldnull);
            _il.Emit(OpCodes.Ldftn, lambdaMethod);
            _il.Emit(OpCodes.Newobj, delegateCtor);
            return true;
        }

        // CAPTURING lambda (L3a snapshot + L3b boxed): each capture is either LIFTED (its name lives in a
        // shared StrongBox — the display class snapshots the BOX reference, so mutation is shared in both
        // directions, the legacy emitter's box-lift model) or NEVER-WRITTEN (a by-value snapshot is then
        // semantics-identical to the legacy emitter, which only box-lifts mutated captures). A written-but-unlifted
        // capture declines (structural writes, unliftable types, use-before-declaration). The whole-body
        // write scan needs the body root — null inside an EXPRESSION-bodied lambda's sub-emitter, so those
        // nested chains decline (block-bodied sub-emitters set it via EmitBody). The capture scan reads
        // kind-6 nodes positionally, so kinds whose children are NOT ordinary expressions (match arms,
        // object initializers) decline the capturing branch outright.
        if (_displayClasses == null || ContainsCaptureOpaqueKind(bodyNode))
            return false;
        var snapshotNames = new List<string>();
        var snapshotTypes = new List<Type>();
        var boxedNames = new List<string>();
        var boxedSources = new List<(LocalBuilder Box, Type ValueType)>();
        foreach (var captureName in captures)
        {
            if (_liftedLocals.TryGetValue(captureName, out var liftedSource))
            {
                boxedNames.Add(captureName);
                boxedSources.Add(liftedSource);
                continue;
            }
            if (_bodyRoot < 0
                || IsAnyNameWritten(_bodyRoot, new SortedSet<string>(StringComparer.Ordinal) { captureName }))
                return false; // written but unlifted (structural write / unliftable / pre-declaration use).
            var captureType = _locals.TryGetValue(captureName, out var capturedLocal)
                ? capturedLocal.LocalType
                : _paramTypes[captureName];
            // A capture typed by (or embedding) a generic METHOD parameter would put an out-of-context
            // MVAR into the display class's field signature — unencodable CLI metadata that saves but
            // throws TypeLoadException at load (adversarial-review finding, probe-confirmed). Decline.
            if (!IsSupportedType(captureType)
                || captureType.IsGenericParameter || captureType.ContainsGenericParameters)
                return false;
            snapshotNames.Add(captureName);
            snapshotTypes.Add(captureType);
        }
        var moduleBuilder = (ModuleBuilder)_programType.Module;
        var display = moduleBuilder.DefineType(
            "<>c__DisplayClass" + _lambdaCounter[0]++,
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed);
        var displayCtor = display.DefineDefaultConstructor(MethodAttributes.Public);
        // SNAPSHOT fields go into the synthetic def (the closure's `_currentStruct` field-chain fallback IS
        // the snapshot-read emission); BOX fields are deliberately kept OUT of it — boxed names route
        // through the closure's _boxedCaptures map, which dereferences `.Value` (a plain field read of the
        // box object would be type-wrong).
        var displayFields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
        for (var f = 0; f < snapshotNames.Count; f++)
            displayFields[snapshotNames[f]] = display.DefineField(snapshotNames[f], snapshotTypes[f], FieldAttributes.Public);
        var boxedCaptureMap = new Dictionary<string, (FieldBuilder BoxField, Type ValueType)>(StringComparer.Ordinal);
        var boxedFields = new FieldBuilder[boxedNames.Count];
        for (var b = 0; b < boxedNames.Count; b++)
        {
            var boxFieldType = typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(boxedSources[b].ValueType);
            boxedFields[b] = display.DefineField(boxedNames[b], boxFieldType, FieldAttributes.Public);
            boxedCaptureMap[boxedNames[b]] = (boxedFields[b], boxedSources[b].ValueType);
        }
        var displayDef = new ColumnarStructDef(display, snapshotNames.ToArray(), displayFields, isReference: true);
        // The lambda becomes an INSTANCE method on the display class: arg 0 is the closure, so parameter
        // ordinals shift +1; snapshot names fall through the sub-emitter's locals/params to the
        // `_currentStruct` field chain, boxed names resolve through _boxedCaptures.
        var shiftedOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var pair in ordinals)
            shiftedOrdinals[pair.Key] = pair.Value + 1;
        var closureMethod = display.DefineMethod(
            "<Lambda>", MethodAttributes.Public | MethodAttributes.HideBySig, delegateReturnType, signatureTypes);
        var closureIl = closureMethod.GetILGenerator();
        var closureEmitter = new ColumnarIlEmitter(
            _nodes, _source, shiftedOrdinals, paramTypeMap, delegateReturnType, closureIl, _siblings,
            _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: displayDef,
            programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
            boxedCaptures: boxedCaptureMap.Count > 0 ? boxedCaptureMap : null,
            enclosingBindingNames: VisibleBindingNamesSnapshot(),
            referenceAssemblyPaths: _referenceAssemblyPaths);
        if (!EmitLambdaBody(closureEmitter, closureIl, bodyNode, delegateReturnType))
            return DeclineMember("emit.body", "capturing lambda body emission declined", bodyNode, "lambda");
        _displayClasses.Add(display);
        // Use site: construct the closure; snapshot captures copy the VALUE, boxed captures copy the BOX
        // reference; bind the delegate to the closure.
        _il.Emit(OpCodes.Newobj, displayCtor);
        for (var f = 0; f < snapshotNames.Count; f++)
        {
            _il.Emit(OpCodes.Dup);
            if (_locals.TryGetValue(snapshotNames[f], out var sourceLocal))
                _il.Emit(OpCodes.Ldloc, sourceLocal);
            else
                EmitLoadArgument(_paramOrdinals[snapshotNames[f]]);
            _il.Emit(OpCodes.Stfld, displayFields[snapshotNames[f]]);
        }
        for (var b = 0; b < boxedNames.Count; b++)
        {
            _il.Emit(OpCodes.Dup);
            _il.Emit(OpCodes.Ldloc, boxedSources[b].Box);
            _il.Emit(OpCodes.Stfld, boxedFields[b]);
        }
        _il.Emit(OpCodes.Ldftn, closureMethod);
        _il.Emit(OpCodes.Newobj, delegateCtor);
        return true;
    }

    // Emit a lambda's BODY into its synthesized method: a statement BLOCK (kind 25 — `x => { ... }`)
    // flows through EmitBody, which owns always-returns checking for value lambdas and the trailing `ret`
    // for void ones (exactly a function body); an EXPRESSION body emits, type-checks against Invoke's
    // return, and appends the `ret`.
    private static bool EmitLambdaBody(ColumnarIlEmitter subEmitter, ILGenerator lambdaIl, int bodyNode, Type returnType)
    {
        if (subEmitter._nodes.Kind(bodyNode) == 25)
            return subEmitter.EmitBody(bodyNode, returnType == typeof(void));
        if (!subEmitter.EmitExpression(bodyNode, out var bodyType))
            return false;
        if (!TypesEquivalent(bodyType, returnType)
            && !subEmitter.TryEmitImplicitWidening(bodyType, returnType)
            && !subEmitter.TryEmitInterfaceUpcast(bodyType, returnType)
            && !TryEmitReferenceConversion(bodyType, returnType)
            && !subEmitter.TryEmitObjectConversion(bodyType, returnType)
            && !subEmitter.TryEmitUserDefinedConversion(bodyType, returnType, allowExplicit: false))
            return false;
        lambdaIl.Emit(OpCodes.Ret);
        return true;
    }

    // Collect the CAPTURES of a lambda body: kind-6 identifiers resolving in the enclosing locals/params
    // and not bound by this lambda's (or a nested lambda's) parameter list. TYPE-kernel subtrees never
    // contribute (their kind space collides with expression kinds — a type node can masquerade as kind 6
    // with a VALUELESS span): the walk skips the type child of casts (16) / new-expressions (15) and all
    // children of generic callees (38), and the kind-6 branch refuses value-less nodes outright (a
    // TYPE-tuple node carries nameStart -1 — Text() would throw). Field-name identifiers inside the
    // remaining capture-opaque kinds are NOT excluded here — the capturing branch declines those bodies.
    private void CollectLambdaCaptures(int node, HashSet<string> bound, SortedSet<string> captures)
    {
        var kind = _nodes.Kind(node);
        if (kind == 38 || kind == 42 || kind == 55)
            return; // children are TYPE subtrees only (38: callee name lives in the value span; 42: bare-new).
        if (kind == 39)
        {
            var nestedBound = new HashSet<string>(bound, StringComparer.Ordinal);
            var nestedParams = _nodes.ChildCount(node) - 1;
            for (var p = 0; p < nestedParams; p++)
            {
                if (_nodes.Kind(Child(node, p)) == 6)
                    nestedBound.Add(Text(Child(node, p)));
            }
            CollectLambdaCaptures(Child(node, nestedParams), nestedBound, captures);
            return;
        }
        if (kind == 6)
        {
            if (_nodes.ValueStart(node) < 0)
                return; // a value-less masquerading TYPE node — never a name read.
            var name = Text(node);
            if (!bound.Contains(name)
                && (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name) || _liftedLocals.ContainsKey(name)))
                captures.Add(name);
        }
        if (kind == 46 || kind == 47) // is/as: child[1] is the TYPE subtree — walk the VALUE child only.
        {
            CollectLambdaCaptures(Child(node, 0), bound, captures);
            return;
        }
        var first = (kind == 15 || kind == 16) ? 1 : 0; // child[0] of new/cast is the TYPE subtree.
        for (var c = first; c < _nodes.ChildCount(node); c++)
            CollectLambdaCaptures(Child(node, c), bound, captures);
    }

    // True when a lambda body references a bare name that resolves on the ENCLOSING type's member chain
    // (and is not a sibling function — siblings beat members in the pinned bare-call order and need no
    // `this`). Such a body requires the instance-bound lowering: the delegate binds directly to the
    // current `this` and the lambda lives as an instance method on the enclosing type.
    private bool BodyReferencesEnclosingChain(int node, HashSet<string> bound)
    {
        var kind = _nodes.Kind(node);
        if (kind == 38 || kind == 42 || kind == 55)
            return false;
        if (kind == 39)
        {
            var nestedBound = new HashSet<string>(bound, StringComparer.Ordinal);
            nestedBound.UnionWith(BoundParamsOf(node));
            return BodyReferencesEnclosingChain(Child(node, _nodes.ChildCount(node) - 1), nestedBound);
        }
        if (kind == 6 && _nodes.ValueStart(node) >= 0 && _currentStruct != null)
        {
            var name = Text(node);
            if (!bound.Contains(name) && !_locals.ContainsKey(name) && !_liftedLocals.ContainsKey(name)
                && !_paramOrdinals.ContainsKey(name) && !_siblings.ContainsKey(name)
                && (TryFindFieldOnChain(_currentStruct, name, out _)
                    || TryFindMethodOnChain(_currentStruct, name, out _)
                    || TryFindStaticFieldOnChain(_currentStruct, name, out _)
                    || TryFindStaticPropertyOnChain(_currentStruct, name, out _)))
                return true;
        }
        if (kind == 46 || kind == 47) // is/as: walk the VALUE child only (child 1 is a TYPE subtree).
            return BodyReferencesEnclosingChain(Child(node, 0), bound);
        var first = (kind == 15 || kind == 16) ? 1 : 0;
        for (var c = first; c < _nodes.ChildCount(node); c++)
        {
            if (BodyReferencesEnclosingChain(Child(node, c), bound))
                return true;
        }
        return false;
    }

    // L3b pre-scan: the LIFTED candidate set = names referenced inside any lambda subtree (unbound by its
    // params) that are ALSO bare-assigned (kind-14, kind-6 target) somewhere in the body, minus names
    // structurally written (foreach vars, deconstruction targets, member/index-rooted assignments) — those
    // stay unlifted and any capture of them declines as in L3a. The candidate set only drives DECLARATION
    // shape; _liftedLocals (actual live boxes) drives reads/writes/captures.
    private void ComputeLiftedCandidates(int bodyRoot)
    {
        var inLambdas = new SortedSet<string>(StringComparer.Ordinal);
        CollectNamesInsideLambdas(bodyRoot, inLambdas);
        if (inLambdas.Count == 0)
            return;
        foreach (var name in inLambdas)
        {
            var single = new SortedSet<string>(StringComparer.Ordinal) { name };
            if (IsNameBareAssigned(bodyRoot, single) && !IsNameStructurallyWritten(bodyRoot, single))
                (_liftedCandidates ??= new HashSet<string>(StringComparer.Ordinal)).Add(name);
        }
    }

    // A type a StrongBox<T> can be closed over and resolved by plain reflection: BAKED runtime, no
    // builders, no generic parameters (mirrors the delegate/tuple builder-arg exclusions).
    // ContainsBuilderBoundType catches builder-bound collections (a captured+reassigned List<Pt> local)
    // — Assembly/ContainsGenericParameters report baked-looking values on those TBIs (spike-proven).
    private static bool IsLiftableValueType(Type t) =>
        IsSupportedType(t) && !(t.Assembly is AssemblyBuilder) && !t.IsGenericParameter
        && !t.ContainsGenericParameters && !ContainsBuilderBoundType(t);

    private static FieldInfo StrongBoxValueField(Type valueType) =>
        typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(valueType).GetField("Value")!;

    // Collect every kind-6 name inside any LAMBDA subtree of `node`, excluding names bound by the lambda's
    // (or a nested lambda's) own parameters — the same walk discipline as CollectLambdaCaptures, but with
    // NO in-scope check (this runs at EmitBody entry, before any local exists).
    private void CollectNamesInsideLambdas(int node, SortedSet<string> names)
    {
        var kind = _nodes.Kind(node);
        if (kind == 38 || kind == 42 || kind == 55)
            return;
        if (kind == 39)
        {
            CollectUnboundNames(Child(node, _nodes.ChildCount(node) - 1), BoundParamsOf(node), names);
            return;
        }
        if (kind == 46 || kind == 47) // is/as: walk the VALUE child only (child 1 is a TYPE subtree).
            { CollectNamesInsideLambdas(Child(node, 0), names); return; }
        var first = (kind == 15 || kind == 16) ? 1 : 0;
        for (var c = first; c < _nodes.ChildCount(node); c++)
            CollectNamesInsideLambdas(Child(node, c), names);
    }

    private HashSet<string> BoundParamsOf(int lambdaNode)
    {
        var bound = new HashSet<string>(StringComparer.Ordinal);
        for (var p = 0; p < _nodes.ChildCount(lambdaNode) - 1; p++)
        {
            if (_nodes.Kind(Child(lambdaNode, p)) == 6)
                bound.Add(Text(Child(lambdaNode, p)));
        }
        return bound;
    }

    private void CollectUnboundNames(int node, HashSet<string> bound, SortedSet<string> names)
    {
        var kind = _nodes.Kind(node);
        if (kind == 38 || kind == 42 || kind == 55)
            return;
        if (kind == 39)
        {
            var nestedBound = new HashSet<string>(bound, StringComparer.Ordinal);
            nestedBound.UnionWith(BoundParamsOf(node));
            CollectUnboundNames(Child(node, _nodes.ChildCount(node) - 1), nestedBound, names);
            return;
        }
        if (kind == 6 && _nodes.ValueStart(node) >= 0)
        {
            var name = Text(node);
            if (!bound.Contains(name))
                names.Add(name);
        }
        if (kind == 46 || kind == 47) // is/as: walk the VALUE child only (child 1 is a TYPE subtree).
            { CollectUnboundNames(Child(node, 0), bound, names); return; }
        var first = (kind == 15 || kind == 16) ? 1 : 0;
        for (var c = first; c < _nodes.ChildCount(node); c++)
            CollectUnboundNames(Child(node, c), bound, names);
    }

    // A kind-14 assignment whose target is the BARE identifier — the liftable write form. A LAMBDA's own
    // parameters shadow: writes to them inside its body are not writes to the outer name (over-lifting is
    // semantically benign — an unwritten box equals a snapshot — but shifts names out of the other gates).
    private bool IsNameBareAssigned(int node, SortedSet<string> names)
    {
        if (_nodes.Kind(node) == 39)
        {
            var bound = BoundParamsOf(node);
            var remaining = new SortedSet<string>(names, StringComparer.Ordinal);
            remaining.ExceptWith(bound);
            return remaining.Count > 0 && IsNameBareAssigned(Child(node, _nodes.ChildCount(node) - 1), remaining);
        }
        if (_nodes.Kind(node) == 14 || _nodes.Kind(node) == 44) // assignment OR postfix `++`/`--` — both write the target.
        {
            var target = Child(node, 0);
            if (_nodes.Kind(target) == 6 && _nodes.ValueStart(target) >= 0 && names.Contains(Text(target)))
                return true;
        }
        for (var c = 0; c < _nodes.ChildCount(node); c++)
        {
            if (IsNameBareAssigned(Child(node, c), names))
                return true;
        }
        return false;
    }

    // Writes the box-lift model does NOT cover: foreach loop variables (per-iteration store semantics are
    // their own slice), deconstruction targets, and member/index-rooted assignments (`b.V = 99` needs the
    // box's Value ADDRESS — a later rung).
    private bool IsNameStructurallyWritten(int node, SortedSet<string> names)
    {
        switch (_nodes.Kind(node))
        {
            case 14:
            case 44: // postfix `++`/`--` writes its target exactly like an assignment.
                var structuralTarget = Child(node, 0);
                if (_nodes.Kind(structuralTarget) == 8 || _nodes.Kind(structuralTarget) == 10)
                {
                    while ((_nodes.Kind(structuralTarget) == 8 || _nodes.Kind(structuralTarget) == 10) && _nodes.ChildCount(structuralTarget) > 0)
                        structuralTarget = Child(structuralTarget, 0);
                    if (_nodes.Kind(structuralTarget) == 6 && _nodes.ValueStart(structuralTarget) >= 0 && names.Contains(Text(structuralTarget)))
                        return true;
                }
                break;
            case 29:
                if (names.Contains(Text(node)))
                    return true;
                break;
            case 30:
                for (var n = 0; n < _nodes.ChildCount(node) - 1; n++)
                {
                    if (_nodes.Kind(Child(node, n)) == 6 && names.Contains(Text(Child(node, n))))
                        return true;
                }
                break;
        }
        for (var c = 0; c < _nodes.ChildCount(node); c++)
        {
            if (IsNameStructurallyWritten(Child(node, c), names))
                return true;
        }
        return false;
    }

    // Kinds whose identifier CHILDREN are not value reads — match/pattern kinds (18/19/32-35, 37) carry
    // arm BINDINGS; object initializers (36) carry field NAMES. A capturing lambda containing any of them
    // declines (under-accept); casts/new/generic-callees are handled precisely by the capture walk above.
    private bool ContainsCaptureOpaqueKind(int node)
    {
        var k = _nodes.Kind(node);
        // 18/19 match arms, 32-37 patterns/object-init, 52 with-expressions: their kind-6 children are
        // FIELD names / pattern bindings, not value reads — the positional capture scan would mis-read
        // them as identifier uses.
        if (k == 18 || k == 19 || (k >= 32 && k <= 37) || k == 52)
            return true;
        for (var c = 0; c < _nodes.ChildCount(node); c++)
        {
            if (ContainsCaptureOpaqueKind(Child(node, c)))
                return true;
        }
        return false;
    }

    // True when any statement in the subtree WRITES one of `names`: an assignment (kind 14, incl. the
    // compound forms — the for-loop increment is one of these) targeting the bare identifier OR any
    // member/index path whose ROOT receiver is the name (`b.V = 99` on a captured value-struct local
    // diverges from the legacy emitter, which box-lifts member-mutated value-type captures — adversarial-review
    // finding, probe-confirmed 101 vs 199; root-receiver matching also conservatively declines reference-
    // type member writes, which would be benign — under-accept), a foreach (kind 29) whose loop variable
    // re-stores per iteration, or a tuple deconstruction (kind 30) binding it. `:=`/typed declarations
    // cannot RE-declare an existing name (declined at declaration), so they are not writes.
    private bool IsAnyNameWritten(int node, SortedSet<string> names)
    {
        switch (_nodes.Kind(node))
        {
            case 14:
            case 44: // postfix `++`/`--` writes its target exactly like an assignment.
                var target = Child(node, 0);
                while ((_nodes.Kind(target) == 8 || _nodes.Kind(target) == 10) && _nodes.ChildCount(target) > 0)
                    target = Child(target, 0); // walk member/index paths to the root receiver.
                if (_nodes.Kind(target) == 6 && _nodes.ValueStart(target) >= 0 && names.Contains(Text(target)))
                    return true;
                break;
            case 29:
                if (names.Contains(Text(node)))
                    return true;
                break;
            case 30:
                for (var n = 0; n < _nodes.ChildCount(node) - 1; n++)
                {
                    if (_nodes.Kind(Child(node, n)) == 6 && names.Contains(Text(Child(node, n))))
                        return true;
                }
                break;
        }
        for (var c = 0; c < _nodes.ChildCount(node); c++)
        {
            if (IsAnyNameWritten(Child(node, c), names))
                return true;
        }
        return false;
    }

    // Emit a ZERO-PARAM expression-bodied lambda with a BODY-INFERRED return type (`zero := () => 99` —
    // L1c): no expected delegate type exists at a `:=` declaration, but a zero-param lambda has no
    // inference gap — the synthesized method is defined signature-LESS, its body emits first (yielding the
    // return type), and SetReturnType/SetParameters run AFTER (spike-proven on PersistedAssemblyBuilder).
    // A void body yields Action; otherwise Func<bodyType> — which must be a modeled delegate (a
    // builder-typed body would produce a builder-arg delegate; IsSupportedDelegateType refuses it).
    // Param-ful `:=` lambdas have no inference source and are pipeline-rejected (NL203) — decline.
    private bool TryEmitInferredZeroParamLambda(int lambdaIdx, out Type delegateType)
    {
        delegateType = null!;
        if (_programType == null || _lambdaCounter == null || _nodes.ChildCount(lambdaIdx) != 1)
            return false;
        var lambdaMethod = _programType.DefineMethod(
            "<Lambda>_" + _lambdaCounter[0]++, MethodAttributes.Private | MethodAttributes.Static);
        var lambdaIl = lambdaMethod.GetILGenerator();
        var subEmitter = new ColumnarIlEmitter(
            _nodes, _source, new Dictionary<string, int>(StringComparer.Ordinal),
            new Dictionary<string, Type>(StringComparer.Ordinal), typeof(void), lambdaIl, _siblings,
            _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: null,
            programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
            enclosingBindingNames: VisibleBindingNamesSnapshot(),
            referenceAssemblyPaths: _referenceAssemblyPaths);
        if (!subEmitter.EmitExpression(Child(lambdaIdx, 0), out var bodyType))
            return DeclineMember("emit.body", "inferred zero-parameter lambda body emission declined", Child(lambdaIdx, 0), "lambda");
        lambdaIl.Emit(OpCodes.Ret);
        delegateType = bodyType == typeof(void) ? typeof(Action) : typeof(Func<>).MakeGenericType(bodyType);
        if (!IsSupportedDelegateType(delegateType))
            return false;
        lambdaMethod.SetReturnType(bodyType);
        lambdaMethod.SetParameters(Type.EmptyTypes);
        var delegateCtor = delegateType.GetConstructor(new[] { typeof(object), typeof(IntPtr) });
        if (delegateCtor == null)
            return false;
        _il.Emit(OpCodes.Ldnull);
        _il.Emit(OpCodes.Ldftn, lambdaMethod);
        _il.Emit(OpCodes.Newobj, delegateCtor);
        return true;
    }

    // Invoke a DELEGATE-typed local or parameter (`t(v)` where `t: Func<int,int>` — L1a): load the delegate
    // value, emit each argument exactly typed against Invoke's parameters, `callvirt Invoke`. Fires ONLY when
    // no method tier carries the name (the pipeline's pinned method-beats-local order — the caller checks);
    // a non-delegate-typed value declines. Invoke resolves by plain GetMethod — sound because
    // IsSupportedDelegateType admits closed Func/Action over BAKED runtime types only (the legacy emitter's
    // TryGetDelegateInvokeMethod does the same for runtime delegate types).
    private bool TryEmitDelegateInvoke(int callIdx, string name, out Type type)
    {
        type = null!;
        Type delegateType;
        // L3b: a lifted (or boxed-captured) delegate's CURRENT value lives in the StrongBox — loading the
        // plain slot would invoke a STALE delegate (adversarial-review finding, both pipelines accept but
        // values diverge). Checked before every other tier.
        if (_boxedCaptures != null && _boxedCaptures.TryGetValue(name, out var boxedDelegate))
        {
            if (!IsSupportedDelegateType(boxedDelegate.ValueType))
                return false;
            delegateType = boxedDelegate.ValueType;
            _il.Emit(OpCodes.Ldarg_0);
            _il.Emit(OpCodes.Ldfld, boxedDelegate.BoxField);
            _il.Emit(OpCodes.Ldfld, StrongBoxValueField(boxedDelegate.ValueType));
        }
        else if (_liftedLocals.TryGetValue(name, out var liftedDelegate))
        {
            if (!IsSupportedDelegateType(liftedDelegate.ValueType))
                return false;
            delegateType = liftedDelegate.ValueType;
            _il.Emit(OpCodes.Ldloc, liftedDelegate.Box);
            _il.Emit(OpCodes.Ldfld, StrongBoxValueField(liftedDelegate.ValueType));
        }
        else if (_locals.TryGetValue(name, out var local))
        {
            if (!IsSupportedDelegateType(local.LocalType))
                return false;
            delegateType = local.LocalType;
            _il.Emit(OpCodes.Ldloc, local);
        }
        else if (_paramOrdinals.TryGetValue(name, out var ordinal))
        {
            var paramType = _paramTypes[name];
            if (!IsSupportedDelegateType(paramType))
                return false;
            delegateType = paramType;
            EmitLoadArgument(ordinal);
        }
        else
        {
            return false;
        }
        var invoke = delegateType.GetMethod("Invoke");
        if (invoke == null)
            return false;
        var invokeParams = invoke.GetParameters();
        var argCount = _nodes.ChildCount(callIdx) - 1;
        if (argCount != invokeParams.Length)
            return false;
        for (var a = 1; a <= argCount; a++)
        {
            if (!EmitExpression(Child(callIdx, a), out var argType) || argType != invokeParams[a - 1].ParameterType)
                return false;
        }
        _il.Emit(OpCodes.Callvirt, invoke);
        type = invoke.ReturnType;
        return true;
    }

    // Emit a call to a GENERIC top-level sibling: emit the args while unifying the declared parameter shapes
    // (T / T[] / concrete) against the emitted argument types — `binding` starts EMPTY for an inferred call
    // (Identity(42)) or PRE-SEEDED for explicit type arguments (Identity<int>(42); the unify loop then verifies
    // each argument against the seeded binding instead of binding it). Conflicting bindings (Same(1, "x")),
    // unbound parameters, composed shapes over T, and user TypeBuilder/EnumBuilder bindings decline. The call
    // binds via MakeGenericMethod on the open MethodBuilder (the de-risking spike's pattern); the result type
    // substitutes the binding into the declared return shape.
    private bool TryEmitGenericSiblingCall(int callIdx, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints) target, Type?[] binding, out Type type)
    {
        type = null!;
        var argCount = _nodes.ChildCount(callIdx) - 1;
        if (argCount != target.ParamTypes.Length)
            return false;
        for (var a = 1; a <= argCount; a++)
        {
            if (!EmitExpression(Child(callIdx, a), out var gArgType))
                return false;
            var declared = target.ParamTypes[a - 1];
            if (declared.IsGenericParameter)
            {
                if (!TryUnifyTypeParam(target.TypeParams, binding, declared, gArgType))
                    return false;
            }
            else if (declared.IsSZArray && declared.GetElementType()!.IsGenericParameter)
            {
                if (!gArgType.IsSZArray || !TryUnifyTypeParam(target.TypeParams, binding, declared.GetElementType()!, gArgType.GetElementType()!))
                    return false;
            }
            else if (declared.IsGenericType && !declared.IsGenericTypeDefinition)
            {
                // A generic-CONTAINER parameter (`items: List<T>`, `Dictionary<string, T>`,
                // `HashSet<T>`, or a fully
                // concrete List<Pt>): unify structurally — List<int> against List<T> binds T=int.
                if (!TryUnifyGenericContainer(target.TypeParams, binding, declared, gArgType))
                    return false;
            }
            else if (declared != gArgType)
            {
                return false;
            }
        }
        var boundArgs = new Type[binding.Length];
        for (var b = 0; b < binding.Length; b++)
        {
            if (binding[b] == null)
                return false; // an unbound type parameter (no argument mentions it, no explicit arg) declines.
            boundArgs[b] = binding[b]!;
        }
        // Enforce the callee's declared constraints (`where T: ...`) against the bound type arguments,
        // mirroring the analyzer's NL208 checks: MakeGenericMethod on a Reflection.Emit MethodBuilder performs
        // NO constraint validation (spike-proven — a violating instantiation silently persists an assembly
        // that fails at load), so a violating OR unverifiable binding must decline here. Bindings that are the
        // CALLER's own open type parameter, or any emitted shape (constraint implication and assignability are
        // unanswerable before bake), decline; everything else is a baked runtime type reflection can answer.
        for (var p = 0; p < boundArgs.Length; p++)
        {
            var special = target.SpecialConstraints.Length > p ? target.SpecialConstraints[p] : 0;
            var baseConstraint = target.BaseConstraints.Length > p ? target.BaseConstraints[p] : null;
            if (special == 0 && baseConstraint == null)
                continue;
            var bound = boundArgs[p];
            if (bound.IsGenericParameter || bound.Assembly is AssemblyBuilder)
                return false;
            if ((special & 1) != 0 && bound.IsValueType)
                return false; // `class`: requires a reference type.
            if ((special & 2) != 0 && (!bound.IsValueType || Nullable.GetUnderlyingType(bound) != null))
                return false; // `struct`: requires a non-nullable value type.
            if ((special & 4) != 0 && !bound.IsValueType && bound.GetConstructor(Type.EmptyTypes) == null)
                return false; // `new()`: requires a public parameterless constructor (value types qualify).
            if (baseConstraint == null)
                continue;
            if (baseConstraint.IsGenericParameter)
            {
                // `where T: U` — the constraint is another of the CALLEE's parameters: check the two bound
                // runtime types' assignability.
                var otherPos = -1;
                for (var q = 0; q < target.TypeParams.Length; q++)
                {
                    if (ReferenceEquals(target.TypeParams[q], baseConstraint)) { otherPos = q; break; }
                }
                if (otherPos < 0)
                    return false;
                var otherBound = boundArgs[otherPos];
                if (otherBound.IsGenericParameter || otherBound.Assembly is AssemblyBuilder
                    || !otherBound.IsAssignableFrom(bound))
                    return false;
            }
            else if (baseConstraint.Assembly is AssemblyBuilder)
            {
                // A user-class base constraint: a baked runtime binding can never derive from an un-baked
                // emitted type — unsatisfiable at this call site.
                return false;
            }
            else if (!baseConstraint.IsAssignableFrom(bound))
            {
                return false;
            }
        }
        var instantiated = ((MethodBuilder)target.Method).MakeGenericMethod(boundArgs);
        _il.Emit(OpCodes.Call, instantiated);
        return TrySubstituteReturnType(target.TypeParams, binding, target.ReturnType, out type);
    }

    // Unify one declared TYPE PARAMETER against an argument's actual type for a generic sibling call. `declared`
    // is one of `typeParams` (the callee's GenericTypeParameterBuilders, in declaration order); `binding` is the
    // positional inference state. A FIRST encounter binds; a repeat must reference-equal the prior binding
    // (Same(1, "x") conflicts → decline). Admissible bound types: the supported concrete value/reference types
    // (incl. their arrays) and the CALLER's own open type parameters (a generic calling a generic — the spike
    // proved MakeGenericMethod over an open T). A user TypeBuilder/EnumBuilder binding declines this slice.
    private static bool TryUnifyTypeParam(Type[] typeParams, Type?[] binding, Type declared, Type actual)
    {
        var pos = -1;
        for (var i = 0; i < typeParams.Length; i++)
        {
            if (ReferenceEquals(typeParams[i], declared)) { pos = i; break; }
        }
        if (pos < 0)
            return false; // a type parameter from some other scope — not resolvable here.
        if (!actual.IsGenericParameter && ContainsBuilderBoundType(actual))
            return false; // T must bind a BAKED type (or the caller's own open param): builder-bound
                          // bindings (T=Pt, T=List<Pt>) stay declined — constraint enforcement and
                          // MakeGenericMethod reflect on the binding (GetConstructor throws on a TBI).
        if (!actual.IsGenericParameter && !IsSupportedType(actual))
            return false;
        if (binding[pos] == null)
        {
            binding[pos] = actual;
            return true;
        }
        return ReferenceEquals(binding[pos], actual) || binding[pos] == actual;
    }

    // Structurally unify a declared generic-CONTAINER parameter (List<T>, Dictionary<string,T>, HashSet<T>, nested
    // shapes, or a fully concrete List<Pt>) against the argument's actual type: the definitions must
    // match, then each declared argument either IS one of the callee's type parameters (TryUnifyTypeParam
    // binds or checks it), recurses as a nested container, or must be structurally the same type.
    // Mirrors the generic-container binding recursion used by declared-method calls.
    private static bool TryUnifyGenericContainer(Type[] typeParams, Type?[] binding, Type declared, Type actual)
    {
        if (!actual.IsGenericType || actual.IsGenericTypeDefinition)
            return false;
        Type declaredDef, actualDef;
            declaredDef = declared.GetGenericTypeDefinition();
            actualDef = actual.GetGenericTypeDefinition();
        if (!ReferenceEquals(declaredDef, actualDef))
            return false;
        var declaredArgs = declared.GetGenericArguments();
        var actualArgs = actual.GetGenericArguments();
        if (declaredArgs.Length != actualArgs.Length)
            return false;
        for (var i = 0; i < declaredArgs.Length; i++)
        {
            var d = declaredArgs[i];
            if (d.IsGenericParameter)
            {
                if (!TryUnifyTypeParam(typeParams, binding, d, actualArgs[i]))
                    return false;
            }
            else if (d.IsGenericType && !d.IsGenericTypeDefinition)
            {
                if (!TryUnifyGenericContainer(typeParams, binding, d, actualArgs[i]))
                    return false;
            }
            else if (!TypesEquivalent(d, actualArgs[i]))
            {
                return false;
            }
        }
        return true;
    }

    // Substitute an inferred binding into a generic sibling's declared RETURN type: T -> binding, T[] ->
    // binding[], a concrete type -> itself, void -> void. Composed shapes over T are not modelled — decline.
    private static bool TrySubstituteReturnType(Type[] typeParams, Type?[] binding, Type declaredReturn, out Type substituted)
    {
        substituted = null!;
        if (declaredReturn.IsGenericParameter)
        {
            for (var i = 0; i < typeParams.Length; i++)
            {
                if (ReferenceEquals(typeParams[i], declaredReturn))
                {
                    substituted = binding[i]!;
                    return true;
                }
            }
            return false;
        }
        if (declaredReturn.IsSZArray && declaredReturn.GetElementType()!.IsGenericParameter)
        {
            var element = declaredReturn.GetElementType()!;
            for (var i = 0; i < typeParams.Length; i++)
            {
                if (ReferenceEquals(typeParams[i], element))
                {
                    substituted = binding[i]!.MakeArrayType();
                    return true;
                }
            }
            return false;
        }
        // A CLOSED-USER-GENERIC return (`func makeNone<T>(x: T): Opt<T>`) carries the CALLEE's generic
        // parameters inside its instantiation arguments — substitute each by the call's binding and re-close.
        // Letting the raw Opt<!!T> escape into a (possibly non-generic) caller bakes out-of-context MVAR
        // references into its locals/isinst targets — BadImageFormatException at runtime (adversarial-review
        // finding, probe-confirmed: the legacy emitter runs the same program correctly). Any argument that cannot
        // fully substitute declines.
        if (IsClosedUserGenericInstantiation(declaredReturn))
        {
            var declaredArgs = declaredReturn.GetGenericArguments();
            var substitutedArgs = new Type[declaredArgs.Length];
            for (var a = 0; a < declaredArgs.Length; a++)
            {
                if (!TrySubstituteReturnType(typeParams, binding, declaredArgs[a], out substitutedArgs[a]))
                    return false;
            }
            substituted = declaredReturn.GetGenericTypeDefinition().MakeGenericType(substitutedArgs);
            return true;
        }
        // A builder-bound BCL-COLLECTION return (`func same<T>(items: List<T>): List<T>`, or List<Pt>):
        // substitute each argument by the binding and re-close the RUNTIME definition — with baked
        // bindings this yields a real runtime List<int>, so the caller's downstream member binding
        // reflects normally. This arm MUST intercept every builder-bound instantiation: the defensive
        // ContainsGenericParameters tail below reports FALSE on a TypeBuilderInstantiation even over an
        // open T (spike-proven), so falling through would leak an open MVAR into the caller (the exact
        // BadImageFormatException class the user-generic arm above guards against). Fully BAKED generic
        // returns (concrete tuples) keep falling through to the tail unchanged.
        if (declaredReturn.IsGenericType && !declaredReturn.IsGenericTypeDefinition && ContainsBuilderBoundType(declaredReturn))
        {
            Type returnDef;
                returnDef = declaredReturn.GetGenericTypeDefinition();
            if (returnDef != typeof(List<>) && returnDef != typeof(Dictionary<,>) && returnDef != typeof(HashSet<>))
                return false; // an unmodelled builder-bound generic return — decline, never leak it open.
            var collectionArgs = declaredReturn.GetGenericArguments();
            var substitutedCollectionArgs = new Type[collectionArgs.Length];
            for (var a = 0; a < collectionArgs.Length; a++)
            {
                if (!TrySubstituteReturnType(typeParams, binding, collectionArgs[a], out substitutedCollectionArgs[a]))
                    return false;
            }
            substituted = returnDef.MakeGenericType(substitutedCollectionArgs);
            return true;
        }
        // Defensively refuse any OTHER shape still containing a generic parameter (the fallthrough below
        // must only pass fully-concrete declared returns into the caller's context).
        bool stillOpen;
            stillOpen = declaredReturn.ContainsGenericParameters;
        if (stillOpen && declaredReturn is not TypeBuilder && declaredReturn is not EnumBuilder)
            return false;
        substituted = declaredReturn;
        return true;
    }

    // Emit a bare (implicit-`this`) INSTANCE method call: `ldarg.0; <args>; call/callvirt`. Used by tiers 1 and 4
    // of the bare-call resolution (own-declared and inherited instance methods). Declines on an arity or arg-type
    // mismatch. A reference `this` calls via callvirt (matching the external-receiver path); a value-type `this`
    // is a managed pointer -> `call`.
    private bool EmitImplicitThisCall(int callIdx, (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method, out Type type)
    {
        type = null!;
        var argCount = _nodes.ChildCount(callIdx) - 1;
        if (argCount != method.ParamTypes.Length)
            return false;
        _il.Emit(OpCodes.Ldarg_0);
        for (var a = 1; a <= argCount; a++)
        {
            if (!EmitDeclaredCallArgument(Child(callIdx, a), method.ParamTypes[a - 1], allowLambdaLiteral: true))
                return false;
        }
        _il.Emit(_currentStruct!.IsReference ? OpCodes.Callvirt : OpCodes.Call, method.Builder);
        type = method.ReturnType;
        return true;
    }

    // Resolve a STATIC FIELD on `def`'s chain by name, nearest declaration first (the legacy emitter's chain-walked
    // static-member resolution — `Derived.count` binds a base-declared static field).
    private static bool TryFindStaticFieldOnChain(ColumnarStructDef def, string name, out FieldBuilder field)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.StaticFields.TryGetValue(name, out field!))
                return true;
        }
        field = null!;
        return false;
    }

    // Resolve a STATIC PROPERTY on `def`'s chain by name, nearest declaration first (`Derived.X` binds a
    // base-declared static property — the fixed legacy emitter chain-walks its get_X/set_X exactly like static fields).
    private static bool TryFindStaticPropertyOnChain(ColumnarStructDef def, string name, out (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType) property)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.StaticProperties.TryGetValue(name, out property))
                return true;
        }
        property = default;
        return false;
    }

    // Resolve a STATIC method call on `def`'s chain by name + ARG COUNT, nearest declaration first. A type whose
    // overload set carries the name but has
    // no matching arity does NOT stop the walk — a base overload of the right arity still binds. (Same-arity
    // overload sets were declined in PASS 0b, so an arity match is unique per type.) The arg TYPES are checked at
    // the emit site (a mismatch declines because implicit conversions are not modelled here).
    private static bool TryFindStaticMethodOnChain(ColumnarStructDef def, string name, int argCount, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (!d.StaticMethods.TryGetValue(name, out var overloads))
                continue;
            foreach (var candidate in overloads)
            {
                if (candidate.ParamTypes.Length == argCount)
                {
                    method = candidate;
                    return true;
                }
            }
        }
        method = default;
        return false;
    }

    private bool TryEmitUserDefinedConversion(Type source, Type target, bool allowExplicit)
    {
        if (TryFindUserDefinedConversion(source, target, "op_Implicit", out var implicitConversion)
            || (allowExplicit && TryFindUserDefinedConversion(source, target, "op_Explicit", out implicitConversion)))
        {
            _il.Emit(OpCodes.Call, implicitConversion.Builder);
            return true;
        }

        return false;
    }

    private bool TryFindUserDefinedConversion(
        Type source,
        Type target,
        string methodName,
        out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        if (FindDefByType(source) is { } sourceDef
            && TryFindUserDefinedConversionOnType(sourceDef, source, target, methodName, out method))
        {
            return true;
        }

        if (FindDefByType(target) is { } targetDef
            && !ReferenceEquals(targetDef, FindDefByType(source))
            && TryFindUserDefinedConversionOnType(targetDef, source, target, methodName, out method))
        {
            return true;
        }

        method = default;
        return false;
    }

    private static bool TryFindUserDefinedConversionOnType(
        ColumnarStructDef def,
        Type source,
        Type target,
        string methodName,
        out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (!d.StaticMethods.TryGetValue(methodName, out var overloads))
                continue;
            foreach (var candidate in overloads)
            {
                if (candidate.ParamTypes.Length == 1
                    && TypesEquivalent(candidate.ParamTypes[0], source)
                    && TypesEquivalent(candidate.ReturnType, target))
                {
                    method = candidate;
                    return true;
                }
            }
        }

        method = default;
        return false;
    }


    // Element types the array read/write/alloc paths can emit ldelem/stelem/newarr for: bool (u1), int/uint (i4),
    // long/ulong (i8), char (u2), double (r8) / float (r4), string/reference handles, and jagged SZ arrays over
    // those same supported elements. uint/ulong storage is just the unsigned bit pattern; unsignedness is in how
    // the VALUE is loaded and operated on.
    private static bool IsSupportedElementType(Type t) =>
        t == typeof(bool)
        || t == typeof(int) || t == typeof(uint) || t == typeof(long) || t == typeof(ulong)
        || t == typeof(char) || t == typeof(string) || t == typeof(double) || t == typeof(float)
        || IsEnumType(t)
        || t is TypeBuilder
        || t == typeof(object)
        || t == typeof(Type)
        || t == typeof(Version)
        || t == typeof(Assembly)
        || t == typeof(PropertyInfo)
        || t == typeof(FieldInfo)
        || t == typeof(LocalBuilder)
        || t == typeof(FieldBuilder)
        || t == typeof(TypeBuilder)
        || t == typeof(MethodBuilder)
        || t == typeof(MethodInfo)
        || t == typeof(ConstructorBuilder)
        || t == typeof(ILGenerator)
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!));

    /// <summary>
    /// Resolve a canonical type string for a GENERIC function's signature: a bare type-parameter name resolves to
    /// its <see cref="GenericTypeParameterBuilder"/>, "T[]" to its array, and everything else falls through to
    /// <see cref="TryResolveType"/>. Type parameters are checked FIRST, mirroring the legacy emitter's ResolveType (a
    /// generic parameter shadows same-named types within its function's signature). Composed shapes over T
    /// (tuples, nested generics) are not modelled and fail — the function declines to the N# backend path.
    /// </summary>
    private static bool TryResolveTypeWithTypeParams(string canonical,
        IReadOnlyDictionary<string, Type> typeParams,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
    {
        if (canonical.StartsWith("&", StringComparison.Ordinal))
        {
            if (canonical.Length > 1
                && TryResolveTypeWithTypeParams(canonical.Substring(1), typeParams, enumRegistry, structRegistry, unionRegistry, out var element)
                && IsSupportedByRefElementType(element))
            {
                type = element.MakeByRefType();
                return true;
            }
            type = null!;
            return false;
        }
        if (typeParams.TryGetValue(canonical, out type!))
            return true;
        if (canonical.EndsWith("[]", StringComparison.Ordinal)
            && typeParams.TryGetValue(canonical.Substring(0, canonical.Length - 2), out var elementParam))
        {
            type = elementParam.MakeArrayType();
            return true;
        }
        // A generic shape whose ARGUMENTS may reference the in-scope type parameters (`Box<T>` as a
        // member/param type inside another generic): resolve through the closed-user-generic path with
        // the parameter map threaded into the argument resolution.
        var genericOpen = canonical.IndexOf('<');
        if (genericOpen > 0 && canonical[^1] == '>' && canonical[0] != '(')
        {
            var unqualifiedGeneric = UnqualifyGenericHead(canonical, genericOpen);
            if (!string.Equals(unqualifiedGeneric, canonical, StringComparison.Ordinal))
                return TryResolveTypeWithTypeParams(unqualifiedGeneric, typeParams, enumRegistry, structRegistry, unionRegistry, out type);
            // The same List/Dictionary/HashSet head-shadowing decline as TryResolveType's generic block.
            if (IsCollectionHeadShadowedByUserType(canonical.Substring(0, genericOpen), enumRegistry, structRegistry, unionRegistry))
            {
                type = null!;
                return false;
            }
            if (TryResolveClosedUserGeneric(canonical, genericOpen, typeParams, enumRegistry, structRegistry, unionRegistry, out type))
                return true;
            if (genericOpen == 10 && canonical.StartsWith("ValueTuple<", StringComparison.Ordinal))
            {
                var tupleArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(11, canonical.Length - 12));
                var openTuple = OpenValueTupleType(tupleArgCanons.Count);
                if (openTuple == null)
                {
                    type = null!;
                    return false;
                }
                var tupleArgs = new Type[tupleArgCanons.Count];
                for (var i = 0; i < tupleArgs.Length; i++)
                {
                    if (!TryResolveTypeWithTypeParams(tupleArgCanons[i], typeParams, enumRegistry, structRegistry, unionRegistry, out tupleArgs[i]))
                    {
                        type = null!;
                        return false;
                    }
                }
                type = openTuple.MakeGenericType(tupleArgs);
                return IsSupportedValueTuple(type);
            }
            if (genericOpen == 4 && canonical.StartsWith("Task<", StringComparison.Ordinal))
            {
                var taskArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(5, canonical.Length - 6));
                if (taskArgCanons.Count == 1
                    && TryResolveTypeWithTypeParams(taskArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var taskElement)
                    && IsSupportedType(taskElement))
                {
                    type = typeof(System.Threading.Tasks.Task<>).MakeGenericType(taskElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (genericOpen == 9 && canonical.StartsWith("ValueTask<", StringComparison.Ordinal))
            {
                var valueTaskArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(10, canonical.Length - 11));
                if (valueTaskArgCanons.Count == 1
                    && TryResolveTypeWithTypeParams(valueTaskArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var valueTaskElement)
                    && IsSupportedType(valueTaskElement))
                {
                    type = typeof(System.Threading.Tasks.ValueTask<>).MakeGenericType(valueTaskElement);
                    return true;
                }
                type = null!;
                return false;
            }
            // BCL COLLECTIONS over in-scope type parameters (`items: List<T>`, `Dictionary<string, T>`,
            // `HashSet<T>`
            // in a generic function's SIGNATURE): close the runtime definition over the threaded
            // resolution so the element lands on the GenericTypeParameterBuilder. The same key/element
            // rules as TryResolveType's collection branches apply — keys must be baked (no T keys).
            if (genericOpen == 4 && canonical.StartsWith("List<", StringComparison.Ordinal))
            {
                var listArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(5, canonical.Length - 6));
                if (listArgCanons.Count == 1
                    && TryResolveTypeWithTypeParams(listArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var listElement)
                    && (listElement is GenericTypeParameterBuilder || IsAdmissibleCollectionElement(listElement)))
                {
                    type = typeof(List<>).MakeGenericType(listElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (genericOpen == 7 && canonical.StartsWith("HashSet<", StringComparison.Ordinal))
            {
                var hashArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(8, canonical.Length - 9));
                if (hashArgCanons.Count == 1
                    && TryResolveTypeWithTypeParams(hashArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var hashElement)
                    && (hashElement is GenericTypeParameterBuilder || IsAdmissibleHashSetElement(hashElement)))
                {
                    type = typeof(HashSet<>).MakeGenericType(hashElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (genericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal))
            {
                var stackArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(6, canonical.Length - 7));
                if (stackArgCanons.Count == 1
                    && TryResolveTypeWithTypeParams(stackArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var stackElement)
                    && (stackElement is GenericTypeParameterBuilder || IsAdmissibleCollectionElement(stackElement)))
                {
                    type = typeof(Stack<>).MakeGenericType(stackElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (genericOpen == 10 && canonical.StartsWith("Dictionary<", StringComparison.Ordinal))
            {
                var dictArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(11, canonical.Length - 12));
                if (dictArgCanons.Count == 2
                    && TryResolveTypeWithTypeParams(dictArgCanons[0], typeParams, enumRegistry, structRegistry, unionRegistry, out var dictKey)
                    && TryResolveTypeWithTypeParams(dictArgCanons[1], typeParams, enumRegistry, structRegistry, unionRegistry, out var dictValue)
                    && !ContainsBuilderBoundType(dictKey)
                    && (dictValue is GenericTypeParameterBuilder || IsAdmissibleCollectionElement(dictValue)))
                {
                    type = typeof(Dictionary<,>).MakeGenericType(dictKey, dictValue);
                    return true;
                }
                type = null!;
                return false;
            }
            type = null!;
            return false;
        }
        return TryResolveType(canonical, enumRegistry, structRegistry, unionRegistry, out type);
    }

    /// <summary>
    /// Member-signature type resolution for a type's own members: the declaring type's generic
    /// parameters (item: T) resolve FIRST, then the registries/builtins.
    /// </summary>
    private static bool TryResolveMemberType(string canonical, ColumnarStructDef def,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
        => def.GenericParameters != null
            ? TryResolveTypeWithTypeParams(canonical, def.GenericParameters, enumRegistry, structRegistry, unionRegistry, out type)
            : TryResolveType(canonical, enumRegistry, structRegistry, unionRegistry, out type);

    /// <summary>
    /// Substitutes a CLOSED instantiation's type arguments into an open member signature type by
    /// generic-parameter position (item: T on Box&lt;int&gt; → int; T[] and nested generics recurse).
    /// Method-level generic parameters are left untouched.
    /// </summary>
    private static Type SubstituteClosedTypeArguments(Type signatureType, Type[] closedArguments)
    {
        if (signatureType.IsGenericParameter)
        {
            bool isMethodParameter;
                isMethodParameter = signatureType.DeclaringMethod != null;
            if (!isMethodParameter && signatureType.GenericParameterPosition < closedArguments.Length)
                return closedArguments[signatureType.GenericParameterPosition];
            return signatureType;
        }
        if (signatureType.IsByRef)
            return SubstituteClosedTypeArguments(signatureType.GetElementType()!, closedArguments).MakeByRefType();
        if (signatureType.IsSZArray)
            return SubstituteClosedTypeArguments(signatureType.GetElementType()!, closedArguments).MakeArrayType();
        if (signatureType.IsGenericType && !signatureType.IsGenericTypeDefinition)
        {
                var definition = signatureType.GetGenericTypeDefinition();
                var arguments = signatureType.GetGenericArguments();
                var substituted = new Type[arguments.Length];
                for (var i = 0; i < arguments.Length; i++)
                    substituted[i] = SubstituteClosedTypeArguments(arguments[i], closedArguments);
                return definition.MakeGenericType(substituted);
        }
        return signatureType;
    }

    private static bool TryResolveKnownExternalType(string canonical, out Type type)
    {
        type = canonical switch
        {
            "IYamlTypeConverter" or "YamlDotNet.Serialization.IYamlTypeConverter" => typeof(IYamlTypeConverter),
            "ObjectDeserializer" or "YamlDotNet.Serialization.ObjectDeserializer" => typeof(ObjectDeserializer),
            "ObjectSerializer" or "YamlDotNet.Serialization.ObjectSerializer" => typeof(ObjectSerializer),
            "DeserializerBuilder" or "YamlDotNet.Serialization.DeserializerBuilder" => typeof(DeserializerBuilder),
            "IDeserializer" or "YamlDotNet.Serialization.IDeserializer" => typeof(IDeserializer),
            "INamingConvention" or "YamlDotNet.Serialization.INamingConvention" => typeof(INamingConvention),
            "CamelCaseNamingConvention" or "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention" => typeof(CamelCaseNamingConvention),
            "IParser" or "YamlDotNet.Core.IParser" => typeof(YamlParser),
            "IEmitter" or "YamlDotNet.Core.IEmitter" => typeof(YamlEmitter),
            "YamlException" or "YamlDotNet.Core.YamlException" => typeof(YamlExceptionType),
            "ParsingEvent" or "YamlDotNet.Core.Events.ParsingEvent" => typeof(ParsingEvent),
            "Scalar" or "YamlDotNet.Core.Events.Scalar" => typeof(Scalar),
            "MappingStart" or "YamlDotNet.Core.Events.MappingStart" => typeof(MappingStart),
            "MappingEnd" or "YamlDotNet.Core.Events.MappingEnd" => typeof(MappingEnd),
            "JsonElement" or "System.Text.Json.JsonElement" => typeof(JsonElement),
            "JsonDocument" or "System.Text.Json.JsonDocument" => typeof(JsonDocument),
            "JsonValueKind" or "System.Text.Json.JsonValueKind" => typeof(JsonValueKind),
            "JsonSerializerOptions" or "System.Text.Json.JsonSerializerOptions" => typeof(JsonSerializerOptions),
            "JsonNamingPolicy" or "System.Text.Json.JsonNamingPolicy" => typeof(JsonNamingPolicy),
            _ => null!,
        };
        return type != null || TryResolveLoadedExternalType(canonical, out type);
    }

    private static bool TryResolveLoadedExternalType(string canonical, out Type type)
    {
        type = null!;
        var fullName = canonical switch
        {
            "WebApplication" => "Microsoft.AspNetCore.Builder.WebApplication",
            "WebApplicationBuilder" => "Microsoft.AspNetCore.Builder.WebApplicationBuilder",
            "HttpContext" => "Microsoft.AspNetCore.Http.HttpContext",
            "HttpRequest" => "Microsoft.AspNetCore.Http.HttpRequest",
            "HttpResponse" => "Microsoft.AspNetCore.Http.HttpResponse",
            "RequestDelegate" => "Microsoft.AspNetCore.Http.RequestDelegate",
            "IResult" => "Microsoft.AspNetCore.Http.IResult",
            _ when canonical.Contains('.', StringComparison.Ordinal) => canonical,
            _ => null,
        };
        if (fullName == null)
            return false;
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            Type? candidate;
            try
            {
                candidate = assembly.GetType(fullName, throwOnError: false);
            }
            catch
            {
                continue;
            }
            if (candidate != null && IsSupportedExternalType(candidate))
            {
                type = candidate;
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Resolves a CLOSED generic over a user-declared generic type (`Box&lt;int&gt;`, or `Box&lt;T&gt;` with
    /// <paramref name="typeParams"/> in scope): the open definition's TypeBuilder (PASS 0 declared its
    /// parameters) is MakeGenericType'd with the recursively resolved argument canonicals. Unknown generic
    /// heads (BCL generics, non-generic user types) and arity mismatches decline.
    /// </summary>
    private static bool TryResolveClosedUserGeneric(string canonical, int genericOpen,
        IReadOnlyDictionary<string, Type>? typeParams,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
    {
        type = null!;
        var headName = canonical.Substring(0, genericOpen);
        // The generic head: a user generic STRUCT/CLASS (`Box<int>`) or a user generic UNION's base
        // (`Opt<int>` — the abstract base closed over the arguments; case heads like `Opt.Some` are NOT
        // annotation types and resolve only inside the construction paths).
        TypeBuilder? openBuilder = null;
        if (structRegistry != null && structRegistry.TryGetValue(headName, out var openDef)
            && openDef.Builder.IsGenericTypeDefinition)
        {
            openBuilder = openDef.Builder;
        }
        else if (unionRegistry != null && unionRegistry.TryGetValue(headName, out var openUnionDef)
            && openUnionDef.Base.IsGenericTypeDefinition)
        {
            openBuilder = openUnionDef.Base;
        }
        if (openBuilder == null)
        {
            return false;
        }

        var argCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2));
        if (argCanons.Count != openBuilder.GetGenericArguments().Length)
        {
            return false;
        }

        var argTypes = new Type[argCanons.Count];
        for (var i = 0; i < argCanons.Count; i++)
        {
            var resolvedArg = typeParams != null
                ? TryResolveTypeWithTypeParams(argCanons[i], typeParams, enumRegistry, structRegistry, unionRegistry, out argTypes[i])
                : TryResolveType(argCanons[i], enumRegistry, structRegistry, unionRegistry, out argTypes[i]);
            if (!resolvedArg)
            {
                return false;
            }
        }

        type = openBuilder.MakeGenericType(argTypes);
        return true;
    }

    /// <summary>
    /// Resolve a canonical N# type string (e.g. "int", "int[]") to its CLR <see cref="Type"/>. Handles a single
    /// trailing "[]" as a single-dimension array of a builtin element; non-builtins/unsupported shapes fail.
    /// </summary>
    private static bool TryResolveType(string canonical, IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
    {
        if (canonical.StartsWith("&", StringComparison.Ordinal))
        {
            if (canonical.Length > 1
                && TryResolveType(canonical.Substring(1), enumRegistry, structRegistry, unionRegistry, out var element)
                && IsSupportedByRefElementType(element))
            {
                type = element.MakeByRefType();
                return true;
            }
            type = null!;
            return false;
        }
        if (canonical.EndsWith("[]", StringComparison.Ordinal))
        {
            if (TryResolveType(canonical.Substring(0, canonical.Length - 2), enumRegistry, structRegistry, unionRegistry, out var elementType)
                && IsSupportedElementType(elementType))
            {
                type = elementType.MakeArrayType();
                return true;
            }
            type = null!;
            return false;
        }
        // A `?` suffix on a REFERENCE type (`string?`, `Box?`) is annotation-only at runtime — the
        // nullable tracking lives in the analyzer; the CLR type is the element itself. A VALUE-type `?`
        // is the REAL Nullable<T> (N2) — modelled over the BAKED value scalars (builders inside a
        // Nullable cannot reflect their members; those decline).
        if (canonical.EndsWith("?", StringComparison.Ordinal))
        {
            var nullableElement = canonical.Substring(0, canonical.Length - 1);
            if (TryResolveType(nullableElement, enumRegistry, structRegistry, unionRegistry, out var elementResolved))
            {
                if (!elementResolved.IsValueType)
                {
                    type = elementResolved;
                    return true;
                }
                if (IsLiftableNullableElement(elementResolved))
                {
                    type = typeof(System.Nullable<>).MakeGenericType(elementResolved);
                    return true;
                }
            }
            type = null!;
            return false;
        }
        // StringBuilder — the modelled mutable reference type — is a valid param/return/local type (a builder is
        // commonly passed IN to an append helper, e.g. AppendQuotedDiagnosticCommandArgument(builder, value)). It
        // is resolved here (param/return/local), NOT in TryResolveBuiltin, so `StringBuilder[]` stays unsupported
        // (array elements resolve through TryResolveBuiltin / IsSupportedElementType, which exclude it).
        if (canonical == "StringBuilder")
        {
            type = typeof(System.Text.StringBuilder);
            return true;
        }
        if (canonical == "object")
        {
            type = typeof(object);
            return true;
        }
        if (canonical == "StringComparer")
        {
            type = typeof(StringComparer);
            return true;
        }
        if (canonical == "SearchOption")
        {
            type = typeof(SearchOption);
            return true;
        }
        if (canonical == "IList")
        {
            type = typeof(IList);
            return true;
        }
        if (canonical == "Type")
        {
            type = typeof(Type);
            return true;
        }
        if (canonical == "Version")
        {
            type = typeof(Version);
            return true;
        }
        if (canonical == "TimeSpan")
        {
            type = typeof(TimeSpan);
            return true;
        }
        if (canonical == "Random")
        {
            type = typeof(Random);
            return true;
        }
        if (canonical == "Process")
        {
            type = typeof(Process);
            return true;
        }
        if (canonical == "ProcessStartInfo")
        {
            type = typeof(ProcessStartInfo);
            return true;
        }
        if (canonical == "StreamReader")
        {
            type = typeof(StreamReader);
            return true;
        }
        if (canonical == "Stream")
        {
            type = typeof(Stream);
            return true;
        }
        if (canonical == "CancellationToken")
        {
            type = typeof(System.Threading.CancellationToken);
            return true;
        }
        if (canonical == "Task")
        {
            type = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (canonical == "ValueTask")
        {
            type = typeof(System.Threading.Tasks.ValueTask);
            return true;
        }
        if (canonical == "Assembly")
        {
            type = typeof(Assembly);
            return true;
        }
        if (canonical == "PropertyInfo")
        {
            type = typeof(PropertyInfo);
            return true;
        }
        if (canonical == "FieldInfo")
        {
            type = typeof(FieldInfo);
            return true;
        }
        if (canonical == "LocalBuilder")
        {
            type = typeof(LocalBuilder);
            return true;
        }
        if (canonical == "FieldBuilder")
        {
            type = typeof(FieldBuilder);
            return true;
        }
        if (canonical == "TypeBuilder")
        {
            type = typeof(TypeBuilder);
            return true;
        }
        if (canonical == "MethodBuilder")
        {
            type = typeof(MethodBuilder);
            return true;
        }
        if (canonical == "MethodInfo")
        {
            type = typeof(MethodInfo);
            return true;
        }
        if (canonical == "ConstructorBuilder")
        {
            type = typeof(ConstructorBuilder);
            return true;
        }
        if (canonical == "ILGenerator")
        {
            type = typeof(ILGenerator);
            return true;
        }
        if (TryResolveKnownExternalType(canonical, out type))
            return true;
        if (TryResolveBclExceptionType(canonical, out type))
            return true;
        // Tuple `(e0,e1,...)` -> System.ValueTuple<...> (positional, arity 2-7). The canonical is parens + comma-joined element canons;
        // split at the TOP level (respecting nested ()/<>/[]), resolve each element recursively, then
        // MakeGenericType the matching open ValueTuple. (Only Tuple type nodes produce a `(...)` canonical.)
        if (canonical.Length >= 2 && canonical[0] == '(' && canonical[^1] == ')')
        {
            var tupleCanonical = ColumnarTypeCanonicalizer.StripTupleElementNames(canonical).Canonical;
            var elements = ColumnarTypeCanonicalizer.SplitTopLevelCommas(tupleCanonical.Substring(1, tupleCanonical.Length - 2));
            Type? openTuple = elements.Count switch
            {
                2 => typeof(ValueTuple<,>),
                3 => typeof(ValueTuple<,,>),
                4 => typeof(ValueTuple<,,,>),
                5 => typeof(ValueTuple<,,,,>),
                6 => typeof(ValueTuple<,,,,,>),
                7 => typeof(ValueTuple<,,,,,,>),
                _ => null,
            };
            if (openTuple != null)
            {
                var elementTypes = new Type[elements.Count];
                var resolved = true;
                for (var i = 0; i < elements.Count; i++)
                {
                    if (!TryResolveType(elements[i], enumRegistry, structRegistry, unionRegistry, out elementTypes[i]))
                    {
                        resolved = false;
                        break;
                    }
                }

                if (resolved)
                {
                    type = openTuple.MakeGenericType(elementTypes);
                    return true;
                }
            }

            type = null!;
            return false;
        }
        // `Func<p1,...,ret>` — the production parser's FUNCTION-TYPE sugar (Parser.cs special-cases the
        // NAME `Func` at parse, so this spelling is ALWAYS a function type even if a user declares a type
        // named Func — the sugar wins; mirror it by checking before the user-generic path). The LAST type
        // argument is the RETURN type; `void` is legal there and lowers to the matching System.Action —
        // `Func<int, void>` IS Action<int>, exactly as the legacy emitter's CreateDelegateType maps it.
        if (canonical.StartsWith("Func<", StringComparison.Ordinal) && canonical[^1] == '>')
        {
            return TryResolveDelegateCanonical(
                canonical.Substring(5, canonical.Length - 6), hasReturnSlot: true,
                enumRegistry, structRegistry, unionRegistry, out type);
        }
        // A CLOSED generic over a user-declared generic type (`Box<int>`): head + args split at the
        // top-level `<`; the open TypeBuilder (PASS 0 declared its parameters) is MakeGenericType'd.
        // Unknown generic heads (BCL generics) decline — EXCEPT `Action<...>`, which falls back to the
        // System.Action family when no user generic claims the name (the parser does NOT sugar Action,
        // so a user-declared Action<T> wins, matching the production resolution order).
        var closedGenericOpen = canonical.IndexOf('<');
        if (closedGenericOpen > 0 && canonical[^1] == '>')
        {
            var unqualifiedGeneric = UnqualifyGenericHead(canonical, closedGenericOpen);
            if (!string.Equals(unqualifiedGeneric, canonical, StringComparison.Ordinal))
                return TryResolveType(unqualifiedGeneric, enumRegistry, structRegistry, unionRegistry, out type);
            // A user type NAMED List/Dictionary/HashSet shadows the BCL heads → the pipeline rejects every
            // closed-generic use of that head (and binds inconsistently between analyzer and emitter
            // for generic ones) — decline before EITHER resolution can claim it.
            if (IsCollectionHeadShadowedByUserType(canonical.Substring(0, closedGenericOpen), enumRegistry, structRegistry, unionRegistry))
            {
                type = null!;
                return false;
            }
            if (TryResolveClosedUserGeneric(canonical, closedGenericOpen, null, enumRegistry, structRegistry, unionRegistry, out type))
                return true;
            if (closedGenericOpen == 10 && canonical.StartsWith("ValueTuple<", StringComparison.Ordinal))
            {
                var tupleArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(11, canonical.Length - 12));
                var openTuple = OpenValueTupleType(tupleArgCanons.Count);
                if (openTuple == null)
                {
                    type = null!;
                    return false;
                }
                var tupleArgs = new Type[tupleArgCanons.Count];
                for (var i = 0; i < tupleArgs.Length; i++)
                {
                    if (!TryResolveType(tupleArgCanons[i], enumRegistry, structRegistry, unionRegistry, out tupleArgs[i]))
                    {
                        type = null!;
                        return false;
                    }
                }
                type = openTuple.MakeGenericType(tupleArgs);
                return IsSupportedValueTuple(type);
            }
            if (closedGenericOpen == 6 && canonical.StartsWith("Action<", StringComparison.Ordinal))
            {
                return TryResolveDelegateCanonical(
                    canonical.Substring(7, canonical.Length - 8), hasReturnSlot: false,
                    enumRegistry, structRegistry, unionRegistry, out type);
            }
            if (closedGenericOpen == 4 && canonical.StartsWith("Task<", StringComparison.Ordinal))
            {
                var taskArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(5, canonical.Length - 6));
                if (taskArgCanons.Count == 1
                    && TryResolveType(taskArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var taskElement)
                    && IsSupportedType(taskElement))
                {
                    type = typeof(System.Threading.Tasks.Task<>).MakeGenericType(taskElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 9 && canonical.StartsWith("ValueTask<", StringComparison.Ordinal))
            {
                var valueTaskArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(10, canonical.Length - 11));
                if (valueTaskArgCanons.Count == 1
                    && TryResolveType(valueTaskArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var valueTaskElement)
                    && IsSupportedType(valueTaskElement))
                {
                    type = typeof(System.Threading.Tasks.ValueTask<>).MakeGenericType(valueTaskElement);
                    return true;
                }
                type = null!;
                return false;
            }
            // BCL COLLECTIONS — `List<T>` / `Dictionary<K,V>` / `HashSet<T>` close over the runtime generics. A USER type
            // named List/Dictionary/HashSet shadows the head entirely (declined above — the pipeline REJECTS such
            // uses; the Action-style "user wins" ordering does NOT hold for these heads). Elements may be
            // user TypeBuilders or nested collections (the builder-element rebind rung — member binding
            // rebinds via ResolveClosedGenericMethod/Ctor); IsAdmissibleCollectionElement pins what stays
            // out. Dictionary KEYS and HashSet ELEMENTS must stay BAKED: hashing over a builder type rides the
            // key/element type's synthesized Equals/GetHashCode, and the columnar PASS 0e synthesis-skip rules
            // (builder-typed-field records get none) would diverge from the legacy emitter — pinned decline.
            if (closedGenericOpen == 4 && canonical.StartsWith("List<", StringComparison.Ordinal))
            {
                var listArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(5, canonical.Length - 6));
                if (listArgCanons.Count == 1
                    && TryResolveType(listArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var listElement)
                    && IsAdmissibleCollectionElement(listElement))
                {
                    type = typeof(List<>).MakeGenericType(listElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 7 && canonical.StartsWith("HashSet<", StringComparison.Ordinal))
            {
                var hashArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(8, canonical.Length - 9));
                if (hashArgCanons.Count == 1
                    && TryResolveType(hashArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var hashElement)
                    && IsAdmissibleHashSetElement(hashElement))
                {
                    type = typeof(HashSet<>).MakeGenericType(hashElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal))
            {
                var stackArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(6, canonical.Length - 7));
                if (stackArgCanons.Count == 1
                    && TryResolveType(stackArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var stackElement)
                    && IsAdmissibleCollectionElement(stackElement))
                {
                    type = typeof(Stack<>).MakeGenericType(stackElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 13 && canonical.StartsWith("IReadOnlyList<", StringComparison.Ordinal))
            {
                var listArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(14, canonical.Length - 15));
                if (listArgCanons.Count == 1
                    && TryResolveType(listArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var listElement)
                    && IsAdmissibleCollectionElement(listElement))
                {
                    type = typeof(IReadOnlyList<>).MakeGenericType(listElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 19 && canonical.StartsWith("IReadOnlyCollection<", StringComparison.Ordinal))
            {
                var collectionArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(20, canonical.Length - 21));
                if (collectionArgCanons.Count == 1
                    && TryResolveType(collectionArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var collectionElement)
                    && IsAdmissibleCollectionElement(collectionElement))
                {
                    type = typeof(IReadOnlyCollection<>).MakeGenericType(collectionElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 12 && canonical.StartsWith("IReadOnlySet<", StringComparison.Ordinal))
            {
                var setArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(13, canonical.Length - 14));
                if (setArgCanons.Count == 1
                    && TryResolveType(setArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var setElement)
                    && IsAdmissibleHashSetElement(setElement))
                {
                    type = typeof(IReadOnlySet<>).MakeGenericType(setElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 11 && canonical.StartsWith("IEnumerable<", StringComparison.Ordinal))
            {
                var enumerableArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(12, canonical.Length - 13));
                if (enumerableArgCanons.Count == 1
                    && TryResolveType(enumerableArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var enumerableElement)
                    && IsAdmissibleCollectionElement(enumerableElement))
                {
                    type = typeof(IEnumerable<>).MakeGenericType(enumerableElement);
                    return true;
                }
                type = null!;
                return false;
            }
            if (closedGenericOpen == 10 && canonical.StartsWith("Dictionary<", StringComparison.Ordinal))
            {
                var dictArgCanons = ColumnarTypeCanonicalizer.SplitTopLevelCommas(canonical.Substring(11, canonical.Length - 12));
                if (dictArgCanons.Count == 2
                    && TryResolveType(dictArgCanons[0], enumRegistry, structRegistry, unionRegistry, out var dictKey)
                    && TryResolveType(dictArgCanons[1], enumRegistry, structRegistry, unionRegistry, out var dictValue)
                    && !ContainsNonEnumBuilderBoundType(dictKey)
                    && IsAdmissibleCollectionElement(dictValue))
                {
                    type = typeof(Dictionary<,>).MakeGenericType(dictKey, dictValue);
                    return true;
                }
                type = null!;
                return false;
            }
            type = null!;
            return false;
        }
        // A bare name matching a user-defined enum resolves to its finalized CLR Type (so `Color` is a valid
        // param/return/local type and can close BCL generics). Checked before the builtins so a user enum never
        // collides with a builtin name (it cannot — builtin names are reserved keywords the parser would not accept
        // as an enum name).
        if (enumRegistry != null && enumRegistry.TryGetValue(canonical, out var enumDef))
        {
            if (enumDef.IsStringBacked)
            {
                type = typeof(string);
                return true;
            }
            type = enumDef.EnumType;
            return true;
        }
        // A bare name matching a user-defined struct resolves to its TypeBuilder (a valid param/return/local type).
        if (structRegistry != null && structRegistry.TryGetValue(canonical, out var structDef))
        {
            type = structDef.Builder;
            return true;
        }
        // A bare name matching a user-defined union resolves to its abstract BASE TypeBuilder — the static type a
        // `Union`-typed param/return/local holds (a concrete case constructed elsewhere is an instance of it).
        // A GENERIC union's bare name is an ARITY ERROR (the pipeline reports NL207: `Opt` requires its type
        // arguments) — fail so the program declines; the closed form (`Opt<int>`) resolves via the
        // closed-user-generic path.
        if (unionRegistry != null && unionRegistry.TryGetValue(canonical, out var unionDef))
        {
            if (unionDef.Base.IsGenericTypeDefinition)
            {
                type = null!;
                return false;
            }
            type = unionDef.Base;
            return true;
        }
        // Bare `Action` (the zero-parameter void delegate). Checked AFTER the user registries — the parser
        // does not sugar the Action name, so a user type named Action wins, matching production resolution.
        if (canonical == "Action")
        {
            type = typeof(Action);
            return true;
        }
        if (TryResolveBuiltin(canonical, out type))
            return true;
        // Alias/namespace-QUALIFIED user type (`Ids.UserId`, `Models.Point`): the registries key
        // SHORT names, so retry with the unqualified tail. Analysis already validated the qualifier.
        if (canonical.Contains('.'))
        {
            var unqualified = ColumnarTypeCanonicalizer.UnqualifiedTypeName(canonical);
            if (!string.Equals(unqualified, canonical, StringComparison.Ordinal))
                return TryResolveType(unqualified, enumRegistry, structRegistry, unionRegistry, out type);
        }
        return false;
    }

    // Resolve a delegate canonical's comma-joined type-argument list to a closed System.Func/Action.
    // `hasReturnSlot` distinguishes Func sugar (LAST argument is the return type, `void` allowed there)
    // from Action<...> (parameters only). Parameters cap at 4 (the modeled surface); every resolved part
    // must be a BAKED runtime type — a delegate closed over an un-baked builder type cannot resolve its
    // ctor/Invoke via plain reflection (the same rule the tuple path applies to its elements).
    private static bool TryResolveDelegateCanonical(string argList, bool hasReturnSlot,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
    {
        type = null!;
        var parts = ColumnarTypeCanonicalizer.SplitTopLevelCommas(argList);
        if (parts.Count == 0)
            return false;
        var paramCount = parts.Count;
        var returnType = typeof(void);
        if (hasReturnSlot)
        {
            paramCount -= 1;
            var returnCanonical = parts[paramCount];
            if (returnCanonical != "void"
                && (!TryResolveType(returnCanonical, enumRegistry, structRegistry, unionRegistry, out returnType)
                    || returnType.Assembly is AssemblyBuilder))
                return false;
        }
        if (paramCount > 4)
            return false;
        var paramTypes = new Type[paramCount];
        for (var i = 0; i < paramCount; i++)
        {
            if (parts[i] == "void"
                || !TryResolveType(parts[i], enumRegistry, structRegistry, unionRegistry, out paramTypes[i])
                || paramTypes[i].Assembly is AssemblyBuilder)
                return false;
        }
        if (returnType == typeof(void))
        {
            if (paramCount == 0)
            {
                type = typeof(Action);
                return true;
            }
            var openAction = paramCount switch
            {
                1 => typeof(Action<>), 2 => typeof(Action<,>), 3 => typeof(Action<,,>), _ => typeof(Action<,,,>),
            };
            type = openAction.MakeGenericType(paramTypes);
            return true;
        }
        var openFunc = paramCount switch
        {
            0 => typeof(Func<>), 1 => typeof(Func<,>), 2 => typeof(Func<,,>), 3 => typeof(Func<,,,>), _ => typeof(Func<,,,,>),
        };
        var closedArgs = new Type[paramCount + 1];
        System.Array.Copy(paramTypes, closedArgs, paramCount);
        closedArgs[paramCount] = returnType;
        type = openFunc.MakeGenericType(closedArgs);
        return true;
    }

    // Parse a floating-point literal's body (type suffix already stripped by the caller) to its double value,
    // mirroring the N# backend path's ParseFloatLiteralValue: drop `_` digit separators, then parse invariant-culture.
    // An f-literal narrows the result to float at the call site; a double-literal uses it directly.
    private static bool TryParseFloatingLiteralBody(string body, out double value)
    {
        value = 0;
        var s = body.Trim().Replace("_", string.Empty);
        return double.TryParse(
            s,
            System.Globalization.NumberStyles.Float | System.Globalization.NumberStyles.AllowThousands,
            System.Globalization.CultureInfo.InvariantCulture,
            out value);
    }

    /// <summary>Canonical N# primitive type name → its CLR <see cref="Type"/>. Non-builtins are unsupported.</summary>
    internal static bool TryResolveBuiltin(string canonical, out Type type)
    {
        type = canonical switch
        {
            "int" => typeof(int),
            "long" => typeof(long),
            "uint" => typeof(uint),
            "ulong" => typeof(ulong),
            "short" => typeof(short),
            "ushort" => typeof(ushort),
            "byte" => typeof(byte),
            "sbyte" => typeof(sbyte),
            "bool" => typeof(bool),
            "char" => typeof(char),
            "double" => typeof(double),
            "float" => typeof(float),
            "decimal" => typeof(decimal),
            "string" => typeof(string),
            "DateTime" => typeof(DateTime),
            _ => null!,
        };
        return type != null;
    }

    /// <summary>
    /// Build a single assembly from one parsed columnar program bundle.
    /// </summary>
    internal static bool TryEmitColumnarAssembly(
        string assemblyName, string typeName, ColumnarProgramInput program, bool isExecutable, out byte[] assembly,
        Version? assemblyVersion = null, IReadOnlyList<string>? referenceAssemblyPaths = null)
    {
        assembly = Array.Empty<byte>();
        var funcs = program.Functions;
        var enums = program.Enums;
        var structs = program.Structs;
        var unions = program.Unions;
        var interfaces = program.Interfaces;
        if (funcs.Count == 0 && enums.Count == 0 && structs.Count == 0 && unions.Count == 0 && interfaces.Count == 0
            && program.Tests is not { Count: > 0 })
            return DeclineStatic("emit.program.empty", "columnar program has no modeled declarations");

        var assemblyIdentity = new AssemblyName(assemblyName);
        if (assemblyVersion != null)
            assemblyIdentity.Version = assemblyVersion;
        var builder = new PersistedAssemblyBuilder(assemblyIdentity, typeof(object).Assembly);
        var module = builder.DefineDynamicModule(assemblyName);
        PreloadSupportedExternalReferenceAssemblies(referenceAssemblyPaths);

        // PASS 0: define every user enum as a module-level i4-underlying enum type, BEFORE the Program type and the
        // function signatures (pass 1) so a function can use an enum as a param/return/local type and resolve its
        // members. Enums have no dependency on later user types, so bake them immediately; this keeps runtime generic
        // instantiations such as List<Color> on normal closed-Type handles instead of fragile EnumBuilder handles.
        var enumRegistry = new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal);
        for (var e = 0; e < enums.Count; e++)
        {
            var en = enums[e];
            if (en.IsStringBacked)
            {
                var stringConstants = new Dictionary<string, string>(StringComparer.Ordinal);
                var tb = module.DefineType(en.Name, TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.Abstract | TypeAttributes.Sealed);
                for (var m = 0; m < en.MemberNames.Length; m++)
                {
                    var memberValue = m < en.MemberStringValues.Length ? en.MemberStringValues[m] : en.MemberNames[m];
                    var field = tb.DefineField(en.MemberNames[m],
                        typeof(string),
                        FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal | FieldAttributes.HasDefault);
                    field.SetConstant(memberValue);
                    stringConstants[en.MemberNames[m]] = memberValue;
                }

                _ = tb.CreateType();
                var stringEnumDef = new ColumnarEnumDef(typeof(string), new Dictionary<string, int>(StringComparer.Ordinal), stringConstants);
                enumRegistry[en.Name] = stringEnumDef;
                TryRegisterEnumAlias(enumRegistry, en.Name, stringEnumDef);
                continue;
            }

            var eb = module.DefineEnum(en.Name, TypeAttributes.Public, typeof(int));
            var constants = new Dictionary<string, int>(StringComparer.Ordinal);
            for (var m = 0; m < en.MemberNames.Length; m++)
            {
                eb.DefineLiteral(en.MemberNames[m], en.MemberValues[m]);
                constants[en.MemberNames[m]] = en.MemberValues[m];
            }
            var enumType = eb.CreateType();
            var enumDef = new ColumnarEnumDef(enumType, constants);
            enumRegistry[en.Name] = enumDef;
            TryRegisterEnumAlias(enumRegistry, en.Name, enumDef);
        }

        // Union registries — declared empty here (populated in the union PASS below, after structs) so the struct/
        // function type-resolution calls can reference them. `unionCaseRegistry` is keyed by qualified "Union.Case".
        var unionRegistry = new Dictionary<string, ColumnarUnionDef>(StringComparer.Ordinal);
        var unionCaseRegistry = new Dictionary<string, ColumnarUnionCaseDef>(StringComparer.Ordinal);
        var unionBaseBuilders = new List<TypeBuilder>();
        var unionCaseBuilders = new List<TypeBuilder>();

        // PASS 0 (structs): define every user struct as a module-level VALUE TYPE — System.ValueType base, attributes
        // `Public | Sealed` with NO explicit layout (default auto) — plus a public instance field per declared field.
        // The FieldBuilder handles are stored in the registry and
        // used DIRECTLY for ldfld/stfld/construction (never GetField, which throws on an un-finalized TypeBuilder).
        // Field types resolve via TryResolveType (single builtins in this slice). Defined after enums so a struct may
        // have an enum-typed field; a struct-typed field resolves only if that struct was declared earlier.
        var structRegistry = new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal);

        // PASS 0i (interfaces): define every user interface (Public|Abstract|Interface), register it
        // in the STRUCT registry with IsInterface=true, then wire base-interface inheritance and abstract
        // method members. All interface TypeBuilders are registered before any base list or signature
        // resolves, so interface inheritance is order-insensitive.
        var interfaceDefsInOrder = new List<ColumnarStructDef>(interfaces.Count);
        var interfaceMethodJobs = new List<(ColumnarStructDef Interface, ColumnarFunctionInput Method, MethodBuilder Builder,
            Type ReturnType, Dictionary<string, int> Ordinals, Dictionary<string, Type> ParamTypes)>();
        foreach (var iface in interfaces)
        {
            var interfaceTb = module.DefineType(iface.Name, TypeAttributes.Public | TypeAttributes.Interface | TypeAttributes.Abstract);
            var interfaceDef = new ColumnarStructDef(interfaceTb, Array.Empty<string>(),
                new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), isReference: true)
            { IsInterface = true };
            structRegistry[iface.Name] = interfaceDef;
            TryRegisterStructAlias(structRegistry, iface.Name, interfaceDef);
            interfaceDefsInOrder.Add(interfaceDef);
        }

        var structBuilders = new TypeBuilder[structs.Count];
        var structDefsInOrder = new ColumnarStructDef[structs.Count];
        for (var s = 0; s < structs.Count; s++)
        {
            var st = structs[s];
            // A RECORD is a reference type (class with `object` base + a public default ctor for object-init via
            // `newobj`); a struct is a `System.ValueType`-based value type. Fields are defined in the next pass
            // after every type name is in the registry, so field signatures can reference later-declared types.
            var tb = st.IsReference
                ? module.DefineType(st.Name, TypeAttributes.Public | TypeAttributes.Class, typeof(object))
                : module.DefineType(st.Name, TypeAttributes.Public | TypeAttributes.Sealed, typeof(ValueType));

            // Generic type parameters (`class Box<T>`): declared on the builder before any member signature
            // resolves (a member type naming T needs the GenericTypeParameterBuilder). Duplicate names decline in
            // the product parser wrapper before this point.
            Dictionary<string, Type>? typeGenericParams = null;
            if (st.TypeParamNames is { Length: > 0 })
            {
                typeGenericParams = new Dictionary<string, Type>(StringComparer.Ordinal);
                var declaredParams = tb.DefineGenericParameters(st.TypeParamNames);
                for (var tp = 0; tp < declaredParams.Length; tp++)
                    typeGenericParams[st.TypeParamNames[tp]] = declaredParams[tp];
            }

            var fields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
            var newDef = new ColumnarStructDef(tb, Array.Empty<string>(), fields, st.IsReference, st.IsRecord)
            {
                IsNewtype = st.IsNewtype,
                GenericParameters = typeGenericParams,
            };
            structBuilders[s] = tb;
            structDefsInOrder[s] = newDef;
            structRegistry[st.Name] = newDef;
            TryRegisterStructAlias(structRegistry, st.Name, newDef);
        }

        // Union BASE types must be known before struct/record fields resolve: records like
        // `TaskItem { Status: Status }` can reference a union declared in the same package. Cases are populated
        // later, after all struct TypeBuilders are registered, but the field signature only needs the base type.
        for (var u = 0; u < unions.Count; u++)
        {
            var un = unions[u];
            if (un.IsValueStruct)
            {
                var structTb = module.DefineType(
                    un.Name,
                    TypeAttributes.Public | TypeAttributes.Sealed | TypeAttributes.SequentialLayout,
                    typeof(ValueType));
                var valueStructDef = new ColumnarUnionDef(structTb, 0) { IsValueStruct = true };
                unionRegistry[un.Name] = valueStructDef;
                TryRegisterUnionAlias(unionRegistry, un.Name, valueStructDef);
                unionBaseBuilders.Add(structTb);
                continue;
            }

            var baseTb = module.DefineType(un.Name, TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.Abstract, typeof(object));
            if (un.TypeParamNames.Length > 0)
                baseTb.DefineGenericParameters(un.TypeParamNames);
            var unionDef = new ColumnarUnionDef(baseTb, un.TypeParamNames.Length);
            unionRegistry[un.Name] = unionDef;
            TryRegisterUnionAlias(unionRegistry, un.Name, unionDef);
            unionBaseBuilders.Add(baseTb);
        }

        for (var i = 0; i < interfaces.Count; i++)
        {
            var iface = interfaces[i];
            var interfaceDef = interfaceDefsInOrder[i];
            foreach (var baseInterfaceName in iface.BaseInterfaceNames)
            {
                if (!structRegistry.TryGetValue(baseInterfaceName, out var baseInterface)
                    || !baseInterface.IsInterface
                    || ReferenceEquals(baseInterface, interfaceDef))
                    return false;
                interfaceDef.InterfaceBases.Add(baseInterface);
                interfaceDef.Builder.AddInterfaceImplementation(baseInterface.Builder);
            }
            for (var m = 0; m < iface.MethodNames.Length; m++)
            {
                Type memberReturn;
                if (iface.MethodReturnCanonicals[m] == "void")
                    memberReturn = typeof(void);
                else if (!TryResolveType(iface.MethodReturnCanonicals[m], enumRegistry, structRegistry, null, out memberReturn)
                    || !IsSupportedType(memberReturn))
                    return false;
                var memberParams = new Type[iface.MethodParamCanonicals[m].Length];
                for (var p = 0; p < memberParams.Length; p++)
                {
                    if (!TryResolveType(iface.MethodParamCanonicals[m][p], enumRegistry, structRegistry, null, out memberParams[p])
                        || !IsSupportedParameterType(memberParams[p]))
                        return false;
                }
                var hasDefaultBody = iface.MethodBodies[m] != null;
                var methodAttributes = MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig
                    | MethodAttributes.NewSlot;
                if (!hasDefaultBody)
                    methodAttributes |= MethodAttributes.Abstract;
                var abstractMethod = interfaceDef.Builder.DefineMethod(
                    iface.MethodNames[m],
                    methodAttributes,
                    memberReturn, memberParams);
                if (!DefineMethodParameterMetadata(abstractMethod, memberParams, iface.MethodParamNames[m], Array.Empty<int>(), Array.Empty<int>(), Array.Empty<string?>(), enumRegistry))
                    return false;
                AddInstanceMethod(interfaceDef, iface.MethodNames[m], (abstractMethod, memberParams, memberReturn));
                if (hasDefaultBody)
                {
                    interfaceDef.DefaultInterfaceMethodNames.Add(iface.MethodNames[m]);
                    var memberOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                    var memberParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal);
                    for (var p = 0; p < memberParams.Length; p++)
                    {
                        memberOrdinals[iface.MethodParamNames[m][p]] = p + 1;
                        memberParamTypes[iface.MethodParamNames[m][p]] = memberParams[p];
                    }
                    interfaceMethodJobs.Add((interfaceDef, iface.MethodBodies[m]!, abstractMethod, memberReturn, memberOrdinals, memberParamTypes));
                }
            }
        }
        var interfaceDepths = new int[interfaceDefsInOrder.Count];
        var interfaceDepthMemo = new Dictionary<ColumnarStructDef, int>();
        for (var i = 0; i < interfaceDefsInOrder.Count; i++)
        {
            var depth = InterfaceDepthOrMinusOne(interfaceDefsInOrder[i], interfaceDepthMemo, new HashSet<ColumnarStructDef>());
            if (depth < 0)
                return false; // interface inheritance cycle.
            interfaceDepths[i] = depth;
        }
        for (var s = 0; s < structs.Count; s++)
        {
            var st = structs[s];
            var tb = structBuilders[s];
            var def = structDefsInOrder[s];
            var typeGenericParams = def.GenericParameters;
            var fields = def.Fields;
            var instanceFieldNames = new List<string>(st.FieldNames.Length);
            var staticFieldInits = new List<(FieldBuilder Field, Type Type, int InitKind, string InitText)>();
            for (var fi = 0; fi < st.FieldNames.Length; fi++)
            {
                // Field types resolve the type's own generic parameters FIRST (item: T), then the registries.
                var fieldTypeResolved = typeGenericParams != null
                    ? TryResolveTypeWithTypeParams(st.FieldTypeCanonicals[fi], typeGenericParams, enumRegistry, structRegistry, unionRegistry, out var fieldType)
                    : TryResolveType(st.FieldTypeCanonicals[fi], enumRegistry, structRegistry, unionRegistry, out fieldType);
                if (!fieldTypeResolved || !IsSupportedType(fieldType))
                {
                    return DeclineStatic("emit.declaration.field-type", "field type '" + st.FieldTypeCanonicals[fi] + "' could not be resolved for '" + st.Name + "." + st.FieldNames[fi] + "'", st.Name);
                }
                // STATIC fields typed by a generic parameter decline: `static count: T` has no single CLR
                // storage across instantiations the modelled surface can express (the legacy emitter's behavior for
                // these shapes is unprobed — decline-safe).
                if (st.FieldStaticFlags[fi] && fieldType is GenericTypeParameterBuilder)
                    return false;
                var isStaticField = st.FieldStaticFlags[fi];
                var isReadonlyField = fi < st.FieldReadonlyFlags.Length && st.FieldReadonlyFlags[fi];
                if (isStaticField)
                {
                    var staticAttributes = FieldAttributes.Public | FieldAttributes.Static;
                    if (isReadonlyField)
                        staticAttributes |= FieldAttributes.InitOnly;
                    var sfb = tb.DefineField(st.FieldNames[fi], fieldType, staticAttributes);
                    def.StaticFields[st.FieldNames[fi]] = sfb;
                    var initKind = st.FieldInitKinds[fi];
                    if (initKind >= 0)
                        staticFieldInits.Add((sfb, fieldType, initKind, st.FieldInitTexts[fi]));
                    continue;
                }
                // An INSTANCE field initializer is not modelled (the kernel declines it; defensive here).
                if (st.FieldInitKinds[fi] >= 0)
                    return DeclineStatic("emit.declaration.field-initializer", "instance field initializer is not modeled for '" + st.Name + "." + st.FieldNames[fi] + "'", st.Name);
                var instanceAttributes = FieldAttributes.Public;
                if (isReadonlyField)
                    instanceAttributes |= FieldAttributes.InitOnly;
                var fb = tb.DefineField(st.FieldNames[fi], fieldType, instanceAttributes);
                fields[st.FieldNames[fi]] = fb;
                if (st.FieldTypeCanonicals[fi].EndsWith("?", StringComparison.Ordinal))
                    def.NullableFields.Add(st.FieldNames[fi]);
                instanceFieldNames.Add(st.FieldNames[fi]);
            }
            def.SetFieldOrder(instanceFieldNames.ToArray());
            // STATIC FIELD INITIALIZERS run in the type's .cctor, in declaration order (static-initializer
            // semantics). Only single-token literals are modelled (the kernel guarantees it); the literal must
            // agree with the declared field type — a mismatch declines (the legacy emitter's implicit conversions are not
            // modelled). Fields with no initializer keep the CLR zero default (no .cctor entry needed).
            if (staticFieldInits.Count > 0)
            {
                var cctorIl = tb.DefineTypeInitializer().GetILGenerator();
                foreach (var (sfField, sfType, sfKind, sfText) in staticFieldInits)
                {
                    if (!TryEmitStaticFieldInitializerLoad(cctorIl, sfType, sfKind, sfText))
                        return false;
                    cctorIl.Emit(OpCodes.Stsfld, sfField);
                }
                cctorIl.Emit(OpCodes.Ret);
            }
        }

        // PASS 0a' (base/interface lists): resolve each colon-list name. Any interface becomes a directly
        // implemented interface (and contributes its inherited interfaces to metadata); at most one class may
        // become the parent, and only for a CLASS. A base on a value type, record inheritance, a record
        // base, an unknown/non-type name, multiple class bases, and inheritance
        // cycles all decline rather than silently changing type identity or emitting unloadable IL.
        for (var s = 0; s < structs.Count; s++)
        {
            var def = structRegistry[structs[s].Name];
            var seenImplementedInterfaces = new HashSet<TypeBuilder>();
            foreach (var baseName in structs[s].BaseNames)
            {
                if (!structRegistry.TryGetValue(baseName, out var baseDef))
                {
                    if (TryResolveKnownExternalType(baseName, out var externalBase) && externalBase.IsInterface)
                    {
                        def.ExternalInterfaces.Add(externalBase);
                        def.Builder.AddInterfaceImplementation(externalBase);
                        continue;
                    }
                    return DeclineStatic("emit.declaration.base-type", "base/interface type '" + baseName + "' could not be resolved for '" + structs[s].Name + "'", structs[s].Name);
                }
                if (baseDef.IsInterface)
                {
                    def.ImplementedInterfaces.Add(baseDef);
                    foreach (var implemented in EnumerateInterfaceAndBases(baseDef))
                    {
                        if (seenImplementedInterfaces.Add(implemented.Builder))
                            def.Builder.AddInterfaceImplementation(implemented.Builder);
                    }
                    continue;
                }
                if (!def.IsReference)
                {
                    return false; // a value-type struct cannot inherit.
                }
                if (def.IsRecord)
                {
                    return false; // record inheritance is unmodelled — only a CLASS may inherit.
                }
                if (!baseDef.IsReference || ReferenceEquals(baseDef, def))
                {
                    return false; // non-class / self base.
                }
                if (baseDef.IsRecord)
                {
                    return false; // a RECORD can never be a base type (the legacy emitter emits records SEALED).
                }
                if (def.BaseDef != null)
                {
                    return false; // multiple class bases.
                }
                def.BaseDef = baseDef;
                def.Builder.SetParent(baseDef.Builder);
            }
        }

        // PASS 0a'' (duck interfaces): N# interfaces are structurally assignable. When a class/record/struct
        // declares the exact instance methods an interface requires, emit real CLR interface metadata so later
        // value-flow sites (for example `List<INotifier>.Add(new ConsoleNotifier())`) are verifiable and the
        // method declaration pass below can wire DefineMethodOverride.
        for (var s = 0; s < structs.Count; s++)
        {
            var st = structs[s];
            var def = structRegistry[st.Name];
            var implementedBuilders = new HashSet<TypeBuilder>();
            foreach (var implementedInterface in def.ImplementedInterfaces)
            {
                foreach (var inherited in EnumerateInterfaceAndBases(implementedInterface))
                    implementedBuilders.Add(inherited.Builder);
            }

            foreach (var interfaceDef in interfaceDefsInOrder)
            {
                if (implementedBuilders.Contains(interfaceDef.Builder))
                    continue;
                if (!ColumnarStructInputSatisfiesDuckInterface(st, def, interfaceDef, enumRegistry, structRegistry, unionRegistry))
                    continue;
                def.ImplementedInterfaces.Add(interfaceDef);
                foreach (var implemented in EnumerateInterfaceAndBases(interfaceDef))
                {
                    if (implementedBuilders.Add(implemented.Builder))
                        def.Builder.AddInterfaceImplementation(implemented.Builder);
                }
            }
        }

        // Chain-depth per type: 0 for no base, base's depth + 1 otherwise. A chain longer than the type count is a
        // CYCLE (A: B, B: A) — decline before any IL references the malformed hierarchy.
        var structDepths = new int[structs.Count];
        for (var s = 0; s < structs.Count; s++)
        {
            var depth = 0;
            for (var d = structRegistry[structs[s].Name].BaseDef; d != null; d = d.BaseDef)
            {
                depth++;
                if (depth > structs.Count)
                    return false; // inheritance cycle.
            }
            structDepths[s] = depth;
        }

        // PASS 0b (struct methods): now that all struct TYPES exist, DECLARE each struct's methods (a second
        // pass so a method's return type may reference any struct). INSTANCE methods: scalar/struct-returning, with
        // or without parameters; `this` is arg 0, so user param ordinals shift by +1 (void instance methods decline
        // — a later slice). STATIC methods (`static func`): declared with MethodAttributes.Static, NO implicit
        // `this` (ordinals unshifted), void allowed (the body emits exactly like a top-level procedure), and
        // OVERLOADS by distinct PARAM COUNT (same-name/same-arity static overload sets are parser declines because
        // columnar static-call resolution is arity-based).
        // The N# struct parser wrapper rejects method names that collide with fields, duplicate instance method
        // names, and static/instance method name collisions before rows reach this pass. The builders + param types
        // are stored for call resolution; bodies are emitted in PASS 2.
        var structMethodJobs = new List<(ColumnarStructDef Struct, ColumnarFunctionInput Method, MethodBuilder Builder, Type ReturnType, Type BodyReturnType, Type? AsyncReturnType, Dictionary<string, int> Ordinals, Dictionary<string, Type> ParamTypes, bool IsStatic)>();
        for (var s = 0; s < structs.Count; s++)
        {
            var def = structRegistry[structs[s].Name];
            // Reference-type (record/class) instance methods are supported: the body emit (bare field -> `ldarg.0;
            // ldfld`) is identical to a value type's (ldfld works on both a managed pointer and an object ref), and
            // the instance CALL branches on IsReference (ldloc + callvirt for a ref receiver vs ldloca + call for a
            // value receiver) — see TryEmitInstanceCall. Slice-1a methods READ fields (no field WRITE in a body yet).
            foreach (var m in structs[s].Methods)
            {
                if (m.IsStatic)
                {
                    Type sReturn;
                    Type? sAsyncWrappedReturn = null;
                    if (m.IsAsync)
                    {
                        if (m.TypeParamNames.Length > 0)
                            return DeclineStatic("emit.declaration.method-return", "generic async static method is not modeled for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                        if (!TryComputeAsyncReturnShape(m.Name, m.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out sReturn, out sAsyncWrappedReturn))
                        {
                            return DeclineStatic("emit.declaration.method-return", "async static method return type '" + m.ReturnCanonical + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                        }
                    }
                    else if (m.ReturnCanonical == "void")
                        sReturn = typeof(void);
                    else if (!TryResolveType(m.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out sReturn) || !IsSupportedType(sReturn))
                    {
                        return DeclineStatic("emit.declaration.method-return", "static method return type '" + m.ReturnCanonical + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                    }
                    // No implicit `this`: param ordinals are NOT shifted (arg 0 is the first parameter).
                    var sParamTypes = new Type[m.ParamNames.Length];
                    var sOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                    var sParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                    for (var i = 0; i < m.ParamNames.Length; i++)
                    {
                        if (!TryResolveType(m.ParamCanonicals[i], enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedParameterType(pt))
                        {
                            return DeclineStatic("emit.declaration.method-param", "static method parameter type '" + m.ParamCanonicals[i] + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                        }
                        sParamTypes[i] = pt;
                        sOrdinals[m.ParamNames[i]] = i;
                        sParamTypeMap[m.ParamNames[i]] = pt;
                    }
                    if (!def.StaticMethods.TryGetValue(m.Name, out var overloads))
                    {
                        overloads = new List<(MethodBuilder, Type[], Type)>();
                        def.StaticMethods[m.Name] = overloads;
                    }
                    var staticMethodAttributes = MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig;
                    if (m.Name.StartsWith("op_", StringComparison.Ordinal))
                        staticMethodAttributes |= MethodAttributes.SpecialName;
                    var sSignatureReturn = sAsyncWrappedReturn ?? sReturn;
                    var smb = def.Builder.DefineMethod(m.Name, staticMethodAttributes, sSignatureReturn, sParamTypes);
                    if (!DefineMethodParameterMetadata(smb, sParamTypes, m.ParamNames, m.ParamModifierKinds, m.ParamDefaultKinds, m.ParamDefaultTexts, enumRegistry))
                        return false;
                    overloads.Add((smb, sParamTypes, sSignatureReturn));
                    structMethodJobs.Add((def, m, smb, sSignatureReturn, sReturn, sAsyncWrappedReturn, sOrdinals, sParamTypeMap, true));
                    continue;
                }
                Type mReturn;
                Type? mAsyncWrappedReturn = null;
                if (m.IsAsync)
                {
                    if (m.TypeParamNames.Length > 0)
                        return DeclineStatic("emit.declaration.method-return", "generic async method is not modeled for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                    if (!TryComputeAsyncReturnShape(m.Name, m.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out mReturn, out mAsyncWrappedReturn))
                    {
                        return DeclineStatic("emit.declaration.method-return", "async method return type '" + m.ReturnCanonical + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                    }
                }
                else if (m.ReturnCanonical == "void")
                    mReturn = typeof(void);
                else if (!TryResolveMemberType(m.ReturnCanonical, def, enumRegistry, structRegistry, unionRegistry, out mReturn) || !IsSupportedType(mReturn))
                {
                    return DeclineStatic("emit.declaration.method-return", "method return type '" + m.ReturnCanonical + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                }
                var mSignatureReturn = mAsyncWrappedReturn ?? mReturn;
                // Resolve param types; ordinals shift by +1 because arg 0 is the value-type `this`.
                var mParamTypes = new Type[m.ParamNames.Length];
                var mOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                var mParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                for (var i = 0; i < m.ParamNames.Length; i++)
                {
                    if (!TryResolveMemberType(m.ParamCanonicals[i], def, enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedParameterType(pt))
                    {
                        return DeclineStatic("emit.declaration.method-param", "method parameter type '" + m.ParamCanonicals[i] + "' could not be resolved for '" + structs[s].Name + "." + m.Name + "'", structs[s].Name);
                    }
                    mParamTypes[i] = pt;
                    mOrdinals[m.ParamNames[i]] = i + 1;
                    mParamTypeMap[m.ParamNames[i]] = pt;
                }
                // An IMPLEMENTING method (name + exact signature matches a member of any directly implemented
                // interface, or one of its inherited interfaces) gets Virtual|Final|NewSlot +
                // DefineMethodOverride for every matching slot — the legacy emitter's DeclareMethod rule
                // (implementing methods are FORCED virtual-final).
                var methodAttributes = MethodAttributes.Public | MethodAttributes.HideBySig;
                List<MethodBuilder>? overriddenInterfaceMethods = null;
                List<MethodInfo>? overriddenExternalInterfaceMethods = null;
                MethodInfo? overriddenObjectMethod = null;
                var seenOverriddenInterfaceMethods = new HashSet<MethodBuilder>();
                var seenOverriddenExternalInterfaceMethods = new HashSet<MethodInfo>();
                foreach (var implementedInterface in def.ImplementedInterfaces)
                {
                    if (TryFindInterfaceMethod(implementedInterface, m.Name, mSignatureReturn, mParamTypes, out var interfaceMember)
                        && seenOverriddenInterfaceMethods.Add(interfaceMember))
                    {
                        methodAttributes |= MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.NewSlot;
                        overriddenInterfaceMethods ??= new List<MethodBuilder>();
                        overriddenInterfaceMethods.Add(interfaceMember);
                    }
                }
                foreach (var externalInterface in def.ExternalInterfaces)
                {
                    foreach (var externalMethod in externalInterface.GetMethods())
                    {
                        if (ExternalInterfaceMethodMatches(externalMethod, m.Name, mSignatureReturn, mParamTypes)
                            && seenOverriddenExternalInterfaceMethods.Add(externalMethod))
                        {
                            methodAttributes |= MethodAttributes.Virtual | MethodAttributes.Final | MethodAttributes.NewSlot;
                            overriddenExternalInterfaceMethods ??= new List<MethodInfo>();
                            overriddenExternalInterfaceMethods.Add(externalMethod);
                        }
                    }
                }
                if ((m.ModifierFlags & NSharpModifierOverride) != 0)
                {
                    if (!TryFindObjectOverrideTarget(m.Name, mSignatureReturn, mParamTypes, out overriddenObjectMethod))
                        return false;
                    methodAttributes |= MethodAttributes.Virtual;
                    methodAttributes &= ~MethodAttributes.NewSlot;
                }
                var mb = def.Builder.DefineMethod(m.Name, methodAttributes, mSignatureReturn, mParamTypes);
                if (!DefineMethodParameterMetadata(mb, mParamTypes, m.ParamNames, m.ParamModifierKinds, m.ParamDefaultKinds, m.ParamDefaultTexts, enumRegistry))
                    return false;
                if (overriddenObjectMethod != null)
                    def.Builder.DefineMethodOverride(mb, overriddenObjectMethod);
                if (overriddenInterfaceMethods != null)
                {
                    foreach (var overriddenInterfaceMethod in overriddenInterfaceMethods)
                        def.Builder.DefineMethodOverride(mb, overriddenInterfaceMethod);
                }
                if (overriddenExternalInterfaceMethods != null)
                {
                    foreach (var overriddenExternalInterfaceMethod in overriddenExternalInterfaceMethods)
                        def.Builder.DefineMethodOverride(mb, overriddenExternalInterfaceMethod);
                }
                AddInstanceMethod(def, m.Name, (mb, mParamTypes, mSignatureReturn));
                structMethodJobs.Add((def, m, mb, mSignatureReturn, mReturn, mAsyncWrappedReturn, mOrdinals, mParamTypeMap, false));
            }
        }

        // COMPLETENESS: every member of every implemented interface must be matched by an
        // implementing method — the pipeline compiles missing members with ZERO diagnostics and the
        // assembly throws TypeLoadException at LOAD (known defect #26); columnar declines instead
        // (never emit an unloadable assembly).
        for (var s = 0; s < structs.Count; s++)
        {
            var def = structRegistry[structs[s].Name];
            var seenRequiredInterfaces = new HashSet<ColumnarStructDef>();
            if (def.ImplementedInterfaces.Count > 0)
            {
                foreach (var implementedInterface in def.ImplementedInterfaces)
                {
                    foreach (var requiredInterface in EnumerateInterfaceAndBases(implementedInterface))
                    {
                        if (!seenRequiredInterfaces.Add(requiredInterface))
                            continue;
                        foreach (var (memberName, member) in requiredInterface.Methods)
                        {
                            if (requiredInterface.DefaultInterfaceMethodNames.Contains(memberName))
                                continue;
                            if (!def.Methods.TryGetValue(memberName, out var impl)
                                || impl.ReturnType != member.ReturnType
                                || !ParamTypesMatch(member.ParamTypes, impl.ParamTypes))
                                return false;
                        }
                    }
                }
            }
            foreach (var externalInterface in def.ExternalInterfaces)
            {
                foreach (var externalMethod in externalInterface.GetMethods())
                {
                    if (!def.Methods.TryGetValue(externalMethod.Name, out var impl)
                        || !ExternalInterfaceMethodMatches(externalMethod, externalMethod.Name, impl.ReturnType, impl.ParamTypes))
                    {
                        return false;
                    }
                }
            }
        }

        // PASS 0b' (property accessors): declare each computed property as a `get_Name` instance
        // method (no params, returning the property type) and — when the property has a setter — a `set_Name` method
        // (one param "value": property type, returning void). The accessor bodies read/write fields exactly like a
        // method, so they emit via the same structMethodJobs path in PASS 2. The property is registered for
        // `receiver.Name` read (case 8 -> callvirt get_Name) + `receiver.Name = v` write (case 23 -> callvirt
        // set_Name). Same-declaration property source-name and synthesized get_Name/set_Name collisions are rejected
        // by the N# struct parser before rows reach this pass.
        for (var s = 0; s < structs.Count; s++)
        {
            if (structs[s].Properties.Count == 0)
                continue;
            var def = structRegistry[structs[s].Name];
            foreach (var prop in structs[s].Properties)
            {
                if (!TryResolveMemberType(prop.TypeCanonical, def, enumRegistry, structRegistry, unionRegistry, out var propType) || !IsSupportedType(propType))
                    return false;
                if (prop.IsStatic)
                {
                    // STATIC property: CLR-static accessors — get_Name takes no args at all; set_Name's `value`
                    // is arg 0 (no implicit `this`). The bodies are STATIC contexts (PASS 2 runs them with
                    // `_currentStruct` null), so a bare backing-field reference inside an accessor declines
                    // exactly where the N# pipeline reports NL103 — the backing access must be `TypeName.field`.
                    var staticGetter = def.Builder.DefineMethod("get_" + prop.Name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig | MethodAttributes.SpecialName, propType, Type.EmptyTypes);
                    structMethodJobs.Add((def, prop.Getter, staticGetter, propType, propType, null, new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), true));
                    var staticProperty = def.Builder.DefineProperty(prop.Name, PropertyAttributes.None, propType, Type.EmptyTypes);
                    staticProperty.SetGetMethod(staticGetter);
                    MethodBuilder? staticSetter = null;
                    if (prop.Setter != null)
                    {
                        staticSetter = def.Builder.DefineMethod("set_" + prop.Name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig | MethodAttributes.SpecialName, typeof(void), new[] { propType });
                        if (!DefineMethodParameterMetadata(staticSetter, [propType], ["value"], Array.Empty<int>(), Array.Empty<int>(), Array.Empty<string?>(), enumRegistry))
                            return false;
                        var staticSetOrdinals = new Dictionary<string, int>(StringComparer.Ordinal) { ["value"] = 0 };
                        var staticSetParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal) { ["value"] = propType };
                        structMethodJobs.Add((def, prop.Setter, staticSetter, typeof(void), typeof(void), null, staticSetOrdinals, staticSetParamTypes, true));
                        staticProperty.SetSetMethod(staticSetter);
                    }
                    def.StaticProperties[prop.Name] = (staticGetter, staticSetter, propType);
                    continue;
                }
                var getter = def.Builder.DefineMethod("get_" + prop.Name, MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName, propType, Type.EmptyTypes);
                structMethodJobs.Add((def, prop.Getter, getter, propType, propType, null, new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), false));
                var property = def.Builder.DefineProperty(prop.Name, PropertyAttributes.None, propType, Type.EmptyTypes);
                property.SetGetMethod(getter);
                MethodBuilder? setter = null;
                if (prop.Setter != null)
                {
                    setter = def.Builder.DefineMethod("set_" + prop.Name, MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName, typeof(void), new[] { propType });
                    if (!DefineMethodParameterMetadata(setter, [propType], ["value"], Array.Empty<int>(), Array.Empty<int>(), Array.Empty<string?>(), enumRegistry))
                        return false;
                    // The setter's `value` parameter is arg 1 (arg 0 = this); its body assigns fields via the
                    // reference-type field-write path. Emitted via structMethodJobs (a void method).
                    var setOrdinals = new Dictionary<string, int>(StringComparer.Ordinal) { ["value"] = 1 };
                    var setParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal) { ["value"] = propType };
                    structMethodJobs.Add((def, prop.Setter, setter, typeof(void), typeof(void), null, setOrdinals, setParamTypes, false));
                    property.SetSetMethod(setter);
                }
                def.Properties[prop.Name] = (getter, setter, propType);
            }
        }

        // PASS 0b'' (inherited-member shadowing): with every field/method/property declared, decline any member of
        // a derived type whose name SHADOWS an inherited member — EXCEPT a method over an inherited METHOD of the
        // SAME kind (instance over instance, static over static), which the N# pipeline accepts as hiding (the
        // nearest declaration wins; chain-walking resolution models exactly that. Field-over-anything,
        // method-over-field/property, property-over-anything, and MIXED static/instance method shadowing is NOT
        // modelled, so this backend declines rather than risk a resolution divergence.
        for (var s = 0; s < structs.Count; s++)
        {
            var def = structRegistry[structs[s].Name];
            if (def.BaseDef == null)
                continue;
            for (var chain = def.BaseDef; chain != null; chain = chain.BaseDef)
            {
                foreach (var fieldName in def.Fields.Keys)
                {
                    if (chain.Fields.ContainsKey(fieldName) || chain.StaticFields.ContainsKey(fieldName) || chain.Methods.ContainsKey(fieldName) || chain.StaticMethods.ContainsKey(fieldName) || chain.Properties.ContainsKey(fieldName) || chain.StaticProperties.ContainsKey(fieldName))
                        return false;
                }
                // A derived STATIC FIELD/PROPERTY shadowing ANY inherited member (incl. its own kind) is
                // unverified against the legacy emitter — decline every shape (unlike methods, no static-member hiding
                // is modelled for data members).
                foreach (var staticFieldName in def.StaticFields.Keys)
                {
                    if (chain.Fields.ContainsKey(staticFieldName) || chain.StaticFields.ContainsKey(staticFieldName) || chain.Methods.ContainsKey(staticFieldName) || chain.StaticMethods.ContainsKey(staticFieldName) || chain.Properties.ContainsKey(staticFieldName) || chain.StaticProperties.ContainsKey(staticFieldName))
                        return false;
                }
                foreach (var staticPropName in def.StaticProperties.Keys)
                {
                    if (chain.Fields.ContainsKey(staticPropName) || chain.StaticFields.ContainsKey(staticPropName) || chain.Methods.ContainsKey(staticPropName) || chain.StaticMethods.ContainsKey(staticPropName) || chain.Properties.ContainsKey(staticPropName) || chain.StaticProperties.ContainsKey(staticPropName))
                        return false;
                }
                foreach (var methodName in def.Methods.Keys)
                {
                    if (chain.Fields.ContainsKey(methodName) || chain.StaticFields.ContainsKey(methodName) || chain.StaticMethods.ContainsKey(methodName) || chain.Properties.ContainsKey(methodName) || chain.StaticProperties.ContainsKey(methodName))
                        return false;
                }
                foreach (var staticName in def.StaticMethods.Keys)
                {
                    if (chain.Fields.ContainsKey(staticName) || chain.StaticFields.ContainsKey(staticName) || chain.Methods.ContainsKey(staticName) || chain.Properties.ContainsKey(staticName) || chain.StaticProperties.ContainsKey(staticName))
                        return false;
                }
                foreach (var propName in def.Properties.Keys)
                {
                    if (chain.Fields.ContainsKey(propName) || chain.StaticFields.ContainsKey(propName) || chain.Methods.ContainsKey(propName) || chain.StaticMethods.ContainsKey(propName) || chain.Properties.ContainsKey(propName) || chain.StaticProperties.ContainsKey(propName))
                        return false;
                }
            }
        }

        // PASS 0c (constructors): declare each user constructor. A constructor is a nameless,
        // void-returning member whose body assigns fields; `this` is arg 0 so user param ordinals shift by +1. Slice
        // scope: one or more OVERLOADED constructors on a REFERENCE type (class/record), optionally with a `: this(...)`
        // (same-type) or `: base(...)` (declared base class) chaining initializer. The N# struct parser rejects exact
        // duplicate constructor signatures before rows reach this pass; overload resolution at construction is still
        // by PARAM COUNT (see case 15), so same-arity/different-type declarations decline only when an ambiguous
        // construction/chaining call site is emitted. Value-type constructors arrive only for the parser-accepted
        // positional shape: non-parameterless and without chain initializers. The ConstructorBuilder + its param types
        // are stored for positional-construction resolution; the body (+ chained call) is emitted (+ validated) in PASS 2.
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes)!;
        var structCtorJobs = new List<(ColumnarStructDef Struct, ColumnarConstructorInput Ctor, ConstructorBuilder Builder, Dictionary<string, int> Ordinals, Dictionary<string, Type> ParamTypes)>();
        var structInitializerJobs = new List<(ColumnarStructDef Struct, ColumnarConstructorInput Ctor, MethodBuilder Builder)>();
        for (var s = 0; s < structs.Count; s++)
        {
            if (structs[s].Constructors.Count == 0)
                continue;
            var def = structRegistry[structs[s].Name];
            foreach (var ctor in structs[s].Constructors)
            {
                if (IsZeroParamSynthesizedInitializer(ctor))
                {
                    if (!def.IsReference)
                        return DeclineStatic("emit.ctor.instance-initializer-value-type", "instance field initializer constructor is only modeled for reference types", def.Builder.Name);
                    var initializer = def.Builder.DefineMethod(
                        "<InitializeFields>$",
                        MethodAttributes.Private | MethodAttributes.HideBySig,
                        typeof(void),
                        Type.EmptyTypes);
                    def.InstanceInitializerMethod = initializer;
                    var ctorSource = program.GetSourceForFileId(ctor.Body.SourceFileId);
                    CollectTopLevelFieldInitializerAssignments(ctor.Body, ctorSource, def.InstanceInitializerFields);
                    structInitializerJobs.Add((def, ctor, initializer));
                    continue;
                }
                if (ctor.ChainInitKind == 2 && def.BaseDef == null)
                    return DeclineStatic("emit.ctor.base-chain-without-base", "constructor base initializer requires a modeled base class", def.Builder.Name + ".constructor");
                var cParamTypes = new Type[ctor.Body.ParamNames.Length];
                var cOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                var cParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                for (var i = 0; i < ctor.Body.ParamNames.Length; i++)
                {
                    if (!TryResolveMemberType(ctor.Body.ParamCanonicals[i], def, enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedParameterType(pt))
                        return DeclineStatic("emit.ctor.param-type", "constructor parameter type is not modeled", def.Builder.Name + ".constructor");
                    cParamTypes[i] = pt;
                    cOrdinals[ctor.Body.ParamNames[i]] = i + 1;
                    cParamTypeMap[ctor.Body.ParamNames[i]] = pt;
                }
                var cb = def.Builder.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, cParamTypes);
                if (!DefineConstructorParameterMetadata(cb, cParamTypes, ctor.Body.ParamNames, ctor.Body.ParamModifierKinds, ctor.ParamDefaultKinds, ctor.ParamDefaultTexts, enumRegistry))
                    return DeclineStatic("emit.ctor.param-metadata", "constructor parameter metadata could not be emitted", def.Builder.Name + ".constructor");
                def.Constructors.Add((cb, cParamTypes, ctor.ParamDefaultKinds, ctor.ParamDefaultTexts));
                structCtorJobs.Add((def, ctor, cb, cOrdinals, cParamTypeMap));
            }
        }

        // PASS 0d (default constructors): synthesize the public parameterless ctor for each reference type with NO
        // user constructors (the `newobj` target for object-init `new T { ... }`). Runs AFTER PASS 0c so a base's
        // USER parameterless ctor is visible, and depth-ASCENDING so a derived default ctor can chain to a base
        // default ctor that was synthesized one iteration earlier. A no-base class keeps today's
        // DefineDefaultConstructor (chains to object); a derived class needs a MANUAL ctor (DefineDefaultConstructor
        // requires a baked base) whose body chains to the base's parameterless ctor — and if the base has ONLY
        // parameterized ctors, the implicit chain is impossible and the N# pipeline rejects it ("must chain to a
        // base constructor") — decline.
        for (var depth = 0; depth < structs.Count; depth++)
        {
            for (var s = 0; s < structs.Count; s++)
            {
                if (structDepths[s] != depth)
                    continue;
                var st = structs[s];
                if (!st.IsReference || HasCallableConstructor(st))
                    continue;
                var def = structRegistry[st.Name];
                if (def.BaseDef == null && def.InstanceInitializerMethod == null)
                {
                    def.DefaultCtor = def.Builder.DefineDefaultConstructor(MethodAttributes.Public);
                    continue;
                }
                if (def.BaseDef != null && ResolveParameterlessCtor(def.BaseDef) == null)
                    return DeclineStatic("emit.ctor.default-base-chain", "default constructor requires a modeled base parameterless constructor", def.Builder.Name);
                var dcb = def.Builder.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Type.EmptyTypes);
                var dcil = dcb.GetILGenerator();
                EmitCtorBaseChain(dcil, def, objectCtor);
                EmitInstanceInitializerCall(dcil, def);
                dcil.Emit(OpCodes.Ret);
                def.DefaultCtor = dcb;
            }
        }

        // PASS 0e (record value members): synthesize Equals(object) / GetHashCode() / `<Clone>$` on each
        // NON-GENERIC records get a `<Clone>$` wrapper for `with`. Equals/GetHashCode are synthesized only
        // when every field type is a baked runtime type: EqualityComparer<T>.Default cannot be reflected over
        // emitted builders at emit time. Classes get NONE of these: a class `.Equals` is the pipeline's NL103
        // (probe-pinned) — parity by rejection. A USER method already named Equals/GetHashCode keeps ownership
        // (the pinned `hsh` behavior): that member's synthesis is skipped and resolution finds the user method
        // as before.
        foreach (var st in structs)
        {
            if (!st.IsRecord)
                continue;
            var def = structRegistry[st.Name];
            if (def.GenericParameters != null)
                continue;
            var fieldsBaked = true;
            foreach (var fieldName in def.FieldOrder)
            {
                // ContainsBuilderBoundType, not a Module test: a builder-bound COLLECTION field
                // (xs: List<Pt>) reports the open definition's CoreLib module, but
                // EqualityComparer<List<Pt>>.Default reflection in the synthesized members would
                // throw — such records skip synthesis exactly like directly builder-typed fields.
                if (ContainsBuilderBoundType(def.Fields[fieldName].FieldType))
                {
                    fieldsBaked = false;
                    break;
                }
            }
            if (fieldsBaked)
                SynthesizeRecordValueMembers(def);
            else
                SynthesizeRecordCloneMember(def);
        }

        // PASS 0 (unions): define every user union — an ABSTRACT base class plus one SEALED nested case class per
        // case. The base has a protected (Family) parameterless ctor
        // chaining to object::.ctor; each case has a public parameterless ctor chaining to the base ctor, plus a
        // public field per case field. These trivial ctor bodies are emitted INLINE here (no user code), exactly as
        // the de-risking spike proved. Case fields resolve via TryResolveType (enums/structs/earlier-unions in scope).
        // Defined after structs so a case field may be an enum or struct; nested case types are finalized BEFORE their
        // base (deepest-first — see the finalization block below).
        //
        // A GENERIC union (`union Opt<T>`) mirrors the legacy emitter's d1c41b6e machinery exactly (spike-proven): the base
        // declares the parameters; every nested case REDECLARES them by the same names (CLR metadata does not
        // inherit generic parameters into nested types) and SetParent()s to the base CLOSED over its own copies
        // (Some<T> : Opt<T>); the case ctor's base-ctor call is REBOUND onto that instantiation via
        // TypeBuilder.GetConstructor. Case fields may name the union's type parameters (`value: T` — the CASE's
        // redeclared parameter, positionally identical to the base's).
        for (var u = 0; u < unions.Count; u++)
        {
            var un = unions[u];

            // VALUE-STRUCT union (mirrors the previous parity baseline's DeclareValueStructUnion): a small, closed, payload-free,
            // non-generic union emits as a SEALED readonly tag struct (over System.ValueType) instead of a class
            // hierarchy, preserving the public allocation-free value-struct ABI (IsValueType==true). Shape: a private
            // `int _tag` (InitOnly) discriminator, a private `U(int)` ctor, a public `Tag` getter, and per case a
            // nested sealed-abstract marker type carrying a `public const int Tag` (reflection/tooling parity, never
            // instantiated) plus a public static `Create_<Case>()` factory (`new U(tag)` — no allocation).
            // Selected by the N# ColumnarUnionIsValueStructEmittable kernel.
            if (un.IsValueStruct)
            {
                if (!unionRegistry.TryGetValue(un.Name, out var valueStructDef) || valueStructDef.Base is not TypeBuilder structTb)
                    return DeclineStatic("emit.union.predeclare", "value-struct union base was not predeclared for '" + un.Name + "'", un.Name);
                var readOnlyCtor = typeof(System.Runtime.CompilerServices.IsReadOnlyAttribute).GetConstructor(Type.EmptyTypes);
                if (readOnlyCtor != null)
                    structTb.SetCustomAttribute(new CustomAttributeBuilder(readOnlyCtor, Array.Empty<object>()));

                var tagField = structTb.DefineField("_tag", typeof(int), FieldAttributes.Private | FieldAttributes.InitOnly);
                var tagCtor = structTb.DefineConstructor(
                    MethodAttributes.Private | MethodAttributes.HideBySig | MethodAttributes.SpecialName | MethodAttributes.RTSpecialName,
                    CallingConventions.Standard,
                    new[] { typeof(int) });
                var tcil = tagCtor.GetILGenerator();
                tcil.Emit(OpCodes.Ldarg_0);
                tcil.Emit(OpCodes.Ldarg_1);
                tcil.Emit(OpCodes.Stfld, tagField);
                tcil.Emit(OpCodes.Ret);

                var tagGetter = structTb.DefineMethod(
                    "get_Tag",
                    MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
                    typeof(int),
                    Type.EmptyTypes);
                var tgil = tagGetter.GetILGenerator();
                tgil.Emit(OpCodes.Ldarg_0);
                tgil.Emit(OpCodes.Ldfld, tagField);
                tgil.Emit(OpCodes.Ret);
                var tagProp = structTb.DefineProperty("Tag", PropertyAttributes.None, typeof(int), Type.EmptyTypes);
                tagProp.SetGetMethod(tagGetter);

                valueStructDef.TagGetter = tagGetter;

                for (var vc = 0; vc < un.CaseNames.Length; vc++)
                {
                    var vsCaseName = un.CaseNames[vc];
                    var markerTb = structTb.DefineNestedType(
                        vsCaseName,
                        TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.Abstract,
                        typeof(object));
                    var caseTagConst = markerTb.DefineField("Tag", typeof(int), FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal);
                    caseTagConst.SetConstant(vc);

                    var factory = structTb.DefineMethod(
                        "Create_" + vsCaseName,
                        MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig,
                        structTb,
                        Type.EmptyTypes);
                    var fil = factory.GetILGenerator();
                    fil.Emit(OpCodes.Ldc_I4, vc);
                    fil.Emit(OpCodes.Newobj, tagCtor);
                    fil.Emit(OpCodes.Ret);

                    var valueStructCaseDef = new ColumnarUnionCaseDef(
                        markerTb, tagCtor, Array.Empty<string>(), new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), structTb)
                    {
                        IsValueStruct = true,
                        ValueStructTag = vc,
                        ValueStructFactory = factory,
                        ValueStructTagGetter = tagGetter,
                    };
                    var vsQualified = un.Name + "." + vsCaseName;
                    valueStructDef.Cases[vsQualified] = valueStructCaseDef;
                    unionCaseRegistry[vsQualified] = valueStructCaseDef;
                    unionCaseBuilders.Add(markerTb);
                }
                continue;
            }

            var isGenericUnion = un.TypeParamNames.Length > 0;
            if (!unionRegistry.TryGetValue(un.Name, out var unionDef) || unionDef.Base is not TypeBuilder baseTb)
                return DeclineStatic("emit.union.predeclare", "union base was not predeclared for '" + un.Name + "'", un.Name);
            var baseCtor = baseTb.DefineConstructor(MethodAttributes.Family, CallingConventions.Standard, Type.EmptyTypes);
            var bcil = baseCtor.GetILGenerator();
            bcil.Emit(OpCodes.Ldarg_0);
            bcil.Emit(OpCodes.Call, typeof(object).GetConstructor(Type.EmptyTypes)!);
            bcil.Emit(OpCodes.Ret);

            for (var c = 0; c < un.CaseNames.Length; c++)
            {
                var caseName = un.CaseNames[c];
                TypeBuilder caseTb;
                Dictionary<string, Type>? caseParamMap = null;
                if (isGenericUnion)
                {
                    // Define with NO parent, redeclare the parameters, THEN parent to the closed base —
                    // the legacy emitter's DeclareUnion order (the parent type references the case's own parameters,
                    // which must exist first).
                    caseTb = baseTb.DefineNestedType(caseName, TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed);
                    var caseParams = caseTb.DefineGenericParameters(un.TypeParamNames);
                    caseTb.SetParent(baseTb.MakeGenericType(caseParams));
                    caseParamMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                    for (var g = 0; g < caseParams.Length; g++)
                        caseParamMap[un.TypeParamNames[g]] = caseParams[g];
                }
                else
                {
                    caseTb = baseTb.DefineNestedType(caseName, TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed, baseTb);
                }
                var caseFieldNames = un.CaseFieldNames[c];
                var caseFieldTypes = un.CaseFieldTypeCanonicals[c];
                var caseFields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
                for (var fi = 0; fi < caseFieldNames.Length; fi++)
                {
                    // The union's type parameters shadow same-named registered types within the case's
                    // field signatures (the legacy emitter scopes them the same way).
                    var fieldResolved = caseParamMap != null
                        ? TryResolveTypeWithTypeParams(caseFieldTypes[fi], caseParamMap, enumRegistry, structRegistry, unionRegistry, out var caseFieldType)
                        : TryResolveType(caseFieldTypes[fi], enumRegistry, structRegistry, unionRegistry, out caseFieldType);
                    if (!fieldResolved || !IsSupportedType(caseFieldType))
                        return false;
                    var cfb = caseTb.DefineField(caseFieldNames[fi], caseFieldType, FieldAttributes.Public);
                    caseFields[caseFieldNames[fi]] = cfb;
                }
                var caseCtor = caseTb.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Type.EmptyTypes);
                var ccil = caseCtor.GetILGenerator();
                ccil.Emit(OpCodes.Ldarg_0);
                if (isGenericUnion)
                    ccil.Emit(OpCodes.Call, TypeBuilder.GetConstructor(baseTb.MakeGenericType(caseTb.GetGenericArguments()), baseCtor));
                else
                    ccil.Emit(OpCodes.Call, baseCtor); // chain to the abstract base's ctor.
                ccil.Emit(OpCodes.Ret);

                var caseDef = new ColumnarUnionCaseDef(caseTb, caseCtor, caseFieldNames, caseFields, baseTb);
                var qualified = un.Name + "." + caseName;
                unionDef.Cases[qualified] = caseDef;
                unionCaseRegistry[qualified] = caseDef;
                unionCaseBuilders.Add(caseTb);
            }
        }

        var type = module.DefineType(typeName, TypeAttributes.Public | TypeAttributes.Class);

        // Pass 1: resolve every signature (int-only) and declare all methods up front. Build the sibling map
        // (name -> declared method + param count) so pass-2 bodies can `call` any function — including forward
        // references and self-recursion — resolving to a MethodBuilder whose body is not yet emitted.
        var methods = new MethodBuilder[funcs.Count];
        var ordinalsByFunc = new Dictionary<string, int>[funcs.Count];
        var paramTypesByFunc = new Dictionary<string, Type>[funcs.Count];
        var returnTypeByFunc = new Type[funcs.Count];
        // ASYNC: the per-function WRAPPED CLR return (the real method signature siblings call) —
        // null for non-async. returnTypeByFunc holds the wrapped type for async funcs (call sites
        // must see ValueTask<int>, never the inner int); the INNER type rides asyncInnerByFunc and
        // becomes the body emitter's _returnType so return-value checks work unchanged.
        var asyncWrappedByFunc = new Type?[funcs.Count];
        var asyncInnerByFunc = new Type[funcs.Count];
        var siblings = new Dictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)>(StringComparer.Ordinal);
        // Sibling RETURN tuple element names (a `(x: int, y: int)` return) — drives `t := mk()` / `mk().x`
        // name derivation; canonicals stay name-erased.
        var siblingReturnTupleNames = new Dictionary<string, string?[]>(StringComparer.Ordinal);
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            // A GENERIC function (`func Identity<T>(x: T): T`) declares a REAL CLR generic method — one
            // definition with open type parameters, instantiated per call site via MakeGenericMethod — exactly
            // the legacy emitter's primary strategy. DefineGenericParameters must run BEFORE the signature is set so the
            // param/return types can reference the GenericTypeParameterBuilders (the de-risking spike's order).
            var emptyTypeParams = System.Array.Empty<Type>();
            Type[] fnTypeParams = emptyTypeParams;
            var fnSpecialConstraints = System.Array.Empty<int>();
            var fnBaseConstraints = System.Array.Empty<Type?>();
            var typeParamMap = (Dictionary<string, Type>?)null;
            if (fn.TypeParamNames.Length > 0)
            {
                methods[f] = type.DefineMethod(fn.Name, MethodAttributes.Public | MethodAttributes.Static);
                var gpBuilders = methods[f].DefineGenericParameters(fn.TypeParamNames);
                typeParamMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                fnTypeParams = new Type[gpBuilders.Length];
                for (var g = 0; g < gpBuilders.Length; g++)
                {
                    typeParamMap[fn.TypeParamNames[g]] = gpBuilders[g];
                    fnTypeParams[g] = gpBuilders[g];
                }
                // Generic CONSTRAINTS (`where T: Base, new()` — D-17b): special flags map onto
                // GenericParameterAttributes and the single type constraint onto SetBaseTypeConstraint,
                // mirroring the legacy emitter's ApplyGenericConstraints (the `struct` flag implies the default-ctor
                // flag, exactly as the legacy emitter sets them; constraints persist and load — spike-proven). Applied
                // AFTER the full typeParamMap exists so a constraint can name another of the function's own
                // parameters (`where T: U`). Modeled base targets: another type parameter, a user REFERENCE
                // class/record TypeBuilder, or a baked BCL class. An INTERFACE constraint never resolves here
                // (columnar has no interface surface yet) and value types / arrays / enums / closed generics
                // as targets decline — under-accept is safe; silently dropping a constraint never is (NL208 is
                // call-site enforced by the pipeline).
                fnSpecialConstraints = new int[gpBuilders.Length];
                fnBaseConstraints = new Type?[gpBuilders.Length];
                for (var g = 0; g < gpBuilders.Length; g++)
                {
                    var special = fn.TypeParamSpecialConstraints.Length > g ? fn.TypeParamSpecialConstraints[g] : 0;
                    fnSpecialConstraints[g] = special;
                    if (special != 0)
                    {
                        var gpAttrs = GenericParameterAttributes.None;
                        if ((special & 1) != 0)
                            gpAttrs |= GenericParameterAttributes.ReferenceTypeConstraint;
                        if ((special & 2) != 0)
                            gpAttrs |= GenericParameterAttributes.NotNullableValueTypeConstraint
                                | GenericParameterAttributes.DefaultConstructorConstraint;
                        else if ((special & 4) != 0)
                            gpAttrs |= GenericParameterAttributes.DefaultConstructorConstraint;
                        gpBuilders[g].SetGenericParameterAttributes(gpAttrs);
                    }
                    var typeConstraints = fn.TypeParamTypeConstraints.Length > g
                        ? fn.TypeParamTypeConstraints[g]
                        : System.Array.Empty<string>();
                    if (typeConstraints.Length == 0)
                        continue;
                    // More than one type constraint is an interface list — unmodelled.
                    if (typeConstraints.Length > 1)
                        return false;
                    if (!TryResolveTypeWithTypeParams(typeConstraints[0], typeParamMap, enumRegistry, structRegistry, unionRegistry, out var constraintType))
                        return false;
                    if (!constraintType.IsGenericParameter)
                    {
                        if (constraintType is TypeBuilder)
                        {
                            // A user type is admissible only with REFERENCE layout (a value struct cannot be a
                            // base constraint); TypeBuilder.IsValueType answers structurally (base == ValueType).
                            if (constraintType.IsValueType)
                                return false;
                        }
                        else if (constraintType.Assembly is AssemblyBuilder
                            || constraintType.IsValueType || constraintType.IsSZArray || !constraintType.IsClass)
                        {
                            // Non-TypeBuilder emitted shapes (EnumBuilder, TypeBuilderInstantiation) and
                            // non-class runtime types are not modeled constraint targets.
                            return false;
                        }
                    }
                    gpBuilders[g].SetBaseTypeConstraint(constraintType);
                    fnBaseConstraints[g] = constraintType;
                }
                // CIRCULAR type-parameter constraints (`where T: T`, `where T: U where U: T`) emit metadata
                // the CLR REJECTS at load (TypeLoadException — probe-proven over-accept). Walk each param's
                // constraint chain; more steps than parameters means a cycle — decline.
                for (var g = 0; g < gpBuilders.Length; g++)
                {
                    var steps = 0;
                    var cursor = g;
                    while (fnBaseConstraints[cursor] is { IsGenericParameter: true } next)
                    {
                        if (++steps > gpBuilders.Length)
                            return false;
                        var nextPos = -1;
                        for (var q = 0; q < fnTypeParams.Length; q++)
                        {
                            if (ReferenceEquals(fnTypeParams[q], next)) { nextPos = q; break; }
                        }
                        if (nextPos < 0)
                            return false; // a parameter from some other scope — not resolvable here.
                        cursor = nextPos;
                    }
                }
            }
            else if (fn.TypeParamSpecialConstraints.Length > 0 || fn.TypeParamTypeConstraints.Length > 0)
            {
                // Constraint rows on a non-generic function are malformed — decline (defensive; the adapter
                // already refuses them).
                return false;
            }
            // The return type may be `void` (a procedure — its body need not always-return and `return` takes
            // no value); otherwise it must be a supported VALUE type. `void` is valid ONLY as a return type, so
            // it is handled here and NOT admitted by IsSupportedType (which gates params/locals/arrays/values).
            Type returnType;
            Type? asyncWrappedReturn = null;
            if (fn.IsAsync)
            {
                // ASYNC (the sync-lowering mirror): generic async declines; the declared return
                // resolves to the INNER type and the METHOD signature wraps it — ValueTask(/T) by
                // default, Task(/T) for `main` (the legacy emitter's entry-point rule), explicit task-like
                // annotations keep their declared family.
                if (fn.TypeParamNames.Length > 0)
                    return false;
                if (!TryComputeAsyncReturnShape(fn.Name, fn.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out returnType, out asyncWrappedReturn))
                    return DeclineStatic("emit.declaration.function-return", "async function return type '" + fn.ReturnCanonical + "' could not be resolved for '" + fn.Name + "'", fn.Name);
            }
            else if (fn.ReturnCanonical == "void")
                returnType = typeof(void);
            else if (typeParamMap != null)
            {
                if (!TryResolveTypeWithTypeParams(fn.ReturnCanonical, typeParamMap, enumRegistry, structRegistry, unionRegistry, out returnType)
                    || !(returnType.IsGenericParameter || (returnType.IsSZArray && returnType.GetElementType()!.IsGenericParameter) || IsSupportedType(returnType)))
                    return DeclineStatic("emit.declaration.function-return", "generic function return type '" + fn.ReturnCanonical + "' could not be resolved for '" + fn.Name + "'", fn.Name);
            }
            else if (!TryResolveType(fn.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out returnType) || !IsSupportedType(returnType))
                return DeclineStatic("emit.declaration.function-return", "function return type '" + fn.ReturnCanonical + "' could not be resolved for '" + fn.Name + "'", fn.Name);
            var paramTypes = new Type[fn.ParamNames.Length];
            var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
            var paramTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
            for (var i = 0; i < fn.ParamNames.Length; i++)
            {
                Type pt;
                if (typeParamMap != null)
                {
                    if (!TryResolveTypeWithTypeParams(fn.ParamCanonicals[i], typeParamMap, enumRegistry, structRegistry, unionRegistry, out pt)
                        || !(pt.IsGenericParameter || (pt.IsSZArray && pt.GetElementType()!.IsGenericParameter) || IsSupportedParameterType(pt)))
                        return DeclineStatic("emit.declaration.function-param", "generic function parameter type '" + fn.ParamCanonicals[i] + "' could not be resolved for '" + fn.Name + "'", fn.Name);
                }
                else if (!TryResolveType(fn.ParamCanonicals[i], enumRegistry, structRegistry, unionRegistry, out pt) || !IsSupportedParameterType(pt))
                    return DeclineStatic("emit.declaration.function-param", "function parameter type '" + fn.ParamCanonicals[i] + "' could not be resolved for '" + fn.Name + "'", fn.Name);
                paramTypes[i] = pt;
                ordinals[fn.ParamNames[i]] = i;
                paramTypeMap[fn.ParamNames[i]] = pt;
            }
            if (fn.TypeParamNames.Length > 0)
            {
                methods[f].SetReturnType(returnType);
                methods[f].SetParameters(paramTypes);
            }
            else
            {
                methods[f] = type.DefineMethod(
                    fn.Name, MethodAttributes.Public | MethodAttributes.Static, asyncWrappedReturn ?? returnType, paramTypes);
            }
            if (!DefineMethodParameterMetadata(methods[f], paramTypes, fn.ParamNames, fn.ParamModifierKinds, fn.ParamDefaultKinds, fn.ParamDefaultTexts, enumRegistry))
                return false;
            ordinalsByFunc[f] = ordinals;
            paramTypesByFunc[f] = paramTypeMap;
            returnTypeByFunc[f] = asyncWrappedReturn ?? returnType; // call sites see the WRAPPED type.
            asyncWrappedByFunc[f] = asyncWrappedReturn;
            asyncInnerByFunc[f] = returnType;
            if (fn.ReturnTupleElementNames != null)
                siblingReturnTupleNames[fn.Name] = fn.ReturnTupleElementNames;
            siblings[fn.Name] = (methods[f], paramTypes, asyncWrappedReturn ?? returnType, fnTypeParams, fnSpecialConstraints, fnBaseConstraints);
        }

        // Pass 2: emit each body into its declared method's IL stream. The Program TypeBuilder + a shared
        // lambda counter ride along so bodies can synthesize `<Lambda>_{n}` static methods (L1b — interleaved
        // DefineMethod and forward ldftn both bake at Save, spike-proven).
        var lambdaCounter = new int[1];
        var displayClasses = new List<TypeBuilder>();
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            var il = methods[f].GetILGenerator();
            // LOCAL FUNCTIONS (L4-i): declare each root-block local function as a `<parent>g__{n}` static
            // BEFORE the parent body emits (forward calls bake at Save); bodies emit after the parent's.
            // Product parser routing only materializes non-generic, non-nested local functions here; resolvable
            // signatures only, duplicate names decline. A local function SHADOWS a same-named sibling at call
            // sites (probe-pinned), so the map is its own resolution tier.
            Dictionary<string, (MethodBuilder Method, Type[] ParamTypes, Type ReturnType)>? localFuncs = null;
            Dictionary<int, string>? declaredLocalFuncNodes = null;
            if (fn.LocalFunctions != null)
            {
                localFuncs = new Dictionary<string, (MethodBuilder, Type[], Type)>(StringComparer.Ordinal);
                declaredLocalFuncNodes = new Dictionary<int, string>();
                foreach (var localFunction in fn.LocalFunctions)
                {
                    var nodeIndex = localFunction.NodeIndex;
                    var localFn = localFunction.Function;
                    Type localReturn;
                    if (localFn.ReturnCanonical == "void")
                        localReturn = typeof(void);
                    else if (!TryResolveType(localFn.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out localReturn) || !IsSupportedType(localReturn))
                        return false;
                    var localParams = new Type[localFn.ParamNames.Length];
                    for (var lp = 0; lp < localParams.Length; lp++)
                    {
                        if (!TryResolveType(localFn.ParamCanonicals[lp], enumRegistry, structRegistry, unionRegistry, out localParams[lp]) || !IsSupportedType(localParams[lp]))
                            return false;
                    }
                    var localMethod = type.DefineMethod(
                        "<" + fn.Name + ">g__" + lambdaCounter[0]++,
                        MethodAttributes.Private | MethodAttributes.Static, localReturn, localParams);
                    if (!DefineMethodParameterMetadata(localMethod, localParams, localFn.ParamNames, localFn.ParamModifierKinds, localFn.ParamDefaultKinds, localFn.ParamDefaultTexts, enumRegistry))
                        return false;
                    localFuncs[localFn.Name] = (localMethod, localParams, localReturn);
                    declaredLocalFuncNodes[nodeIndex] = localFn.Name;
                }
            }
            Dictionary<string, string?[]>? fnParamTupleNames = null;
            if (fn.ParamTupleElementNames != null)
            {
                for (var pn = 0; pn < fn.ParamNames.Length && pn < fn.ParamTupleElementNames.Length; pn++)
                {
                    if (fn.ParamTupleElementNames[pn] is { } paramElementNames)
                        (fnParamTupleNames ??= new Dictionary<string, string?[]>(StringComparer.Ordinal))[fn.ParamNames[pn]] = paramElementNames;
                }
            }
            // ASYNC bodies check return values against the INNER type; the method's CLR signature
            // (and every sibling call site) sees the WRAPPED type.
            var bodyReturnType = asyncWrappedByFunc[f] != null ? asyncInnerByFunc[f] : returnTypeByFunc[f];
            var functionSource = program.GetSourceForFileId(fn.SourceFileId);
            var emitter = new ColumnarIlEmitter(
                fn.BodyNodes, functionSource, ordinalsByFunc[f], paramTypesByFunc[f], bodyReturnType, il, siblings,
                enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, currentStruct: null,
                programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                localFuncs: localFuncs, declaredLocalFuncNodes: declaredLocalFuncNodes,
                siblingReturnTupleNames: siblingReturnTupleNames, paramTupleNames: fnParamTupleNames,
                asyncReturnType: asyncWrappedByFunc[f],
                asyncBareReturnDeclines: fn.ReturnCanonical is "Task" or "ValueTask",
                referenceAssemblyPaths: referenceAssemblyPaths);
            ColumnarDeclineTrace.SetSourceFileId(fn.SourceFileId);
            try
            {
                if (!emitter.EmitBody(fn.BodyRoot, bodyReturnType == typeof(void)))
                    return DeclineStatic("emit.body", "function body emission declined", fn.Name);
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
            if (fn.LocalFunctions != null)
            {
                // NL316 across the local-function boundary: the pipeline rejects a local-func PARAM or
                // body binding that shadows a parent binding. Local bodies emit AFTER the parent's, so no
                // live snapshot exists — use the parent's STRUCTURAL binding superset (params + every name
                // any parent statement binds; extra declines are safe under-acceptance).
                var parentBindings = new HashSet<string>(ordinalsByFunc[f].Keys, StringComparer.Ordinal);
                CollectBindingNames(fn.BodyNodes, functionSource, fn.BodyRoot, parentBindings);
                var visiblePrefix = new List<string>();
                foreach (var localFunction in fn.LocalFunctions)
                {
                    var localFn = localFunction.Function;
                    visiblePrefix.Add(localFn.Name);
                    var target = localFuncs![localFn.Name];
                    var localOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                    var localParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal);
                    for (var lp = 0; lp < localFn.ParamNames.Length; lp++)
                    {
                        localOrdinals[localFn.ParamNames[lp]] = lp;
                        if (parentBindings.Contains(localFn.ParamNames[lp]))
                            return false; // a local-func param shadowing a parent binding — NL316.
                        localParamTypes[localFn.ParamNames[lp]] = target.ParamTypes[lp];
                    }
                    var localIl = target.Method.GetILGenerator();
                    // The local body shares the SAME localFuncs map (self/mutual recursion + the parent's
                    // other local functions); outer locals/params are NOT in scope — captures decline.
                    var localFunctionSource = program.GetSourceForFileId(localFn.SourceFileId);
                    var localEmitter = new ColumnarIlEmitter(
                        localFn.BodyNodes, localFunctionSource, localOrdinals, localParamTypes, target.ReturnType, localIl,
                        siblings, enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, currentStruct: null,
                        programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                        localFuncs: localFuncs, visibleLocalFuncs: visiblePrefix,
                        enclosingBindingNames: parentBindings,
                        referenceAssemblyPaths: referenceAssemblyPaths);
                    ColumnarDeclineTrace.SetSourceFileId(localFn.SourceFileId);
                    try
                    {
                        if (!localEmitter.EmitBody(localFn.BodyRoot, target.ReturnType == typeof(void)))
                            return DeclineStatic("emit.body", "local function body emission declined", fn.Name + "." + localFn.Name);
                    }
                    finally
                    {
                        ColumnarDeclineTrace.ClearSourceFileId();
                    }
                }
            }
        }

        // Emit default interface method bodies (before finalizing interface types). The body runs with
        // `_currentStruct` set to the interface def, so bare calls to other interface members lower through the
        // same implicit-this call path as class/struct instance methods.
        foreach (var job in interfaceMethodJobs)
        {
            var mil = job.Builder.GetILGenerator();
            var methodSource = program.GetSourceForFileId(job.Method.SourceFileId);
            var emitter = new ColumnarIlEmitter(
                job.Method.BodyNodes, methodSource, job.Ordinals, job.ParamTypes, job.ReturnType, mil, siblings,
                enumRegistry, structRegistry, unionRegistry, unionCaseRegistry,
                currentStruct: job.Interface, enclosingType: job.Interface,
                programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                referenceAssemblyPaths: referenceAssemblyPaths);
            ColumnarDeclineTrace.SetSourceFileId(job.Method.SourceFileId);
            try
            {
                if (!emitter.EmitBody(job.Method.BodyRoot, job.ReturnType == typeof(void)))
                    return DeclineStatic("emit.body", "default interface method body emission declined", job.Interface.Builder.Name + "." + job.Method.Name);
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
        }

        // Emit synthesized instance-field initializer methods before constructors that call them. The N# constructor
        // parser builds these bodies as assignment statements (`field = initializer`) using the same columnar node
        // shape as constructor bodies, so C# only wires the private method and invocation order.
        foreach (var job in structInitializerJobs)
        {
            var mil = job.Builder.GetILGenerator();
            var ctorSource = program.GetSourceForFileId(job.Ctor.Body.SourceFileId);
            var emitter = new ColumnarIlEmitter(
                job.Ctor.Body.BodyNodes, ctorSource,
                new Dictionary<string, int>(StringComparer.Ordinal),
                new Dictionary<string, Type>(StringComparer.Ordinal),
                typeof(void), mil, siblings,
                enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, job.Struct,
                isSynthesizedInitializerBody: true,
                programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                referenceAssemblyPaths: referenceAssemblyPaths);
            ColumnarDeclineTrace.SetSourceFileId(job.Ctor.Body.SourceFileId);
            try
            {
                if (!emitter.EmitBody(job.Ctor.Body.BodyRoot, isVoid: true))
                    return DeclineStatic("emit.body", "instance field initializer emission declined", job.Struct.Builder.Name + ".<InitializeFields>$");
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
        }

        // Emit struct method bodies (before finalizing the struct types). An INSTANCE body runs with
        // `_currentStruct` set so bare field names resolve to `ldarg.0; ldfld` (`this` is arg 0). A STATIC body
        // runs with `_currentStruct` NULL — there is no instance, so every implicit-`this` path (bare fields, bare
        // instance-method calls) structurally cannot fire and such programs decline (the N# pipeline rejects them)
        // — while `_enclosingType` still anchors bare STATIC-method resolution on the type's own chain. Methods may
        // `call` top-level funcs (siblings); a forward `call` to any MethodBuilder resolves at Save.
        foreach (var job in structMethodJobs)
        {
            var mil = job.Builder.GetILGenerator();
            var methodSource = program.GetSourceForFileId(job.Method.SourceFileId);
            var emitter = new ColumnarIlEmitter(
                job.Method.BodyNodes, methodSource, job.Ordinals, job.ParamTypes, job.BodyReturnType, mil, siblings,
                enumRegistry, structRegistry, unionRegistry, unionCaseRegistry,
                currentStruct: job.IsStatic ? null : job.Struct, enclosingType: job.Struct,
                programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                asyncReturnType: job.AsyncReturnType,
                asyncBareReturnDeclines: job.Method.ReturnCanonical is "Task" or "ValueTask",
                referenceAssemblyPaths: referenceAssemblyPaths);
            // A property SETTER body is void (it assigns a field and falls through); a method/getter is a value
            // function (always-returns). EmitBody handles both — pass isVoid by the job's declared return type.
            ColumnarDeclineTrace.SetSourceFileId(job.Method.SourceFileId);
            try
            {
                if (!emitter.EmitBody(job.Method.BodyRoot, job.BodyReturnType == typeof(void)))
                    return DeclineStatic("emit.body", "member body emission declined", job.Struct.Builder.Name + "." + job.Method.Name);
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
        }

        // Emit user-constructor bodies. Each chains to the base `object` ctor first (`ldarg.0; call object::.ctor()`),
        // then emits the ctor body (field assignments via the reference-type field-write path), with `_currentStruct`
        // set and the ctor's param ordinals (arg 0 = `this`). The body is VOID (no return value), so EmitBody(isVoid:
        // true) appends a trailing `ret` where control falls through.
        foreach (var job in structCtorJobs)
        {
            var cil = job.Builder.GetILGenerator();
            var ctorSource = program.GetSourceForFileId(job.Ctor.Body.SourceFileId);
            var emitter = new ColumnarIlEmitter(
                job.Ctor.Body.BodyNodes, ctorSource, job.Ordinals, job.ParamTypes, typeof(void), cil, siblings,
                enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, job.Struct,
                isConstructorBody: true, isSynthesizedInitializerBody: job.Ctor.IsSynthesizedInitializer,
                programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                referenceAssemblyPaths: referenceAssemblyPaths);
            ColumnarDeclineTrace.SetSourceFileId(job.Ctor.Body.SourceFileId);
            try
            {
                if (job.Ctor.ChainInitKind != 0)
                {
                    // A `: this(...)` (kind 1) or `: base(...)` (kind 2) CHAINING constructor delegates field assignment
                    // to the chained ctor, so the NL304 all-fields-assigned check does NOT apply (empirically pinned for
                    // BOTH kinds against the N# pipeline) — but `return` is still forbidden (NL103). Emit the chained
                    // call (resolved by chain-arg count among the same type's / the base type's ctors) in place of the
                    // base object ctor, then the body.
                    if (emitter.ContainsReturnStatement(job.Ctor.Body.BodyRoot))
                        return false;
                    if (!emitter.EmitChainedConstructorCall(job.Ctor, job.Builder))
                        return false;
                    if (job.Ctor.ChainInitKind == 2)
                        EmitInstanceInitializerCall(cil, job.Struct);
                }
                else if (job.Struct.IsReference)
                {
                    // A non-chaining ctor must (1) contain no `return` (NL103) and (2) assign every OWN field (NL304 —
                    // inherited fields are the base ctor's responsibility). Synthesized initializer constructors
                    // produced from class/record declarations may leave fields at their CLR defaults; explicit
                    // constructors keep the all-fields-assigned check. Validate BEFORE emitting — declining here discards
                    // the whole assembly (→ N# backend path). Then chain implicitly: to the declared base's parameterless
                    // ctor when the type has one (decline when the base offers only parameterized ctors — ECMA-335
                    // requires chaining to the DIRECT base, and the N# pipeline rejects the implicit chain), else to the
                    // `object` ctor.
                    if (job.Ctor.IsSynthesizedInitializer
                        ? emitter.ContainsReturnStatement(job.Ctor.Body.BodyRoot)
                        : !emitter.IsValidReferenceCtorBody(job.Ctor.Body.BodyRoot))
                        return false;
                    if (job.Struct.BaseDef != null && ResolveParameterlessCtor(job.Struct.BaseDef) == null)
                        return false; // base has only parameterized ctors — `: base(...)` is required.
                    EmitCtorBaseChain(cil, job.Struct, objectCtor);
                    EmitInstanceInitializerCall(cil, job.Struct);
                }
                else
                {
                    // VALUE-TYPE ctor: no base chain (value types don't chain), and NO all-fields-assigned
                    // validation — the legacy emitter ACCEPTS partial assignment in struct ctors (probed: unassigned
                    // fields keep the zero-initialized value). Only `return` is forbidden (NL103).
                    if (emitter.ContainsReturnStatement(job.Ctor.Body.BodyRoot))
                        return false;
                }
                // A synthesized NEWTYPE ctor has an empty body; it assigns its single parameter
                // to the Value field directly (the legacy synthetic record's primary-ctor contract).
                if (job.Struct.IsNewtype && job.Struct.Fields.TryGetValue("Value", out var newtypeValueField))
                {
                    cil.Emit(OpCodes.Ldarg_0);
                    cil.Emit(OpCodes.Ldarg_1);
                    cil.Emit(OpCodes.Stfld, newtypeValueField);
                }
                if (!emitter.EmitBody(job.Ctor.Body.BodyRoot, isVoid: true))
                    return DeclineStatic("emit.body", "constructor body emission declined", job.Struct.Builder.Name + ".constructor");
            }
            finally
            {
                ColumnarDeclineTrace.ClearSourceFileId();
            }
        }

        // Finalize the struct types before the Program type (the spike's ordering). Struct fields are already
        // defined, so CreateType bakes the type metadata; methods that reference un-finalized builders resolve to
        // the finalized types at Save. Enums were baked in pass 0 because no later user type can affect them.
        // Interfaces bake BEFORE their implementers, and base interfaces bake before derived interfaces.
        for (var depth = 0; depth <= interfaces.Count; depth++)
        {
            for (var i = 0; i < interfaceDefsInOrder.Count; i++)
            {
                if (interfaceDepths[i] == depth)
                    interfaceDefsInOrder[i].Builder.CreateType();
            }
        }
        // Struct/class types bake BASE-BEFORE-DERIVED (depth ascending): CreateType on a derived TypeBuilder
        // requires its parent to be created first. Depth 0 (no base) covers every value-type struct and standalone
        // class, so the no-inheritance ordering is unchanged.
        for (var depth = 0; depth < structs.Count; depth++)
        {
            for (var s = 0; s < structs.Count; s++)
            {
                if (structDepths[s] == depth)
                    structBuilders[s].CreateType();
            }
        }
        // Union types: a NESTED case must be finalized BEFORE its enclosing base (deepest-first),
        // so create every case, then every base.
        foreach (var caseTb in unionCaseBuilders)
            caseTb.CreateType();
        foreach (var baseTb in unionBaseBuilders)
            baseTb.CreateType();

        // Display classes (capturing lambdas) bake BEFORE the Program type — the legacy emitter's
        // closure-types-first order; their instance methods are referenced by ldftn from Program bodies.
        // Executable finalization — the legacy emitter's SaveAssembly rule: an exe assembly must be
        // serialized through ManagedPEBuilder with the entry-point token set (PersistedAssemblyBuilder.Save
        // never writes one). An async `main` cannot BE the CLR entry point (its CLR signature returns
        // Task/Task<T>), so a sync __NSharpEntryPoint wrapper calls it and blocks on
        // GetAwaiter().GetResult() — the legacy EnsureRuntimeEntryPointWrapper verbatim. The wrapper is
        // declared BEFORE type.CreateType() so it bakes with the Program type.
        // TEST DECLARATIONS — the legacy emitter's NSharpTests contract: one public module-level
        // type holding every test as a public instance void method carrying
        // Trait("NSharpDescription", <description>) + Fact, both resolved from the restored xunit
        // at emit time (ResolveTestFrameworkType). Bodies emit through the standard body emitter
        // with the sibling top-level functions in scope; `nlc test` (XunitFrontController or the
        // attribute-free NSharpTests reflection fallback) and `dotnet test` both discover them.
        if (program.Tests is { Count: > 0 } testInputs)
        {
            Type factAttributeType;
            Type traitAttributeType;
            try
            {
                factAttributeType = ResolveTestFrameworkType("Xunit.FactAttribute", referenceAssemblyPaths, "xunit.core", "xunit.v3.core");
                traitAttributeType = ResolveTestFrameworkType("Xunit.TraitAttribute", referenceAssemblyPaths, "xunit.core", "xunit.v3.core");
            }
            catch (InvalidOperationException)
            {
                return DeclineStatic("emit.tests.framework", "xunit attribute types were not resolvable in this emit host", "NSharpTests");
            }

            var traitCtor = traitAttributeType.GetConstructor(new[] { typeof(string), typeof(string) });
            var factCtor = factAttributeType.GetConstructor(Type.EmptyTypes);
            if (traitCtor == null || factCtor == null)
                return DeclineStatic("emit.tests.framework", "xunit attribute constructors were not resolvable", "NSharpTests");

            var testType = module.DefineType("NSharpTests", TypeAttributes.Public | TypeAttributes.Class);
            var usedTestMethodNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (var testInput in testInputs)
            {
                var methodName = TestDescriptionToMethodName(testInput.Description);
                if (!usedTestMethodNames.Add(methodName))
                {
                    var suffix = 2;
                    while (!usedTestMethodNames.Add(methodName + "_" + suffix))
                        suffix++;
                    methodName = methodName + "_" + suffix;
                }

                var testMethod = testType.DefineMethod(methodName, MethodAttributes.Public | MethodAttributes.HideBySig, typeof(void), Type.EmptyTypes);
                testMethod.SetCustomAttribute(new CustomAttributeBuilder(traitCtor, new object[] { "NSharpDescription", testInput.Description }));
                testMethod.SetCustomAttribute(new CustomAttributeBuilder(factCtor, Array.Empty<object>()));

                var testBody = testInput.Body;
                var testIl = testMethod.GetILGenerator();
                var testSource = program.GetSourceForFileId(testBody.SourceFileId);
                var testEmitter = new ColumnarIlEmitter(
                    testBody.BodyNodes, testSource,
                    new Dictionary<string, int>(StringComparer.Ordinal),
                    new Dictionary<string, Type>(StringComparer.Ordinal),
                    typeof(void), testIl, siblings,
                    enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, currentStruct: null,
                    programType: type, lambdaCounter: lambdaCounter, displayClasses: displayClasses,
                    siblingReturnTupleNames: siblingReturnTupleNames,
                    referenceAssemblyPaths: referenceAssemblyPaths);
                ColumnarDeclineTrace.SetSourceFileId(testBody.SourceFileId);
                try
                {
                    if (!testEmitter.EmitBody(testBody.BodyRoot, true))
                        return DeclineStatic("emit.tests.body", "test body emission declined", "test " + testInput.Description);
                }
                finally
                {
                    ColumnarDeclineTrace.ClearSourceFileId();
                }
            }

            testType.CreateType();
        }

        MethodBuilder? entryPointMethod = null;
        if (isExecutable)
        {
            var mainIndex = -1;
            for (var f = 0; f < funcs.Count && mainIndex < 0; f++)
                if (string.Equals(funcs[f].Name, "main", StringComparison.Ordinal))
                    mainIndex = f;
            for (var f = 0; f < funcs.Count && mainIndex < 0; f++)
                if (string.Equals(funcs[f].Name, "Main", StringComparison.Ordinal))
                    mainIndex = f;

            if (mainIndex >= 0)
            {
                entryPointMethod = methods[mainIndex];
                var wrappedReturn = asyncWrappedByFunc[mainIndex];
                if (wrappedReturn != null)
                {
                    if (paramTypesByFunc[mainIndex].Count != 0)
                        return false; // an async main with parameters has no modeled wrapper — decline.

                    var innerReturn = asyncInnerByFunc[mainIndex];
                    var wrapperReturn = innerReturn == typeof(int) || innerReturn == typeof(uint)
                        ? innerReturn
                        : typeof(void);
                    var wrapper = type.DefineMethod(
                        "__NSharpEntryPoint",
                        MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig,
                        wrapperReturn,
                        Type.EmptyTypes);
                    var wrapperIl = wrapper.GetILGenerator();
                    wrapperIl.Emit(OpCodes.Call, entryPointMethod);
                    var getAwaiter = wrappedReturn.GetMethod("GetAwaiter", Type.EmptyTypes)!;
                    wrapperIl.Emit(getAwaiter.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, getAwaiter);
                    var awaiterType = getAwaiter.ReturnType;
                    var awaiterLocal = wrapperIl.DeclareLocal(awaiterType);
                    wrapperIl.Emit(OpCodes.Stloc, awaiterLocal);
                    wrapperIl.Emit(OpCodes.Ldloca_S, awaiterLocal);
                    wrapperIl.Emit(OpCodes.Call, awaiterType.GetMethod("GetResult", Type.EmptyTypes)!);
                    if (wrapperReturn == typeof(void) && innerReturn != typeof(void))
                        wrapperIl.Emit(OpCodes.Pop);
                    wrapperIl.Emit(OpCodes.Ret);
                    entryPointMethod = wrapper;
                }
            }
            else
            {
                // A static Main declared inside a user class (`class Program { static func Main() ... }`).
                foreach (var def in structRegistry.Values)
                {
                    if (def.StaticMethods.TryGetValue("Main", out var mains)
                        && mains.Count == 1
                        && mains[0].ParamTypes.Length == 0)
                    {
                        entryPointMethod = mains[0].Builder;
                        break;
                    }
                }
            }

            if (entryPointMethod == null)
                return false; // an exe without a resolvable entry point would save as a non-runnable
                              // assembly — decline so the pipeline's diagnostics own the failure.
        }

        foreach (var displayTb in displayClasses)
            displayTb.CreateType();
        type.CreateType();
        using var stream = new MemoryStream();
        if (entryPointMethod != null)
        {
            var metadataBuilder = builder.GenerateMetadata(out var ilStream, out var mappedFieldData);
            var peBuilder = new System.Reflection.PortableExecutable.ManagedPEBuilder(
                header: System.Reflection.PortableExecutable.PEHeaderBuilder.CreateExecutableHeader(),
                metadataRootBuilder: new System.Reflection.Metadata.Ecma335.MetadataRootBuilder(metadataBuilder),
                ilStream: ilStream,
                mappedFieldData: mappedFieldData,
                entryPoint: System.Reflection.Metadata.Ecma335.MetadataTokens.MethodDefinitionHandle(entryPointMethod.MetadataToken));
            var peBlob = new System.Reflection.Metadata.BlobBuilder();
            peBuilder.Serialize(peBlob);
            peBlob.WriteContentTo(stream);
        }
        else
        {
            builder.Save(stream);
        }

        assembly = stream.ToArray();
        return true;
    }

    // Emit a function body. A VALUE function (non-void) must always-return on every path (NL305) — else the IL
    // would fall off the end with no `ret`; decline to the analyzer-validated product path. A VOID function (procedure) need not
    // always-return: emit the body, then a trailing `ret` IFF control can fall through to the method end (when
    // the body already always-returns via value-less `return`s, no trailing `ret` is emitted, so there is no
    // unreachable code).
    private bool EmitBody(int bodyRoot, bool isVoid)
    {
        // The body root anchors the never-mutated capture scan (L3a): a lambda may capture an enclosing
        // local/param only when NOTHING in this whole body writes it. Null inside a lambda's own
        // sub-emitter (EmitExpression is entered directly), so nested capture chains decline.
        _bodyRoot = bodyRoot;
        // L3b pre-scan: names captured by some lambda AND bare-assigned somewhere become LIFTED candidates
        // (declared as shared StrongBox<T>); lifted PARAMS box-init here so every later read/write — in
        // the body or any closure — goes through the one box.
        ComputeLiftedCandidates(bodyRoot);
        if (_liftedCandidates != null)
        {
            foreach (var liftedParam in _liftedCandidates)
            {
                if (!_paramOrdinals.TryGetValue(liftedParam, out var liftedOrdinal))
                    continue;
                var liftedParamType = _paramTypes[liftedParam];
                if (!IsLiftableValueType(liftedParamType))
                    continue; // stays a plain param; a later capture of it declines (written, unlifted).
                var boxType = typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(liftedParamType);
                var boxLocal = _il.DeclareLocal(boxType);
                EmitLoadArgument(liftedOrdinal);
                _il.Emit(OpCodes.Newobj, boxType.GetConstructor(new[] { liftedParamType })!);
                _il.Emit(OpCodes.Stloc, boxLocal);
                _liftedLocals[liftedParam] = (boxLocal, liftedParamType);
            }
        }
        if (_asyncReturnType != null)
        {
            // ASYNC FAULT GUARD (the legacy emitter's BeginAsyncFaultGuard/EndAsyncFaultGuard): the whole
            // body is ONE protected region — every return WRAPS its value and leaves to the shared
            // tail; a UNIT body falling off the end wraps the completed task; the catch converts
            // the thrown exception into a faulted task (Task.FromException, + the ValueTask ctor).
            // Value bodies must still always-return (the analyzer's rule — unit-task asyncs are
            // exempt). Nested try/lock statements decline via _inProtectedRegion (one region per
            // body — the existing rung scope), so the guard's region nesting stays flat.
            if (_asyncResultType != null && !AlwaysReturns(bodyRoot))
                return false;
            _protectedResult = _il.DeclareLocal(_asyncReturnType);
            _protectedDone = _il.DefineLabel();
            _protectedDoneCreated = true;
            _inProtectedRegion = true;
            _il.BeginExceptionBlock();
            var asyncFallsThrough = _asyncResultType == null && !AlwaysReturns(bodyRoot);
            if (!EmitStatement(bodyRoot))
                return false;
            if (asyncFallsThrough)
            {
                EmitWrappedAsyncCompletedReturn(hasValueOnStack: false);
                _il.Emit(OpCodes.Stloc, _protectedResult);
                _il.Emit(OpCodes.Leave, _protectedDone);
            }
            _il.BeginCatchBlock(typeof(Exception));
            EmitFaultedAsyncReturnMirror();
            _il.Emit(OpCodes.Stloc, _protectedResult);
            _il.Emit(OpCodes.Leave, _protectedDone);
            _il.EndExceptionBlock();
            _inProtectedRegion = false;
            _il.MarkLabel(_protectedDone);
            _il.Emit(OpCodes.Ldloc, _protectedResult);
            _il.Emit(OpCodes.Ret);
            return true;
        }
        if (!isVoid)
        {
            if (!AlwaysReturns(bodyRoot))
            {
                return false;
            }
            if (!EmitStatement(bodyRoot))
                return false;
            EmitProtectedReturnTail(isVoid: false);
            return true;
        }
        var fallsThrough = !AlwaysReturns(bodyRoot);
        if (!EmitStatement(bodyRoot))
            return false;
        if (fallsThrough)
            _il.Emit(OpCodes.Ret);
        EmitProtectedReturnTail(isVoid: true);
        return true;
    }

    // ASYNC mirror of the legacy emitter's EmitWrapCurrentAsyncReturn: wraps the (already-emitted) return
    // value — or, with no value, the completed unit task — into the wrapped CLR return type.
    // Unit + ValueTask -> default(ValueTask); unit + Task -> Task.CompletedTask;
    // T + ValueTask<T> -> newobj ValueTask<T>(T); T + Task<T> -> Task.FromResult<T>(T).
    private void EmitWrappedAsyncCompletedReturn(bool hasValueOnStack)
    {
        if (_asyncResultType == null)
        {
            if (_asyncReturnsValueTask)
            {
                var unitTemp = _il.DeclareLocal(typeof(System.Threading.Tasks.ValueTask));
                _il.Emit(OpCodes.Ldloca, unitTemp);
                _il.Emit(OpCodes.Initobj, typeof(System.Threading.Tasks.ValueTask));
                _il.Emit(OpCodes.Ldloc, unitTemp);
            }
            else
            {
                _il.Emit(OpCodes.Call,
                    typeof(System.Threading.Tasks.Task).GetProperty(nameof(System.Threading.Tasks.Task.CompletedTask))!.GetGetMethod()!);
            }
            return;
        }
        if (!hasValueOnStack)
            throw new InvalidOperationException("async value return requires the value on the stack");
        if (_asyncReturnsValueTask)
        {
            _il.Emit(OpCodes.Newobj, _asyncReturnType!.GetConstructor(new[] { _asyncResultType })!);
        }
        else
        {
            _il.Emit(OpCodes.Call, FindTaskStaticMethod("FromResult", generic: true).MakeGenericMethod(_asyncResultType!));
        }
    }

    private static MethodInfo FindTaskStaticMethod(string methodName, bool generic)
    {
        foreach (var m in typeof(System.Threading.Tasks.Task).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name == methodName && m.IsGenericMethodDefinition == generic && m.GetParameters().Length == 1)
                return m;
        }
        throw new InvalidOperationException($"Could not resolve Task.{methodName}");
    }

    // ASYNC mirror of the legacy emitter's EmitFaultedAsyncReturn: with an Exception on the stack, leaves a
    // FAULTED task of the wrapped return type carrying it (Task.FromException(<T>), then the
    // ValueTask(<T>) Task-wrapping ctor when the family is ValueTask).
    private void EmitFaultedAsyncReturnMirror()
    {
        if (_asyncResultType == null)
        {
            _il.Emit(OpCodes.Call, FindTaskStaticMethod("FromException", generic: false));
            if (_asyncReturnsValueTask)
                _il.Emit(OpCodes.Newobj, typeof(System.Threading.Tasks.ValueTask).GetConstructor(new[] { typeof(System.Threading.Tasks.Task) })!);
            return;
        }
        _il.Emit(OpCodes.Call, FindTaskStaticMethod("FromException", generic: true).MakeGenericMethod(_asyncResultType));
        if (_asyncReturnsValueTask)
        {
            var taskOfT = typeof(System.Threading.Tasks.Task<>).MakeGenericType(_asyncResultType);
            _il.Emit(OpCodes.Newobj, _asyncReturnType!.GetConstructor(new[] { taskOfT })!);
        }
    }

    // ASYNC mirror of the legacy emitter's EmitAwaiterGetResult — the BLOCKING await: ValueTask(/T) spills
    // and converts via AsTask() first; Task(/T) goes callvirt GetAwaiter() then the STRUCT awaiter
    // spills for `call GetResult()`. Only the four BCL task shapes are modelled — any other
    // awaitable declines (the legacy emitter's general GetAwaiter pattern is a later rung).
    private bool TryEmitBlockingAwait(Type awaitableType, out Type resultType)
    {
        resultType = null!;
        if (awaitableType == typeof(System.Threading.Tasks.ValueTask))
        {
            var vtLocal = _il.DeclareLocal(awaitableType);
            _il.Emit(OpCodes.Stloc, vtLocal);
            _il.Emit(OpCodes.Ldloca, vtLocal);
            _il.Emit(OpCodes.Call, awaitableType.GetMethod(nameof(System.Threading.Tasks.ValueTask.AsTask), Type.EmptyTypes)!);
            return TryEmitBlockingAwait(typeof(System.Threading.Tasks.Task), out resultType);
        }
        if (awaitableType.IsGenericType && !awaitableType.IsGenericTypeDefinition
            && awaitableType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.ValueTask<>))
        {
            var vtLocal = _il.DeclareLocal(awaitableType);
            _il.Emit(OpCodes.Stloc, vtLocal);
            _il.Emit(OpCodes.Ldloca, vtLocal);
            _il.Emit(OpCodes.Call,
                ResolveClosedGenericMethod(awaitableType, typeof(System.Threading.Tasks.ValueTask<>).GetMethod("AsTask", Type.EmptyTypes)!));
            return TryEmitBlockingAwait(
                typeof(System.Threading.Tasks.Task<>).MakeGenericType(awaitableType.GetGenericArguments()[0]), out resultType);
        }
        if (awaitableType == typeof(System.Threading.Tasks.Task))
        {
            _il.Emit(OpCodes.Callvirt, awaitableType.GetMethod("GetAwaiter", Type.EmptyTypes)!);
            var awaiterType = typeof(System.Runtime.CompilerServices.TaskAwaiter);
            var awaiterLocal = _il.DeclareLocal(awaiterType);
            _il.Emit(OpCodes.Stloc, awaiterLocal);
            _il.Emit(OpCodes.Ldloca, awaiterLocal);
            _il.Emit(OpCodes.Call, awaiterType.GetMethod("GetResult", Type.EmptyTypes)!);
            resultType = typeof(void);
            return true;
        }
        if (awaitableType.IsGenericType && !awaitableType.IsGenericTypeDefinition
            && awaitableType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<>))
        {
            var taskResult = awaitableType.GetGenericArguments()[0];
            if (!IsSupportedType(taskResult))
                return false;
            _il.Emit(OpCodes.Callvirt,
                ResolveClosedGenericMethod(awaitableType, typeof(System.Threading.Tasks.Task<>).GetMethod("GetAwaiter", Type.EmptyTypes)!));
            var awaiterType = typeof(System.Runtime.CompilerServices.TaskAwaiter<>).MakeGenericType(taskResult);
            var awaiterLocal = _il.DeclareLocal(awaiterType);
            _il.Emit(OpCodes.Stloc, awaiterLocal);
            _il.Emit(OpCodes.Ldloca, awaiterLocal);
            _il.Emit(OpCodes.Call,
                ResolveClosedGenericMethod(awaiterType, typeof(System.Runtime.CompilerServices.TaskAwaiter<>).GetMethod("GetResult", Type.EmptyTypes)!));
            resultType = taskResult;
            return true;
        }
        return false;
    }

    // The single body-level tail every protected-region `return` leaves to (E2): `done: [ldloc result;] ret`.
    // Emitted whenever ANY try exists — not only when a protected return targeted it: Reflection.Emit's
    // implicit `leave`s (BeginCatchBlock/EndExceptionBlock) make the post-block position reachable in the
    // JIT's view even when every region exits via `throw`, so an all-throws try/catch without this tail
    // falls off a reachable method end (InvalidProgramException — probe-found, both pipelines).
    private void EmitProtectedReturnTail(bool isVoid)
    {
        if (!_protectedDoneCreated)
            return;
        _il.MarkLabel(_protectedDone);
        if (!isVoid)
            _il.Emit(OpCodes.Ldloc, _protectedResult!);
        _il.Emit(OpCodes.Ret);
    }

    private bool EmitStatement(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 25: // Block — emit each statement in order.
            {
                // Block scoping: a `:=` local declared in this block leaves scope when the block ends, so a
                // later reference (e.g. a loop-body local read after the loop) correctly resolves to nothing
                // and declines, rather than reading a method-level slot that may be unassigned (invalid IL).
                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                var outerLifted = new HashSet<string>(_liftedLocals.Keys, StringComparer.Ordinal);
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                {
                    var child = Child(idx, n);
                    if (!EmitStatement(child))
                        return Decline(
                            "emit.statement.block-child",
                            "block child " + n + " (node kind " + _nodes.Kind(child).ToString() + ") could not be emitted",
                            child);
                    // A statement that unconditionally transfers control — always-returns, or a direct
                    // `break`/`continue` — must be the LAST in its block; anything after it is unreachable (an
                    // NL312 diagnostic). Decline rather than emit code after the transfer `ret`/`br`, keeping the
                    // analyzer-validated product path authoritative. (A break/continue nested inside an `if` is
                    // conditional, so only a DIRECT break/continue child counts here.)
                    var transfers = AlwaysReturns(child) || _nodes.Kind(child) == 21 || _nodes.Kind(child) == 22;
                    if (transfers && n != _nodes.ChildCount(idx) - 1)
                    {
                        return Decline("emit.statement.unreachable-after-transfer", "block contains a statement after an unconditional transfer", child);
                    }
                }

                var blockLocals = new List<string>();
                foreach (var name in _locals.Keys)
                {
                    if (!outerLocals.Contains(name))
                        blockLocals.Add(name);
                }

                foreach (var name in blockLocals)
                    _locals.Remove(name);
                var blockLifted = new List<string>();
                foreach (var name in _liftedLocals.Keys)
                {
                    if (!outerLifted.Contains(name))
                        blockLifted.Add(name);
                }
                foreach (var name in blockLifted)
                    _liftedLocals.Remove(name);
                return true;
            }

            case 49: // TryStatement [tryBlock, catch1..catchN] — each catch a kind-50 CatchClause (value
            {        // span = exception TYPE name, -1 = bare; children [nameIdent?, block]). The clauses
                     // emit as sequential BeginCatchBlock(type) regions, giving first-match-in-declaration-
                     // order natively (probe-pinned, incl. base-before-derived). BeginCatchBlock implicitly
                     // leaves the prior region and PUSHES the exception typed as the catch type — stloc the
                     // bound variable (a fresh block-scoped local; shadowing declines = the pipeline's
                     // NL316) or Pop when unbound. Unknown/non-whitelist exception types decline (the
                     // pipeline silently resolves unknown names to a CATCH-ALL — known defect #16 — and
                     // accepts non-exception types as dead clauses — #17; declining inherits neither).
                     // Returns inside any region go through the body's leave tail. An optional trailing
                     // kind-25 child is the FINALLY block (E4); break/continue inside the regions emit
                     // `leave` when they cross the boundary (the case 21/22 rules), so try-inside-loop
                     // emits. NESTED try declines (one level this rung).
                if (_nodes.ChildCount(idx) < 2 || _inProtectedRegion)
                    return false;
                if (_protectedResult == null && _returnType != typeof(void))
                    _protectedResult = _il.DeclareLocal(_returnType);
                if (!_protectedDoneCreated)
                {
                    _protectedDone = _il.DefineLabel();
                    _protectedDoneCreated = true;
                }
                _inProtectedRegion = true;
                _il.BeginExceptionBlock();
                if (!EmitStatement(Child(idx, 0)))
                    return false;
                for (var c = 1; c < _nodes.ChildCount(idx); c++)
                {
                    var clause = Child(idx, c);
                    if (_nodes.Kind(clause) == 25)
                    {
                        // The FINALLY block (E4) — always the LAST child. BeginFinallyBlock implicitly
                        // ends the prior region; EndExceptionBlock implicitly ends the handler.
                        if (c != _nodes.ChildCount(idx) - 1)
                            return false;
                        _il.BeginFinallyBlock();
                        _inFinallyRegion = true;
                        var finallyOk = EmitStatement(clause);
                        _inFinallyRegion = false;
                        if (!finallyOk)
                            return false;
                        break;
                    }
                    if (_nodes.Kind(clause) != 50)
                        return false;
                    Type catchType;
                    if (_nodes.ValueStart(clause) >= 0)
                    {
                        if (!TryResolveBclExceptionType(Text(clause), out catchType))
                            return false;
                    }
                    else
                    {
                        catchType = typeof(Exception); // bare catch — the pipeline's exact default.
                    }
                    _il.BeginCatchBlock(catchType);
                    var hasBinding = _nodes.ChildCount(clause) == 2;
                    string? catchVarName = null;
                    if (hasBinding)
                    {
                        catchVarName = Text(Child(clause, 0));
                        // Shadowing an existing binding — incl. one in an ENCLOSING function when this is a
                        // nested body — is the pipeline's NL316 error; `_` is the discard spelling. Both
                        // decline rather than model unverified semantics.
                        if (catchVarName == "_" || IsVisibleBindingName(catchVarName))
                            return false;
                        var catchLocal = _il.DeclareLocal(catchType);
                        _il.Emit(OpCodes.Stloc, catchLocal);
                        _locals[catchVarName] = catchLocal;
                    }
                    else
                    {
                        _il.Emit(OpCodes.Pop); // unbound catch discards the exception object.
                    }
                    if (!EmitStatement(Child(clause, _nodes.ChildCount(clause) - 1)))
                        return false;
                    if (catchVarName != null)
                        _locals.Remove(catchVarName); // the binding is scoped to its own clause.
                }
                _il.EndExceptionBlock();
                _inProtectedRegion = false;
                return true;
            }

            case 51: // LockStatement [lockee, body] — `Monitor.Enter(obj); try { body } finally
            {        // { Monitor.Exit(obj) }`, the legacy emitter's EmitLock verbatim. The lockee must be a
                     // REFERENCE value: the analyzer rejects value-type lockees with NL320 (legacy emitter
                     // defect #21 fixed front-door; the CS0185 analog), so none can reach emit on the
                     // production path — the decline below stays as this emitter's contract guard.
                     // One protected region per body (nested forms decline), exactly as for try.
                if (_nodes.ChildCount(idx) != 2 || _inProtectedRegion)
                    return false;
                if (!EmitExpression(Child(idx, 0), out var lockeeType))
                    return false;
                if (lockeeType.IsValueType || lockeeType == typeof(void))
                    return false; // value lockees are analyzer-rejected (NL320) — decline as a guard.
                if (_protectedResult == null && _returnType != typeof(void))
                    _protectedResult = _il.DeclareLocal(_returnType);
                if (!_protectedDoneCreated)
                {
                    _protectedDone = _il.DefineLabel();
                    _protectedDoneCreated = true;
                }
                var lockLocal = _il.DeclareLocal(typeof(object));
                _il.Emit(OpCodes.Stloc, lockLocal);
                _il.Emit(OpCodes.Ldloc, lockLocal);
                _il.Emit(OpCodes.Call, typeof(System.Threading.Monitor).GetMethod(nameof(System.Threading.Monitor.Enter), new[] { typeof(object) })!);
                _inProtectedRegion = true;
                _il.BeginExceptionBlock();
                if (!EmitStatement(Child(idx, 1)))
                    return false;
                _il.BeginFinallyBlock();
                _inFinallyRegion = true;
                _il.Emit(OpCodes.Ldloc, lockLocal);
                _il.Emit(OpCodes.Call, typeof(System.Threading.Monitor).GetMethod(nameof(System.Threading.Monitor.Exit), new[] { typeof(object) })!);
                _inFinallyRegion = false;
                _il.EndExceptionBlock();
                _inProtectedRegion = false;
                return true;
            }

            case 48: // Throw [exception] — `throw <expr>`: emit the exception REFERENCE and `throw`. The
            {        // expression must produce a System.Exception-derived reference (the whitelisted BCL
                     // exception constructions; anything else declines — the analyzer's type rule stays
                     // with the N# backend path).
                if (_nodes.ChildCount(idx) != 1 || !EmitExpression(Child(idx, 0), out var thrownType))
                    return false;
                if (!typeof(Exception).IsAssignableFrom(thrownType))
                    return false;
                _il.Emit(OpCodes.Throw);
                return true;
            }

            case 56: // Print [value] — `print <expr>`: evaluate the value, box a value type, and call
            {        // Console.WriteLine(object) — the legacy emitter's single canonical lowering
                     // (EmitPrint parity: no per-type overload selection).
                if (_nodes.ChildCount(idx) != 1)
                    return Decline("emit.print.shape", "print statement has an unsupported shape", idx);
                if (!EmitExpression(Child(idx, 0), out var printedType))
                    return Decline("emit.print.expression", "print expression could not be emitted", Child(idx, 0));
                if (printedType == typeof(void) || printedType.IsByRef || printedType.IsPointer)
                    return Decline("emit.print.type", "print expression type is not printable", Child(idx, 0));
                if (printedType.IsValueType)
                    _il.Emit(OpCodes.Box, printedType);
                _il.Emit(OpCodes.Call, typeof(Console).GetMethod(nameof(Console.WriteLine), new[] { typeof(object) })!);
                return true;
            }

            case 20: // Return [value?] — in a VOID function a value-less `return` emits a bare `ret`; in a VALUE
            {        // function a value is REQUIRED (a value-less `ret` with an empty stack is invalid IL) and its
                     // type must match the declared return type (TypesEquivalent — two closed instantiations of one
                     // user generic are distinct TypeBuilderInstantiation objects). A value-bearing `return` in a
                     // void function, or a value-less one in a value function, declines (mismatched arity). A
                     // generic-union case construction with NO type args ADOPTS the return type's arguments here
                     // (`return new Opt.None` on `(): Opt<int>` — one of the two pipeline-accepted adoption sites).
                if (_inFinallyRegion)
                    return false; // a return cannot leave a finally handler (illegal IL) — analyzer-
                                  // rejected with NL319 (defect #20 fixed); decline as a guard.
                if (_returnType == typeof(void))
                {
                    if (_nodes.ChildCount(idx) != 0)
                        return false;
                    if (_inProtectedRegion)
                    {
                        if (_asyncReturnType != null)
                        {
                            // a bare `return` in a UNIT async body — legal ONLY when the unit-ness
                            // is IMPLICIT (no annotation): the pipeline's NL305 unit-task exemption
                            // covers fall-through bodies, and a bare return under an EXPLICIT
                            // Task/ValueTask annotation is rejected as a non-value return path
                            // (review-probe-pinned boundary). Wrap and route through the async tail.
                            if (_asyncBareReturnDeclines)
                                return false;
                            EmitWrappedAsyncCompletedReturn(hasValueOnStack: false);
                            _il.Emit(OpCodes.Stloc, _protectedResult!);
                        }
                        _il.Emit(OpCodes.Leave, _protectedDone);
                        return true;
                    }
                    _il.Emit(OpCodes.Ret);
                    return true;
                }
                if (_nodes.ChildCount(idx) == 0)
                    return false;
                var retNode = Child(idx, 0);
                Type retType;
                if (IsAdoptableUnionConstruction(retNode, _returnType))
                {
                    if (!EmitAdoptedUnionConstruction(retNode, _returnType, out retType))
                        return false;
                }
                else if (TryEmitIntLiteralAsType(retNode, _returnType, out retType))
                {
                    // `return 50` on a byte/uint/long/ulong function — the literal adopts the return type.
                }
                else if (TryEmitArrayLiteralAsType(retNode, _returnType, out retType))
                {
                    // target-typed array literal return.
                }
                else if (TryEmitNullLiteralAsType(retNode, _returnType, out retType))
                {
                    // `return null` on a reference-typed function.
                }
                else if (IsSupportedNullable(_returnType))
                {
                    // `return 5` / `return null` / `return n` on an int? function — the lifted
                    // conversion OWNS the emission; failure declines the whole program.
                    if (!TryEmitValueAsNullable(retNode, _returnType, out retType))
                    {
                        return false;
                    }
                }
                else if (!EmitExpression(retNode, out retType))
                {
                    return Decline("emit.return.expression", "return expression could not be emitted", retNode);
                }
                if (!TypesEquivalent(retType, _returnType) && !TryEmitImplicitWidening(retType, _returnType) && !TryEmitInterfaceUpcast(retType, _returnType) && !TryEmitReferenceConversion(retType, _returnType) && !TryEmitObjectConversion(retType, _returnType) && !TryEmitUserDefinedConversion(retType, _returnType, allowExplicit: false))
                {
                    return Decline("emit.return.type-mismatch", "return expression type '" + retType.FullName + "' does not match declared return type '" + _returnType.FullName + "'", retNode);
                }
                if (_inProtectedRegion)
                {
                    // ASYNC: the INNER value wraps into the completed task before the store (the
                    // legacy emitter's EmitWrapCurrentAsyncReturn before its structured return).
                    if (_asyncReturnType != null)
                        EmitWrappedAsyncCompletedReturn(hasValueOnStack: true);
                    // E2: `ret` is invalid inside try/catch — store + leave to the body tail (spike rule 1).
                    _il.Emit(OpCodes.Stloc, _protectedResult!);
                    _il.Emit(OpCodes.Leave, _protectedDone);
                    return true;
                }
                _il.Emit(OpCodes.Ret);
                return true;
            }

            case 24: // VariableDeclaration (`:=`): emit the initializer, declare a local of the initializer's
            {        // type (inferred), store into it.
                var name = Text(idx);
                // Decline a local that shadows a parameter or redeclares a local — incl. a binding in an
                // ENCLOSING function when this is a nested (lambda/local-func) body: N# treats shadowing as
                // a diagnostic (NL316; a same-`:=` redeclaration as an error), which the spike does not
                // model — declining keeps the analyzer-validated product path authoritative.
                if (IsVisibleBindingName(name))
                    return Decline("emit.local.redeclaration-or-shadowing", "local declaration shadows or redeclares a visible binding '" + name + "'", idx);
                if (_nodes.ChildCount(idx) == 0)
                    return Decline("emit.local.missing-initializer", "local declaration has no modeled initializer", idx);
                // A ZERO-PARAM lambda initializer (`zero := () => 99` — L1c): the only `:=` lambda shape with
                // no inference gap (param-ful `:=` lambdas are pipeline-rejected with NL203). The return type
                // is INFERRED from the body, so the synthesized method's signature is set AFTER the body emits
                // (spike-proven order); the local's type is Func<bodyType> (or Action for a void body).
                if (_nodes.Kind(Child(idx, 0)) == 39)
                {
                    if (!TryEmitInferredZeroParamLambda(Child(idx, 0), out var lambdaType))
                        return Decline("emit.local.lambda-inference", "local lambda initializer could not be inferred", Child(idx, 0));
                    var lambdaLocal = _il.DeclareLocal(lambdaType);
                    _il.Emit(OpCodes.Stloc, lambdaLocal);
                    _locals[name] = lambdaLocal;
                    return true;
                }
                // A local of an open generic-parameter type (`y := x` inside a generic function, x: T) is legal —
                // DeclareLocal over a GenericTypeParameterBuilder works (spike-proven) and loads/stores/returns
                // of T flow by reference equality. T[] locals likewise.
                if (!EmitExpression(Child(idx, 0), out var initType))
                {
                    return Decline("emit.local.initializer", "local initializer expression emission declined for '" + name + "'", Child(idx, 0));
                }
                if (!(initType.IsGenericParameter || (initType.IsSZArray && initType.GetElementType()!.IsGenericParameter) || IsSupportedType(initType)))
                {
                    return Decline("emit.local.unsupported-type", "local initializer type is not supported for '" + name + "': " + initType.FullName, idx);
                }
                // L3b: a lifted candidate (captured by some lambda AND bare-assigned) declares as a shared
                // StrongBox<T> — the init value is on the stack; wrap it. A non-liftable type stays plain
                // (a later capture of it declines — written, unlifted).
                if (_liftedCandidates != null && _liftedCandidates.Contains(name) && IsLiftableValueType(initType))
                {
                    var liftBoxType = typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(initType);
                    var liftBox = _il.DeclareLocal(liftBoxType);
                    _il.Emit(OpCodes.Newobj, liftBoxType.GetConstructor(new[] { initType })!);
                    _il.Emit(OpCodes.Stloc, liftBox);
                    _liftedLocals[name] = (liftBox, initType);
                    return true;
                }
                var local = _il.DeclareLocal(initType);
                _il.Emit(OpCodes.Stloc, local);
                _locals[name] = local;
                // Tuple ELEMENT NAMES derived from the initializer (a named literal, an identifier copy,
                // or a sibling call with a named return type) carry onto the local for member access.
                if (TupleNamesOfExpressionNode(Child(idx, 0)) is { } inferredTupleNames)
                    _tupleNamesByVariable[name] = inferredTupleNames;
                return true;
            }

            case 40: // TypedLocalDeclaration (`[let] name: Type = init` — L2): the DECLARED type's source
            {        // span rides in the value slot (whitespace-stripped to the canonical — canonicals never
                     // contain spaces); children = [name Identifier, init]. A kind-39 lambda initializer is
                     // typed CONTEXTUALLY from the declared delegate type (the L1b machinery — this is what
                     // unlocks `let f: Func<int, int> = x => x + 1`); any other initializer must emit exactly
                     // the declared type (a mismatch is pipeline-rejected NL202 — decline). `let` locals are
                     // MUTABLE in N# (probe-pinned: `let n: int = 5  n = 6` runs), so a plain local suffices.
                if (_nodes.ChildCount(idx) != 2 || _nodes.Kind(Child(idx, 0)) != 6)
                    return Decline("emit.typed-local.shape", "typed local declaration has an unsupported shape", idx);
                var declaredName = Text(Child(idx, 0));
                if (IsVisibleBindingName(declaredName))
                    return Decline("emit.typed-local.redeclaration-or-shadowing", "typed local declaration shadows or redeclares a visible binding '" + declaredName + "'", idx);
                var typeCanonical = ColumnarTypeCanonicalizer.RemoveWhitespace(Text(idx));
                // A NAMED tuple annotation (`let t: (x: int, y: int) = ...`) strips to the positional
                // canonical for resolution; the names are recorded for member access below. (The BARE
                // form with a tuple type is a production-grammar parse error — the kernel refuses it.)
                var tupleStrip = ColumnarTypeCanonicalizer.StripTupleElementNames(typeCanonical);
                typeCanonical = tupleStrip.Canonical;
                var declaredTupleNames = tupleStrip.Names;
                if (!TryResolveType(typeCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var declaredType)
                    || !IsSupportedType(declaredType))
                    return Decline("emit.typed-local.unsupported-type", "typed local declaration type is not supported for '" + declaredName + "': " + typeCanonical, idx);
                var declaredInit = Child(idx, 1);
                if (_nodes.Kind(declaredInit) == 39)
                {
                    if (!TryEmitLambdaLiteral(declaredInit, declaredType))
                        return false;
                }
                // A generic-union case construction with NO type args ADOPTS the declared type's arguments
                // (`n: Opt<int> = new Opt.Some { value: 5 }` — the second pipeline-accepted adoption site).
                else if (IsAdoptableUnionConstruction(declaredInit, declaredType))
                {
                    if (!EmitAdoptedUnionConstruction(declaredInit, declaredType, out var adoptedType)
                        || !TypesEquivalent(adoptedType, declaredType))
                        return Decline("emit.typed-local.union-adoption", "typed local union construction could not adopt declared type for '" + declaredName + "'", declaredInit);
                }
                else if (TryEmitIntLiteralAsType(declaredInit, declaredType, out _))
                {
                    // `b: byte = 200` / `u: ulong = 10` — the in-range literal adopts the declared type.
                }
                else if (TryEmitArrayLiteralAsType(declaredInit, declaredType, out _))
                {
                    // `values: T[] = [a, b]` — the target array type owns the element type.
                }
                else if (TryEmitNullLiteralAsType(declaredInit, declaredType, out _))
                {
                    // `s: string? = null` (a `?`-annotated reference resolves to its element type).
                }
                else if (IsSupportedNullable(declaredType))
                {
                    // `n: int? = 5` / `= null` / `= v` — the lifted conversion owns the emission.
                    if (!TryEmitValueAsNullable(declaredInit, declaredType, out _))
                        return Decline("emit.typed-local.nullable-conversion", "typed local nullable initializer could not convert for '" + declaredName + "'", declaredInit);
                }
                else
                {
                    if (!EmitExpression(declaredInit, out var declaredInitType))
                        return Decline("emit.typed-local.initializer", "typed local initializer expression emission declined for '" + declaredName + "'", declaredInit);
                    if (!TypesEquivalent(declaredInitType, declaredType) && !TryEmitImplicitWidening(declaredInitType, declaredType) && !TryEmitInterfaceUpcast(declaredInitType, declaredType) && !TryEmitReferenceConversion(declaredInitType, declaredType) && !TryEmitObjectConversion(declaredInitType, declaredType) && !TryEmitUserDefinedConversion(declaredInitType, declaredType, allowExplicit: false))
                        return Decline("emit.typed-local.type-mismatch", "typed local initializer type '" + declaredInitType.FullName + "' does not match declared type '" + declaredType.FullName + "' for '" + declaredName + "'", declaredInit);
                }
                // L3b: a lifted candidate declares as a shared StrongBox<T> (the L3b lift; lambda-typed
                // initializers stay unlifted — a reassigned-and-captured delegate local declines later).
                if (_nodes.Kind(declaredInit) != 39 && _liftedCandidates != null && _liftedCandidates.Contains(declaredName)
                    && IsLiftableValueType(declaredType))
                {
                    var typedBoxType = typeof(System.Runtime.CompilerServices.StrongBox<>).MakeGenericType(declaredType);
                    var typedBox = _il.DeclareLocal(typedBoxType);
                    _il.Emit(OpCodes.Newobj, typedBoxType.GetConstructor(new[] { declaredType })!);
                    _il.Emit(OpCodes.Stloc, typedBox);
                    _liftedLocals[declaredName] = (typedBox, declaredType);
                    return true;
                }
                var declaredLocal = _il.DeclareLocal(declaredType);
                _il.Emit(OpCodes.Stloc, declaredLocal);
                _locals[declaredName] = declaredLocal;
                if (declaredTupleNames != null)
                    _tupleNamesByVariable[declaredName] = declaredTupleNames;
                else if (_nodes.Kind(declaredInit) != 39 && TupleNamesOfExpressionNode(declaredInit) is { } typedInitNames)
                    _tupleNamesByVariable[declaredName] = typedInitNames;
                return true;
            }

            case 41: // LocalFunctionDeclaration — the declaration itself emits NO IL (the method was
                     // pre-declared before the body walk); reaching it makes the NAME visible (textual
                     // scoping, probe-pinned). A kind-41 node NOT in the declared map is a nested-block
                     // local function (scoping is a later rung) — decline.
                if (_declaredLocalFuncNodes == null || !_declaredLocalFuncNodes.TryGetValue(idx, out var declaredLocalName))
                    return false;
                _visibleLocalFuncs.Add(declaredLocalName);
                return true;

            case 27: // If [condition, then, else?] — general form covering all four then/else
            {        // fall-through-vs-return combinations, with a fall-through merge label.
                var childCount = _nodes.ChildCount(idx);
                if (childCount != 2 && childCount != 3)
                    return Decline("emit.if.shape", "if statement has an unsupported shape", idx);
                if (!EmitCondition(Child(idx, 0)))
                    return Decline("emit.if.condition", "if condition could not be emitted as a bool", Child(idx, 0));

                var thenStmt = Child(idx, 1);
                var elseLabel = _il.DefineLabel();
                _il.Emit(OpCodes.Brfalse, elseLabel);   // condition false -> else branch (or the merge end if no else)

                // then-branch. Scope its `:=` locals so a BRACELESS `:=` does not leak past the if (a Block
                // then-branch already self-scopes; this also covers the braceless single-statement form).
                var beforeThen = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(thenStmt))
                    return Decline("emit.if.then", "if then-branch could not be emitted", thenStmt);
                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!beforeThen.Contains(name))
                        _locals.Remove(name);
                }

                if (childCount == 2)
                {
                    // if-WITHOUT-else (a guard clause): the brfalse already targets the merge. Both edges
                    // reach it with an empty stack (a fall-through then-branch is net-zero; a returning
                    // then-branch ends in `ret` and never reaches it).
                    _il.MarkLabel(elseLabel);
                    return true;
                }

                // if-WITH-else. The unconditional branch over the else-block (and the end label it targets)
                // are emitted ONLY when the then-branch can FALL THROUGH to them — exactly the EmitIf fix.
                // If the then-branch always returns, that `br` is dead and would mark a label that could
                // land at the bare method end (the EmitIf/EmitSwitch hazard). The function-level
                // always-returns gate guarantees that when the if itself falls through (both branches
                // fall, or one falls), a later statement follows, so the merge is never the bare method end.
                var thenFallsThrough = !AlwaysReturns(thenStmt);
                var endLabel = _il.DefineLabel();
                if (thenFallsThrough)
                    _il.Emit(OpCodes.Br, endLabel);
                _il.MarkLabel(elseLabel);

                var elseStmt = Child(idx, 2);
                var beforeElse = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(elseStmt))
                    return Decline("emit.if.else", "if else-branch could not be emitted", elseStmt);
                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!beforeElse.Contains(name))
                        _locals.Remove(name);
                }

                if (thenFallsThrough)
                    _il.MarkLabel(endLabel);
                return true;
            }

            case 23: // ExpressionStatement — a SIMPLE `=` assignment (kind 14) to a `:=` local OR an array
            {        // element `a[i] = value`, OR a bare CALL statement (a void BCL call such as `Array.Fill(...)`,
                     // `Array.Clear(...)`, `Array.Copy(...)`, `Array.Resize(...)`, `Array.Sort(...)`,
                     // `Array.Reverse(...)`,
                     // or a sibling/BCL call whose non-void result is discarded), OR a COMPOUND assignment
                     // (`+=` `-=` `*=` `/=` on a bare local/param — lowered to load/op/store below).
                var expr = UnwrapParenthesizedNode(Child(idx, 0));

                if (_nodes.Kind(expr) == 44) // a bare `n++` / `n--` statement — the stepped value is not kept.
                {
                    return TryEmitPostfixUnary(expr, keepValue: false, out _);
                }

                if (_nodes.Kind(expr) == 9) // a bare call statement.
                {
                    // Emit the call. A void call (e.g. Array.Fill/Array.Clear/Array.Copy) leaves nothing on the stack; a
                    // NON-void call leaves its result, which is unused in statement position — discard it with `pop` (exactly
                    // what the N# backend path emits for a discarded call result, so the side effects + result are
                    // identical). This is the `helper(args)`-as-statement idiom (e.g. LinterImports.nl clearing
                    // flags for its side effect and ignoring the returned count).
                    if (!EmitExpression(expr, out var callType))
                    {
                        return Decline("emit.expression-statement.call", "call expression statement could not be emitted", expr);
                    }
                    if (callType != typeof(void))
                        _il.Emit(OpCodes.Pop);
                    return true;
                }

                if (_nodes.Kind(expr) == 53) // `await expr` as a statement — legal in N# (the await-statement rule).
                {
                    // The blocking await of a UNIT task leaves nothing; a value task's awaited result is
                    // discarded with `pop`, exactly like a bare call statement.
                    if (!EmitExpression(expr, out var awaitStmtType))
                        return Decline("emit.expression-statement.await", "await expression statement could not be emitted", expr);
                    if (awaitStmtType != typeof(void))
                        _il.Emit(OpCodes.Pop);
                    return true;
                }

                if (_nodes.Kind(expr) != 14)
                    return Decline("emit.expression-statement.unsupported", "expression statement is not a modeled assignment, call, await, or postfix mutation", expr);
                var assignOp = Text(expr);
                // COMPOUND assignment `target op= value` (`+=` `-=` `*=` `/=`) on a bare LOCAL/PARAM target —
                // lowered to load/op/store with the binary operator's exact opcode selection (ulong divides
                // unsigned; string `+=` is Concat; both sides must share one type). Lifted/boxed captures,
                // member/index targets, `%=` (unparsed) and `??=` (nullability slice) decline.
                if (assignOp is "+=" or "-=" or "*=" or "/=")
                {
                    var compoundTarget = UnwrapParenthesizedNode(Child(expr, 0));
                    // A COLLECTION indexer compound target (`d[k] += v` / `lst[i] += 1` — probe-pinned
                    // working legacy-emitter side): receiver and index evaluate ONCE into temps (N#'s
                    // single-evaluation semantics), then get_Item, the op, set_Item.
                    if (_nodes.Kind(compoundTarget) == 10)
                    {
                        if (!EmitExpression(Child(compoundTarget, 0), out var idxRecvType)
                            || !IsSupportedIndexableCollectionType(idxRecvType))
                            return false;
                        // Builder-bound collections never have the scalar/string elements compound
                        // assignment requires — decline BEFORE reflecting (plain GetMethod below
                        // throws NotSupportedException on a TypeBuilderInstantiation).
                        if (ContainsBuilderBoundType(idxRecvType))
                            return false;
                        var idxRecvDef = idxRecvType.GetGenericTypeDefinition();
                        var idxKeyType = idxRecvDef == typeof(List<>) ? typeof(int) : idxRecvType.GetGenericArguments()[0];
                        var idxElemType = idxRecvDef == typeof(List<>) ? idxRecvType.GetGenericArguments()[0] : idxRecvType.GetGenericArguments()[1];
                        var idxRecvTemp = _il.DeclareLocal(idxRecvType);
                        _il.Emit(OpCodes.Stloc, idxRecvTemp);
                        if (!EmitArg(compoundTarget, 1, idxKeyType))
                            return false;
                        var idxKeyTemp = _il.DeclareLocal(idxKeyType);
                        _il.Emit(OpCodes.Stloc, idxKeyTemp);
                        _il.Emit(OpCodes.Ldloc, idxRecvTemp);
                        _il.Emit(OpCodes.Ldloc, idxKeyTemp);
                        _il.Emit(OpCodes.Ldloc, idxRecvTemp);
                        _il.Emit(OpCodes.Ldloc, idxKeyTemp);
                        _il.Emit(OpCodes.Callvirt, idxRecvType.GetMethod("get_Item", new[] { idxKeyType })!);
                        if (TryEmitIntLiteralAsType(Child(expr, 1), idxElemType, out var idxRhsType))
                        {
                            // constant adoption (`lst[0] += 1` on a small-int element).
                        }
                        else if (!EmitExpression(Child(expr, 1), out idxRhsType))
                        {
                            return false;
                        }
                        if (!TypesEquivalent(idxRhsType, idxElemType))
                            return false;
                        if (idxElemType == typeof(string))
                        {
                            if (assignOp != "+=")
                                return false;
                            _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                        }
                        else if (idxElemType == typeof(int) || idxElemType == typeof(long) || idxElemType == typeof(ulong)
                            || idxElemType == typeof(double) || idxElemType == typeof(float))
                        {
                            _il.Emit(
                                assignOp == "+=" ? OpCodes.Add :
                                assignOp == "-=" ? OpCodes.Sub :
                                assignOp == "*=" ? OpCodes.Mul :
                                idxElemType == typeof(ulong) ? OpCodes.Div_Un : OpCodes.Div);
                        }
                        else
                        {
                            return false;
                        }
                        _il.Emit(OpCodes.Callvirt, idxRecvType.GetMethod("set_Item", new[] { idxKeyType, idxElemType })!);
                        return true;
                    }
                    // A MEMBER compound target (`s.X += 1`, `c.X += 1`, `o.i.X += 3` — the post-#22
                    // legacy emitter shape): locator; dup; ldfld; value; op; stfld — the dup'd locator (an
                    // address for value links, an object ref for reference links) makes the
                    // read-modify-write hit the SAME storage. The scalar/string op set matches the
                    // bare-local arm; decimal member compounds decline (unprobed — fallback).
                    if (_nodes.Kind(compoundTarget) == 8)
                    {
                        if (!TryResolveMemberWriteChain(Child(compoundTarget, 0), out var compoundChain)
                            || compoundChain.ReceiverType is not TypeBuilder compoundOwnerTb
                            || FindDefByBuilder(compoundOwnerTb) is not { } compoundOwnerDef
                            || !TryFindFieldOnChain(compoundOwnerDef, Text(compoundTarget), out var compoundMemberField))
                            return false;
                        var compoundMemberType = compoundMemberField.FieldType;
                        if (compoundMemberType != typeof(string) && compoundMemberType != typeof(int)
                            && compoundMemberType != typeof(long) && compoundMemberType != typeof(ulong)
                            && compoundMemberType != typeof(double) && compoundMemberType != typeof(float))
                            return false;
                        EmitMemberWriteLocator(compoundChain);
                        _il.Emit(OpCodes.Dup);
                        _il.Emit(OpCodes.Ldfld, compoundMemberField);
                        if (!TryEmitIntLiteralAsType(Child(expr, 1), compoundMemberType, out var compoundMemberValueType)
                            && (!EmitExpression(Child(expr, 1), out compoundMemberValueType)
                                || !TypesEquivalent(compoundMemberValueType, compoundMemberType)))
                            return false;
                        if (compoundMemberType == typeof(string))
                        {
                            if (assignOp != "+=")
                                return false;
                            _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                        }
                        else
                        {
                            _il.Emit(
                                assignOp == "+=" ? OpCodes.Add :
                                assignOp == "-=" ? OpCodes.Sub :
                                assignOp == "*=" ? OpCodes.Mul :
                                compoundMemberType == typeof(ulong) ? OpCodes.Div_Un : OpCodes.Div);
                        }
                        _il.Emit(OpCodes.Stfld, compoundMemberField);
                        return true;
                    }
                    if (_nodes.Kind(compoundTarget) != 6)
                        return false;
                    var compoundName = Text(compoundTarget);
                    if (_liftedLocals.ContainsKey(compoundName)
                        || (_boxedCaptures != null && _boxedCaptures.ContainsKey(compoundName)))
                        return false;
                    LocalBuilder? compoundLocal = null;
                    var compoundParamOrdinal = -1;
                    Type compoundType;
                    if (_locals.TryGetValue(compoundName, out var compoundFound))
                    {
                        compoundLocal = compoundFound;
                        compoundType = compoundFound.LocalType;
                    }
                    else if (_paramOrdinals.TryGetValue(compoundName, out var compoundOrdinal))
                    {
                        compoundParamOrdinal = compoundOrdinal;
                        compoundType = _paramTypes[compoundName];
                    }
                    else
                    {
                        return false;
                    }

                    if (compoundLocal != null)
                        _il.Emit(OpCodes.Ldloc, compoundLocal);
                    else
                        EmitLoadArgument(compoundParamOrdinal);
                    // `u /= 3` — an in-range int literal adopts the target's type (N# constant conversion).
                    if (!TryEmitIntLiteralAsType(Child(expr, 1), compoundType, out var compoundValueType)
                        && (!EmitExpression(Child(expr, 1), out compoundValueType) || !TypesEquivalent(compoundValueType, compoundType)))
                        return false;

                    if (compoundType == typeof(string))
                    {
                        if (assignOp != "+=")
                            return false;
                        _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                    }
                    else if (compoundType == typeof(decimal))
                    {
                        _il.Emit(OpCodes.Call, typeof(decimal).GetMethod(
                            assignOp == "+=" ? "op_Addition" : assignOp == "-=" ? "op_Subtraction"
                            : assignOp == "*=" ? "op_Multiply" : "op_Division",
                            new[] { typeof(decimal), typeof(decimal) })!);
                    }
                    else if (compoundType == typeof(int) || compoundType == typeof(long) || compoundType == typeof(ulong)
                        || compoundType == typeof(double) || compoundType == typeof(float))
                    {
                        _il.Emit(
                            assignOp == "+=" ? OpCodes.Add :
                            assignOp == "-=" ? OpCodes.Sub :
                            assignOp == "*=" ? OpCodes.Mul :
                            compoundType == typeof(ulong) ? OpCodes.Div_Un : OpCodes.Div);
                    }
                    else
                    {
                        return false;
                    }

                    if (compoundLocal != null)
                        _il.Emit(OpCodes.Stloc, compoundLocal);
                    else
                        EmitStoreArgument(compoundParamOrdinal);
                    return true;
                }
                if (assignOp != "=")
                    return false;
                var target = UnwrapParenthesizedNode(Child(expr, 0));

                if (_nodes.Kind(target) == 10) // array element write: a[i] = value
                {
                    if (!EmitExpression(Child(target, 0), out var arrayType))
                        return false;
                    // A closed List<T>/Dictionary<K,V> indexer WRITE — callvirt set_Item(int|K, T|V)
                    // (the dominant Dictionary shape `d[k] = v`, probe-pinned incl. overwrite);
                    // resolved from the open definition so builder-bound receivers rebind.
                    if (IsSupportedIndexableCollectionType(arrayType))
                    {
                        var setDef = arrayType.GetGenericTypeDefinition();
                        var setIdxType = setDef == typeof(List<>)
                            ? typeof(int)
                            : arrayType.GetGenericArguments()[0];
                        var setValType = setDef == typeof(List<>)
                            ? arrayType.GetGenericArguments()[0]
                            : arrayType.GetGenericArguments()[1];
                        if (!EmitArg(target, 1, setIdxType))
                            return false;
                        if (!EmitExpression(Child(expr, 1), out var setValueType)
                            || (!TypesEquivalent(setValueType, setValType) && !TryEmitReferenceConversion(setValueType, setValType) && !TryEmitObjectConversion(setValueType, setValType)))
                            return false;
                        _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(arrayType, setDef.GetMethod("set_Item")!));
                        return true;
                    }
                    if (!arrayType.IsSZArray)
                        return false;
                    // Stelem order is (array, index, value): emit the array ref, the int index, the value, store.
                    var elementType = arrayType.GetElementType()!;
                    if (!EmitExpression(Child(target, 1), out var indexType) || indexType != typeof(int))
                        return false;
                    if (!EmitExpression(Child(expr, 1), out var elementValueType) || elementValueType != elementType)
                        return false;
                    if (!EmitArrayElementStore(elementType))
                        return false;
                    return true;
                }

                if (_nodes.Kind(target) == 8) // a member-access target: a class PROPERTY setter OR a value-type struct field.
                {
                    var fieldReceiver = Child(target, 0);
                    var memberName = Text(target);
                    // STATIC member write `TypeName.member = value`: the receiver names a registered TYPE (not
                    // shadowed by a local/param/sibling) — chain-walk its static FIELDS (`<value>; stsfld`) then
                    // static PROPERTIES (`<value>; call set_Name`; a get-only static property declines). A
                    // type-name receiver whose member is NEITHER declines (a type name is not a value).
                    if (_nodes.Kind(fieldReceiver) == 6)
                    {
                        var staticRecvName = Text(fieldReceiver);
                        if (!_locals.ContainsKey(staticRecvName) && !_liftedLocals.ContainsKey(staticRecvName) && !_paramOrdinals.ContainsKey(staticRecvName) && !_siblings.ContainsKey(staticRecvName)
                            && _structRegistry.TryGetValue(staticRecvName, out var staticWriteOwner))
                        {
                            if (TryFindStaticFieldOnChain(staticWriteOwner, memberName, out var staticFieldWrite))
                            {
                                if (!TryEmitAssignableValue(Child(expr, 1), staticFieldWrite.FieldType, out _))
                                    return false;
                                _il.Emit(OpCodes.Stsfld, staticFieldWrite);
                                return true;
                            }
                            if (TryFindStaticPropertyOnChain(staticWriteOwner, memberName, out var staticPropWrite) && staticPropWrite.Setter != null)
                            {
                                if (!TryEmitAssignableValue(Child(expr, 1), staticPropWrite.PropertyType, out _))
                                    return false;
                                _il.Emit(OpCodes.Call, staticPropWrite.Setter);
                                return true;
                            }
                            return false;
                        }
                    }
                    if (TryEmitSupportedBclPropertyAssignment(fieldReceiver, memberName, Child(expr, 1)))
                        return true;

                    // MEMBER WRITES through a resolved receiver CHAIN (D-18b, mirroring the post-#22
                    // legacy emitter): roots are bare LOCALS and PARAMS; hops are instance FIELDS (`p.X = v`
                    // on struct params, `c.X = v` on class/record locals and params, `o.i.X = v`,
                    // `h.s.X = v`, `a.b.s.X = v`). The chain resolves BEFORE any emission (the
                    // emit-ownership rule). A FIELD write emits locator; value; stfld — stfld accepts
                    // an object ref OR a managed pointer, so value links use ldloca/ldarga/ldflda and
                    // reference links ldloc/ldarg/ldfld and the chain composes uniformly. A PROPERTY
                    // write needs a REFERENCE final receiver (value-type properties stay declined):
                    // locator; value; callvirt setter. Record fields are NOT init-only in the pipeline
                    // (probe-pinned `r.X = 5` -> 5) — they write exactly like class fields. DECLINES:
                    // indexer/call-result receivers (pipeline-REJECTED, NL322 — parity by rejection
                    // via the fallback), lifted/captured roots (the capture-mutation family stays
                    // conservative), and closed-generic receivers (`Box<int>` — a later rebind rung).
                    if (TryResolveMemberWriteChain(fieldReceiver, out var writeChain)
                        && writeChain.ReceiverType is TypeBuilder writeOwnerTb
                        && FindDefByBuilder(writeOwnerTb) is { } writeOwnerDef)
                    {
                        if (TryFindFieldOnChain(writeOwnerDef, memberName, out var writeField))
                        {
                            EmitMemberWriteLocator(writeChain);
                            Type writeValueType;
                            if (TryEmitIntLiteralAsType(Child(expr, 1), writeField.FieldType, out writeValueType))
                            {
                                // constant adoption (`s.B = 5` on a small-int field).
                            }
                            else if (TryEmitNullLiteralAsType(Child(expr, 1), writeField.FieldType, out writeValueType))
                            {
                                // `c.name = null` on a reference-typed field.
                            }
                            else if (!EmitExpression(Child(expr, 1), out writeValueType))
                            {
                                return false;
                            }
                            if (!TypesEquivalent(writeValueType, writeField.FieldType)
                                && !TryEmitImplicitWidening(writeValueType, writeField.FieldType) && !TryEmitInterfaceUpcast(writeValueType, writeField.FieldType) && !TryEmitReferenceConversion(writeValueType, writeField.FieldType) && !TryEmitObjectConversion(writeValueType, writeField.FieldType) && !TryEmitUserDefinedConversion(writeValueType, writeField.FieldType, allowExplicit: false))
                                return false;
                            _il.Emit(OpCodes.Stfld, writeField);
                            return true;
                        }
                        if (writeOwnerDef.IsReference
                            && TryFindPropertyOnChain(writeOwnerDef, memberName, out var writeProp)
                            && writeProp.Setter != null)
                        {
                            EmitMemberWriteLocator(writeChain);
                            if (!EmitExpression(Child(expr, 1), out var writePropValueType)
                                || !TypesEquivalent(writePropValueType, writeProp.PropertyType))
                                return false;
                            _il.Emit(OpCodes.Callvirt, writeProp.Setter);
                            return true;
                        }
                    }
                    return false;
                }

                if (_nodes.Kind(target) != 6)
                    return false;
                var targetName = Text(target);
                if (IsExplicitThisIdentifier(target))
                {
                    if (_currentStruct == null || (!_currentStruct.IsReference && !_isConstructorBody))
                        return false;
                    if (TryFindFieldOnChain(_currentStruct, targetName, out var explicitThisFieldTarget))
                    {
                        _il.Emit(OpCodes.Ldarg_0);
                        if (!TryEmitAssignableValue(Child(expr, 1), explicitThisFieldTarget.FieldType, out _))
                            return false;
                        _il.Emit(OpCodes.Stfld, explicitThisFieldTarget);
                        return true;
                    }
                    if (_currentStruct.IsReference
                        && TryFindPropertyOnChain(_currentStruct, targetName, out var explicitThisPropertyTarget)
                        && explicitThisPropertyTarget.Setter != null)
                    {
                        _il.Emit(OpCodes.Ldarg_0);
                        if (!TryEmitAssignableValue(Child(expr, 1), explicitThisPropertyTarget.PropertyType, out _))
                            return false;
                        _il.Emit(OpCodes.Callvirt, explicitThisPropertyTarget.Setter);
                        return true;
                    }
                    return false;
                }
                // L3b: writes to a BOXED capture (closure body) or a LIFTED local/param store through the
                // shared StrongBox's Value — checked before every other tier.
                if (_boxedCaptures != null && _boxedCaptures.TryGetValue(targetName, out var boxedWrite))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    _il.Emit(OpCodes.Ldfld, boxedWrite.BoxField);
                    if (!EmitExpression(Child(expr, 1), out var boxedValueType) || boxedValueType != boxedWrite.ValueType)
                        return false;
                    _il.Emit(OpCodes.Stfld, StrongBoxValueField(boxedWrite.ValueType));
                    return true;
                }
                if (_liftedLocals.TryGetValue(targetName, out var liftedWrite))
                {
                    _il.Emit(OpCodes.Ldloc, liftedWrite.Box);
                    if (!EmitExpression(Child(expr, 1), out var liftedValueType) || liftedValueType != liftedWrite.ValueType)
                        return false;
                    _il.Emit(OpCodes.Stfld, StrongBoxValueField(liftedWrite.ValueType));
                    return true;
                }
                if (_locals.TryGetValue(targetName, out var assignTarget))
                {
                    // `local = expr` — store into the `:=` local (value type must match the local's type;
                    // TypesEquivalent — closed user-generic instantiations are referentially distinct). A
                    // generic-union case construction with no type args ADOPTS the local's declared type
                    // (`o = new Opt.None` on an Opt<int> local — probe-pinned).
                    Type valueType;
                    if (IsAdoptableUnionConstruction(Child(expr, 1), assignTarget.LocalType))
                    {
                        if (!EmitAdoptedUnionConstruction(Child(expr, 1), assignTarget.LocalType, out valueType))
                            return false;
                    }
                    else if (TryEmitIntLiteralAsType(Child(expr, 1), assignTarget.LocalType, out valueType))
                    {
                        // `b = 5` on a byte/uint/long/ulong local — constant conversion.
                    }
                    else if (TryEmitArrayLiteralAsType(Child(expr, 1), assignTarget.LocalType, out valueType))
                    {
                        // target-typed array literal re-store.
                    }
                    else if (TryEmitNullLiteralAsType(Child(expr, 1), assignTarget.LocalType, out valueType))
                    {
                        // `s = null` on a reference-typed local.
                    }
                    else if (IsSupportedNullable(assignTarget.LocalType))
                    {
                        // lifted re-store onto an int? local (owns the emission).
                        if (!TryEmitValueAsNullable(Child(expr, 1), assignTarget.LocalType, out valueType))
                            return false;
                    }
                    else if (!EmitExpression(Child(expr, 1), out valueType))
                    {
                        return false;
                    }
                    if (!TypesEquivalent(valueType, assignTarget.LocalType) && !TryEmitImplicitWidening(valueType, assignTarget.LocalType) && !TryEmitInterfaceUpcast(valueType, assignTarget.LocalType) && !TryEmitReferenceConversion(valueType, assignTarget.LocalType) && !TryEmitObjectConversion(valueType, assignTarget.LocalType) && !TryEmitUserDefinedConversion(valueType, assignTarget.LocalType, allowExplicit: false))
                        return false;
                    _il.Emit(OpCodes.Stloc, assignTarget);
                    return true;
                }
                if (_isSynthesizedInitializerBody
                    && _currentStruct != null
                    && TryFindFieldOnChain(_currentStruct, targetName, out var synthesizedFieldTarget))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    if (!TryEmitAssignableValue(Child(expr, 1), synthesizedFieldTarget.FieldType, out _))
                        return false;
                    _il.Emit(OpCodes.Stfld, synthesizedFieldTarget);
                    return true;
                }
                if (_paramOrdinals.TryGetValue(targetName, out var paramOrdinal))
                {
                    var declaredParamType = _paramTypes[targetName];
                    if (declaredParamType.IsByRef)
                    {
                        var paramElementType = declaredParamType.GetElementType()!;
                        EmitLoadArgument(paramOrdinal);
                        Type byRefParamValueType;
                        if (IsAdoptableUnionConstruction(Child(expr, 1), paramElementType))
                        {
                            if (!EmitAdoptedUnionConstruction(Child(expr, 1), paramElementType, out byRefParamValueType))
                                return false;
                        }
                        else if (TryEmitIntLiteralAsType(Child(expr, 1), paramElementType, out byRefParamValueType))
                        {
                            // constant conversion onto the byref parameter's element type.
                        }
                        else if (TryEmitNullLiteralAsType(Child(expr, 1), paramElementType, out byRefParamValueType))
                        {
                            // `out value = null` on a reference-typed byref parameter.
                        }
                        else if (IsSupportedNullable(paramElementType))
                        {
                            if (!TryEmitValueAsNullable(Child(expr, 1), paramElementType, out byRefParamValueType))
                                return false;
                        }
                        else if (!EmitExpression(Child(expr, 1), out byRefParamValueType))
                        {
                            return false;
                        }
                        if (!TypesEquivalent(byRefParamValueType, paramElementType)
                            && !TryEmitImplicitWidening(byRefParamValueType, paramElementType)
                            && !TryEmitInterfaceUpcast(byRefParamValueType, paramElementType)
                            && !TryEmitReferenceConversion(byRefParamValueType, paramElementType)
                            && !TryEmitObjectConversion(byRefParamValueType, paramElementType)
                            && !TryEmitUserDefinedConversion(byRefParamValueType, paramElementType, allowExplicit: false))
                            return false;
                        EmitStoreByRefElement(paramElementType);
                        return true;
                    }
                    // `param = expr` — store into the argument slot (`starg`). N# permits mutating a parameter
                    // (value params have value semantics, so the mutation is method-local, matching the N# backend path).
                    // The value's type must match the parameter's declared type; adoption applies as for locals.
                    Type paramValueType;
                    if (IsAdoptableUnionConstruction(Child(expr, 1), _paramTypes[targetName]))
                    {
                        if (!EmitAdoptedUnionConstruction(Child(expr, 1), _paramTypes[targetName], out paramValueType))
                            return false;
                    }
                    else if (TryEmitIntLiteralAsType(Child(expr, 1), _paramTypes[targetName], out paramValueType))
                    {
                        // constant conversion onto the param's declared type.
                    }
                    else if (TryEmitNullLiteralAsType(Child(expr, 1), _paramTypes[targetName], out paramValueType))
                    {
                        // `s = null` on a reference-typed param.
                    }
                    else if (IsSupportedNullable(_paramTypes[targetName]))
                    {
                        // lifted re-store onto an int? param (owns the emission).
                        if (!TryEmitValueAsNullable(Child(expr, 1), _paramTypes[targetName], out paramValueType))
                            return false;
                    }
                    else if (!EmitExpression(Child(expr, 1), out paramValueType))
                    {
                        return false;
                    }
                    if (!TypesEquivalent(paramValueType, _paramTypes[targetName]) && !TryEmitImplicitWidening(paramValueType, _paramTypes[targetName]) && !TryEmitInterfaceUpcast(paramValueType, _paramTypes[targetName]) && !TryEmitReferenceConversion(paramValueType, _paramTypes[targetName]) && !TryEmitObjectConversion(paramValueType, _paramTypes[targetName]) && !TryEmitUserDefinedConversion(paramValueType, _paramTypes[targetName], allowExplicit: false))
                        return false;
                    EmitStoreArgument(paramOrdinal);
                    return true;
                }
                // `field = expr` inside a REFERENCE-type instance method/constructor body: a bare name that is neither
                // a local nor a param falls back to a FIELD of the current type (`this.field = expr`). `this` is arg 0
                // (the object ref), so emit `ldarg.0; <value>; stfld <FieldBuilder>`. (Checked AFTER locals/params so a
                // local/param shadows a field — matching the bare-field READ in EmitExpression's identifier case.)
                // GATED to reference types: a VALUE-type (struct) instance call spills the receiver to a TEMP COPY
                // (TryEmitInstanceCall), so a struct method's field mutation would write the copy, not the caller's
                // variable — diverging from N#'s in-place value semantics. Struct field-mutation-in-method therefore
                // DECLINES until the call site addresses the receiver's own storage (a later slice). A class/record
                // ref is shared through the temp, so the mutation persists correctly. Resolution walks the BASE
                // chain (nearest first) so a derived member may assign an INHERITED field.
                if (_currentStruct != null && (_currentStruct.IsReference || _isConstructorBody) && TryFindFieldOnChain(_currentStruct, targetName, out var thisFieldTarget))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    if (!TryEmitAssignableValue(Child(expr, 1), thisFieldTarget.FieldType, out _))
                        return false;
                    _il.Emit(OpCodes.Stfld, thisFieldTarget);
                    return true;
                }
                // Bare STATIC-field write inside an INSTANCE member body (`count = expr` where count is a static
                // field on the chain). The N# pipeline's pinned ASYMMETRY: bare static-field access resolves in
                // INSTANCE contexts only — a STATIC method body must qualify (`TypeName.field`), so this is gated
                // on `_currentStruct` (null in static bodies → declines exactly where the pipeline errors). No
                // receiver: `<value>; stsfld`. (Statics need no address, so value-type enclosing types are fine.)
                if (_currentStruct != null && TryFindStaticFieldOnChain(_currentStruct, targetName, out var bareStaticTarget))
                {
                    if (!TryEmitAssignableValue(Child(expr, 1), bareStaticTarget.FieldType, out _))
                        return false;
                    _il.Emit(OpCodes.Stsfld, bareStaticTarget);
                    return true;
                }
                return false;
            }

            case 26: // While [condition, body] — emit `check: cond; brfalse end; body; [br check]; end:`. The
            {        // stack is empty at both merge labels (cond pushes a bool, brfalse pops it; the body is
                     // net-zero), so it is stack-consistent.
                if (TryEmitVectorizedReductionWhile(idx))
                    return true;
                if (TryEmitVectorizedRangeCountWhile(idx))
                    return true;
                if (TryEmitVectorizedMinMaxWhile(idx))
                    return true;
                if (TryEmitVectorizedCountTransitionsWhile(idx))
                    return true;
                var body = Child(idx, 1);
                var checkLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                if (!EmitCondition(Child(idx, 0)))
                    return false;
                _il.Emit(OpCodes.Brfalse, endLabel);
                // Scope the body's `:=` locals so they leave scope at the loop end. A Block body self-scopes;
                // this also covers a BRACELESS single-statement body (e.g. a bare `:=`), which is not a Block.
                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                var outerLifted = new HashSet<string>(_liftedLocals.Keys, StringComparer.Ordinal);
                // `break` exits to endLabel, `continue` re-tests at checkLabel; both reach their target with an
                // empty stack (the body up to the transfer is net-zero), so they are stack-consistent.
                _loopLabels.Push((endLabel, checkLabel, _inProtectedRegion, _inFinallyRegion));
                var bodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!bodyEmitted)
                    return false;
                var bodyLocals = new List<string>();
                foreach (var name in _locals.Keys)
                {
                    if (!outerLocals.Contains(name))
                        bodyLocals.Add(name);
                }

                foreach (var name in bodyLocals)
                    _locals.Remove(name);
                foreach (var name in new List<string>(_liftedLocals.Keys))
                {
                    if (!outerLifted.Contains(name))
                        _liftedLocals.Remove(name);
                }
                // The bottom back-edge is reachable ONLY if the body can FALL THROUGH to it. If the body always
                // transfers on every path (a scan loop that `continue`s otherwise + `return`s, or a degenerate
                // run-once `{ return X }` body), it never falls through, so the bottom `br check` would be dead
                // code — skip it (the `continue`s already branch to checkLabel directly, so the loop still
                // iterates). This both AVOIDS unreachable IL and ADMITS the common scan-loop pattern that the
                // old blanket `AlwaysReturns(body)` decline wrongly rejected.
                if (!AlwaysReturns(body))
                    _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);
                return true;
            }

            case 28: // For [init, cond, incr, body] — C-style: emit `init; check: cond; brfalse end; body;
            {        // cont: incr; br check; end:`. `break` -> end, `continue` -> cont (the increment, THEN the
                     // re-test), matching N# for-loop semantics. The loop's own locals (the `init` declaration's
                     // variable + any body `:=` locals) are scoped to the loop and removed at its end.
                var init = Child(idx, 0);
                var cond = Child(idx, 1);
                var incr = Child(idx, 2);
                var body = Child(idx, 3);

                // A for-body that always transfers on every path (never falls through) would make the increment +
                // back-edge unreachable (a `continue` aside) — a degenerate shape; decline it to the N# backend path. A
                // normal counting loop falls through, and a `continue` body still falls through on its other path.
                if (AlwaysReturns(body))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                var outerLifted = new HashSet<string>(_liftedLocals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(init)) // runs once before the loop; declares the loop variable.
                    return false;

                if (TryEmitVectorizedReductionFor(cond, incr, body))
                {
                    foreach (var name in new List<string>(_locals.Keys))
                    {
                        if (!outerLocals.Contains(name))
                            _locals.Remove(name);
                    }
                    foreach (var name in new List<string>(_liftedLocals.Keys))
                    {
                        if (!outerLifted.Contains(name))
                            _liftedLocals.Remove(name);
                    }
                    return true;
                }

                if (TryEmitVectorizedRangeCountFor(cond, incr, body))
                {
                    foreach (var name in new List<string>(_locals.Keys))
                    {
                        if (!outerLocals.Contains(name))
                            _locals.Remove(name);
                    }
                    foreach (var name in new List<string>(_liftedLocals.Keys))
                    {
                        if (!outerLifted.Contains(name))
                            _liftedLocals.Remove(name);
                    }
                    return true;
                }

                if (TryEmitVectorizedMinMaxFor(cond, incr, body))
                {
                    foreach (var name in new List<string>(_locals.Keys))
                    {
                        if (!outerLocals.Contains(name))
                            _locals.Remove(name);
                    }
                    foreach (var name in new List<string>(_liftedLocals.Keys))
                    {
                        if (!outerLifted.Contains(name))
                            _liftedLocals.Remove(name);
                    }
                    return true;
                }

                if (TryEmitVectorizedCountTransitionsFor(cond, incr, body))
                {
                    foreach (var name in new List<string>(_locals.Keys))
                    {
                        if (!outerLocals.Contains(name))
                            _locals.Remove(name);
                    }
                    foreach (var name in new List<string>(_liftedLocals.Keys))
                    {
                        if (!outerLifted.Contains(name))
                            _liftedLocals.Remove(name);
                    }
                    return true;
                }

                var checkLabel = _il.DefineLabel();
                var contLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                if (!EmitCondition(cond))
                    return false;
                _il.Emit(OpCodes.Brfalse, endLabel);

                _loopLabels.Push((endLabel, contLabel, _inProtectedRegion, _inFinallyRegion));
                var forBodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!forBodyEmitted)
                    return false;

                _il.MarkLabel(contLabel);     // `continue` lands here -> run the increment, then re-test.
                if (!EmitStatement(incr))
                    return false;
                _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);

                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!outerLocals.Contains(name))
                        _locals.Remove(name);
                }
                foreach (var name in new List<string>(_liftedLocals.Keys))
                {
                    if (!outerLifted.Contains(name))
                        _liftedLocals.Remove(name);
                }
                return true;
            }

            case 29: // Foreach [collection, body] — arrays lower to an index loop; supported BCL
            {        // collections lower through the interface-enumerator shape. Everything else
                     // declines. The var name is in the value span.
                var collectionNode = Child(idx, 0);
                var body = Child(idx, 1);
                var varName = Text(idx);

                // A body that always transfers on every path makes the increment unreachable -> decline (as for/while).
                if (AlwaysReturns(body))
                    return false;
                // The loop variable must not shadow an existing binding — own OR enclosing (NL316).
                if (IsVisibleBindingName(varName))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                var outerLifted = new HashSet<string>(_liftedLocals.Keys, StringComparer.Ordinal);

                // Evaluate the collection; a List<T>/Dictionary<K,V>/HashSet<T> takes the enumerator branch,
                // a single-dim array the index loop; everything else declines.
                if (!EmitExpression(collectionNode, out var collectionType))
                    return false;
                if (IsSupportedCollectionType(collectionType))
                {
                    var collectionDef = collectionType.GetGenericTypeDefinition();
                    var listElementType = collectionDef == typeof(Dictionary<,>)
                        ? typeof(KeyValuePair<,>).MakeGenericType(collectionType.GetGenericArguments())
                        : collectionType.GetGenericArguments()[0];
                    if (!IsSupportedType(listElementType) && !IsSupportedKeyValuePairType(listElementType))
                        return false;
                    var enumerableInterface = typeof(IEnumerable<>).MakeGenericType(listElementType);
                    var enumeratorInterface = typeof(IEnumerator<>).MakeGenericType(listElementType);
                    _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(enumerableInterface, typeof(IEnumerable<>).GetMethod("GetEnumerator")!));
                    var enumeratorLocal = _il.DeclareLocal(enumeratorInterface);
                    _il.Emit(OpCodes.Stloc, enumeratorLocal);

                    var listLoopStart = _il.DefineLabel();
                    var disposeLabel = _il.DefineLabel();
                    _il.MarkLabel(listLoopStart);
                    _il.Emit(OpCodes.Ldloc, enumeratorLocal);
                    _il.Emit(OpCodes.Callvirt, typeof(System.Collections.IEnumerator).GetMethod(nameof(System.Collections.IEnumerator.MoveNext))!);
                    _il.Emit(OpCodes.Brfalse, disposeLabel);
                    _il.Emit(OpCodes.Ldloc, enumeratorLocal);
                    _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(enumeratorInterface, typeof(IEnumerator<>).GetProperty("Current")!.GetGetMethod()!));
                    var listLoopVar = _il.DeclareLocal(listElementType);
                    _il.Emit(OpCodes.Stloc, listLoopVar);
                    _locals[varName] = listLoopVar;

                    _loopLabels.Push((disposeLabel, listLoopStart, _inProtectedRegion, _inFinallyRegion));
                    var listBodyEmitted = EmitStatement(body);
                    _loopLabels.Pop();
                    if (!listBodyEmitted)
                        return false;
                    _il.Emit(OpCodes.Br, listLoopStart);
                    _il.MarkLabel(disposeLabel);
                    _il.Emit(OpCodes.Ldloc, enumeratorLocal);
                    _il.Emit(OpCodes.Callvirt, typeof(IDisposable).GetMethod(nameof(IDisposable.Dispose))!);

                    foreach (var name in new List<string>(_locals.Keys))
                    {
                        if (!outerLocals.Contains(name))
                            _locals.Remove(name);
                    }
                    foreach (var name in new List<string>(_liftedLocals.Keys))
                    {
                        if (!outerLifted.Contains(name))
                            _liftedLocals.Remove(name);
                    }
                    return true;
                }
                if (!collectionType.IsSZArray)
                    return false;
                var elementType = collectionType.GetElementType()!;
                if (!IsSupportedElementType(elementType))
                    return false;
                var arrayLocal = _il.DeclareLocal(collectionType);
                _il.Emit(OpCodes.Stloc, arrayLocal);
                var indexLocal = _il.DeclareLocal(typeof(int));
                _il.Emit(OpCodes.Ldc_I4_0);
                _il.Emit(OpCodes.Stloc, indexLocal);

                var checkLabel = _il.DefineLabel();
                var contLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                _il.Emit(OpCodes.Ldloc, indexLocal);
                _il.Emit(OpCodes.Ldloc, arrayLocal);
                _il.Emit(OpCodes.Ldlen);
                _il.Emit(OpCodes.Conv_I4);
                _il.Emit(OpCodes.Bge, endLabel); // index >= length -> exit

                // <var> := arr[index]  (declare the loop variable of the element type, store the current element).
                _il.Emit(OpCodes.Ldloc, arrayLocal);
                _il.Emit(OpCodes.Ldloc, indexLocal);
                if (elementType == typeof(bool)) _il.Emit(OpCodes.Ldelem_U1);
                else if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(uint)) _il.Emit(OpCodes.Ldelem_U4);
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                else if (!elementType.IsValueType) _il.Emit(OpCodes.Ldelem_Ref);
                else if (elementType is TypeBuilder || IsSupportedType(elementType)) _il.Emit(OpCodes.Ldelem, elementType);
                else return false;
                var loopVar = _il.DeclareLocal(elementType);
                _il.Emit(OpCodes.Stloc, loopVar);
                _locals[varName] = loopVar;

                _loopLabels.Push((endLabel, contLabel, _inProtectedRegion, _inFinallyRegion));
                var foreachBodyEmitted = EmitStatement(body);
                _loopLabels.Pop();
                if (!foreachBodyEmitted)
                    return false;

                _il.MarkLabel(contLabel);   // `continue` lands here -> increment the index, then re-test.
                _il.Emit(OpCodes.Ldloc, indexLocal);
                _il.Emit(OpCodes.Ldc_I4_1);
                _il.Emit(OpCodes.Add);
                _il.Emit(OpCodes.Stloc, indexLocal);
                _il.Emit(OpCodes.Br, checkLabel);
                _il.MarkLabel(endLabel);

                foreach (var name in new List<string>(_locals.Keys))
                {
                    if (!outerLocals.Contains(name))
                        _locals.Remove(name);
                }
                foreach (var name in new List<string>(_liftedLocals.Keys))
                {
                    if (!outerLifted.Contains(name))
                        _liftedLocals.Remove(name);
                }
                return true;
            }

            case 30: // TupleDeconstruction [name0, ..., nameN-1, value] — `n0, n1, ... := <tuple>`. Emit the value
            {        // (a ValueTuple), store to a temp, then for each non-`_` name declare a local of the element
                     // type and store the matching ItemN. Mirrors the tuple deconstruction emitter (plain path).
                var childCount = _nodes.ChildCount(idx);
                if (childCount < 3) // at least 2 names + the value.
                    return false;
                var nameCount = childCount - 1;
                var valueNode = Child(idx, nameCount);

                // The Go-style error capture `v, err := <call>` (names[1] == "err" — the legacy
                // emitter's IsErrorTupleDeconstruction): v = default(T); err = null;
                // try { v = <call> } catch (Exception e) { err = e }. The initializer is a single
                // expression, so no control transfer can cross the protected region.
                if (nameCount == 2 && Text(Child(idx, 1)) == "err")
                {
                    if (_inProtectedRegion || _inFinallyRegion)
                        return false;
                    var errResultName = Text(Child(idx, 0));
                    if (IsVisibleBindingName("err") || (errResultName != "_" && IsVisibleBindingName(errResultName)))
                        return false;

                    LocalBuilder? errResultLocal = null;
                    Type? errResultType = null;
                    if (errResultName != "_")
                    {
                        if (!TryGetPreflightExpressionType(valueNode, out errResultType) || errResultType == typeof(void))
                            return Decline("emit.tuple-error.preflight", "error-tuple value expression type could not be preflighted", valueNode);
                        errResultLocal = _il.DeclareLocal(errResultType);
                        if (!TryEmitDefaultValue(errResultType))
                            return Decline("emit.tuple-error.default", "error-tuple result default value could not be emitted", valueNode);
                        _il.Emit(OpCodes.Stloc, errResultLocal);
                    }

                    var errLocal = _il.DeclareLocal(typeof(Exception));
                    _il.Emit(OpCodes.Ldnull);
                    _il.Emit(OpCodes.Stloc, errLocal);

                    _il.BeginExceptionBlock();
                    _inProtectedRegion = true;
                    var errValueOk = EmitExpression(valueNode, out var errValueType);
                    _inProtectedRegion = false;
                    if (!errValueOk)
                        return Decline("emit.tuple-error.value", "error-tuple value expression could not be emitted", valueNode);
                    if (errResultLocal != null)
                    {
                        if (!TypesEquivalent(errValueType, errResultType!))
                            return Decline("emit.tuple-error.type-mismatch", "error-tuple value expression type '" + errValueType.FullName + "' does not match preflighted type '" + errResultType!.FullName + "'", valueNode);
                        _il.Emit(OpCodes.Stloc, errResultLocal);
                    }
                    else if (errValueType != typeof(void))
                    {
                        _il.Emit(OpCodes.Pop);
                    }
                    _il.BeginCatchBlock(typeof(Exception));
                    _il.Emit(OpCodes.Stloc, errLocal);
                    _il.EndExceptionBlock();

                    if (errResultLocal != null)
                        _locals[errResultName] = errResultLocal;
                    _locals["err"] = errLocal;
                    return true;
                }

                if (!EmitExpression(valueNode, out var tupleType) || !IsSupportedValueTuple(tupleType))
                    return false;
                var tupleArgs = tupleType.GetGenericArguments();
                if (tupleArgs.Length != nameCount) // the tuple arity must match the number of targets.
                    return false;

                var tupleLocal = _il.DeclareLocal(tupleType);
                _il.Emit(OpCodes.Stloc, tupleLocal);

                for (var i = 0; i < nameCount; i++)
                {
                    var name = Text(Child(idx, i));
                    if (name == "_") // discard — the element is not bound.
                        continue;
                    if (IsVisibleBindingName(name))
                        return false; // redeclaration / shadow — own OR enclosing (NL316) — is not modelled.
                    var field = tupleType.GetField("Item" + (i + 1), BindingFlags.Public | BindingFlags.Instance);
                    if (field == null)
                    {
                        return false;
                    }
                    var nameLocal = _il.DeclareLocal(field.FieldType);
                    _il.Emit(OpCodes.Ldloca, tupleLocal); // value-type field load: address of the tuple, then ldfld.
                    _il.Emit(OpCodes.Ldfld, field);
                    _il.Emit(OpCodes.Stloc, nameLocal);
                    _locals[name] = nameLocal;
                }

                return true;
            }

            case 21: // Break — branch to the innermost loop's end label. From inside a protected region
            {        // whose loop began OUTSIDE it, the branch crosses the boundary: `leave` (which also
                     // runs an intervening finally — probe-pinned against the fixed legacy emitter). Out of a
                     // FINALLY itself is illegal IL — analyzer-rejected with NL319 (defect #20 fixed);
                     // the decline stays as this emitter's contract guard.
                if (_loopLabels.Count == 0)
                    return false;
                var breakTarget = _loopLabels.Peek();
                if (_inFinallyRegion && !breakTarget.InFinallyRegion)
                    return false;
                _il.Emit(_inProtectedRegion && !breakTarget.InProtectedRegion ? OpCodes.Leave : OpCodes.Br, breakTarget.Break);
                return true;
            }

            case 22: // Continue — branch to the innermost loop's condition-check label (same region rules
            {        // as break).
                if (_loopLabels.Count == 0)
                    return false;
                var continueTarget = _loopLabels.Peek();
                if (_inFinallyRegion && !continueTarget.InFinallyRegion)
                    return false;
                _il.Emit(_inProtectedRegion && !continueTarget.InProtectedRegion ? OpCodes.Leave : OpCodes.Br, continueTarget.Continue);
                return true;
            }

            case 61: // AssertStatement [condition, message?] — the legacy emitter's EmitAssert: brtrue past
            {        // a `throw new InvalidOperationException(<message text or "Assertion failed">)`.
                if (_nodes.ChildCount(idx) is not (1 or 2))
                    return false;
                if (!EmitExpression(Child(idx, 0), out var assertCondType) || assertCondType != typeof(bool))
                    return false;
                var assertOk = _il.DefineLabel();
                _il.Emit(OpCodes.Brtrue, assertOk);
                if (_nodes.ChildCount(idx) == 2)
                {
                    if (!EmitExpression(Child(idx, 1), out var assertMessageType))
                        return false;
                    if (assertMessageType != typeof(string))
                    {
                        if (assertMessageType.IsValueType)
                            _il.Emit(OpCodes.Box, assertMessageType);
                        _il.Emit(OpCodes.Callvirt, typeof(object).GetMethod(nameof(ToString), Type.EmptyTypes)!);
                    }
                }
                else
                {
                    _il.Emit(OpCodes.Ldstr, "Assertion failed");
                }
                _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                _il.Emit(OpCodes.Throw);
                _il.MarkLabel(assertOk);
                return true;
            }

            case 62: // AssertThrowsStatement [body] — legacy EmitAssertThrows: run the body in a try; a
            {        // fall-through throws "Expected exception ... was not thrown"; catching the expected
                     // type pops it. Control transfers out of the body (return/break/continue) and nesting
                     // inside another protected region decline (the try arm's conservative discipline).
                if (_nodes.ChildCount(idx) != 1 || _inProtectedRegion || _inFinallyRegion)
                    return false;
                if (!TryResolveBclExceptionType(Text(idx), out var expectedExceptionType))
                    return false;
                var assertThrowsBody = Child(idx, 0);
                if (ContainsReturnStatement(assertThrowsBody) || ContainsControlTransfer(assertThrowsBody))
                    return false;
                // A missed-flag local set after the body keeps the failure throw OUTSIDE the
                // protected region (the legacy emitter threw inside the try, so an expected type of
                // InvalidOperationException swallowed its own failure signal — a false pass).
                var assertThrowsMissed = _il.DeclareLocal(typeof(bool));
                _il.Emit(OpCodes.Ldc_I4_0);
                _il.Emit(OpCodes.Stloc, assertThrowsMissed);
                _il.BeginExceptionBlock();
                _inProtectedRegion = true;
                var assertThrowsBodyOk = EmitStatement(assertThrowsBody);
                _inProtectedRegion = false;
                if (!assertThrowsBodyOk)
                    return false;
                _il.Emit(OpCodes.Ldc_I4_1);
                _il.Emit(OpCodes.Stloc, assertThrowsMissed);
                _il.BeginCatchBlock(expectedExceptionType);
                _il.Emit(OpCodes.Pop);
                _il.EndExceptionBlock();
                var assertThrowsOk = _il.DefineLabel();
                _il.Emit(OpCodes.Ldloc, assertThrowsMissed);
                _il.Emit(OpCodes.Brfalse, assertThrowsOk);
                _il.Emit(OpCodes.Ldstr, "Expected exception of type " + expectedExceptionType.Name + " was not thrown");
                _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                _il.Emit(OpCodes.Throw);
                _il.MarkLabel(assertThrowsOk);
                return true;
            }

            default:
                return Decline(
                    "emit.statement.unhandled-kind",
                    "unsupported statement (node kind " + _nodes.Kind(idx).ToString() + ")",
                    idx);
        }
    }

    // default(T) on the stack: null for reference types, ldc zero for the primitive scalars,
    // initobj through a temp for other value types.
    private bool TryEmitDefaultValue(Type type)
    {
        if (!type.IsValueType)
        {
            _il.Emit(OpCodes.Ldnull);
            return true;
        }
        if (type == typeof(int) || type == typeof(bool) || type == typeof(char)
            || type == typeof(byte) || type == typeof(sbyte) || type == typeof(short) || type == typeof(ushort)
            || type == typeof(uint))
        {
            _il.Emit(OpCodes.Ldc_I4_0);
            return true;
        }
        if (type == typeof(long) || type == typeof(ulong))
        {
            _il.Emit(OpCodes.Ldc_I8, 0L);
            return true;
        }
        if (type == typeof(double))
        {
            _il.Emit(OpCodes.Ldc_R8, 0.0);
            return true;
        }
        if (type == typeof(float))
        {
            _il.Emit(OpCodes.Ldc_R4, 0.0f);
            return true;
        }
        if (type is TypeBuilder || ContainsBuilderBoundType(type))
        {
            var builderTemp = _il.DeclareLocal(type);
            _il.Emit(OpCodes.Ldloca, builderTemp);
            _il.Emit(OpCodes.Initobj, type);
            _il.Emit(OpCodes.Ldloc, builderTemp);
            return true;
        }
        var temp = _il.DeclareLocal(type);
        _il.Emit(OpCodes.Ldloca, temp);
        _il.Emit(OpCodes.Initobj, type);
        _il.Emit(OpCodes.Ldloc, temp);
        return true;
    }

    // Whether the subtree rooted at `idx` contains a direct break/continue (kinds 21/22) anywhere —
    // used by regions that cannot route transfers across their boundary (assert throws).
    private bool ContainsControlTransfer(int idx)
    {
        if (_nodes.Kind(idx) is 21 or 22)
            return true;
        for (var c = 0; c < _nodes.ChildCount(idx); c++)
        {
            if (ContainsControlTransfer(Child(idx, c)))
                return true;
        }
        return false;
    }

    // Phase P-1 (columnar): canonical counted integer reduction lowering for
    // the columnar node tables, without materializing the object AST. The matched loop is:
    //   while i < bound { acc = acc + a[i]; i = i + 1 }
    // or, after the for initializer has already executed:
    //   for i := start; i < bound; i++ { acc = acc + a[i] }
    // and the lowering is:
    //   acc += SimdReductions.Sum...(a, i, bound); i = max(i, bound)
    // False positives must be impossible; a non-match simply falls through to the scalar loop.
    private bool TryEmitVectorizedReductionWhile(int whileNode)
    {
        if (!TryMatchWhileReduction(whileNode, out var shape))
            return false;
        return EmitVectorizedReduction(shape);
    }

    private bool TryEmitVectorizedReductionFor(int conditionNode, int iteratorStatementNode, int bodyNode)
    {
        if (!TryMatchForReduction(conditionNode, iteratorStatementNode, bodyNode, out var shape))
            return false;
        return EmitVectorizedReduction(shape);
    }

    private bool TryMatchWhileReduction(int whileNode, out ColumnarReductionShape shape)
    {
        shape = null!;
        if (_nodes.ChildCount(whileNode) != 2)
            return false;
        if (!TryMatchReductionCondition(Child(whileNode, 0), out var indexNode, out var indexName, out var boundNode))
            return false;

        var body = Child(whileNode, 1);
        if (_nodes.Kind(body) != 25 || _nodes.ChildCount(body) != 2)
            return false;
        if (!TryGetExpressionStatementExpression(Child(body, 0), out var update)
            || !TryGetExpressionStatementExpression(Child(body, 1), out var increment))
            return false;
        if (!TryMatchReductionUpdate(update, indexName, out var accumulatorNode, out var accumulatorName, out var arrayNode, out var arrayName))
            return false;
        // The while-form detector accepts assignment-style increments here; postfix ++ is a
        // for-iterator surface in the current corpus and is kept out of this mirror.
        if (!TryMatchUnitIndexIncrement(increment, indexName, allowPostfix: false))
            return false;
        return TryBuildReductionShape(accumulatorNode, arrayNode, indexNode, boundNode, accumulatorName, arrayName, indexName, out shape);
    }

    private bool TryMatchForReduction(int conditionNode, int iteratorStatementNode, int bodyNode, out ColumnarReductionShape shape)
    {
        shape = null!;
        if (!TryMatchReductionCondition(conditionNode, out var indexNode, out var indexName, out var boundNode))
            return false;
        if (!TryGetExpressionStatementExpression(iteratorStatementNode, out var iterator)
            || !TryMatchUnitIndexIncrement(iterator, indexName, allowPostfix: true))
            return false;
        if (!TryGetSingleReductionBodyStatement(bodyNode, out var bodyStatement)
            || !TryGetExpressionStatementExpression(bodyStatement, out var update))
            return false;
        if (!TryMatchReductionUpdate(update, indexName, out var accumulatorNode, out var accumulatorName, out var arrayNode, out var arrayName))
            return false;
        return TryBuildReductionShape(accumulatorNode, arrayNode, indexNode, boundNode, accumulatorName, arrayName, indexName, out shape);
    }

    private bool TryBuildReductionShape(
        int accumulatorNode, int arrayNode, int indexNode, int boundNode,
        string accumulatorName, string arrayName, string indexName,
        out ColumnarReductionShape shape)
    {
        shape = null!;
        if (accumulatorName == arrayName || accumulatorName == indexName || arrayName == indexName)
            return false;
        if (BoundReadsIdentifier(boundNode, accumulatorName))
            return false;
        if (!TryGetPureLocalOrParameterType(accumulatorNode, out _, out var accumulatorType)
            || !TryGetPureLocalOrParameterType(arrayNode, out _, out var arrayType)
            || !TryGetPureLocalOrParameterType(indexNode, out _, out var indexType))
            return false;
        if (indexType != typeof(int) || !arrayType.IsSZArray)
            return false;
        var elementType = arrayType.GetElementType()!;
        var helper = ReductionHelperForColumnarElementType(elementType);
        if (helper == null || accumulatorType != elementType)
            return false;
        if (!IsSideEffectFreeInt32Bound(boundNode, indexName))
            return false;

        shape = new ColumnarReductionShape(
            accumulatorNode, arrayNode, indexNode, boundNode,
            accumulatorName, arrayName, indexName, elementType, helper);
        return true;
    }

    private bool EmitVectorizedReduction(ColumnarReductionShape shape)
    {
        var boundLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.BoundNode, out var boundType) || boundType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, boundLocal);

        // acc = acc + Sum...(array, index, bound)
        if (!EmitExpression(shape.AccumulatorNode, out var accumulatorType) || accumulatorType != shape.ElementType)
            return false;
        if (!EmitExpression(shape.ArrayNode, out var arrayType) || !arrayType.IsSZArray || arrayType.GetElementType() != shape.ElementType)
            return false;
        if (!EmitExpression(shape.IndexNode, out var indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        _il.Emit(OpCodes.Call, shape.Helper);
        _il.Emit(OpCodes.Add);
        if (!StoreReductionIdentifier(shape.Accumulator))
            return false;

        // The scalar loop exits with index == max(start, bound), not unconditionally bound (empty /
        // negative ranges leave the index unchanged). Preserve that observable post-loop value.
        if (!EmitExpression(shape.IndexNode, out indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _il.DefineLabel();
        _il.Emit(OpCodes.Bge, keepIndexLabel);
        _il.Emit(OpCodes.Ldloc, boundLocal);
        if (!StoreReductionIdentifier(shape.Index))
            return false;
        _il.MarkLabel(keepIndexLabel);
        return true;
    }

    private static MethodInfo? ReductionHelperForColumnarElementType(Type elementType)
    {
        if (elementType == typeof(int)) return s_sumInt32Reduction;
        if (elementType == typeof(uint)) return s_sumUInt32Reduction;
        if (elementType == typeof(long)) return s_sumInt64Reduction;
        if (elementType == typeof(ulong)) return s_sumUInt64Reduction;
        return null;
    }

    // Phase P-2 (columnar): masked-SIMD range-predicate count lowering for the
    // columnar node tables. The matched loop is:
    //   [value := a[i]]
    //   if subject >= lo && subject <= hi { count++ }
    // with a unit-stride counted loop around it. The lowering is:
    //   count += SimdReductions.CountInRangeInt32(array, index, bound, lo, hi); index = max(index, bound)
    private bool TryEmitVectorizedRangeCountWhile(int whileNode)
    {
        if (!TryMatchWhileRangeCount(whileNode, out var shape))
            return false;
        return EmitVectorizedRangeCount(shape);
    }

    private bool TryEmitVectorizedRangeCountFor(int conditionNode, int iteratorStatementNode, int bodyNode)
    {
        if (!TryMatchForRangeCount(conditionNode, iteratorStatementNode, bodyNode, out var shape))
            return false;
        return EmitVectorizedRangeCount(shape);
    }

    private bool TryMatchWhileRangeCount(int whileNode, out ColumnarRangeCountShape shape)
    {
        shape = null!;
        if (_nodes.ChildCount(whileNode) != 2)
            return false;
        if (!TryMatchReductionCondition(Child(whileNode, 0), out var indexNode, out var indexName, out var boundNode))
            return false;

        var body = Child(whileNode, 1);
        if (_nodes.Kind(body) != 25)
            return false;

        int tempStatement;
        int ifStatement;
        int incrementStatement;
        switch (_nodes.ChildCount(body))
        {
            case 2:
                tempStatement = -1;
                ifStatement = Child(body, 0);
                incrementStatement = Child(body, 1);
                break;
            case 3:
                tempStatement = Child(body, 0);
                ifStatement = Child(body, 1);
                incrementStatement = Child(body, 2);
                break;
            default:
                return false;
        }

        if (!TryGetExpressionStatementExpression(incrementStatement, out var increment)
            || !TryMatchUnitIndexIncrement(increment, indexName, allowPostfix: true))
            return false;
        return TryMatchRangeCountBody(tempStatement, ifStatement, indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchForRangeCount(int conditionNode, int iteratorStatementNode, int bodyNode, out ColumnarRangeCountShape shape)
    {
        shape = null!;
        if (!TryMatchReductionCondition(conditionNode, out var indexNode, out var indexName, out var boundNode))
            return false;
        if (!TryGetExpressionStatementExpression(iteratorStatementNode, out var iterator)
            || !TryMatchUnitIndexIncrement(iterator, indexName, allowPostfix: true))
            return false;

        int tempStatement;
        int ifStatement;
        if (_nodes.Kind(bodyNode) == 27)
        {
            tempStatement = -1;
            ifStatement = bodyNode;
        }
        else if (_nodes.Kind(bodyNode) == 25 && _nodes.ChildCount(bodyNode) == 1)
        {
            tempStatement = -1;
            ifStatement = Child(bodyNode, 0);
        }
        else if (_nodes.Kind(bodyNode) == 25 && _nodes.ChildCount(bodyNode) == 2)
        {
            tempStatement = Child(bodyNode, 0);
            ifStatement = Child(bodyNode, 1);
        }
        else
        {
            return false;
        }

        return TryMatchRangeCountBody(tempStatement, ifStatement, indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchRangeCountBody(
        int tempStatementNode, int ifStatementNode, int indexNode, string indexName, int boundNode,
        out ColumnarRangeCountShape shape)
    {
        shape = null!;
        if (_nodes.Kind(ifStatementNode) != 27 || _nodes.ChildCount(ifStatementNode) != 2)
            return false;
        var predicate = Child(ifStatementNode, 0);
        if (_nodes.Kind(predicate) != 12 || _nodes.ChildCount(predicate) != 2 || Text(predicate) != "&&")
            return false;
        var ge = Child(predicate, 0);
        var le = Child(predicate, 1);
        if (_nodes.Kind(ge) != 12 || _nodes.ChildCount(ge) != 2 || Text(ge) != ">="
            || _nodes.Kind(le) != 12 || _nodes.ChildCount(le) != 2 || Text(le) != "<=")
            return false;

        int arrayNode;
        string arrayName;
        string? tempName = null;
        if (tempStatementNode >= 0)
        {
            if (_nodes.Kind(tempStatementNode) != 24 || _nodes.ChildCount(tempStatementNode) != 1)
                return false;
            tempName = Text(tempStatementNode);
            if (IsVisibleBindingName(tempName))
                return false;
            if (!TryMatchArrayIndexByIdentifier(Child(tempStatementNode, 0), indexName, out arrayNode, out arrayName))
                return false;
            if (!TryGetIdentifierName(Child(ge, 0), out var geSubject) || geSubject != tempName)
                return false;
            if (!TryGetIdentifierName(Child(le, 0), out var leSubject) || leSubject != tempName)
                return false;
        }
        else
        {
            if (!TryMatchArrayIndexByIdentifier(Child(ge, 0), indexName, out arrayNode, out arrayName))
                return false;
            if (!TryMatchArrayIndexByIdentifier(Child(le, 0), indexName, out _, out var secondArrayName)
                || secondArrayName != arrayName)
                return false;
        }

        var loNode = Child(ge, 1);
        var hiNode = Child(le, 1);
        if (!TryGetSingleRangeBodyStatement(Child(ifStatementNode, 1), out var thenStatement)
            || !TryGetExpressionStatementExpression(thenStatement, out var counterIncrement)
            || !TryMatchUnitCounterIncrement(counterIncrement, out var counterNode, out var counterName))
            return false;

        if (!IsInvariantRangeOperand(loNode, indexName, tempName, counterName)
            || !IsInvariantRangeOperand(hiNode, indexName, tempName, counterName))
            return false;
        if (counterName == arrayName || counterName == indexName || arrayName == indexName)
            return false;
        if (tempName != null && (tempName == counterName || tempName == arrayName || tempName == indexName))
            return false;
        if (BoundReadsIdentifier(boundNode, counterName)
            || (tempName != null && BoundReadsIdentifier(boundNode, tempName)))
            return false;

        return TryBuildRangeCountShape(counterNode, arrayNode, indexNode, boundNode, loNode, hiNode, counterName, indexName, out shape);
    }

    private bool TryBuildRangeCountShape(
        int counterNode, int arrayNode, int indexNode, int boundNode, int loNode, int hiNode,
        string counterName, string indexName,
        out ColumnarRangeCountShape shape)
    {
        shape = null!;
        if (!TryGetPureLocalOrParameterType(counterNode, out _, out var counterType)
            || !TryGetPureLocalOrParameterType(arrayNode, out _, out var arrayType)
            || !TryGetPureLocalOrParameterType(indexNode, out _, out var indexType))
            return false;
        if (counterType != typeof(int) || arrayType != typeof(int[]) || indexType != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(boundNode, indexName)
            || !IsSideEffectFreeInt32Operand(loNode)
            || !IsSideEffectFreeInt32Operand(hiNode))
            return false;

        shape = new ColumnarRangeCountShape(
            counterNode, arrayNode, indexNode, boundNode, loNode, hiNode,
            counterName, indexName);
        return true;
    }

    private bool EmitVectorizedRangeCount(ColumnarRangeCountShape shape)
    {
        var boundLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.BoundNode, out var boundType) || boundType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, boundLocal);

        var loLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.LoNode, out var loType) || loType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, loLocal);

        var hiLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.HiNode, out var hiType) || hiType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, hiLocal);

        // count = count + CountInRangeInt32(array, index, bound, lo, hi)
        if (!EmitExpression(shape.CounterNode, out var counterType) || counterType != typeof(int))
            return false;
        if (!EmitExpression(shape.ArrayNode, out var arrayType) || arrayType != typeof(int[]))
            return false;
        if (!EmitExpression(shape.IndexNode, out var indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        _il.Emit(OpCodes.Ldloc, loLocal);
        _il.Emit(OpCodes.Ldloc, hiLocal);
        _il.Emit(OpCodes.Call, s_countInRangeInt32);
        _il.Emit(OpCodes.Add);
        if (!StoreReductionIdentifier(shape.Counter))
            return false;

        if (!EmitExpression(shape.IndexNode, out indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _il.DefineLabel();
        _il.Emit(OpCodes.Bge, keepIndexLabel);
        _il.Emit(OpCodes.Ldloc, boundLocal);
        if (!StoreReductionIdentifier(shape.Index))
            return false;
        _il.MarkLabel(keepIndexLabel);
        return true;
    }

    // Phase P-3 (columnar): lane-wise min/max reduction lowering, including the fused
    // single-pass MinMaxInt32 helper for exactly one min and one max reduction over the same int[] scan.
    private bool TryEmitVectorizedMinMaxWhile(int whileNode)
    {
        if (!TryMatchWhileMinMax(whileNode, out var shape))
            return false;
        return EmitVectorizedMinMax(shape);
    }

    private bool TryEmitVectorizedMinMaxFor(int conditionNode, int iteratorStatementNode, int bodyNode)
    {
        if (!TryMatchForMinMax(conditionNode, iteratorStatementNode, bodyNode, out var shape))
            return false;
        return EmitVectorizedMinMax(shape);
    }

    private bool TryMatchWhileMinMax(int whileNode, out ColumnarMinMaxShape shape)
    {
        shape = null!;
        if (_nodes.ChildCount(whileNode) != 2)
            return false;
        if (!TryMatchReductionCondition(Child(whileNode, 0), out var indexNode, out var indexName, out var boundNode))
            return false;

        var body = Child(whileNode, 1);
        if (_nodes.Kind(body) != 25 || _nodes.ChildCount(body) < 2)
            return false;
        var incrementStatement = Child(body, _nodes.ChildCount(body) - 1);
        if (!TryGetExpressionStatementExpression(incrementStatement, out var increment)
            || !TryMatchUnitIndexIncrement(increment, indexName, allowPostfix: true))
            return false;

        var statements = new int[_nodes.ChildCount(body) - 1];
        for (var i = 0; i < statements.Length; i++)
            statements[i] = Child(body, i);
        return TryMatchMinMaxBody(statements, indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchForMinMax(int conditionNode, int iteratorStatementNode, int bodyNode, out ColumnarMinMaxShape shape)
    {
        shape = null!;
        if (!TryMatchReductionCondition(conditionNode, out var indexNode, out var indexName, out var boundNode))
            return false;
        if (!TryGetExpressionStatementExpression(iteratorStatementNode, out var iterator)
            || !TryMatchUnitIndexIncrement(iterator, indexName, allowPostfix: true))
            return false;

        int[] statements;
        if (_nodes.Kind(bodyNode) == 27)
        {
            statements = new[] { bodyNode };
        }
        else if (_nodes.Kind(bodyNode) == 25)
        {
            statements = new int[_nodes.ChildCount(bodyNode)];
            for (var i = 0; i < statements.Length; i++)
                statements[i] = Child(bodyNode, i);
        }
        else
        {
            return false;
        }

        return TryMatchMinMaxBody(statements, indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchMinMaxBody(
        IReadOnlyList<int> statementNodes, int indexNode, string indexName, int boundNode,
        out ColumnarMinMaxShape shape)
    {
        shape = null!;
        if (statementNodes.Count < 1 || statementNodes.Count > 3)
            return false;

        var ifStart = 0;
        string? tempName = null;
        var arrayNode = -1;
        var arrayName = string.Empty;
        if (_nodes.Kind(statementNodes[0]) == 24)
        {
            var tempStatement = statementNodes[0];
            if (_nodes.ChildCount(tempStatement) != 1)
                return false;
            tempName = Text(tempStatement);
            if (IsVisibleBindingName(tempName))
                return false;
            if (!TryMatchArrayIndexByIdentifier(Child(tempStatement, 0), indexName, out arrayNode, out arrayName))
                return false;
            ifStart = 1;
        }

        var ifCount = statementNodes.Count - ifStart;
        if (ifCount < 1 || ifCount > 2)
            return false;

        var reductions = new List<ColumnarMinMaxReduction>(ifCount);
        var seenAccumulators = new HashSet<string>(StringComparer.Ordinal);
        for (var i = ifStart; i < statementNodes.Count; i++)
        {
            if (!TryMatchMinMaxIf(statementNodes[i], indexName, tempName, ref arrayNode, ref arrayName, out var reduction))
                return false;
            if (!seenAccumulators.Add(reduction.Accumulator))
                return false;
            reductions.Add(reduction);
        }

        if (arrayNode < 0 || arrayName == indexName)
            return false;
        if (tempName != null && (tempName == arrayName || tempName == indexName))
            return false;
        foreach (var reduction in reductions)
        {
            if (reduction.Accumulator == arrayName || reduction.Accumulator == indexName || reduction.Accumulator == tempName)
                return false;
            if (BoundReadsIdentifier(boundNode, reduction.Accumulator))
                return false;
        }
        if (tempName != null && BoundReadsIdentifier(boundNode, tempName))
            return false;

        return TryBuildMinMaxShape(arrayNode, indexNode, boundNode, indexName, reductions, out shape);
    }

    private bool TryMatchMinMaxIf(
        int ifStatementNode, string indexName, string? tempName, ref int arrayNode, ref string arrayName,
        out ColumnarMinMaxReduction reduction)
    {
        reduction = null!;
        if (_nodes.Kind(ifStatementNode) != 27 || _nodes.ChildCount(ifStatementNode) != 2)
            return false;
        if (!TryGetSingleReductionBodyStatement(Child(ifStatementNode, 1), out var thenStatement)
            || !TryGetExpressionStatementExpression(thenStatement, out var assignment)
            || _nodes.Kind(assignment) != 14
            || _nodes.ChildCount(assignment) != 2
            || Text(assignment) != "=")
            return false;
        var accumulatorNode = Child(assignment, 0);
        if (!TryGetIdentifierName(accumulatorNode, out var accumulatorName))
            return false;
        if (!TryMatchMinMaxSubject(Child(assignment, 1), indexName, tempName, ref arrayNode, ref arrayName))
            return false;

        var condition = Child(ifStatementNode, 0);
        if (_nodes.Kind(condition) != 12 || _nodes.ChildCount(condition) != 2 || Text(condition) is not ("<" or ">"))
            return false;
        var left = Child(condition, 0);
        var right = Child(condition, 1);
        var leftIsAccumulator = TryGetIdentifierName(left, out var leftName) && leftName == accumulatorName;
        var rightIsAccumulator = TryGetIdentifierName(right, out var rightName) && rightName == accumulatorName;
        var leftIsSubject = IsMinMaxSubject(left, indexName, tempName, arrayName);
        var rightIsSubject = IsMinMaxSubject(right, indexName, tempName, arrayName);

        bool isMin;
        if (leftIsSubject && rightIsAccumulator)
            isMin = Text(condition) == "<";
        else if (leftIsAccumulator && rightIsSubject)
            isMin = Text(condition) == ">";
        else
            return false;

        reduction = new ColumnarMinMaxReduction(accumulatorNode, accumulatorName, isMin);
        return true;
    }

    private bool TryMatchMinMaxSubject(int node, string indexName, string? tempName, ref int arrayNode, ref string arrayName)
    {
        if (tempName != null)
            return TryGetIdentifierName(node, out var name) && name == tempName;
        if (!TryMatchArrayIndexByIdentifier(node, indexName, out var candidateArrayNode, out var candidateArrayName))
            return false;
        if (arrayNode < 0)
        {
            arrayNode = candidateArrayNode;
            arrayName = candidateArrayName;
            return true;
        }

        return candidateArrayName == arrayName;
    }

    private bool IsMinMaxSubject(int node, string indexName, string? tempName, string arrayName)
    {
        if (tempName != null)
            return TryGetIdentifierName(node, out var name) && name == tempName;
        return TryMatchArrayIndexByIdentifier(node, indexName, out _, out var candidateArrayName)
               && candidateArrayName == arrayName;
    }

    private bool TryBuildMinMaxShape(
        int arrayNode, int indexNode, int boundNode, string indexName,
        IReadOnlyList<ColumnarMinMaxReduction> reductions,
        out ColumnarMinMaxShape shape)
    {
        shape = null!;
        if (!TryGetPureLocalOrParameterType(arrayNode, out _, out var arrayType)
            || !TryGetPureLocalOrParameterType(indexNode, out _, out var indexType))
            return false;
        if (arrayType != typeof(int[]) || indexType != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(boundNode, indexName))
            return false;
        foreach (var reduction in reductions)
        {
            if (!TryGetPureLocalOrParameterType(reduction.AccumulatorNode, out _, out var accumulatorType)
                || accumulatorType != typeof(int))
                return false;
        }

        shape = new ColumnarMinMaxShape(arrayNode, indexNode, boundNode, indexName, reductions);
        return true;
    }

    private bool EmitVectorizedMinMax(ColumnarMinMaxShape shape)
    {
        var boundLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.BoundNode, out var boundType) || boundType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, boundLocal);

        if (TryGetMinMaxPair(shape.Reductions, out var minReduction, out var maxReduction))
        {
            var tupleLocal = _il.DeclareLocal(typeof(ValueTuple<int, int>));
            if (!EmitExpression(shape.ArrayNode, out var arrayType) || arrayType != typeof(int[]))
                return false;
            if (!EmitExpression(shape.IndexNode, out var indexType) || indexType != typeof(int))
                return false;
            _il.Emit(OpCodes.Ldloc, boundLocal);
            if (!EmitExpression(minReduction.AccumulatorNode, out var minType) || minType != typeof(int))
                return false;
            if (!EmitExpression(maxReduction.AccumulatorNode, out var maxType) || maxType != typeof(int))
                return false;
            _il.Emit(OpCodes.Call, s_minMaxInt32Reduction);
            _il.Emit(OpCodes.Stloc, tupleLocal);

            _il.Emit(OpCodes.Ldloca, tupleLocal);
            _il.Emit(OpCodes.Ldfld, s_valueTupleItem1);
            if (!StoreReductionIdentifier(minReduction.Accumulator))
                return false;
            _il.Emit(OpCodes.Ldloca, tupleLocal);
            _il.Emit(OpCodes.Ldfld, s_valueTupleItem2);
            if (!StoreReductionIdentifier(maxReduction.Accumulator))
                return false;
        }
        else
        {
            foreach (var reduction in shape.Reductions)
            {
                if (!EmitExpression(shape.ArrayNode, out var arrayType) || arrayType != typeof(int[]))
                    return false;
                if (!EmitExpression(shape.IndexNode, out var indexType) || indexType != typeof(int))
                    return false;
                _il.Emit(OpCodes.Ldloc, boundLocal);
                if (!EmitExpression(reduction.AccumulatorNode, out var accumulatorType) || accumulatorType != typeof(int))
                    return false;
                _il.Emit(OpCodes.Call, reduction.IsMin ? s_minInt32Reduction : s_maxInt32Reduction);
                if (!StoreReductionIdentifier(reduction.Accumulator))
                    return false;
            }
        }

        if (!EmitExpression(shape.IndexNode, out var terminalIndexType) || terminalIndexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _il.DefineLabel();
        _il.Emit(OpCodes.Bge, keepIndexLabel);
        _il.Emit(OpCodes.Ldloc, boundLocal);
        if (!StoreReductionIdentifier(shape.Index))
            return false;
        _il.MarkLabel(keepIndexLabel);
        return true;
    }

    private static bool TryGetMinMaxPair(
        IReadOnlyList<ColumnarMinMaxReduction> reductions,
        out ColumnarMinMaxReduction min,
        out ColumnarMinMaxReduction max)
    {
        min = null!;
        max = null!;
        if (reductions.Count != 2 || reductions[0].IsMin == reductions[1].IsMin)
            return false;
        min = reductions[0].IsMin ? reductions[0] : reductions[1];
        max = reductions[0].IsMin ? reductions[1] : reductions[0];
        return true;
    }

    // Phase P-4 (columnar): shifted-compare adjacent-transition count lowering.
    // The matched body is exactly:
    //   current := a[i]
    //   if current != previous { count++ }
    //   previous = current
    // and the helper restores both count and the carried previous value.
    private bool TryEmitVectorizedCountTransitionsWhile(int whileNode)
    {
        if (!TryMatchWhileCountTransitions(whileNode, out var shape))
            return false;
        return EmitVectorizedCountTransitions(shape);
    }

    private bool TryEmitVectorizedCountTransitionsFor(int conditionNode, int iteratorStatementNode, int bodyNode)
    {
        if (!TryMatchForCountTransitions(conditionNode, iteratorStatementNode, bodyNode, out var shape))
            return false;
        return EmitVectorizedCountTransitions(shape);
    }

    private bool TryMatchWhileCountTransitions(int whileNode, out ColumnarCountTransitionsShape shape)
    {
        shape = null!;
        if (_nodes.ChildCount(whileNode) != 2)
            return false;
        if (!TryMatchReductionCondition(Child(whileNode, 0), out var indexNode, out var indexName, out var boundNode))
            return false;
        var body = Child(whileNode, 1);
        if (_nodes.Kind(body) != 25 || _nodes.ChildCount(body) != 4)
            return false;
        if (!TryGetExpressionStatementExpression(Child(body, 3), out var increment)
            || !TryMatchUnitIndexIncrement(increment, indexName, allowPostfix: true))
            return false;
        return TryMatchCountTransitionsBody(Child(body, 0), Child(body, 1), Child(body, 2), indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchForCountTransitions(int conditionNode, int iteratorStatementNode, int bodyNode, out ColumnarCountTransitionsShape shape)
    {
        shape = null!;
        if (!TryMatchReductionCondition(conditionNode, out var indexNode, out var indexName, out var boundNode))
            return false;
        if (!TryGetExpressionStatementExpression(iteratorStatementNode, out var iterator)
            || !TryMatchUnitIndexIncrement(iterator, indexName, allowPostfix: true))
            return false;
        if (_nodes.Kind(bodyNode) != 25 || _nodes.ChildCount(bodyNode) != 3)
            return false;
        return TryMatchCountTransitionsBody(Child(bodyNode, 0), Child(bodyNode, 1), Child(bodyNode, 2), indexNode, indexName, boundNode, out shape);
    }

    private bool TryMatchCountTransitionsBody(
        int tempStatementNode, int ifStatementNode, int carryStatementNode, int indexNode, string indexName, int boundNode,
        out ColumnarCountTransitionsShape shape)
    {
        shape = null!;

        if (_nodes.Kind(tempStatementNode) != 24 || _nodes.ChildCount(tempStatementNode) != 1)
            return false;
        var currentName = Text(tempStatementNode);
        if (IsVisibleBindingName(currentName))
            return false;
        if (!TryMatchArrayIndexByIdentifier(Child(tempStatementNode, 0), indexName, out var arrayNode, out var arrayName))
            return false;

        if (_nodes.Kind(ifStatementNode) != 27 || _nodes.ChildCount(ifStatementNode) != 2)
            return false;
        var condition = Child(ifStatementNode, 0);
        if (_nodes.Kind(condition) != 12 || _nodes.ChildCount(condition) != 2 || Text(condition) != "!=")
            return false;
        if (!TryResolvePreviousForTransition(condition, currentName, out var previousNode, out var previousName))
            return false;
        if (!TryGetSingleReductionBodyStatement(Child(ifStatementNode, 1), out var thenStatement)
            || !TryGetExpressionStatementExpression(thenStatement, out var counterIncrement)
            || !TryMatchUnitCounterIncrement(counterIncrement, out var counterNode, out var counterName))
            return false;

        if (!TryGetExpressionStatementExpression(carryStatementNode, out var carry)
            || _nodes.Kind(carry) != 14
            || _nodes.ChildCount(carry) != 2
            || Text(carry) != "="
            || !TryGetIdentifierName(Child(carry, 0), out var carryTarget)
            || carryTarget != previousName
            || !TryGetIdentifierName(Child(carry, 1), out var carryValue)
            || carryValue != currentName)
            return false;

        if (!AllDistinct(counterName, arrayName, indexName, previousName, currentName))
            return false;
        if (BoundReadsIdentifier(boundNode, counterName)
            || BoundReadsIdentifier(boundNode, previousName)
            || BoundReadsIdentifier(boundNode, currentName))
            return false;

        return TryBuildCountTransitionsShape(counterNode, arrayNode, indexNode, previousNode, boundNode, counterName, indexName, previousName, out shape);
    }

    private bool TryResolvePreviousForTransition(int compareNode, string currentName, out int previousNode, out string previousName)
    {
        previousNode = -1;
        previousName = string.Empty;
        var left = Child(compareNode, 0);
        var right = Child(compareNode, 1);
        if (TryGetIdentifierName(left, out var leftName) && leftName == currentName
            && TryGetIdentifierName(right, out previousName))
        {
            previousNode = right;
            return true;
        }
        if (TryGetIdentifierName(right, out var rightName) && rightName == currentName
            && TryGetIdentifierName(left, out previousName))
        {
            previousNode = left;
            return true;
        }

        return false;
    }

    private static bool AllDistinct(string a, string b, string c, string d, string e)
        => a != b && a != c && a != d && a != e
           && b != c && b != d && b != e
           && c != d && c != e
           && d != e;

    private bool TryBuildCountTransitionsShape(
        int counterNode, int arrayNode, int indexNode, int previousNode, int boundNode,
        string counterName, string indexName, string previousName,
        out ColumnarCountTransitionsShape shape)
    {
        shape = null!;
        if (!TryGetPureLocalOrParameterType(counterNode, out _, out var counterType)
            || !TryGetPureLocalOrParameterType(arrayNode, out _, out var arrayType)
            || !TryGetPureLocalOrParameterType(indexNode, out _, out var indexType)
            || !TryGetPureLocalOrParameterType(previousNode, out _, out var previousType))
            return false;
        if (counterType != typeof(int) || arrayType != typeof(int[]) || indexType != typeof(int) || previousType != typeof(int))
            return false;
        if (!IsSideEffectFreeInt32Bound(boundNode, indexName))
            return false;

        shape = new ColumnarCountTransitionsShape(
            counterNode, arrayNode, indexNode, previousNode, boundNode,
            counterName, indexName, previousName);
        return true;
    }

    private bool EmitVectorizedCountTransitions(ColumnarCountTransitionsShape shape)
    {
        var boundLocal = _il.DeclareLocal(typeof(int));
        if (!EmitExpression(shape.BoundNode, out var boundType) || boundType != typeof(int))
            return false;
        _il.Emit(OpCodes.Stloc, boundLocal);

        var tupleLocal = _il.DeclareLocal(typeof(ValueTuple<int, int>));
        if (!EmitExpression(shape.ArrayNode, out var arrayType) || arrayType != typeof(int[]))
            return false;
        if (!EmitExpression(shape.IndexNode, out var indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        if (!EmitExpression(shape.PreviousNode, out var previousType) || previousType != typeof(int))
            return false;
        _il.Emit(OpCodes.Call, s_countTransitionsInt32);
        _il.Emit(OpCodes.Stloc, tupleLocal);

        if (!EmitExpression(shape.CounterNode, out var counterType) || counterType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloca, tupleLocal);
        _il.Emit(OpCodes.Ldfld, s_valueTupleItem1);
        _il.Emit(OpCodes.Add);
        if (!StoreReductionIdentifier(shape.Counter))
            return false;

        _il.Emit(OpCodes.Ldloca, tupleLocal);
        _il.Emit(OpCodes.Ldfld, s_valueTupleItem2);
        if (!StoreReductionIdentifier(shape.Previous))
            return false;

        if (!EmitExpression(shape.IndexNode, out indexType) || indexType != typeof(int))
            return false;
        _il.Emit(OpCodes.Ldloc, boundLocal);
        var keepIndexLabel = _il.DefineLabel();
        _il.Emit(OpCodes.Bge, keepIndexLabel);
        _il.Emit(OpCodes.Ldloc, boundLocal);
        if (!StoreReductionIdentifier(shape.Index))
            return false;
        _il.MarkLabel(keepIndexLabel);
        return true;
    }

    private bool TryMatchReductionCondition(int conditionNode, out int indexNode, out string indexName, out int boundNode)
    {
        indexNode = -1;
        indexName = string.Empty;
        boundNode = -1;
        if (_nodes.Kind(conditionNode) != 12 || _nodes.ChildCount(conditionNode) != 2 || Text(conditionNode) != "<")
            return false;
        var left = Child(conditionNode, 0);
        var right = Child(conditionNode, 1);
        if (!TryGetIdentifierName(left, out indexName))
            return false;
        if (!IsSideEffectFreeInt32Bound(right, indexName))
            return false;
        indexNode = left;
        boundNode = right;
        return true;
    }

    private bool TryMatchReductionUpdate(
        int updateNode, string indexName,
        out int accumulatorNode, out string accumulatorName, out int arrayNode, out string arrayName)
    {
        accumulatorNode = -1;
        accumulatorName = string.Empty;
        arrayNode = -1;
        arrayName = string.Empty;
        if (_nodes.Kind(updateNode) != 14 || _nodes.ChildCount(updateNode) != 2)
            return false;
        var target = Child(updateNode, 0);
        if (!TryGetIdentifierName(target, out accumulatorName))
            return false;

        var op = Text(updateNode);
        if (op == "=")
        {
            var value = Child(updateNode, 1);
            if (_nodes.Kind(value) != 12 || _nodes.ChildCount(value) != 2 || Text(value) != "+")
                return false;
            var left = Child(value, 0);
            var right = Child(value, 1);
            if (!TryGetIdentifierName(left, out var leftName) || leftName != accumulatorName)
                return false;
            if (!TryMatchArrayIndexByIdentifier(right, indexName, out arrayNode, out arrayName))
                return false;
        }
        else if (op == "+=")
        {
            if (!TryMatchArrayIndexByIdentifier(Child(updateNode, 1), indexName, out arrayNode, out arrayName))
                return false;
        }
        else
        {
            return false;
        }

        accumulatorNode = target;
        return true;
    }

    private bool TryMatchArrayIndexByIdentifier(int node, string indexName, out int arrayNode, out string arrayName)
    {
        arrayNode = -1;
        arrayName = string.Empty;
        if (_nodes.Kind(node) != 10 || _nodes.ChildCount(node) != 2)
            return false;
        var receiver = Child(node, 0);
        var index = Child(node, 1);
        if (!TryGetIdentifierName(receiver, out arrayName)
            || !TryGetIdentifierName(index, out var actualIndex)
            || actualIndex != indexName)
            return false;
        arrayNode = receiver;
        return true;
    }

    private bool TryMatchUnitIndexIncrement(int node, string indexName, bool allowPostfix)
    {
        if (_nodes.Kind(node) == 14 && _nodes.ChildCount(node) == 2)
        {
            var target = Child(node, 0);
            if (!TryGetIdentifierName(target, out var targetName) || targetName != indexName)
                return false;
            var op = Text(node);
            if (op == "+=")
                return IsLiteralOne(Child(node, 1));
            if (op != "=")
                return false;
            var value = Child(node, 1);
            return _nodes.Kind(value) == 12
                && _nodes.ChildCount(value) == 2
                && Text(value) == "+"
                && TryGetIdentifierName(Child(value, 0), out var leftName)
                && leftName == indexName
                && IsLiteralOne(Child(value, 1));
        }

        if (allowPostfix && _nodes.Kind(node) == 44 && _nodes.ChildCount(node) == 1 && Text(node) == "++")
            return TryGetIdentifierName(Child(node, 0), out var targetName) && targetName == indexName;

        return false;
    }

    private bool TryGetExpressionStatementExpression(int statementNode, out int expressionNode)
    {
        expressionNode = -1;
        if (_nodes.Kind(statementNode) != 23 || _nodes.ChildCount(statementNode) != 1)
            return false;
        expressionNode = Child(statementNode, 0);
        return true;
    }

    private bool TryGetSingleReductionBodyStatement(int bodyNode, out int statementNode)
    {
        statementNode = -1;
        if (_nodes.Kind(bodyNode) == 25)
        {
            if (_nodes.ChildCount(bodyNode) != 1)
                return false;
            statementNode = Child(bodyNode, 0);
            return true;
        }

        if (_nodes.Kind(bodyNode) == 23)
        {
            statementNode = bodyNode;
            return true;
        }

        return false;
    }

    private bool TryMatchUnitCounterIncrement(int node, out int counterNode, out string counterName)
    {
        counterNode = -1;
        counterName = string.Empty;
        if (_nodes.Kind(node) == 44 && _nodes.ChildCount(node) == 1 && Text(node) == "++")
        {
            var target = Child(node, 0);
            if (!TryGetIdentifierName(target, out counterName))
                return false;
            counterNode = target;
            return true;
        }

        if (_nodes.Kind(node) != 14 || _nodes.ChildCount(node) != 2)
            return false;
        var assignmentTarget = Child(node, 0);
        if (!TryGetIdentifierName(assignmentTarget, out counterName))
            return false;
        var op = Text(node);
        if (op == "+=")
        {
            if (!IsLiteralOne(Child(node, 1)))
                return false;
            counterNode = assignmentTarget;
            return true;
        }
        if (op != "=")
            return false;
        var value = Child(node, 1);
        if (_nodes.Kind(value) != 12
            || _nodes.ChildCount(value) != 2
            || Text(value) != "+"
            || !TryGetIdentifierName(Child(value, 0), out var leftName)
            || leftName != counterName
            || !IsLiteralOne(Child(value, 1)))
            return false;
        counterNode = assignmentTarget;
        return true;
    }

    private bool TryGetSingleRangeBodyStatement(int bodyNode, out int statementNode)
        => TryGetSingleReductionBodyStatement(bodyNode, out statementNode);

    private bool IsInvariantRangeOperand(int node, string indexName, string? tempName, string counterName)
    {
        if (TryGetIdentifierName(node, out var name))
            return name != indexName && name != counterName && name != tempName;
        return IsInt32Literal(node);
    }

    private bool IsSideEffectFreeInt32Bound(int node, string indexName)
    {
        if (TryGetIdentifierName(node, out var name))
        {
            if (name == indexName)
                return false;
            return TryGetPureLocalOrParameterType(node, out _, out var type) && type == typeof(int);
        }
        if (IsInt32Literal(node))
            return true;
        if (_nodes.Kind(node) == 8 && _nodes.ChildCount(node) == 1 && Text(node) == "Length")
        {
            var receiver = Child(node, 0);
            return TryGetPureLocalOrParameterType(receiver, out _, out var receiverType) && receiverType.IsSZArray;
        }

        return false;
    }

    private bool IsSideEffectFreeInt32Operand(int node)
    {
        if (TryGetIdentifierName(node, out _))
            return TryGetPureLocalOrParameterType(node, out _, out var type) && type == typeof(int);
        return IsInt32Literal(node);
    }

    private bool BoundReadsIdentifier(int node, string name)
    {
        if (TryGetIdentifierName(node, out var id))
            return id == name;
        return _nodes.Kind(node) == 8
            && _nodes.ChildCount(node) == 1
            && Text(node) == "Length"
            && TryGetIdentifierName(Child(node, 0), out var receiver)
            && receiver == name;
    }

    private bool TryGetPureLocalOrParameterType(int node, out string name, out Type type)
    {
        type = null!;
        if (!TryGetIdentifierName(node, out name))
            return false;
        if (_liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
            return false;
        if (_locals.TryGetValue(name, out var local))
        {
            type = local.LocalType;
            return true;
        }
        if (_paramTypes.TryGetValue(name, out type!))
            return _paramOrdinals.ContainsKey(name);
        return false;
    }

    private bool StoreReductionIdentifier(string name)
    {
        if (_liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
            return false;
        if (_locals.TryGetValue(name, out var local))
        {
            _il.Emit(OpCodes.Stloc, local);
            return true;
        }
        if (_paramOrdinals.TryGetValue(name, out var ordinal))
        {
            EmitStoreArgument(ordinal);
            return true;
        }
        return false;
    }

    private bool TryGetIdentifierName(int node, out string name)
    {
        name = string.Empty;
        if (_nodes.Kind(node) != 6 || _nodes.ValueStart(node) < 0)
            return false;
        name = Text(node);
        return true;
    }

    private bool IsInt32Literal(int node)
        => _nodes.Kind(node) == 0
           && _nodes.ValueStart(node) >= 0
           && Text(node).Length > 0
           && Text(node)[^1] is not ('u' or 'U' or 'l' or 'L' or 'm' or 'M')
           && int.TryParse(Text(node), out _);

    private bool IsLiteralOne(int node)
        => _nodes.Kind(node) == 0 && _nodes.ValueStart(node) >= 0 && Text(node) == "1";

    /// <summary>
    /// Emit an `if`/`while` CONDITION as a bool (i4 0/1) on the stack for a following <c>brfalse</c>/<c>brtrue</c>.
    /// Now that the expression emitter is type-aware, a condition is ANY bool expression — a comparison, a bool
    /// literal/local/param, a bool-returning call, or a logical-not — verified by its reported type, so a
    /// non-bool (e.g. an int) can never reach a branch. Anything that is not statically bool declines.
    /// </summary>
    private bool EmitCondition(int idx)
    {
        if (!EmitExpression(idx, out var type))
        {
            return false;
        }
        if (type != typeof(bool))
        {
            return false;
        }
        return true;
    }

    /// <summary>
    /// Whether this statement always exits via a return — the same columnar subset as the diagnostics pass
    /// (Return; a Block whose any statement returns; an If with an else where both branches return). Used to
    /// guarantee the emitted `if` has no fall-through.
    /// </summary>
    private bool AlwaysReturns(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 20: // Return
            case 48: // Throw — always exits (E1).
                return true;
            case 49: // Try — the analyzer's rule VERBATIM: exits iff the TRY block exits AND there is at
            {        // least ONE catch AND every catch clause's block exits. The FINALLY (a trailing
                     // kind-25 child) is IGNORED — probe-pinned: a zero-catch `try {return} finally {}`
                     // NEVER satisfies always-returns (the pipeline demands a trailing return, NL305).
                if (!AlwaysReturns(Child(idx, 0)))
                    return false;
                var sawCatch = false;
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                {
                    var clause = Child(idx, n);
                    if (_nodes.Kind(clause) != 50)
                        continue; // the finally block — ignored by the analyzer's rule.
                    sawCatch = true;
                    if (!AlwaysReturns(Child(clause, _nodes.ChildCount(clause) - 1)))
                        return false;
                }

                return sawCatch;
            }
            case 25: // Block
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                {
                    if (AlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;
            case 27: // If [cond, then, else?]
                return _nodes.ChildCount(idx) == 3 && AlwaysReturns(Child(idx, 1)) && AlwaysReturns(Child(idx, 2));
            case 51: // Lock [lockee, body] — exits iff the body exits (probe-pinned: `lock s { return 1 }`
                     // with no trailing return satisfies the analyzer).
                return AlwaysReturns(Child(idx, 1));
            default:
                return false;
        }
    }

    // The registered struct/record/class def whose TypeBuilder IS this builder, or null.
    private ColumnarStructDef? FindDefByBuilder(TypeBuilder builder)
    {
        foreach (var d in _structRegistry.Values)
        {
            if (d.Builder == builder)
                return d;
        }

        return null;
    }

    private ColumnarStructDef? FindDefByType(Type type)
        => type is TypeBuilder builder ? FindDefByBuilder(builder) : null;

    // PASS 0e bodies — the legacy emitter's synthesized record members VERBATIM (EmitRecordEquals /
    // EmitRecordGetHashCode / EmitRecordCloneMethod): Equals(object) = null-check + isinst + per-field
    // EqualityComparer<T>.Default.Equals chain; GetHashCode = `hash = 17; hash = hash * 23 +
    // EqualityComparer<T>.Default.GetHashCode(field)`; `<Clone>$` = object.MemberwiseClone + castclass
    // (the FAMILY-access clone wrapper `with` lowers through — calling MemberwiseClone cross-type is
    // unverifiable IL, calling the public wrapper is not). Virtual + matching signatures make
    // Equals/GetHashCode implicit overrides of object's.
    private static void SynthesizeRecordValueMembers(ColumnarStructDef def)
    {
        var tb = def.Builder;
        if (!def.Methods.ContainsKey("Equals"))
        {
            var equals = tb.DefineMethod(
                "Equals", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
                typeof(bool), new[] { typeof(object) });
            var eil = equals.GetILGenerator();
            var returnFalse = eil.DefineLabel();
            var compareFields = eil.DefineLabel();
            eil.Emit(OpCodes.Ldarg_1);
            eil.Emit(OpCodes.Brfalse, returnFalse);
            eil.Emit(OpCodes.Ldarg_1);
            eil.Emit(OpCodes.Isinst, tb);
            eil.Emit(OpCodes.Dup);
            eil.Emit(OpCodes.Brtrue, compareFields);
            eil.Emit(OpCodes.Pop);
            eil.Emit(OpCodes.Br, returnFalse);
            eil.MarkLabel(compareFields);
            var other = eil.DeclareLocal(tb);
            // A boxed VALUE record must unbox before the typed store; a reference record stores the
            // isinst result directly.
            if (!def.IsReference)
                eil.Emit(OpCodes.Unbox_Any, tb);
            eil.Emit(OpCodes.Stloc, other);
            foreach (var fieldName in def.FieldOrder)
            {
                var field = def.Fields[fieldName];
                var comparer = typeof(EqualityComparer<>).MakeGenericType(field.FieldType);
                eil.Emit(OpCodes.Call, comparer.GetProperty(nameof(EqualityComparer<int>.Default))!.GetGetMethod()!);
                eil.Emit(OpCodes.Ldarg_0);
                eil.Emit(OpCodes.Ldfld, field);
                eil.Emit(OpCodes.Ldloc, other);
                eil.Emit(OpCodes.Ldfld, field);
                eil.Emit(OpCodes.Callvirt, comparer.GetMethod(nameof(Equals), new[] { field.FieldType, field.FieldType })!);
                eil.Emit(OpCodes.Brfalse, returnFalse);
            }
            eil.Emit(OpCodes.Ldc_I4_1);
            eil.Emit(OpCodes.Ret);
            eil.MarkLabel(returnFalse);
            eil.Emit(OpCodes.Ldc_I4_0);
            eil.Emit(OpCodes.Ret);
            def.RecordEquals = equals;
        }

        if (!def.Methods.ContainsKey("GetHashCode"))
        {
            var hash = tb.DefineMethod(
                "GetHashCode", MethodAttributes.Public | MethodAttributes.Virtual | MethodAttributes.HideBySig,
                typeof(int), Type.EmptyTypes);
            var hil = hash.GetILGenerator();
            var acc = hil.DeclareLocal(typeof(int));
            hil.Emit(OpCodes.Ldc_I4, 17);
            hil.Emit(OpCodes.Stloc, acc);
            foreach (var fieldName in def.FieldOrder)
            {
                var field = def.Fields[fieldName];
                var comparer = typeof(EqualityComparer<>).MakeGenericType(field.FieldType);
                hil.Emit(OpCodes.Ldloc, acc);
                hil.Emit(OpCodes.Ldc_I4, 23);
                hil.Emit(OpCodes.Mul);
                hil.Emit(OpCodes.Call, comparer.GetProperty(nameof(EqualityComparer<int>.Default))!.GetGetMethod()!);
                hil.Emit(OpCodes.Ldarg_0);
                hil.Emit(OpCodes.Ldfld, field);
                hil.Emit(OpCodes.Callvirt, comparer.GetMethod(nameof(GetHashCode), new[] { field.FieldType })!);
                hil.Emit(OpCodes.Add);
                hil.Emit(OpCodes.Stloc, acc);
            }
            hil.Emit(OpCodes.Ldloc, acc);
            hil.Emit(OpCodes.Ret);
            def.RecordGetHashCode = hash;
        }

        SynthesizeRecordCloneMember(def);
    }

    private static void SynthesizeRecordCloneMember(ColumnarStructDef def)
    {
        if (def.RecordClone != null)
            return;
        var tb = def.Builder;
        var clone = tb.DefineMethod(
            "<Clone>$", MethodAttributes.Public | MethodAttributes.HideBySig,
            tb, Type.EmptyTypes);
        var cil = clone.GetILGenerator();
        if (def.IsReference)
        {
            cil.Emit(OpCodes.Ldarg_0);
            cil.Emit(OpCodes.Call, typeof(object).GetMethod("MemberwiseClone", BindingFlags.Instance | BindingFlags.NonPublic)!);
            cil.Emit(OpCodes.Castclass, tb);
        }
        else
        {
            // A VALUE record clones by loading the value through the byref `this`.
            cil.Emit(OpCodes.Ldarg_0);
            cil.Emit(OpCodes.Ldobj, tb);
        }
        cil.Emit(OpCodes.Ret);
        def.RecordClone = clone;
    }

    // The BCL exception types a typed catch clause may name (E3). Each simple name must resolve to the
    // SAME runtime type the pipeline's ResolveType binds — all are System-namespace exceptions reachable
    // by simple name on the previous baseline path. Anything else declines: the pipeline silently resolves UNKNOWN
    // names to a catch-all (known defect #16) and accepts non-exception types as dead clauses (#17);
    // declining inherits neither wrongness. User-defined exception classes are not modelled (a columnar
    // class cannot derive a BCL base yet).
    // Legacy TestDescriptionToMethodName: PascalCase the description words, keep letters/digits/
    // underscores, prefix Test_ when the result would not start with a letter.
    private static string TestDescriptionToMethodName(string description)
    {
        var words = description.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries);
        var builder = new System.Text.StringBuilder();
        foreach (var word in words)
        {
            builder.Append(char.ToUpper(word[0]));
            builder.Append(word, 1, word.Length - 1);
        }

        var filtered = new System.Text.StringBuilder(builder.Length);
        for (var c = 0; c < builder.Length; c++)
        {
            if (char.IsLetterOrDigit(builder[c]) || builder[c] == '_')
                filtered.Append(builder[c]);
        }

        var result = filtered.ToString();
        if (result.Length == 0 || !char.IsLetter(result[0]))
        {
            result = "Test_" + result;
        }

        return result;
    }

    // Legacy ResolveTestFrameworkType: scan already-loaded assemblies, then load the known
    // test-framework assemblies by simple name. Throws when the type is unreachable — the caller
    // converts that into a decline with a reason.
    private static Type ResolveTestFrameworkType(string fullTypeName, IReadOnlyList<string>? referenceAssemblyPaths, params string[] assemblyNames)
    {
        foreach (var assembly in ExternalAssemblyScan.Loaded())
        {
            var loadedType = assembly.GetType(fullTypeName, throwOnError: false);
            if (loadedType != null)
                return loadedType;
        }

        // The compilation's RESOLVED reference paths carry the restored test-framework assemblies
        // with exact versions — prefer them over name probing so the emitted attribute identity
        // matches what the runner and `dotnet test` restore alongside the test assembly.
        if (referenceAssemblyPaths != null)
        {
            foreach (var referencePath in referenceAssemblyPaths)
            {
                var fileName = Path.GetFileNameWithoutExtension(referencePath);
                if (!fileName.StartsWith("xunit", StringComparison.OrdinalIgnoreCase)
                    && !fileName.StartsWith("nunit", StringComparison.OrdinalIgnoreCase))
                    continue;
                try
                {
                    var loadedType = Assembly.LoadFrom(referencePath).GetType(fullTypeName, throwOnError: false);
                    if (loadedType != null)
                        return loadedType;
                }
                catch
                {
                    // Try the next candidate reference.
                }
            }
        }

        foreach (var assemblyName in assemblyNames)
        {
            try
            {
                var assembly = Assembly.Load(new AssemblyName(assemblyName));
                var loadedType = assembly.GetType(fullTypeName, throwOnError: false);
                if (loadedType != null)
                    return loadedType;
            }
            catch
            {
                // Try the next known test-framework assembly name.
            }
        }

        throw new InvalidOperationException($"Could not resolve required test framework type {fullTypeName}");
    }

    private static bool TryResolveReferencedType(
        IReadOnlyList<string>? referenceAssemblyPaths,
        string assemblySimpleName,
        string fullTypeName,
        out Type type)
    {
        type = null!;
        if (referenceAssemblyPaths == null)
            return false;

        foreach (var referencePath in referenceAssemblyPaths)
        {
            if (!string.Equals(Path.GetFileNameWithoutExtension(referencePath), assemblySimpleName, StringComparison.OrdinalIgnoreCase))
                continue;
            try
            {
                var loadedType = Assembly.LoadFrom(referencePath).GetType(fullTypeName, throwOnError: false);
                if (loadedType != null)
                {
                    type = loadedType;
                    return true;
                }
            }
            catch
            {
                // Try the next resolved reference path.
            }
        }

        return false;
    }

    private static void PreloadSupportedExternalReferenceAssemblies(IReadOnlyList<string>? referenceAssemblyPaths)
    {
        if (referenceAssemblyPaths == null)
            return;

        foreach (var referencePath in referenceAssemblyPaths)
        {
            var fileName = Path.GetFileNameWithoutExtension(referencePath);
            if (!fileName.StartsWith("Microsoft.AspNetCore", StringComparison.OrdinalIgnoreCase)
                && !fileName.StartsWith("Microsoft.Extensions.Hosting", StringComparison.OrdinalIgnoreCase))
                continue;

            try
            {
                _ = Assembly.LoadFrom(referencePath);
            }
            catch
            {
                // Signature resolution falls back to explicit reference lookups at use sites.
            }
        }
    }

    private static bool TryResolveBclExceptionType(string name, out Type type)
    {
        type = name switch
        {
            "Exception" or "System.Exception" => typeof(Exception),
            "InvalidOperationException" or "System.InvalidOperationException" => typeof(InvalidOperationException),
            "ArgumentException" or "System.ArgumentException" => typeof(ArgumentException),
            "ArgumentNullException" or "System.ArgumentNullException" => typeof(ArgumentNullException),
            "ArgumentOutOfRangeException" or "System.ArgumentOutOfRangeException" => typeof(ArgumentOutOfRangeException),
            "FormatException" or "System.FormatException" => typeof(FormatException),
            "NotSupportedException" or "System.NotSupportedException" => typeof(NotSupportedException),
            "NotImplementedException" or "System.NotImplementedException" => typeof(NotImplementedException),
            "TimeoutException" or "System.TimeoutException" => typeof(TimeoutException),
            "DivideByZeroException" or "System.DivideByZeroException" => typeof(DivideByZeroException),
            "ArithmeticException" or "System.ArithmeticException" => typeof(ArithmeticException),
            "OverflowException" or "System.OverflowException" => typeof(OverflowException),
            "NullReferenceException" or "System.NullReferenceException" => typeof(NullReferenceException),
            "IndexOutOfRangeException" or "System.IndexOutOfRangeException" => typeof(IndexOutOfRangeException),
            "InvalidCastException" or "System.InvalidCastException" => typeof(InvalidCastException),
            "FileNotFoundException" or "System.IO.FileNotFoundException" => typeof(FileNotFoundException),
            "YamlException" or "YamlDotNet.Core.YamlException" => typeof(YamlExceptionType),
            _ => null!,
        };
        return type != null;
    }

    private static bool TryGetSupportedBclReadableProperty(Type receiverType, string member, out PropertyInfo property)
    {
        property = null!;
        if (receiverType == typeof(Process) && member is nameof(Process.ExitCode) or nameof(Process.StandardOutput) or nameof(Process.StandardError))
        {
            property = typeof(Process).GetProperty(member)!;
            return property.GetMethod != null;
        }
        if (receiverType.IsGenericType
            && !receiverType.IsGenericTypeDefinition
            && receiverType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<>)
            && member == "Result"
            && IsSupportedType(receiverType.GetGenericArguments()[0]))
        {
            property = receiverType.GetProperty("Result")!;
            return property.GetMethod != null;
        }
        if (receiverType == typeof(IList) && member == "Count")
        {
            property = typeof(ICollection).GetProperty("Count")!;
            return property.GetMethod != null;
        }
        if (receiverType == typeof(Assembly) && member is nameof(Assembly.IsDynamic) or nameof(Assembly.IsCollectible))
        {
            property = typeof(Assembly).GetProperty(member)!;
            return property.GetMethod != null;
        }
        if (receiverType == typeof(JsonDocument) && member == nameof(JsonDocument.RootElement))
        {
            property = typeof(JsonDocument).GetProperty(nameof(JsonDocument.RootElement))!;
            return property.GetMethod != null;
        }
        if (receiverType == typeof(JsonElement) && member == nameof(JsonElement.ValueKind))
        {
            property = typeof(JsonElement).GetProperty(nameof(JsonElement.ValueKind))!;
            return property.GetMethod != null;
        }
        if (IsSupportedAspNetExternalReferenceType(receiverType))
        {
            property = receiverType.GetProperty(member, BindingFlags.Public | BindingFlags.Instance)!;
            return property?.GetMethod != null && IsSupportedType(property.PropertyType);
        }
        return false;
    }

    private static bool TryGetSupportedBclWritableProperty(Type receiverType, string member, out PropertyInfo property)
    {
        property = null!;
        if (receiverType == typeof(ProcessStartInfo)
            && member is nameof(ProcessStartInfo.FileName)
                or nameof(ProcessStartInfo.Arguments)
                or nameof(ProcessStartInfo.WorkingDirectory)
                or nameof(ProcessStartInfo.RedirectStandardOutput)
                or nameof(ProcessStartInfo.RedirectStandardError)
                or nameof(ProcessStartInfo.UseShellExecute))
        {
            property = typeof(ProcessStartInfo).GetProperty(member)!;
            return property.SetMethod != null;
        }
        if (IsSupportedAspNetExternalReferenceType(receiverType))
        {
            property = receiverType.GetProperty(member, BindingFlags.Public | BindingFlags.Instance)!;
            return property?.SetMethod != null && IsSupportedType(property.PropertyType);
        }
        return false;
    }

    // A reference-type CONSTRUCTOR body is valid for columnar emit iff it (1) contains NO `return` statement — the
    // N# pipeline rejects `return` in a constructor (NL103, "there's no function to return from") — and (2) ASSIGNS
    // EVERY non-nullable own field of the type. Nullable own fields may retain the CLR null/default. The assignment
    // check is conservative: only a TOP-LEVEL `field = expr` statement counts, so a field assigned only inside an
    // `if`/loop declines to the N# backend path (safe under-acceptance) rather than risking a partial-coverage mis-accept.
    private bool IsValidReferenceCtorBody(int bodyRoot)
    {
        if (_currentStruct == null || _nodes.Kind(bodyRoot) != 25 || ContainsReturnStatement(bodyRoot))
            return false;
        var assigned = new HashSet<string>(_currentStruct.InstanceInitializerFields, StringComparer.Ordinal);
        for (var n = 0; n < _nodes.ChildCount(bodyRoot); n++)
        {
            var stmt = Child(bodyRoot, n);
            if (_nodes.Kind(stmt) != 23) // an expression statement
                continue;
            var e = Child(stmt, 0);
            if (_nodes.Kind(e) != 14 || Text(e) != "=") // a simple `=` assignment
                continue;
            var target = Child(e, 0);
            if (_nodes.Kind(target) == 6 && _currentStruct.Fields.ContainsKey(Text(target)))
                assigned.Add(Text(target));
        }
        foreach (var fieldName in _currentStruct.Fields.Keys)
        {
            if (!assigned.Contains(fieldName) && !_currentStruct.NullableFields.Contains(fieldName))
                return false;
        }
        return true;
    }

    // Emit a constructor's `: this(args)` / `: base(args)` CHAINING call: `ldarg.0; <args>; call <chained ctor>`.
    // The chained ctor is resolved by chain-arg COUNT — for `: this` among the current type's constructors
    // (excluding the chaining ctor itself), for `: base` among the DIRECT base's constructors (no self-exclusion;
    // a zero-arg `: base()` against a no-user-ctor base resolves to its PASS-0d default ctor). Two candidates of
    // that arity are ambiguous-by-count -> decline. Each chained arg is a param IDENTIFIER (kind 0, resolved to the
    // chaining ctor's param ordinal via `ldarg`, type-checked against the chained ctor's param type) or an INT
    // LITERAL (kind 1, `ldc.i4`). Returns false (whole assembly discarded) on any unresolved/mismatched arg.
    private bool EmitChainedConstructorCall(ColumnarConstructorInput ctor, ConstructorBuilder self)
    {
        if (_currentStruct == null)
            return false;
        var argKinds = ctor.ChainArgKinds;
        var argTexts = ctor.ChainArgTexts;
        ConstructorBuilder? chained = null;
        Type[]? chainedParamTypes = null;
        var ambiguous = false;
        if (ctor.ChainInitKind == 2)
        {
            var baseDef = _currentStruct.BaseDef;
            if (baseDef == null)
                return false; // guarded in PASS 0c — defensive.
            foreach (var (cb, cpt, _, _) in baseDef.Constructors)
            {
                if (cpt.Length != argKinds.Length)
                    continue;
                if (chained != null) { ambiguous = true; break; }
                chained = cb;
                chainedParamTypes = cpt;
            }
            if (chained == null && argKinds.Length == 0 && baseDef.DefaultCtor != null)
            {
                // `: base()` against a base with NO user ctors chains to the synthesized default ctor.
                chained = baseDef.DefaultCtor;
                chainedParamTypes = Type.EmptyTypes;
            }
        }
        else
        {
            foreach (var (cb, cpt, _, _) in _currentStruct.Constructors)
            {
                if (cb == self || cpt.Length != argKinds.Length)
                    continue;
                if (chained != null) { ambiguous = true; break; }
                chained = cb;
                chainedParamTypes = cpt;
            }
        }
        if (chained == null || ambiguous)
            return false;

        _il.Emit(OpCodes.Ldarg_0);
        for (var a = 0; a < argKinds.Length; a++)
        {
            if (argKinds[a] == 0) // a param identifier of the chaining ctor.
            {
                if (!_paramOrdinals.TryGetValue(argTexts[a], out var ordinal) || !_paramTypes.TryGetValue(argTexts[a], out var paramType))
                    return false;
                if (paramType != chainedParamTypes![a])
                    return false;
                EmitLoadArgument(ordinal);
            }
            else // an int literal.
            {
                if (chainedParamTypes![a] != typeof(int)
                    || !int.TryParse(argTexts[a], System.Globalization.NumberStyles.AllowLeadingSign, System.Globalization.CultureInfo.InvariantCulture, out var literal))
                    return false;
                _il.Emit(OpCodes.Ldc_I4, literal);
            }
        }
        _il.Emit(OpCodes.Call, chained);
        return true;
    }

    // Whether the subtree rooted at `idx` contains a Return statement (kind 20) anywhere. Expression kinds are 0-19,
    // so a kind-20 node only ever appears in statement position — walking all children is safe.
    private bool ContainsReturnStatement(int idx)
    {
        if (_nodes.Kind(idx) == 20)
            return true;
        for (var n = 0; n < _nodes.ChildCount(idx); n++)
        {
            if (ContainsReturnStatement(Child(idx, n)))
                return true;
        }
        return false;
    }

    // Emit `idx` as a value on the stack and report its CLR type via `type`. Returns false (declining the whole
    // function) on any unsupported form or a type mismatch the spike does not model. The reported type drives
    // correct opcode selection and prevents cross-type mixing (e.g. a bool leaking into int arithmetic) that
    // would diverge from N#'s type rules.
    private bool EmitExpression(int idx, out Type type)
        => EmitExpressionCore(idx, out type);

    private bool EmitExpressionWithOverflowChecking(int idx, bool enabled, out Type type)
    {
        var previous = _overflowCheckingEnabled;
        _overflowCheckingEnabled = enabled;
        try
        {
            return EmitExpression(Child(idx, 0), out type);
        }
        finally
        {
            _overflowCheckingEnabled = previous;
        }
    }

    private bool EmitExpressionCore(int idx, out Type type)
    {
        type = null!;
        switch (_nodes.Kind(idx))
        {
            case 6: // Identifier — a `:=` local (ldloc, type = LocalType) or a parameter (ldarg, type from the
                    // signature); the two name sets are disjoint (a local shadowing a param is declined at decl).
            {
                var name = Text(idx);
                if (IsExplicitThisIdentifier(idx))
                {
                    if (_currentStruct == null)
                        return false;
                    if (TryFindFieldOnChain(_currentStruct, name, out var explicitThisField))
                    {
                        _il.Emit(OpCodes.Ldarg_0);
                        _il.Emit(OpCodes.Ldfld, explicitThisField);
                        type = explicitThisField.FieldType;
                        return true;
                    }
                    if (TryFindPropertyOnChain(_currentStruct, name, out var explicitThisProperty))
                    {
                        _il.Emit(OpCodes.Ldarg_0);
                        _il.Emit(_currentStruct.IsReference ? OpCodes.Callvirt : OpCodes.Call, explicitThisProperty.Getter);
                        type = explicitThisProperty.PropertyType;
                        return true;
                    }
                    return false;
                }
                // L3b: a BOXED capture (in a closure body) or a LIFTED local/param reads through the shared
                // StrongBox's Value — checked before every other tier (a lifted name's plain slot is dead).
                if (_boxedCaptures != null && _boxedCaptures.TryGetValue(name, out var boxedRead))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    _il.Emit(OpCodes.Ldfld, boxedRead.BoxField);
                    _il.Emit(OpCodes.Ldfld, StrongBoxValueField(boxedRead.ValueType));
                    type = boxedRead.ValueType;
                    return true;
                }
                if (_liftedLocals.TryGetValue(name, out var liftedRead))
                {
                    _il.Emit(OpCodes.Ldloc, liftedRead.Box);
                    _il.Emit(OpCodes.Ldfld, StrongBoxValueField(liftedRead.ValueType));
                    type = liftedRead.ValueType;
                    return true;
                }
                if (_locals.TryGetValue(name, out var local))
                {
                    _il.Emit(OpCodes.Ldloc, local);
                    type = local.LocalType;
                    return true;
                }

                if (_paramOrdinals.TryGetValue(name, out var ordinal))
                {
                    var paramType = _paramTypes[name];
                    EmitLoadArgument(ordinal);
                    if (paramType.IsByRef)
                    {
                        type = paramType.GetElementType()!;
                        EmitLoadByRefElement(type);
                    }
                    else
                    {
                        type = paramType;
                    }
                    return true;
                }

                // Inside a struct INSTANCE method, a bare name that is neither a local nor a param falls back to a
                // FIELD of the current struct (`this.field`): `this` is arg 0, so emit `ldarg.0; ldfld <FieldBuilder>`.
                // (Checked AFTER locals/params so a local/param correctly shadows a field.) Resolution walks the
                // BASE chain (nearest first) so a derived member may read an INHERITED field.
                if (_currentStruct != null && TryFindFieldOnChain(_currentStruct, name, out var thisField))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    _il.Emit(OpCodes.Ldfld, thisField);
                    type = thisField.FieldType;
                    return true;
                }
                if (_currentStruct != null && TryFindPropertyOnChain(_currentStruct, name, out var thisProperty))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    _il.Emit(_currentStruct.IsReference ? OpCodes.Callvirt : OpCodes.Call, thisProperty.Getter);
                    type = thisProperty.PropertyType;
                    return true;
                }

                // Bare STATIC-member read inside an INSTANCE member body. The N# pipeline's pinned ASYMMETRY: bare
                // static-member access resolves in INSTANCE contexts only (a static body must qualify with the type
                // name) — gated on `_currentStruct`, which is null in static bodies, so those decline exactly
                // where the pipeline errors. No receiver: `ldsfld` for a field, `call get_Name` for a property.
                if (_currentStruct != null && TryFindStaticFieldOnChain(_currentStruct, name, out var bareStaticField))
                {
                    _il.Emit(OpCodes.Ldsfld, bareStaticField);
                    type = bareStaticField.FieldType;
                    return true;
                }
                if (_currentStruct != null && TryFindStaticPropertyOnChain(_currentStruct, name, out var bareStaticProp))
                {
                    _il.Emit(OpCodes.Call, bareStaticProp.Getter);
                    type = bareStaticProp.PropertyType;
                    return true;
                }

                return false;
            }

            case 0: // IntLiteral — decimal `int`, a signed `long` (L/l), or a `ulong` (a u/U AND an l/L suffix in
            {       // any order: UL/LU/ul/...). The lexer keeps the suffix in the token text. A BARE u/U (uint) is
                    // not in the supported set. Strip the trailing [uUlL] run and classify by which letters appear.
                var text = Text(idx);
                if (text.Length > 0 && text[^1] is 'm' or 'M')
                    return TryEmitDecimalLiteral(text.Substring(0, text.Length - 1), out type); // `5m`
                var end = text.Length;
                var sawU = false;
                var sawL = false;
                while (end > 0 && (text[end - 1] is 'u' or 'U' or 'l' or 'L'))
                {
                    if (text[end - 1] is 'u' or 'U') sawU = true; else sawL = true;
                    end--;
                }
                var digits = text.Substring(0, end);
                if (sawU && sawL) // ulong (u8): load the bit pattern via Ldc_I8.
                {
                    if (ulong.TryParse(digits, out var ulongValue))
                    {
                        _il.Emit(OpCodes.Ldc_I8, unchecked((long)ulongValue));
                        type = typeof(ulong);
                        return true;
                    }
                    return false;
                }
                if (sawU) // bare uint, not modelled.
                    return false;
                if (sawL) // signed long.
                {
                    if (long.TryParse(digits, out var longValue))
                    {
                        _il.Emit(OpCodes.Ldc_I8, longValue);
                        type = typeof(long);
                        return true;
                    }
                    return false;
                }
                if (int.TryParse(text, out var value))
                {
                    _il.Emit(OpCodes.Ldc_I4, value);
                    type = typeof(int);
                    return true;
                }

                return false;
            }

            case 1: // FloatLiteral — `3.5` / `3.5d` (double, r8 Ldc_R8) or `3.5f` (float, r4 Ldc_R4). An `m`/`M`
            {       // (decimal) suffix is a different type -> decline. The value is parsed identically to the
                    // path's ParseFloatLiteralValue (strip the type suffix, drop `_` separators, invariant parse),
                    // then narrowed to float for an f-literal (matching `Ldc_R4, (float)ParseFloatLiteralValue`).
                var raw = Text(idx);
                var last = raw.Length > 0 ? raw[raw.Length - 1] : '\0';
                if (last == 'm' || last == 'M')
                    return TryEmitDecimalLiteral(raw.Substring(0, raw.Length - 1), out type); // `2.5m`
                var isFloatLiteral = last == 'f' || last == 'F';
                var body = (isFloatLiteral || last == 'd' || last == 'D') ? raw.Substring(0, raw.Length - 1) : raw;
                if (!TryParseFloatingLiteralBody(body, out var doubleValue))
                    return false;
                if (isFloatLiteral)
                {
                    _il.Emit(OpCodes.Ldc_R4, (float)doubleValue);
                    type = typeof(float);
                }
                else
                {
                    _il.Emit(OpCodes.Ldc_R8, doubleValue);
                    type = typeof(double);
                }
                return true;
            }

            case 4: // BoolLiteral — true/false (i4 1/0).
                switch (Text(idx))
                {
                    case "true": _il.Emit(OpCodes.Ldc_I4_1); type = typeof(bool); return true;
                    case "false": _il.Emit(OpCodes.Ldc_I4_0); type = typeof(bool); return true;
                    default: return false;
                }

            case 2: // CharLiteral — `'x'` (or an escape like `'\n'`) -> ldc.i4 of the code point (type char).
            {
                var raw = Text(idx);
                if (raw.Length >= 2 && raw[0] == '\'' && raw[raw.Length - 1] == '\'')
                    raw = raw.Substring(1, raw.Length - 2);
                if (!NSharpLang.Compiler.StringLiteralDecoder.TryDecodeBody(raw, out var charValue) || charValue.Length != 1)
                    return false;
                _il.Emit(OpCodes.Ldc_I4, (int)charValue[0]);
                type = typeof(char);
                return true;
            }

            case 3: // StringLiteral
            {
                var stringText = Text(idx);
                if (stringText.Length > 0 && stringText[0] == '$')
                    return TryEmitInterpolatedString(stringText, out type);
                _il.Emit(OpCodes.Ldstr, NSharpLang.Compiler.StringLiteralDecoder.Decode(stringText));
                type = typeof(string);
                return true;
            }

            case 7: // Parenthesized — emit the inner expression, propagating its type.
                return EmitExpression(Child(idx, 0), out type);

            case 53: // AwaitExpression [operand] — the legacy emitter's SYNC lowering (no state machine in
            {        // EITHER pipeline): a blocking GetAwaiter().GetResult() on the four BCL task
                     // shapes (ValueTask(/T) converts via AsTask() first). Awaits are legal in
                     // NON-async functions too (probe-pinned: no await-outside-async diagnostic
                     // exists; the lowering is identical). Other awaitables decline.
                if (_nodes.ChildCount(idx) != 1 || !EmitExpression(Child(idx, 0), out var awaitableType))
                    return false;
                return TryEmitBlockingAwait(awaitableType, out type);
            }

            case 55: // TypeOfExpression [typeRoot] — `typeof(Type)`: resolve the embedded TYPE subtree and load
            {        // the runtime System.Type via RuntimeTypeHandle, matching the CLR lowering used by C#.
                if (_nodes.ChildCount(idx) != 1
                    || !TryBuildTypeNodeCanonical(Child(idx, 0), out var typeOfCanonical)
                    || !TryResolveType(typeOfCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var typeOfTarget))
                    return false;
                _il.Emit(OpCodes.Ldtoken, typeOfTarget);
                _il.Emit(OpCodes.Call, typeof(Type).GetMethod(nameof(Type.GetTypeFromHandle), new[] { typeof(RuntimeTypeHandle) })!);
                type = typeof(Type);
                return true;
            }

            case 57: // CheckedContextExpression [value] — `checked(expr)` / `unchecked(expr)`.
            {
                if (_nodes.ChildCount(idx) != 1)
                    return false;
                return Text(idx) switch
                {
                    "checked" => EmitExpressionWithOverflowChecking(idx, enabled: true, out type),
                    "unchecked" => EmitExpressionWithOverflowChecking(idx, enabled: false, out type),
                    _ => false,
                };
            }

            case 11: // Unary [operand] — int/long prefix `-`/`~`, or bool `!`. `++`/`--` decline.
            {
                if (Text(idx) == "-" && _nodes.ChildCount(idx) == 1 && _nodes.Kind(Child(idx, 0)) == 0)
                {
                    var magnitudeText = Text(Child(idx, 0));
                    if (magnitudeText == "2147483648")
                    {
                        _il.Emit(OpCodes.Ldc_I4, int.MinValue);
                        type = typeof(int);
                        return true;
                    }
                    if (magnitudeText == "9223372036854775808L" || magnitudeText == "9223372036854775808l")
                    {
                        _il.Emit(OpCodes.Ldc_I8, long.MinValue);
                        type = typeof(long);
                        return true;
                    }
                }
                if (!EmitExpression(Child(idx, 0), out var operandType))
                    return false;
                switch (Text(idx))
                {
                    case "-": // negate — Neg works on i4/i8/r8/r4; result is the operand's numeric type. NOT valid on
                              // ulong (N# forbids unary minus on an unsigned type) — decline it. On double/float, Neg
                              // is the IEEE negate (-NaN stays NaN, -0.0 is distinct from 0.0), matching the N# backend path.
                              // decimal negates via op_UnaryNegation (not an IL primitive).
                        if (operandType == typeof(decimal))
                        {
                            _il.Emit(OpCodes.Call, typeof(decimal).GetMethod("op_UnaryNegation", new[] { typeof(decimal) })!);
                            type = typeof(decimal); return true;
                        }
                        if (operandType != typeof(int) && operandType != typeof(long) && operandType != typeof(double) && operandType != typeof(float)) return false;
                        if (_overflowCheckingEnabled && (operandType == typeof(int) || operandType == typeof(long)))
                        {
                            var negOperand = _il.DeclareLocal(operandType);
                            _il.Emit(OpCodes.Stloc, negOperand);
                            if (operandType == typeof(long))
                                _il.Emit(OpCodes.Ldc_I8, 0L);
                            else
                                _il.Emit(OpCodes.Ldc_I4_0);
                            _il.Emit(OpCodes.Ldloc, negOperand);
                            _il.Emit(OpCodes.Sub_Ovf);
                            type = operandType;
                            return true;
                        }
                        _il.Emit(OpCodes.Neg); type = operandType; return true;
                    case "~": // bitwise not — Not works on i4 and i8 (and on ulong's u8 bit pattern).
                        if (operandType != typeof(int) && operandType != typeof(long) && operandType != typeof(ulong)) return false;
                        _il.Emit(OpCodes.Not); type = operandType; return true;
                    case "!": // logical not on a bool: x == false.
                        if (operandType != typeof(bool)) return false;
                        _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); type = typeof(bool); return true;
                    default: return false;
                }
            }

            case 12: // Binary [left, right] — int/long arithmetic & bitwise, shifts, short-circuit `&&`/`||`, or a
            {        // comparison producing bool. Most operators need both operands the SAME type.
                var op = Text(idx);

                // Short-circuit `&&`/`||` MUST conditionally evaluate the right operand — both for production semantics
                // and for safety (e.g. `i < n && a[i] == x` must not index a[i] when i >= n). So handle these
                // BEFORE evaluating either operand: emit left, branch on it, evaluate right only on the
                // non-short-circuiting path. Both operands and the result are bool.
                if (op == "&&" || op == "||")
                {
                    if (!EmitExpression(Child(idx, 0), out var shortLeftType) || shortLeftType != typeof(bool))
                        return false;
                    var shortLabel = _il.DefineLabel();
                    var endLabel = _il.DefineLabel();
                    // `&&` short-circuits to false when left is false; `||` to true when left is true.
                    _il.Emit(op == "&&" ? OpCodes.Brfalse : OpCodes.Brtrue, shortLabel);
                    if (!EmitExpression(Child(idx, 1), out var shortRightType) || shortRightType != typeof(bool))
                        return false;
                    _il.Emit(OpCodes.Br, endLabel);
                    _il.MarkLabel(shortLabel);
                    _il.Emit(op == "&&" ? OpCodes.Ldc_I4_0 : OpCodes.Ldc_I4_1);
                    _il.MarkLabel(endLabel);
                    type = typeof(bool);
                    return true;
                }

                if (op == "+" && TryEmitStringConcatChain(idx, out type))
                    return true;

                // NULL comparisons (`s == null` / `s != null`) and `??` COALESCING on REFERENCE types:
                // handled BEFORE the operand pair (a bare null has no self-type to unify). The null
                // literal as a LEFT operand (`null == s`) also works — both orders emit ldnull + ceq.
                if ((op == "==" || op == "!=") && (_nodes.Kind(Child(idx, 0)) == 5 || _nodes.Kind(Child(idx, 1)) == 5))
                {
                    var valueNode = _nodes.Kind(Child(idx, 0)) == 5 ? Child(idx, 1) : Child(idx, 0);
                    if (_nodes.Kind(valueNode) == 5)
                    {
                        // null == null is constant true (the pipeline folds the same way at runtime).
                        _il.Emit(OpCodes.Ldc_I4, op == "==" ? 1 : 0);
                        type = typeof(bool);
                        return true;
                    }
                    if (!EmitExpression(valueNode, out var nullCmpType))
                        return false;
                    if (IsSupportedNullable(nullCmpType))
                    {
                        // `n == null` on a Nullable<T> is !HasValue (and != null is HasValue) — the nullable lowering.
                        var nullableTemp = _il.DeclareLocal(nullCmpType);
                        _il.Emit(OpCodes.Stloc, nullableTemp);
                        _il.Emit(OpCodes.Ldloca, nullableTemp);
                        _il.Emit(OpCodes.Call, nullCmpType.GetMethod("get_HasValue")!);
                        if (op == "==")
                        {
                            _il.Emit(OpCodes.Ldc_I4_0);
                            _il.Emit(OpCodes.Ceq);
                        }
                        type = typeof(bool);
                        return true;
                    }
                    if (nullCmpType.IsValueType)
                        return false; // plain value types never compare to null (the pipeline rejects).
                    _il.Emit(OpCodes.Ldnull);
                    _il.Emit(OpCodes.Ceq);
                    if (op == "!=")
                    {
                        _il.Emit(OpCodes.Ldc_I4_0);
                        _il.Emit(OpCodes.Ceq);
                    }
                    type = typeof(bool);
                    return true;
                }
                if (op == "??")
                {
                    // `a ?? b` — REFERENCE left: `<a>; dup; brtrue end; pop; <b>; end:`. NULLABLE<T>
                    // left (N2): `tmp = a; tmp.HasValue ? tmp.GetValueOrDefault() : <b as T>` — both the
                    // exact nullable lowerings. The Nullable form's RESULT is the ELEMENT type.
                    if (!EmitExpression(Child(idx, 0), out var coalesceLeft))
                        return false;
                    if (IsSupportedNullable(coalesceLeft))
                    {
                        var coalesceElement = coalesceLeft.GetGenericArguments()[0];
                        var nullableLocal = _il.DeclareLocal(coalesceLeft);
                        _il.Emit(OpCodes.Stloc, nullableLocal);
                        var elseLabel2 = _il.DefineLabel();
                        var endLabel2 = _il.DefineLabel();
                        _il.Emit(OpCodes.Ldloca, nullableLocal);
                        _il.Emit(OpCodes.Call, coalesceLeft.GetMethod("get_HasValue")!);
                        _il.Emit(OpCodes.Brfalse, elseLabel2);
                        _il.Emit(OpCodes.Ldloca, nullableLocal);
                        _il.Emit(OpCodes.Call, coalesceLeft.GetMethod("GetValueOrDefault", Type.EmptyTypes)!);
                        _il.Emit(OpCodes.Br, endLabel2);
                        _il.MarkLabel(elseLabel2);
                        if (!TryEmitIntLiteralAsType(Child(idx, 1), coalesceElement, out _))
                        {
                            // emit-then-check is decline-safe: a false return abandons the program.
                            if (!EmitExpression(Child(idx, 1), out var coalesceRightType)
                                || !TypesEquivalent(coalesceRightType, coalesceElement))
                                return false;
                        }
                        _il.MarkLabel(endLabel2);
                        type = coalesceElement;
                        return true;
                    }
                    if (coalesceLeft.IsValueType)
                        return false;
                    var coalesceEnd = _il.DefineLabel();
                    _il.Emit(OpCodes.Dup);
                    _il.Emit(OpCodes.Brtrue, coalesceEnd);
                    _il.Emit(OpCodes.Pop);
                    if (_nodes.Kind(Child(idx, 1)) == 5)
                        _il.Emit(OpCodes.Ldnull);
                    else if (!EmitExpression(Child(idx, 1), out var coalesceRight) || !TypesEquivalent(coalesceRight, coalesceLeft))
                        return false;
                    _il.MarkLabel(coalesceEnd);
                    type = coalesceLeft;
                    return true;
                }

                if (TryEmitMixedNumericBinary(idx, op, out type))
                    return true;

                if (!EmitExpression(Child(idx, 0), out var leftType))
                {
                    return false;
                }
                // The RIGHT operand: an unsuffixed int literal against a uint/long/ulong LEFT adopts the
                // left's type (N#'s constant conversion — `u / 2`, `l + 5`); the left emits first, so this
                // is well-ordered. A literal LEFT against a typed right cannot adopt (the left is already
                // on the stack) — those mixes decline below, pinned for the widening slice.
                Type rightType;
                if ((leftType == typeof(uint) || leftType == typeof(long) || leftType == typeof(ulong))
                    && TryEmitIntLiteralAsType(Child(idx, 1), leftType, out rightType))
                {
                    // adopted — rightType == leftType.
                }
	                else if (!EmitExpression(Child(idx, 1), out rightType))
	                {
	                    return false;
	                }
	                if (op == "+" && TryEmitStringCharConcat(leftType, rightType, out type))
	                    return true;

	                // Shifts are special: the value is int/long, the shift COUNT is always int (not necessarily the
	                // value's type), and the result is the value's type. Shr is the SIGNED (arithmetic) right shift,
                // matching  for int/long; the columnar `>>` is a single binary operator here (the `>>` token
                // split only applies inside generic type arguments, not expression context).
                if (op == "<<" || op == ">>")
                {
                    if ((leftType != typeof(int) && leftType != typeof(long) && leftType != typeof(ulong)) || rightType != typeof(int))
                        return false;
                    // Shl is the same for signed/unsigned. `>>` is the SIGNED (arithmetic) Shr for int/long, but
                    // the UNSIGNED (logical, zero-fill) Shr_Un for ulong — matching N#'s ulong `>>`. A wrong Shr
                    // here would sign-extend a high-bit-set ulong.
                    _il.Emit(op == "<<" ? OpCodes.Shl : (leftType == typeof(ulong) ? OpCodes.Shr_Un : OpCodes.Shr));
                    type = leftType;
                    return true;
                }

                // NUMERIC PROMOTION (ECMA §12.4.7) for the modelled int-like types: int, char, and the SMALL
                // INTS (byte/sbyte/short/ushort) are ALL i4 on the stack (the load sign/zero-extends by the
                // storage type), so ANY mix of them promotes to int with NO conversion IL (`b + s` is int,
                // exactly ). long/ulong/uint/bool/string do NOT auto-promote (int/long needs a conv; uint
                // runs native u4 against itself only) — they must match exactly. `opType` is the type the
                // operation runs as; a same-type small-int pair promotes its RESULT to int below.
                Type opType;
                if (leftType == rightType)
                    opType = leftType;
                else if (ColumnarNumericFacts.IsIntPromotable(leftType) && ColumnarNumericFacts.IsIntPromotable(rightType))
                    opType = typeof(int);
                else
                {
                    return false;
                }

                // String CONCATENATION: `s1 + s2` -> String.Concat(string, string) (VALUE concat, matching the
                // path's result). Both operands are already on the stack. Only string+string is modelled (the
                // corpus' shape, e.g. `"diag-" + Math.Abs(hash).ToString("x")`); string+int etc. decline.
                if (op == "+" && opType == typeof(string))
                {
                    _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                    type = typeof(string);
                    return true;
                }
                // DECIMAL (SC-6): not an IL primitive — arithmetic/comparisons call System.Decimal's op_*
                // statics on the two already-emitted operands (the exact IL emit; 0.1m stays exact).
                if (opType == typeof(decimal))
                {
                    var decimalOpMethod = op switch
                    {
                        "+" => "op_Addition", "-" => "op_Subtraction", "*" => "op_Multiply",
                        "/" => "op_Division", "%" => "op_Modulus",
                        "<" => "op_LessThan", ">" => "op_GreaterThan",
                        "<=" => "op_LessThanOrEqual", ">=" => "op_GreaterThanOrEqual",
                        "==" => "op_Equality", "!=" => "op_Inequality",
                        _ => null,
                    };
                    if (decimalOpMethod == null)
                        return false;
                    _il.Emit(OpCodes.Call, typeof(decimal).GetMethod(decimalOpMethod, new[] { typeof(decimal), typeof(decimal) })!);
                    type = op is "+" or "-" or "*" or "/" or "%" ? typeof(decimal) : typeof(bool);
                    return true;
                }
                switch (op)
                {
                    case "+": case "-": case "*": case "/": case "%":
                        // Add/Sub/Mul/Div/Rem work on i4, i8, and r8 (double); the result is `opType`'s numeric type.
                        // Div/Rem are SIGNED for int/long (UNSIGNED Div_Un/Rem_Un for ulong); on DOUBLE the same
                        // `div`/`rem` opcodes do IEEE FP division/remainder (x/0.0 -> ±Inf, 0.0/0.0 -> NaN — no
                        // throw, matching the N# backend path), so double is NOT unsignedDivRem. Integer divide-by-zero /
                        // INT_MIN÷-1 still throw exactly as the N# backend path does. A CHAR result promotes to INT (a char
                        // never survives an arithmetic op — `c - 'A'` is int; matches Analyzer.cs:12820's GetWiderType).
                        if (!ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(double) && opType != typeof(float)) return false;
                        var unsignedArithmetic = opType == typeof(ulong) || opType == typeof(uint);
                        var checkedIntegralArithmetic = _overflowCheckingEnabled
                            && op is "+" or "-" or "*"
                            && (ColumnarNumericFacts.IsIntPromotable(opType) || opType == typeof(long) || opType == typeof(ulong) || opType == typeof(uint));
                        _il.Emit(
                            op == "+" ? (checkedIntegralArithmetic ? (unsignedArithmetic ? OpCodes.Add_Ovf_Un : OpCodes.Add_Ovf) : OpCodes.Add) :
                            op == "-" ? (checkedIntegralArithmetic ? (unsignedArithmetic ? OpCodes.Sub_Ovf_Un : OpCodes.Sub_Ovf) : OpCodes.Sub) :
                            op == "*" ? (checkedIntegralArithmetic ? (unsignedArithmetic ? OpCodes.Mul_Ovf_Un : OpCodes.Mul_Ovf) : OpCodes.Mul) :
                            op == "/" ? (unsignedArithmetic ? OpCodes.Div_Un : OpCodes.Div) :
                            (unsignedArithmetic ? OpCodes.Rem_Un : OpCodes.Rem));
                        // char and the small ints never survive an arithmetic op — the result is INT (N#'s
                        // promoted result, matching Analyzer.cs GetWiderType); uint stays uint (u4 native).
                        type = ColumnarNumericFacts.IsIntPromotable(opType) ? typeof(int) : opType;
                        return true;
                    case "&": case "|": case "^":
                        // Bitwise on the int-promotable set (result INT — N# promotes), long, ulong, or uint
                        // (And/Or/Xor work on i4 and i8 alike).
                        if (!ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint)) return false;
                        _il.Emit(op == "&" ? OpCodes.And : op == "|" ? OpCodes.Or : OpCodes.Xor);
                        type = ColumnarNumericFacts.IsIntPromotable(opType) ? typeof(int) : opType;
                        return true;
                    case "<": case ">": case "<=": case ">=":
                        // Ordering on int, long, char (signed Clt/Cgt; a char is a non-negative i4 so signed is
                        // correct), ulong (UNSIGNED Clt_Un/Cgt_Un — a ulong > long.MaxValue must compare as a large
                        // positive, not a negative i8), or double (ORDERED Clt/Cgt for `<`/`>`; the UNORDERED
                        // complement for `<=`/`>=` so a NaN operand yields false — see EmitComparison's isFloat path).
                        // The int-promotable set compares SIGNED on i4 (the load's sign/zero extension makes
                        // every small-int value its true integer — ushort 60000 is a positive i4); uint joins
                        // ulong on the UNSIGNED compares (4000000000 must order as large-positive).
                        if (!ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(double) && opType != typeof(float)) return false;
                        EmitComparison(op, opType == typeof(ulong) || opType == typeof(uint), opType == typeof(double) || opType == typeof(float));
                        type = typeof(bool);
                        return true;
                    case "==": case "!=":
                        if (opType == typeof(string))
                        {
                            // String equality is VALUE equality (String.op_Equality), NOT `ceq` (which compares
                            // references). `!=` negates the result.
                            _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                            if (op == "!=") { _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); }
                            type = typeof(bool);
                            return true;
                        }
                        if (opType == typeof(Type))
                        {
                            var typeEquality = typeof(Type).GetMethod(op == "==" ? "op_Equality" : "op_Inequality", new[] { typeof(Type), typeof(Type) });
                            if (typeEquality != null)
                                _il.Emit(OpCodes.Call, typeEquality);
                            else
                                EmitComparison(op);
                            type = typeof(bool);
                            return true;
                        }
                        // REFERENCE identity on registered user reference types (records AND classes): the
                        // pipeline's `==`/`!=` on user reference values is reference equality (probe-pinned —
                        // record VALUE equality lives in `.Equals`, never in `==`) — exactly `ceq`.
                        if (opType is TypeBuilder eqOperandTb && FindDefByBuilder(eqOperandTb) is { IsReference: true })
                        {
                            EmitComparison(op);
                            type = typeof(bool);
                            return true;
                        }
                        // RECORD STRUCT structural equality: `==`/`!=` on a value record routes through its
                        // synthesized Equals(object) (box the right operand; call on the left's address).
                        if (opType is TypeBuilder recordStructTb
                            && FindDefByBuilder(recordStructTb) is { IsReference: false, IsRecord: true, RecordEquals: not null } recordStructDef)
                        {
                            var recordRightTemp = _il.DeclareLocal(recordStructTb);
                            _il.Emit(OpCodes.Stloc, recordRightTemp);
                            var recordLeftTemp = _il.DeclareLocal(recordStructTb);
                            _il.Emit(OpCodes.Stloc, recordLeftTemp);
                            _il.Emit(OpCodes.Ldloca, recordLeftTemp);
                            _il.Emit(OpCodes.Ldloc, recordRightTemp);
                            _il.Emit(OpCodes.Box, recordStructTb);
                            _il.Emit(OpCodes.Call, recordStructDef.RecordEquals);
                            if (op == "!=") { _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); }
                            type = typeof(bool);
                            return true;
                        }
                        // Equality on int, long, ulong, bool, char, double, float, or a baked i4 enum (Ceq is bit-identical
                        // signed/unsigned; on double/float it is the IEEE ordered equal — NaN == NaN is false and
                        // NaN != NaN is true, which the `!=` negation of Ceq produces correctly).
                        if (!ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(bool) && opType != typeof(double) && opType != typeof(float) && !IsKnownEnumType(opType))
                        {
                            return false;
                        }
                        EmitComparison(op);
                        type = typeof(bool);
                        return true;
                    default: return false;
                }
            }

            case 9: // Call [callee, args...] — a sibling top-level function (bare-identifier callee, incl.
            {       // self/recursion), or a BCL method call (instance on a string, or static on a type like Char)
                    // whose callee is a MemberAccess [receiver, method-name].
                var callee = Child(idx, 0);
                if (_nodes.Kind(callee) == 6) // bare identifier -> resolved in the N# pipeline's EMPIRICALLY PINNED order.
                {
                    var name = Text(callee);
                    // A local/param of the same name: the N# pipeline binds bare calls to the METHOD (locals do
                    // not shadow call targets — pinned), so a name carried by BOTH a value and ANY method tier
                    // declines (under-accept). When NO method tier carries the name, a DELEGATE-typed local/param
                    // invokes via callvirt Invoke (L1a); a non-delegate value still declines.
                    if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name)
                        || _liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
                    {
                        if (_siblings.ContainsKey(name)
                            || (_currentStruct != null && TryFindMethodOnChain(_currentStruct, name, out _))
                            || (_enclosingType != null && TryFindStaticMethodOnChain(_enclosingType, name, _nodes.ChildCount(idx) - 1, out _)))
                            return false;
                        return TryEmitDelegateInvoke(idx, name, out type);
                    }
                    // Bare-call resolution order, verified probe-by-probe against the production pipeline (a
                    // first agent-probe round claimed own-instance-beats-top-level; DIRECT re-probing REFUTED
                    // that — the pinned truth, parity-tested, is):
                    //   1. a sibling TOP-LEVEL function — beats every same-named type member (own instance,
                    //      inherited instance, and statics alike),
                    //   2. an instance method on the enclosing type's chain (nearest declaration first),
                    //   3. a STATIC method on the enclosing type's chain (nearest arity match).
                    // Tier 2 requires an instance context (`_currentStruct` — null inside a static method, so a
                    // static body calling an instance method bare structurally declines, as the pipeline rejects
                    // it); tier 3 anchors on `_enclosingType` so it fires in static bodies too. Tiers 2 and 3 can
                    // never compete: a name carried by both an instance and a static method anywhere on the chain
                    // was declined in PASS 0b/0b''.
                    // LOCAL FUNCTIONS shadow same-named siblings at call sites (probe-pinned: the
                    // pipeline calls the local) — their tier comes FIRST.
                    if (_localFuncs != null && _visibleLocalFuncs.Contains(name)
                        && _localFuncs.TryGetValue(name, out var localTarget))
                    {
                        var localArgCount = _nodes.ChildCount(idx) - 1;
                        if (localArgCount != localTarget.ParamTypes.Length)
                            return false;
                        for (var a = 1; a <= localArgCount; a++)
                        {
                            var localArgNode = Child(idx, a);
                            if (_nodes.Kind(localArgNode) == 39)
                                return false;
                            if (!EmitExpression(localArgNode, out var localArgType) || !TypesEquivalent(localArgType, localTarget.ParamTypes[a - 1]))
                                return false;
                        }
                        _il.Emit(OpCodes.Call, localTarget.Method);
                        type = localTarget.ReturnType;
                        return true;
                    }
                    if (_siblings.TryGetValue(name, out var target))
                    {
                        var argCount = _nodes.ChildCount(idx) - 1;
                        if (argCount != target.ParamTypes.Length) // arity must match (no overloads / defaults / params).
                            return false;
                        if (target.TypeParams.Length > 0)
                        {
                            // A GENERIC sibling with INFERRED type arguments: start from an empty binding —
                            // the shared emission helper unifies each declared parameter shape against the
                            // emitted argument types (the legacy emitter's TryInferDeclaredMethodTypeArguments).
                            return TryEmitGenericSiblingCall(idx, target, new Type?[target.TypeParams.Length], out type);
                        }
                        // Each argument's type must match the callee's declared parameter type. int and bool are both
                        // i4 on the CLR stack, so without this check a mismatch (e.g. an int passed to a bool
                        // parameter) would emit verifiable-but-semantically-wrong IL instead of declining.
                        // A LAMBDA literal argument (kind 39) is CONTEXTUALLY typed — the declared delegate
                        // parameter supplies its signature (the production's expected-type flow); it synthesizes
                        // a static `<Lambda>_{n}` method and constructs the delegate in place (L1b).
                        for (var a = 1; a <= argCount; a++)
                        {
                            if (!EmitDeclaredCallArgument(Child(idx, a), target.ParamTypes[a - 1], allowLambdaLiteral: true))
                                return false;
                        }
                        _il.Emit(OpCodes.Call, target.Method);
                        type = target.ReturnType;
                        return true;
                    }
                    if (_currentStruct != null && TrySelectInstanceMethodOnChain(_currentStruct, name, idx, out var ownMethod))
                        return EmitImplicitThisCall(idx, ownMethod, out type);
                    if (_enclosingType != null && TryFindStaticMethodOnChain(_enclosingType, name, _nodes.ChildCount(idx) - 1, out var ownStatic))
                    {
                        // No receiver: just the args, then a direct `call` to the declaring type's static.
                        var staticArgCount = _nodes.ChildCount(idx) - 1;
                        for (var a = 1; a <= staticArgCount; a++)
                        {
                            if (!EmitDeclaredCallArgument(Child(idx, a), ownStatic.ParamTypes[a - 1], allowLambdaLiteral: true))
                            {
                                return Decline("emit.call.static-argument", "static call argument " + a + " for '" + name + "' could not be emitted", Child(idx, a));
                            }
                        }
                        _il.Emit(OpCodes.Call, ownStatic.Builder);
                        type = ownStatic.ReturnType;
                        return true;
                    }
                    // CALL-STYLE newtype construction (`UserId(42)`): newtypes ONLY (the legacy
                    // emitter's RecordsTopLevelNewtypeNames gate) — resolve the synthesized
                    // single-parameter constructor and newobj it.
                    if (_structRegistry.TryGetValue(name, out var newtypeDef) && newtypeDef.IsNewtype)
                    {
                        var newtypeArgCount = _nodes.ChildCount(idx) - 1;
                        foreach (var (ctorBuilder, ctorParamTypes, _, _) in newtypeDef.Constructors)
                        {
                            if (ctorParamTypes.Length != newtypeArgCount)
                                continue;
                            for (var a = 1; a <= newtypeArgCount; a++)
                            {
                                if (!EmitDeclaredCallArgument(Child(idx, a), ctorParamTypes[a - 1], allowLambdaLiteral: false))
                                    return false;
                            }
                            _il.Emit(OpCodes.Newobj, ctorBuilder);
                            type = newtypeDef.Builder;
                            return true;
                        }
                        return false;
                    }
                    return Decline("emit.call.bare-unresolved", "bare call '" + name + "' with " + (_nodes.ChildCount(idx) - 1) + " argument(s) could not be resolved", idx);
                }
                if (_nodes.Kind(callee) == 38) // GenericCallee — an EXPLICIT generic call `F<T1, T2>(args)`.
                {
                    if (TryEmitJsonSerializerDeserializeGenericCall(idx, callee, out type))
                        return true;
                    var gName = Text(callee);
                    // The callee resolves exactly like a bare identifier: locals/params shadow-decline; only a
                    // GENERIC top-level sibling binds (explicit type args on a non-generic are pipeline-rejected).
                    if (_locals.ContainsKey(gName) || _paramOrdinals.ContainsKey(gName))
                        return Decline("emit.call.generic-shadowed", "generic call '" + gName + "' is shadowed by a value binding", idx);
                    if (!_siblings.TryGetValue(gName, out var gTarget) || gTarget.TypeParams.Length == 0)
                        return Decline("emit.call.generic-unresolved", "generic call '" + gName + "' with " + (_nodes.ChildCount(idx) - 1) + " argument(s) could not be resolved", idx);
                    if (_nodes.ChildCount(callee) != gTarget.TypeParams.Length)
                        return false; // an explicit-argument ARITY mismatch is pipeline-rejected — decline.
                    // Resolve each explicit type argument: SIMPLE (kind 0) type nodes only this slice (the
                    // children of a kind-38 node are TYPE-kernel subtrees by construction). The resolved type
                    // must be a bindable concrete type — TypeBuilder/EnumBuilder instantiations decline, exactly
                    // like inferred bindings. The PRE-SEEDED binding then flows through the shared emission
                    // helper, whose unify loop VERIFIES each argument against it (Identity<string>(5) declines).
                    var explicitBinding = new Type?[gTarget.TypeParams.Length];
                    for (var ta = 0; ta < gTarget.TypeParams.Length; ta++)
                    {
                        var typeArgNode = Child(callee, ta);
                        if (_nodes.Kind(typeArgNode) != 0)
                            return false; // composed explicit type args (List<int>, T[]) decline this slice.
                        if (!TryResolveType(Text(typeArgNode), _enumRegistry, _structRegistry, _unionRegistry, out var taType))
                            return false;
                        if (taType is TypeBuilder || taType is EnumBuilder || !IsSupportedType(taType))
                            return false;
                        explicitBinding[ta] = taType;
                    }
                    return TryEmitGenericSiblingCall(idx, gTarget, explicitBinding, out type);
                }
                if (_nodes.Kind(callee) == 8) // MemberAccess callee -> a BCL instance/static method call.
                    return TryEmitBclMethodCall(idx, callee, out type);
                return false;
            }

            case 8: // MemberAccess [receiver] — an ENUM CONSTANT (e.g. StringComparison.Ordinal), or `.Length` on
            {       // an array/string/StringBuilder (-> int). The member name is the value span.
                // An enum constant: a bare-identifier receiver naming the enum TYPE (not a value) + a member that
                // is one of its named constants -> load the constant's underlying int (an enum is its underlying
                // value on the stack). Only StringComparison is modelled (the corpus' only enum).
                var memberAccessReceiver = Child(idx, 0);
                if (_nodes.Kind(memberAccessReceiver) == 8
                    && Text(memberAccessReceiver) == nameof(Environment.SpecialFolder)
                    && _nodes.Kind(Child(memberAccessReceiver, 0)) == 6
                    && Text(Child(memberAccessReceiver, 0)) == nameof(Environment)
                    && Text(idx) == nameof(Environment.SpecialFolder.UserProfile))
                {
                    _il.Emit(OpCodes.Ldc_I4, (int)Environment.SpecialFolder.UserProfile);
                    type = typeof(Environment.SpecialFolder);
                    return true;
                }
                if (_nodes.Kind(memberAccessReceiver) == 6)
                {
                    var receiverIdent = Text(memberAccessReceiver);
                    if (receiverIdent == "StringComparison"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (!TryGetStringComparisonValue(Text(idx), out var enumValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, enumValue);
                        type = typeof(StringComparison);
                        return true;
                    }
                    if (receiverIdent == "StringComparer"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) is "Ordinal" or "OrdinalIgnoreCase")
                    {
                        _il.Emit(OpCodes.Call, typeof(StringComparer).GetProperty(Text(idx))!.GetGetMethod()!);
                        type = typeof(StringComparer);
                        return true;
                    }
                    if (receiverIdent == "CamelCaseNamingConvention"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(CamelCaseNamingConvention.Instance))
                    {
                        _il.Emit(OpCodes.Ldsfld, typeof(CamelCaseNamingConvention).GetField(nameof(CamelCaseNamingConvention.Instance))!);
                        type = typeof(INamingConvention);
                        return true;
                    }
                    if (receiverIdent == "SearchOption"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(SearchOption.TopDirectoryOnly))
                    {
                        _il.Emit(OpCodes.Ldc_I4, (int)SearchOption.TopDirectoryOnly);
                        type = typeof(SearchOption);
                        return true;
                    }
                    if (receiverIdent == "NumberStyles"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(System.Globalization.NumberStyles.HexNumber))
                    {
                        _il.Emit(OpCodes.Ldc_I4, (int)System.Globalization.NumberStyles.HexNumber);
                        type = typeof(System.Globalization.NumberStyles);
                        return true;
                    }
                    if (receiverIdent == "JsonValueKind"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Enum.TryParse<JsonValueKind>(Text(idx), out var jsonValueKind))
                    {
                        _il.Emit(OpCodes.Ldc_I4, (int)jsonValueKind);
                        type = typeof(JsonValueKind);
                        return true;
                    }
                    if (receiverIdent == "JsonNamingPolicy"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(JsonNamingPolicy.CamelCase))
                    {
                        _il.Emit(OpCodes.Call, typeof(JsonNamingPolicy).GetProperty(nameof(JsonNamingPolicy.CamelCase))!.GetGetMethod()!);
                        type = typeof(JsonNamingPolicy);
                        return true;
                    }
                    if (!_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && TryEmitPrimitiveStaticConstant(receiverIdent, Text(idx), out type))
                    {
                        return true;
                    }
                    if (receiverIdent == "Environment"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) is nameof(Environment.NewLine) or nameof(Environment.CurrentDirectory))
                    {
                        _il.Emit(OpCodes.Call, typeof(Environment).GetProperty(Text(idx))!.GetGetMethod()!);
                        type = typeof(string);
                        return true;
                    }
                    if (receiverIdent == "AppContext"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(AppContext.BaseDirectory))
                    {
                        _il.Emit(OpCodes.Call, typeof(AppContext).GetProperty(nameof(AppContext.BaseDirectory))!.GetGetMethod()!);
                        type = typeof(string);
                        return true;
                    }
                    if (receiverIdent == "CultureInfo"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(System.Globalization.CultureInfo.InvariantCulture))
                    {
                        _il.Emit(OpCodes.Call, typeof(System.Globalization.CultureInfo).GetProperty(nameof(System.Globalization.CultureInfo.InvariantCulture))!.GetGetMethod()!);
                        type = typeof(System.Globalization.CultureInfo);
                        return true;
                    }
                    if (receiverIdent == "AppDomain"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(AppDomain.CurrentDomain))
                    {
                        _il.Emit(OpCodes.Call, typeof(AppDomain).GetProperty(nameof(AppDomain.CurrentDomain))!.GetGetMethod()!);
                        type = typeof(AppDomain);
                        return true;
                    }
                    if (receiverIdent == "Console"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(Console.Error))
                    {
                        _il.Emit(OpCodes.Call, typeof(Console).GetProperty(nameof(Console.Error))!.GetGetMethod()!);
                        type = typeof(TextWriter);
                        return true;
                    }
                    if (receiverIdent == "Task"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(System.Threading.Tasks.Task.CompletedTask))
                    {
                        _il.Emit(OpCodes.Call,
                            typeof(System.Threading.Tasks.Task).GetProperty(nameof(System.Threading.Tasks.Task.CompletedTask))!.GetGetMethod()!);
                        type = typeof(System.Threading.Tasks.Task);
                        return true;
                    }
                    if (receiverIdent == "Random"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent)
                        && Text(idx) == nameof(Random.Shared))
                    {
                        _il.Emit(OpCodes.Call, typeof(Random).GetProperty(nameof(Random.Shared))!.GetGetMethod()!);
                        type = typeof(Random);
                        return true;
                    }
                    if (receiverIdent == "DateTime"
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (typeof(DateTime).GetProperty(Text(idx), BindingFlags.Public | BindingFlags.Static) is { GetMethod: not null } dateTimeStaticProperty
                            && IsSupportedType(dateTimeStaticProperty.PropertyType))
                        {
                            _il.Emit(OpCodes.Call, dateTimeStaticProperty.GetMethod);
                            type = dateTimeStaticProperty.PropertyType;
                            return true;
                        }
                        // Static readonly fields (UnixEpoch, MinValue, MaxValue) load with ldsfld.
                        if (typeof(DateTime).GetField(Text(idx), BindingFlags.Public | BindingFlags.Static) is { } dateTimeStaticField
                            && IsSupportedType(dateTimeStaticField.FieldType))
                        {
                            _il.Emit(OpCodes.Ldsfld, dateTimeStaticField);
                            type = dateTimeStaticField.FieldType;
                            return true;
                        }
                    }
                    // A USER-DEFINED enum constant: the receiver names a registered enum TYPE (not shadowed by a
                    // local/param/sibling) and the member is one of its constants -> load the underlying int. The
                    // reported type is the same finalized enum Type used for params/returns and collection elements.
                    if (_enumRegistry.TryGetValue(receiverIdent, out var userEnum)
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (userEnum.StringConstants != null)
                        {
                            if (!userEnum.StringConstants.TryGetValue(Text(idx), out var stringValue))
                                return false;
                            _il.Emit(OpCodes.Ldstr, stringValue);
                            type = typeof(string);
                            return true;
                        }
                        if (!userEnum.Constants.TryGetValue(Text(idx), out var memberValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, memberValue);
                        type = userEnum.EnumType;
                        return true;
                    }
                    // A USER-TYPE STATIC member read `TypeName.member`: the receiver names a registered struct/
                    // record/class TYPE (not shadowed by a local/param/sibling) — chain-walk its static FIELDS
                    // then static PROPERTIES (nearest declaration first; `Derived.count` binds a base-declared
                    // static, matching the fixed legacy emitter): `ldsfld` for a field, `call get_Name` for a property.
                    // A member that is NEITHER declines (a type name is not a value — nothing to fall through to).
                    if (_structRegistry.TryGetValue(receiverIdent, out var staticOwner)
                        && !_locals.ContainsKey(receiverIdent) && !_liftedLocals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (TryFindStaticFieldOnChain(staticOwner, Text(idx), out var staticFieldRead))
                        {
                            _il.Emit(OpCodes.Ldsfld, staticFieldRead);
                            type = staticFieldRead.FieldType;
                            return true;
                        }
                        if (TryFindStaticPropertyOnChain(staticOwner, Text(idx), out var staticPropRead))
                        {
                            _il.Emit(OpCodes.Call, staticPropRead.Getter);
                            type = staticPropRead.PropertyType;
                            return true;
                        }
                        return false;
                    }
                }
                // Instance member access: `.Length` (array/string/StringBuilder -> int) or `.ItemN` (a tuple
                // element). Anything else declines BEFORE the receiver is emitted (no wasted side effects).
                var member = Text(idx);
                // A NAMED tuple element (`t.x` on a receiver whose declared names contain x) rewrites to the
                // positional ItemN spelling BEFORE the accessor gate — names come from the per-variable map
                // (annotated params, named-literal/call-derived locals), never the erased CLR type.
                member = MaybeRewriteTupleMemberName(Child(idx, 0), member);
                // `.ItemN` is a tuple element accessor only if a DIGIT follows "Item" (so `.Items`/`.ItemFoo`
                // decline early without emitting the receiver); the actual element is still gated by GetField below.
                var isTupleItem = member.Length > 4 && member.StartsWith("Item", StringComparison.Ordinal) && char.IsDigit(member[4]);
                if (TryResolveMemberWriteChain(Child(idx, 0), out var directReadChain)
                    && directReadChain.ReceiverType is TypeBuilder directReadOwnerTb
                    && FindDefByBuilder(directReadOwnerTb) is { } directReadOwnerDef)
                {
                    if (TryFindFieldOnChain(directReadOwnerDef, member, out var directReadField))
                    {
                        EmitMemberWriteLocator(directReadChain);
                        _il.Emit(OpCodes.Ldfld, directReadField);
                        type = directReadField.FieldType;
                        return true;
                    }
                    if (TryFindPropertyOnChain(directReadOwnerDef, member, out var directReadProperty))
                    {
                        EmitMemberWriteLocator(directReadChain);
                        _il.Emit(directReadOwnerDef.IsReference ? OpCodes.Callvirt : OpCodes.Call, directReadProperty.Getter);
                        type = directReadProperty.PropertyType;
                        return true;
                    }
                }
                if (member != "Length" && !isTupleItem)
                {
                    // Other supported receivers fall back to the emitted-receiver path for BCL members,
                    // closed generics, and reference-type properties.
                    if (!EmitExpression(Child(idx, 0), out var structReceiverType))
                    {
                        return false;
                    }
                    // `e.Message` on an Exception-derived receiver (the typed-catch bound variable's main
                    // use) — callvirt get_Message, exactly the property get the pipeline binds.
                    if (member == "Message" && typeof(Exception).IsAssignableFrom(structReceiverType))
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(Exception).GetProperty(nameof(Exception.Message))!.GetGetMethod()!);
                        type = typeof(string);
                        return true;
                    }
                    if (structReceiverType == typeof(Version) && member is "Major" or "Minor" or "Build" or "Revision")
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(Version).GetProperty(member)!.GetGetMethod()!);
                        type = typeof(int);
                        return true;
                    }
                    if (structReceiverType == typeof(TimeSpan) && member == nameof(TimeSpan.TotalMilliseconds))
                    {
                        var timeSpanTemp = _il.DeclareLocal(typeof(TimeSpan));
                        _il.Emit(OpCodes.Stloc, timeSpanTemp);
                        _il.Emit(OpCodes.Ldloca, timeSpanTemp);
                        _il.Emit(OpCodes.Call, typeof(TimeSpan).GetProperty(nameof(TimeSpan.TotalMilliseconds))!.GetGetMethod()!);
                        type = typeof(double);
                        return true;
                    }
                    if (structReceiverType == typeof(DateTime)
                        && typeof(DateTime).GetProperty(member, BindingFlags.Public | BindingFlags.Instance) is { GetMethod: not null } dateTimeProperty
                        && IsSupportedType(dateTimeProperty.PropertyType))
                    {
                        var dateTimeTemp = _il.DeclareLocal(typeof(DateTime));
                        _il.Emit(OpCodes.Stloc, dateTimeTemp);
                        _il.Emit(OpCodes.Ldloca, dateTimeTemp);
                        _il.Emit(OpCodes.Call, dateTimeProperty.GetMethod);
                        type = dateTimeProperty.PropertyType;
                        return true;
                    }
                    if (structReceiverType == typeof(JsonElement) && member == nameof(JsonElement.ValueKind))
                    {
                        var jsonElementTemp = _il.DeclareLocal(typeof(JsonElement));
                        _il.Emit(OpCodes.Stloc, jsonElementTemp);
                        _il.Emit(OpCodes.Ldloca, jsonElementTemp);
                        _il.Emit(OpCodes.Call, typeof(JsonElement).GetProperty(nameof(JsonElement.ValueKind))!.GetGetMethod()!);
                        type = typeof(JsonValueKind);
                        return true;
                    }
                    if (structReceiverType == typeof(JsonElement.ArrayEnumerator) && member == nameof(JsonElement.ArrayEnumerator.Current))
                    {
                        var enumeratorTemp = _il.DeclareLocal(typeof(JsonElement.ArrayEnumerator));
                        _il.Emit(OpCodes.Stloc, enumeratorTemp);
                        _il.Emit(OpCodes.Ldloca, enumeratorTemp);
                        _il.Emit(OpCodes.Call, typeof(JsonElement.ArrayEnumerator).GetProperty(nameof(JsonElement.ArrayEnumerator.Current))!.GetGetMethod()!);
                        type = typeof(JsonElement);
                        return true;
                    }
                    if (structReceiverType == typeof(JsonElement.ObjectEnumerator) && member == nameof(JsonElement.ObjectEnumerator.Current))
                    {
                        var enumeratorTemp = _il.DeclareLocal(typeof(JsonElement.ObjectEnumerator));
                        _il.Emit(OpCodes.Stloc, enumeratorTemp);
                        _il.Emit(OpCodes.Ldloca, enumeratorTemp);
                        _il.Emit(OpCodes.Call, typeof(JsonElement.ObjectEnumerator).GetProperty(nameof(JsonElement.ObjectEnumerator.Current))!.GetGetMethod()!);
                        type = typeof(JsonProperty);
                        return true;
                    }
                    if (structReceiverType == typeof(JsonProperty) && member is nameof(JsonProperty.Name) or nameof(JsonProperty.Value))
                    {
                        var propertyTemp = _il.DeclareLocal(typeof(JsonProperty));
                        _il.Emit(OpCodes.Stloc, propertyTemp);
                        _il.Emit(OpCodes.Ldloca, propertyTemp);
                        var property = typeof(JsonProperty).GetProperty(member);
                        if (property?.GetMethod == null)
                            return false;
                        _il.Emit(OpCodes.Call, property.GetMethod);
                        type = property.PropertyType;
                        return true;
                    }
                    if (structReceiverType == typeof(Type) && member is nameof(Type.Name) or nameof(Type.FullName) or nameof(Type.Namespace) or nameof(Type.IsNested))
                    {
                        var property = typeof(Type).GetProperty(member);
                        if (property?.GetMethod == null)
                            return false;
                        _il.Emit(OpCodes.Callvirt, property.GetMethod);
                        type = property.PropertyType;
                        return true;
                    }
                    if (structReceiverType == typeof(YamlParser) && member == nameof(YamlParser.Current))
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(YamlParser).GetProperty(nameof(YamlParser.Current))!.GetGetMethod()!);
                        type = typeof(ParsingEvent);
                        return true;
                    }
                    if (structReceiverType == typeof(Scalar) && member == nameof(Scalar.Value))
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(Scalar).GetProperty(nameof(Scalar.Value))!.GetGetMethod()!);
                        type = typeof(string);
                        return true;
                    }
                    if (TryGetSupportedBclReadableProperty(structReceiverType, member, out var bclPropertyRead))
                    {
                        _il.Emit(OpCodes.Callvirt, bclPropertyRead.GetMethod!);
                        type = bclPropertyRead.PropertyType;
                        return true;
                    }
                    if (structReceiverType.FullName == "Microsoft.AspNetCore.Builder.WebApplication"
                        && member == "Environment")
                    {
                        var property = structReceiverType.GetProperty("Environment", BindingFlags.Public | BindingFlags.Instance);
                        if (property?.GetMethod == null)
                            return false;
                        _il.Emit(OpCodes.Callvirt, property.GetMethod);
                        type = property.PropertyType;
                        return true;
                    }
                    if (IsSupportedNullable(structReceiverType) && member is "HasValue" or "Value")
                    {
                        var nullableTemp = _il.DeclareLocal(structReceiverType);
                        _il.Emit(OpCodes.Stloc, nullableTemp);
                        _il.Emit(OpCodes.Ldloca, nullableTemp);
                        if (member == "HasValue")
                        {
                            _il.Emit(OpCodes.Call, structReceiverType.GetProperty(nameof(Nullable<int>.HasValue))!.GetGetMethod()!);
                            type = typeof(bool);
                            return true;
                        }
                        _il.Emit(OpCodes.Call, structReceiverType.GetProperty(nameof(Nullable<int>.Value))!.GetGetMethod()!);
                        type = structReceiverType.GetGenericArguments()[0];
                        return true;
                    }
                    // `.Count` on a closed List<T>/Dictionary<K,V>/HashSet<T> — callvirt get_Count -> int
                    // (resolved from the open definition so builder-bound receivers rebind).
                    if (member == "Count" && TryResolveCollectionCountGetter(structReceiverType, out var countGetter))
                    {
                        _il.Emit(OpCodes.Callvirt, countGetter);
                        type = typeof(int);
                        return true;
                    }
                    // `kvp.Key` / `kvp.Value` on a KeyValuePair<K,V> (the Dictionary foreach loop
                    // variable) — a VALUE-type receiver: spill, ldloca, call the non-virtual getter.
                    // The result type comes from the CLOSED arguments, never the getter's ReturnType:
                    // a REBOUND getter reports the OPEN TKey/TValue (spike-proven) — propagating that
                    // would leak an open generic parameter into downstream typing (wrong-IL hazard).
                    if (member is "Key" or "Value" && IsSupportedKeyValuePairType(structReceiverType))
                    {
                        var kvpTemp = _il.DeclareLocal(structReceiverType);
                        _il.Emit(OpCodes.Stloc, kvpTemp);
                        _il.Emit(OpCodes.Ldloca, kvpTemp);
                        var openKvpGetter = typeof(KeyValuePair<,>).GetProperty(member)!.GetGetMethod()!;
                        _il.Emit(OpCodes.Call, ResolveClosedGenericMethod(structReceiverType, openKvpGetter));
                        type = structReceiverType.GetGenericArguments()[member == "Key" ? 0 : 1];
                        return true;
                    }
                    ColumnarStructDef? fieldStruct = null;
                    foreach (var d in _structRegistry.Values)
                    {
                        if (d.Builder == structReceiverType) { fieldStruct = d; break; }
                    }
                    if (fieldStruct == null)
                    {
                        // A CLOSED user-generic receiver (`Box<int>`): resolve on the OPEN definition (own
                        // type only — generic bases decline at declaration), rebind the token via
                        // TypeBuilder.GetField/GetMethod (reflection member queries throw on
                        // TypeBuilderInstantiation), and substitute the closed type arguments into the
                        // member type (b.item on Box<int> is int).
                        if (TryGetClosedReceiverDef(structReceiverType, out var closedFieldDef, out var closedFieldArgs))
                        {
                            if (closedFieldDef.Fields.TryGetValue(member, out var openField))
                            {
                                if (closedFieldDef.IsReference)
                                {
                                    _il.Emit(OpCodes.Ldfld, TypeBuilder.GetField(structReceiverType, openField));
                                }
                                else
                                {
                                    var closedFieldTemp = _il.DeclareLocal(structReceiverType);
                                    _il.Emit(OpCodes.Stloc, closedFieldTemp);
                                    _il.Emit(OpCodes.Ldloca, closedFieldTemp);
                                    _il.Emit(OpCodes.Ldfld, TypeBuilder.GetField(structReceiverType, openField));
                                }
                                type = SubstituteClosedTypeArguments(openField.FieldType, closedFieldArgs);
                                return true;
                            }
                            if (closedFieldDef.Properties.TryGetValue(member, out var openProp))
                            {
                                var closedGetter = TypeBuilder.GetMethod(structReceiverType, openProp.Getter);
                                if (closedFieldDef.IsReference)
                                {
                                    _il.Emit(OpCodes.Callvirt, closedGetter);
                                }
                                else
                                {
                                    var closedPropertyTemp = _il.DeclareLocal(structReceiverType);
                                    _il.Emit(OpCodes.Stloc, closedPropertyTemp);
                                    _il.Emit(OpCodes.Ldloca, closedPropertyTemp);
                                    _il.Emit(OpCodes.Call, closedGetter);
                                }
                                type = SubstituteClosedTypeArguments(openProp.PropertyType, closedFieldArgs);
                                return true;
                            }
                        }
                        return false;
                    }
                    // Resolution walks the BASE chain (nearest first) so a derived receiver exposes INHERITED
                    // fields/properties (`d.X` where X is declared on Base).
                    if (TryFindFieldOnChain(fieldStruct, member, out var structField))
                    {
                        if (fieldStruct.IsReference)
                        {
                            // RECORD/CLASS (reference type): the receiver is the object ref already on the stack.
                            _il.Emit(OpCodes.Ldfld, structField);
                        }
                        else
                        {
                            // VALUE-TYPE struct: ldfld needs the value's ADDRESS — spill to a temp and ldloca.
                            var fieldTemp = _il.DeclareLocal(structReceiverType);
                            _il.Emit(OpCodes.Stloc, fieldTemp);
                            _il.Emit(OpCodes.Ldloca, fieldTemp);
                            _il.Emit(OpCodes.Ldfld, structField);
                        }
                        type = structField.FieldType;
                        return true;
                    }
                    if (TryFindPropertyOnChain(fieldStruct, member, out var propAccessor))
                    {
                        if (fieldStruct.IsReference)
                        {
                            // Reference receiver: the object ref is already on the stack.
                            _il.Emit(OpCodes.Callvirt, propAccessor.Getter);
                        }
                        else
                        {
                            // Value receiver: instance accessors need the receiver address.
                            var propertyTemp = _il.DeclareLocal(structReceiverType);
                            _il.Emit(OpCodes.Stloc, propertyTemp);
                            _il.Emit(OpCodes.Ldloca, propertyTemp);
                            _il.Emit(OpCodes.Call, propAccessor.Getter);
                        }
                        type = propAccessor.PropertyType;
                        return true;
                    }
                    return false;
                }
                if (!EmitExpression(Child(idx, 0), out var receiverType))
                    return false;
                if (member == "Length")
                {
                    if (receiverType.IsSZArray)
                    {
                        _il.Emit(OpCodes.Ldlen);     // pushes the array length as a native int...
                        _il.Emit(OpCodes.Conv_I4);   // ...narrowed to int (N# array length is int).
                        type = typeof(int);
                        return true;
                    }
                    if (receiverType == typeof(string))
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(string).GetProperty(nameof(string.Length))!.GetGetMethod()!);
                        type = typeof(int);
                        return true;
                    }
                    if (receiverType == typeof(System.Text.StringBuilder))
                    {
                        _il.Emit(OpCodes.Callvirt, typeof(System.Text.StringBuilder).GetProperty(nameof(System.Text.StringBuilder.Length))!.GetGetMethod()!);
                        type = typeof(int);
                        return true;
                    }
                    return false;
                }
                // `t.ItemN` on a ValueTuple -> ldfld the element (ItemN is a public instance FIELD of ValueTuple).
                // The receiver value (a value type) is already on the stack; ldfld reads the field from it.
                if (IsSupportedValueTuple(receiverType))
                {
                    var itemField = receiverType.GetField(member, BindingFlags.Public | BindingFlags.Instance);
                    if (itemField == null)
                    {
                        return false;
                    }
                    _il.Emit(OpCodes.Ldfld, itemField);
                    type = itemField.FieldType;
                    return true;
                }
                return false;
            }

            case 10: // IndexAccess [object, index] — array element READ (ldelem) or string char READ (get_Chars).
            {        // The index is int; the result type is the element type (array) or char (string).
                if (!EmitExpression(Child(idx, 0), out var indexedType))
                    return false;
                if (indexedType == typeof(string))
                {
                    if (!EmitExpression(Child(idx, 1), out var stringIndexType) || stringIndexType != typeof(int))
                        return false;
                    _il.Emit(OpCodes.Callvirt, typeof(string).GetMethod("get_Chars", new[] { typeof(int) })!);
                    type = typeof(char);
                    return true;
                }
                // A closed List<T>/Dictionary<K,V> indexer READ — callvirt get_Item(int|K) -> T|V (the
                // runtime throws ArgumentOutOfRangeException / KeyNotFoundException exactly as the
                // pipeline's emit does — probe-pinned exception parity). The result type comes from the
                // CLOSED arguments: a REBOUND get_Item reports the OPEN T/TValue as ReturnType
                // (spike-proven) — propagating that would leak an open parameter into downstream typing.
                if (IsSupportedIndexableCollectionType(indexedType))
                {
                    var indexedDef = indexedType.GetGenericTypeDefinition();
                    var idxParamType = indexedDef == typeof(List<>)
                        ? typeof(int)
                        : indexedType.GetGenericArguments()[0];
                    if (!EmitArg(idx, 1, idxParamType))
                        return false;
                    _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(indexedType, indexedDef.GetMethod("get_Item")!));
                    type = indexedDef == typeof(List<>)
                        ? indexedType.GetGenericArguments()[0]
                        : indexedType.GetGenericArguments()[1];
                    return true;
                }
                if (indexedType.IsGenericType && !indexedType.IsGenericTypeDefinition
                    && indexedType.GetGenericTypeDefinition() == typeof(IReadOnlyList<>))
                {
                    if (!EmitArg(idx, 1, typeof(int)))
                        return false;
                    var itemGetter = typeof(IReadOnlyList<>).GetProperty("Item")!.GetGetMethod()!;
                    _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(indexedType, itemGetter));
                    type = indexedType.GetGenericArguments()[0];
                    return true;
                }
                if (indexedType == typeof(IList))
                {
                    if (!EmitArg(idx, 1, typeof(int)))
                        return false;
                    _il.Emit(OpCodes.Callvirt, typeof(IList).GetProperty("Item")!.GetGetMethod()!);
                    type = typeof(object);
                    return true;
                }
                if (!indexedType.IsSZArray)
                    return false;
                var elementType = indexedType.GetElementType()!;
                if (!EmitExpression(Child(idx, 1), out var indexType) || indexType != typeof(int))
                    return false;
                if (elementType == typeof(bool)) _il.Emit(OpCodes.Ldelem_U1);
                else if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(uint)) _il.Emit(OpCodes.Ldelem_U4);
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                // An OPEN generic-parameter element (xs: T[] inside a generic function): the type-operand
                // `ldelem !!T` form loads any element type (spike-proven).
                else if (elementType.IsGenericParameter) _il.Emit(OpCodes.Ldelem, elementType);
                else if (!elementType.IsValueType) _il.Emit(OpCodes.Ldelem_Ref);
                else if (elementType is TypeBuilder || IsSupportedType(elementType)) _il.Emit(OpCodes.Ldelem, elementType);
                else return false; // other element types arrive with their type slices.
                type = elementType;
                return true;
            }

            case 15: // New [type, args...] — `new T[](size)` array allocation, OR `new string(char[], int, int)`
            {        // (the String(char[],int,int) constructor). child[0] is a TYPE subtree (2 = Array, 0 = Simple).
                var typeNode = Child(idx, 0);
                if (_nodes.Kind(typeNode) == 0) // a Simple type -> a constructor call (string or StringBuilder).
                {
                    var newTypeName = Text(typeNode);
                    // Alias/namespace-QUALIFIED user type (`Ids.UserId`): normalize to the
                    // registry's short name — unless the qualifier is a UNION, whose dotted
                    // spelling is case construction and resolves on its own path.
                    if (newTypeName.Contains('.'))
                    {
                        var newTypeQualifier = newTypeName.Substring(0, newTypeName.IndexOf('.'));
                        var newTypeTail = ColumnarTypeCanonicalizer.UnqualifiedTypeName(newTypeName);
                        if (!_unionRegistry.ContainsKey(newTypeQualifier)
                            && (_structRegistry.ContainsKey(newTypeTail) || _enumRegistry.ContainsKey(newTypeTail)))
                            newTypeName = newTypeTail;
                    }
                    if (newTypeName == "string")
                    {
                        if (_nodes.ChildCount(idx) == 3)
                        {
                            if (!EmitArg(idx, 1, typeof(char)) || !EmitArg(idx, 2, typeof(int)))
                                return false;
                            var repeatCtor = typeof(string).GetConstructor(new[] { typeof(char), typeof(int) });
                            if (repeatCtor == null)
                                return false;
                            _il.Emit(OpCodes.Newobj, repeatCtor);
                            type = typeof(string);
                            return true;
                        }
                        // `new string(char[] value, int startIndex, int length)` — copy a char[] slice into a
                        // string. Emit the char[] then the two int args, then `newobj` the String ctor.
                        if (_nodes.ChildCount(idx) != 4)
                            return false;
                        if (!EmitExpression(Child(idx, 1), out var charArrType)
                            || !charArrType.IsSZArray || charArrType.GetElementType() != typeof(char))
                            return false;
                        if (!EmitArg(idx, 2, typeof(int)) || !EmitArg(idx, 3, typeof(int)))
                            return false;
                        var stringCtor = typeof(string).GetConstructor(new[] { typeof(char[]), typeof(int), typeof(int) });
                        if (stringCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, stringCtor);
                        type = typeof(string);
                        return true;
                    }
                    if (newTypeName == "StringBuilder")
                    {
                        // `new System.Text.StringBuilder()` or `new StringBuilder(int capacity)`. (Other ctor overloads
                        // decline.)
                        var ctorArgCount = _nodes.ChildCount(idx) - 1;
                        System.Reflection.ConstructorInfo? sbCtor;
                        if (ctorArgCount == 0)
                            sbCtor = typeof(System.Text.StringBuilder).GetConstructor(Type.EmptyTypes);
                        else if (ctorArgCount == 1)
                            sbCtor = EmitArg(idx, 1, typeof(int))
                                ? typeof(System.Text.StringBuilder).GetConstructor(new[] { typeof(int) })
                                : null;
                        else
                            return false;
                        if (sbCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, sbCtor);
                        type = typeof(System.Text.StringBuilder);
                        return true;
                    }
                    if (newTypeName == "Version")
                    {
                        if (_nodes.ChildCount(idx) != 5
                            || !EmitArg(idx, 1, typeof(int))
                            || !EmitArg(idx, 2, typeof(int))
                            || !EmitArg(idx, 3, typeof(int))
                            || !EmitArg(idx, 4, typeof(int)))
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(Version).GetConstructor(new[] { typeof(int), typeof(int), typeof(int), typeof(int) })!);
                        type = typeof(Version);
                        return true;
                    }
                    if (newTypeName == "object")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(object).GetConstructor(Type.EmptyTypes)!);
                        type = typeof(object);
                        return true;
                    }
                    if (newTypeName == "ProcessStartInfo" || newTypeName == "Process")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        var bclCtorType = newTypeName == "ProcessStartInfo" ? typeof(ProcessStartInfo) : typeof(Process);
                        _il.Emit(OpCodes.Newobj, bclCtorType.GetConstructor(Type.EmptyTypes)!);
                        type = bclCtorType;
                        return true;
                    }
                    if (newTypeName == "JsonSerializerOptions")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(JsonSerializerOptions).GetConstructor(Type.EmptyTypes)!);
                        type = typeof(JsonSerializerOptions);
                        return true;
                    }
                    if (newTypeName == "StreamReader")
                    {
                        if (_nodes.ChildCount(idx) != 2 || !EmitArg(idx, 1, typeof(Stream)))
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(StreamReader).GetConstructor(new[] { typeof(Stream) })!);
                        type = typeof(StreamReader);
                        return true;
                    }
                    if (newTypeName == "JsonElement")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        var jsonElement = _il.DeclareLocal(typeof(JsonElement));
                        _il.Emit(OpCodes.Ldloca, jsonElement);
                        _il.Emit(OpCodes.Initobj, typeof(JsonElement));
                        _il.Emit(OpCodes.Ldloc, jsonElement);
                        type = typeof(JsonElement);
                        return true;
                    }
                    if (newTypeName == "DeserializerBuilder")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(DeserializerBuilder).GetConstructor(Type.EmptyTypes)!);
                        type = typeof(DeserializerBuilder);
                        return true;
                    }
                    if (newTypeName == "Scalar")
                    {
                        if (_nodes.ChildCount(idx) != 2 || !EmitArg(idx, 1, typeof(string)))
                            return false;
                        _il.Emit(OpCodes.Newobj, typeof(Scalar).GetConstructor(new[] { typeof(string) })!);
                        type = typeof(Scalar);
                        return true;
                    }
                    if (newTypeName == "MappingStart" || newTypeName == "MappingEnd")
                    {
                        if (_nodes.ChildCount(idx) != 1)
                            return false;
                        var eventType = newTypeName == "MappingStart" ? typeof(MappingStart) : typeof(MappingEnd);
                        _il.Emit(OpCodes.Newobj, eventType.GetConstructor(Type.EmptyTypes)!);
                        type = eventType;
                        return true;
                    }
                    // WHITELISTED exception constructions (E1/E3): parameterless, one-string, and two-string
                    // ctors of the same exception types accepted by typed catches and BootstrapServices throws.
                    if (TryResolveBclExceptionType(newTypeName, out var exceptionType))
                    {
                        var exceptionArgCount = _nodes.ChildCount(idx) - 1;
                        ConstructorInfo? exceptionCtor;
                        if (exceptionArgCount == 0)
                        {
                            exceptionCtor = exceptionType.GetConstructor(Type.EmptyTypes);
                        }
                        else if (exceptionArgCount == 1)
                        {
                            exceptionCtor = exceptionType.GetConstructor(new[] { typeof(string) });
                            if (exceptionCtor == null || !EmitArg(idx, 1, typeof(string)))
                                return false;
                        }
                        else if (exceptionArgCount == 2)
                        {
                            exceptionCtor = exceptionType.GetConstructor(new[] { typeof(string), typeof(string) });
                            if (exceptionCtor == null || !EmitArg(idx, 1, typeof(string)) || !EmitArg(idx, 2, typeof(string)))
                                return false;
                        }
                        else
                        {
                            return false;
                        }
                        if (exceptionCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, exceptionCtor);
                        type = exceptionType;
                        return true;
                    }
                    if (TryGetUnionCaseByKey(newTypeName, out _, out var positionalCaseDef))
                    {
                        if (positionalCaseDef.UnionBase.IsGenericTypeDefinition)
                            return false;
                        return TryEmitUnionCasePositionalConstruction(positionalCaseDef, Type.EmptyTypes, idx, _nodes.ChildCount(idx) - 1, out type);
                    }
                    if (_structRegistry.TryGetValue(newTypeName, out var defaultCtorDef)
                        && defaultCtorDef.IsReference
                        && defaultCtorDef.DefaultCtor != null
                        && _nodes.ChildCount(idx) == 1)
                    {
                        _il.Emit(OpCodes.Newobj, defaultCtorDef.DefaultCtor);
                        type = defaultCtorDef.Builder;
                        return true;
                    }
                    // A user type with a positional constructor: `new T(args)`. The type names a registered
                    // type with ≥1 user ctor; resolve by arg COUNT first, and when overloads share an arity use a
                    // conservative type preflight to select exactly one compatible signature. Emit each arg
                    // (type-checked against the chosen ctor's param type), then `newobj <ctor>`; the result's type is
                    // the type. (`newobj` on a VALUE type zero-initializes then runs the ctor and pushes the value —
                    // the legacy emitter's probed semantics for partially-assigning struct ctors. Fields-only value
                    // structs construct via object-init.)
                    if (_structRegistry.TryGetValue(newTypeName, out var ctorDef) && ctorDef.Constructors.Count > 0)
                    {
                        if (!TrySelectUserConstructor(idx, ctorDef, out var chosenCtor, out var chosenParamTypes, out var chosenDefaultKinds, out var chosenDefaultTexts))
                        {
                            return false;
                        }
                        var providedCtorArgCount = _nodes.ChildCount(idx) - 1;
                        for (var a = 0; a < chosenParamTypes.Length; a++)
                        {
                            if (a >= providedCtorArgCount)
                            {
                                if (!TryEmitConstructorDefaultArgument(chosenParamTypes[a], chosenDefaultKinds[a], chosenDefaultTexts[a], out _))
                                    return false;
                                continue;
                            }

                            var ctorArgNode = Child(idx, 1 + a);
                            Type ctorArgType;
                            if (TryEmitNullLiteralAsType(ctorArgNode, chosenParamTypes[a], out ctorArgType))
                            {
                                // Null adopted to the declared reference/nullable constructor parameter type.
                            }
                            else if (!EmitExpression(ctorArgNode, out ctorArgType))
                            {
                                return false;
                            }
                            // exact match, or the INTERFACE upcast (an implementer into an
                            // interface-typed ctor param — boxes value implementers, IF-1).
                            if (!TypesEquivalent(ctorArgType, chosenParamTypes![a])
                                && !TryEmitInterfaceUpcast(ctorArgType, chosenParamTypes[a])
                                && !TryEmitReferenceConversion(ctorArgType, chosenParamTypes[a])
                                && !TryEmitObjectConversion(ctorArgType, chosenParamTypes[a]))
                            {
                                return false;
                            }
                        }
                        _il.Emit(OpCodes.Newobj, chosenCtor);
                        type = ctorDef.Builder;
                        return true;
                    }
                    return false; // other Simple-type constructors are a host boundary; decline.
                }
                // `new Box<int>(args)` — CLOSED construction of a user generic type (type node kind 1).
                // Canonicalize the generic subtree, resolve it (MakeGenericType over the open TypeBuilder),
                // bind the user ctor by ARG COUNT on the OPEN definition, check each arg against the
                // POSITIONALLY SUBSTITUTED param type (v: T on Box<int> expects int), then `newobj` the
                // ctor REBOUND onto the closed type (TypeBuilder.GetConstructor — the same machinery the
                // previous parity baseline uses; reflection member queries throw on TypeBuilderInstantiation).
                if (_nodes.Kind(typeNode) == 1)
                {
                    if (!TryBuildTypeNodeCanonical(typeNode, out var closedCanonical))
                    {
                        return false;
                    }
                    if (!TryResolveType(closedCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var closedType))
                    {
                        return false;
                    }
                    // A closed BCL COLLECTION (`new List<int>()` / `new Dictionary<string,int>(10)` / `new HashSet<int>()` /
                    // `new List<Pt>()` over a user TypeBuilder): newobj the parameterless ctor, or the
                    // int-capacity ctor (both probe-pinned legacy-emitter working) — resolved from the OPEN
                    // definition so builder-bound instantiations rebind. Other overloads decline.
                    // (`new List<T>()` inside a generic BODY never reaches here: the canonical resolves
                    // via the typeParams-less TryResolveType, so body-side construction declines — the
                    // generic surface this rung is params/returns/foreach/indexing, pinned.)
                    if (IsSupportedCollectionType(closedType))
                    {
                        var collectionOpenDef = closedType.GetGenericTypeDefinition();
                        var collectionCtorArgs = _nodes.ChildCount(idx) - 1;
                        if (collectionCtorArgs == 0)
                        {
                            _il.Emit(OpCodes.Newobj, ResolveClosedGenericCtor(closedType, collectionOpenDef.GetConstructor(Type.EmptyTypes)!));
                            type = closedType;
                            return true;
                        }
                        if (collectionCtorArgs == 1
                            && CanEmitConstructorArgumentAs(Child(idx, 1), typeof(int))
                            && EmitArg(idx, 1, typeof(int)))
                        {
                            var openCapacityCtor = collectionOpenDef.GetConstructor(new[] { typeof(int) });
                            if (openCapacityCtor == null)
                                return false;
                            _il.Emit(OpCodes.Newobj, ResolveClosedGenericCtor(closedType, openCapacityCtor));
                            type = closedType;
                            return true;
                        }
                        if (collectionCtorArgs == 1
                            && (collectionOpenDef == typeof(Dictionary<,>) || collectionOpenDef == typeof(HashSet<>)))
                        {
                            var keyOrElementType = closedType.GetGenericArguments()[0];
                            var comparerType = typeof(IEqualityComparer<>).MakeGenericType(keyOrElementType);
                            var openComparerCtor = Array.Find(
                                collectionOpenDef.GetConstructors(),
                                ctor =>
                                {
                                    var parameters = ctor.GetParameters();
                                    return parameters.Length == 1
                                        && parameters[0].ParameterType.IsGenericType
                                        && parameters[0].ParameterType.GetGenericTypeDefinition() == typeof(IEqualityComparer<>);
                                });
                            if (openComparerCtor == null || !EmitArg(idx, 1, comparerType))
                                return false;
                            _il.Emit(OpCodes.Newobj, ResolveClosedGenericCtor(closedType, openComparerCtor));
                            type = closedType;
                            return true;
                        }
                        return false;
                    }
                    if (IsSupportedValueTuple(closedType))
                    {
                        var tupleArgTypes = closedType.GetGenericArguments();
                        if (_nodes.ChildCount(idx) - 1 != tupleArgTypes.Length)
                            return false;
                        for (var i = 0; i < tupleArgTypes.Length; i++)
                        {
                            if (!EmitArg(idx, i + 1, tupleArgTypes[i]))
                                return false;
                        }
                        var tupleCtor = closedType.GetConstructor(tupleArgTypes);
                        if (tupleCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, tupleCtor);
                        type = closedType;
                        return true;
                    }
                    if (!IsClosedUserGenericInstantiation(closedType))
                        return false;
                    if (!_structRegistry.TryGetValue(Text(typeNode), out var openGenericDef)
                        || openGenericDef.Constructors.Count == 0)
                        return false; // 0-ctor generic types decline (object-init on closed generics is unmodelled).

                    var closedCtorArgCount = _nodes.ChildCount(idx) - 1;
                    ConstructorBuilder? chosenOpenCtor = null;
                    Type[]? chosenOpenParamTypes = null;
                    var closedAmbiguous = false;
                    foreach (var (cb, cpt, _, _) in openGenericDef.Constructors)
                    {
                        if (cpt.Length != closedCtorArgCount)
                            continue;
                        if (chosenOpenCtor != null) { closedAmbiguous = true; break; }
                        chosenOpenCtor = cb;
                        chosenOpenParamTypes = cpt;
                    }
                    if (chosenOpenCtor == null || closedAmbiguous)
                        return false;

                    var closedTypeArguments = closedType.GetGenericArguments();
                    for (var a = 0; a < closedCtorArgCount; a++)
                    {
                        var expectedArgType = SubstituteClosedTypeArguments(chosenOpenParamTypes![a], closedTypeArguments);
                        if (!EmitExpression(Child(idx, 1 + a), out var closedArgType) || !TypesEquivalent(closedArgType, expectedArgType))
                            return false;
                    }
                    _il.Emit(OpCodes.Newobj, TypeBuilder.GetConstructor(closedType, chosenOpenCtor));
                    type = closedType;
                    return true;
                }
                if (_nodes.ChildCount(idx) != 2 || _nodes.Kind(typeNode) != 2) // array alloc: exactly one ctor arg; type must be Array.
                    return false;
                var elementNode = Child(typeNode, 0); // the array's element type subtree.
                if (!TryBuildTypeNodeCanonical(elementNode, out var elementCanonical)
                    || !TryResolveType(elementCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var newElementType)
                    || !IsSupportedElementType(newElementType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sizeType) || sizeType != typeof(int)) // length: int.
                    return false;
                _il.Emit(OpCodes.Newarr, newElementType);
                type = newElementType.MakeArrayType();
                return true;
            }

            case 16: // Cast [type, operand] — explicit numeric conversion among int/long/char. child[0] is a
            {        // TYPE subtree (Simple); child[1] is the operand. Other casts (to/from string, bool, etc.)
                     // decline (the N# backend path stays authoritative).
                var castTypeNode = Child(idx, 0);
                if (_nodes.Kind(castTypeNode) != 0)
                    return false;
                var castTargetName = Text(castTypeNode);
                if (!TryResolveBuiltin(castTargetName, out var targetType)
                    && !TryResolveType(castTargetName, _enumRegistry, _structRegistry, _unionRegistry, out targetType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sourceType))
                    return false;
                if (TypesEquivalent(sourceType, targetType))
                {
                    type = targetType;
                    return true;
                }
                if (TryEmitUserDefinedConversion(sourceType, targetType, allowExplicit: true))
                {
                    type = targetType;
                    return true;
                }
                if (IsKnownEnumType(targetType))
                {
                    if (IsKnownEnumType(sourceType))
                        sourceType = typeof(int);
                    if (!ColumnarNumericFacts.IsIntPromotable(sourceType))
                        return false;
                    type = targetType;
                    return true;
                }
                if (TryEmitExternalInterfaceUpcast(sourceType, targetType))
                {
                    type = targetType;
                    return true;
                }
                if (!ColumnarNumericFacts.IsCastableScalar(targetType))
                {
                    if (sourceType == typeof(object) && targetType is TypeBuilder targetBuilder && FindDefByBuilder(targetBuilder) is { } targetDef)
                    {
                        _il.Emit(targetDef.IsReference ? OpCodes.Castclass : OpCodes.Unbox_Any, targetBuilder);
                        type = targetType;
                        return true;
                    }
                    if (sourceType == typeof(object) && !targetType.IsValueType)
                    {
                        _il.Emit(OpCodes.Castclass, targetType);
                        type = targetType;
                        return true;
                    }
                    return false;
                }
                // An i4-underlying enum operand is its int on the stack, so `enum as <numeric>` is a cast FROM int:
                // enum->int is identity (no opcode), enum->long/double/etc. widens exactly like int->long/double. The
                // N# backend path emits the same (the underlying-int value, then the same numeric conversion).
                if (IsEnumType(sourceType))
                    sourceType = typeof(int);
                if (!ColumnarNumericFacts.IsCastableScalar(sourceType))
                    return false;
                // Emit the conversion only when the stack representation differs (char->int and same-type casts
                // are no-ops). The opcode is TARGET-driven, matching the N# backend path (TryGetNumericConversionOpcode):
                // -> double = conv.r8, -> float = conv.r4, -> long = conv.i8, -> char = conv.u2, -> int = conv.i4.
                // float/double->int truncates toward zero exactly as the N# backend path's conv.i4 does (same opcode).
                if (sourceType != targetType)
                {
                    // DECIMAL casts route through System.Decimal's conversion operators (not conv opcodes):
                    // TO decimal = op_Implicit(int/long/...)/op_Explicit(double/float); FROM decimal =
                    // op_Explicit(decimal)->target — the exact IL emit.
                    if (targetType == typeof(decimal) || sourceType == typeof(decimal))
                    {
                        var conversionName = targetType == typeof(decimal)
                            && sourceType != typeof(double) && sourceType != typeof(float)
                            ? "op_Implicit" : "op_Explicit";
                        var fromType = targetType == typeof(decimal)
                            ? (ColumnarNumericFacts.IsIntPromotable(sourceType) && sourceType != typeof(char) ? typeof(int) : sourceType)
                            : typeof(decimal);
                        // (small-int sources are already extended i4 — fromType above maps them to the
                        // int operator; char keeps its own op_Implicit(char).)
                        MethodInfo? decimalConversion = null;
                        foreach (var m in typeof(decimal).GetMethods(BindingFlags.Public | BindingFlags.Static))
                        {
                            if (m.Name != conversionName)
                                continue;
                            var ps = m.GetParameters();
                            if (ps.Length == 1 && ps[0].ParameterType == fromType && m.ReturnType == (targetType == typeof(decimal) ? typeof(decimal) : targetType))
                            {
                                decimalConversion = m;
                                break;
                            }
                        }
                        if (decimalConversion == null)
                            return false;
                        _il.Emit(OpCodes.Call, decimalConversion);
                        type = targetType;
                        return true;
                    }
                    if (targetType == typeof(double)) _il.Emit(OpCodes.Conv_R8);      // any numeric -> double (widen)
                    else if (targetType == typeof(float)) _il.Emit(OpCodes.Conv_R4);  // any numeric -> float
                    else if (targetType == typeof(long)) _il.Emit(OpCodes.Conv_I8);   // i4-slot/double/float -> long (sign-extend)
                    else if (targetType == typeof(ulong)) _il.Emit(sourceType == typeof(uint) ? OpCodes.Conv_U8 : OpCodes.Conv_I8); // N# unchecked: int sign-extends, uint zero-extends
                    else if (targetType == typeof(char)) _il.Emit(OpCodes.Conv_U2);   // -> char (truncate)
                    else if (targetType == typeof(byte)) _il.Emit(OpCodes.Conv_U1);   // -> byte (truncate)
                    else if (targetType == typeof(sbyte)) _il.Emit(OpCodes.Conv_I1);  // -> sbyte (truncate)
                    else if (targetType == typeof(short)) _il.Emit(OpCodes.Conv_I2);  // -> short (truncate)
                    else if (targetType == typeof(ushort)) _il.Emit(OpCodes.Conv_U2); // -> ushort (truncate)
                    else if (targetType == typeof(uint) || targetType == typeof(int))
                    {
                        // -> int/uint: i8/r8/r4 sources truncate to the i4 slot; i4-slot sources are identity
                        // (N# unchecked emits nothing for int<->uint<->small-int slot-mates).
                        if (sourceType == typeof(long) || sourceType == typeof(ulong) || sourceType == typeof(double) || sourceType == typeof(float))
                            _il.Emit(targetType == typeof(uint) ? OpCodes.Conv_U4 : OpCodes.Conv_I4);
                    }
                }
                type = targetType;
                return true;
            }

            case 17: // Tuple [e0, e1, ...] — construct a positional System.ValueTuple<...>: emit each element value
            {        // (left-to-right, the ctor's argument order), then `newobj` the matching ValueTuple ctor.
                     // Arity 2-7 (a 1-tuple is not a tuple; >7 needs the nested TRest form — both decline).
                var arity = _nodes.ChildCount(idx);
                Type? openTuple = arity switch
                {
                    2 => typeof(ValueTuple<,>),
                    3 => typeof(ValueTuple<,,>),
                    4 => typeof(ValueTuple<,,,>),
                    5 => typeof(ValueTuple<,,,,>),
                    6 => typeof(ValueTuple<,,,,,>),
                    7 => typeof(ValueTuple<,,,,,,>),
                    _ => null,
                };
                if (openTuple == null)
                    return false;
                var elementTypes = new Type[arity];
                for (var i = 0; i < arity; i++)
                {
                    // A NAMED element (kind-43 wrapper, `(x: 1, y: 2)`) emits its VALUE child — names are
                    // compile-time metadata (the `:=` declaration path records them for member access).
                    var elementNode = Child(idx, i);
                    if (_nodes.Kind(elementNode) == 43)
                        elementNode = Child(elementNode, 0);
                    // ContainsBuilderBoundType: a builder-bound element (a record, a List<Pt>) would make
                    // the closed ValueTuple a TypeBuilderInstantiation whose GetConstructor below throws —
                    // decline cleanly instead (the IsSupportedValueTuple element rule, applied at emission).
                    if (!EmitExpression(elementNode, out var elemType) || !IsSupportedType(elemType)
                        || ContainsBuilderBoundType(elemType))
                        return false;
                    elementTypes[i] = elemType;
                }
                var tupleType = openTuple.MakeGenericType(elementTypes);
                var tupleCtor = tupleType.GetConstructor(elementTypes);
                if (tupleCtor == null)
                    return false;
                _il.Emit(OpCodes.Newobj, tupleCtor);
                type = tupleType;
                return true;
            }

            case 42: // BareNew [typeRoot] — `new <type>` with neither `( args )` nor `{ inits }`. Modelled ONLY for
            {        // UNION CASES (the pipeline's brace-less construction form — fields stay CLR-default, probe-
                     // pinned): `new Color.Red` (Simple root) and `new Opt.None<int>` (Generic root with explicit
                     // args). A generic case with NO args is the adoption shape — handled at the return/typed-local
                     // statement sites; reaching here declines (`:=` is NL207). Every non-union-case type root
                     // (struct/BCL/array) declines — those bare-new forms are not modelled.
                var bareRoot = Child(idx, 0);
                if (_nodes.Kind(bareRoot) == 0 && TryGetUnionCaseByKey(Text(bareRoot), out _, out var bareCaseDef))
                {
                    if (bareCaseDef.UnionBase.IsGenericTypeDefinition)
                        return false;
                    return TryEmitUnionCaseConstruction(bareCaseDef, Type.EmptyTypes, idx, 0, out type);
                }
                if (_nodes.Kind(bareRoot) == 1 && TryGetUnionCaseByKey(Text(bareRoot), out _, out var bareGenericCaseDef)
                    && bareGenericCaseDef.UnionBase.IsGenericTypeDefinition
                    && TryResolveUnionCaseTypeArgs(bareRoot, bareGenericCaseDef, out var bareArgs))
                {
                    return TryEmitUnionCaseConstruction(bareGenericCaseDef, bareArgs, idx, 0, out type);
                }
                return false;
            }

            case 36: // ObjectInitializer [typeRoot, name0, value0, ...] — `new Struct { Field: value, ... }`. Build a
            {        // user-struct value: a temp local, `ldloca; initobj` (zero all fields), then per named field
                     // `ldloca; <value>; stfld <FieldBuilder>`, then `ldloc` the temp. Mirrors the struct
                     // object-initializer (default + per-field assignment). Only a registered struct type is modelled.
                     // A `new Union.Case { f: v }` object-init (a reference type like a record) is handled first.
                var typeRootNode = Child(idx, 0);
                var initChildCount = _nodes.ChildCount(idx);
                if ((initChildCount % 2) != 1) // typeRoot + (name, value) pairs.
                    return false;
                var pairCount = (initChildCount - 1) / 2;

                if (_nodes.Kind(typeRootNode) == 0)
                {
                    Type? bclInitType = Text(typeRootNode) switch
                    {
                        "JsonSerializerOptions" => typeof(JsonSerializerOptions),
                        "ProcessStartInfo" => typeof(ProcessStartInfo),
                        "Process" => typeof(Process),
                        _ => null,
                    };
                    if (bclInitType != null)
                    {
                        var defaultCtor = bclInitType.GetConstructor(Type.EmptyTypes);
                        if (defaultCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, defaultCtor);
                        var assignedBclMembers = new HashSet<string>(StringComparer.Ordinal);
                        for (var p = 0; p < pairCount; p++)
                        {
                            var nameNode = Child(idx, 1 + (2 * p));
                            var valueNode = Child(idx, 2 + (2 * p));
                            if (_nodes.Kind(nameNode) != 6)
                                return false;
                            var memberName = Text(nameNode);
                            if (!assignedBclMembers.Add(memberName))
                                return false;
                            var property = bclInitType.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance);
                            if (property?.SetMethod == null)
                                return false;
                            _il.Emit(OpCodes.Dup);
                            var propertyType = property.PropertyType;
                            Type propertyValueType;
                            if (TryEmitNullLiteralAsType(valueNode, propertyType, out propertyValueType))
                            {
                                // Null adopted to the declared reference property type.
                            }
                            else if (!EmitExpression(valueNode, out propertyValueType))
                            {
                                return false;
                            }
                            if (!TypesEquivalent(propertyValueType, propertyType)
                                && !TryEmitImplicitWidening(propertyValueType, propertyType)
                                && !TryEmitInterfaceUpcast(propertyValueType, propertyType)
                                && !TryEmitReferenceConversion(propertyValueType, propertyType)
                                && !TryEmitObjectConversion(propertyValueType, propertyType))
                                return false;
                            _il.Emit(property.SetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, property.SetMethod);
                        }
                        type = bclInitType;
                        return true;
                    }
                }

                if (_nodes.Kind(typeRootNode) == 15)
                {
                    if (!EmitExpression(typeRootNode, out var constructedType))
                        return false;
                    var assignedMembers = new HashSet<string>(StringComparer.Ordinal);
                    for (var p = 0; p < pairCount; p++)
                    {
                        var nameNode = Child(idx, 1 + (2 * p));
                        var valueNode = Child(idx, 2 + (2 * p));
                        if (_nodes.Kind(nameNode) != 6)
                            return false;
                        var memberName = Text(nameNode);
                        if (!assignedMembers.Add(memberName))
                            return false;

                        ColumnarStructDef? constructedUserDef = null;
                        var constructedClosedArgs = Array.Empty<Type>();
                        if (constructedType is TypeBuilder constructedBuilder)
                        {
                            constructedUserDef = FindDefByBuilder(constructedBuilder);
                        }
                        else if (TryGetClosedReceiverDef(constructedType, out var closedConstructedDef, out var closedConstructedArgs))
                        {
                            constructedUserDef = closedConstructedDef;
                            constructedClosedArgs = closedConstructedArgs;
                        }

                        if (constructedUserDef != null)
                        {
                            if (!constructedUserDef.IsReference)
                            {
                                return false;
                            }
                            if (TryFindPropertyOnChain(constructedUserDef, memberName, out var userInitProperty))
                            {
                                if (userInitProperty.Setter == null)
                                {
                                    return false;
                                }
                                var propertyType = constructedClosedArgs.Length == 0
                                    ? userInitProperty.PropertyType
                                    : SubstituteClosedTypeArguments(userInitProperty.PropertyType, constructedClosedArgs);
                                _il.Emit(OpCodes.Dup);
                                Type propertyValueType;
                                if (TryEmitNullLiteralAsType(valueNode, propertyType, out propertyValueType))
                                {
                                    // Null adopted to the declared reference/nullable property type.
                                }
                                else if (!EmitExpression(valueNode, out propertyValueType))
                                {
                                    return false;
                                }
                                if (!TypesEquivalent(propertyValueType, propertyType)
                                    && !TryEmitImplicitWidening(propertyValueType, propertyType)
                                    && !TryEmitInterfaceUpcast(propertyValueType, propertyType)
                                    && !TryEmitReferenceConversion(propertyValueType, propertyType)
                                    && !TryEmitObjectConversion(propertyValueType, propertyType))
                                {
                                    return false;
                                }
                                var userSetter = constructedClosedArgs.Length == 0
                                    ? userInitProperty.Setter
                                    : TypeBuilder.GetMethod(constructedType, userInitProperty.Setter);
                                _il.Emit(OpCodes.Callvirt, userSetter);
                                continue;
                            }

                            if (TryFindFieldOnChain(constructedUserDef, memberName, out var userInitField))
                            {
                                var userFieldType = constructedClosedArgs.Length == 0
                                    ? userInitField.FieldType
                                    : SubstituteClosedTypeArguments(userInitField.FieldType, constructedClosedArgs);
                                _il.Emit(OpCodes.Dup);
                                Type userFieldValueType;
                                if (TryEmitNullLiteralAsType(valueNode, userFieldType, out userFieldValueType))
                                {
                                    // Null adopted to the declared reference/nullable field type.
                                }
                                else if (!EmitExpression(valueNode, out userFieldValueType))
                                {
                                    return false;
                                }
                                if (!TypesEquivalent(userFieldValueType, userFieldType)
                                    && !TryEmitImplicitWidening(userFieldValueType, userFieldType)
                                    && !TryEmitInterfaceUpcast(userFieldValueType, userFieldType)
                                    && !TryEmitReferenceConversion(userFieldValueType, userFieldType)
                                    && !TryEmitObjectConversion(userFieldValueType, userFieldType))
                                {
                                    return false;
                                }
                                _il.Emit(OpCodes.Stfld, constructedClosedArgs.Length == 0
                                    ? userInitField
                                    : TypeBuilder.GetField(constructedType, userInitField));
                                continue;
                            }
                            return false;
                        }

                        _il.Emit(OpCodes.Dup);
                        var property = constructedType.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance);
                        if (property?.SetMethod != null)
                        {
                            var propertyType = property.PropertyType;
                            Type propertyValueType;
                            if (TryEmitNullLiteralAsType(valueNode, propertyType, out propertyValueType))
                            {
                                // Null adopted to the declared reference/nullable property type.
                            }
                            else if (!EmitExpression(valueNode, out propertyValueType))
                            {
                                return false;
                            }
                            if (!TypesEquivalent(propertyValueType, propertyType)
                                && !TryEmitImplicitWidening(propertyValueType, propertyType)
                                && !TryEmitInterfaceUpcast(propertyValueType, propertyType)
                                && !TryEmitReferenceConversion(propertyValueType, propertyType)
                                && !TryEmitObjectConversion(propertyValueType, propertyType))
                                return false;
                            _il.Emit(property.SetMethod.IsVirtual ? OpCodes.Callvirt : OpCodes.Call, property.SetMethod);
                            continue;
                        }

                        var field = constructedType.GetField(memberName, BindingFlags.Public | BindingFlags.Instance);
                        if (field == null)
                            return false;
                        var fieldType = field.FieldType;
                        Type fieldValueType;
                        if (TryEmitNullLiteralAsType(valueNode, fieldType, out fieldValueType))
                        {
                            // Null adopted to the declared reference/nullable field type.
                        }
                        else if (!EmitExpression(valueNode, out fieldValueType))
                        {
                            return false;
                        }
                        if (!TypesEquivalent(fieldValueType, fieldType)
                            && !TryEmitImplicitWidening(fieldValueType, fieldType)
                            && !TryEmitInterfaceUpcast(fieldValueType, fieldType)
                            && !TryEmitReferenceConversion(fieldValueType, fieldType)
                            && !TryEmitObjectConversion(fieldValueType, fieldType))
                            return false;
                        _il.Emit(OpCodes.Stfld, field);
                    }
                    type = constructedType;
                    return true;
                }

                // CLOSED GENERIC UNION CASE: `new Union.Case<args> { field: value, ... }` — a Generic type root
                // (kind 1) whose dotted head names a registered union case of a GENERIC union. The explicit
                // arguments (after the CASE name — the pinned N# surface) close the case and the result's static
                // type is the BASE closed over the same arguments.
                if (_nodes.Kind(typeRootNode) == 1 && TryGetUnionCaseByKey(Text(typeRootNode), out _, out var genericInitCaseDef))
                {
                    if (!genericInitCaseDef.UnionBase.IsGenericTypeDefinition
                        || !TryResolveUnionCaseTypeArgs(typeRootNode, genericInitCaseDef, out var explicitArgs))
                        return false;
                    return TryEmitUnionCaseConstruction(genericInitCaseDef, explicitArgs, idx, pairCount, out type);
                }

                // CLOSED GENERIC object-init: `new Pair<int> { first: 1, ... }` — a Generic type root
                // (kind 1) whose head names a registered generic RECORD/default-ctor CLASS or a VALUE
                // struct. The default ctor (for reference types) and every field handle are REBOUND onto
                // the instantiation (TypeBuilder.GetConstructor/GetField, the union-construction
                // machinery's analog) and each field's expected value type substitutes the arguments
                // positionally (`first: T` on Pair<int> expects int). Value structs mirror the non-generic
                // struct path: temp local, initobj, then address-based field stores. A user-ctor class has
                // no default ctor — object-init declines exactly like the non-generic rule below.
                if (_nodes.Kind(typeRootNode) == 1 && _structRegistry.TryGetValue(Text(typeRootNode), out var closedInitDef)
                    && closedInitDef.Builder.IsGenericTypeDefinition)
                {
                    // A user GENERIC type named List/Dictionary/HashSet: the pipeline's analyzer binds the BCL
                    // head for `new List<int> { ... }` and rejects its members (NL303, probe-pinned) —
                    // the user definition must not claim the construction. Decline (parity by rejection).
                    if (Text(typeRootNode) is "List" or "Dictionary" or "HashSet")
                        return false;
                    var closedArity = closedInitDef.Builder.GetGenericArguments().Length;
                    if (_nodes.ChildCount(typeRootNode) != closedArity)
                        return false;
                    var closedInitArgs = new Type[closedArity];
                    for (var i = 0; i < closedArity; i++)
                    {
                        if (!TryBuildTypeNodeCanonical(Child(typeRootNode, i), out var closedArgCanonical)
                            || !TryResolveType(closedArgCanonical, _enumRegistry, _structRegistry, _unionRegistry, out closedInitArgs[i])
                            || !IsSupportedType(closedInitArgs[i]))
                            return false;
                    }
                    var closedInitType = closedInitDef.Builder.MakeGenericType(closedInitArgs);
                    var closedAssigned = new HashSet<string>(StringComparer.Ordinal);

                    if (closedInitDef.IsReference)
                    {
                        if (closedInitDef.DefaultCtor == null)
                            return false;
                        _il.Emit(OpCodes.Newobj, TypeBuilder.GetConstructor(closedInitType, closedInitDef.DefaultCtor));
                        for (var p = 0; p < pairCount; p++)
                        {
                            var nameNode = Child(idx, 1 + (2 * p));
                            var valueNode = Child(idx, 2 + (2 * p));
                            if (_nodes.Kind(nameNode) != 6)
                                return false;
                            var fieldName = Text(nameNode);
                            if (!closedInitDef.Fields.TryGetValue(fieldName, out var openInitField) || !closedAssigned.Add(fieldName))
                                return false; // unknown or duplicately-assigned field -> decline.
                            var expectedInitType = SubstituteClosedTypeArguments(openInitField.FieldType, closedInitArgs);
                            _il.Emit(OpCodes.Dup);
                            if (!EmitExpression(valueNode, out var closedInitValueType)
                                || (!TypesEquivalent(closedInitValueType, expectedInitType) && !TryEmitInterfaceUpcast(closedInitValueType, expectedInitType) && !TryEmitReferenceConversion(closedInitValueType, expectedInitType) && !TryEmitObjectConversion(closedInitValueType, expectedInitType)))
                                return false;
                            _il.Emit(OpCodes.Stfld, TypeBuilder.GetField(closedInitType, openInitField));
                        }
                        type = closedInitType;
                        return true;
                    }

                    var closedStructValue = _il.DeclareLocal(closedInitType);
                    _il.Emit(OpCodes.Ldloca, closedStructValue);
                    _il.Emit(OpCodes.Initobj, closedInitType);
                    for (var p = 0; p < pairCount; p++)
                    {
                        var nameNode = Child(idx, 1 + (2 * p));
                        var valueNode = Child(idx, 2 + (2 * p));
                        if (_nodes.Kind(nameNode) != 6)
                            return false;
                        var fieldName = Text(nameNode);
                        if (!closedInitDef.Fields.TryGetValue(fieldName, out var openInitField) || !closedAssigned.Add(fieldName))
                            return false; // unknown or duplicately-assigned field -> decline.
                        var expectedInitType = SubstituteClosedTypeArguments(openInitField.FieldType, closedInitArgs);
                        _il.Emit(OpCodes.Ldloca, closedStructValue);
                        if (!EmitExpression(valueNode, out var closedInitValueType)
                            || (!TypesEquivalent(closedInitValueType, expectedInitType) && !TryEmitInterfaceUpcast(closedInitValueType, expectedInitType) && !TryEmitReferenceConversion(closedInitValueType, expectedInitType) && !TryEmitObjectConversion(closedInitValueType, expectedInitType)))
                            return false;
                        _il.Emit(OpCodes.Stfld, TypeBuilder.GetField(closedInitType, openInitField));
                    }
                    _il.Emit(OpCodes.Ldloc, closedStructValue);
                    type = closedInitType;
                    return true;
                }

                if (_nodes.Kind(typeRootNode) != 0)
                    return false; // not a Simple type-ref.
                var assigned = new HashSet<string>(StringComparer.Ordinal);

                // UNION CASE: `new Union.Case { field: value, ... }` — the dotted type name resolves to a registered
                // union case (a sealed reference type). `newobj <case ctor>` then per named field `dup; <value>;
                // stfld`. The expression's STATIC type is the union BASE (an upcast — the runtime object is the
                // concrete case), so the result flows wherever a `Union` is expected and a later match recovers it.
                // A GENERIC union's case with NO explicit arguments is the expected-type ADOPTION shape, modelled
                // ONLY at the return/typed-local statement sites (which pre-handle it before EmitExpression) — the
                // pipeline rejects every other argument-less position (`:=` is NL207, call-argument adoption NL103),
                // so reaching here with a generic case declines.
                if (TryGetUnionCaseByKey(Text(typeRootNode), out _, out var initCaseDef))
                {
                    if (initCaseDef.UnionBase.IsGenericTypeDefinition)
                        return false;
                    return TryEmitUnionCaseConstruction(initCaseDef, Type.EmptyTypes, idx, pairCount, out type);
                }

                if (!_structRegistry.TryGetValue(Text(typeRootNode), out var initStructDef))
                    return false; // not a registered struct/record/union-case type.
                if (initStructDef.Builder.IsGenericTypeDefinition)
                    return false; // a GENERIC type's bare name is an arity error (NL207) — `new Pair { ... }`
                                  // never constructs the open definition; the closed form is the kind-1 branch.
                if (initStructDef.IsReference)
                {
                    // RECORD/CLASS (reference type): `newobj <default ctor>` then per named field `dup; <value>;
                    // stfld`. The object ref stays on the stack between assignments (and as the result) via dup —
                    // mirrors N#'s reference-type object initializer. A class with a USER constructor has NO default
                    // (parameterless) ctor, so object-init on it declines (it must be constructed positionally).
                    if (initStructDef.DefaultCtor == null)
                        return false;
                    _il.Emit(OpCodes.Newobj, initStructDef.DefaultCtor);
                    for (var p = 0; p < pairCount; p++)
                    {
                        var nameNode = Child(idx, 1 + (2 * p));
                        var valueNode = Child(idx, 2 + (2 * p));
                        if (_nodes.Kind(nameNode) != 6)
                            return false;
                        var fieldName = Text(nameNode);
                        if (!assigned.Add(fieldName))
                            return false;
                        if (TryFindPropertyOnChain(initStructDef, fieldName, out var initProperty))
                        {
                            if (initProperty.Setter == null)
                                return false;
                            _il.Emit(OpCodes.Dup);
                            Type initPropertyValueType;
                            if (TryEmitNullLiteralAsType(valueNode, initProperty.PropertyType, out initPropertyValueType))
                            {
                                // Null adopted to the declared reference/nullable property type.
                            }
                            else if (!EmitExpression(valueNode, out initPropertyValueType))
                            {
                                return false;
                            }
                            if (!TypesEquivalent(initPropertyValueType, initProperty.PropertyType)
                                && !TryEmitImplicitWidening(initPropertyValueType, initProperty.PropertyType)
                                && !TryEmitInterfaceUpcast(initPropertyValueType, initProperty.PropertyType)
                                && !TryEmitReferenceConversion(initPropertyValueType, initProperty.PropertyType)
                                && !TryEmitObjectConversion(initPropertyValueType, initProperty.PropertyType))
                                return false;
                            _il.Emit(OpCodes.Callvirt, initProperty.Setter);
                            continue;
                        }
                        if (!initStructDef.Fields.TryGetValue(fieldName, out var initField))
                            return false;
                        _il.Emit(OpCodes.Dup);
                        // TypesEquivalent, not !=: a builder-bound collection field's declared type and the
                        // init value's type come from independent resolutions (referentially distinct TBIs).
                        if (!EmitExpression(valueNode, out var initValueType)
                            || (!TypesEquivalent(initValueType, initField.FieldType) && !TryEmitImplicitWidening(initValueType, initField.FieldType) && !TryEmitInterfaceUpcast(initValueType, initField.FieldType) && !TryEmitReferenceConversion(initValueType, initField.FieldType) && !TryEmitObjectConversion(initValueType, initField.FieldType)))
                            return false;
                        _il.Emit(OpCodes.Stfld, initField);
                    }
                    type = initStructDef.Builder;
                    return true;
                }
                // VALUE-TYPE struct: a temp local, ldloca; initobj (zero defaults), then per field ldloca; <value>;
                // stfld, then ldloc the temp.
                var structValue = _il.DeclareLocal(initStructDef.Builder);
                _il.Emit(OpCodes.Ldloca, structValue);
                _il.Emit(OpCodes.Initobj, initStructDef.Builder);
                for (var p = 0; p < pairCount; p++)
                {
                    var nameNode = Child(idx, 1 + (2 * p));
                    var valueNode = Child(idx, 2 + (2 * p));
                    if (_nodes.Kind(nameNode) != 6)
                        return false;
                    var fieldName = Text(nameNode);
                    if (!initStructDef.Fields.TryGetValue(fieldName, out var initField) || !assigned.Add(fieldName))
                        return false; // unknown or duplicately-assigned field -> decline.
                    _il.Emit(OpCodes.Ldloca, structValue);
                    if (!EmitExpression(valueNode, out var initValueType)
                        || (!TypesEquivalent(initValueType, initField.FieldType) && !TryEmitInterfaceUpcast(initValueType, initField.FieldType) && !TryEmitReferenceConversion(initValueType, initField.FieldType) && !TryEmitObjectConversion(initValueType, initField.FieldType)))
                        return false;
                    _il.Emit(OpCodes.Stfld, initField);
                }
                _il.Emit(OpCodes.Ldloc, structValue);
                type = initStructDef.Builder;
                return true;
            }

            case 52: // WithExpression [receiver, name0, value0, ...] — `r with { Field: v, ... }`: callvirt
            {        // the synthesized `<Clone>$` (PASS 0e), then stfld each named field on the clone — the
                     // legacy emitter's EmitWithExpression verbatim. Receivers: NON-GENERIC records carrying the
                     // synthesis; classes decline (their `with` falls to a raw cross-type MemberwiseClone
                     // call legacy-emitter side — unverifiable IL), generic records decline (the legacy emitter's
                     // with-on-generic emit is the known-broken B4 residual), builder-typed-field records
                     // decline (no synthesis). Zero pairs = a pure clone.
                if ((_nodes.ChildCount(idx) & 1) == 0)
                    return Decline("emit.with.shape", "with expression has an unsupported shape", idx);
                if (!EmitExpression(Child(idx, 0), out var withReceiverType))
                    return Decline("emit.with.receiver", "with expression receiver could not be emitted", Child(idx, 0));
                if (withReceiverType is not TypeBuilder withTb
                    || FindDefByBuilder(withTb) is not { IsRecord: true, RecordClone: not null } withDef)
                    return Decline("emit.with.clone", "with expression receiver type does not have a modeled record clone", Child(idx, 0));
                _il.Emit(OpCodes.Callvirt, withDef.RecordClone);
                var cloneLocal = _il.DeclareLocal(withReceiverType);
                _il.Emit(OpCodes.Stloc, cloneLocal);
                for (var p = 1; p + 1 < _nodes.ChildCount(idx); p += 2)
                {
                    var withNameChild = Child(idx, p);
                    if (_nodes.Kind(withNameChild) != 6 || _nodes.ValueStart(withNameChild) < 0)
                        return Decline("emit.with.field-name", "with expression field name is not modeled", withNameChild);
                    if (!withDef.Fields.TryGetValue(Text(withNameChild), out var withField))
                        return Decline("emit.with.field", "with expression field '" + Text(withNameChild) + "' does not exist on receiver type", withNameChild);
                    _il.Emit(OpCodes.Ldloc, cloneLocal);
                    if (TryEmitIntLiteralAsType(Child(idx, p + 1), withField.FieldType, out var withValueType))
                    {
                        // constant adoption (`with { X: 10 }` on a small-int field).
                    }
                    else if (!EmitExpression(Child(idx, p + 1), out withValueType))
                    {
                        return Decline("emit.with.value", "with expression value for field '" + Text(withNameChild) + "' could not be emitted", Child(idx, p + 1));
                    }
                    if (!TypesEquivalent(withValueType, withField.FieldType) && !TryEmitImplicitWidening(withValueType, withField.FieldType) && !TryEmitReferenceConversion(withValueType, withField.FieldType) && !TryEmitObjectConversion(withValueType, withField.FieldType))
                        return Decline("emit.with.type-mismatch", "with expression value type '" + withValueType.FullName + "' does not match field type '" + withField.FieldType.FullName + "'", Child(idx, p + 1));
                    _il.Emit(OpCodes.Stfld, withField);
                }
                _il.Emit(OpCodes.Ldloc, cloneLocal);
                type = withReceiverType;
                return true;
            }

            case 44: // PostfixUnary [target] — `n++` / `n--` in EXPRESSION position: N# post-semantics, the
            {        // value is the PRE-step value. Bare LOCAL/PARAM targets of int/long/ulong only (the
                     // pipeline's double/float `++` silently NO-OPS — an known defect; columnar declines those
                     // so it never diverges). Lifted/boxed targets decline (capture rung).
                if (!TryEmitPostfixUnary(idx, keepValue: true, out type))
                    return false;
                return true;
            }

            case 46: // IsExpression [value, typeRoot] — `value is Type`: `isinst <T>; ldnull; cgt.un` ->
            case 47: // bool; AsExpression [value, typeRoot] — `value as Type`: `isinst <T>` keeping the
            {        // target type (null on mismatch). The typeRoot resolves a UNION CASE (closed over a
                     // generic scrutinee via the match machinery) or a registered REFERENCE type; value
                     // types and unresolvable targets decline (`as` with a value type is pipeline-rejected).
                if (_nodes.ChildCount(idx) != 2 || !EmitExpression(Child(idx, 0), out var testedType))
                    return false;
                // A value-struct union has no reference identity: `is U.Case` is an integer tag test and an `is`/`as`
                // against ANY reference target boxes the value before isinst (N# value-type `as`/`is` semantics). An
                // isinst against the unboxed struct would be invalid IL. Decline so the previous parity baseline, which owns that
                // boxing/tag lowering, handles every value-struct-union is/as form uniformly.
                if (IsValueStructUnionType(testedType))
                    return false;
                var isAsTypeRoot = Child(idx, 1);
                Type? targetTestType = null;
                if (_nodes.Kind(isAsTypeRoot) == 0)
                {
                    var isAsName = Text(isAsTypeRoot);
                    if (TryGetUnionCaseByKey(isAsName, out _, out _))
                    {
                        if (!TryGetCaseTestType(isAsName, testedType, out _, out targetTestType, out _))
                            return false; // not a case of the scrutinee's union — the pipeline rejects.
                    }
                    else if (TryResolveType(isAsName, _enumRegistry, _structRegistry, _unionRegistry, out var plainTarget)
                        && !plainTarget.IsValueType)
                    {
                        targetTestType = plainTarget;
                    }
                }
                if (targetTestType == null)
                    return false;
                _il.Emit(OpCodes.Isinst, targetTestType);
                if (_nodes.Kind(idx) == 46)
                {
                    _il.Emit(OpCodes.Ldnull);
                    _il.Emit(OpCodes.Cgt_Un);
                    type = typeof(bool);
                }
                else
                {
                    type = targetTestType;
                }
                return true;
            }

            case 45: // MustExpression [operand] — `must x`, the prefix null-assert (the legacy emitter's
            {        // EmitMustExpression mirror): a NULLABLE<T> unwraps via HasValue/get_Value (throwing
                     // InvalidOperationException("must unwrap failed: value was null") when empty — the EXACT
                     // pipeline message); a REFERENCE null-checks dup/brtrue/pop/throw keeping its type; a
                     // plain VALUE type passes through unchanged (the pipeline's no-op).
                if (_nodes.ChildCount(idx) != 1 || !EmitExpression(Child(idx, 0), out var mustType))
                    return false;
                if (IsSupportedNullable(mustType))
                {
                    var mustElement = mustType.GetGenericArguments()[0];
                    var mustLocal = _il.DeclareLocal(mustType);
                    _il.Emit(OpCodes.Stloc, mustLocal);
                    var mustOk = _il.DefineLabel();
                    _il.Emit(OpCodes.Ldloca, mustLocal);
                    _il.Emit(OpCodes.Call, mustType.GetMethod("get_HasValue")!);
                    _il.Emit(OpCodes.Brtrue, mustOk);
                    _il.Emit(OpCodes.Ldstr, "must unwrap failed: value was null");
                    _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                    _il.Emit(OpCodes.Throw);
                    _il.MarkLabel(mustOk);
                    _il.Emit(OpCodes.Ldloca, mustLocal);
                    _il.Emit(OpCodes.Call, mustType.GetMethod("get_Value")!);
                    type = mustElement;
                    return true;
                }
                if (!mustType.IsValueType)
                {
                    var refOk = _il.DefineLabel();
                    _il.Emit(OpCodes.Dup);
                    _il.Emit(OpCodes.Brtrue, refOk);
                    _il.Emit(OpCodes.Pop);
                    _il.Emit(OpCodes.Ldstr, "must unwrap failed: value was null");
                    _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                    _il.Emit(OpCodes.Throw);
                    _il.MarkLabel(refOk);
                    type = mustType;
                    return true;
                }
                // a plain VALUE type: the pipeline REJECTS redundant `must` (NL907 — the analyzer
                // gates it before the emitter's no-op would run) — decline so the N# backend path reports it.
                return false;
            }

            case 13: // Ternary [cond, then, else] — `cond ? then : else`, a branch/merge with ONE result on the
            {        // stack. Both arms must produce the SAME type (TypesEquivalent — the match-arm unification
                     // rule); MIXED-type arms decline to the N# backend path (its implicit-conversion unification is a
                     // widening-slice concern). The condition emits through the shared bool gate.
                if (_nodes.ChildCount(idx) != 3)
                    return false;
                if (!EmitCondition(Child(idx, 0)))
                    return false;
                var ternaryElse = _il.DefineLabel();
                var ternaryEnd = _il.DefineLabel();
                _il.Emit(OpCodes.Brfalse, ternaryElse);
                if (!EmitExpression(Child(idx, 1), out var ternaryThenType))
                    return false;
                _il.Emit(OpCodes.Br, ternaryEnd);
                _il.MarkLabel(ternaryElse);
                if (!EmitExpression(Child(idx, 2), out var ternaryElseType) || !TypesEquivalent(ternaryThenType, ternaryElseType))
                    return false;
                _il.MarkLabel(ternaryEnd);
                type = ternaryThenType;
                return true;
            }

            case 18: // Match [value, pat0, res0, pat1, res1, ...] — `match value { p => r, ... }`, lowered to a
            {        // linear chain mirroring the match-expression emitter: eval value -> temp; per case test the
                     // pattern, on match eval the result + br end; no match -> throw. An EXPRESSION: leaves one
                     // result on the stack. Patterns: a LITERAL (equality test) or an identifier (`_` discard or a
                     // binding that always matches and binds the matched value); a pattern may carry a `when` guard
                     // (kind 19 [pattern, guard]) tested after the pattern; richer patterns decline.
                var childCount = _nodes.ChildCount(idx);
                if (childCount < 3 || (childCount % 2) == 0) // value + >=1 (pattern, result) pair.
                    return false;
                var caseCount = (childCount - 1) / 2;

                if (!EmitExpression(Child(idx, 0), out var matchValueType) || !IsSupportedMatchValueType(matchValueType))
                    return false;
                var matchLocal = _il.DeclareLocal(matchValueType);
                _il.Emit(OpCodes.Stloc, matchLocal);

                // ENUM EXHAUSTIVENESS: N# requires an enum match to cover EVERY member or carry a catch-all (the
                // analyzer's NL501 NonExhaustiveMatch). The columnar emit would otherwise compile a PARTIAL enum
                // match (with a runtime throw for the missing members). Decline such a match so the columnar path
                // never accepts a source shape the analyzer rejected.
                // This is a DECLINE, not a diagnostic — consistent with how
                // the emitter declines everything outside its faithfully-modelled subset. Coverage counts only
                // TOP-LEVEL UNGUARDED arms: an unguarded `_`/binding is a catch-all; an unguarded `Enum.Member`
                // (kind 8) covers that member. Guarded and combinator/relational arms do not count (conservative — a
                // richer-but-exhaustive form simply declines to , still correct).
                ColumnarEnumDef? matchEnumDef = null;
                foreach (var def in _enumRegistry.Values)
                {
                    if (!def.IsStringBacked && def.EnumType == matchValueType) { matchEnumDef = def; break; }
                }
                if (matchEnumDef != null)
                {
                    var covered = new HashSet<string>(StringComparer.Ordinal);
                    var hasCatchAll = false;
                    for (var c = 0; c < caseCount; c++)
                    {
                        var rawP = Child(idx, 1 + (2 * c));
                        if (_nodes.Kind(rawP) == 19) // a `when`-guarded arm does not contribute to coverage.
                            continue;
                        if (_nodes.Kind(rawP) == 6) // `_` discard or an unguarded binding -> a catch-all.
                            hasCatchAll = true;
                        else if (_nodes.Kind(rawP) == 8) // `Enum.Member` -> covers that member (if it is THIS enum's).
                        {
                            var recv = Child(rawP, 0);
                            if (_nodes.Kind(recv) == 6 && _enumRegistry.TryGetValue(Text(recv), out var rd)
                                && rd.EnumType == matchValueType && matchEnumDef.Constants.ContainsKey(Text(rawP)))
                                covered.Add(Text(rawP));
                        }
                    }
                    if (!hasCatchAll && !covered.SetEquals(matchEnumDef.Constants.Keys))
                        return false;
                }

                // UNION EXHAUSTIVENESS: union matches must cover EVERY case or carry a catch-all (NL501).
                // A partial union match would otherwise emit a runtime throw for the missing cases, so decline it
                // to the analyzer-backed N# backend path. Coverage
                // counts only TOP-LEVEL UNGUARDED arms: an unguarded `_`/binding (kind 6) is a catch-all; an
                // unguarded union-case pattern (kind 37 over `Union.Case`) covers that case.
                // A non-generic union's scrutinee is its open base TypeBuilder; a GENERIC union's is a CLOSED
                // instantiation of the base (`Opt<int>`) — the helper resolves both (and the closed form's
                // arguments drive the per-case isinst/field closing in the pattern emitters).
                ColumnarUnionDef? matchUnionDef = null;
                if (TryGetUnionDefForMatchValue(matchValueType, out var foundUnionDef, out _))
                    matchUnionDef = foundUnionDef;
                if (matchUnionDef != null)
                {
                    var coveredCases = new HashSet<string>(StringComparer.Ordinal);
                    var hasCatchAll = false;
                    for (var c = 0; c < caseCount; c++)
                    {
                        var rawP = Child(idx, 1 + (2 * c));
                        if (_nodes.Kind(rawP) == 19) // a `when`-guarded arm does not contribute to coverage.
                            continue;
                        if (_nodes.Kind(rawP) == 6) // `_` discard or an unguarded binding -> a catch-all.
                            hasCatchAll = true;
                        else if (_nodes.Kind(rawP) == 37) // union-case PROPERTY pattern -> covers that case (if THIS union's).
                        {
                            var mem = Child(rawP, 0);
                            if (_nodes.Kind(mem) == 8)
                            {
                                var memRecv = Child(mem, 0);
                                if (_nodes.Kind(memRecv) == 6)
                                {
                                    var qualified = Text(memRecv) + "." + Text(mem);
                                    if (TryGetUnionCaseByKey(matchUnionDef, qualified, out var primaryCase, out _))
                                        coveredCases.Add(primaryCase);
                                }
                            }
                        }
                        else if (_nodes.Kind(rawP) == 8) // bare `Union.Case` TYPE pattern -> covers that case (no binding).
                        {
                            var bareRecv = Child(rawP, 0);
                            if (_nodes.Kind(bareRecv) == 6)
                            {
                                var qualified = Text(bareRecv) + "." + Text(rawP);
                                if (TryGetUnionCaseByKey(matchUnionDef, qualified, out var primaryCase, out _))
                                    coveredCases.Add(primaryCase);
                            }
                        }
                    }
                    if (!hasCatchAll && !coveredCases.SetEquals(matchUnionDef.Cases.Keys))
                        return false;
                }

                var matchEnd = _il.DefineLabel();
                Type? matchResultType = null;
                for (var c = 0; c < caseCount; c++)
                {
                    var rawPattern = Child(idx, 1 + (2 * c));
                    var resultNode = Child(idx, 2 + (2 * c));
                    var nextCase = _il.DefineLabel();
                    var armLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);

                    // A `when` guard wraps the pattern in a GuardedPattern (kind 19 [pattern, guard]). Unwrap it:
                    // the inner pattern is tested exactly as a bare pattern, then the guard (a bool expression with
                    // the pattern's binding in scope) gates the arm. A guarded catch-all is NOT exhaustive, so the
                    // trailing no-match throw remains correct.
                    int patternNode;
                    int guardNode;
                    if (_nodes.Kind(rawPattern) == 19)
                    {
                        if (_nodes.ChildCount(rawPattern) != 2)
                            return false;
                        patternNode = Child(rawPattern, 0);
                        guardNode = Child(rawPattern, 1);
                    }
                    else
                    {
                        patternNode = rawPattern;
                        guardNode = -1;
                    }

                    if (_nodes.Kind(patternNode) == 6) // top-level identifier: `_` discard or a binding -> always matches.
                    {
                        var patName = Text(patternNode);
                        if (patName != "_")
                        {
                            if (IsVisibleBindingName(patName))
                                return false; // a binding that shadows (own OR enclosing, NL316) is not modelled.
                            var bindLocal = _il.DeclareLocal(matchValueType);
                            _il.Emit(OpCodes.Ldloc, matchLocal);
                            _il.Emit(OpCodes.Stloc, bindLocal);
                            _locals[patName] = bindLocal;
                        }
                        // Always matches -> fall through to the guard / result.
                    }
                    else if (_nodes.Kind(patternNode) == 37) // union-case pattern `Union.Case { f }` (top-level only).
                    {
                        // isinst-test the case + bind its named fields; on MATCH fall through to the guard/result
                        // (armBody), on NO-MATCH branch to nextCase. Handled here (not in EmitPatternMatch) because it
                        // introduces field BINDINGS, valid only at an arm's top level — a union-case pattern nested in
                        // a combinator declines via EmitPatternMatch's default.
                        var armBody = _il.DefineLabel();
                        if (!EmitUnionCasePattern(patternNode, matchValueType, matchLocal, armBody, nextCase))
                            return false;
                        _il.MarkLabel(armBody);
                    }
                    else // literal / relational / and-or-not combinator -> recursive pattern test.
                    {
                        // On MATCH fall through to the guard/result (armBody); on NO-MATCH branch to nextCase. The
                        // recursive helper models literals, relational patterns, and `and`/`or`/`not` combinators,
                        // declining the whole match for anything it cannot emit exactly.
                        var armBody = _il.DefineLabel();
                        if (!EmitPatternMatch(patternNode, matchValueType, matchLocal, armBody, nextCase))
                            return false;
                        _il.MarkLabel(armBody);
                    }

                    // `when` guard: the pattern matched; now require the guard (a bool) to hold. The pattern's
                    // binding (if any) is already in _locals, so the guard may reference it. False -> next case.
                    if (guardNode >= 0)
                    {
                        if (!EmitExpression(guardNode, out var guardType) || guardType != typeof(bool))
                            return false;
                        _il.Emit(OpCodes.Brfalse, nextCase);
                    }

                    if (!EmitExpression(resultNode, out var armResultType))
                        return false;
                    if (matchResultType == null)
                        matchResultType = armResultType;
                    else if (!TypesEquivalent(armResultType, matchResultType)) // every arm's result must share the match's type.
                        return false;
                    _il.Emit(OpCodes.Br, matchEnd);

                    _il.MarkLabel(nextCase);
                    foreach (var name in new List<string>(_locals.Keys)) // drop this arm's binding (if any).
                    {
                        if (!armLocals.Contains(name))
                            _locals.Remove(name);
                    }
                }

                // No case matched -> throw (mirrors the N# backend path). Unreachable if a catch-all arm is present.
                _il.Emit(OpCodes.Ldstr, "No matching case in match expression");
                _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                _il.Emit(OpCodes.Throw);
                _il.MarkLabel(matchEnd);
                type = matchResultType!;
                return true;
            }

            case 59: // AnonymousObjectInitializer [name0, value0, ...] — `new { Name: value, ... }`.
                return TryEmitAnonymousObjectInitializer(idx, out type);

            default:
                return Decline(
                    "emit.expression.unhandled-kind",
                    "unsupported expression (node kind " + _nodes.Kind(idx).ToString() + ")",
                    idx);
        }
    }

    private bool TryEmitAnonymousObjectInitializer(int idx, out Type type)
    {
        type = null!;
        if (_programType == null || _lambdaCounter == null || _displayClasses == null)
            return false;
        var childCount = _nodes.ChildCount(idx);
        if ((childCount % 2) != 0)
            return false;
        var propertyCount = childCount / 2;
        var names = new string[propertyCount];
        var valueNodes = new int[propertyCount];
        var seen = new HashSet<string>(StringComparer.Ordinal);
        for (var p = 0; p < propertyCount; p++)
        {
            var nameNode = Child(idx, 2 * p);
            if (_nodes.Kind(nameNode) != 6)
                return false;
            var name = Text(nameNode);
            if (!seen.Add(name))
                return false;
            names[p] = name;
            valueNodes[p] = Child(idx, (2 * p) + 1);
        }

        var module = (ModuleBuilder)_programType.Module;
        var anonymousType = module.DefineType(
            "<>f__AnonymousObject" + _lambdaCounter[0]++,
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed);
        var ctor = anonymousType.DefineDefaultConstructor(MethodAttributes.Public);
        var setters = new MethodBuilder[propertyCount];
        for (var p = 0; p < propertyCount; p++)
        {
            var field = anonymousType.DefineField("<" + names[p] + ">k__BackingField", typeof(object), FieldAttributes.Private);
            var property = anonymousType.DefineProperty(names[p], PropertyAttributes.None, typeof(object), Type.EmptyTypes);
            var getter = anonymousType.DefineMethod(
                "get_" + names[p],
                MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
                typeof(object),
                Type.EmptyTypes);
            var getterIl = getter.GetILGenerator();
            getterIl.Emit(OpCodes.Ldarg_0);
            getterIl.Emit(OpCodes.Ldfld, field);
            getterIl.Emit(OpCodes.Ret);

            var setter = anonymousType.DefineMethod(
                "set_" + names[p],
                MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
                typeof(void),
                new[] { typeof(object) });
            var setterIl = setter.GetILGenerator();
            setterIl.Emit(OpCodes.Ldarg_0);
            setterIl.Emit(OpCodes.Ldarg_1);
            setterIl.Emit(OpCodes.Stfld, field);
            setterIl.Emit(OpCodes.Ret);
            property.SetGetMethod(getter);
            property.SetSetMethod(setter);
            setters[p] = setter;
        }
        _displayClasses.Add(anonymousType);

        _il.Emit(OpCodes.Newobj, ctor);
        for (var p = 0; p < propertyCount; p++)
        {
            _il.Emit(OpCodes.Dup);
            if (!EmitExpression(valueNodes[p], out var valueType)
                || !TryEmitObjectConversion(valueType, typeof(object)))
                return false;
            _il.Emit(OpCodes.Callvirt, setters[p]);
        }
        type = anonymousType;
        return true;
    }

    // Recursive match-pattern test mirroring the pattern-test emitter structure (success/fail labels), but reading the
    // matched value from `matchLocal` instead of a stack dup. On MATCH it branches to successLabel; on NO-MATCH to
    // failLabel. Models literal patterns (kinds 0-4), relational patterns (32), and `and`/`or`/`not` combinators
    // (33/34/35) over those. It does NOT model bindings: an identifier (kind 6) is only handled at the TOP LEVEL of
    // an arm, so an identifier inside a combinator declines (returns false) and required columnar emission rejects
    // the program. A `false` return discards the entire emitted assembly, so a partially-emitted test is harmless.
    private bool EmitPatternMatch(int patternNode, Type matchValueType, LocalBuilder matchLocal, Label successLabel, Label failLabel)
    {
        switch (_nodes.Kind(patternNode))
        {
            case 34: // OrPattern [left, right]: left matches -> success; else fall through and try right.
            {
                if (_nodes.ChildCount(patternNode) != 2)
                    return false;
                var orNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, successLabel, orNext))
                    return false;
                _il.MarkLabel(orNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 33: // AndPattern [left, right]: left must match (else fail), then right decides.
            {
                if (_nodes.ChildCount(patternNode) != 2)
                    return false;
                var andNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, andNext, failLabel))
                    return false;
                _il.MarkLabel(andNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 35: // NotPattern [inner]: inner matches -> fail, inner fails -> success (just swap the labels).
            {
                if (_nodes.ChildCount(patternNode) != 1)
                    return false;
                return EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, failLabel, successLabel);
            }
            case 32: // RelationalPattern `<op> <constant>` -> ordered comparison (the pattern-test emitter mirror).
            {
                if (_nodes.ChildCount(patternNode) != 1 || !ColumnarPatternFacts.IsOrderedMatchType(matchValueType))
                    return false;
                var operandNode = Child(patternNode, 0);
                if (!ColumnarPatternFacts.IsLiteralPatternKind(_nodes.Kind(operandNode)))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                if (!EmitExpression(operandNode, out var relType) || relType != matchValueType)
                    return false;
                // Plain ordered Clt/Cgt for ALL types (matches  exactly, incl. NaN/large ulong). `<`/`>` take the
                // arm when the compare is TRUE; `<=`/`>=` are the negations — take when FALSE. Branch to successLabel
                // when taken, else fall to the `Br failLabel`.
                switch (Text(patternNode))
                {
                    case "<": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Brtrue, successLabel); break;
                    case ">": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Brtrue, successLabel); break;
                    case "<=": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Brfalse, successLabel); break;
                    case ">=": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Brfalse, successLabel); break;
                    default: return false;
                }
                _il.Emit(OpCodes.Br, failLabel);
                return true;
            }
            case 8: // MemberAccess pattern: `Enum.Member` (enum-constant equality) OR `Union.Case` (a bare union TYPE
            {        // pattern — match the case by type, NO destructuring/binding).
                var recv = Child(patternNode, 0);
                if (_nodes.Kind(recv) != 6)
                    return false;
                var recvName = Text(recv);
                // ENUM constant: the receiver names a REGISTERED enum (not shadowed by a local/param/sibling), the
                // member is one of its constants, and the match value is THAT enum's type. Underlying-int Ceq.
                if (_enumRegistry.TryGetValue(recvName, out var enumDef)
                    && !_locals.ContainsKey(recvName) && !_liftedLocals.ContainsKey(recvName) && !_paramOrdinals.ContainsKey(recvName) && !_siblings.ContainsKey(recvName))
                {
                    if (matchValueType != enumDef.EnumType)
                        return false;
                    if (enumDef.StringConstants != null)
                    {
                        if (!enumDef.StringConstants.TryGetValue(Text(patternNode), out var stringValue))
                            return false;
                        _il.Emit(OpCodes.Ldloc, matchLocal);
                        _il.Emit(OpCodes.Ldstr, stringValue);
                        _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                        _il.Emit(OpCodes.Brtrue, successLabel);
                        _il.Emit(OpCodes.Br, failLabel);
                        return true;
                    }
                    if (!enumDef.Constants.TryGetValue(Text(patternNode), out var memberValue))
                        return false;
                    _il.Emit(OpCodes.Ldloc, matchLocal);
                    _il.Emit(OpCodes.Ldc_I4, memberValue);
                    _il.Emit(OpCodes.Ceq);             // underlying-int equality (matches N#'s Beq-on-underlying-int).
                    _il.Emit(OpCodes.Brtrue, successLabel);
                    _il.Emit(OpCodes.Br, failLabel);
                    return true;
                }
                // UNION bare TYPE pattern `Union.Case` (no `{ }`): an `isinst` test against the case's concrete type,
                // matching WITHOUT binding any field — the idiomatic way to match a payload-free case (where `Case {}`
                // is NL503), and to match a payload case by type alone. Binds nothing, so it is SAFE inside `and`/`or`/
                // `not` combinators (unlike the binding property pattern, which is top-level only). The match value
                // must be THIS union's base (a CLOSED instantiation of it when generic — the isinst target then
                // closes the case over the scrutinee's arguments). No `dup`/`pop` needed: the isinst result is
                // consumed by the branch.
                var qualifiedCase = recvName + "." + Text(patternNode);
                // VALUE-STRUCT union bare pattern: the scrutinee is a tag struct, so test `scrutinee.Tag == caseTag`
                // (read via the public get_Tag) instead of an isinst — there is no reference identity to test.
                if (TryGetUnionCaseByKey(qualifiedCase, out _, out var bareValueStructCase) && bareValueStructCase.IsValueStruct
                    && bareValueStructCase.UnionBase == matchValueType && bareValueStructCase.ValueStructTagGetter != null
                    && !_locals.ContainsKey(recvName) && !_liftedLocals.ContainsKey(recvName) && !_paramOrdinals.ContainsKey(recvName) && !_siblings.ContainsKey(recvName))
                {
                    _il.Emit(OpCodes.Ldloca, matchLocal);
                    _il.Emit(OpCodes.Call, bareValueStructCase.ValueStructTagGetter);
                    _il.Emit(OpCodes.Ldc_I4, bareValueStructCase.ValueStructTag);
                    _il.Emit(OpCodes.Ceq);
                    _il.Emit(OpCodes.Brtrue, successLabel);
                    _il.Emit(OpCodes.Br, failLabel);
                    return true;
                }
                if (TryGetCaseTestType(qualifiedCase, matchValueType, out _, out var bareCaseTestType, out _)
                    && !_locals.ContainsKey(recvName) && !_liftedLocals.ContainsKey(recvName) && !_paramOrdinals.ContainsKey(recvName) && !_siblings.ContainsKey(recvName))
                {
                    _il.Emit(OpCodes.Ldloc, matchLocal);
                    _il.Emit(OpCodes.Isinst, bareCaseTestType);
                    _il.Emit(OpCodes.Brtrue, successLabel);
                    _il.Emit(OpCodes.Br, failLabel);
                    return true;
                }
                return false; // not a registered enum constant or union case -> decline.
            }
            default: // literal pattern (kinds 0-4) -> equality test; any other primary (null/paren/call/index/…) declines.
            {
                if (!ColumnarPatternFacts.IsLiteralPatternKind(_nodes.Kind(patternNode)))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                if (!EmitExpression(patternNode, out var patType) || patType != matchValueType)
                    return false;
                if (matchValueType == typeof(string))
                    _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
                else
                    _il.Emit(OpCodes.Ceq);
                _il.Emit(OpCodes.Brtrue, successLabel);
                _il.Emit(OpCodes.Br, failLabel);
                return true;
            }
        }
    }

    // Resolves the explicit type-argument subtrees of a kind-1 (Generic) type root naming a union case
    // (`Opt.Some<int>` → [int]) — each argument canonicalized (TryBuildTypeNodeCanonical handles nested
    // generics/arrays) and resolved against the registries; arity-checked against the union BASE's declared
    // parameters (cases redeclare them positionally, so one arity governs both).
    private bool TryResolveUnionCaseTypeArgs(int typeRootNode, ColumnarUnionCaseDef caseDef, out Type[] args)
    {
        args = Type.EmptyTypes;
        var arity = caseDef.UnionBase.GetGenericArguments().Length;
        if (_nodes.ChildCount(typeRootNode) != arity)
            return false;
        var resolved = new Type[arity];
        for (var i = 0; i < arity; i++)
        {
            if (!TryBuildTypeNodeCanonical(Child(typeRootNode, i), out var argCanonical)
                || !TryResolveType(argCanonical, _enumRegistry, _structRegistry, _unionRegistry, out resolved[i])
                || !IsSupportedType(resolved[i]))
                return false;
        }
        args = resolved;
        return true;
    }

    // Emits a union-case CONSTRUCTION: `newobj <case ctor>` then per named object-init field `dup; <value>;
    // stfld`. `typeArgs` empty = a non-generic case (the original D-10 path: open builders directly);
    // non-empty = a GENERIC case closed over the arguments — the ctor and every field handle are REBOUND
    // onto the closed instantiation via TypeBuilder.GetConstructor/GetField (reflection member queries throw
    // on TypeBuilderInstantiation — the legacy emitter's machinery, spike-proven), and each field's expected value
    // type substitutes the arguments positionally (`value: T` on Opt<int> expects int). `pairCount` 0 emits
    // the bare/payload-default form (`new Color.Red {}`, brace-less `new Opt.None<int>` — fields stay
    // CLR-default, the pipeline's probed semantics). The result's static type is the union BASE (closed over
    // the same arguments when generic) — an upcast; a later match recovers the case.
    private bool TryEmitUnionCaseConstruction(ColumnarUnionCaseDef caseDef, Type[] typeArgs, int initIdx, int pairCount, out Type type)
    {
        type = null!;

        // VALUE-STRUCT union case: allocation-free construction through the union's static `Create_<Case>` factory
        // (`new U(tag)`), mirroring the previous parity baseline. Value-struct unions are non-generic and payload-free, so a `{ }`
        // with fields (pairCount > 0) or explicit type args never reach here for a valid program — guard and decline.
        if (caseDef.IsValueStruct)
        {
            if (typeArgs.Length != 0 || pairCount != 0 || caseDef.ValueStructFactory == null)
                return false;
            _il.Emit(OpCodes.Call, caseDef.ValueStructFactory);
            type = caseDef.UnionBase; // the union struct value.
            return true;
        }

        Type resultType;
        ConstructorInfo ctor;
        Type? closedCase = null;
        if (typeArgs.Length == 0)
        {
            if (caseDef.UnionBase.IsGenericTypeDefinition)
                return false; // a generic case never constructs open.
            ctor = caseDef.Ctor;
            resultType = caseDef.UnionBase;
        }
        else
        {
            if (caseDef.UnionBase.GetGenericArguments().Length != typeArgs.Length)
                return false;
            closedCase = caseDef.CaseType.MakeGenericType(typeArgs);
            ctor = TypeBuilder.GetConstructor(closedCase, caseDef.Ctor);
            resultType = caseDef.UnionBase.MakeGenericType(typeArgs);
        }

        _il.Emit(OpCodes.Newobj, ctor);
        var assignedFields = new HashSet<string>(StringComparer.Ordinal);
        for (var p = 0; p < pairCount; p++)
        {
            var nameNode = Child(initIdx, 1 + (2 * p));
            var valueNode = Child(initIdx, 2 + (2 * p));
            if (_nodes.Kind(nameNode) != 6)
                return false;
            var fieldName = Text(nameNode);
            if (!caseDef.Fields.TryGetValue(fieldName, out var openField) || !assignedFields.Add(fieldName))
                return false; // unknown or duplicately-assigned field -> decline.
            var expectedFieldType = closedCase == null ? openField.FieldType : SubstituteClosedTypeArguments(openField.FieldType, typeArgs);
            _il.Emit(OpCodes.Dup);
            // A FIELD VALUE adopts the substituted field type's arguments (probe-pinned:
            // `new Opt.Some<Opt<int>> { value: new Opt.None }` adopts Opt<int> from `value: T`).
            Type valueType;
            if (IsAdoptableUnionConstruction(valueNode, expectedFieldType))
            {
                if (!EmitAdoptedUnionConstruction(valueNode, expectedFieldType, out valueType))
                    return false;
            }
            else if (!EmitExpression(valueNode, out valueType))
            {
                return false;
            }
            if (!TypesEquivalent(valueType, expectedFieldType))
                return false;
            _il.Emit(OpCodes.Stfld, closedCase == null ? openField : TypeBuilder.GetField(closedCase, openField));
        }
        type = resultType; // upcast to the union base.
        return true;
    }

    private bool TryEmitUnionCasePositionalConstruction(ColumnarUnionCaseDef caseDef, Type[] typeArgs, int newIdx, int argCount, out Type type)
    {
        type = null!;
        if (caseDef.IsValueStruct)
        {
            if (typeArgs.Length != 0 || argCount != 0 || caseDef.ValueStructFactory == null)
                return false;
            _il.Emit(OpCodes.Call, caseDef.ValueStructFactory);
            type = caseDef.UnionBase;
            return true;
        }

        if (caseDef.FieldOrder.Length != argCount)
            return false;

        Type resultType;
        ConstructorInfo ctor;
        Type? closedCase = null;
        if (typeArgs.Length == 0)
        {
            if (caseDef.UnionBase.IsGenericTypeDefinition)
                return false;
            ctor = caseDef.Ctor;
            resultType = caseDef.UnionBase;
        }
        else
        {
            if (caseDef.UnionBase.GetGenericArguments().Length != typeArgs.Length)
                return false;
            closedCase = caseDef.CaseType.MakeGenericType(typeArgs);
            ctor = TypeBuilder.GetConstructor(closedCase, caseDef.Ctor);
            resultType = caseDef.UnionBase.MakeGenericType(typeArgs);
        }

        _il.Emit(OpCodes.Newobj, ctor);
        for (var a = 0; a < argCount; a++)
        {
            var fieldName = caseDef.FieldOrder[a];
            if (!caseDef.Fields.TryGetValue(fieldName, out var openField))
                return false;
            var expectedFieldType = closedCase == null ? openField.FieldType : SubstituteClosedTypeArguments(openField.FieldType, typeArgs);
            _il.Emit(OpCodes.Dup);
            var argNode = Child(newIdx, 1 + a);
            Type valueType;
            if (IsAdoptableUnionConstruction(argNode, expectedFieldType))
            {
                if (!EmitAdoptedUnionConstruction(argNode, expectedFieldType, out valueType))
                    return false;
            }
            else if (!EmitExpression(argNode, out valueType))
            {
                return false;
            }
            if (!TypesEquivalent(valueType, expectedFieldType))
                return false;
            _il.Emit(OpCodes.Stfld, closedCase == null ? openField : TypeBuilder.GetField(closedCase, openField));
        }
        type = resultType;
        return true;
    }

    // True when `exprNode` is the expected-type ADOPTION shape for a GENERIC union case: a `new Union.Case
    // { ... }` object-init (kind 36) or brace-less `new Union.Case` (kind 42) whose Simple type root names a
    // registered case of a GENERIC union, with the expected type a CLOSED instantiation of THAT union's base
    // (`return new Opt.None` on `(): Opt<int>`; `n: Opt<int> = new Opt.Some { value: 5 }`). The pipeline
    // adopts the expected type's arguments at FIVE probe-pinned positions, each with an exact expected type:
    // return statements, typed-local inits, union-case object-init FIELD VALUES, and local/param
    // REASSIGNMENT — exactly the emitters that consult this before their normal EmitExpression call. It
    // REJECTS call-argument adoption (NL103 — queued known defect) and `:=` (NL207, no expected type), so
    // kind-36/42 nodes reaching plain EmitExpression with a generic case decline there.
    private bool IsAdoptableUnionConstruction(int exprNode, Type expectedType)
    {
        if (_nodes.Kind(exprNode) != 36 && _nodes.Kind(exprNode) != 42)
            return false;
        if (_nodes.Kind(exprNode) == 36 && (_nodes.ChildCount(exprNode) % 2) != 1)
            return false;
        var root = Child(exprNode, 0);
        if (_nodes.Kind(root) != 0)
            return false;
        if (!TryGetUnionCaseByKey(Text(root), out _, out var caseDef) || !caseDef.UnionBase.IsGenericTypeDefinition)
            return false;
        return IsClosedUserGenericInstantiation(expectedType)
            && ReferenceEquals(expectedType.GetGenericTypeDefinition(), caseDef.UnionBase);
    }

    // Emits an adoption-shape construction (see IsAdoptableUnionConstruction) closed over the EXPECTED
    // type's arguments. The caller has already established applicability.
    private bool EmitAdoptedUnionConstruction(int exprNode, Type expectedType, out Type type)
    {
        type = null!;
        if (!TryGetUnionCaseByKey(Text(Child(exprNode, 0)), out _, out var caseDef))
            return false;
        var pairCount = _nodes.Kind(exprNode) == 36 ? (_nodes.ChildCount(exprNode) - 1) / 2 : 0;
        return TryEmitUnionCaseConstruction(caseDef, expectedType.GetGenericArguments(), exprNode, pairCount, out type);
    }

    // A union-case pattern `Union.Case { f0, f1 }` (kind 37, children [memberAccess, bind0, ...]): an `isinst` type
    // test against the case's concrete type, and on match a field-binding of each named field to a fresh local. This
    // is handled ONLY at the TOP LEVEL of a match arm (not inside `and`/`or`/`not` — bindings in a negated/disjoined
    // pattern are restricted, so a union-case pattern under a combinator declines via EmitPatternMatch's
    // default). On MATCH it branches to successLabel (with the bindings live in `_locals`, cleaned up per-arm by the
    // caller); on NO-MATCH to failLabel. Returns false (whole match declines) on any unsupported shape.
    private bool EmitUnionCasePattern(int patternNode, Type matchValueType, LocalBuilder matchLocal, Label successLabel, Label failLabel)
    {
        var memberNode = Child(patternNode, 0);
        if (_nodes.Kind(memberNode) != 8)
            return false;
        var caseRecv = Child(memberNode, 0);
        if (_nodes.Kind(caseRecv) != 6)
            return false; // the head must be a bare `Union` identifier (a qualified `Union.Case`).
        var qualifiedCase = Text(caseRecv) + "." + Text(memberNode);
        // The scrutinee must be THIS union (the open base, or a CLOSED instantiation of it when generic —
        // the case is then isinst-tested CLOSED over the scrutinee's arguments, the legacy emitter's machinery).
        if (!TryGetCaseTestType(qualifiedCase, matchValueType, out var caseDef, out var caseTestType, out var caseArgs))
            return false; // not a registered case of THIS union -> decline.
        // A `{ }` PROPERTY pattern on a PAYLOAD-FREE case is rejected by  (NL503 — "doesn't carry any data — you
        // can't destructure it with property patterns"); a zero-field case is matched as a BARE type pattern instead
        // (not modelled here). Decline so columnar never accepts a destructuring  refuses.
        if (caseDef.Fields.Count == 0)
            return false;

        // `ldloc value; isinst Case; dup; brtrue ok; pop; br fail; ok: stloc caseLocal`. The dup keeps a copy so the
        // success path stores the (non-null) case ref; the fail path pops the null before branching — leaving the
        // stack empty at BOTH labels (matching every other pattern's stack discipline).
        var caseLocal = _il.DeclareLocal(caseTestType);
        var caseOk = _il.DefineLabel();
        _il.Emit(OpCodes.Ldloc, matchLocal);
        _il.Emit(OpCodes.Isinst, caseTestType);
        _il.Emit(OpCodes.Dup);
        _il.Emit(OpCodes.Brtrue, caseOk);
        _il.Emit(OpCodes.Pop);
        _il.Emit(OpCodes.Br, failLabel);
        _il.MarkLabel(caseOk);
        _il.Emit(OpCodes.Stloc, caseLocal);

        // Bind each listed field to a local of the field's type (`ldloc caseLocal; ldfld f; stloc bind`). A `_`
        // binding is a discard (skip). A binding must name a case field and must not shadow a local/param.
        // On a CLOSED case the field handle is REBOUND via TypeBuilder.GetField and the binding's local type
        // substitutes the scrutinee's arguments positionally (`value: T` on Opt<int> binds an int local).
        var bindCount = _nodes.ChildCount(patternNode) - 1;
        for (var b = 0; b < bindCount; b++)
        {
            var bindNode = Child(patternNode, 1 + b);
            if (_nodes.Kind(bindNode) != 6)
                return false;
            var bindName = Text(bindNode);
            if (bindName == "_")
                continue;
            if (!caseDef.Fields.TryGetValue(bindName, out var bindField))
                return false; // the binding must name a field of the case (slice scope: bare field bindings).
            if (_locals.ContainsKey(bindName) || _paramOrdinals.ContainsKey(bindName)
                || _liftedLocals.ContainsKey(bindName)
                || (_boxedCaptures != null && _boxedCaptures.ContainsKey(bindName)))
                return false; // a binding that shadows a local/param is not modelled.
            var bindFieldType = caseArgs.Length == 0 ? bindField.FieldType : SubstituteClosedTypeArguments(bindField.FieldType, caseArgs);
            if (!IsSupportedType(bindFieldType))
                return false; // a substituted binding type outside the modelled set declines.
            var bindLocal = _il.DeclareLocal(bindFieldType);
            _il.Emit(OpCodes.Ldloc, caseLocal);
            _il.Emit(OpCodes.Ldfld, caseArgs.Length == 0 ? bindField : TypeBuilder.GetField(caseTestType, bindField));
            _il.Emit(OpCodes.Stloc, bindLocal);
            _locals[bindName] = bindLocal;
        }
        _il.Emit(OpCodes.Br, successLabel);
        return true;
    }

    // Types a `match` value may be tested against in the modelled pattern set: the scalars (Ceq equality), string
    // (op_Equality), a user-defined enum (its underlying-int Ceq, via the MemberAccess pattern case), and a
    // user-defined UNION base (isinst per union-case pattern). Records/etc. are not modelled, so a match over them
    // declines to the N# backend path. (Instance — the union base is identified by the union registry.)
    private bool IsSupportedMatchValueType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
        || t == typeof(bool) || t == typeof(double) || t == typeof(float) || t == typeof(string)
        || IsEnumType(t)
        || TryGetUnionDefForMatchValue(t, out _, out _);

    // True when `type` is the struct of a value-struct (payload-free tag) union. Used to decline `is`/`as` whose
    // SOURCE is such a union — those need value-type boxing before isinst (owned by the previous parity baseline), which columnar
    // does not emit.
    private bool IsValueStructUnionType(Type type)
    {
        foreach (var unionDef in _unionRegistry.Values)
        {
            if (unionDef.IsValueStruct && unionDef.Base == type)
                return true;
        }

        return false;
    }

    private bool TryGetUnionCaseByKey(string qualifiedCase, out string primaryKey, out ColumnarUnionCaseDef caseDef)
    {
        if (_unionCaseRegistry.TryGetValue(qualifiedCase, out caseDef!))
        {
            primaryKey = qualifiedCase;
            return true;
        }

        foreach (var candidate in _unionCaseRegistry)
        {
            if (string.Equals(ShortUnionCaseKey(candidate.Key), qualifiedCase, StringComparison.Ordinal))
            {
                primaryKey = candidate.Key;
                caseDef = candidate.Value;
                return true;
            }
        }

        primaryKey = string.Empty;
        caseDef = null!;
        return false;
    }

    private static bool TryGetUnionCaseByKey(ColumnarUnionDef unionDef, string qualifiedCase, out string primaryKey, out ColumnarUnionCaseDef caseDef)
    {
        if (unionDef.Cases.TryGetValue(qualifiedCase, out caseDef!))
        {
            primaryKey = qualifiedCase;
            return true;
        }

        foreach (var candidate in unionDef.Cases)
        {
            if (string.Equals(ShortUnionCaseKey(candidate.Key), qualifiedCase, StringComparison.Ordinal))
            {
                primaryKey = candidate.Key;
                caseDef = candidate.Value;
                return true;
            }
        }

        primaryKey = string.Empty;
        caseDef = null!;
        return false;
    }

    // Resolves a match VALUE type to its union def: the OPEN base TypeBuilder (a non-generic union's
    // scrutinee) or a CLOSED instantiation of a generic union's base (`Opt<int>`), yielding the
    // instantiation's type arguments (empty when non-generic) for closing case types and field bindings.
    // A generic union's OPEN base never types a value — bare generic-union annotations decline at
    // resolution — so a raw generic-definition TypeBuilder returns false.
    private bool TryGetUnionDefForMatchValue(Type matchValueType, out ColumnarUnionDef unionDef, out Type[] scrutineeArgs)
    {
        unionDef = null!;
        scrutineeArgs = Type.EmptyTypes;
        if (matchValueType is TypeBuilder && !matchValueType.IsGenericTypeDefinition)
        {
            foreach (var u in _unionRegistry.Values)
            {
                if (u.Base == matchValueType)
                {
                    unionDef = u;
                    return true;
                }
            }
            return false;
        }
        if (IsClosedUserGenericInstantiation(matchValueType))
        {
            var definition = matchValueType.GetGenericTypeDefinition();
            foreach (var u in _unionRegistry.Values)
            {
                if (ReferenceEquals(u.Base, definition))
                {
                    unionDef = u;
                    scrutineeArgs = matchValueType.GetGenericArguments();
                    return true;
                }
            }
        }
        return false;
    }

    // Maps a match value type + qualified case name to the case def, the CONCRETE type to isinst against
    // (the case CLOSED over the scrutinee's arguments when generic), and those arguments (empty when
    // non-generic). False when the case is not a registered case of the scrutinee's union.
    private bool TryGetCaseTestType(string qualifiedCase, Type matchValueType, out ColumnarUnionCaseDef caseDef, out Type caseTestType, out Type[] caseArgs)
    {
        caseTestType = null!;
        caseArgs = Type.EmptyTypes;
        if (!TryGetUnionCaseByKey(qualifiedCase, out _, out caseDef))
            return false;
        if (matchValueType == caseDef.UnionBase)
        {
            caseTestType = caseDef.CaseType;
            return true;
        }
        if (IsClosedUserGenericInstantiation(matchValueType)
            && ReferenceEquals(matchValueType.GetGenericTypeDefinition(), caseDef.UnionBase))
        {
            caseArgs = matchValueType.GetGenericArguments();
            caseTestType = caseDef.CaseType.MakeGenericType(caseArgs);
            return true;
        }
        return false;
    }

    // The underlying int value of a System.StringComparison named constant (the enum's documented stable values).
    // An enum on the CLR stack is just its underlying int, so an enum constant emits `ldc.i4 <value>`.
    private static bool TryGetStringComparisonValue(string name, out int value)
    {
        value = name switch
        {
            nameof(StringComparison.CurrentCulture) => 0,
            nameof(StringComparison.CurrentCultureIgnoreCase) => 1,
            nameof(StringComparison.InvariantCulture) => 2,
            nameof(StringComparison.InvariantCultureIgnoreCase) => 3,
            nameof(StringComparison.Ordinal) => 4,
            nameof(StringComparison.OrdinalIgnoreCase) => 5,
            _ => -1,
        };
        return value >= 0;
    }

    // Emit the comparison opcode(s) for `op` over two like-typed values already on the stack, leaving an i4 bool.
    // `unsigned` selects the unsigned ordering opcodes (Clt_Un/Cgt_Un) for ulong — equality (Ceq) is identical.
    // `isFloat` (double) uses the ORDERED Clt/Cgt for `<`/`>` (a NaN operand yields false), but `<=`/`>=` must
    // negate the UNORDERED complement (Cgt_Un/Clt_Un) so a NaN operand yields false too — matching N#'s float
    // comparison lowering (`a <= b` is `!(a cgt.un b)`). For int/ulong (no NaN) the complement equals the ordering.
    private void EmitComparison(string op, bool unsigned = false, bool isFloat = false)
    {
        var lt = unsigned ? OpCodes.Clt_Un : OpCodes.Clt;
        var gt = unsigned ? OpCodes.Cgt_Un : OpCodes.Cgt;
        var ltComplement = isFloat ? OpCodes.Clt_Un : lt;
        var gtComplement = isFloat ? OpCodes.Cgt_Un : gt;
        switch (op)
        {
            case "<": _il.Emit(lt); break;
            case ">": _il.Emit(gt); break;
            case "==": _il.Emit(OpCodes.Ceq); break;
            case "!=": _il.Emit(OpCodes.Ceq); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break;
            case "<=": _il.Emit(gtComplement); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a > b)
            case ">=": _il.Emit(ltComplement); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); break; // !(a < b)
        }
    }

    private void EmitArrayElementLoad(Type elementType)
    {
        if (elementType == typeof(bool)) _il.Emit(OpCodes.Ldelem_U1);
        else if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
        else if (elementType == typeof(uint)) _il.Emit(OpCodes.Ldelem_U4);
        else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
        else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
        else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
        else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
        else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
        else if (elementType.IsGenericParameter) _il.Emit(OpCodes.Ldelem, elementType);
        else if (!elementType.IsValueType) _il.Emit(OpCodes.Ldelem_Ref);
        else _il.Emit(OpCodes.Ldelem, elementType);
    }

    // A BCL method call whose callee is a MemberAccess [receiver, method-name]. A STATIC call (receiver is a
    // bare identifier naming a known type, e.g. `Char`) must be detected BEFORE the receiver is emitted (the
    // type name is not a value); an INSTANCE call emits the receiver value then dispatches on its type.
    private bool TryEmitBclMethodCall(int callIdx, int callee, out Type type)
    {
        type = null!;
        var memberName = Text(callee);
        var receiver = Child(callee, 0);
        var argCount = _nodes.ChildCount(callIdx) - 1;

        if (_nodes.Kind(receiver) == 6) // a bare identifier receiver that is NOT a value (local/param/sibling) is a type name.
        {
            var receiverName = Text(receiver);
            if (!_locals.ContainsKey(receiverName) && !_liftedLocals.ContainsKey(receiverName) && !_paramOrdinals.ContainsKey(receiverName) && !_siblings.ContainsKey(receiverName)
                && !IsCurrentInstanceMemberName(receiverName))
            {
                // CALL-STYLE newtype construction through a file-import ALIAS (`Ids.UserId(42)`):
                // the member names a synthesized newtype and the receiver is the alias qualifier.
                if (_structRegistry.TryGetValue(memberName, out var aliasNewtypeDef) && aliasNewtypeDef.IsNewtype
                    && !_structRegistry.ContainsKey(receiverName) && !_enumRegistry.ContainsKey(receiverName) && !_unionRegistry.ContainsKey(receiverName))
                {
                    foreach (var (aliasCtorBuilder, aliasCtorParamTypes, _, _) in aliasNewtypeDef.Constructors)
                    {
                        if (aliasCtorParamTypes.Length != argCount)
                            continue;
                        for (var a = 1; a <= argCount; a++)
                        {
                            if (!EmitDeclaredCallArgument(Child(callIdx, a), aliasCtorParamTypes[a - 1], allowLambdaLiteral: false))
                                return false;
                        }
                        _il.Emit(OpCodes.Newobj, aliasCtorBuilder);
                        type = aliasNewtypeDef.Builder;
                        return true;
                    }
                    return false;
                }
                return TryEmitStaticCall(callIdx, receiverName, memberName, argCount, out type);
            }
        }

        if (memberName == nameof(JsonElement.ArrayEnumerator.MoveNext) && argCount == 0
            && TryGetAddressableTargetType(receiver, out var addressableReceiverType)
            && (addressableReceiverType == typeof(JsonElement.ArrayEnumerator) || addressableReceiverType == typeof(JsonElement.ObjectEnumerator)))
        {
            if (!EmitAddressOfByRefTarget(receiver, addressableReceiverType))
                return false;
            _il.Emit(OpCodes.Call, addressableReceiverType.GetMethod(nameof(JsonElement.ArrayEnumerator.MoveNext), Type.EmptyTypes)!);
            type = typeof(bool);
            return true;
        }

        if (!EmitExpression(receiver, out var receiverType)) // instance: receiver value goes on the stack first.
        {
            return false;
        }
        if (!TryEmitInstanceCall(callIdx, receiverType, memberName, argCount, out type))
        {
            return false;
        }
        return true;
    }

    private bool IsCurrentInstanceMemberName(string name)
        => _currentStruct != null
           && (TryFindFieldOnChain(_currentStruct, name, out _)
               || TryFindPropertyOnChain(_currentStruct, name, out _));

    private bool TryEmitJsonSerializerDeserializeGenericCall(int callIdx, int callee, out Type type)
    {
        type = null!;
        var calleeName = Text(callee);
        if (calleeName != nameof(JsonSerializer.Deserialize)
            && calleeName != "JsonSerializer.Deserialize")
            return false;
        if (_nodes.ChildCount(callee) != 1 || _nodes.ChildCount(callIdx) - 1 != 2)
            return false;
        if (!TryBuildTypeNodeCanonical(Child(callee, 0), out var targetCanonical)
            || !TryResolveType(targetCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var targetType)
            || !IsSupportedType(targetType))
            return false;

        var deserialize = Array.Find(
            typeof(JsonSerializer).GetMethods(BindingFlags.Public | BindingFlags.Static),
            method =>
            {
                if (method.Name != nameof(JsonSerializer.Deserialize)
                    || !method.IsGenericMethodDefinition)
                    return false;
                var parameters = method.GetParameters();
                return parameters.Length == 2
                       && parameters[0].ParameterType == typeof(string)
                       && parameters[1].ParameterType == typeof(JsonSerializerOptions);
            });
        if (deserialize == null
            || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(string), allowLambdaLiteral: false)
            || !EmitDeclaredCallArgument(Child(callIdx, 2), typeof(JsonSerializerOptions), allowLambdaLiteral: false))
            return false;
        _il.Emit(OpCodes.Call, deserialize.MakeGenericMethod(targetType));
        type = targetType;
        return true;
    }

    // Static calls (no receiver on the stack): a USER type's static methods first, then a small BCL whitelist.
    // Char.IsLetterOrDigit/IsWhiteSpace(char) -> bool.
    private bool TryEmitStaticCall(int callIdx, string typeName, string member, int argCount, out Type type)
    {
        type = null!;
        // A USER-DECLARED type name binds its OWN static methods (chain-walked, nearest declaration first — the
        // legacy emitter resolves `Derived.F()` to a base-declared static). Resolution is by arg count; arg TYPES must
        // match exactly (the legacy emitter's implicit conversions are not modelled — mismatch declines). CRITICALLY, a
        // user type name must NEVER fall through to the BCL whitelist below: a user `record Math { … }` SHADOWS
        // System.Math in the N# pipeline, so emitting the BCL method for `Math.Abs(x)` would be semantically wrong
        // IL (the over-acceptance failure mode). The same gate covers user enums and unions — no static methods
        // are modelled on them, so any TypeName.Member(...) call on one declines.
        if (_structRegistry.TryGetValue(typeName, out var userType))
        {
            if (!TryFindStaticMethodOnChain(userType, member, argCount, out var userStatic))
                return Decline("emit.call.static-user-member-unmodeled", "static call '" + typeName + "." + member + "' with " + argCount + " argument(s) is not modeled", callIdx);
            for (var a = 1; a <= argCount; a++)
            {
                if (!EmitDeclaredCallArgument(Child(callIdx, a), userStatic.ParamTypes[a - 1], allowLambdaLiteral: true))
                    return Decline("emit.call.static-user-argument", "static call argument " + a + " for '" + typeName + "." + member + "' could not be emitted", Child(callIdx, a));
            }
            _il.Emit(OpCodes.Call, userStatic.Builder);
            type = userStatic.ReturnType;
            return true;
        }
        if (_enumRegistry.ContainsKey(typeName) || _unionRegistry.ContainsKey(typeName))
            return false;
        if ((typeName == "JsonConvert" || typeName == "Newtonsoft.Json.JsonConvert")
            && member == "SerializeObject"
            && argCount == 1)
        {
            if (!TryResolveReferencedType(
                    _referenceAssemblyPaths,
                    "Newtonsoft.Json",
                    "Newtonsoft.Json.JsonConvert",
                    out var jsonConvert))
                return false;
            var method = Array.Find(
                jsonConvert.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != "SerializeObject" || candidate.ReturnType != typeof(string))
                        return false;
                    var parameters = candidate.GetParameters();
                    return parameters.Length == 1 && parameters[0].ParameterType == typeof(object);
                });
            if (method == null
                || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(object), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if ((typeName == "WebApplication" || typeName == "Microsoft.AspNetCore.Builder.WebApplication")
            && member == "CreateBuilder"
            && argCount == 1)
        {
            if (!TryResolveReferencedType(
                    _referenceAssemblyPaths,
                    "Microsoft.AspNetCore",
                    "Microsoft.AspNetCore.Builder.WebApplication",
                    out var webApplication))
                return false;
            var method = webApplication.GetMethod("CreateBuilder", new[] { typeof(string[]) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string[])))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = method.ReturnType;
            return true;
        }
        // The receiver may be the type NAME `Char` (via `using System`) or the builtin alias `char` (the
        // lowercase keyword) — both bind to System.Char, so accept either.
        if ((typeName == "Char" || typeName == "char") && argCount == 1)
        {
            // Static System.Char methods taking a single char: classifiers (-> bool) and invariant case
            // transforms (-> char). The result type comes from the resolved method.
            MethodInfo? method = member switch
            {
                "IsLetterOrDigit" => typeof(char).GetMethod(nameof(char.IsLetterOrDigit), new[] { typeof(char) }),
                "IsLetter" => typeof(char).GetMethod(nameof(char.IsLetter), new[] { typeof(char) }),
                "IsDigit" => typeof(char).GetMethod(nameof(char.IsDigit), new[] { typeof(char) }),
                "IsWhiteSpace" => typeof(char).GetMethod(nameof(char.IsWhiteSpace), new[] { typeof(char) }),
                "IsUpper" => typeof(char).GetMethod(nameof(char.IsUpper), new[] { typeof(char) }),
                "ToLowerInvariant" => typeof(char).GetMethod(nameof(char.ToLowerInvariant), new[] { typeof(char) }),
                "ToUpperInvariant" => typeof(char).GetMethod(nameof(char.ToUpperInvariant), new[] { typeof(char) }),
                _ => null,
            };
            if (method == null || !EmitArg(callIdx, 1, typeof(char)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = method.ReturnType;
            return true;
        }
        if (typeName == "BitOperations" && member == "PopCount" && argCount == 1)
        {
            // System.Numerics.BitOperations.PopCount(ulong) -> int (population count / set-bit count). The arg
            // is a ulong; emit `call` (static). CliQueryParsing.nl uses it to count packed success bits.
            var method = typeof(System.Numerics.BitOperations).GetMethod(nameof(System.Numerics.BitOperations.PopCount), new[] { typeof(ulong) });
            if (method == null || !EmitArg(callIdx, 1, typeof(ulong)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Math" && member == "Abs" && argCount == 1)
        {
            // System.Math.Abs(int) -> int (absolute value). The arg is an int; emit `call` (static). Negative
            // inputs return the magnitude; int.MinValue throws OverflowException — identical to the N# backend path,
            // which binds the same overload, so parity holds (the columnar and N# results match, throw included).
            var method = typeof(Math).GetMethod(nameof(Math.Abs), new[] { typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Math" && member == "Max" && argCount == 2)
        {
            var method = typeof(Math).GetMethod(nameof(Math.Max), new[] { typeof(int), typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)) || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Math" && member == "Min" && argCount == 2)
        {
            var method = typeof(Math).GetMethod(nameof(Math.Min), new[] { typeof(int), typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)) || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.GetFullPath) && argCount == 1)
        {
            var method = typeof(Path).GetMethod(nameof(Path.GetFullPath), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.GetDirectoryName) && argCount == 1)
        {
            var method = typeof(Path).GetMethod(nameof(Path.GetDirectoryName), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.GetFileName) && argCount == 1)
        {
            var method = typeof(Path).GetMethod(nameof(Path.GetFileName), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.IsPathRooted) && argCount == 1)
        {
            var method = typeof(Path).GetMethod(nameof(Path.IsPathRooted), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.Combine) && argCount == 2)
        {
            var method = typeof(Path).GetMethod(nameof(Path.Combine), new[] { typeof(string), typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.ChangeExtension) && argCount == 2)
        {
            var method = typeof(Path).GetMethod(nameof(Path.ChangeExtension), new[] { typeof(string), typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.GetRelativePath) && argCount == 2)
        {
            var method = typeof(Path).GetMethod(nameof(Path.GetRelativePath), new[] { typeof(string), typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Path" && member == nameof(Path.TrimEndingDirectorySeparator) && argCount == 1)
        {
            var method = typeof(Path).GetMethod(nameof(Path.TrimEndingDirectorySeparator), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Directory" && member == nameof(Directory.Exists) && argCount == 1)
        {
            var method = typeof(Directory).GetMethod(nameof(Directory.Exists), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (typeName == "Directory" && member == nameof(Directory.CreateDirectory) && argCount == 1)
        {
            var method = typeof(Directory).GetMethod(nameof(Directory.CreateDirectory), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(DirectoryInfo);
            return true;
        }
        if (typeName == "Directory" && member == nameof(Directory.GetFiles) && argCount == 3)
        {
            var method = typeof(Directory).GetMethod(nameof(Directory.GetFiles), new[] { typeof(string), typeof(string), typeof(SearchOption) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)) || !EmitArg(callIdx, 3, typeof(SearchOption)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string[]);
            return true;
        }
        if (typeName == "Directory" && member == nameof(Directory.GetDirectories) && argCount == 3)
        {
            var method = typeof(Directory).GetMethod(nameof(Directory.GetDirectories), new[] { typeof(string), typeof(string), typeof(SearchOption) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)) || !EmitArg(callIdx, 3, typeof(SearchOption)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string[]);
            return true;
        }
        if (typeName == "File" && member == nameof(File.WriteAllText) && argCount == 2)
        {
            var method = typeof(File).GetMethod(nameof(File.WriteAllText), new[] { typeof(string), typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(void);
            return true;
        }
        if (typeName == "File" && member == nameof(File.Exists) && argCount == 1)
        {
            var method = typeof(File).GetMethod(nameof(File.Exists), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (typeName == "File" && member == nameof(File.ReadAllText) && argCount == 1)
        {
            var method = typeof(File).GetMethod(nameof(File.ReadAllText), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "File" && member == nameof(File.ReadAllLines) && argCount == 1)
        {
            var method = typeof(File).GetMethod(nameof(File.ReadAllLines), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string[]);
            return true;
        }
        if (typeName == "File" && member == nameof(File.ReadAllLinesAsync) && argCount == 1)
        {
            var method = typeof(File).GetMethod(nameof(File.ReadAllLinesAsync), new[] { typeof(string), typeof(System.Threading.CancellationToken) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(string))
                || !TryEmitDefaultValue(typeof(System.Threading.CancellationToken)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(System.Threading.Tasks.Task<string[]>);
            return true;
        }
        if (typeName == "File" && member == nameof(File.WriteAllLinesAsync) && argCount == 2)
        {
            var method = typeof(File).GetMethod(nameof(File.WriteAllLinesAsync), new[] { typeof(string), typeof(IEnumerable<string>), typeof(System.Threading.CancellationToken) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(string))
                || !EmitArg(callIdx, 2, typeof(IEnumerable<string>))
                || !TryEmitDefaultValue(typeof(System.Threading.CancellationToken)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (typeName == "File" && member == nameof(File.Copy) && argCount == 3)
        {
            var method = typeof(File).GetMethod(nameof(File.Copy), new[] { typeof(string), typeof(string), typeof(bool) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string)) || !EmitArg(callIdx, 3, typeof(bool)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(void);
            return true;
        }
        if (typeName == "Environment" && member == nameof(Environment.GetEnvironmentVariable) && argCount == 1)
        {
            var method = typeof(Environment).GetMethod(nameof(Environment.GetEnvironmentVariable), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Environment" && member == nameof(Environment.GetCommandLineArgs) && argCount == 0)
        {
            var method = typeof(Environment).GetMethod(nameof(Environment.GetCommandLineArgs), Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string[]);
            return true;
        }
        if (typeName == "Environment" && member == nameof(Environment.GetFolderPath) && argCount == 1)
        {
            var method = typeof(Environment).GetMethod(nameof(Environment.GetFolderPath), new[] { typeof(Environment.SpecialFolder) });
            if (method == null || !EmitArg(callIdx, 1, typeof(Environment.SpecialFolder)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "JsonSerializer" && member == nameof(JsonSerializer.Serialize) && argCount == 2)
        {
            if (!EmitExpression(Child(callIdx, 1), out var valueType)
                || !EmitArg(callIdx, 2, typeof(JsonSerializerOptions)))
                return false;
            var serialize = Array.Find(
                typeof(JsonSerializer).GetMethods(BindingFlags.Public | BindingFlags.Static),
                method =>
                {
                    if (method.Name != nameof(JsonSerializer.Serialize)
                        || !method.IsGenericMethodDefinition
                        || method.ReturnType != typeof(string))
                        return false;
                    var parameters = method.GetParameters();
                    return parameters.Length == 2
                           && parameters[0].ParameterType.IsGenericParameter
                           && parameters[1].ParameterType == typeof(JsonSerializerOptions);
                });
            if (serialize == null)
                return false;
            _il.Emit(OpCodes.Call, serialize.MakeGenericMethod(valueType));
            type = typeof(string);
            return true;
        }
        if (typeName == "TimeSpan" && member == nameof(TimeSpan.FromMinutes) && argCount == 1)
        {
            var method = typeof(TimeSpan).GetMethod(nameof(TimeSpan.FromMinutes), new[] { typeof(double) });
            if (method == null || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(double), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(TimeSpan);
            return true;
        }
        if (typeName == "DateTime" && member == nameof(DateTime.Parse) && argCount == 1)
        {
            var method = typeof(DateTime).GetMethod(nameof(DateTime.Parse), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(DateTime);
            return true;
        }
        if ((typeName == "Int32" || typeName == "int") && member == nameof(Int32.Parse) && argCount == 1)
        {
            var method = typeof(int).GetMethod(nameof(int.Parse), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if ((typeName == "Int32" || typeName == "int") && member == nameof(Int32.TryParse) && argCount == 2)
        {
            var method = typeof(int).GetMethod(nameof(int.TryParse), new[] { typeof(string), typeof(int).MakeByRefType() });
            if (method == null
                || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(string), allowLambdaLiteral: false)
                || !EmitDeclaredCallArgument(Child(callIdx, 2), typeof(int).MakeByRefType(), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (typeName == "Convert" && member == nameof(Convert.ToInt32) && argCount == 1)
        {
            var method = typeof(Convert).GetMethod(nameof(Convert.ToInt32), new[] { typeof(object) });
            if (method == null || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(object), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if (typeName == "Convert" && member == nameof(Convert.ToUInt64) && argCount == 2)
        {
            var method = typeof(Convert).GetMethod(nameof(Convert.ToUInt64), new[] { typeof(string), typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(ulong);
            return true;
        }
        if ((typeName == "UInt64" || typeName == "ulong") && member == nameof(UInt64.Parse) && argCount == 2)
        {
            var method = typeof(ulong).GetMethod(nameof(ulong.Parse), new[] { typeof(string), typeof(IFormatProvider) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(IFormatProvider)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(ulong);
            return true;
        }
        if ((typeName == "UInt64" || typeName == "ulong") && member == nameof(UInt64.Parse) && argCount == 3)
        {
            var method = typeof(ulong).GetMethod(nameof(ulong.Parse), new[] { typeof(string), typeof(System.Globalization.NumberStyles), typeof(IFormatProvider) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(string))
                || !EmitArg(callIdx, 2, typeof(System.Globalization.NumberStyles))
                || !EmitArg(callIdx, 3, typeof(IFormatProvider)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(ulong);
            return true;
        }
        if (typeName == "Enum" && member == nameof(Enum.GetName) && argCount == 2)
        {
            var method = typeof(Enum).GetMethod(nameof(Enum.GetName), new[] { typeof(Type), typeof(object) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(Type))
                || !EmitDeclaredCallArgument(Child(callIdx, 2), typeof(object), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Enum" && member == nameof(Enum.ToObject) && argCount == 2)
        {
            var method = typeof(Enum).GetMethod(nameof(Enum.ToObject), new[] { typeof(Type), typeof(object) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(Type))
                || !EmitDeclaredCallArgument(Child(callIdx, 2), typeof(object), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(object);
            return true;
        }
        if (typeName == "JsonDocument" && member == nameof(JsonDocument.Parse) && argCount == 1)
        {
            var method = typeof(JsonDocument).GetMethod(nameof(JsonDocument.Parse), new[] { typeof(string), typeof(JsonDocumentOptions) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            var options = _il.DeclareLocal(typeof(JsonDocumentOptions));
            _il.Emit(OpCodes.Ldloca, options);
            _il.Emit(OpCodes.Initobj, typeof(JsonDocumentOptions));
            _il.Emit(OpCodes.Ldloc, options);
            _il.Emit(OpCodes.Call, method);
            type = typeof(JsonDocument);
            return true;
        }
        if (typeName == "Task" && member == nameof(System.Threading.Tasks.Task.Run) && argCount == 1)
        {
            var method = typeof(System.Threading.Tasks.Task).GetMethod(nameof(System.Threading.Tasks.Task.Run), new[] { typeof(Action) });
            if (method == null || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(Action), allowLambdaLiteral: true))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (typeName == "Task" && member == nameof(System.Threading.Tasks.Task.WaitAll) && argCount >= 1)
        {
            var method = typeof(System.Threading.Tasks.Task).GetMethod(nameof(System.Threading.Tasks.Task.WaitAll), new[] { typeof(System.Threading.Tasks.Task[]) });
            if (method == null)
                return false;

            var taskArrayType = typeof(System.Threading.Tasks.Task[]);
            if (argCount == 1
                && TryGetPreflightExpressionType(Child(callIdx, 1), out var directArgType)
                && TypesEquivalent(directArgType, taskArrayType))
            {
                if (!EmitDeclaredCallArgument(Child(callIdx, 1), taskArrayType, allowLambdaLiteral: false))
                    return false;
            }
            else
            {
                _il.Emit(OpCodes.Ldc_I4, argCount);
                _il.Emit(OpCodes.Newarr, typeof(System.Threading.Tasks.Task));
                for (var a = 1; a <= argCount; a++)
                {
                    _il.Emit(OpCodes.Dup);
                    _il.Emit(OpCodes.Ldc_I4, a - 1);
                    if (!EmitDeclaredCallArgument(Child(callIdx, a), typeof(System.Threading.Tasks.Task), allowLambdaLiteral: false))
                        return false;
                    _il.Emit(OpCodes.Stelem_Ref);
                }
            }

            _il.Emit(OpCodes.Call, method);
            type = typeof(void);
            return true;
        }
        if (typeName == "ArgumentNullException" && member == nameof(ArgumentNullException.ThrowIfNull) && argCount == 1)
        {
            var method = typeof(ArgumentNullException).GetMethod(nameof(ArgumentNullException.ThrowIfNull), new[] { typeof(object), typeof(string) });
            if (method == null || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(object), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Ldnull);
            _il.Emit(OpCodes.Call, method);
            type = typeof(void);
            return true;
        }
        if (typeName == "ArgumentException" && member == nameof(ArgumentException.ThrowIfNullOrWhiteSpace) && argCount == 1)
        {
            var method = typeof(ArgumentException).GetMethod(nameof(ArgumentException.ThrowIfNullOrWhiteSpace), new[] { typeof(string), typeof(string) });
            if (method == null || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(string), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Ldnull);
            _il.Emit(OpCodes.Call, method);
            type = typeof(void);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == nameof(string.Equals) && argCount == 3)
        {
            var method = typeof(string).GetMethod(nameof(string.Equals), new[] { typeof(string), typeof(string), typeof(StringComparison) });
            if (method == null
                || !EmitArg(callIdx, 1, typeof(string))
                || !EmitArg(callIdx, 2, typeof(string))
                || !EmitArg(callIdx, 3, typeof(StringComparison)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (typeName == "OperatingSystem" && member == nameof(OperatingSystem.IsWindows) && argCount == 0)
        {
            _il.Emit(OpCodes.Call, typeof(OperatingSystem).GetMethod(nameof(OperatingSystem.IsWindows), Type.EmptyTypes)!);
            type = typeof(bool);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == "Compare")
        {
            // String.Compare overloads -> int (ordinal/culture comparison sign). Two shapes are modelled:
            //   3-arg: Compare(string, string, StringComparison)
            //   6-arg: Compare(string, int, string, int, int, StringComparison)
            // Both take a StringComparison enum constant as the LAST arg (emitted as its underlying int). The
            // return is the comparison sign (<0 / 0 / >0), matching the numeric binder's pick of the same overload.
            if (argCount == 3)
            {
                var method = typeof(string).GetMethod(nameof(string.Compare),
                    new[] { typeof(string), typeof(string), typeof(StringComparison) });
                if (method == null
                    || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(string))
                    || !EmitArg(callIdx, 3, typeof(StringComparison)))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(int);
                return true;
            }
            if (argCount == 6)
            {
                var method = typeof(string).GetMethod(nameof(string.Compare),
                    new[] { typeof(string), typeof(int), typeof(string), typeof(int), typeof(int), typeof(StringComparison) });
                if (method == null
                    || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(int))
                    || !EmitArg(callIdx, 3, typeof(string)) || !EmitArg(callIdx, 4, typeof(int))
                    || !EmitArg(callIdx, 5, typeof(int)) || !EmitArg(callIdx, 6, typeof(StringComparison)))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(int);
                return true;
            }
            return false;
        }
        if ((typeName == "String" || typeName == "string") && member == "IsNullOrWhiteSpace" && argCount == 1)
        {
            var method = typeof(string).GetMethod(nameof(string.IsNullOrWhiteSpace), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == "IsNullOrEmpty" && argCount == 1)
        {
            var method = typeof(string).GetMethod(nameof(string.IsNullOrEmpty), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == "Join" && argCount == 2)
        {
            var valuesType = typeof(IEnumerable<string>);
            var method = typeof(string).GetMethod(nameof(string.Join), new[] { typeof(string), valuesType });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, valuesType))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (typeName == "Array" && member == "Fill" && (argCount == 2 || argCount == 4))
        {
            // Array.Fill<T>(T[] array, T value) and Array.Fill<T>(T[] array, T value, int startIndex, int count)
            // -> void. The array's element type drives the generic instantiation; the value must match the
            // element type; ranged fills additionally require int startIndex/count.
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (!EmitArg(callIdx, 2, elementType))
                return false;
            if (argCount == 4 && (!EmitArg(callIdx, 3, typeof(int)) || !EmitArg(callIdx, 4, typeof(int))))
                return false;
            var fill = ResolveArrayFill(argCount);
            if (fill == null)
                return false;
            _il.Emit(OpCodes.Call, fill.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        if (typeName == "Array" && member == "Resize" && argCount == 2)
        {
            // Array.Resize<T>(ref T[] array, int newSize) -> void. Keep this as an exact ref-to-SZ-array
            // special case instead of opening general byref reference slots in IsSupportedParameterType.
            var refArg = Child(callIdx, 1);
            if (_nodes.Kind(refArg) != 54 || _nodes.ChildCount(refArg) != 1 || Text(refArg) != "ref")
                return false;
            if (!TryGetAddressableTargetType(Child(refArg, 0), out var arrayType)
                || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (!EmitByRefCallArgument(refArg, arrayType.MakeByRefType())
                || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            var resize = ResolveArrayResize();
            if (resize == null)
                return false;
            _il.Emit(OpCodes.Call, resize.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        if (typeName == "Array" && member == "Sort" && (argCount == 1 || argCount == 3 || argCount == 4))
        {
            // Array.Sort<T>(T[] array), Array.Sort<T>(T[] array, int index, int length), and the ranged
            // IComparer<T> overload -> void. Keep this to one supported SZ array; key/value parallel arrays and
            // comparison-delegate overloads stay declined.
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (argCount == 3 && (!EmitArg(callIdx, 2, typeof(int)) || !EmitArg(callIdx, 3, typeof(int))))
                return false;
            if (argCount == 4
                && (!EmitArg(callIdx, 2, typeof(int))
                    || !EmitArg(callIdx, 3, typeof(int))
                    || !EmitArg(callIdx, 4, typeof(IComparer<>).MakeGenericType(elementType))))
                return false;
            var sort = ResolveArraySort(argCount);
            if (sort == null)
                return false;
            _il.Emit(OpCodes.Call, sort.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        if (typeName == "Array" && member == "Reverse" && (argCount == 1 || argCount == 3))
        {
            // Array.Reverse<T>(T[] array) and Array.Reverse<T>(T[] array, int index, int length) -> void. Keep
            // this to one supported SZ array; non-generic Array and unsupported element shapes stay declined.
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (argCount == 3 && (!EmitArg(callIdx, 2, typeof(int)) || !EmitArg(callIdx, 3, typeof(int))))
                return false;
            var reverse = ResolveArrayReverse(argCount);
            if (reverse == null)
                return false;
            _il.Emit(OpCodes.Call, reverse.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        if (typeName == "Array" && member == "Clear" && (argCount == 1 || argCount == 3))
        {
            // Array.Clear(Array) and Array.Clear(Array, int, int) -> void. The emitted argument remains the
            // concrete T[] reference; the BCL parameter is System.Array, so no copy or element loop is introduced.
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;

            MethodInfo? clear;
            if (argCount == 1)
            {
                clear = typeof(Array).GetMethod(nameof(Array.Clear), new[] { typeof(Array) });
            }
            else
            {
                clear = typeof(Array).GetMethod(nameof(Array.Clear), new[] { typeof(Array), typeof(int), typeof(int) });
                if (!EmitArg(callIdx, 2, typeof(int)) || !EmitArg(callIdx, 3, typeof(int)))
                    return false;
            }
            if (clear == null)
                return false;
            _il.Emit(OpCodes.Call, clear);
            type = typeof(void);
            return true;
        }
        if (typeName == "Array" && member == "Copy" && (argCount == 3 || argCount == 5))
        {
            // Array.Copy(Array, Array, int) and Array.Copy(Array, int, Array, int, int) -> void. Keep this slice
            // to exact same-element SZ-array copies; wider Array covariance and long-index overloads stay declined.
            if (!EmitExpression(Child(callIdx, 1), out var sourceArrayType) || !sourceArrayType.IsSZArray)
                return false;

            MethodInfo? copy;
            if (argCount == 3)
            {
                if (!EmitExpression(Child(callIdx, 2), out var destinationArrayType)
                    || !AreSameSupportedArrayType(sourceArrayType, destinationArrayType)
                    || !EmitArg(callIdx, 3, typeof(int)))
                    return false;
                copy = typeof(Array).GetMethod(nameof(Array.Copy), new[] { typeof(Array), typeof(Array), typeof(int) });
            }
            else
            {
                if (!EmitArg(callIdx, 2, typeof(int))
                    || !EmitExpression(Child(callIdx, 3), out var destinationArrayType)
                    || !AreSameSupportedArrayType(sourceArrayType, destinationArrayType)
                    || !EmitArg(callIdx, 4, typeof(int))
                    || !EmitArg(callIdx, 5, typeof(int)))
                    return false;
                copy = typeof(Array).GetMethod(nameof(Array.Copy), new[] { typeof(Array), typeof(int), typeof(Array), typeof(int), typeof(int) });
            }
            if (copy == null)
                return false;
            _il.Emit(OpCodes.Call, copy);
            type = typeof(void);
            return true;
        }
        return Decline(
            "emit.call.static-member-unmodeled",
            "static call '" + typeName + "." + member + "' with " + argCount.ToString() + " argument(s) is not modeled",
            callIdx);
    }

    private static bool AreSameSupportedArrayType(Type sourceArrayType, Type destinationArrayType)
    {
        if (!sourceArrayType.IsSZArray || !destinationArrayType.IsSZArray)
            return false;
        var sourceElementType = sourceArrayType.GetElementType()!;
        var destinationElementType = destinationArrayType.GetElementType()!;
        return sourceElementType == destinationElementType && IsSupportedElementType(sourceElementType);
    }

    // System.Array.Fill<T> as a generic method DEFINITION. The caller binds T via MakeGenericMethod(elementType).
    // Returns null if the requested overload is unexpectedly absent (then the call declines).
    private static MethodInfo? ResolveArrayFill(int parameterCount)
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name == "Fill" && m.IsGenericMethodDefinition && m.GetParameters().Length == parameterCount)
                return m;
        }
        return null;
    }

    // System.Array.Resize<T>(ref T[] array, int newSize) as a generic method DEFINITION.
    private static MethodInfo? ResolveArrayResize()
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name != "Resize" || !m.IsGenericMethodDefinition)
                continue;
            var parameters = m.GetParameters();
            if (parameters.Length == 2 && parameters[0].ParameterType.IsByRef && parameters[1].ParameterType == typeof(int))
                return m;
        }
        return null;
    }

    // System.Array.Sort<T>(T[] array[, int index, int length[, IComparer<T> comparer]]) as a generic method
    // DEFINITION.
    private static MethodInfo? ResolveArraySort(int parameterCount)
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name != "Sort" || !m.IsGenericMethodDefinition)
                continue;
            var parameters = m.GetParameters();
            if (parameters.Length != parameterCount
                || !parameters[0].ParameterType.IsSZArray
                || !parameters[0].ParameterType.GetElementType()!.IsGenericParameter)
                continue;
            if (parameterCount == 1
                || (parameters[1].ParameterType == typeof(int) && parameters[2].ParameterType == typeof(int)))
            {
                if (parameterCount == 4)
                {
                    var comparerType = parameters[3].ParameterType;
                    if (!comparerType.IsGenericType || comparerType.GetGenericTypeDefinition() != typeof(IComparer<>))
                        continue;
                }
                return m;
            }
        }
        return null;
    }

    // System.Array.Reverse<T>(T[] array[, int index, int length]) as a generic method DEFINITION.
    private static MethodInfo? ResolveArrayReverse(int parameterCount)
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name != "Reverse" || !m.IsGenericMethodDefinition)
                continue;
            var parameters = m.GetParameters();
            if (parameters.Length != parameterCount
                || !parameters[0].ParameterType.IsSZArray
                || !parameters[0].ParameterType.GetElementType()!.IsGenericParameter)
                continue;
            if (parameterCount == 1
                || (parameters[1].ParameterType == typeof(int) && parameters[2].ParameterType == typeof(int)))
                return m;
        }
        return null;
    }

    // ---- Named-tuple element names (the columnar mirror of the legacy emitter's _tupleElementNamesByVariable) ----

    // The tuple element names statically derivable for an expression node: an identifier with tracked
    // names, a parenthesized wrap, a NAMED tuple literal (kind-17 with kind-43 wrappers), or a direct
    // sibling call whose declared return type carries names. Null = no names (no rewrite happens).
    private string?[]? TupleNamesOfExpressionNode(int node)
    {
        switch (_nodes.Kind(node))
        {
            case 6:
                return _nodes.ValueStart(node) >= 0 && _tupleNamesByVariable.TryGetValue(Text(node), out var variableNames)
                    ? variableNames
                    : null;
            case 7:
                return _nodes.ChildCount(node) == 1 ? TupleNamesOfExpressionNode(Child(node, 0)) : null;
            case 17:
            {
                if (_nodes.ChildCount(node) == 0 || _nodes.Kind(Child(node, 0)) != 43)
                    return null;
                var literalNames = new string?[_nodes.ChildCount(node)];
                for (var i = 0; i < literalNames.Length; i++)
                {
                    var elementNode = Child(node, i);
                    if (_nodes.Kind(elementNode) != 43)
                        return null; // all-or-nothing by the kernel; defensive.
                    literalNames[i] = Text(elementNode);
                }
                return literalNames;
            }
            case 9:
            {
                var callee = Child(node, 0);
                if (_nodes.Kind(callee) == 6 && _nodes.ValueStart(callee) >= 0 && _siblingReturnTupleNames != null
                    && !_locals.ContainsKey(Text(callee)) && !_paramOrdinals.ContainsKey(Text(callee))
                    && _siblingReturnTupleNames.TryGetValue(Text(callee), out var returnNames))
                {
                    return returnNames;
                }
                return null;
            }
            default:
                return null;
        }
    }

    private bool TryEmitStringConcatChain(int idx, out Type type)
    {
        type = null!;
        var terms = new List<int>();
        var pending = new Stack<int>();
        var seen = new HashSet<int>();
        pending.Push(idx);
        while (pending.Count > 0)
        {
            var current = pending.Pop();
            if (!seen.Add(current))
                return false;
            if (_nodes.Kind(current) == 12 && Text(current) == "+" && _nodes.ChildCount(current) == 2)
            {
                pending.Push(Child(current, 1));
                pending.Push(Child(current, 0));
                continue;
            }
            terms.Add(current);
        }
        if (terms.Count <= 2)
            return false;
        for (var i = 0; i < terms.Count; i++)
        {
            if (!CanProveStringExpression(terms[i]))
                return false;
        }

        _il.Emit(OpCodes.Ldc_I4, terms.Count);
        _il.Emit(OpCodes.Newarr, typeof(string));
        for (var i = 0; i < terms.Count; i++)
        {
            _il.Emit(OpCodes.Dup);
            _il.Emit(OpCodes.Ldc_I4, i);
            if (!EmitExpression(terms[i], out var termType) || termType != typeof(string))
                return false;
            _il.Emit(OpCodes.Stelem_Ref);
        }
        _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string[]) })!);
	        type = typeof(string);
	        return true;
	    }

	    private bool TryEmitStringCharConcat(Type leftType, Type rightType, out Type type)
	    {
	        type = null!;
	        if (leftType == typeof(string) && rightType == typeof(char))
	        {
	            EmitTopCharToString();
	            _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
	            type = typeof(string);
	            return true;
	        }

	        if (leftType == typeof(char) && rightType == typeof(string))
	        {
	            var right = _il.DeclareLocal(typeof(string));
	            _il.Emit(OpCodes.Stloc, right);
	            EmitTopCharToString();
	            _il.Emit(OpCodes.Ldloc, right);
	            _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
	            type = typeof(string);
	            return true;
	        }

	        return false;
	    }

	    private void EmitTopCharToString()
	    {
	        var value = _il.DeclareLocal(typeof(char));
	        _il.Emit(OpCodes.Stloc, value);
	        _il.Emit(OpCodes.Ldloca, value);
	        _il.Emit(OpCodes.Call, typeof(char).GetMethod(nameof(char.ToString), Type.EmptyTypes)!);
	    }

	    private bool CanProveStringExpression(int idx)
	    {
        switch (_nodes.Kind(idx))
        {
            case 3:
                return true;
            case 6:
            {
                var name = Text(idx);
                if (_locals.TryGetValue(name, out var local))
                    return local.LocalType == typeof(string);
                return _paramTypes.TryGetValue(name, out var paramType) && paramType == typeof(string);
            }
            case 7:
                return _nodes.ChildCount(idx) == 1 && CanProveStringExpression(Child(idx, 0));
            default:
                return false;
        }
    }

    private bool TryEmitPrimitiveStaticConstant(string receiverIdent, string member, out Type type)
    {
        type = null!;
        if (member != "MaxValue" && member != "MinValue")
            return false;

        switch (receiverIdent)
        {
            case "int":
            case "Int32":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? int.MaxValue : int.MinValue);
                type = typeof(int);
                return true;
            case "long":
            case "Int64":
                _il.Emit(OpCodes.Ldc_I8, member == "MaxValue" ? long.MaxValue : long.MinValue);
                type = typeof(long);
                return true;
            case "uint":
            case "UInt32":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? unchecked((int)uint.MaxValue) : 0);
                type = typeof(uint);
                return true;
            case "ulong":
            case "UInt64":
                _il.Emit(OpCodes.Ldc_I8, member == "MaxValue" ? unchecked((long)ulong.MaxValue) : 0L);
                type = typeof(ulong);
                return true;
            case "short":
            case "Int16":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? short.MaxValue : short.MinValue);
                type = typeof(short);
                return true;
            case "ushort":
            case "UInt16":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? ushort.MaxValue : 0);
                type = typeof(ushort);
                return true;
            case "byte":
            case "Byte":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? byte.MaxValue : 0);
                type = typeof(byte);
                return true;
            case "sbyte":
            case "SByte":
                _il.Emit(OpCodes.Ldc_I4, member == "MaxValue" ? sbyte.MaxValue : sbyte.MinValue);
                type = typeof(sbyte);
                return true;
            default:
                return false;
        }
    }

    // N#'s implicit NUMERIC widening for the modelled scalars, emitted as a conversion on the value
    // already on the stack: the int-promotable set (int/char/small ints) -> long (conv.i8), -> double
    // (conv.r8), -> float (conv.r4), or -> int (identity — the load already extended); long/float ->
    // double; long -> float. uint/ulong SOURCES are excluded (their extension/precision rules are
    // subtler — those mixes decline, pinned for a later rung).
    private bool TryEmitImplicitWidening(Type source, Type target)
    {
        if (ColumnarNumericFacts.IsIntPromotable(source))
        {
            if (target == typeof(int))
                return true; // already an extended i4.
            if (target == typeof(long)) { _il.Emit(OpCodes.Conv_I8); return true; }
            if (target == typeof(double)) { _il.Emit(OpCodes.Conv_R8); return true; }
            if (target == typeof(float)) { _il.Emit(OpCodes.Conv_R4); return true; }
            if (target == typeof(decimal))
            {
                var fromType = source == typeof(char) ? typeof(char) : typeof(int);
                var conversion = typeof(decimal).GetMethod("op_Implicit", BindingFlags.Public | BindingFlags.Static, null, new[] { fromType }, null);
                if (conversion == null)
                    return false;
                _il.Emit(OpCodes.Call, conversion);
                return true;
            }
            return false;
        }
        if (source == typeof(long))
        {
            if (target == typeof(double)) { _il.Emit(OpCodes.Conv_R8); return true; }
            if (target == typeof(float)) { _il.Emit(OpCodes.Conv_R4); return true; }
            if (target == typeof(decimal))
            {
                var conversion = typeof(decimal).GetMethod("op_Implicit", BindingFlags.Public | BindingFlags.Static, null, new[] { typeof(long) }, null);
                if (conversion == null)
                    return false;
                _il.Emit(OpCodes.Call, conversion);
                return true;
            }
            return false;
        }
        if (source == typeof(float) && target == typeof(double)) { _il.Emit(OpCodes.Conv_R8); return true; }
        return false;
    }

    private bool TryEmitMixedNumericBinary(int idx, string op, out Type type)
    {
        type = null!;
        if (op is not ("+" or "-" or "*" or "/" or "%" or "<" or ">" or "<=" or ">=" or "==" or "!="))
            return false;

        var leftNode = Child(idx, 0);
        var rightNode = Child(idx, 1);
        if (!TryGetPreflightExpressionType(leftNode, out var leftType)
            || !TryGetPreflightExpressionType(rightNode, out var rightType)
            || TypesEquivalent(leftType, rightType)
            || !TrySelectMixedNumericCommonType(leftType, rightType, out var opType))
            return false;

        if (!EmitExpression(leftNode, out var emittedLeft)
            || (!TypesEquivalent(emittedLeft, opType) && !TryEmitImplicitWidening(emittedLeft, opType)))
            return false;
        if (!EmitExpression(rightNode, out var emittedRight)
            || (!TypesEquivalent(emittedRight, opType) && !TryEmitImplicitWidening(emittedRight, opType)))
            return false;

        switch (op)
        {
            case "+":
                _il.Emit(OpCodes.Add);
                type = opType;
                return true;
            case "-":
                _il.Emit(OpCodes.Sub);
                type = opType;
                return true;
            case "*":
                _il.Emit(OpCodes.Mul);
                type = opType;
                return true;
            case "/":
                _il.Emit(OpCodes.Div);
                type = opType;
                return true;
            case "%":
                _il.Emit(OpCodes.Rem);
                type = opType;
                return true;
            case "<":
            case ">":
            case "<=":
            case ">=":
                EmitComparison(op, isFloat: opType == typeof(double) || opType == typeof(float));
                type = typeof(bool);
                return true;
            case "==":
            case "!=":
                EmitComparison(op);
                type = typeof(bool);
                return true;
            default:
                return false;
        }
    }

    private static bool TrySelectMixedNumericCommonType(Type left, Type right, out Type common)
    {
        common = null!;
        if (left == typeof(double) || right == typeof(double))
            common = typeof(double);
        else if (left == typeof(float) || right == typeof(float))
            common = typeof(float);
        else if (left == typeof(long) || right == typeof(long))
            common = typeof(long);
        else
            return false;

        return CanUseImplicitNumericWidening(left, common)
            && CanUseImplicitNumericWidening(right, common);
    }

    private static bool CanUseImplicitNumericWidening(Type source, Type target)
    {
        if (TypesEquivalent(source, target))
            return true;
        if (ColumnarNumericFacts.IsIntPromotable(source))
            return target == typeof(int) || target == typeof(long) || target == typeof(double) || target == typeof(float);
        if (source == typeof(long))
            return target == typeof(double) || target == typeof(float);
        if (source == typeof(float))
            return target == typeof(double);
        return false;
    }

    private bool TryEmitObjectConversion(Type source, Type target)
    {
        if (target != typeof(object) || source == typeof(void))
            return false;
        if (source == typeof(object))
            return true;
        if (source is TypeBuilder sourceBuilder)
        {
            if (IsEnumType(sourceBuilder))
            {
                _il.Emit(OpCodes.Box, sourceBuilder);
                return true;
            }

            var sourceDef = FindDefByBuilder(sourceBuilder);
            if (sourceDef != null && !sourceDef.IsReference)
                _il.Emit(OpCodes.Box, sourceBuilder);
            return true;
        }
        if (source.IsValueType || source.IsGenericParameter || IsEnumType(source))
            _il.Emit(OpCodes.Box, source);
        return true;
    }

    private static bool TryEmitReferenceConversion(Type source, Type target)
    {
        if (source == typeof(void) || source.IsValueType || target.IsValueType)
            return false;
        try
        {
            if (target.IsAssignableFrom(source))
                return true;
        }
        catch (NotSupportedException)
        {
        }

        if (source.IsSZArray && target.IsGenericType && !target.IsGenericTypeDefinition)
        {
            var targetDef = target.GetGenericTypeDefinition();
            if ((targetDef == typeof(IReadOnlyList<>) || targetDef == typeof(IReadOnlyCollection<>) || targetDef == typeof(IEnumerable<>))
                && TypesEquivalent(source.GetElementType()!, target.GetGenericArguments()[0]))
                return true;
        }

        if (source.IsGenericType && !source.IsGenericTypeDefinition && target.IsGenericType && !target.IsGenericTypeDefinition)
        {
            var sourceDef = source.GetGenericTypeDefinition();
            var targetDef = target.GetGenericTypeDefinition();
            var sourceArgs = source.GetGenericArguments();
            var targetArgs = target.GetGenericArguments();
            if (targetArgs.Length == 1 && sourceArgs.Length >= 1
                && TypesEquivalent(sourceArgs[0], targetArgs[0])
                && ((sourceDef == typeof(List<>) && (targetDef == typeof(IReadOnlyList<>) || targetDef == typeof(IReadOnlyCollection<>) || targetDef == typeof(IEnumerable<>)))
                    || (sourceDef == typeof(HashSet<>) && (targetDef == typeof(IReadOnlySet<>) || targetDef == typeof(IReadOnlyCollection<>) || targetDef == typeof(IEnumerable<>)))
                    || (sourceDef == typeof(Stack<>) && targetDef == typeof(IEnumerable<>))))
                return true;
        }

        return false;
    }

    private bool TryEmitSupportedBclPropertyAssignment(int receiverNode, string member, int valueNode)
    {
        receiverNode = UnwrapParenthesizedNode(receiverNode);

        Type receiverType;
        LocalBuilder? receiverLocal = null;
        var receiverOrdinal = -1;
        if (_nodes.Kind(receiverNode) == 6)
        {
            var receiverName = Text(receiverNode);
            if (_liftedLocals.ContainsKey(receiverName) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(receiverName)))
                return false;
            if (_locals.TryGetValue(receiverName, out var local))
            {
                receiverLocal = local;
                receiverType = local.LocalType;
            }
            else if (_paramOrdinals.TryGetValue(receiverName, out var ordinal))
            {
                receiverOrdinal = ordinal;
                receiverType = _paramTypes[receiverName];
            }
            else
            {
                return false;
            }
        }
        else
        {
            if (!TryGetPreflightExpressionType(receiverNode, out receiverType))
                return false;
        }

        if (!TryGetSupportedBclWritableProperty(receiverType, member, out var property))
            return false;

        if (receiverLocal != null)
            _il.Emit(OpCodes.Ldloc, receiverLocal);
        else if (receiverOrdinal >= 0)
            EmitLoadArgument(receiverOrdinal);
        else if (!EmitExpression(receiverNode, out var emittedReceiverType) || !TypesEquivalent(emittedReceiverType, receiverType))
            return false;

        var propertyType = property.PropertyType;
        Type valueType;
        if (TryEmitNullLiteralAsType(valueNode, propertyType, out valueType))
        {
            // Null adopted to the declared reference property type.
        }
        else if (!EmitExpression(valueNode, out valueType))
        {
            return false;
        }
        if (!TypesEquivalent(valueType, propertyType)
            && !TryEmitImplicitWidening(valueType, propertyType)
            && !TryEmitInterfaceUpcast(valueType, propertyType)
            && !TryEmitReferenceConversion(valueType, propertyType)
            && !TryEmitObjectConversion(valueType, propertyType))
            return false;

        _il.Emit(OpCodes.Callvirt, property.SetMethod!);
        return true;
    }

    // A DECIMAL literal (`2.5m`, `5m` — suffix already stripped): the IL emit is the bits-decomposed
    // 5-arg Decimal ctor (lo, mid, hi, isNegative, scale) — exact, never via double.
    private bool TryEmitDecimalLiteral(string body, out Type type)
    {
        type = null!;
        if (!decimal.TryParse(body.Replace("_", ""), System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var value))
            return false;
        var bits = decimal.GetBits(value);
        _il.Emit(OpCodes.Ldc_I4, bits[0]);
        _il.Emit(OpCodes.Ldc_I4, bits[1]);
        _il.Emit(OpCodes.Ldc_I4, bits[2]);
        _il.Emit(OpCodes.Ldc_I4, (bits[3] & unchecked((int)0x80000000)) != 0 ? 1 : 0);
        _il.Emit(OpCodes.Ldc_I4, (bits[3] >> 16) & 0xFF);
        _il.Emit(OpCodes.Newobj, typeof(decimal).GetConstructor(new[] { typeof(int), typeof(int), typeof(int), typeof(bool), typeof(byte) })!);
        type = typeof(decimal);
        return true;
    }

    // The value scalars a Nullable<T> may lift (null N2): BAKED runtime value types only — a
    // Nullable over a TypeBuilder/EnumBuilder cannot reflect its ctor/members at emit.
    private static bool IsLiftableNullableElement(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(uint)
        || t == typeof(short) || t == typeof(ushort) || t == typeof(byte) || t == typeof(sbyte)
        || t == typeof(bool) || t == typeof(char) || t == typeof(double) || t == typeof(float)
        || t == typeof(decimal) || t == typeof(TimeSpan)
        || IsSupportedValueTuple(t);

    private static bool IsSupportedNullable(Type t) =>
        t.IsGenericType && !t.IsGenericTypeDefinition
        && t.GetGenericTypeDefinition() == typeof(System.Nullable<>)
        && IsLiftableNullableElement(t.GetGenericArguments()[0]);

    // LIFTING onto a Nullable<T> target (null N2): a bare NULL emits default(T?) (initobj on a temp);
    // an already-T? value passes through; a T-typed value (or an int literal adopting T) wraps via
    // `newobj Nullable<T>(T)` — the exact N# conversions for `n: int? = 5` / `= null` / `= v` / `= m`.
    // The caller must invoke this ONLY when the target IS a supported Nullable, and a FALSE return is a
    // WHOLE-PROGRAM decline (the value may already be on the stack — never fall through and re-emit).
    private bool TryEmitValueAsNullable(int node, Type target, out Type type)
    {
        type = null!;
        var element = target.GetGenericArguments()[0];
        if (_nodes.Kind(node) == 5)
        {
            var defaultLocal = _il.DeclareLocal(target);
            _il.Emit(OpCodes.Ldloca, defaultLocal);
            _il.Emit(OpCodes.Initobj, target);
            _il.Emit(OpCodes.Ldloc, defaultLocal);
            type = target;
            return true;
        }
        if (TryEmitIntLiteralAsType(node, element, out _))
        {
            _il.Emit(OpCodes.Newobj, target.GetConstructor(new[] { element })!);
            type = target;
            return true;
        }
        if (!EmitExpression(node, out var emitted))
            return false;
        if (TypesEquivalent(emitted, target))
        {
            type = target; // already a T? value — pass through.
            return true;
        }
        if (!TypesEquivalent(emitted, element))
            return false; // emitted-but-wrong — the caller declines the whole program (stack abandoned).
        _il.Emit(OpCodes.Newobj, target.GetConstructor(new[] { element })!);
        type = target;
        return true;
    }

    // A bare NULL literal (kind 5) adopts any REFERENCE-typed target (`return null` on a string
    // function, `s = null`, a null argument) — N#'s null-assignability for the modelled set. Value-typed
    // targets decline (Nullable<T> is the N2 rung).
    private bool TryEmitNullLiteralAsType(int node, Type target, out Type type)
    {
        type = null!;
        if (_nodes.Kind(node) != 5 || target.IsValueType)
            return false;
        _il.Emit(OpCodes.Ldnull);
        type = target;
        return true;
    }

    private bool TryEmitArrayLiteralAsType(int node, Type target, out Type type)
    {
        type = null!;
        if (_nodes.Kind(node) != 58 || !target.IsSZArray)
            return false;
        var elementType = target.GetElementType()!;
        if (!IsSupportedElementType(elementType))
            return false;
        var elementCount = _nodes.ChildCount(node);
        _il.Emit(OpCodes.Ldc_I4, elementCount);
        _il.Emit(OpCodes.Newarr, elementType);
        for (var i = 0; i < elementCount; i++)
        {
            _il.Emit(OpCodes.Dup);
            _il.Emit(OpCodes.Ldc_I4, i);
            if (!TryEmitAssignableValue(Child(node, i), elementType, out _))
                return false;
            if (!EmitArrayElementStore(elementType))
                return false;
        }
        type = target;
        return true;
    }

    private bool EmitArrayElementStore(Type elementType)
    {
        if (elementType == typeof(bool)) _il.Emit(OpCodes.Stelem_I1);
        else if (elementType == typeof(int) || elementType == typeof(uint)) _il.Emit(OpCodes.Stelem_I4);
        else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Stelem_I8);
        else if (elementType == typeof(char)) _il.Emit(OpCodes.Stelem_I2);
        else if (elementType == typeof(double)) _il.Emit(OpCodes.Stelem_R8);
        else if (elementType == typeof(float)) _il.Emit(OpCodes.Stelem_R4);
        else if (elementType == typeof(string)) _il.Emit(OpCodes.Stelem_Ref);
        else if (!elementType.IsValueType) _il.Emit(OpCodes.Stelem_Ref);
        else if (elementType is TypeBuilder || IsSupportedType(elementType)) _il.Emit(OpCodes.Stelem, elementType);
        else return false;
        return true;
    }

    // An UNSUFFIXED int literal ADOPTS a small-int/uint/long/ulong target when its value fits — N#'s
    // implicit constant conversion (`b: byte = 200`, `u: ulong = 10`, `return 50` on a byte function).
    // Small ints + uint load as i4 (uint over int.MaxValue wraps the bit pattern, the standard emit);
    // long/ulong load as i8. Suffixed literals, out-of-range values (the pipeline's NL202), and
    // non-literal nodes return false — the caller falls through to its normal exact-type path.
    private bool TryEmitIntLiteralAsType(int node, Type target, out Type type)
    {
        type = null!;
        // A NEGATIVE literal arrives as unary minus (kind 11, "-") wrapping the bare literal —
        // `s: short = -300`. Signed targets only; the value emits pre-negated (no Neg opcode).
        var negative = false;
        if (_nodes.Kind(node) == 11 && _nodes.ChildCount(node) == 1 && Text(node) == "-")
        {
            negative = true;
            node = Child(node, 0);
        }
        if (_nodes.Kind(node) != 0 || _nodes.ValueStart(node) < 0)
            return false;
        var text = Text(node);
        if (text.Length == 0 || text[^1] is 'u' or 'U' or 'l' or 'L' or 'm' or 'M')
            return false; // a suffixed literal has its own fixed type.
        if (!ulong.TryParse(text, out var value))
            return false;
        if (negative)
        {
            if (target == typeof(byte) || target == typeof(ushort) || target == typeof(uint) || target == typeof(ulong))
                return false; // no negative values on unsigned targets (the pipeline's NL202).
            // Negative magnitudes cap at the MAXVALUE magnitude, not MinValue: the PIPELINE rejects
            // `v: sbyte = -128` (and the other exact MinValues) with NL202 — its negation range check is
            // off by one (known defect bundle #14) — and overflows on any unsuffixed literal beyond int
            // range regardless of target (`l: long = -5000000000` → NL103 overflow — defect #13).
            var min = target == typeof(sbyte) ? (ulong)sbyte.MaxValue
                : target == typeof(short) ? (ulong)short.MaxValue
                : (ulong)int.MaxValue;
            if (value > min)
                return false;
            if (target == typeof(long))
                _il.Emit(OpCodes.Ldc_I8, -(long)value);
            else
                _il.Emit(OpCodes.Ldc_I4, (int)(-(long)value));
            type = target;
            return true;
        }
        if (target == typeof(byte) || target == typeof(sbyte) || target == typeof(short)
            || target == typeof(ushort) || target == typeof(uint))
        {
            // uint caps at int.MaxValue, NOT uint.MaxValue: the PIPELINE mis-evaluates uint locals
            // initialized with literals above int.MaxValue (`u: uint = 4000000000; u / 2` returned the
            // signed-division bit pattern 4147483648, and `print u / 2` dropped the line entirely —
            // known defect bundle #12, probe-confirmed); columnar declines those so it never diverges.
            var max = target == typeof(byte) ? (ulong)byte.MaxValue
                : target == typeof(sbyte) ? (ulong)sbyte.MaxValue
                : target == typeof(short) ? (ulong)short.MaxValue
                : target == typeof(ushort) ? (ulong)ushort.MaxValue
                : (ulong)int.MaxValue;
            if (value > max)
                return false;
            _il.Emit(OpCodes.Ldc_I4, unchecked((int)value));
            type = target;
            return true;
        }
        if (target == typeof(long) || target == typeof(ulong))
        {
            // Positive magnitudes ALSO cap at int.MaxValue: the pipeline overflows on unsuffixed
            // literals beyond int range whatever the target (known defect bundle #13) — suffixed
            // literals (5000000000L) carry their own type and never reach this rule.
            if (value > int.MaxValue)
                return false;
            _il.Emit(OpCodes.Ldc_I8, (long)value);
            type = target;
            return true;
        }
        return false;
    }

    // Postfix `++`/`--` (kind 44) on a bare LOCAL/PARAM or field of int/long/ulong: load, step by one, store —
    // keeping the PRE-step value on the stack when `keepValue` (N# post-semantics; `m := n++` reads the
    // old n). double/float decline (the pipeline's `++` on them silently no-ops — known defect bundle);
    // lifted/boxed captures, property targets, and unsupported receivers decline.
    private bool TryEmitPostfixUnary(int idx, bool keepValue, out Type type)
    {
        type = null!;
        if (_nodes.ChildCount(idx) != 1)
            return false;
        var target = UnwrapParenthesizedNode(Child(idx, 0));
        if (_nodes.Kind(target) == 8)
            return TryEmitMemberPostfixUnary(idx, target, keepValue, out type);
        if (_nodes.Kind(target) != 6 || _nodes.ValueStart(target) < 0)
            return false;
        var name = Text(target);
        if (_liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
            return false;
        LocalBuilder? local = null;
        var paramOrdinal = -1;
        Type targetType;
        if (_locals.TryGetValue(name, out var found))
        {
            local = found;
            targetType = found.LocalType;
        }
        else if (_paramOrdinals.TryGetValue(name, out var ordinal))
        {
            paramOrdinal = ordinal;
            targetType = _paramTypes[name];
        }
        else if (_currentStruct != null
                 && (_currentStruct.IsReference || _isConstructorBody)
                 && TryFindFieldOnChain(_currentStruct, name, out var thisField))
        {
            targetType = thisField.FieldType;
            if (targetType != typeof(int) && targetType != typeof(long) && targetType != typeof(ulong))
                return false;

            _il.Emit(OpCodes.Ldarg_0);
            _il.Emit(OpCodes.Dup);
            _il.Emit(OpCodes.Ldfld, thisField);
            LocalBuilder? oldValue = null;
            if (keepValue)
            {
                oldValue = _il.DeclareLocal(targetType);
                _il.Emit(OpCodes.Dup);
                _il.Emit(OpCodes.Stloc, oldValue);
            }
            EmitPostfixStep(targetType, Text(idx));
            _il.Emit(OpCodes.Stfld, thisField);
            if (oldValue != null)
                _il.Emit(OpCodes.Ldloc, oldValue);

            type = targetType;
            return true;
        }
        else
        {
            return false;
        }
        if (targetType != typeof(int) && targetType != typeof(long) && targetType != typeof(ulong))
            return false;

        if (local != null)
            _il.Emit(OpCodes.Ldloc, local);
        else
            EmitLoadArgument(paramOrdinal);
        if (keepValue)
            _il.Emit(OpCodes.Dup);
        EmitPostfixStep(targetType, Text(idx));
        if (local != null)
            _il.Emit(OpCodes.Stloc, local);
        else
            EmitStoreArgument(paramOrdinal);
        type = targetType;
        return true;
    }

    private bool TryEmitMemberPostfixUnary(int idx, int target, bool keepValue, out Type type)
    {
        type = null!;
        if (!TryResolveMemberWriteChain(Child(target, 0), out var chain)
            || chain.ReceiverType is not TypeBuilder ownerBuilder
            || FindDefByBuilder(ownerBuilder) is not { } ownerDef
            || !TryFindFieldOnChain(ownerDef, Text(target), out var field))
        {
            return false;
        }

        var targetType = field.FieldType;
        if (targetType != typeof(int) && targetType != typeof(long) && targetType != typeof(ulong))
            return false;

        EmitMemberWriteLocator(chain);
        _il.Emit(OpCodes.Dup);
        _il.Emit(OpCodes.Ldfld, field);
        LocalBuilder? oldValue = null;
        if (keepValue)
        {
            oldValue = _il.DeclareLocal(targetType);
            _il.Emit(OpCodes.Stloc, oldValue);
            _il.Emit(OpCodes.Ldloc, oldValue);
        }
        EmitPostfixStep(targetType, Text(idx));
        _il.Emit(OpCodes.Stfld, field);
        if (oldValue != null)
            _il.Emit(OpCodes.Ldloc, oldValue);

        type = targetType;
        return true;
    }

    private void EmitPostfixStep(Type targetType, string op)
    {
        _il.Emit(OpCodes.Ldc_I4_1);
        if (targetType != typeof(int))
            _il.Emit(OpCodes.Conv_I8); // long AND ulong step by an i8 one (u8 shares the slot).
        if (_overflowCheckingEnabled)
        {
            var isUnsigned = targetType == typeof(ulong);
            _il.Emit(op == "++"
                ? (isUnsigned ? OpCodes.Add_Ovf_Un : OpCodes.Add_Ovf)
                : (isUnsigned ? OpCodes.Sub_Ovf_Un : OpCodes.Sub_Ovf));
        }
        else
        {
            _il.Emit(op == "++" ? OpCodes.Add : OpCodes.Sub);
        }
    }

    // Rewrites a named tuple member to its ItemN spelling when the receiver's tracked names contain it;
    // any other shape returns the original member (declining exactly as before this feature).
    private string MaybeRewriteTupleMemberName(int receiverNode, string member)
    {
        var names = TupleNamesOfExpressionNode(receiverNode);
        if (names == null)
            return member;
        for (var i = 0; i < names.Length; i++)
        {
            if (names[i] == member)
                return "Item" + (i + 1);
        }
        return member;
    }

    // Rebuilds the canonical type string from an embedded TYPE subtree in the expression node table
    // (kind 0 Simple = the name text; kind 1 Generic = name<argCanons>; kind 2 Array = element[],
    // kind 3 Nullable = element?, kind 6 Tuple = ValueTuple<...>, kind 7 single-child wrapper = transparent
    // named/parenthesized type element). Other type-node kinds decline until their consumers own the
    // corresponding emit path.
    private bool TryBuildTypeNodeCanonical(int typeNode, out string canonical)
    {
        switch (_nodes.Kind(typeNode))
        {
            case 0:
                canonical = Text(typeNode);
                return true;
            case 1:
            {
                var builder = new System.Text.StringBuilder(Text(typeNode));
                builder.Append('<');
                for (var c = 0; c < _nodes.ChildCount(typeNode); c++)
                {
                    if (c > 0)
                        builder.Append(',');
                    if (!TryBuildTypeNodeCanonical(Child(typeNode, c), out var argCanonical))
                    {
                        canonical = string.Empty;
                        return false;
                    }
                    builder.Append(argCanonical);
                }
                builder.Append('>');
                canonical = builder.ToString();
                return true;
            }
            case 2:
            {
                if (!TryBuildTypeNodeCanonical(Child(typeNode, 0), out var elementCanonical))
                {
                    canonical = string.Empty;
                    return false;
                }
                canonical = elementCanonical + "[]";
                return true;
            }
            case 3:
            {
                if (!TryBuildTypeNodeCanonical(Child(typeNode, 0), out var elementCanonical))
                {
                    canonical = string.Empty;
                    return false;
                }
                canonical = elementCanonical + "?";
                return true;
            }
            case 6:
            {
                var childCount = _nodes.ChildCount(typeNode);
                if (childCount < 2 || childCount > 7)
                {
                    canonical = string.Empty;
                    return false;
                }
                var builder = new System.Text.StringBuilder("ValueTuple<");
                for (var c = 0; c < childCount; c++)
                {
                    if (c > 0)
                        builder.Append(',');
                    if (!TryBuildTypeNodeCanonical(Child(typeNode, c), out var argCanonical))
                    {
                        canonical = string.Empty;
                        return false;
                    }
                    builder.Append(argCanonical);
                }
                builder.Append('>');
                canonical = builder.ToString();
                return true;
            }
            case 7:
            {
                if (_nodes.ChildCount(typeNode) != 1)
                {
                    canonical = string.Empty;
                    return false;
                }
                return TryBuildTypeNodeCanonical(Child(typeNode, 0), out canonical);
            }
            default:
                canonical = string.Empty;
                return false;
        }
    }

    // Type equality that treats two CLOSED instantiations of the same user generic as EQUAL even when
    // they are distinct TypeBuilderInstantiation instances: MakeGenericType over a TypeBuilder does not
    // cache, and TypeBuilderInstantiation equality is referential — so `new Box<Box<int>>(new Box<int>(v))`
    // produces one Box<int> from the inner construction and ANOTHER from the ctor-parameter substitution.
    private static bool TypesEquivalent(Type a, Type b)
    {
        if (a == b)
            return true;
        if (IsEnumType(a) || IsEnumType(b))
            return IsSameEnumType(a, b);
        if (a.IsByRef || b.IsByRef)
            return a.IsByRef && b.IsByRef && TypesEquivalent(a.GetElementType()!, b.GetElementType()!);
        if (a.IsSZArray || b.IsSZArray)
            return a.IsSZArray && b.IsSZArray && TypesEquivalent(a.GetElementType()!, b.GetElementType()!);
        if (a is TypeBuilder || b is TypeBuilder)
        {
            if (a is not TypeBuilder leftBuilder || b is not TypeBuilder rightBuilder)
                return false;
            return string.Equals(leftBuilder.FullName, rightBuilder.FullName, StringComparison.Ordinal)
                && ReferenceEquals(leftBuilder.Module, rightBuilder.Module);
        }
        // Structural equivalence for closed generic INSTANTIATIONS — user-headed (Box<int>) AND
        // builder-bound BCL-headed (List<Pt>, Dictionary<string,Pt>): every independent MakeGenericType
        // over a builder yields a referentially DISTINCT TypeBuilderInstantiation (probe-proven), so
        // definitions must reference-match and arguments recurse. Fully baked instantiations are cached
        // by the runtime and already matched by the == above.
        if (!a.IsGenericType || !b.IsGenericType || a.IsGenericTypeDefinition || b.IsGenericTypeDefinition)
            return false;
        Type aDef, bDef;
            aDef = a.GetGenericTypeDefinition();
            bDef = b.GetGenericTypeDefinition();
        if (!TypesEquivalent(aDef, bDef))
            return false;
        var aArgs = a.GetGenericArguments();
        var bArgs = b.GetGenericArguments();
        if (aArgs.Length != bArgs.Length)
            return false;
        for (var i = 0; i < aArgs.Length; i++)
        {
            if (!TypesEquivalent(aArgs[i], bArgs[i]))
                return false;
        }
        return true;
    }

    private static bool IsSameEnumType(Type a, Type b)
    {
        if (!IsEnumType(a) || !IsEnumType(b))
            return false;
        try
        {
            if (a.TypeHandle.Equals(b.TypeHandle))
                return true;
        }
        catch (NotSupportedException)
        {
        }
        return string.Equals(a.FullName, b.FullName, StringComparison.Ordinal)
            && ReferenceEquals(a.Module, b.Module);
    }

    private bool IsKnownEnumType(Type type)
    {
        if (IsEnumType(type))
            return true;
        foreach (var enumDef in _enumRegistry.Values)
        {
            if (ReferenceEquals(enumDef.EnumType, type))
                return true;
        }
        return false;
    }

    private bool TrySelectUserConstructor(
        int newNode,
        ColumnarStructDef def,
        out ConstructorBuilder chosenCtor,
        out Type[] chosenParamTypes,
        out int[] chosenDefaultKinds,
        out string?[] chosenDefaultTexts)
    {
        chosenCtor = null!;
        chosenParamTypes = null!;
        chosenDefaultKinds = null!;
        chosenDefaultTexts = null!;
        var argCount = _nodes.ChildCount(newNode) - 1;
        var candidates = new List<(ConstructorBuilder Builder, Type[] ParamTypes, int[] DefaultKinds, string?[] DefaultTexts)>();
        foreach (var ctor in def.Constructors)
        {
            if (ctor.ParamTypes.Length < argCount)
                continue;
            var hasTrailingDefaults = true;
            for (var p = argCount; p < ctor.ParamTypes.Length; p++)
            {
                if (!CanUseConstructorDefaultAs(ctor.ParamTypes[p], ctor.DefaultKinds, ctor.DefaultTexts, p))
                {
                    hasTrailingDefaults = false;
                    break;
                }
            }
            if (hasTrailingDefaults)
                candidates.Add(ctor);
        }
        if (candidates.Count == 0)
            return false;
        var exactCandidates = new List<(ConstructorBuilder Builder, Type[] ParamTypes, int[] DefaultKinds, string?[] DefaultTexts)>();
        foreach (var candidate in candidates)
        {
            if (candidate.ParamTypes.Length == argCount)
                exactCandidates.Add(candidate);
        }
        if (exactCandidates.Count > 0)
            candidates = exactCandidates;
        if (candidates.Count == 1)
        {
            chosenCtor = candidates[0].Builder;
            chosenParamTypes = candidates[0].ParamTypes;
            chosenDefaultKinds = candidates[0].DefaultKinds;
            chosenDefaultTexts = candidates[0].DefaultTexts;
            return true;
        }

        foreach (var ctor in candidates)
        {
            var matches = true;
            for (var a = 0; a < argCount; a++)
            {
                if (!CanEmitConstructorArgumentAs(Child(newNode, 1 + a), ctor.ParamTypes[a]))
                {
                    matches = false;
                    break;
                }
            }
            if (!matches)
                continue;
            if (chosenCtor != null)
                return false;
            chosenCtor = ctor.Builder;
            chosenParamTypes = ctor.ParamTypes;
            chosenDefaultKinds = ctor.DefaultKinds;
            chosenDefaultTexts = ctor.DefaultTexts;
        }
        return chosenCtor != null;
    }

    private bool CanUseConstructorDefaultAs(Type expectedType, int[] defaultKinds, string?[] defaultTexts, int index)
    {
        if (index < 0 || index >= defaultKinds.Length || index >= defaultTexts.Length)
            return false;
        return defaultKinds[index] switch
        {
            46 => !expectedType.IsValueType,
            44 or 45 => expectedType == typeof(bool),
            1 => expectedType == typeof(int)
                 && int.TryParse(defaultTexts[index], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out _),
            4 => expectedType == typeof(string),
            ParameterDefaultMemberAccessKind => TryResolveStringEnumParameterDefault(expectedType, defaultTexts[index], _enumRegistry, out _)
                                                || TryResolveEnumParameterDefault(expectedType, defaultTexts[index], _enumRegistry, out _),
            _ => false,
        };
    }

    private bool TryEmitConstructorDefaultArgument(Type expectedType, int defaultKind, string? defaultText, out Type type)
    {
        type = null!;
        switch (defaultKind)
        {
            case 46 when !expectedType.IsValueType:
                _il.Emit(OpCodes.Ldnull);
                type = expectedType;
                return true;
            case 44 when expectedType == typeof(bool):
                _il.Emit(OpCodes.Ldc_I4_1);
                type = typeof(bool);
                return true;
            case 45 when expectedType == typeof(bool):
                _il.Emit(OpCodes.Ldc_I4_0);
                type = typeof(bool);
                return true;
            case 1 when expectedType == typeof(int)
                        && int.TryParse(defaultText, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var intDefault):
                _il.Emit(OpCodes.Ldc_I4, intDefault);
                type = typeof(int);
                return true;
            case 4 when expectedType == typeof(string):
                _il.Emit(OpCodes.Ldstr, defaultText != null ? NSharpLang.Compiler.StringLiteralDecoder.Decode(defaultText) : string.Empty);
                type = typeof(string);
                return true;
            case ParameterDefaultMemberAccessKind when TryResolveStringEnumParameterDefault(expectedType, defaultText, _enumRegistry, out var stringEnumDefault):
                _il.Emit(OpCodes.Ldstr, stringEnumDefault);
                type = expectedType;
                return true;
            case ParameterDefaultMemberAccessKind when TryResolveEnumParameterDefault(expectedType, defaultText, _enumRegistry, out var enumDefault):
                _il.Emit(OpCodes.Ldc_I4, enumDefault);
                type = expectedType;
                return true;
            default:
                return false;
        }
    }

    private bool CanEmitConstructorArgumentAs(int argNode, Type expectedType)
    {
        argNode = UnwrapParenthesizedNode(argNode);
        if (_nodes.Kind(argNode) == 5)
            return !expectedType.IsValueType;
        if (CanAdoptIntLiteralAsType(argNode, expectedType))
            return true;
        return TryGetPreflightExpressionType(argNode, out var actualType)
               && (TypesEquivalent(actualType, expectedType)
                   || CanUseInterfaceUpcast(actualType, expectedType)
                   || TryEmitReferenceConversion(actualType, expectedType)
                   || CanUseObjectConversion(actualType, expectedType));
    }

    private bool TryGetPreflightExpressionType(int node, out Type type)
    {
        node = UnwrapParenthesizedNode(node);
        type = null!;
        switch (_nodes.Kind(node))
        {
            case 0:
                return TryGetIntLiteralType(Text(node), out type);
            case 1:
            {
                var raw = Text(node);
                var last = raw.Length > 0 ? raw[raw.Length - 1] : '\0';
                if (last == 'm' || last == 'M')
                {
                    type = typeof(decimal);
                    return true;
                }
                type = last == 'f' || last == 'F' ? typeof(float) : typeof(double);
                return true;
            }
            case 2:
                type = typeof(char);
                return true;
            case 3:
                type = typeof(string);
                return true;
            case 4:
                type = typeof(bool);
                return true;
            case 6:
            {
                var name = Text(node);
                if (_locals.TryGetValue(name, out var local))
                {
                    type = local.LocalType;
                    return true;
                }
                if (_paramTypes.TryGetValue(name, out var paramType) && _paramOrdinals.ContainsKey(name))
                {
                    type = paramType;
                    return true;
                }
                if (_currentStruct != null && TryFindFieldOnChain(_currentStruct, name, out var thisField))
                {
                    type = thisField.FieldType;
                    return true;
                }
                if (_currentStruct != null && TryFindPropertyOnChain(_currentStruct, name, out var thisProperty))
                {
                    type = thisProperty.PropertyType;
                    return true;
                }
                return false;
            }
            case 8:
                return TryGetPreflightMemberAccessType(node, out type);
            case 15:
                return TryGetNewExpressionResultType(node, out type);
            case 16:
            {
                if (_nodes.ChildCount(node) != 2 || _nodes.Kind(Child(node, 0)) != 0)
                    return false;
                var castTargetName = Text(Child(node, 0));
                return (TryResolveBuiltin(castTargetName, out type)
                        || TryResolveType(castTargetName, _enumRegistry, _structRegistry, _unionRegistry, out type))
                       && IsSupportedType(type);
            }
            case 9:
            {
                // Preflight a CALL's result type via the bare-call resolution tiers (no emission):
                // local function -> sibling top-level -> instance chain -> static chain. Shadowed
                // names and member-access callees stay un-preflighted.
                var callee = Child(node, 0);
                if (_nodes.Kind(callee) == 8)
                {
                    var receiver = Child(callee, 0);
                    if (TryGetPreflightExpressionType(receiver, out var receiverType)
                        && TryGetPreflightInstanceCallType(receiverType, Text(callee), node, out type))
                        return true;
                    return false;
                }
                if (_nodes.Kind(callee) != 6)
                    return false;
                var calleeName = Text(callee);
                if (_locals.ContainsKey(calleeName) || _paramOrdinals.ContainsKey(calleeName)
                    || _liftedLocals.ContainsKey(calleeName) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(calleeName)))
                    return false;
                if (_localFuncs != null && _visibleLocalFuncs.Contains(calleeName) && _localFuncs.TryGetValue(calleeName, out var localFn))
                {
                    type = localFn.ReturnType;
                    return true;
                }
                if (_siblings.TryGetValue(calleeName, out var sibling) && sibling.TypeParams.Length == 0)
                {
                    type = sibling.ReturnType;
                    return true;
                }
                if (_currentStruct != null && TrySelectInstanceMethodOnChain(_currentStruct, calleeName, node, out var ownMethod))
                {
                    type = ownMethod.ReturnType;
                    return true;
                }
                if (_enclosingType != null && TryFindStaticMethodOnChain(_enclosingType, calleeName, _nodes.ChildCount(node) - 1, out var ownStatic))
                {
                    type = ownStatic.ReturnType;
                    return true;
                }
                return false;
            }
            case 57:
                return _nodes.ChildCount(node) == 1 && TryGetPreflightExpressionType(Child(node, 0), out type);
            default:
                return false;
        }
    }

    private bool TryGetPreflightInstanceCallType(Type receiverType, string member, int callIdx, out Type type)
    {
        type = null!;
        if (receiverType is TypeBuilder receiverBuilder)
        {
            var def = FindDefByBuilder(receiverBuilder);
            if (def != null && TrySelectInstanceMethodOnChain(def, member, callIdx, out var method))
            {
                type = method.ReturnType;
                return true;
            }
            if (def is { IsRecord: true })
            {
                if (member == "Equals" && _nodes.ChildCount(callIdx) == 2 && def.RecordEquals != null)
                {
                    type = typeof(bool);
                    return true;
                }
                if (member == "GetHashCode" && _nodes.ChildCount(callIdx) == 1 && def.RecordGetHashCode != null)
                {
                    type = typeof(int);
                    return true;
                }
            }
            return false;
        }

        if (TryGetClosedReceiverDef(receiverType, out var closedDef, out var closedArgs)
            && TrySelectInstanceMethodOnChain(closedDef, member, callIdx, out var closedMethod))
        {
            type = SubstituteClosedTypeArguments(closedMethod.ReturnType, closedArgs);
            return true;
        }

        return false;
    }

    private bool TryGetPreflightMemberAccessType(int node, out Type type)
    {
        type = null!;
        if (TryResolveMemberWriteChain(node, out var chain))
        {
            type = chain.ReceiverType;
            return true;
        }

        var receiver = Child(node, 0);
        var member = Text(node);
        if (TryGetPreflightExpressionType(receiver, out var instanceReceiverType)
            && TryResolveInterpolationMemberPlan(instanceReceiverType, member, out var instanceHop)
            && IsSupportedType(instanceHop.ValueType))
        {
            type = instanceHop.ValueType;
            return true;
        }

        if (member == "Count"
            && TryGetPreflightExpressionType(receiver, out var receiverType)
            && TryResolveCollectionCountGetter(receiverType, out _))
        {
            type = typeof(int);
            return true;
        }

        if (_nodes.Kind(receiver) == 6)
        {
            var receiverIdent = Text(receiver);
            var isUnshadowedTypeName = !_locals.ContainsKey(receiverIdent)
                && !_liftedLocals.ContainsKey(receiverIdent)
                && !_paramOrdinals.ContainsKey(receiverIdent)
                && !_siblings.ContainsKey(receiverIdent);
            if (!isUnshadowedTypeName)
                return false;
            if (receiverIdent == "StringComparison")
            {
                type = typeof(StringComparison);
                return true;
            }
            if (receiverIdent == "StringComparer" && Text(node) is "Ordinal" or "OrdinalIgnoreCase")
            {
                type = typeof(StringComparer);
                return true;
            }
            if (receiverIdent == "JsonNamingPolicy" && Text(node) == nameof(JsonNamingPolicy.CamelCase))
            {
                type = typeof(JsonNamingPolicy);
                return true;
            }
            if (receiverIdent == "DateTime"
                && typeof(DateTime).GetProperty(Text(node), BindingFlags.Public | BindingFlags.Static) is { GetMethod: not null } dateTimeStaticProperty
                && IsSupportedType(dateTimeStaticProperty.PropertyType))
            {
                type = dateTimeStaticProperty.PropertyType;
                return true;
            }
            if (receiverIdent == "DateTime"
                && typeof(DateTime).GetField(Text(node), BindingFlags.Public | BindingFlags.Static) is { } dateTimeStaticField
                && IsSupportedType(dateTimeStaticField.FieldType))
            {
                type = dateTimeStaticField.FieldType;
                return true;
            }
            if (receiverIdent == "Random" && Text(node) == nameof(Random.Shared))
            {
                type = typeof(Random);
                return true;
            }
            if (_enumRegistry.TryGetValue(receiverIdent, out var userEnum)
                && ((userEnum.StringConstants != null && userEnum.StringConstants.ContainsKey(Text(node)))
                    || userEnum.Constants.ContainsKey(Text(node))))
            {
                type = userEnum.EnumType;
                return true;
            }
            if (_structRegistry.TryGetValue(receiverIdent, out var staticOwner))
            {
                if (TryFindStaticFieldOnChain(staticOwner, Text(node), out var staticField))
                {
                    type = staticField.FieldType;
                    return true;
                }
                if (TryFindStaticPropertyOnChain(staticOwner, Text(node), out var staticProperty))
                {
                    type = staticProperty.PropertyType;
                    return true;
                }
            }
        }
        return false;
    }

    private bool TryGetNewExpressionResultType(int node, out Type type)
    {
        type = null!;
        if (_nodes.Kind(node) != 15 || _nodes.ChildCount(node) == 0)
            return false;
        var typeNode = Child(node, 0);
        if (_nodes.Kind(typeNode) == 0)
        {
            var typeName = Text(typeNode);
            type = typeName switch
            {
                "string" => typeof(string),
                "StringBuilder" => typeof(System.Text.StringBuilder),
                "Version" => typeof(Version),
                "object" => typeof(object),
                "ProcessStartInfo" => typeof(ProcessStartInfo),
                "Process" => typeof(Process),
                "Exception" => typeof(Exception),
                "InvalidOperationException" => typeof(InvalidOperationException),
                "ArgumentException" => typeof(ArgumentException),
                "FormatException" => typeof(FormatException),
                "TimeoutException" => typeof(TimeoutException),
                "NotSupportedException" => typeof(NotSupportedException),
                _ => null!,
            };
            if (type != null)
                return true;
            if (_structRegistry.TryGetValue(typeName, out var def))
            {
                type = def.Builder;
                return true;
            }
            return false;
        }
        if (_nodes.Kind(typeNode) == 1)
        {
            return TryBuildTypeNodeCanonical(typeNode, out var canonical)
                   && TryResolveType(canonical, _enumRegistry, _structRegistry, _unionRegistry, out type);
        }
        if (_nodes.Kind(typeNode) == 2)
        {
            var elementNode = Child(typeNode, 0);
            if (!TryBuildTypeNodeCanonical(elementNode, out var elementCanonical)
                || !TryResolveType(elementCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var elementType)
                || !IsSupportedElementType(elementType))
                return false;
            type = elementType.MakeArrayType();
            return true;
        }
        return false;
    }

    private static bool TryGetIntLiteralType(string text, out Type type)
    {
        type = null!;
        if (text.Length > 0 && text[^1] is 'm' or 'M')
        {
            type = typeof(decimal);
            return true;
        }
        var end = text.Length;
        var sawU = false;
        var sawL = false;
        while (end > 0 && (text[end - 1] is 'u' or 'U' or 'l' or 'L'))
        {
            if (text[end - 1] is 'u' or 'U') sawU = true; else sawL = true;
            end--;
        }
        if (sawU && sawL)
        {
            type = typeof(ulong);
            return true;
        }
        if (sawU)
            return false;
        type = sawL ? typeof(long) : typeof(int);
        return true;
    }

    private bool CanAdoptIntLiteralAsType(int node, Type target)
    {
        var negative = false;
        if (_nodes.Kind(node) == 11 && _nodes.ChildCount(node) == 1 && Text(node) == "-")
        {
            negative = true;
            node = Child(node, 0);
        }
        if (_nodes.Kind(node) != 0 || _nodes.ValueStart(node) < 0)
            return false;
        var text = Text(node);
        if (text.Length == 0 || text[^1] is 'u' or 'U' or 'l' or 'L' or 'm' or 'M')
            return false;
        if (!ulong.TryParse(text, out var value))
            return false;
        if (negative)
        {
            if (target == typeof(byte) || target == typeof(ushort) || target == typeof(uint) || target == typeof(ulong))
                return false;
            var min = target == typeof(sbyte) ? (ulong)sbyte.MaxValue
                : target == typeof(short) ? (ulong)short.MaxValue
                : (ulong)int.MaxValue;
            return value <= min && (target == typeof(sbyte) || target == typeof(short) || target == typeof(int) || target == typeof(long));
        }
        if (target == typeof(byte) || target == typeof(sbyte) || target == typeof(short)
            || target == typeof(ushort) || target == typeof(uint))
        {
            var max = target == typeof(byte) ? (ulong)byte.MaxValue
                : target == typeof(sbyte) ? (ulong)sbyte.MaxValue
                : target == typeof(short) ? (ulong)short.MaxValue
                : target == typeof(ushort) ? (ulong)ushort.MaxValue
                : (ulong)int.MaxValue;
            return value <= max;
        }
        if (target == typeof(long) || target == typeof(ulong))
            return value <= int.MaxValue;
        return false;
    }

    private bool CanUseInterfaceUpcast(Type valueType, Type targetType)
    {
        return targetType is TypeBuilder targetBuilder
               && FindDefByBuilder(targetBuilder) is { IsInterface: true }
               && valueType is TypeBuilder valueBuilder
               && FindDefByBuilder(valueBuilder) is { } valueDef
               && AnyInterfaceEqualsOrExtends(valueDef.ImplementedInterfaces, targetBuilder);
    }

    private static bool CanUseObjectConversion(Type source, Type target)
        => target == typeof(object) && source != typeof(void);

    // Maps a CLOSED user-generic receiver (Box<int>) back to its OPEN definition's registry entry.
    // Member tokens on the closed type are rebound via TypeBuilder.GetField/GetMethod; member TYPES
    // substitute the closed arguments positionally.
    private bool TryGetClosedReceiverDef(Type receiverType, out ColumnarStructDef def, out Type[] closedArguments)
    {
        def = null!;
        closedArguments = System.Array.Empty<Type>();
        if (!IsClosedUserGenericInstantiation(receiverType))
            return false;
        var definition = receiverType.GetGenericTypeDefinition();
        foreach (var d in _structRegistry.Values)
        {
            if (d.Builder == definition)
            {
                def = d;
                closedArguments = receiverType.GetGenericArguments();
                return true;
            }
        }
        return false;
    }

    private static bool TryGetEnumerableElementType(Type receiverType, out Type elementType)
    {
        elementType = null!;
        if (receiverType.IsSZArray)
        {
            elementType = receiverType.GetElementType()!;
            return IsSupportedElementType(elementType);
        }

        if (!IsSupportedCollectionType(receiverType))
            return false;
        var collectionDef = receiverType.GetGenericTypeDefinition();
        if (collectionDef == typeof(Dictionary<,>))
            return false;
        var args = receiverType.GetGenericArguments();
        if (args.Length != 1)
            return false;
        elementType = args[0];
        return IsAdmissibleCollectionElement(elementType) || IsSupportedElementType(elementType);
    }

    private static MethodInfo? FindEnumerableSourceOnlyMethod(string name)
        => Array.Find(
            typeof(System.Linq.Enumerable).GetMethods(BindingFlags.Public | BindingFlags.Static),
            method =>
            {
                if (method.Name != name
                    || !method.IsGenericMethodDefinition
                    || method.GetGenericArguments().Length != 1)
                    return false;
                var parameters = method.GetParameters();
                return parameters.Length == 1
                       && parameters[0].ParameterType.IsGenericType
                       && parameters[0].ParameterType.GetGenericTypeDefinition() == typeof(IEnumerable<>);
            });

    private static MethodInfo? FindEnumerableLambdaMethod(string name, int genericArgumentCount, Type delegateDefinition)
        => Array.Find(
            typeof(System.Linq.Enumerable).GetMethods(BindingFlags.Public | BindingFlags.Static),
            method =>
            {
                if (method.Name != name
                    || !method.IsGenericMethodDefinition
                    || method.GetGenericArguments().Length != genericArgumentCount)
                    return false;
                var parameters = method.GetParameters();
                return parameters.Length == 2
                       && parameters[0].ParameterType.IsGenericType
                       && parameters[0].ParameterType.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                       && parameters[1].ParameterType.IsGenericType
                       && parameters[1].ParameterType.GetGenericTypeDefinition() == delegateDefinition;
            });

    private static MethodInfo? FindEnumerableIntAggregateMethod(string name)
        => Array.Find(
            typeof(System.Linq.Enumerable).GetMethods(BindingFlags.Public | BindingFlags.Static),
            method =>
            {
                if (method.Name != name || method.ReturnType != typeof(int))
                    return false;
                var parameters = method.GetParameters();
                return parameters.Length == 1 && parameters[0].ParameterType == typeof(IEnumerable<int>);
            });

    private bool TryInferSingleParameterLambdaReturnType(int lambdaNode, Type parameterType, out Type returnType)
    {
        returnType = null!;
        if (_nodes.Kind(lambdaNode) != 39 || _nodes.ChildCount(lambdaNode) != 2)
            return false;
        var parameterNode = Child(lambdaNode, 0);
        if (_nodes.Kind(parameterNode) != 6)
            return false;
        var parameterName = Text(parameterNode);
        if (IsVisibleBindingName(parameterName))
            return false;
        var ordinals = new Dictionary<string, int>(StringComparer.Ordinal)
        {
            [parameterName] = 0,
        };
        var paramTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
        {
            [parameterName] = parameterType,
        };
        var subEmitter = new ColumnarIlEmitter(
            _nodes, _source, ordinals, paramTypes, typeof(void), _il, _siblings,
            _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: _currentStruct,
            enclosingType: _enclosingType,
            programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
            localFuncs: _localFuncs, declaredLocalFuncNodes: _declaredLocalFuncNodes, visibleLocalFuncs: _visibleLocalFuncs,
            siblingReturnTupleNames: _siblingReturnTupleNames,
            enclosingBindingNames: VisibleBindingNamesSnapshot(),
            referenceAssemblyPaths: _referenceAssemblyPaths);
        return subEmitter.TryGetPreflightExpressionType(Child(lambdaNode, 1), out returnType)
               && returnType != typeof(void)
               && IsSupportedType(returnType);
    }

    private bool TryInferZeroParameterLambdaReturnType(int lambdaNode, out Type returnType)
    {
        returnType = null!;
        if (_nodes.Kind(lambdaNode) != 39 || _nodes.ChildCount(lambdaNode) != 1)
            return false;
        var subEmitter = new ColumnarIlEmitter(
            _nodes, _source, new Dictionary<string, int>(StringComparer.Ordinal),
            new Dictionary<string, Type>(StringComparer.Ordinal), typeof(void), _il, _siblings,
            _enumRegistry, _structRegistry, _unionRegistry, _unionCaseRegistry, currentStruct: _currentStruct,
            enclosingType: _enclosingType,
            programType: _programType, lambdaCounter: _lambdaCounter, displayClasses: _displayClasses,
            localFuncs: _localFuncs, declaredLocalFuncNodes: _declaredLocalFuncNodes, visibleLocalFuncs: _visibleLocalFuncs,
            siblingReturnTupleNames: _siblingReturnTupleNames,
            enclosingBindingNames: VisibleBindingNamesSnapshot(),
            referenceAssemblyPaths: _referenceAssemblyPaths);
        return subEmitter.TryGetPreflightExpressionType(Child(lambdaNode, 0), out returnType)
               && returnType != typeof(void)
               && IsSupportedType(returnType);
    }

    private bool TryResolveAspNetReferencedType(string assemblySimpleName, string fullTypeName, out Type type)
        => TryResolveReferencedType(_referenceAssemblyPaths, assemblySimpleName, fullTypeName, out type)
           || TryResolveLoadedExternalType(fullTypeName, out type);

    private bool TryResolveAspNetHttpContextType(out Type type)
        => TryResolveAspNetReferencedType("Microsoft.AspNetCore.Http.Abstractions", "Microsoft.AspNetCore.Http.HttpContext", out type)
           || TryResolveAspNetReferencedType("Microsoft.AspNetCore.Http", "Microsoft.AspNetCore.Http.HttpContext", out type);

    private bool TryEmitAspNetRouteHandler(int handlerNode, out Type delegateType)
    {
        delegateType = null!;
        handlerNode = UnwrapParenthesizedNode(handlerNode);
        if (_nodes.Kind(handlerNode) == 39)
        {
            var parameterCount = _nodes.ChildCount(handlerNode) - 1;
            if (parameterCount == 0)
            {
                var returnType = TryInferZeroParameterLambdaReturnType(handlerNode, out var inferredReturn)
                    ? inferredReturn
                    : typeof(object);
                delegateType = typeof(Func<>).MakeGenericType(returnType);
                return IsSupportedContextualDelegateType(delegateType)
                       && TryEmitLambdaLiteral(handlerNode, delegateType);
            }

            if (parameterCount == 1 && TryResolveAspNetHttpContextType(out var httpContextType))
            {
                var returnType = TryInferSingleParameterLambdaReturnType(handlerNode, httpContextType, out var inferredReturn)
                    ? inferredReturn
                    : typeof(System.Threading.Tasks.Task);
                delegateType = typeof(Func<,>).MakeGenericType(httpContextType, returnType);
                return IsSupportedContextualDelegateType(delegateType)
                       && TryEmitLambdaLiteral(handlerNode, delegateType);
            }
            return false;
        }

        if (_nodes.Kind(handlerNode) == 6
            && _currentStruct != null
            && _currentStruct.IsReference
            && TryResolveAspNetHttpContextType(out var contextType)
            && TryFindMethodOnChain(_currentStruct, Text(handlerNode), 1, out var method)
            && TypesEquivalent(method.ParamTypes[0], contextType)
            && IsSupportedType(method.ReturnType))
        {
            delegateType = typeof(Func<,>).MakeGenericType(contextType, method.ReturnType);
            if (!TryGetSupportedDelegateSignature(delegateType, allowBuilderBoundArguments: true, out _, out _, out var delegateCtor))
                return false;
            _il.Emit(OpCodes.Ldarg_0);
            _il.Emit(OpCodes.Ldftn, method.Builder);
            _il.Emit(OpCodes.Newobj, delegateCtor);
            return true;
        }

        return false;
    }

    private bool TryEmitAspNetMapEndpointCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;
        if (receiverType.FullName != "Microsoft.AspNetCore.Builder.WebApplication"
            || member is not ("MapGet" or "MapPost")
            || argCount != 2)
            return false;
        if (!TryResolveAspNetReferencedType(
                "Microsoft.AspNetCore.Routing",
                "Microsoft.AspNetCore.Builder.EndpointRouteBuilderExtensions",
                out var endpointExtensions))
            return false;

        var mapMethod = Array.Find(
            endpointExtensions.GetMethods(BindingFlags.Public | BindingFlags.Static),
            candidate =>
            {
                if (candidate.Name != member)
                    return false;
                var parameters = candidate.GetParameters();
                return parameters.Length == 3
                       && parameters[1].ParameterType == typeof(string)
                       && parameters[2].ParameterType == typeof(Delegate);
            });
        if (mapMethod == null
            || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(string), allowLambdaLiteral: false)
            || !TryEmitAspNetRouteHandler(Child(callIdx, 2), out _))
            return false;

        _il.Emit(OpCodes.Call, mapMethod);
        type = mapMethod.ReturnType;
        return true;
    }

    private bool TryEmitAspNetStaticFilesCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;
        if (receiverType.FullName != "Microsoft.AspNetCore.Builder.WebApplication")
            return false;

        if ((member == "UseDefaultFiles" || member == "UseStaticFiles") && argCount == 0)
        {
            var extensionTypeName = member == "UseDefaultFiles"
                ? "Microsoft.AspNetCore.Builder.DefaultFilesExtensions"
                : "Microsoft.AspNetCore.Builder.StaticFileExtensions";
            if (!TryResolveAspNetReferencedType("Microsoft.AspNetCore.StaticFiles", extensionTypeName, out var extensionType))
                return false;
            var method = Array.Find(
                extensionType.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != member)
                        return false;
                    var parameters = candidate.GetParameters();
                    return parameters.Length == 1
                           && parameters[0].ParameterType.FullName == "Microsoft.AspNetCore.Builder.IApplicationBuilder";
                });
            if (method == null)
                return false;
            _il.Emit(OpCodes.Call, method);
            type = method.ReturnType;
            return true;
        }

        if (member == "MapFallbackToFile" && argCount == 1)
        {
            if (!TryResolveAspNetReferencedType(
                    "Microsoft.AspNetCore.StaticFiles",
                    "Microsoft.AspNetCore.Builder.StaticFilesEndpointRouteBuilderExtensions",
                    out var extensionType))
                return false;
            var method = Array.Find(
                extensionType.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != member)
                        return false;
                    var parameters = candidate.GetParameters();
                    return parameters.Length == 2
                           && parameters[0].ParameterType.FullName == "Microsoft.AspNetCore.Routing.IEndpointRouteBuilder"
                           && parameters[1].ParameterType == typeof(string);
                });
            if (method == null
                || !EmitDeclaredCallArgument(Child(callIdx, 1), typeof(string), allowLambdaLiteral: false))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = method.ReturnType;
            return true;
        }

        return false;
    }

    private bool TryEmitEnumerableExtensionCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;
        if (!TryGetEnumerableElementType(receiverType, out var sourceType))
            return false;

        if (member == "Where" && argCount == 1)
        {
            var predicateType = typeof(Func<,>).MakeGenericType(sourceType, typeof(bool));
            var where = FindEnumerableLambdaMethod(nameof(System.Linq.Enumerable.Where), 1, typeof(Func<,>));
            if (where == null
                || !IsSupportedContextualDelegateType(predicateType)
                || !EmitDeclaredCallArgument(Child(callIdx, 1), predicateType, allowLambdaLiteral: true))
                return false;
            _il.Emit(OpCodes.Call, where.MakeGenericMethod(sourceType));
            type = typeof(IEnumerable<>).MakeGenericType(sourceType);
            return true;
        }

        if (member == "Select" && argCount == 1)
        {
            if (!TryInferSingleParameterLambdaReturnType(Child(callIdx, 1), sourceType, out var resultType))
                return false;
            var selectorType = typeof(Func<,>).MakeGenericType(sourceType, resultType);
            var select = FindEnumerableLambdaMethod(nameof(System.Linq.Enumerable.Select), 2, typeof(Func<,>));
            if (select == null
                || !IsSupportedContextualDelegateType(selectorType)
                || !EmitDeclaredCallArgument(Child(callIdx, 1), selectorType, allowLambdaLiteral: true))
                return false;
            _il.Emit(OpCodes.Call, select.MakeGenericMethod(sourceType, resultType));
            type = typeof(IEnumerable<>).MakeGenericType(resultType);
            return true;
        }

        if (member == "ToArray" && argCount == 0)
        {
            var toArray = FindEnumerableSourceOnlyMethod(nameof(System.Linq.Enumerable.ToArray));
            if (toArray == null || !IsSupportedElementType(sourceType))
                return false;
            _il.Emit(OpCodes.Call, toArray.MakeGenericMethod(sourceType));
            type = sourceType.MakeArrayType();
            return true;
        }

        if (member == "ToList" && argCount == 0)
        {
            var toList = FindEnumerableSourceOnlyMethod(nameof(System.Linq.Enumerable.ToList));
            if (toList == null)
                return false;
            _il.Emit(OpCodes.Call, toList.MakeGenericMethod(sourceType));
            type = typeof(List<>).MakeGenericType(sourceType);
            return true;
        }

        if ((member == "Min" || member == "Max") && argCount == 0 && sourceType == typeof(int))
        {
            var aggregate = FindEnumerableIntAggregateMethod(member);
            if (aggregate == null)
                return false;
            _il.Emit(OpCodes.Call, aggregate);
            type = typeof(int);
            return true;
        }

        if (member == "Contains" && argCount == 1)
        {
            if (ContainsNonEnumBuilderBoundType(sourceType) || !EmitArg(callIdx, 1, sourceType))
                return false;
            var contains = Array.Find(
                typeof(System.Linq.Enumerable).GetMethods(BindingFlags.Public | BindingFlags.Static),
                method =>
                {
                    if (method.Name != nameof(System.Linq.Enumerable.Contains)
                        || !method.IsGenericMethodDefinition
                        || method.GetGenericArguments().Length != 1)
                        return false;
                    var parameters = method.GetParameters();
                    return parameters.Length == 2
                           && parameters[0].ParameterType.IsGenericType
                           && parameters[0].ParameterType.GetGenericTypeDefinition() == typeof(IEnumerable<>)
                           && parameters[1].ParameterType.IsGenericParameter;
                });
            if (contains == null)
                return false;
            _il.Emit(OpCodes.Call, contains.MakeGenericMethod(sourceType));
            type = typeof(bool);
            return true;
        }

        return false;
    }

    // Instance BCL calls (the receiver value is already on the stack): a small whitelist of string methods.
    // string.IndexOf(char, int) -> int ; string.Substring(int, int) -> string.
    private bool TryEmitInstanceCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;

        if (TryEmitAspNetStaticFilesCall(callIdx, receiverType, member, argCount, out type))
            return true;

        if (TryEmitAspNetMapEndpointCall(callIdx, receiverType, member, argCount, out type))
            return true;

        if (TryEmitEnumerableExtensionCall(callIdx, receiverType, member, argCount, out type))
            return true;

        if (receiverType == typeof(AppDomain) && member == nameof(AppDomain.GetAssemblies) && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(AppDomain).GetMethod(nameof(AppDomain.GetAssemblies), Type.EmptyTypes)!);
            type = typeof(Assembly[]);
            return true;
        }
        if (receiverType == typeof(JsonDocument) && member == nameof(JsonDocument.Dispose) && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(JsonDocument).GetMethod(nameof(JsonDocument.Dispose), Type.EmptyTypes)!);
            type = typeof(void);
            return true;
        }
        if (receiverType == typeof(DeserializerBuilder))
        {
            if (member == nameof(BuilderSkeleton<DeserializerBuilder>.WithNamingConvention) && argCount == 1)
            {
                var method = typeof(DeserializerBuilder).GetMethod(nameof(BuilderSkeleton<DeserializerBuilder>.WithNamingConvention), new[] { typeof(INamingConvention) });
                if (method == null || !EmitArg(callIdx, 1, typeof(INamingConvention)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(DeserializerBuilder);
                return true;
            }
            if (member == nameof(BuilderSkeleton<DeserializerBuilder>.WithTypeConverter) && argCount == 1)
            {
                var method = typeof(DeserializerBuilder).GetMethod(nameof(BuilderSkeleton<DeserializerBuilder>.WithTypeConverter), new[] { typeof(IYamlTypeConverter) });
                if (method == null || !EmitArg(callIdx, 1, typeof(IYamlTypeConverter)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(DeserializerBuilder);
                return true;
            }
            if (member == nameof(DeserializerBuilder.IgnoreUnmatchedProperties) && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, typeof(DeserializerBuilder).GetMethod(nameof(DeserializerBuilder.IgnoreUnmatchedProperties), Type.EmptyTypes)!);
                type = typeof(DeserializerBuilder);
                return true;
            }
            if (member == nameof(DeserializerBuilder.Build) && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, typeof(DeserializerBuilder).GetMethod(nameof(DeserializerBuilder.Build), Type.EmptyTypes)!);
                type = typeof(IDeserializer);
                return true;
            }
        }
        if (receiverType == typeof(IDeserializer) && member == nameof(IDeserializer.Deserialize) && argCount == 2)
        {
            var method = typeof(IDeserializer).GetMethod(nameof(IDeserializer.Deserialize), new[] { typeof(string), typeof(Type) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(Type)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(object);
            return true;
        }
        if (receiverType == typeof(YamlParser) && member == nameof(YamlParser.MoveNext) && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(YamlParser).GetMethod(nameof(YamlParser.MoveNext), Type.EmptyTypes)!);
            type = typeof(bool);
            return true;
        }
        if (receiverType == typeof(YamlEmitter) && member == nameof(YamlEmitter.Emit) && argCount == 1)
        {
            if (!EmitArg(callIdx, 1, typeof(ParsingEvent)))
                return false;
            _il.Emit(OpCodes.Callvirt, typeof(YamlEmitter).GetMethod(nameof(YamlEmitter.Emit), new[] { typeof(ParsingEvent) })!);
            type = typeof(void);
            return true;
        }
        if (receiverType.FullName == "Microsoft.AspNetCore.Builder.WebApplicationBuilder"
            && member == "Build"
            && argCount == 0)
        {
            var method = receiverType.GetMethod("Build", Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = method.ReturnType;
            return true;
        }
        if (receiverType.FullName == "Microsoft.AspNetCore.Builder.WebApplication"
            && member == "Run"
            && argCount == 0)
        {
            var method = receiverType.GetMethod("Run", Type.EmptyTypes)
                ?? Array.Find(
                    receiverType.GetMethods(BindingFlags.Public | BindingFlags.Instance),
                    candidate =>
                    {
                        if (candidate.Name != "Run")
                            return false;
                        var parameters = candidate.GetParameters();
                        return parameters.Length == 1
                               && parameters[0].ParameterType == typeof(string)
                               && parameters[0].IsOptional;
                    });
            if (method == null)
                return false;
            if (method.GetParameters().Length == 1)
                _il.Emit(OpCodes.Ldnull);
            _il.Emit(OpCodes.Callvirt, method);
            type = method.ReturnType;
            return true;
        }
        if ((receiverType.FullName == "Microsoft.AspNetCore.Hosting.IWebHostEnvironment"
                || receiverType.FullName == "Microsoft.Extensions.Hosting.IHostEnvironment"
                || receiverType.FullName == "Microsoft.Extensions.Hosting.IHostingEnvironment")
            && member == "IsDevelopment"
            && argCount == 0)
        {
            if (!TryResolveReferencedType(
                    _referenceAssemblyPaths,
                    "Microsoft.Extensions.Hosting.Abstractions",
                    "Microsoft.Extensions.Hosting.HostEnvironmentEnvExtensions",
                    out var hostingEnvironmentExtensions)
                && !TryResolveReferencedType(
                    _referenceAssemblyPaths,
                    "Microsoft.Extensions.Hosting.Abstractions",
                    "Microsoft.Extensions.Hosting.HostingEnvironmentExtensions",
                    out hostingEnvironmentExtensions)
                && !TryResolveReferencedType(
                    _referenceAssemblyPaths,
                    "Microsoft.AspNetCore.Hosting.Abstractions",
                    "Microsoft.AspNetCore.Hosting.HostingEnvironmentExtensions",
                    out hostingEnvironmentExtensions))
                return false;
            var method = Array.Find(
                hostingEnvironmentExtensions.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != "IsDevelopment")
                        return false;
                    var parameters = candidate.GetParameters();
                    return parameters.Length == 1
                           && parameters[0].ParameterType.FullName is "Microsoft.Extensions.Hosting.IHostEnvironment"
                               or "Microsoft.Extensions.Hosting.IHostingEnvironment";
                });
            if (method == null)
                return false;
            var hostingParameterType = method.GetParameters()[0].ParameterType;
            if (!TypesEquivalent(receiverType, hostingParameterType))
                _il.Emit(OpCodes.Castclass, hostingParameterType);
            _il.Emit(OpCodes.Call, method);
            type = typeof(bool);
            return true;
        }
        if (receiverType.FullName == "Microsoft.AspNetCore.Http.HttpResponse"
            && member == "WriteAsync"
            && argCount == 1)
        {
            if (!TryResolveAspNetReferencedType(
                    "Microsoft.AspNetCore.Http.Abstractions",
                    "Microsoft.AspNetCore.Http.HttpResponseWritingExtensions",
                    out var responseWritingExtensions))
                return false;
            var method = Array.Find(
                responseWritingExtensions.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != "WriteAsync" || candidate.ReturnType != typeof(System.Threading.Tasks.Task))
                        return false;
                    var parameters = candidate.GetParameters();
                    return (parameters.Length == 2 || parameters.Length == 3)
                           && parameters[0].ParameterType.FullName == "Microsoft.AspNetCore.Http.HttpResponse"
                           && parameters[1].ParameterType == typeof(string)
                           && (parameters.Length == 2 || parameters[2].ParameterType == typeof(System.Threading.CancellationToken));
                });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            if (method.GetParameters().Length == 3 && !TryEmitDefaultValue(typeof(System.Threading.CancellationToken)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (receiverType.FullName == "Microsoft.AspNetCore.Http.HttpResponse"
            && member == "WriteAsJsonAsync"
            && (argCount == 2 || argCount == 3))
        {
            if (!TryResolveAspNetReferencedType(
                    "Microsoft.AspNetCore.Http.Extensions",
                    "Microsoft.AspNetCore.Http.HttpResponseJsonExtensions",
                    out var responseJsonExtensions))
                return false;
            var method = Array.Find(
                responseJsonExtensions.GetMethods(BindingFlags.Public | BindingFlags.Static),
                candidate =>
                {
                    if (candidate.Name != "WriteAsJsonAsync"
                        || !candidate.IsGenericMethodDefinition
                        || candidate.ReturnType != typeof(System.Threading.Tasks.Task))
                        return false;
                    var parameters = candidate.GetParameters();
                    return parameters.Length == argCount + 1
                           && parameters[0].ParameterType.FullName == "Microsoft.AspNetCore.Http.HttpResponse"
                           && parameters[1].ParameterType.IsGenericParameter
                           && parameters[2].ParameterType == typeof(JsonSerializerOptions)
                           && (argCount == 2 || parameters[3].ParameterType == typeof(System.Threading.CancellationToken));
                });
            if (method == null
                || !EmitExpression(Child(callIdx, 1), out var jsonValueType)
                || !EmitArg(callIdx, 2, typeof(JsonSerializerOptions)))
                return false;
            if (argCount == 3 && !EmitArg(callIdx, 3, typeof(System.Threading.CancellationToken)))
                return false;
            _il.Emit(OpCodes.Call, method.MakeGenericMethod(jsonValueType));
            type = typeof(System.Threading.Tasks.Task);
            return true;
        }
        if (receiverType == typeof(JsonElement))
        {
            if (member == nameof(JsonElement.EnumerateArray) && argCount == 0)
            {
                var receiverTemp = _il.DeclareLocal(typeof(JsonElement));
                _il.Emit(OpCodes.Stloc, receiverTemp);
                _il.Emit(OpCodes.Ldloca, receiverTemp);
                _il.Emit(OpCodes.Call, typeof(JsonElement).GetMethod(nameof(JsonElement.EnumerateArray), Type.EmptyTypes)!);
                type = typeof(JsonElement.ArrayEnumerator);
                return true;
            }
            if (member == nameof(JsonElement.EnumerateObject) && argCount == 0)
            {
                var receiverTemp = _il.DeclareLocal(typeof(JsonElement));
                _il.Emit(OpCodes.Stloc, receiverTemp);
                _il.Emit(OpCodes.Ldloca, receiverTemp);
                _il.Emit(OpCodes.Call, typeof(JsonElement).GetMethod(nameof(JsonElement.EnumerateObject), Type.EmptyTypes)!);
                type = typeof(JsonElement.ObjectEnumerator);
                return true;
            }
            if (member == nameof(JsonElement.GetInt32) && argCount == 0)
            {
                var receiverTemp = _il.DeclareLocal(typeof(JsonElement));
                _il.Emit(OpCodes.Stloc, receiverTemp);
                _il.Emit(OpCodes.Ldloca, receiverTemp);
                _il.Emit(OpCodes.Call, typeof(JsonElement).GetMethod(nameof(JsonElement.GetInt32), Type.EmptyTypes)!);
                type = typeof(int);
                return true;
            }
            if (member == nameof(JsonElement.GetString) && argCount == 0)
            {
                var receiverTemp = _il.DeclareLocal(typeof(JsonElement));
                _il.Emit(OpCodes.Stloc, receiverTemp);
                _il.Emit(OpCodes.Ldloca, receiverTemp);
                _il.Emit(OpCodes.Call, typeof(JsonElement).GetMethod(nameof(JsonElement.GetString), Type.EmptyTypes)!);
                type = typeof(string);
                return true;
            }
            if (member == nameof(JsonElement.TryGetProperty) && argCount == 2)
            {
                var method = typeof(JsonElement).GetMethod(nameof(JsonElement.TryGetProperty), new[] { typeof(string), typeof(JsonElement).MakeByRefType() });
                if (method == null)
                    return false;
                var receiverTemp = _il.DeclareLocal(typeof(JsonElement));
                _il.Emit(OpCodes.Stloc, receiverTemp);
                _il.Emit(OpCodes.Ldloca, receiverTemp);
                if (!EmitArg(callIdx, 1, typeof(string))
                    || !EmitByRefCallArgument(Child(callIdx, 2), typeof(JsonElement).MakeByRefType()))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(bool);
                return true;
            }
        }

        // BCL COLLECTION instance methods on a closed List<T>/Dictionary<K,V>/HashSet<T> (the runtime constructed
        // type reflects normally; the receiver is already on the stack). The modelled set is the
        // probe-pinned examples surface: List.Add(T)/Insert(int,T)/RemoveAt(int)/Contains(T)/IndexOf(T)/Remove(T)/Reverse()/Clear(),
        // Dictionary.Add(K,V)/TryAdd(K,V)/ContainsKey(K)/TryGetValue(K,out V)/Remove(K)/Clear(),
        // HashSet.Add(T)/Contains(T)/Remove(T)/Clear().
        // Everything else declines.
        if (IsSupportedCollectionType(receiverType))
        {
            var collectionDef = receiverType.GetGenericTypeDefinition();
            var collectionArgs = receiverType.GetGenericArguments();
            if ((collectionDef == typeof(List<>)
                    || collectionDef == typeof(HashSet<>)
                    || collectionDef == typeof(Stack<>)
                    || collectionDef == typeof(IReadOnlyList<>)
                    || collectionDef == typeof(IReadOnlySet<>)
                    || collectionDef == typeof(IEnumerable<>))
                && member == "ToList"
                && argCount == 0)
            {
                var toList = Array.Find(
                    typeof(System.Linq.Enumerable).GetMethods(),
                    method => method.Name == nameof(System.Linq.Enumerable.ToList)
                              && method.IsGenericMethodDefinition
                              && method.GetParameters().Length == 1);
                if (toList == null)
                    return false;
                _il.Emit(OpCodes.Call, toList.MakeGenericMethod(collectionArgs[0]));
                type = typeof(List<>).MakeGenericType(collectionArgs[0]);
                return true;
            }
            if (collectionDef == typeof(IReadOnlySet<>) && member == "Contains" && argCount == 1)
            {
                if (ContainsNonEnumBuilderBoundType(collectionArgs[0]) || !EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(IReadOnlySet<>).GetMethod("Contains")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Add" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Add")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "AddRange" && argCount == 1)
            {
                var enumerableType = typeof(IEnumerable<>).MakeGenericType(collectionArgs[0]);
                if (!EmitArg(callIdx, 1, enumerableType))
                    return false;
                var addRange = Array.Find(
                    typeof(List<>).GetMethods(),
                    method => method.Name == nameof(List<int>.AddRange)
                              && method.GetParameters().Length == 1
                              && method.GetParameters()[0].ParameterType.IsGenericType
                              && method.GetParameters()[0].ParameterType.GetGenericTypeDefinition() == typeof(IEnumerable<>));
                if (addRange == null)
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, addRange));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Insert" && argCount == 2)
            {
                if (!EmitArg(callIdx, 1, typeof(int)) || !EmitArg(callIdx, 2, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Insert")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "RemoveAt" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, typeof(int)))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("RemoveAt")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Contains" && argCount == 1)
            {
                if (ContainsNonEnumBuilderBoundType(collectionArgs[0]) || !EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Contains")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "IndexOf" && argCount == 1)
            {
                if (ContainsNonEnumBuilderBoundType(collectionArgs[0]) || !EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                var openIndexOf = Array.Find(
                    typeof(List<>).GetMethods(),
                    method => method.Name == "IndexOf" && method.GetParameters().Length == 1)!;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, openIndexOf));
                type = typeof(int);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Remove" && argCount == 1)
            {
                if (ContainsNonEnumBuilderBoundType(collectionArgs[0]) || !EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Remove")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Reverse" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Reverse", Type.EmptyTypes)!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("Clear")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(List<>) && member == "ToArray" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(List<>).GetMethod("ToArray", Type.EmptyTypes)!));
                type = collectionArgs[0].MakeArrayType();
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "ContainsKey" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Dictionary<,>).GetMethod("ContainsKey")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "TryGetValue" && argCount == 2)
            {
                var valueType = collectionArgs[1];
                if (!IsSupportedByRefElementType(valueType)
                    || !EmitArg(callIdx, 1, collectionArgs[0])
                    || !EmitByRefCallArgument(Child(callIdx, 2), valueType.MakeByRefType()))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Dictionary<,>).GetMethod("TryGetValue")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "Add" && argCount == 2)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0])
                    || !EmitArg(callIdx, 2, collectionArgs[1]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Dictionary<,>).GetMethod("Add")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "TryAdd" && argCount == 2)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0])
                    || !EmitArg(callIdx, 2, collectionArgs[1]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Dictionary<,>).GetMethod("TryAdd")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "Remove" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                var openRemove = Array.Find(
                    typeof(Dictionary<,>).GetMethods(),
                    method => method.Name == "Remove" && method.GetParameters().Length == 1)!;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, openRemove));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "Remove" && argCount == 2)
            {
                var valueType = collectionArgs[1];
                if (!IsSupportedByRefElementType(valueType)
                    || !EmitArg(callIdx, 1, collectionArgs[0])
                    || !EmitByRefCallArgument(Child(callIdx, 2), valueType.MakeByRefType()))
                    return false;
                var openRemove = Array.Find(
                    typeof(Dictionary<,>).GetMethods(),
                    method => method.Name == "Remove" && method.GetParameters().Length == 2)!;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, openRemove));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(Dictionary<,>) && member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Dictionary<,>).GetMethod("Clear")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(HashSet<>) && member == "Add" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(HashSet<>).GetMethod("Add")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(HashSet<>) && member == "Contains" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(HashSet<>).GetMethod("Contains")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(HashSet<>) && member == "Remove" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(HashSet<>).GetMethod("Remove")!));
                type = typeof(bool);
                return true;
            }
            if (collectionDef == typeof(HashSet<>) && member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(HashSet<>).GetMethod("Clear")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(Stack<>) && member == "Push" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, collectionArgs[0]))
                    return false;
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Stack<>).GetMethod("Push")!));
                type = typeof(void);
                return true;
            }
            if (collectionDef == typeof(Stack<>) && member == "Pop" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Stack<>).GetMethod("Pop")!));
                type = collectionArgs[0];
                return true;
            }
            if (collectionDef == typeof(Stack<>) && member == "Peek" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Stack<>).GetMethod("Peek")!));
                type = collectionArgs[0];
                return true;
            }
            if (collectionDef == typeof(Stack<>) && member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, ResolveClosedGenericMethod(receiverType, typeof(Stack<>).GetMethod("Clear")!));
                type = typeof(void);
                return true;
            }
            return false;
        }

        if (receiverType == typeof(object) && member == "GetType" && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(object).GetMethod(nameof(object.GetType), Type.EmptyTypes)!);
            type = typeof(Type);
            return true;
        }
        if (receiverType == typeof(object) && member == "ToString" && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(object).GetMethod(nameof(object.ToString), Type.EmptyTypes)!);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(TextWriter) && member == nameof(TextWriter.WriteLine) && argCount == 1)
        {
            if (!EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Callvirt, typeof(TextWriter).GetMethod(nameof(TextWriter.WriteLine), new[] { typeof(string) })!);
            type = typeof(void);
            return true;
        }
        if (receiverType == typeof(Type) && member is "GetProperty" or "GetField" && argCount == 1)
        {
            if (!EmitArg(callIdx, 1, typeof(string)))
                return false;
            var method = typeof(Type).GetMethod(member, new[] { typeof(string) });
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = member == "GetProperty" ? typeof(PropertyInfo) : typeof(FieldInfo);
            return true;
        }
        if (receiverType == typeof(PropertyInfo) && member == "GetValue" && argCount == 1)
        {
            if (!EmitArg(callIdx, 1, typeof(object)))
                return false;
            _il.Emit(OpCodes.Callvirt, typeof(PropertyInfo).GetMethod(nameof(PropertyInfo.GetValue), new[] { typeof(object) })!);
            type = typeof(object);
            return true;
        }
        if (receiverType == typeof(FieldInfo) && member == "GetValue" && argCount == 1)
        {
            if (!EmitArg(callIdx, 1, typeof(object)))
                return false;
            _il.Emit(OpCodes.Callvirt, typeof(FieldInfo).GetMethod(nameof(FieldInfo.GetValue), new[] { typeof(object) })!);
            type = typeof(object);
            return true;
        }
        if (receiverType == typeof(Process))
        {
            if (member == nameof(Process.Start) && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, typeof(Process).GetMethod(nameof(Process.Start), Type.EmptyTypes)!);
                type = typeof(bool);
                return true;
            }
            if (member == nameof(Process.WaitForExit) && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, typeof(Process).GetMethod(nameof(Process.WaitForExit), Type.EmptyTypes)!);
                type = typeof(void);
                return true;
            }
            if (member == nameof(Process.WaitForExit) && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, typeof(int)))
                    return false;
                _il.Emit(OpCodes.Callvirt, typeof(Process).GetMethod(nameof(Process.WaitForExit), new[] { typeof(int) })!);
                type = typeof(bool);
                return true;
            }
            if (member == nameof(Process.Kill) && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, typeof(bool)))
                    return false;
                _il.Emit(OpCodes.Callvirt, typeof(Process).GetMethod(nameof(Process.Kill), new[] { typeof(bool) })!);
                type = typeof(void);
                return true;
            }
            if (member == nameof(IDisposable.Dispose) && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, typeof(IDisposable).GetMethod(nameof(IDisposable.Dispose), Type.EmptyTypes)!);
                type = typeof(void);
                return true;
            }
            return false;
        }
        if (receiverType == typeof(StreamReader) && member == nameof(StreamReader.ReadToEndAsync) && argCount == 0)
        {
            _il.Emit(OpCodes.Callvirt, typeof(StreamReader).GetMethod(nameof(StreamReader.ReadToEndAsync), Type.EmptyTypes)!);
            type = typeof(System.Threading.Tasks.Task<string>);
            return true;
        }
        if (receiverType == typeof(Random) && member == nameof(Random.Next) && (argCount == 0 || argCount == 1 || argCount == 2))
        {
            Type[] paramTypes = argCount switch
            {
                0 => Type.EmptyTypes,
                1 => new[] { typeof(int) },
                _ => new[] { typeof(int), typeof(int) },
            };
            var method = typeof(Random).GetMethod(nameof(Random.Next), paramTypes);
            if (method == null)
                return false;
            for (var a = 0; a < argCount; a++)
            {
                if (!EmitArg(callIdx, 1 + a, typeof(int)))
                    return false;
            }
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(int);
            return true;
        }

        // A USER-TYPE INSTANCE method (`receiver.Method(args)`): the receiver VALUE/REF is already on the stack.
        // - VALUE type (struct): the instance method needs the receiver's ADDRESS, so spill to a temp and
        //   `ldloca temp; <args>; call <MethodBuilder>` (non-virtual `call` — value-type instance methods are sealed).
        // - REFERENCE type (record/class): the receiver IS the object ref, so spill and `ldloc temp; <args>; callvirt`
        //   (callvirt gives the standard null check; the method is non-virtual but callvirt calls it directly).
        // Args are emitted AFTER the receiver, in order, each type-checked against the method's declared param type.
        // Resolution walks the BASE chain (nearest declaration first — modelling method hiding) so a derived
        // receiver exposes INHERITED methods (`d.GetX()` where GetX is declared on Base).
        if (receiverType is TypeBuilder)
        {
            foreach (var d in _structRegistry.Values)
            {
                if (d.Builder == receiverType && TrySelectInstanceMethodOnChain(d, member, callIdx, out var structMethod))
                {
                    var receiverTemp = _il.DeclareLocal(receiverType);
                    _il.Emit(OpCodes.Stloc, receiverTemp);
                    _il.Emit(d.IsReference ? OpCodes.Ldloc : OpCodes.Ldloca, receiverTemp);
                    for (var a = 0; a < argCount; a++)
                    {
                        if (!EmitDeclaredCallArgument(Child(callIdx, 1 + a), structMethod.ParamTypes[a], allowLambdaLiteral: true))
                            return false;
                    }
                    _il.Emit(d.IsReference ? OpCodes.Callvirt : OpCodes.Call, structMethod.Builder);
                    type = structMethod.ReturnType;
                    return true;
                }
            }
            // The synthesized RECORD value members (PASS 0e): `.Equals(other)` -> callvirt the generated
            // Equals(object) (a reference arg converts to object implicitly; an unboxed value arg
            // declines); `.GetHashCode()` -> callvirt the generated override. Classes have neither —
            // the pipeline's NL103 (probe-pinned) — so they fall through to the decline below.
            if (FindDefByBuilder((TypeBuilder)receiverType) is { IsRecord: true } recordDef)
            {
                if (member == "Equals" && argCount == 1 && recordDef.RecordEquals != null)
                {
                    // A VALUE record receiver needs its address (`call`); a reference record calls
                    // through the object ref (`callvirt`). Value-typed args box into the object param.
                    if (!recordDef.IsReference)
                    {
                        var equalsReceiverTemp = _il.DeclareLocal(receiverType);
                        _il.Emit(OpCodes.Stloc, equalsReceiverTemp);
                        _il.Emit(OpCodes.Ldloca, equalsReceiverTemp);
                    }
                    if (!EmitExpression(Child(callIdx, 1), out var equalsArgType))
                        return false;
                    if (equalsArgType.IsValueType)
                        _il.Emit(OpCodes.Box, equalsArgType);
                    _il.Emit(recordDef.IsReference ? OpCodes.Callvirt : OpCodes.Call, recordDef.RecordEquals);
                    type = typeof(bool);
                    return true;
                }
                if (member == "GetHashCode" && argCount == 0 && recordDef.RecordGetHashCode != null)
                {
                    if (!recordDef.IsReference)
                    {
                        var hashReceiverTemp = _il.DeclareLocal(receiverType);
                        _il.Emit(OpCodes.Stloc, hashReceiverTemp);
                        _il.Emit(OpCodes.Ldloca, hashReceiverTemp);
                    }
                    _il.Emit(recordDef.IsReference ? OpCodes.Callvirt : OpCodes.Call, recordDef.RecordGetHashCode);
                    type = typeof(int);
                    return true;
                }
            }
            return false; // a TypeBuilder receiver with no matching instance method -> decline.
        }

        // A CLOSED user-generic receiver (`Box<int>`): resolve the method on the OPEN definition (own
        // type only — generic base chains are declined at declaration), rebind via TypeBuilder.GetMethod,
        // and substitute the closed type arguments into the param checks and the result type.
        if (TryGetClosedReceiverDef(receiverType, out var closedDef, out var closedArgs))
        {
            if (!TrySelectInstanceMethodOnChain(closedDef, member, callIdx, out var closedMethod))
                return false;
            var closedReceiverTemp = _il.DeclareLocal(receiverType);
            _il.Emit(OpCodes.Stloc, closedReceiverTemp);
            _il.Emit(closedDef.IsReference ? OpCodes.Ldloc : OpCodes.Ldloca, closedReceiverTemp);
            for (var a = 0; a < argCount; a++)
            {
                var expectedParam = SubstituteClosedTypeArguments(closedMethod.ParamTypes[a], closedArgs);
                if (!EmitDeclaredCallArgument(Child(callIdx, 1 + a), expectedParam, allowLambdaLiteral: true))
                    return false;
            }
            _il.Emit(closedDef.IsReference ? OpCodes.Callvirt : OpCodes.Call, TypeBuilder.GetMethod(receiverType, closedMethod.Builder));
            type = SubstituteClosedTypeArguments(closedMethod.ReturnType, closedArgs);
            return true;
        }

        if (receiverType == typeof(string) && member == "IndexOf")
        {
            // string.IndexOf overloads -> int. 1-arg: IndexOf(char). 2-arg: distinguished by the FIRST arg's
            // type — IndexOf(char, int) vs IndexOf(string, StringComparison) — so emit arg1, read its type, then
            // bind the matching overload + arg2.
            if (argCount == 1)
            {
                var method1 = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(char) });
                if (method1 == null || !EmitArg(callIdx, 1, typeof(char)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method1);
                type = typeof(int);
                return true;
            }
            if (argCount == 2)
            {
                if (!EmitExpression(Child(callIdx, 1), out var arg1Type))
                    return false;
                if (arg1Type == typeof(char))
                {
                    var m = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(char), typeof(int) });
                    if (m == null || !EmitArg(callIdx, 2, typeof(int)))
                        return false;
                    _il.Emit(OpCodes.Callvirt, m);
                    type = typeof(int);
                    return true;
                }
                if (arg1Type == typeof(string))
                {
                    var m = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(string), typeof(StringComparison) });
                    if (m == null || !EmitArg(callIdx, 2, typeof(StringComparison)))
                        return false;
                    _il.Emit(OpCodes.Callvirt, m);
                    type = typeof(int);
                    return true;
                }
                return false;
            }
            if (argCount == 3)
            {
                var method3 = typeof(string).GetMethod(nameof(string.IndexOf), new[] { typeof(string), typeof(int), typeof(StringComparison) });
                if (method3 == null
                    || !EmitArg(callIdx, 1, typeof(string))
                    || !EmitArg(callIdx, 2, typeof(int))
                    || !EmitArg(callIdx, 3, typeof(StringComparison)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method3);
                type = typeof(int);
                return true;
            }
            return false;
        }
        if (receiverType == typeof(string) && member is "Trim" or "TrimEnd" && argCount == 0)
        {
            // string.Trim() -> string (strip leading/trailing whitespace). The receiver string is on the stack;
            // `callvirt` the parameterless overload. DiagnosticClusters.nl: `builder.ToString().Trim()`.
            var method = typeof(string).GetMethod(member, Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(string) && member == "Split" && argCount == 1)
        {
            if (!TryGetPreflightExpressionType(Child(callIdx, 1), out var separatorType))
                return false;
            if (separatorType == typeof(char))
            {
                var method = Array.Find(
                    typeof(string).GetMethods(),
                    m => m.Name == nameof(string.Split)
                         && m.GetParameters().Length == 1
                         && m.GetParameters()[0].ParameterType == typeof(char[]));
                if (method == null)
                    return false;
                _il.Emit(OpCodes.Ldc_I4_1);
                _il.Emit(OpCodes.Newarr, typeof(char));
                _il.Emit(OpCodes.Dup);
                _il.Emit(OpCodes.Ldc_I4_0);
                if (!EmitArg(callIdx, 1, typeof(char)))
                    return false;
                _il.Emit(OpCodes.Stelem_I2);
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(string[]);
                return true;
            }
            if (separatorType == typeof(string))
            {
                var method = typeof(string).GetMethod(nameof(string.Split), new[] { typeof(string), typeof(StringSplitOptions) });
                if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                    return false;
                _il.Emit(OpCodes.Ldc_I4_0);
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(string[]);
                return true;
            }
            return false;
        }
        if (receiverType == typeof(int) && member == "ToString" && argCount == 1)
        {
            // int.ToString(string format) -> string (e.g. .ToString("x") for lowercase hex). Int32.ToString is a
            // VALUE-TYPE instance method, so `this` must be a managed pointer: spill the receiver int (already on
            // the stack) to a temp local and `ldloca` its address, then push the format string and `call`. The
            // N# backend path binds the same Int32.ToString(string) overload, so the formatted text matches exactly.
            var method = typeof(int).GetMethod(nameof(int.ToString), new[] { typeof(string) });
            if (method == null)
                return false;
            var temp = _il.DeclareLocal(typeof(int));
            _il.Emit(OpCodes.Stloc, temp);
            _il.Emit(OpCodes.Ldloca, temp);
            if (!EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(string) && member == "Substring" && argCount == 2)
        {
            var method = typeof(string).GetMethod(nameof(string.Substring), new[] { typeof(int), typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)) || !EmitArg(callIdx, 2, typeof(int)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        // string.Substring(int) — the 1-arg overload (the match-positions ROUTE-ONLY gap, flipped by the
        // strings slice).
        if (receiverType == typeof(string) && member == "Substring" && argCount == 1)
        {
            var method = typeof(string).GetMethod(nameof(string.Substring), new[] { typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(string) && member == nameof(string.CompareTo) && argCount == 1)
        {
            var method = typeof(string).GetMethod(nameof(string.CompareTo), new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(int);
            return true;
        }
        // Parameterless string members: casing transforms, ToString (identity, but the pipeline accepts it), and
        // GetHashCode for emitted value-semantics helpers.
        if (receiverType == typeof(string) && argCount == 0 && member is "ToUpper" or "ToLower" or "ToUpperInvariant" or "ToLowerInvariant" or "ToString" or "GetHashCode")
        {
            var method = typeof(string).GetMethod(member, Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = member == "GetHashCode" ? typeof(int) : typeof(string);
            return true;
        }
        // 1-arg string predicates/transforms over string arguments — exact overloads, both pipelines bind
        // identically: Contains/StartsWith/EndsWith(string) -> bool.
        if (receiverType == typeof(string) && argCount == 1 && member is "Contains" or "StartsWith" or "EndsWith")
        {
            var method = typeof(string).GetMethod(member, new[] { typeof(string) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(bool);
            return true;
        }
        if (receiverType == typeof(string) && argCount == 2 && member is "Contains" or "StartsWith" or "EndsWith")
        {
            var method = typeof(string).GetMethod(member, new[] { typeof(string), typeof(StringComparison) });
            if (method == null || !EmitArg(callIdx, 1, typeof(string)) || !EmitArg(callIdx, 2, typeof(StringComparison)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(bool);
            return true;
        }
        if (receiverType == typeof(string) && argCount == 2 && member == "Replace")
        {
            if (!EmitExpression(Child(callIdx, 1), out var firstArgType))
                return false;
            if (firstArgType == typeof(char))
            {
                var method = typeof(string).GetMethod(nameof(string.Replace), new[] { typeof(char), typeof(char) });
                if (method == null || !EmitArg(callIdx, 2, typeof(char)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(string);
                return true;
            }
            if (firstArgType == typeof(string))
            {
                var method = typeof(string).GetMethod(nameof(string.Replace), new[] { typeof(string), typeof(string) });
                if (method == null || !EmitArg(callIdx, 2, typeof(string)))
                    return false;
                _il.Emit(OpCodes.Callvirt, method);
                type = typeof(string);
                return true;
            }
            return false;
        }
        if (receiverType == typeof(string) && member is "PadLeft" or "PadRight" && argCount == 1)
        {
            var method = typeof(string).GetMethod(member, new[] { typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)))
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(DateTime))
        {
            if (member == nameof(DateTime.AddDays) && argCount == 1)
            {
                var method = typeof(DateTime).GetMethod(nameof(DateTime.AddDays), new[] { typeof(double) });
                if (method == null)
                    return false;
                var temp = _il.DeclareLocal(typeof(DateTime));
                _il.Emit(OpCodes.Stloc, temp);
                _il.Emit(OpCodes.Ldloca, temp);
                if (!EmitDeclaredCallArgument(Child(callIdx, 1), typeof(double), allowLambdaLiteral: false))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(DateTime);
                return true;
            }
            if (member == nameof(DateTime.ToString) && (argCount == 0 || argCount == 1))
            {
                var method = typeof(DateTime).GetMethod(
                    nameof(DateTime.ToString),
                    argCount == 0 ? Type.EmptyTypes : new[] { typeof(string) });
                if (method == null)
                    return false;
                var temp = _il.DeclareLocal(typeof(DateTime));
                _il.Emit(OpCodes.Stloc, temp);
                _il.Emit(OpCodes.Ldloca, temp);
                if (argCount == 1 && !EmitArg(callIdx, 1, typeof(string)))
                    return false;
                _il.Emit(OpCodes.Call, method);
                type = typeof(string);
                return true;
            }
        }
        // Parameterless ToString() on the VALUE scalars (the match-positions ROUTE-ONLY gap): a value-type
        // instance call — spill the receiver, `ldloca`, `call` the type's OWN ToString overload (never the
        // object virtual — the N# backend path binds the same concrete method, so the text matches exactly,
        // culture and all).
        if (member == "ToString" && argCount == 0
            && (receiverType == typeof(int) || receiverType == typeof(long) || receiverType == typeof(ulong)
                || receiverType == typeof(uint) || receiverType == typeof(short) || receiverType == typeof(ushort)
                || receiverType == typeof(byte) || receiverType == typeof(sbyte)
                || receiverType == typeof(double) || receiverType == typeof(float)
                || receiverType == typeof(bool) || receiverType == typeof(char) || receiverType == typeof(decimal)
                || receiverType == typeof(TimeSpan)))
        {
            var method = receiverType.GetMethod(nameof(object.ToString), Type.EmptyTypes);
            if (method == null)
                return false;
            var temp = _il.DeclareLocal(receiverType);
            _il.Emit(OpCodes.Stloc, temp);
            _il.Emit(OpCodes.Ldloca, temp);
            _il.Emit(OpCodes.Call, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(System.Text.StringBuilder))
        {
            // Mutating-builder instance methods (the receiver builder is already on the stack):
            //   .Append(char|string|int) -> StringBuilder (fluent; result usually discarded as a statement)
            //   .Clear()                 -> StringBuilder
            //   .ToString()              -> string
            var sb = typeof(System.Text.StringBuilder);
            if (member == "ToString" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(object.ToString), Type.EmptyTypes)!);
                type = typeof(string);
                return true;
            }
            if (member == "Clear" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(System.Text.StringBuilder.Clear), Type.EmptyTypes)!);
                type = sb;
                return true;
            }
            if (member == "AppendLine" && argCount == 0)
            {
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(System.Text.StringBuilder.AppendLine), Type.EmptyTypes)!);
                type = sb;
                return true;
            }
            if (member == "AppendLine" && argCount == 1)
            {
                if (!EmitArg(callIdx, 1, typeof(string)))
                    return false;
                _il.Emit(OpCodes.Callvirt, sb.GetMethod(nameof(System.Text.StringBuilder.AppendLine), new[] { typeof(string) })!);
                type = sb;
                return true;
            }
            if (member == "Append" && argCount == 1)
            {
                // Resolve the overload by the ARGUMENT'S type (char/string/int): emit the arg, then bind
                // Append(thatType). (The receiver is already on the stack, so the arg goes on top — correct order.)
                if (!EmitExpression(Child(callIdx, 1), out var appendArgType))
                {
                    return false;
                }
                if (appendArgType != typeof(char) && appendArgType != typeof(string) && appendArgType != typeof(int))
                {
                    return false;
                }
                var append = sb.GetMethod(nameof(System.Text.StringBuilder.Append), new[] { appendArgType });
                if (append == null)
                    return false;
                _il.Emit(OpCodes.Callvirt, append);
                type = sb;
                return true;
            }
            return false;
        }
        return Decline(
            "emit.call.instance-member-unmodeled",
            "instance call '" + receiverType.Name + "." + member + "' with " + argCount.ToString() + " argument(s) is not modeled",
            callIdx);
    }

    private bool TrySelectInstanceMethodOnChain(
        ColumnarStructDef def,
        string name,
        int callIdx,
        out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        var argCount = _nodes.ChildCount(callIdx) - 1;
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (TrySelectInstanceMethodOnDef(d, name, callIdx, argCount, out method, out var hadArityMatch))
                return true;
            if (hadArityMatch)
                return false;
            if (d.IsInterface && TrySelectInstanceMethodOnInterfaceBases(d, name, callIdx, argCount, out method, out hadArityMatch))
                return true;
            if (hadArityMatch)
                return false;
        }
        method = default;
        return false;
    }

    private bool TrySelectInstanceMethodOnInterfaceBases(
        ColumnarStructDef def,
        string name,
        int callIdx,
        int argCount,
        out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method,
        out bool hadArityMatch)
    {
        foreach (var baseInterface in def.InterfaceBases)
        {
            if (TrySelectInstanceMethodOnDef(baseInterface, name, callIdx, argCount, out method, out hadArityMatch))
                return true;
            if (hadArityMatch)
                return false;
            if (TrySelectInstanceMethodOnInterfaceBases(baseInterface, name, callIdx, argCount, out method, out hadArityMatch))
                return true;
            if (hadArityMatch)
                return false;
        }
        method = default;
        hadArityMatch = false;
        return false;
    }

    private bool TrySelectInstanceMethodOnDef(
        ColumnarStructDef def,
        string name,
        int callIdx,
        int argCount,
        out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method,
        out bool hadArityMatch)
    {
        method = default;
        hadArityMatch = false;
        if (!def.MethodOverloads.TryGetValue(name, out var overloads))
            return false;

        var arityMatches = 0;
        (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) soleArityMatch = default;
        foreach (var candidate in overloads)
        {
            if (candidate.ParamTypes.Length != argCount)
                continue;
            hadArityMatch = true;
            arityMatches++;
            soleArityMatch = candidate;
        }

        if (arityMatches == 0)
            return false;
        if (arityMatches == 1)
        {
            method = soleArityMatch;
            return true;
        }

        var selected = false;
        foreach (var candidate in overloads)
        {
            if (candidate.ParamTypes.Length != argCount
                || !CanDeclaredCallArgumentsMatch(callIdx, candidate.ParamTypes, allowLambdaLiteral: true))
                continue;
            if (selected)
            {
                method = default;
                return false;
            }
            method = candidate;
            selected = true;
        }

        return selected;
    }

    private bool CanDeclaredCallArgumentsMatch(int callIdx, Type[] parameterTypes, bool allowLambdaLiteral)
    {
        if (_nodes.ChildCount(callIdx) - 1 != parameterTypes.Length)
            return false;
        for (var a = 0; a < parameterTypes.Length; a++)
        {
            if (!CanDeclaredCallArgumentMatch(Child(callIdx, 1 + a), parameterTypes[a], allowLambdaLiteral))
                return false;
        }
        return true;
    }

    private bool CanDeclaredCallArgumentMatch(int argNode, Type expectedParamType, bool allowLambdaLiteral)
    {
        if (expectedParamType.IsByRef)
        {
            return _nodes.Kind(argNode) == 54
                   && _nodes.ChildCount(argNode) == 1
                   && TryGetAddressableTargetType(Child(argNode, 0), out var targetType)
                   && TypesEquivalent(targetType, expectedParamType.GetElementType()!);
        }
        if (_nodes.Kind(argNode) == 54)
            return false;
        if (allowLambdaLiteral && _nodes.Kind(argNode) == 39)
            return IsSupportedContextualDelegateType(expectedParamType);
        if (_nodes.Kind(argNode) == 5)
            return !expectedParamType.IsValueType || IsSupportedNullable(expectedParamType);
        if (!TryGetPreflightExpressionType(argNode, out var argType))
            return false;
        if (IsSupportedNullable(expectedParamType))
        {
            var nullableElement = expectedParamType.GetGenericArguments()[0];
            return TypesEquivalent(argType, expectedParamType)
                   || TypesEquivalent(argType, nullableElement)
                   || CanUseImplicitNumericWidening(argType, nullableElement);
        }
        return TypesEquivalent(argType, expectedParamType)
               || CanUseImplicitNumericWidening(argType, expectedParamType)
               || CanUseInterfaceUpcast(argType, expectedParamType)
               || CanUseExternalInterfaceUpcast(argType, expectedParamType)
               || TryEmitReferenceConversion(argType, expectedParamType)
               || CanUseObjectConversion(argType, expectedParamType);
    }

    // Emit the argument at child position `argPosition` of the call and require its type to match
    // `expected` (TypesEquivalent, not ==: builder-bound instantiations from independent resolutions
    // are referentially distinct — `outer.Add(inner)` on a List<List<Pt>> compares two distinct TBIs).
    // Interface-typed arguments accept implementers through the same upcast/box path as sibling calls.
    private bool EmitArg(int callIdx, int argPosition, Type expected)
        => EmitExpression(Child(callIdx, argPosition), out var argType)
           && (TypesEquivalent(argType, expected)
               || TryEmitInterfaceUpcast(argType, expected)
               || TryEmitExternalInterfaceUpcast(argType, expected)
               || TryEmitReferenceConversion(argType, expected)
               || TryEmitObjectConversion(argType, expected)
               || TryEmitUserDefinedConversion(argType, expected, allowExplicit: false));

    private bool EmitDeclaredCallArgument(int argNode, Type expectedParamType, bool allowLambdaLiteral)
    {
        if (expectedParamType.IsByRef)
            return EmitByRefCallArgument(argNode, expectedParamType);
        if (_nodes.Kind(argNode) == 54)
            return false;
        if (allowLambdaLiteral && _nodes.Kind(argNode) == 39)
            return TryEmitLambdaLiteral(argNode, expectedParamType);
        if (TryEmitNullLiteralAsType(argNode, expectedParamType, out _))
            return true;
        if (IsSupportedNullable(expectedParamType))
            return TryEmitValueAsNullable(argNode, expectedParamType, out _);
        return EmitExpression(argNode, out var argType)
               && (TypesEquivalent(argType, expectedParamType)
                   || TryEmitImplicitWidening(argType, expectedParamType)
                   || TryEmitInterfaceUpcast(argType, expectedParamType)
                   || TryEmitExternalInterfaceUpcast(argType, expectedParamType)
                   || TryEmitReferenceConversion(argType, expectedParamType)
                   || TryEmitObjectConversion(argType, expectedParamType)
                   || TryEmitUserDefinedConversion(argType, expectedParamType, allowExplicit: false));
    }

    private bool EmitByRefCallArgument(int argNode, Type expectedByRefType)
    {
        if (!expectedByRefType.IsByRef || _nodes.Kind(argNode) != 54 || _nodes.ChildCount(argNode) != 1)
            return false;
        var modifier = Text(argNode);
        if (modifier != "ref" && modifier != "out")
            return false;
        return EmitAddressOfByRefTarget(Child(argNode, 0), expectedByRefType.GetElementType()!);
    }

    private bool TryGetAddressableTargetType(int targetNode, out Type targetType)
    {
        targetType = typeof(void);
        targetNode = UnwrapParenthesizedNode(targetNode);

        if (_nodes.Kind(targetNode) == 6)
        {
            var name = Text(targetNode);
            if (_liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
                return false;
            if (_locals.TryGetValue(name, out var local))
            {
                targetType = local.LocalType;
                return true;
            }
            if (_paramTypes.TryGetValue(name, out var paramType))
            {
                targetType = paramType.IsByRef ? paramType.GetElementType()! : paramType;
                return true;
            }
            return false;
        }

        if (_nodes.Kind(targetNode) == 8 && TryResolveMemberWriteChain(targetNode, out var memberChain))
        {
            targetType = memberChain.ReceiverType;
            return true;
        }

        return false;
    }

    private bool EmitAddressOfByRefTarget(int targetNode, Type expectedElementType)
    {
        targetNode = UnwrapParenthesizedNode(targetNode);

        if (_nodes.Kind(targetNode) == 6)
        {
            var name = Text(targetNode);
            if (_liftedLocals.ContainsKey(name) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(name)))
                return false;
            if (_locals.TryGetValue(name, out var local))
            {
                if (!TypesEquivalent(local.LocalType, expectedElementType))
                    return false;
                _il.Emit(OpCodes.Ldloca, local);
                return true;
            }
            if (_paramOrdinals.TryGetValue(name, out var ordinal) && _paramTypes.TryGetValue(name, out var paramType))
            {
                if (paramType.IsByRef)
                {
                    if (!TypesEquivalent(paramType.GetElementType()!, expectedElementType))
                        return false;
                    EmitLoadArgument(ordinal);
                    return true;
                }
                if (!TypesEquivalent(paramType, expectedElementType))
                    return false;
                EmitLoadArgumentAddress(ordinal);
                return true;
            }
            return false;
        }

        if (_nodes.Kind(targetNode) == 8
            && TryResolveMemberWriteChain(targetNode, out var memberChain)
            && TypesEquivalent(memberChain.ReceiverType, expectedElementType))
        {
            EmitMemberWriteLocator(memberChain);
            return true;
        }

        return false;
    }

    private void EmitLoadArgument(int index)
    {
        switch (index)
        {
            case 0: _il.Emit(OpCodes.Ldarg_0); break;
            case 1: _il.Emit(OpCodes.Ldarg_1); break;
            case 2: _il.Emit(OpCodes.Ldarg_2); break;
            case 3: _il.Emit(OpCodes.Ldarg_3); break;
            default:
                if (index <= 255)
                    _il.Emit(OpCodes.Ldarg_S, (byte)index);
                else
                    _il.Emit(OpCodes.Ldarg, index);
                break;
        }
    }

    // Store the value on the stack into argument slot `index` (`starg`/`starg.s`). N# parameters are ordinary
    // argument slots, so a `param = expr` assignment mutates the slot directly (method-local value semantics).
    private void EmitStoreArgument(int index)
    {
        if (index <= 255)
            _il.Emit(OpCodes.Starg_S, (byte)index);
        else
            _il.Emit(OpCodes.Starg, index);
    }

    private void EmitLoadArgumentAddress(int index)
    {
        // _paramOrdinals already carry the instance-method `this` shift — never re-shift here.
        if (index <= 255)
            _il.Emit(OpCodes.Ldarga_S, (byte)index);
        else
            _il.Emit(OpCodes.Ldarga, index);
    }

    private void EmitLoadByRefElement(Type elementType)
    {
        if (IsReferenceWriteLink(elementType))
            _il.Emit(OpCodes.Ldind_Ref);
        else
            _il.Emit(OpCodes.Ldobj, elementType);
    }

    private void EmitStoreByRefElement(Type elementType)
    {
        if (IsReferenceWriteLink(elementType))
            _il.Emit(OpCodes.Stind_Ref);
        else
            _il.Emit(OpCodes.Stobj, elementType);
    }

    // The resolved WRITE-RECEIVER chain of a member assignment: a root local/param plus zero or more
    // instance-FIELD hops (the `p.q` of `p.q.X = v`). Resolution is EMISSION-FREE so a failed chain
    // declines cleanly (the emit-ownership rule); EmitMemberWriteLocator then emits the owner value
    // an stfld/ldfld/ldflda/callvirt-setter consumes — an ADDRESS for value-typed links
    // (ldloca/ldarga/ldflda), an OBJECT REF for reference-typed links (ldloc/ldarg/ldfld). stfld and
    // ldflda accept either owner form, so the chain composes uniformly — mirroring the legacy emitter's
    // fixed EmitAddressableExpression (defect #22).
    private bool TryResolveMemberWriteChain(int node, out ColumnarMemberWriteChain chain)
    {
        chain = default;
        // Collect kind-8 hops outermost-first down to the root, which must be a BARE name.
        // Parentheses are transparent syntax for addressability; indexer and call-result receivers
        // are pipeline-REJECTED writes (NL322 — parity by rejection via the fallback) and never emit here.
        var hopNodes = new List<int>();
        var cursor = UnwrapParenthesizedNode(node);
        while (_nodes.Kind(cursor) == 8)
        {
            hopNodes.Add(cursor);
            cursor = UnwrapParenthesizedNode(Child(cursor, 0));
        }
        if (_nodes.Kind(cursor) != 6)
            return false;
        var rootName = Text(cursor);
        if (_liftedLocals.ContainsKey(rootName) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(rootName)))
            return false; // lifted/captured roots stay declined — the capture-mutation family is conservative.
        LocalBuilder? rootLocal = null;
        var rootParamOrdinal = -1;
        Type rootType;
        if (_locals.TryGetValue(rootName, out var local))
        {
            rootLocal = local;
            rootType = local.LocalType;
        }
        else if (_paramOrdinals.TryGetValue(rootName, out var ordinal))
        {
            rootParamOrdinal = ordinal;
            rootType = _paramTypes[rootName];
        }
        else
        {
            return false; // a sibling/type/unknown name is not a variable root.
        }
        var hops = new List<FieldBuilder>(hopNodes.Count);
        var current = rootType.IsByRef ? rootType.GetElementType()! : rootType;
        for (var h = hopNodes.Count - 1; h >= 0; h--) // innermost hop (adjacent to the root) first.
        {
            if (current is not TypeBuilder hopOwner
                || FindDefByBuilder(hopOwner) is not { } hopDef
                || !TryFindFieldOnChain(hopDef, Text(hopNodes[h]), out var hopField))
                return false; // non-registered owners (closed generics, BCL) and non-field hops decline.
            hops.Add(hopField);
            current = hopField.FieldType;
        }
        chain = new ColumnarMemberWriteChain(rootLocal, rootParamOrdinal, rootType, hops, current);
        return true;
    }

    private int UnwrapParenthesizedNode(int node)
    {
        while (_nodes.Kind(node) == 7 && _nodes.ChildCount(node) == 1)
            node = Child(node, 0);
        return node;
    }

    private void EmitMemberWriteLocator(in ColumnarMemberWriteChain chain)
    {
        if (chain.RootLocal != null)
            _il.Emit(chain.RootType.IsByRef || IsReferenceWriteLink(chain.RootType) ? OpCodes.Ldloc : OpCodes.Ldloca, chain.RootLocal);
        else if (chain.RootType.IsByRef)
            EmitLoadArgument(chain.RootParamOrdinal);
        else if (IsReferenceWriteLink(chain.RootType))
            EmitLoadArgument(chain.RootParamOrdinal);
        else
            EmitLoadArgumentAddress(chain.RootParamOrdinal);
        foreach (var hop in chain.Hops)
            _il.Emit(IsReferenceWriteLink(hop.FieldType) ? OpCodes.Ldfld : OpCodes.Ldflda, hop);
    }

    // Whether a chain link is traversed as an object REFERENCE (ldloc/ldarg/ldfld) or by ADDRESS
    // (ldloca/ldarga/ldflda): registered user types answer by their IsReference flag; anything else
    // by CLR value-typeness (IsValueType is TBI-safe — spike-pinned).
    private bool IsReferenceWriteLink(Type t)
        => t is TypeBuilder tb && FindDefByBuilder(tb) is { } def ? def.IsReference : !t.IsValueType;

    private bool TryEmitAssignableValue(int valueNode, Type targetType, out Type valueType)
    {
        if (IsAdoptableUnionConstruction(valueNode, targetType))
        {
            if (!EmitAdoptedUnionConstruction(valueNode, targetType, out valueType))
                return false;
        }
        else if (TryEmitIntLiteralAsType(valueNode, targetType, out valueType))
        {
            // constant conversion onto the storage type.
        }
        else if (TryEmitArrayLiteralAsType(valueNode, targetType, out valueType))
        {
            // target-typed array literal.
        }
        else if (TryEmitNullLiteralAsType(valueNode, targetType, out valueType))
        {
            // `null` adopted to a reference or nullable storage type.
        }
        else if (IsSupportedNullable(targetType))
        {
            if (!TryEmitValueAsNullable(valueNode, targetType, out valueType))
                return false;
        }
        else if (!EmitExpression(valueNode, out valueType))
        {
            return false;
        }

        var assignable = TypesEquivalent(valueType, targetType)
            || TryEmitImplicitWidening(valueType, targetType)
            || TryEmitInterfaceUpcast(valueType, targetType)
            || TryEmitReferenceConversion(valueType, targetType)
            || TryEmitObjectConversion(valueType, targetType)
            || TryEmitUserDefinedConversion(valueType, targetType, allowExplicit: false);
        return assignable;
    }

    private const int ParameterDefaultMemberAccessKind = 1000;

    private static bool DefineMethodParameterMetadata(
        MethodBuilder method,
        Type[] parameterTypes,
        string[] names,
        int[] modifierKinds,
        int[] defaultKinds,
        string?[] defaultTexts,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry)
    {
        for (var i = 0; i < names.Length; i++)
        {
            var attributes = ParameterAttributes.None;
            if (i < modifierKinds.Length && modifierKinds[i] == 2)
                attributes |= ParameterAttributes.Out;
            var hasDefault = HasParameterDefault(defaultKinds, defaultTexts, i);
            if (hasDefault)
                attributes |= ParameterAttributes.Optional | ParameterAttributes.HasDefault;
            var parameter = method.DefineParameter(i + 1, attributes, names[i]);
            var parameterType = i < parameterTypes.Length ? parameterTypes[i] : typeof(object);
            if (hasDefault && !TrySetParameterDefault(parameter, parameterType, defaultKinds[i], defaultTexts[i], enumRegistry))
                return false;
        }
        return true;
    }

    private static bool DefineConstructorParameterMetadata(
        ConstructorBuilder constructor,
        Type[] parameterTypes,
        string[] names,
        int[] modifierKinds,
        int[] defaultKinds,
        string?[] defaultTexts,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry)
    {
        for (var i = 0; i < names.Length; i++)
        {
            var attributes = ParameterAttributes.None;
            if (i < modifierKinds.Length && modifierKinds[i] == 2)
                attributes |= ParameterAttributes.Out;
            var hasDefault = HasParameterDefault(defaultKinds, defaultTexts, i);
            if (hasDefault)
                attributes |= ParameterAttributes.Optional | ParameterAttributes.HasDefault;
            var parameter = constructor.DefineParameter(i + 1, attributes, names[i]);
            var parameterType = i < parameterTypes.Length ? parameterTypes[i] : typeof(object);
            if (hasDefault && !TrySetParameterDefault(parameter, parameterType, defaultKinds[i], defaultTexts[i], enumRegistry))
                return false;
        }
        return true;
    }

    private static bool HasParameterDefault(int[] defaultKinds, string?[] defaultTexts, int index)
        => index >= 0
           && index < defaultKinds.Length
           && index < defaultTexts.Length
           && defaultKinds[index] >= 0;

    private static bool TrySetParameterDefault(
        ParameterBuilder parameter,
        Type parameterType,
        int defaultKind,
        string? defaultText,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry)
    {
        switch (defaultKind)
        {
            case 46:
                parameter.SetConstant(null);
                return true;
            case 44:
                parameter.SetConstant(true);
                return true;
            case 45:
                parameter.SetConstant(false);
                return true;
            case 1 when int.TryParse(defaultText, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var intDefault):
                parameter.SetConstant(intDefault);
                return true;
            case 4:
                parameter.SetConstant(defaultText != null ? NSharpLang.Compiler.StringLiteralDecoder.Decode(defaultText) : null);
                return true;
            case ParameterDefaultMemberAccessKind when TryResolveStringEnumParameterDefault(parameterType, defaultText, enumRegistry, out var stringEnumDefault):
                parameter.SetConstant(stringEnumDefault);
                return true;
            case ParameterDefaultMemberAccessKind when TryResolveEnumParameterDefault(parameterType, defaultText, enumRegistry, out var enumDefault):
                parameter.SetConstant(enumDefault);
                return true;
            default:
                return false;
        }
    }

    private static bool TryResolveStringEnumParameterDefault(
        Type parameterType,
        string? defaultText,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry,
        out string value)
    {
        value = string.Empty;
        if (string.IsNullOrWhiteSpace(defaultText))
            return false;

        var lastDot = defaultText.LastIndexOf('.');
        if (lastDot <= 0 || lastDot + 1 >= defaultText.Length)
            return false;

        var enumTypeName = defaultText[..lastDot];
        var memberName = defaultText[(lastDot + 1)..];
        if (enumRegistry.TryGetValue(enumTypeName, out var enumDef)
            && enumDef.StringConstants != null
            && TypesEquivalent(enumDef.EnumType, parameterType)
            && enumDef.StringConstants.TryGetValue(memberName, out var resolvedValue))
        {
            value = resolvedValue;
            return true;
        }

        return false;
    }

    private static bool TryResolveEnumParameterDefault(
        Type parameterType,
        string? defaultText,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry,
        out int value)
    {
        value = 0;
        if (string.IsNullOrWhiteSpace(defaultText))
            return false;

        var lastDot = defaultText.LastIndexOf('.');
        if (lastDot <= 0 || lastDot + 1 >= defaultText.Length)
            return false;

        var enumTypeName = defaultText[..lastDot];
        var memberName = defaultText[(lastDot + 1)..];
        if (enumRegistry.TryGetValue(enumTypeName, out var enumDef)
            && TypesEquivalent(enumDef.EnumType, parameterType)
            && enumDef.Constants.TryGetValue(memberName, out value))
        {
            return true;
        }

        if (parameterType is not TypeBuilder
            && parameterType is not EnumBuilder
            && parameterType.IsEnum
            && string.Equals(parameterType.Name, enumTypeName, StringComparison.Ordinal)
            && Enum.IsDefined(parameterType, memberName))
        {
            value = Convert.ToInt32(Enum.Parse(parameterType, memberName), System.Globalization.CultureInfo.InvariantCulture);
            return true;
        }

        if (parameterType is not TypeBuilder
            && parameterType is not EnumBuilder
            && parameterType.IsEnum
            && string.Equals(parameterType.FullName, enumTypeName, StringComparison.Ordinal)
            && Enum.IsDefined(parameterType, memberName))
        {
            value = Convert.ToInt32(Enum.Parse(parameterType, memberName), System.Globalization.CultureInfo.InvariantCulture);
            return true;
        }

        return false;
    }

    private static bool ParamTypesMatch(Type[] a, Type[] b)
    {
        if (a.Length != b.Length)
            return false;
        for (var i = 0; i < a.Length; i++)
        {
            if (a[i] != b[i])
                return false;
        }
        return true;
    }

    private static bool ExternalInterfaceMethodMatches(MethodInfo method, string name, Type returnType, Type[] paramTypes)
    {
        if (method.Name != name || !TypesEquivalent(method.ReturnType, returnType))
            return false;
        var parameters = method.GetParameters();
        if (parameters.Length != paramTypes.Length)
            return false;
        for (var i = 0; i < parameters.Length; i++)
        {
            if (!TypesEquivalent(parameters[i].ParameterType, paramTypes[i]))
                return false;
        }
        return true;
    }

    private static bool TryFindInterfaceMethod(
        ColumnarStructDef interfaceDef, string name, Type returnType, Type[] paramTypes,
        out MethodBuilder method)
    {
        if (interfaceDef.Methods.TryGetValue(name, out var own)
            && own.ReturnType == returnType
            && ParamTypesMatch(own.ParamTypes, paramTypes))
        {
            method = own.Builder;
            return true;
        }
        foreach (var baseInterface in interfaceDef.InterfaceBases)
        {
            if (TryFindInterfaceMethod(baseInterface, name, returnType, paramTypes, out method))
                return true;
        }
        method = null!;
        return false;
    }

    private static bool ColumnarStructInputSatisfiesDuckInterface(
        ColumnarStructInput source,
        ColumnarStructDef sourceDef,
        ColumnarStructDef interfaceDef,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry)
    {
        foreach (var requiredInterface in EnumerateInterfaceAndBases(interfaceDef))
        {
            foreach (var (memberName, member) in requiredInterface.Methods)
            {
                if (requiredInterface.DefaultInterfaceMethodNames.Contains(memberName))
                    continue;
                if (!ColumnarStructInputHasDuckMethod(
                        source,
                        sourceDef,
                        memberName,
                        member.ReturnType,
                        member.ParamTypes,
                        enumRegistry,
                        structRegistry,
                        unionRegistry))
                    return false;
            }
        }
        return true;
    }

    private static bool ColumnarStructInputHasDuckMethod(
        ColumnarStructInput source,
        ColumnarStructDef sourceDef,
        string name,
        Type returnType,
        Type[] paramTypes,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry)
    {
        foreach (var method in source.Methods)
        {
            if (method.IsStatic
                || method.Name != name
                || method.ParamCanonicals.Length != paramTypes.Length
                || method.TypeParamNames.Length > 0)
                continue;

            Type candidateReturn;
            if (method.IsAsync)
            {
                if (!TryComputeAsyncReturnShape(method.Name, method.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out _, out candidateReturn))
                    return false;
            }
            else if (method.ReturnCanonical == "void")
            {
                candidateReturn = typeof(void);
            }
            else if (!TryResolveMemberType(method.ReturnCanonical, sourceDef, enumRegistry, structRegistry, unionRegistry, out candidateReturn)
                     || !IsSupportedType(candidateReturn))
            {
                return false;
            }

            if (!TypesEquivalent(candidateReturn, returnType))
                continue;

            var parametersMatch = true;
            for (var i = 0; i < method.ParamCanonicals.Length; i++)
            {
                if (!TryResolveMemberType(method.ParamCanonicals[i], sourceDef, enumRegistry, structRegistry, unionRegistry, out var candidateParam)
                    || !IsSupportedParameterType(candidateParam)
                    || !TypesEquivalent(candidateParam, paramTypes[i]))
                {
                    parametersMatch = false;
                    break;
                }
            }
            if (parametersMatch)
                return true;
        }
        return false;
    }

    private static IEnumerable<ColumnarStructDef> EnumerateInterfaceAndBases(ColumnarStructDef interfaceDef)
    {
        yield return interfaceDef;
        foreach (var baseInterface in interfaceDef.InterfaceBases)
        {
            foreach (var inherited in EnumerateInterfaceAndBases(baseInterface))
                yield return inherited;
        }
    }

    private static bool InterfaceEqualsOrExtends(ColumnarStructDef interfaceDef, TypeBuilder targetBuilder)
    {
        foreach (var candidate in EnumerateInterfaceAndBases(interfaceDef))
        {
            if (ReferenceEquals(candidate.Builder, targetBuilder))
                return true;
        }
        return false;
    }

    private static bool AnyInterfaceEqualsOrExtends(IEnumerable<ColumnarStructDef> interfaceDefs, TypeBuilder targetBuilder)
    {
        foreach (var interfaceDef in interfaceDefs)
        {
            if (InterfaceEqualsOrExtends(interfaceDef, targetBuilder))
                return true;
        }
        return false;
    }

    private static int InterfaceDepthOrMinusOne(
        ColumnarStructDef interfaceDef,
        Dictionary<ColumnarStructDef, int> memo,
        HashSet<ColumnarStructDef> visiting)
    {
        if (memo.TryGetValue(interfaceDef, out var cached))
            return cached;
        if (!visiting.Add(interfaceDef))
            return -1;
        var depth = 0;
        foreach (var baseInterface in interfaceDef.InterfaceBases)
        {
            var baseDepth = InterfaceDepthOrMinusOne(baseInterface, memo, visiting);
            if (baseDepth < 0)
            {
                visiting.Remove(interfaceDef);
                return -1;
            }
            depth = Math.Max(depth, baseDepth + 1);
        }
        visiting.Remove(interfaceDef);
        memo[interfaceDef] = depth;
        return depth;
    }

    // INTERFACE upcast at value-flow boundaries (the legacy emitter's EmitValueCoercion interface arm,
    // Operators.cs ~694): a value whose def IMPLEMENTS the target interface converts — VALUE-type
    // implementers BOX, reference implementers pass as-is (the object ref IS the interface value).
    // Wired beside TryEmitImplicitWidening at returns/typed-locals/reassignments/sibling args/
    // member writes; the value is already on the stack.
    private bool TryEmitInterfaceUpcast(Type valueType, Type targetType)
    {
        if (!CanUseInterfaceUpcast(valueType, targetType)
            || valueType is not TypeBuilder valueBuilder
            || FindDefByBuilder(valueBuilder) is not { } valueDef)
            return false;
        if (!valueDef.IsReference)
            _il.Emit(OpCodes.Box, valueBuilder);
        return true;
    }

    private bool CanUseExternalInterfaceUpcast(Type valueType, Type targetType)
    {
        if (!targetType.IsInterface
            || valueType is not TypeBuilder valueBuilder
            || FindDefByBuilder(valueBuilder) is not { } valueDef)
            return false;
        foreach (var externalInterface in valueDef.ExternalInterfaces)
        {
            if (externalInterface == targetType || targetType.IsAssignableFrom(externalInterface))
                return true;
        }
        return false;
    }

    private bool TryEmitExternalInterfaceUpcast(Type valueType, Type targetType)
    {
        if (!CanUseExternalInterfaceUpcast(valueType, targetType)
            || valueType is not TypeBuilder valueBuilder
            || FindDefByBuilder(valueBuilder) is not { } valueDef)
            return false;
        foreach (var externalInterface in valueDef.ExternalInterfaces)
        {
            if (externalInterface == targetType || targetType.IsAssignableFrom(externalInterface))
            {
                if (!valueDef.IsReference)
                    _il.Emit(OpCodes.Box, valueBuilder);
                return true;
            }
        }
        return false;
    }

    // INTERPOLATED STRINGS (`$"a{n}b"` / `$"""a{n}b"""`): the kind-3 token carries the whole
    // literal (`$` + holes inside the span). Split via the shared ColumnarInterpolationSplitter
    // (identifier-chain holes only — anything richer declines) and mirror the
    // legacy emitter's EmitInterpolatedString exactly: empty/NO-hole literals constant-fold to the
    // concatenated DECODED text (`ldstr`); otherwise the DefaultInterpolatedStringHandler lowering —
    // ctor(literalLength = sum of DECODED text lengths, formattedCount), AppendLiteral per text
    // segment, AppendFormatted per hole (string holes use the (string) overload, format clauses the
    // generic (T, string), the rest the generic (T)), then ToStringAndClear. Hole chains resolve
    // EMISSION-FREE first (the emit-ownership rule): roots are locals/params (lifted/boxed roots
    // decline), hops are instance FIELDS on registered defs, and an optional final zero-argument user
    // instance call is modelled for holes such as `{value.ToString()}`; builder-typed hole VALUES decline
    // (the legacy emitter BOXES those through AppendFormatted(object, int, string) — a later rung).
    private bool TryEmitInterpolatedString(string literal, out Type type)
    {
        type = null!;
        var parts = new List<ColumnarInterpolationPart>();
        if (!ColumnarInterpolationSplitter.TrySplit(literal, parts))
            return false;
        var formattedCount = 0;
        foreach (var part in parts)
        {
            if (part.IsHole)
                formattedCount++;
        }
        if (formattedCount == 0)
        {
            var folded = new System.Text.StringBuilder();
            foreach (var part in parts)
                folded.Append(NSharpLang.Compiler.StringLiteralDecoder.DecodeInterpolatedText(literal, part.Text));
            _il.Emit(OpCodes.Ldstr, folded.ToString());
            type = typeof(string);
            return true;
        }
        // Resolve every hole BEFORE any emission.
        var holePlans = new List<ColumnarInterpolationHolePlan>(formattedCount);
        var literalLength = 0;
        foreach (var part in parts)
        {
            if (!part.IsHole)
            {
                literalLength += NSharpLang.Compiler.StringLiteralDecoder.DecodeInterpolatedText(literal, part.Text).Length;
                continue;
            }
            if (!TryResolveInterpolationHolePlan(part.Text, part.Format, out var plan))
                return DeclineStatic(
                    "emit.interpolation.hole",
                    "interpolated string hole '" + part.Text + "' is not modeled");
            holePlans.Add(plan);
        }
        var handlerType = typeof(System.Runtime.CompilerServices.DefaultInterpolatedStringHandler);
        var handlerLocal = _il.DeclareLocal(handlerType);
        _il.Emit(OpCodes.Ldloca, handlerLocal);
        _il.Emit(OpCodes.Ldc_I4, literalLength);
        _il.Emit(OpCodes.Ldc_I4, formattedCount);
        _il.Emit(OpCodes.Call, handlerType.GetConstructor(new[] { typeof(int), typeof(int) })!);
        var holeIndex = 0;
        foreach (var part in parts)
        {
            _il.Emit(OpCodes.Ldloca, handlerLocal);
            if (!part.IsHole)
            {
                _il.Emit(OpCodes.Ldstr, NSharpLang.Compiler.StringLiteralDecoder.DecodeInterpolatedText(literal, part.Text));
                _il.Emit(OpCodes.Call, handlerType.GetMethod("AppendLiteral")!);
                continue;
            }
            var plan = holePlans[holeIndex++];
            EmitInterpolationHoleValue(plan);
            if (plan.ValueType == typeof(string) && plan.Format == null)
            {
                _il.Emit(OpCodes.Call, handlerType.GetMethod("AppendFormatted", new[] { typeof(string) })!);
            }
            else if (plan.Format != null)
            {
                _il.Emit(OpCodes.Ldstr, plan.Format);
                _il.Emit(OpCodes.Call, FindAppendFormattedGeneric(handlerType, withFormat: true).MakeGenericMethod(plan.ValueType));
            }
            else
            {
                _il.Emit(OpCodes.Call, FindAppendFormattedGeneric(handlerType, withFormat: false).MakeGenericMethod(plan.ValueType));
            }
        }
        _il.Emit(OpCodes.Ldloca, handlerLocal);
        _il.Emit(OpCodes.Call, handlerType.GetMethod("ToStringAndClear")!);
        type = typeof(string);
        return true;
    }

    private bool TryResolveInterpolationHolePlan(string text, string? format, out ColumnarInterpolationHolePlan plan)
    {
        plan = null!;
        text = text.Trim();
        if (TrySplitInterpolationCast(text, out var castTargetName, out var castOperandText)
            && (TryResolveBuiltin(castTargetName, out var castTargetType)
                || TryResolveType(castTargetName, _enumRegistry, _structRegistry, _unionRegistry, out castTargetType))
            && TryResolveInterpolationChainPlan(castOperandText, allowBuilderValue: true, out var castOperandPlan)
            && castOperandPlan.ValueType != null
            && CanEmitInterpolationCast(castOperandPlan.ValueType, castTargetType))
        {
            castOperandPlan.CastSourceType = castOperandPlan.ValueType;
            castOperandPlan.CastTargetType = castTargetType;
            castOperandPlan.ValueType = castTargetType;
            castOperandPlan.Format = format;
            plan = castOperandPlan;
            return true;
        }

        if (TrySplitInterpolationEquality(text, out var equalityLeftText, out var equalityOperator, out var equalityRightText))
        {
            if (!TryResolveInterpolationChainPlan(equalityLeftText, allowBuilderValue: true, out var equalityLeft)
                || !TryResolveInterpolationChainPlan(equalityRightText, allowBuilderValue: true, out var equalityRight)
                || equalityLeft.ValueType == null
                || equalityRight.ValueType == null
                || !TypesEquivalent(equalityLeft.ValueType, equalityRight.ValueType)
                || !IsSupportedInterpolationEqualityType(equalityLeft.ValueType))
                return false;
            plan = new ColumnarInterpolationHolePlan
            {
                BinaryOperator = equalityOperator,
                BinaryLeft = equalityLeft,
                BinaryRight = equalityRight,
                ValueType = typeof(bool),
                Format = format,
            };
            return true;
        }

        if (TryEvaluateInterpolationIntegerAdditiveExpression(text, out var constantInt))
        {
            plan = new ColumnarInterpolationHolePlan
            {
                ValueType = typeof(int),
                Format = format,
                ConstantInt = constantInt,
            };
            return true;
        }

        var coalesce = text.IndexOf("??", StringComparison.Ordinal);
        if (coalesce >= 0)
        {
            if (text.IndexOf("??", coalesce + 2, StringComparison.Ordinal) >= 0)
                return false;
            var leftText = text.Substring(0, coalesce).Trim();
            var rightText = text.Substring(coalesce + 2).Trim();
            if (leftText.Length == 0 || rightText.Length == 0)
                return false;
            if (!TryResolveInterpolationChainPlan(leftText, out var left)
                || !TryResolveInterpolationChainPlan(rightText, out var right)
                || left.ValueType.IsValueType
                || !TypesEquivalent(left.ValueType, right.ValueType))
                return false;

            left.CoalesceRight = right;
            left.Format = format;
            plan = left;
            return true;
        }

        if (!TryResolveInterpolationChainPlan(text, out plan))
            return false;
        plan.Format = format;
        return true;
    }

    private bool TryResolveInterpolationChainPlan(string chain, out ColumnarInterpolationHolePlan plan)
        => TryResolveInterpolationChainPlan(chain, allowBuilderValue: false, out plan);

    private bool TryResolveInterpolationChainPlan(string chain, bool allowBuilderValue, out ColumnarInterpolationHolePlan plan)
    {
        plan = null!;
        if (!TryResolveInterpolationHole(
                chain,
                allowBuilderValue,
                out var rootLocal,
                out var rootOrdinal,
                out var rootThis,
                out var rootGetter,
                out var rootType,
                out var rootIndexLocal,
                out var rootIndexOrdinal,
                out var rootIndexConstant,
                out var rootIndexElementType,
                out var hops,
                out var callBuilder,
                out var callArgLocal,
                out var callArgOrdinal,
                out var callArgType,
                out var valueType))
            return false;
        plan = new ColumnarInterpolationHolePlan
        {
            RootLocal = rootLocal,
            RootOrdinal = rootOrdinal,
            RootThis = rootThis,
            RootGetter = rootGetter,
            RootType = rootType,
            RootIndexLocal = rootIndexLocal,
            RootIndexOrdinal = rootIndexOrdinal,
            RootIndexConstant = rootIndexConstant,
            RootIndexElementType = rootIndexElementType,
            Hops = hops,
            CallBuilder = callBuilder,
            CallArgLocal = callArgLocal,
            CallArgOrdinal = callArgOrdinal,
            CallArgType = callArgType,
            ValueType = valueType,
        };
        return true;
    }

    private void EmitInterpolationHoleValue(ColumnarInterpolationHolePlan plan)
    {
        if (plan.BinaryOperator != null)
        {
            EmitInterpolationHoleValue(plan.BinaryLeft!);
            EmitInterpolationHoleValue(plan.BinaryRight!);
            EmitInterpolationEquality(plan.BinaryOperator, plan.BinaryLeft!.ValueType!);
            return;
        }

        if (plan.CoalesceRight != null)
        {
            EmitInterpolationSimpleHoleValue(plan);
            var end = _il.DefineLabel();
            _il.Emit(OpCodes.Dup);
            _il.Emit(OpCodes.Brtrue, end);
            _il.Emit(OpCodes.Pop);
            EmitInterpolationHoleValue(plan.CoalesceRight);
            _il.MarkLabel(end);
            return;
        }

        EmitInterpolationSimpleHoleValue(plan);
    }

    private void EmitInterpolationSimpleHoleValue(ColumnarInterpolationHolePlan plan)
    {
        if (plan.ConstantInt is { } constantInt)
        {
            _il.Emit(OpCodes.Ldc_I4, constantInt);
            return;
        }

        if (plan.RootThis)
            _il.Emit(OpCodes.Ldarg_0);
        else if (plan.RootLocal != null)
            _il.Emit(OpCodes.Ldloc, plan.RootLocal);
        else
            EmitLoadArgument(plan.RootOrdinal);
        var current = plan.RootType;
        var stackHasCurrentAddress = plan.RootThis && !IsReferenceWriteLink(current);
        if (plan.RootGetter != null)
        {
            _il.Emit(IsReferenceWriteLink(current) ? OpCodes.Callvirt : OpCodes.Call, plan.RootGetter);
            current = plan.RootGetter.ReturnType;
            stackHasCurrentAddress = false;
        }
        if (plan.RootIndexElementType != null)
        {
            if (plan.RootIndexConstant is { } constantIndex)
                _il.Emit(OpCodes.Ldc_I4, constantIndex);
            else if (plan.RootIndexLocal != null)
                _il.Emit(OpCodes.Ldloc, plan.RootIndexLocal);
            else
                EmitLoadArgument(plan.RootIndexOrdinal);
            EmitArrayElementLoad(plan.RootIndexElementType);
            current = plan.RootIndexElementType;
            stackHasCurrentAddress = false;
        }
        foreach (var hop in plan.Hops)
        {
            if (!IsReferenceWriteLink(current))
            {
                if (!stackHasCurrentAddress)
                {
                    var spill = _il.DeclareLocal(current);
                    _il.Emit(OpCodes.Stloc, spill);
                    _il.Emit(OpCodes.Ldloca, spill);
                }
            }
            if (hop.Field != null)
            {
                _il.Emit(OpCodes.Ldfld, hop.Field);
            }
            else if (hop.Getter != null)
            {
                _il.Emit(IsReferenceWriteLink(current) ? OpCodes.Callvirt : OpCodes.Call, hop.Getter);
            }
            else
            {
                throw new InvalidOperationException("Invalid interpolation member plan");
            }
            current = hop.ValueType;
            stackHasCurrentAddress = false;
        }
        if (plan.CallBuilder != null)
        {
            if (!IsReferenceWriteLink(current))
            {
                if (!stackHasCurrentAddress)
                {
                    var spill = _il.DeclareLocal(current);
                    _il.Emit(OpCodes.Stloc, spill);
                    _il.Emit(OpCodes.Ldloca, spill);
                }
                EmitInterpolationCallArgument(plan);
                _il.Emit(OpCodes.Call, plan.CallBuilder);
            }
            else
            {
                EmitInterpolationCallArgument(plan);
                _il.Emit(OpCodes.Callvirt, plan.CallBuilder);
            }
        }
        if (plan.CastSourceType != null && plan.CastTargetType != null)
            EmitInterpolationCast(plan.CastSourceType, plan.CastTargetType);
    }

    private bool TrySplitInterpolationCast(string text, out string targetName, out string operandText)
    {
        targetName = string.Empty;
        operandText = string.Empty;
        if (!text.StartsWith("(", StringComparison.Ordinal))
            return false;
        var close = text.IndexOf(')');
        if (close <= 1 || close == text.Length - 1)
            return false;
        targetName = text.Substring(1, close - 1).Trim();
        operandText = text.Substring(close + 1).Trim();
        return targetName.Length > 0
               && operandText.Length > 0
               && targetName.IndexOfAny(new[] { ' ', '\t', '\r', '\n' }) < 0;
    }

    private bool CanEmitInterpolationCast(Type sourceType, Type targetType)
    {
        if (TypesEquivalent(sourceType, targetType))
            return true;
        if (targetType == typeof(decimal) || sourceType == typeof(decimal))
            return false;
        if (IsKnownEnumType(targetType))
        {
            var enumSource = IsKnownEnumType(sourceType) ? typeof(int) : sourceType;
            return ColumnarNumericFacts.IsIntPromotable(enumSource);
        }
        if (!ColumnarNumericFacts.IsCastableScalar(targetType))
            return false;
        var scalarSource = IsKnownEnumType(sourceType) ? typeof(int) : sourceType;
        return ColumnarNumericFacts.IsCastableScalar(scalarSource);
    }

    private void EmitInterpolationCast(Type sourceType, Type targetType)
    {
        if (TypesEquivalent(sourceType, targetType) || IsKnownEnumType(targetType))
            return;
        if (IsKnownEnumType(sourceType))
            sourceType = typeof(int);
        if (sourceType == targetType)
            return;
        if (targetType == typeof(double))
            _il.Emit(OpCodes.Conv_R8);
        else if (targetType == typeof(float))
            _il.Emit(OpCodes.Conv_R4);
        else if (targetType == typeof(long))
            _il.Emit(OpCodes.Conv_I8);
        else if (targetType == typeof(ulong))
            _il.Emit(OpCodes.Conv_U8);
        else if (targetType == typeof(uint))
            _il.Emit(OpCodes.Conv_U4);
        else if (targetType == typeof(char) || targetType == typeof(ushort))
            _il.Emit(OpCodes.Conv_U2);
        else if (targetType == typeof(byte))
            _il.Emit(OpCodes.Conv_U1);
        else if (targetType == typeof(sbyte))
            _il.Emit(OpCodes.Conv_I1);
        else if (targetType == typeof(short))
            _il.Emit(OpCodes.Conv_I2);
        else
            _il.Emit(OpCodes.Conv_I4);
    }

    private void EmitInterpolationEquality(string op, Type operandType)
    {
        if (operandType == typeof(string))
        {
            _il.Emit(OpCodes.Call, typeof(string).GetMethod("op_Equality", new[] { typeof(string), typeof(string) })!);
        }
        else if (operandType == typeof(Type))
        {
            var typeEquality = typeof(Type).GetMethod(op == "==" ? "op_Equality" : "op_Inequality", new[] { typeof(Type), typeof(Type) });
            if (typeEquality != null)
            {
                _il.Emit(OpCodes.Call, typeEquality);
                return;
            }
            EmitComparison(op);
            return;
        }
        else if (operandType is TypeBuilder recordStructTb
                 && FindDefByBuilder(recordStructTb) is { IsReference: false, IsRecord: true, RecordEquals: not null } recordStructDef)
        {
            var recordRightTemp = _il.DeclareLocal(recordStructTb);
            _il.Emit(OpCodes.Stloc, recordRightTemp);
            var recordLeftTemp = _il.DeclareLocal(recordStructTb);
            _il.Emit(OpCodes.Stloc, recordLeftTemp);
            _il.Emit(OpCodes.Ldloca, recordLeftTemp);
            _il.Emit(OpCodes.Ldloc, recordRightTemp);
            _il.Emit(OpCodes.Box, recordStructTb);
            _il.Emit(OpCodes.Call, recordStructDef.RecordEquals);
        }
        else
        {
            EmitComparison(op);
            return;
        }

        if (op == "!=")
        {
            _il.Emit(OpCodes.Ldc_I4_0);
            _il.Emit(OpCodes.Ceq);
        }
    }

    private bool IsSupportedInterpolationEqualityType(Type type)
    {
        if (type == typeof(string) || type == typeof(Type))
            return true;
        if (type is TypeBuilder typeBuilder)
            return FindDefByBuilder(typeBuilder) is { IsReference: true }
                || FindDefByBuilder(typeBuilder) is { IsReference: false, IsRecord: true, RecordEquals: not null };
        return ColumnarNumericFacts.IsIntPromotable(type)
            || type == typeof(long)
            || type == typeof(ulong)
            || type == typeof(uint)
            || type == typeof(bool)
            || type == typeof(double)
            || type == typeof(float)
            || IsKnownEnumType(type);
    }

    private void EmitInterpolationCallArgument(ColumnarInterpolationHolePlan plan)
    {
        if (plan.CallArgType == null)
            return;
        if (plan.CallArgLocal != null)
            _il.Emit(OpCodes.Ldloc, plan.CallArgLocal);
        else
            EmitLoadArgument(plan.CallArgOrdinal);
        if (plan.CallArgType.IsValueType)
            _il.Emit(OpCodes.Box, plan.CallArgType);
    }

    private bool TryResolveInterpolationHole(string chain, bool allowBuilderValue, out LocalBuilder? rootLocal, out int rootOrdinal,
        out bool rootThis, out MethodInfo? rootGetter, out Type rootType, out LocalBuilder? rootIndexLocal,
        out int rootIndexOrdinal, out int? rootIndexConstant, out Type? rootIndexElementType, out List<ColumnarInterpolationMemberPlan> hops,
        out MethodBuilder? callBuilder, out LocalBuilder? callArgLocal, out int callArgOrdinal, out Type? callArgType, out Type valueType)
    {
        rootLocal = null;
        rootOrdinal = -1;
        rootThis = false;
        rootGetter = null;
        rootType = null!;
        rootIndexLocal = null;
        rootIndexOrdinal = -1;
        rootIndexConstant = null;
        rootIndexElementType = null;
        hops = new List<ColumnarInterpolationMemberPlan>();
        callBuilder = null;
        callArgLocal = null;
        callArgOrdinal = -1;
        callArgType = null;
        valueType = null!;
        string? callMember = null;
        string? callArgument = null;
        if (chain.EndsWith(")", StringComparison.Ordinal))
        {
            var openParen = chain.LastIndexOf('(');
            if (openParen < 0)
                return false;
            callArgument = chain.Substring(openParen + 1, chain.Length - openParen - 2).Trim();
            if (callArgument.Contains(','))
                return false;
            var callTarget = chain.Substring(0, openParen);
            var lastDot = callTarget.LastIndexOf('.');
            if (lastDot <= 0 || lastDot == callTarget.Length - 1)
                return false;
            callMember = callTarget.Substring(lastDot + 1);
            chain = callTarget.Substring(0, lastDot);
        }
        var names = chain.Split('.');
        var rootName = names[0];
        string? rootIndexText = null;
        var openBracket = rootName.IndexOf('[');
        if (openBracket >= 0)
        {
            if (openBracket == 0 || !rootName.EndsWith("]", StringComparison.Ordinal))
                return false;
            rootIndexText = rootName.Substring(openBracket + 1, rootName.Length - openBracket - 2).Trim();
            if (rootIndexText.Length == 0 || rootIndexText.IndexOf('[') >= 0 || rootIndexText.IndexOf(']') >= 0)
                return false;
            rootName = rootName.Substring(0, openBracket);
        }
        if (_liftedLocals.ContainsKey(rootName) || (_boxedCaptures != null && _boxedCaptures.ContainsKey(rootName)))
            return false; // lifted/boxed roots decline — the capture scans cannot see hole uses.
        if (_locals.TryGetValue(rootName, out var local))
        {
            rootLocal = local;
            rootType = local.LocalType;
        }
        else if (_paramOrdinals.TryGetValue(rootName, out var ordinal))
        {
            rootOrdinal = ordinal;
            rootType = _paramTypes[rootName];
        }
        else if (_currentStruct != null && TryFindFieldOnChain(_currentStruct, rootName, out var thisField))
        {
            rootThis = true;
            rootType = _currentStruct.Builder;
            hops.Add(new ColumnarInterpolationMemberPlan(thisField, null, thisField.FieldType));
        }
        else if (_currentStruct != null && TryFindPropertyOnChain(_currentStruct, rootName, out var thisProperty))
        {
            rootThis = true;
            rootGetter = thisProperty.Getter;
            rootType = _currentStruct.Builder;
            valueType = thisProperty.PropertyType;
        }
        else
        {
            return false; // siblings/statics/this-fields in holes — unmodelled, decline.
        }
        if (rootIndexText != null)
        {
            if (rootThis || rootGetter != null || hops.Count != 0)
                return false;
            if (!rootType.IsSZArray)
                return false;
            if (int.TryParse(rootIndexText, out var constantIndex))
            {
                rootIndexConstant = constantIndex;
            }
            else if (_locals.TryGetValue(rootIndexText, out var indexLocal))
            {
                if (indexLocal.LocalType != typeof(int))
                    return false;
                rootIndexLocal = indexLocal;
            }
            else if (_paramOrdinals.TryGetValue(rootIndexText, out var indexOrdinal))
            {
                if (_paramTypes[rootIndexText] != typeof(int))
                    return false;
                rootIndexOrdinal = indexOrdinal;
            }
            else
            {
                return false;
            }
            rootIndexElementType = rootType.GetElementType();
            if (rootIndexElementType == null || !IsSupportedType(rootIndexElementType))
                return false;
        }
        var current = rootIndexElementType ?? (rootGetter != null ? valueType : (hops.Count == 0 ? rootType : hops[^1].ValueType));
        for (var n = 1; n < names.Length; n++)
        {
            var member = n == 1 ? MaybeRewriteInterpolationTupleMemberName(rootName, names[n]) : names[n];
            if (!TryResolveInterpolationMemberPlan(current, member, out var hop))
                return false;
            hops.Add(hop);
            current = hop.ValueType!;
        }
        if (callMember != null)
        {
            if (current is not TypeBuilder owner || FindDefByBuilder(owner) is not { } def)
                return false;
            if (callArgument == "")
            {
                if (!TryFindMethodOnChain(def, callMember, out var method)
                    || method.ParamTypes.Length != 0
                    || method.ReturnType == typeof(void))
                    return false;
                callBuilder = method.Builder;
                current = method.ReturnType;
            }
            else
            {
                if (callArgument == null
                    || callMember != "Equals"
                    || !def.IsRecord
                    || def.RecordEquals == null
                    || !TryResolveInterpolationSimpleArgument(callArgument, out var argLocal, out var argOrdinal, out var argType))
                    return false;
                callBuilder = def.RecordEquals;
                callArgLocal = argLocal;
                callArgOrdinal = argOrdinal;
                callArgType = argType;
                current = typeof(bool);
            }
        }
        if ((!allowBuilderValue && ContainsBuilderBoundType(current)) || !IsSupportedType(current))
            return false;
        valueType = current;
        return true;
    }

    private bool TryResolveInterpolationMemberPlan(Type current, string member, out ColumnarInterpolationMemberPlan hop)
    {
        hop = null!;
        if (current is TypeBuilder owner && FindDefByBuilder(owner) is { } def)
        {
            if (TryFindFieldOnChain(def, member, out var hopField))
            {
                hop = new ColumnarInterpolationMemberPlan(hopField, null, hopField.FieldType);
                return true;
            }
            if (TryFindPropertyOnChain(def, member, out var hopProperty))
            {
                hop = new ColumnarInterpolationMemberPlan(null, hopProperty.Getter, hopProperty.PropertyType);
                return true;
            }
            return false;
        }

        if (TryGetClosedReceiverDef(current, out var closedDef, out var closedArgs))
        {
            if (closedDef.Fields.TryGetValue(member, out var openField))
            {
                var field = TypeBuilder.GetField(current, openField);
                hop = new ColumnarInterpolationMemberPlan(field, null, SubstituteClosedTypeArguments(openField.FieldType, closedArgs));
                return true;
            }
            if (closedDef.Properties.TryGetValue(member, out var openProperty))
            {
                var getter = TypeBuilder.GetMethod(current, openProperty.Getter);
                hop = new ColumnarInterpolationMemberPlan(null, getter, SubstituteClosedTypeArguments(openProperty.PropertyType, closedArgs));
                return true;
            }
            return false;
        }

        if (IsSupportedValueTuple(current) && IsTupleItemMember(member))
        {
            var itemField = current.GetField(member, BindingFlags.Public | BindingFlags.Instance);
            if (itemField == null)
                return false;
            hop = new ColumnarInterpolationMemberPlan(itemField, null, itemField.FieldType);
            return true;
        }

        if (member == "Length" && current == typeof(string))
        {
            var getter = typeof(string).GetProperty(nameof(string.Length))!.GetGetMethod()!;
            hop = new ColumnarInterpolationMemberPlan(null, getter, typeof(int));
            return true;
        }

        if (member == "Count" && TryResolveCollectionCountGetter(current, out var countGetter))
        {
            hop = new ColumnarInterpolationMemberPlan(null, countGetter, typeof(int));
            return true;
        }

        if (member is "Key" or "Value" && IsSupportedKeyValuePairType(current))
        {
            var getter = ResolveClosedGenericMethod(current, typeof(KeyValuePair<,>).GetProperty(member)!.GetGetMethod()!);
            hop = new ColumnarInterpolationMemberPlan(null, getter, current.GetGenericArguments()[member == "Key" ? 0 : 1]);
            return true;
        }

        if (current == typeof(DateTime)
            && typeof(DateTime).GetProperty(member, BindingFlags.Public | BindingFlags.Instance) is { GetMethod: not null } dateTimeProperty
            && IsSupportedType(dateTimeProperty.PropertyType))
        {
            hop = new ColumnarInterpolationMemberPlan(null, dateTimeProperty.GetMethod, dateTimeProperty.PropertyType);
            return true;
        }

        if (TryGetSupportedBclReadableProperty(current, member, out var bclProperty))
        {
            hop = new ColumnarInterpolationMemberPlan(null, bclProperty.GetMethod!, bclProperty.PropertyType);
            return true;
        }

        return false;
    }

    private string MaybeRewriteInterpolationTupleMemberName(string rootName, string member)
    {
        if (!_tupleNamesByVariable.TryGetValue(rootName, out var names))
            return member;
        for (var i = 0; i < names.Length; i++)
        {
            if (names[i] == member)
                return "Item" + (i + 1);
        }
        return member;
    }

    private static bool IsTupleItemMember(string member)
        => member.Length > 4
           && member.StartsWith("Item", StringComparison.Ordinal)
           && char.IsDigit(member[4]);

    private bool TryResolveInterpolationSimpleArgument(string text, out LocalBuilder? local, out int ordinal, out Type type)
    {
        local = null;
        ordinal = -1;
        type = null!;
        if (string.IsNullOrWhiteSpace(text) || text.IndexOf('.') >= 0 || text.IndexOf('(') >= 0 || text.IndexOf(')') >= 0)
            return false;
        if (_locals.TryGetValue(text, out var foundLocal))
        {
            local = foundLocal;
            type = foundLocal.LocalType;
            return true;
        }
        if (_paramOrdinals.TryGetValue(text, out var foundOrdinal))
        {
            ordinal = foundOrdinal;
            type = _paramTypes[text];
            return true;
        }
        return false;
    }

    private static bool TrySplitInterpolationEquality(string text, out string left, out string op, out string right)
    {
        left = "";
        op = "";
        right = "";
        var found = -1;
        for (var i = 0; i + 1 < text.Length; i++)
        {
            var ch = text[i];
            var next = text[i + 1];
            if ((ch == '=' && next == '=') || (ch == '!' && next == '='))
            {
                if (found >= 0)
                    return false;
                found = i;
                i++;
            }
        }

        if (found < 0)
            return false;
        left = text.Substring(0, found).Trim();
        op = text.Substring(found, 2);
        right = text.Substring(found + 2).Trim();
        return left.Length > 0 && right.Length > 0;
    }

    private static bool TryEvaluateInterpolationIntegerAdditiveExpression(string text, out int value)
    {
        value = 0;
        var pos = 0;
        if (!TryReadInterpolationIntegerTerm(text, ref pos, out value))
            return false;

        while (true)
        {
            SkipInterpolationExpressionSpace(text, ref pos);
            if (pos >= text.Length)
                return true;
            var op = text[pos];
            if (op != '+' && op != '-')
                return false;
            pos++;
            if (!TryReadInterpolationIntegerTerm(text, ref pos, out var rhs))
                return false;
            try
            {
                value = op == '+' ? checked(value + rhs) : checked(value - rhs);
            }
            catch (OverflowException)
            {
                return false;
            }
        }
    }

    private static bool TryReadInterpolationIntegerTerm(string text, ref int pos, out int value)
    {
        value = 0;
        SkipInterpolationExpressionSpace(text, ref pos);
        var start = pos;
        while (pos < text.Length && IsInterpolationAsciiDigit(text[pos]))
            pos++;
        if (pos == start)
            return false;
        return int.TryParse(
            text.Substring(start, pos - start),
            System.Globalization.NumberStyles.None,
            System.Globalization.CultureInfo.InvariantCulture,
            out value);
    }

    private static void SkipInterpolationExpressionSpace(string text, ref int pos)
    {
        while (pos < text.Length && (text[pos] == ' ' || text[pos] == '\t'))
            pos++;
    }

    private static bool IsInterpolationAsciiDigit(char ch) => ch is >= '0' and <= '9';

    private static MethodInfo FindAppendFormattedGeneric(Type handlerType, bool withFormat)
    {
        foreach (var m in handlerType.GetMethods())
        {
            if (m.Name != "AppendFormatted" || !m.IsGenericMethodDefinition)
                continue;
            var ps = m.GetParameters();
            if (!withFormat && ps.Length == 1)
                return m;
            if (withFormat && ps.Length == 2 && ps[1].ParameterType == typeof(string))
                return m;
        }
        throw new InvalidOperationException("DefaultInterpolatedStringHandler.AppendFormatted overload not found");
    }

    private int Child(int idx, int n) => _nodes.Child(idx, n);

    private string Text(int idx)
        => _nodes.Kind(idx) == 14 && _nodes.ValueStart(idx) < 0 && _nodes.ValueLengths[idx] == 1
            ? "="
            : _nodes.Text(_source, idx);

    private bool IsExplicitThisIdentifier(int idx)
    {
        if (_nodes.Kind(idx) != 6)
            return false;
        var valueStart = _nodes.ValueStart(idx);
        if (valueStart < 0)
            return false;
        var spanStart = _nodes.SpanStart(idx);
        const string prefix = "this.";
        return spanStart >= 0
               && valueStart - spanStart == prefix.Length
               && spanStart + prefix.Length <= _source.Length
               && string.Compare(_source, spanStart, prefix, 0, prefix.Length, StringComparison.Ordinal) == 0;
    }
}
