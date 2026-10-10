namespace NSharpLang.CensusEmitShapes.Tests

import System


// `typeof(void)` IS THE ONE TYPE POSITION THAT ADMITS `void`.
//
// `void` is a built-in type SPELLING everywhere a return type is written, but it is not a type a
// local, field, parameter or array element can hold, so the columnar binder's explicit-type builtin
// set deliberately omits it. `typeof` is the exception the CLR itself carries (C# §12.8.18): the
// type argument of `typeof` may be `void`, and only there. The lowering is the ordinary
// `ldtoken`/`Type.GetTypeFromHandle` pair every other target uses, and its value is the same
// `System.Void` a reflected `void` method reports as its return type.
class VoidTypeFacts {

    // The root position: the whole return expression is the `typeof`.
    static func VoidType(): Type {
        return typeof(void)
    }

    // A local initializer, which is where the reflected identity is compared against the runtime's
    // own answer for a `void` method.
    static func VoidTypeName(): string {
        candidate := typeof(void)
        return candidate.Name
    }

    // An operand of an ordinary reference comparison, so the token survives a binary operator.
    static func MatchesVoid(candidate: Type): bool {
        return candidate == typeof(void)
    }

    // An ordinary `void` method, used as the runtime oracle for the token above.
    static func DoesNothing() {
    }
}
