namespace NSharpLang.CensusEmitShapes.Tests

import System

test "typeof(void) emits the runtime System.Void identity" {
    assert VoidTypeFacts.VoidType() == typeof(void)
    assert VoidTypeFacts.VoidType().FullName == "System.Void"
    assert VoidTypeFacts.VoidTypeName() == "Void"
}

test "typeof(void) is the identity a reflected void method reports" {
    nothing := typeof(VoidTypeFacts).GetMethod("DoesNothing", new Type[](0))
    if nothing == null {
        throw new InvalidOperationException("The void oracle method was not emitted.")
    }
    assert nothing.ReturnType == VoidTypeFacts.VoidType()
    assert VoidTypeFacts.MatchesVoid(nothing.ReturnType)
    assert !VoidTypeFacts.MatchesVoid(typeof(int))
}
