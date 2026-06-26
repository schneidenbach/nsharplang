namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

public class ColumnarEnumDef {
    enumTypeValue: Type
    constantsValue: Dictionary<string, int>

    EnumType: Type => enumTypeValue
    Constants: Dictionary<string, int> => constantsValue

    constructor(enumType: Type, constants: Dictionary<string, int>) {
        enumTypeValue = enumType
        constantsValue = constants
    }
}
