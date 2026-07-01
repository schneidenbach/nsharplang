namespace NSharpLang.Compiler.Columnar

import System
import System.Diagnostics
import System.IO

public class ColumnarRuntimeTypeFacts {
    public static func IsSupportedProcessInteropType(clrType: Type): bool {
        return clrType == typeof(Process)
            || clrType == typeof(ProcessStartInfo)
            || clrType == typeof(StreamReader)
    }
}
