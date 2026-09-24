namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Reflection
import System.Reflection.Emit


// THE BASE CLOSED OVER A TYPE THIS COMPILATION IS WRITING.
//
// `class Catalogue: Collection<Item>` — where `Item` is a source class — reaches emission as
// `Collection<TypeBuilder>`, and the CLR has no handle for such a type: every member query on it
// throws `NotSupportedException`. That exception used to escape `nlc check` entirely. The fixture
// below builds exactly that shape so the contracts can state both halves: that asking the
// instantiation directly still throws (so the walk through the definition is necessary, not
// decorative), and that this owner answers anyway.
func ExternalBaseCtorSourceTypeBuilder(name: string): TypeBuilder {
    assemblyName := "NSharpTests." + name
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)

    return dynamicModule.DefineType(
        "ExternalBaseCtorTests." + name,
        TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.BeforeFieldInit,
        typeof(object)
    )
}

func ExternalBaseCtorBuilderBoundCollection(name: string): Type {
    openCollection := typeof(Collection<int>).GetGenericTypeDefinition()
    sourceType: Type = ExternalBaseCtorSourceTypeBuilder(name)

    return openCollection.MakeGenericType([sourceType])
}

test "a base closed over a source type answers no member query of its own" {
    builderBound := ExternalBaseCtorBuilderBoundCollection("DirectQueryThrows")
    threw := false
    try {
        builderBound.GetConstructors(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    } catch {
        threw = true
    }

    assert threw
    assert ColumnarExternalBaseConstructors.IsBuilderBoundInstantiation(builderBound)
    assert ColumnarExternalBaseConstructors.LookupType(builderBound) == typeof(Collection<int>).GetGenericTypeDefinition()
}

test "the definition supplies the constructors, and the instantiation supplies the handles" {
    builderBound := ExternalBaseCtorBuilderBoundCollection("DefinitionAnswers")
    resolved := ColumnarExternalBaseConstructors.Resolve(builderBound)

    // `Collection<T>` declares `Collection()` and `Collection(IList<T> list)`, both public.
    assert resolved.Count == 2

    parameterless := ColumnarExternalBaseConstructors.ResolveParameterless(builderBound)
    assert parameterless != null

    // The handle is the REBOUND one: it belongs to the instantiation, not to the definition.
    assert parameterless.get_DeclaringType() == builderBound

    listArgument := 0
    index := 0
    while index < resolved.Count {
        candidate := resolved[index]
        assert candidate.Parameters.Length == candidate.ParameterTypes.Length
        if candidate.ParameterTypes.Length == 1 {
            listArgument = listArgument + 1

            // The parameter type is re-expressed in the INSTANTIATION's argument: `IList<T>`
            // becomes `IList<Item>`, never the open `IList<T>` the definition spells.
            assert !candidate.ParameterTypes[0].get_ContainsGenericParameters()
            assert candidate.ParameterTypes[0].GetGenericArguments()[0] is TypeBuilder
        }

        index = index + 1
    }

    assert listArgument == 1
}

test "an ordinary external base keeps answering directly" {
    assert !ColumnarExternalBaseConstructors.IsBuilderBoundInstantiation(typeof(Collection<string>))
    assert ColumnarExternalBaseConstructors.LookupType(typeof(Collection<string>)) == typeof(Collection<string>)

    resolved := ColumnarExternalBaseConstructors.Resolve(typeof(Collection<string>))
    assert resolved.Count == 2

    parameterless := ColumnarExternalBaseConstructors.ResolveParameterless(typeof(Collection<string>))
    assert parameterless != null
    assert parameterless.get_DeclaringType() == typeof(Collection<string>)
}

// WHICH LEVELS A DERIVED TYPE IN ANOTHER ASSEMBLY MAY CALL. `public`, `protected` and
// `protected internal` — never `internal`, `private protected` or `private`, because the assembly
// half of every level is unsatisfiable across a reference and N# models no `InternalsVisibleTo`.
test "an external base constructor is reachable at exactly three levels" {
    // `Exception()` is public; `Exception(SerializationInfo, StreamingContext)` is protected.
    resolved := ColumnarExternalBaseConstructors.Resolve(typeof(Exception))
    sawPublic := false
    sawProtected := false
    index := 0
    while index < resolved.Count {
        handle := resolved[index].Handle
        if handle.get_IsPublic() {
            sawPublic = true
        }

        if handle.get_IsFamily() {
            sawProtected = true
        }

        assert !handle.get_IsPrivate()
        assert !handle.get_IsAssembly()
        assert !handle.get_IsFamilyAndAssembly()
        index = index + 1
    }

    assert sawPublic
    assert sawProtected
}

test "a base with no accessible parameterless constructor answers nothing" {
    // `StreamWriter` declares no parameterless constructor at any level.
    assert ColumnarExternalBaseConstructors.ResolveParameterless(typeof(System.IO.StreamWriter)) == null
    assert ColumnarExternalBaseConstructors.ResolveParameterless(null) == null
    assert ColumnarExternalBaseConstructors.Resolve(null).Count == 0
}
