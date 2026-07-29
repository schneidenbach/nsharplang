# Analyzer Component

**Files:** `src/NSharpLang.Compiler/Analyzer.cs`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerDeclarationContext.nl`,
`src/NSharpLang.Compiler.BootstrapServices/TypeInfoIdentityFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerConversionFacts.nl`

## Responsibility

Performs semantic analysis, type checking, and name resolution on the AST.

`Analyzer.cs` is the diagnostic/scope shell. `AnalyzerDeclarationContext.nl` is the N# owner for
the project declaration catalog, case-sensitive canonical source-type identity, file and namespace
imports, alias-cycle handling, owner-open generic substitution, lexical nested-type lookup, and
source member projection. The shell
loads parsed project units into that owner at the start of analysis and routes declaration/member
queries through it; do not recreate those policies as C# caches or fallback resolvers.
Project candidates across every visible namespace import are exhausted before CLR candidates;
bare CLR names use the same case-sensitive exported-type assembly scan as the analyzer shell.
`TypeInfoIdentityFacts.nl` owns exact structural identity for composed types and exact CLR metadata
identity; nominal source types compare through the canonical declaration handles supplied by the
declaration context. Tuple element labels are metadata rather than type identity, while dynamic
assembly types remain reference-identity-only even after they are baked.

`AnalyzerConversionFacts.nl` is the N# owner for the analyzer's conversion/assignability
classification tables — the leaf policy the assignability decision consults:

- `IsImplicitNumericConversion(TypeInfo, TypeInfo)` and `IsImplicitNumericReflectionConversion(Type, Type)`
  are the CLR implicit numeric-widening table. The relation is stated once over
  `NumericConversionKind` and reached through two disjoint name maps — N# source spellings
  (`byte`, `sbyte`, …) and CLR full names (`System.Byte`, …). Neither vocabulary accepts the other's
  spellings. Identical reflection types short-circuit to true and `Nullable<T>` is read through to
  `T` on both sides; identical source names are NOT a conversion, because the caller answers
  identity first.
- `IsReferenceType(TypeInfo)` decides whether `null` is one of a type's values. Record structs,
  enums, byref types and closed generic instantiations are value types; every simple name outside
  the built-in value list is a reference type; reflection types defer to the CLR value-type flag.
- `IsReflectionAssignableFrom(Type, Type)` is the MetadataLoadContext-safe assignability walk:
  exact identity, then `Type.IsAssignableFrom`, then the source's interface list and base chain
  compared by exact metadata identity (types loaded from different assembly identities are not
  reference-equal inside the MLC, so `IsAssignableFrom` alone is not sufficient).

Do not reintroduce any of these tables in C#, and do not grow this class with the rest of the
assignability closure — later families land in sibling N# owners.

## Core Functions

1. **Type Checking**: Ensures expressions have compatible types
2. **Type Inference**: Infers types for `:=` declarations
3. **Name Resolution**: Resolves identifiers to declarations
4. **Scope Management**: Tracks nested scopes (global, class, function, block)
5. **External Type Resolution**: Resolves .NET types via reflection
6. **Error Detection**: Reports type errors, undefined names, etc.

## Scope Management

### Scope Hierarchy
```
Global Scope
└── Class Scope (per class/struct/record)
    └── Function Scope (per function)
        └── Block Scope (per { }, if, for, while, etc.)
```

### Symbol Tables
Scopes are managed via:
- `EnterScope()`: Push new scope
- `ExitScope()`: Pop scope
- `DeclareSymbol(name, type)`: Add to current scope
- `LookupSymbol(name)`: Search current + parent scopes

## Type System

See `src/NSharpLang.Compiler/TypeSystem/TypeInfo.cs` for type representations:

### Built-in Types
- **PrimitiveTypeInfo**: `int`, `long`, `float`, `double`, `bool`, `string`, `void`
- **UnknownTypeInfo**: Type not yet resolved

### User-Defined Types
- **ClassTypeInfo**: N#-owned class declaration metadata
- **StructTypeInfo**: N#-owned struct declaration metadata
- **RecordTypeInfo**: N#-owned record declaration metadata (reference or struct)
- **InterfaceTypeInfo**: N#-owned interface declaration metadata
- **UnionTypeInfo**: N#-owned union metadata derived from union declarations
- **EnumTypeInfo**: From enum declarations (int or string)

### External Types
- **ReflectionTypeInfo**: .NET types loaded via reflection (e.g., `System.Console`)
- **ReflectionMethodInfo**: Single method from external type
- **ReflectionMethodGroupInfo**: Overloaded methods (multiple signatures)
- **ExternalTypeInfo**: Unresolved external type (placeholder)

### Special Types
- **FunctionTypeInfo**: N#-owned function signature metadata; source declarations remain opaque handles until the function declaration model moves
- **NSharpMethodGroupInfo**: N#-owned overload group metadata with opaque source declaration handles
- **ArrayTypeInfo**: Array types (`T[]`)
- **GenericTypeInfo**: Generic types (`List<T>`)
- **NullableTypeInfo**: Nullable types (`T?`)

## External Type Resolution

The Analyzer tracks imports and mechanically routes external type-valued receivers to canonical
N# resolution. Static field/property selection and emitted-plan validation are N#-owned.

### Process
1. `ExternalAssemblyScan.nl` builds the deterministic assembly catalog, preserving exact assembly
   identities and pairing reference assets with runtime implementations.
2. `ColumnarBindingScopeFacts.nl` exports reusable source/import/type facts and applies lexical
   shadowing, accessibility, package precedence, and ordered namespace lookup for short owners.
3. `ExternalQualifiedTypeResolver.nl` resolves complete dotted CLR type receivers, including nested
   types; `Analyzer.cs` only supplies its existing scope barriers and wraps the resolved `Type`.
4. `ColumnarExternalStaticMemberPlanner.nl` validates the exact field/property handle and builds a
   persisted schema-v3 plan. `ColumnarCodePlanExecutor.nl` validates and emits that plan directly.

Do not add emitter-side static-member whitelists, reflection scans, preload policy, or parallel
scope analyzers. Extend the N# catalog, binding facts, and planner instead.

### MetadataLoadContext Host Verdict

Track D Sub-arc 0 probe (2026-07-03): BootstrapServices can carry the
`System.Reflection.MetadataLoadContext` 10.0.5 dependency, but the N# columnar backend declines a
minimal external abstract override probe:

`AnalyzerMetadataResolverProbe: MetadataAssemblyResolver` with
`override func Resolve(context: MetadataLoadContext, assemblyName: AssemblyName): Assembly`.

Exact build result:
`error NL103: Columnar emission is required for 'NSharpLang.Compiler.BootstrapServices', but the columnar backend declined.`

Verdict: keep `NSharpMetadataResolver` as bounded mechanical C# glue until the columnar backend
supports overriding external abstract members. Its policy decisions should move to N# functions;
the C# shell may only host the `Resolve` override and `MetadataLoadContext` integration boundary.

### Reference Resolution Policy (assembly loading)

A `MetadataLoadContext` holds at most one assembly per identity; loading the same identity from a
second path throws. The analyzer therefore treats explicitly resolved reference paths as ground
truth and dedupes everything else against them:

- `LoadFromProjectConfig` loads Dll/project references (the restored paths MSBuild's
  `EmitIlAssembly` and the CLI's `CompilationReferenceResolver` inject) **before** NuGet-name
  references, and pins every package version recorded in `obj/project.assets.json` on the
  resolver.
- A version-less NuGet dependency binds the restored version from `project.assets.json`; only
  when no restore output exists does it fall back to the highest cached version, ordered by
  SemVer precedence (`NuGetVersionComparer`), never by ordinal string comparison (which ranks
  `0.1.0-anything` above `0.1.0` and `0.9` above `0.10`).
- `NSharpMetadataResolver.Resolve` first unifies on an already-loaded assembly with the same
  simple name, so later binds can never pull a second copy of a different version out of the
  NuGet cache; its cache scans honor the pinned restored versions.
- `LoadReferencedAssembly` dedupes against `MetadataLoadContext.GetAssemblies()` (not just the
  analyzer's own registry) and adopts an already-loaded identity instead of throwing.
- `WellKnownTypes` resolves the `NSharpLang.Runtime` union/result types **lazily** so the
  project's own restored runtime — loaded during project-config processing, after the
  constructor runs — is the copy that wins, not whatever a NuGet-cache scan finds first.

Do not resurrect eager cache scans: a dirty cache (multiple extracted versions of
`nsharplang.runtime`) previously made every SDK build crash with "has already been loaded into
this MetadataLoadContext" whenever the restored version was not the lexically greatest extraction.

### Method Overload Resolution
For external methods with multiple overloads:
- Create a `ReflectionMethodGroupInfo` with the complete applicable method surface. For CLR
  interfaces this includes inherited interface methods, which `Type.GetMethods()` does not expose
  on the derived interface itself.
- Filter by positional/named arity, optional parameters, `params`, receiver compatibility,
  ref/out shape, generic bindings, and contextual delegate/lambda compatibility.
- Rank viable candidates by exact type and conversion quality, preferring instance methods over
  extension methods, non-`params` candidates, and fewer defaults. An equal best match is rejected
  as ambiguous rather than selected by declaration or reflection order.
- N# overload groups use the same principle: argument types and conversion specificity decide the
  unique best candidate; incompatible candidates and equal-best ties are diagnostics.

## Type Checking

### Assignment Compatibility
`IsAssignable(target, source)` checks if source can be assigned to target:
- Exact type match
- Inheritance (class → base class)
- Interface implementation (class → interface)
- Duck interface structural typing (see [Duck interfaces](../../website/docs/types.md#duck-interfaces))
- User-defined implicit conversions
- Nullable conversions (`T → T?`)
- CLR-backed assignability and the explicitly modeled generic collection variance/conversions
- Exact array-to-span and `Span<T>`-to-`ReadOnlySpan<T>` conversions with preserved element identity

### Type Inference
For `:=` declarations:
- Infer from initializer expression type
- If array literal, infer array type from elements
- Contextual delegate targets (`Action`, `Func`, and other CLR delegates) supply lambda parameter
  and return expectations during call and assignment binding. A lambda with no usable target may
  still contain inference holes rather than being treated as an independently nominal value.

### Exact Runtime Structural Projections

Some CLR surfaces cannot be reconstructed safely by comparing display names or by mixing runtime
`Type` objects with `MetadataLoadContext` types. `AnalyzerDeclarationContext.nl` therefore owns a
small, identity-checked projection layer:

- `NSharpLang.Runtime.Result<T, E>` exposes `IsOk`, `IsErr`, `OkValue`,
  `OkValueUnchecked`, `ErrValue`, and `ErrValueUnchecked`, preserving both source type arguments.
- Exact `System.Span<T>` and `System.ReadOnlySpan<T>` expose `Length`, `IsEmpty`, and the governed
  systems-programming `ptr` surface.
- Exact read-only collection definitions expose `Count`.
- Arrays expose the real `AsSpan()` and `AsSpan(start, length)` extension surface only when
  `System` is imported, preserving the array element type.
- CLR interfaces expose the effective method group from the interface and all inherited
  interfaces, consistently for runtime reflection and metadata-only reflection.

`TypeInfoIdentityFacts.nl` is the single identity boundary used by these projections and assignment
rules. It compares composed N# types structurally, canonical source declarations nominally, exact
CLR definitions across runtime and metadata-load contexts, runtime delegate definitions,
Int32-backed CLR enums, and the exact `Span<T>` to `ReadOnlySpan<T>` widening. Do not replace these
checks with type-name matching.

### Definite Assignment
For non-nullable fields:
- Must be assigned in constructor
- Analyzer tracks which fields are assigned
- Reports error if field not initialized

### Error Tuple Result Availability
For Go-style error tuples (`result, err := MightFail()`):
- The result is available only on paths where the paired `err` is proven `null`
- `if err == null { ... }` makes the result available inside the success branch
- `if err != null { return }` or `throw` makes the result available after the guard
- Using the result while `err` may be non-null reports `NL314`

### Must-Use Results
- Functions/methods annotated `[MustUse]` produce results that cannot be silently discarded.
- A bare call statement (`Compute()`) whose result is thrown away reports `NL315` (`DiscardedMustUseResult`), underlining the callee name.
- Sanctioned uses: assign/return/pass the value, or discard explicitly via `_ = Compute()`. `_ = expr` is an explicit discard target (handled in `AnalyzeAssignment`); it binds nothing and only analyzes the right-hand side.
- Scope is intentionally conservative: only `[MustUse]`-annotated N# declarations and external (reflection) methods carrying a `MustUse`/`MustUseAttribute` attribute. Plain non-void results are NOT forced to be used.

## Convention-Based Visibility

Enforced by Analyzer:
- `PascalCase` identifiers → public
- `camelCase` identifiers → private
- Explicit modifiers override convention

Non-conforming names report build-blocking compiler diagnostics (`NL903`) unless the declaration uses an explicit visibility modifier that makes the intent unambiguous.

## Pattern Matching Analysis

### Match Exhaustiveness Checking
For discriminated unions:
- Check all union cases are covered
- Allow wildcard `_` as catch-all
- Report missing cases if non-exhaustive

Guard handling:
- Guarded arms do not count toward coverage (only partial)
- Unguarded arms count as full coverage
- Catch-all bindings (`_` or plain identifiers) cover all remaining cases

Skipped when:
- Non-union types (can't enumerate all values)

### Pattern Type Checking
- Validates pattern variables have correct types
- Ensures property patterns match union case properties
- Type checks guard expressions (must be bool)

## Circular Import Detection

Project compilation detects circular file imports before semantic analysis:
- **Self-import**: File importing itself (A -> A)
- **Two-file cycle**: A -> B -> A
- **Longer chains**: A -> B -> C -> A and longer cycles
- Reports `ErrorCode.CircularImport` (NL703) with a bounded cycle path and a suggested refactor to extract shared declarations or invert one dependency

The analyzer still has a shallow per-file guard in `ProcessFileImport` for direct self-import and two-file cycles, but `MultiFileCompiler` owns the complete project-level graph diagnostic.

## Error Reporting

Analyzer emits `CompilerError` records with:
- **Error code**: `NL001`-`NL999` (see `ErrorReporting.cs`)
- **Message**: Human-readable description
- **Location**: File, line, column
- **Suggestions**: Helpful hints (e.g., "Did you mean X?")

## Testing

Analyzer coverage is split deliberately across:

- `src/NSharpLang.Compiler.BootstrapServices/AnalyzerDeclarationContext.tests.nl` for the N#
  declaration catalog, source ownership, visibility, imports, members, and exact runtime
  projections.
- `src/NSharpLang.Compiler.BootstrapServices/TypeInfoIdentityFacts.tests.nl` for nominal,
  structural, runtime, and metadata-only identity and conversion rules.
- `tests/AnalyzerTests.cs` for analyzer-shell diagnostics, flow analysis, call binding, and
  end-to-end semantic behavior.

Keep ownership-policy tests beside the N# owner. C# tests should exercise only the remaining
diagnostic/integration shell, not recreate semantic lookup or identity policy in test helpers.
