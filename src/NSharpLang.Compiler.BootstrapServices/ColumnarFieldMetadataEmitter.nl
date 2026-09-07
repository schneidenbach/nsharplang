namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// Own the complete field-definition metadata operation. The C# assembly executor supplies only a
// planned attribute word and ThreadStatic fact; it does not decode visibility or choose whether a
// custom attribute is attached. Other field declaration phases remain with the temporary host.
class ColumnarFieldMetadataEmitter {
    static func Define(owner: TypeBuilder, name: string, fieldType: Type, attributeWord: int, isThreadStatic: bool): FieldBuilder {
        attributes := (FieldAttributes)attributeWord
        field := owner.DefineField(name, fieldType, attributes)
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
}
