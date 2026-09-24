namespace NSharpLang.Compiler.Columnar

import System
import System.Diagnostics
import System.IO

class ColumnarRuntimeTypeFacts {
    static func IsSupportedDirectCallInteropType(clrType: Type): bool {
        if clrType == typeof(Stream) {
            return true
        }

        fileStreamType := Type.GetType("System.IO.FileStream")
        if fileStreamType != null && clrType == fileStreamType {
            return true
        }

        directoryInfoType := Type.GetType("System.IO.DirectoryInfo")
        return directoryInfoType != null && clrType == directoryInfoType
    }

    static func IsSupportedProcessInteropType(clrType: Type): bool {
        return clrType == typeof(Process) || clrType == typeof(ProcessStartInfo) || clrType == typeof(StreamReader)
    }
}
