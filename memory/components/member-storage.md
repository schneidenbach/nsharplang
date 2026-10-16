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
- A bare member cannot be `virtual`/`abstract`/`override` (NL311): in-assembly code reads the storage
  directly, which an override could never intercept. Virtual auto-properties (EF lazy-loading
  proxies) would need accessor-routed in-assembly access; that is a separate feature.

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
semantics, compound/step), `ColumnarSourceAttributeEmission.tests.nl` (row-for-row shape),
`census-source-attributes` (attribute routing).
