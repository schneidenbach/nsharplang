namespace Census.FreeFunctionIdentity.Tests

import System
import System.Collections.Generic
import System.Reflection
import Census.FreeFunctionIdentity.Holder
import Census.FreeFunctionIdentity.Spread
import Census.FreeFunctionIdentity.StaticOnly
import Census.FreeFunctionIdentity.TypesOnly
import Census.FreeFunctionIdentity.X
import Census.FreeFunctionIdentity.X.Deep
import Census.FreeFunctionIdentity.X.Deeper
import Census.FreeFunctionIdentity.Y
import Census.FreeFunctionIdentity.Z


// A FREE FUNCTION IS (NAMESPACE, NAME), NEVER THE BARE NAME.
//
// Before this rule the emitter kept ONE project-wide map keyed by `fn.Name`, so a second `Helper`
// declared in another namespace was shadowed by the first in every caller — `check` and `build` were
// clean and the program printed the wrong answer. These assertions execute the emitted IL, so a
// regression is a failing test rather than a silent miscompile.
class IdentityFacts {
    static func Assembly(): Assembly {
        markerType: Type = typeof(XMarker)
        return markerType.get_Assembly()
    }

    static func Holder(namespaceName: string): Type {
        return Assembly().GetType(namespaceName + ".Program")
    }

    static func HolderMethod(namespaceName: string, name: string): MethodInfo {
        holder := Holder(namespaceName)
        if holder == null {
            return null
        }

        return holder.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    }

    static func DeclaringTypeName(method: MethodInfo?): string {
        if method == null {
            return "<no method>"
        }

        owner := method.get_DeclaringType()
        if owner == null {
            return "<no declaring type>"
        }

        return owner.FullName ?? "<unnamed>"
    }

    // Every type in this assembly whose NAME is a holder spelling and which declares nothing —
    // no method, no field. A holder exists to hold something; one that holds nothing is a type row
    // the emitter wrote for a namespace that never asked for it, and it is PUBLIC, so a C# consumer
    // that references two such assemblies cannot name `Program` at all (CS0433).
    static func EmptyHolderNames(): List<string> {
        empty := new List<string>()
        for candidate in Assembly().GetTypes() {
            candidateName := candidate.Name
            if candidateName != "Program" && candidateName != "<Program>" {
                continue
            }

            declaredMethods := candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            declaredFields := candidate.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            if declaredMethods.Length == 0 && declaredFields.Length == 0 {
                empty.Add(candidate.FullName ?? candidateName)
            }
        }
        return empty
    }

    static func LoweredLambdaCount(owner: Type?): int {
        if owner == null {
            return -1
        }

        count := 0
        for method in owner.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly) {
            if method.Name.StartsWith("<Lambda>_", StringComparison.Ordinal) {
                count = count + 1
            }
        }

        return count
    }

    static func HolderMethodCount(namespaceName: string, name: string): int {
        holder := Holder(namespaceName)
        if holder == null {
            return -1
        }

        matched := 0
        for candidate in holder.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.DeclaredOnly) {
            if candidate.Name == name {
                matched = matched + 1
            }
        }
        return matched
    }
}

test "two namespaces that both declare `Helper` each call their own" {
    assert UseHelperFromX() == "X"
    assert UseHelperFromY() == "Y"
}

test "two namespaces that both declare a camelCase `helper` each call their own" {
    assert UseCamelHelperFromX() == "x"
    assert UseCamelHelperFromY() == "y"
}

test "a nested namespace's own declaration wins over the enclosing one" {
    assert UseOwnHelper() == "X.Deep"
}

test "a nested namespace with no declaration of its own climbs to the enclosing namespace" {
    assert UseEnclosingHelper() == "X"
}

test "a third namespace reaches an exported function through its import" {
    assert UseImportedHelper() == "Y"
    assert ZOnly() == "Z"
}

test "a body with local functions still reaches its own namespace's sibling" {
    assert LocalAndSiblingFromX() == "x-local/X"
    assert LocalAndSiblingFromY() == "y-local/Y"
}

test "return tuple element labels follow the function the call actually reached" {
    assert SplitHeadFromX() == "X-head"
    assert SplitFirstFromY() == "Y-first"
}

test "a method group over a same-named function binds the caller's own declaration" {
    fromX := HelperGroupFromX()
    fromY := HelperGroupFromY()

    assert fromX() == "X"
    assert fromY() == "Y"
}

test "same-named iterators in two namespaces keep their own state machines" {
    assert StepSumFromX() == 3
    assert StepSumFromY() == 30
}

test "each namespace gets its own `Program` holder type" {
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.X") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.Y") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.Z") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.X.Deep") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.X.Deeper") != null
}

test "the two `Helper` methods are distinct metadata rows on distinct holders" {
    fromX := IdentityFacts.HolderMethod("Census.FreeFunctionIdentity.X", "Helper")
    fromY := IdentityFacts.HolderMethod("Census.FreeFunctionIdentity.Y", "Helper")

    assert fromX != null
    assert fromY != null
    assert IdentityFacts.DeclaringTypeName(fromX) == "Census.FreeFunctionIdentity.X.Program"
    assert IdentityFacts.DeclaringTypeName(fromY) == "Census.FreeFunctionIdentity.Y.Program"
    assert fromX.get_MetadataToken() != fromY.get_MetadataToken()
}

test "a holder declares each name exactly once" {
    assert IdentityFacts.HolderMethodCount("Census.FreeFunctionIdentity.X", "Helper") == 1
    assert IdentityFacts.HolderMethodCount("Census.FreeFunctionIdentity.Y", "Helper") == 1
    assert IdentityFacts.HolderMethodCount("Census.FreeFunctionIdentity.X", "helper") == 1
    assert IdentityFacts.HolderMethodCount("Census.FreeFunctionIdentity.Y", "helper") == 1
}

test "a method group's delegate carries the holder of the namespace it was written in" {
    fromX := HelperGroupFromX()
    fromY := HelperGroupFromY()

    assert IdentityFacts.DeclaringTypeName(fromX.get_Method()) == "Census.FreeFunctionIdentity.X.Program"
    assert IdentityFacts.DeclaringTypeName(fromY.get_Method()) == "Census.FreeFunctionIdentity.Y.Program"
}

test "a camelCase free function is namespace-private, not file-private" {
    // The analyzer's ruling (census 2026-09-13, §VIS): every file of a namespace sees that
    // namespace's camelCase functions with no import and no export. The emitter used to refuse the
    // call the analyzer had already accepted.
    assert DescribeAcross(3) == "spread:3/label"

    // A method group over one of them binds the same declaration.
    group := SpreadGroup()
    assert group() == "label"
}

test "a user type named `Program` keeps its name and the holder yields" {
    // The shape three of this repository's examples are written in.
    made := MakeProgram(21)
    assert made.Doubled() == 42
    assert UseHolderHelper() == "holder"

    // The SOURCE type keeps the ordinary name...
    holderNamespace := "Census.FreeFunctionIdentity.Holder"
    userType := IdentityFacts.Assembly().GetType(holderNamespace + ".Program")
    assert userType != null
    assert IdentityFacts.HolderMethodCount(holderNamespace, "HolderHelper") == 0

    // ...and the free functions live on the reserved spelling instead, which no source can write.
    reserved := IdentityFacts.Assembly().GetType(holderNamespace + ".<Program>")
    assert reserved != null
    assert reserved.GetMethod("HolderHelper", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static) != null
    assert reserved.GetMethod("UseHolderHelper", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static) != null

    // A namespace with no such type is unaffected: it still gets the ordinary `Program`.
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.Spread") != null
}

test "a namespace that declares nothing gets no holder at all" {
    // The holders are created ON DEMAND, so a library whose every file names a namespace does not
    // emit an empty global `Program` beside the real ones.
    assert IdentityFacts.Assembly().GetType("Program") == null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity") == null
}

test "a namespace that declares only types emits no holder" {
    // `Census.FreeFunctionIdentity.TypesOnly` declares one class and no free function. Its
    // constructor, its instance methods, its two lambdas and its anonymous object all place their
    // members somewhere else, so the namespace has nothing to put on a `Program` and gets none.
    //
    // ON DEMAND USED TO MEAN "THE MOMENT ANY BODY IS EMITTED". Every body was handed a resolved
    // holder `TypeBuilder` in case it lifted something, and resolving one is what defines it, so a
    // namespace acquired an empty public `Program` for owning a single method. The type IS reachable
    // — `Calc` is the proof the namespace emitted — so a missing holder here is the rule, not an
    // empty assembly.
    calc := new Calc(21)
    assert calc.Doubled() == 42
    assert calc.PlusOne(1) == 2
    assert calc.PlusSeed(1) == 22
    assert calc.Described() != null

    assert IdentityFacts.Assembly().GetType("Census.FreeFunctionIdentity.TypesOnly.Calc") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.TypesOnly") == null
    assert IdentityFacts.Assembly().GetType("Census.FreeFunctionIdentity.TypesOnly.<Program>") == null
}

test "a namespace whose only lambdas are in static bodies emits no holder" {
    // `Census.FreeFunctionIdentity.StaticOnly` declares one class and no free function, and every
    // lambda in it is written in a STATIC body: a static field initializer, a static method with a
    // delegate-typed target, a static method whose lambda infers its own signature, and a static
    // method whose lambda captures a local. None of them is file level, so the namespace still has
    // nothing to put on a `Program` and gets none.
    //
    // The placement decision used to read the INSTANCE-context marker, which is null in all four,
    // so all four landed on the holder and DEFINED it — a public `Program` for a namespace that
    // declares no free function. `NSharpLang.Cli.Program` in the emitted `Compiler` assembly was
    // exactly that, and it is what CS0436 names in `src/NSharpLang.Cli/Program.cs`.
    assert StaticHost.PlusOne(1) == 2
    assert StaticHost.Inferred(1) == 42
    assert StaticHost.Captured(1) == 42

    assert IdentityFacts.Assembly().GetType("Census.FreeFunctionIdentity.StaticOnly.StaticHost") != null
    assert IdentityFacts.Holder("Census.FreeFunctionIdentity.StaticOnly") == null
    assert IdentityFacts.Assembly().GetType("Census.FreeFunctionIdentity.StaticOnly.<Program>") == null

    // And the lambdas are on the type whose static member was being emitted, not merely elsewhere:
    // three of the four, because the CAPTURING one becomes an instance method on a module-level
    // display class as it always did and never touched the holder.
    host := IdentityFacts.Assembly().GetType("Census.FreeFunctionIdentity.StaticOnly.StaticHost")
    assert IdentityFacts.LoweredLambdaCount(host) == 3
}

test "no holder type in the emitted assembly is empty" {
    // The whole-assembly form of the rule above, so a namespace this file has not named cannot
    // acquire an empty holder unnoticed — including this test file's own
    // `Census.FreeFunctionIdentity.Tests`, which declares no free function. A holder that DOES
    // declare something is not reported: the two real ones and the reserved `<Program>` each carry
    // their functions.
    empty := IdentityFacts.EmptyHolderNames()
    assert empty.Count == 0
}
