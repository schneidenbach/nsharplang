# Phase-B contracts — the binding-mask call surface

Task 017 slice 20 **phase A** landed the capability: two catalog rows in
`src/NSharpLang.Compiler.BootstrapServices/ColumnarExternalBindingPlans.nl` — the
`System.Type.GetMethods(BindingFlags)` call row in `GetInstanceCallPlan`, and the `BindingFlags`
enum's own member row in `GetStaticMemberPlan`. This file holds the contracts that EXERCISE the
capability, staged here rather than in the project because of the bootstrap wall: the packaged
toolset that builds `NSharpLang.Compiler.BootstrapServices` carries its own snapshot of that
catalog, so until it is repacked these contracts fail to compile.

The decline was MEASURED at phase A, not assumed — a probe `.tests.nl` placed in the project failed
the build with:

```
error NL103: Columnar emission is required for 'NSharpLang.Compiler.BootstrapServices', but the
columnar backend declined. Declined at emit.call.instance-member-unmodeled: instance call
'Type.GetMethods' with 1 argument(s) is not modeled
```

A `.tests.nl` in the project therefore breaks the contracts gate; a staged `.nl`-suffixed file trips
the ownership audit's `OWN009` (unknown product-adjacent file type). A closeout `.md` is the one
home that perturbs neither.

**Every shape below was verified at phase A to COMPILE AND RUN against a freshly built compiler**,
which links a freshly built `BootstrapServices` and is therefore behaviourally the post-repin
toolset. The emitted binary printed `57` public-instance methods and `79` declared methods on
`List<int>` — the mask demonstrably widening the result, not merely compiling — and re-found the
open `Add` on `List<T>`'s generic definition by metadata token. An activation failure means the
repin did not take, not that the shapes are wrong.

## To activate (phase B, after the toolset repin)

1. Pack and install the SDK so the packaged toolset carries the two new catalog rows.
2. Copy the block below to
   `src/NSharpLang.Compiler.BootstrapServices/AnalyzerReflectionArgumentBinder.tests.nl`
   (or wherever `GetOpenReflectionSignatureMethod` lands), adjusting the namespace to match.
3. `dotnet test src/NSharpLang.Compiler.BootstrapServices -p:NSharpExcludeTests=false`
   (expect 1,994 + 3 = 1,997, before phase B's own member contracts).
4. Delete this file once the contracts live in the project.

## What it pins

That the two rows are reachable from `.nl` at once: the mask's members type, they combine with `|`
into a value that is still a `BindingFlags`, and the combined value selects the filtered
`Type.GetMethods` overload — which is exactly `GetOpenReflectionSignatureMethod`'s body.

Two shape rules phase B must keep, each one measured at phase A by deleting a row and rebuilding:

- The INLINE combined mask (`GetMethods(A | B | C | D)`) needs the call row. Without it the ordinary
  runtime direct-call resolver still binds a SINGLE-member argument (`GetMethods(BindingFlags.Public)`)
  and a mask hoisted into a local (`flags: BindingFlags = A | B`), but the inline `|` argument
  declines at `emit.call.instance-member-unmodeled`. A local hoist is therefore a route-around, and
  the row is what makes the natural spelling work.
- Nothing at all types without the mask row. With it absent, every form declines — the member read,
  the local, and the call — which is why slice 19 recorded three separate "enum-local" capability
  facts that were in truth one missing row.

```nsharp
namespace NSharpLang.Compiler

import System
import System.Reflection

// The generic type DEFINITION whose members the mask re-finds. A test body cannot narrow a
// maybe-null local (`assert x != null` does not narrow — NL905), so every lookup that can fail is
// resolved here and answers a non-null value or throws.
func maskProbeListDefinition(): Type {
    definition := Type.GetType("System.Collections.Generic.List`1, System.Private.CoreLib")
    if definition == null {
        throw new InvalidOperationException("List`1 was unavailable.")
    }
    return definition
}

func maskProbeClosedAdd(): MethodInfo {
    closedName := "System.Collections.Generic.List`1[[System.Int32, System.Private.CoreLib]], System.Private.CoreLib"
    closedType := Type.GetType(closedName)
    if closedType == null {
        throw new InvalidOperationException("List<int> was unavailable.")
    }
    closed := closedType.GetMethod("Add")
    if closed == null {
        throw new InvalidOperationException("List<int>.Add was unavailable.")
    }
    return closed
}

// GetOpenReflectionSignatureMethod's body, which is the whole reason for the rows.
func maskProbeOpenAdd(): MethodInfo {
    closed := maskProbeClosedAdd()
    declaring := closed.get_DeclaringType()
    if declaring == null {
        throw new InvalidOperationException("List<int>.Add had no declaring type.")
    }
    definition := declaring.GetGenericTypeDefinition()
    candidates := definition.GetMethods(
        BindingFlags.Public
            | BindingFlags.NonPublic
            | BindingFlags.Instance
            | BindingFlags.Static)
    i := 0
    while i < candidates.Length {
        candidate := candidates[i]
        if candidate.get_MetadataToken() == closed.get_MetadataToken() {
            return candidate
        }
        i = i + 1
    }
    throw new InvalidOperationException("The open signature was not re-found.")
}

test "the binding mask combines and selects the filtered enumeration" {
    definition := maskProbeListDefinition()

    publicInstance := definition.GetMethods(BindingFlags.Public | BindingFlags.Instance)
    declared := definition.GetMethods(
        BindingFlags.Public
            | BindingFlags.NonPublic
            | BindingFlags.Instance
            | BindingFlags.Static)

    // The mask is not decoration: the wider request answers strictly more members.
    assert publicInstance.Length > 0
    assert declared.Length > publicInstance.Length

    // The unfiltered arity-0 arm is still its own overload and still binds.
    assert definition.GetMethods().Length == publicInstance.Length
}

test "a single mask member and a hoisted mask both bind" {
    definition := maskProbeListDefinition()

    // The two shapes the ordinary runtime resolver already covered once the mask row admits the
    // enum. They must keep working: a regression here means the mask row stopped admitting it.
    // A lone visibility flag is a legal mask that selects NOTHING — the CLR requires a staticness
    // flag too — so the empty answer is the proof that the call bound and ran, not that it failed.
    single := definition.GetMethods(BindingFlags.Public)
    assert single.Length == 0

    hoisted: BindingFlags = BindingFlags.Public | BindingFlags.Instance
    assert definition.GetMethods(hoisted).Length
        == definition.GetMethods(BindingFlags.Public | BindingFlags.Instance).Length
    assert definition.GetMethods(hoisted).Length > 0
}

test "an open signature is re-found on the generic definition by metadata token" {
    openAdd := maskProbeOpenAdd()
    assert openAdd.get_Name() == "Add"
    assert openAdd.GetParameters().Length == 1
    assert openAdd.get_MetadataToken() == maskProbeClosedAdd().get_MetadataToken()
}
```
