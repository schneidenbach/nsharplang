namespace NSharpLang.Compiler

import System.Collections.Generic

class NSharpMethodGroupInfoFactory {
    static func FromFunctions(functions: IEnumerable<FunctionTypeInfo>): NSharpMethodGroupInfo {
        result := new List<FunctionTypeInfo>()
        for functionInfo in functions {
            result.Add(functionInfo)
        }

        return new NSharpMethodGroupInfo(result)
    }

    static func GetFunctions(methodGroup: NSharpMethodGroupInfo): List<FunctionTypeInfo> {
        result := new List<FunctionTypeInfo>()
        source := methodGroup.Functions

        index := 0
        while index < source.Count {
            result.Add(source[index])
            index = index + 1
        }

        return result
    }

    static func AddFunction(methodGroup: NSharpMethodGroupInfo, functionInfo: FunctionTypeInfo) {
        methodGroup.Functions.Add(functionInfo)
    }
}
