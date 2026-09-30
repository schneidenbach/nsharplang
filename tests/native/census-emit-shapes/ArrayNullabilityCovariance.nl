namespace NSharpLang.CensusEmitShapes.Tests

import System.Reflection


// NULLABILITY IS ARRAY-COVARIANT FOR READS, AND IN ONE DIRECTION. A reference nullable annotation is
// not a CLR type, so `T[]` and `T?[]` are one runtime array and the view costs nothing; every element
// read out of the widened view is honestly typed `T?`. This is the relation an `object[]` needs to
// reach a parameter declared `object?[]?` — `MethodInfo.Invoke`'s, which is where the census found it
// refused. A write of null through the widened view is the same hazard C# accepts.
func WidenStrings(values: string[]): string?[] {
    return values
}

func WidenObjects(values: object[]): object?[] {
    return values
}

func CountNonNull(widened: string?[]): int {
    total := 0
    for value in widened {
        if value != null {
            total = total + 1
        }
    }
    return total
}

// The same widening at a CALL position, into the BCL parameter the census reached it through.
func InvokeThrough(method: MethodInfo, target: object, arguments: object[]): object? {
    return method.Invoke(target, arguments)
}
