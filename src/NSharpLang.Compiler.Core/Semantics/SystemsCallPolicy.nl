namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT A CALL TARGET IS, AND WHAT A LOCAL STILL OWES.
//
// Every call a systems function makes is put to this owner before the walk decides what to say about
// it, and the ORDER the walk asks in is a precedence, not a list of independent tests: a recognised
// dispose answers before a concurrency primitive, which answers before runtime dispatch, which
// answers before pooling, and anything none of them claims falls through to the unknown-external-call
// report. So a predicate here does not merely classify — a `true` it returns is a diagnostic another
// rule will now never emit, and a `false` is an NSYS050 a developer will read.
//
// THE TABLES ARE WRITTEN NAMES, DELIBERATELY, AND THEY ARE NOT KEYED ALIKE. No TABLE here consults a
// semantic model or a loaded assembly: a systems policy whose CLASSIFICATION depended on whether a
// reference resolved would report different things on two machines. (The two LEDGER DISCHARGES are
// the exception and they are not classifications — see the discharge paragraph below.) What each
// table keys ON differs, and the difference is the rule:
//   * the CONCURRENCY tables and the RESOURCE FACTORY table list both the bare and the
//     namespace-qualified spelling (`Volatile.Read` AND `System.Threading.Volatile.Read`,
//     `File.Open` AND `System.IO.File.Open`), so a project that imported the namespace and one that
//     did not classify the same — and a user's OWN `MyApp.File.Open` matches neither, which is
//     correct, because it is not that factory;
//   * the DISPOSABLE TYPE table is matched against the SIMPLE name of the erased type, so
//     `System.IO.FileStream` and `FileStream` are one entry rather than two;
//   * the POOL, DISPATCH and REFLECTION tables match by SUBSTRING or SUFFIX, because they are about
//     a SHAPE of call rather than an identity: anything ending `.Rent` is a rent, anything containing
//     `IEnumerable` dispatches at runtime, anything ending `.GetType` is reflection.
// All three keyings are ORDINAL. `StartsWith`/`EndsWith` default to culture-sensitive comparison in
// .NET, which is a different function on some inputs, so every one of them names `Ordinal` here the
// way the C# original did.
//
// THE UNSUPPORTED-CONCURRENCY TABLE IS THE KNOWN ONE'S COMPLEMENT AND IS ASKED SECOND. Every name
// `IsKnownConcurrencyPrimitive` accepts also starts with a prefix `IsUnsupportedConcurrencyPrimitive`
// accepts; the walk asks the specific question first, so the broad one only ever sees the members of
// those three types that v1 has no HotSummary semantics for.
//
// WHAT A LOCAL STILL OWES IS A LEDGER, AND THIS OWNER DISCHARGES IT. A `Rent()` bound to a local and
// a disposable created in one both open an obligation that the walk records in the function summary;
// `MarkResourceDisposedIfRecognized` and `MarkPoolReturnIfRecognized` are the only two places that
// close one. The ledgers stay on the analyzer's own summary — the balance checks that later report
// NSYS090 and NSYS130 read them too, so they are not this family's to keep — and they are handed in
// as arguments, exactly the way the stackalloc escape rule takes the set of stackalloc-backed locals.
// The entries themselves are already N# (`PoolRent`, `ResourceLocal`), so closing an obligation is a
// field write here rather than a hand-back to C#.
//
// A DISPOSE IS RECOGNISED BY SHAPE AND ONLY THEN BY NAME, AND `recognized` MEANS "THIS NAME WAS ON A
// LEDGER". `using (x)` hands in a bare identifier; `x.Dispose()` and `x.DisposeAsync()` hand in a
// call; a bare `x.Dispose` member access reaches it too. A name that is on NEITHER ledger answers
// false, and that false is what lets the call walk carry on and classify the call some other way.
//
// A DISCHARGE IS THE ONE ANSWER HERE THAT A WRITTEN NAME MAY NOT DECIDE ALONE, AND THE MEASUREMENT
// SAYS WHY. A discharge is not a classification: it ASSERTS that an obligation opened earlier in the
// function is closed, and it STOPS the call walk, so the same call is never reported as an unknown
// external one either. Decided by the member NAME alone it inverted — the only `Dispose()` the
// resource rule accepted was one that DOES NOT EXIST. Both halves were measured on the shipped CLI:
// `stream.Dispose()` on a project class with no members reported `NL303: Member 'Dispose' not found`
// and NO NSYS090 and NO NSYS050, while the same source with `func Dispose()` actually declared
// reported NSYS090 "is not disposed" and nothing else — a false negative on broken source and a
// false POSITIVE on correct source, from one rule. So the two discharge doors now take the
// analyzer's own verdict, and `MarkDeclaredCalleeDischarges` is the door the RESOLVED half of the
// walk uses. See `MemberIsPositivelyRejected` for what "the analyzer's own verdict" is allowed to
// mean, which is deliberately narrow.
//
// ONE CLASSIFICATION NEEDS A TABLE THE DECLARATION WALK FILLS, AND IT IS THE ONLY STATE HERE. A
// `.TryGetValue` is only a dictionary probe when its RECEIVER is a dictionary, and the analyzer knows
// that from the fields and properties it registered, keyed `Type.Member` by the erased type name. The
// table is registered as the walk meets each declaration, cleared once per analysis, and read by that
// one rule — nobody else touches it, which is why it belongs here rather than on the analyzer.
class SystemsCallPolicy {
    memberTypeNamesValue: Dictionary<string, string>

    constructor() {
        memberTypeNamesValue = new Dictionary<string, string>(StringComparer.Ordinal)
    }

    // One call per analysis, from the analyzer's own reset block.
    func BeginAnalysis() {
        memberTypeNamesValue.Clear()
    }

    // Registered from the declaration walk for every field, property and SoA column. An unnamed
    // container or an untyped member registers nothing rather than a partial key: a `null` receiver
    // type would answer the dictionary rule wrongly rather than not at all.
    func RegisterMemberType(containingType: string?, memberName: string, memberType: TypeReference?) {
        if containingType == null || memberType == null {
            return
        }

        memberTypeNamesValue[containingType + "." + memberName] = SystemsTypeNames.ErasedName(memberType)
    }

    // A DICTIONARY PROBE IS NOT AN UNKNOWN EXTERNAL CALL. `map.TryGetValue(k, out v)` is the one
    // BCL call the walk lets through on the strength of the receiver's DECLARED type, and all three
    // conditions are load-bearing: the suffix, a receiver written as a member access, and a
    // registered receiver type whose erased simple name is exactly `Dictionary`. A `.TryGetValue` on
    // anything else — an unregistered local, a `ConcurrentDictionary`, a user type — is still an
    // unknown external call, which is the conservative answer.
    func IsDictionaryTryGetValueCall(call: CallExpression, target: string): bool {
        if !target.EndsWith(".TryGetValue", StringComparison.Ordinal) {
            return false
        }

        member := call.Callee as MemberAccessExpression
        if member == null {
            return false
        }

        receiverType := ""
        if !memberTypeNamesValue.TryGetValue(SystemsExpressionNames.ExpressionKey(member.Object), out receiverType) {
            return false
        }

        return SystemsTypeNames.SimpleName(receiverType) == "Dictionary"
    }

    // THE TWO NAMES THAT ARE NOT CALLS TO ANYTHING. `Ok(v)` and `Err(e)` are the Result factories the
    // language itself provides, so they are neither recorded as an outgoing call nor classified as an
    // external one — a systems function that returns `Ok(x)` has called nobody. They are matched as
    // BARE names on purpose: a user's `Result.Ok` is a real member of a real type and belongs in the
    // call graph.
    func IsResultFactoryTarget(target: string): bool {
        return target == "Ok" || target == "Err"
    }

    // The static receivers a `[hot]` function may read without a warmup fact. All eight are BCL
    // types whose static state is either nothing at all or initialised before any managed code runs.
    func IsKnownStaticHotReceiver(name: string): bool {
        return name == "BinaryPrimitives" || name == "MemoryMarshal" || name == "BitOperations" || name == "Math" || name == "MathF" || name == "Volatile" || name == "Interlocked" || name == "Thread"
    }

    // The concurrency operations v1 DOES model, by the type that owns them: the two `Volatile`
    // accessors, the five `Interlocked` read-modify-writes and `Thread.MemoryBarrier`.
    func IsKnownConcurrencyPrimitive(target: string): bool {
        return IsKnownVolatileOperation(target) || IsKnownInterlockedOperation(target) || IsKnownThreadOperation(target)
    }

    // Each of the three tables is written once and read in BOTH spellings, so a row cannot be added
    // to one spelling and forgotten in the other.
    func IsKnownVolatileOperation(target: string): bool {
        return IsThreadingMember(target, "Volatile.Read") || IsThreadingMember(target, "Volatile.Write")
    }

    func IsKnownInterlockedOperation(target: string): bool {
        return IsThreadingMember(target, "Interlocked.Exchange") || IsThreadingMember(target, "Interlocked.CompareExchange") || IsThreadingMember(target, "Interlocked.Increment") || IsThreadingMember(target, "Interlocked.Decrement") || IsThreadingMember(target, "Interlocked.Add")
    }

    func IsKnownThreadOperation(target: string): bool {
        return IsThreadingMember(target, "Thread.MemoryBarrier")
    }

    // The bare spelling and the `System.Threading`-qualified one name the same operation, because a
    // project that imported the namespace and one that did not must classify alike.
    func IsThreadingMember(target: string, memberPath: string): bool {
        return target == memberPath || target == "System.Threading." + memberPath
    }

    // Anything else on those three types. Asked only after the known table has answered, so this is
    // the complement rather than an overlap.
    func IsUnsupportedConcurrencyPrimitive(target: string): bool {
        return IsThreadingTypeMember(target, "Interlocked.") || IsThreadingTypeMember(target, "Volatile.") || IsThreadingTypeMember(target, "Thread.")
    }

    // A member OF one of the three types, in either spelling. The trailing dot is what makes it a
    // member rather than a type mention, and what keeps `MyInterlocked.Read` out.
    func IsThreadingTypeMember(target: string, typePrefix: string): bool {
        return target.StartsWith(typePrefix, StringComparison.Ordinal) || target.StartsWith("System.Threading." + typePrefix, StringComparison.Ordinal)
    }

    // Calls whose callee is chosen at runtime rather than at compile time: either the target NAMES an
    // enumerable surface, or it STEPS one.
    func IsRuntimeDispatchCall(target: string): bool {
        return NamesAnEnumerableSurface(target) || StepsAnEnumeratorOrDelegate(target)
    }

    // Named by SUBSTRING, because these appear as receivers, as type arguments and as qualified
    // namespaces alike and all three positions mean the same thing here.
    func NamesAnEnumerableSurface(target: string): bool {
        return target.Contains("System.Linq", StringComparison.Ordinal) || target.Contains("IEnumerable", StringComparison.Ordinal) || target.Contains("IQueryable", StringComparison.Ordinal)
    }

    // Matched by SUFFIX, because these are members: a user's own function called `MoveNext` is not
    // one, but any receiver's `.MoveNext` is.
    func StepsAnEnumeratorOrDelegate(target: string): bool {
        return target.EndsWith(".GetEnumerator", StringComparison.Ordinal) || target.EndsWith(".MoveNext", StringComparison.Ordinal) || target.EndsWith(".DynamicInvoke", StringComparison.Ordinal)
    }

    // Pooling by shape: either pool type by name anywhere in the target, or either half of the
    // rent/return pair as a suffix. Deliberately wide — a custom pool that spells `Rent` and `Return`
    // gets the balance rule for free.
    func IsPoolCall(target: string): bool {
        return NamesAPoolType(target) || IsPoolRentTarget(target) || IsPoolReturnTarget(target)
    }

    func NamesAPoolType(target: string): bool {
        return target.Contains("ArrayPool", StringComparison.Ordinal) || target.Contains("MemoryPool", StringComparison.Ordinal)
    }

    // WHICH HALF OF THE RENT/RETURN PAIR A TARGET NAMES. Three rules ask about the rent half —
    // whether a local now owes a return, whether a `[hot]` function needed an `allow(pool)` to ask
    // for the buffer, and whether the project needs a warmup before it can — and two ask about the
    // return half. They must not be able to disagree, which is why each suffix is written once here
    // rather than once per asking site.
    func IsPoolRentTarget(target: string): bool {
        return target.EndsWith(".Rent", StringComparison.Ordinal)
    }

    func IsPoolReturnTarget(target: string): bool {
        return target.EndsWith(".Return", StringComparison.Ordinal)
    }

    // WHAT OPENS A POOL OBLIGATION: a direct call, to a pool, on the rent half. The `IsPoolCall`
    // conjunct is not redundant with the rent half — `IsPoolCall` also accepts a target merely
    // CONTAINING a pool type name, and an obligation is only opened by a call that does both.
    func IsPoolRentExpression(expression: Expression): bool {
        call := expression as CallExpression
        if call == null {
            return false
        }

        target := SystemsExpressionNames.CallTarget(call.Callee)
        if target == null {
            return false
        }

        return IsPoolCall(target) && IsPoolRentTarget(target)
    }

    // WHAT OPENS A RESOURCE OBLIGATION, and what KIND of resource it is. Null means "not a resource
    // creation"; anything else is the kind, which reaches a developer verbatim inside the NSYS090
    // sentence. The C# original was a `bool` with an `out string`; every affirmative arm assigned a
    // non-empty kind first, so a nullable return is exact rather than approximate.
    //
    // The `alloc` arm looks THROUGH the marker: `alloc new FileStream(...)` opens the same obligation
    // as `new FileStream(...)`, because spelling the allocation says something about the heap, not
    // about ownership.
    func ResourceCreationKind(expression: Expression): string? {
        allocExpression := expression as AllocExpression
        if allocExpression != null {
            return ResourceCreationKind(allocExpression.Expression)
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            if newExpression.Type == null {
                return null
            }

            typeName := SystemsTypeNames.SimpleName(SystemsTypeNames.ErasedName(newExpression.Type))
            if IsKnownDisposableType(typeName) {
                return typeName
            }

            return null
        }

        call := expression as CallExpression
        if call != null {
            target := SystemsExpressionNames.CallTarget(call.Callee)
            if target != null && IsKnownResourceFactory(target) {
                return target
            }

            return null
        }

        return null
    }

    // Matched against the SIMPLE name of the erased type, so the namespace a project writes makes no
    // difference and a generic disposable is matched by its constructor. Fourteen names in two
    // groups — the things that hold a file handle and the things that hold an OS or kernel one.
    func IsKnownDisposableType(typeName: string): bool {
        return IsKnownDisposableStreamType(typeName) || IsKnownDisposableHandleType(typeName)
    }

    func IsKnownDisposableStreamType(typeName: string): bool {
        return typeName == "FileStream" || typeName == "StreamReader" || typeName == "StreamWriter" || typeName == "BinaryReader" || typeName == "BinaryWriter" || typeName == "TextReader" || typeName == "TextWriter" || typeName == "MemoryStream"
    }

    func IsKnownDisposableHandleType(typeName: string): bool {
        return typeName == "Socket" || typeName == "TcpClient" || typeName == "UdpClient" || typeName == "HttpClient" || typeName == "SemaphoreSlim" || typeName == "CancellationTokenSource"
    }

    // Matched against the WHOLE dotted target and NOT simplified, which is why four factories need
    // eight rows: a user's own `File.Open` in their own namespace is written the same way as the
    // BCL's only when they, too, spell it `File.Open`, and `MyApp.File.Open` is a different function
    // that must not inherit this rule.
    func IsKnownResourceFactory(target: string): bool {
        return IsFileFactoryTarget(target, "Open") || IsFileFactoryTarget(target, "OpenRead") || IsFileFactoryTarget(target, "OpenWrite") || IsFileFactoryTarget(target, "Create")
    }

    // The bare and the `System.IO`-qualified spelling of one factory. Written once so the pair cannot
    // drift apart, and deliberately NOT simplified: `MyApp.File.Open` matches neither row.
    func IsFileFactoryTarget(target: string, memberName: string): bool {
        return target == "File." + memberName || target == "System.IO.File." + memberName
    }

    // THE NAME A DISPOSE DISCHARGES, in the three written forms that reach it, and null for anything
    // else. The identifier arm comes FIRST and is unconditional: `using (buffer)` names the local
    // directly, and there is no member to check.
    func DisposalTargetName(expression: Expression): string? {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        call := expression as CallExpression
        if call != null {
            calleeMember := call.Callee as MemberAccessExpression
            if calleeMember != null && IsDisposeMemberName(calleeMember.MemberName) {
                callReceiver := calleeMember.Object as IdentifierExpression
                if callReceiver != null {
                    return callReceiver.Name
                }
            }

            return null
        }

        member := expression as MemberAccessExpression
        if member != null && IsDisposeMemberName(member.MemberName) {
            memberReceiver := member.Object as IdentifierExpression
            if memberReceiver != null {
                return memberReceiver.Name
            }
        }

        return null
    }

    // Both spellings of the disposal member, and only on a BARE identifier receiver: disposing
    // `owner.buffer` discharges nothing this walk recorded, because the ledger is keyed by local name.
    func IsDisposeMemberName(memberName: string): bool {
        return memberName == "Dispose" || memberName == "DisposeAsync"
    }

    // WHETHER THE ANALYZER POSITIVELY REJECTED THE MEMBER A DISCHARGE IS WRITTEN ON.
    //
    // "POSITIVELY" IS THE WHOLE RULE AND IT IS ONE CONDITION: the analyzer recorded an UNKNOWN type
    // at this expression's own position. A member it RESOLVED — in project source or through
    // metadata — is not rejected, so `File.OpenRead(path)` followed by `stream.Dispose()` still
    // discharges; and a position it recorded NOTHING at is not rejected either, because an
    // unresolved owner is deliberately permissive everywhere else in the analyzer and it is
    // permissive here. The narrowness is what keeps two machines classifying alike: only a verdict
    // the analyzer actually wrote down can refuse a discharge, never the absence of one.
    //
    // A null model is the analyzer driven without one, and it answers `false` — no verdict, so no
    // refusal.
    func MemberIsPositivelyRejected(model: SemanticModel?, expression: Expression): bool {
        if model == null {
            return false
        }

        types := model.ExpressionTypes
        key := (Line: expression.Line, Column: expression.Column)
        if !types.ContainsKey(key) {
            return false
        }

        return BuiltInTypes.IsUnknown(types[key])
    }

    // WHAT A RESOLVED CALL STILL DISCHARGES, AND WHY THE DOOR HAS TO EXIST.
    //
    // A call that binds to a PROJECT declaration never reaches the classification chain: the walk
    // resolves it, records it in the call graph and stops. So before this door, the ONLY disposal the
    // resource ledger ever accepted was one that did not resolve — a user type that spells
    // `func Dispose()` and is disposed correctly was reported as leaked (NSYS090), measured. A
    // resolved call needs no rejection test, because it resolved; both ledgers are offered it, since
    // a project's own pool spelling `Return` is a return the same way a project's `Dispose` is a
    // dispose.
    func MarkDeclaredCalleeDischarges(call: CallExpression, poolRents: Dictionary<string, PoolRent>, resourceLocals: Dictionary<string, ResourceLocal>) {
        MarkResourceDisposedIfRecognized(call.Callee, poolRents, resourceLocals, null)
        MarkPoolReturnIfRecognized(call, poolRents, null)
    }

    // DISCHARGES BOTH LEDGERS FOR ONE NAME, and answers whether the name was on either. A `true` here
    // stops the call walk: a recognised disposal is not also an unknown external call. The lookup is
    // a membership test followed by a read rather than a single `TryGetValue` because the entry is
    // then mutated in place, and the two are the same answer.
    //
    // THE REJECTION TEST COMES FIRST AND ITS `false` IS LOAD-BEARING TWICE OVER: the obligation stays
    // open (so the balance rule reports NSYS090/NSYS130 at the place it was opened) AND the call walk
    // carries on to its own fall-through (so the same call is reported as the unknown external call
    // it is). One mistake, reported by the rule that owns each half.
    func MarkResourceDisposedIfRecognized(expression: Expression, poolRents: Dictionary<string, PoolRent>, resourceLocals: Dictionary<string, ResourceLocal>, model: SemanticModel?): bool {
        if MemberIsPositivelyRejected(model, expression) {
            return false
        }

        variableName := DisposalTargetName(expression)
        if variableName == null {
            return false
        }

        recognized := false
        if poolRents.ContainsKey(variableName) {
            rent := poolRents[variableName]
            rent.Returned = true
            recognized = true
        }

        if resourceLocals.ContainsKey(variableName) {
            resource := resourceLocals[variableName]
            resource.Disposed = true
            recognized = true
        }

        return recognized
    }

    // DISCHARGES THE POOL LEDGER FOR EVERY BUFFER HANDED TO A `.Return`. It marks by ARGUMENT rather
    // than by receiver, because `pool.Return(buffer)` names the buffer in the argument list, and it
    // marks EVERY identifier argument, because a return that takes several is still a return of each.
    // Unlike a disposal this answers nothing: an unrecognised return is still a pool call and the walk
    // has already said so.
    //
    // IT TAKES THE SAME REJECTION TEST AS THE DISPOSAL, for the same reason: `Zqxwvut.Return(buffer)`
    // closed a rental over a receiver the analyzer reports as `NL301: Variable 'Zqxwvut' not found`.
    func MarkPoolReturnIfRecognized(call: CallExpression, poolRents: Dictionary<string, PoolRent>, model: SemanticModel?) {
        if MemberIsPositivelyRejected(model, call.Callee) {
            return
        }

        target := SystemsExpressionNames.CallTarget(call.Callee)
        if target == null || !IsPoolReturnTarget(target) {
            return
        }

        for argument in call.Arguments {
            identifier := argument.Value as IdentifierExpression
            if identifier != null && poolRents.ContainsKey(identifier.Name) {
                rent := poolRents[identifier.Name]
                rent.Returned = true
            }
        }
    }

    // The narrower half of the reflection rule: calls that build code or types at RUNTIME, which is
    // what makes an assembly untrimmable rather than merely unanalysable.
    func IsDynamicCodeCall(target: string): bool {
        return ConstructsAtRuntime(target) || InstantiatesGenericsAtRuntime(target)
    }

    func ConstructsAtRuntime(target: string): bool {
        return target.Contains("Activator.CreateInstance", StringComparison.Ordinal) || target.EndsWith(".CreateDelegate", StringComparison.Ordinal) || target.EndsWith(".DynamicInvoke", StringComparison.Ordinal)
    }

    func InstantiatesGenericsAtRuntime(target: string): bool {
        return target.EndsWith(".MakeGenericType", StringComparison.Ordinal) || target.EndsWith(".MakeGenericMethod", StringComparison.Ordinal)
    }

    // The wider half, which SUBSUMES the narrower one by construction: everything that generates code
    // is reflection, plus the read-only reflection surface that only blocks trimming facts.
    func IsReflectionOrDynamicCall(target: string): bool {
        return IsDynamicCodeCall(target) || QueriesMetadata(target)
    }

    // Reading metadata rather than generating from it. `.GetType` is a SUFFIX because it is a member;
    // the four `Get…` families are SUBSTRINGS because the analyzer means to catch their overloads and
    // their qualified spellings alike.
    func QueriesMetadata(target: string): bool {
        return target.EndsWith(".GetType", StringComparison.Ordinal) || target.Contains(".GetMethod", StringComparison.Ordinal) || target.Contains(".GetMethods", StringComparison.Ordinal) || target.Contains(".GetProperty", StringComparison.Ordinal) || target.Contains(".GetCustomAttribute", StringComparison.Ordinal)
    }

    // The one unsafe BCL primitive the analyzer has facts for. Both spellings, exact match.
    func IsBufferMemoryCopyCall(target: string): bool {
        return target == "Buffer.MemoryCopy" || target == "System.Buffer.MemoryCopy"
    }
}
