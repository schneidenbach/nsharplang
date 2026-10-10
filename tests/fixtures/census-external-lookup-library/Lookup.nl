namespace Census.Lookup


// THE ENCLOSING NAMESPACE, COMPILED INTO ANOTHER ASSEMBLY. `tests/native/census-external-lookup` sits
// in `Census.Lookup.Consumer`, so every type here is a member of a namespace that encloses it, and a
// bare name binds here before any import is asked — the shape `Compiler.Model` takes once it is carved
// out of `Compiler.Core`. `TypeInfo` is spelled like `System.Reflection.TypeInfo` on purpose.
class TypeInfo {
    static func Make(): TypeInfo {
        return new TypeInfo()
    }

    func Side(): string {
        return "lookup"
    }
}

// A base class a consumer derives from by its bare name.
class Base {
    func Kind(): string {
        return "base"
    }
}
