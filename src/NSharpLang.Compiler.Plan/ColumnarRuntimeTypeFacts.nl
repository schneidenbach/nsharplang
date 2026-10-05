namespace NSharpLang.Compiler.Columnar

import System
import System.Diagnostics
import System.IO
import System.Reflection

class ColumnarRuntimeTypeFacts {
    static func RequiredElementType(clrType: Type): Type {
        elementType := clrType.GetElementType()
        if elementType == null {
            throw new InvalidOperationException("Compiler internal error: CLR type '" + clrType.ToString() + "' has no element type.")
        }
        return elementType
    }

    static func RequiredConstructor(owner: Type, parameterTypes: Type[], display: string): ConstructorInfo {
        constructor := owner.GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("Compiler internal error: required CLR constructor " + display + " was not found.")
        }
        return constructor
    }

    static func RequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
        method := owner.GetMethod(name, parameterTypes)
        if method == null {
            throw new InvalidOperationException("Compiler internal error: required CLR method '" + owner.ToString() + "." + name + "' was not found.")
        }
        return method
    }

    static func RequiredField(owner: Type, name: string): FieldInfo {
        field := owner.GetField(name)
        if field == null {
            throw new InvalidOperationException("Compiler internal error: required CLR field '" + owner.ToString() + "." + name + "' was not found.")
        }
        return field
    }

    static func RequiredDeclaringType(member: MemberInfo): Type {
        declaringType := member.DeclaringType
        if declaringType == null {
            throw new InvalidOperationException("Compiler internal error: reflected member '" + member.ToString() + "' has no declaring type.")
        }
        return declaringType
    }

    static func IsSupportedDirectCallInteropType(clrType: Type): bool {
        if clrType == typeof(Stream) {
            return true
        }

        fileStreamType := RequiredRuntimeTypes.Find("System.IO.FileStream")
        if fileStreamType != null && clrType == fileStreamType {
            return true
        }

        directoryInfoType := RequiredRuntimeTypes.Find("System.IO.DirectoryInfo")
        return directoryInfoType != null && clrType == directoryInfoType
    }

    static func IsSupportedProcessInteropType(clrType: Type): bool {
        return clrType == typeof(Process) || clrType == typeof(ProcessStartInfo) || clrType == typeof(StreamReader)
    }
}
