# Static-field initializer emission ownership

Selected from clean/pushed `4269be784`: complete static-field initializer emission, including the
production `.cctor` driver and seven connected helpers: `TryEmitStaticFieldInitializerLoad`,
`TryEmitStaticFieldExpressionInitializerLoad`, `TryParseParameterlessStaticInitializerCall`,
`IsSimpleIdentifierText`, `TryEmitStaticFieldLiteralInitializerLoad`, `TryParseFloatingLiteralBody`
and `IsSupportedGenericExtensionReceiverChainText`. The last caller moves with the identifier
predicate so its C# Array.Exists decision callback disappears too.

The driver visits source definitions in declaration order, scans pending initializer rows by owner
identity, creates a type initializer only on the first matched row, emits each value then Stsfld, and
emits Ret after that owner’s rows. A failed value emission preserves earlier emitted work and stops
before later owners. The load owner resolves same-type static overloads in order before lazily
checking siblings. Literal handling preserves integer suffix/type rules, unchecked ulong conversion,
floating culture/separators/sign/narrowing, character decoding and string behavior. Parsing and
receiver-chain outputs retain their initial/failure states and original exception/read order.

Original state includes List<(ColumnarStructDef, FieldBuilder, Type, int, string)> pending rows and an
eight-field sibling signature dictionary. Compile the actual complete proposed source before
claiming a capability blocker. Necessary state moves with callers; no new C# projection helper,
adapter, decision callback, fallback or canonical test is permitted. Canonical assertions migrate
with their complete compiler behavior; native coverage is reused where it already proves the path.

Sol Max owns production and end-to-end assertion migration, Terra Max direct N# controls, Astra
reviews/integrates/ratchets/gates/pushes. Evidence:
`/private/tmp/nsharp-static-initializer-ownership-20260906/baseline.json`, immutable `baseline-cli`,
`emitter-before.cs`, `ratchet-before.json`. Prior fresh gate passed590 unit/7,849 canonical/52 native
projects/12 throughput/68 IL in448s. The selected area and full compiler goal remain open.
Broader branch initiatives stay in `tasks/BRANCH-BACKLOG.md`.
