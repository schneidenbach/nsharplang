namespace NSharpLang.Compiler

import System.Collections.Generic

public class NSharpMethodGroupInfoFactory {
    public static func FromDeclarations(declarations: IEnumerable<object>): NSharpMethodGroupInfo {
        result := new List<object>()
        foreach declaration in declarations {
            result.Add(declaration)
        }

        return new NSharpMethodGroupInfo(result)
    }

    public static func GetDeclarations(methodGroup: NSharpMethodGroupInfo): List<object> {
        result := new List<object>()
        source := methodGroup.Declarations

        index := 0
        while index < source.Count {
            result.Add(source[index])
            index = index + 1
        }

        return result
    }

    public static func AddDeclaration(methodGroup: NSharpMethodGroupInfo, declaration: object) {
        methodGroup.Declarations.Add(declaration)
    }
}
