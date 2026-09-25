# Analyzer Component

**Files:** `src/NSharpLang.Compiler/Analyzer.cs`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationContext.nl`,
`src/NSharpLang.Compiler.Model/TypeInfoIdentityFacts.nl`,
`src/NSharpLang.Compiler.Model/AnalyzerConversionFacts.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerCallableReferenceFacts.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerWellKnownTypes.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerWellKnownTypeFacts.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerClrTypeConversion.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerAssignabilityFacts.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerExternalTypeProbe.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeReferenceFacts.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerScopeStack.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerProjectDiscovery.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeResolver.nl`,
`src/NSharpLang.Compiler.Model/TypeArityNames.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeSubstitution.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerStructuralAssignability.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerDiagnosticSink.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerStateModels.nl`,
`src/NSharpLang.Compiler.Core/Semantics/AnalyzerDiagnostics.nl`

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
  enums and byref types are value types; every simple name outside the built-in value list is a
  reference type; reflection types defer to the CLR value-type flag. A closed generic instantiation
  answers from its DEFINITION — `List<T>` is a class, `Nullable<T>` is a struct — and one that
  carries no definition keeps the conservative `false`, because that is an absence of information
  rather than a decision. An OBLIVIOUS shell is transparent: metadata written without a nullable
  context reads back as `string![]!` / `IReadOnlyDictionary<string!, string!>!`, and an oblivious
  reference position admits null, exactly as in C#. (Both of those used to answer false, which is
  why `null` was refused by an N#-emitted `IReadOnlyDictionary<string, string>?` parameter with
  NL402, and why source `xs: List<string> = null` was refused while `s: string = null` was not.)
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
A written TUPLE reifies as `System.ValueTuple`N` closed over its element types, with the eighth and
later elements in a REST tuple exactly as the CLR spells them; element names are not part of the CLR
type, so `(Item: string, Count: int)` and `(string, int)` convert to one `ValueTuple<string, int>`.
Without that arm the funnel answered null for every tuple, which is why a tuple written as an
explicit type ARGUMENT to a referenced assembly's generic method (`Enumerable.Empty<(int, string)>()`)
was refused before its arguments were ever scored.

THE NORMALISATION MUST HOLD AT EVERY BOUNDARY THAT REBUILDS A CONSTRUCTED GENERIC, not only at the
three that resolve one. `AnalyzerTypeSubstitution.ResolveGenericTypeWithSubstitution` re-resolves a
head and then rebuilds it over substituted arguments, and it read the head's definition off the plain
walk's answer CAST TO `GenericTypeInfo` — which a normalised tuple is not, so the definition came back
null and the rebuild produced the second representation of `ValueTuple`N` this compiler deliberately
does not have. That path is how a SOURCE function's SIGNATURE is resolved, so a parameter or return
written `ValueTuple<string, int>` disagreed with the tuple spelling everywhere it was called, while
the same annotation on a LOCAL (which resolves through `AnalyzerDeclarationContext`) agreed: the head
is now asked for its own definition when the plain walk answered a tuple, and the rebuild runs the
same `ValueTupleTypeFacts.TryNormalizeConstructed` the other two boundaries run.

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
- ARRAY COVARIANCE is `TryGetArrayConversionElements` here (the SHAPE: both sides are arrays once
  their oblivious shells are off, and here are the two element types) plus
  `AnalyzerAssignability.IsImplicitReferenceConversion` (the RELATION). The split is the pending-pair
  discipline in a different form: the relation re-enters the engine and this owner stays silent.
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
  produces a second diagnostic and the bottom type is universally assignable. The `null` arm asks
  `AnalyzerConversionFacts.AcceptsNull`, which is also what a position with no assignability owner
  in hand (target-typing a `null` tuple element) asks, so the two cannot drift. That predicate
  reaches `IsReferenceType`, and a CONSTRUCTED GENERIC there is asked of its own DEFINITION rather
  than answered false on sight: `List<int>` is a class and `KeyValuePair<int, int>` is a struct, and
  the constructed shape alone does not say which. Answering a blanket false made
  `Task.FromResult<List<int>?>(null)` report NL402 "no overload accepts 1 argument with these types"
  — `null` was assignable to no constructed generic at all — while the same call with `string?` or
  `int[]` bound without complaint. A constructed generic whose definition is unknown stays false,
  because `IsReferenceType` is the predicate callers REPORT on.
- BY-REF is symmetric and TOTAL: if EITHER side is by-ref the answer is "both are, over equal inner
  types", and no later arm is consulted — not even the `object` arm.
- The UNION arms come before everything structural. A target union needs ONE arm to accept; a source
  union needs EVERY arm to be assignable.
- TUPLE-TO-TUPLE comes next, and compares ELEMENT BY ELEMENT rather than by identity. Element names
  are not part of tuple identity, and a nullable annotation over a REFERENCE type is not a CLR type,
  so `(string, string)` fits `(string?, string)` and a `null` element fits any slot that accepts
  null. A REPRESENTATION-CHANGING element conversion is refused on purpose — C# converts
  `(int, int)` to `(long, long)` and `(string, string)` to `(object, object)` by taking the tuple
  apart and rebuilding it, and N# emits no such per-element conversion, so accepting it would hand
  the emitter a shape it can only decline. `Nullable<int>` is a real CLR type and stays a difference
  from `int` for the same reason. Before this arm existed, a tuple whose declared type differed from
  the literal's only by a nullable annotation reported NL202 against source the writer had spelled
  correctly.
- The CALLABLE-REFERENCE arms come before `object`. A bare method group is not a value, so it is NOT
  assignable to `object` — that single exception is what forces the whole ordering, and it composes:
  a union with a method-group arm is not assignable to `object` either. A method group WITH A
  DELEGATE TARGET is a different question and is answered there: `IsMethodGroupAssignableToDelegate`
  applies C#'s rule — exactly one of the group's candidates applicable to the delegate's signature —
  reading that signature through `DelegateSignatureOfExpectedType`, which is the one place a
  delegate-shaped expected type is reduced to a `FunctionTypeInfo` however it is spelled (a function
  type, a reflected delegate, `Func`/`Action`, any other constructed generic delegate's `Invoke`,
  through the transparent nullable and oblivious shells). The two REFLECTION group shapes stay
  refused here; their candidates are `MethodInfo`s the call binder selects among.
- A LAMBDA REACHES ANY DELEGATE TYPE. There used to be one hand-placed bridge comparing the target's
  identity with `ThreadStart`, so every other non-`Func`/`Action` delegate was refused. The rule is
  the delegate's `Invoke`, wherever it is carried: a reflected target answers through
  `AnalyzerCallableReferenceFacts.IsInvocableMemberType` (runtime identity OR the metadata base-chain
  names, so the relation does not depend on which side of the `MetadataLoadContext` boundary the
  reference set is on), and a constructed GENERIC delegate answers through
  `GenericDelegateInvokeSignature` — the CLOSED type when the reference set can spell it, and
  otherwise the DEFINITION's `Invoke` with this instantiation's arguments substituted
  (`AnalyzerFunctionTypeFactory.CreateFromDelegateDefinition`), which is how a delegate closed over a
  type the compilation is still writing answers. `Func` and `Action` keep their positional reading,
  because those two are also built WITHOUT a reflected definition behind them.
- THE DELEGATE-SIGNATURE SCORER TREATS A NULLABLE POSITION AS TRANSPARENT-INWARDS: a position that
  admits null admits whatever its inner type admits. Read in the two directions the scorer is called
  in, that is the whole nullability rule for a delegate signature — a method whose PARAMETER is
  `string?` accepts everything a `string` parameter accepts (contravariance), and a delegate whose
  RETURN is `string?` accepts a method returning `string` (covariance). The reference-conversion gate
  below it refuses a nullable shell outright, which is why `names.Select(formatTypeRef)` on a
  `List<string>` reported NL402 for a `formatTypeRef(typeRef: TypeReference?)` that the same delegate
  written out accepted.
- FUNCTION-TYPE structural comparison comes before the identity fallback, because every
  `FunctionTypeInfo` renders identically.
- ARRAY COVARIANCE (ECMA-335) sits with the other array arms, after `object` and the span view. `S[]`
  is a `T[]` when `S` converts to `T` by an IMPLICIT REFERENCE conversion —
  `IsImplicitReferenceConversion`, which is deliberately NARROWER than `IsAssignable`: boxing,
  numeric widening, span views, collection-expression targets and user-defined `implicit operator`s
  may not be carried across an array, because the CLR conversion is a no-op on the array object and
  every element would have to be rewritten. Both element types must be reference types, so `int[]` to
  `object[]` is refused (and `TypeConversionSuggester` says why). Covariance composes, so `string[][]`
  reaches `object[][]`. The emitter's half of the same relation is
  `ColumnarReferenceConversionFacts.IsArrayCovariantConversion`, which exists because
  Reflection.Emit's `IsAssignableFrom` cannot answer an array whose element is still an unbaked
  `TypeBuilder`.
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
- **"IS THIS A NULLABLE VALUE TYPE" IS ANSWERED BY METADATA NAME, NEVER BY `Nullable.GetUnderlyingType`.**
  The BCL helper compares against `typeof(Nullable<>)` by reference, and under a MetadataLoadContext
  the projected `System.Nullable`1` is a different object — so it answered NO for every `int?` that
  came from a referenced assembly, and the parameter converted to a `GenericTypeInfo` named
  "Nullable" instead of the `NullableTypeInfo` that `int?` in source produces. The two then failed to
  match in either direction, with NL402 printing the two halves of one type as `SymbolKind?` and
  `Nullable<SymbolKind>` in the same sentence. `ExternalUserDefinedConversions.NullableUnderlyingTypeOrNull`
  is the one reader; `AnalyzerReflectionTypeConversion`'s plain and substitution-aware walks lift
  through it too, so there is ONE spelling of `T?` in the analyzer.
- **A `T?` ON AN UNCONSTRAINED TYPE PARAMETER IS A REFERENCE ANNOTATION, AND A VALUE ARGUMENT ERASES
  IT** (census NULLABLE2). C#'s `T?` there says "may be the default" and has no runtime form: only
  `where T : struct` spells a real `Nullable<T>`, and the CLR writes THAT one as `Nullable<T>` in
  metadata, so the two are different types with one spelling. `NullabilityGenericSubstitution`
  owns both halves of the decision — `ErasesNullableAnnotation` (a bound type that cannot carry a
  reference annotation erases it; `unknown` never does, so a failed inference is not a silent type
  change) and `LiftedTypeParameterNames` (the declaration's `struct`-constrained parameters) — and
  THREE walks ask it: the reflection reader's substituted-parameter arm,
  `AnalyzerSyntheticCallFacts.ApplyGenericBindings` for a generic FUNCTION's own parameters, and
  `AnalyzerDeclarationContext.ResolveTypeReferenceCore` for a member read through an instantiation of
  the declaring TYPE. The census site was
  `times.OrderBy(kvp => kvp.Value).FirstOrDefault()` over a `Dictionary<string, DateTime>`: the
  result read as `KeyValuePair<string, DateTime>?`, so `.Value` bound as the nullable UNWRAP instead
  of as the pair's own property.
- **THE NARROWED-ORIGIN LOOKUP HAS TWO HALVES, BECAUSE A LOCAL AND A PATH ARE NARROWED BY DIFFERENT
  MACHINERY** (census NULLABLE3). A narrowed LOCAL is rebound in the branch scope's symbol table, so
  nothing collapses at the read and `AnalyzerScopeStack.FindEnclosingNullableSymbol` walks OUT to the
  declaration. A member PATH's declared type belongs to its owning class and is not the scope's to
  rebind, so a path carries a null FACT alone and `ApplyNullabilityFlowType` collapses `int?` to
  `int` at the read — which left the member lookup nothing to see, and `h.Slot.Value` past a guard
  reported NL303 "Member 'Value' not found on type 'int'". The collapse now records what it
  collapsed (`AnalyzerNullFlow.RecordNarrowedNullableOrigin`, keyed by AST NODE identity because a
  line/column is not unique across the files of one analysis), and
  `AnalyzerNullFlow.NarrowedNullableOrigin` is the ONE owner of both halves — asked by
  `AnalyzerMemberAccess`'s two nullable arms and by `AnalyzerCallAnalysis`'s
  `TryRestoreNarrowedNullableReceiver`.
- **A TYPE PARAMETER IS A VALUE TYPE WHEN ITS OWN `where` CLAUSE SAYS SO, AND THAT FACT NOW LIVES ON
  THE SCOPE** (census NULLABLE3). `T` is a `SimpleTypeInfo` carrying nothing but its spelling, so
  `AnalyzerConversionFacts.IsReferenceType` answers YES of every bare name — and the `T?` of
  `func F<T>(a: T?) where T : struct` therefore lost its own surface INSIDE its own body:
  `a.HasValue` reported NL905 on a read that cannot throw, `a.GetValueOrDefault()` reported NL303 for
  a member `T` certainly does not declare, while `if a == null` and the narrowed `a.Value` beside
  them were already fine. `where T : struct` names no TYPE, so `Scope.TypeParameterConstraints` could
  not hold it; `Scope.StructConstrainedTypeParameters` does, written by
  `AnalyzerFunctionBodies.RecordTypeParameterConstraints` and read by
  `AnalyzerScopeStack.IsStructConstrainedTypeParameter`. `NullabilityGenericSubstitution.IsStructConstrained`
  is the ONE reading of the `struct` bit, shared with `LiftedTypeParameterNames`.
- **WHICH OF A `T?`'S TWO CANDIDATE TYPES A NAME BINDS ON IS DECIDED BY WHAT `Nullable<T>` DECLARES**
  (census NULLABLE3), read off the definition with `BindingFlags.DeclaredOnly`. The rule used to be
  "ask `T` first, fall through only for a name `T` cannot answer", which gave `T`'s answer for the
  three names `Nullable<T>` OVERRIDES — `ToString`, `Equals`, `GetHashCode` — so `v.ToString()` on an
  `int?` bound `int.ToString` and read the receiver as a DEREFERENCE (NL905 for a call that cannot
  throw). Both readings are metadata questions and neither is a name list; this one is the reading
  C# has. `GetType` is deliberately on the OTHER side: `Nullable<T>` does not override it, it boxes,
  and boxing an absent nullable is a null reference — the dereference report is the right answer.
- **A CONSTRUCTED GENERIC'S VALUE/REFERENCE KIND LIVES ON ITS DEFINITION.**
  `CanConvertedTypeCarryReferenceNullability` answered from the outer shape, so a non-generic
  external struct (a `ReflectionTypeInfo`) was read correctly and a constructed one (a
  `GenericTypeInfo`) was not — which is the whole reason `DateTime` worked and
  `KeyValuePair<K, V>` did not. It asks the DEFINITION now, the same way
  `AnalyzerConversionFacts.IsReferenceType` does, so the two owners cannot disagree; a
  `TupleTypeInfo` is a `ValueTuple` and answers the same as any other struct.
- **AN OBLIVIOUS SHELL IS TRANSPARENT TO IDENTITY ON EITHER SIDE.** `TypeInfoIdentityFacts.AreEqual`
  used to unwrap one only when BOTH sides had it, and `ResolveDeclaredAlias` already strips it at the
  top of a comparison — so it was transparent for `string` and opaque one level down, and the
  `string![]!` an N#-emitted `string[]` parameter reads back as refused a `string[]` argument. It
  unwraps on either side now, comparing the inner type against the other side, so `string![]` matches
  `string[]` and still does not match `string?[]`.
- THE TYPE OVERRIDE is consulted TWICE — once before the walk for a generic parameter, and again at
  the leaf for a type the walk did not decompose. A null answer means "decline", and falls through
  to exactly what no override at all would produce.
- THE OVERRIDE CROSSES THE BOUNDARY AS `Func<Type, object>`, not `Func<Type, TypeInfo>`. A closed
  `Func` over an EMITTED type is off the columnar surface (`emit.declaration.method-param`), while
  one over `object` is on it, so the N# owner takes `object` and casts once. The C# call sites keep
  their own `TypeInfo`-returning lambdas verbatim; the conversion is the C# compiler's own implicit
  reference conversion.
- FOUR FLOW ATTRIBUTES are recognised by the TYPE reader and no others: `MaybeNull`, `NotNull`,
  `NotNullWhen` and `ParamArray`. `MaybeNullWhen`, in particular, contributes nothing to the rendered
  TYPE — an out parameter annotated with it renders as a plain `out string? value`. The FLOW reader
  beside it (`AnalyzerNullabilityPostconditions.nl`, below) reads a wider set, because a postcondition
  is a fact about the caller's variable rather than about the parameter's type.
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

### Nullability postconditions — what a call leaves behind (census 2026-09-13, §FLOW3)

`AnalyzerNullabilityPostconditions.nl` (Semantics) owns what a call proves about the arguments it
was handed once it has returned. Its vocabulary sits one slice lower, in `NullabilityFlowFacts.nl`
(Model), because the type factories read it too: `NullabilityFlowFacts` is the bit vocabulary and the
SOURCE reader (over the parser's `AttributeNode`s); `NullabilityFlowAttributeReflection` is the
metadata reader (over `CustomAttributeData`, with the same boxed-value comparison the type reader
needs under an MLC). `NullabilityPostcondition` is one fact: a stable path, a condition (0
unconditional, 1 when the call returned true, 2 when false) and a `NullState`.

Three rules, composed in this order:

- An `out` or `ref` argument's variable holds whatever the PARAMETER's declared nullability says once
  the call returns. `out string` leaves a non-null string; `out string?` leaves a maybe-null one; an
  OBLIVIOUS parameter read out of un-annotated metadata says nothing and leaves the variable's own
  state alone.
- `[NotNull]` on ANY parameter overrides that and holds unconditionally — that is the whole of
  `Assert.NotNull(value)`. `[MaybeNull]` is asymmetric on purpose: on an `out`/`ref` parameter it is a
  postcondition, and on an INPUT parameter it is a statement about what the callee does with the
  value and proves nothing about the caller's variable.
- `[NotNullWhen(b)]` / `[MaybeNullWhen(b)]` make the fact CONDITIONAL on the call's own boolean
  result. The named branch gets the attribute's state; the branch it did not name keeps what the
  declaration alone already said (which is only owed for a by-ref position).

CONDITIONAL FACTS ARE FILED AGAINST THE CALL NODE RATHER THAN APPLIED, because a call in a condition
is analysed BEFORE the `if` walk asks what the condition proves; `AnalyzerFlowNarrowing`'s call arm
reads them back when it meets the same node, so `&&`, `||`, `!` and the ternary compose for free.

`c == true` IS `c` (census 2026-09-13, §FLOW5). `AnalyzerFlowNarrowing.TryExtractBooleanLiteralComparison`
is the one rule behind all four spellings: the comparison holds when the operand is TRUE exactly when
`(operator is ==) == (literal is true)`, which passes the two lists through, and otherwise swaps them
— the same thing `!` does. A converter writes `== true` wherever the source compared a LIFTED boolean,
and until this rule existed the comparison proved nothing at all. A LIFTED operand (its spine crosses
a `?.`) only proves the side the comparison DECIDED: `==` is definite when it held and `!=` when it did
not, and the decided side also gets the chain's tested receivers, while the other side is a
disjunction with "the receiver was null" and proves neither operand.
Unconditional facts are written into the flow immediately, INCLUDING the invalidation an assignment
performs — an `out` argument IS an assignment, so every fact derived from that path is stale.

A REFLECTED CANDIDATE THAT LOSES LEAVES NOTHING BEHIND: the facts are computed in
`AnalyzerReflectionArgumentBinder`'s finalise, held on `ReflectionCallFinalizeState.Postconditions`,
and committed by `AnalyzerCallAnalysis` only when the call's walk accepts the candidate. The SOURCE
half is recorded by `AnalyzerSyntheticCallValidator.RecordCallPostconditions`, a second pass over the
same binding the argument checks used (a second pass because the first `continue`s past positions it
has nothing to report about, and those positions still owe a postcondition).

A MEMBER'S NULLABILITY ATTRIBUTES TRAVEL ON `DeclaredMemberInfo` (census 2026-09-13, §FLOW6).
`AnalyzerFunctionTypeFactory.BuildFromDeclaration` reads them straight off a free function's
`FunctionDeclaration`, but a member declared on a TYPE reaches its callers through
`NominalTypeInfoFactory.CreateDeclaredMemberInfo`, and that record used to carry only the
REACHABILITY bits. So `Assert.NotNull(x)` proved nothing whenever `Assert` was a class — which is
every converted xunit file — while the identical free function proved it. `ParameterNullabilityFacts`
now sits beside `ParameterReachabilityFacts`, is filled by `GetParameterNullabilityFactArray` /
`ReadNullabilityFlowFacts` (the same walk as the reachability reader, asking the other vocabulary),
and both arrays reach the signature through one `ToDeclaredFactList` — both spell "nothing to say" as
zero, and a null list is what keeps the call validator's cheap skip cheap.

### An unwrap is a flow fact (census 2026-09-13, §FLOW6)

`AnalyzerNullFlow.RecordAssertedNonNullPath` is called from `AnalyzerExpressionTail.Finish` for EVERY
expression, before the tail reads that expression's own null state. Two shapes qualify, recognised
syntactically: `must e`, and `e ?? throw …` (through a parenthesised `throw`). Both record
`NullState.NotNull` for the operand's STABLE PATH, so a member path is proved exactly as a local is,
and an unstable operand records nothing.

`must` IS TRANSPARENT IN BOTH STABLE-PATH WALKS. `TryGetStableNullPath` and
`TryGetNullConditionalChainPath` step through a `MustExpression` the way they step through a
parenthesis: `must x` denotes the storage `x` denotes, and the keyword adds a throw rather than a
different path. That is what makes `Assert.NotNull((must doc).Error)` file its postcondition against
`doc.Error` instead of against nothing — the shape the converter writes for C#'s `doc!.Error`.

The over-approximation is deliberate and matches the postcondition machinery beside it: an unwrap in
a conditionally-evaluated position (an `&&` right operand, a ternary arm) still records, because the
author asserted it and the runtime check is real.

### A loop's back edge (census 2026-09-13, §FLOW6)

`AnalyzerLoopCarriedNullFacts` collects every stable path a loop body — and, for a `for`, its update
clause — can write; `AnalyzerLoopSequence.JoinLoopBackEdge` invalidates each one at the loop head.
The analyzer walks a body ONCE and the program runs it many times, so without the join a fact proved
before the loop was believed on every turn even when the body wrote the path it was about, in all
four loop forms and for a local as well as a member path.

WHERE THE JOIN SITS IS THE RULE. `while` joins at phase 10 and `for` at phase 22 — BEFORE the
condition, so `while x != null { … }` still narrows inside its own body, and AFTER a `for`'s
initializer, which runs once and whose facts survive. `foreach` joins at phase 4, before the body and
after the collection, because the collection is evaluated once outside the loop.

WHAT COUNTS AS A WRITE is what invalidates a fact anywhere else: an assignment, a `++`/`--`, and a
`ref`/`out` argument, each named by `TryGetStableNullPath`, walked through lambdas and local functions
declared in the body. A method call on a receiver is NOT a write (C#'s optimistic rule), and a `:=`
tuple deconstruction declares rather than writes. The walk is typed rather than reflective; a new
expression node needs an arm there, and its absence is a SILENT missing NL905 rather than a red test,
which is why `AnalyzerLoopCarriedNullFacts.tests.nl` pins every container shape.

### The join after a conditional (census 2026-09-13, §FLOW7)

`AnalyzerConditionalJoin` owns what is true AFTER an `if`, and `AnalyzerLoopSequence`'s `if` walk
phases 31–37 are its caller. The guard-clause rule was the only half that existed: a branch that
always leaves deletes one path, so the surviving flow inherits the other. An `if` whose branch FALLS
THROUGH has two live paths, and the analyzer used to answer by forgetting both — the branch's facts
died with the branch's scope and the condition's FALSE facts were installed nowhere — so the
TryGetValue-or-create idiom (`if !d.TryGetValue(k, out v) { v = new … }` then read `v`) reported
NL905 on a value both paths had just proved non-null.

THE RULE: after `if c { S }` the state is `join(exit(S), falseFacts(c))`; after `if c { S } else { T }`
it is `join(exit(S), exit(T))`; a branch that always leaves contributes nothing. `Meet` is the
ordinary lattice — agreement survives, disagreement is `MaybeNull`, `Unknown` swallows and `Oblivious`
yields — and it is the same rule `NullableWalker.VisitIfStatement` states.

A BRANCH'S EXIT STATE IS A SCOPE'S FACT TABLE, which is why the `if` walk now OWNS the scope each
branch runs in. A BLOCK branch is handed back as its STATEMENT LIST (request kind 8, driven through
`StatementSequence.BeginList`) so the block does not push a scope of its own; the walk's own scope
opens at the block's position, so the scope COUNT and POSITIONS are unchanged. The `if` band grew to
30..43 for it: 31 opens the narrowing scope (still only when that branch's list is non-empty), 38
installs those facts, 32 opens the branch scope, 39 runs the body, 33 reads the branch's facts and
closes it, 40 reads the narrowing scope's and closes it — `OverlayFacts` lays the branch's over the
condition's — and 41/35/42/36/43 are the else branch's five. Keeping the narrowing scope SEPARATE is
load-bearing: a type narrowing writes the narrowed type into its scope's symbol table, so collapsing
the two turned `if v is string { v := 5 }` from an NL020 shadow into a false NL306 redeclaration. An
`else if` is a statement that scopes itself and still goes through kind 5 — inside the else branch's
scope, so what its own join installs is the else branch's exit state rather than a fact escaping the
outer `if`.

TWO GUARDS KEEP THE JOIN HONEST. Only a path BOTH sides speak for is joined: a path one side never
mentioned is one that side left to the enclosing flow. And a joined answer that is WEAKER than a
definite fact the enclosing flow still holds is refused — an assignment invalidates its path in every
open scope, so a path the enclosing flow can still answer for is a path neither branch assigned, and
without the veto a redundant `if x != null { … }` below a guard clause took `x` back to maybe-null.
A branch-local is filtered out by `ExitFacts`: a name the branch scope binds that NO enclosing scope
binds (`AnalyzerScopeStack.IsNameBoundOutsideTop`) dies at the closing brace, while a name it binds
that an outer scope also binds is an outer binding the branch merely NARROWED.

A `switch`'s ARMS JOIN THE SAME WAY. `AnalyzerPatternAnalysis`'s switch form already opened a scope
per arm (phase 72) and closed it at phase 75, so an arm's exit state was already a scope's fact
table; `RecordArmExit` reads it before the close and `InstallSwitchJoin` folds `MeetFacts` over the
arms at phase 72's exit. An arm that ALWAYS LEAVES contributes nothing; a `break` anywhere in an arm
sets `ArmsJoinable = false` and declines the whole join, because control then reaches the code below
from the middle of an arm; and a switch with no `default` arm
(`AnalyzerStatementTermination.HasDefaultCase`) is reached from one more place than it has arms, so
the meet also takes in `SurvivingFacts` — the state the enclosing flow still holds, which a path an
arm assigned no longer has. The owner now holds the scope stack and takes the flow-narrowing writer
at `BeginSwitch`. Columnar declines `switch` statements, so this rule's coverage is the estate rather
than a running native project.

A LOOP EXIT IS THE SAME RULE. `while` (phase 14) and `for` (phase 29, after its outer scope closed)
install the condition's FALSE narrowings into the surviving flow, because a loop is left through the
bottom only when its condition failed — unless `AnalyzerConditionalJoin.ContainsLoopBreak` finds a
`break` bound to this loop, which leaves with the condition untested. The walk stops at nested loops
(their `break` is theirs) and does not descend into lambdas or local functions.

### Lifted equality on a nullable value type (census 2026-09-13, §FLOW5)

`AnalyzerOperatorExpressions.CanCompareLiftedEquality` is the whole analyzer half: both operands are
unwrapped by `UnwrapLiftedValueOperand` — which answers the `T` of a `T?` ONLY when `T` is a value
type, so a reference annotation is left to the reference arm — and the SAME equality question is then
asked of what is left. It therefore admits exactly the lifted forms of the pairs the unlifted rule
already admits, and the result is `bool` rather than `bool?`: two absent values are equal and an
absent one differs from every present one, so the comparison is always decided (C# §12.12.7). It
recurses at most once, because an unwrapped operand is not a nullable.

That line was later CLOSED: every operator family lifts now — see "Lifted operators over a nullable
value type" below — and `CanCompareLiftedEquality` remains the primitive/enum/record-struct half of
equality's lift, with the USER-DEFINED half (`decimal? == decimal`, `TimeSpan? == TimeSpan`) answered
by `TryLiftedBinaryResult`'s equality arm ahead of it.

EMIT MIRRORS IT IN `ColumnarIlEmitter.TryEmitLiftedNullableEquality`:
`a.GetValueOrDefault() == b.GetValueOrDefault() & a.HasValue == b.HasValue` when both sides are
lifted, and `a.GetValueOrDefault() == <b> & a.HasValue` when one is. The lifted operand is STORED into
a local before its value is read, which is what preserves left-to-right evaluation order; the
`HasValue` half re-reads the locals and evaluates nothing. The element must be one `ceq` answers for
(the integral family, `char`, `bool`, the two floating types, any enum); anything else declines rather
than comparing wrongly. The arm commits when either side preflights as a `Nullable<T>` OR is a `?.`
chain root the preflight could not answer for — the other operand's known `ceq` element is what makes
that safe — and then reads the real types off what it emitted. `TryGetPreflightExpressionType` now
answers for a `?.` chain (`TryGetPreflightNullConditionalChainType` applies the chain's lift, and the
guard node itself is transparent to the type), which it previously could not do at all.

### Lifted operators over a nullable value type (census 2026-09-13, §LIFT)

C# §12.4.8, and ONE rule rather than one per operator family.
`AnalyzerOperatorExpressions.TryLiftedBinaryResult` runs AHEAD of every `*Result` arm in
`PlainOperatorResult`: it unwraps whichever operands are a `T?` over a non-nullable VALUE type
(`UnwrapLiftedValueOperand`, plus `AnalyzerConversionFacts.IsDefinitelyNonNullableValueType` on what
is left, which is C#'s own requirement), asks the UNLIFTED question of the elements, and wraps the
answer back up. `TryLiftedUnaryResult` is the same rule for `-`, `~`, `!`, `++` and `--`.

The unlifted question is asked by `UnliftedBinaryResultOrNull` / `UnliftedUnaryResultOrNull` --
PURE readers that REPORT NOTHING and are each the deciding half of the matching `*Result` rule with
its diagnostics removed. That is what makes the lift unable to admit a pair the unlifted rule
refuses, and what makes a refusal fall through to the ordinary arm, which states the problem in the
types the programmer WROTE (`int? + bool` still says `'int?' and 'bool'`).

TWO RESULT SHAPES. Arithmetic, bitwise and shift answer `R?`; an ORDERING comparison answers a plain
`bool`, FALSE when either operand is absent -- so the comparison is always decided and nothing may
narrow out of it. `++`/`--` answer the OPERAND'S OWN type, because the value is written back into the
storage it came from.

`&&` and `||` are NOT lifted (C# §12.14 defines only `&` and `|` over `bool?`): a short-circuiting
operator decides whether to evaluate its right side from the LEFT side alone, and an absent left
side cannot answer that. `LogicalOperatorResult` says exactly that, and its suggestion names
`== true`, `!= false`, `?? false` and the non-short-circuiting counterpart.

A bare `null` operand is NOT a lift (the lift needs a `T?` TYPE and the literal has none), a
REFERENCE annotation is not a lift (unwrapping `string?` would hand `string` to the primitive arm),
and nothing in the family is constant-folded.

EMIT IS `ColumnarIlEmitter.TryEmitLiftedNullableBinary` / `TryEmitLiftedNullableUnary` /
`TryEmitLiftedCompoundOperation`, plus the `Nullable<T>` arm of `EmitPostfixStep`. Both operands are
evaluated in source order into locals (a lifted operator does NOT short-circuit), every lifted side's
`HasValue` is tested, and the unlifted operation runs on the values; the absent path answers
`default(R?)` for a value result and `ldc.i4.0` for a comparison. There is NO per-operator table: the
operation is whatever `TrySelectLiftedElementBinary` selects, which is the SAME source-declared
`op_*` lookup, runtime `op_*` lookup and predefined promotion the unlifted arm performs, asked of the
element types. Only the PRESENCE test is lifted, so `checked` still throws and a present divide by
zero still throws.

`LiftedOperandArrivalType` is what keeps the lift out of a NARROWED read: a bare name flow has proved
present is read as its element type, so `if x != null { x + 1 }` is an ordinary `int + int` and is
not lifted a second time.

`bool? & bool?` and `bool? | bool?` are C# §12.14's THREE-VALUED table, not an ordinary lift --
`false & null` is FALSE and `true | null` is TRUE. `TryEmitThreeValuedBooleanLogical` writes it
branch-free as the two facts the table states: `value = a.v op b.v`, and
`present = (a.h & b.h) | (a.h & <a decides>) | (b.h & <b decides>)` where "decides" is `!a.v` under
`&` and `a.v` under `|`. A plain `bool` operand is wrapped into a `bool?` first, so one lowering
serves all three operand shapes. `^` has no such shortcut and is the ordinary lift.

Equality's USER-DEFINED half rides the same selection: `EmitLiftedEqualityElementComparison` uses
`ceq` for the elements the instruction answers for and the element's own `op_Equality` for the rest,
which is what makes `decimal? == decimal` and `TimeSpan? == TimeSpan` compile.

A `null` TERNARY ARM TAKES THE OTHER ARM'S TYPE. `flag ? name : null` used to decline with
"unsupported expression (node kind 5)" because a bare `null` has no self-type; the residual ternary
arm now emits `ldnull` for it and takes the other arm's type, which must be a reference type. When the
literal is the THEN arm it is emitted first, so the else arm's type is preflighted before the branch
is written at all.

### Equality over an OPEN type parameter (census 2026-09-14, §NULLABLE4)

`a == b` where both operands name the SAME type parameter of the enclosing function or type — seen
through at most one `?` — is admitted by `AnalyzerOperatorExpressions.CanCompareOpenTypeParameter`,
which sits between `CanCompareLiftedEquality` and the reference tail of
`CanCompareWithEqualityOperator`. `OpenTypeParameterName` answers the written name when the operand
resolves to a `SimpleTypeInfo` the enclosing declaration introduced (a type parameter has no TypeInfo
kind of its own), and `DeclaresEnclosingTypeParameter` reads `ambient.CurrentFunction` and
`ambient.CurrentClass` — exactly as the `lock` rule does.

A BARE `T` already compared, accidentally: the reference tail reads an unresolved parameter name as a
reference. `T? == T?` did not, and that asymmetry is what the census caught (`Same<T>(a: T?, b: T?)`
under `where T : struct`). The CONSTRAINT decides the LOWERING, not the legality — a `struct`
parameter's `T?` is a real `Nullable<T>` and lifts, an unconstrained or `class` parameter's `?` is an
annotation on one CLR type and lowers to the bare comparison. TWO DIFFERENT parameters (`T == U`) are
NOT this rule and keep the old refusal.

EMIT IS `ColumnarIlEmitter.EmitOpenTypeParameterEquality`: `EqualityComparer<T>.Default.Equals(a, b)`,
resolved through `ResolveClosedGenericMethod` (the same closed-generic member rebinding the
`Nullable<T>` getters use). The two values are already on the stack when the comparer receiver has to
precede them, so they are parked in locals and re-loaded in the SAME order — nothing is re-evaluated.
`IsLiftedEqualityOperandType` now admits a generic-parameter element, so the existing lifted pair
(`GetValueOrDefault` values compared that way, `HasValue` presence compared with `ceq`) serves `T?`
unchanged. C# refuses BOTH forms outright (CS0019); only equality lifts this way, because `<` and `+`
need an operand type that HAS them.

### A conditional arm with no type of its own is TARGET-typed (census 2026-09-14, §NULLABLE4)

`ColumnarIlEmitter.TryEmitConditionalAsType` takes a kind-13 node whose THEN or ELSE arm is a bare
`null`, a `default` or a `throw`, and emits BOTH arms as the target type — the declared return type,
the declared local's type, the assigned local's type, or the parameter's type. The typed arm goes
through `EmitConditionalArmAsType`, which is the lifted conversion when the target is a `Nullable<T>`
(that is what makes the `int` arm of `flag ? n : null` a `Nullable<int>`) and the keyword-zero,
adopted-int-literal and ordinary-walk doors otherwise.

THE ROUTE IS CHOSEN BEFORE ANYTHING IS EMITTED, because emit-then-check abandons the program: a
conditional whose arms BOTH carry types keeps the existing unification arm and its exact IL. A
throwing arm emits NO branch to the merge — the exception ends that path, so the merge label is
reached only from the arm that produces a value. BOTH arms throwing still declines
(`emit.conditional.both-arms-throw`), which C# refuses too.

### Reachability attributes — where a call sends control (census 2026-09-13, §FLOW4)

`AnalyzerReachabilityAttributes.nl` is the reachability companion of the nullability vocabulary
above: `ReachabilityFlowFacts` holds the bits and the SOURCE reader, and
`ReachabilityFlowAttributeReflection` the metadata one, with the same four name spellings and the
same boxed-boolean comparison under an MLC. `AnalyzerTerminatingCalls.nl` is the one owner that files
what each call proved, and both binders commit into it: the source path through
`AnalyzerSyntheticCallValidator.RecordCallTermination`, and the reflection path through
`ReflectionCallFinalizeState.TerminatingMethodFacts` / `TerminatingGuardArgumentIndex`, held until the
call's walk accepts the candidate for the same reason the postconditions are.

- `[DoesNotReturn]` on the callee ends the path the call is written on. `AnalyzerStatementTermination`
  reads it through an ExpressionStatement arm, so the missing-return rule (NL305) and the
  unreachable-statement rule (NL312) both get it. This is the ONE thing in that judgement that is not
  pure syntax, which is why the fact-holder is a PARAMETER: all three askers ask AFTER the statements
  in question have been analysed, and a caller that supplies none gets the pure-syntax answer.
- `[DoesNotReturnIf(b)]` on a parameter makes the call a guard clause. The flow that survives it is
  narrowed by what the argument proved on the branch the attribute did NOT name, through
  `AnalyzerExpressionStatements`' discard phase 4 and request kinds 9 (narrow by TRUE) and 10 (by
  FALSE) — the same step the `assert` statement uses.

WHOSE NULLABILITY THE `out` PARAMETER TAKES IS THE RECEIVER'S, AND A NULLABILITY ANNOTATION IS NOT A
SHAPE (census 2026-09-13, §FLOW5). `AnalyzerReflectionArgumentBinder.PopulateTypeInfoBindingsFromType`
reads the argument's structure to bind the method's own type parameters, and it asked
`argumentTypeInfo as GenericTypeInfo` directly — so a receiver wearing an `ObliviousTypeInfo` shell
(`ITestCase.Traits` is `Dictionary<string!, List<string!>!>!`, because xunit.abstractions carries no
nullable context) or a nullable REFERENCE annotation (`doc.Symbols?.TryGetValue(...)` hands the
receiver over as `Dictionary<K, V>?`) answered "not a generic" and contributed NOTHING. First binding
wins, so `TValue` was then bound by the next argument — the `out` variable, whose own `List<string>?`
made `DeclaredParameterState` answer MAYBE-NULL and the `[MaybeNullWhen(false)]` fallback fact say the
TRUE branch leaves a maybe-null value. The strip is structural only: the bare type-parameter position
still binds the annotated `TypeInfo` verbatim, and a VALUE nullable is never stripped because `int?`
IS `Nullable<int>` and a parameter spelled `T?` matches it as the construction it is.

A MEMBER DECLARED ON A TYPE reaches its callers through `DeclaredMemberInfo`, not through its
`FunctionDeclaration`, so that record carries `DoesNotReturn` and `ParameterReachabilityFacts` too;
without them the attribute worked on a free function and on an unqualified call and nowhere else.
(The nullability `ParameterFlowFacts` are still NOT carried there — a `[NotNullWhen]` on a method
declared on a type is the parallel gap, and it is FLOW3's to close.)

EMIT AGREES THROUGH ITS OWN MIRROR. `ColumnarMethodBodyPlanner.AlwaysReturns` takes the same fact as
a set of statement-node indices, and `ColumnarIlEmitter` WRITES that set as it emits each bare call —
where the callee is finally resolved — so the non-void body emits first and asks afterwards. The IL
still gets a terminator, because at the IL level the call does return: an `InvalidOperationException`
naming the callee, unreachable while the callee keeps the contract. At emission the fact is read for
members THIS program declares; a `[DoesNotReturn]` member of a referenced assembly binds through the
external call plan and is not read there, so such a body declines at emission — a decline, never a
wrong answer, and the diagnostics pass reads both.

### A FREE FUNCTION ACROSS AN ASSEMBLY BOUNDARY (2026-09-24, the Compiler.Syntax carve)

A namespace's free functions are its members wherever they were compiled, exactly as its types are.
Until this held, a referenced N# assembly's free function could not be called at all -- NL412 in the
analyzer, `emit.call.bare-unresolved` in the emitter -- and carving `Compiler.Syntax`, whose parser
kernels are GLOBAL free functions, out of Core broke every Core call into them. The rule and its two
owners:

- **The holder.** An N# assembly puts a namespace's free functions on `<namespace>.Program`, or on
  `<namespace>.<Program>` where the namespace declares its own `Program` (the name is then the user's
  type). A free function is one of the holder's PUBLIC static methods; a camelCase one is CLR
  `assembly` and not exported. EVERY referenced assembly's holder is asked, never the first that
  answers: two references may each hold one namespace's functions (the global namespace above all),
  and a name held twice is not one function -- it answers nothing and a call declines.
- **The analyzer** (`AnalyzerProjectDiscovery.TryResolveVisibleFunction`, asking
  `AnalyzerExternalTypeProbe.NamespaceFreeFunctions`): each visible namespace, in
  `SimpleNamePrecedence` order, is asked of source and then of metadata before the walk moves outward,
  so a source function wins at its own namespace and a referenced one in a nearer namespace beats a
  source one further out. A referenced winner is typed as its reflected method, so the call arm binds
  it like any reflected call (a refused argument is NL402, not NL202), and it credits the import that
  supplied it (NL010). The NL209 import tie counts referenced functions too.
- **The emitter** (`ColumnarFreeFunctionScope.BuildViews`, reading
  `ColumnarExternalTypeCatalog.FreeFunctionHolders` and `ColumnarExternalFreeFunctions`): each
  candidate namespace's referenced holders enter the file's sibling view at that namespace's rank,
  below a source function of the same rank, as `ColumnarSiblingMethodDefinition`s read off metadata
  (parameter modifiers, names, simple defaults, generic constraints, `[DoesNotReturn]`). Every sibling
  path -- the bare call, the preflight, the direct-call planner, method groups -- then reads them
  unchanged.

`tests/native/census-external-free-functions` pins it over
`tests/fixtures/census-external-free-functions-library`: the analysed and the emit-only paths compute
the same answer through global, enclosing, imported and yielded holders, and the precedence, export,
NL209 and refused-argument rows.

### A PROGRAM SPLIT INTO TWO PROJECTS (2026-09-24, the Compiler.Model carve)

A class type declared in a REFERENCED assembly is judged exactly as the same declaration is in
source, unless that assembly is the shared framework's. Carving `Compiler.Model` out of Core found three
places that judged a referenced class type more loosely -- 68 of Core's own NL202s vanished and one
false NL402 appeared, with no source change -- and each rule now lives in its owner:

- **The CLR bridge** (`AnalyzerAssignability.IsAssignableCore`, the mixed reflected arm): a reference
  `?` is not a CLR type, so asking the CLR whether `Node?` converts to `Node` erased the annotation and
  said yes. `IsMaybeNullIntoNotNull` keeps a maybe-null source of a non-framework referenced class
  type away from a not-null target there (an oblivious target still accepts it).
- **A reflected call's chosen signature** (`AnalyzerReflectionArgumentBinder.RefusesMaybeNullArgument`,
  reported by `AnalyzerCallAnalysis.ReportReflectionNullabilityMismatches` through the source call's own
  NL202 reporter): applicability peels a `?` on purpose (nullability never picks an overload), and
  nothing asked afterwards. Once a candidate of a non-framework method is accepted, each written
  argument the plain relation refuses is NL202 -- `string?` into a referenced `string` included.
- **The default flow state** (`NullStateFacts.DefaultFor`): every reflected class type was OBLIVIOUS,
  so a written `node: Node` over a referenced `Node`, or the narrowed `out` of
  `map.TryGetValue(key, out found)`, was never not-null. A bare non-framework reflected class type is
  not-null now: its metadata's maybe-null positions already arrive as `NullableTypeInfo` and its
  unstated ones as `ObliviousTypeInfo`.

The fourth defect was the member reader: `TryResolveSpelledTypeParameterMember` answered a closed
generic's member from the definition only when the member's type IS a type parameter, so
`IReadOnlyDictionary<string, Node>.Keys` (`IEnumerable<TKey>`) was read off the closed type, where
`NullabilityInfoContext` reports the substituted `TKey` maybe-null -- `IEnumerable<string?>` -- and an
overloaded call taking it (`ToDictionary`, six candidates) found none. A member that MENTIONS a type
parameter is answered from the definition now too.

"Shared framework" is `ExternalAssemblyScan.IsSharedFrameworkAssembly`: loaded from
`<dotnet>/shared/Microsoft.*/<version>/` or a `packs/*.Ref` reference image. Its class-type annotations
keep the old leniency, because enforcing them is a separate decision: measured on Compiler.Core alone
it adds 860 NL202s (`Type?` 673, `MethodInfo?` 65, `FieldInfo?` 65, `ConstructorInfo?` 23, ...).
`tests/native/census-external-nullability` analyses one consumer beside the library source and against
the library's built assembly and requires the same findings, plus the framework and oblivious controls.

### `out` nullability, and the by-ref relaxation that carries it

`ByRefTypeInfo.IsOutArgument` is a fact about the CALL SITE, set in `AnalyzerCallAnalysis.CompleteArgument`
when the argument was written `out`, and read in exactly one place: the by-ref arm of
`AnalyzerAssignability.IsAssignableCore`. C#'s rule is asymmetric — an `out` argument's variable may
have ANY nullability because the callee assigns it and never reads it, while a `ref` argument's must
match in both directions — and assignability is the only place the two sides of a by-ref position
meet. Putting the flag on the argument's type is what makes overload scoring, the argument validator
and the reflected binder agree without three copies of the rule.

ONLY A REFERENCE ANNOTATION IS DROPPED (`WithoutReferenceNullability`): `int?` is `Nullable<int>` and
`int` is not, so an `int?` variable is still not an `out int` argument. N# has no `in` modifier, so
that third C# case does not arise.

### A `?.` chain and its continuation

`AnalyzerNullConditionalChainFacts.nl` answers where a chain begins and how far right it reaches, and
three owners ask it: `AnalyzerMemberAccess.Finish`, `AnalyzerIndexAccess`, and
`AnalyzerCallAnalysis.IsNullConditionalInvocationTarget` (which is now just a spelling of
`SpineReachesNullGuard`). A link written after a `?.` in the same receiver spine is a CONTINUATION: it
reports no null dereference, and its result is lifted. An INVOCATION whose callee spine crosses a `?.`
is lifted at the call — `.Trim` resolves to a method group, which has no nullable form, so the lift
waits for the value (`AnalyzerCallAnalysis.LiftNullConditionalChainResult`, at the walk's one exit).

A PARENTHESIS ENDS THE CHAIN and the walk does not step through one, which is the same node
`ColumnarIlEmitter.IsNullConditionalChainRoot` stops at. The emitter has always read chains this way;
before this slice the ANALYZER did not, so `s?.Trim()` typed as `string` while the emitter returned a
null reference for a null receiver.

THE LIFT SKIPS A CALLEE — EVERY CALLEE, INCLUDING THE `?.` LINK ITSELF (census 2026-09-13, §FLOW5).
`AnalyzerMemberAccess.Finish` used to lift on `member.IsNullConditional` regardless of whether the
member sat in INVOCATION position, so `x?.M(...)`'s callee came back as a `NullableTypeInfo` over a
`ReflectionMethodGroupInfo` — and `AnalyzerCallAnalysis.Dispatch` matches nothing against that, so
the call fell off the end of the dispatch table and answered `unknown`. Every `?.` invocation in the
language was therefore unbound: no overload resolution, no argument diagnostics (`h?.M("a","b","c")`
reported no arity error at all), no nullability postconditions and no `[DoesNotReturn]` facts. The
gate is now `(member.IsNullConditional || isChainContinuation) && !invocationPosition`, and the
INVOCATION lifts the result exactly as it always did.

`AnalyzerNullConditionalChainFacts.CollectGuardedReceiverPaths` answers the other half — WHICH
receivers a chain tested — by walking the same spine and handing the first `?.` link's receiver to
`AnalyzerDiagnosticSpanFacts.TryGetNullConditionalChainPath`, which collects any further `?.` to its
left. `AnalyzerFlowNarrowing` uses it to narrow those receivers on the branch a lifted comparison
decided.

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
- `BuiltInTypeSpellings.BuiltInClrTypeName(name)` (Model) is the CLR name each of the eighteen
  denotes, over the same membership. It is what the editor's type resolution asks; do not confuse either with
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

TWO EXCLUSIONS, both C#'s. THE WHOLE LEXICAL CHAIN wins outright — a lexically closer declaration is
not a tie, so the file's own namespace AND every enclosing namespace outward (ending at the global
namespace) stand the gate down, and an `import` that merely names one of them is skipped as redundant
rather than counted as a rival — and the project-wide unique-exported FALLBACK is never a candidate,
because it is the channel that runs when no import supplies the name.

THE METADATA HALF IS NO LONGER A HALF (census 2026-09-13, §AMBIG). The tie check used to ask the
assemblies only once the SOURCE sweep had already matched, because a miss was re-swept over every
loaded assembly on every call and putting that on `Console`, `List` and every other ordinary CLR
spelling was not affordable — so two IMPORTED CLR namespaces declaring one spelling resolved
first-import-wins with NO diagnostic, and `import System` beside a library that declares its own
`Range` silently meant a type its author never chose. That was a cost, never a rule: C# reports
CS0104 for that shape too. `AnalyzerExternalTypeProbe.TryResolveFullName` now remembers a miss
against the ASSEMBLY COUNT that proved it — the analyzer's assembly list only grows while a file's
imports are processed, so the count is an exact invalidation — and the sweep the resolver was going
to take a step later is what answers the gate. The tie is reported wherever it occurs: source against
source, source against metadata, metadata against metadata. The probe name carries its ARITY (`List`1`
and `List` are different metadata identities); the two candidates a reader is shown are spelled the
way the file spells them.

THE NAMESPACE WALK LIVES IN THE DISCOVERY OWNER, not in the probe: only discovery knows the file's
namespace, so only it can skip an import that merely names a LEXICAL namespace, or the namespace a
source declaration already claimed. `AnalyzerExternalTypeProbe.ImportedNamespaceDeclares` is the
single step it walks with.

EVERY POSITION REACHES THE GATE. `AnalyzerTypeResolver.ReportAmbiguousImportedTypeIfNeeded` is the
callable owner (the inline block it replaced could only be reached by the type walk). An ATTRIBUTE's
bracket spelling is looked up through a deliberately positionless probe — `ResolveSimpleType(name, 0, 0)`,
so `AnalyzerAttributeValidator` can own its own "not found" wording — and that silence used to swallow
the tie as well; the validator now asks the gate first, for both of `[Tag]`'s legal spellings
(`Tag`, `TagAttribute`), and reporting ends that attribute.

A CROSS-FILE MEMBER'S TYPE REFERENCE IS READ IN THE FILE THAT DECLARES IT. `DeclaredMemberInfo`
carries raw `TypeReference`s out of another file's syntax tree: their spelling is scoped by THAT
file's imports and their line/column are positions in THAT file.
`AnalyzerConstruction.DelegateConstructorParameterType` handed them to the current file's resolver,
which produced a false NL209 decided by the CONSUMER's imports and stamped at the declaring file's
coordinates against the consumer's path — a caret pointing into the middle of a line that never
spells the name (census 2026-09-13, §AMBIG, finding 4). It now reads them through
`AnalyzerDeclarationContext.TryResolveTypeForOwner`, the owner-scoped door the rest of the
declared-member family already uses. Any new site that resolves a `TypeReference` it did not read out
of the file being analysed must use that door.

**THE GENERIC HALF OF THAT GUARD WAS UNREACHABLE** (census 2026-09-13, §AMBIG). The
imported-CLR-type probe below was asked for `TypeArityNames.Display(name)` — the identity with its
arity suffix stripped — and no assembly declares a type called `List`, so a source `class List<T>` in
a namespace a file never imported took the name back from the `System.Collections.Generic.List` that
file's own `import` brought in, and `items.Add(1)` reported NL303. The probe is asked at the LOOKUP
name now. `tests/native/census-imports/ShadowingGeneric.tests.nl` executes it.

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

**THE EMITTER NOW CLASSIFIES THE SAME RECEIVER THE SAME WAY.** `ColumnarIlEmitter.TryEmitBclMethodCall`
read only a BARE identifier as a possible type name, so a call the analyzer had already resolved through
`TryResolveQualifiedTypeName` reached the INSTANCE arm at emit, tried to put a namespace on the stack,
and declined at `emit.call.receiver` — the analyze/emit disagreement this section warns about.
`TryClassifyDottedTypeNameReceiver` asks the ordinary type-name question (root not bound to any visible
value; the whole dotted name resolved by `ColumnarSemanticTypeRegistry.TryResolve`) and routes a chain
that answers with a type into the same static arm the bare spelling uses. Its argument twin is the
PREFLIGHT type of `must` (node kind 45): the unwrap produces its operand's type, `Nullable<T>` yielding
`T`, which is what lets overload scoring see a `must` argument at all.

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
`AddProjectUnitsTo` hands it the units in it. (Those 47 are the ROOT `project.yml`'s umbrella over
every example, fixture and template in the repository — single-file example directories with no
`project.yml` of their own, `examples/17-issue-tracker` beside its `tests/fixtures` copy — and within
that umbrella they are reported as they would be in any one project: NL306 for a free function,
NL339 for a type. The order still decides what a USE binds to; it no longer decides silently.)

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

`TryResolveVisibleProjectFunction` takes the SAME export decision as step 1 of the type channel —
export is required from every visible namespace EXCEPT the file's own — and returns the matched
`FunctionDeclaration`, its file and its symbol declaration; the shell then asks
`AnalyzerFunctionTypeFactory.CreateFromDeclarationInFile` for the `FunctionTypeInfo`. Nothing in
this family is C# any more.

**THE UNIT OF PRIVACY IS THE NAMESPACE, NOT THE FILE** (ruling 2026-09-02), and both channels say
so. Until 2026-09-13 the function channel required export unconditionally, so `A.nl`'s
`func formatTypeRef` was invisible to `B.nl` of the same namespace — NL412 at a direct call, NL402
at `names.Select(formatTypeRef)` — while a camelCase CLASS in those same two files already resolved.
N# has no file-private tier; splitting one namespace across files is the ordinary way to write it.
The cross-namespace answer is unchanged and is NL308 from `TryFindInaccessibleVisibleFunction`,
naming the declaring namespace and suggesting the PascalCase export. In CLR metadata a camelCase
free function is emitted `assembly` (`ColumnarDeclarationPlan.MethodVisibilityAttributes`) and a
PascalCase one `public`; the ruling changed the LANGUAGE rule, not one metadata bit. Contracts:
`AnalyzerProjectDiscovery.tests.nl` (both channels, from inside and outside the namespace) and
`tests/native/census-visibility` (runtime, CLR metadata, `FindDefinition`/`FindReferences`,
completion and the NL308 negative, over files on disk).

**THE DECLARED ACCESSIBILITY RULE IS A SECOND, INDEPENDENT SYSTEM** (2026-09-13, stream ACCESS), and
`MemberAccessibility` is its one owner. The package rule above is about a NAME's casing;
`private` / `protected` / `protected internal` / `private protected` / `internal` are about a TYPE,
mean what the CLR means, and until this slice N# parsed them, emitted them into metadata, and
enforced NONE of them — `d.Seed` on a `protected` field from a free function checked clean and
emitted.

`MemberAccessibility` publishes the CLR's six levels as an ORDERING (`Private` 0 …`Public` 5), reads
a level off written modifier bits (`LevelOfDeclaredModifiers`) or off a reflected
`MethodBase`/`FieldInfo` (`LevelOfMethod` / `LevelOfField` / `LevelOfClrFlags`), and answers ONE
relation for both:

```
IsAccessible(level, isDeclaringType, derivesFromDeclaringType, receiverIsAccessingTypeOrDerived, sameAssembly)
```

The receiver argument is C# §7.5.4 and is not optional: inside a derived type, `this.Seed`,
`Seed`, `base.Seed` and `other.Seed` where `other` is of the DERIVED type are legal, and
`other.Seed` where `other` is typed as the BASE is not. `base.` is its own arm at the call site
rather than a receiver judgement, because `base` is typed as the base and so never satisfies the
receiver test.

`LevelOfDeclaredModifiers` deliberately answers `Public` for a member with NO written word,
including a camelCase one. Folding casing in here would refuse `widget.count` inside the package
that declared it — casing is the other rule, with the other owner and the other sentence.

`AnalyzerMemberAccess.ValidateDeclaredMemberAccessibility` is the call site, and it runs only when
the package rule did NOT report: one wrong thing gets one underline.
`AnalyzerDiagnosticSink.ReportInaccessibleDeclaredMember` renders it, naming the word, the declaring
type, and the type the access was written from ("from outside every type" at namespace scope).
`CompletionVisibilityFacts.IsOfferableByDeclaredAccessibility` keeps the editor from offering what
the analyzer will refuse, driven by `EnclosingTypeName(unit, line)` and the name-based base-chain
walk `IsTypeOrDerived`; a caret outside every type offers exactly the public and package surface.
Contracts: `MemberAccessibility.tests.nl` (the relation as a table, source and reflected levels),
`SourceAccessibilityDiagnostics.tests.nl` (the refusals and their exact text, plus a fixture of
every access the rule ADMITS so a false refusal fails) and `tests/native/census-accessibility`
(runtime reads through `this`/bare/`base`/sibling receivers and the emitted metadata word).

**A SOURCE TYPE REACHES ITS EXTERNAL BASE'S `protected` METHODS** (2026-09-13, stream ACCESS;
COMPLETED by stream INHERIT2 the same day — see the closing note below). `Collection<T>` is designed to be extended through `SetItem`/`ClearItems`/`InsertItem`, all
`protected virtual`, and a `class Bag: Collection<string>` could not NAME any of them: the analyzer's
metadata arm asked `BindingFlags.Public` only (NL303/NL412) and the emitter's candidate enumeration
did the same. `AnalyzerMemberResolution.ResolveMember` now carries `inheritedProtectedAccess` — the
receiver half of the rule, answered by the caller (`AnalyzerMemberAccess.InheritsProtectedThrough`
for a written receiver, unconditionally true for a bare name, `base.`/`this.` as their own cases) —
and `IsReachableReflectedLevel` decides what that admits: the family surface and nothing else,
because the base is in a REFERENCED assembly and `assembly`-level members are never reachable.
`ColumnarOrdinaryRuntimeDirectCallResolver.ResolveInheritedWithFacts` is the emitter's twin, used by
the three inherited-base call sites only.

**...AND ITS FIELDS, ITS PROPERTIES, AND EVERY SPELLING OF BOTH** (2026-09-13, stream INHERIT2).
Two spellings still declined at NL103 after ACCESS, and neither was an accessibility gap:

* a protected method named with NO RECEIVER (`SetItem(0, v)`), while the identical
  `this.SetItem(0, v)` emitted. The inherited-base ARM behind the bare-call gate already selected
  `protected` members; the GATE in front of it (`ColumnarDirectCallPlanner.HasInheritedExternalInstanceMethod`)
  enumerated `GetMethods()` — public-only, and throwing outright on a builder-bound base. It asks the
  same candidate set the arm resolves over now, through
  `ColumnarOrdinaryRuntimeDirectCallResolver.HasInstanceMethodAtArity`. A gate narrower than its own
  arm is a gap, not a rule.
* a FIELD or PROPERTY READ (`this.Items`, `this.CoreNewLine`, and the bare and `base.` spellings of
  each). `ColumnarBoundIdentifierPlanner` reached inherited members through
  `TrySelectAdmittedProperty`, which answers a NARROWER question than the one asked: a PUBLIC
  PROPERTY whose result type is on the modelled-value list. Three independent facts each declined the
  read on their own — `protected`, being a field, and a result type off the list, the last of which
  refused PUBLIC members too. `TryResolveInheritedExternalMember` routes all four read sites
  (`this.`/bare through `TryResolveCurrentInstance`, `base.` through `TryResolveBaseMember`, and the
  two "is this name a value of the instance" predicates in `ColumnarFragmentBindings` and
  `ColumnarIlEmitter`) through the ordinary `ColumnarRuntimeInstanceMemberResolver.TrySelect` with
  the inherited-protected flag set, which answers for fields and properties alike at any result type
  the backend can hold. `CurrentField`/`BaseField` were already kinds; nothing new was needed to emit
  the field read.

Do not reintroduce a result-type list on this path, and do not let a gate ask a narrower question
than the resolution behind it.

**...AND TAKES THE SLOT OF ONE** (2026-09-13, stream INHERIT2). `override func SetItem(...)` over
`Collection<T>`'s `protected virtual SetItem` reported "no overridable base member matches", with or
without a written `protected`: `ColumnarBaseMethodMatch.IsOverridableTarget` enumerated the base's
non-public members and then threw every one of them away with `IsPublic`. It asks
`MemberAccessibility.IsAccessible` as a derived type in another assembly now, so `public`, `protected`
and `protected internal` are targets and the three assembly-bound levels are not. Behind it,
`ColumnarExternalMethodDescriptor.RecoverOpenMethod` was public-only too and answered
"The external method's open MethodDef could not be recovered from its declaring type" on the closed
handle's way back to its open `MethodDef`.

AN `override` TAKES THE ACCESSIBILITY OF THE SLOT IT REUSES when the source wrote no accessibility
word. A slot's accessibility belongs to the type that OPENED it, and the PascalCase spelling that
would otherwise make a member public is a default rather than a statement — emitting a `public`
override of a `protected` extension point would publish an API the base deliberately did not.
`ColumnarMethodOverrideDeclaration.DeclaresAccessibilityWord` carries whether a word was written and
`CompleteCore` swaps the metadata access bits for the matched target's when it was not. A written word
is still honoured, including a deliberate widening; the CLR refuses only a NARROWING override.

**COMPLETION OFFERS WHAT THE DERIVED TYPE INHERITS, INCLUDING `protected`** (2026-09-13, stream
INHERIT2, LSP-VISIBLE). A caret after `this.` inside a `class Bag: Collection<string>` listed `Add`
and `Count` and not `SetItem`, `ClearItems`, `InsertItem`, `RemoveItem` or `Items` — the members that
type exists to have overridden, and which the compiler accepts.
`CompletionReceiverFacts.AppendInheritedMemberItems` already carried `canReachProtected` down the
SOURCE links of the chain and then dropped it at the reflected base, where
`CompletionReflectionFacts.GetReflectionBindingFlags` asked for `Public` only. That walk asks for
`NonPublic` too now, and `CompletionReflectionFacts.IsReachableInheritedMember` (the same
`MemberAccessibility` relation the analyzer and the emitter ask) decides what of it is offered —
`private` and `internal` members of the base are still never listed. Every other receiver keeps the
public-only flags. `System.Object`'s own `protected` methods (`MemberwiseClone`, `Finalize`) are now
listed on such a receiver, which is honest — they ARE reachable — and is what a name-based filter
would have to be invented to suppress. A VS Code visual pass over this list is OWED.

**A LOCAL FUNCTION MAY DECLARE ITS OWN TYPE PARAMETERS** (2026-09-14, stream CAPTURE3). The statement
kernel refused any local function that declared one (`ParseColumnarFunctionInfoCore`'s
`isLocalFunction != 0 && signatureResult.Values[2] > 0`), so the whole ENCLOSING function failed at
`parse.function`. Lifting it needed no new lowering: `TryDeclareGenericLocalFunction` declares the
method in the order a generic top-level `func` is declared (define with no signature,
`DefineGenericParameters`, resolve the declared types through `TryResolveTypeWithTypeParams` in that
scope, `SetReturnType`/`SetParameters`), registers the parameters against a METHOD owner
(`ColumnarStructuralGenericOwnerIdentity.SourceTypeMethod`, keyed by the enclosing function's name
plus the synthesized ordinal — an unregistered parameter is refused outright by
`ColumnarStructuralTypeReferences`), and publishes the same `ColumnarSiblingMethodDefinition` a
generic top-level `func` publishes. Both call arms — the bare name and the explicit `id<int>(…)` —
then reach `TryEmitGenericSiblingCall`, which is where the inference, the constraint check and
`MakeGenericMethod` already live; a capturing one pushes its display receiver first, exactly as a
non-generic one does. An enclosing free function's parameters remain in scope: a capture-free local
copies them ahead of its own method parameters, while a capturing local copies them onto its generic
display type and leaves its own parameters on the display method. That distinction preserves CLR
VAR/MVAR ownership even when both parameters have ordinal zero, and copied constraints are emitted
on the new owner. `StrongBox<T>` construction and field access use `TypeBuilder.GetConstructor` and
`TypeBuilder.GetField` when T is builder-bound, because reflection cannot query that instantiation
before bake. The generic ones ride a SEPARATE map on `ColumnarLocalFunctionLowering`
(`GenericLocalFuncs`) because the direct map's entries are handles a call site dispatches without
closing. The same model applies inside a generic method on a non-generic source type. An `async`
generic local function remains refused (`emit.local-function.generic-async`).

**THE CONTEXTUAL-TIER GATE ASKS ALL THREE METHOD-GROUP SHAPES** (2026-09-14, stream CAPTURE3).
`ColumnarIlEmitter.IsContextualDelegateValueNode` — the predicate `HasContextualDelegateArgument`
uses to decide whether the contextual walk runs at all — recognised an OVERLOADED group written as a
bare name or on a TYPE, and not one written on a VALUE, even though the inference loop's own
phase-one test already reads all three (`TryGetReceiverInstanceMethodGroup` is its third arm). The
EXTENSION tier has no such gate by design, so `words.Select(greeter.Describe)` ran while
`words.ConvertAll(greeter.Describe)` — the same question asked of an INSTANCE method, which goes
through `TryResolveContextualDirectCandidate` — declined at `emit.call.instance-member`. A genuine
ambiguity (a group whose overloads make TWO `Select` overloads applicable) is still NL414, matching
C# CS0121.

**A PREFLIGHTED BLOCK LAMBDA'S OWN LOCALS ARE PART OF ITS FRAME** (2026-09-14, stream CAPTURE3).
`ColumnarIlEmitter.CollectBlockReturnTypes` typed each `return` in a frame carrying the lambda's
parameters and the enclosing scope and nothing the BLOCK declared, so
`xs.ConvertAll(x => { s := x * f; return s + 1 })` could type no arm at all and the call declined at
`emit.call.instance-member` after the analyzer had accepted it. `SeedPreflightBlockDeclaration` now
seeds a `:=` from its initializer's preflighted type and a `let name: T = …` from its written
annotation, as the walk reaches each statement in source order. The seeding rule is the one
`TryPreflightContextualLambdaReturnType` already states for the lambda's own parameters: only the
TYPE outlives this plan, so the ordinal need only be DISTINCT — the real lowering declares a local
and assigns the slot that reaches IL. A name the frame can already see is refused rather than
rebound, which is the emitter's own shadowing rule (NL316) restated.

**A MEMBER DECLARED IN A MORE DERIVED TYPE HIDES ONE OF THE SAME SIGNATURE IN A BASE** (2026-09-14,
stream CAPTURE3). `Type.GetMethods()` returns BOTH declarations of a `new`-hidden member, and both
candidate paths of `ColumnarOrdinaryRuntimeDirectCallResolver` counted that as an ambiguity:
`ResolveFromCandidatesCore` scored them equally (`bestCount > 1` -> `Rejected`, which the direct-call
planner reports as OWNED and refused) and `CandidatesAtArityCore` left two rows standing (so the
unique-at-arity rule answered nothing). `Task<TResult>` re-declares `GetAwaiter()` — returning
`TaskAwaiter<TResult>` where the base `Task`'s returns `TaskAwaiter` — so a written
`t.GetAwaiter()` on a `Task<int>` declined at emit while the identical call on a non-generic `Task`
bound. Both paths now apply C# §12.5's hiding relation, reusing the `SameCallSignature` /
`HidesDeclaration` pair the interface walk beside them already had: a return type is not part of a
signature, and when NEITHER declaration hides the other both are kept, because two unrelated base
interfaces declaring one signature is a real ambiguity.

**`object`'S PROTECTED SURFACE IS THE SAME BASE WHETHER OR NOT ONE IS WRITTEN, AND `Finalize` IS
REFUSED AT THE CALL** (2026-09-14, stream CAPTURE3). `class Holder: Exception` reached
`MemberwiseClone` and `Finalize` through the reflected base walk above; `class Holder` with no written
base reported NL303 for both, because `AnalyzerMemberResolution.TryResolveInheritedRuntimeMember` —
the arm `TryResolveSourceObjectMember` uses for the IMPLICIT `object` base — asked for
`BindingFlags.Public` only. It now takes `inheritedProtectedAccess` (the same flag `ResolveMember`
already threads) and opens `NonPublic` on its METHOD arm alone, holding every candidate to
`IsReachableReflectedMethod`; `object` declares no non-public property or field, so the other two arms
stay public-only. The enum surface (`System.Enum`) keeps the public-only flags: it is asked of a
VALUE, never from inside a declaring type.

`AnalyzerCallAnalysis` reports **NL341** after reflection overload binding selects a method.
`AnalyzerMemberResolution.IsRuntimeFinalizerMethod` follows that method's virtual slot to
`System.Object.Finalize`. It requires a non-static, virtual, parameterless `void Finalize()` and
walks declared base methods until it reaches `System.Object` or an unrelated new slot. An override
of an ordinary new-slot `Finalize` remains callable, as does a selected overload with parameters.
`MethodInfo.GetBaseDefinition()` is unavailable in `MetadataLoadContext`, so the walk reads
`MethodAttributes.NewSlot` (0x0100) and compares reflected type names across the metadata context.
The backend regression builds a referenced N# fixture, verifies its ordinary base slot with runtime
reflection, accepts both legal calls, and separately requires NL341 for `object.Finalize`.

**THE FORMATTER STOPPED WIDENING MEMBERS** (2026-09-13, stream INHERIT2, LSP-VISIBLE — format on
save). `FormatterSyntaxText.ShouldPreserveExplicitCasingVisibility` dropped a written `public`/
`private` whenever the PACKAGE-export answer was unchanged, which is only half of what a word means:

* `private protected Guarded` was reprinted as the strictly wider `protected` — the export answer is
  the same either way and the DECLARED level is not;
* `private draw` was reprinted as bare `draw`, turning a declaring-type-only member into a
  package-visible one (the contract in `FormatterSyntaxText.tests.nl` encoded the old answer and was
  updated);
* `public override func InsertItem(...)` was reprinted as `override func InsertItem(...)`, which
  after the override-accessibility rule above turns a deliberate widening back into `protected`.

A word is dropped now only when `MemberAccessibility.LevelOfDeclaredModifiers` AND
`VisibilityConventions.IsExportedIdentifier` both answer the same with and without it, and never on
an `override`. `public Draw` is still dropped, which is the only case that was ever redundant.

**A LAMBDA READS THE ENCLOSING INSTANCE IN EVERY SPELLING** (2026-09-13, stream INHERIT2). Two lambda
shapes could not, and neither was about capture analysis:

* `f := () => this.Value` declined at `emit.body` while `f: Func<int> = () => this.Value` emitted the
  same lambda. The PLACEMENT question — static program method, or private instance method bound to
  `this`? — was asked only on the path that has a delegate target; the `:=` path defined a
  signature-less STATIC method with no receiver at all.
  `ColumnarLambdaPlacementPlanner.PlanInferredZeroParameterPlacement` asks it for the inferred shape
  too, and differs from `PlanNonCapturingPlacement` only in defining the method signature-less so
  `SetReturnType`/`SetParameters` can run after the body decides the return type.
* `items.FindAll(x => x == this.Value)` CRASHED: "One argument ordinal cannot carry conflicting
  bound-identifier facts". Contextual return-type inference
  (`ColumnarIlEmitter.TryPreflightContextualLambdaReturnType`) runs in the ENCLOSING method's frame,
  where argument zero is `this`, and put the lambda's own parameter on ordinal 0 on top of it. The
  inference shifts the lambda's ordinals by one inside an instance body, which is what the real
  lowering already does; only the TYPE it computes outlives the plan.

**A FREE FUNCTION'S VISIBILITY WORD NOW REACHES METADATA** (2026-09-13, stream ACCESS). The word was
parsed into `ColumnarFunctionInput.VisibilityModifierFlags` and read by free-function identity, but
`ColumnarDeclarationPlan.BuildMethods` passed only `ModifierFlags` — which carries
`async`/`generator`/`native import` and never the visibility word — so `public func helper()` emitted
non-public and `private func Helper()` emitted PUBLIC. Both columns are now read.
`FreeFunctionVisibilityAttributes` is the rule and it has only TWO answers: `public` (written, or
implied by a PascalCase name) is `Public|Static` (22), and EVERY other spelling — a written
`private` or `internal`, and the camelCase default — is `Assembly|Static` (19). `Private` would be
wrong: a class of the same package, a lambda's display class and a local function's closure are each
a different CLR type and may all legally call a package-private function.

A resolved declaration's LINE is the declaration's own and its COLUMN is where the NAME starts on
that line (`CodeIntelligenceTextUtilities.FindIdentifierNameColumn`), which is what a
go-to-definition span has to point at.

**A FREE FUNCTION IS (NAMESPACE, NAME) EVERYWHERE, INCLUDING IN THE EMITTER** (census 2026-09-13,
§EMIT3). The analyzer always resolved a bare call through `SimpleNamePrecedence`; the emitter kept
ONE project-wide sibling map keyed by `fn.Name`, so a second `Helper` declared in another namespace
was shadowed by the first in every caller — `check` and `build` were clean and the program printed
the other namespace's answer. `ColumnarFreeFunctionScope.nl` is now the emitter's half of the same
rule: it holds every declared free function as a (namespace, name, exported, source file) row and
hands each body the sibling map ITS file sees, ranked caller's-file-first, then whole-file imports,
then the lexical chain outward, then the namespace imports. `ColumnarFreeFunctionHolders` gives each namespace its own `Program`
holder type, created on demand, so the two `Helper`s are two methods on two types
(`X.Program.Helper`, `Y.Program.Helper`) instead of two identical rows on one.

Two consequences the analyzer owns:

- **NL209 reaches the function channel.** `TryFindAmbiguousImportedFunction` mirrors
  `TryFindAmbiguousImportedType` for top-level functions, reported from the same 3a ambiguity gate in
  `AnalyzerIdentifierResolution`. It is asked only when the type half said no. The SUGGESTION differs:
  a free function has no namespace-qualified call spelling, so the fix is to drop an import.
- **A user type named `Program` keeps its name; the HOLDER yields.** `class Program` beside free
  functions is ordinary in this repository's own examples, so `ColumnarFreeFunctionHolders` asks
  `ColumnarProgramInput.DeclaresSourceTypeNamed` before it claims the name and falls back to
  `<Program>` — unspellable in source, therefore always free. Nothing is rejected and the source
  type's CLR name is untouched. MEASURED on 33b777917: the GLOBAL-namespace form of this shape
  emitted TWO type rows named `Program` into one assembly and the program still ran, so the fallback
  makes that metadata single-valued as well. (An earlier revision of this slice reported NL306 here
  instead; it broke three shipped examples and was withdrawn.)
- **A free-function name is declared ONCE per namespace, across files (NL306).** Measured on
  353fb69f7: two files of `X` each declaring `func Helper()` passed `check`, built, and the program
  printed whichever `Helper` the emitter's declaration order kept — the analyzer's file scan and the
  emitter had each picked a winner. `AnalyzerProjectTypeDiscovery.SameNamespaceFunctionTwins` builds,
  once per analysis, the top-level function names the OTHER files of the current namespace declare
  (first other file wins, own file excluded), and `AnalyzerDeclarationPolicy.DeclareTopLevelFunction`
  reports at each file's declaration naming the other — neither file is "second". The parameter
  lists play no part: the identity is (namespace, name); cross-file overloads of one name never
  worked (the view is name-keyed), and in-file free-function overloads decline at
  `parse.declaration-scan` (re-measured on 353fb69f7). The emitter's own word is
  `ColumnarFreeFunctionScope.Declare` answering `false` for a second (namespace, name) row, declined
  at `emit.declaration.duplicate`. The report is asked only when
  `AnalyzerProjectSourceProvider.CompilesAsOneProgram()` — the analysis root has a `project.yml`:
  `examples/03-functions` and its siblings are standalone single-file programs (five `Main`s, two
  `Sum`s in the global namespace) that the gate's Step 10 checks as ONE directory and the LSP opens
  with the directory as its fallback root; nothing compiles them together, so they cannot collide.
- **A type declared in two files of one namespace is NL339's, and its USE resolves.** NL339
  (`AnalyzerDeclarationPolicy.ReportTypeDeclaredInAnotherFile`) owns the duplicate: one report, at the
  later declaration, naming the first. Measured on 353fb69f7, the same project ALSO reported NL201
  "Type 'Widget' not found" at `new Widget()` in a third file, because
  `AnalyzerDeclarationContext.TryResolveDeclarationInNamespace` REFUSED a second same-namespace claim
  of one (name, arity) instead of picking one. It now answers the FIRST file of the namespace (and
  `TryResolveUniqueExported` counts namespaces, not files), so the use binds like the function
  channel and go-to-definition. `ColumnarDeclarationPlanner.TryFindDuplicateTypeDeclaration` is the
  emitter's own refusal at `emit.declaration.duplicate`, over one ledger of enum, interface,
  struct/class/record and union exact names (`PersistedAssemblyBuilder` accepts a second `DefineType`
  of one name silently). Unlike NL306's function rule, NL339 is not gated on a `project.yml` — the
  playground pins it in a project-less root.
- **The rule is per COMPILATION, so two assemblies may each declare the name — and the SDK's own
  slices are held to a stricter rule elsewhere.** NL306 and NL339 ask about one project, one
  assembly. Across assemblies the lookup rule (`SimpleNamePrecedence`) keeps a same (namespace,
  name) unambiguous: a bare call reaches only the compilation's OWN free functions (a referenced
  assembly's is NL412 as a bare call), a type at one namespace resolves source over metadata
  (CS0436's resolution), and two imported namespaces supplying one name are NL209. Probed on this
  port with a library and an app both declaring `X.Helper` and `X.Widget`: check clean, the app's own
  `Helper` and `Widget` win. So a user project may legitimately reuse a referenced library's names.
  The per-slice assemblies this compiler SHIPS side by side (Compiler.Model, Compiler.Core, the
  Syntax carve) are stricter, and not because of NL306: any free function puts a `<namespace>.Program`
  holder in its assembly, and two shipped assemblies holding one namespace's `Program` is CS0433 for
  every C# consumer that references both — `tests/native/census-free-function-identity`'s
  `ShippedHolders.tests.nl` refuses that for the committed seed and for the next pack's payload,
  whatever the function names are. Measured at 353fb69f7 the src projects share NO free-function or
  type identity across assemblies (294 function identities, 1,520 type identities).

**EXPORT IS REQUIRED ONLY ACROSS NAMESPACES, AND ONE OWNER SAYS SO.**
`SimpleNamePrecedence.RequiresExport(currentNamespace, candidateNamespace)` is that half of the rule:
a declaration is reachable from its OWN namespace whatever its casing — camelCase is
NAMESPACE-private (§VIS's ruling), not file-private — and every other namespace, an ENCLOSING one
included, needs it exported. Both `AnalyzerProjectDiscovery.TryResolveVisibleProjectFunction` and
`ColumnarFreeFunctionScope` read it, because they spelled it separately once and drifted: the
analyzer accepted a cross-file call to a camelCase function of the same namespace and the emitter
then declined the program at `emit.call.bare-unresolved`. A FILE import is the exception and always
requires export, because a file import carries only what the imported file exports.

**WHERE EXPORTEDNESS COMES FROM, AND WHY IT NEEDED A NEW COLUMN.** The declaration scan collects
modifier words for structs only, so a free function's `public`/`internal` word never reached the
columnar input and casing alone would have called `public func buildExplicit()` file-private and
`internal func Render()` exported — both the opposite of the analyzer's answer.
`ColumnarFunctionInput.VisibilityModifierFlags` now carries that word, filled from the same
`ColumnarStructDeclarationMetadataModifierFlagsAt` scan the struct column uses, and
`VisibilityConventions.IsExportedIdentifierWithFlags` is the one rule both sides read. It is a
SEPARATE column from `ModifierFlags` on purpose: folding the word in there would change the CLR
method attributes the declaration planner composes for every existing program, which is a different
decision. (Which is also why `public func` still emits a non-public method — a standing gap, not this
rule's.)

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
- **One walk skips the innermost scope**, because its question is about an ENCLOSING binding.
  `FindEnclosingNullableSymbol` answers what an identifier was DECLARED as when the flow is reading it
  as something narrower; it does not stop at a scope that binds the name to something non-nullable,
  and it starts at the INNERMOST scope — a guard clause (`if x == null { return }`) installs its facts
  into the scope that also declares the local, so there is no inner scope to skip.
  `ShadowsEnclosingValueBinding` (the NL316 decision) starts one scope out and stops
  dead at the first type-level or global scope: a member or a global of the same name is not
  shadowing. Underscore-prefixed names, `this`, `value`, function declarations and names the scope
  also binds as a type are all not value bindings, so they neither shadow nor are shadowed.
- **A type parameter's `where` clause lives on the scope that declared it.** A type parameter is a
  `SimpleTypeInfo` of its own name and carries nothing else, so `DeclareTypeParameterConstraints`
  records the resolved constraint types beside it and they leave scope with the declaration.
  `ConstrainedReceiverType` is the substitution both member lookup and the reflection call bind make
  before they ask anything about a receiver: ONE constraint IS the receiver's member surface, two is a
  merge-and-ambiguity question this owner does not resolve, and anything else answers with itself.
  BOTH call sites must substitute — `AnalyzerMemberAccess` before `ResolveMember` and
  `AnalyzerCallAnalysis` before the receiver is converted for `PreBindReflectionMethod` — because the
  surface the member was found on and the receiver an extension's own slot is matched against have to
  be the same type; substituting in only one of them makes `items.Count()` stop binding.
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
a path recorded as `NullState.Unknown`, and `NullState?` is off the columnar surface. A PATH is a
first-class subject here, not a second-class one: `doc.Error` carries its own state, established by a
guard, by `must`, by `?? throw` or by a `[NotNull]` postcondition on the argument expression, and
dropped by a write to any prefix, a `ref`/`out` on a prefix, the scope ending, or a loop's back edge
— see "An unwrap is a flow fact" and "A loop's back edge".

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

See `src/NSharpLang.Compiler.Model/TypeInfoModels.nl` (with `TypeInfoFactories.nl` and
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

`tests/native/tuple-names` is the executable evidence for both directions, and
`tests/native/census-parse-shapes/ValueTupleIdentity.tests.nl` for everything below.

ONE TypeInfo FOR `System.ValueTuple`N`. The analyzer used to have two representations for one CLR
type — a `GenericTypeInfo` named "ValueTuple" for the reflected or hand-written spelling and a
`TupleTypeInfo` for the written one — so `g: ValueTuple<string, List<int>> = (x, l)` reported NL202
with the two halves of one type printed as if they disagreed, and the mirror assignment reported the
mirror image. `ValueTupleTypeFacts.TryNormalizeConstructed` normalises a constructed `ValueTuple`N`
into a `TupleTypeInfo` at the CONVERSION BOUNDARY — `ReflectionTypeInfoFactory.FromConstructedGeneric`
for everything reflected, `AnalyzerTypeResolver.ResolveGenericTypeReference` and
`AnalyzerDeclarationContext.ResolveGenericType` for the written spelling, and
`AnalyzerTypeSubstitution.ResolveGenericTypeWithSubstitution` for the REBUILD a source signature goes
through — which is the rule `AnalyzerReflectionTypeConversion` already applies to `Nullable<T>`: lift
once, rather than special-case identity, assignability, display, member resolution and overload
scoring one at a time. Arity one keeps the constructed shape (`(T)` is not tuple syntax), and the
`ValueTuple`8` REST nesting is flattened so an eight-element tuple is eight flat elements.

NAMES TRAVEL WITH THE POSITION A VALUE WAS READ OUT OF. A member resolved through reflection has no
element names in it — `Dictionary<string, (Item: string, Ranges: List<int>)>.Values` substitutes over
the CLOSED CLR type — so `groups.Values` typed as `ValueCollection<string, (string, List<int>)>` and
every read off it reported NL303. `AnalyzerTupleElementNames.GraftFromReceiver`, applied where
`AnalyzerMemberAccess` settles a member's type, gives an UNNAMED tuple in the member's type the names
of the receiver's own tuple when the receiver's written type mentions exactly ONE tuple of that shape.
Only names change; identity is unaffected, because `TypeInfoIdentityFacts.AreEqual` ignores them. The
match must be unique: a receiver mentioning the same shape twice with different names says nothing.

AT EMIT, THE SAME WALK MUST PASS THROUGH THREE MORE LINKS, each of which used to end it — so a chain
written in ONE expression compiled while the same chain broken over statements did not, and the other
way round. `tests/native/census-parse-shapes/TupleNamesThroughBindings.tests.nl` executes all three.

- A LOCAL BINDING. `vals := groups.Values` binds a `ValueCollection<...>` that no annotation ever
  named, so `_labeledTypeByVariable` got no entry and `NearestLabeledContext` had nothing to follow.
  `_labeledContextByVariable` records where such a binding's value CAME FROM, and the walk goes
  through a local exactly as it goes through an undeclared property hop. Only one of the two maps is
  ever set for a name: one says what a binding IS, the other where it came from.
- A FIELD OR PROPERTY OF A SOURCE TYPE. `ColumnarInstanceMemberPlanner` claims a member access before
  the emitter's own arm sees it, and its name rewrite could only start a chain at a bare identifier,
  so `holder.Pairs["k"].Ranges` declined while `pairs["k"].Ranges` compiled.
  `TryReceiverWrittenType` answers the written spelling AND the CLR type that spelling names in one
  recursive walk (binding, source member, index read), because each link needs both: the label to
  carry and the type that says which position the next link reads. `TryGetPreflightMemberAccessType`
  gained the matching arm — preflight could not type an instance member of one of this compilation's
  own types at all, so every chain rooted at a source field was untypable.
- A GENERIC FUNCTION'S INFERRED RETURN. `Echo(row)` declared `func Echo<T>(value: T): T` answers the
  tuple `row` is, because a tuple type includes its element names and inference gives `T` the
  argument's own type. The written return canonical is `T`, which names nothing, and that empty
  answer used to win; a return written as a type PARAMETER now declares nothing, and
  `SiblingInferredReturnLabeled` reads the answer off the argument whose position is declared with
  that same parameter. The rule is structural (live signature handles, no name strings) and an
  ambiguous inference — two positions declared with the parameter — says nothing.

A TUPLE IS AN ARRAY'S ELEMENT TYPE too. `ColumnarTypeOfPlanner.IsSupportedElementType` admitted the
tuple syntax at every declared position except that one, so `rows: (Item: string, Count: int)[]`
declined at emit — and `ColumnarTupleElementNames.ArrayElementText`, written for exactly this read,
could never be reached.

A NARROWED nullable answers `.Value` whatever family its inner type is in. The narrowed-origin gate in
`AnalyzerMemberAccess` admitted only a `SimpleTypeInfo` or a `ReflectionTypeInfo`, so `found.Value` on
a narrowed `(Uri: string, Line: int)?` reported NL303 while the same access on a narrowed `int?`
resolved. The gate is identity with the origin's INNER type — the question the second nullable arm
already asked.

BUT ONLY FOR A VALUE `T?` (census 2026-09-13, §FLOW5). `Nullable<T>`'s surface exists because
`Nullable<T>` is a CLR STRUCT; a reference `T?` is an ANNOTATION on one CLR type, so `Value`,
`HasValue` and `GetValueOrDefault` there are whatever the CLASS declares and nothing more.
`TryResolveNullableMemberAccess` answered them for EVERY `NullableTypeInfo`, so
`documentation.MarkupContent?.Value` — `MarkupContent` being a class with its own `Value: string` —
typed as `MarkupContent`, warned NL907 about an unwrap the program never wrote, and then refused the
`string?` the function returned. The arm is now gated on
`!AnalyzerConversionFacts.IsReferenceType(nullableType.InnerType)` (the second arm,
`TryResolveNullableValueTypeOwnMember`, was already value-type-gated through the CLR handle). A
reference `T?` therefore falls through to ordinary resolution, and its maybe-null dereference rules
apply exactly as they do to every other member read.

AND FOR EVERY VALUE `T`, NOT ONLY THE ONES WITH A CLR HANDLE (census 2026-09-13, §NULLABLE2).
`TryResolveNullableValueTypeOwnMember` read the surface off the CLOSED CLR construction, and there is
no closed construction while `T` is a struct or an enum THIS COMPILATION is emitting — so
`money.GetValueOrDefault()` on a `Money?` reported NL303 "Member 'GetValueOrDefault' not found on
type 'Money'" (the name fell through to the UNWRAPPED receiver, the one type that certainly does not
declare it) plus NL905, while the identical spelling over an `int?` bound. Two rules replace that:
`IsLiftedValueReceiver` asks whether `T` is a VALUE type — of the CLR where it has a handle, of the
DECLARATION where it does not (a struct, an enum, a struct record and a tuple are values; `unknown`
is not one) — and `TryResolveOpenNullableDefinitionMember` reads the members off the `Nullable<>`
DEFINITION under the element substitution, the same `AnalyzerReflectionTypeOverride` every other
external generic closed over a source type goes through. Whatever `Nullable<T>` declares is what a
`T?` receiver has: both `GetValueOrDefault` overloads come back because the definition declares both,
and no name list decides anything. The definition is reached through the analyzer's own conversion
funnel rather than `typeof(Nullable<>)`, because under a MetadataLoadContext the projected definition
is a different object. The T-FIRST ORDER is unchanged: a name `T` itself declares still binds on `T`.

DECONSTRUCTION IS NOT ONLY FOR TUPLES. `AnalyzerVariableDeclaration.TryGetDeconstructMethodElements`
asks a non-tuple source for an accessible instance `Deconstruct(out ...)` whose out-parameter count
matches the target count, which is C#'s own rule and what makes `(k, v) := pair` work over a
`KeyValuePair<K, V>`. A type declared in this compilation answers from its own `DeclaredMembers`; one
from a referenced assembly answers through reflection, with a constructed generic's out types
substituted by position. Two overloads of the same arity answer nothing rather than picking one.

Still unsupported, and reported as such: an individually named element in a REST position past the
seventh.

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

### Which runtime handle a reference contract pairs with

A catalog entry has two halves: the METADATA image the `MetadataLoadContext` reads (a `ref/<tfm>`
facade, a framework pack, or a plain assembly) and the RUNTIME handle Reflection.Emit writes types
from. `ExternalAssemblyScan.SelectRuntimeAssemblyByMetadata` is the single place that pairs them, and
it asks, in order:

1. the project's own output, for an `obj/**/ref` or `obj/**/refint` input — and nothing else, ever;
2. the contract's own runtime asset (`lib/<tfm>` beside a `ref/<tfm>`, or the shared framework file
   behind a `packs/*.Ref` image) if that exact file is loaded;
3. a loaded assembly with the same identity AND the same module identity, i.e. the same build from
   another file;
4. the assembly the compiler's OWN LOAD CONTEXT BINDS for that identity.

Step 4 is not a fallback for untidy inputs, it is the normal answer whenever the compiler runs inside
a host that already owns an implementation of the identity — MSBuild's `Microsoft.Build.*`, or the
SDK's own copy of a package the project restored (`System.Reflection.MetadataLoadContext`,
`Microsoft.NET.StringTools`). A process cannot hold two assemblies of one identity in one load
context, so that handle is the only executable implementation the contract can ever have; refusing it
leaves the reference with no runtime types and the emitter declines (`emit.declaration.field-type`,
`emit.body`) rather than finding a better one.

The question is asked OF THE BINDER (`IsContextBoundRuntimeAssembly`), never by comparing load-context
objects: MSBuild loads the build task and Compiler.Core into a context of its own while keeping
`Microsoft.Build.Framework` in the context that one defers to, so a context-object comparison calls
the host's own implementation foreign. It stays exact in both directions — the binder must answer with
THAT assembly, so a same-identity build sitting in an unrelated load context is still refused.

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
`src/NSharpLang.LanguageServer/Services/TypeResolver.nl` performs the reflection reads and the
caching; it decides nothing. `BuiltInTypeSpellings.BuiltInClrTypeName` still owns the built-in
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
reason `KnownReceiverSpellings` gives: `typeof` of a static class does not emit and an open
`typeof(List<>)` does not parse.

Two owners are consulted rather than copied:

- **Eight of the twelve short-name spellings** are `KnownReceiverSpellings`'s answers (the table
  completion reflects over), not a second table: `Console`, `String`, `Math` and `DateTime` come from
  `KnownReceiverType`, and `List`, `Dictionary`, `HashSet` and `IEnumerable` from
  `KnownReceiverGenericDefinition` — which is
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

### The call walk's receiver is walked ONCE

A call whose callee is a member access analyses that member access, which analyses the RECEIVER —
and then the call walk asks for the same receiver AGAIN, once per receiver-shaped question the bind
has: six `AcquireReceiver` sites (a receiver-style generic candidate's inference, its validation and
its return type, and the same three for the bound member of an overload group) plus
`AcquireReflectionReceiver` for the reflected bind's CLR receiver. How MANY of those fire is the
walk's own decision and is unchanged — three for a receiver-style generic, one for a group whose
winner is not.

What changed is what a repeat COSTS. Each repeat used to re-walk the receiver's whole subtree, and a
fluent chain's receiver is itself a call whose receiver is a call, so an N-link chain was analysed
once per PATH through it — 2^N. Measured on `items.Select(x => x)…`: 14 links 6 s, 16 links 18 s, 18
links 66 s, a clean doubling per link; a 27-link `.WithHandler<T>()` server registration did not
terminate, which is what made `nlc check` never finish on a 31-file converted LanguageServer.

The repeats now ask for step KIND 16 instead of kind 6. `Analyzer.DriveMemberAccess` publishes the
receiver's DISPATCHED type — the value `AnalyzerExpressionTail.Finish` has not yet folded null flow
and the four value-misuse guards into — into a single slot, and `Analyzer.AnalyzeCall` keeps it in
LOCALS for the length of that call's walk. Every kind-16 read re-runs the tail on the kept type where
it stands, so each site still judges the receiver at its OWN ambient position (the callee frame
suppresses the method-group and SoA-operation guards; a later site does not), and nothing walks the
subtree twice. A member access that answered without a walk step — an import alias, a qualified type
name — publishes no receiver, and its reads fall back to a full analysis, which is how
`System.Console.WriteLine` still resolves its receiver as a TYPE the second time.

The visible consequence is that a receiver whose own analysis reports now reports ONCE. It used to
report once per repeat: `nlc check` distincted its result set and hid it, `nlc build` rendered the
same NL401 up to four times per pass.

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

#### `AnalyzerOverloadSpecificity` — "better function member", one owner, three callers (census 2026-09-13, OVERLOAD)

The score ladder rates two candidates the same whenever neither parameter is the argument's own type,
and until this owner existed the tie was broken by ORDER: declaration order in the source world,
metadata order in the reflected one. `Assert.Single(x.EnumerateArray())` bound the non-generic
`Single(IEnumerable): object?` over `Single<T>(IEnumerable<T>): T`, and the call's type silently
became `object?` (24 of the converted census's 29 `this value` NL905s).

`AnalyzerOverloadSpecificity` is ECMA-334 §12.6.4.3 stated once. It takes BOOLEANS, not types, so the
three worlds supply their own conversion oracle and share only the decision:

- `CompareConversionTargets(leftIsIdentity, rightIsIdentity, leftToRight, rightToLeft)` — one
  argument position's verdict. Identity first (the argument's own type wins the position), then the
  more specific type (the one that converts to the other and not back).
- `FoldArgumentVerdicts` — ALL-OR-NOTHING. A candidate that wins one position and loses another is
  not better, it is INCOMPARABLE, and incomparable is what NL414 reports.
- `CompareTieBreaks(parameterTypesIdentical, …, openTypeVerdict)` — non-generic over generic (gated on
  the substituted parameter types being IDENTICAL), normal form over an expanded `params` tail, fewer
  defaults, and LAST the written-signature verdict `AnalyzerOpenTypeSpecificity` supplies.
- `FindMaximalIndexes(comparisons, count)` — SELECTION IS A MAXIMAL-SET SEARCH, NOT A SORT. "Better"
  is a PARTIAL order, so a sort has no defined answer and would make the chosen overload depend on the
  candidate order. One maximal candidate is the call's overload; two or more is NL414; NONE (a cycle
  in the verdicts) leaves the caller's existing order alone.

The three callers:

- `AnalyzerCallAnalysis.PromoteBestReflectionCandidate` — runs after `SortReflectionCandidates` (which
  still owns the RETRY order) and moves the unique maximal candidate to the front. Oracle:
  `TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity` and `HasImplicitReflectionConversion`
  (`IsReflectionAssignableFrom` plus the numeric widening table) over each candidate's SUBSTITUTED
  parameter type per position. A member declared on a MORE DERIVED type wins an otherwise-identical
  pair (§12.6.4.4 hiding), asked before the generic rule. Three rules the positions themselves need:
  - **THE EXTENSION RECEIVER IS POSITION 0.** `values.AsQueryable()` writes no arguments at all and
    chooses between `AsQueryable(IEnumerable)` and `AsQueryable<T>(IEnumerable<T>)` entirely on the
    receiver; a comparison that read only the written list saw nothing to tell them apart, fell through
    to "non-generic beats generic" and typed the result as the bare `IQueryable`, after which
    `query.Where(x => x > 1)` had no element type to give the lambda (NL203).
  - **A POSITION NEITHER CANDIDATE FILLS IS NOT A DIFFERENCE.** Slot 0 is null for every non-extension
    call; treating that as "the parameter lists differ" switches off the non-generic tie-break for
    every ordinary static call.
  - **AN ARGUMENT WITH NO CLR FORM FALLS BACK TO THE N# RELATION** (`assignability.IsAssignable` over
    the parameter's `ConvertReflectionType`): a parameter that accepts the argument is a better target
    than one that does not, which is applicability stated as betterness for the case where
    applicability had no CLR type to reject either candidate with.
- `ReflectionComparisonIsFullyInformed` GATES THE REPORT, not the choice. NL414 accuses the reader of
  writing a call the LANGUAGE cannot resolve, and that is only honest when the comparison had something
  to compare. A position where the two parameter types DIFFER and the argument has no type at all — an
  anonymous object, which types as `unknown` and is therefore assignable to every parameter, or a lambda
  phase 32 deliberately left unanalysed — means the tie is the compiler's, not the program's, so the
  candidate is still chosen but nothing is reported. `BadRequest(new { errors: errors })` is that case
  (`BadRequest(object?)` vs `BadRequest(ModelStateDictionary)`); a METHOD GROUP has a type and is not
  exempt, which is the `Enumerable.Select` case NL414 exists for.
- `AnalyzerSyntheticCallWalk.BindNSharpCall` — collects the applicable candidates first and compares
  them afterwards, for the same partial-order reason. Oracle: `TypeInfoIdentityFacts.AreEqual` and
  `AnalyzerAssignability.IsAssignable` over the same `GetArgumentComparisonTypes` the SCORER reads, so
  the types the rule compares are the types the score came from. The two candidates must be asked
  about the SAME argument type (a `params` tail can make one compare a spread's element).
- `ColumnarSourceDirectCallResolver.SelectMostSpecificParameters` — the EMITTER resolves source calls
  independently, so it needs the rule too or it declines (NL103) a call the analyzer accepted. Oracle:
  `ExactTypeShapeMatches` and `ArgumentFlowScore(...) >= 0`. Asked only on a tie.

#### `ShouldReportUndefinedMember` through a BCL generic over a source type (census 2026-09-13, LAMBDA5)

`List<PriceArgs>.Nope` and `items.Nope` (over `items: List<PriceArgs>`) reported NOTHING: the generic
arm answers from a SOURCE definition or from a reachable CLR type, and a BCL definition closed over a
type that is still a declaration has neither — its closed CLR type cannot be constructed. The miss
first surfaced as an emitter decline (`emit.expression.generic-type-receiver` / `emit.return.expression`),
which names a backend rather than the typo.

The DEFINITION answers instead, and it is asked about the NAME: `HasReliableReflectionMemberSet(List<>)`
AND `List<>` has no member called `Nope`. A type argument never adds a member, so the report is certain.
Asking only "is the definition reliable" is NOT enough and was the first (reverted) shape — `List<T>`
inside a generic function has the same unconstructible closed type, and every `result.Add(...)` in the
estate became a false NL303. A name the definition DOES have is the analyzer's own resolution gap, not
the reader's.

#### `AnalyzerOpenTypeSpecificity` — "more specific parameter types", the last tie-break (census 2026-09-13, LAMBDA5)

`Task.Run(() => Task.FromResult(11))` answered `Task<Task<int>>` and every rule above agreed it should:
`Run<TResult>(Func<TResult>)` and `Run<TResult>(Func<Task<TResult>>)` BOTH close to `Func<Task<int>>`,
score the same, expand no params tail and default no parameter. C# separates such a pair with
§12.6.4.3's LAST tie-break, which is the only rule that reads the signatures UNINSTANTIATED. The
relation, spelled once for both worlds:

- a TYPE PARAMETER is less specific than anything that is not one (`Task<TResult>` beats `TResult`);
- an ARRAY is ordered by its element type, and only against an array of the same rank;
- a CONSTRUCTED type of the same arity is ordered element-wise, folded by `FoldArgumentVerdicts` —
  at least one argument more specific and none less specific. DIFFERENT arity answers NEITHER, which
  is why `Func<Task>` and `Func<Task<TResult>>` are not ordered here.

Two oracles, one rule: `CompareReflectionTypes` over CLR `Type`s (`IsGenericParameter`, `IsArray`,
`GetGenericArguments`) and `CompareSourceTypes` over the `TypeReference` the declaration WROTE, where
a type parameter is a bare name matching the signature's own `TypeParameters` — and each candidate is
asked with its OWN list, because `F<T>(x: T)` and `G(x: T)` name their parameters independently.
Written `Func<…>` parses as a `FunctionTypeReference`, so its parameters and return are its type
arguments. The source world's older `GetGenericParameterCost` (count of positions written as a BARE
`T`) is the shallow case of the same question and still answers before it.

Three callers: `AnalyzerCallAnalysis.BuildReflectionOpenParameterTypesByArgument` (the same walk that
builds the closed array, minus `ApplyReflectionBindings`), `AnalyzerSyntheticCallFacts.GetSourceOpenParameterTypesByArgument`
(the same walk `GetGenericParameterCost` uses), and — because the emitter resolves contextual calls
independently — `ColumnarIlEmitter.CompareContextualOpenSignatures` over each binding's
`OpenArgumentType`, which is what stops `Task.Run(() => Task.FromResult(11))` declining at emission
after the analyzer typed it.

#### The EXACT-MATCH candidate run (census 2026-09-13, LAMBDA5)

The open-type rule alone is not enough for `Task.Run`: `Run(Func<Task>)` accepts a lambda handing back
a `Task<int>` (by covariance) and C# eliminates it with §12.6.4.4's FIRST clause — the delegate the
lambda EXACTLY matches beats one it merely converts to. N# cannot ask that where C# does, because
phase 32 leaves a lambda argument unanalysed until an overload is chosen. So it is asked in the RETRY
loop instead: a GROUP whose call carries a lambda is walked TWICE, first with
`ReflectionCallFinalizeState.RequireExactLambdaMatch` (the lambda's own return type must BE the now-bound
delegate's — `AnalyzerReflectionArgumentBinder.LambdaExactlyMatchesTarget`, asked at the phase-two
analysis whose result nothing read before), and then, only if that bound nothing, accepting every
conversion exactly as the walk always did. Nothing a single run used to bind stops binding.
`PromoteBestReflectionCandidate` now moves EVERY maximal candidate to the front rather than just the
first, so the fallback the exact run falls back to is the next-best member and not the next row of the
score sort.

`AnalyzerOverloadFacts.LambdaBodyProducesValue` scores BOTH directions of the lambda-return rule. An
expression-bodied lambda has a value to give and prefers a delegate that keeps it (`Task.Run(() => 42)`
picks `Run<TResult>(Func<TResult>)`); a STATEMENT-bodied one with no `return <expr>` has none and
prefers a delegate that expects none (`Task.Run(() => { work() })` picks `Run(Action)`). Rewarding only
the first direction left the second pair tied on every key, which became an ambiguity report for a call
C# resolves without hesitating. The walk descends every statement the lambda's own body executes and
stops at a nested LOCAL FUNCTION; nested lambdas are never reached, because they live in expressions.

`AnalyzerOverloadFacts.MethodGroupConversionScore()` is 6, a CONSTANT. The inner walk that picks which
overload of a method GROUP to use still adds one ladder value per delegate parameter plus one for the
return — right there, because every survivor matched the same expected signature — but that sum may
not reach the enclosing candidate's score: `Enumerable.Select` declares a one-parameter and a
two-parameter selector, and the longer signature used to win purely for having one more position to
add up. C# does not rank a method-group conversion at all; it ranks the delegate PARAMETER TYPES.

**NL414** (`ErrorCode.AmbiguousCall`) is reported by `AnalyzerReflectionCallReporter.ReportAmbiguousCall`
and `AnalyzerSyntheticCallReporter.ReportAmbiguousCall`, both rendering
`AnalyzerOverloadSpecificity.AmbiguousCallSummary/Explanation/Hint`. The reflected arm dedupes through
the analyzer-lifetime `AnalyzerCallableReferenceReportLog` (key prefix `NL414 `), because a method
group is pre-bound several times for one written occurrence. A SURROGATE method group is exempt: its
candidates are read off an instantiation closed over `object`, so two of them looking alike is the
surrogate failing to represent the call. Both arms still BIND the first maximal candidate, so the
call keeps a type and the IDE keeps its semantic-model row.

MEASURED, tip against `census/merge` 17d626dca, over the converted census at
`/Users/spencer/repos/nsharp-cs2nl/out` (`nlc check --json`, five projects): `cli` 22 -> 15 rows
(NL402 8 -> 1: the `compileProjectWithIlBackend(..., out ignored3, ...)` family, fixed by the by-ref
shell below), `tests` 53 -> 29 (NL905 29 -> 5: the 24 `this value` rows an `object?`-returning overload
produced), `languageserver` 36 -> 36, `playground-wasm` 23 -> 23, `runtime` 0 -> 0. No code appears that
did not appear before, and NL414 appears in NONE of them.

The same measurement over the COMPILER'S OWN 819 `.nl` files (`nlc check --json` in
`src/NSharpLang.Compiler.Core`) moves 1588 rows -> 1313: NL402 195 -> 3, NL905 540 -> 469, NL202 406 ->
394, every other code identical, and again no NL414. The NL402 collapse is the `ref`/`out` shell; the
NL905 collapse is the calls that used to bind an `object?`-returning overload.

A source `ref`/`out` position is scored through its BY-REF SHELL:
`AnalyzerSyntheticCallBinder.GetArgumentComparisonTypes` applies
`AnalyzerOverloadFacts.ApplySyntheticParameterModifier` exactly as the validator does. Without it a
`Facts` parameter did not accept the `&Facts` an `out` argument carries, so an overload set containing
an `out` signature reported NL402 for the very call that signature exists for — while the same call to
a LONE declaration bound, because a lone declaration is never scored.
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
- A WRITTEN type argument that is the enclosing METHOD's type parameter takes the same road (census
  2026-09-13, §CONV3). `JsonSerializer.Deserialize<T>(json, options)` inside
  `func Read<T>(json: string, options: JsonSerializerOptions): T?` reported NL402 "No overload of
  'Deserialize' accepts 2 arguments with these types", because `PreBindReflectionMethod` required
  every written type argument to convert to a CLR type and `T` converts to none.
  `IsOpenWrittenTypeArgument` now recognises that shape — the analyzer spells a type parameter in
  scope as a bare `SimpleTypeInfo`, and every BUILT-IN spelled that way converts and never reaches
  it — records the binding in `typeInfoBindings` only, and `CloseGenericRuntimeMethod` leaves the
  method open. A name that resolves to nothing is `UnknownTypeInfo` and is still a non-binding, so
  `Deserialize<Nonsense>(…)` is still a report. This one DOES emit for a generic free function:
  `tests/native/census-conversions/ReflectedParameterTargets` runs four instantiations of it.

### Argument conversions in overload resolution (census 2026-09-13, CONV2/3 and CONV2/4)

Applicability is not decided by the STANDARD conversions alone, and a collection expression written
as an argument has no type of its own until a parameter names one. Both live in
`AnalyzerReflectionArgumentBinder.TryScoreReflectionSuppliedArgument`, asked in this order after the
standard match has declined:

- `TryScoreConstantExpressionArgument` (census 2026-09-13, §CONV3) — the two implicit CONSTANT
  conversions, ECMA-334 §10.2.11 (an in-range `int` constant to a narrower integral) and §10.2.4
  (the literal zero to any enum). Both are implicit conversions, so both belong to APPLICABILITY
  (§12.6.4.2); without this `roots.TryAdd(root, 0)` on a `ConcurrentDictionary<string, byte>`,
  `map.Add("a", 0)` on a `Dictionary<string, byte>` and `stream.WriteByte(0)` all reported NL402.
  The constant is measured against the parameter type with the candidate's BINDINGS APPLIED, so a
  `TValue` the receiver fixed to `byte` is a real target and one still open is refused (a constant
  drives no method type inference). `ConstantExpressionConversionScore()` is 6, the implicit-numeric
  rung: `f(int)` still wins for `0` on identity, and `f(byte)` versus `f(long)` ties here and is
  separated by `AnalyzerOverloadSpecificity`'s better-conversion-target rule, which answers `byte`
  exactly as C# does. The FINALISING walk asks the same question again through
  `ReflectionCallFinalizeState.PendingConstant` / `IsAcceptedReflectionArgument`, because a literal
  analysed against a narrower target still answers `int` (so does `b: byte = 0`) and validation
  would otherwise refuse what applicability admitted.
  `ConstantConversionFacts.AcceptsIntegerConstant` is the single owner of the pair, shared with
  `AnalyzerAssignability.IsConstantConvertible`; its target tests compare `FullName` rather than
  `== typeof(byte)`, because a reflected parameter type comes from a MetadataLoadContext and
  reference equality over `Type` was false for the CLR's own `System.Byte`.
- `TryScoreCollectionExpressionArgument` — an array literal is applicable to an SZ-array parameter
  when the literal's PROVISIONAL element type (what the pre-pass inferred with nothing in the
  target-typing slot) is assignable to the parameter's, and the score is that element's: 8 for an
  identical element type, 4 for one that converts. This is what ranks `f(int[])` above `f(object[])`
  for `[1, 2]` and what makes `method.Invoke(null, [args])` bind at all. It is an APPLICABILITY
  answer only: the chosen candidate's finalising walk analyses the same literal again with the
  parameter's real element type in the slot, and that is the conversion. When the provisional element
  type does not convert, `AllElementsAreInRangeConstants` asks the ELEMENTS (census 2026-09-13,
  §CONV3): `[0]` is an `int[]` that is not a `byte[]`, but the element written there is the constant
  `0`, which §10.2.11 converts — which is why the same literal was accepted at
  `one: byte[] = [0]` and refused at `sha.TransformBlock([0], 0, 1, null, 0)`. An EMPTY literal
  answers false (it carries no constant, so the ordinary element relation decides it), and a written
  `[]` at a reflected array parameter remains a NOT-YET.
- `HasUserDefinedArgumentConversion` — an operator declared by the argument's type or the
  parameter's, selected by `ExternalUserDefinedConversions`, the same owner the emitter asks for the
  handle to call. `result.Attribute("outcome")` reaches `XName::op_Implicit(string)` this way. It is
  refused for a BY-REF parameter and for one that still mentions a type parameter (a user-defined
  conversion takes no part in method type inference), and an AMBIGUOUS conversion makes the candidate
  inapplicable rather than picking one. `UserDefinedConversionScore()` is 1 — below the whole
  standard ladder — so an overload reachable without one always wins.

The pre-pass's reports about an untargeted array literal are WITHDRAWN
(`AnalyzerCallAnalysis.WithdrawUntargetedCollectionReports`, on both the group-argument pass and the
reflection pre-pass): `m.Invoke(null, [1, "two"])` is an ordinary `object?[]` and the "all elements in
an array must be the same type" report was about a type the literal never had. The provisional type
is kept, because scoring reads it.

`AnalyzerArrayLiteral.TryGetExpectedElementType` looks through a NULLABLE shell once, so `object?[]?`
— `MethodInfo.Invoke`'s own second parameter — names `object?` as its element type.

NOT YET: a collection expression whose elements have no common type, written against a SOURCE
overload set of the same arity, type-checks and then declines at emission — `ColumnarIlEmitter`'s
static-call arm selects a same-arity candidate before it looks at the argument.

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
EMITTING a generic method declared on a SOURCE type that is called with a lambda (it type-checks; the
emit path declines at `emit.expression.unhandled-kind`).

### Method type inference for a lambda or a method group (census 2026-09-12, §11/§12)

A lambda has no type until the delegate it is passed to is known, and for a generic method that
delegate is part of what the call is inferring. Both sides now run C#'s two phases, and BOTH sides
run them the same way — phase one folds in the receiver and every argument that already has a type,
phase two analyses each lambda whose delegate INPUTS are now fixed and folds its result into the
delegate's RETURN position, repeating while anything moves.

- `AnalyzerReflectionArgumentBinder.FoldLambdaInference` is the check-side phase two. It runs the
  SAME relation that folds a selected method group's signature into the bindings
  (`TryPopulateReflectionBindingsFromMethodGroupDelegate`), so a lambda and a method group are one
  path. It used to take the lambda's return type for "the one type parameter still unbound", which is
  not a position at all: every call whose lambdas fix two type parameters answered with the first
  lambda's type twice (`ToDictionary(n => n, n => n.Length)` typed as `Dictionary<string, string>`).
- `AnalyzerCallAnalysis.EmitSyntheticArgument` is the same phasing for a call to an N#-DECLARED
  generic function: the bindings are re-inferred from every argument analysed so far before the next
  argument's expected type is read. A position that is still open offers NO expected type — the
  surrogate it would otherwise offer is a type the program never wrote — except a DELEGATE, whose
  open position is what the lambda decides. `AnalyzerSyntheticCallFacts.NarrowOpenExpectedArgumentType`
  states that rule.
- `ColumnarContextualExtensionInference.nl` is the EMIT-side engine, and it replaced a per-member
  table in `ColumnarIlEmitter` that named `Where`, `Select`, `ToArray`, `ToList`, `Min`, `Max` and
  `Contains` and nothing else. Candidates come from the referenced-assembly extension index for an
  extension call and from the owner's own metadata for a static or instance call; the only difference
  between the three shapes is the binding's `ParameterOffset`. The receiver slot WIDENS through
  interfaces and the base chain (`List<string>` satisfies `IEnumerable<TSource>`) and argument slots
  read the actual type through its implementations too (`char[]` is an `IEnumerable<char>`, which is
  what `SelectMany` needs).
- Two tie-breaks, both C#'s: a candidate that would throw a lambda's result away loses to one that
  keeps it (`Task.Run(Action)` against `Task.Run<TResult>(Func<TResult>)`, scored on the check side by
  `TryScoreReflectionSuppliedArgument`), and between two candidates that close to the SAME signature
  the less generic one wins (`Max<TSource>` against `Max<TSource, TResult>`).
- A CONSTRUCTED GENERIC DELEGATE takes its nullability from its TYPE ARGUMENTS wherever the
  definition spelled a bare type parameter (`AnalyzerFunctionTypeFactory.OpenDelegateInvokeParameters`
  / `OpenDelegateInvokeReturnType`, and the same rule in the binder's
  `CreateDelegateSignatureFromOpenType`). Reading the closed `Invoke` through the nullability tables
  answered `string?` for `Predicate<string>`, so a source `func IsLong(value: string)` did not match
  the delegate it obviously implements (NL402) and a lambda written there was told its parameter was
  maybe-null (NL905). `Func` and `Action` never had the problem because they read their type
  arguments directly; the two readings must agree.
- TWO BOUNDS FOR ONE TYPE PARAMETER THAT DIFFER ONLY BY THE NULLABLE LIFT FIX IT TO THE LIFTED ONE
  (census wave 7, LAMBDA3 item 3). `X` converts to `X?` and `X?` does not convert back, so C# fixes
  the parameter to `X?`; the walks recorded the FIRST bound and then refused the second, which is why
  `Assert.Equal(expected, lspDiagnostic.Severity)` over a reflected `Equal<T>(T, T)` reported NL402
  at seven converted sites. The relation is one fact stated on each side of the boundary —
  `AnalyzerConversionFacts.IsNullableLiftOf` (CLR bounds) and `IsNullableLiftOfTypeInfo` (N# bounds),
  applied by `AnalyzerOverloadScoring.TryMatchReflectionParameter` and the binder's
  `RecordTypeInfoBinding`; `ColumnarTypeEquivalenceFacts.IsNullableLiftOf`, applied by
  `ColumnarRuntimeGenericMethodResolver.Unify` and `ColumnarContextualExtensionInference.TryUnifySlot`.
  Both analyzer maps widen together, so the type the analyzer reports is the instantiation the
  backend closes. NO OTHER widening is admitted here: a later bound that merely converts to the
  earlier one is still absorbed, and a reference-widening pair (`Derived`/`Base`) still declines, so
  the two maps cannot drift apart.
- A BLOCK-BODIED LAMBDA'S RETURN TYPE IS THE BEST COMMON TYPE OF ITS `return` EXPRESSIONS WHEN THE
  TARGET'S RETURN POSITION IS NOT DECIDED (census wave 9, LAMBDA4 item 1). C# §12.6.3.13's inferred
  return type. A block body used to take the SIGNATURE's return type whatever the block did, so
  `names.Select(name => { …; return new Range(…) })` had its returns CHECKED against an unbound
  `TResult` (NL202 "should return TResult but returns Range") and contributed nothing to the
  inference that would have bound it — a second NL202 then reported the call as `List<TResult>`. Four
  owners state the one rule: `AnalyzerLambdaAnalysis.DecidedReturnTarget` answers `unknown` for a
  bare unbound reflected type parameter, `AnalyzerSyntheticCallBinder.NarrowOpenDelegateReturnPosition`
  does the same for a SOURCE generic's open return position (the parameter half survives, which is
  what types the lambda's parameters), `AnalyzerAmbientContext.EnterNestedBody` collects instead of
  checking when the boundary's return type is `unknown` and joins with
  `JoinInferredReturnType`, and `AnalyzerLambdaAnalysis.CompleteBlockBody` takes the join. The join is
  the match expression's: assignable either way wins outright, otherwise
  `AnalyzerMatchExpression.FindCommonBaseType`, otherwise `unknown` and STICKY. The emit side is
  `ColumnarIlEmitter.TryPreflightBlockBodyReturnType`, which reads the same returns; it joins only
  through the SOURCE base chain, so a body whose arms meet at a shared interface analyses and then
  declines.
- A GENERIC DELEGATE CLOSED OVER A SOURCE TYPE READS ITS SHAPE FROM THE DEFINITION'S `Invoke`
  (census wave 9, LAMBDA4 item 2). `Action<PriceArgs>` for a source class has no CLR instantiation to
  reflect while `PriceArgs` is a builder, so `AnalyzerLambdaAnalysis.FunctionSignature` read the
  signature off nothing and reported NL203 about every parameter of a handler lambda.
  `UnreflectableGenericDelegateSignature` reads the definition's `Invoke` and substitutes this
  instantiation's arguments into the positions it spells as bare type parameters. `Func` escaped only
  because the PARSER spells `Func<…>` as a `FunctionTypeReference`, which made the gap read as an
  `Action` problem when `Predicate<T>`, `Comparison<T>`, `Converter<T, R>`, `EventHandler<T>` and a
  referenced assembly's own all failed the same way. The emitter's half is
  `ColumnarIlEmitter.TryGetDelegateDefinitionInvokeSignature`, reached from
  `TryGetSupportedDelegateSignature` whenever the instantiation is builder-bound.
- AN `async` LAMBDA'S TYPE IS THE TARGET'S TASK FAMILY OVER ITS BODY'S RESULT, AND THE TARGET IS
  SPELLED EITHER WAY (census wave 9, LAMBDA4). `AnalyzerLambdaAnalysis.AsyncWrappedReturnType` read
  only a `ReflectionTypeInfo`, but `AnalyzerReflectionTypeConversion` spells a constructed generic as
  a `GenericTypeInfo` over the reflected DEFINITION — so `Task<TResult>` answered nothing and the
  lambda kept the target's own unbound return. `Task.Run(async () => { return 11 })` and
  `Task.Run(async () => await Task.FromResult(11))` both reported `Task<TResult>` where `Task<int>`
  was expected. `AsyncTaskFamilyDefinition` answers for both spellings.
- `unknown` contributes NO binding (`PopulateReflectionBindingsFromTypeInfo` returns immediately).
  It is the analyzer's answer for an expression it could not type, and recording it closed the method
  over a type the program never wrote.
- A LAMBDA'S RESULT IS READ THROUGH ITS CLR SHAPE WHEN THE N# SPELLING CANNOT ANSWER (census wave 7,
  LAMBDA3 item 2). `PopulateReflectionBindingsFromTypeInfo` descended only into a `GenericTypeInfo`'s
  own type arguments, and only when its NAME matched the parameter's definition. A member read off a
  REFLECTED type carries a `ReflectionTypeInfo` wrapping the CLR type whole, so
  `safeActions.SelectMany(f => f.Edits)` over a reflected `List<TextEdit>` member fixed nothing for
  `TResult` (NL402 at nine converted sites) while the identical member declared in source fixed it.
  The walk now falls through to `AnalyzerOverloadFacts.TryMatchReflectionParameter` over the source
  type's CLR form, on a TRIAL copy of the bindings merged only on success — the same reading every
  non-lambda argument already gets, which is what traces `List<T>` to `IEnumerable<T>` through its
  interface list.
- AN OVERLOADED METHOD GROUP AT A POSITION WHOSE OUTPUT TYPE PARAMETER IS STILL OPEN IS A PHASE-TWO
  ARGUMENT, NOT A PHASE-ONE ONE (census wave 7, LAMBDA3 item 4). A name with several overloads
  carries no single signature, and `ColumnarIlEmitter.TryRunContextualInference` marked the position
  SETTLED anyway, so the delegate's return position stayed open and the whole call declined
  (`emit.call.instance-member-unmodeled`): one `Widen` emitted and two declined. Phase one now leaves
  such a position for phase two, and phase two's new first arm is C#'s output type inference FROM a
  method group (§12.6.3.6) — `TryGetMethodGroupSignatureForInputs` filters the candidates by the
  now-fixed INPUT types alone (`ParameterTypesMatchDelegate`, the return-free half of
  `SignatureMatchesDelegate`) and folds the unique survivor's return type in. Two survivors and none
  both decline. STILL OPEN: a group with two ARITIES (`Of(int)` and `Of(int, int)`) makes BOTH
  `Enumerable.Select` overloads close, so the emitter declines where C# reports CS0121 — the analyzer
  silently picks one, so the two disagree and the user sees NL103 rather than an ambiguity
  diagnostic.
- OPEN, HIGH (census wave 7, LAMBDA3 item 5 — diagnosed, not fixed): OVERLOAD RESOLUTION HAS NO
  SPECIFICITY TIE-BREAK, so a NON-GENERIC `IEnumerable` overload wins over the generic
  `IEnumerable<T>` one and the call silently answers `object?`. `Assert.Single(x.EnumerateArray())`
  binds `Single(IEnumerable): object?` instead of `Single<T>(IEnumerable<T>): T`, which is why 24 of
  the 29 remaining NL905 "`this value` is maybe-null" sites in the converted test corpus are there —
  not the xunit metapackage cascade (TESTREFS) and not a generic-return annotation. Both candidates
  score 4 on the reflection ladder (`GetReflectionMatchScore` answers "assignable" for each), and
  `AnalyzerCallAnalysis.PrecedesReflectionCandidate` then breaks the tie on `UsesParams` and
  `DefaultsUsed` only, so declaration order decides. C# §12.6.4.3 decides it by BETTER CONVERSION:
  `IEnumerable<JsonElement>` converts to `IEnumerable` and not back, so the generic candidate is
  better. `Assert.Single<int>(values)` and the two-argument predicate form (generic only) both bind
  correctly today, which is how the diagnosis was confirmed. The fix belongs in
  `PrecedesReflectionCandidate` as a per-argument pairwise comparison of the two candidates' CLOSED
  parameter types, and it changes the answer of every reflected call, so it wants its own stream and
  its own estate sweep.
- A TYPE CLOSED OVER A TYPE THE COMPILATION IS WRITING cannot be asked about itself, and three
  separate readings had to learn that. `List<Query>` for a source class `Query` is a
  `TypeBuilderInstantiation` whose `GetInterfaces` throws; `Query[]` is an array over a `TypeBuilder`
  whose interface list is equally unreadable; and `Enumerable.First<Query>` is a
  `MethodBuilderInstantiation` whose `GetParameters` reports the DEFINITION's `TSource`.
  `ColumnarContextualExtensionInference.FindClosedImplementation` therefore falls back to the
  receiver's own DEFINITION with its type arguments substituted, and to the CLR's own vector contract
  for an array (the generic interfaces `typeof(object[])` implements, closed over the element — read
  off the CLR, not written down). `TryClose` SUBSTITUTES the closed signature from the declaration
  rather than reading it back, exactly as `ColumnarRuntimeGenericMethodResolver` already does. Before
  this, `items.First()` emitted for `List<string>` and declined for `List<Query>`.
- `ColumnarExtensionMethodResolver.ReferenceAssignableFrom` asks that same owner what closed shapes a
  receiver HAS instead of `IsAssignableFrom`, which throws on exactly those receivers. One notion of
  "what interface does this receiver have", not two.
- EXPLICIT TYPE ARGUMENTS on an extension call are `ColumnarExtensionMethodResolver.CollectExplicit`
  plus `ResolveExplicit` / `ResolveExplicitUnique`, reached from
  `ColumnarIlEmitter.TryEmitExplicitGenericExtensionCall`. They replaced a two-member table that named
  `Cast` and `OfType` and hard-coded `IEnumerable` as their receiver slot. C#'s rule (ECMA-334
  §12.6.4.1) is that written type arguments SKIP inference: a candidate whose own arity differs is
  excluded rather than an error. A VALUE-type receiver slot is now indexed
  (`IsSupportedReceiverParameter` excludes only by-ref, pointer and BARE type-parameter slots), which
  is what `JsonSerializer.Deserialize<TValue>(this JsonElement, ...)` needs; the receiver is pushed by
  VALUE there, and boxed when the declared slot is a reference type.
- A CONSTRUCTOR ARGUMENT WITH NO TYPE OF ITS OWN is `ColumnarIlEmitter.TryEmitContextualConstruction`:
  the constructor is selected first (by the written arity, and among same-arity overloads by whether
  each written argument CAN match the declared parameter), then each argument is emitted against its
  declared parameter type, which is what gives a lambda its shape. Every tier below types its
  arguments before it selects, so `new Lazy<int>(() => 1)` reached no owner at all. The columnar
  PARSER reaches it because the lambda level now runs in every argument position — a call argument, a
  constructor argument, an indexer argument, an object-, anonymous-object- or `with`-initializer
  value, and an array or tuple literal element.

### Member lookup in CALLEE position

`AnalyzerMemberResolution.ResolveMember` carries C#'s must-be-invocable-if-member rule as a fifth
parameter. In callee position a VALUE member only answers when a value of its type can be CALLED
(`AnalyzerCallableReferenceFacts.IsInvocableMemberType`: a method group, a `FunctionTypeInfo`, a
`Func`/`Action` however spelled, or a metadata delegate); otherwise the arms below it — the method
group, then the extension surface — answer instead. That is the whole reason
`values.Count(predicate)` is a legal program: `List<T>.Count` is an `int` PROPERTY and
`Enumerable.Count<TSource>` is an extension.

The POSITION is the exact callee NODE, carried on `AmbientCallCalleeFrame.CallCalleeNode`, because
the frame's `AnalyzingCallCallee` flag covers the whole callee SUBTREE while the rule applies to the
outermost link alone (`a.b.Count(x)` must not lose the property `b`). A member that resolves as a
value and cannot be called is NL413 — reported by `AnalyzerMemberAccess.ReportMemberNotCallableIfNeeded`,
which re-resolves the same name as a VALUE and stays silent when that answers nothing, so the
undefined-member report is still the one an unknown name gets.

A CONSTRUCTOR argument is an argument: `AnalyzerConstruction.DelegateConstructorParameterType` reads
the delegate a position wants from the constructors themselves (external ones through CLR metadata,
declared ones through their written parameter types) and only when every arity-compatible
constructor agrees on one. Without it `new Lazy<Type>(makeType)` reported NL411.

### Generic methods declared by EXTERNAL types

The analyzer side of a reflected generic call has always accepted a written type-argument list:
`AnalyzerReflectionArgumentBinder` requires the candidate to be a generic method DEFINITION whose own
arity equals the written count, converts each written argument with `TryConvertWrittenTypeArgument`
(an N#-only type contributes `object` as its CLR binding surrogate), and seeds the candidate's
bindings with it before the arguments are bound. A count that matches nothing simply drops the
candidate.

What that left was a REPORT, not a binding: a dropped candidate reached
`AnalyzerReflectionCallReporter.ReportUnboundCall`, which recited the ARGUMENT types (NL402) for a
mistake that is about the TYPE-argument list. `TryReportWrittenTypeArgumentArity` now answers first
and reports NL207 in the exact words `ValidateWrittenTypeArgumentCount` uses for a source
declaration. It is deliberately silent whenever the list is not the whole story — a candidate of the
written arity exists, or the name declares several arities and none is the written one — so those
still get the ordinary overload report, which lists every signature.

The EMIT side is where the gap actually was, and it is `ColumnarExplicitRuntimeGenericMethodResolver`
(in `ColumnarRuntimeGenericMethodResolver.nl`), the explicit twin of the inference tier beside it:

- Candidate admission is SHARED — `IsInferableCandidateShape` is the half of the inference tier's
  rule that does not depend on the arguments — so the two tiers cannot disagree about which
  declarations are reachable. The explicit tier adds only the arity rule.
- `MakeGenericMethod` is what enforces the declared constraints; a candidate it refuses is dropped,
  which is how a constraint violation becomes a "no such call" answer rather than an exception at
  emit.
- The closed signature is SUBSTITUTED rather than read back, for the reason the inference tier states:
  a `MethodBuilderInstantiation` reports the DEFINITION's own parameters.
- A trailing optional whose metadata default is the null reference is filled (the ordinary resolver's
  `CanFillOptional`), so `JsonSerializer.Deserialize<T>(json)` binds without `options`.
- Two entry points: `ResolveWithFacts` scores the candidates with the shared argument-flow scorer when
  the site's arguments all type ahead of emission; `Resolve` requires a UNIQUE candidate at the arity,
  which is the only honest answer for a site carrying a lambda or an `out`.

`ColumnarIlEmitter.TryEmitExplicitGenericExternalCall` is the call site. It reads the parser's kind-38
callee exactly as `TryEmitExplicitGenericSourceCall` does — the node keeps only the dotted NAME, so a
lexical value binding in front of the member is an INSTANCE receiver and anything else that resolves
to a type is a STATIC owner — and emits each argument against the SUBSTITUTED parameter type, which
is what gives a lambda argument its contextual shape and sends an `out` argument through the by-ref
path.

Two neighbours moved with it, because the same "the planner cannot type these arguments" problem
produced them:

- `ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity` is the non-generic counterpart
  (`u.Switch(a => ..., b => ...)`, `items.ForEach(...)`, `Comparer<int>.Create(...)`). The emitter's
  arm runs ahead of its per-receiver residual table and preflights every argument with
  `CanDeclaredCallArgumentMatch` before emitting the first one, so a selection it cannot complete
  leaves the stack untouched.
- `TryGetSupportedDelegateSignature` read a delegate's signature from its NAME — an Action/Func table
  — so `Predicate<T>`, `Comparison<T>` and every user-written delegate had no lambda form. Any other
  delegate now reads its signature from its own `Invoke`.

A METHOD ON A CONSTRUCTED EXTERNAL GENERIC CLOSED OVER A SOURCE TYPE now resolves through the
SURROGATE binding type (`AnalyzerMemberResolution.TryResolveReflectionMethodGroup`). The objection
recorded beside the property/field arm — reading `Comparer<Item>.Default` off `Comparer<object>` would
answer `Comparer<object?>` — is about the ANSWER's type, and a method group is not an answer: it is a
set of candidates the reflected binder then closes, and that binder already rebuilds every signature
position from the SPELLED receiver via `TryPopulateReceiverGenericTypeBindings`. Without this arm the
callee typed as `unknown` and the call was not checked at ALL — no arity, no argument conversions, and
(the census site) no `[MaybeNullWhen(false)]`, so `if map.TryGetValue(k, out v)` left `v` maybe-null in
the branch where the BCL guarantees it is present.

NOT YET: a written type-argument list directly on a call's RESULT (`Make().As<int>()`). The parser's
kind-38 node keeps only the callee's TEXT, so the receiver subtree is gone by the time the emitter
sees it and `Make().Is` is not a name anything can resolve; bind the receiver first. An ORDINARY
member off a call result does read — `ColumnarIlEmitter`'s member-access arm asks
`ColumnarRuntimeInstanceMemberResolver` and spills a value receiver for its address, where it used to
consult a per-receiver residual table (`Make().IsOk` read and `Make().Index` did not).

## Type Checking

### Binary operator typing (census 2026-09-13, CONV2/1 and CONV2/2)

`AnalyzerOperatorExpressions` decides what an operator is WORTH, and two of its rules are about what
the operands are walked under rather than about the operands themselves:

- NEITHER OPERAND OF A SHIFT TAKES THE SURROUNDING TARGET. C# fixes both operand types of every shift
  operator (§12.11), so the target-typing slot is replaced for both steps and restored in `Supply` —
  `null` for the value operand, `int` for the count. Leaving the slot in place typed the `63` in
  `okWords[i >> 6] | (1UL << (i & 63))` as a `ulong` and reported NL202 about a mask idiom that is
  correct in every language with shifts. The result is the UNARY promotion of the left operand alone.
- AN INTEGER CONSTANT ADOPTS THE OTHER OPERAND'S TYPE (ECMA-334 §10.2.11). `ConstantPromotedType` is
  asked only after `WiderType` has declined, so it can never change an answer the promotion table
  already had, and it reads the operand EXPRESSION (`ConstantOperandFacts.FromExpression` plus
  `NumericLiteralFacts`' magnitude tables) because being constant is a property of what was written.
  Arithmetic, bitwise, relational and equality all inherit it, on either side. A suffixed literal
  adopts nothing and a negative one adopts only a signed target.
- The pair that is still refused — `ulong` against a signed integral with a NON-constant operand —
  has its own report (`TryReportNoUnsignedCommonType`) naming the rule and the cast, rather than the
  generic "these two don't work".

The backend mirror is `ColumnarPrimitiveBinaryPlanner`: `TryAppendAdoptedIntegerLiteral` consults
`ConstantConversionFacts` (which is why a hexadecimal constant adopts where the old decimal-digit
scan refused it), `TryReplanWithAdoptedLeftLiteral` replans the pair when the constant is written
FIRST, and `TryAppendShift` covers `uint` as well as int/long/ulong.

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

### Init and required construction

`AnalyzerConstruction` records the exact selected source declaration or reflected constructor in
its construction state. Required-member analysis consumes that identity directly when it checks
`[SetsRequiredMembers]`; it does not rescan constructors by arity. This matters when same-arity
overloads differ by reference or numeric specificity, named placement, defaults, `params`, or
`ref`/`out`: only the constructor ordinary overload resolution selected may exempt the creation.
An unknown argument suppresses the exemption and does not add a secondary ambiguity diagnostic.

An `init` setter is identified in CLR metadata by `modreq(IsExternalInit)` on its return position.
Reflection.Emit drops custom modifiers when it creates a `MemberRef` for a method on a constructed
type, so `ColumnarModifiedMemberReferenceRepair` handles affected constructed-generic calls at the
`PersistedAssemblyBuilder.GenerateMetadata` boundary. The first pass records exact owners and
setter signatures and discovers the emitted MemberRef rows. A conditional second emission appends
corrected rows, preserves modifier order and placement while retaining the emitted VAR/MVAR
shape, and structurally remaps only InlineMethod operands. Before publishing the image it compares
the original ordered AssemblyRef, TypeDef, TypeRef, TypeSpec, MethodDef, and MemberRef identities
against discovery and verifies each appended repaired row. Assemblies with no affected setter stay
on the ordinary single-pass path.
For `Box<U>` inside a generic function or local function, the owner TypeSpec contains method
parameter `!!0`, while the setter signature still uses its declaring type's `!0`. The repair request
therefore records the constructed setter and substituted property type, retaining the open setter
only as the modifier source. Unbaked generic parameters use their authoritative type/method kind;
a missing `DeclaringMethod` does not turn an MVAR into a VAR.

The repair ledger is shared by every plan emitted into the assembly. Iterator realization passes
that same ledger through synchronous `MoveNext`, asynchronous `MoveNextCore`, and generator lambda
bodies, so a constructed-generic initializer used by a direct `yield`, a synchronous callback, or
an async callback contributes its exact setter request to the assembly repair. The direct-call root
used by ordinary async bodies preserves the ledger as well; wrapping such an initializer in a call
does not detach its MemberRef from the two-pass repair.

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

### Field initializers — NL328 and NL329

`AnalyzerFieldInitializerRules` owns the two questions a field initializer answers to, and both run
from `AnalyzerTypeDeclarations.AdvanceFieldEntry` before the initializer is walked, so the report
lands whether the field's type is written or inferred.

- **NL328 — the initializer cannot reach the instance.** An instance field initializer is emitted
  inline at the start of every constructor that reaches the base constructor, *ahead of the base
  constructor call* (`ColumnarIlEmitter`, and `ColumnarFieldInitPlanner` for the placement). The
  object does not exist there, so the rule is C#'s (CS0027/CS0236): `this`, `base`, and any bare
  instance field, method or property of the declaring type are refused. The member set comes from
  the enclosing `ClassTypeInfo.DeclaredMembers` (`IsStatic == false`); lambda parameters written
  anywhere in the initializer are collected first and shadow a member of the same name. Static field
  initializers are exempt — they run in the type initializer, where there is no instance at all.
- **NL329 — a struct field initializer needs a constructor to run in.** A value type's `default`
  reaches no constructor, so the initializers run for the values built through one and the CLR zero
  stands for the rest; a struct that declares NO constructor (primary or written) would never run
  them at all, and that is what the rule refuses. The check reads the enclosing scope's
  `StructTypeInfo` (or `RecordTypeInfo.IsStruct`) plus its `PrimaryConstructorParameters` and its
  `DeclaredMemberKind.Constructor` members. A struct's *static* field initializers are unaffected.

Static field initializers themselves are not an analyzer rule: the parser reads them into a
synthesized `<StaticInitialize>$` body (`BuildColumnarStaticInitializerBodyCore`) and the emitter
emits that body into the type initializer, so an initializer is type-checked as the assignment it
is — the same NL202 an assignment in a static method would get.

### Definite Assignment
For non-nullable **reference-typed** fields:
- Must be assigned in the constructor
- Analyzer tracks which fields are assigned
- Reports NL304 on the `constructor` keyword if such a field is not initialized

A VALUE-typed field owes the constructor nothing (C#'s CS8618 rule): every value type's `default` is
a valid value of it and the CLR has already written it, so a `bool`, an `int`, an enum, a struct, an
`int?` and an unconstrained `T` field are all definitely assigned at construction. The decision is
`AnalyzerConversionFacts.IsDefinitelyReferenceType` — a POSITIVE test that follows a constructed
generic to its definition and answers false for a bare type parameter, an unknown, and anything it
cannot place, so a report is only ever made on a type the analyzer is sure about.
`ColumnarConstructorDeclarationPlanner.IsValidReferenceCtorBody` is the emitter's mirror of the same
rule and reads the field builder's CLR type.

### Statement termination — the one judgement, two questions

`AnalyzerStatementTermination` is the analyzer's only control-flow-termination judgement, and it has
two entry points over ONE walk (`Walk(statement, breakLeaves, continueLeaves)`):

- `AlwaysReturns` — "does every path end in a `return` or a `throw`". The missing-return rule
  (`NL305`) and the unreachable-code rule ask it. Both jumps are off, because a `break` out of a loop
  is not a way out of the function.
- `AlwaysLeaves` — "does every path leave the block that contains this statement". Only the
  guard-clause rule (`AnalyzerLoopSequence.AdvanceIfGuardClause`) asks it, so that
  `if x == null { break }` and `if x == null { continue }` narrow what follows exactly as
  `return`/`throw` do. Both jumps are on.

`break` and `continue` travel as separate flags because they bind to different constructs: descending
into a `switch` stops counting `break` (it leaves the switch, not the branch) and keeps counting
`continue` (it still leaves the enclosing loop); a `finally` block counts neither, since a jump out of
one is not legal IL. A loop body is never descended into, so a `break` written inside a nested loop
escapes nothing.

`try` follows C#'s end-point rule (§13.2): the statement leaves when the `finally` block leaves by
itself, or when the guarded block AND every handler leave. A zero-catch `try { return x } finally { ... }`
therefore leaves — which is what every C# `using` that returns lowers to.

An ENDLESS LOOP leaves for the same end-point reason: a `while` whose condition is the constant
`true`, or a `for` with no condition, cannot be fallen out of unless a reachable `break` targets it,
so `while true { … return … }` needs no return after it. The constant is read only through the
literal, a parenthesis and a `!`; nothing is evaluated. The `break` search descends through blocks,
`if`s, locks, `using`s and a `try`'s guarded block and handlers, and stops at a nested loop, a
`switch` and a `finally`, because a `break` in any of those binds elsewhere. A `for <name> in
<collection>` is NOT endless: the parser wraps it in a `ForStatement` with all three clauses null and
the `ForeachStatement` as its body, so the body's shape is what tells the two apart.

`ColumnarMethodBodyPlanner.AlwaysReturns` is the node-table mirror of the same rule and must be kept
verbatim-identical to it; it takes the SOURCE TEXT as a parameter because a literal's value is a span
into the source rather than a value. `ColumnarIlEmitter` skips the `brfalse end` for a constant-true
condition in both the `while` and `for` arms — emitting it would make `end:` reachable in a loop
nothing can fall out of, and a value function would then fall off its own end.

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
| an `override` that NARROWS the accessibility of the slot it takes | `NL311` | `AnalyzerTypeDeclarations.nl` |

**`on` / `off` DECIDE WHAT AN EVENT NAME MEANS.** Inside the declaring type a source event's name
reads as the backing DELEGATE — that is what makes `Changed?.Invoke(...)` and `Changed == null`
ordinary reads there — but an `on`/`off` TARGET always reads it as the EVENT. The slot is
`AnalyzerAmbientContext.AllowEventReference`, which `Analyzer.DriveOnSubscription` already opened
around the target expression for `AnalyzerExpressionTail`'s "event used as a value" guard;
`AnalyzerMemberResolution.AllowsEventReference` reads the same slot, so the two cannot disagree. An
owner with no ambient behind it (every planner unit test) gets the ordinary reading. Emission
follows: `ParseEventTargetNode` collapses `this.Member` to the bare member read, so
`ParseOnSubscriptionNode` accepts an IDENTIFIER root (it refused one, declining the whole
declaration at `parse.struct`), and `ColumnarIlEmitter`'s `on` arm treats a bare name as the
enclosing type's event — `this` as the receiver for an instance event, no receiver for a static one.

**A DERIVED INTERFACE REACHES ITS BASE INTERFACES' MEMBERS.** `AnalyzerSourceMemberShape` carries a
`BaseInterfaces` array beside its single `BaseType`, because a class has ONE base and an interface has
MANY; `AnalyzerDeclarationContext.ResolveBaseInterfaces` fills it for an `InterfaceTypeInfo` (resolving
each `TypeReference` against the file that WROTE the derived declaration, with the receiver's
substitution applied, and dropping a reference that does not resolve so an unresolved base clause stays
one diagnostic). Three walks fan out over it: `AnalyzerMemberResolution.ResolveMember` (the NL303
owner), `AnalyzerDeclarationContext.TryFindMemberCore` (go-to-definition) and
`CollectAvailableSourceMemberNames` (completions). Depth-first in written order, first declaration
wins — the same rule the single-inheritance chain beside it follows.

EMISSION NEEDS THE RECEIVER SPELLED AS THE DECLARING INTERFACE. Both interfaces are unbaked
`TypeBuilder`s, over which `Type.IsAssignableFrom` and `Type.GetInterfaces` throw
`NotSupportedException` (measured), so the sealed code plan cannot check the edge the source declared
and refused the call with "reference receiver for 'Name' does not match its declaring type". The
planners state the widening instead: `ColumnarDirectCallPlanner.AppendInterfaceReceiverWidening` for a
`func` slot and `ColumnarInstanceMemberPlanner.AppendInterfaceReceiverWidening` for a value member both
append a `castclass` to the declaring interface — the same answer `AppendArgumentConversion` already
gives for an ARGUMENT flowing into a source interface. A CONSTRUCTED source interface receiver
(`IBox<int>`) declines rather than guessing at a substituted base clause.

**WHAT A SLOT IS WORTH DEPENDS ON WHO IS ASKING.** `AnalyzerTypeDeclarations.InheritedAccessibilityLevel`
is the one owner of that relation, and `ReflectionSlotAccessibility` is the only caller that has to
apply it — a SOURCE slot is in this compilation by construction, so the boundary never moves it.
`protected internal` (`FamORAssem`, level 5) is a UNION of a family half and an assembly half; read
from another assembly the assembly half is gone, so what an override inherits is `protected`
(level 4). `private protected` (`FamANDAssem`, level 2) is an INTERSECTION, so the same boundary
erases it entirely and the walk answers -1 ("cannot tell") rather than comparing against a level no
type outside the declaring assembly can reach. `InternalsVisibleToGrants` is the one owner of the
friend question and is asked through `IsFriendOfDeclaringAssembly`; with a grant every level reads
back exactly as its metadata says.

This is measured against the runtime, not copied from C#. `Reflection.Emit`-ing an override of
`ExpressionVisitor.VisitExtension` (`protected internal virtual`, System.Linq.Expressions) and
loading it shows `Family` LOADS, `FamORAssem` LOADS, and only `Assembly` and `FamANDAssem` raise
`TypeLoadException: … cannot reduce access.` So `protected override` there is an exact match (Roslyn
accepts only that spelling, via CS0507) and `protected internal override` is an ordinary widening
N# honours, consistent with every other widening the family permits. Before this rule the analyzer
read the raw metadata level and reported `protected override` as a NARROWING — the shape every
converted OmniSharp handler has, 22 sites in one converter census.

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

## What a Source Type Inherits From an External Base (census 2026-09-13, INHERIT)

A `:` clause naming a referenced type states a fact: `class Names: List<string>` IS a
`List<string>`. Four owners read that fact and each of them used to stop at the last SOURCE link of
the base chain.

**The analyzer's surrogate.** `AnalyzerClrTypeConversion.TryConvertTypeInfoToClrTypeForBinding`
answered `object` for every N#-declared type, so a call's receiver contributed no binding for the
declaring type's `T`: `names.Add("a")` reported NL402 "No overload of 'Add' accepts 1 argument with
these types" while printing `Add(string item)` as the overload it could not match. The surrogate is
now the NEAREST CLR type the declaration states the receiver is, found by
`TryConvertDeclaredBaseChainToClrType` walking the DECLARED chain (the derived links have no CLR form
yet) and accepting only the EXACT conversion per link. This is the generalisation the enum arm
already made when it answered `System.Enum` instead of `object`. Member RESOLUTION already walked the
declared base — `AnalyzerMemberResolution.ResolveMember` re-enters itself on `sourceShape.BaseType` —
so nothing there changed.

**The emitter's one base walk.** `ColumnarInheritedExternalBase` is the single owner: given a
`ColumnarStructDef` (or a receiver `Type`) it walks `BaseDef`/`ExactBaseType` to the terminal
external base, substituting each link's type arguments as it descends, and answers nothing for a
chain that ends at the implicit `System.Object`. Five call sites use it and no other walk exists:

| Site | What it answers |
| --- | --- |
| `ColumnarInstanceMemberPlanner.TrySelectSourceDefinition` | a property or field read past the source chain |
| `ColumnarIlEmitter.IndexerLookupType` | which type's `get_Item`/`set_Item` a `[...]` names |
| `ColumnarIlEmitter.TryEmitInstanceCall` | a call with a LAMBDA argument, which the direct-call planner yields |
| `ColumnarIlEmitter.TryEmitExplicitGenericExternalCall` | a call with EXPLICIT type arguments |
| `ColumnarDirectCallPlanner.ResolveExternalRuntimeBase` | the pre-existing bare/`base.` call arms, now delegating |

In every one of them only the LOOKUP type moves: the receiver value on the stack stays the derived
type, and a `callvirt` to the base's member with a derived receiver is the instruction a base-typed
receiver already emits.

**The conversion relation.** `ColumnarReferenceConversionFacts.ExternalBaseImplementsInterface` adds
the interfaces the external base implements to the derived type's own set. Without it a `Names` had
no conversion to `IEnumerable<string>` and `list.AddRange(names)` declined.

**The value-binding question, which is asked one step earlier than all of the above.** A qualified
callee whose ROOT is not a value binding is read as a call on a TYPE of that name. `Count` was not a
value binding, so `Count.ToString()` inside `Names` was owned-rejected as an unresolvable static
owner before the receiver was ever resolved — while `Count`, `this.Count` and `base.Count` all
worked. `ColumnarFragmentBindings.HasCurrentInstanceValue` and the emitter's
`IsCurrentInstanceMemberName` now ask the same inherited-base walk after the source facts.

Only PUBLIC inherited members are reachable: `TrySelectAdmittedProperty` and the ordinary runtime
call resolver both filter to public, and N# does not yet model access to an external base's
`protected` surface. Do not add a base-type allowlist and do not grow a second base walk.

**An external base over an OPEN type parameter (2026-09-25).** `class Mid<U>: List<U>` and
`func FirstOf<U>(xs: List<U>)` name a `List<U>` whose `U` is a bare `SimpleTypeInfo` with no CLR
handle, so neither conversion answered and every member resolved to `unknown` — lenient, so a wrong
return type went unreported and the emitter declined against an empty type. Three pieces fix it:

- `AnalyzerClrTypeConversion.TryConvertOpenInstantiationForBinding` closes such an instantiation with
  `object` in the type-parameter slots (nested ones too). It is a RECEIVER-only door, separate from
  `TryConvertTypeInfoToClrTypeForBinding`, because that one also measures ARGUMENTS and `List<U>` is
  not a `List<object>`. `ResolveMember` tries it after the surrogate, so the existing definition arms
  (`TryResolveConstructedGenericPropertyOrField`, the surrogate method group) answer with the SPELLED
  `U`; `AnalyzerCallAnalysis.ConvertReflectionReceiver` tries it for the call's receiver, and the
  binder reads `T` as `U` off the spelled receiver.
- `AnalyzerClrTypeConversion.TryResolveDeclaredExternalBase` is the TypeInfo twin of
  `TryConvertDeclaredBaseChainToClrType`: the external base as WRITTEN (`List<U>`, `List<string>`),
  substituted through source generic links. `ConvertReflectionReceiver` retargets a source receiver
  to it, so `this.ToArray()` inside `Mid<U>` binds against `List<U>` rather than `object`.
- `AnalyzerCallAnalysis.ImplicitReflectionReceiver` gives a BARE call the enclosing instance as its
  receiver when every candidate is an instance method and the name reads as a member of this type.
  Without it `ToArray()[0]` inside even the CLOSED `class Names: List<string>` typed as the open `T`.

The emitter needed nothing for members used INSIDE the type (`ColumnarDirectCallPlanner`'s bare and
`this.` arms already plan against the open base). Rows: `AnalyzerMemberResolution.tests.nl` (each
with a wrong-type twin) and `tests/native/census-free-function-identity/OpenBaseMembers.tests.nl`.

Still open, in the EMITTER and independent of the above: calling an inherited external member from
OUTSIDE on a constructed source generic — `m.Add("a")` on `m: Mid<string>` — emits an image the CLR
refuses (`BadImageFormatException`), and over a value argument (`Mid<int>`) declines at
`emit.internal-error` "expected 'Type: U', found 'System.Int32'". The member reference is built on the
open `List<U>` instead of being substituted with the receiver's arguments.

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

## `[MethodImpl]` — the pseudo-custom attribute

`System.Runtime.CompilerServices.MethodImplAttribute` is never a custom-attribute row. The CLR keeps
what it says in the method definition row's implementation-flags column, so N# routes it there and
only there, exactly as the C# compiler does. Two owners split the work:

- `MethodImplAttributeFacts.nl` (analyzer side) answers the rules. It recognises the attribute by the
  resolved type's FULL NAME, never by spelling, so a user type that happens to be called
  `MethodImplAttribute` stays an ordinary attribute. It reads `MethodImplOptions` off the attribute's
  own one-argument enum constructor and `MethodCodeType` off its own named-argument field, rather
  than looking either up by name, so the project's reference set decides what the enums are.
- `ColumnarMethodImplAttributes.nl` (emit side) turns the attribute into
  `MethodBuilder.SetImplementationFlags` / `ConstructorBuilder.SetImplementationFlags`, and
  `ColumnarSourceAttributeBinder.TryPlan` REFUSES it so no blob is ever written. That refusal is the
  C# parity: `GetCustomAttributesData()` on an N#-emitted member answers the same nothing.

`ColumnarSourceAttributeInput` therefore carries four things rather than one: the decoded `Arguments`
(string literals only), `ArgumentTexts` (every argument exactly as written, whatever its shape),
`IsStringArgumentList` (whether the string-only blob writer could write it) and `ArgumentSyntax` /
`IsDecodable` (every argument as a constant SHAPE, which is what an ordinary attribute is encoded
from). Before this, an attribute whose arguments were not all string literals was dropped by the
reader without a word.

Three diagnostics state what the attribute cannot do:

| Code | Rule |
|---|---|
| `NL930` | `[MethodImpl]` on a declaration with no implementation-flags column — a type, a field, an enum, an interface, a union. |
| `NL931` | A value with a bit no `MethodImplOptions` member defines (the C# `ERR_InvalidAttributeArgument` rule). |
| `NL932` | A combination the type loader refuses: `Synchronized` on a value type's member, `InternalCall` or `Unmanaged` on a member with a body. |

`NL932`'s value-type half is asked from the STRUCT's own declaration over its members, because the
enclosing type's kind is not in hand when a member is validated on its own; the other two rules are
the member's own and are asked there. Nothing is measured twice.

N# has no attribute position inside accessor braces, so a property's or indexer's attributes are its
ACCESSORS' attributes — `ColumnarProgramInputBuilder` copies the property's `SourceAttributes` onto
both the getter's and the setter's `ColumnarFunctionInput`. That is N#'s spelling of C#'s per-accessor
`[MethodImpl]`. There is also no way to name a constant of enum type at type scope: `const` is a
local-variable keyword, not a field modifier, so the `private const MethodImplOptions HotPathImpl`
shape C# uses in `src/NSharpLang.Runtime/Result.cs` is written out at each member instead.

## Attributes a program declares for itself

An attribute type declared in the program being compiled is an ORDINARY attribute. It used to be
refused outright (`NL323`, "Source-defined attribute 'X' is not supported by IL emission yet"), and
an attribute from a referenced assembly was emitted only when every one of its arguments was a string
literal and the chosen constructor took nothing but strings — so `[Obsolete("gone", true)]` and
`[Obsolete(DiagnosticId = "ID1")]` were dropped from the assembly with no diagnostic at all.

Four owners split the work, and the split is the same one the rest of the emitter uses — a shape
reader, an encoder, a binder, and a phase:

- `ColumnarAttributeArgumentSyntax.nl` reads one argument out of the declaration token table into a
  constant SHAPE: the literals, `typeof`, `nameof`, a dotted member path, array literals, `- ~ !` and
  `| & ^` with C# precedence. It is syntactic on purpose — `-1`'s bytes depend on a width nobody knows
  until the constructor is chosen.
- `ColumnarAttributeBlobWriter.nl` encodes that shape AGAINST THE TYPE IT FILLS (ECMA-335 II.23.3):
  every primitive width, string, `Type` (as a name), an enum at its underlying width, SZARRAY, a
  boxed `object` carrying its natural type in front of the value, and named field/property arguments.
  A value it cannot encode refuses the WHOLE attribute rather than writing a blob the source did not
  say. Two traps are written down there: an `object` fixed argument is `<FieldOrPropType> <value>`
  with NO leading `ELEMENT_TYPE_BOXED` (0x51 is a FieldOrPropType, and writing it makes every reader
  raise `CustomAttributeFormatException`), and a type still being built answers almost no reflection
  question — `TypeBuilder`, and a persisted `EnumBuilder`'s CREATED type, both throw
  `NotSupportedException: This non-CLS method is not implemented.` from `GetField`, `GetProperty`,
  `GetConstructors` and `AssemblyQualifiedName`.
- `ColumnarSourceAttributeBinder.nl` resolves the attribute type through the ordinary canonical
  resolver (both the `Mark` and `MarkAttribute` spellings, written spelling first), collects the
  constructor candidates from the emitter's own `ColumnarStructDef` for a source type and by
  reflection for a metadata one, and selects the signature the arguments encode into — preferring the
  least `object`-typed. Named arguments bind to a settable property or mutable field, walking the
  declaration's base chain and crossing into metadata at the first external base.
- `ColumnarSourceAttributeQueue` (same file) makes attachment a PHASE. A source attribute's
  `ConstructorBuilder` does not exist when the attribute on another declaration is met, so every
  attachment is queued in the order it is met and the queue is flushed once, after every type, method
  and constructor is defined and before the first `CreateType`.

On the analyzer side, `AnalyzerAttributeValidator` measures a source-declared attribute's arguments
against its DECLARATION — constructors, primary parameters, exported settable fields and properties —
and reports the same three sentences the metadata path reports. Where a declared parameter or member
type cannot be named as a CLR type (a source-declared enum, say) the question is DROPPED rather than
answered: a false "no constructor accepts these types" is worse than a missed one.

An integer constant now fills any numeric parameter whose RANGE CONTAINS IT, decided by the value and
not by the type, which is the C# constant-expression conversion and the only way `sbyte`, `byte`,
`short` and `ushort` attribute parameters are writable in a language with no cast expression in an
attribute argument. The constant is carried as a magnitude and a sign, because `ulong`'s top half has
no signed representation and that is exactly where a flags constant lives.

`AnalyzerAttributeUsageFacts.nl` answers `[AttributeUsage(...)]` — read from the declaration for a
source attribute (`AnalyzerDeclarationContext.TryGetDeclaredClassAttributes`), from
`GetCustomAttributesData()` for a metadata one, and inherited from the base in both worlds. Two
diagnostics enforce it:

| Code | Rule |
|---|---|
| `NL933` | The attribute is written on a declaration its `AttributeTargets` exclude. |
| `NL934` | The attribute is written twice on one declaration without `AllowMultiple = true`. |
| `NL935` | The attribute is written at a position N# has none — a target prefix. |

The target is the DECLARATION's, and a property offers both `Property` and `Method` because N# has no
attribute position inside accessor braces. `[MethodImpl]`'s placement is exempt from `NL933`: `NL930`
already says the same thing better, and reporting both would report one mistake twice.

Attachment reaches types, methods and free functions, constructors, properties (the PROPERTY row —
which is where `PropertyInfo.GetCustomAttributes` and every framework that reads it looks), FIELDS and
parameters — a METHOD's, a CONSTRUCTOR's and a PRIMARY CONSTRUCTOR's alike. A field's attributes used to be validated and then dropped, because the struct field scan
in `ColumnarParserKernels.ParseColumnarStructInfoInto` yielded field NAME and TYPE texts with no
declaration token index for `ColumnarSourceAttributes.Read` to scan back from. The scan now records
each field's NAME TOKEN index in a `FieldDeclTokens` column — the same shape `FieldInitTokens` takes —
carried through `ColumnarStructOutputTable` to `ColumnarStructInput.FieldSourceAttributes`, and the
emitter queues them through the same deferred attachment every other position uses. A field
synthesized from a primary-constructor parameter has no member position of its own and records -1.

### An omitted argument, and an argument that converts per element

A custom-attribute blob has no notion of an omitted argument: every fixed argument is written. So an
attribute that leaves an optional parameter off has to write the parameter's DECLARED DEFAULT, which
is what the C# compiler writes for the same declaration. Both halves changed together:

- `AnalyzerAttributeValidator` asks arity as a RANGE — from the constructor's required count to its
  full parameter list — on the source path (`DeclaredMemberInfo.RequiredParameterCount`) and on the
  metadata path (`ParameterInfo.IsOptional`, counted from the end). Only the arguments the source
  WROTE are measured against their parameters.
- `ColumnarSourceAttributeBinder` carries a `DefaultValues` column beside each candidate's parameter
  types and fills the omitted tail from it. A source constructor's defaults come from the declaration
  columns (`ColumnarConstructorDef.DefaultKinds`/`DefaultTexts`, which are TOKEN kinds); a metadata
  one's come from `ParameterInfo.DefaultValue`, turned into the same `ColumnarAttributeArgumentNode`
  shape a written argument reduces to so the one blob writer encodes both. Among applicable
  signatures, fewer omitted arguments wins, then fewer `object` parameters.

An ARRAY argument converts per ELEMENT, not as a whole. `[Bytes([1, 2])]` writes an `int[]` as
written and there is no conversion from `int[]` to `byte[]`, but the blob already writes each element
against the ELEMENT type — so `IsAttributeArgumentCompatibleValue` applies the same
constant-expression conversion one level down, which is as deep as attribute metadata goes.

### A positional constructor parameter is ONE declaration and TWO metadata rows

A primary constructor's parameter declares the constructor's parameter AND the field that parameter
stores into. C# picks between them with a target prefix (`[property: JsonIgnore]`); N# has no prefix
at any position, so the attribute's own `[AttributeUsage]` picks. Three owners changed together:

- `ColumnarParserKernels.ParsePrimaryConstructorParameterSpansCore` SKIPS the `[...]` groups before a
  parameter (`SkipPrimaryConstructorParameterAttributeGroups`). It used to answer -1 at the `[`, which
  the caller reports as `parse.struct` on the type header — so `record Options([JsonIgnore] Summary:
  bool = false)` declined the WHOLE type at emission while the analyzer reported NL933 on it.
- `ColumnarProgramInputBuilder.TryParseColumnarConstructorAt` reads
  `ColumnarSourceAttributes.ReadParameters` into `ctor.Body.ParameterSourceAttributes`, which serves an
  explicit `constructor(...)` and the synthesized primary constructor alike — the primary's
  declaration token is the type keyword, and the reader walks forward to the `(` from whatever token
  it is given. A CONSTRUCTOR's parameter attributes were dropped from the assembly entirely before
  this: `DefineConstructorParameterMetadata*` never asked what the source declared.
- `ColumnarConstructorDeclarationPlanner.PositionalParameterFields` pairs each parameter with the
  field it declares (null for an explicit constructor — a parameter that shares a field's NAME is
  still only a parameter), and `ColumnarSourceAttributeQueue.QueuePositionalParameter` carries the
  pair. The choice is made at FLUSH time, because it needs the attribute type resolved.

`ColumnarSourceAttributeQueue.AdmitsParameter` is the rule: the parameter wins wherever the usage
admits `Parameter`, the field takes it when the usage admits `Field` and not `Parameter`, and an
attribute that admits neither stays on the parameter — the analyzer has already reported it. The
analyzer asks the same question as a COMBINED target
(`AnalyzerAttributeUsageFacts.PositionalParameterDeclarationTargets()` = `Parameter | Field`, the same
shape `PropertyDeclarationTargets()` has), so `NL933` fires only when neither row admits the
attribute, and `DescribeAttributeTargetRepair` gives that case its own sentence.

`ColumnarAttributeUsageTargets` is how the EMITTER learns a usage the analyzer reads from the AST. A
source-declared attribute class is a `TypeBuilder` when the attribute is attached, and a type still
being built answers no reflection question, so its `[AttributeUsage]` is read from
`ColumnarStructDef.DeclaredSourceAttributes` — the attributes its own declaration carried, recorded
beside the `QueueType` call — and its positional argument is reduced by
`ColumnarAttributeBlobWriter.TryEvaluateInteger`, the same evaluator that encodes
`AttributeTargets.Method | AttributeTargets.Class` into the blob. The walk crosses into metadata
(`AnalyzerAttributeUsageFacts.ReadUsage`) at the first base from a referenced assembly.

### Positions N# has no attribute for

`NL935` (`ErrorCode.AttributePositionUnsupported`) is reported by `ColumnarParserRecovery` at the
attribute TARGET PREFIX, and it SKIPs the refused `[...]` so nothing after it cascades:

| Written | Reported |
|---|---|
| an attribute TARGET prefix — `[return: X]`, `[assembly: X]`, `[field: X]` | one `NL935` naming the prefix; `[return: Mark]` used to produce four diagnostics, none of which named the problem |

The prefix is recognised by the COLON after the first token inside `[`, not by the token's kind: a
prefix may be a keyword (`return`) or a plain identifier (`field`), and no legal attribute presents a
colon at that position (a named argument's `name:` is inside the parentheses). The formatter never
rewrites a file that reported a parse error, so a refused attribute is never silently deleted.

### An enum member IS a field, and the emitter's materialization order says so

`[Description("warm")] Red = 1` was `NL935` until 2026-09-14, and the reason was an ORDER: the enum
pass ran first in `ColumnarIlEmitter` and `CreateType`d each enum immediately, while the
source-attribute queue flushes at the END of the declaration walk — and
`FieldBuilder.SetCustomAttribute` on a literal is refused once its declaring type is created.

THE FIX IS NOT A DEFERRAL, IT IS A TYPE-MODEL CHANGE. Deferring `ModuleBuilder.DefineEnum`'s
`CreateType` past the flush makes the assembly unloadable:

    System.BadImageFormatException: A valid typedef or typeref token is expected to follow a
    ELEMENT_TYPE_CLASS or ELEMENT_TYPE_VALUETYPE

This was recorded as a NESTED-enum token-ordering bug in the persisted metadata writer. IT IS NOT.
Measured by execution at `0.1.0+4c3a25f30`, a TOP-LEVEL enum fails the same way and nesting is
irrelevant: the failing shape is `$"{value}"` over an enum — a GENERIC INSTANTIATION
(`DefaultInterpolatedStringHandler.AppendFormatted<T>`) whose signature blob names the enum. What
`DefineEnum` answers is an `EnumBuilder`, a WRAPPER around the real `TypeBuilder`, and
`PersistedAssemblyBuilder` resolves an un-created `EnumBuilder` in a generic instantiation to a bogus
token. Creating it hid the bug because `CreateType()` answers the wrapper's baked form.

So the emitter does the three things `DefineEnum` does, itself:

    module.DefineType(name, visibility | Sealed, typeof(Enum))
    DefineField("value__", typeof(int), Public | SpecialName | RTSpecialName)
    DefineField(member, <the TypeBuilder>, Public | Static | Literal | HasDefault).SetConstant(value)

The enum is then an ordinary `TypeBuilder` from definition to `CreateType`, nothing downstream
notices (every un-baked-builder guard in the back end already reads `is TypeBuilder`), and the type
can stay OPEN for the whole declaration walk. It is created immediately after the first
`sourceAttributeQueue.Flush()`, before the interfaces and the structs. Measured on the whole native
corpus: 92 projects, 3932 tests, none not-green.

With the type open, PASS 0n (right after the resolution catalog exists) queues both positions:
`QueueType(enumBuilder, input.SourceAttributes, …)` and, per member,
`QueueField(literal, input.MemberSourceAttributesAt(m), …)`. A member's attributes answer to
`AttributeTargets.Field` (`AnalyzerAttributeValidator` walks `EnumDeclaration.Members`), because a
member IS a field; `AttributeTargets.Enum` belongs to the declaration above them.

THE ENUM'S OWN ATTRIBUTES WERE ALSO BEING DROPPED, silently, and nobody had noticed: `[Flags]` on an
N# enum emitted NO custom-attribute row at all (`typeof(Color).GetCustomAttributes(false).Length == 0`,
and `(Color.Red | Color.Blue).ToString()` printed `3`). `ColumnarEnumInput` had no `SourceAttributes`
column and the emitter never called `QueueType` for an enum. Both columns are read by
`ColumnarProgramInputBuilder` now, from the member's own name-token index and the `enum` keyword's.

A STRING-BACKED enum is not a CLR enum — it is an `abstract sealed` class of literal string fields and
its `ColumnarEnumDef.EnumType` is `typeof(string)` — but its literal fields take attributes on exactly
the same rows; reflection reaches that class by name, not through `typeof`.

Not supported, and stated as such in `website/docs/basics.md`: `[assembly: ...]`, `[return: ...]`,
and generic attributes.

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

- `src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationContext.tests.nl` for the N#
  declaration catalog, source ownership, visibility, imports, members, and exact runtime
  projections.
- `src/NSharpLang.Compiler.Core/Model/TypeInfoIdentityFacts.tests.nl` for nominal,
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
- `tests/native/census-events` for what `on` / `off` DO at runtime, which is the half the analyzer
  contracts cannot see: subscribe / raise / unsubscribe counts for every receiver shape (a static
  type, a local, a parameter, a bare field, `this.`-qualified, a property chain, an indexed element),
  for all three handler shapes (inline lambda, delegate value, method group), for a handle captured by
  a local function and for `on` written inside a lambda or a local-function body, plus `off`
  idempotence and two subscriptions to one event detaching independently. Before the EVENTS census
  slice every one of those functions declined the WHOLE enclosing declaration at `parse.function` /
  `parse.struct` — the columnar pipeline had no `on` at all — so the file COMPILING is half of each
  contract and the COUNT is the other half.
- `tests/native/census-source-events` for events a SOURCE type declares. `event Name: DelegateType`
  resolves to TWO different things depending on who is asking, and that is the whole rule: inside the
  declaring type the name IS the backing delegate (`AnalyzerDeclarationContext.TryResolveDeclaredEventMember`
  answers the handler type, which is what makes `Changed?.Invoke(this, args)`, `Changed(this, args)`
  and `Changed != null` ordinary expressions there), and everywhere else it is a `SourceEventInfo` —
  a `TypeInfo` with no value at all, so reading it, invoking it, assigning to it and `+=`/`-=` each
  report `NL337` naming the declaring type. `SourceEventFacts.IsInsideDeclaringType` is the single
  owner of the where-am-I question; C#'s rule is kept exactly, so a DERIVED type is outside. `on`
  admits a `SourceEventInfo` in `AnalyzerLambdaAnalysis.ClassifyOnTarget` with the declared handler
  type as the lambda's contextual target, and the value-type arm reports the same sentence a .NET
  instance event on a struct gets. The runtime half — subscribe / raise / detach counts, a static
  event, a struct-declared one, an inherited one, a method-group handler — plus the CLR metadata half
  (`GetEvent`, both accessors, the `[CompilerGenerated]` private backing field, and `EventInfo.AddEventHandler`
  standing in for a C# caller's `+=`) is all in that project. EVENTS3 added the three INHERITANCE
  shapes and the INTERFACE one to it. An event's accessors are methods, so `virtual`/`abstract`/
  `override` mean on an event what they mean on a `func`; what NL311 still refuses is what the CLR
  cannot carry (a `static` event, a value form, `abstract` outside an abstract class, `virtual` inside
  a sealed one, and an `override` with no open base event — measured by `ClassifyOverrideEventTarget`,
  the third member of the walk family `ClassifyOverrideTarget` and `ClassifyOverridePropertyTarget`
  belong to). An `abstract` event has NO storage, so `SourceEventFacts.IsAbstractDeclaredEvent` keeps
  it an EVENT even inside its own declaring type and `Ping?.Invoke(...)` there reports NL337 rather
  than declining at `emit.call.receiver`. NL324 and NL325 both count events now — on the supplied
  side and on the required side, source and reflected — so `class Chatty: INotifyPropertyChanged {}`
  names `PropertyChanged` instead of emitting a type the CLR refuses to load.
- IFACE closed the interface's fourth member shape and two modifier holes beside it
  (`tests/native/census-interfaces`). An interface's VALUE member — `Name: Type`, the bare spelling a
  class body uses — is a GET-ONLY abstract property slot: one `get_Name` accessor and the
  `PropertyInfo` row naming it. The analyzer already modelled it (NL325 has always matched an
  interface's bare value member against a class's field OR property); what declined was the columnar
  parser, which knew `func` and `event` and nothing else. An implementer fills the slot with either
  spelling: a computed property's getter takes Virtual|Final|NewSlot, and a plain FIELD of that name
  gets a synthesized `get_Name` over it, because a CLR field cannot fill a property slot. The
  implementer gets NO second `PropertyInfo` row of that name — its `Name` stays the field its source
  says it is. The slot is get-only on purpose: a read slot is one every implementer can fill, and N#
  has no body-less accessor with which to spell a settable one.
  DUCK MATCHING HAD TO LEARN THE SAME SHAPE: `RequiredDuckInterfaceSatisfied` counted only the
  interface's `Methods`, so an interface declaring no `func` at all matched EVERY type in the program
  and the CLR then refused to load each one; value members and events are slots too, and both are now
  asked for. The fill walk reads the RESOLVED interface set (`ImplementedInterfaces` +
  `ExternalInterfaces`) beside the written base names, because a duck interface is never written in a
  base list. A generic interface closed over a type still being emitted is a `TypeBuilderInstantiation`
  whose every member query throws, so both walks guard with `ContainsBuilderBoundType` —
  `readonly struct Box<T>: IEquatable<Box<T>>` crashed the whole check without it.
  A write THROUGH the interface to a value member is `NL342`
  (`AnalyzerWriteTargets.TryFindInterfaceValueMemberWriteTarget`, beside the read-only-property rule
  it shares a report function with): the slot has no setter, and the reader cannot see why, because in
  a CLASS body the same line is a mutable field. Only a SOURCE interface answers — an external one's
  property carries its own accessors in metadata.
  The two modifier holes: `ReportAbstractMemberFault` replaced a raw `TypeBuilder` throw
  (`Type must be declared abstract if any of its methods are abstract.`, no file/line/column) and a
  SILENTLY DROPPED body on an `abstract` member with one; `ValidateOverrideAccessibility` replaced a
  `TypeLoadException: … cannot reduce access.` at first call. Both are NL311 — see
  `memory/components/error-reporting.md` for the verdict order and the accessibility ladder.
- `AnalyzerMemberResolution`'s event arm carries one more true fact since EVENTS3:
  `ReflectionEventInfo.AnnotatedHandlerType`, read by
  `NullabilityMetadataReflection.ConvertEventHandlerType`. `EventInfo.EventHandlerType` answers a bare
  CLR type and reference nullability is metadata on the MEMBER, so
  `AssemblyLoadContext.Resolving` — declared `event Func<AssemblyLoadContext, AssemblyName,
  Assembly?>?` — reflected as `Func`3[…, Assembly]` and a handler returning `Assembly?` was refused
  with NL318 over exactly the delegate the BCL declares. The reader runs the same
  `NullabilityInfoContext` walk properties, fields and parameters run, and drops the event's own
  maybe-null shell: `event Func<…>?` says the backing field may hold no handler yet, not that the
  handler a subscriber attaches may be null.
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
  `NSharpLang.Compiler.FunctionTypeInfo`; a code NAMED `NullabilityWarning` used to be reported at
  `Error` severity and is now a real WARNING (census FLOW2: both of its shapes describe CORRECT
  programs, and the redundant-`must` half depends on flow state a converter cannot know); `null` assigns to a non-nullable `string` and to a non-nullable class in SILENCE while
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
`scripts/ilverify.sh` — since E1 that script is a reviewed delivery row, so adding the line means
reviewing the change and repinning the row (OWN005) rather than shedding lines — but its
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

**LEXICAL SOURCE TYPES INSIDE GENERIC SIGNATURES** use that same structural selection path. A
declaration such as `Outer.CachedList: List<Cached>` must resolve `Cached` from `Outer`, even though
the current declaration's exact name is `Outer.CachedList` and `Cached` is private. Both
`ColumnarSemanticTypeRegistry` and `ColumnarBindingScopeFacts` rewrite a lexical generic head at its
written arity (`Slot`1`, not the arity-free `Slot`), then recurse through each argument. The selected
structural reference preserves the open generic definition beside the closed runtime handle: a
`TypeBuilderInstantiation` over an unbaked source argument is legal metadata but cannot reliably
answer `IsClass` or `IsInterface`, so `ColumnarBaseTypePlanner` classifies the definition and applies
the closed handle. Fields, properties, events, parameters, returns, locals, base lists, constraints,
arrays, nullable source structs, delegates and nested source generics consequently share one
resolution rule. `tests/native/census-generic-signatures` verifies both emitted metadata and runtime
member use, including `(value: Cached) => ...` as an explicitly typed lambda parameter.

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

**AN ENCLOSING NAMESPACE IS THE FILE'S OWN SCOPE, AND ONE OWNER SAYS SO.** `SimpleNamePrecedence` is
the single ordering both halves of the compiler read:

1. built-ins and lexical scope;
2. the file's own namespace, then each ENCLOSING namespace outward, ending at the global namespace —
   an exported declaration there wins outright, with no diagnostic;
3. the file's explicit namespace imports (exactly one supplying the name wins; two or more is NL209);
4. project-wide auto-discovery of a unique exported project type, which never overrides 2 or 3.

`LexicalNamespaces` is step 2, `CandidateNamespaces` is 2+3, `IsLexicalNamespace` answers "does this
namespace win by nearness rather than by being imported", `EnclosingNamespaceNames` is step 2 alone in
the emitter's `""`-for-global spelling, and `QualifierNamespaces` applies the same chain to the
LEFTMOST segment of a qualified name.

**THE RULE, NOT ONLY THE ORDER (2026-09-24): `SimpleNamePrecedence.Select` / `SelectQualified`.** A
namespace's members are its types WHEREVER THEY WERE COMPILED, so steps 2-3 ask SOURCE and METADATA at
every candidate: the caller drives a `SimpleNameSelection` with one `(declaresSource,
declaresMetadata)` answer per candidate and the owner settles it — the first lexical namespace that
declares the name wins (source before metadata AT ONE namespace, CS0436-style), and the import tier is
ONE tier: two imports supplying it, in any source/metadata mix, is `Ambiguous` (NL209), never "first
import written" — `nlc format` sorts imports, so order must decide nothing. The drivers:
`AnalyzerProjectTypeDiscovery.SelectVisibleType` (memoised per analysis; `ResolveVisibleProjectType`
materialises its source answer and STEPS ASIDE for lexical metadata; `TryFindAmbiguousImportedType` is
its `Ambiguous`), `AnalyzerExternalTypeProbe` (lexical chain -> imports -> scan cache -> scan; the scan's
bare-name guesses live in their own `scanCache` so they never pre-empt a later file's chain or
imports), `AnalyzerDeclarationContext.ResolveTypeNameWalk` (lexical tier + qualified; an imported CLR
type now outranks its unique-exported fallback), the type resolver's and member access's qualified
channels, and in the emitter `ColumnarBindingScopeFacts.SelectSimpleName/SelectQualifiedName` (gates
in the explicit-type walk, the source-declaration-name walk, `TryResolveProjectSourceTypeName`,
`TryResolveQualifiedSourceTypeName`, `BlocksSourceType`) plus `ColumnarExternalTypeCatalog.ResolveOwner`
(lexical -> import tier, a tie answers Unknown and declines with `emit.names.ambiguous-import` -> scan).
NL002 (`AnalyzerImportUsageCredit.RecordMetadataName`) and completion's auto-import
(`ImportEditPlanner.IsNamespaceInScope`) treat a lexical namespace as needing no import. Found carving
`Compiler.Model` out of Core: before this, `TypeInfo` inside `NSharpLang.Compiler.Columnar` bound
`System.Reflection.TypeInfo` once Model was another assembly, and `Ast.X` did not resolve. Contracts:
`Driver/ExternalLexicalLookup.tests.nl` (analysis, emit-only, formatter-order, code intel over an
emitted library), `SimpleNamePrecedence.tests.nl`, `tests/native/census-external-lookup`.

FOUR WALKS READ IT AND USED TO SPELL IT THEMSELVES: `AnalyzerTypeReferenceFacts.VisibleTypeNamespaces`
(now a delegation), `AnalyzerProjectTypeDiscovery` (the ambiguity gate and the inaccessible-declaration
probe, which now stands down for the whole chain), `AnalyzerDeclarationContext.ResolveTypeName` (the
cross-file signature resolver, which resolves against the file that WROTE the declaration and so
climbs THAT file's chain), and `ColumnarBindingScopeFacts` (both bare-name walks,
`TryResolveProjectSourceTypeName`, `ResolveSourceBaseName` and the `BlocksSourceType` veto).

The drift the single owner removes was real and two-sided. The ANALYZER never climbed at all, so it
reported 84 false NL209s over the compiler's own estate (`TypeInfo` 43, `TokenType` 41) for names its
enclosing `NSharpLang.Compiler` declares. The EMITTER climbed, but AFTER the imports, and
`TryResolveProjectSourceTypeName` probed the global namespace after them as well — so the SAME
spelling resolved two ways inside one file (a signature saw the enclosing declaration and a body local
saw the imported external type, `emit.typed-local.type-mismatch` naming both, which is what
`tests/native/runtime-acceptance` reproduced).

Step 2 is NOT the auto-discovery fallback beside it: that one finds a declaration in an UNRELATED
namespace and deliberately loses to an imported external type (the shadowing hazard
`tests/native/qualified-names` pins), while an enclosing namespace is lexically nearer than any
import. A SIBLING namespace (`A.Ast` beside `A.Columnar`) is not lexical at all and reaches a file
only by import.

A NON-EXPORTED declaration in an enclosing namespace is walked PAST rather than claiming the name or
reporting NL308: the file never asked for that namespace, so a private declaration out there must not
take a name the file explicitly imported. Both halves agree on that — the emitter matches only
`exportedSourceTypeNames`, and `TryFindInaccessibleVisibleDeclaration` skips every lexical namespace.

**A QUALIFIER CLIMBS THE SAME CHAIN.** The leftmost segment of a namespace-or-type-name is looked up
the way a simple name is, so `Ast.ParameterModifier` written inside `NSharpLang.Compiler` — or inside
`NSharpLang.Compiler.Columnar`, which reaches it through the enclosing `NSharpLang.Compiler` — names
`NSharpLang.Compiler.Ast.ParameterModifier`, and the written spelling is always the chain's last
candidate so an absolute qualifier still resolves. Imports are deliberately NOT in that chain: an
import brings a namespace's TYPES into a file, never its sub-namespaces, exactly as C# reads it. Wired
through `AnalyzerTypeResolver.TryResolveNamespaceQualifiedType`,
`AnalyzerMemberAccess.TryResolveTypeInNamespaceOrAssemblies` (expression position),
`AnalyzerDeclarationContext.ResolveTypeName`'s dotted branch (cross-file signatures — without it a
relative qualifier in a signature read from another file resolved to `unknown`, which surfaced as
`List<unknown>` at the caller's assignment) and the binding scope's dotted walks plus
`TryResolveQualifiedSourceTypeName`.

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

### What `for x in e` iterates

`ForeachPatternFacts.nl` is the C# `foreach` pattern (Roslyn's `ForEachLoopBinder`) written ONCE,
over `System.Type`, so the analyser (which types the loop variable) and the emitter (which lowers the
loop) cannot disagree about which collections iterate. `LoopSequenceTypeFacts.nl` is the element-type
half the analyser asks; `ColumnarForeachLoopPlanner.nl` is the lowering half the emitter asks.

The order is the language rule: array → `string` → the enumerator pattern (an accessible
parameterless `GetEnumerator()` whose result has a readable `Current` and a parameterless
`bool MoveNext()`) → `IEnumerable<T>` → the non-generic `IEnumerable` (element `object`).

Four things about this owner are load-bearing:

- **EVERY IDENTITY TEST IS BY `FullName`, NEVER BY `typeof`.** The analyser reads referenced
  assemblies through a MetadataLoadContext, where the projected `System.Boolean` is not `typeof(bool)`
  and the projected `IEnumerable<>` is not `typeof(IEnumerable<>)`. The walk this replaced compared
  RUNTIME IDENTITIES in all four of its arms, so it answered NO for every type that arrived through
  metadata — which is why a `foreach` over a `JsonElement.ArrayEnumerator`, a
  `Dictionary<K,V>.KeyCollection`, a `StringBuilder.ChunkEnumerator` or any user type from a
  referenced assembly was rejected as "collection must be enumerable". The conversion table beside it
  (`AnalyzerReflectionTypeConversion`) is keyed the same way for the same reason.
- **THE NAME TABLE IS GONE.** `LoopSequenceTypeFacts` used to answer eighteen unqualified spellings
  (`List`, `HashSet`, `Queue`, `Span`, five dictionary names…). A generic instantiation now answers
  through its DEFINITION and the arguments are substituted by POSITION
  (`AnalyzerReflectionTypeOverride.ForGenericArguments`), which is how `Dictionary<string, Widget>`
  produces `KeyValuePair<string, Widget>` over a source `Widget` the CLR has no handle for. An
  instantiation whose definition nothing binds answers nothing — a bare name is no longer evidence.
- **MEMBER LOOKUP WALKS THE DECLARATION CHAIN ITSELF.** `GetMethod`/`GetProperty` throw
  `AmbiguousMatchException` when a derived type shadows the member asked for, and an exception
  escaping type inference is a crashed `nlc`. A `DeclaredOnly` walk from the most derived declaration
  outward answers the same member and cannot throw. An INTERFACE has no `BaseType`, so the walk
  continues into its base interfaces — `IReadOnlyList<T>` declares none of the three itself.
- **DISPOSAL HAS FOUR ANSWERS, AND A BY-REF-LIKE ENUMERATOR IS NOT ONE OF THEM.** A value-type
  enumerator implementing `IDisposable` is disposed through a `constrained.` call; a reference one is
  null-checked; a non-sealed reference one that does not implement it is tested at run time. On this
  runtime `Span<T>.Enumerator` DOES name `IDisposable` (a by-ref-like type may implement an interface
  now) but no by-ref-like value can be converted to one, so only a PATTERN `void Dispose()` counts —
  and it implements `Dispose` explicitly, so a loop over a span disposes nothing and carries no
  protected region at all.

One emitter limit shapes the lowering: **a member whose signature carries REQUIRED CUSTOM MODIFIERS
cannot be referenced from emitted IL**, because the metadata writer drops them when it emits a
`MemberRef` ("Method not found: `'!0 ByRef Enumerator.get_Current()'`" at run time).
`ReadOnlySpan<T>.Enumerator.Current` is `ref readonly T`, which is exactly that shape, so
`ColumnarForeachLoopPlanner` refuses the pattern for it and lowers an INDEX loop instead — through
`ColumnarReadOnlySpanElementRead`, the same `Slice`/`MemoryMarshal.AsBytes`/`MemoryMarshal.Read` door
the index EXPRESSION already went through. `Span<T>`'s `Current` is a plain `ref T` and takes the
ordinary enumerator path.

Executable coverage: `tests/native/census-pattern-foreach` (runtime values and order for every shape,
disposal counts on the exhausted / `break` / `return` / throwing paths, and CLR metadata assertions
that the hidden enumerator local is the STRUCT rather than the interface and that a span loop emits no
exception-handling clause while a list loop emits one).

### Local functions are bound by the BLOCK, not by the walk

`AnalyzerLocalFunctionScope.nl` is the N# owner for "which local functions does this statement list
declare". `AnalyzerStatementSequence` asks it (request kind 4) BEFORE the list's first statement is
walked — and, for a block form, AFTER the block's own scope opened — so every local function of a
block is bound throughout that block: above its own declaration, below it, and inside its siblings.
That is C#'s rule (`LocalScopeBinder`) and it is the only way MUTUAL recursion is spellable; the old
rule declared the name where the statement was walked, so `visitStatement` calling `visitBlock`
reported NL412 whenever `visitBlock` was written second.

- Only DIRECT children of the list are hoisted. A local function declared in a nested block belongs
  to that block, is bound into that block's scope and dies with it, so it is still NL412 outside.
- `Scope.RecordHoistedLocalFunction` / `HasHoistedLocalFunction` is the per-scope memory that stops
  `AnalyzerFunctionBodies.AdvanceDeclareFunction` from declaring the same name a second time and
  reporting the declaration as a duplicate of itself. The check is asked rather than assumed, so a
  `LocalFunctionStatement` reached by a path that walked no statement list still gets its name.
- The position the hoist declares at is the STATEMENT's, which is what
  `AnalyzerFunctionBodies.BeginLocalFunction` already used — go-to-definition does not move.
- A LOCAL FUNCTION DECLARATION IS NOT CODE THAT RUNS in the enclosing list, so it is never dead
  code: the analyzer's unreachable rule (NL312), the linter's (NL006) and the columnar emitter's
  `emit.statement.unreachable-after-transfer` guard all skip a `LocalFunctionStatement` written after
  a `return`. The statement is still walked — its body has rules of its own — and the terminated flag
  stays set, so an ordinary statement after it is still reported.
- The emitter's half: the parent body and every local body now start with the FULL declared
  local-function name set (`visibleLocalFuncNames`), where visibility used to be textual. The locals
  are `<parent>g__N` private statics declared before the parent body emits, so mutual recursion is
  just two forward-referenced `MethodBuilder`s that bake at Save.

`AnalyzerLocalFunctionCaptures.nl` owns the other half: CALLING a local function reads every variable
its body reads, and definite assignment is asked about them AT THE CALL (C#'s CS0165 position), because
the same body is legal after the variable is assigned and illegal before it. There is no second
expression recursion — `AnalyzerDefiniteAssignment` re-runs its own walk with
`DefiniteAssignmentState.Collected` set, which turns its report into a RECORD, and the call site
judges the records against the CALLER's candidate and assigned sets. `Active` is the cycle guard, so
a mutually recursive pair contributes each other's reads exactly once; a call reached while already
collecting reports nothing and merges its reads outwards. The sub-walk is driven from
`AnalyzerDefiniteAssignment`'s own call arm rather than from the capture owner, because that class is
at the columnar front end's per-class member ceiling and a bare `this` declines it.

A local function CAPTURES through the same model a lambda does — see "A local function and a lambda
are one closure" below. A local function still does not SHADOW a same-named top-level function at
the call site (both calls resolve to the top-level one) — a separate pre-existing gap in the call
planner, unchanged by the block-scoping rule.

`ref`, `out` and `in` parameters are the one thing a local function may not capture. A byref
parameter is a pointer into the CALLER's frame and the closure object outlives it, so
`AnalyzerIdentifierResolution.Resolve` reports NL331 at the READ — C#'s CS1628 position and C#'s
rule. The enclosing function's byref parameter names travel into the local function's walk through
`AnalyzerAmbientContext.EnterLocalFunctionByRefParameters`, which ACCUMULATES rather than replaces,
so a nested local function may not read an outer function's byref parameter either. It is asked at
the one identifier door rather than by a second AST walk, so every use — read, write, argument —
reports without the rule naming any of those forms.

### A local function and a lambda are one closure

`ColumnarLocalFunctionClosurePlanner.nl` is the N# owner of "what do this body's local functions
capture, and where does each one live". It is asked BEFORE the enclosing body emits, because the
answer chooses each local function's OWNER and the call sites need the `MethodBuilder` in hand.

The plan is STRUCTURAL — names, not types — which is what lets it run that early. A local function's
free names are read from its own body table, the names it binds for itself are subtracted, and what
remains is matched against the DECLARING SCOPE (the enclosing parameters plus the root block's own
declarations) and against the enclosing type's instance members.

- CAPTURES NOTHING -> a private static, the lowering that was already there.
- CAPTURES A LOCAL OR PARAMETER -> an instance method of one `<>c__DisplayClass{n}` created for the
  scope. The captured binding is lifted into a shared `StrongBox<T>` in the enclosing body and the
  display holds the BOX, so both sides read and write one storage location — the `_liftedLocals`
  route in the body and the `_boxedCaptures` route off `ldarg.0` in the method, which is exactly what
  a capturing lambda already uses. The box is stored into its display field at the point the box is
  created, because a local's box does not exist until its declaration runs; a capture that never
  reached a box is reported BY NAME at `emit.local-function.capture`.
- CAPTURES ONLY `this` -> an instance method of the ENCLOSING TYPE. Its own arg 0 is the receiver, so
  every bare member read, write and call inside it lowers exactly as in an ordinary method body — and
  for a STRUCT that placement IS C#'s `ref this`, since an instance method of a value type receives
  its receiver by reference.
- CAPTURES BOTH -> a display method, with `<>4__this` on the display (the field a mixed-capture
  lambda already carries).

BOTH REQUIREMENTS FLOW BACKWARDS ALONG THE CALL GRAPH, IN ONE FIXPOINT. A capture-free local function
that calls a capturing one needs the receiver that sibling runs on, and one that calls a
`this`-reading sibling needs the instance; mutual recursion is a cycle in that graph and settles in
the same loop. An explicit generic call such as `Read<V>(other)` contributes the bare callee from the
`GenericCallee` node's value span. Its child nodes are TYPE arguments and are deliberately not scanned
as value names; a qualified spelling is likewise not treated as a local sibling by its short name.
The bare candidate is matched against the exact local declarations in the same scope before it
becomes a call-graph edge.

THE DECLARING SCOPE IS NOT THE WHOLE BODY. `CollectDeclaringScopeBindingNames` reads the enclosing
parameters plus the ROOT BLOCK's declarations. Reading every name the body binds anywhere refused
`func visit(item: string)` in a body that also wrote `for item in items` — two `item`s that never
share a scope, which `nlc check` and C# both accept.

`TryDeclareLocalFunctions` and `TryEmitLocalFunctionBodies` in `ColumnarIlEmitter.nl` are the one
pair of helpers a FREE function's body and a type MEMBER's body both call; the member half also
needed `ColumnarStructMethodUnsupportedStatus` to stop answering "unsupported" for any member with a
local function, which used to decline the whole type declaration at `parse.struct`. A local function
in a GENERIC TYPE MEMBER still declines (`emit.local-function.generic-member`); generic free
functions carry their enclosing parameters as described above.

### A display chain, not a display level

`ColumnarStructDef.ClosureEnclosingDef` is the link that turns the display class model above from a
one-level answer into a chain. A display that captured an enclosing RECEIVER records the scope it was
made for: the declaring TYPE when the capturing scope is a member body, and the PARENT DISPLAY when
the capturing scope is itself a lambda or local function with a display of its own. `<>4__this` is
therefore one link, not a step.

`ColumnarBoundIdentifierPlanner.TryResolveCapturedEnclosingInstance` walks it. From argument zero it
collects one `<>4__this` per level and stops at the level that declares the name, which may be the
enclosing TYPE (a field, a property, or a member inherited from an external base, by the same
ordinary current-instance resolution `this.Member` uses) or another DISPLAY (a snapshot capture of
the scope above). The selection carries the whole `ReceiverFields` chain, so no arm counts levels and
`x => y => z => …` costs nothing extra. A parent display's field resolves AHEAD of the blocked-name
gate, because it is capture storage; the enclosing type's members resolve AFTER it, because an
enclosing LOCAL of the same name does shadow a member.

Two consequences fell out of having that route at all:

- `BodyReferencesEnclosingInstanceMemberChain` (was `…InstanceMethodChain`) asks the whole
  instance-member question — field, property or method, plus bare `this`. It used to narrow to
  instance METHODS because there was no way to emit the field read the wider answer would have
  admitted. A STATIC member still says no: it belongs to the type and is reached with no receiver.
- A MUTATED capture is reachable from one level deeper. Inside a display, a lifted name's box rides a
  FIELD of the display the body runs on rather than a local, so the capture scan offers
  `_boxedCaptures` alongside the locals and the classification copies the BOX reference out of
  argument zero — the same copy the lifted-local arm makes from a slot, which is why a write at
  either depth is seen at every other.

A lambda whose whole body is another lambda takes its shape from the outer delegate's RETURN type,
the same contextual reading `return x => …` and a delegate argument position perform; and an
EXPRESSION body is its own `_bodyRoot`, without which the never-mutated scan a nested capture needs
had no body to scan.

### A lambda body is typed in the frame around it

`TryPreflightContextualLambdaReturnType` builds its sub-emitter from the ENCLOSING frame — parameters,
locals, lifted and boxed captures, tuple-element names — with the lambda's own parameters written over
it. Only a TYPE comes back out of a preflight, so the lambda's ordinals simply move past the enclosing
frame's rather than colliding with them (two bindings at one argument ordinal is a contradiction the
plan refuses by throwing).

This is what a generic call whose OUTPUT type parameter is bound by the lambda's return needs:
`xs.ConvertAll(x => x + bump)` could not type `bump`, so `TOutput` had nothing to bind it and the call
declined at `emit.call.instance-member`. The same lambda reading a FIELD inferred fine, because the
instance was already in reach through `_currentStruct` — which is how the gap was named.

STILL OPEN: a BLOCK-bodied lambda at an inferring position cannot type a `return` that reads a local
the BLOCK declares. `CollectBlockReturnTypes` has no storage to bind such a name to, and it declines
with or without a capture.

### A substituted type parameter takes the type ARGUMENT's nullability

`NullabilityGenericSubstitution.nl` is the N# owner for the two facts the nullability reader needs
when a member position is a bare type parameter, and `NullabilityMetadataReflection.ConvertMemberType`
is the one place that consults it.

THE ROOT CAUSE IS `NullabilityInfoContext`. It answers `Nullable` for EVERY bare-parameter position —
measured on the CLOSED instantiation as well as on the open definition, and it has to, because an
unconstrained `T` may be instantiated with a nullable type. Taking that answer made
`Lazy<string>.Value`, `Task<string>.Result`, `Tuple<string, int>.Item1` and a `Predicate<string>`
lambda's parameter all maybe-null: the census's ten `docQuery.Value` NL905s and every
`xs.Find(s => s.Length > 0)` whose `s` was reported inside the lambda.

- `OpenPropertyType` / `OpenFieldType` / `OpenParameterType` answer the position's spelling AS ITS
  DEFINITION WRITES IT. A member read off a constructed generic already has its type substituted by
  the CLR, so the `T` survives only on the definition. TWO substitutions may have to be undone and
  the order matters: the METHOD's own (`Enumerable.FirstOrDefault<string>` →
  `FirstOrDefault<TSource>`) first because positions align exactly, then the DECLARING TYPE's
  (`List<string>.Find` → `List<>.Find`). The declaring type is the member's, not the receiver's, so
  an inherited member resolves against the base that declares it; an ambiguous overload name or a
  lookup that finds nothing answers with the CLOSED type, which is the old behaviour.
- `IsAnnotatedNullable` reads the annotation from THREE places, because C# writes it in three:
  `NullableAttribute(2)` on the position (`List<T>.Find`'s return), the nearest
  `NullableContextAttribute(2)` at or above the member (`Enumerable.FirstOrDefault` carries it on the
  METHOD while `Enumerable` carries `(1)` — reading only the position makes `First` and
  `FirstOrDefault` mean the same thing), and `[MaybeNullWhen(...)]`, which N# does not model
  conditionally and therefore reads as plainly nullable (this is also what preserves
  `Dictionary<K, V>.TryGetValue`'s `out string? value`). Nothing found at all is oblivious, which is
  NOT annotated-nullable: the argument decides.
- `ConvertSubstitutedParameterType` is the conversion that takes the read state as a VALUE instead of
  reading it, and it is deliberately a sibling of `ConvertReflectedType` rather than a parameter on
  it. Only the TOP-LEVEL position is overridden; everything nested keeps reading its own
  `NullabilityInfo`, because a nested position is about a type ARGUMENT the member really did write.
  Collapsing the two made `Array.ConvertAll`'s `TOutput[]` return read `string?[]`.
  The override arm honours the supplied state too — `FirstOrDefault` is `TSource?` and the override
  alone answers the argument verbatim, losing the `?`.
- `AnalyzerMemberResolution.TryResolveSpelledTypeParameterMember` is the other half: `Lazy<string?>`
  and `Lazy<string>` are the SAME CLR type, so the argument's `?` lives only in the SOURCE spelling.
  A property or field whose definition position is a bare parameter is therefore read off the
  DEFINITION with `AnalyzerReflectionTypeOverride.ForGenericArguments` — the exact-conversion twin of
  the surrogate path beside it. It answers for nothing else: a member whose type does not mention a
  parameter reads identically off the closed type, and an INHERITED one is spelled in its BASE's
  parameters, which the receiver's arguments do not index.

Two estate contracts encoded the OLD answer and were updated with the reason:
`NullabilityMetadataReflection`'s `List<T>.Add` parameter (`Nullable(Simple(T))` → `Simple(T)`) and
`AnalyzerReflectionArgumentBinder`'s bound `Converter<int, TOutput>` signature (`(int)->string?` →
`(int)->string`).

NOT YET: the columnar backend does not emit `Enumerable.FirstOrDefault`/`LastOrDefault` calls, so
their `T?` contract is pinned in the estate rather than in `tests/native/census-flow-rules`.

### The loop variable's written type — `for x: T in e`, and NL330

The loop variable may carry an annotation, and it is the C# `foreach (T x in e)` form: each element
is converted to `T` by an EXPLICIT conversion, once per iteration. Three owners carry it.

- **The parsers.** `ForeachStatement.VariableType` is an optional `TypeReference`. The recovery
  parser decides with the BOUNDED TYPE SCAN the cast disambiguation already owns
  (`ScanTypeReference` from the `:`, then require `in`) — committing on the `Identifier :` prefix
  alone would steal a C-style header whose initializer is annotated. The scan is spelled INLINE
  because `ColumnarParserRecovery` is at the per-class member ceiling (§2.1 of the closeout STATUS).
  The columnar kernel produces **node kind 76**, TypedForeach: a type TREE cannot share the statement
  node table, so the annotation rides as a SOURCE SPAN in the value slot exactly as a typed local's
  (kind 40) does, and the name moves into a leading child — children `[name, collection, body]`.
- **`ForeachElementConversionFacts.nl`** is the rule, stated as five questions to the ORDINARY
  assignability oracle rather than as a table of pairs: an implicit conversion element → declared;
  the same question BACKWARDS (every explicit reference conversion and every unboxing is the reverse
  of an implicit one — this is what identifies a downcast without a second classification); both
  sides numeric; an enum against a number or another enum; an interface on either side. A type that
  is `unknown` or an `ExternalTypeInfo` (a bare NAME, with no base, members or interfaces) is
  SILENT. Failure is `NL330`, reported at the ANNOTATION's span and naming both types.
  `AnalyzerLoopSequence.ApplyForeachVariableAnnotation` then makes the written type the loop
  variable's type for the scope, the semantic model, the binding map and the body — *including when
  the conversion was refused*, so one mistake stays one diagnostic instead of cascading.
- **The emitter.** `ColumnarIlEmitter.TryEmitCastConversion` is the kind-16 cast arm's whole
  conversion body, extracted unchanged, and all four loop shapes run it on the loaded element before
  storing it into a local declared at the WRITTEN type. The loop and the cast therefore share ONE
  definition of the explicit conversions. Extracting it also closed a cast gap: a downcast between
  two types this compilation is EMITTING (`(Square)shape`) declined, and now asks
  `ColumnarReferenceConversionFacts.TryEmitReferenceConversion` with the two types swapped and emits
  `castclass`.

An annotated loop inside a generator is not lowered yet: `ColumnarIteratorPlanner` declines kind 76
by name (`emit.iterator.for-in-unsupported`).

Executable coverage: `tests/native/census-pattern-foreach/AnnotatedLoopVariable.*` — every conversion
run as emitted IL, the metadata assertion that the hidden local is the ANNOTATED type, the assertion
that an identity annotation costs no IL bytes, and the `InvalidCastException` a wrong runtime type
produces. Contracts: `ForeachElementConversionFacts.tests.nl`, the NL330 blocks in
`AnalyzerLoopSequence.tests.nl`, the parser blocks in `ColumnarParserAst.tests.nl` and the printing
blocks in `FormatterWalk.tests.nl`.

## Iterator Bodies Are Ordinary Bodies

An iterator (`func*` / `async func*`) body is planned by the SAME expression owner a plain function
body uses. `ColumnarIteratorBodyScope` (`ColumnarIteratorBodyScope.nl`) is the whole of the state
machine's effect on a body's meaning, and it is TWO binding rules rather than a planner:

- a HOISTED name — a captured parameter, a hoisted local, a synthesized loop slot — is a FIELD of
  `this`, which is `ColumnarBoundIdentifierPlanner`'s `CurrentField` selection (`ldarg.0; ldfld`);
- an ENCLOSING-TYPE member read by an instance machine is the new `CapturedInstanceField` selection
  (`ldarg.0; ldfld <>__this; ldfld <member>`) — the same two-hop read a closure display does through
  its captured box, with a member field in place of `StrongBox<T>.Value`.

With those published, every value in the body goes through
`ColumnarRangeIndexPlanner.TryAppendConstructionValue` — the append-mode value cascade a CALL ARGUMENT
uses — so calls, `new`, object initializers, array and collection literals, indexers, member access,
casts, ranges, ternaries and binaries behave identically inside and outside a generator.
`ColumnarIteratorPlanner`'s old mini-planner for iterator expressions is DELETED (its canonical-string
type inference, binary-operator table, string-method allowlist and BCL-exception allowlist with it).

Consequences worth knowing:

- **A hoisted local's TYPE is resolved at realization, not at classification.** `AnalyzeShape` still
  owns each hoisted field's NAME, ROLE and POSITION (which is what state numbering and the
  guarded-layout decision need) but marks a `:=` local's canonical UNRESOLVED (`"?"`,
  `ColumnarIteratorPlanner.IsUnresolvedCanonical`). `ColumnarIteratorEmitContext.TryEnsureHoistedField`
  defines the CLR field from the initializer's planned type when the lowering reaches the declaration.
  A slot that already exists keeps ITS type and the value must be storable in it (identity, or a
  reference widening between two baked handles), so `v := 1` then `v := true` in disjoint branches
  declines while a host-supplied wider slot is reused.
- **A decline can now happen during body lowering** rather than only during classification. The
  context carries `DeclineSite`/`DeclineMessage`; `ColumnarIteratorRealization` reports it after
  `BuildMoveNextPlan` and before any IL is executed into the method.
- **`yield <value>` takes the conversion a `return` takes** —
  `ColumnarDirectCallPlanner.AppendArgumentConversion`, the call-argument conversion owner — and a
  target-typed array literal (`yield ["a", 1]` as `object[]`) is planned by
  `ColumnarConstructionPlanner.TryAppendTargetTypedArray`, the position-knows-the-element-type
  counterpart of `TryAppendInferredArray`.
- **`for..in` inside a generator enumerates any sequence.** The source is an ordinary expression; its
  element type comes from the planned value's CLR type (an SZ array's element, or the single
  `IEnumerable<T>` it implements). A hoisted ARRAY field still takes the index loop.

Three plan-schema rules were relaxed to say what a METHOD BODY is, and each is narrow: a `System.Void`
fragment result is legal on a schema-v4 ROOT fragment (`ColumnarCodePlan.IsMethodBodyRootFragment`)
because a body is a sequence of statement trees and a call statement's tree is void; the same rule
replaces `callFragment == 0` in `ColumnarDirectCallPlanner`'s void guards; and an `arr[i]` is a
non-root claim at every position a method body can put it in, because an index access is never a
statement. A NESTED void fragment is still refused on every schema.

### A generator suspends inside `try`/`finally`

A `yield` may appear inside a `try` whose ONLY handler is a `finally`. The lowering is the C#
compiler's:

- **Every `try` in the body is a region ordinal**, assigned in classification walk order and re-assigned
  identically by the emission walk (`ColumnarIteratorWalkState.TryRegionParents` /
  `ResumeRegions`, carried on `ColumnarIteratorShape`). A resume state records the innermost region it
  suspends inside.
- **A resume point inside a region is reached by dispatching twice.** A branch INTO a protected region
  is illegal IL, so the method prologue's dispatch sends such a state to the region's ENTRY label
  (just before its `try`), and the region's own first rows are a second dispatch that finishes the hop
  — recursively, for nested regions (`ColumnarIteratorBodyPlanner.AppendStateDispatch` /
  `DispatchTargetFor`).
- **The `finally` handler is guarded by the machine's state**: `if (<>__state < 0) { <handler> }`. A
  handler runs on every exit from a protected region, and a `yield return` leaves one — but suspending
  is not ending the statement. The suspension stored a POSITIVE resume state just before branching out;
  a normal completion, an in-flight exception and a dispose-driven unwind are all still `-1` (running).
- **Abandonment re-drives the machine in dispose mode.** A `<>__disposing` field (role 9) exists only
  on a machine that can suspend inside a region; `Dispose` sets it and calls `MoveNext`, which resumes
  at the suspension point, marks itself running, sees the flag and branches to the end label — leaving
  every open region so the runtime runs each `finally`, innermost first
  (`ColumnarIteratorBodyPlanner.AppendDisposeModeUnwind` / `AppendDisposeModeExit`).
- **`ret` is illegal inside a protected region**, so a body that writes any `try` takes the same
  result-local-plus-`leave` exit shape the hoisted-enumerator (try/FAULT) layout already used;
  `BuildMoveNextPlan` now emits all three shapes from one walk.
- **A catch clause hoists the exception it binds** — a state machine's bindings are fields — under the
  clause's own variable name, or `<>__exception{k}` for a clause that binds none.
- `ColumnarCodePlanExecutor` now admits SEVERAL catch handlers on one region and a `finally`/`fault`
  after them, as its terminal handler.

The three placements a suspension cannot resume from are **NL332**
(`AnalyzerAmbientContext.EnterYieldForbidden` / `ReportYieldPlacementIfNeeded`, pushed by
`AnalyzerResourceStatements.AdvanceTry`): a `yield` inside a `try` that declares a `catch`, inside a
`catch` handler, or inside a `finally` handler. `ColumnarIteratorPlanner.WalkTryStatement` refuses the
same three with the same sentences, so no shape can reach lowering without a diagnostic.

### An `async` lambda moves the boundary between the body and the delegate

`async x => …` is the ordinary lambda with one thing changed: the body produces the RESULT the
target delegate's task carries, and the lambda's own type is a task of it. Everything else — the
parameter list, the contextual typing, the display class — is unchanged.

- **Two node kinds, one shape.** The parser emits **kind 78** for an `async` lambda and kind 39 for a
  plain one, with identical children and spans; the `async` token is consumed in
  `ParseLambdaOrAssignmentExpressionNode` only when a lambda actually follows it, so `async func` (a
  local function) is untouched. Every reader that only asks "is this a lambda" goes through
  `ColumnarLambdaNodeFacts.IsLambda`, so no dispatch table could be left behind; only the body's
  expected type and the method it is emitted into ask `IsAsyncLambda`. The AST twin is
  `LambdaExpression.IsAsync`, set by `ColumnarParserRecovery` (which re-anchors the node on the
  `async` keyword) and written back by `FormatterWalk`.
- **`return` now parses a lambda.** Both parsers take the LAMBDA level after `return`, so
  `return async () => …` (and `return x => …`) is a delegate-returning function's ordinary body; the
  emitter's return arm gives a returned lambda its shape from the DECLARED return type, exactly as the
  method-group arm beside it does.
- **The analyzer unwraps, then re-wraps.** `AnalyzerLambdaAnalysis.AsyncBodyReturnType` turns the
  target's `Task<T>`/`ValueTask<T>` into `T` and its `Task`/`ValueTask` into `void` for the body's
  expected type, and `FinishLambda` puts the body's answer back into the target's task family
  (`AsyncWrappedReturnType`). Both halves are load-bearing: without the first the body is measured
  against the task, and without the second `Task.Run(async () => await F())` cannot fix `TResult`,
  because folding `Task<TResult>` against `Task<TResult>` fixes nothing.
- **There is NO `async void`, deliberately.** N#'s `await` is sync-lowered, so an async body with no
  task to carry its result or fault IS its own body — the keyword would mean nothing, and the C#
  meaning (the exception posted to a synchronization context) is not on offer. **NL334** reports a
  non-task-like target and a target-less lambda. Refusing it is also what keeps overload selection
  honest: `AnalyzerReflectionArgumentBinder` drops a non-task candidate for an `async` lambda outright
  and scores the value-keeping task position higher, so `Task.Run(async () => …)` cannot bind to
  `Task.Run(Action)` and silently discard what the body awaited. The emitter agrees through
  `IsContextualLambdaTarget`, and its `Task.Run` arm picks `Action` or `Func<Task>` by the argument's
  own shape rather than by a fixed table row.
- **NL335 IS NL334'S MIRROR** and is reported from the expression-body phase: the target's return IS
  task-like and the body's value is NOT a task, so no conversion exists and the missing `async` is
  the fix. It is a rule about the CONVERSION rather than about `await` — N# allows `await` in a body
  that is not declared `async`, so "you awaited without saying async" is not a rule this language has.
  A block body is not asked: a lambda does not infer a block's return type, and its `return`s are
  measured against the signature by the nested-body boundary, which reports their mismatch there.
- **An `async` LOCAL FUNCTION is the same shape in a local function's method.** It declares its INNER
  type and the emitted method returns the wrap (`TryComputeAsyncReturnShape`, the same owner a
  top-level `async func` asks), so every call site sees `ValueTask<T>`; the body sub-emitter is given
  the inner type plus the async return shape. `emit.local-function.async` — the decline that said "its
  body is not routed through the async return planner" — is gone.
- **Emission is the async function's shape, in a lambda's method.** `TryEmitLambdaLiteral` keeps the
  DELEGATE's signature on the synthesized method and hands the sub-emitter the unwrapped type plus
  `asyncReturnType`, so `EmitBody`'s async fault guard runs for a block body and
  `EmitAsyncLambdaExpressionBody` writes the same guard around a single expression. That guard is the
  observable contract: an exception raised in the body becomes a FAULTED TASK rather than reaching the
  caller.

### A bare `throw` is the rethrow, and its placement is an ambient question

`throw` with no expression re-raises the exception the enclosing `catch` handler is running for, as IL
`rethrow`, which is the only way to re-raise WITHOUT resetting the stack trace (`throw e` raises the
same object from the handler's own frame and loses the original site).

- **The parser builds the node either way.** `ColumnarParserRecovery.ParseThrowStatement` produces
  `ThrowStatement(null, …)` at a statement boundary (EOF, `}`, `;`, or a token on a later line —
  `IsBareThrowBoundary`), and the kernel's `throw` arm emits **kind 48 with ZERO children**, the same
  shape `yield break` uses against `yield`. Whether it is legal where it stands is semantic, exactly
  as `break` outside a loop is. (A `throw` in EXPRESSION position still requires an operand.)
- **The rule lives on the ambient context**, beside the loop and `finally` families:
  `EnterCatchHandler` / `ExitCatchHandler` keep `CatchHandlerDepth` and `RethrowTargetFinallyDepth`
  (the `finally` depth the innermost handler opened at), pushed by
  `AnalyzerResourceStatements.AdvanceTry` phases 4/5 around a clause's body.
  `ReportRethrowIfNeeded` raises **NL336** with two different sentences: no handler at all, and a
  `finally` nested inside the handler it would re-throw from. `EnterNestedBody` ZEROES both — a lambda
  or a local function compiles to a method of its own, and `rethrow` is valid only in a handler of the
  method it stands in.
- **Emission mirrors the same two counters.** `ColumnarIlEmitter` tracks `_catchHandlerDepth` /
  `_rethrowTargetFinallyDepth` around each handler body and emits `OpCodes.Rethrow`; the state-machine
  path appends `ColumnarCodePlanContract.Rethrow()` (0xFE1A, `-486`) with
  `ColumnarMoveNextEmit.CatchHandlerDepth` answering the same question. Both refusals are contract
  guards: the analyzer has already reported every program that could reach them.
- **A region END is a reachable entry in the method-body stack validator.** `EndExceptionBlock` writes
  no instruction of its own and every `leave` out of the region targets the row AFTER it, so a handler
  that ends in `throw` or `rethrow` leaves that row with nothing falling into it. It is seeded at
  height 0 alongside the handler starts; without that, an ordinary `catch { throw }` inside a
  generator was refused as "unreachable instructions".

### An assignment target may be a member or an indexer

`ColumnarStoreTargetPlanner` is the WRITE twin of the member and index reads, as code-plan rows, and
it is a general owner rather than an iterator one: `ClaimsTarget` takes a one-child member access or a
two-child index access, and `TryAppendStore` appends receiver, index and value in source order.

- A MEMBER is selected by `ColumnarInstanceMemberPlanner.TrySelect` — the same call the READ takes —
  so a source field, an inherited source field, a reflected field and a settable property all resolve
  identically on both sides. A property's setter is the `set_X` beside the `get_X` the read selected,
  on the same declaring type (`SetterFor`); a builder-bound owner cannot answer a reflection query and
  declines.
- An INDEXER over an SZ array is `stelem` with the element conversion; every other receiver resolves
  `set_Item` through `ColumnarOrdinaryRuntimeDirectCallResolver` against the WRITTEN index and value
  types, which are discovered by planning them into a scratch plan first (overload selection has to
  finish before a receiver that cannot be reached again goes on the stack).
- A VALUE-TYPE receiver reached as a value is a COPY, so `IsObservableWriteReceiver` refuses it rather
  than emitting a store nothing can read back. A read-only field and a get-only property decline for
  the same reason.
- The stored value goes through `ColumnarConstructionPlanner.TryAppendTargetTypedValue`, the one
  target-typed door, so a target-typed literal and an ordinary value both take the conversion a call
  argument at that type would take.

Inside a generator, `ColumnarIteratorBodyPlanner.EmitStoreTargetAssignment` routes to it, and
`EmitEnclosingMemberAssignment` writes an instance generator's enclosing member through the captured
`<>__this` — the same two-hop write the READ of that name already performs. A COMPOUND assignment to a
member or an indexer still declines (it would evaluate the receiver twice, and this owner does not yet
hold the single-evaluation temporaries).

### The annotated loop variable, inside a generator

`for v: T in e` (node kind 76) shares ONE classification walk and ONE emission walk with the
unannotated spelling — `ColumnarIteratorPlanner.WalkForIn` and `ColumnarIteratorBodyPlanner.EmitForIn`
— because the two differ in exactly one fact: whether the loop variable's type is WRITTEN. An
annotated variable's hoisted field is defined from the annotation; an inferred one's is defined from
the element the planned source produces, as before.

The conversion itself is `ColumnarCastConversionPlanner`, the plan-row counterpart of
`ColumnarIlEmitter.TryEmitCastConversion`: identity and a reference widening cost nothing, a boxing is
`box`, an unboxing (and every conversion TO a type parameter) is `unbox.any`, a reference downcast is
`castclass`, and a numeric conversion is the unchecked `conv.*` its TARGET selects (an enum through its
underlying type). `ForeachElementConversionFacts` still owns the QUESTION — NL330 reports the pair
that has no conversion — so a program the analyzer accepted is the program the machine runs.

Merging the two walks also closed a latent mismatch: classification hoisted an `<>__index{k}` slot
only for an array element the index loop can load (`IsLowerableArrayElementCanonical`), while emission
took the array loop for ANY array element canonical. An `object[]` source therefore hoisted enumerator
facts and then looked for an index field that was never reserved. Both sides now ask the identical
question.

### `await`, for any awaitable, in any BOUND position

The `await Task.Delay(<int>)`-only admission is gone. `ColumnarIteratorPlanner.WalkAwait` counts the
suspension and walks the operand as an ordinary expression;
`ColumnarIteratorBodyPlanner.AppendAwait` then asks the operand's PLANNED type for `GetAwaiter()`, and
that awaiter for `get_IsCompleted`, `OnCompleted(Action)` and `GetResult()` — ordinary CLR member
lookup, no table of known tasks. A `Task`, a `Task<T>`, a `ValueTask<T>` and a user awaitable all
answer; a struct awaitable is called through the address of a temporary, and a struct awaiter through
the address of its own field (a copy would throw the continuation state away). The awaiter field is
hoisted UNRESOLVED (role 5) and defined from that awaiter type when the lowering reaches the
suspension, so a machine with two awaits of different awaitables carries two differently-typed slots.

An ASYNC machine may enumerate a sequence source too: the hoisted `<>__enum{k}` field is the same one
the synchronous machine reserves, and only its RELEASE differs — a synchronous machine has a FAULT
handler for the exceptional path, and the async step core rides the `catch (Exception)` it already has
(an exception must reach the pending call's promise) plus `DisposeAsync` for the abandonment path.

An `await` may be the WHOLE value of a declaration, an assignment or a `yield`
(`ColumnarIteratorPlanner.WalkBoundValue` / `ColumnarIteratorBodyPlanner.AppendBoundFieldStore`), and
nothing else: a suspension branches out of the step core and ECMA requires an EMPTY evaluation stack
at that branch, so the awaited value is produced FIRST, parked in a plan local, and only then is
`this` loaded and the field written. An `await` nested inside a larger expression needs a spill this
owner does not yet hold and declines saying so.

### Lambda captures in a generator

A capture declared outside a loop remains a field of the generator state machine. For that common
case, `ColumnarIteratorBodyPlanner.AppendLambda` defines the private instance method directly on the
machine and builds the delegate from the machine receiver. A loop-declared capture instead gets a
fresh `StrongBox<T>` when its iteration begins. The lambda method lives on a synthesized display that
stores those box references plus the machine reference. Later writes in the same iteration update the
same box, while the next iteration gets another box; names declared outside the loop remain shared
through the machine. The signature still comes from the delegate's own `Invoke`, and both bodies use
the same expression scope.

`ldftn` is new in the plan schema (`ColumnarCodePlanContract.Ldftn`, 0xFE06): it reads no argument and
pushes one value, modelled as `IntPtr` because that is exactly what a delegate constructor's second
parameter is declared as, so the following `newobj` matches with no new stack kind.

`ColumnarIteratorWalkState.LocalLoopDepths` records where each local is declared, and the lambda walk
records only names it actually captures; the lambda's own parameters shadow body bindings and are
excluded.

Closing this also fixed a delegate-canonical bug that was never iterator-specific:
`ColumnarCanonicalTypeResolver.TrySelectDelegateCanonical` split `Func<int, int>` into `int` and
` int` and failed on the second, so every delegate written with a space after its comma failed to
resolve while the same type written without one succeeded. And `TryResolveIteratorCanonical` now
accepts a complete external DELEGATE type as a hoisted field type; the general storable-type catalog
has not been widened, because that is a question about the whole value surface.

An async lambda inside a generator uses its selected machine or per-iteration display as its closure
and writes a synthesized method returning the target's exact Task/ValueTask family. Its own awaits use the current
blocking-await lowering within the generator lambda's supported expression forms, including binary
operands, call arguments and indexes, and never consume a resume state from
the enclosing iterator. Successful results are wrapped and synchronous body exceptions become faulted
tasks. The delegate may return `Task`, `Task<T>`, `ValueTask` or `ValueTask<T>`.

Not yet lowered inside a generator body, each with its own decline: `return <value>`
(`emit.iterator.unsupported-shape`), `lock`, an `await` nested in a larger expression of the
enclosing async iterator, an `await` inside a `catch` handler and an awaiting `finally` beside a
`catch` on the same `try` (both `emit.iterator.async-await-unsupported`). Generic async iterator
methods remain declined at `emit.iterator.async-unsupported`. The existing generator-lambda expression
boundary still excludes non-literal unary negation, such as `() => -value`, with or without an await.
Generator lambdas also retain the existing refusal for mutation of their own parameters or locals,
including postfix steps and plain assignment. Ordinary lambda support for those forms does not
extend the generator statement planner; captured generator bindings have their own supported storage.

### Protected regions and awaits in handler positions (census ITER4)

A `try`/`catch`/`finally`, a `using`, an `await using` and an `await foreach` may all be written
inside an `async func*`. Three facts make that work, and they are worth stating separately because
each one was a bug before it was a feature.

**One suspension counter.** An async machine interleaves `yield` and `await` under ONE resume
numbering (`ColumnarMoveNextEmit.NextResume`), but classification keyed the region table by the YIELD
count (`ResumeRegions[state.YieldReturnCount]`). Every suspension after the first `await` therefore
recorded the wrong region, which is invisible until a region exists at all.
`ColumnarIteratorWalkState.ResumeCount` is the shared counter both kinds now increment, and
`TotalResumeCount` is the emission side of the same question — a dispatch that asked only about the
yields would never route a resume that suspended at an `await` inside a region.

**The async shape carries the region facts.** `BuildSupportedAsyncShape` copies
`TryRegionCount`/`TryRegionParents`/`ResumeRegions` exactly as the synchronous one does, and the
dispose flag is decided for BOTH machines before either counts its fields. `BuildAsyncMoveNextCorePlan`
defines the region-entry labels the dispatch hops through.

**`DisposeAsync` drives the unwind and then asks the promise.** The synchronous twin drives
`MoveNext` once and throws the answer away; an async machine cannot, because a handler it is standing
in may itself suspend. `AppendAsyncDisposeUnwind` sets the dispose flag, clears the promise, drives
the step core, and returns `new ValueTask(promise.Task)` when a suspension left one — otherwise the
core already reached its end label, marked the machine done and released its enumerators (which is
why that release moved INTO the core's end path, not `DisposeAsync`'s).

#### The hoisted handler

An `await` inside a `finally` can never run inside the region it guards: a suspension leaves the
method with an empty evaluation stack and comes back through the state dispatch, and a dispatch
cannot branch INTO a protected region. `EmitHoistedHandlerRegion` implements Roslyn's
`AsyncMethodToStateMachineRewriter.VisitTryStatement` lowering —

    entry_k:  this.<>__pending{k} = null; this.<>__branch{k} = 0
              try   { <dispatch for k> <body> leave end_k }
              catch (Exception e) { this.<>__pending{k} = ExceptionDispatchInfo.Capture(e) }
    end_k:    <handler body — awaits freely, in ordinary code>
              if (this.<>__pending{k} != null) this.<>__pending{k}.Throw()
              if (this.<>__branch{k} != 0) <re-issue the exit, one level out>

— and pays for the hoist with two FIELDS (a plan local would not survive a suspension inside the
handler). `<>__pending{k}` is an `ExceptionDispatchInfo` so the ORIGINAL stack trace survives the
re-raise; `<>__branch{k}` records an exit that would otherwise jump straight to the body's end label
and skip the handler. `AppendBodyExit` is the ONE place that knows this, and it re-issues the branch
in the ENCLOSING context so nested hoisted regions hop out one level at a time. There is no
`state < 0` guard and none is needed: a suspension inside the body leaves to the METHOD's region end,
never to this region's.

`BeginHoistedHandlerRegion`/`EndHoistedHandlerRegion` are shared by all three owners — a written
awaiting `finally`, `await using` (whose handler awaits `DisposeAsync()` in the same four release
shapes the synchronous `using` has) and `await foreach` (whose handler releases the inner
`IAsyncEnumerator<T>`). The `await foreach` enumerator is deliberately NOT a `<>__enum{k}` slot:
those are released by the machine's blanket SYNCHRONOUS disposal, which is the wrong release for an
`IAsyncDisposable`. `AppendAwait` is split at `AppendAwaitOfStackValue` so a synthesized suspension
runs the identical rows a written `await` does.

Two shapes remain declined, and the reason is one sentence: the hoisted form replaces the statement's
own handlers with ONE catch-all, so a `catch` clause would have to be re-matched by hand against the
parked exception. An `await` inside a `catch`, and an awaiting `finally` on a `try` that also declares
a `catch`, therefore decline with their own messages.

⚠ THE REPO'S "DECLINING SHAPE" SENTINEL is now a generic async iterator method. Analysis accepts the
shape, while iterator realization declines at `emit.iterator.async-unsupported` because its generic
state machine is not yet lowered. The sentinel appears in the compilation-reference fixture and the
native reference-resolution, columnar-emit-facts, CLI-command-contracts and compilation-backend
projects. An async lambda inside an ordinary generator is supported and must not be reused as a
negative sentinel.

### The branch-merge value forms on the plan side (census ITER3)

`??`, the conditional and `throw` written as an EXPRESSION are branch-merges, and only the ternary
had a plan-side owner: `ColumnarIlEmitter`'s own `op == "??"` arm and its throw-arm handling were the
only lowering, so an iterator body — which plans every value — declined `yield name ?? "d"`,
`yield name ?? throw e` and `yield flag ? v : throw e` (`node kind 12` / `node kind 13`).

- `ColumnarConditionalPlanner` now owns `??` as its THIRD shape (`IsNullCoalesceBinary`,
  `TryPlanNullCoalesce`), in the same three left-operand cases the emitter has: a reference left
  (`dup; brtrue end; pop; <fallback>`), a `Nullable<T>` left (park, `HasValue`, `GetValueOrDefault()`
  — the RESULT is the ELEMENT type) and a generic-parameter left (one `box` as a TEST, result stays
  `T`). The fallback takes the ONE argument-conversion owner's conversion to the merge type, and a
  `null` fallback is the one shape the nested value owner does not claim (it has no type of its own).
- `ColumnarThrowExpressionPlanner` owns kind 83. `throw` is a METHOD-BODY opcode, so a schema-v3
  expression fragment declines a throw arm and the legacy emitter arm still serves it there. The
  stack story is what makes a throw arm safe inside a branch-merge: `ValidateMethodBodyStack` merges
  no height into the row after a `throw`, so the merge label is reached only from the arm that still
  produces a value — and the `br` to it is written only when that arm falls through.
- ⚠ `ColumnarConditionalPlanner.MayPlanRoot` DELIBERATELY still refuses a `??` root. That gate is
  what the EMITTER's cascade asks; widening it would move a `??` root onto a schema-v3 fragment where
  `throw` is not an admissible opcode. The claim lives on the METHOD-BODY door
  (`ColumnarMethodBodyPlanner`'s kind-12 arm and `ColumnarRangeIndexPlanner`'s nested dispatcher),
  which reaches `TryAppendRoot` directly. The emitter's `??` arm therefore REMAINS, serving the
  bodies the plan door still declines; collapsing the two owners waits on the plan door claiming
  every body.

⚠ ITER4 ASKED WHETHER THE EMITTER'S `??` ARM CAN GO NOW, AND MEASURED THAT IT CANNOT. The REFERENCE
arm's lowering is `dup; brtrue; pop; <fallback>`, and `pop` is a METHOD-BODY opcode: a schema-v3
expression plan does not decline it, it THROWS ("The opcode does not use an operand-free row"). That
was a LATENT CRASH — reachable the moment a wider gate let a reference `??` reach a v3 fragment,
which is exactly what admitting `??` as a call argument did (two native projects died with that
message, not a decline). `TryPlanReferenceCoalesce` now asks `plan.IsMethodBodySchema()` and declines
in a v3 position, the same contract `ColumnarThrowExpressionPlanner` states for a `throw` arm. The
emitter's `??` arm stays, and stays until every body reaches the plan door.

### A source type's statics on the plan side (census ITER3)

`ColumnarExternalStaticMemberPlanner` answers a static that lives in a REFERENCED assembly; nothing
answered `Counter.Total` where `Counter` is declared in the same program, so an iterator body
declined it (`node kind 8`) while a plain body emitted through `ColumnarIlEmitter`'s own arm.
`ColumnarSourceStaticMemberPlanner` is the plan-side twin: it resolves the owner through
`ColumnarSourceMemberChainResolver` (a static belongs to the type that DECLARES it, so naming a
derived type binds the base's declaration), loads a field with `ldsfld`, a static property through
its getter, and a static int constant as its literal. `ColumnarStoreTargetPlanner` asks it BEFORE it
plans a receiver, because a static target has no receiver to evaluate.

⚠ A definition's `DeclaredTypeName` may carry its NAMESPACE while the source writes the simple name,
so the lookup matches a declared name it equals OR that ends with `.` + the written name — asked at
a dot boundary, so `Counter` never matches `RowCounter`. Matching only on equality is why the first
version of this owner resolved nothing at all.

### A value-typed `using` resource in a generator (census ITER3)

A struct resource lives in one of the machine's FIELDS, so releasing it means `ldflda` for the
address plus `constrained.` over it — a boxed `Dispose` would release a copy nobody can observe.
`ColumnarCodePlanContract.Constrained()` is the new row (0xFE 0x16, carried as the negative short
`-490` exactly as `rethrow` carries 0xFE 0x1A); it is a PREFIX, so its evaluation-stack delta is zero
and `MethodBodyStackDelta`'s `TypeOperand` fallback already states that. Kind 4 (a value type that
declares `Dispose` without the interface) has no slot to constrain to and takes a direct `call` over
the same address; neither shape takes a null guard, because a struct is never null.

⚠ AND THE DISPOSAL SHAPE IS DECIDED FROM THE DEFINITION, NOT FROM REFLECTION. The iterator passed
`null` for the `ColumnarStructDef`, so `ColumnarUsingResourcePlanner.Plan` asked an UNBAKED
`TypeBuilder` for its interfaces, got nothing, and reported no release shape at all — a disposable
source struct looked non-disposable. It now resolves the definition through
`ColumnarSourceDefinitionResolver.TryResolveStruct`, which is what the plain-body `using` has always
done.

### Branch-merge values as call arguments and receivers (census ITER4)

`ColumnarRangeIndexPlanner`'s value dispatcher has owned the ternary, `&&`/`||` and `??` in every
value position since the conditional planner landed, but the call owner's SYNTAX PREFLIGHT —
`ColumnarDirectCallPlanner.IsAdmittedValueSyntax`, the gate that types an argument or a receiver
before the call is claimed — took no `source`. Three of the four forms are kind-12 binaries separated
from arithmetic only by their operator TEXT, which lives in the source span, so the gate could not
see them and refused kind 13 outright. In an ordinary body that refusal was invisible (the call fell
back to the legacy emitter arm); inside a `func*` there is no legacy arm, so `list.Add(flag ? "a" :
"b")` declined the whole generator.

- The gate takes `source` now (threaded through `ColumnarConstructionPlanner`'s shape-only twin and
  `ColumnarPrimitiveBinaryPlanner.IsAdmittedOperandSyntax`) and asks one predicate,
  `ColumnarConditionalPlanner.IsBranchMergeValue` — deliberately WIDER than `MayPlanRoot`, which must
  keep refusing a `??` root.
- An OPERAND of a branch-merge is admitted through the wider CONSTRUCTION-value question, because
  that is the surface `TryPlanTernary`/`TryPlanShortCircuit`/`TryPlanNullCoalesce` actually append
  their operands through. Asking the narrow question refused `flag && count > 0 ? a : b` at the
  preflight while the append step would have planned it.
- A branch-merge argument types through `ColumnarConditionalPlanner.TryGetBranchMergeValueType`, a
  METHOD-BODY scratch, rather than `TryGetPlannableValueType`'s schema-v3 one — for the `pop` reason
  above. The type side runs the identical rows the append side will run.

### A yielded value parses at the LAMBDA level

`return` parsed its value with `ParseLambdaOrAssignmentExpressionNode` and `yield` parsed its own
with `ParseAssignmentExpressionNode`, so `yield () => v` was a PARSE failure of the whole function
(`parse.function`) — the one diagnostic that cannot say what it did not understand. `yield` now takes
the same level; the lambda level falls through to assignment for everything that is not a lambda.

## The `using` Resource: NL333 and a Read-Only Binding

`AnalyzerResourceStatements` is the driver for `try`, `using` and `lock`, and the `using` walk asks
TWO questions the other two do not.

**Is the resource releasable?** Either nominally — the type implements `IDisposable` — or
structurally: it declares a parameterless `Dispose` returning `void`. Neither is NL333, whose sentence
names both the TYPE and the INTERFACE, because the author can see only one of them on the line. An
`await using` asks the SAME shape about a DIFFERENT contract (`IAsyncDisposable` / `DisposeAsync`), so
the walk reads which contract to ask about off `UsingStatement.IsAsync` rather than threading it
through the recursion: every arm — the wrappers, the redirects, the structural test and the nominal
test — is one shape asked twice. The squiggle goes under the RESOURCE, not under the bound name: the
name is not the mistake, and for the `using x := e` spelling the declaration is anchored on the
`using` keyword anyway, so a caret at the name would underline the one token that is certainly right.

**Is the name still holding what the statement promised to release?** The resource binding is
READ-ONLY for as long as it is visible, and rebinding it reports NL309. The mark lives on the SCOPE
(`Scope.MarkReadOnly` / `AnalyzerScopeStack.IsReadOnlySymbol`) rather than in a walk-lifetime set,
because the region and the scope are the same thing: the block form marks the name in the scope the
statement opened, and a using DECLARATION marks it in the ENCLOSING block — so the mark expires
exactly when the guarantee does, with nothing to unwind. Writing THROUGH the resource is ordinary
mutation and is none of the rule's business.

**A using DECLARATION opens no scope.** Its guarded region is the rest of the enclosing block, which
is also where its binding belongs; a scope of its own would end at the statement and hide the name
from every line the declaration is supposed to cover. `AnalyzerStatementTermination` treats a `using`
BLOCK as terminating when its body terminates (the release runs on the way out and changes nothing
about whether control leaves) and a using DECLARATION as terminating nothing, because the statements
it guards are its siblings and the block walk measures those.

## One Exception-Resolution Path

`ColumnarCanonicalTypeResolver.TryResolveBclExceptionType` resolves a catch/throw type by ORDINARY CLR
name lookup — a qualified name through `Type.GetType`, a bare simple name through an index of the
runtime assembly's own exception types — admitting exactly what the CLR admits as a handler type
(derives from `System.Exception`). The two hand-maintained allowlists it replaced had drifted:
`System.ArrayTypeMismatchException` was in one and not the other, so the same program compiled or
declined depending on how its catch clause was spelled. `ColumnarTypeOfPlanner.TryResolveExceptionType`
now forwards. Source declarations still resolve first, so a user type that shares a BCL exception's
name wins.

Object initializers and member writes over a REFLECTED type (including an N#-compiled record in a
referenced assembly) likewise resolve by ordinary reflection: `ColumnarConstructionPlanner`'s runtime
member arm assigns a writable instance FIELD as well as a settable property, the three-type
`IsApprovedRuntimeObjectInitializerType` allowlist is gone, and `ColumnarIlEmitter`'s member-write
chain has a reflected-owner arm beside its source-definition one.

### `assert` narrows the surviving flow, and `[MaybeNullWhen]` is not part of a type

Two rules that only showed up once the substituted-parameter nullability rule and FLOW3's
postcondition owner were in the same tree:

- `[MaybeNullWhen(false)]` IS A POSTCONDITION, NOT A TYPE ANNOTATION, so
  `NullabilityGenericSubstitution.IsAnnotatedNullable` deliberately does not read it.
  `Dictionary<K, V>.TryGetValue` declares `out TValue value`, so with a `Dictionary<string, Entry>`
  receiver the parameter's TYPE is `Entry` and the false branch's maybe-null is the fact
  `AnalyzerNullabilityPostconditions` files against the call. Folding the attribute into the type
  makes BOTH branches maybe-null, because `AddFallbackBranchFact` gives the branch the attribute did
  NOT name the declared state — so `if map.TryGetValue(k, out found) { found.Label }` reported NL905
  in the branch the call had just proved. The reader answers the TYPE; the postcondition owner
  answers what the call LEAVES BEHIND, and `[MaybeNull]`, `[NotNull]` and `[NotNullWhen(b)]` are read
  the same way for the same reason.
- `assert cond` NARROWS EVERYTHING AFTER IT. An assert that fails throws, so the surviving flow is
  the condition's true branch — the guard clause `if !cond { throw }` written the other way round.
  `AnalyzerExpressionStatements`'s assert walk gained phase 16 and request kind 9 ("narrow by this
  condition having been true"), and `Analyzer.NarrowSurvivingFlow` installs
  `AnalyzerFlowNarrowing.ExtractFlowNarrowings(condition).Then` into the ENCLOSING scope. The
  extraction is the one every `if` uses, so `x != null`, `x is T y`, `&&` chains, parentheses, `!`
  and a call's own `[NotNullWhen]`/`[MaybeNullWhen]` postconditions all reach it without a second
  vocabulary, and the walk does not decide whether a condition is worth narrowing by.
  IT IS THE LAST PHASE, AFTER THE MESSAGE: the message is the expression evaluated when the assert
  FAILS, so narrowing before it would hand the failure path a fact only the success path has.

## What a Source Enum Inherits, and What a Conditional Is Worth

- AN ENUM VALUE'S INSTANCE SURFACE IS `System.Enum`, NOT `object`. The CLR gives every enum
  `System.Enum` as its base type, and `AnalyzerMemberResolution`'s enum arm asks that type through
  `TryResolveSourceEnumMember` (the same ordinary reflection walk `TryResolveSourceObjectMember`
  uses, over a different base). Asking `object` handed back `object.ToString()`'s `string?`, so
  `symbol.Kind.ToString().ToLower()` reported NL905 on a value that cannot be null, and `HasFlag`
  was NL303 "not found on type". Two owners carry the same fact for the argument side:
  `AnalyzerClrTypeConversion.TryConvertTypeInfoToClrTypeForBinding` gives a source enum the
  surrogate `System.Enum` rather than `object` (every other declared family keeps `object`, because
  nothing else has a CLR base the compiler can name before emission), and
  `AnalyzerAssignability.IsSubtypeOf` answers the enum's CLR base chain for a reflected target.
  On the emit side `ColumnarIlEmitter.TryEmitInstanceCall` dispatches an inherited `System.Enum`
  member by boxing the receiver and calling whatever ordinary CLR resolution over `typeof(Enum)`
  selects — no per-member table.
- THE COMMON TYPE OF A CONDITIONAL IS SEMANTIC IDENTITY, THE PROMOTION TABLE, AND THE NULLABLE LIFT.
  `AnalyzerOperatorExpressions.CommonType`'s non-numeric rule was reference identity alone, so two
  separately constructed answers for one type — an interpolated string beside a `string` — came back
  `unknown` and every use of the result reported against a type the conditional plainly had. It asks
  `TypeInfoIdentityFacts.AreEqual` now, and when the two arms differ only in nullability it answers
  the nullable one, which is C#'s rule and what the value can actually be.
- NULLABILITY IS ARRAY-COVARIANT FOR READS, IN ONE DIRECTION. `AnalyzerAssignability.IsImplicitReferenceConversion`
  peels a nullable annotation off the TARGET before the reference-type gate, so `T[]` converts to
  `T?[]` (the annotation is not a CLR type; the view is a no-op and every element read out of it is
  honestly typed `T?`) and `T?[]` still does not convert to `T[]`. This is the relation an `object[]`
  needs to reach `MethodInfo.Invoke`'s `object?[]?`.

## A Bare Identifier in Receiver Position, and Reachability From a Referenced Assembly (census 2026-09-13, EMIT4)

**Value or type name — one question, three owners.** A bare identifier in front of a `.` is either a
VALUE whose members are read or the TYPE NAME of a static member access, and three owners decide it:
`ColumnarFragmentBindings.IsValueBinding` (which `ColumnarDirectCallPlanner`'s `staticSyntax` test
reads), the emitter's own receiver arm in `ColumnarIlEmitter.TryEmitBclMethodCall`, and the preflight
type walk. Each of the three had a hole of its own:

- A **STATIC member of the enclosing type** answered no to all of them. `Entries.Add(name)`, inside
  the type declaring `static Entries: List<string>`, was read as a call on a TYPE named `Entries` and
  declined at `emit.expression-statement.call`, while the bare `Entries` read and
  `local := Entries` then `local.Add(name)` both emitted. `HasEnclosingStaticValue` is the static
  twin of `HasCurrentInstanceValue`, anchored on `EnclosingTypeDefinition` because a static member is
  in scope in every body the type owns, and both walk the declared base chain.
- **`this`** is the one bare identifier that can never be a type name, and it is in no binding map,
  so the emitter's receiver arm read `this.GetType()` as a static call on a type named `this`. It is
  excluded explicitly now. (A bare `this` is still claimed and rejected one tier earlier by
  `ColumnarBoundIdentifierPlanner`, which has no selection kind for the current instance, so
  `this.<member>` still declines where the member is not declared on the source chain.)

**Object's own members are every receiver's members.** `GetType`, `ToString`, `GetHashCode` and
`Equals(object)` are inherited by every type, including the ones the compilation is still building.
A source receiver is a `TypeBuilder`, which answers no member query, and `ColumnarInheritedExternalBase`
reports the implicit `System.Object` base as NO answer (it contributes nothing beyond object's own) —
so `thing.GetType().Name` declined while `(thing as object).GetType().Name` emitted. `TryEmitInstanceCall`
now asks ordinary scoped resolution of `typeof(object)` after the source and external-base tiers, and
boxes a source VALUE-type receiver first. `ColumnarDirectCallPlanner`'s inherited-external tier makes
the same correction on the implicit-/explicit-`this` side, where `ResolveExternalRuntimeBase` answered
null for a class with no `:` clause and the call was claimed and rejected — `this.GetType()` declined
while `(this as object).GetType()` emitted. A REFERENCE `this` is `ldarg.0` either way; a value `this`
is a managed pointer whose inherited dispatch needs a box, so a struct keeps the older answer. Bare
`GetType()` with no receiver at all is still NL412: the analyzer's bare-name resolution has the same
hole on its own side.

**Reachability attributes are read from both sides of the fence at EMIT too.** The diagnostics pass
already read a referenced assembly's `[DoesNotReturn]`/`[DoesNotReturnIf]`, so a statement after
`Environment.FailFast(...)` was NL312 unreachable — while `ColumnarIlEmitter`'s two readers
(`CallStatementNeverReturns`, `CallStatementParameterReachabilityFacts`) saw only source declarations.
A value function whose last statement was such a call therefore declined at `emit.body` for not
always-returning. `TryResolveExternalCallStatementMethod` resolves the reflected callee through the
same scoped resolution every other external call uses, and `ReachabilityFlowAttributeReflection` reads
the bits off it.

**Ordinary static resolution is the rule; the per-API table is a residual.** `TryEmitStaticCall` ends
in an ordinary-resolution arm over the owner the call named, so a static whose single declaration at
that arity accepts the written arguments needs no table entry (`Debug.Assert(x != null)` was
`emit.call.static-member-unmodeled`). The argument side needed one more fact: preflight could not type
a NULL COMPARISON, because typing both operands first fails on the null literal, so `x != null` could
not be scored as a `bool` argument while `x.Length > 0` could.

**A tuple literal has a preflight type, and a tuple over a source type has a constructor.** A closed
`ValueTuple` over a source type is a `TypeBuilderInstantiation` whose `GetConstructor` throws — the
same wall the tuple's FIELD read already walks around with `TypeBuilder.GetField` — so the literal arm
refused a builder-bound element outright and the typed-local arm reached the throw. Both go through
one `TryResolveValueTupleConstructor` now. Separately, a tuple literal had no preflight type at all,
so a lambda whose body is one had no inferable return type and `xs.Select(d => (d.Code, d.Line))`
declined at the extension call. Element NAMES still do not survive an `IGrouping.Key` hop
(`group.Key.Code` declines; `group.Key.Item1` emits) — that is the labelled-context gap, not this one.

## Import usage is a binding fact, and both import rules read it (census 2026-09-13, TOOL3)

`ImportUsageFacts` (`src/NSharpLang.Compiler.Model/ImportUsageFacts.nl`) is a per-file ledger the
analyzer stamps on the `CompilationUnit` it analyses. It records two things: every namespace some
written name resolved THROUGH, and, for a name that resolved to a METADATA type, which namespace
supplied it. The linter's two import rules are that one measurement read from two sides — an import
the ledger credits is used (NL010 quiet), and a name whose supplying namespace the file does not
import is NL002.

**The measurement is arithmetic on the resolved identity, not a lookup.** A written spelling `W` that
resolved to a type whose full name is `F` was supplied by `N` exactly when `F` is `N.W`, so the answer
is `F` with `"." + W` cut off its end (`AnalyzerImportUsageCredit.SupplyingNamespace`). Two metadata
spellings are normalised first — the arity suffix (``List`1``) and the nested separator
(`Outer+Inner`). Three consequences fall out rather than being coded: a FULLY QUALIFIED spelling
leaves no prefix and credits nothing, a PARTIALLY QUALIFIED one credits the import that supplied its
ROOT (`import System` + `Collections.Generic.List`), and an ALIAS-qualified one credits the namespace
it is an alias of after the root is expanded.

**This replaced two hand-written tables and both of their failure modes.** NL010 read a closed-world
list of the names each of ten namespaces provides (112 spellings for `System`) and NL002 a 25-name
whitelist. `import System` beside `OperatingSystem.IsWindows()` was reported UNUSED — an ERROR whose
`nlc fix` deletes the line — while the same file without the import was accepted in silence. A
namespace with no row was reported USED no matter what, so every dead import outside those ten rows,
a project's own namespace included, was invisible.

**Every channel a name can reach an import through credits it, and a channel that forgets is a false
NL010 that deletes working code.** The nine:

| channel | owner | what it credits |
| --- | --- | --- |
| a written type, anywhere a type may be written | `AnalyzerTypeResolver.ResolveSimpleTypeCore` | the resolved identity's prefix |
| a declared member's type | `AnalyzerDeclarationContext.ResolveTypeName` (current file only) | same |
| a bare static receiver (`Console.WriteLine`) | `AnalyzerIdentifierResolution` step 6 | same |
| a type-valued receiver (`Encoding.UTF8`) | `AnalyzerMemberAccess.TryResolveTypeValuedMemberAccess` | same |
| an attribute's bracket spelling | `AnalyzerAttributeValidator.CreditAttributeImport` | either of its two legal spellings |
| an extension method (`.Where(…)`) | `AnalyzerExtensionMethodResolution.ExternalExtensionMethodType` | the METHOD's declaring namespace |
| a delegate type (`Func<int, int>`) | `AnalyzerTypeResolver.CreditWrittenDelegateName` | the written name at the arity the reference writes |
| a project source type | `AnalyzerProjectTypeDiscovery.ResolveVisibleProjectType` | the namespace the sweep answered from |
| a name declared but not exported (NL308), an ambiguity (NL209), an import that does not resolve (NL704) | `AnalyzerDiagnosticSink`, `AnalyzerImports` | the namespace, so NL010 does not pile a second diagnostic on one mistake |

**A metadata type is the only NL002 finding, and a name the project declares is never one.** A source
type in another namespace of the same project resolves with no import at all, so it is credited but
never recorded as needing one. A receiver position resolves through the external probe BEFORE it
consults a sibling file's declarations, so a source `class Guard` beside a metadata `Guard` answers
with the metadata one — `AnalyzerDeclarationContext.DeclaresTypeNamed` is what keeps NL002 from
telling the author to import a namespace their program does not use.

**The ledger is per ANALYSIS, and the rules are gated on it.** `Analyze` replaces it and sets
`Analyzed` only on the path that walked every declaration. A file with no facts, or with partial
ones, reports NO namespace import — an import whose use cannot be proven has not been proven dead —
while NL010's FILE arm answers regardless, because it needs no binding. `MultiFileCompiler` therefore
analyses before it strict-lints, and `FixCommand` loads the project once and hands the analysed unit
to `FixApplicator`.

**The cost is two memoised metadata reads.** `Type.get_Namespace` and `get_FullName` are COMPUTED by
the MetadataLoadContext, and asking them per resolution measured ~60% on top of `nlc check`; they are
memoised against the `Type`, and the common case (an undotted spelling on a non-nested type) is one
`Namespace` read rather than the arithmetic.

## One type name in two files of one namespace is NL339 (census 2026-09-13, TOOL3/EMIT4)

A namespace's declaration scope is per FILE, so `class Widget` written in two files each declared into
an empty table and neither saw the other. Both were emitted: the probe's assembly carried TWO
`TypeDef` rows called `P2.Widget` — the metadata C# refuses as CS0101 — and a reference to the name
bound to whichever the loader reached first. `nlc check` said "no errors" and `nlc build` said "Build
successful".

`AnalyzerDeclarationContext.TryFindFirstDeclaringFile` is the evidence a per-file scope cannot hold:
every compiled file is registered there, and the walk answers with the ORDINAL-least full path that
declares the (namespace, arity-name) pair. The order is deliberately NOT the registration order —
`Reset` empties the owner before every file's analysis and re-adds the file being analysed FIRST, so
"the file registered first" is always the current one and every file would be its own first
declaration. `AnalyzerDeclarationPolicy.DeclareType` reports NL339 at the SECOND declaration, naming
the first's file and line; the first reports nothing, which is what keeps one collision from being
reported twice.

Different arities are different types (`Widget` and ``Widget`1``), different namespaces are different
scopes, and two declarations in ONE file are still NL306. A namespace-less project is one namespace:
two `class Shared` reachable through aliased file imports collide, because
`ColumnarBindingScopeFacts.ExactTypeNameForFile` gives a namespace-less type its bare name and the
assembly would carry both.

## A `throw` written as a value is NL340 unless something else can type it (census 2026-09-13, THROWEXPR)

`x ?? throw e`, `cond ? v : throw e` and `func F(): T => throw e` all TYPED correctly before this
slice — `AnalyzerPassThroughOperands.FinishThrow` has always answered `BuiltInTypes.Never`, and
`AnalyzerOperatorExpressions.NullCoalesceResult` has always read a `throw` on the right of `??` as
"the expression is worth the LEFT side, non-null". What was missing was on either side of the type
rule: the columnar backend declined all three forms (NL103), and a MISPLACED throw was complained
about by whatever it was handed to rather than named.

The placement rule is **NL340**, and it lives in the PARSER rather than here, because it is purely
positional: three callers publish the token index of the operand they are about to descend into and
the unary tier compares the cursor against it (see `memory/components/parser.md`). Nothing in the
analyzer decides placement, and nothing here had to change for it.

Two consequences worth knowing when reading analyzer output:

- A misplaced throw still reaches the analyzer as a real `ThrowExpression` typed `never`, so the
  operand tier's own complaint (`The '+' operator doesn't work with 'int' and 'never'`) still
  follows NL340 at the same position. NL340 sorts first and names the mistake; the second sentence
  is pre-existing `never`-operand behaviour and was deliberately left alone rather than special-cased
  across the seven operator report sites.
- `AnalyzerNullFlow.IsThrowFallback` unwraps parentheses when it looks for `x ?? (throw e)`. That
  spelling is now NL340 (C# refuses it too), so the unwrap is unreachable defence rather than a
  supported form; it is left in place because a flow fact that over-narrows on a rejected program
  changes nothing.
## A reference's `InternalsVisibleTo` grant (census 2026-09-13, IVT)

`Assembly.GetType` answers for INTERNAL types too, so the metadata probe once saw every internal type
of every reference (`System.TokenType` shadowed a source `TokenType`). Answering only for
`Type.IsVisible` fixed that and was HALF the rule: C# sees the internals of exactly those assemblies
that named this one in an `[assembly: InternalsVisibleTo(...)]`. The converted language-server test
project — assembly `Tests`, referencing the C# `LanguageServer.dll`, which grants `Tests` — was
NL301 x23 on `internal static class LspDiagnosticConverter`.

`InternalsVisibleToGrants` is the single owner of the rule.

* The attribute is read with `GetCustomAttributesData()`, the only reader a `MetadataLoadContext`
  supports (`IsDefined` and `GetCustomAttributes` throw there).
* The argument is an assembly DISPLAY name: only the simple name before the first comma is compared,
  and it is compared `OrdinalIgnoreCase`, because assembly simple names compare that way. A
  strong-name key after the comma is not part of the identity; a near miss (`Tests.Unit`, `Test`) is
  not a friend.
* The compiling name comes from `CompilationReferenceResolverKernels.GetProjectAssemblyName` — the
  project's `name:`, falling back to its directory — and is set in `Analyzer.LoadFromProjectConfig`,
  the one point where the config and the assembly list meet.
* An UNNAMED instance grants nothing. That is the behaviour a bare `new Analyzer()` and every
  unit-built owner keeps, so nothing that lacks a project changed.

TWO CARRIERS, ONE RULE. The analyzer HOLDS an instance and hands it to the owners that ask
(`AnalyzerExternalTypeProbe`, `AnalyzerMemberResolution`, `AnalyzerExtensionMethodResolution`,
`AnalyzerDeclarationContext` and through it `AnalyzerDeclarationPolicy`, `EditorTypeCatalog`). The
columnar back end cannot: its accessibility filters are static functions shared with planner unit
tests and code intelligence, so it reads `InternalsVisibleToEmissionScope`, a THREAD-LOCAL scope
opened by `MultiFileCompiler.RunColumnarEmissionOnCurrentThread` (the wide-stack emit thread) and
closed when that emission ends. An unopened scope grants nothing, exactly like an unnamed instance.

What each reader changed:

* nameability — `IsNameableType` is `Type.IsVisible` OR (granting assembly AND every level of the
  nesting chain is `public`/`assembly`/`FamORAssem`). `protected` and `private protected` are NOT
  admitted by a NAMING question: both need a derivation relation the question does not carry.
* the exported-name scan (`AnalyzerExternalTypeProbe.ResolveExternalType`, `EditorTypeCatalog`,
  `ExternalAssemblyScan.FindFirstVisibleType`, `ExternalQualifiedTypeResolver`) reads `GetTypes()`
  instead of `GetExportedTypes()` for a GRANTING assembly only, so an ordinary project's scan costs
  what it did before.
* member reach — `MemberAccessibility.IsAccessible`'s `sameAssembly` argument is the grant, asked of
  the member's OWN declaring type (a member inherited from a base in a third assembly is reachable
  only if THAT assembly granted this one). Every filter that widens its `BindingFlags` to
  `NonPublic` for a friend keeps the level test beside it.
* extension hosts — `ScanExternalExtensionMethods` already read DECLARED types so an extension on an
  `internal static class` would be found, which offered every reference's internal hosts to
  everybody. The host is now gated by `IsNameableType`, and an `internal` extension METHOD of a
  public host is admitted for a granting assembly.
* emission — reaching a friend's internal member emits the ORDINARY instruction; the CLR re-checks
  the grant at load. No filter was added to `ExternalAssemblyScan`'s TYPE lookup, and that was
  measured rather than assumed: gating `FindExactType`/`FindFirstVisibleType` on
  `InternalsVisibleToEmissionScope.CanNameType` compiled and passed the estate, then took SIX native
  projects down in the full sweep — `census-emit-shapes`, `qualified-names` and `tuple-names` to
  ZERO tests, and one test each in `census-import-usage`, `diagnostic-honesty` and `lsp-lifetime`.
  The back end's type lookup is reached by paths whose answers a nameability filter perturbs, and
  the shapes that broke (a tuple over a source type, a qualified name, a named tuple) say the
  perturbation is not about internals at all. The filter was reverted whole; see STILL OPEN.

### IVT2: the grants a project WRITES, the qualified spelling, and what the editor says (2026-09-19)

Three of the four items above are closed; the fourth (member-level completion) was closed at the
merge by `8f22c251c`.

**`project.yml` `internalsVisibleTo:` emits the attribute.** Each entry becomes an
`[assembly: InternalsVisibleTo("…")]` row on the produced assembly, written by
`ColumnarInternalsVisibleToEmitter` where the `PersistedAssemblyBuilder` is created — an
assembly-level attribute belongs to the assembly table and waits for no target, so it is not queued
with the source attributes. The stage-0 wall is gone: the republished seed compiles
`PersistedAssemblyBuilder.SetCustomAttribute(ConstructorInfo, byte[])` from Core's own source.

The declared grants travel to the back end **through `InternalsVisibleToEmissionScope`**, not
through `TryEmitColumnarAssembly`'s parameter list. That is not only tidiness: adding a defaulted
eighth parameter to that entry point made the SEED decline the six estate call sites that pass
seven arguments (`emit.statement.block-child`, node kind 61) and took `columnar-emit-facts` from
206 to 183. The scope already carries the identity of the assembly being emitted — its NAME decides
which references befriend it — and its own friend declarations are the other half of that identity,
opened and closed by the same owner (`MultiFileCompiler.RunColumnarEmissionOnCurrentThread`). A
planner test that emits with no scope open declares no grants and gets no attribute.

**What a grant EXPOSES out of an N# assembly, measured by reflection on an emitted dll:** a camelCase
— unexported — FUNCTION, METHOD **or TOP-LEVEL TYPE** is emitted as CLR `assembly`; a PascalCase one is
`public`; a NESTED type answers its own casing as `NestedAssembly`/`NestedPublic`, which it always did;
and every FIELD is `public` whatever its casing. So a grant admits the unexported types, functions and
methods, and adds nothing at a field.

**THE TYPE ROW CHANGED, AND IT USED TO BE THE ODD ONE OUT.** A top-level type was emitted CLR `public`
whatever its name, so "casing decides PACKAGE export, which the CLR knows nothing about" was true for
types alone while the rule reached metadata for every member, every free function and every NESTED
type. It no longer is: `ColumnarStructInput.TopLevelVisibilityFor` answers the same
`VisibilityConventions` question `NestedVisibilityFor` already answered, and
`ColumnarDeclarationPlanner`'s struct/interface/enum attribute composers plus the union arm in
`ColumnarIlEmitter` take its answer instead of a hard `Public`. So another ASSEMBLY can no longer name
a type its package never exported — which it silently could before, producing a dll the CLR would
refuse at load rather than a diagnostic.

The package rule itself is still not lifted by a grant: it is the compiler's, enforced in every
assembly, so a consumer in another namespace of the SAME assembly still cannot name an unexported name
(and an unexported FREE function of a referenced N# assembly is unreachable regardless of casing — a
separate gap, not this rule's). `website/docs/types.md` carries the table for readers, and
`tests/native/census-package-private-types` pins the per-kind metadata rows against their PascalCase
twins.

**The qualified spelling is refused where the simple one is, and the back end was left alone.** The
fix is in the ANALYZER, not in `ExternalAssemblyScan` — the six-project collateral above stands as
the evidence against the back-end filter. `AnalyzerExternalTypeProbe.DeclaresUnnameableFullName`
answers ONE narrow question: does a referenced assembly really declare this exact full name (walking
the `A.B.C` → `A.B+C` nested spellings) and is the friend rule the only reason it was rejected?
`AnalyzerTypeResolver`'s fall-through reports NL201 for a dotted name when that is true, and keeps
the pre-existing leniency for every other dotted miss — a name that resolves through no channel
because this compilation is not ALLOWED to spell it is not a name that might resolve elsewhere.
Measured before: a project named `NotTests` compiled
`new NSharpLang.LanguageServer.Handlers.SemanticTokenLocation(4, 5, "x")` and a parameter of that
type into a successful `NotTests.dll` the CLR refuses at load, with no diagnostic; `System.TokenType`
did the same. After: NL201 per written position, the same code and sentence the simple name gets,
while the same source under the granted name `Tests` still compiles, and a qualified PUBLIC type of
the same references is untouched.

**The editor says why a name resolves.** `HoverResult.Accessibility` carries the DECLARED level's
word (`internal`, `protected`, `protected internal`) for a metadata member, and nothing for a public
one; `CodeIntelligenceSignatureKernels.GetReflectedMemberAccessibility` reads it through
`MemberAccessibility` (a property's effective level is the wider of its accessors), so the editor's
word and a refusal's word are the same word. It is a separate optional key rather than a decoration
on `kind`, which editors switch on, so `schemaVersion` stays 1. Three surfaces move together:
`accessibility` in the JSON envelope, `Access:` in `--text`, `*Accessibility:*` in the language
server's markdown.

Contracts: `InternalsVisibleToGrants.tests.nl` (the rule, and the scope's open/closed answers, and
the grants the scope carries), `ColumnarInternalsVisibleToEmitter.tests.nl` (which spellings become
rows, the attribute, the pinned blob), `ProjectFileParser.tests.nl` (the key and its refusal) and
`tests/native/census-internals-visible-to` 27/27 (the end of it, RUN: the project is named `Tests`,
which `LanguageServer.csproj` and `Cli.csproj` both declare as a friend; `NotAFriend.tests.nl`
compiles the same source under five names and both spellings through `MultiFileCompiler`;
`SourceGrants.tests.nl` builds an N# library with `internalsVisibleTo:`, reads its metadata back,
compiles a named consumer and a stranger against it, and LOADS the consumer so the CLR performs its
own friend check; `GrantedEditorVisibility.tests.nl` hovers the granted member through
`CodeIntelligenceService`).

## A static member receiver is an ordinary call, and `typeof(void)` (census 2026-09-14, EMIT5)

**The emitter's runtime-call tier could not break a tie, so the ties became tables.** The
direct-call planner owns every external call whose receiver AND arguments it can type; a receiver
that is a STATIC MEMBER READ (`Encoding.UTF8`, `Holder.Text`) is one it yields, so those calls land
in `ColumnarIlEmitter`'s own runtime tier. That tier asked only
`ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity`, which refuses a name with two
declarations at the arity — so `Encoding.UTF8.GetString(bytes)` (`byte[]` beside
`ReadOnlySpan<byte>`) and `Holder.Text.IndexOf("a")` (`char` beside `string`) declined at
`emit.call.instance-member-unmodeled` / `emit.call.instance-member` while the SAME call through a
parameter or a local emitted. The declines were papered over downstream by hand-written per-API
arms, and one of them was WRONG: `string.IndexOf`'s table bound `IndexOf(char)` for a `string`
argument (declining the call) and `IndexOf(string, StringComparison)` for `IndexOf("a", 0)`, reading
a start index as a comparison mode.

`ColumnarIlEmitter.SelectOrdinaryRuntimeCall` is now the one selector for both the static and the
instance runtime tiers, in three tiers of its own:

1. `ResolveUniqueAtArity` — the only tier a site with a LAMBDA or `out` argument can reach.
2. `ResolveWithFacts` — the SAME scored resolver the direct-call planner uses, fed the argument types
   `TryGetPreflightExpressionType` can determine. A site that reaches it picks what the planner would
   have picked for the same arguments.
3. The admitted candidate set, filtered by emit-applicability. A COLLECTION EXPRESSION has no type
   until a parameter names its element type, so its preflight type is provisional (`[72, 105]` is
   `int[]`) and scoring it answers no — but `CanEmitOrdinaryRuntimeCallArguments` answers exactly the
   question the literal can answer, and `Encoding.UTF8.GetString([72, 105])` is left with one
   candidate. Two or more survivors is a real ambiguity and stays refused.

`ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity` is the new door for tier 3;
`ResolveUniqueAtArity` is now literally "that set, when it has exactly one member", so the admission
rule (accessibility, name, staticness, arity, excluded intrinsic shapes, unsupported resolved
signature, dispatchability) exists once. The `string.IndexOf` table arm is DELETED.

**An empty collection expression converts by its target alone.** `[]` carries no element, so the
pre-pass that types arguments before a candidate is chosen can only give it `unknown[]`; every later
element question then answered no and `sha.TransformFinalBlock([], 0, 0)` reported NL402 for a call
with exactly one overload. `AnalyzerReflectionArgumentBinder.TryScoreEmptyCollectionExpressionArgument`
states C# §12.6.4.4 directly — an empty collection expression is applicable at any
collection-expression target — on the COLLECTION rung (4), never the identity one, using the same
target gate `TryScoreCollectionExpressionArgument` uses. `AllElementsAreInRangeConstants` still
answers false for an empty literal: that rule is about what the WRITTEN elements convert to.

**`typeof` is the one type position that admits `void`.** `ColumnarBindingScopeFacts.TryResolveExplicitBuiltin`
deliberately binds seventeen built-in spellings and not `void`, because `void` is not a type a local
can hold, and that refusal stays. C# §12.8.18 permits `void` as the type argument of `typeof` and
nowhere else, so the admission is stated in `ColumnarTypeOfPlanner.TryResolveTarget` (ahead of the
binding-scope lookup, which can never bind a keyword) with `IsSupportedTypeOfTarget` beside
`IsSupportedType` for the preflight guard. The lowering is the ordinary `ldtoken`/`GetTypeFromHandle`
pair. The plan validator needed the matching split: `ColumnarCodePlanExecutor` validated EVERY
type-pool row as STORAGE, and a row read only by `ldtoken` names METADATA — `MetadataOnlyTypePoolRows`
marks those rows (no argument slot, no plan local, no non-`ldtoken` instruction references them) and
`ValidateMetadataReferenceType` keeps every other rule while dropping the void refusal.

**And the SOURCE static twin of the instance selector.** `ColumnarIlEmitter.TryEmitStaticCall` chose a
same-arity source overload with `TryFindStaticMethodOnChain`, which answers by NAME AND ARITY and takes
the first declaration it meets — the right answer for the existence readers (is this bare name a static
of the enclosing type; does the callee never return) and the wrong one for a CALL. The INSTANCE arm has
had the argument-aware selector all along (`TrySelectInstanceMethodOnDef`: unique by arity, else unique
by `CanDeclaredCallArgumentsMatch`), so `sink.Take([1, "b", null])` bound and `Sink.Accept([1, "b", null])`
declined at `emit.call.static-user-argument`. `TrySelectStaticMethodOnChain`/`TrySelectStaticMethodOnDef`
are that selector's exact static mirror, including its refusals: a level with arity matches answers for
the whole call, and two applicable candidates there is an ambiguity refused rather than guessed. This is
the limit `website/docs/types.md` recorded as "a collection expression whose elements have no common type
… declines at emission"; the bullet is removed.

**And a loop variable remembers where its value came from.** `ColumnarIlEmitter`'s labelled-context
walk gave a foreach variable the element's own WRITTEN type when `LabeledElementOfCollection` found
one, and nothing otherwise. `rows.GroupBy(r => r)` over a `List<(Code: string, Amount: int)>` yields
an `IGrouping<…>` — a type no written spelling in the chain names — so the search answered nothing,
the loop variable remembered nothing, and `group.Key.Code` declined while `group.Key.Item1` emitted.
The KEY, though, is the very tuple the collection's written type named. The foreach arm now falls back
to `LabeledContextOfCollection` (the factored "own written type ?? the binding's remembered context ??
the nearest receiver-chain link") into `_labeledContextByVariable`, exactly as a `:=` local already
does, and the ordinary member walk finds the element. Names whose ONLY source is a lambda's own tuple
LITERAL (`GroupBy(r => (Code: r.Code, Amount: r.Amount))`) still do not survive: nothing WRITTEN names
them, which is a different gap from this one.

**And a coalesce has a preflight type.** Deleting the `string.IndexOf` table exposed the reason it
existed: `ColumnarIlEmitter.TryGetPreflightBinaryExpressionType` typed both operands of a `??` and then
fell off the end, so `census.IndexOf("returnLifetime=" + (value ?? ""), StringComparison.Ordinal)` had
an untypable first argument and the table's emit-then-decide arm was the only thing that could bind it.
The emit arm has always known the rule — a REFERENCE left yields the left's own type, a `Nullable<T>`
left yields its ELEMENT — and the preflight now states the same one. A widening, a derived reference
and a `throw` right-hand side stay un-typed rather than guessed: those are the shapes the emit arm
decides WHILE emitting.

## `nameof` names something; it does not read it (census 2026-09-14, SELFHOST)

`nameof`'s target is walked by the ORDINARY expression walk — the answer has to know what the target
resolved to, and a second name binder for one keyword is how a compiler ends up with two that
disagree. But that walk's tail refuses, correctly, the shapes that are not VALUES: a bare method
group (NL411, "Method 'X' must be called or passed to a delegate") and a bare event. Inside `nameof`
those are exactly the shapes a developer means, and **192 of the compiler's own `nameof`s were that
diagnostic** — every NL411 the front door reported on `src/NSharpLang.Compiler.Core`.

`Analyzer.AnalyzeNameofTarget` opens the two existing ambient suppressions
(`EnterAllowUnboundCallableReference`, `EnterAllowEventReference`) for the target and nothing else,
the same way a call's own callee already opens them. The SoA row escape, the identifier-or-member
shape rule and every resolution diagnostic the target produces still report. Pinned by
`tests/native/self-host-front-door/NameofTargets.*`.

**Still open in `nameof`** (both reproduce standalone, both reported on Core's own source):
`nameof(ToString)` — a bare inherited member by simple name — is NL301 "Variable 'ToString' not
found"; and `nameof(JsonElement.ArrayEnumerator.Current)` is NL303, because a member access does not
resolve a NESTED TYPE segment. Neither is a `nameof` rule: they are simple-name and member-access
resolution gaps that `nameof` is simply the most common way to hit.

## A named argument names a parameter, and the backend places it (census 2026-09-14, NAMEDARGS)

`G(flag: true)` type-checked and then declined at `parse.function`: the ANALYZER had owned named
arguments for both source and reflected calls for a long time — `AnalyzerSyntheticCallBinder`
produces the argument-to-parameter map, and NL402 reports an unknown name, a parameter named twice
and a parameter left with nothing, each with its own sentence and fix-it — while the columnar backend
could not so much as parse the `name:` prefix outside a `new <type>(...)` argument list. Six sites in
the converted Language Server hit it, and converted C# hits it constantly (`new Foo(name: x)`,
`Log(message, exception: e)`, `Assert.Equal(expected: 1, actual: n)`).

**One placement rule, stated once and applied twice.** A NAMED argument binds to the parameter it
names, wherever it is written; a POSITIONAL argument fills the next parameter nothing has claimed
yet. That is `AnalyzerSyntheticCallBinder.BindFunctionArguments`, and it is deliberately what
`ColumnarNamedArgumentBinder.TryPlace` re-states for the backend — the backend never invents a
placement the front door rejected, and it declines rather than binding one the front door would not
have produced. The rule is more permissive than C# §12.6.2.2, which refuses a positional argument
after an out-of-position named one; N# admits it because the answer is unambiguous either way.

**The backend's whole job is a permutation.** Everything below the planner — overload scoring,
conversions, the argument walk, IL — reads argument `i` as parameter `i`, so the name is resolved
once, in `ColumnarDirectCallPlanner.TryAppendCall` and `ColumnarConstructionPlanner`, BEFORE argument
types are inferred. The candidate parameter-name lists come from the same registries the arms select
from (`ColumnarSiblingCallFacts.ParameterNames`, `ColumnarInstanceMethodDef`/`ColumnarStaticMethodDef`/
`ColumnarConstructorDef.ParamNames`, and `ParameterInfo.Name` for a reflected member) and never from a
second resolution of their own. A placement is accepted only when every candidate that admits the
written names agrees on it, so two same-arity overloads that both admit them and place them
differently decline instead of guessing. The five definition records had to start CARRYING the
parameter names: they were read once to stamp CLR metadata and dropped, and a `MethodBuilder` answers
no `GetParameters()` before its owner is baked.

**Evaluation order is the written order.** `Send(body: Build(), to: Lookup())` runs `Build()` first
because it is written first, even though `to` is the earlier parameter. When a placement MOVES an
argument, `ColumnarDirectCallPlanner.AppendReorderedArguments` evaluates along the written order into
plan locals and loads them in slot order; when the two orders agree — every call whose names were
written where the signature keeps them — nothing is spilled. A reordered `ref`/`out` argument spills
its managed address and reloads that same address in parameter order, so later argument evaluation
still observes and may mutate the caller's storage before the callee writes it.

**A verified in-position placement is flattened into the node table.** Once the names have been
checked against a real signature and found to name the parameters they were already written at, the
kind-60 wrappers carry nothing, so `ColumnarNamedArgumentBinder.FlattenPlacedArguments` removes them.
A call the planner then declines for some unrelated reason — a lambda argument, say — reaches the
residual emitter as the ordinary positional call it is. A placement that MOVES an argument is never
flattened: only the planner can emit the move, because only it spills the written order.

**Optional holes are filled by the caller.** A call such as `Opt(last: 9)` first places the written
argument, then supplies the declaration default for every unclaimed slot. Source free functions,
constructors, instance methods and static methods carry their default syntax beside their parameter
names; referenced methods read the equivalent constants from `ParameterInfo`. Supplied expressions
still run in written order before the final parameter-order load. Constructor-chain inputs retain
each written name beside its expression span, so `base(last: 9)` and `this(last: 9)` use the same
placement and optional-hole rules for source and reflected constructors.

Attribute syntax keeps the CLR's two concepts distinct: `name: value` names a constructor parameter,
while `Name = value` assigns a public mutable field or settable property in the custom-attribute row.
The analyzer and emitter carry the separator fact separately, so neither form silently falls through
to the other when a constructor parameter and member share a spelling.

Delegate invocation uses the parameter names declared by the selected delegate's real `Invoke`
metadata, including the framework `Func`/`Action` families at every CLR-supported arity and custom
delegates such as `Comparison<T>`. The framework fast path first proves the resolved generic
definition's CLR identity, so a source type that happens to be named `Func` or `Action` never acquires
those metadata names. Constructors carry source `ref`/`out` modifier facts beside their unbaked
builder identity; this lets a reordered sparse `out` initialize an unassigned local while the same
address passed to `ref` still obeys definite assignment.

An explicit generic sibling call applies its written type arguments before scoring the placed arguments.
`First<int>(second: 2, first: 40)` therefore uses the same spill-and-reload permutation as its
non-generic form, then emits the exact constructed method identity. That path also fills optional
holes, preserves reordered `ref`/`out` addresses, and handles a trailing `params` array in its direct,
omitted, expanded, and spread forms. A generic method on a generic source receiver substitutes the
declaring type's parameters and the method's parameters by their distinct live CLR identities; their
shared ordinal positions never stand in for identity. The same closed-signature argument binding is
used for source instance methods and static methods on constructed source types, including optional
and `params` parameters.

Signature help uses the same written names when it selects the highlighted parameter. Its N#
syntax owner lexes the document through the cursor, finds the innermost unmatched call, and counts
only top-level argument separators using the parser's generic-call lookahead. A completed nested
call, a multiline argument list, a comparison expression, a block lambda, or punctuation inside a
comment or string therefore cannot redirect the request or move the highlight. The language-server
handler only resolves the resulting call and renders the selected signature. Explicit generic
receiver spellings such as `Catalog.Box<int>.Map<string>(value: ...)` retain the complete receiver
for semantic value lookup. Source declaration lookup removes type arguments only after that lookup,
while preserving namespace and enclosing-type identity.

## An explicit interface implementation names its own slot (census 2026-09-23, D1)

`func IEnumerable.GetEnumerator(): IEnumerator { … }` inside a type body fills the interface's slot and
nothing else. It exists because `IEnumerable<T>` inherits the non-generic `IEnumerable` and their two
`GetEnumerator` slots differ **only in return type** — so an ordinary member fills one of them and
nothing else in the language could fill the other. Before this, no N# type could implement
`IEnumerable<T>` at all.

**THE DECLARED SPELLING IS THE MEMBER TABLE'S KEY, AND THAT IS THE WHOLE DESIGN.** Round 7 filed this
feature as expensive because `ColumnarStructDef.Methods` is keyed by the plain member name and "every
lookup in the backend, the analyzer's member binding, the completeness walk, the editor projections
and `nlc query` read that key". Keying the explicit member by its QUALIFIED spelling turns that from a
cost into the mechanism: an ordinary lookup for `GetEnumerator` does not find it, which is exactly the
reachability rule the feature is for, and no lookup had to learn a new rule to get it. Overload
resolution over the simple name is untouched, and an implicit `GetEnumerator` beside an explicit
`IEnumerable.GetEnumerator` is two keys rather than a collision.

**THREE STRINGS, AND THEY ARE NOT THE SAME STRING** (`ExplicitInterfaceMemberFacts`):

* the DECLARED spelling — `IEnumerable.GetEnumerator` — the member table's key and what hover,
  completion, rename, find-references, signature help and document symbols all show;
* the SIMPLE name — `GetEnumerator` — what the interface declares its slot under and what the slot
  match is made on; the qualification is the language's, not the interface's;
* the METADATA name — `System.Collections.IEnumerable.GetEnumerator` — what the CLR carries. It was
  MEASURED against the BCL's own assemblies rather than assumed: `List<T>` carries exactly that, and
  `Dictionary<TKey, TValue>` carries
  `System.Collections.Generic.ICollection<System.Collections.Generic.KeyValuePair<TKey,TValue>>.Add` —
  type arguments fully qualified, no space after the comma, a type PARAMETER by its bare name. A value
  member's accessor puts the prefix INSIDE the qualification (`…IList.get_Item`), which is also
  measured.

**THE COMPLETENESS WALK HAD TO BE TOLD.** It asks the method table for the interface's member under the
slot's own name, and the explicit member is deliberately not there — so without a second source of
truth every explicitly implemented interface read as unsatisfied. `ColumnarStructDef.ExplicitInterfaceSlots`
is that source: the declaration pass records the METADATA name of each slot it filled, and the three
walks that could fail (`ColumnarExternalInterfaceMethodResolver.InterfacesSatisfied`,
`ColumnarInterfaceRealization.RequiredInterfaceMembersSatisfied`,
`ColumnarClosedGenericMemberResolver.SourceInterfaceMembersSatisfied`) consult it **on the failure path
only**, so a type with no explicit implementations pays nothing. The analyzer's own supply set does the
same thing one level up: `AddDeclaredMemberNames` adds the SIMPLE half of a qualified name beside the
qualified one, so `NL325` does not fire on a correctly implemented interface.

**ONLY THE NAMED INTERFACE'S SLOTS ARE OFFERED**, and the qualifier is RESOLVED AS A TYPE rather than
matched as a string. `ColumnarExplicitInterfaceImplementation.TryResolveNamedInterface` runs the
qualifier through `ColumnarCanonicalTypeResolver` — the same resolver every annotation goes through, so
a closed generic's arguments resolve by the compilation's own rules, including arguments that are
SOURCE types — and compares the answer to the implements closure by TYPE IDENTITY. Feeding the whole
implements list to the target resolver would let `func IFoo.Ping()` fill `IBar`'s `Ping` slot too,
which is a different program from the one that was written.

**FIVE DIAGNOSTICS, AND THEY ARE ANALYZER DIAGNOSTICS RATHER THAN EMIT DECLINES.** The backend refuses
all five as well — it has to, because a MethodImpl row naming a method the type does not implement
emits an assembly the CLR rejects at LOAD — but a decline says "the columnar backend declined" at no
position. `AnalyzerExplicitInterfaceImplementation` owns the five because they share one input, the
written interface list resolved to its inherited closure: `NL345` (an interface this type does not
implement), `NL346` (a member the interface does not declare), `NL347` (one slot claimed twice),
`NL348` (a modifier word — accessibility, `static`, `virtual`, `override`, `abstract` or `sealed` — on a
member that is `private final virtual newslot` by construction), `NL349` (a generic interface named
without the arguments the implements list writes). `NL347` deliberately does NOT fire on two members of
the SAME name, because that is already `NL306`; what it catches is two DIFFERENT spellings of one slot
(`IPing.Ping` and `Sample.IPing.Ping`), which nothing else can see.

**WHAT THIS SLICE DOES NOT REACH, refused rather than mis-emitted:**

* a GENERIC interface METHOD (`func ILogger.Log<TState>(…)`). A generic slot's MethodImpl row is
  decided from the name and arity BEFORE the signature exists (`DeclaresGenericMethodSlot`), and that
  decision cannot be made from a qualified name. `emit.declaration.explicit-interface-generic`.
* an EXPLICIT EVENT. The grammar has no `add`/`remove` accessor syntax — a field-like event is
  `event Name: Delegate` — so there is no explicit spelling to give one.
* a `static` member, which occupies no virtual slot. `emit.declaration.explicit-interface-static`.

**THE NEXT DEFECT THIS FEATURE MADE REACHABLE, and it is a separate slice.** An EXTENSION-METHOD call
whose receiver is a SOURCE type — `bag.Count()`, `bag.Select(…)` — does not bind, while the static
spelling (`Enumerable.Count<string>(bag)`) does and is what the tests and the example use.
`ColumnarContextualExtensionInference.FindClosedImplementation` reads the receiver's interface list by
reflection, a `TypeBuilder` answers nothing before `CreateType`, and the source definition that DOES
know is not reachable from the extension resolver (`ColumnarExtensionMethodResolver.Resolve` takes only
types). `List<Row>` works because it is a builder-bound CONSTRUCTION and reaches its interfaces through
its generic DEFINITION; a non-generic source type has no definition to go through. It is the same
family as the wave-12 `OfType`/`Cast` finding and needs the registry threaded into the resolver, which
is its own pass.
