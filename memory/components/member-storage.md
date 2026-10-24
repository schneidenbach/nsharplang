# Member storage: when a bare `Name: T` is a property and when it is a field

**Decided 2026-10-15 (issue schneidenbach/nsharplang#197).** The owner chose to make the language
emit auto-properties, not to document fields, because EF Core, System.Text.Json and ASP.NET model
binding all read properties and none of them see a field by default.

User-facing statement: `website/docs/types.md` → "Fields and properties".

## The rule

A bare value member `Name: T` (with or without `= initializer`, with or without `required`) is a
**get/set auto-property** — C#'s `public T Name { get; set; }` — when all of these hold:

1. it is declared in a **reference** `class` or `record` (not `struct`, `record struct`, `ref struct`,
   union case, soa record, newtype, interface);
2. it is an **instance** member;
3. it is not `readonly`, `const` or an `event`;
4. it is **exported**: PascalCase with no visibility word, or written `public`/`protected`/`internal`
   (`private protected` counts; plain `private` does not).

Everything else stays a field. `init Name: T` is always a property (`{ get; init; }`, unchanged). A
primary-constructor parameter declares a member of its own name that follows the same rule, so
`record Person(Name: string)` declares a property and `class Service(logger: ILogger)` a field.

**One owner:** `MemberStorageRules` (`src/NSharpLang.Compiler.Model/MemberStorageRules.nl`). The
analyzer's member model (`NominalTypeInfoFactory.CreateDeclaredMemberInfo` → `Kind = Property`,
`HasSetter`, `IsAutoProperty`), the emitter's field rows (`ColumnarDeclarationPlanner.FieldIsAutoPropertyAt`
→ `ColumnarFieldRows.FieldIsAutoProperty`), the attribute validator, hover, document symbols and the
editor symbol table all ask it. Never re-derive the rule at a call site.

## Why each exclusion

- **Structs stay fields.** A struct is a storage layout first: `[StructLayout]`, P/Invoke, `ldflda`
  through `holder.Inner.X`, and mutating struct methods all need fields. C#'s own precedent
  (`System.Numerics.Vector3`, `ValueTuple`) is public fields. A struct that needs a property writes
  `init` or explicit accessors.
- **Statics stay fields.** `[ThreadStatic]` exists only on fields, `Interlocked.Increment(ref Count)` /
  `Volatile` / `LazyInitializer.EnsureInitialized(ref …)` need an address, and no serializer, ORM or
  binder reads statics.
- **`readonly` / `const` stay fields.** Both are CLR field words (`initonly`, literal); the author
  spelled a storage modifier.
- **camelCase / `private` stay fields.** That is the type's own storage — C#'s `private int _stock;`
  behind a full property, as in the types.md `Product` example.
- **Union payloads stay fields.** A case is a pattern-matched value whose payload the case constructor
  sets; the documented CLR shape is fields. (Revisit only as its own decision.)
- **Compiler-synthesized fields** (closure displays, state machines, event backing fields) are not
  `ColumnarStructInput` field rows and never reach the rule.

## Emission shape (`ColumnarAutoPropertyEmitter`)

C#'s rows: `<Name>k__BackingField` with `[CompilerGenerated]` and `[DebuggerBrowsable(Never)]`,
`get_Name`/`set_Name` with `[CompilerGenerated]`, a `PropertyInfo` row carrying nullability, tuple
names and the member's attributes. One deliberate difference: a get/set property's backing field is
**`assembly`**, not `private`, and it is registered in `ColumnarStructDef.Fields` under the
**member's own name** (the property fact is in `SettableAutoProperties`, never also in `Properties` —
`ColumnarInstanceMemberPlanner` refuses a name declared twice). So every in-assembly body — field
initializers and primary-constructor stores that run before the base constructor (where a setter
call would be unverifiable), methods, closures on `Program`, object initializers, `with`, record
equality, `+=`, `++` — keeps emitting `ldfld`/`stfld` on the storage, which is also the perf answer
(no accessor call in Debug/tier-0). Only other assemblies go through the accessors. The `init` shape
keeps C#'s `private` backing field registered under `<Name>k__BackingField`.

## Semantics that change because a property is a value

- `ref`/`out` of an auto-property (bare `Count`, `this.Count`, `obj.Count`) is refused:
  `'Count' is a property, so it has no storage to pass as the 'ref' argument` (NL103, with a repair
  naming camelCase/`private`/`static` storage). `AnalyzerWriteTargets.NamesCurrentTypeProperty` covers
  bare names, which previously were always "addressable".
- NL322 applies to writes through a struct-typed auto-property (`holder.Pos.X = 1`), as C#'s CS1612.
- A mutating call on a struct-typed auto-property (`holder.Counter.Bump()`) mutates a **copy**, in
  this assembly as in any other: `ColumnarAutoPropertyEmitter.IsBackingField` makes the storage
  non-addressable in `ColumnarBoundIdentifierPlanner.TryGetReceiverType` and
  `ColumnarInstanceMemberPlanner.TryAppendAddressableValueReceiver`.
- `virtual`/`abstract`/`override` make an auto-property a SLOT, and then in-assembly code may no
  longer read the storage — see "Dispatched auto-properties" below.

## Dispatched auto-properties (`virtual` / `abstract` / `override` / `sealed override`)

**Added 2026-10-16** for EF Core lazy-loading proxies, which subclass entities at run time and require
virtual navigations. C#'s shapes: `public virtual|abstract|override|sealed override T Name { get; set; }`.

- **Analyzer** (`AnalyzerTypeDeclarations.ValidateFieldInheritanceModifiers`): the words are accepted
  exactly when `MemberStorageRules` makes the member an auto-property and it is not `init` (an init
  property's in-type writes store the field, which an override could not intercept — refused, a
  possible later feature). Every field shape gets its own NL311 sentence (`ReportFieldWithNoSlot`).
  `abstract` needs an abstract class and no initializer; a record class may declare `virtual` (its
  CLR type is unsealed, so proxies can override) but not `abstract`; `override` needs a base property
  with a setter (`ClassifyOverridePropertySetter`, C#'s CS0546); `sealed` needs `override`. A bare
  auto-property counts as a property for NL324 (`CollectDeclaredMemberNames`).
- **Emitter** (`ColumnarAutoPropertyEmitter.Define`, inheritance kind 1–4): the storage is C#'s
  `private` field registered ONLY under `<Name>k__BackingField` (plus `AutoPropertyBackingFields`),
  and the member is in `Properties` like a written property — never in `Fields` under its name. So
  every in-assembly read, write, `+=`, `++` (`TryEmitCurrentInstancePropertyStep`), closure
  (`BodyReferencesEnclosingChain` now counts properties), object initializer and `with`
  (`ColumnarRecordWithPlan.Setters`) goes through `callvirt`. The ONE direct store is the member's
  own initializer in the synthesized initializer body (`TryFindOwnAutoPropertyBackingField`), which
  runs before the base constructor, as C#'s does. Record equality compares the backing field. An
  abstract property has no field. `override` proves its base slot first
  (`ColumnarPropertyOverrideMatch`: getter AND setter virtual, not final, same type) and adopts the
  slot's accessibility when no word is written; the shadowing pass (`IsOverridingPropertySlot`) and
  the member planner (`ReusesSlot`) treat an override as the same member, not a shadow.
- `sealed` reaches the emitter as field-word bit 14 (`FieldSealedFlags`).

- **Override definition order.** An `override` bare member is only RECORDED in PASS 0a''' (its
  backing-field name keeps its place in the field order; `ColumnarDeferredOverrideAutoProperty`) and
  is defined in the second sweep of PASS 0b', base types first (`BaseFirstStructOrder` over chain
  depth), together with written `override` properties. So a bare override over a written `virtual`
  property works, and neither kind depends on source order (a subclass declared before its base used
  to decline `emit.declaration.override-target`).

## Written-accessor properties (`virtual` / `override` / `sealed override`)

**Added 2026-10-18.** A property written with accessors (`Text: T => …`, `{ get … set … }`) honours the
inheritance words on each accessor it declares — before this, they were accepted by the analyzer and
dropped by emission, so `override Message: string => …` on an exception compiled but did not dispatch.

- **Parse/plan:** the property row's prefix word carries bits 5–8 (`virtual`, `abstract`, `override`,
  `sealed`) and 9–12 (`public`, `private`, `internal`, `protected`)
  (`ParseDeclarationMemberPropertyModifierBits`, `ColumnarStructPropertyFlagModifiers`), surfacing as
  `ColumnarPropertyInput.ModifierFlags` in the `Modifiers` bit space.
  `ColumnarDeclarationPlanner.InstanceAccessorAttributes(modifierFlags)`: Virtual|NewSlot, Virtual
  (override), Virtual|Final (sealed override).
- **Emitter:** override properties are the second sweep of PASS 0b' (above). `ColumnarPropertyOverrideMatch`
  takes `overridesSetter`: a get-only override needs only the getter slot, and the setter walk steps
  past an intermediate get-only override. A get-only override in a concrete type over an ABSTRACT
  setter declines (the CLR would refuse to load it). Accessibility: the written word, else the slot's.
  A `virtual`/`override` getter that fills an interface slot keeps its own word (no Final).
- **Analyzer** (`ValidatePropertyInheritanceModifiers`): NL311 for `sealed` without `override`, a
  static property, an interface's, a struct/record struct/union's, `virtual` in a sealed class, and a
  `set` over a get-only base (CS0546). NL324 names `Name.set` when a concrete class's get-only override
  leaves an abstract setter (`CollectAbstractSettersLeftOpen`). `abstract` stays NL311 (bodies).
- **Accessibility (2026-10-23):** `InstanceAccessorAttributes(name, flags)` /
  `StaticAccessorAttributes(name, flags)` use `MethodVisibilityAttributes` — the written word, else the
  casing (camelCase = assembly). An `override` with no word still adopts the slot's. A non-public getter
  (written or bare) that fills an interface value slot gets a MethodImpl row
  (`ColumnarExplicitInterfaceImplementation.DefineNonPublicValueSlotFills`), as a non-public `func`
  does; the CLR binds implicit implementations by name only when public.
- **Inherited setter:** a get-only written override whose overridden property has a setter is NOT put
  in `def.Properties` (`ColumnarPropertyOverrideMatch.InheritsSetter`): every read and write binds to
  the overridden declaration, and `callvirt` on its getter reaches the override (C# binds to the
  original virtual the same way). A CLR base's property is written through a source receiver by its
  public setter (`ColumnarIlEmitter` member-write path). Analyzer: `TryIsReadOnlyPropertyMember` and
  the reflected walk step past a get-only override (`OverridesInheritedGetter`).
- **Known gap, separate:** writing an inherited written property through a subclass of a CLOSED
  GENERIC source base (`class P: Holder<int>`, `p.Value = 5`) declines in emission
  (`emit.statement.block-child`), override or not; so does `h: Holder<int> = new P()` as a typed local.

## Emitter support added alongside

Because cross-assembly consumers of an N# library now reach these members through accessors:
compound assignment and `++`/`--` on reflected properties and on source explicit properties
(`TryEmitPropertyReadModifyWrite`), and `Count += n` / `this.Count += n` on the current instance
(`TryEmitCurrentInstanceCompound`, which also closed a pre-existing gap for plain fields).

## Attribute placement

N# has no `[field:]`/`[property:]` prefix, so `[AttributeUsage]` decides
(`ColumnarSourceAttributeQueue.QueueAutoProperty`, `AnalyzerAttributeUsageFacts.AutoPropertyDeclarationTargets`):
property when allowed, else the backing field (e.g. `[NonSerialized]`). A positional parameter:
parameter when allowed, else property, else backing field.

## Self-hosting note

The compiler's own assemblies are built by the pinned stage-0 seed, so their own PascalCase members
stay fields until the next reseed. On reseed expect: AST-JSON key order (sorted by metadata token)
and incremental-build stamps to change once, and any C# consumer of the self-compiled assemblies to
see properties. Build every C# consumer (`Cli`, `Build.Tasks`, `LanguageServer`, `Playground`)
against the new seed before believing it.

Tests: `tests/native/auto-properties` (rule, metadata, STJ, EF Core `DbSet` population, copy
semantics, compound/step; `VirtualAutoProperties.tests.nl`: dispatch and real EF Core lazy-loading
proxies), `ColumnarSourceAttributeEmission.tests.nl` (row-for-row shape),
`census-source-attributes` (attribute routing).
