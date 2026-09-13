namespace Census.FreeFunctionIdentity.Tests

import System
import System.Reflection
import Census.FreeFunctionIdentity.Holder
import Census.FreeFunctionIdentity.Spread
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
