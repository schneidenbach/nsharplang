# Analyzer Component

**Files:** `src/NSharpLang.Compiler/Analyzer.cs`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerDeclarationContext.nl`,
`src/NSharpLang.Compiler.BootstrapServices/TypeInfoIdentityFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerConversionFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerCallableReferenceFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerWellKnownTypes.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerWellKnownTypeFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerClrTypeConversion.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerAssignabilityFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerExternalTypeProbe.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerTypeReferenceFacts.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerScopeStack.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerProjectDiscovery.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerTypeResolver.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerTypeSubstitution.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerStructuralAssignability.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerDiagnosticSink.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerStateModels.nl`,
`src/NSharpLang.Compiler.BootstrapServices/AnalyzerDiagnostics.nl`

## Responsibility

Performs semantic analysis, type checking, and name resolution on the AST.

`Analyzer.cs` is the diagnostic/scope shell. `AnalyzerDeclarationContext.nl` is the N# owner for
the project declaration catalog, case-sensitive canonical source-type identity, file and namespace
imports, declared-alias identity and alias resolution, alias-cycle handling, owner-open generic
substitution, lexical nested-type lookup, and
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
- `IsSpanTypeName(string)` is the Span/ReadOnlySpan name gate for the implicit array-to-span
  conversion. It matches exactly four spellings — `Span`, `ReadOnlySpan` and their `System.`-qualified
  forms — and nothing else. (`LoopSequenceTypeFacts` has a same-named file-private helper that
  deliberately matches only the unqualified pair; the two are not interchangeable.)

Do not reintroduce any of these tables in C#, and do not grow this class with the rest of the
assignability closure — later families land in sibling N# owners.

`AnalyzerCallableReferenceFacts.nl` is the N# owner for the callable / delegate-reference
classification family — what a value that names code IS:

- `IsMethodGroupReferenceType(TypeInfo)` is true for the three method-group shapes
  (`ReflectionMethodInfo`, `ReflectionMethodGroupInfo`, `NSharpMethodGroupInfo`). The shape decides;
  an empty group is still a group.
- `HasSourceFunctionIdentity(FunctionTypeInfo)` is the method-group-versus-lambda discriminator: a
  non-empty `SourceName` means the function type came from a DECLARED function. The synthetic name
  is never consulted.
- `IsCallableReferenceType(TypeInfo)` unions the two — the predicate behind the
  `MethodGroupUsedAsValue` diagnostic and behind `IsAssignable`'s rejection of a bare method
  reference as a value.
- `IsRuntimeDelegateType(Type)` classifies concrete CLR delegate types, excluding the two abstract
  roots. The roots are read out of the core library with the `typeof(object).get_Assembly()` idiom
  rather than written `typeof(Delegate)`, because the columnar front end's `typeof` surface does not
  carry them; the resulting Type instances are the runtime ones, so a delegate loaded into a
  MetadataLoadContext still answers false, exactly as before.
- `GetFunctionParameterModifier(FunctionTypeInfo, int)` is the total modifier read (absent or short
  modifier list ⇒ `None`), and `NormalizeDelegateParameterModifier` erases `params` to `None` for
  delegate-signature matching while keeping `ref` and `out`.
- `CreateFunctionTypeInfoFromGenericDelegate(GenericTypeInfo)` reifies `Func<…>` / `Action<…>` into a
  `FunctionTypeInfo` signature — `Func` takes its last type argument as the return type and needs at
  least one, `Action` takes them all as parameters and returns `void`. The match is on the simple
  name and is case-sensitive; every other name returns null.

Do not reintroduce any of these predicates in C#, and do not grow this class beyond the
callable/delegate family.

`AnalyzerWellKnownTypes.nl` is the N# owner for the analyzer's well-known-type FACT BAG. One
instance is built per analysis from the analyzer's `MetadataLoadContext` and caches every CLR type
the semantic phase compares against or constructs generics over: the 16 required core types, plus
`System.Type` and `System.Delegate`, plus the optional open generics (`Nullable`, the generic
collection interfaces and implementations, `Task`/`ValueTask`, `IQueryable`, `JsonTypeInfo`, the
`Action`/`Action`1-4` and `Func`1-5` delegate roots), plus a LAZY `GetRuntimeUnionOpen()` /
`GetRuntimeResultOpen()` pair that resolves `NSharpLang.Runtime.Union<,>` and `Result<,>` on first
read and absorbs a missing runtime assembly.

- These are METADATA types, not the compiler's own `typeof(...)` types. That distinction is the
  whole point of the class: it lets the analyzer reason about the project's reference set. Do not
  replace a field here with a `typeof`.
- Required types throw at construction when absent — an analyzer that cannot see `System.Int32`
  cannot produce trustworthy diagnostics. Optional types stay null and every consumer tolerates it.
- Each name is probed in the core assembly first and then in `System.Private.CoreLib`, because a
  reference set can split the framework across facades and implementations.
- The core assembly is PASSED IN rather than read off the context: `MetadataLoadContext.CoreAssembly`
  is not on the columnar front end's external binding surface, and extending that surface is a
  compiler-capability change requiring a two-stage bootstrap. The single C# construction site reads
  it and hands it over.
- The lazy accessors are METHODS, not properties, because the `.nl` surface has no block-bodied
  property. The first read decides and the answer never changes for the rest of the analysis.

`AnalyzerWellKnownTypeFacts.nl` is the N# owner for the policy that is a pure function of that bag.
Three tables live there and are deliberately kept apart:

- `KnownOpenGenericType(facts, name, arity)` maps the compiler-known generic names — the ones a
  project may write WITHOUT an import — to their open CLR definitions. It is consulted both when
  constructing a generic type AND by unresolved-type reporting, so a name added here silently stops
  being reported as missing. The match is arity-exact, case-sensitive, and accepts only the
  spellings listed (`Result` and `NSharpLang.Runtime.Result`; `JsonTypeInfo` and its full name).
- `BindingSurrogateOpenGenericType(facts, name, arity)` is the SMALLER vocabulary used when a
  generic is reconstructed with `object` surrogates for N#-defined type arguments, purely so CLR
  method binding can proceed. It deliberately omits `Result`, `JsonTypeInfo` and every qualified
  spelling — those are only meaningful with real type arguments. Merging the two tables would
  silently widen the surrogate surface; they stay separate, the same discipline the two numeric
  vocabularies in `AnalyzerConversionFacts` are held to.
- `BuiltInRuntimeClrType(TypeInfo)` is the fallback used when no metadata facts exist at all. It
  answers with RUNTIME types, covers the built-in simple types plus arrays, nullables and oblivious
  wrappers, and — unlike the metadata-backed path — resolves NO aliases as it descends. That
  difference is behaviour, not an oversight. `void` and `Nullable<>` are read out of the core library
  with the `typeof(object).get_Assembly()` idiom because the columnar `typeof` surface does not carry
  them.

Do not reintroduce any of this in C#, and do not put policy in `AnalyzerWellKnownTypes` — that class
only resolves and holds.

### Alias identity and alias resolution

Alias resolution is a DECLARATION-CONTEXT fact, not a scope-stack walk. `DeclareType` registers the
`AliasTypeInfo` instance it builds for a `type X = …` declaration with the declaration context
(`RegisterDeclaredAlias`), so the context's catalog — which is keyed by TypeInfo REFERENCE identity
— contains the same instance the analyzer's scope hands back. That registration is instance-only:
the canonical `typesByFile` entry for an alias NAME stays the RESOLVED target type the context
computes for the declaration, so name lookup is untouched. Do not "simplify" this by routing aliases
through `RegisterCanonicalType` / `TryGetCanonicalType` — that would replace the alias with its
target in the analyzer's scope and poison the context's own alias resolution.

`AnalyzerDeclarationContext.ResolveDeclaredAlias(TypeInfo)` is the N# owner for what `Analyzer.cs`
used to call `ResolveTypeAlias`: it normalizes a declared alias — and the `ObliviousTypeInfo`
wrapper, the other transparent shell — down to the type it names, resolving the aliased type
reference against the alias's OWN declaring file and walking to a fixed point. A reference-identity
cycle answers `unknown`; an alias the context does not own is transparent to it; every other
TypeInfo is its own answer. It normalizes the value it is handed and never rewrites type arguments
nested inside another family.

Because the aliased reference is resolved by the declaration context rather than by the scope stack,
an alias used as a GENERIC ARGUMENT (`type Boxed = Box<IntList>` where `type IntList = List<int>`)
now resolves through, where the scope-stack path left the argument as a bare `AliasTypeInfo` and
produced a false `NL202` whose `expectedType` printed the internal class name
`NSharpLang.Compiler.AliasTypeInfo`. That false positive is gone; nothing else in the corpus moves.

### The CLR-conversion funnel

`AnalyzerClrTypeConversion.nl` is the N# owner for every TypeInfo → CLR `Type` construction the
semantic phase performs. It is built from the declaration context and the well-known-type bag, and
it reports nothing and records nothing: a conversion that cannot be made is a null answer and the
caller decides what that means. Its two entry points are NOT interchangeable.

- `TryConvertTypeInfoToClrType(TypeInfo)` is the EXACT conversion. It answers null the moment any
  position names a type the CLR does not have — which is every N#-declared class, record, struct,
  interface, union, enum and newtype — because a caller holding a `Type` must be able to trust that
  it denotes the type the program actually wrote.
- `TryConvertTypeInfoToClrTypeForBinding(TypeInfo)` is the SURROGATE conversion. Where the exact one
  gives up on an N#-declared type it substitutes `object` so CLR-level method binding can proceed;
  the real N# types stay tracked separately as TypeInfo bindings. Never use it where the answer is
  treated as the program's type.
- `TryConstructDelegateType(FunctionTypeInfo)` is public only because the lambda-to-delegate path
  asks for a delegate directly rather than through a type-shaped entry point. A `void` return picks
  the `Action` family (arities 0-4), anything else picks `Func` (parameter arities 0-4), and a wider
  signature answers null.

Both entry points resolve declared aliases at EVERY position they descend through, so
`type Meters = int` converts identically as an array element, a nullable inner type, a type
argument, a delegate parameter or a union arm. `JsonTypeInfo<T>` is the ONE generic whose type
argument may come from the surrogate conversion — source-generated JSON metadata over N#-declared
types is the reason the surrogate exists — and both spellings of the name carry that exception.
An anonymous union reifies as `NSharpLang.Runtime.Union<,>` at arity two and at no other arity.

The well-known-type bag is NULLABLE and that state is live: until the analyzer has loaded its
`MetadataLoadContext` there are no metadata facts and the funnel falls back to
`AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType`, which answers with the COMPILER's own runtime
types and resolves no aliases as it descends (the top-level alias is still resolved — that happens
before the facts are consulted). Because the bag is built and torn down over an analyzer's lifetime,
`Analyzer.cs` REBUILDS the owner at those two points rather than mutating it; the owner's own fields
never change after construction. Do not give the owner a setter, and do not reintroduce any of this
in C#.

`ResolveType(TypeReference)` — the diagnostic-reporting, semantic-model-recording, MLC-probing
type-REFERENCE engine — is a different thing and remains the analyzer shell's own. It is not a
dependency of the funnel.

### The assignability shape decisions

`AnalyzerAssignabilityFacts.nl` is the N# owner for the ARMS of the analyzer's assignability
question: which generic instantiations stand in a known assignable relation and which of those are
covariant, structural function-type assignability, which types a collection expression may target
and what element type it then demands, when an array widens to a span, which types a delegate
reference conversion may cross, whether a type is reference-like for variance, whether a CLR type is
a concrete delegate, and what expected type a bare callable reference can bind to at all. Like the
conversion funnel it is built from the declaration context and the well-known-type bag, is REBUILT
at the two points where that bag changes, and reports and records nothing.

- The known-generic relation is a CLOSED table over the runtime collection interfaces and it does
  not run backwards: `IEnumerable` accepts `IEnumerable`/`List`/`ICollection`/`IList`/`HashSet`/
  `Queue`, `ICollection` accepts `List`/`IList`/`HashSet`, `IList` and `IReadOnlyList` accept `List`,
  `IReadOnlyCollection` accepts `List`/`IReadOnlyList`/`HashSet`/`Queue`, `IQueryable` accepts only
  itself. BOTH sides must carry the real runtime generic definition, so a program's own type that
  merely shares the name never acquires the relation.
- Only the four read-only/streaming targets (`IEnumerable`, `IQueryable`, `IReadOnlyCollection`,
  `IReadOnlyList`) are COVARIANT in their argument, and only for reference-like arguments. The
  mutable ones are invariant on purpose: `ICollection<Animal>` must not accept an
  `ICollection<Dog>`, or a caller could add a cat.
- Collection-expression targets are matched by TWO arms that are deliberately different: the generic
  arm accepts fifteen spellings and requires the real runtime definition, while the reflection arm
  matches twelve metadata names and refuses an OPEN definition — `List<>` names no element type, so
  answering with its type parameter would hand a caller a `T` as if it were the element.
- `T[]` → `Span<T>`/`ReadOnlySpan<T>` is nominal on the target and invariant on the element, with
  aliases resolved on both halves.
- A bare callable reference binds only to a source function type, the two delegate generics by NAME
  (`Func`, `Action`), or a real runtime delegate; the nullable and oblivious shells are transparent.
  A concrete delegate is one that derives from the load context's `System.Delegate` WITHOUT being
  one of the two abstract roots, and without metadata facts nothing is a delegate at all.

THE PENDING-PAIR PROTOCOL. The known-generic and function-type decisions cannot finish without
re-entering assignability, and the owner does not call back. Instead they answer with an
`AnalyzerAssignabilityDecision`: either a DECIDED verdict, or the ORDERED target/source pairs whose
assignability the caller must answer, the relation holding exactly when every pair does. Note the
directions a function type hands back: a parameter pair is source ← target while the return pair is
target ← source, and an inferred (unknown) source parameter is ACCEPTED without a pair rather than
rejected, because a lambda still being inferred must not be pre-judged. The protocol's other half is
now `AnalyzerAssignability` (below) rather than a C# shell: the two shells in `Analyzer.cs` are
DELETED and the recursion they expressed is simply a call.

### The assignability decision itself

`AnalyzerAssignability.nl` owns the whole strongly-connected component — `IsAssignable`, `IsSubtypeOf`,
`HasImplicitConversion`, the delegate scorers, the lambda arm and the two absorbed pending-pair
shells. There is no sub-cut of its interior: every member re-enters `IsAssignable`, which is why it
is one owner and not several.

THE DISPATCH ORDER IS THE SPECIFICATION. Moving one arm past another changes the language:

- Identity, `null`, `never` and the three unknown KINDS answer first, so error recovery never
  produces a second diagnostic and the bottom type is universally assignable.
- BY-REF is symmetric and TOTAL: if EITHER side is by-ref the answer is "both are, over equal inner
  types", and no later arm is consulted — not even the `object` arm.
- The UNION arms come before everything structural. A target union needs ONE arm to accept; a source
  union needs EVERY arm to be assignable.
- The CALLABLE-REFERENCE arms come before `object`. A bare method group is not a value, so it is NOT
  assignable to `object` — that single exception is what forces the whole ordering, and it composes:
  a union with a method-group arm is not assignable to `object` either.
- FUNCTION-TYPE structural comparison comes before the identity fallback, because every
  `FunctionTypeInfo` renders identically.
- The USER-DEFINED conversion is LAST, so a conversion operator can never shadow a built-in relation.

THE RE-ENTRANCY GUARD IS CORRECTNESS, NOT AN OPTIMISATION. A user-defined implicit conversion can
name types whose own conversions name it back; without the active-pair guard `HasImplicitConversion`
recurses forever. `AnalyzerImplicitConversionGuard` holds it as two parallel `List<TypeInfo>` — an
EMITTED type cannot key a dictionary on the columnar surface — scanned with the static
`Object.Equals`, which is the same virtual equality a set of pairs would use. It lives OUTSIDE
`AnalyzerAssignability` because that owner is REBUILT whenever the well-known-type bag is built or
torn down, and the guard must survive that rebuild.

THE DELEGATE SCORE LADDER. `TryGetDelegateSignatureConversionScore` answers a SCORE rather than a
verdict — 8 exact, 4 a reference conversion, 2 an open type parameter, 1 an unknown — and that ladder
is what makes an EXACT overload beat a merely convertible one. A method-group match needs equal arity
and equal ref-ness (`params` erases to `None`, `ref`/`out` do not), an unknown source parameter
contributes nothing rather than failing, and the RETURN is scored in the reverse direction, which is
covariance.

### The FunctionTypeInfo factory

`AnalyzerFunctionTypeFactory.nl` builds every `FunctionTypeInfo` the analyzer has, from four sources
that are not interchangeable: a CLR delegate type, a source function declaration resolved against the
file being analysed, the same declaration resolved against ANOTHER file's declaration context, and a
declared member read off a type's member table (optionally as seen from a declaring owner).

- The `Func`/`Action` ARITY TABLES answer WITHOUT consulting nullability metadata; every other
  delegate goes through `Invoke`, where the annotations do apply. `Func` takes its last type argument
  as the return type, `Action` takes them all as parameters.
- An `Expression<TDelegate>` unwraps to its delegate first, including through a by-ref shell. The
  test there is the delegate ROOT (`System.Delegate` is assignable from the argument) — NOT the
  concrete-delegate test, which excludes the two abstract roots.
- A function's OWN type parameters shadow: each is bound to a `SimpleTypeInfo` of its own name before
  any reference resolves, so `func F<T>(x: T)` names `T` rather than resolving it in scope.
- THE ASYNC CALL-RETURN RULE: only an async non-generator is wrapped; `main` gets the `Task` family
  (case-insensitively) and everything else `ValueTask`; a declared type that is already task-like is
  left exactly as written, which is what lets a function declare `Task<int>` explicitly.

### CLR type → TypeInfo conversion

`AnalyzerReflectionTypeConversion.nl` is the opposite direction from the conversion funnel above:
that owner asks what CLR type an N# type denotes, this one what N# type a reflected type denotes. It
is TOTAL — every `Type` converts, with `ReflectionTypeInfo` as the catch-all.

- The built-in table is keyed on `FullName`, NOT on `typeof`, and that is load-bearing: under a
  MetadataLoadContext the projected `System.Int32` is not `typeof(int)`. It is consulted FIRST, ahead
  of the by-ref/array/generic arms — a by-ref `int&` has `FullName` "System.Int32&" and falls past it
  on its own.
- THE OVERRIDE IS DATA, NOT A CALLBACK. `AnalyzerReflectionTypeOverride` carries the TypeInfo
  overrides, the CLR bindings and which of two composition rules applies, so the nullability reader
  can consult it at every leaf without a function crossing a boundary. The DIRECT rule always composes
  through the override walk; the BOUND rule applies the CLR bindings to the type itself and converts
  the RESULT whenever there is nothing left to substitute. The two are not interchangeable: the
  override walk builds a `GenericTypeInfo` over converted arguments, while applying bindings first
  yields a closed CLR type that converts as one reflected instantiation.
- An override never DECLINES, and an EMPTY override is therefore not the same as NO override: with no
  override an unbound generic parameter reads as the walk's named `SimpleTypeInfo`, while an empty one
  answers the plain conversion, which reads it as a reflected type.

### The two arms that look something up

`AnalyzerStructuralAssignability.nl` owns the two assignability arms that are NOT decidable from the
two types alone, and they are kept out of `AnalyzerAssignabilityFacts` so that class can stay silent.

- THE DUCK-INTERFACE ARM (`ImplementsDuckInterface` + `MethodSignaturesMatch`) is the only EFFECTFUL
  member of the whole assignability closure: comparing two members means RESOLVING the references
  they were declared with, and that walk records into the semantic model and can report. A source
  satisfies a duck interface when it declares a matching function for every FUNCTION the interface
  declares. Only function members are demanded and only function members can satisfy them, in both
  directions. A source with no declared-member list at all — a CLR type, a built-in, an array, an
  interface — satisfies NOTHING, including the empty duck interface, because the member list is
  consulted before the interface's demands are; a class, struct or record with an EMPTY member list
  does satisfy it. Signature equality is by the RESOLVED type's display form, an absent return type
  means `void`, and the resolution ORDER is behaviour: parameters are resolved in pairs, left to
  right, and the first mismatch stops the walk, so a rejected candidate's later references are never
  resolved and never recorded.
- THE ACTIONRESULT ARM answers that ASP.NET Core's `ActionResult<T>` accepts whatever the
  non-generic `ActionResult` accepts. It refuses unless the target is a one-argument generic named
  `ActionResult` or `Microsoft.AspNetCore.Mvc.ActionResult`, the source is a CLR type, and the
  referenced-assembly probe actually finds `Microsoft.AspNetCore.Mvc.ActionResult` — so it is inert
  in a project that does not reference ASP.NET Core.

`IsAssignable` itself, and the arms that re-enter it, remain in `Analyzer.cs` for ONE measured
reason, and it is no longer the duck arm, the metadata probe, or the columnar surface: the
capability landed in slice 12 stage A (five type rows in `ColumnarExternalBindingPlans`, the two
computed closed-`IList<T>` identities their attribute sequences answer with, and one enum
static-member row — **no call plan, because a supported plan would PRE-EMPT
`ColumnarOrdinaryRuntimeDirectCallResolver` terminally and a value receiver like
`CustomAttributeTypedArgument` cannot survive that**), and stage B then N#-owned the reader itself.
That was the last blocker, and the SCC has since landed WHOLE. `IsAssignable`'s callable-reference
arm builds a runtime delegate's signature through `AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate`,
and every other member of the closure (`IsSubtypeOf`, `HasImplicitConversion`, the delegate scorers,
the lambda arm and the two former protocol shells) lives beside it in `AnalyzerAssignability` — no
sub-cut of the interior exists, so the whole component moved in one cut, with no callback, no
fallback and no protocol left.

### The nullability metadata reader

`NullabilityMetadataReflection.nl` is the N# owner of the reflection half; `NullabilityMetadataCore.nl`
already owned every decision that is a pure function of facts, and the two compose. The reader
answers a `TypeInfo` for a CLR `Type`, `PropertyInfo`, `FieldInfo`, `ParameterInfo` or a method's
return, and the display forms (`FormatType`, `FormatParameter`, `FormatReturnType`, `FormatTypeInfo`)
that hover, completion and every diagnostic that prints a CLR member signature read.

- The walk strips by-ref, answers the type override, converts, and only then applies the read state.
  A NULLABLE VALUE TYPE is never wrapped in an oblivious or nullable layer of its own — it already
  IS one. Every reference layer carries its own state, so `string[]` answers
  `Oblivious(Array(Oblivious(string)))`: the array and its element are annotated separately.
- THE TYPE OVERRIDE is consulted TWICE — once before the walk for a generic parameter, and again at
  the leaf for a type the walk did not decompose. A null answer means "decline", and falls through
  to exactly what no override at all would produce.
- THE OVERRIDE CROSSES THE BOUNDARY AS `Func<Type, object>`, not `Func<Type, TypeInfo>`. A closed
  `Func` over an EMITTED type is off the columnar surface (`emit.declaration.method-param`), while
  one over `object` is on it, so the N# owner takes `object` and casts once. The C# call sites keep
  their own `TypeInfo`-returning lambdas verbatim; the conversion is the C# compiler's own implicit
  reference conversion.
- FOUR FLOW ATTRIBUTES are recognised and no others: `MaybeNull`, `NotNull`, `NotNullWhen` and
  `ParamArray`. `MaybeNullWhen`, in particular, contributes nothing — an out parameter annotated
  with it renders as a plain `out string? value`.
- **THE ATTRIBUTE ARGUMENT MUST BE TESTED BY VALUE, NEVER BY `ArgumentType`.** Under a
  MetadataLoadContext — which is how the analyzer sees every external assembly —
  `CustomAttributeTypedArgument.ArgumentType` is a PROJECTED `System.Boolean` that is not
  `typeof(bool)`, while `Value` is still a live boxed CLR bool. Comparing the boxed value against
  boxed `true`/`false` is exact in both worlds; comparing the type silently drops every
  `[NotNullWhen(...)]` prefix on MLC-loaded members. This was found by a differential, not by
  reading.

Three shape rules the port keeps, each one found by a decline and pinned by the owner's contracts in
`NullabilityMetadataReflection.tests.nl`:

- `new NullabilityInfoContext()` does NOT emit — the emitter's `new` chain is a name table that does
  not model the type. Construct through `typeof(T).GetConstructor(...)` + `ConstructorInfo.Invoke`,
  the idiom `ExternalAssemblyScan.CreateMetadataLoadContext` already uses; the argument array must be
  declared `object?[]` or the analyzer refuses the `Invoke` overload.
- `GetCustomAttributesData()` and `ConstructorArguments` answer a closed `IList<T>`. `get_Item(int)`
  binds directly, but `Count` is declared on `ICollection<T>` and an interface receiver's own member
  lookup reaches neither it nor `foreach`. Bind the sequence through an `object` local and read the
  non-generic `IList.Count`.
- A boxed `CustomAttributeTypedArgument.Value` cannot be unboxed by a cast, an `as`, or an `is` test;
  compare it against a boxed constant with `Equals`.

### Substitution-aware resolution

`AnalyzerTypeSubstitution.nl` owns type-reference resolution AS SEEN FROM A DECLARING TYPE — the
question a member read off a declared type asks, as opposed to the plain walk's "what does this name
mean in the file being analysed".

- `ResolveGenericDefinition` answers the open definition an instantiation CARRIES, falling back to
  the bare name in scope. The carried definition answered every one of the corpus's 6,172 lookups.
- `GetSourceDeclarationOwner` answers which declaration a type is declared by, plus the substitution
  its arguments induce. An alias answers for the type it names. A generic over an N#-declared
  definition answers the DEFINITION with the binding; a generic whose definition is a CLR type is NOT
  substituted, because reflection already carries its own arguments and re-substituting would
  double-apply them.
- `ResolveTypeForSourceOwner` asks the declaration context first — which answered all 22,245 corpus
  and 4,112 suite calls, zero fallbacks — and only then walks the substitution itself.
- The substitution walk's ORDER is behaviour. A simple name the binding BINDS answers with the bound
  type and never reaches the resolver, so it writes no semantic-model record; a simple name it does
  not bind falls all the way through to the plain walk rather than into the composed arms. Generic,
  array and nullable references are rewritten; a tuple, function, union or by-ref reference is handed
  to the plain walk untouched even under a live binding. A generic head is resolved by the PLAIN walk
  — that is what records it and finds the open definition — and only its arguments are rewritten, so
  the instantiation keeps its nominal identity.

### The type-reference resolver

`AnalyzerTypeResolver` (`AnalyzerTypeResolver.nl`) is the SOLE authority for turning a `TypeReference`
into a `TypeInfo`, for every diagnostic that walk reports, and for every semantic-model and
binding-map record it writes. `Analyzer.cs` holds no resolution policy: it constructs the resolver
once, tells it which file an analysis is about, and calls it. The owners below are the decision tables
the walk consults; they are handed to it by argument, so nothing in the walk names the shell.

`AnalyzerExternalTypeProbe.nl` is the N# owner for every question answered by looking at referenced
assembly metadata. It is constructed ONCE per analyzer, holds the resolution cache, and is never
rebuilt — the two other analyzer owners are rebuilt when the well-known-type bag changes, and this one
must not be, because its cache is part of the answer.

- `ResolveExternalType(name)` is the ordered probe: the bare spelling as previously cached, then for
  each imported namespace IN IMPORT ORDER `"<namespace>.<name>"` — cached, then resolved against every
  loaded assembly in load order — then, failing all of that, the first assembly that EXPORTS a type
  whose simple name or full name equals the spelling.
- **The cache participates in that order and is therefore behaviour, not an optimisation.** The
  exported-name scan caches under the BARE spelling, so a later call short-circuits at step 1 and
  never reconsiders the imports. Dropping or rebuilding this cache mid-analysis can change an answer.
  Misses are NOT cached, so a name that fails before an assembly loads is genuinely retried.
- `ResolveExactExternalType(fullName)` does no prefixing and no exported-name scan, which is what lets
  import validation tell a namespace from a type. It shares the one cache in both directions.
- `KnownGenericHeadArities(facts, name)` is the ascending arity sweep behind "available arities are
  ...": the compiler-known table first, then the arity-qualified metadata probe (`Name`1`, `Name`2`,
  ... up to the CLR's limit of 17), which must land on an open DEFINITION to count.
- The assembly list and the using-namespace list are the analyzer's LIVE collections, held by
  reference: both grow as imports are processed and the probe must see the additions. Do not snapshot.

`AnalyzerTypeReferenceFacts.nl` is the N# owner for the walk's pure rules.

- `BuiltInSimpleType(name)` is the sixteen spellings resolved before any other channel. `null`,
  `never` and the inference/deferred holes are deliberately absent: those are types the analyzer
  synthesises, not names a program can write at a type position.
- `GenericHeadArity(TypeInfo)` distinguishes ZERO — "I know this head and it takes no type
  parameters", which the caller reports as an error — from -1, "unresolved external text, arity cannot
  be checked here", which is silent. A CLOSED reflected generic answers 0, not its argument count; only
  an open DEFINITION answers its parameter count. Enums, aliases and newtypes answer 0, so `Color<int>`
  is reportable and an alias is reported on the ALIAS rather than on its target.
- `VisibleTypeNamespaces(current, imports)` is the candidate order for project-wide discovery: the
  current namespace first — as `null` when the file declares none, because the global namespace is a
  real candidate and not an absence — then each import in declaration order, first occurrence winning,
  compared case-sensitively.

`AnalyzerDiagnostics.UnresolvedTypeSuggestion(name, candidates)` holds the "did you mean" policy for
`NL201`: the nearest candidate within a case-insensitive edit distance of 2, candidates under three
characters skipped (at that length everything is near everything), the name itself skipped, ties
keeping the caller's FIRST candidate so the suggestion is stable rather than hash-ordered.

#### The eight channels

`ResolveSimpleType(name, line, column)` tries, IN ORDER: the built-in name table; the scope stack; the
current file's import aliases; a dotted nested type; project-wide discovery; a namespace alias
resolved as a type; the referenced-assembly probe; and finally an unresolved `ExternalTypeInfo`
placeholder. The order is behaviour — a local declaration shadows a project type, and a project type
outranks a CLR type of the same name — and so is the fact that the last channel is a PLACEHOLDER
rather than an error type: analysis carries on with a named stand-in.

The using-alias channel is measured DEAD in every population (corpus, unit suite and fixtures) and is
preserved verbatim rather than deleted: `RegisterNamespaceImport` only records an alias after
`ValidateNamespaceImport` has proved the target is a namespace and not a type, so the aliased full
name can never resolve as a type. It is structurally unreachable, not merely unexercised.

`line <= 0` means "no source position". The walk still resolves through every channel, but it records
no binding, reports nothing, and — for a generic reference — skips the whole head probe, so the
resolved `GenericTypeInfo` carries no definition. One asymmetry follows from the ordering and is
deliberate: `var` at a real position is refused with `NL103`, while `var` at line 0 falls through
every channel to the placeholder, because the `var` check is the only thing that recognises it.

#### The ten report sites

All of them live in the resolver, and all of them go through `AnalyzerDiagnosticSink`:

- `NL201` for a claimed file alias, for an undotted simple name, and for a generic name;
- `NL207` for a spelling available at several arities ("available arities are ...") and for an arity
  mismatch against a known head;
- `NL103` for `var` used as a type and for a SoA `.Row` reference;
- `NL306` for a repeated anonymous-union arm and `NL207` for more than two distinct arms;
- `NL308` for an inaccessible project declaration.

`NL201` and the two `NL207` shapes are gated on the REPORT OPT-IN, which is off by default and turned
on only by `ResolveDeclaredType` — parameter, return, field, property, variable annotation, type alias
and `new` positions. Pass-1 signature collection and lazy cross-file member resolution run without
generic type parameters in scope and must stay lenient, which is why the opt-in exists at all. Dotted
names are lenient even at a declared-type position: a namespace-qualified external or a
`new Union.Case` reference legitimately resolves through another channel.

The open-generic head probe forces the opt-in OFF for its own name resolution and then consults the
CALLER's opt-in for all three of its reports. CLR open generics carry an arity suffix (`List` resolves
as ``List`1``), so the plain simple-name probe legitimately misses external generic types; reporting
the head probe's own miss would be a false positive on every `List<int>`.

#### The dedupe sets

Two sets, both keyed by `(name, line, column)` and both cleared once per analysis. The
unresolved-reference set is shared by all five `NL201`/`NL207` sites AND by the two inaccessible-member
reports the shell still owns outside the walk (the `new Union.Case` probe and the identifier-binding
probe), which route through `MarkUnresolvedTypeReported`. That sharing is the point: the first report
at a position suppresses every later one there, so an inaccessible member is not also reported as an
unresolved type. The SoA-row set is separate, because its report is not an unresolved-type report —
and note that a repeat `.Row` reference still ANSWERS true (the reference is still refused); only the
diagnostic is suppressed.

#### The records

`RecordTypeReference` fires on EVERY `ResolveType` call, at the reference's own start span, and is
what hover and the semantic-token pass read; a reference with no valid span is skipped. `RecordType`
fires on the file-alias and project channels, and `RecordBinding` on the scope, file-alias and project
channels — the last of these is what makes go-to-definition work across files. The semantic model and
the binding map are REPLACED per analysis rather than cleared, so they arrive through `BeginAnalysis`
rather than being held from construction.

#### The diagnostic sink

`AnalyzerDiagnosticSink` (`AnalyzerDiagnosticSink.nl`) is the single authority for turning a semantic
finding into a `CompilerError`. It is given the analyzer's OWN `_errors` list rather than owning one,
which is what keeps report ORDER meaningful: the shell's remaining reports and the resolver's reports
append to one list, so a diagnostic's position among its neighbours does not depend on which side of
the boundary produced it. The snippet is the analysed file's own text when there is one and the
project snapshot's copy otherwise (the unsaved-editor-buffer path); no text and line 0 both mean no
snippet, which is what makes `AnalyzerDiagnostics.Create` fall back to the detail-only shape. `NL308`
lives here too, because its message names the DECLARING file's namespace, read from disk through the
project source provider.

One member of this family is NOT movable yet, for a recorded reason rather than by omission.
`NamespaceExists` and `GetExternalSearchAssemblies` deduplicate the loaded assemblies by
`Assembly.FullName`, and neither `Assembly.get_FullName` nor `AssemblyName.get_Name` is on the
columnar external binding surface; extending it is a compiler-capability change requiring a two-stage
bootstrap, so they stay. (`NamespaceExists`'s PROJECT half is N#-owned — see "Project discovery"
below — and only its metadata half is blocked.) `IsTopLevelTypeDeclaration` is no longer blocked and
is no longer name-based: `AnalyzerProjectTypeDiscovery.IsTopLevelTypeDeclaration` dispatches on the
declaration's own TYPE (`declaration as ClassDeclaration != null`, once per family), which is the same
decision the shell's `is ClassDeclaration or …` pattern made. The scope stack and the project channel
are no longer blockers — both are N#-owned; see the next two sections. The resolution surface has no C# piece left:
`CreateFunctionTypeInfoInDeclarationContext` is now
`AnalyzerFunctionTypeFactory.CreateFromDeclarationInFile`, which resolves each reference through the
DECLARING file's context rather than the reader's, and deliberately does not carry a containing type
across.

### Project discovery

N# has no `using`-style TYPE import. A project's files see each other's exported top-level
declarations directly, so the resolver has to be able to look at every source file in the project —
enumerate it, read it, parse it, and read its declared namespace. `AnalyzerProjectDiscovery.nl` owns
that capability and the walk built on it, in two classes.

`AnalyzerProjectSourceProvider` is the SOURCE AND UNIT PROVIDER, constructed once per analyzer and
never rebuilt. It holds the four caches the shell used to hold:

- the in-memory SNAPSHOT of the project's source texts (`SetProjectSourceTexts` routes into
  `ResetSourceTexts` + `AddSourceText`), keyed by full path, case-insensitively;
- the parsed unit per file, including the NEGATIVE answer — a file that fails to parse caches a null
  unit and is never re-parsed;
- the set of namespaces the project ROOT declares, per root;
- the namespace each FILE declares, including the negative answer for a file that does not exist.

The lifetimes are deliberately asymmetric and are reproduced, not tidied: `Analyze` clears the two
NAMESPACE caches (`BeginAnalysis`) and nothing else, while a new snapshot (`ResetSourceTexts`) also
drops the parsed units, because they were parsed from the old texts.

**THE ENUMERATION ORDER IS PART OF THE ANSWER.** `SourceFilePaths()` returns the snapshot's keys in
INSERTION order when there is a snapshot, and `ProjectConfig.EnumerateSourceFiles` order otherwise.
Every walk over it takes the FIRST file that matches, and duplicate names across files are ordinary
rather than pathological — measured over this repository's own root project (440 files) there are 47
distinct (namespace, name) pairs declared by more than one file, `Person` by 14 files and `Main` by
42. So the order is behaviour. `AnalyzerDeclarationContext` depends on the same order, which is why
`AddProjectUnitsTo` hands it the units in it.

The two namespace questions read from DISK rather than from the snapshot, because they ask about the
project as it exists on the filesystem: `ProjectNamespaceExists` (which `NamespaceExists` consults
first) and `GetNamespaceForFile` (which `IsCrossPackageFile` and the `InaccessibleMember` message
consult). `ProjectSourceText` is the one place the two sources meet: snapshot, then disk, then empty.

`AnalyzerProjectTypeDiscovery` is the WALK. `ResolveVisibleProjectType` answers all THREE outcomes in
one call, because their ORDER is the semantics:

1. the visible-namespace sweep, in `VisibleTypeNamespaces` order, requiring export only for a
   namespace that is not the file's own — a hit records the declaring file for the project index;
2. otherwise, and ONLY when the caller has a real source position, the INACCESSIBLE decision: some
   visible namespace OTHER than the file's own declares this name and does not export it. The
   decision lives here and the REPORT stays in the shell, and this outcome SUPPRESSES step 3;
3. otherwise the project-wide unique-exported fallback.

The type channel and the function channel differ on duplicates, and deliberately: a duplicate type
name inside one namespace REFUSES to resolve (`AnalyzerDeclarationContext` requires uniqueness),
while the function channel and the inaccessible probe take the FIRST match. That is why the
enumeration order is decisive for the latter two and irrelevant for the first.

`TryResolveVisibleProjectFunction` returns the matched `FunctionDeclaration`, its file and its symbol
declaration; the shell then asks `AnalyzerFunctionTypeFactory.CreateFromDeclarationInFile` for the
`FunctionTypeInfo`. Nothing in this family is C# any more.

A resolved declaration's LINE is the declaration's own and its COLUMN is where the NAME starts on
that line (`CodeIntelligenceTextUtilities.FindIdentifierNameColumn`), which is what a
go-to-definition span has to point at.

### The scope stack

`AnalyzerScopeStack` (`AnalyzerScopeStack.nl`) owns the analyzer's open scopes and every question the
semantic phase answers by walking them. `Scope` was already N#; what moved is the STACK — the
container plus its walk semantics — so the shell holds one `AnalyzerScopeStack _scopes` field and no
walk of its own.

Three rules are behaviour rather than bookkeeping, and are why the stack has to be one owner:

- **Every name walk runs innermost-first, and the first scope that HAS the name answers.** A scope
  that binds the name under a different meaning still ends the walk. `IsCurrentTypeMemberReference`
  answers from the kind of the scope it stopped at; `IsErrorTupleResultAvailable` answers differently
  for an availability mark, a guard, and a plain symbol binding, whichever it meets first; the
  error-tuple guard walk stops at a scope that rebinds the result name, because past that point the
  name is not the guarded result. `LookupType` / `LookupSymbol` / `CurrentTypeScope` (the innermost
  binding of `this`) are the simple cases of the same rule, and `CurrentScopeSymbol` is deliberately
  the innermost scope ALONE — "is this name already mine?" rather than "is it visible?".
- **Two walks skip the innermost scope**, because their question is about an ENCLOSING binding.
  `FindEnclosingNullableSymbol` answers what an identifier was DECLARED as when the current scope
  holds its narrowed type, and it does not stop at a scope that binds the name to something
  non-nullable. `ShadowsEnclosingValueBinding` (the NL316 decision) starts one scope out and stops
  dead at the first type-level or global scope: a member or a global of the same name is not
  shadowing. Underscore-prefixed names, `this`, `value`, function declarations and names the scope
  also binds as a type are all not value bindings, so they neither shadow nor are shadowed.
- **The lexical scope stack and the semantic-scope-id stack move in lockstep.** `Push` opens a
  semantic scope parented to the id currently on top (−1 when there is none); `Pop` closes it at the
  analyzer's current line and column `int.MaxValue`. The id stack is popped only when non-empty while
  the scope stack is popped unconditionally, so the two can legally sit at different depths.

Two members that RECORD live here anyway, because what they record is reachable without a callback:
`BindingMap` and `SemanticModel` are themselves N#, so `RecordTypeBinding` and `ResolveBindingTarget`
take the map as an ARGUMENT and stay whole rather than being split into a decision plus a shell write.
Both are replaced per `Analyze` call, which is why they are arguments and not fields.
`ResolveBindingTarget` walks SYMBOLS before TYPES — an identifier in scope means the value first —
and records the declaration binding of whichever scope answered.

Null facts are flow-sensitive scope state: the innermost recorded fact for a path wins, an assignment
invalidates the path and every member path under it in EVERY open scope (a name that merely shares a
prefix survives), and presence is asked separately from value — a path with no fact is not the same as
a path recorded as `NullState.Unknown`, and `NullState?` is off the columnar surface.

Declaration POLICY stays in the shell because it reports: `DeclareSymbol`, `DeclareType`,
`CheckShadowedDeclaration`'s diagnostic and the file-import walk. What they use of the stack is the
DECISION (`ShadowsEnclosingValueBinding`) and the scope ACCESS (`Peek`, `GlobalScope`).

`Peek` and `Pop` on an empty stack, and `GlobalScope` on an empty stack, throw exactly what
`Stack<Scope>.Peek()`, `Stack<Scope>.Pop()` and `Enumerable.Last()` threw, message included. No
production path reaches them, but a silent change from one exception to another is still a behaviour
change.

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
The stack is `AnalyzerScopeStack` (N#, see "The scope stack" above); the shell's `PushScope` /
`PopScope` / `DeclareSymbol` / `DeclareType` route into it:
- `_scopes.Push(model, scope, line, column)`: open a lexical scope and its semantic scope
- `_scopes.Pop(model, currentLine)`: close both
- `DeclareSymbol(name, type)`: add to `_scopes.Peek()`, reporting duplicates and shadowing
- `_scopes.LookupSymbol(name)` / `_scopes.LookupType(name)`: innermost-first walk, first hit wins

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

### Pattern ownership

Every pattern DECISION is N#-owned. `Analyzer.cs` keeps one zero-policy driver, `AnalyzePattern`,
which is a request loop over the N# walk plus a five-case switch; each case performs exactly one
pre-existing analyzer operation (the expression walk, a symbol declaration, or one of the two SoA
escape reporters) with operands the walk supplied, and hands the answer back. The walk suspends and
resumes with that answer because a literal pattern's escape report is passed the type the analysis
before it produced, and a relational pattern's two escape reports are joined by `&&`, so the first
answer decides whether the second step and the comparability judgement happen at all.

The six N# owners:

| Owner | Decides |
| --- | --- |
| `AnalyzerPatternAnalysis.nl` | which of the thirteen arms a pattern node takes, what it binds, which union case it names, and its four NL503 reports |
| `AnalyzerPropertyPatternBinding.nl` | what an object pattern's property list resolves to and binds, and NL503 for a missing property |
| `AnalyzerPatternReachability.nl` | whether a type test can ever succeed (NL506), and whether a subtree carries a parser recovery artifact |
| `AnalyzerPatternShapes.nl` | a list pattern's element type (NL504) and a relational pattern's comparability (NL202) |
| `AnalyzerMatchExhaustiveness.nl` | whether a match covers everything its scrutinee can be (NL501) |
| `AnalyzerExhaustivenessSelector.nl` | which union case a pattern names, and which patterns are total |

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
- `tests/native/analyzer-identifier-binding` for what the analyzer BINDS an identifier to at an
  incomplete member access — the bound `ClassTypeInfo`, its name and anchor, its whole declared-member
  census in declaration order, and the analysis diagnostic census. This is a native N# project rather
  than an estate contract because `Analyzer` is the C# class in `Compiler.dll`, and `Compiler.dll`
  depends on BootstrapServices; every other type on that route (`SemanticModel`, `ClassTypeInfo`,
  `DeclaredMemberInfo`, `AnalysisResult`) is already N# in the estate.
- `tests/native/analyzer-event-subscription` for the `on` / `off` event diagnostics end to end —
  `NL317` on `+=` and `-=` over a real .NET event, `NL318` on `off` over a non-subscription, each
  with its whole message and suggestion, and the WHOLE diagnostic census rather than one code. It is
  a native project for the same reason as the row above, and it is the only coverage those two arms
  have that runs the real analyzer over real reflection: `EventRequiresOnOff` appears in NO estate
  contract, and `InvalidEventSubscription` appears in exactly one — `AnalyzerLambdaAnalysis.tests.nl`,
  over a kernel harness with a stand-in subscription root, for the `on`-target-is-not-an-event arm.
- `tests/native/analyzer-binding-map` for what `AnalysisResult.Bindings` answers — `GetBindingAt`
  over interpolation holes, member accesses, and type annotations in every composite position
  (nullable, array, generic argument, delegate argument), and `FindAllReferences` with its WHOLE
  usage list rather than a count floor. Same native route and same reason.
- `tests/native/analyzer-error-handling` for what the analyzer reports over MALFORMED and
  C#-SHAPED source — undefined variables and functions, type and return-type mismatches, wrong
  argument counts, duplicate declarations, unreachable code after `return` / two `return`s / `throw` /
  an if-else whose branches both return, missing returns, and `break` / `continue` outside a loop.
  Same native route and same reason. It also drives the **LINTER** over the same fixtures, and that
  pairing is why it is one project rather than two: **the two owners DISAGREE on the if-else case.**
  The analyzer reports `NL312:UnreachableStatement@7:5+1`; the linter reports NOTHING, while it does
  report `NL006` for the other three terminators. The empty linter census is pinned deliberately, so
  closing the divergence is a decision rather than an accident (task 020 slice 25).
- `tests/AnalyzerTests.cs` for analyzer-shell diagnostics, flow analysis, call binding, and
  end-to-end semantic behavior.

Keep ownership-policy tests beside the N# owner. C# tests should exercise only the remaining
diagnostic/integration shell, not recreate semantic lookup or identity policy in test helpers.
