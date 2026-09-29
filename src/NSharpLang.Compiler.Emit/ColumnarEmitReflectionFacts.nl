namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

class ColumnarEmitReflectionFacts {
    static func EmitMethod(generator: ILGenerator, opcode: OpCode, method: MethodInfo?, lookup: string): void {
        generator.Emit(opcode, RequiredMethod(method, lookup))
    }

    static func EmitConstructor(generator: ILGenerator, opcode: OpCode, constructor: ConstructorInfo?, lookup: string): void {
        generator.Emit(opcode, RequiredConstructor(constructor, lookup))
    }

    static func EmitType(generator: ILGenerator, opcode: OpCode, type: Type?, lookup: string): void {
        generator.Emit(opcode, RequiredType(type, lookup))
    }

    static func RequiredElementType(elementType: Type?, lookup: string): Type {
        if elementType == null {
            throw new InvalidOperationException("Compiler internal error: " + lookup + " did not provide an element type.")
        }
        return elementType
    }

    static func RequiredType(value: Type?, lookup: string): Type {
        if value == null {
            throw new InvalidOperationException("Compiler internal error: " + lookup + " did not provide a CLR type.")
        }
        return value
    }

    static func RequiredMethod(method: MethodInfo?, lookup: string): MethodInfo {
        if method == null {
            throw new InvalidOperationException("Compiler internal error: required CLR method lookup '" + lookup + "' returned no method.")
        }
        return method
    }

    static func RequiredMethodBuilder(method: MethodBuilder?, lookup: string): MethodBuilder {
        if method == null {
            throw new InvalidOperationException("Compiler internal error: required emitted method '" + lookup + "' was not defined.")
        }
        return method
    }

    static func RequiredConstructor(constructor: ConstructorInfo?, lookup: string): ConstructorInfo {
        if constructor == null {
            throw new InvalidOperationException("Compiler internal error: required CLR constructor lookup '" + lookup + "' returned no constructor.")
        }
        return constructor
    }

    static func RequiredField(field: FieldInfo?, lookup: string): FieldInfo {
        if field == null {
            throw new InvalidOperationException("Compiler internal error: required CLR field lookup '" + lookup + "' returned no field.")
        }
        return field
    }

    static func RequiredProperty(property: PropertyInfo?, lookup: string): PropertyInfo {
        if property == null {
            throw new InvalidOperationException("Compiler internal error: required CLR property lookup '" + lookup + "' returned no property.")
        }
        return property
    }

    static func RequiredGetter(property: PropertyInfo?, lookup: string): MethodInfo {
        requiredProperty := RequiredProperty(property, lookup)
        getter := requiredProperty.GetGetMethod()
        if getter == null {
            throw new InvalidOperationException("Compiler internal error: required getter '" + lookup + "' was not found.")
        }
        return getter
    }
}
