# Analyzer Component

**Files:** `src/NSharpLang.Compiler/Analyzer.cs`,
`src/NSharpLang.Compiler.Core/AnalyzerDeclarationContext.nl`,
`src/NSharpLang.Compiler.Core/TypeInfoIdentityFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerConversionFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerCallableReferenceFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerWellKnownTypes.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerWellKnownTypeFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerClrTypeConversion.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerAssignabilityFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerExternalTypeProbe.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerTypeReferenceFacts.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerScopeStack.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerProjectDiscovery.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerTypeResolver.nl`,
`src/NSharpLang.Compiler.Core/TypeArityNames.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerTypeSubstitution.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerStructuralAssignability.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerDiagnosticSink.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerStateModels.nl`,
`src/NSharpLang.Compiler.Core/AnalyzerDiagnostics.nl`

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
  `Queue`/`IReadOnlyList`, `ICollection` accepts `List`/`IList`/`HashSet`, `IList` and `IReadOnlyList` accept `List`,
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
  It is searched on BOTH ENDS — the type converted FROM and the type converted TO — because a
  wrapper's `implicit operator Wrap<T>(value: T)` can only be declared on the target: the `T` end may
  be `int`, which declares nothing about `Wrap`. Each end's operator signature is read through that
  end's OWN substitution, so reached as `Wrap<int>` the operator is asked as `int -> Wrap<int>`.
- The three REFLECTED arms (both ends reflected; reflected target with a built-in source; built-in
  target with a reflected source) take an ACCEPTANCE and nothing else. They used to RETURN the CLR's
  `IsAssignableFrom` verdict, which sent every reflected pair to a type error before the user-defined
  arm below could be asked — `IsAssignableFrom` knows nothing about `implicit operator XName(string)`
  or `implicit operator DateTimeOffset(DateTime)`. A refusal now falls through, exactly as the
  constructed-generic bridge beside them already did.

USER-DEFINED CONVERSIONS AN EXTERNAL TYPE DECLARES ARE A SEPARATE ARM WITH A SHARED OWNER.
`DeclaresImplicitConversion` reads `DeclaredMembers`, which only a SOURCE declaration has, so a
referenced assembly's `op_Implicit` / `op_Explicit` was invisible to it. `ClassifyExternalConversion`
converts both ends through the EXACT CLR conversion (never the surrogate one) and asks
`ExternalUserDefinedConversions` — the SAME owner `ColumnarIlEmitter.TryEmitUserDefinedConversion`
asks for the handle to call, so the analyzer cannot accept a conversion the emitter then declines.

That owner implements ECMA-334 §10.5.3 (implicit) and §10.5.4 (explicit) rather than an exact
signature match: candidates are the operators declared by the source type, by the target type and by
their base classes (read `DeclaredOnly` per level — conversion operators are not inherited members);
applicability is decided by STANDARD conversions only, which is also why the search never recurses;
and the most specific source and target types must be spanned by exactly ONE operator. A tie is
`Ambiguous` and selects nothing, so `Union<float, decimal> u = 5` stays a type error rather than an
arbitrary arm. `AnalyzerAssignability.ClassifyUserDefinedConversion` is the classification a
reporting site can consult to say WHY; assignability itself still answers only true or false.

A cheap memo (`externalConversionOwners`) answers "does either end declare ANY conversion operator"
before a candidate list is built, because assignability asks this of every pair it cannot otherwise
relate and almost none of them name such a type.

NOT YET: a LIFTED user-defined conversion (`S? -> T?` synthesised from `S -> T`), and a conversion
declared by an external generic that is not yet closed over real types — inside
`func Wrap<T>(): Union<T, string>` the instantiation is builder-bound and contributes no candidates.

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
- `IsBuiltInTypeName(name)` is the EIGHTEEN-spelling membership — the sixteen above plus `nint` and
  `nuint` — and it is the single owner of "is this identifier a built-in type spelling". The two
  extras are a pinned analyzer gap, not a separate policy: the columnar binder resolves `nint`/`nuint`
  to `IntPtr`/`UIntPtr` and `SystemsTypePolicy` counts them as primitives, but `BuiltInTypes` has no
  `TypeInfo` for either, so `BuiltInSimpleType` still answers null for them. Contracts assert the
  divergence is exactly those two names.
- `BuiltInClrTypeName(name)` is the CLR name each of the eighteen denotes, over the same membership.
  It is what the editor's type resolution asks; do not confuse either with
  `AnalyzerResourceStatements.IsPrimitiveValueTypeName` or `SystemsTypePolicy.IsPrimitiveValueTypeName`,
  which answer "is this a primitive VALUE type" and exclude `string` and `object` on purpose.
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
current file's import aliases; a dotted nested type; the AMBIGUITY GATE (below); project-wide
discovery; a namespace alias resolved as a type; the referenced-assembly probe; and finally an
unresolved `ExternalTypeInfo` placeholder. The order is behaviour — a local declaration shadows a
project type, and a project type outranks a CLR type of the same name — and so is the fact that the
last channel is a PLACEHOLDER
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

#### The ambiguity gate and the import-precedence rule (NL209)

Every channel above the gate answers from ONE place — a scope, the enclosing type, the built-in
table — so a name that reaches it is about to be resolved from an IMPORT, and an import is the only
place two declarations can supply one spelling. `AnalyzerProjectTypeDiscovery.TryFindAmbiguousImportedType`
answers whether they do, and the two report-capable owners (`AnalyzerTypeResolver` at a type
position, `AnalyzerIdentifierResolution` at an expression position) render it through
`AnalyzerDiagnosticSink.ReportAmbiguousTypeReference`. They share the unresolved-reference dedupe
set, so one position is told once.

TWO EXCLUSIONS, both C#'s. The file's OWN namespace wins outright — a closer declaration is not a
tie — and the project-wide unique-exported FALLBACK is never a candidate, because it is the channel
that runs when no import supplies the name.

ONE MEASURED LIMIT. The metadata half of the tie check is asked only once the SOURCE half has
matched: an assembly sweep is imports × assemblies of `Assembly.GetType`, a miss is deliberately not
cached, and running it for every name that reaches the gate would put that cost on `Console`, `List`
and every other ordinary CLR spelling. So two IMPORTED CLR namespaces that declare the same spelling
still resolve first-import-wins. That limit is written down on `website/docs/errors/NL209.md`.

**AN EXPLICIT IMPORT OUTRANKS PROJECT-WIDE AUTO-DISCOVERY, and that ordering is a correctness fix.**
`ResolveVisibleProjectType`'s third outcome — the unique-exported fallback — matches by unqualified
name across every exported source declaration in the compilation, whatever namespace it lives in and
whether or not the file imported it. It used to run BEFORE the referenced-assembly probe, so a source
`class SimdReductions` in a namespace a file never imported silently replaced the
`NSharpLang.Runtime.SimdReductions` that file's own `import` brought in, with no diagnostic: a whole
parity harness became a self-comparison. The fallback is now skipped when
`AnalyzerExternalTypeProbe.ResolveImportedExternalType` — the IMPORT-QUALIFIED half of the ordered
probe, with no exported-name scan behind it — answers for the name.

**THE EMITTER APPLIES THE SAME PRECEDENCE, and it has to.** `ColumnarBindingScopeFacts` reaches the
same fork through `TryFindUniqueExportedSourceName`, and it consults
`ColumnarExternalTypeCatalog.TryGetImported` — the catalog's own imports-only probe — at both sites.
A program that passed analysis and then declined at emit is what disagreement here looks like.

#### Qualified names in expression position

`AnalyzerMemberAccess.TryResolveQualifiedTypeName` is the whole of it, and it is asked TWICE per
member access: once about the RECEIVER (`System.Console` under `System.Console.WriteLine`) and once
about the NODE ITSELF, which is the channel that makes a dotted type name a type-valued expression
exactly as `AnalyzerIdentifierResolution` makes a bare one. Without the second, the reflected bind's
SECOND analysis of a callee's receiver (`AnalyzerCallAnalysis` phase 30, which deliberately repeats
the walk) analysed `System` as a value and reported NL301 — which is why a qualified CALL failed
while a qualified static READ in the same file resolved.

It resolves, in order: a namespace ALIAS expanded to its target (`import System.IO as Io` makes
`Io.Path` mean `System.IO.Path`); a PROJECT type in the named namespace, split at the last dot,
subject to the ordinary export rule; then a CLR type through `ExternalQualifiedTypeResolver`. Its six
vetoes — a local, a local type, a file-import alias, a project type of the ROOT name, an
enclosing-type member and a project function — all still fire first, and they are ordered cheap-first
because this owner is now asked twice per node.

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

`TypeArityNames.nl` is the N# owner of TYPE IDENTITY BY (NAME, GENERIC ARITY). A type's identity is
the pair, spelled as one string the way CLR metadata spells it — the bare name at arity 0 and
`` Name`N `` above it — and every analyzer declaration table is keyed by it: the scope's `Types` map
(with `Scope.TypeArities` beside it answering "which arities of this name are in scope?"), the
semantic model's `TypesByIdentity`, the declaration context's per-file canonical-type cache and its
declaration matching, and the scope declaration locations. `Subscription` and `Subscription<T>`
therefore coexist, a reference resolves the arity it writes (falling back to the best same-name
candidate when nothing has that arity, which is what lets NL207 name the type it found), and NL306
fires only for a repeated (name, arity). The DISPLAY name — the key with its suffix stripped — is
what every diagnostic, hover, completion label and go-to-definition span carries; `SemanticModel.Types`
is keyed by it, with a non-generic type winning the slot over a same-name generic one. The columnar
side uses the same spelling for its exact declaration names, which is also the CLR metadata name the
emitter writes.

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

See `src/NSharpLang.Compiler.Core/TypeInfoModels.nl` (with `TypeInfoFactories.nl` and
`TypeInfoIdentityFacts.nl`) for type representations:

### Built-in Types
- **PrimitiveTypeInfo**: `int`, `long`, `float`, `double`, `bool`, `string`, `void`
- **UnknownTypeInfo**: Type not yet resolved

### User-Defined Types

A generic type's STATIC members are ordinary members. There is no declaration-time refusal of a
static field, property, method, operator or conversion operator on a type with type parameters —
`AnalyzerTypeDeclarations.ValidateNoStaticMembersOnGenericType` and its NL323 reporter are deleted —
and a static member is nameable without a qualifier from every body the type owns, static or
instance, resolving against the current instantiation. What remains unsupported is a generic METHOD
declared by a user type (`static func Of<U>(...)`), which the columnar struct kernel refuses at
parse.

Members, constructors and operators of a CONSTRUCTED EXTERNAL generic type are ordinary scoped CLR
resolution too — there is no modeled-call table, allowlist or lane-count special case behind
`Vector<int>.Count`, `new Vector<uint>(array, i)`, `a0 += ...`, `v[lane]` or `Vector.Sum(...)`.
`tests/native/external-generic-construction` isolates each element and `tests/native/simd-reductions`
is the whole-library proof: a complete N# translation of `src/NSharpLang.Runtime/SimdReductions.cs`
executed side by side with the C# original on the same inputs. Two emitter holes that surfaced there
are fixed: `uint` was missing from `TryEmitCompoundOperation`'s IL-primitive arm (so `sum += a[i]`
declined on a `uint` accumulator while `sum = sum + a[i]` emitted), and named tuple element names
were carried only for FREE functions, so element access on a tuple returned by a static or instance
method declined at emit even though the analyzer had resolved it —
`ColumnarStaticMethodDef`/`ColumnarInstanceMethodDef` now carry `ReturnTupleElementNames`.

NAMED TUPLE ELEMENT NAMES CROSS THE ASSEMBLY BOUNDARY IN BOTH DIRECTIONS. A named tuple has no CLR
identity — `(int Min, int Max)` IS `ValueTuple<int, int>` — so the names live in a
`System.Runtime.CompilerServices.TupleElementNamesAttribute(string[])` on the signature POSITION, and
N# writes and reads it the way every other .NET language does:

- `ColumnarTupleElementNames` flattens a written type into that array in C#'s order — a pre-order
  walk with each tuple's own names first, so `(A:int,D:(B:int,C:int))` is `A/D/B/C` and
  `List<(Min:int,Max:int)>` is `Min/Max`; an unnamed nested tuple still occupies its elements' slots,
  and a tuple longer than seven elements carries the extra slots its `ValueTuple` REST nesting adds.
  Every expected row in its tests, including the raw blob bytes, was measured against `csc` output.
- The parser kernels produce a LABELLED canonical (`TypeReferenceLabeledCanonicalTextCore`) beside
  the structural one, because the structural canonical drops element labels at every level and
  `ReturnTupleElementNames` carries only the TOP-LEVEL ones. `ColumnarFunctionInput` carries it as
  `ReturnLabeledCanonical` / `ParamLabeledCanonicals`.
- `ColumnarTupleElementNameEmitter` attaches the attribute to the return position, parameters and
  constructor parameters; the blob comes from `ColumnarAttributeBlobs.StringArray` (hand-rolled,
  AOT-safe) rather than `CustomAttributeBuilder`.
- `AnalyzerTupleElementNames` reads the attribute off an external member's `CustomAttributeData` and
  rebuilds the converted type as a `TupleTypeInfo` carrying the names, spending the flattened array
  in the same order the emitter writes it. All four member-facing conversions in
  `NullabilityMetadataReflection` (return, parameter, field, property) route through it; a position
  with no attribute is left exactly as it was.
- Names stay out of identity (`TypeInfoIdentityFacts` compares tuples by element TYPE), which is the
  C# rule. N# has no lint mirroring C#'s name-mismatch warning.
- The emitter learns an external method's names from its metadata, selecting the member through the
  ordinary scoped CLR overload resolver over preflighted argument types — no per-API table.
- A named tuple DISPLAYS as `(Min: int, Max: int)` in hover and `nlc query type`; before this it
  answered the class name `NSharpLang.Compiler.TupleTypeInfo`.

`tests/native/tuple-names` is the executable evidence for both directions.

Still unsupported, and reported as such: an individually named element (`(A: int, int)` — the parse
kernel is all-or-nothing at each level), and a FIELD or PROPERTY declared with a tuple type at all
(`Pair: (Min: int, Max: int)` inside a class or struct declines at `parse.struct`, even unnamed), so
those attribute positions are unreachable rather than unimplemented.

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

Compiler Core carries the `System.Reflection.MetadataLoadContext` 10.0.5 dependency, but the N#
columnar backend declines a minimal external abstract override probe:

`AnalyzerMetadataResolverProbe: MetadataAssemblyResolver` with
`override func Resolve(context: MetadataLoadContext, assemblyName: AssemblyName): Assembly`.

Exact build result:
`error NL103: Columnar emission is required for 'NSharpLang.Compiler.Core', but the columnar backend declined.`

So `NSharpMetadataResolver` stays as a bounded mechanical C# host until the columnar backend
supports overriding external abstract members: the C# shell hosts the `Resolve` override and the
`MetadataLoadContext` integration boundary, and **nothing else**. Every policy decision it used to
make now lives in `AnalyzerMetadataLoadPolicy.nl` — see below.

The AOT successor is a different question and it is currently shut. `MetadataReader` is not
spellable from the estate in any form: as a type annotation it reports `NL201`, its
`System.Reflection.PortableExecutable` namespace reports `NL704` without a `nuget:` dependency, and
with one every direct spelling declines at columnar emit (`emit.local.initializer`). Beyond that,
the analyzer's whole external type model is `System.Reflection`'s object model — `Type`, `Assembly`,
`MethodInfo` — across the N# owners, so replacing the load context with a metadata reader is a
type-model replacement, not a host swap.

### AnalyzerMetadataLoadPolicy.nl — every decision the loading surface makes

`AnalyzerMetadataLoadPolicy.nl` is the N# owner for the metadata-loading surface's DECISIONS. Its
functions are pure: strings, paths and version spellings in, an answer out. The C# performs the IO
and drives the load context; it decides nothing.

- **Which assemblies are pre-loaded**: `CommonAssemblyNames()` is DEFINED FROM
  `ExternalAssemblyScan.CommonAssemblyNames()`, so the analyzer and the columnar scan share one
  list. Do not give the analyzer its own copy — it had one, it drifted, and the analyzer ended up
  seeing one fewer assembly than the back end. `MetadataCoreAssemblyName()` is the identity the
  context binds primitives against.
- **ASP.NET**: `RequiresAspNetCoreAssemblies(sdk)` is a CONTAINS test on the SDK spelling, because
  the SDK id a user writes is not a closed set; `AspNetCoreAssemblyNames()` is the eight names it
  selects.
- **The shared-framework walk**: `SharedRootFromRuntimeDirectory` climbs at most
  `MaximumSharedRootSearchDepth()` (5) parents looking for a directory named `shared`.
  `SharedFrameworkDirectoryNames()` searches ASP.NET before the base framework, and that order is
  visible because the registry is first-loaded-wins.
- **Where a package lives**: `NuGetPackagesRoot` / `NuGetPackageCacheDirectory` are DEFINED FROM
  `CompilationReferenceResolverKernels.GetGlobalPackagesFolder` + `GetNuGetPackageDirectory`, so the
  analyzer reads metadata from the folder `nlc restore` writes. `LocallyBuiltPackageAssemblyPath`
  states that a locally built copy outranks the cache.
- **Which target-framework asset answers**: `FallbackTargetFrameworks()` is the ONE ladder
  (`net10.0` → `netstandard2.0`, seven deep) and `MetadataProbeTargetFrameworks(tfm)` is the same
  ladder with the project's own framework in front. There used to be two ladders of different
  lengths in one file, so a package publishing only `lib/net6.0` was reachable one way and not the
  other. Do not reintroduce a second list.
- **Version precedence**: `CompareVersionSpellings` is SemVer, not ordinal — `+metadata` is
  discarded, up to four numeric parts compare numerically, a release outranks every prerelease of
  the same numbers, prerelease identifiers compare part by part with numeric below alphanumeric, an
  unparseable spelling (including one whose numeric part overflows) sorts below every parseable one,
  and the order is total. `PickHighestVersionDirectory` and `OrderVersionDirectoriesDescending` are
  its two consumers and they agree on their first element.
- **What the project restored**: `RestoredPackageAssetsPath`, `RestoredLibrariesPropertyName` and
  the `RestoredLibraryPackageName` / `RestoredLibraryPackageVersion` pair, which split a `libraries`
  key at the FIRST slash and drop a key that names no package version.
- **What a project reference resolves to**: `IsCSharpProjectReference` /
  `IsNSharpProjectReference` / `ProjectReferenceAssemblyName` (a `.csproj`'s assembly is its file
  name; a `project.yml`'s is `ProjectFileParser.EffectiveName`), `ProjectReferenceOutputPath`,
  `ResolvedReferencePath` and `UnknownProjectReferenceWarning`.
- **When two loads are the same load**: `IsSameAssemblyPath` and `IsSameSimpleName` are
  case-INSENSITIVE; `ShouldAddSearchDirectory`'s duplicate test is ORDINAL, because a search list is
  a probe order rather than an identity set. `ShouldRecordLoadFailure` keeps the FIRST failure per
  identity, so the `NL923` sentence points at the cause rather than at a fallback.
- **The resolver's cache sweep**: `NuGetPackageDirectoryMatchesPrefix` is a PREFIX test on the
  normalised package id, never a substring test, and `PinnedPackageVersionDirectory` lets a pinned
  version outrank the highest extracted one.

Do not reintroduce any of this in C#, and do not put IO in this class — it decides, the host acts.

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
  SemVer precedence (`AnalyzerMetadataLoadPolicy.CompareVersionSpellings`), never by ordinal string
  comparison (which ranks `0.1.0-anything` above `0.1.0` and `0.9` above `0.10`).
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

### The editor's type universe is NOT the analyzer's

`EditorTypeCatalogFacts.nl` is the N# owner for what the **Language Server** offers out of metadata:
which assemblies the editor may see, which short names a general completion always volunteers and
what each denotes, which namespaces a bare name is probed in and in what order, how a written type
name is spelled, which CLR types may be offered, how they are ranked, and how many may be sent.
`src/NSharpLang.LanguageServer/Services/TypeResolver.cs` performs the reflection reads and the
caching; it decides nothing. `AnalyzerTypeReferenceFacts.BuiltInClrTypeName` still owns the built-in
aliases and is consulted before this catalogue.

**The two universes are disjoint, and that is a product defect rather than a spelling one.** The
analyzer builds a `MetadataLoadContext` over `ExternalAssemblyScan.CommonAssemblyNames()`'s 27 names
PLUS the project's own restored references, so it sees everything a program compiles against. The
editor's catalogue is four seed type names — `System.Object`, `System.Console, System.Console`,
`System.Linq.Enumerable, System.Linq`, ``System.Collections.Generic.List`1`` — resolved by LIVE
reflection over the language-server process itself. Those four names reach exactly **three**
assemblies (``List`1`` and `object` both live in `System.Private.CoreLib`), and none of them is a
project reference. So **completion cannot offer a type from a package the user depends on, and hover
cannot name one.**

Closing that gap means serving the editor from the analyzer's universe, which is a
`MetadataLoadContext` — the AOT type-model verdict above is what currently blocks it. **Do not paper
over it by adding a fifth seed name.** The seed names are metadata names rather than `typeof` for the
reason `CompletionReflectionFacts` gives: `typeof` of a static class does not emit and an open
`typeof(List<>)` does not parse.

Two owners are consulted rather than copied:

- **Eight of the twelve short-name spellings** are `CompletionReflectionFacts`'s answers, not a
  second table: `Console`, `String`, `Math` and `DateTime` come from `KnownReceiverType`, and
  `List`, `Dictionary`, `HashSet` and `IEnumerable` from `KnownReceiverGenericDefinition` — which is
  also where the arity suffixes come from. The other four (`Guid`, `Exception`, the NON-generic
  `Task`, `CancellationToken`) have no owner and are spelled once. The contracts assert each derived
  answer equals the literal it replaced, so a drift in the other owner fails there rather than
  silently costing the editor a completion.
- **Ordinal comparison** is `AnalyzerMetadataLoadPolicy.CompareOrdinalText`. Both the importable-type
  order and the namespace-segment order route to it, so no comparison policy is spelled twice.

One divergence is recorded rather than unified: `EditorTypeCatalogFacts.CompletionTypeDisplayName`
truncates a name at the FIRST arity backtick while `DocQueryKernels.StripGenericArity` removes every
backtick run. They are different total functions that were measured identical over all 1,391 exported
types the editor's universe can reach, and the contracts pin both the agreement and the divergence.
Unifying them changes what `nlc query` prints too, so it belongs to a slice that can measure that
side as well.

**Hover's use of this catalogue is a FALLBACK, not the main path.** `HoverHandler.Handle` consults
`DocumentManager.FindProjectHover` — the N#-owned code intelligence — before the AST branch that
reaches `TypeResolver.ResolveType`, and for a document inside a workspace the project hover answers
every time (measured: 1,332 positions, zero reaching the type-resolver formatters). The seam is only
observable for a document opened OUTSIDE the workspace root, which is the loose-`.nl`-file case.
Completion is the live consumer.

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
- Exact type identity is decided on the `TypeInfo` values, not only by reference or by CLR type. A
  CONSTRUCTED SOURCE GENERIC converts to no CLR type at all, so without that rule
  `Equals(Outcome<TOk, TErr>)` and `Equals(object?)` score the same and tie.
- A generic method's own type parameter INFERS FROM AN ARGUMENT THE CLR HAS NO TYPE FOR — a type
  parameter of the enclosing declaration, as in `HashCode.Combine(state, ok)` written inside
  `struct Outcome<TOk, TErr>`. The binding is recorded on the N# side only, and the reflected method
  is then left OPEN rather than closed over a surrogate whose declared constraints would be checked
  against a type the program never wrote; the finalised signature and return type read from the N#
  bindings. Emission of that call is a separate, still-open question (it needs a MethodSpec over an
  emitted type's generic parameter).

### Generic methods declared by user types

A `class`, `struct` or `record` may declare a generic method. The analyzer treats its type
parameters as the method's own, layered over whatever the declaring type binds:

- `AnalyzerFunctionTypeFactory.CreateFromDeclaredMember` shadows each member type parameter over the
  receiver's substitution, so a signature may name the owner's parameters, the method's, or both
  (`func Map<TResult>(f: Func<T, TResult>): Box<TResult>`).
- CLOSING that signature over a call's type arguments is `ApplyGenericBindings`, and it rebuilds
  EVERY composite shell — generic, array, nullable, oblivious, by-ref, tuple, function and anonymous
  union — over substituted leaves. A tuple or function shell left unsubstituted is how
  `Plain.Pair<int, string>(1, "a")` used to answer `(T1, T2)`.
- The BOUNDS walk descends into a tuple parameter, and reads a `Func`/`Action` parameter positionally
  against a lambda's inferred `FunctionTypeInfo` (the reading
  `CreateFunctionTypeInfoFromGenericDelegate` gives those two names), so a method type parameter
  mentioned inside a delegate can be inferred from an argument.
- `AnalyzerTypeSubstitution.ResolveTypeWithSubstitution` rebuilds the same shells rather than
  dropping them to the plain walk — but it runs the plain walk FIRST on tuple, function and union
  references, because that walk records each reference in the semantic model and is the only place an
  anonymous union's shape rules are reported.
- A WRITTEN type-argument list is validated for LENGTH before anything else about the call
  (`ValidateWrittenTypeArgumentCount`): a partial list, an over-long one, and a list on a non-generic
  name are all NL207, and the report returns so the parameters it did not name are not reported
  again.
- A declaration's own type parameter may not shadow one an enclosing declaration binds — NL316,
  decided by `AnalyzerScopeStack.HasEnclosingTypeParameter`, which is backed by a per-scope set of
  type-parameter names because a type parameter is otherwise indistinguishable from a built-in
  spelling once it is in the scope's type table.

NOT YET: a generic method declared by an `interface` (refused at parse into columnar input), and
inferring a type parameter that appears only in a delegate's RESULT from the lambda's body — the same
limit a generic FREE function with a `Func<TValue, TResult>` parameter has.

## Type Checking

### Assignment Compatibility
`IsAssignable(target, source)` checks if source can be assigned to target:
- Exact type match
- Inheritance (class → base class)
- Interface implementation (class → interface)
- Duck interface structural typing (see [Duck interfaces](../../website/docs/types.md#duck-interfaces))
- User-defined implicit conversions, declared by a SOURCE type or by an EXTERNAL one
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

## Class Inheritance: abstract, virtual, override

Source-declared classes take part in inheritance on C#'s terms, and the analyzer already owned every
negative case before the emitter could express the positive ones. No new codes were needed:

| Shape | Diagnostic | Owner |
| --- | --- | --- |
| a concrete class does not implement an inherited abstract member | `NL324` | `AnalyzerTypeDeclarations.nl` |
| `new` on an abstract class | `NL803` | `AnalyzerConstruction.nl` |
| `override` with no base member of that name | `NL311` | `AnalyzerTypeDeclarations.nl` |
| `override` of a base member that is not `virtual`/`abstract`/`override` | `NL311` | `AnalyzerTypeDeclarations.nl` |

The EMISSION side has three owners worth knowing about:

- `ColumnarSourceBaseMethodMatch` (`ColumnarOverrideTargetResolver.nl`) is the override lookup for a
  base being emitted in the SAME assembly. `ColumnarBaseMethodMatch` reads a base chain through
  Reflection, which an unbaked `TypeBuilder` cannot answer; this one walks the source base's own
  declaration table instead. It deliberately produces NO `DefineMethodOverride` target — a class
  override of a class member is bound by the CLR from name and signature, and C# writes no MethodImpl
  row for it either. Its type-identity rule is REFERENCE EQUALITY for anything builder-bound, because
  a builder has no stable assembly-qualified name and two unrelated `T`s would compare equal by name.
- `ColumnarInheritanceDepthOrder` orders the method-declaration pass by inheritance depth, so a base
  has always declared its members before a subclass asks. Ties keep source order.
- `ColumnarStructMethodFlagIsAbstract` / `ColumnarFunctionInput.IsBodylessAbstractMember` are the one
  decision that an abstract instance member has NO BODY. The parser records it from its signature
  alone (the same `signatureOnly` path a `LibraryImport` stub uses) and the emitter schedules no body
  job for it.

Do not add an override allowlist or a name-based base lookup. The two match owners are the whole
surface: one for baked bases, one for source ones.

## Columnar Type Admissibility Over Type Parameters

`ColumnarTypeOfPlanner.IsSupportedType` is the compiler's type-admissibility head. When a type is
builder-bound it consults a list of named structural families (collection, task, result, union,
enumerator, key-value pair, value tuple) — each of which exists to state an ADDITIONAL rule about its
arguments, such as "a dictionary key must be hashable".

`IsSupportedExternalGenericOverTypeParameters` is the general rule beside them: a constructed
external generic whose only builder-bound content is a type PARAMETER is storable. `Action<T>`,
`Func<T, TResult>` and `IComparer<T>` reach the surface through it, and they impose no extra rule on
their arguments, which is exactly why they are not a named family. It refuses a by-ref-like
instantiation (never a field) and a source `TypeBuilder` argument (a type that does not exist yet).

Two resolution facts go with it, both in `ColumnarCanonicalTypeResolver.nl`:

- The type-parameter walk reads a NULLABLE ANNOTATION the same way the ordinary walk does: `List<T>?`
  is `List<T>`, `T?` stays `T` (which of `Nullable<T>` and `T` it means is per-instantiation and
  cannot be written down), and a value type lifts.
- `TrySelectDelegateCanonical` takes the type-parameter map. It used to resolve its arguments through
  the ordinary walk even when reached from the generic-aware entry point, which is the only reason
  the delegate families could not name a type parameter.

On the emit side, `ColumnarIlEmitter.ResolveDelegateInvokeMethod` rebinds `Invoke` from the open
definition onto a builder-bound instantiation — reflection member queries THROW on a
`TypeBuilderInstantiation` — and reads the signature from the instantiation's generic arguments,
because the rebound handle cannot be asked for its parameters either.

## External Instance Members on Exceptions

`ColumnarRuntimeInstanceMemberResolver.TrySelect` is a table of `(receiver type, member)` pairs.
Exceptions are NOT one of its rows any more: any type assignable to `Exception` goes through the
ordinary `TrySelectAdmittedProperty` lookup on the RECEIVER's own type, so `ex.ParamName`,
`ex.StackTrace`, `ex.Source` and a derived or NuGet exception type's own properties resolve exactly
as `ex.Message` does. The admitted-value-type fence still decides what may be read.

Before this, `Message` was the single modelled member — not because it was different, but because it
was the one that had been needed. Do not add exception members back by name.

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

- `src/NSharpLang.Compiler.Core/AnalyzerDeclarationContext.tests.nl` for the N#
  declaration catalog, source ownership, visibility, imports, members, and exact runtime
  projections.
- `src/NSharpLang.Compiler.Core/TypeInfoIdentityFacts.tests.nl` for nominal,
  structural, runtime, and metadata-only identity and conversion rules.
- `tests/native/analyzer-identifier-binding` for what the analyzer BINDS an identifier to at an
  incomplete member access — the bound `ClassTypeInfo`, its name and anchor, its whole declared-member
  census in declaration order, and the analysis diagnostic census. This is a native N# project rather
  than an estate contract because `Analyzer` is the C# class in `Compiler.dll`, and `Compiler.dll`
  depends on Compiler Core; every other type on that route (`SemanticModel`, `ClassTypeInfo`,
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
- `tests/native/analyzer-semantic-model` for what ANALYSIS PUTS INTO `AnalysisResult.SemanticModel`
  — every flat table (`Variables`, `Functions`, `Properties`, `Fields`, `Types`), `TypeMembers`,
  both POSITION tables (`ExpressionTypes` and `TypeReferenceTypes`, pinned separately so a row in
  the wrong one is a visible change), the whole scope list with both bounds, and the model's own
  queries at the positions the deleted methods probed. Same native route and same reason: the model
  is N# in the estate, but only `Analyzer` — C# in `Compiler.dll` — populates it, so
  `SemanticModel.tests.nl` owns the ALGEBRA and this project owns the POPULATION (task 020 slice 26).
  It states what nothing had: a function looks up as its RETURN type while the table it comes from
  holds a `FunctionTypeInfo`; the flat tables COLLIDE across scopes (two functions with a parameter
  of the same name leave ONE row); `GetVisibleVariablesAtPosition` answers FUNCTIONS too; every
  scope's end column is `int.MaxValue`; and one LINQ chain opens FIFTEEN scopes, twelve of them for
  two lambdas that are re-entered during overload resolution.
  **Task 020 slice 27 extended the SAME project rather than adding a sibling**, taking the file's
  remaining 18 `[Fact]`s and DELETING `tests/AnalyzerSemanticModelTests.cs`. Two of them walk
  `SemanticModel.Types[…]`, and the walker built for them — `SmTypeRuntimes`, `SmTypeInfo`,
  `SmTypeFacts`, `SmTypeMemberNames`, `SmTypeMemberCount`, `SmTypeMember` — is a REUSABLE surface
  documented in the project's header, meant for the `AnalyzerTests.cs` campaign. The other 16 read
  only `result.Errors` and are the diagnostics the nominal facts DRIVE: generic arity, generic
  member and primary-constructor initializers, property patterns, member writes through a value
  copy, the `using`/`Dispose` pattern in three shapes, `ref` arguments over static fields and
  properties, user-declared binary and unary operators, and static and instance readonly
  assignment. It states what nothing had: the type table holds TWENTY types where the deleted
  monster named eighteen; a `sealed class` anchors at the `class` keyword while a `duck interface`
  anchors at `duck`; `TypeMembers` and `DeclaredMembers` are different tables with different
  population rules; and **two initializer mismatches used to report an `NL202` whose whole message
  was the bare words `Type mismatch` with a NULL suggestion** — the four-argument-`Analyze` defect,
  now fixed: both name the member and the two types. The generic suggestion is still null because
  the rich shape carries a specific `ContextualHint` in its place.
- `tests/native/analyzer-clean-source` for what the analyzer decides about ASSIGNABILITY and FLOW
  NARROWING read from SOURCE TEXT — nominal subtyping, the whole 43-pair numeric widening matrix and
  its ten narrowing rejections, the nullable assignability matrix, flow-sensitive null narrowing
  (guards, `??`, `throw`, `is` patterns, `match` null arms, reassignment, `?.`, member paths, loop
  conditions, `must`, `.Value`, `HasValue`), enum exhaustiveness, error-recovery suppression, the
  `&&` / `||` / is-pattern / same-symbol narrowing chains, and lambda-delegate structural
  validation. Same native route and same reason (task 020 slice 28, the `AnalyzerTests.cs`
  campaign's tranche 1a — 109 `[Fact]`s and 1,584 C# lines deleted). It states what nothing had:
  the rejected-lambda `NL202` **says a value is not assignable to its own type**, both sides spelled
  `NSharpLang.Compiler.FunctionTypeInfo`; a code NAMED `NullabilityWarning` is reported at `Error`
  severity; `null` assigns to a non-nullable `string` and to a non-nullable class in SILENCE while
  `null` to `int` is rejected, so the annotation is enforced at the dereference and not at the
  assignment; the ten narrowing rejections are ONE message template over ten type pairs, all
  anchored on the declared name for one column; the `NL905` suggestion is TEMPLATED with the user's
  own variable name and suggests `?[` for an index and `?.` for a dereference; and every one of the
  24 diagnostic rows carries a NULL `ContextualHint`.
  **Slice 29 extended the same project with TRANCHE 1b** — generic constraint validation,
  string-to-enum rejection, overload betterness, type-system edge cases, impossible patterns, numeric
  narrowing cast suggestions and `default`/`new()` expressions: 82 more `[Fact]`s and 1,193 more C#
  lines deleted, after which `AnalyzerTests.cs` has no `#region` left. **It found that the analyzer's
  two entry points are different answers.** `Analyze(unit)` — which every deleted helper called, and
  which has ZERO production callers — and `Analyze(unit, path, root, source)` — which both production
  call sites use, `MultiFileCompiler.cs:282` and the language server's `DocumentManager.cs:277` —
  agree on every CODE and disagreed on 22 of the 33 reporting fixtures' POSITION and on
  15 of their MESSAGES, where the rich path collapsed `Variable 'c' is typed as 'Color', but the value
  is 'string'` to the bare `Type mismatch` and DROPPED the generic suggestion, adding a
  `ContextualHint` in its place. **THE MESSAGE HALF OF THAT SPLIT WAS A DEFECT AND IS FIXED**:
  `ErrorMessageBuilder.TypeMismatch` now takes the reporting site's own sentence instead of writing
  a headline of its own, so both routes say the same thing and the rich one only ADDS the snippet,
  the caret width, the hint and the docs link. The POSITION half stands — the plain route is handed
  no source text and cannot measure a token, so its anchors are one column wide. That is the whole reason tranche 1a saw `ContextualHint` as `<null>` twenty-four times: the
  field belongs to the entry point, not the fixture. `SourceSnippet` behaves the same way (33 non-null
  rich, 0 plain). It also found that **a bodiless positional record does not parse** — `record
  Person(Name: string, Age: int)` reports `NL102`/`NL106` and swallows the file — which makes two of
  the deleted `AssertNoErrors` methods VACUOUS, invisible to an assertion that read only the analyzer.
  **Slice 30 extended it again with TRANCHE 2 — the ERROR-CODE assertion family**: every method
  that named `AssertHasErrorCode` or `AssertNoErrorCode` (88) plus the 18 direct-`Analyze` shape
  neighbours interleaved among their deletion runs, 106 methods and 1,743 C# lines, after which
  **both helpers are gone**. It added the one shape the campaign had no kernel for — a
  severity-filtered error-CODE census read (`AcCodeMatchIndex` / `AcCodeErrorCount` / `AcCodeRow` /
  `AcCodeAnchor`, plus `AcSuggestions` for the plural `Suggestions` list). Its findings: **the
  severity half of both helpers is dead over this corpus** (all 82 diagnostics the 111 fixtures
  produce are `Error`, so the severity-blind `AcCodeCount` and the filtered `AcCodeErrorCount` agree
  everywhere); **34 of the 35 `AssertNoErrorCode` fixtures analyse completely silent**, so the
  assertion "this code is absent" was almost always "everything is absent"; **the one that is not
  silent is a false clean** (`EnumValueObjectMemberAccess_Resolves` reports
  `NL202:TypeMismatch@10:17+1`); **`switch`/`case` is not N# syntax and newline-separated enum
  members do not parse**, which made one deleted claim vacuous and left another passing over a file
  whose analysis reports `NL903` about an identifier named `<error>`; **`VisibilityConventionWarning`
  is reported at `Error` severity**; and the two entry points disagree again — census on 16 fixtures,
  code row on 28, anchor on 13 — with **three deleted assertions true ONLY of the entry point nothing
  ships**. The plural `Suggestions` list is a production-only field (0 of 82 plain rows, 5 of 82
  rich), so the `?? error.Suggestions` fallback the deleted code carried was unreachable on the route
  the deleted code used.
  **Slice 31 extended it again with TRANCHE 3** — the WHOLE remaining direct-`Analyze` + `ErrorCode`
  shape (24 methods, so that shape is now at ZERO) plus the `AnalyzeWithSource` + `ErrorCode`
  shape's first 56, cut at the end of the readonly-field subject: 80 methods, 1,349 declaration
  lines and 1,599 C# lines, carrying **31 of the residue's 34 `[Theory]`s as native tables**. It
  needed NO new kernel and killed NO helper — the first tranche of which both are true. Its
  headline is an anchor defect in the entry point nothing ships: over 148 row pairs analysed through
  both routes, **23 differ in LENGTH and the one-argument route reports `1` in every one of the 23**
  while the four-argument production route reports the real token width. The one-argument overload
  receives no source text and cannot measure a token, which is why slice 30 saw `NL202` anchors as
  truncated single letters. Seven suggestions and three messages also differ (the sharpest being
  `MethodGroupToClrDelegate_RejectsNumericParameterConversion`, where the plain route offers a
  suggestion and production offers none), and `ContextualHint` is non-null on 11 rich rows and 0
  plain. It also found that **5 of the tranche's 13 absence claims were vacuous** — three fixtures
  report nothing at all — and that `Method 'X' must be called or passed to a delegate` has TWO
  owners, `ErrorMessageBuilder.nl` for the rich route and `AnalyzerReflectionCallReporter.nl` for
  the plain one, each moving exactly 5 native contracts when mutated.
  **Slice 32 extended it again with TRANCHE 4** — the REST of the `AnalyzeWithSource` + `ErrorCode`
  shape, which goes to ZERO, plus the WHOLE 79-method `AssertHasError` family, after which
  **`AssertHasError` dies with its last consumer**: 112 methods, 1,515 declaration lines and 1,689
  C# lines across 53 runs, 114 fixtures, 282 claim rows, and two new kernels (`AcTypes` for the
  `ActualType`/`ExpectedType` pair and `AcExplanation` for `HumanExplanation`, both fields no
  contract in the arc had read). Its headline is that **`AssertHasError` pinned sentences the
  shipping compiler does not write**: the helper reached the one-argument `Analyze(unit)`, and of
  the 282 deleted claims — all of which hold on their own route — **40 are false on the other one**,
  32 of those being `AssertHasError` message substrings production never emits, over 32 of the 79
  family members. The positional gap widened too: 31 length differences (all with `plain = 1`),
  **20 COLUMN differences all with `plain < rich`** (the plain route anchors the declaration, the
  production route the offending value), and **one whole-LINE difference** where the plain route
  blames the `return` statement and production blames the signature with no return type. Codes,
  severities and row counts are identical on both routes everywhere. **Eight of its nine absence
  claims were vacuous** — eight fixtures report nothing at all — the campaign's worst ratio.
- `tests/AnalyzerTests.cs` NO LONGER EXISTS. Task 020's nine-slice campaign migrated all 519
  `[Fact]`s and both `[Theory]` families into `tests/native/analyzer-clean-source`,
  `tests/native/analyzer-error-handling` and the compiler-service estate, and slice 36 deleted the
  file. Analyzer-shell diagnostics, flow analysis, call binding and end-to-end semantic behaviour
  are pinned there in N#, on BOTH the one-argument `Analyze(unit)` and the four-argument
  `Analyze(unit, path, projectRoot, source)` entry points, with the parse census, the unit shape,
  every row's `Code|Message|Suggestion|Severity`, its `ContextualHint` and its `SourceSnippet`.

**READONLY STRUCTS** (`AnalyzerTypeDeclarations.ValidateReadonlyStructInstanceFields`, phase 1). A
`readonly struct` / `readonly ref struct` / `readonly record struct` must have every INSTANCE field
declared `readonly`; a mutable one is **NL326** on the field name (C# `CS8340`). `static`, `const` and
`init` fields are exempt — they are not the instance state the promise covers. A PLAIN struct with
readonly fields is NOT a readonly struct and is never flagged. Writes to the readonly fields are the
existing NL309 rule's business, unchanged. The emitted metadata half lives in
`ColumnarDeclarationPlan.FieldIsReadonlyAt` (every instance field of a readonly struct is `initonly`,
including a primary constructor's synthesized capture fields) and `ColumnarIlEmitter` (the
`IsReadOnlyAttribute` on the type); `tests/native/readonly-structs` proves both by reflection. That project is NOT registered in
`scripts/ilverify.sh` — adding the line trips the OWN004/OWN005 non-N# growth ratchet — but its
assembly verifies clean under `scripts/ilverify.sh --built-dirs-file`. KNOWN LIMIT: a `with`
expression over a `readonly record struct` declines at `emit.with.plan` (the with planner needs
settable named members and every instance field is now initonly) — the same decline a plain
`record struct` with readonly fields already had; it needs a synthesized copy constructor, not a
readonly-struct change.

**EXTERNAL GENERICS CONSTRUCTED OVER A SOURCE TYPE PARAMETER** (`EqualityComparer<TOk>` inside
`Outcome<TOk, TErr>`, `IEquatable<Outcome<TOk, TErr>>` in its base list, `Dictionary<string, T>` as a
field). Four owners decide these, and none of them consults the head's NAME:

- `ColumnarGenericTypeReceiverFacts.TryResolveReceiverType` splits the EXTERNAL answer from the
  SOURCE one by the RESOLVED TYPE'S OWN IDENTITY (`ColumnarTypeOfPlanner.IsClosedSourceGeneric`), not
  by the scoped resolver's `claimed` flag. `claimed` is set by any source-answered part of a
  spelling, and a type-parameter ARGUMENT is one of those parts, so reading it as "the head is a
  source type" routed every `EqualityComparer<TOk>` to the source member owners, which own no such
  declaration (the old `emit.expression.generic-type-receiver` decline). `IsBuilderBoundConstruction`
  is the predicate for "external head, builder-bound arguments"; its members are read off the runtime
  DEFINITION and rebound with `TypeBuilder.GetField`/`GetMethod`, and their types are substituted with
  the instantiation's arguments because a rebound wrapper reports the OPEN member type.
- `ColumnarCanonicalTypeResolver.TrySelectExternalGenericConstruction` is the general arm behind the
  modeled family rows in `TrySelectTypeParameterModeledFamily`. The rows state narrower ELEMENT
  policies for the families whose lowerings care (spans, collection elements, dictionary keys); when
  a row declines, or names a head no row covers, the definition is resolved through ordinary scoped
  type resolution at the written arity and closed with `MakeGenericType`. The same function's array
  and nullable suffix arms re-enter the TYPE-PARAMETER resolver rather than the ordinary one, which
  is what `Func<T, bool>?` needs.
- `ColumnarTypeOfPlanner.IsSupportedExternalConstruction` admits such a construction as a storable
  type. Its boundary is that the spelling MENTIONS a visible type parameter: a builder-bound
  construction over COMPLETE arguments (`Func<SourceClass>`, `IEnumerator<Box<int>>`,
  `Dictionary<string, SourceRow[]>.KeyCollection.Enumerator`) keeps the family boundary it already
  had, because those shapes have real lowerings that decide their own admissibility. By-ref-like
  heads are excluded (asked of the DEFINITION — the instantiation refuses the read), and so is any
  head from an assembly this process is emitting, so a source namesake cannot borrow a BCL generic's
  admission.
- `ColumnarExternalInterfaceMethodResolver.AddBuilderBoundMatchingTargets` /
  `InterfacesSatisfied` implement the interface half. A `TypeBuilderInstantiation` answers no
  `GetMethods()`, so the members come from the runtime definition, the effective signature is the
  definition's signature substituted with the instantiation's arguments, and the MethodImpl slot is
  that declaration rebound with `TypeBuilder.GetMethod`. The structural `ColumnarExternalMethodDescriptor`
  is deliberately NOT built for these: it validates a reflected lookup context that a
  `TypeBuilderInstantiation` has none of.

Three shared substitution fences had the same latent bug and now share one rule: a signature type
that resolved to one of the INSTANTIATION'S OWN arguments is CLOSED, not open
(`ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedResolvedSignatureType`, consumed by the
ordinary call resolver and by `ColumnarConstructionPlanner.HasUnsupportedConstructorSignature`); and
a generic type DEFINITION standing in for its own instantiation must be substituted, not skipped
(`ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments` and
`ColumnarCodePlanExecutor.ResolveMemberSignatureType`) — `EqualityComparer<T>.Default` is typed
`EqualityComparer<T>`, which the CLR spells as the definition itself. `tests/native/constructed-generic-interop`
executes all of it, including BCL dispatch THROUGH the constructed interface with an equality that is
deliberately not field-wise.


## External Generics Over Complete Source Types

`ColumnarTypeOfPlanner.IsSupportedExternalConstruction` no longer requires the spelling to mention a
visible type parameter. Its question is STORABILITY and only that: an external head the catalog
verifies by exact identity, over arguments this compilation can already store, is an ordinary
reference or value whether those arguments are finished or not. `IEquatable<Plain>`, `Comparer<Item>`,
`Func<Plain, bool>` and `IEquatable<Outcome<int, string>>` reach the surface through it. Three shapes
stay out: a by-ref-like head (asked of the DEFINITION, because a builder-bound instantiation refuses
the read), `Nullable<T>` (routed to `IsSupportedNullable` by `IsSupportedType` before this arm, so
lifting keeps one owner), and a head declared by the assembly being emitted.

The narrower family predicates beside it are NOT a second opinion about storage. Each states a rule
its own LOWERING needs — a collection element it will box or copy, a dictionary key it will hash, an
enumerator protocol it will drive — and each lowering asks its own predicate directly. A shape
admitted by the general arm that no lowering models is stored, loaded and passed; the operation that
is not modelled still declines at the site that would have to emit it. That split is what the six
rewritten estate boundaries now state (`ColumnarCatalogTypeAdmission`, `ColumnarEnumeratorProtocol`
twice, `ColumnarDictionaryKeyEnumeratorPrerequisite`, `ColumnarTypeOfPlanner`,
`ColumnarReferenceConversionFacts`): the family predicate's answer is unchanged in every one of them;
only `IsSupportedType` moved.

Three resolution facts go with it, all in `ColumnarCanonicalTypeResolver.nl`:

- `TrySelectExternalGenericConstruction` serves BOTH walks. `typeParams` is null on the ordinary
  walk, and the arguments resolve through whichever walk the caller is on.
- A MODELED ROW THAT OWNS THE HEAD IS TERMINAL. Each row sets `claimedHead` where it matches its
  head, and a claimed head never falls through to the general arm — otherwise `Dictionary<Plain,
  string>` would bypass the key-hashability rule that is the entire reason the Dictionary row exists.
- THE TWO WALKS STATE THE SAME ELEMENT POLICIES. The type-parameter walk's `IEnumerable<` row used to
  admit only two exact shapes, and it had no row at all for `IReadOnlyList`/`IReadOnlyCollection`/
  `IReadOnlySet`/`IReadOnlyDictionary` — so a BODY LOCAL typed `IEnumerable<int>` resolved to nothing
  while the identical signature spelling resolved. A body's resolver is not a narrower language.

`ColumnarReferenceConversionFacts` gained the matching conversion halves:

- `TryClassifyExactSourceInterfaceUpcast` accepts a CLOSED INSTANTIATION of a source generic as the
  source, substituting the instantiation's arguments through the declaration's own
  `ExternalInterfaces`. The walk stops at that declaration: an inherited edge is written in the
  BASE's parameters and mapping this instantiation's arguments onto them needs a recorded base map
  this fact does not carry, so it declines rather than guessing by position.
- `IsExternalConstructionUpcast` answers one external generic converting to another while an argument
  is still a builder (`EqualityComparer<Plain>` into `IEqualityComparer<Plain>`), by substituting the
  instantiation's arguments through the DEFINITION's base chain and interface list. `IsAssignableFrom`
  cannot be asked about these instantiations at all.
- `ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast` is now the emission half of that
  single fact rather than a second walk, and it is wired into every conversion chain in
  `ColumnarIlEmitter` — return, typed local, assignment, field, property, object initializer,
  constructor argument, by-ref argument — where before only the ARGUMENT chains had it. A value that
  could be passed into an interface but not stored in one was the gap.

KNOWN LIMITS, all separately owned: a COLLECTION whose element is an array of a source type
(`List<Plain[]>`) keeps `IsAdmissibleCollectionElement`'s narrower rule; implementing `IEnumerable<T>`
on a source class emits a type the CLR refuses to load, because the inherited non-generic
`IEnumerable.GetEnumerator()` differs only by return type and N# has no explicit interface
implementation (the same is true of `class Bag: IEnumerable<int>`, so it is not a generic-argument
gap); and `Task.FromResult(sourceValue)` is an unmodelled generic static call.

`tests/native/complete-source-generic-args` executes the whole surface, including
`EqualityComparer<Outcome<int, string>>.Default.Equals` dispatching through the source `IEquatable`
implementation and `List<Item>.Sort()` ordering by the source `IComparable<Item>`.

**`this` AND `base` AS EXPRESSIONS** (`AnalyzerCurrentInstanceReferences`, reached from `Analyzer`'s
expression dispatch). Both words name the object the current member was called on. When there is one,
`this` answers the enclosing type scope and `base` answers `AnalyzerDeclarationContext.ResolveBaseType`
of it; when there is none, the reference is **NL327** at the word, in one of two sentences — a `static`
member, or a top-level function that is not a member of any type. Before this owner the analyzer
answered `unknown` and said nothing, and the mistake surfaced only as an emission decline with no
source position on it.

WHETHER THERE IS A RECEIVER IS A FACT ABOUT THE ENCLOSING MEMBER, NOT ABOUT THE EXPRESSION, and it is
recorded on the ambient context (`AnalyzerAmbientContext.CurrentMemberIsStatic`) at the member boundary
rather than derived from `CurrentFunction`. Two shapes are why: a LAMBDA has no declaration of its own
(`EnterNestedBody` passes `null`) and so INHERITS its enclosing member's answer, and a PROPERTY or
INDEXER accessor has no `FunctionDeclaration` at all — `Analyzer.AnalyzeDeclaration` opens the pair
around `DriveAccessorBody` so an expression body answers it too. `false` is the default and the safe
one: it means "assume there is a receiver", so a walk that has not passed a member boundary reports
nothing rather than reporting wrongly.

A member the base does not declare stays **NL303** naming the BASE's type; `base` itself was fine. The
emission half is `ColumnarExpressionNodeKind.BaseMemberExpression()` (kind 71) out of
`ParsePostfixExpressionNode`, `ColumnarDirectCallPlanner.TryAppendBaseCall` (non-virtual `call`, source
base through `ColumnarSourceDirectCallResolver` and runtime base through the ordinary runtime resolver,
an abstract base member refused) and `ColumnarBoundIdentifierPlanner`'s `BaseField`/`BaseProperty`
selections. `tests/native/class-inheritance` proves the dispatch is non-virtual with a three-level
chain whose answer names every level exactly once.

A CONSTRUCTOR INITIALIZER'S ARGUMENTS MAY NOT READ THROUGH `base` any more than through `this`, and
the guard is `ColumnarIlEmitter.ConstructorChainArgumentNodeUsesCurrentInstance`: kind 71 is a LEAF
carrying the member name, so neither the identifier arm nor the child walk can see it and it needs an
arm of its own. Without it `constructor(): base(base.Value) {}` emitted a field read before the base
constructor had run (C# reports the CS0027 family). The decline is `emit.ctor.chain-instance`, the
same one `this.Value`, a bare field name and an instance call in a chain argument reach; there is no
analyzer diagnostic for any of them, so the four stay at parity.

KNOWN LIMITS, both PRE-EXISTING and both reproducible
without `base`: a subclass that declares a property whose name a base already declares declines at
`parse.struct`, and reading a property inherited from a CLOSED GENERIC ancestor two levels up
(`Box<string>.Value` from a grandchild) fails plan validation with "reference receiver ... does not
match its declaring type" for `this.Value` and `Value` alike.

**CALLING A DELEGATE, AND CALLING IT ONLY IF IT IS THERE.** Three gaps closed together, all in the
columnar call path:

1. `.Invoke` ON A DELEGATE OVER A TYPE PARAMETER declined at `emit.call.instance-member-unmodeled`.
   `ColumnarOrdinaryRuntimeDirectCallResolver` already rebinds a member from the open definition for a
   builder-bound instantiation (`TryGetBuilderBoundRuntimeDefinition` +
   `SelectedBuilderBound` -> `TypeBuilder.GetMethod`) — and then refused the SUBSTITUTED signature,
   because `IsUnsupportedSignatureType` rejected every generic parameter, including the ones
   `ResolveParameterTypes` had just substituted in. It now takes the receiver's `closedArguments` and
   accepts a generic parameter that is one of THEM; anything the substitution could not reach is still
   genuinely open and still refused. (The three other callers pass an empty set, so their behaviour is
   unchanged.)
   A DELEGATE'S `Invoke` IS ALSO ANSWERED BY `ColumnarIlEmitter.TryEmitInstanceCall` itself, right
   after the planned-external door and before the legacy tiers, through the same
   `TryResolveDelegateInvocation`. The N# direct-call planner owns the dotted `current.Invoke(h)`, but
   it declines by construction anything whose receiver is a null guard, so without that arm the SAME
   call written `current?.Invoke(h)` reached the legacy instance tier and declined as
   `emit.call.instance-member-unmodeled`.
2. A BARE CALL ON A DELEGATE FIELD (`pick(item)`) declined at `emit.call.bare-unresolved`: the
   bare-call arm only reached locals, parameters and lifted captures.
   `ColumnarDirectCallPlanner.TryAppendDelegateInvoke` now resolves `Invoke` through the ORDINARY
   runtime resolver with the CALLEE NODE ITSELF as the receiver, so `AppendExplicitReceiver` plans the
   identifier exactly as it would anywhere else and any storage works — `this.` in front of it too.
   `IsDelegateValueType` asks the CLR hierarchy (`typeof(Delegate).IsAssignableFrom`, through the open
   definition for a builder-bound instantiation), never a list of delegate names. METHOD-BEATS-VALUE is
   unchanged and pinned: a method of the name on any tier keeps the name.
3. `?.` WAS A PARSE GAP, for the read form and the call form alike. It is now the `.` access with a
   GUARDED RECEIVER: `ColumnarExpressionNodeKind.NullGuardExpression()` is kind 75 and wraps the
   receiver, so the access above it stays an ordinary kind-8 `MemberAccess` and `a?.M(x)` stays an
   ordinary kind-9 `Call` over that — every consumer that already reads an access keeps reading it, and
   a delegate's `Invoke` reaches the SAME owners the dotted `current.Invoke(h)` reaches (owner 1 above).
   `ColumnarIlEmitter` emits the chain from its ROOT (`IsNullConditionalChainRoot`), not from the guard,
   because `a?.B.C` is one expression that is null when `a` is; parentheses are deliberately not walked,
   so `(a?.B).C` ends the chain, C#'s reading. `TryEmitNullGuard` is the test: a reference receiver tests
   itself, a `Nullable<T>` receiver tests `HasValue` and hands the access its `Value`, and an
   unconstrained TYPE PARAMETER boxes first. The result follows C#: void leaves nothing, a reference
   result is `ldnull`, and a non-nullable value result is lifted to `Nullable<T>`. KNOWN LIMITS: `?[`
   null-conditional indexing, and a plain non-nullable value receiver (which has no null to test for).

**AN ENCLOSING NAMESPACE IS THE FILE'S OWN SCOPE.** `ColumnarBindingScopeFacts` resolves a bare type
name through the file's declarations, its imports, then its own namespace — and now, before the
project-wide unique-exported fallback, through each ENCLOSING namespace
(`TryFindEnclosingNamespaceSourceName`, asked by both the explicit-type walk and the
declaration-name walk). A file in `A.B` sits inside `A`, so an exported declaration there is in scope
without an import, exactly as C# reads it. This is NOT the auto-discovery fallback beside it: that
one finds a declaration in an UNRELATED namespace and deliberately loses to an imported external type
(the shadowing hazard `tests/native/qualified-names` pins), while an enclosing namespace is
lexically nearer than any import. Without the step the SAME spelling resolved two ways inside one
file — a signature saw the enclosing declaration and a body local saw the imported external type of
that name (`emit.typed-local.type-mismatch` naming both), which is what
`tests/native/runtime-acceptance` reproduced.

**A `ref`/`out` ARGUMENT IS A CALL FACT, AND IT MAY NAME A FIELD.** The semantic call planner typed NO
by-ref argument at all, so no by-ref call ever reached overload resolution:
`Interlocked.Exchange` declined at `emit.call.static-member-unmodeled` for every receiver type
(`Interlocked.Increment` only worked because it is a MODELED entry in `ColumnarIlEmitter`),
`int.TryParse(text, out field)` at the same place, and `Fill(ref count)` on a field at
`emit.expression-statement.call`. Seven owners together:

- `ColumnarDirectCallArgumentFacts.IsByRefArgument` — a SYNTAX fact beside the literal ones, because
  `f(x)` and `f(ref x)` are different calls at the same argument type. The recorded `argumentTypes`
  entry stays the ELEMENT type, which is what a parameter's element type is compared against.
- `ColumnarDirectCallPlanner.TryGetArgumentTypes` / `ByRefArgumentTarget` — the kind-54 modifier node
  (`ref`/`out` only; `in` has its own resolution rules and is NOT admitted through this door).
- `ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts` — the two spellings must agree in BOTH
  directions and the element type is EXACT (an alias to a converted temporary would alias something
  the caller cannot see).
- `ColumnarBoundIdentifierPlanner.TryAppendAddressOf` — `ldloca` / `ldarga` (or `ldarg` for a
  parameter that is itself by-ref) / `ldarg.0; ldflda`. It is NOT
  `TryAppendReceiver(preserveValueStorage: true)`: that owner addresses only VALUE types, and a
  `ref Action<T>` needs an address exactly as a `ref int` does.
- `ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType` — a PARAMETER may be by-ref;
  a RETURN may not. The two questions were one predicate, which made every by-ref overload invisible.
- `ColumnarRuntimeGenericMethodResolver` — `Unify` already walked through a by-ref shell; what was
  missing is that a `null` LITERAL contributes NOTHING to inference (ECMA-334 §12.6.3), the closed
  signature's return comes from the same substitution the parameters do (a wrapper closed over a
  builder-bound argument can report the raw `T`), and a shape closed over the declaration's own type
  parameters is bindable (`CloseOrNull` is the arbiter).
- `ColumnarCodePlanExecutor` — `ValidateCallArgument` requires an exact managed address for a by-ref
  parameter and refuses one everywhere else; `ValidateParameterType` admits a by-ref slot;
  `ResolveMemberSignatureType` substitutes THROUGH `T&` instead of hitting the compound refusal.

A STATIC field is deliberately NOT addressable: its address is `ldsflda`, and the pinned stage-0 SDK
that builds Compiler.Core does not model `OpCodes.Ldsflda` (`ColumnarExternalBindingPlans.tests.nl`
pins the absence), so the instruction cannot be written until the SDK is repacked. A composed target
(an array element, a nested member chain) is refused rather than approximated.

**`x == null` ON A GENERIC PARAMETER WAS UNVERIFIABLE IL.** `ldnull; ceq` against a `T` is
`StackUnexpected` to ilverify ("found Nullobjref, expected value 'T'"), which the tests never saw
because the JIT accepts it. The value is now BOXED first, exactly as C# boxes an unconstrained
`T == null`; `box` on a type that turns out to be a reference type at runtime is a no-op per
ECMA-335, so the constrained case costs nothing. Found by running `scripts/ilverify.sh
--built-dirs-file` over `tests/native/type-arity`, which the gate's own project list does not cover.

**THE RUNTIME ACCEPTANCE TRANSLATIONS** (`tests/native/runtime-acceptance`) are the reference for what
a complete generic type looks like in N#: `Result<TOk, TErr>` and `Union<T0, T1>` from
`src/NSharpLang.Runtime` written member for member as readonly generic structs with private
constructors, static factories, `out`-shaped `Try` reads, generic methods (`Match<TResult>`,
`Is<T>`, `TryGet<T>`, `As<T>`), conversion operators, `==`/`!=`, `IEquatable<Self>` base lists and
`EqualityComparer<T>.Default` equality. The project asserts behaviour AND parity: the same inputs are
run against the C# types from the referenced runtime assembly, reached by IMPORTING
`NSharpLang.Runtime` from a sibling namespace that declares no `Result`/`Union` of its own (a source
declaration is always the nearer name, and a fully qualified external type reaches fewer positions
than an imported one — see `website/docs/types.md`'s "Current limits"). Five compiler defects were
found by writing it and are fixed there: an implicit-`this` instance call inside a GENERIC type named
the receiver by the open definition while the handle named the instantiation (the plan executor threw
rather than declined); a generic type's own generic STATIC call was emitted against the open
definition ("the method itself or the containing type is not fully instantiated" at run time); a
property read inside a string INTERPOLATION had the same open-definition getter; `(T)value` over an
`object` emitted `castclass !T`, which is invalid IL for a value instantiation rather than a wrong
answer; and a generic method with an `out`/`ref` parameter over its own type parameter was
uncallable. `Type.IsSZArray` is now reached only through `ColumnarTypeEquivalenceFacts.IsSafeSzArrayType`
compiler-wide, because Reflection.Emit's generic-parameter builder throws `NotImplementedException`
from it and every raw call was a latent crash inside a generic body.

Keep ownership-policy tests beside the N# owner. C# tests should exercise only the remaining
diagnostic/integration shell, not recreate semantic lookup or identity policy in test helpers.
