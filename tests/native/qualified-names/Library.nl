namespace NSharpLang.QualifiedNames.Library


// A LIBRARY IN ITS OWN NAMESPACE, reached from the test namespace ONLY by its qualified name: no
// file in this project imports `NSharpLang.QualifiedNames.Library`, so every reference to these
// declarations in the test sources proves namespace qualification and nothing else.
class Helper {
    static Answer: int => 42
    static Origin: string = "library"

    static func Twice(value: int): int {
        return value * 2
    }

    static func Concat(left: string, right: string): string {
        return left + right
    }
}

enum Season {
    Spring = 0,
    Summer = 1,
    Autumn = 2,
    Winter = 3
}
