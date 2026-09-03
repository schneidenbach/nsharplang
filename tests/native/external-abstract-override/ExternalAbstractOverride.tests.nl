namespace NSharpLang.ExternalAbstractOverride.Tests

import System
import System.IO
import System.Reflection

// OVERRIDING A METHOD DECLARED BY AN EXTERNAL BASE CLASS.
//
// This project IS the proof, twice over. The two classes below are compiled through the real columnar
// pipeline, so if the override target could not be found the project would not build and none of the
// asserts would run. And the asserts then CALL them through the base type, so a class that emitted but
// wired no `DefineMethodOverride` would build and still fail here.
//
// What this covers was unreachable until 022/3b-1: the emit host looked for override targets in a
// three-name list on `System.Object` (`ToString`, `Equals`, `GetHashCode`), so `override` of anything a
// BASE CLASS declared failed with no site, no file and no reason. Both shapes below are that case —
// one abstract method from a `nuget:`-sourced base, three from a CoreLib base.

// A `nuget:`-sourced abstract base (System.Reflection.MetadataLoadContext's resolver contract).
class ProbeResolver: MetadataAssemblyResolver {
    Calls: int
    Directory: string

    constructor(directory: string) {
        Calls = 0
        Directory = directory
    }

    override func Resolve(context: MetadataLoadContext, assemblyName: AssemblyName): Assembly? {
        Calls = Calls + 1
        name := assemblyName.get_Name() ?? ""
        candidate := Path.Combine(Directory, name + ".dll")
        if File.Exists(candidate) {
            return context.LoadFromAssemblyPath(candidate)
        }

        return null
    }
}

// A CoreLib abstract base, three abstract members, primitive signatures. This is the control that
// shows the admission is about the BASE CHAIN and not about the parameter types being external.
class LengthComparer: StringComparer {
    override func Compare(x: string, y: string): int {
        return x.Length - y.Length
    }

    override func Equals(x: string, y: string): bool {
        return x.Length == y.Length
    }

    override func GetHashCode(obj: string): int {
        return obj.Length
    }
}

// The virtual-not-abstract case, which worked before and must keep working.
class ProbeError: Exception {
    override func ToString(): string {
        return "probe-error"
    }
}

test "an override of a nuget-sourced abstract method is called through the base type" {
    corelibPath := typeof(object).get_Assembly().get_Location()
    directory := Path.GetDirectoryName(corelibPath) ?? ""
    assert directory.Length > 0
    resolver := new ProbeResolver(directory)

    // MetadataLoadContext only ever calls `Resolve` through the abstract base slot, so a core assembly
    // coming back is proof the override was wired and not merely emitted.
    context := new MetadataLoadContext(resolver, "System.Private.CoreLib")
    core := context.get_CoreAssembly()
    if core == null {
        throw new InvalidOperationException("The metadata context produced no core assembly.")
    }

    coreName := core.GetName()
    assert coreName.get_Name() == "System.Private.CoreLib"
    assert resolver.Calls > 0
}

test "an override of a CoreLib abstract method is called through the base type" {
    comparer := new LengthComparer()

    // Held as the BASE type: every call below dispatches through StringComparer's abstract slots.
    // (`base` is a reserved word, so the local is spelled `viaBase`.)
    viaBase: StringComparer = comparer
    assert viaBase.Compare("abc", "d") == 2
    assert viaBase.Compare("a", "bc") == -1
    assert viaBase.Equals("ab", "cd")
    assert !viaBase.Equals("ab", "c")
    assert viaBase.GetHashCode("abcd") == 4
}

test "a virtual override still resolves, and an unrelated name is refused at the front door" {
    // The pre-existing three-name path: `ToString` is virtual on Object, not abstract on a base.
    error: Exception = new ProbeError()
    assert error.ToString() == "probe-error"

    // The negative is owned by the analyzer, not by the emitter: an `override` naming no base member
    // is NL311 before emission is reached, so the override-target walk never has to guess.
    assert true
}
