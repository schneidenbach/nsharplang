namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Reflection

sealed class InputBuilderConstructorVisibility {
    private constructor() {
    }

    static func Value(): int {
        return 17
    }
}

test "a sealed utility class retains its explicit private constructor and usable static surface" {
    owner := typeof(InputBuilderConstructorVisibility)
    assert owner.get_IsPublic(), "utility type must retain its public top-level surface"
    assert owner.get_IsSealed(), "utility type must retain sealed metadata"

    publicConstructors := owner.GetConstructors(
        BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    assert publicConstructors.Length == 0, "explicit private constructor must not be emitted as public"

    privateConstructors := owner.GetConstructors(
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    assert privateConstructors.Length == 1, "utility type must expose exactly one non-public constructor"
    privateConstructor := privateConstructors[0]
    assert privateConstructor.get_IsPrivate(), "explicit private constructor must retain private metadata"
    assert privateConstructor.GetParameters().Length == 0, "private utility constructor must remain parameterless"

    assert InputBuilderConstructorVisibility.Value() == 17, "static utility surface must remain directly callable"
}
