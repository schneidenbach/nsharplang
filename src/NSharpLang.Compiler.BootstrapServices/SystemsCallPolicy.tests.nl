namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A CALL TARGET IS, AND WHAT A LOCAL STILL OWES.
//
// This family names NO diagnostic code of its own — the only cut in the 018 arc that does not — and
// that is precisely why it needs the most direct pinning. Every predicate here is consumed as a
// PRECEDENCE ARM in one walk: a `true` means some later rule never runs, and the fall-through at the
// end of the chain is NSYS050, "unknown external call". So a table row lost here does not produce a
// wrong message, it produces an EXTRA message on a call that used to be understood, or removes one
// from a call that no longer is.
//
// FIVE THINGS THAT ARE EASY TO GET WRONG, ALL PINNED BELOW.
//
// (1) THE THREE TABLES ARE KEYED DIFFERENTLY ON PURPOSE. The disposable-type table is matched
// against the SIMPLE name of the erased type; the resource-factory table is matched against the WHOLE
// dotted target and lists both spellings by hand; the pool/dispatch/reflection tables match by
// substring or suffix because they describe a shape rather than an identity.
//
// (2) THE CONCURRENCY TABLES OVERLAP AND THE ORDER RESOLVES IT. Every SUPPORTED primitive also
// matches the UNSUPPORTED prefix test. The walk asks the specific question first; both contracts
// below state that overlap explicitly so nobody "fixes" it into an exclusive pair.
//
// (3) A LEDGER DISCHARGE IS NOT A CLASSIFICATION. `MarkResourceDisposedIfRecognized` answers TRUE
// only when the name it derived was actually on a ledger, and that `true` is what stops the call
// walk. An unknown `x.Dispose()` must answer false so the call carries on to the rest of the chain.
//
// (4) THE POOL RETURN MARKS BY ARGUMENT, THE DISPOSAL BY RECEIVER. They are different shapes of the
// same obligation and neither can be written in terms of the other.
//
// (5) THE DICTIONARY RULE IS THE ONLY ONE WITH STATE, AND ALL THREE OF ITS CONDITIONS ARE
// LOAD-BEARING: the suffix, a member-access receiver, and a REGISTERED receiver type whose erased
// simple name is exactly `Dictionary`.

func ScpArgs(): List<Argument> {
    return new List<Argument>()
}

func ScpIdentifier(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 4, 9)
}

func ScpMember(receiver: Expression, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(receiver, memberName, false, 4, 9)
}

func ScpDotted(receiverName: string, memberName: string): MemberAccessExpression {
    return ScpMember(ScpIdentifier(receiverName), memberName)
}

func ScpCall(callee: Expression): CallExpression {
    return new CallExpression(callee, ScpArgs(), null, 4, 9)
}

func ScpCallWith(callee: Expression, arguments: List<Argument>): CallExpression {
    return new CallExpression(callee, arguments, null, 4, 9)
}

func ScpPositional(value: Expression): Argument {
    return new Argument(null, value, ArgumentModifier.None)
}

func ScpNew(typeName: string): NewExpression {
    return new NewExpression(new SimpleTypeReference(typeName, 0, 0), ScpArgs(), null, 4, 9)
}

func ScpPoolLedger(names: List<string>): Dictionary<string, PoolRent> {
    ledger := new Dictionary<string, PoolRent>()
    for name in names {
        ledger[name] = new PoolRent(name, 4, 9)
    }

    return ledger
}

func ScpResourceLedger(names: List<string>): Dictionary<string, ResourceLocal> {
    ledger := new Dictionary<string, ResourceLocal>()
    for name in names {
        ledger[name] = new ResourceLocal(name, "FileStream", 4, 9)
    }

    return ledger
}

func ScpNames(first: string): List<string> {
    names := new List<string>()
    names.Add(first)
    return names
}

// ------------------------------------------------------------------ the static hot receivers

test "THE EIGHT STATIC RECEIVERS A HOT FUNCTION MAY READ WITHOUT A WARMUP FACT" {
    policy := new SystemsCallPolicy()
    assert policy.IsKnownStaticHotReceiver("BinaryPrimitives")
    assert policy.IsKnownStaticHotReceiver("MemoryMarshal")
    assert policy.IsKnownStaticHotReceiver("BitOperations")
    assert policy.IsKnownStaticHotReceiver("Math")
    assert policy.IsKnownStaticHotReceiver("MathF")
    assert policy.IsKnownStaticHotReceiver("Volatile")
    assert policy.IsKnownStaticHotReceiver("Interlocked")
    assert policy.IsKnownStaticHotReceiver("Thread")

    // The table is matched WHOLE and case-sensitively: a project's own `Maths` or `math` is a static
    // receiver the analyzer knows nothing about, and NSYS110 is the correct answer for it.
    assert !policy.IsKnownStaticHotReceiver("Maths")
    assert !policy.IsKnownStaticHotReceiver("math")
    assert !policy.IsKnownStaticHotReceiver("System.Math")
    assert !policy.IsKnownStaticHotReceiver("Registry")
}

// ------------------------------------------------------------------ concurrency

test "THE SIXTEEN CONCURRENCY PRIMITIVES V1 MODELS, IN BOTH SPELLINGS" {
    policy := new SystemsCallPolicy()
    assert policy.IsKnownConcurrencyPrimitive("Volatile.Read")
    assert policy.IsKnownConcurrencyPrimitive("Volatile.Write")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Volatile.Read")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Volatile.Write")
    assert policy.IsKnownConcurrencyPrimitive("Interlocked.Exchange")
    assert policy.IsKnownConcurrencyPrimitive("Interlocked.CompareExchange")
    assert policy.IsKnownConcurrencyPrimitive("Interlocked.Increment")
    assert policy.IsKnownConcurrencyPrimitive("Interlocked.Decrement")
    assert policy.IsKnownConcurrencyPrimitive("Interlocked.Add")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Interlocked.Exchange")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Interlocked.CompareExchange")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Interlocked.Increment")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Interlocked.Decrement")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Interlocked.Add")
    assert policy.IsKnownConcurrencyPrimitive("Thread.MemoryBarrier")
    assert policy.IsKnownConcurrencyPrimitive("System.Threading.Thread.MemoryBarrier")
}

test "A NEIGHBOURING MEMBER OF THE SAME TYPE IS NOT MODELLED, AND THAT IS THE WHOLE POINT" {
    policy := new SystemsCallPolicy()
    // `Interlocked.Read` and `Thread.Sleep` exist; v1 has no HotSummary semantics for them.
    assert !policy.IsKnownConcurrencyPrimitive("Interlocked.Read")
    assert !policy.IsKnownConcurrencyPrimitive("Thread.Sleep")
    assert !policy.IsKnownConcurrencyPrimitive("Volatile.ReadUnaligned")
    // Partial spellings match nothing: the table is exact, not a prefix.
    assert !policy.IsKnownConcurrencyPrimitive("Threading.Volatile.Read")
    assert !policy.IsKnownConcurrencyPrimitive("Volatile")
}

test "THE UNSUPPORTED TEST IS A PREFIX TEST AND IT SUBSUMES THE SUPPORTED TABLE" {
    policy := new SystemsCallPolicy()
    assert policy.IsUnsupportedConcurrencyPrimitive("Interlocked.Read")
    assert policy.IsUnsupportedConcurrencyPrimitive("System.Threading.Interlocked.Read")
    assert policy.IsUnsupportedConcurrencyPrimitive("Volatile.ReadUnaligned")
    assert policy.IsUnsupportedConcurrencyPrimitive("System.Threading.Volatile.ReadUnaligned")
    assert policy.IsUnsupportedConcurrencyPrimitive("Thread.Sleep")
    assert policy.IsUnsupportedConcurrencyPrimitive("System.Threading.Thread.Sleep")

    // THE OVERLAP, STATED: every supported primitive also matches here. The walk asks the supported
    // question FIRST and returns, so this arm only ever sees the rest. Making the pair exclusive
    // would be a behaviour change dressed as a cleanup.
    assert policy.IsKnownConcurrencyPrimitive("Volatile.Read")
    assert policy.IsUnsupportedConcurrencyPrimitive("Volatile.Read")

    // The trailing dot is required, so a type mentioned without a member is not a primitive call.
    assert !policy.IsUnsupportedConcurrencyPrimitive("Interlocked")
    assert !policy.IsUnsupportedConcurrencyPrimitive("MyInterlocked.Read")
    assert !policy.IsUnsupportedConcurrencyPrimitive("Math.Abs")
}

// ------------------------------------------------------------------ runtime dispatch

test "RUNTIME DISPATCH IS A SHAPE, MATCHED BY SUBSTRING AND BY SUFFIX" {
    policy := new SystemsCallPolicy()
    assert policy.IsRuntimeDispatchCall("System.Linq.Enumerable.Where")
    assert policy.IsRuntimeDispatchCall("rows.AsIEnumerable")
    assert policy.IsRuntimeDispatchCall("query.IQueryableProvider")
    assert policy.IsRuntimeDispatchCall("rows.GetEnumerator")
    assert policy.IsRuntimeDispatchCall("cursor.MoveNext")
    assert policy.IsRuntimeDispatchCall("handler.DynamicInvoke")

    // The suffix arms need the dot: a function of that bare name is a user's own.
    assert !policy.IsRuntimeDispatchCall("MoveNext")
    assert !policy.IsRuntimeDispatchCall("rows.MoveNextChunk")
    assert !policy.IsRuntimeDispatchCall("Linq.Where")
    assert !policy.IsRuntimeDispatchCall("compute")
}

// ------------------------------------------------------------------ pooling

test "A POOL CALL IS EITHER POOL TYPE BY NAME OR EITHER HALF OF THE RENT/RETURN PAIR" {
    policy := new SystemsCallPolicy()
    assert policy.IsPoolCall("ArrayPool<byte>.Shared.Rent")
    assert policy.IsPoolCall("System.Buffers.MemoryPool.Shared.Rent")
    assert policy.IsPoolCall("pool.Rent")
    assert policy.IsPoolCall("pool.Return")

    // Deliberately wide, and deliberately not wider: a `Reset` on a pool-shaped name is not pooling.
    assert !policy.IsPoolCall("pool.Reset")
    assert !policy.IsPoolCall("Rent")
    assert !policy.IsPoolCall("compute")
}

test "THE RENT HALF IS ONE RULE ASKED BY THREE PLACES" {
    policy := new SystemsCallPolicy()
    assert policy.IsPoolRentTarget("pool.Rent")
    assert policy.IsPoolRentTarget("ArrayPool<byte>.Shared.Rent")
    assert !policy.IsPoolRentTarget("pool.Return")
    assert !policy.IsPoolRentTarget("Rent")

    // An `ArrayPool` name alone is a pool call but NOT a rent — which is why the obligation rule
    // keeps both conjuncts.
    assert policy.IsPoolCall("ArrayPool.Create")
    assert !policy.IsPoolRentTarget("ArrayPool.Create")
}

test "A POOL OBLIGATION IS OPENED ONLY BY A DIRECT CALL TO THE RENT HALF OF A POOL" {
    policy := new SystemsCallPolicy()
    assert policy.IsPoolRentExpression(ScpCall(ScpDotted("pool", "Rent")))
    assert policy.IsPoolRentExpression(ScpCall(ScpMember(ScpDotted("ArrayPool", "Shared"), "Rent")))

    assert !policy.IsPoolRentExpression(ScpCall(ScpDotted("pool", "Return")))
    assert !policy.IsPoolRentExpression(ScpCall(ScpDotted("ArrayPool", "Create")))
    assert !policy.IsPoolRentExpression(ScpIdentifier("buffer"))
    assert !policy.IsPoolRentExpression(ScpDotted("pool", "Rent"))

    // A callee with no written name cannot open one either: the target is null before any table.
    unnamed: Expression = new IndexAccessExpression(ScpIdentifier("pools"), new IntLiteralExpression("0", 1, 1), false, 1, 1)
    assert !policy.IsPoolRentExpression(ScpCall(unnamed))
}

// ------------------------------------------------------------------ resources

test "THE FOURTEEN DISPOSABLE TYPES, MATCHED ON THE SIMPLE NAME" {
    policy := new SystemsCallPolicy()
    assert policy.IsKnownDisposableType("FileStream")
    assert policy.IsKnownDisposableType("StreamReader")
    assert policy.IsKnownDisposableType("StreamWriter")
    assert policy.IsKnownDisposableType("BinaryReader")
    assert policy.IsKnownDisposableType("BinaryWriter")
    assert policy.IsKnownDisposableType("TextReader")
    assert policy.IsKnownDisposableType("TextWriter")
    assert policy.IsKnownDisposableType("MemoryStream")
    assert policy.IsKnownDisposableType("Socket")
    assert policy.IsKnownDisposableType("TcpClient")
    assert policy.IsKnownDisposableType("UdpClient")
    assert policy.IsKnownDisposableType("HttpClient")
    assert policy.IsKnownDisposableType("SemaphoreSlim")
    assert policy.IsKnownDisposableType("CancellationTokenSource")

    // This table is asked with an ALREADY simplified name, so it holds no qualified rows.
    assert !policy.IsKnownDisposableType("System.IO.FileStream")
    assert !policy.IsKnownDisposableType("MyStream")
}

test "THE EIGHT RESOURCE FACTORIES, MATCHED ON THE WHOLE DOTTED TARGET" {
    policy := new SystemsCallPolicy()
    assert policy.IsKnownResourceFactory("File.Open")
    assert policy.IsKnownResourceFactory("File.OpenRead")
    assert policy.IsKnownResourceFactory("File.OpenWrite")
    assert policy.IsKnownResourceFactory("File.Create")
    assert policy.IsKnownResourceFactory("System.IO.File.Open")
    assert policy.IsKnownResourceFactory("System.IO.File.OpenRead")
    assert policy.IsKnownResourceFactory("System.IO.File.OpenWrite")
    assert policy.IsKnownResourceFactory("System.IO.File.Create")

    // THE ASYMMETRY, PINNED: this table is NOT simplified, which is why four factories need eight
    // rows and why a user's own `File` type in their own namespace is not the BCL's.
    assert !policy.IsKnownResourceFactory("MyApp.File.Open")
    assert !policy.IsKnownResourceFactory("Open")
    assert !policy.IsKnownResourceFactory("File.OpenText")
}

test "A RESOURCE OBLIGATION IS OPENED BY A DISPOSABLE CONSTRUCTION OR A KNOWN FACTORY, AND NAMES ITS KIND" {
    policy := new SystemsCallPolicy()
    assert policy.ResourceCreationKind(ScpNew("FileStream")) == "FileStream"
    assert policy.ResourceCreationKind(ScpCall(ScpDotted("File", "Open"))) == "File.Open"

    // The kind is what a developer reads inside the NSYS090 sentence, so the two arms deliberately
    // report different KINDS of thing: a type name and a factory target.
    assert policy.ResourceCreationKind(ScpNew("MemoryStream")) == "MemoryStream"
    assert policy.ResourceCreationKind(ScpCall(ScpMember(ScpDotted("System", "IO"), "File"))) == null
}

test "THE CONSTRUCTION ARM SIMPLIFIES AND ERASES; THE FACTORY ARM DOES NEITHER" {
    policy := new SystemsCallPolicy()
    // Qualified construction still matches, because the type name is simplified first.
    qualified: TypeReference = new SimpleTypeReference("System.IO.FileStream", 0, 0)
    assert policy.ResourceCreationKind(new NewExpression(qualified, ScpArgs(), null, 4, 9)) == "FileStream"

    // A generic disposable is matched by its CONSTRUCTOR, because the name is erased first.
    generics := new List<TypeReference>()
    generics.Add(new SimpleTypeReference("byte", 0, 0))
    generic: TypeReference = new GenericTypeReference("MemoryStream", generics, 0, 0)
    assert policy.ResourceCreationKind(new NewExpression(generic, ScpArgs(), null, 4, 9)) == "MemoryStream"

    // But the FACTORY arm keys on the raw target, so the qualified factory needs its own row.
    assert policy.ResourceCreationKind(ScpCall(ScpMember(ScpMember(ScpDotted("System", "IO"), "File"), "Open"))) == "System.IO.File.Open"
    assert policy.ResourceCreationKind(ScpCall(ScpMember(ScpDotted("MyApp", "File"), "Open"))) == null
}

test "THE ALLOC MARKER IS TRANSPARENT TO OWNERSHIP" {
    policy := new SystemsCallPolicy()
    // Spelling the allocation says something about the heap, not about who closes the handle.
    assert policy.ResourceCreationKind(new AllocExpression(ScpNew("FileStream"), 4, 9)) == "FileStream"
    assert policy.ResourceCreationKind(new AllocExpression(new AllocExpression(ScpNew("Socket"), 4, 9), 4, 9)) == "Socket"
    assert policy.ResourceCreationKind(new AllocExpression(ScpNew("Vector"), 4, 9)) == null
}

test "NOTHING ELSE OPENS A RESOURCE OBLIGATION" {
    policy := new SystemsCallPolicy()
    assert policy.ResourceCreationKind(ScpNew("Vector")) == null
    assert policy.ResourceCreationKind(ScpIdentifier("existing")) == null
    assert policy.ResourceCreationKind(ScpCall(ScpIdentifier("openFile"))) == null

    // A `new` with no written type — an array literal shape — reaches the arm and answers null
    // rather than throwing on the missing type.
    assert policy.ResourceCreationKind(new NewExpression(null, ScpArgs(), null, 4, 9)) == null
}

// ------------------------------------------------------------------ discharging the ledgers

test "THE THREE WRITTEN FORMS THAT DISCHARGE AN OBLIGATION, AND NOTHING ELSE" {
    policy := new SystemsCallPolicy()
    assert policy.DisposalTargetName(ScpIdentifier("handle")) == "handle"
    assert policy.DisposalTargetName(ScpCall(ScpDotted("handle", "Dispose"))) == "handle"
    assert policy.DisposalTargetName(ScpCall(ScpDotted("handle", "DisposeAsync"))) == "handle"
    assert policy.DisposalTargetName(ScpDotted("handle", "Dispose")) == "handle"
    assert policy.DisposalTargetName(ScpDotted("handle", "DisposeAsync")) == "handle"

    // A different member is not a disposal, and neither is a call through something unnamed.
    assert policy.DisposalTargetName(ScpCall(ScpDotted("handle", "Close"))) == null
    assert policy.DisposalTargetName(ScpDotted("handle", "Flush")) == null
    assert policy.DisposalTargetName(ScpCall(ScpIdentifier("dispose"))) == null
}

test "THE LEDGER IS KEYED BY LOCAL NAME, SO A DOTTED RECEIVER DISCHARGES NOTHING" {
    policy := new SystemsCallPolicy()
    // `owner.buffer.Dispose()` may well dispose something, but not a local this walk recorded, and
    // guessing would silence a real NSYS090.
    assert policy.DisposalTargetName(ScpCall(ScpMember(ScpDotted("owner", "buffer"), "Dispose"))) == null
    assert policy.DisposalTargetName(ScpMember(ScpDotted("owner", "buffer"), "Dispose")) == null
}

test "A DISCHARGE MARKS BOTH LEDGERS AND ANSWERS WHETHER THE NAME WAS ON EITHER" {
    policy := new SystemsCallPolicy()
    pool := ScpPoolLedger(ScpNames("buffer"))
    resources := ScpResourceLedger(ScpNames("handle"))

    assert !pool["buffer"].Returned
    assert !resources["handle"].Disposed

    assert policy.MarkResourceDisposedIfRecognized(ScpCall(ScpDotted("buffer", "Dispose")), pool, resources)
    assert pool["buffer"].Returned
    assert !resources["handle"].Disposed

    assert policy.MarkResourceDisposedIfRecognized(ScpIdentifier("handle"), pool, resources)
    assert resources["handle"].Disposed
}

test "ONE NAME ON BOTH LEDGERS DISCHARGES BOTH" {
    policy := new SystemsCallPolicy()
    pool := ScpPoolLedger(ScpNames("shared"))
    resources := ScpResourceLedger(ScpNames("shared"))

    assert policy.MarkResourceDisposedIfRecognized(ScpCall(ScpDotted("shared", "DisposeAsync")), pool, resources)
    assert pool["shared"].Returned
    assert resources["shared"].Disposed
}

test "AN UNRECOGNISED DISPOSE ANSWERS FALSE, AND THAT FALSE IS WHAT KEEPS THE CALL WALK GOING" {
    policy := new SystemsCallPolicy()
    pool := ScpPoolLedger(ScpNames("buffer"))
    resources := ScpResourceLedger(ScpNames("handle"))

    // A name on no ledger: the call is still classified by every later arm, and may still be
    // reported as an unknown external call.
    assert !policy.MarkResourceDisposedIfRecognized(ScpCall(ScpDotted("other", "Dispose")), pool, resources)
    // A shape that is not a disposal at all.
    assert !policy.MarkResourceDisposedIfRecognized(ScpCall(ScpDotted("buffer", "Close")), pool, resources)
    assert !pool["buffer"].Returned
    assert !resources["handle"].Disposed
}

test "A POOL RETURN MARKS EVERY IDENTIFIER ARGUMENT, NOT ITS RECEIVER" {
    policy := new SystemsCallPolicy()
    pool := ScpPoolLedger(ScpNames("first"))
    pool["second"] = new PoolRent("second", 4, 9)
    pool["pool"] = new PoolRent("pool", 4, 9)

    arguments := ScpArgs()
    arguments.Add(ScpPositional(ScpIdentifier("first")))
    arguments.Add(ScpPositional(ScpIdentifier("second")))
    arguments.Add(ScpPositional(ScpIdentifier("unknown")))
    arguments.Add(ScpPositional(new IntLiteralExpression("0", 1, 1)))

    policy.MarkPoolReturnIfRecognized(ScpCallWith(ScpDotted("pool", "Return"), arguments), pool)

    assert pool["first"].Returned
    assert pool["second"].Returned
    // The RECEIVER is not the buffer, so `pool` itself is untouched even though it is on the ledger.
    assert !pool["pool"].Returned
}

test "ONLY THE RETURN HALF DISCHARGES, AND ONLY WHEN THE CALLEE IS NAMED" {
    policy := new SystemsCallPolicy()
    pool := ScpPoolLedger(ScpNames("buffer"))
    arguments := ScpArgs()
    arguments.Add(ScpPositional(ScpIdentifier("buffer")))

    policy.MarkPoolReturnIfRecognized(ScpCallWith(ScpDotted("pool", "Rent"), arguments), pool)
    assert !pool["buffer"].Returned

    unnamed: Expression = new IndexAccessExpression(ScpIdentifier("pools"), new IntLiteralExpression("0", 1, 1), false, 1, 1)
    policy.MarkPoolReturnIfRecognized(ScpCallWith(unnamed, arguments), pool)
    assert !pool["buffer"].Returned

    policy.MarkPoolReturnIfRecognized(ScpCallWith(ScpDotted("pool", "Return"), arguments), pool)
    assert pool["buffer"].Returned
}

// ------------------------------------------------------------------ reflection and AOT

test "DYNAMIC CODE IS THE NARROW HALF AND IT IS SUBSUMED BY THE WIDE ONE" {
    policy := new SystemsCallPolicy()
    assert policy.IsDynamicCodeCall("Activator.CreateInstance")
    assert policy.IsDynamicCodeCall("System.Activator.CreateInstance")
    assert policy.IsDynamicCodeCall("method.CreateDelegate")
    assert policy.IsDynamicCodeCall("handler.DynamicInvoke")
    assert policy.IsDynamicCodeCall("open.MakeGenericType")
    assert policy.IsDynamicCodeCall("open.MakeGenericMethod")

    // Every one of them is also reflection: the summary sets both flags and the AOT verdict reads
    // the narrow one.
    assert policy.IsReflectionOrDynamicCall("Activator.CreateInstance")
    assert policy.IsReflectionOrDynamicCall("method.CreateDelegate")
    assert policy.IsReflectionOrDynamicCall("handler.DynamicInvoke")
    assert policy.IsReflectionOrDynamicCall("open.MakeGenericType")
    assert policy.IsReflectionOrDynamicCall("open.MakeGenericMethod")
}

test "THE READ-ONLY REFLECTION SURFACE IS REFLECTION AND IS NOT DYNAMIC CODE" {
    policy := new SystemsCallPolicy()
    assert policy.IsReflectionOrDynamicCall("value.GetType")
    assert policy.IsReflectionOrDynamicCall("type.GetMethod")
    assert policy.IsReflectionOrDynamicCall("type.GetMethods")
    assert policy.IsReflectionOrDynamicCall("type.GetProperty")
    assert policy.IsReflectionOrDynamicCall("member.GetCustomAttributes")

    assert !policy.IsDynamicCodeCall("value.GetType")
    assert !policy.IsDynamicCodeCall("type.GetMethod")
    assert !policy.IsDynamicCodeCall("member.GetCustomAttributes")

    // Neither half claims an ordinary call.
    assert !policy.IsReflectionOrDynamicCall("compute")
    assert !policy.IsReflectionOrDynamicCall("value.GetTypeCode")
    assert !policy.IsDynamicCodeCall("compute")
}

// ------------------------------------------------------------------ the two exact-match tables

test "THE ONE UNSAFE PRIMITIVE THE ANALYZER HAS FACTS FOR, IN BOTH SPELLINGS" {
    policy := new SystemsCallPolicy()
    assert policy.IsBufferMemoryCopyCall("Buffer.MemoryCopy")
    assert policy.IsBufferMemoryCopyCall("System.Buffer.MemoryCopy")
    assert !policy.IsBufferMemoryCopyCall("MemoryCopy")
    assert !policy.IsBufferMemoryCopyCall("Buffer.BlockCopy")
}

test "THE RESULT FACTORIES ARE BARE NAMES AND ARE CALLS TO NOBODY" {
    policy := new SystemsCallPolicy()
    assert policy.IsResultFactoryTarget("Ok")
    assert policy.IsResultFactoryTarget("Err")

    // A member called `Ok` on a real type IS a call and belongs in the call graph.
    assert !policy.IsResultFactoryTarget("Result.Ok")
    assert !policy.IsResultFactoryTarget("ok")
    assert !policy.IsResultFactoryTarget("Error")
}

// ------------------------------------------------------------------ the dictionary receiver rule

test "A REGISTERED DICTIONARY RECEIVER MAKES A TryGetValue A KNOWN CALL" {
    policy := new SystemsCallPolicy()
    policy.RegisterMemberType("Cache", "Entries", new SimpleTypeReference("Dictionary", 0, 0))

    call := ScpCall(ScpMember(ScpDotted("Cache", "Entries"), "TryGetValue"))
    assert policy.IsDictionaryTryGetValueCall(call, "Cache.Entries.TryGetValue")
}

test "THE RECEIVER TYPE IS ERASED AND SIMPLIFIED BEFORE IT IS COMPARED" {
    policy := new SystemsCallPolicy()
    generics := new List<TypeReference>()
    generics.Add(new SimpleTypeReference("string", 0, 0))
    generics.Add(new SimpleTypeReference("int", 0, 0))
    policy.RegisterMemberType("Cache", "Entries", new GenericTypeReference("System.Collections.Generic.Dictionary", generics, 0, 0))

    call := ScpCall(ScpMember(ScpDotted("Cache", "Entries"), "TryGetValue"))
    assert policy.IsDictionaryTryGetValueCall(call, "Cache.Entries.TryGetValue")
}

test "ALL THREE CONDITIONS ARE LOAD-BEARING" {
    policy := new SystemsCallPolicy()
    policy.RegisterMemberType("Cache", "Entries", new SimpleTypeReference("Dictionary", 0, 0))
    policy.RegisterMemberType("Cache", "Bag", new SimpleTypeReference("ConcurrentDictionary", 0, 0))
    receiver := ScpMember(ScpDotted("Cache", "Entries"), "TryGetValue")

    // (1) the suffix
    assert !policy.IsDictionaryTryGetValueCall(ScpCall(receiver), "Cache.Entries.TryGetValueOrDefault")
    // (2) a member-access callee — a bare `TryGetValue(...)` has no receiver to look up
    assert !policy.IsDictionaryTryGetValueCall(ScpCall(ScpIdentifier("TryGetValue")), "x.TryGetValue")
    // (3) a REGISTERED receiver whose erased simple name is exactly `Dictionary`
    assert !policy.IsDictionaryTryGetValueCall(ScpCall(ScpMember(ScpDotted("Cache", "Bag"), "TryGetValue")), "Cache.Bag.TryGetValue")
    assert !policy.IsDictionaryTryGetValueCall(ScpCall(ScpMember(ScpDotted("Cache", "Missing"), "TryGetValue")), "Cache.Missing.TryGetValue")
}

test "AN UNNAMED CONTAINER OR AN UNTYPED MEMBER REGISTERS NOTHING" {
    policy := new SystemsCallPolicy()
    policy.RegisterMemberType(null, "Entries", new SimpleTypeReference("Dictionary", 0, 0))
    policy.RegisterMemberType("Cache", "Entries", null)

    assert !policy.IsDictionaryTryGetValueCall(ScpCall(ScpMember(ScpDotted("Cache", "Entries"), "TryGetValue")), "Cache.Entries.TryGetValue")
}

test "THE TABLE IS CLEARED ONCE PER ANALYSIS" {
    policy := new SystemsCallPolicy()
    policy.RegisterMemberType("Cache", "Entries", new SimpleTypeReference("Dictionary", 0, 0))
    call := ScpCall(ScpMember(ScpDotted("Cache", "Entries"), "TryGetValue"))
    assert policy.IsDictionaryTryGetValueCall(call, "Cache.Entries.TryGetValue")

    policy.BeginAnalysis()
    assert !policy.IsDictionaryTryGetValueCall(call, "Cache.Entries.TryGetValue")
}
