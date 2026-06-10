using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// One top-level function's parsed signature plus its columnar body node tables, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. The body table arrays are produced per-function by
/// the parser kernel <c>ParseStatementNodes</c>; <see cref="BodyRoot"/> is that body's root statement index.
/// </summary>
public sealed class ColumnarFunctionInput
{
    public ColumnarFunctionInput(
        string name, string returnCanonical, string[] paramNames, string[] paramCanonicals,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        int bodyRoot, bool isStatic = false, string[]? typeParamNames = null,
        int[]? typeParamSpecialConstraints = null, string[][]? typeParamTypeConstraints = null)
    {
        Name = name;
        ReturnCanonical = returnCanonical;
        ParamNames = paramNames;
        ParamCanonicals = paramCanonicals;
        Kinds = kinds;
        ValueStarts = valueStarts;
        ValueLengths = valueLengths;
        ChildStart = childStart;
        ChildCount = childCount;
        ChildIndices = childIndices;
        BodyRoot = bodyRoot;
        IsStatic = isStatic;
        TypeParamNames = typeParamNames ?? System.Array.Empty<string>();
        TypeParamSpecialConstraints = typeParamSpecialConstraints ?? new int[TypeParamNames.Length];
        if (typeParamTypeConstraints == null)
        {
            typeParamTypeConstraints = new string[TypeParamNames.Length][];
            for (var t = 0; t < typeParamTypeConstraints.Length; t++)
                typeParamTypeConstraints[t] = System.Array.Empty<string>();
        }
        TypeParamTypeConstraints = typeParamTypeConstraints;
    }

    public string Name { get; }
    public string ReturnCanonical { get; }
    public string[] ParamNames { get; }
    public string[] ParamCanonicals { get; }
    public int[] Kinds { get; }
    public int[] ValueStarts { get; }
    public int[] ValueLengths { get; }
    public int[] ChildStart { get; }
    public int[] ChildCount { get; }
    public int[] ChildIndices { get; }
    public int BodyRoot { get; }
    // True for a `static func` member of a struct/record/class body (no implicit `this`; param ordinals are NOT
    // shifted). Always false for a top-level function (those are CLR-static on the Program type, but their static-
    // ness is structural, not a member modifier). Set by the adapter from the kernel's outMethodStaticFlags.
    public bool IsStatic { get; }
    // Generic TYPE-PARAMETER names (`func Identity<T>(x: T): T` → ["T"]); empty for a non-generic function. A
    // generic TOP-LEVEL function declares a real CLR generic method (DefineGenericParameters, mirroring the
    // oracle's primary strategy); call sites infer the type arguments from the emitted argument types and bind
    // via MakeGenericMethod. Generic METHODS on user types decline (the oracle itself fails on them — B12).
    public string[] TypeParamNames { get; }
    // Generic CONSTRAINTS (`where T: Base, new()` — D-17b), positionally aligned with TypeParamNames. Special
    // flags mirror SpecialConstraintKind (Class=1, Struct=2, New=4); type constraints are canonical type names
    // (a base class, `string`, or another of the function's own type parameters). Both default to "none".
    public int[] TypeParamSpecialConstraints { get; }
    public string[][] TypeParamTypeConstraints { get; }
}

/// <summary>
/// One user CONSTRUCTOR: its signature + body (<see cref="Body"/>, a nameless void function) plus its optional
/// chaining initializer. <see cref="ChainInitKind"/> is 0 (none), 1 (<c>: this(args)</c>), or 2 (<c>: base(args)</c>).
/// The chained args are restricted to a param IDENTIFIER (kind 0) or an INT LITERAL (kind 1); <see cref="ChainArgKinds"/>
/// and <see cref="ChainArgTexts"/> are positionally aligned (the identifier name or the int-literal text). A
/// <c>: this(...)</c> ctor delegates field assignment to the chained ctor; a <c>: base(...)</c> ctor declines at emit
/// (no modelled base class).
/// </summary>
public sealed class ColumnarConstructorInput
{
    public ColumnarConstructorInput(ColumnarFunctionInput body, int chainInitKind, int[] chainArgKinds, string[] chainArgTexts)
    {
        Body = body;
        ChainInitKind = chainInitKind;
        ChainArgKinds = chainArgKinds;
        ChainArgTexts = chainArgTexts;
    }

    public ColumnarFunctionInput Body { get; }
    public int ChainInitKind { get; }
    public int[] ChainArgKinds { get; }
    public string[] ChainArgTexts { get; }
}

/// <summary>
/// One top-level <c>enum</c> declaration's parsed members, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. <see cref="MemberValues"/> are the resolved underlying
/// ints (auto-incremented and/or explicit), positionally aligned with <see cref="MemberNames"/>. The parser kernel
/// <c>ParseEnumDeclarationInto</c> produces the member spans; the adapter materializes the names and values.
/// </summary>
public sealed class ColumnarEnumInput
{
    public ColumnarEnumInput(string name, string[] memberNames, int[] memberValues)
    {
        Name = name;
        MemberNames = memberNames;
        MemberValues = memberValues;
    }

    public string Name { get; }
    public string[] MemberNames { get; }
    public int[] MemberValues { get; }
}

/// <summary>
/// A user-defined enum being emitted: its <see cref="EnumBuilder"/> (its CLR <see cref="Type"/> — an i4-underlying
/// value type) plus its member-name → constant-int map (for <c>Enum.Member</c> value and pattern resolution). Built
/// in PASS 0 of <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/> and threaded into type resolution + emit.
/// </summary>
internal sealed class ColumnarEnumDef
{
    public ColumnarEnumDef(EnumBuilder builder, Dictionary<string, int> constants)
    {
        Builder = builder;
        Constants = constants;
    }

    public EnumBuilder Builder { get; }
    public Dictionary<string, int> Constants { get; }
}

/// <summary>
/// One top-level fields-only <c>struct</c> declaration's parsed fields, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. <see cref="FieldTypeCanonicals"/> are the canonical type
/// strings (e.g. "int") positionally aligned with <see cref="FieldNames"/>. The parser kernel
/// <c>ParseStructDeclarationInto</c> produces the field spans; the adapter materializes the names and type strings.
/// </summary>
/// <summary>
/// One computed PROPERTY on a class/record: its name, its type canonical, its getter BODY (a function whose name is
/// the IL accessor "get_Name", no params, returning the property type), and an optional setter BODY (a function whose
/// name is "set_Name", one parameter "value" of the property type, returning void). The emitter declares get_Name (+
/// set_Name when present) instance methods and resolves a `receiver.Name` read to get_Name / a `receiver.Name = v`
/// write to set_Name.
/// </summary>
public sealed class ColumnarPropertyInput
{
    public ColumnarPropertyInput(string name, string typeCanonical, ColumnarFunctionInput getter, ColumnarFunctionInput? setter, bool isStatic = false)
    {
        Name = name;
        TypeCanonical = typeCanonical;
        Getter = getter;
        Setter = setter;
        IsStatic = isStatic;
    }

    // True for a `static Name: Type { get {...} [set {...}] }` member: the accessors are CLR-static (no implicit
    // `this`; the setter's `value` is arg 0), resolved via `TypeName.Name` (chain-walked) and bare READS inside
    // INSTANCE member bodies (the pipeline's pinned asymmetry — a static body must qualify).
    public bool IsStatic { get; }

    public string Name { get; }
    public string TypeCanonical { get; }
    public ColumnarFunctionInput Getter { get; }
    // The setter body ("set_Name", param "value": Type, returns void), or null for a get-only property.
    public ColumnarFunctionInput? Setter { get; }
}

public sealed class ColumnarStructInput
{
    public ColumnarStructInput(string name, string[] fieldNames, string[] fieldTypeCanonicals, IReadOnlyList<ColumnarFunctionInput> methods, IReadOnlyList<ColumnarConstructorInput> constructors, IReadOnlyList<ColumnarPropertyInput> properties, bool isReference, string? baseName = null, bool[]? fieldStaticFlags = null, int[]? fieldInitKinds = null, string?[]? fieldInitTexts = null, bool isRecord = false, string[]? typeParamNames = null)
    {
        Name = name;
        FieldNames = fieldNames;
        FieldTypeCanonicals = fieldTypeCanonicals;
        Methods = methods;
        Constructors = constructors;
        Properties = properties;
        IsReference = isReference;
        BaseName = baseName;
        FieldStaticFlags = fieldStaticFlags;
        FieldInitKinds = fieldInitKinds;
        FieldInitTexts = fieldInitTexts;
        IsRecord = isRecord;
        TypeParamNames = typeParamNames;
    }

    public string Name { get; }
    public string[] FieldNames { get; }
    public string[] FieldTypeCanonicals { get; }
    // Instance methods declared in the struct body (parsed exactly like a top-level function — signature + body
    // node tables). Models scalar/struct-returning methods (with or without parameters) reading fields by bare name.
    public IReadOnlyList<ColumnarFunctionInput> Methods { get; }
    // User CONSTRUCTORS declared in the body (reference types only this slice). Each is parsed like a function whose
    // name is "constructor" and whose return is void — its params + body node tables drive a DefineConstructor + a
    // ctor body (base call + field assignments). Empty when the type has no user constructor (object-init only).
    public IReadOnlyList<ColumnarConstructorInput> Constructors { get; }
    // Get-only computed PROPERTIES declared in the body (reference types this slice). Each drives a get_Name instance
    // method; a `receiver.Name` read resolves to a call of it.
    public IReadOnlyList<ColumnarPropertyInput> Properties { get; }
    // True for a RECORD or CLASS (a reference type — class base object, constructed via newobj + a default ctor or a
    // user ctor, fields read directly via ldfld on the ref). False for a value-type struct (initobj + ldloca + ldfld).
    public bool IsReference { get; }
    // The optional `: Base` single-identifier base-type name (`class D: Base`), or null. Only a CLASS may inherit,
    // and only from another declared class — the emitter validates and declines everything else (a struct/record/
    // enum/union/unknown base, a base on a value type).
    public string? BaseName { get; }
    // Per-field STATIC flags, positionally aligned with FieldNames (null = all instance, for older callers). A
    // static field is CLR-static on the type (FieldAttributes.Static), excluded from the instance FieldOrder
    // (object-init / positional construction never bind it), and accessed via `TypeName.field` (or bare inside an
    // INSTANCE member body — the N# pipeline's pinned asymmetry: bare static-field access resolves in instance
    // contexts but NOT in static ones).
    public bool[]? FieldStaticFlags { get; }
    // Per-field INITIALIZER literal token kinds (-1 = none): IntLiteral 1 / FloatLiteral 2 / CharLiteral 3 /
    // StringLiteral 4 / true 44 / false 45. Static fields only (the kernel declines instance-field initializers).
    public int[]? FieldInitKinds { get; }
    // The initializer's literal source text (incl. an optional leading `-` on numerics), aligned with
    // FieldInitKinds; null where no initializer. Emitted into the type's .cctor in declaration order.
    public string?[]? FieldInitTexts { get; }
    // True for a RECORD declaration (keyword 13). Records are reference types like classes, but the C# oracle
    // emits them SEALED — a record can never appear as a BASE type, and record inheritance itself is unmodelled;
    // PASS 0a' declines both shapes by this flag.
    public bool IsRecord { get; }
    // Generic type parameters declared on the type (`class Box<T>` → ["T"]), or null for a non-generic type.
    // The adapter already declines generic RECORDS (columnar does not yet model the oracle's backing-field
    // lowering for init-only members on closed generics — the .NET 10 PersistedAssemblyBuilder modreq-drop
    // workaround) and generic types WITH a base. PASS 0 declares them
    // via DefineGenericParameters; member signatures resolve these names before any other type lookup.
    public string[]? TypeParamNames { get; }
}

/// <summary>
/// One top-level <c>union</c> declaration's parsed cases, as consumed by
/// <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>. Each case has a name and a (possibly empty) list of
/// fields; <see cref="CaseFieldNames"/>[c] and <see cref="CaseFieldTypeCanonicals"/>[c] are positionally aligned
/// for case <c>c</c>. The parser kernel <c>ParseUnionDeclarationInto</c> produces the per-case spans; the adapter
/// materializes the names and type strings.
/// </summary>
public sealed class ColumnarUnionInput
{
    public ColumnarUnionInput(string name, string[] caseNames, string[][] caseFieldNames, string[][] caseFieldTypeCanonicals)
    {
        Name = name;
        CaseNames = caseNames;
        CaseFieldNames = caseFieldNames;
        CaseFieldTypeCanonicals = caseFieldTypeCanonicals;
    }

    public string Name { get; }
    public string[] CaseNames { get; }
    public string[][] CaseFieldNames { get; }
    public string[][] CaseFieldTypeCanonicals { get; }
}

/// <summary>
/// A user-defined struct being emitted: its <see cref="TypeBuilder"/> (a <see cref="System.ValueType"/>-based value
/// type) plus its field-name → <see cref="FieldBuilder"/> map (so construction and field access emit ldfld/stfld
/// against the builder handles directly — never <c>GetField</c>, which throws on an un-finalized TypeBuilder). Built
/// in PASS 0 of <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>.
/// </summary>
internal sealed class ColumnarStructDef
{
    public ColumnarStructDef(TypeBuilder builder, string[] fieldOrder, Dictionary<string, FieldBuilder> fields, bool isReference, bool isRecord = false)
    {
        Builder = builder;
        FieldOrder = fieldOrder;
        Fields = fields;
        IsReference = isReference;
        IsRecord = isRecord;
    }

    public TypeBuilder Builder { get; }
    public string[] FieldOrder { get; }
    public Dictionary<string, FieldBuilder> Fields { get; }
    // Generic type parameters declared on this type (`class Box<T>` → "T" → its builder), or null for a
    // non-generic type. Member signatures and bodies resolve these names FIRST (before registries/builtins);
    // closed instantiations (`Box<int>`) MakeGenericType the Builder and rebind member tokens via
    // TypeBuilder.GetField/GetConstructor/GetMethod (reflection member queries throw on
    // TypeBuilderInstantiation — the same machinery the C# oracle uses).
    public Dictionary<string, Type>? GenericParameters { get; set; }
    // True for a RECORD or CLASS (a reference type). For a record, DefaultCtor is its parameterless ctor (newobj target).
    public bool IsReference { get; }
    // True for a RECORD specifically — records can never be BASE types (the oracle emits them sealed) and record
    // inheritance is unmodelled; PASS 0a' declines both shapes.
    public bool IsRecord { get; }
    // The synthesized public parameterless constructor (the object-init `newobj` target) for a reference type with
    // NO user constructors — chains to object (no base) or to the base's parameterless ctor. Set in PASS 0d (after
    // user ctors are declared, so a derived default ctor can chain to a base USER 0-param ctor); null for a value
    // type or a type with user ctors.
    public ConstructorBuilder? DefaultCtor { get; set; }
    // The declared BASE class's def (`class D: Base`), or null. Reference types only; set in PASS 0a'. Member
    // resolution (fields/methods/properties) walks this chain, nearest declaration first (modelling method hiding).
    public ColumnarStructDef? BaseDef { get; set; }
    // Instance methods declared on this struct, by name -> (the declared MethodBuilder, param types, return type).
    // Populated in PASS 0; lets `receiver.Method(args)` resolve the instance call (ldloca receiver; <args>; call).
    public Dictionary<string, (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)> Methods { get; } = new(StringComparer.Ordinal);
    // STATIC methods declared on this type, by name -> the declared overloads (distinct PARAM COUNT only — a
    // same-arity overload set declines in PASS 0b, mirroring the constructor-overload rule). Resolved by
    // `TypeName.Method(args)` (chain-walked, nearest declaration first) and by bare calls inside this type's own
    // member bodies (after locals/params and sibling top-level functions — the empirically pinned N# order).
    public Dictionary<string, List<(MethodBuilder Builder, Type[] ParamTypes, Type ReturnType)>> StaticMethods { get; } = new(StringComparer.Ordinal);
    // STATIC fields declared on this type, by name -> the FieldBuilder. CLR-static (ldsfld/stsfld); excluded from
    // FieldOrder/Fields so object-init and positional construction never see them. Resolved by `TypeName.field`
    // (chain-walked) and by bare names inside INSTANCE member bodies only (the pipeline's pinned asymmetry).
    public Dictionary<string, FieldBuilder> StaticFields { get; } = new(StringComparer.Ordinal);
    // STATIC computed properties, by name -> (static get_Name, static set_Name or null, property type). Resolved
    // by `TypeName.Name` reads (`call get_Name`) / writes (`call set_Name`, chain-walked) and by bare READS inside
    // INSTANCE member bodies (after instance members and static fields).
    public Dictionary<string, (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType)> StaticProperties { get; } = new(StringComparer.Ordinal);
    // User CONSTRUCTORS (reference types this slice): each declared ConstructorBuilder + its param types. Positional
    // construction `new T(args)` matches a ctor by arg count + arg types. Empty when the type has no user ctor (then
    // DefaultCtor drives object-init). A type with ≥1 user ctor has NO DefaultCtor (object-init on it declines).
    public List<(ConstructorBuilder Builder, Type[] ParamTypes)> Constructors { get; } = new();
    // Computed PROPERTIES, by name -> (the get_Name getter MethodBuilder, the set_Name setter MethodBuilder or null,
    // the property type). A `receiver.Name` read resolves to `callvirt get_Name`; a `receiver.Name = v` write (when a
    // setter exists) to `callvirt set_Name`.
    public Dictionary<string, (MethodBuilder Getter, MethodBuilder? Setter, Type PropertyType)> Properties { get; } = new(StringComparer.Ordinal);
}

/// <summary>
/// A user-defined union being emitted. <see cref="Base"/> is an ABSTRACT reference type (class) — the common base
/// every case derives from, and the type a <c>match</c> scrutinee / a <c>Union</c>-typed param/return is statically
/// seen as. <see cref="Cases"/> maps each case's QUALIFIED name ("Union.Case") to its
/// <see cref="ColumnarUnionCaseDef"/>. Built in PASS 0 of <see cref="ColumnarIlEmitter.TryEmitColumnarAssembly"/>,
/// mirroring the C# ILCompiler's <c>DeclareUnion</c> (abstract base + sealed nested case classes).
/// </summary>
internal sealed class ColumnarUnionDef
{
    public ColumnarUnionDef(TypeBuilder baseBuilder)
    {
        Base = baseBuilder;
    }

    public TypeBuilder Base { get; }
    // Qualified "Union.Case" -> case. Enumerated for match exhaustiveness; keyed for construction/pattern lookup.
    public Dictionary<string, ColumnarUnionCaseDef> Cases { get; } = new(StringComparer.Ordinal);
}

/// <summary>
/// One case of a <see cref="ColumnarUnionDef"/>: a SEALED reference type (class) deriving from the union base, with a
/// public parameterless constructor (the <c>newobj</c> target for object-initializer construction) and a public
/// field per declared case field. <see cref="UnionBase"/> is the enclosing union's base type — the STATIC type a
/// constructed case is reported as (an upcast; the runtime object is the concrete case, recovered by a later match).
/// </summary>
internal sealed class ColumnarUnionCaseDef
{
    public ColumnarUnionCaseDef(TypeBuilder caseType, ConstructorBuilder ctor, string[] fieldOrder, Dictionary<string, FieldBuilder> fields, TypeBuilder unionBase)
    {
        CaseType = caseType;
        Ctor = ctor;
        FieldOrder = fieldOrder;
        Fields = fields;
        UnionBase = unionBase;
    }

    public TypeBuilder CaseType { get; }
    public ConstructorBuilder Ctor { get; }
    public string[] FieldOrder { get; }
    public Dictionary<string, FieldBuilder> Fields { get; }
    public TypeBuilder UnionBase { get; }
}

/// <summary>
/// COLUMNAR PIPELINE — stage 4 SPIKE (docs/design/roadmap-to-done.md). Proof that the columnar node tables can
/// drive IL emission END-TO-END with no C# AST: for a single trivial function it emits a real .NET assembly
/// (one static method) whose body IL is generated DIRECTLY from the columnar statement/expression tables, then
/// returns the assembly bytes so a caller can load + invoke it. This is the de-risking spike for Stage 4 — the
/// emit primitives (<c>ldarg</c> / <c>ldc.i4</c> / arithmetic / <c>ret</c>) are exactly what the full columnar
/// codegen will emit; later slices grow the supported surface and route through <c>ILCompiler</c> proper.
///
/// Deliberately narrow: top-level <c>func</c> with INT params/return only (mixed-type arithmetic would need
/// conversions this spike does not emit). Statements: <c>:=</c> int locals, a simple <c>local = expr</c>
/// assignment, Return (value required), an <c>if</c>/<c>else</c> where BOTH branches always return (no
/// fall-through), and a <c>while</c> loop whose body does not always return. Value expressions: a parameter, a
/// <c>:=</c> local, an int literal, a parenthesized expr, an int unary <c>-</c>/<c>~</c>, or an int +/-/* binary.
/// <c>if</c> conditions are an
/// int comparison (<c>&lt; &gt; &lt;= &gt;= == !=</c>) only. Anything else returns false (the adapter declines
/// → the C# path is unaffected).
/// </summary>
public sealed class ColumnarIlEmitter
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStart;
    private readonly int[] _childCount;
    private readonly int[] _childIndices;
    private readonly string _source;
    private readonly Dictionary<string, int> _paramOrdinals;
    private readonly IReadOnlyDictionary<string, Type> _paramTypes;
    private readonly Type _returnType;
    private readonly ILGenerator _il;
    // Sibling top-level functions callable from this body, by name -> (declared method, param types, return
    // type). All are declared (pass 1) before any body is emitted (pass 2), so a forward/self call resolves to
    // a MethodBuilder whose body is not yet emitted — the token is baked at CreateType/Save. Includes this
    // function itself, so direct recursion works. Param/return types are carried (rather than reflected) because
    // MethodBuilder.GetParameters()/ReturnType is unsupported before the type is created — and a Call checks each
    // argument's type against the callee's param types (int and bool are both i4, so a mismatch would otherwise
    // produce verifiable-but-wrong IL rather than declining).
    private readonly IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)> _siblings;
    // User-defined enums in this program, by name -> (EnumBuilder, member->value). Lets member access `Enum.Member`
    // and enum match patterns resolve their underlying-int constant, and types resolve `Color` to its EnumBuilder.
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
    private readonly Stack<(Label Break, Label Continue)> _loopLabels = new();

    // True when this emitter is producing a CONSTRUCTOR body. In a VALUE-TYPE ctor, `this` (arg 0)
    // is the managed pointer to the caller's storage (newobj passes the new value's address), so
    // bare field WRITES are correct there — unlike struct METHODS, whose receiver is a spilled
    // temp copy (mutation would write the copy; those stay declined).
    private readonly bool _isConstructorBody;

    private ColumnarIlEmitter(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStart, int[] childCount, int[] childIndices, string source,
        Dictionary<string, int> paramOrdinals, IReadOnlyDictionary<string, Type> paramTypes, Type returnType,
        ILGenerator il,
        IReadOnlyDictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)> siblings,
        IReadOnlyDictionary<string, ColumnarEnumDef> enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef> structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef> unionRegistry,
        IReadOnlyDictionary<string, ColumnarUnionCaseDef> unionCaseRegistry,
        ColumnarStructDef? currentStruct,
        ColumnarStructDef? enclosingType = null,
        bool isConstructorBody = false)
    {
        _isConstructorBody = isConstructorBody;
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStart = childStart;
        _childCount = childCount;
        _childIndices = childIndices;
        _source = source;
        _paramOrdinals = paramOrdinals;
        _paramTypes = paramTypes;
        _returnType = returnType;
        _il = il;
        _siblings = siblings;
        _enumRegistry = enumRegistry;
        _structRegistry = structRegistry;
        _unionRegistry = unionRegistry;
        _unionCaseRegistry = unionCaseRegistry;
        _currentStruct = currentStruct;
        _enclosingType = enclosingType ?? currentStruct;
    }

    // The types the type-aware emitter currently handles: int/bool/long/ulong scalars (double is a later
    // slice), plus a single-dimension ARRAY of a supported element type (e.g. int[], long[], ulong[]). (Mixed
    // arithmetic — implicit widening — is not modelled; an expression's operands must share one type.) ulong is
    // u8 on the stack like long (i8), but its arithmetic uses the UNSIGNED opcodes (Shr_Un/Div_Un/Rem_Un and
    // unsigned compares) — see the binary/comparison cases.
    private static bool IsSupportedType(Type t) =>
        t == typeof(int) || t == typeof(bool) || t == typeof(long) || t == typeof(ulong)
        || t == typeof(string) || t == typeof(char) || t == typeof(double) || t == typeof(float)
        || t == typeof(System.Text.StringBuilder)
        || t is EnumBuilder                       // a user-defined enum — its own i4-underlying value type
        || t is TypeBuilder                       // a user-defined struct (value type) OR record (reference type);
                                                  // only those reach here as a resolved type — the Program type never does
        || t is GenericTypeParameterBuilder       // a generic type/method parameter (T) — valid member/param/local type
        || IsClosedUserGenericInstantiation(t)    // Box<int> over a user generic definition (TypeBuilderInstantiation)
        || (t.IsSZArray && IsSupportedElementType(t.GetElementType()!))
        || IsSupportedValueTuple(t)
        || IsSupportedDelegateType(t);            // a closed System.Func/Action over baked runtime types (L1a)

    // A closed System.Func/Action delegate over BAKED runtime types (the L1a delegate surface), or the bare
    // System.Action — valid as a param/return/local so delegate-typed parameters can be received and invoked
    // (`t(v)` -> callvirt Invoke). Builder-arg instantiations are excluded: ctor/Invoke resolution throws on
    // a runtime generic closed over an un-baked builder type (the same rule the tuple elements apply).
    private static bool IsSupportedDelegateType(Type t)
    {
        if (t == typeof(Action))
            return true;
        if (t is TypeBuilder || t is EnumBuilder || !t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        Type def;
        try
        {
            def = t.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return false;
        }
        if (def != typeof(Action<>) && def != typeof(Action<,>) && def != typeof(Action<,,>) && def != typeof(Action<,,,>)
            && def != typeof(Func<>) && def != typeof(Func<,>) && def != typeof(Func<,,>) && def != typeof(Func<,,,>)
            && def != typeof(Func<,,,,>))
            return false;
        foreach (var arg in t.GetGenericArguments())
        {
            if (arg.Assembly is AssemblyBuilder || !IsSupportedType(arg))
                return false;
        }
        return true;
    }

    // A closed instantiation of a USER generic type (Box<int> where Box is an uncreated TypeBuilder).
    // Reflection member queries throw on these — member access goes through the open definition's
    // bookkeeping with rebound tokens, mirroring the C# oracle's closed-generic machinery.
    private static bool IsClosedUserGenericInstantiation(Type t)
    {
        if (t is TypeBuilder || !t.IsGenericType || t.IsGenericTypeDefinition)
            return false;
        try
        {
            return t.GetGenericTypeDefinition() is TypeBuilder;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

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
            // Exclude an EnumBuilder OR a user-struct TypeBuilder element: a ValueTuple<…> instantiated over a
            // builder type cannot resolve its ctor/ItemN fields via plain reflection (GetConstructor/GetField throw
            // NotSupportedException at emit), so enum-in-tuple / struct-in-tuple must DECLINE here (→ C# fallback) —
            // consistent with the array-element decline. Enums and structs are modelled as scalars/locals only.
            // Delegates are likewise excluded from tuple elements (the L1a delegate surface is params/locals only).
            if (arg is EnumBuilder || arg is TypeBuilder || IsSupportedDelegateType(arg) || !IsSupportedType(arg))
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
        foreach (var (builder, paramTypes) in def.Constructors)
        {
            if (paramTypes.Length == 0)
                return builder;
        }
        return null;
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

    private static bool TryFindMethodOnChain(ColumnarStructDef def, string name, out (MethodBuilder Builder, Type[] ParamTypes, Type ReturnType) method)
    {
        for (var d = def; d != null; d = d.BaseDef)
        {
            if (d.Methods.TryGetValue(name, out method))
                return true;
        }
        method = default;
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
    // the literal agrees with the declared field type (mismatch declines — the oracle's implicit numeric
    // conversions are not modelled). Mirrors the expression emitter's literal cases EXACTLY: int suffix
    // classification (L/UL), float suffixes (f/d; m declines), RAW string literals (Trim('"'), no escape decode —
    // matching the C# path's GetStringLiteralRuntimeValue), char escape decode, true/false. The text may carry a
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
                if (!TryDecodeLiteralBody(raw, out var charValue) || charValue.Length != 1)
                    return false;
                il.Emit(OpCodes.Ldc_I4, (int)charValue[0]);
                return true;
            }
            case 4: // StringLiteral: RAW (Trim('"'), no escape decode — the N#/C#-path semantics).
                if (fieldType != typeof(string))
                    return false;
                il.Emit(OpCodes.Ldstr, text.Trim('"'));
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

    // Invoke a DELEGATE-typed local or parameter (`t(v)` where `t: Func<int,int>` — L1a): load the delegate
    // value, emit each argument exactly typed against Invoke's parameters, `callvirt Invoke`. Fires ONLY when
    // no method tier carries the name (the pipeline's pinned method-beats-local order — the caller checks);
    // a non-delegate-typed value declines. Invoke resolves by plain GetMethod — sound because
    // IsSupportedDelegateType admits closed Func/Action over BAKED runtime types only (the oracle's
    // TryGetDelegateInvokeMethod does the same for runtime delegate types).
    private bool TryEmitDelegateInvoke(int callIdx, string name, out Type type)
    {
        type = null!;
        Type delegateType;
        if (_locals.TryGetValue(name, out var local))
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
        var argCount = _childCount[callIdx] - 1;
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
        var argCount = _childCount[callIdx] - 1;
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
        if (actual is TypeBuilder || actual is EnumBuilder)
            return false; // instantiating over an un-baked user type is a Reflection.Emit hazard — decline.
        if (!actual.IsGenericParameter && !IsSupportedType(actual))
            return false;
        if (binding[pos] == null)
        {
            binding[pos] = actual;
            return true;
        }
        return ReferenceEquals(binding[pos], actual) || binding[pos] == actual;
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
        var argCount = _childCount[callIdx] - 1;
        if (argCount != method.ParamTypes.Length)
            return false;
        _il.Emit(OpCodes.Ldarg_0);
        for (var a = 1; a <= argCount; a++)
        {
            if (!EmitExpression(Child(callIdx, a), out var argType) || argType != method.ParamTypes[a - 1])
                return false;
        }
        _il.Emit(_currentStruct!.IsReference ? OpCodes.Callvirt : OpCodes.Call, method.Builder);
        type = method.ReturnType;
        return true;
    }

    // Resolve a STATIC FIELD on `def`'s chain by name, nearest declaration first (the oracle's chain-walked
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
    // base-declared static property — the fixed oracle chain-walks its get_X/set_X exactly like static fields).
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

    // Resolve a STATIC method call on `def`'s chain by name + ARG COUNT, nearest declaration first. Mirrors the
    // oracle's bind-or-walk-on rule (the fixed C# ILCompiler): a type whose overload set carries the name but has
    // no matching arity does NOT stop the walk — a base overload of the right arity still binds. (Same-arity
    // overload sets were declined in PASS 0b, so an arity match is unique per type.) The arg TYPES are checked at
    // the emit site (a mismatch declines — the oracle's implicit conversions are not modelled).
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


    // Element types the array read/write/alloc paths can emit ldelem/stelem/newarr for: int/long/ulong (i4/i8),
    // char (u2), double (r8) / float (r4), and string (a reference element). bool is excluded until its element
    // opcodes land. ulong shares long's 8-byte slot (Ldelem_I8/Stelem_I8 move the bit pattern; the unsignedness is
    // purely in how the VALUE is operated on, not how it is stored/loaded).
    private static bool IsSupportedElementType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char) || t == typeof(string)
        || t == typeof(double) || t == typeof(float);

    /// <summary>
    /// Resolve a canonical type string for a GENERIC function's signature: a bare type-parameter name resolves to
    /// its <see cref="GenericTypeParameterBuilder"/>, "T[]" to its array, and everything else falls through to
    /// <see cref="TryResolveType"/>. Type parameters are checked FIRST, mirroring the oracle's ResolveType (a
    /// generic parameter shadows same-named types within its function's signature). Composed shapes over T
    /// (tuples, nested generics) are not modelled and fail — the function declines to the C# path.
    /// </summary>
    private static bool TryResolveTypeWithTypeParams(string canonical,
        IReadOnlyDictionary<string, Type> typeParams,
        IReadOnlyDictionary<string, ColumnarEnumDef>? enumRegistry,
        IReadOnlyDictionary<string, ColumnarStructDef>? structRegistry,
        IReadOnlyDictionary<string, ColumnarUnionDef>? unionRegistry, out Type type)
    {
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
            return TryResolveClosedUserGeneric(canonical, genericOpen, typeParams, enumRegistry, structRegistry, unionRegistry, out type);
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
            try
            {
                isMethodParameter = signatureType.DeclaringMethod != null;
            }
            catch (NotSupportedException)
            {
                isMethodParameter = false;
            }
            if (!isMethodParameter && signatureType.GenericParameterPosition < closedArguments.Length)
                return closedArguments[signatureType.GenericParameterPosition];
            return signatureType;
        }
        if (signatureType.IsSZArray)
            return SubstituteClosedTypeArguments(signatureType.GetElementType()!, closedArguments).MakeArrayType();
        if (signatureType.IsGenericType && !signatureType.IsGenericTypeDefinition)
        {
            try
            {
                var definition = signatureType.GetGenericTypeDefinition();
                var arguments = signatureType.GetGenericArguments();
                var substituted = new Type[arguments.Length];
                for (var i = 0; i < arguments.Length; i++)
                    substituted[i] = SubstituteClosedTypeArguments(arguments[i], closedArguments);
                return definition.MakeGenericType(substituted);
            }
            catch (NotSupportedException)
            {
                return signatureType;
            }
        }
        return signatureType;
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
        if (structRegistry == null || !structRegistry.TryGetValue(headName, out var openDef)
            || !openDef.Builder.IsGenericTypeDefinition)
        {
            return false;
        }

        var argCanons = SplitTopLevelCommas(canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2));
        if (argCanons.Count != openDef.Builder.GetGenericArguments().Length)
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

        type = openDef.Builder.MakeGenericType(argTypes);
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
        if (canonical.EndsWith("[]", StringComparison.Ordinal))
        {
            if (TryResolveBuiltin(canonical.Substring(0, canonical.Length - 2), out var elementType))
            {
                type = elementType.MakeArrayType();
                return true;
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
        // Tuple `(e0,e1,...)` -> System.ValueTuple<...> (positional, arity 2-7). The canonical (from the kernel's
        // ColumnarTypeCanon / the C# ColumnarFunctionSymbol.CanonicalType) is parens + comma-joined element canons;
        // split at the TOP level (respecting nested ()/<>/[]), resolve each element recursively, then
        // MakeGenericType the matching open ValueTuple. (Only Tuple type nodes produce a `(...)` canonical.)
        if (canonical.Length >= 2 && canonical[0] == '(' && canonical[^1] == ')')
        {
            var elements = SplitTopLevelCommas(canonical.Substring(1, canonical.Length - 2));
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
        // `Func<int, void>` IS Action<int>, exactly as the oracle's CreateDelegateType maps it.
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
            if (TryResolveClosedUserGeneric(canonical, closedGenericOpen, null, enumRegistry, structRegistry, unionRegistry, out type))
                return true;
            if (closedGenericOpen == 6 && canonical.StartsWith("Action<", StringComparison.Ordinal))
            {
                return TryResolveDelegateCanonical(
                    canonical.Substring(7, canonical.Length - 8), hasReturnSlot: false,
                    enumRegistry, structRegistry, unionRegistry, out type);
            }
            type = null!;
            return false;
        }
        // A bare name matching a user-defined enum resolves to its EnumBuilder (so `Color` is a valid param/return/
        // local type). Checked before the builtins so a user enum never collides with a builtin name (it cannot —
        // builtin names are reserved keywords the parser would not accept as an enum name).
        if (enumRegistry != null && enumRegistry.TryGetValue(canonical, out var enumDef))
        {
            type = enumDef.Builder;
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
        if (unionRegistry != null && unionRegistry.TryGetValue(canonical, out var unionDef))
        {
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
        return TryResolveBuiltin(canonical, out type);
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
        var parts = SplitTopLevelCommas(argList);
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

    // Split `s` on commas at bracket depth 0 (parens, angle brackets, and square brackets all nest), so a tuple
    // canonical `(int,int),string` splits into its top-level element canons without breaking nested tuples/generics.
    private static List<string> SplitTopLevelCommas(string s)
    {
        var parts = new List<string>();
        var depth = 0;
        var start = 0;
        for (var i = 0; i < s.Length; i++)
        {
            switch (s[i])
            {
                case '(': case '<': case '[': depth++; break;
                case ')': case '>': case ']': depth--; break;
                case ',' when depth == 0:
                    parts.Add(s.Substring(start, i - start));
                    start = i + 1;
                    break;
            }
        }

        parts.Add(s.Substring(start));
        return parts;
    }

    /// <summary>
    /// Decode the (quote-stripped) body of a char/string literal, resolving the common C-style escape sequences
    /// (<c>\n \r \t \\ \" \' \0 \a \b \f \v</c>) to their characters. Returns false for an unknown/unsupported
    /// escape (e.g. <c>\u</c>/<c>\x</c> or a trailing backslash) so that literal declines — keeping the C# path
    /// authoritative rather than mis-decoding. A body with no backslash is returned verbatim.
    /// </summary>
    private static bool TryDecodeLiteralBody(string body, out string decoded)
    {
        decoded = string.Empty;
        if (!body.Contains('\\'))
        {
            decoded = body;
            return true;
        }
        var sb = new System.Text.StringBuilder(body.Length);
        for (var i = 0; i < body.Length; i++)
        {
            var ch = body[i];
            if (ch != '\\')
            {
                sb.Append(ch);
                continue;
            }
            if (i + 1 >= body.Length)
                return false; // trailing backslash.
            i++;
            switch (body[i])
            {
                case 'n': sb.Append('\n'); break;
                case 'r': sb.Append('\r'); break;
                case 't': sb.Append('\t'); break;
                case '\\': sb.Append('\\'); break;
                case '"': sb.Append('"'); break;
                case '\'': sb.Append('\''); break;
                case '0': sb.Append('\0'); break;
                case 'a': sb.Append('\a'); break;
                case 'b': sb.Append('\b'); break;
                case 'f': sb.Append('\f'); break;
                case 'v': sb.Append('\v'); break;
                default: return false; // \u, \x, or unknown escape — decline.
            }
        }
        decoded = sb.ToString();
        return true;
    }

    // Parse a floating-point literal's body (type suffix already stripped by the caller) to its double value,
    // mirroring the C# path's ParseFloatLiteralValue: drop `_` digit separators, then parse invariant-culture.
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
    public static bool TryResolveBuiltin(string canonical, out Type type)
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
            "string" => typeof(string),
            _ => null!,
        };
        return type != null;
    }

    /// <summary>
    /// Build a one-method assembly for <paramref name="funcName"/> whose body IL is emitted from the columnar
    /// tables. Returns false (no assembly) for any unsupported type or body shape. The emitted type is
    /// <c>ColumnarSpike</c> and the method is static. Thin wrapper over <see cref="TryEmitColumnarAssembly"/>.
    /// </summary>
    public static bool TryEmitSingleFunctionAssembly(
        string funcName, string returnCanonical, string[] paramNames, string[] paramCanonicals,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, int bodyRoot, out byte[] assembly)
    {
        var input = new ColumnarFunctionInput(
            funcName, returnCanonical, paramNames, paramCanonicals,
            kinds, valueStarts, valueLengths, childStart, childCount, childIndices, bodyRoot);
        return TryEmitColumnarAssembly("ColumnarSpike", "ColumnarSpike", new[] { input }, Array.Empty<ColumnarEnumInput>(), Array.Empty<ColumnarStructInput>(), Array.Empty<ColumnarUnionInput>(), source, out assembly);
    }

    /// <summary>
    /// Build a single assembly containing ALL of <paramref name="funcs"/> as static methods on one type
    /// (<paramref name="typeName"/>), each body's IL emitted from its columnar tables. This is the standalone
    /// columnar backend's assembly seam (the chosen Stage 4j routing — a columnar-first pipeline that owns
    /// emission, not a re-parse hook into the C# ILCompiler). Two-pass: pass 1 resolves types and DECLARES every
    /// method (so a body can later resolve a call to a sibling method that is declared but not yet emitted —
    /// the foundation for slice 4i); pass 2 emits each body. Returns false (no assembly) if ANY function is
    /// ineligible (non-int type or an unsupported body shape) — the whole program declines, keeping the C# path
    /// authoritative. INT-ONLY for now (untyped <c>add</c>/<c>ldc.i4</c>); later slices add type-aware emission.
    /// </summary>
    public static bool TryEmitColumnarAssembly(
        string assemblyName, string typeName, IReadOnlyList<ColumnarFunctionInput> funcs,
        IReadOnlyList<ColumnarEnumInput> enums, IReadOnlyList<ColumnarStructInput> structs,
        IReadOnlyList<ColumnarUnionInput> unions, string source, out byte[] assembly)
    {
        assembly = Array.Empty<byte>();
        if (funcs.Count == 0)
            return false;

        var builder = new PersistedAssemblyBuilder(new AssemblyName(assemblyName), typeof(object).Assembly);
        var module = builder.DefineDynamicModule(assemblyName);

        // PASS 0: define every user enum as a module-level i4-underlying enum type, BEFORE the Program type and the
        // function signatures (pass 1) so a function can use an enum as a param/return/local type and resolve its
        // members. The EnumBuilder is its own CLR Type; it is referenced (un-finalized) throughout passes 1-2 and
        // finalized (CreateType) just before the Program type — the same ordering proven by the de-risking spike.
        var enumRegistry = new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal);
        var enumBuilders = new EnumBuilder[enums.Count];
        for (var e = 0; e < enums.Count; e++)
        {
            var en = enums[e];
            var eb = module.DefineEnum(en.Name, TypeAttributes.Public, typeof(int));
            var constants = new Dictionary<string, int>(StringComparer.Ordinal);
            for (var m = 0; m < en.MemberNames.Length; m++)
            {
                eb.DefineLiteral(en.MemberNames[m], en.MemberValues[m]);
                // A duplicate member name within one enum is malformed — decline the whole program.
                if (!constants.TryAdd(en.MemberNames[m], en.MemberValues[m]))
                    return false;
            }
            enumBuilders[e] = eb;
            // A duplicate enum name is an ambiguous type — decline rather than silently pick one.
            if (!enumRegistry.TryAdd(en.Name, new ColumnarEnumDef(eb, constants)))
                return false;
        }

        // Union registries — declared empty here (populated in the union PASS below, after structs) so the struct/
        // function type-resolution calls can reference them. `unionCaseRegistry` is keyed by qualified "Union.Case".
        var unionRegistry = new Dictionary<string, ColumnarUnionDef>(StringComparer.Ordinal);
        var unionCaseRegistry = new Dictionary<string, ColumnarUnionCaseDef>(StringComparer.Ordinal);
        var unionBaseBuilders = new List<TypeBuilder>();
        var unionCaseBuilders = new List<TypeBuilder>();

        // PASS 0 (structs): define every user struct as a module-level VALUE TYPE — System.ValueType base, attributes
        // `Public | Sealed` with NO explicit layout (default auto), matching the C# ILCompiler's DeclareStruct exactly
        // — plus a public instance field per declared field. The FieldBuilder handles are stored in the registry and
        // used DIRECTLY for ldfld/stfld/construction (never GetField, which throws on an un-finalized TypeBuilder).
        // Field types resolve via TryResolveType (single builtins in this slice). Defined after enums so a struct may
        // have an enum-typed field; a struct-typed field resolves only if that struct was declared earlier.
        var structRegistry = new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal);
        var structBuilders = new TypeBuilder[structs.Count];
        for (var s = 0; s < structs.Count; s++)
        {
            var st = structs[s];
            // A RECORD is a reference type (class with `object` base + a public default ctor for object-init via
            // `newobj`); a struct is a `System.ValueType`-based value type. Both carry public instance fields.
            var tb = st.IsReference
                ? module.DefineType(st.Name, TypeAttributes.Public | TypeAttributes.Class, typeof(object))
                : module.DefineType(st.Name, TypeAttributes.Public | TypeAttributes.Sealed, typeof(ValueType));

            // Generic type parameters (`class Box<T>`): declared on the builder before any member signature
            // resolves (a member type naming T needs the GenericTypeParameterBuilder). Duplicate names decline.
            Dictionary<string, Type>? typeGenericParams = null;
            if (st.TypeParamNames is { Length: > 0 })
            {
                typeGenericParams = new Dictionary<string, Type>(StringComparer.Ordinal);
                var declaredParams = tb.DefineGenericParameters(st.TypeParamNames);
                for (var tp = 0; tp < declaredParams.Length; tp++)
                {
                    if (!typeGenericParams.TryAdd(st.TypeParamNames[tp], declaredParams[tp]))
                        return false;
                }
            }

            var fields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
            var instanceFieldNames = new List<string>(st.FieldNames.Length);
            var staticFieldDefs = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
            var staticFieldInits = new List<(FieldBuilder Field, Type Type, int InitKind, string InitText)>();
            for (var fi = 0; fi < st.FieldNames.Length; fi++)
            {
                // Field types resolve the type's own generic parameters FIRST (item: T), then the registries.
                var fieldTypeResolved = typeGenericParams != null
                    ? TryResolveTypeWithTypeParams(st.FieldTypeCanonicals[fi], typeGenericParams, enumRegistry, structRegistry, unionRegistry, out var fieldType)
                    : TryResolveType(st.FieldTypeCanonicals[fi], enumRegistry, structRegistry, unionRegistry, out fieldType);
                if (!fieldTypeResolved || !IsSupportedType(fieldType))
                    return false;
                // STATIC fields typed by a generic parameter decline: `static count: T` has no single CLR
                // storage across instantiations the modelled surface can express (the oracle's behavior for
                // these shapes is unprobed — decline-safe).
                if (st.FieldStaticFlags != null && st.FieldStaticFlags[fi] && fieldType is GenericTypeParameterBuilder)
                    return false;
                var isStaticField = st.FieldStaticFlags != null && st.FieldStaticFlags[fi];
                // A static and an instance field (or two fields of either kind) sharing a name is NL306 — decline.
                if (fields.ContainsKey(st.FieldNames[fi]) || staticFieldDefs.ContainsKey(st.FieldNames[fi]))
                    return false;
                if (isStaticField)
                {
                    var sfb = tb.DefineField(st.FieldNames[fi], fieldType, FieldAttributes.Public | FieldAttributes.Static);
                    staticFieldDefs[st.FieldNames[fi]] = sfb;
                    var initKind = st.FieldInitKinds != null ? st.FieldInitKinds[fi] : -1;
                    if (initKind >= 0)
                        staticFieldInits.Add((sfb, fieldType, initKind, st.FieldInitTexts![fi]!));
                    continue;
                }
                // An INSTANCE field initializer is not modelled (the kernel declines it; defensive here).
                if (st.FieldInitKinds != null && st.FieldInitKinds[fi] >= 0)
                    return false;
                var fb = tb.DefineField(st.FieldNames[fi], fieldType, FieldAttributes.Public);
                fields[st.FieldNames[fi]] = fb;
                instanceFieldNames.Add(st.FieldNames[fi]);
            }
            // A value-type struct needs at least one INSTANCE field (a zero-size value type is a CLR layout edge
            // case — the same rule the adapter applies to fully fieldless structs; statics do not give it a size).
            if (!st.IsReference && instanceFieldNames.Count == 0)
                return false;
            // STATIC FIELD INITIALIZERS run in the type's .cctor, in declaration order (C# static-initializer
            // semantics). Only single-token literals are modelled (the kernel guarantees it); the literal must
            // agree with the declared field type — a mismatch declines (the oracle's implicit conversions are not
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
            structBuilders[s] = tb;
            var newDef = new ColumnarStructDef(tb, instanceFieldNames.ToArray(), fields, st.IsReference, st.IsRecord)
            {
                GenericParameters = typeGenericParams,
            };
            foreach (var (sfName, sfBuilder) in staticFieldDefs)
                newDef.StaticFields[sfName] = sfBuilder;
            if (!structRegistry.TryAdd(st.Name, newDef))
                return false; // a duplicate struct name is an ambiguous type.
        }

        // PASS 0a' (base classes): resolve each `class D: Base` base name and re-parent the TypeBuilder. Only a
        // CLASS (reference type) may inherit, and only from another declared CLASS — a base on a value type, a
        // value-type/enum/union/unknown base name, and an inheritance CYCLE all decline (the N# pipeline rejects
        // each: "only classes and interfaces can appear in a base list" / unknown type). The base may be declared
        // before OR after the derived class in source (forward base references are legal); finalization below
        // orders CreateType base-before-derived by chain depth.
        for (var s = 0; s < structs.Count; s++)
        {
            var baseName = structs[s].BaseName;
            if (baseName == null)
                continue;
            var def = structRegistry[structs[s].Name];
            if (!def.IsReference)
                return false; // a value-type struct cannot inherit.
            if (def.IsRecord)
                return false; // record inheritance is unmodelled — only a CLASS may inherit.
            if (!structRegistry.TryGetValue(baseName, out var baseDef) || !baseDef.IsReference || baseDef == def)
                return false; // unknown / non-class / self base.
            if (baseDef.IsRecord)
                return false; // a RECORD can never be a base type (the oracle emits records SEALED).
            def.BaseDef = baseDef;
            def.Builder.SetParent(baseDef.Builder);
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
        // OVERLOADS by distinct PARAM COUNT (a same-arity static overload set declines — same rule as constructor
        // overloads; the N# pipeline accepts type-distinguished same-arity sets, so declining is the safe side).
        // A static and an instance member sharing a name is NL306 in the N# binder — decline. The builders + param
        // types are stored for call resolution; bodies are emitted in PASS 2.
        var structMethodJobs = new List<(ColumnarStructDef Struct, ColumnarFunctionInput Method, MethodBuilder Builder, Type ReturnType, Dictionary<string, int> Ordinals, Dictionary<string, Type> ParamTypes, bool IsStatic)>();
        for (var s = 0; s < structs.Count; s++)
        {
            var def = structRegistry[structs[s].Name];
            // Reference-type (record/class) instance methods are supported: the body emit (bare field -> `ldarg.0;
            // ldfld`) is identical to a value type's (ldfld works on both a managed pointer and an object ref), and
            // the instance CALL branches on IsReference (ldloc + callvirt for a ref receiver vs ldloca + call for a
            // value receiver) — see TryEmitInstanceCall. Slice-1a methods READ fields (no field WRITE in a body yet).
            foreach (var m in structs[s].Methods)
            {
                // A GENERIC method on a user type (`func With<U>(...)` in a type body) is not modelled — the
                // oracle itself fails on them (probe B12: "Operation is not valid..."), so decline both the
                // instance and static forms.
                if (m.TypeParamNames.Length > 0)
                    return false;
                // A method whose name collides with a FIELD (instance or static) is rejected by the N# binder
                // (NL306 — a name must be unique within the struct scope), so decline to keep the columnar path
                // from accepting a program the language refuses.
                if (def.Fields.ContainsKey(m.Name) || def.StaticFields.ContainsKey(m.Name))
                    return false;
                if (m.IsStatic)
                {
                    // A static method sharing its name with an INSTANCE method (NL306) declines; vice versa below.
                    if (def.Methods.ContainsKey(m.Name))
                        return false;
                    // STATIC methods on a GENERIC type decline this slice: a static member's CLR identity is
                    // per-INSTANTIATION (Box<int>.M vs Box<string>.M), and the columnar static chain-walk
                    // machinery is keyed by open builders — closed-static semantics are unprobed.
                    if (def.GenericParameters != null)
                        return false;
                    Type sReturn;
                    if (m.ReturnCanonical == "void")
                        sReturn = typeof(void);
                    else if (!TryResolveType(m.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out sReturn) || !IsSupportedType(sReturn))
                        return false;
                    // No implicit `this`: param ordinals are NOT shifted (arg 0 is the first parameter).
                    var sParamTypes = new Type[m.ParamNames.Length];
                    var sOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                    var sParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                    for (var i = 0; i < m.ParamNames.Length; i++)
                    {
                        if (!TryResolveType(m.ParamCanonicals[i], enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedType(pt))
                            return false;
                        sParamTypes[i] = pt;
                        sOrdinals[m.ParamNames[i]] = i;
                        sParamTypeMap[m.ParamNames[i]] = pt;
                    }
                    if (!def.StaticMethods.TryGetValue(m.Name, out var overloads))
                    {
                        overloads = new List<(MethodBuilder, Type[], Type)>();
                        def.StaticMethods[m.Name] = overloads;
                    }
                    // Overloads resolve by ARG COUNT (see the call sites), so two same-arity overloads would be
                    // ambiguous there — decline the set (the C# fallback handles type-distinguished overloads).
                    foreach (var (_, existingParams, _) in overloads)
                    {
                        if (existingParams.Length == sParamTypes.Length)
                            return false;
                    }
                    var smb = def.Builder.DefineMethod(m.Name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig, sReturn, sParamTypes);
                    overloads.Add((smb, sParamTypes, sReturn));
                    structMethodJobs.Add((def, m, smb, sReturn, sOrdinals, sParamTypeMap, true));
                    continue;
                }
                if (m.ReturnCanonical == "void")
                    return false; // void instance methods are a later slice.
                // An instance method sharing its name with a STATIC method is NL306 — decline (the static may have
                // been declared first when source order is static-then-instance).
                if (def.StaticMethods.ContainsKey(m.Name))
                    return false;
                if (!TryResolveMemberType(m.ReturnCanonical, def, enumRegistry, structRegistry, unionRegistry, out var mReturn) || !IsSupportedType(mReturn))
                    return false;
                // Resolve param types; ordinals shift by +1 because arg 0 is the value-type `this`.
                var mParamTypes = new Type[m.ParamNames.Length];
                var mOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                var mParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                for (var i = 0; i < m.ParamNames.Length; i++)
                {
                    if (!TryResolveMemberType(m.ParamCanonicals[i], def, enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedType(pt))
                        return false;
                    mParamTypes[i] = pt;
                    mOrdinals[m.ParamNames[i]] = i + 1;
                    mParamTypeMap[m.ParamNames[i]] = pt;
                }
                var mb = def.Builder.DefineMethod(m.Name, MethodAttributes.Public | MethodAttributes.HideBySig, mReturn, mParamTypes);
                if (!def.Methods.TryAdd(m.Name, (mb, mParamTypes, mReturn)))
                    return false; // a duplicate method name on one struct is an overload set the slice does not model.
                structMethodJobs.Add((def, m, mb, mReturn, mOrdinals, mParamTypeMap, false));
            }
        }

        // PASS 0b' (property accessors): declare each reference-type's computed property as a `get_Name` instance
        // method (no params, returning the property type) and — when the property has a setter — a `set_Name` method
        // (one param "value": property type, returning void). The accessor bodies read/write fields exactly like a
        // method, so they emit via the same structMethodJobs path in PASS 2. The property is registered for
        // `receiver.Name` read (case 8 -> callvirt get_Name) + `receiver.Name = v` write (case 23 -> callvirt
        // set_Name). Declines: a value-type property (deferred), a property name colliding with a field/method/another
        // property, or a synthesized get_Name/set_Name colliding with a user method of that name.
        for (var s = 0; s < structs.Count; s++)
        {
            if (structs[s].Properties.Count == 0)
                continue;
            var def = structRegistry[structs[s].Name];
            if (!def.IsReference)
                return false; // value-type properties are deferred.
            foreach (var prop in structs[s].Properties)
            {
                if (def.Fields.ContainsKey(prop.Name) || def.StaticFields.ContainsKey(prop.Name) || def.Methods.ContainsKey(prop.Name) || def.StaticMethods.ContainsKey(prop.Name) || def.Properties.ContainsKey(prop.Name) || def.StaticProperties.ContainsKey(prop.Name))
                    return false; // a property colliding with a field/method/another property is a duplicate member.
                // A synthesized accessor name ("get_Name"/"set_Name") must not collide with a user method of the same
                // name (the N# pipeline accepts them as distinct symbols, but two CLR methods of identical signature
                // would throw at CreateType) — decline so columnar never emits the duplicate.
                if (def.Methods.ContainsKey("get_" + prop.Name) || def.StaticMethods.ContainsKey("get_" + prop.Name)
                    || (prop.Setter != null && (def.Methods.ContainsKey("set_" + prop.Name) || def.StaticMethods.ContainsKey("set_" + prop.Name))))
                    return false;
                if (!TryResolveMemberType(prop.TypeCanonical, def, enumRegistry, structRegistry, unionRegistry, out var propType) || !IsSupportedType(propType))
                    return false;
                // STATIC properties on a GENERIC type decline (per-instantiation static semantics, unprobed —
                // same rule as static methods/fields above).
                if (prop.IsStatic && def.GenericParameters != null)
                    return false;
                if (prop.IsStatic)
                {
                    // STATIC property: CLR-static accessors — get_Name takes no args at all; set_Name's `value`
                    // is arg 0 (no implicit `this`). The bodies are STATIC contexts (PASS 2 runs them with
                    // `_currentStruct` null), so a bare backing-field reference inside an accessor declines
                    // exactly where the N# pipeline reports NL103 — the backing access must be `TypeName.field`.
                    var staticGetter = def.Builder.DefineMethod("get_" + prop.Name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig | MethodAttributes.SpecialName, propType, Type.EmptyTypes);
                    structMethodJobs.Add((def, prop.Getter, staticGetter, propType, new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), true));
                    MethodBuilder? staticSetter = null;
                    if (prop.Setter != null)
                    {
                        staticSetter = def.Builder.DefineMethod("set_" + prop.Name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig | MethodAttributes.SpecialName, typeof(void), new[] { propType });
                        var staticSetOrdinals = new Dictionary<string, int>(StringComparer.Ordinal) { ["value"] = 0 };
                        var staticSetParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal) { ["value"] = propType };
                        structMethodJobs.Add((def, prop.Setter, staticSetter, typeof(void), staticSetOrdinals, staticSetParamTypes, true));
                    }
                    def.StaticProperties[prop.Name] = (staticGetter, staticSetter, propType);
                    continue;
                }
                var getter = def.Builder.DefineMethod("get_" + prop.Name, MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName, propType, Type.EmptyTypes);
                structMethodJobs.Add((def, prop.Getter, getter, propType, new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal), false));
                MethodBuilder? setter = null;
                if (prop.Setter != null)
                {
                    setter = def.Builder.DefineMethod("set_" + prop.Name, MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName, typeof(void), new[] { propType });
                    // The setter's `value` parameter is arg 1 (arg 0 = this); its body assigns fields via the
                    // reference-type field-write path. Emitted via structMethodJobs (a void method).
                    var setOrdinals = new Dictionary<string, int>(StringComparer.Ordinal) { ["value"] = 1 };
                    var setParamTypes = new Dictionary<string, Type>(StringComparer.Ordinal) { ["value"] = propType };
                    structMethodJobs.Add((def, prop.Setter, setter, typeof(void), setOrdinals, setParamTypes, false));
                }
                def.Properties[prop.Name] = (getter, setter, propType);
            }
        }

        // PASS 0b'' (inherited-member shadowing): with every field/method/property declared, decline any member of
        // a derived type whose name SHADOWS an inherited member — EXCEPT a method over an inherited METHOD of the
        // SAME kind (instance over instance, static over static), which the N# pipeline accepts as hiding (the
        // nearest declaration wins; chain-walking resolution models exactly that — static hiding pinned by the
        // oracle's ILCompiler_StaticMethodHidingBindsNearestDeclaration). Field-over-anything,
        // method-over-field/property, property-over-anything, and MIXED static/instance method shadowing is NOT
        // verified against the oracle — decline to the C# path rather than risk a resolution divergence.
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
                // unverified against the oracle — decline every shape (unlike methods, no static-member hiding
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

        // PASS 0c (constructors): declare each reference-type's user constructor(s). A constructor is a nameless,
        // void-returning member whose body assigns fields; `this` is arg 0 so user param ordinals shift by +1. Slice
        // scope: one or more OVERLOADED constructors on a REFERENCE type (class/record), optionally with a `: this(...)`
        // (same-type) or `: base(...)` (declared base class) chaining initializer. Overload resolution at construction
        // is by PARAM COUNT (see case 15). A value-type struct constructor declines. The ConstructorBuilder + its
        // param types are stored for positional-construction resolution; the body (+ chained call) is emitted
        // (+ validated) in PASS 2.
        var structCtorJobs = new List<(ColumnarStructDef Struct, ColumnarConstructorInput Ctor, ConstructorBuilder Builder, Dictionary<string, int> Ordinals, Dictionary<string, Type> ParamTypes)>();
        for (var s = 0; s < structs.Count; s++)
        {
            if (structs[s].Constructors.Count == 0)
                continue;
            var def = structRegistry[structs[s].Name];
            foreach (var ctor in structs[s].Constructors)
            {
                if (ctor.ChainInitKind == 2 && def.BaseDef == null)
                    return false; // a `: base(...)` initializer requires a declared (modelled) base class.
                // VALUE-TYPE ctor chains decline: probing the oracle showed `new S()` with a declared
                // parameterless `: this(...)` ctor ZERO-INITS instead of running the user ctor (an oracle
                // defect recorded for a future fix bundle) — decline-safe until those semantics are fixed
                // and pinned. Positional value-type ctors (the supported shape) have no chain.
                if (!def.IsReference && ctor.ChainInitKind != 0)
                    return false;
                // A PARAMETERLESS value-type user ctor is the same hazard (`new S()` zero-inits, bypassing
                // it) — decline so columnar never emits a ctor the construction site won't call.
                if (!def.IsReference && ctor.Body.ParamNames.Length == 0)
                    return false;
                var cParamTypes = new Type[ctor.Body.ParamNames.Length];
                var cOrdinals = new Dictionary<string, int>(StringComparer.Ordinal);
                var cParamTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
                for (var i = 0; i < ctor.Body.ParamNames.Length; i++)
                {
                    if (!TryResolveMemberType(ctor.Body.ParamCanonicals[i], def, enumRegistry, structRegistry, unionRegistry, out var pt) || !IsSupportedType(pt))
                        return false;
                    cParamTypes[i] = pt;
                    cOrdinals[ctor.Body.ParamNames[i]] = i + 1;
                    cParamTypeMap[ctor.Body.ParamNames[i]] = pt;
                }
                // A constructor whose param-type signature DUPLICATES an already-declared one is a duplicate member
                // the N# binder rejects — decline rather than emit two ctors with the same signature.
                foreach (var (_, existingParamTypes) in def.Constructors)
                {
                    if (existingParamTypes.Length != cParamTypes.Length)
                        continue;
                    var sameSignature = true;
                    for (var i = 0; i < cParamTypes.Length; i++)
                    {
                        if (existingParamTypes[i] != cParamTypes[i]) { sameSignature = false; break; }
                    }
                    if (sameSignature)
                        return false;
                }
                var cb = def.Builder.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, cParamTypes);
                def.Constructors.Add((cb, cParamTypes));
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
                if (!st.IsReference || st.Constructors.Count > 0)
                    continue;
                var def = structRegistry[st.Name];
                if (def.BaseDef == null)
                {
                    def.DefaultCtor = def.Builder.DefineDefaultConstructor(MethodAttributes.Public);
                    continue;
                }
                var baseCtorTarget = ResolveParameterlessCtor(def.BaseDef);
                if (baseCtorTarget == null)
                    return false; // base has only parameterized ctors — an implicit chain is impossible.
                var dcb = def.Builder.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Type.EmptyTypes);
                var dcil = dcb.GetILGenerator();
                dcil.Emit(OpCodes.Ldarg_0);
                dcil.Emit(OpCodes.Call, baseCtorTarget);
                dcil.Emit(OpCodes.Ret);
                def.DefaultCtor = dcb;
            }
        }

        // PASS 0 (unions): define every user union — an ABSTRACT base class plus one SEALED nested case class per
        // case — mirroring the C# ILCompiler's DeclareUnion. The base has a protected (Family) parameterless ctor
        // chaining to object::.ctor; each case has a public parameterless ctor chaining to the base ctor, plus a
        // public field per case field. These trivial ctor bodies are emitted INLINE here (no user code), exactly as
        // the de-risking spike proved. Case fields resolve via TryResolveType (enums/structs/earlier-unions in scope).
        // Defined after structs so a case field may be an enum or struct; nested case types are finalized BEFORE their
        // base (deepest-first — see the finalization block below).
        for (var u = 0; u < unions.Count; u++)
        {
            var un = unions[u];
            var baseTb = module.DefineType(un.Name, TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.Abstract, typeof(object));
            var baseCtor = baseTb.DefineConstructor(MethodAttributes.Family, CallingConventions.Standard, Type.EmptyTypes);
            var bcil = baseCtor.GetILGenerator();
            bcil.Emit(OpCodes.Ldarg_0);
            bcil.Emit(OpCodes.Call, typeof(object).GetConstructor(Type.EmptyTypes)!);
            bcil.Emit(OpCodes.Ret);

            var unionDef = new ColumnarUnionDef(baseTb);
            unionBaseBuilders.Add(baseTb);
            if (!unionRegistry.TryAdd(un.Name, unionDef))
                return false; // a duplicate union name is an ambiguous type.

            for (var c = 0; c < un.CaseNames.Length; c++)
            {
                var caseName = un.CaseNames[c];
                var caseTb = baseTb.DefineNestedType(caseName, TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed, baseTb);
                var caseFieldNames = un.CaseFieldNames[c];
                var caseFieldTypes = un.CaseFieldTypeCanonicals[c];
                var caseFields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
                for (var fi = 0; fi < caseFieldNames.Length; fi++)
                {
                    if (!TryResolveType(caseFieldTypes[fi], enumRegistry, structRegistry, unionRegistry, out var caseFieldType) || !IsSupportedType(caseFieldType))
                        return false;
                    var cfb = caseTb.DefineField(caseFieldNames[fi], caseFieldType, FieldAttributes.Public);
                    if (!caseFields.TryAdd(caseFieldNames[fi], cfb))
                        return false; // a duplicate field name within one case is malformed.
                }
                var caseCtor = caseTb.DefineConstructor(MethodAttributes.Public, CallingConventions.Standard, Type.EmptyTypes);
                var ccil = caseCtor.GetILGenerator();
                ccil.Emit(OpCodes.Ldarg_0);
                ccil.Emit(OpCodes.Call, baseCtor); // chain to the abstract base's ctor.
                ccil.Emit(OpCodes.Ret);

                var caseDef = new ColumnarUnionCaseDef(caseTb, caseCtor, caseFieldNames, caseFields, baseTb);
                var qualified = un.Name + "." + caseName;
                if (!unionDef.Cases.TryAdd(qualified, caseDef) || !unionCaseRegistry.TryAdd(qualified, caseDef))
                    return false; // a duplicate case name within one union is malformed.
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
        var siblings = new Dictionary<string, (MethodInfo Method, Type[] ParamTypes, Type ReturnType, Type[] TypeParams, int[] SpecialConstraints, Type?[] BaseConstraints)>(StringComparer.Ordinal);
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            // A GENERIC function (`func Identity<T>(x: T): T`) declares a REAL CLR generic method — one
            // definition with open type parameters, instantiated per call site via MakeGenericMethod — exactly
            // the oracle's primary strategy. DefineGenericParameters must run BEFORE the signature is set so the
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
                    // A duplicate type-parameter name is malformed — decline.
                    if (!typeParamMap.TryAdd(fn.TypeParamNames[g], gpBuilders[g]))
                        return false;
                    fnTypeParams[g] = gpBuilders[g];
                }
                // Generic CONSTRAINTS (`where T: Base, new()` — D-17b): special flags map onto
                // GenericParameterAttributes and the single type constraint onto SetBaseTypeConstraint,
                // mirroring the oracle's ApplyGenericConstraints (the `struct` flag implies the default-ctor
                // flag, exactly as the oracle sets them; constraints persist and load — spike-proven). Applied
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
            if (fn.ReturnCanonical == "void")
                returnType = typeof(void);
            else if (typeParamMap != null)
            {
                if (!TryResolveTypeWithTypeParams(fn.ReturnCanonical, typeParamMap, enumRegistry, structRegistry, unionRegistry, out returnType)
                    || !(returnType.IsGenericParameter || (returnType.IsSZArray && returnType.GetElementType()!.IsGenericParameter) || IsSupportedType(returnType)))
                    return false;
            }
            else if (!TryResolveType(fn.ReturnCanonical, enumRegistry, structRegistry, unionRegistry, out returnType) || !IsSupportedType(returnType))
                return false;
            var paramTypes = new Type[fn.ParamNames.Length];
            var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
            var paramTypeMap = new Dictionary<string, Type>(StringComparer.Ordinal);
            for (var i = 0; i < fn.ParamNames.Length; i++)
            {
                Type pt;
                if (typeParamMap != null)
                {
                    if (!TryResolveTypeWithTypeParams(fn.ParamCanonicals[i], typeParamMap, enumRegistry, structRegistry, unionRegistry, out pt)
                        || !(pt.IsGenericParameter || (pt.IsSZArray && pt.GetElementType()!.IsGenericParameter) || IsSupportedType(pt)))
                        return false;
                }
                else if (!TryResolveType(fn.ParamCanonicals[i], enumRegistry, structRegistry, unionRegistry, out pt) || !IsSupportedType(pt))
                    return false;
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
                    fn.Name, MethodAttributes.Public | MethodAttributes.Static, returnType, paramTypes);
            }
            ordinalsByFunc[f] = ordinals;
            paramTypesByFunc[f] = paramTypeMap;
            returnTypeByFunc[f] = returnType;
            // A duplicate top-level function name is an overload set the spike does not model — decline the
            // whole program rather than silently pick one (a real call would be ambiguous).
            if (!siblings.TryAdd(fn.Name, (methods[f], paramTypes, returnType, fnTypeParams, fnSpecialConstraints, fnBaseConstraints)))
                return false;
        }

        // Pass 2: emit each body into its declared method's IL stream.
        for (var f = 0; f < funcs.Count; f++)
        {
            var fn = funcs[f];
            var il = methods[f].GetILGenerator();
            var emitter = new ColumnarIlEmitter(
                fn.Kinds, fn.ValueStarts, fn.ValueLengths, fn.ChildStart, fn.ChildCount, fn.ChildIndices,
                source, ordinalsByFunc[f], paramTypesByFunc[f], returnTypeByFunc[f], il, siblings, enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, currentStruct: null);
            if (!emitter.EmitBody(fn.BodyRoot, returnTypeByFunc[f] == typeof(void)))
                return false;
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
            var emitter = new ColumnarIlEmitter(
                job.Method.Kinds, job.Method.ValueStarts, job.Method.ValueLengths, job.Method.ChildStart, job.Method.ChildCount, job.Method.ChildIndices,
                source, job.Ordinals, job.ParamTypes, job.ReturnType, mil, siblings, enumRegistry, structRegistry, unionRegistry, unionCaseRegistry,
                currentStruct: job.IsStatic ? null : job.Struct, enclosingType: job.Struct);
            // A property SETTER body is void (it assigns a field and falls through); a method/getter is a value
            // function (always-returns). EmitBody handles both — pass isVoid by the job's declared return type.
            if (!emitter.EmitBody(job.Method.BodyRoot, job.ReturnType == typeof(void)))
                return false;
        }

        // Emit user-constructor bodies. Each chains to the base `object` ctor first (`ldarg.0; call object::.ctor()`),
        // then emits the ctor body (field assignments via the reference-type field-write path), with `_currentStruct`
        // set and the ctor's param ordinals (arg 0 = `this`). The body is VOID (no return value), so EmitBody(isVoid:
        // true) appends a trailing `ret` where control falls through.
        var objectCtor = typeof(object).GetConstructor(Type.EmptyTypes)!;
        foreach (var job in structCtorJobs)
        {
            var cil = job.Builder.GetILGenerator();
            var emitter = new ColumnarIlEmitter(
                job.Ctor.Body.Kinds, job.Ctor.Body.ValueStarts, job.Ctor.Body.ValueLengths, job.Ctor.Body.ChildStart, job.Ctor.Body.ChildCount, job.Ctor.Body.ChildIndices,
                source, job.Ordinals, job.ParamTypes, typeof(void), cil, siblings, enumRegistry, structRegistry, unionRegistry, unionCaseRegistry, job.Struct,
                isConstructorBody: true);
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
            }
            else if (job.Struct.IsReference)
            {
                // A non-chaining ctor must (1) contain no `return` (NL103) and (2) assign every OWN field (NL304 —
                // inherited fields are the base ctor's responsibility). Validate BEFORE emitting — declining here
                // discards the whole assembly (→ C# path). Then chain implicitly: to the declared base's
                // parameterless ctor when the type has one (decline when the base offers only parameterized ctors —
                // ECMA-335 requires chaining to the DIRECT base, and the N# pipeline rejects the implicit chain),
                // else to the `object` ctor.
                if (!emitter.IsValidReferenceCtorBody(job.Ctor.Body.BodyRoot))
                    return false;
                if (job.Struct.BaseDef != null)
                {
                    var baseParameterless = ResolveParameterlessCtor(job.Struct.BaseDef);
                    if (baseParameterless == null)
                        return false; // base has only parameterized ctors — `: base(...)` is required.
                    cil.Emit(OpCodes.Ldarg_0);
                    cil.Emit(OpCodes.Call, baseParameterless);
                }
                else
                {
                    cil.Emit(OpCodes.Ldarg_0);
                    cil.Emit(OpCodes.Call, objectCtor);
                }
            }
            else
            {
                // VALUE-TYPE ctor: no base chain (value types don't chain), and NO all-fields-assigned
                // validation — the oracle ACCEPTS partial assignment in struct ctors (probed: unassigned
                // fields keep the zero-initialized value). Only `return` is forbidden (NL103).
                if (emitter.ContainsReturnStatement(job.Ctor.Body.BodyRoot))
                    return false;
            }
            if (!emitter.EmitBody(job.Ctor.Body.BodyRoot, isVoid: true))
                return false;
        }

        // Finalize the enum and struct types before the Program type (the spike's ordering). Each enum member
        // literal / struct field is already defined, so CreateType bakes the type's metadata; the methods that
        // reference the un-finalized builders resolve to the finalized types at Save.
        foreach (var eb in enumBuilders)
            eb.CreateType();
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
        // Union types: a NESTED case must be finalized BEFORE its enclosing base (deepest-first), matching the C#
        // ILCompiler's OrderTypeBuildersByDescendingTypeKeyDepth — so create every case, then every base.
        foreach (var caseTb in unionCaseBuilders)
            caseTb.CreateType();
        foreach (var baseTb in unionBaseBuilders)
            baseTb.CreateType();

        type.CreateType();
        using var stream = new MemoryStream();
        builder.Save(stream);
        assembly = stream.ToArray();
        return true;
    }

    // Emit a function body. A VALUE function (non-void) must always-return on every path (NL305) — else the IL
    // would fall off the end with no `ret`; decline it to the C# analyzer. A VOID function (procedure) need not
    // always-return: emit the body, then a trailing `ret` IFF control can fall through to the method end (when
    // the body already always-returns via value-less `return`s, no trailing `ret` is emitted, so there is no
    // unreachable code).
    private bool EmitBody(int bodyRoot, bool isVoid)
    {
        if (!isVoid)
            return AlwaysReturns(bodyRoot) && EmitStatement(bodyRoot);
        var fallsThrough = !AlwaysReturns(bodyRoot);
        if (!EmitStatement(bodyRoot))
            return false;
        if (fallsThrough)
            _il.Emit(OpCodes.Ret);
        return true;
    }

    private bool EmitStatement(int idx)
    {
        switch (_kinds[idx])
        {
            case 25: // Block — emit each statement in order.
            {
                // Block scoping: a `:=` local declared in this block leaves scope when the block ends, so a
                // later reference (e.g. a loop-body local read after the loop) correctly resolves to nothing
                // and declines, rather than reading a method-level slot that may be unassigned (invalid IL).
                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    var child = Child(idx, n);
                    if (!EmitStatement(child))
                        return false;
                    // A statement that unconditionally transfers control — always-returns, or a direct
                    // `break`/`continue` — must be the LAST in its block; anything after it is unreachable (an
                    // NL312 diagnostic). Decline rather than emit code after the transfer `ret`/`br`, keeping the
                    // C# analyzer/codegen authoritative. (A break/continue nested inside an `if` is conditional,
                    // so only a DIRECT break/continue child counts here.)
                    var transfers = AlwaysReturns(child) || _kinds[child] == 21 || _kinds[child] == 22;
                    if (transfers && n != _childCount[idx] - 1)
                        return false;
                }

                var blockLocals = new List<string>();
                foreach (var name in _locals.Keys)
                {
                    if (!outerLocals.Contains(name))
                        blockLocals.Add(name);
                }

                foreach (var name in blockLocals)
                    _locals.Remove(name);
                return true;
            }

            case 20: // Return [value?] — in a VOID function a value-less `return` emits a bare `ret`; in a VALUE
                     // function a value is REQUIRED (a value-less `ret` with an empty stack is invalid IL) and its
                     // type must match the declared return type. A value-bearing `return` in a void function, or a
                     // value-less one in a value function, declines (mismatched arity).
                if (_returnType == typeof(void))
                {
                    if (_childCount[idx] != 0)
                        return false;
                    _il.Emit(OpCodes.Ret);
                    return true;
                }
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0), out var retType) || retType != _returnType)
                    return false;
                _il.Emit(OpCodes.Ret);
                return true;

            case 24: // VariableDeclaration (`:=`): emit the initializer, declare a local of the initializer's
            {        // type (inferred), store into it.
                var name = Text(idx);
                // Decline a local that shadows a parameter or redeclares a local: N# treats shadowing as a
                // diagnostic (and a same-`:=` redeclaration as an error), which the spike does not model —
                // declining keeps the C# analyzer authoritative rather than silently compiling it.
                if (_paramOrdinals.ContainsKey(name) || _locals.ContainsKey(name))
                    return false;
                // A local of an open generic-parameter type (`y := x` inside a generic function, x: T) is legal —
                // DeclareLocal over a GenericTypeParameterBuilder works (spike-proven) and loads/stores/returns
                // of T flow by reference equality. T[] locals likewise.
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0), out var initType)
                    || !(initType.IsGenericParameter || (initType.IsSZArray && initType.GetElementType()!.IsGenericParameter) || IsSupportedType(initType)))
                    return false;
                var local = _il.DeclareLocal(initType);
                _il.Emit(OpCodes.Stloc, local);
                _locals[name] = local;
                return true;
            }

            case 27: // If [condition, then, else?] — general form covering all four then/else
            {        // fall-through-vs-return combinations, with a fall-through merge label.
                var childCount = _childCount[idx];
                if (childCount != 2 && childCount != 3)
                    return false;
                if (!EmitCondition(Child(idx, 0)))
                    return false;

                var thenStmt = Child(idx, 1);
                var elseLabel = _il.DefineLabel();
                _il.Emit(OpCodes.Brfalse, elseLabel);   // condition false -> else branch (or the merge end if no else)

                // then-branch. Scope its `:=` locals so a BRACELESS `:=` does not leak past the if (a Block
                // then-branch already self-scopes; this also covers the braceless single-statement form).
                var beforeThen = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(thenStmt))
                    return false;
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
                    return false;
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
                     // or a sibling/BCL call whose non-void result is discarded). Compound ops (`+=`) decline.
                var expr = Child(idx, 0);

                if (_kinds[expr] == 9) // a bare call statement.
                {
                    // Emit the call. A void call (e.g. Array.Fill) leaves nothing on the stack; a NON-void call
                    // leaves its result, which is unused in statement position — discard it with `pop` (exactly
                    // what the C# path emits for a discarded call result, so the side effects + result are
                    // identical). This is the `helper(args)`-as-statement idiom (e.g. LinterImports.nl clearing
                    // flags for its side effect and ignoring the returned count).
                    if (!EmitExpression(expr, out var callType))
                        return false;
                    if (callType != typeof(void))
                        _il.Emit(OpCodes.Pop);
                    return true;
                }

                if (_kinds[expr] != 14 || Text(expr) != "=")
                    return false;
                var target = Child(expr, 0);

                if (_kinds[target] == 10) // array element write: a[i] = value
                {
                    // Stelem order is (array, index, value): emit the array ref, the int index, the value, store.
                    if (!EmitExpression(Child(target, 0), out var arrayType) || !arrayType.IsSZArray)
                        return false;
                    var elementType = arrayType.GetElementType()!;
                    if (!EmitExpression(Child(target, 1), out var indexType) || indexType != typeof(int))
                        return false;
                    if (!EmitExpression(Child(expr, 1), out var elementValueType) || elementValueType != elementType)
                        return false;
                    if (elementType == typeof(int)) _il.Emit(OpCodes.Stelem_I4);
                    else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Stelem_I8);
                    else if (elementType == typeof(char)) _il.Emit(OpCodes.Stelem_I2);
                    else if (elementType == typeof(double)) _il.Emit(OpCodes.Stelem_R8);
                    else if (elementType == typeof(float)) _il.Emit(OpCodes.Stelem_R4);
                    else if (elementType == typeof(string)) _il.Emit(OpCodes.Stelem_Ref);
                    else return false; // other element types arrive with their type slices.
                    return true;
                }

                if (_kinds[target] == 8) // a member-access target: a class PROPERTY setter OR a value-type struct field.
                {
                    var fieldReceiver = Child(target, 0);
                    var memberName = Text(target);
                    // STATIC member write `TypeName.member = value`: the receiver names a registered TYPE (not
                    // shadowed by a local/param/sibling) — chain-walk its static FIELDS (`<value>; stsfld`) then
                    // static PROPERTIES (`<value>; call set_Name`; a get-only static property declines). A
                    // type-name receiver whose member is NEITHER declines (a type name is not a value).
                    if (_kinds[fieldReceiver] == 6)
                    {
                        var staticRecvName = Text(fieldReceiver);
                        if (!_locals.ContainsKey(staticRecvName) && !_paramOrdinals.ContainsKey(staticRecvName) && !_siblings.ContainsKey(staticRecvName)
                            && _structRegistry.TryGetValue(staticRecvName, out var staticWriteOwner))
                        {
                            if (TryFindStaticFieldOnChain(staticWriteOwner, memberName, out var staticFieldWrite))
                            {
                                if (!EmitExpression(Child(expr, 1), out var staticValueType) || staticValueType != staticFieldWrite.FieldType)
                                    return false;
                                _il.Emit(OpCodes.Stsfld, staticFieldWrite);
                                return true;
                            }
                            if (TryFindStaticPropertyOnChain(staticWriteOwner, memberName, out var staticPropWrite) && staticPropWrite.Setter != null)
                            {
                                if (!EmitExpression(Child(expr, 1), out var staticPropValueType) || staticPropValueType != staticPropWrite.PropertyType)
                                    return false;
                                _il.Emit(OpCodes.Call, staticPropWrite.Setter);
                                return true;
                            }
                            return false;
                        }
                    }
                    // PROPERTY setter write `receiver.Name = value` on a reference type: emit the receiver ref, the
                    // value (type-checked against the property type), then `callvirt set_Name`. The receiver must be a
                    // bare local/param (the modelled receiver forms) of a registered reference type with a settable
                    // property `Name`. A get-only property (no setter) falls through and declines.
                    if (_kinds[fieldReceiver] == 6)
                    {
                        var recvName = Text(fieldReceiver);
                        Type? recvStaticType = null;
                        if (_locals.TryGetValue(recvName, out var recvLocalForProp))
                            recvStaticType = recvLocalForProp.LocalType;
                        else if (_paramTypes.TryGetValue(recvName, out var recvParamType))
                            recvStaticType = recvParamType;
                        if (recvStaticType is TypeBuilder)
                        {
                            foreach (var d in _structRegistry.Values)
                            {
                                if (d.Builder == recvStaticType && d.IsReference
                                    && TryFindPropertyOnChain(d, memberName, out var propWrite) && propWrite.Setter != null)
                                {
                                    if (!EmitExpression(fieldReceiver, out _))
                                        return false;
                                    if (!EmitExpression(Child(expr, 1), out var setValueType) || setValueType != propWrite.PropertyType)
                                        return false;
                                    _il.Emit(OpCodes.Callvirt, propWrite.Setter);
                                    return true;
                                }
                            }
                        }
                    }
                    // VALUE-TYPE struct field write: the receiver is a `:=` LOCAL of a registered struct type; the
                    // field is mutated IN PLACE via the local's ADDRESS (ldloca; <value>; stfld). A param receiver, a
                    // nested receiver (`p.q.X`), or a non-struct/non-field target declines (no modelled addressable
                    // storage; a RECORD field may be init-only) → C# fallback.
                    if (_kinds[fieldReceiver] != 6 || !_locals.TryGetValue(Text(fieldReceiver), out var recLocal))
                        return false;
                    ColumnarStructDef? targetStruct = null;
                    foreach (var d in _structRegistry.Values)
                    {
                        if (d.Builder == recLocal.LocalType) { targetStruct = d; break; }
                    }
                    if (targetStruct == null || targetStruct.IsReference || !targetStruct.Fields.TryGetValue(memberName, out var targetField))
                        return false;
                    _il.Emit(OpCodes.Ldloca, recLocal);
                    if (!EmitExpression(Child(expr, 1), out var fieldValueType) || fieldValueType != targetField.FieldType)
                        return false;
                    _il.Emit(OpCodes.Stfld, targetField);
                    return true;
                }

                if (_kinds[target] != 6)
                    return false;
                var targetName = Text(target);
                if (_locals.TryGetValue(targetName, out var assignTarget))
                {
                    // `local = expr` — store into the `:=` local (value type must match the local's type).
                    if (!EmitExpression(Child(expr, 1), out var valueType) || valueType != assignTarget.LocalType)
                        return false;
                    _il.Emit(OpCodes.Stloc, assignTarget);
                    return true;
                }
                if (_paramOrdinals.TryGetValue(targetName, out var paramOrdinal))
                {
                    // `param = expr` — store into the argument slot (`starg`). N# permits mutating a parameter
                    // (value params have value semantics, so the mutation is method-local, matching the C# path).
                    // The value's type must match the parameter's declared type.
                    if (!EmitExpression(Child(expr, 1), out var paramValueType) || paramValueType != _paramTypes[targetName])
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
                // variable — diverging from C#'s in-place value semantics. Struct field-mutation-in-method therefore
                // DECLINES until the call site addresses the receiver's own storage (a later slice). A class/record
                // ref is shared through the temp, so the mutation persists correctly. Resolution walks the BASE
                // chain (nearest first) so a derived member may assign an INHERITED field.
                if (_currentStruct != null && (_currentStruct.IsReference || _isConstructorBody) && TryFindFieldOnChain(_currentStruct, targetName, out var thisFieldTarget))
                {
                    _il.Emit(OpCodes.Ldarg_0);
                    if (!EmitExpression(Child(expr, 1), out var thisValueType) || thisValueType != thisFieldTarget.FieldType)
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
                    if (!EmitExpression(Child(expr, 1), out var bareStaticValueType) || bareStaticValueType != bareStaticTarget.FieldType)
                        return false;
                    _il.Emit(OpCodes.Stsfld, bareStaticTarget);
                    return true;
                }
                return false;
            }

            case 26: // While [condition, body] — emit `check: cond; brfalse end; body; [br check]; end:`. The
            {        // stack is empty at both merge labels (cond pushes a bool, brfalse pops it; the body is
                     // net-zero), so it is stack-consistent.
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
                // `break` exits to endLabel, `continue` re-tests at checkLabel; both reach their target with an
                // empty stack (the body up to the transfer is net-zero), so they are stack-consistent.
                _loopLabels.Push((endLabel, checkLabel));
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
                     // re-test), matching C# for-loop semantics. The loop's own locals (the `init` declaration's
                     // variable + any body `:=` locals) are scoped to the loop and removed at its end.
                var init = Child(idx, 0);
                var cond = Child(idx, 1);
                var incr = Child(idx, 2);
                var body = Child(idx, 3);

                // A for-body that always transfers on every path (never falls through) would make the increment +
                // back-edge unreachable (a `continue` aside) — a degenerate shape; decline it to the C# path. A
                // normal counting loop falls through, and a `continue` body still falls through on its other path.
                if (AlwaysReturns(body))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);
                if (!EmitStatement(init)) // runs once before the loop; declares the loop variable.
                    return false;

                var checkLabel = _il.DefineLabel();
                var contLabel = _il.DefineLabel();
                var endLabel = _il.DefineLabel();
                _il.MarkLabel(checkLabel);
                if (!EmitCondition(cond))
                    return false;
                _il.Emit(OpCodes.Brfalse, endLabel);

                _loopLabels.Push((endLabel, contLabel));
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
                return true;
            }

            case 29: // Foreach [collection, body] — `foreach <var> in <array> { body }` lowered to an index loop
            {        // over the array, mirroring the C# ILCompiler's EmitForeachForArray: arr := collection; i := 0;
                     // check: if i >= arr.Length goto end; <var> := arr[i]; body; cont: i = i+1; br check; end:.
                     // ARRAY collections only (others decline -> C# fallback). The var name is in the value span.
                var collectionNode = Child(idx, 0);
                var body = Child(idx, 1);
                var varName = Text(idx);

                // A body that always transfers on every path makes the increment unreachable -> decline (as for/while).
                if (AlwaysReturns(body))
                    return false;
                // The loop variable must not shadow an existing local/param (shadowing is not modelled).
                if (_locals.ContainsKey(varName) || _paramOrdinals.ContainsKey(varName))
                    return false;

                var outerLocals = new HashSet<string>(_locals.Keys, StringComparer.Ordinal);

                // Evaluate the collection; require a single-dim array of a supported element type.
                if (!EmitExpression(collectionNode, out var collectionType) || !collectionType.IsSZArray)
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
                if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                else return false;
                var loopVar = _il.DeclareLocal(elementType);
                _il.Emit(OpCodes.Stloc, loopVar);
                _locals[varName] = loopVar;

                _loopLabels.Push((endLabel, contLabel));
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
                return true;
            }

            case 30: // TupleDeconstruction [name0, ..., nameN-1, value] — `n0, n1, ... := <tuple>`. Emit the value
            {        // (a ValueTuple), store to a temp, then for each non-`_` name declare a local of the element
                     // type and store the matching ItemN. Mirrors the C# EmitTupleDeconstruction (plain path).
                var childCount = _childCount[idx];
                if (childCount < 3) // at least 2 names + the value.
                    return false;
                var nameCount = childCount - 1;
                var valueNode = Child(idx, nameCount);

                // The Go-style `name, err := ...` error path is handled specially by the C# ILCompiler
                // (EmitErrorTupleDeconstruction); decline it so the columnar backend never diverges from that path.
                if (nameCount == 2 && Text(Child(idx, 1)) == "err")
                    return false;

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
                    if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name))
                        return false; // redeclaration / shadow is not modelled (keep the C# analyzer authoritative).
                    var field = tupleType.GetField("Item" + (i + 1), BindingFlags.Public | BindingFlags.Instance);
                    if (field == null)
                        return false;
                    var nameLocal = _il.DeclareLocal(field.FieldType);
                    _il.Emit(OpCodes.Ldloca, tupleLocal); // value-type field load: address of the tuple, then ldfld.
                    _il.Emit(OpCodes.Ldfld, field);
                    _il.Emit(OpCodes.Stloc, nameLocal);
                    _locals[name] = nameLocal;
                }

                return true;
            }

            case 21: // Break — branch to the innermost loop's end label.
                if (_loopLabels.Count == 0)
                    return false;
                _il.Emit(OpCodes.Br, _loopLabels.Peek().Break);
                return true;

            case 22: // Continue — branch to the innermost loop's condition-check label.
                if (_loopLabels.Count == 0)
                    return false;
                _il.Emit(OpCodes.Br, _loopLabels.Peek().Continue);
                return true;

            default: // spike: Block / Return / `:=` / assignment / if-else / while / break / continue.
                return false;
        }
    }

    /// <summary>
    /// Emit an `if`/`while` CONDITION as a bool (i4 0/1) on the stack for a following <c>brfalse</c>/<c>brtrue</c>.
    /// Now that the expression emitter is type-aware, a condition is ANY bool expression — a comparison, a bool
    /// literal/local/param, a bool-returning call, or a logical-not — verified by its reported type, so a
    /// non-bool (e.g. an int) can never reach a branch. Anything that is not statically bool declines.
    /// </summary>
    private bool EmitCondition(int idx)
    {
        return EmitExpression(idx, out var type) && type == typeof(bool);
    }

    /// <summary>
    /// Whether this statement always exits via a return — the same columnar subset as the diagnostics pass
    /// (Return; a Block whose any statement returns; an If with an else where both branches return). Used to
    /// guarantee the emitted `if` has no fall-through.
    /// </summary>
    private bool AlwaysReturns(int idx)
    {
        switch (_kinds[idx])
        {
            case 20: // Return
                return true;
            case 25: // Block
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    if (AlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;
            case 27: // If [cond, then, else?]
                return _childCount[idx] == 3 && AlwaysReturns(Child(idx, 1)) && AlwaysReturns(Child(idx, 2));
            default:
                return false;
        }
    }

    // A reference-type CONSTRUCTOR body is valid for columnar emit iff it (1) contains NO `return` statement — the
    // N# pipeline rejects `return` in a constructor (NL103, "there's no function to return from") — and (2) ASSIGNS
    // EVERY field of the type — the N# pipeline requires definite assignment of non-nullable fields (NL304), and all
    // MODELLED fields are non-nullable (a nullable/composed field type declines at the parser kernel). The assignment
    // check is conservative: only a TOP-LEVEL `field = expr` statement counts, so a field assigned only inside an
    // `if`/loop declines to the C# path (safe under-acceptance) rather than risking a partial-coverage mis-accept.
    private bool IsValidReferenceCtorBody(int bodyRoot)
    {
        if (_currentStruct == null || _kinds[bodyRoot] != 25 || ContainsReturnStatement(bodyRoot))
            return false;
        var assigned = new HashSet<string>(StringComparer.Ordinal);
        for (var n = 0; n < _childCount[bodyRoot]; n++)
        {
            var stmt = Child(bodyRoot, n);
            if (_kinds[stmt] != 23) // an expression statement
                continue;
            var e = Child(stmt, 0);
            if (_kinds[e] != 14 || Text(e) != "=") // a simple `=` assignment
                continue;
            var target = Child(e, 0);
            if (_kinds[target] == 6 && _currentStruct.Fields.ContainsKey(Text(target)))
                assigned.Add(Text(target));
        }
        return assigned.Count == _currentStruct.Fields.Count;
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
            foreach (var (cb, cpt) in baseDef.Constructors)
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
            foreach (var (cb, cpt) in _currentStruct.Constructors)
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
        if (_kinds[idx] == 20)
            return true;
        for (var n = 0; n < _childCount[idx]; n++)
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
    {
        type = null!;
        switch (_kinds[idx])
        {
            case 6: // Identifier — a `:=` local (ldloc, type = LocalType) or a parameter (ldarg, type from the
                    // signature); the two name sets are disjoint (a local shadowing a param is declined at decl).
            {
                var name = Text(idx);
                if (_locals.TryGetValue(name, out var local))
                {
                    _il.Emit(OpCodes.Ldloc, local);
                    type = local.LocalType;
                    return true;
                }

                if (_paramOrdinals.TryGetValue(name, out var ordinal))
                {
                    EmitLoadArgument(ordinal);
                    type = _paramTypes[name];
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
            {       // (decimal) suffix is a different type -> decline. The value is parsed identically to the C#
                    // path's ParseFloatLiteralValue (strip the type suffix, drop `_` separators, invariant parse),
                    // then narrowed to float for an f-literal (matching `Ldc_R4, (float)ParseFloatLiteralValue`).
                var raw = Text(idx);
                var last = raw.Length > 0 ? raw[raw.Length - 1] : '\0';
                if (last == 'm' || last == 'M')
                    return false; // decimal — not modelled.
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
                if (!TryDecodeLiteralBody(raw, out var charValue) || charValue.Length != 1)
                    return false;
                _il.Emit(OpCodes.Ldc_I4, (int)charValue[0]);
                type = typeof(char);
                return true;
            }

            case 3: // StringLiteral — N# string literals are RAW: the C# path emits `value.Trim('"')` with NO
            {       // escape processing (ILCompiler.GetStringLiteralRuntimeValue), so a backslash stays literal.
                    // Match that EXACTLY (Trim('"') over the source substring) — do NOT decode escapes here.
                _il.Emit(OpCodes.Ldstr, Text(idx).Trim('"'));
                type = typeof(string);
                return true;
            }

            case 7: // Parenthesized — emit the inner expression, propagating its type.
                return EmitExpression(Child(idx, 0), out type);

            case 11: // Unary [operand] — int/long prefix `-`/`~`, or bool `!`. `++`/`--` decline.
            {
                if (!EmitExpression(Child(idx, 0), out var operandType))
                    return false;
                switch (Text(idx))
                {
                    case "-": // negate — Neg works on i4/i8/r8/r4; result is the operand's numeric type. NOT valid on
                              // ulong (C# forbids unary minus on an unsigned type) — decline it. On double/float, Neg
                              // is the IEEE negate (-NaN stays NaN, -0.0 is distinct from 0.0), matching the C# path.
                        if (operandType != typeof(int) && operandType != typeof(long) && operandType != typeof(double) && operandType != typeof(float)) return false;
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

                // Short-circuit `&&`/`||` MUST conditionally evaluate the right operand — both for C# semantics
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

                if (!EmitExpression(Child(idx, 0), out var leftType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var rightType))
                    return false;

                // Shifts are special: the value is int/long, the shift COUNT is always int (not necessarily the
                // value's type), and the result is the value's type. Shr is the SIGNED (arithmetic) right shift,
                // matching C# for int/long; the columnar `>>` is a single binary operator here (the `>>` token
                // split only applies inside generic type arguments, not expression context).
                if (op == "<<" || op == ">>")
                {
                    if ((leftType != typeof(int) && leftType != typeof(long) && leftType != typeof(ulong)) || rightType != typeof(int))
                        return false;
                    // Shl is the same for signed/unsigned. `>>` is the SIGNED (arithmetic) Shr for int/long, but
                    // the UNSIGNED (logical, zero-fill) Shr_Un for ulong — matching C#'s ulong `>>`. A wrong Shr
                    // here would sign-extend a high-bit-set ulong.
                    _il.Emit(op == "<<" ? OpCodes.Shl : (leftType == typeof(ulong) ? OpCodes.Shr_Un : OpCodes.Shr));
                    type = leftType;
                    return true;
                }

                // NUMERIC PROMOTION (ECMA §12.4.7) for the modelled int-like types: int and char are BOTH i4 on
                // the stack, so a char/int mix promotes both to int with NO conversion IL (e.g. `c * (i + 1)` is
                // int). long/ulong/bool/string do NOT auto-promote (an int/long mix would need a conv) — they must
                // match exactly. `opType` is the type the operation runs as.
                Type opType;
                if (leftType == rightType)
                    opType = leftType;
                else if ((leftType == typeof(int) || leftType == typeof(char)) && (rightType == typeof(int) || rightType == typeof(char)))
                    opType = typeof(int);
                else
                    return false;

                // String CONCATENATION: `s1 + s2` -> String.Concat(string, string) (VALUE concat, matching the C#
                // path's result). Both operands are already on the stack. Only string+string is modelled (the
                // corpus' shape, e.g. `"diag-" + Math.Abs(hash).ToString("x")`); string+int etc. decline.
                if (op == "+" && opType == typeof(string))
                {
                    _il.Emit(OpCodes.Call, typeof(string).GetMethod(nameof(string.Concat), new[] { typeof(string), typeof(string) })!);
                    type = typeof(string);
                    return true;
                }
                switch (op)
                {
                    case "+": case "-": case "*": case "/": case "%":
                        // Add/Sub/Mul/Div/Rem work on i4, i8, and r8 (double); the result is `opType`'s numeric type.
                        // Div/Rem are SIGNED for int/long (UNSIGNED Div_Un/Rem_Un for ulong); on DOUBLE the same
                        // `div`/`rem` opcodes do IEEE FP division/remainder (x/0.0 -> ±Inf, 0.0/0.0 -> NaN — no
                        // throw, matching the C# path), so double is NOT unsignedDivRem. Integer divide-by-zero /
                        // INT_MIN÷-1 still throw exactly as the C# path does. A CHAR result promotes to INT (a char
                        // never survives an arithmetic op — `c - 'A'` is int; matches Analyzer.cs:12820's GetWiderType).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
                        var unsignedDivRem = opType == typeof(ulong);
                        _il.Emit(
                            op == "+" ? OpCodes.Add :
                            op == "-" ? OpCodes.Sub :
                            op == "*" ? OpCodes.Mul :
                            op == "/" ? (unsignedDivRem ? OpCodes.Div_Un : OpCodes.Div) :
                            (unsignedDivRem ? OpCodes.Rem_Un : OpCodes.Rem));
                        type = opType == typeof(char) ? typeof(int) : opType;
                        return true;
                    case "&": case "|": case "^":
                        // Bitwise on int/long/ulong (And/Or/Xor work on i4 and i8); result is `opType` (a char/int
                        // mix is opType=int, so `c & mask` works; a pure char&char declines as i4-but-not-int).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong)) return false;
                        _il.Emit(op == "&" ? OpCodes.And : op == "|" ? OpCodes.Or : OpCodes.Xor);
                        type = opType;
                        return true;
                    case "<": case ">": case "<=": case ">=":
                        // Ordering on int, long, char (signed Clt/Cgt; a char is a non-negative i4 so signed is
                        // correct), ulong (UNSIGNED Clt_Un/Cgt_Un — a ulong > long.MaxValue must compare as a large
                        // positive, not a negative i8), or double (ORDERED Clt/Cgt for `<`/`>`; the UNORDERED
                        // complement for `<=`/`>=` so a NaN operand yields false — see EmitComparison's isFloat path).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
                        EmitComparison(op, opType == typeof(ulong), opType == typeof(double) || opType == typeof(float));
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
                        // Equality on int, long, ulong, bool, char, double, or float (Ceq is bit-identical
                        // signed/unsigned; on double/float it is the IEEE ordered equal — NaN == NaN is false and
                        // NaN != NaN is true, which the `!=` negation of Ceq produces correctly).
                        if (opType != typeof(int) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(bool) && opType != typeof(char) && opType != typeof(double) && opType != typeof(float)) return false;
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
                if (_kinds[callee] == 6) // bare identifier -> resolved in the N# pipeline's EMPIRICALLY PINNED order.
                {
                    var name = Text(callee);
                    // A local/param of the same name: the N# pipeline binds bare calls to the METHOD (locals do
                    // not shadow call targets — pinned), so a name carried by BOTH a value and ANY method tier
                    // declines (under-accept). When NO method tier carries the name, a DELEGATE-typed local/param
                    // invokes via callvirt Invoke (L1a); a non-delegate value still declines.
                    if (_locals.ContainsKey(name) || _paramOrdinals.ContainsKey(name))
                    {
                        if (_siblings.ContainsKey(name)
                            || (_currentStruct != null && TryFindMethodOnChain(_currentStruct, name, out _))
                            || (_enclosingType != null && TryFindStaticMethodOnChain(_enclosingType, name, _childCount[idx] - 1, out _)))
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
                    if (_siblings.TryGetValue(name, out var target))
                    {
                        var argCount = _childCount[idx] - 1;
                        if (argCount != target.ParamTypes.Length) // arity must match (no overloads / defaults / params).
                            return false;
                        if (target.TypeParams.Length > 0)
                        {
                            // A GENERIC sibling with INFERRED type arguments: start from an empty binding —
                            // the shared emission helper unifies each declared parameter shape against the
                            // emitted argument types (the oracle's TryInferDeclaredMethodTypeArguments).
                            return TryEmitGenericSiblingCall(idx, target, new Type?[target.TypeParams.Length], out type);
                        }
                        // Each argument's type must match the callee's declared parameter type. int and bool are both
                        // i4 on the CLR stack, so without this check a mismatch (e.g. an int passed to a bool
                        // parameter) would emit verifiable-but-semantically-wrong IL instead of declining.
                        for (var a = 1; a <= argCount; a++)
                        {
                            if (!EmitExpression(Child(idx, a), out var argType) || argType != target.ParamTypes[a - 1])
                                return false;
                        }
                        _il.Emit(OpCodes.Call, target.Method);
                        type = target.ReturnType;
                        return true;
                    }
                    if (_currentStruct != null && TryFindMethodOnChain(_currentStruct, name, out var ownMethod))
                        return EmitImplicitThisCall(idx, ownMethod, out type);
                    if (_enclosingType != null && TryFindStaticMethodOnChain(_enclosingType, name, _childCount[idx] - 1, out var ownStatic))
                    {
                        // No receiver: just the args, then a direct `call` to the declaring type's static.
                        var staticArgCount = _childCount[idx] - 1;
                        for (var a = 1; a <= staticArgCount; a++)
                        {
                            if (!EmitExpression(Child(idx, a), out var sArgType) || sArgType != ownStatic.ParamTypes[a - 1])
                                return false;
                        }
                        _il.Emit(OpCodes.Call, ownStatic.Builder);
                        type = ownStatic.ReturnType;
                        return true;
                    }
                    return false;
                }
                if (_kinds[callee] == 38) // GenericCallee — an EXPLICIT generic call `F<T1, T2>(args)`.
                {
                    var gName = Text(callee);
                    // The callee resolves exactly like a bare identifier: locals/params shadow-decline; only a
                    // GENERIC top-level sibling binds (explicit type args on a non-generic are pipeline-rejected).
                    if (_locals.ContainsKey(gName) || _paramOrdinals.ContainsKey(gName))
                        return false;
                    if (!_siblings.TryGetValue(gName, out var gTarget) || gTarget.TypeParams.Length == 0)
                        return false;
                    if (_childCount[callee] != gTarget.TypeParams.Length)
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
                        if (_kinds[typeArgNode] != 0)
                            return false; // composed explicit type args (List<int>, T[]) decline this slice.
                        if (!TryResolveType(Text(typeArgNode), _enumRegistry, _structRegistry, _unionRegistry, out var taType))
                            return false;
                        if (taType is TypeBuilder || taType is EnumBuilder || !IsSupportedType(taType))
                            return false;
                        explicitBinding[ta] = taType;
                    }
                    return TryEmitGenericSiblingCall(idx, gTarget, explicitBinding, out type);
                }
                if (_kinds[callee] == 8) // MemberAccess callee -> a BCL instance/static method call.
                    return TryEmitBclMethodCall(idx, callee, out type);
                return false;
            }

            case 8: // MemberAccess [receiver] — an ENUM CONSTANT (e.g. StringComparison.Ordinal), or `.Length` on
            {       // an array/string/StringBuilder (-> int). The member name is the value span.
                // An enum constant: a bare-identifier receiver naming the enum TYPE (not a value) + a member that
                // is one of its named constants -> load the constant's underlying int (an enum is its underlying
                // value on the stack). Only StringComparison is modelled (the corpus' only enum).
                var memberAccessReceiver = Child(idx, 0);
                if (_kinds[memberAccessReceiver] == 6)
                {
                    var receiverIdent = Text(memberAccessReceiver);
                    if (receiverIdent == "StringComparison"
                        && !_locals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (!TryGetStringComparisonValue(Text(idx), out var enumValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, enumValue);
                        type = typeof(StringComparison);
                        return true;
                    }
                    // A USER-DEFINED enum constant: the receiver names a registered enum TYPE (not shadowed by a
                    // local/param/sibling) and the member is one of its constants -> load the underlying int. The
                    // reported type is the enum's EnumBuilder (the same instance used for its param/return types, so
                    // `return Color.Green` reference-matches the declared `Color` return).
                    if (_enumRegistry.TryGetValue(receiverIdent, out var userEnum)
                        && !_locals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
                    {
                        if (!userEnum.Constants.TryGetValue(Text(idx), out var memberValue))
                            return false;
                        _il.Emit(OpCodes.Ldc_I4, memberValue);
                        type = userEnum.Builder;
                        return true;
                    }
                    // A USER-TYPE STATIC member read `TypeName.member`: the receiver names a registered struct/
                    // record/class TYPE (not shadowed by a local/param/sibling) — chain-walk its static FIELDS
                    // then static PROPERTIES (nearest declaration first; `Derived.count` binds a base-declared
                    // static, matching the fixed oracle): `ldsfld` for a field, `call get_Name` for a property.
                    // A member that is NEITHER declines (a type name is not a value — nothing to fall through to).
                    if (_structRegistry.TryGetValue(receiverIdent, out var staticOwner)
                        && !_locals.ContainsKey(receiverIdent) && !_paramOrdinals.ContainsKey(receiverIdent) && !_siblings.ContainsKey(receiverIdent))
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
                // `.ItemN` is a tuple element accessor only if a DIGIT follows "Item" (so `.Items`/`.ItemFoo`
                // decline early without emitting the receiver); the actual element is still gated by GetField below.
                var isTupleItem = member.Length > 4 && member.StartsWith("Item", StringComparison.Ordinal) && char.IsDigit(member[4]);
                if (member != "Length" && !isTupleItem)
                {
                    // A USER-TYPE FIELD read `p.Field` or get-only PROPERTY read `p.Prop`: emit the receiver, and if it
                    // is a registered struct/class with a field/property named `member`, read it. A value-type field
                    // read needs the value's ADDRESS (spill to a temp + ldloca); a reference field reads directly; a
                    // PROPERTY reads via `callvirt get_Name` on the receiver ref. Otherwise decline (the emitted
                    // receiver is discarded with the whole assembly on false).
                    if (!EmitExpression(Child(idx, 0), out var structReceiverType))
                        return false;
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
                            if (closedFieldDef.IsReference && closedFieldDef.Properties.TryGetValue(member, out var openProp))
                            {
                                _il.Emit(OpCodes.Callvirt, TypeBuilder.GetMethod(structReceiverType, openProp.Getter));
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
                    if (fieldStruct.IsReference && TryFindPropertyOnChain(fieldStruct, member, out var propAccessor))
                    {
                        // get-only PROPERTY read: the receiver ref is the getter's `this` — `callvirt get_Name`.
                        _il.Emit(OpCodes.Callvirt, propAccessor.Getter);
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
                        return false;
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
                if (!indexedType.IsSZArray)
                    return false;
                var elementType = indexedType.GetElementType()!;
                if (!EmitExpression(Child(idx, 1), out var indexType) || indexType != typeof(int))
                    return false;
                if (elementType == typeof(int)) _il.Emit(OpCodes.Ldelem_I4);
                else if (elementType == typeof(long) || elementType == typeof(ulong)) _il.Emit(OpCodes.Ldelem_I8);
                else if (elementType == typeof(char)) _il.Emit(OpCodes.Ldelem_U2);
                else if (elementType == typeof(double)) _il.Emit(OpCodes.Ldelem_R8);
                else if (elementType == typeof(float)) _il.Emit(OpCodes.Ldelem_R4);
                else if (elementType == typeof(string)) _il.Emit(OpCodes.Ldelem_Ref);
                // An OPEN generic-parameter element (xs: T[] inside a generic function): the type-operand
                // `ldelem !!T` form loads any element type (spike-proven).
                else if (elementType.IsGenericParameter) _il.Emit(OpCodes.Ldelem, elementType);
                else return false; // other element types arrive with their type slices.
                type = elementType;
                return true;
            }

            case 15: // New [type, args...] — `new T[](size)` array allocation, OR `new string(char[], int, int)`
            {        // (the String(char[],int,int) constructor). child[0] is a TYPE subtree (2 = Array, 0 = Simple).
                var typeNode = Child(idx, 0);
                if (_kinds[typeNode] == 0) // a Simple type -> a constructor call (string or StringBuilder).
                {
                    var newTypeName = Text(typeNode);
                    if (newTypeName == "string")
                    {
                        // `new string(char[] value, int startIndex, int length)` — copy a char[] slice into a
                        // string. Emit the char[] then the two int args, then `newobj` the String ctor.
                        if (_childCount[idx] != 4)
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
                        // `new StringBuilder()` or `new StringBuilder(int capacity)`. (Other ctor overloads
                        // decline.)
                        var ctorArgCount = _childCount[idx] - 1;
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
                    // A user type with a positional constructor: `new T(args)`. The type names a registered
                    // type with ≥1 user ctor; resolve the OVERLOAD by arg COUNT — exactly one ctor must have
                    // that param count (two with the same count are ambiguous-by-count → decline to C#). Emit each arg
                    // (type-checked against the chosen ctor's param type), then `newobj <ctor>`; the result's type is
                    // the type. (`newobj` on a VALUE type zero-initializes then runs the ctor and pushes the value —
                    // the oracle's probed semantics for partially-assigning struct ctors. A 0-ctor type declines here;
                    // fields-only value structs construct via object-init.)
                    if (_structRegistry.TryGetValue(newTypeName, out var ctorDef) && ctorDef.Constructors.Count > 0)
                    {
                        var ctorArgCount = _childCount[idx] - 1;
                        ConstructorBuilder? chosenCtor = null;
                        Type[]? chosenParamTypes = null;
                        var ambiguous = false;
                        foreach (var (cb, cpt) in ctorDef.Constructors)
                        {
                            if (cpt.Length != ctorArgCount)
                                continue;
                            if (chosenCtor != null) { ambiguous = true; break; }
                            chosenCtor = cb;
                            chosenParamTypes = cpt;
                        }
                        if (chosenCtor == null || ambiguous)
                            return false; // no ctor of that arity, or ambiguous-by-count overloads -> decline.
                        for (var a = 0; a < ctorArgCount; a++)
                        {
                            if (!EmitExpression(Child(idx, 1 + a), out var ctorArgType) || ctorArgType != chosenParamTypes![a])
                                return false;
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
                // C# oracle uses; reflection member queries throw on TypeBuilderInstantiation).
                if (_kinds[typeNode] == 1)
                {
                    if (!TryBuildTypeNodeCanonical(typeNode, out var closedCanonical)
                        || !TryResolveType(closedCanonical, _enumRegistry, _structRegistry, _unionRegistry, out var closedType)
                        || !IsClosedUserGenericInstantiation(closedType))
                        return false;
                    if (!_structRegistry.TryGetValue(Text(typeNode), out var openGenericDef)
                        || openGenericDef.Constructors.Count == 0)
                        return false; // 0-ctor generic types decline (object-init on closed generics is unmodelled).

                    var closedCtorArgCount = _childCount[idx] - 1;
                    ConstructorBuilder? chosenOpenCtor = null;
                    Type[]? chosenOpenParamTypes = null;
                    var closedAmbiguous = false;
                    foreach (var (cb, cpt) in openGenericDef.Constructors)
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
                if (_childCount[idx] != 2 || _kinds[typeNode] != 2) // array alloc: exactly one ctor arg; type must be Array.
                    return false;
                var elementNode = Child(typeNode, 0); // the array's element type subtree.
                if (_kinds[elementNode] != 0) // element must be a Simple builtin (not jagged/generic).
                    return false;
                if (!TryResolveBuiltin(Text(elementNode), out var newElementType) || !IsSupportedElementType(newElementType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sizeType) || sizeType != typeof(int)) // length: int.
                    return false;
                _il.Emit(OpCodes.Newarr, newElementType);
                type = newElementType.MakeArrayType();
                return true;
            }

            case 16: // Cast [type, operand] — explicit numeric conversion among int/long/char. child[0] is a
            {        // TYPE subtree (Simple); child[1] is the operand. Other casts (to/from string, bool, etc.)
                     // decline (the C# path stays authoritative).
                var castTypeNode = Child(idx, 0);
                if (_kinds[castTypeNode] != 0 || !TryResolveBuiltin(Text(castTypeNode), out var targetType))
                    return false;
                if (!IsCastableScalar(targetType))
                    return false;
                if (!EmitExpression(Child(idx, 1), out var sourceType))
                    return false;
                // An i4-underlying enum operand is its int on the stack, so `enum as <numeric>` is a cast FROM int:
                // enum->int is identity (no opcode), enum->long/double/etc. widens exactly like int->long/double. The
                // C# path emits the same (the underlying-int value, then the same numeric conversion).
                if (sourceType is EnumBuilder)
                    sourceType = typeof(int);
                if (!IsCastableScalar(sourceType))
                    return false;
                // Emit the conversion only when the stack representation differs (char->int and same-type casts
                // are no-ops). The opcode is TARGET-driven, matching the C# path (TryGetNumericConversionOpcode):
                // -> double = conv.r8, -> float = conv.r4, -> long = conv.i8, -> char = conv.u2, -> int = conv.i4.
                // float/double->int truncates toward zero exactly as the C# path's conv.i4 does (same opcode).
                if (sourceType != targetType)
                {
                    if (targetType == typeof(double)) _il.Emit(OpCodes.Conv_R8);      // int/long/char/float -> double (widen)
                    else if (targetType == typeof(float)) _il.Emit(OpCodes.Conv_R4);  // int/long/char/double -> float
                    else if (targetType == typeof(long)) _il.Emit(OpCodes.Conv_I8);   // int/char/double/float -> long
                    else if (targetType == typeof(char)) _il.Emit(OpCodes.Conv_U2);   // int/long/double/float -> char (truncate)
                    else if (sourceType == typeof(long) || sourceType == typeof(double) || sourceType == typeof(float)) _il.Emit(OpCodes.Conv_I4); // long/double/float -> int
                    // char -> int is identity (the char is already an i4 code point): no opcode.
                }
                type = targetType;
                return true;
            }

            case 17: // Tuple [e0, e1, ...] — construct a positional System.ValueTuple<...>: emit each element value
            {        // (left-to-right, the ctor's argument order), then `newobj` the matching ValueTuple ctor.
                     // Arity 2-7 (a 1-tuple is not a tuple; >7 needs the nested TRest form — both decline).
                var arity = _childCount[idx];
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
                    if (!EmitExpression(Child(idx, i), out var elemType) || !IsSupportedType(elemType))
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

            case 36: // ObjectInitializer [typeRoot, name0, value0, ...] — `new Struct { Field: value, ... }`. Build a
            {        // user-struct value: a temp local, `ldloca; initobj` (zero all fields), then per named field
                     // `ldloca; <value>; stfld <FieldBuilder>`, then `ldloc` the temp. Mirrors the C# struct
                     // object-initializer (default + per-field assignment). Only a registered struct type is modelled.
                     // A `new Union.Case { f: v }` object-init (a reference type like a record) is handled first.
                var typeRootNode = Child(idx, 0);
                if (_kinds[typeRootNode] != 0)
                    return false; // not a Simple type-ref.
                var initChildCount = _childCount[idx];
                if ((initChildCount % 2) != 1) // typeRoot + (name, value) pairs.
                    return false;
                var pairCount = (initChildCount - 1) / 2;
                var assigned = new HashSet<string>(StringComparer.Ordinal);

                // UNION CASE: `new Union.Case { field: value, ... }` — the dotted type name resolves to a registered
                // union case (a sealed reference type). `newobj <case ctor>` then per named field `dup; <value>;
                // stfld`. The expression's STATIC type is the union BASE (an upcast — the runtime object is the
                // concrete case), so the result flows wherever a `Union` is expected and a later match recovers it.
                if (_unionCaseRegistry.TryGetValue(Text(typeRootNode), out var initCaseDef))
                {
                    _il.Emit(OpCodes.Newobj, initCaseDef.Ctor);
                    for (var p = 0; p < pairCount; p++)
                    {
                        var nameNode = Child(idx, 1 + (2 * p));
                        var valueNode = Child(idx, 2 + (2 * p));
                        if (_kinds[nameNode] != 6)
                            return false;
                        var fieldName = Text(nameNode);
                        if (!initCaseDef.Fields.TryGetValue(fieldName, out var caseInitField) || !assigned.Add(fieldName))
                            return false; // unknown or duplicately-assigned field -> decline.
                        _il.Emit(OpCodes.Dup);
                        if (!EmitExpression(valueNode, out var caseInitValueType) || caseInitValueType != caseInitField.FieldType)
                            return false;
                        _il.Emit(OpCodes.Stfld, caseInitField);
                    }
                    type = initCaseDef.UnionBase; // upcast to the union base.
                    return true;
                }

                if (!_structRegistry.TryGetValue(Text(typeRootNode), out var initStructDef))
                    return false; // not a registered struct/record/union-case type.
                if (initStructDef.IsReference)
                {
                    // RECORD/CLASS (reference type): `newobj <default ctor>` then per named field `dup; <value>;
                    // stfld`. The object ref stays on the stack between assignments (and as the result) via dup —
                    // mirrors C#'s reference-type object initializer. A class with a USER constructor has NO default
                    // (parameterless) ctor, so object-init on it declines (it must be constructed positionally).
                    if (initStructDef.DefaultCtor == null)
                        return false;
                    _il.Emit(OpCodes.Newobj, initStructDef.DefaultCtor);
                    for (var p = 0; p < pairCount; p++)
                    {
                        var nameNode = Child(idx, 1 + (2 * p));
                        var valueNode = Child(idx, 2 + (2 * p));
                        if (_kinds[nameNode] != 6)
                            return false;
                        var fieldName = Text(nameNode);
                        if (!initStructDef.Fields.TryGetValue(fieldName, out var initField) || !assigned.Add(fieldName))
                            return false;
                        _il.Emit(OpCodes.Dup);
                        if (!EmitExpression(valueNode, out var initValueType) || initValueType != initField.FieldType)
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
                    if (_kinds[nameNode] != 6)
                        return false;
                    var fieldName = Text(nameNode);
                    if (!initStructDef.Fields.TryGetValue(fieldName, out var initField) || !assigned.Add(fieldName))
                        return false; // unknown or duplicately-assigned field -> decline.
                    _il.Emit(OpCodes.Ldloca, structValue);
                    if (!EmitExpression(valueNode, out var initValueType) || initValueType != initField.FieldType)
                        return false;
                    _il.Emit(OpCodes.Stfld, initField);
                }
                _il.Emit(OpCodes.Ldloc, structValue);
                type = initStructDef.Builder;
                return true;
            }

            case 18: // Match [value, pat0, res0, pat1, res1, ...] — `match value { p => r, ... }`, lowered to a
            {        // linear chain mirroring the C# EmitMatchExpression: eval value -> temp; per case test the
                     // pattern, on match eval the result + br end; no match -> throw. An EXPRESSION: leaves one
                     // result on the stack. Patterns: a LITERAL (equality test) or an identifier (`_` discard or a
                     // binding that always matches and binds the matched value); a pattern may carry a `when` guard
                     // (kind 19 [pattern, guard]) tested after the pattern; richer patterns decline.
                var childCount = _childCount[idx];
                if (childCount < 3 || (childCount % 2) == 0) // value + >=1 (pattern, result) pair.
                    return false;
                var caseCount = (childCount - 1) / 2;

                if (!EmitExpression(Child(idx, 0), out var matchValueType) || !IsSupportedMatchValueType(matchValueType))
                    return false;
                var matchLocal = _il.DeclareLocal(matchValueType);
                _il.Emit(OpCodes.Stloc, matchLocal);

                // ENUM EXHAUSTIVENESS: C# requires an enum match to cover EVERY member or carry a catch-all (the
                // analyzer's NL501 NonExhaustiveMatch). The columnar emit would otherwise compile a PARTIAL enum
                // match (with a runtime throw for the missing members), ACCEPTING a program C# REJECTS. Decline such
                // a match so the columnar path never accepts what C# refuses (→ C# fallback, which reports NL501).
                // This is a DECLINE (route to the analyzer-backed C# path), not a diagnostic — consistent with how
                // the emitter declines everything outside its faithfully-modelled subset. Coverage counts only
                // TOP-LEVEL UNGUARDED arms: an unguarded `_`/binding is a catch-all; an unguarded `Enum.Member`
                // (kind 8) covers that member. Guarded and combinator/relational arms do not count (conservative — a
                // richer-but-exhaustive form simply declines to C#, still correct).
                ColumnarEnumDef? matchEnumDef = null;
                foreach (var def in _enumRegistry.Values)
                {
                    if (def.Builder == matchValueType) { matchEnumDef = def; break; }
                }
                if (matchEnumDef != null)
                {
                    var covered = new HashSet<string>(StringComparer.Ordinal);
                    var hasCatchAll = false;
                    for (var c = 0; c < caseCount; c++)
                    {
                        var rawP = Child(idx, 1 + (2 * c));
                        if (_kinds[rawP] == 19) // a `when`-guarded arm does not contribute to coverage.
                            continue;
                        if (_kinds[rawP] == 6) // `_` discard or an unguarded binding -> a catch-all.
                            hasCatchAll = true;
                        else if (_kinds[rawP] == 8) // `Enum.Member` -> covers that member (if it is THIS enum's).
                        {
                            var recv = Child(rawP, 0);
                            if (_kinds[recv] == 6 && _enumRegistry.TryGetValue(Text(recv), out var rd)
                                && rd.Builder == matchValueType && matchEnumDef.Constants.ContainsKey(Text(rawP)))
                                covered.Add(Text(rawP));
                        }
                    }
                    if (!hasCatchAll && !covered.SetEquals(matchEnumDef.Constants.Keys))
                        return false;
                }

                // UNION EXHAUSTIVENESS: like enums, C# requires a union match to cover EVERY case or carry a
                // catch-all (NL501). A partial union match would otherwise emit a runtime throw for the missing
                // cases — accepting a program C# rejects — so decline it to the analyzer-backed C# path. Coverage
                // counts only TOP-LEVEL UNGUARDED arms: an unguarded `_`/binding (kind 6) is a catch-all; an
                // unguarded union-case pattern (kind 37 over `Union.Case`) covers that case.
                ColumnarUnionDef? matchUnionDef = null;
                foreach (var def in _unionRegistry.Values)
                {
                    if (def.Base == matchValueType) { matchUnionDef = def; break; }
                }
                if (matchUnionDef != null)
                {
                    var coveredCases = new HashSet<string>(StringComparer.Ordinal);
                    var hasCatchAll = false;
                    for (var c = 0; c < caseCount; c++)
                    {
                        var rawP = Child(idx, 1 + (2 * c));
                        if (_kinds[rawP] == 19) // a `when`-guarded arm does not contribute to coverage.
                            continue;
                        if (_kinds[rawP] == 6) // `_` discard or an unguarded binding -> a catch-all.
                            hasCatchAll = true;
                        else if (_kinds[rawP] == 37) // union-case PROPERTY pattern -> covers that case (if THIS union's).
                        {
                            var mem = Child(rawP, 0);
                            if (_kinds[mem] == 8)
                            {
                                var memRecv = Child(mem, 0);
                                if (_kinds[memRecv] == 6)
                                {
                                    var qualified = Text(memRecv) + "." + Text(mem);
                                    if (matchUnionDef.Cases.ContainsKey(qualified))
                                        coveredCases.Add(qualified);
                                }
                            }
                        }
                        else if (_kinds[rawP] == 8) // bare `Union.Case` TYPE pattern -> covers that case (no binding).
                        {
                            var bareRecv = Child(rawP, 0);
                            if (_kinds[bareRecv] == 6)
                            {
                                var qualified = Text(bareRecv) + "." + Text(rawP);
                                if (matchUnionDef.Cases.ContainsKey(qualified))
                                    coveredCases.Add(qualified);
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
                    if (_kinds[rawPattern] == 19)
                    {
                        if (_childCount[rawPattern] != 2)
                            return false;
                        patternNode = Child(rawPattern, 0);
                        guardNode = Child(rawPattern, 1);
                    }
                    else
                    {
                        patternNode = rawPattern;
                        guardNode = -1;
                    }

                    if (_kinds[patternNode] == 6) // top-level identifier: `_` discard or a binding -> always matches.
                    {
                        var patName = Text(patternNode);
                        if (patName != "_")
                        {
                            if (_locals.ContainsKey(patName) || _paramOrdinals.ContainsKey(patName))
                                return false; // a binding that shadows is not modelled.
                            var bindLocal = _il.DeclareLocal(matchValueType);
                            _il.Emit(OpCodes.Ldloc, matchLocal);
                            _il.Emit(OpCodes.Stloc, bindLocal);
                            _locals[patName] = bindLocal;
                        }
                        // Always matches -> fall through to the guard / result.
                    }
                    else if (_kinds[patternNode] == 37) // union-case pattern `Union.Case { f }` (top-level only).
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
                        // declining (whole match -> C# fallback) anything it cannot emit with exact C# parity.
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
                    else if (armResultType != matchResultType) // every arm's result must share the match's type.
                        return false;
                    _il.Emit(OpCodes.Br, matchEnd);

                    _il.MarkLabel(nextCase);
                    foreach (var name in new List<string>(_locals.Keys)) // drop this arm's binding (if any).
                    {
                        if (!armLocals.Contains(name))
                            _locals.Remove(name);
                    }
                }

                // No case matched -> throw (mirrors the C# path). Unreachable if a catch-all arm is present.
                _il.Emit(OpCodes.Ldstr, "No matching case in match expression");
                _il.Emit(OpCodes.Newobj, typeof(InvalidOperationException).GetConstructor(new[] { typeof(string) })!);
                _il.Emit(OpCodes.Throw);
                _il.MarkLabel(matchEnd);
                type = matchResultType!;
                return true;
            }

            default:
                return false;
        }
    }

    // Recursive match-pattern test mirroring the C# EmitPatternTest structure (success/fail labels), but reading the
    // matched value from `matchLocal` instead of a stack dup. On MATCH it branches to successLabel; on NO-MATCH to
    // failLabel. Models literal patterns (kinds 0-4), relational patterns (32), and `and`/`or`/`not` combinators
    // (33/34/35) over those. It does NOT model bindings: an identifier (kind 6) is only handled at the TOP LEVEL of
    // an arm, so an identifier inside a combinator declines (returns false) and the whole match falls back to the C#
    // pipeline. A `false` return discards the entire emitted assembly, so a partially-emitted test is harmless.
    private bool EmitPatternMatch(int patternNode, Type matchValueType, LocalBuilder matchLocal, Label successLabel, Label failLabel)
    {
        switch (_kinds[patternNode])
        {
            case 34: // OrPattern [left, right]: left matches -> success; else fall through and try right.
            {
                if (_childCount[patternNode] != 2)
                    return false;
                var orNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, successLabel, orNext))
                    return false;
                _il.MarkLabel(orNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 33: // AndPattern [left, right]: left must match (else fail), then right decides.
            {
                if (_childCount[patternNode] != 2)
                    return false;
                var andNext = _il.DefineLabel();
                if (!EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, andNext, failLabel))
                    return false;
                _il.MarkLabel(andNext);
                return EmitPatternMatch(Child(patternNode, 1), matchValueType, matchLocal, successLabel, failLabel);
            }
            case 35: // NotPattern [inner]: inner matches -> fail, inner fails -> success (just swap the labels).
            {
                if (_childCount[patternNode] != 1)
                    return false;
                return EmitPatternMatch(Child(patternNode, 0), matchValueType, matchLocal, failLabel, successLabel);
            }
            case 32: // RelationalPattern `<op> <constant>` -> ordered comparison (the C# EmitPatternTest mirror).
            {
                if (_childCount[patternNode] != 1 || !IsOrderedMatchType(matchValueType))
                    return false;
                var operandNode = Child(patternNode, 0);
                if (!IsLiteralPatternKind(_kinds[operandNode]))
                    return false;
                _il.Emit(OpCodes.Ldloc, matchLocal);
                if (!EmitExpression(operandNode, out var relType) || relType != matchValueType)
                    return false;
                // Plain ordered Clt/Cgt for ALL types (matches C# exactly, incl. NaN/large ulong). `<`/`>` take the
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
                if (_kinds[recv] != 6)
                    return false;
                var recvName = Text(recv);
                // ENUM constant: the receiver names a REGISTERED enum (not shadowed by a local/param/sibling), the
                // member is one of its constants, and the match value is THAT enum's type. Underlying-int Ceq.
                if (_enumRegistry.TryGetValue(recvName, out var enumDef)
                    && !_locals.ContainsKey(recvName) && !_paramOrdinals.ContainsKey(recvName) && !_siblings.ContainsKey(recvName))
                {
                    if (matchValueType != enumDef.Builder)
                        return false;
                    if (!enumDef.Constants.TryGetValue(Text(patternNode), out var memberValue))
                        return false;
                    _il.Emit(OpCodes.Ldloc, matchLocal);
                    _il.Emit(OpCodes.Ldc_I4, memberValue);
                    _il.Emit(OpCodes.Ceq);             // underlying-int equality (matches C#'s Beq-on-underlying-int).
                    _il.Emit(OpCodes.Brtrue, successLabel);
                    _il.Emit(OpCodes.Br, failLabel);
                    return true;
                }
                // UNION bare TYPE pattern `Union.Case` (no `{ }`): an `isinst` test against the case's concrete type,
                // matching WITHOUT binding any field — the idiomatic way to match a payload-free case (where `Case {}`
                // is NL503), and to match a payload case by type alone. Binds nothing, so it is SAFE inside `and`/`or`/
                // `not` combinators (unlike the binding property pattern, which is top-level only). The match value
                // must be THIS union's base. No `dup`/`pop` needed: the isinst result is consumed by the branch.
                var qualifiedCase = recvName + "." + Text(patternNode);
                if (_unionCaseRegistry.TryGetValue(qualifiedCase, out var bareCaseDef) && matchValueType == bareCaseDef.UnionBase
                    && !_locals.ContainsKey(recvName) && !_paramOrdinals.ContainsKey(recvName) && !_siblings.ContainsKey(recvName))
                {
                    _il.Emit(OpCodes.Ldloc, matchLocal);
                    _il.Emit(OpCodes.Isinst, bareCaseDef.CaseType);
                    _il.Emit(OpCodes.Brtrue, successLabel);
                    _il.Emit(OpCodes.Br, failLabel);
                    return true;
                }
                return false; // not a registered enum constant or union case -> decline.
            }
            default: // literal pattern (kinds 0-4) -> equality test; any other primary (null/paren/call/index/…) declines.
            {
                if (!IsLiteralPatternKind(_kinds[patternNode]))
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

    // A union-case pattern `Union.Case { f0, f1 }` (kind 37, children [memberAccess, bind0, ...]): an `isinst` type
    // test against the case's concrete type, and on match a field-binding of each named field to a fresh local. This
    // is handled ONLY at the TOP LEVEL of a match arm (not inside `and`/`or`/`not` — bindings in a negated/disjoined
    // pattern are restricted in C#, so a union-case pattern under a combinator declines via EmitPatternMatch's
    // default). On MATCH it branches to successLabel (with the bindings live in `_locals`, cleaned up per-arm by the
    // caller); on NO-MATCH to failLabel. Returns false (whole match -> C# fallback) on any unsupported shape.
    private bool EmitUnionCasePattern(int patternNode, Type matchValueType, LocalBuilder matchLocal, Label successLabel, Label failLabel)
    {
        var memberNode = Child(patternNode, 0);
        if (_kinds[memberNode] != 8)
            return false;
        var caseRecv = Child(memberNode, 0);
        if (_kinds[caseRecv] != 6)
            return false; // the head must be a bare `Union` identifier (a qualified `Union.Case`).
        var qualifiedCase = Text(caseRecv) + "." + Text(memberNode);
        if (!_unionCaseRegistry.TryGetValue(qualifiedCase, out var caseDef) || matchValueType != caseDef.UnionBase)
            return false; // not a registered case of THIS union -> decline.
        // A `{ }` PROPERTY pattern on a PAYLOAD-FREE case is rejected by C# (NL503 — "doesn't carry any data — you
        // can't destructure it with property patterns"); a zero-field case is matched as a BARE type pattern instead
        // (not modelled here). Decline so columnar never accepts a destructuring C# refuses.
        if (caseDef.Fields.Count == 0)
            return false;

        // `ldloc value; isinst Case; dup; brtrue ok; pop; br fail; ok: stloc caseLocal`. The dup keeps a copy so the
        // success path stores the (non-null) case ref; the fail path pops the null before branching — leaving the
        // stack empty at BOTH labels (matching every other pattern's stack discipline).
        var caseLocal = _il.DeclareLocal(caseDef.CaseType);
        var caseOk = _il.DefineLabel();
        _il.Emit(OpCodes.Ldloc, matchLocal);
        _il.Emit(OpCodes.Isinst, caseDef.CaseType);
        _il.Emit(OpCodes.Dup);
        _il.Emit(OpCodes.Brtrue, caseOk);
        _il.Emit(OpCodes.Pop);
        _il.Emit(OpCodes.Br, failLabel);
        _il.MarkLabel(caseOk);
        _il.Emit(OpCodes.Stloc, caseLocal);

        // Bind each listed field to a local of the field's type (`ldloc caseLocal; ldfld f; stloc bind`). A `_`
        // binding is a discard (skip). A binding must name a case field and must not shadow a local/param.
        var bindCount = _childCount[patternNode] - 1;
        for (var b = 0; b < bindCount; b++)
        {
            var bindNode = Child(patternNode, 1 + b);
            if (_kinds[bindNode] != 6)
                return false;
            var bindName = Text(bindNode);
            if (bindName == "_")
                continue;
            if (!caseDef.Fields.TryGetValue(bindName, out var bindField))
                return false; // the binding must name a field of the case (slice scope: bare field bindings).
            if (_locals.ContainsKey(bindName) || _paramOrdinals.ContainsKey(bindName))
                return false; // a binding that shadows a local/param is not modelled.
            var bindLocal = _il.DeclareLocal(bindField.FieldType);
            _il.Emit(OpCodes.Ldloc, caseLocal);
            _il.Emit(OpCodes.Ldfld, bindField);
            _il.Emit(OpCodes.Stloc, bindLocal);
            _locals[bindName] = bindLocal;
        }
        _il.Emit(OpCodes.Br, successLabel);
        return true;
    }

    // Node kinds that are LITERAL match patterns (constant-equality): int(0)/float(1)/char(2)/string(3)/bool(4).
    // A non-literal primary in pattern position (null/parenthesized/member/call/index/…) is not a constant pattern,
    // so the match declines to the C# path rather than emitting a misleading equality test. Identifier patterns
    // (kind 6 — `_` discard / binding) are handled separately, before this is consulted.
    private static bool IsLiteralPatternKind(int kind) => kind >= 0 && kind <= 4;

    // Ordered scalar types a RELATIONAL match pattern (`< c`, `>= c`, …) may test — numeric + char. bool and string
    // have no `<`/`>` ordering in the modelled set, so a relational pattern over them declines to the C# path.
    private static bool IsOrderedMatchType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
        || t == typeof(double) || t == typeof(float);

    // Types a `match` value may be tested against in the modelled pattern set: the scalars (Ceq equality), string
    // (op_Equality), a user-defined enum (its underlying-int Ceq, via the MemberAccess pattern case), and a
    // user-defined UNION base (isinst per union-case pattern). Records/etc. are not modelled, so a match over them
    // declines to the C# path. (Instance — the union base is identified by the union registry.)
    private bool IsSupportedMatchValueType(Type t) =>
        t == typeof(int) || t == typeof(long) || t == typeof(ulong) || t == typeof(char)
        || t == typeof(bool) || t == typeof(double) || t == typeof(float) || t == typeof(string)
        || t is EnumBuilder
        || (t is TypeBuilder && IsUnionBase(t));

    // True iff `t` is the abstract base of one of this program's user-defined unions.
    private bool IsUnionBase(Type t)
    {
        foreach (var u in _unionRegistry.Values)
        {
            if (u.Base == t)
                return true;
        }
        return false;
    }

    // Scalars that participate in explicit numeric casts (int/long/char on the i4/i8 slots; double on r8, float on r4).
    private static bool IsCastableScalar(Type t) => t == typeof(int) || t == typeof(long) || t == typeof(char) || t == typeof(double) || t == typeof(float);

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
    // negate the UNORDERED complement (Cgt_Un/Clt_Un) so a NaN operand yields false too — matching C#'s float
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

    // A BCL method call whose callee is a MemberAccess [receiver, method-name]. A STATIC call (receiver is a
    // bare identifier naming a known type, e.g. `Char`) must be detected BEFORE the receiver is emitted (the
    // type name is not a value); an INSTANCE call emits the receiver value then dispatches on its type.
    private bool TryEmitBclMethodCall(int callIdx, int callee, out Type type)
    {
        type = null!;
        var memberName = Text(callee);
        var receiver = Child(callee, 0);
        var argCount = _childCount[callIdx] - 1;

        if (_kinds[receiver] == 6) // a bare identifier receiver that is NOT a value (local/param/sibling) is a type name.
        {
            var receiverName = Text(receiver);
            if (!_locals.ContainsKey(receiverName) && !_paramOrdinals.ContainsKey(receiverName) && !_siblings.ContainsKey(receiverName))
                return TryEmitStaticCall(callIdx, receiverName, memberName, argCount, out type);
        }

        if (!EmitExpression(receiver, out var receiverType)) // instance: receiver value goes on the stack first.
            return false;
        return TryEmitInstanceCall(callIdx, receiverType, memberName, argCount, out type);
    }

    // Static calls (no receiver on the stack): a USER type's static methods first, then a small BCL whitelist.
    // Char.IsLetterOrDigit/IsWhiteSpace(char) -> bool.
    private bool TryEmitStaticCall(int callIdx, string typeName, string member, int argCount, out Type type)
    {
        type = null!;
        // A USER-DECLARED type name binds its OWN static methods (chain-walked, nearest declaration first — the
        // oracle resolves `Derived.F()` to a base-declared static). Resolution is by arg count; arg TYPES must
        // match exactly (the oracle's implicit conversions are not modelled — mismatch declines). CRITICALLY, a
        // user type name must NEVER fall through to the BCL whitelist below: a user `record Math { … }` SHADOWS
        // System.Math in the N# pipeline, so emitting the BCL method for `Math.Abs(x)` would be semantically wrong
        // IL (the over-acceptance failure mode). The same gate covers user enums and unions — no static methods
        // are modelled on them, so any TypeName.Member(...) call on one declines.
        if (_structRegistry.TryGetValue(typeName, out var userType))
        {
            if (!TryFindStaticMethodOnChain(userType, member, argCount, out var userStatic))
                return false;
            for (var a = 1; a <= argCount; a++)
            {
                if (!EmitExpression(Child(callIdx, a), out var argType) || argType != userStatic.ParamTypes[a - 1])
                    return false;
            }
            _il.Emit(OpCodes.Call, userStatic.Builder);
            type = userStatic.ReturnType;
            return true;
        }
        if (_enumRegistry.ContainsKey(typeName) || _unionRegistry.ContainsKey(typeName))
            return false;
        // The receiver may be the type NAME `Char` (via `using System`) or the builtin alias `char` (the
        // lowercase keyword) — both bind to System.Char in N#/C#, so accept either.
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
            // inputs return the magnitude; int.MinValue throws OverflowException — identical to the C# path,
            // which binds the same overload, so parity holds (the columnar and C# results match, throw included).
            var method = typeof(Math).GetMethod(nameof(Math.Abs), new[] { typeof(int) });
            if (method == null || !EmitArg(callIdx, 1, typeof(int)))
                return false;
            _il.Emit(OpCodes.Call, method);
            type = typeof(int);
            return true;
        }
        if ((typeName == "String" || typeName == "string") && member == "Compare")
        {
            // String.Compare overloads -> int (ordinal/culture comparison sign). Two shapes are modelled:
            //   3-arg: Compare(string, string, StringComparison)
            //   6-arg: Compare(string, int, string, int, int, StringComparison)
            // Both take a StringComparison enum constant as the LAST arg (emitted as its underlying int). The
            // return is the comparison sign (<0 / 0 / >0), matching the C# binder's pick of the same overload.
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
        if (typeName == "Array" && member == "Fill" && argCount == 4)
        {
            // Array.Fill<T>(T[] array, T value, int startIndex, int count) -> void. The array's element type
            // drives the generic instantiation; the value must match the element type; startIndex/count are int.
            // (The 2-arg Fill<T>(T[], T) is a separate overload — only the 4-arg span-fill is modelled here.)
            if (!EmitExpression(Child(callIdx, 1), out var arrayType) || !arrayType.IsSZArray)
                return false;
            var elementType = arrayType.GetElementType()!;
            if (!IsSupportedElementType(elementType))
                return false;
            if (!EmitArg(callIdx, 2, elementType) || !EmitArg(callIdx, 3, typeof(int)) || !EmitArg(callIdx, 4, typeof(int)))
                return false;
            var fill = ResolveArrayFill4();
            if (fill == null)
                return false;
            _il.Emit(OpCodes.Call, fill.MakeGenericMethod(elementType));
            type = typeof(void);
            return true;
        }
        return false;
    }

    // System.Array.Fill&lt;T&gt;(T[] array, T value, int startIndex, int count) — the 4-arg overload as a generic
    // method DEFINITION (the 2-arg Fill&lt;T&gt;(T[], T) is excluded by the parameter count). The caller binds T via
    // MakeGenericMethod(elementType). Returns null if the method is unexpectedly absent (then the call declines).
    private static MethodInfo? ResolveArrayFill4()
    {
        foreach (var m in typeof(System.Array).GetMethods(BindingFlags.Public | BindingFlags.Static))
        {
            if (m.Name == "Fill" && m.IsGenericMethodDefinition && m.GetParameters().Length == 4)
                return m;
        }
        return null;
    }

    // Rebuilds the canonical type string from an embedded TYPE subtree in the expression node table
    // (kind 0 Simple = the name text; kind 1 Generic = name<argCanons>; kind 2 Array = element[]).
    // Other type-node kinds (nullable/union/byref/tuple) decline — the construction and closed-generic
    // paths that consume this only model these three shapes.
    private bool TryBuildTypeNodeCanonical(int typeNode, out string canonical)
    {
        switch (_kinds[typeNode])
        {
            case 0:
                canonical = Text(typeNode);
                return true;
            case 1:
            {
                var builder = new System.Text.StringBuilder(Text(typeNode));
                builder.Append('<');
                for (var c = 0; c < _childCount[typeNode]; c++)
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
        if (!IsClosedUserGenericInstantiation(a) || !IsClosedUserGenericInstantiation(b))
            return false;
        if (!ReferenceEquals(a.GetGenericTypeDefinition(), b.GetGenericTypeDefinition()))
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

    // Instance BCL calls (the receiver value is already on the stack): a small whitelist of string methods.
    // string.IndexOf(char, int) -> int ; string.Substring(int, int) -> string.
    private bool TryEmitInstanceCall(int callIdx, Type receiverType, string member, int argCount, out Type type)
    {
        type = null!;

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
                if (d.Builder == receiverType && TryFindMethodOnChain(d, member, out var structMethod))
                {
                    if (argCount != structMethod.ParamTypes.Length)
                        return false;
                    var receiverTemp = _il.DeclareLocal(receiverType);
                    _il.Emit(OpCodes.Stloc, receiverTemp);
                    _il.Emit(d.IsReference ? OpCodes.Ldloc : OpCodes.Ldloca, receiverTemp);
                    for (var a = 0; a < argCount; a++)
                    {
                        if (!EmitExpression(Child(callIdx, 1 + a), out var argType) || argType != structMethod.ParamTypes[a])
                            return false;
                    }
                    _il.Emit(d.IsReference ? OpCodes.Callvirt : OpCodes.Call, structMethod.Builder);
                    type = structMethod.ReturnType;
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
            if (!closedDef.Methods.TryGetValue(member, out var closedMethod))
                return false;
            if (argCount != closedMethod.ParamTypes.Length)
                return false;
            var closedReceiverTemp = _il.DeclareLocal(receiverType);
            _il.Emit(OpCodes.Stloc, closedReceiverTemp);
            _il.Emit(closedDef.IsReference ? OpCodes.Ldloc : OpCodes.Ldloca, closedReceiverTemp);
            for (var a = 0; a < argCount; a++)
            {
                var expectedParam = SubstituteClosedTypeArguments(closedMethod.ParamTypes[a], closedArgs);
                if (!EmitExpression(Child(callIdx, 1 + a), out var argType) || !TypesEquivalent(argType, expectedParam))
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
            return false;
        }
        if (receiverType == typeof(string) && member == "Trim" && argCount == 0)
        {
            // string.Trim() -> string (strip leading/trailing whitespace). The receiver string is on the stack;
            // `callvirt` the parameterless overload. DiagnosticClusters.nl: `builder.ToString().Trim()`.
            var method = typeof(string).GetMethod(nameof(string.Trim), Type.EmptyTypes);
            if (method == null)
                return false;
            _il.Emit(OpCodes.Callvirt, method);
            type = typeof(string);
            return true;
        }
        if (receiverType == typeof(int) && member == "ToString" && argCount == 1)
        {
            // int.ToString(string format) -> string (e.g. .ToString("x") for lowercase hex). Int32.ToString is a
            // VALUE-TYPE instance method, so `this` must be a managed pointer: spill the receiver int (already on
            // the stack) to a temp local and `ldloca` its address, then push the format string and `call`. The
            // C# path binds the same Int32.ToString(string) overload, so the formatted text matches exactly.
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
            if (member == "Append" && argCount == 1)
            {
                // Resolve the overload by the ARGUMENT'S type (char/string/int): emit the arg, then bind
                // Append(thatType). (The receiver is already on the stack, so the arg goes on top — correct order.)
                if (!EmitExpression(Child(callIdx, 1), out var appendArgType)
                    || (appendArgType != typeof(char) && appendArgType != typeof(string) && appendArgType != typeof(int)))
                    return false;
                var append = sb.GetMethod(nameof(System.Text.StringBuilder.Append), new[] { appendArgType });
                if (append == null)
                    return false;
                _il.Emit(OpCodes.Callvirt, append);
                type = sb;
                return true;
            }
            return false;
        }
        return false;
    }

    // Emit the argument at child position `argPosition` of the call and require its type to equal `expected`.
    private bool EmitArg(int callIdx, int argPosition, Type expected)
        => EmitExpression(Child(callIdx, argPosition), out var argType) && argType == expected;

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

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);
}
