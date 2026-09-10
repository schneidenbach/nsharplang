namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// Own the complete field-definition metadata operation. The C# assembly executor supplies only a
// planned attribute word and ThreadStatic fact; it does not decode visibility or choose whether a
// custom attribute is attached. Other field declaration phases remain with the temporary host.
class ColumnarFieldMetadataEmitter {
    static func Define(owner: TypeBuilder, name: string, fieldType: Type, attributeWord: int, isThreadStatic: bool, isLiteral: bool = false, literalValue: int = 0): FieldBuilder {
        attributes := (FieldAttributes)attributeWord
        field := owner.DefineField(name, fieldType, attributes)
        if isLiteral {
            field.SetConstant(literalValue)
        }
        if isThreadStatic {
            attributeType := typeof(object).get_Assembly().GetType("System.ThreadStaticAttribute")
            if attributeType == null {
                throw new InvalidOperationException("The ThreadStaticAttribute runtime type was not found.")
            }
            constructor := attributeType.GetConstructor(new Type[](0))
            if constructor == null {
                throw new InvalidOperationException("The no-argument ThreadStaticAttribute constructor was not found.")
            }
            field.SetCustomAttribute(constructor, ColumnarAttributeBlobs.NoArgument())
        }
        return field
    }

    // The first literal-field slice is intentionally bounded to the three public `int` constants
    // consumed by the Playground facade. Keep the source text and initializer kind validation at
    // the metadata boundary so an expression, suffix, or another field type cannot accidentally
    // become a CLR Constant row with a changed type contract.
    static func TryGetIntLiteralValue(fieldType: Type, initializerKind: int, text: string, out value: int): bool {
        value = 0
        if fieldType != typeof(int) || initializerKind != 1 || text == null || text.Length == 0 {
            return false
        }

        literalKind := 0
        magnitude := 0UL
        if !ColumnarScalarLiteralPlanner.TryParseIntegerLiteral(text, out literalKind, out magnitude) || literalKind != 0 || magnitude > 2147483647UL {
            return false
        }

        value = (int)magnitude
        return true
    }

    static func TryEmitIntLiteralLoad(il: ILGenerator, fieldType: Type, value: int): bool {
        if il == null || fieldType != typeof(int) {
            return false
        }

        il.Emit(OpCodes.Ldc_I4, value)
        return true
    }
}
