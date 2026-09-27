namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// `init` AND `required`, AS THE CLR SPELLS THEM.
//
// Both words are promises about WHEN a member may be written, and the CLR has exactly one place to
// record each of them:
//
//   * `init Name: string` is an INIT-ONLY AUTO-PROPERTY. The promise — "writable while the object is
//     being created, never afterwards" — lives on the SETTER'S RETURN TYPE, as
//     `modreq(System.Runtime.CompilerServices.IsExternalInit)`. That is not decoration: it is the
//     only marker C#, F# and VB all read, and a reader that ignores it simply sees an ordinary
//     settable property. A FIELD cannot carry the promise at all, because a field has no setter, so
//     an `init` row becomes a property with a private `[CompilerGenerated]` backing field — exactly
//     what C# emits for `public string Name { get; init; }`.
//
//   * `required Name: string` stays whatever it was written as — a field or a property — and gains
//     `[RequiredMember]`. The TYPE gains `[RequiredMember]` too, and every constructor gains
//     `[CompilerFeatureRequired("RequiredMembers")]`, which is how a type tells an older compiler
//     that it must not construct it: a compiler that does not understand the feature name refuses
//     the constructor rather than silently skipping the members the type demands.
//
// Both attribute sets are read back by the analyzer, on N#'s own types and on C#'s alike, which is
// why they are metadata and not a side table.
class ColumnarInitRequiredMemberEmitter {

    // The marker whose presence on a setter's return type MAKES the setter an init accessor. It is a
    // runtime type (System.Runtime), not a synthesized one: an emitted assembly that spelled its own
    // copy would make a promise no other compiler would read.
    static func ExternalInitMarkerType(): Type {
        marker := typeof(object).Assembly.GetType("System.Runtime.CompilerServices.IsExternalInit")
        if marker == null {
            throw new InvalidOperationException("The IsExternalInit runtime type was not found.")
        }

        return marker
    }

    static func InitOnlySetterReturnModifiers(): Type[] {
        modifiers := new Type[](1)
        modifiers[0] = ExternalInitMarkerType()
        return modifiers
    }

    // The setter-return modifier list a property row needs: the `IsExternalInit` marker for an
    // `init` accessor, and nothing at all for an ordinary `set`.
    static func SetterReturnModifiersFor(isInitOnly: bool): Type[]? {
        if isInitOnly {
            return InitOnlySetterReturnModifiers()
        }

        return null
    }

    static func RequiredMemberAttributeConstructor(): ConstructorInfo {
        return NoArgumentAttributeConstructor("System.Runtime.CompilerServices.RequiredMemberAttribute")
    }

    static func CompilerGeneratedAttributeConstructor(): ConstructorInfo {
        return NoArgumentAttributeConstructor("System.Runtime.CompilerServices.CompilerGeneratedAttribute")
    }

    static func NoArgumentAttributeConstructor(fullName: string): ConstructorInfo {
        attributeType := typeof(object).Assembly.GetType(fullName)
        if attributeType == null {
            throw new InvalidOperationException("The runtime type '" + fullName + "' was not found.")
        }

        constructor := attributeType.GetConstructor(new Type[](0))
        if constructor == null {
            throw new InvalidOperationException("The no-argument constructor of '" + fullName + "' was not found.")
        }

        return constructor
    }

    // `[CompilerFeatureRequired("RequiredMembers")]`, whose single argument is the feature NAME. The
    // string is the one the runtime defines for this feature; a different spelling would be a
    // different feature and would not guard anything.
    static func CompilerFeatureRequiredAttributeConstructor(): ConstructorInfo {
        attributeType := typeof(object).Assembly.GetType("System.Runtime.CompilerServices.CompilerFeatureRequiredAttribute")
        if attributeType == null {
            throw new InvalidOperationException("The CompilerFeatureRequiredAttribute runtime type was not found.")
        }

        parameters := new Type[](1)
        parameters[0] = typeof(string)
        constructor := attributeType.GetConstructor(parameters)
        if constructor == null {
            throw new InvalidOperationException("The CompilerFeatureRequiredAttribute(string) constructor was not found.")
        }

        return constructor
    }

    static func RequiredMembersFeatureName(): string {
        return "RequiredMembers"
    }

    static func ApplyRequiredMemberToField(field: FieldBuilder) {
        field.SetCustomAttribute(RequiredMemberAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
    }

    static func ApplyRequiredMemberToProperty(property: PropertyBuilder) {
        property.SetCustomAttribute(RequiredMemberAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
    }

    static func ApplyRequiredMemberToType(builder: TypeBuilder) {
        builder.SetCustomAttribute(RequiredMemberAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
    }

    static func ApplyCompilerFeatureRequiredToConstructor(builder: ConstructorBuilder) {
        builder.SetCustomAttribute(CompilerFeatureRequiredAttributeConstructor(), ColumnarAttributeBlobs.OneString(RequiredMembersFeatureName()))
    }

    // Whether the declaration writes `required` on ANY member. The type-level attribute and the
    // per-constructor guard are decided from this one question, and it is asked of the INPUT rather
    // than of the emitted builders because a type under construction answers no reflection question.
    static func DeclaresRequiredMember(input: ColumnarStructInput): bool {
        for fieldRequiredFlag2 in input.FieldRequiredFlags {
            if fieldRequiredFlag2 {
                return true
            }
        }

        for property2 in input.Properties {
            if property2.IsRequired {
                return true
            }
        }

        return false
    }

    // THE BACKING FIELD'S NAME. C#'s own spelling, and deliberately unspellable in N# source: the
    // storage behind an init-only property is not a member the author wrote, and nothing but the two
    // accessors this class emits may reach it.
    static func BackingFieldName(propertyName: string): string {
        return "<" + propertyName + ">k__BackingField"
    }

    // DEFINE THE WHOLE MEMBER — backing field, both accessors, both bodies, and the `PropertyInfo` —
    // as one operation, so no caller can register half an init-only property.
    //
    // `labeledCanonical` is the property's type AS WRITTEN. An init-only property is a PUBLIC signature
    // position like any other, so its `?`s have to reach metadata or a consumer in another assembly
    // reads the whole thing back as non-null; the backing field is private and carries the same
    // annotation for the reader that walks it.
    static func Define(owner: ColumnarStructDef, propertyName: string, propertyType: Type, isStatic: bool, visibilityWord: int, isRequired: bool, implementsInterfaceValueSlot: bool, labeledCanonical: string? = null): ColumnarPropertyDef {
        if owner == null || propertyName == null || propertyType == null {
            throw new InvalidOperationException("Init-only property definition inputs cannot be null.")
        }

        builder := owner.Builder
        backingFieldAttributes := 1
        // FieldAttributes.Private
        if isStatic {
            backingFieldAttributes = backingFieldAttributes | 16
        }
        // FieldAttributes.Static
        backingField := ColumnarFieldMetadataEmitter.Define(builder, BackingFieldName(propertyName), propertyType, backingFieldAttributes, false, false, 0)
        backingField.SetCustomAttribute(CompilerGeneratedAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
        ColumnarSignatureMetadataEmitter.ApplyToField(backingField, propertyType, labeledCanonical)

        // HideBySig 0x0080, SpecialName 0x0800, Static 0x0010 — the same word an ordinary accessor
        // carries. An init-only property that fills an interface's read slot takes that slot the way
        // any other value member does: Virtual|Final|NewSlot on the GETTER only, because an
        // interface's value member is a read slot and nothing asks its setter to be virtual.
        getterWord := visibilityWord | 0x0080 | 0x0800
        setterWord := getterWord
        if isStatic {
            getterWord = getterWord | 0x0010
            setterWord = setterWord | 0x0010
        } else if implementsInterfaceValueSlot {
            getterWord = getterWord | 0x0040 | 0x0100 | 0x0020
        }

        getter := builder.DefineMethod("get_" + propertyName, (MethodAttributes)getterWord, propertyType, new Type[](0))
        EmitGetterBody(getter.GetILGenerator(), backingField, isStatic)

        setterParameters := new Type[](1)
        setterParameters[0] = propertyType
        setter := builder.DefineMethod(
            "set_" + propertyName,
            (MethodAttributes)setterWord,
            CallingConventions.Standard,
            ColumnarTypeOfPlanner.RequiredVoidType(),
            InitOnlySetterReturnModifiers(),
            null,
            setterParameters,
            null,
            null
        )
        setter.DefineParameter(1, ParameterAttributes.None, "value")
        EmitSetterBody(setter.GetILGenerator(), backingField, isStatic)

        property := builder.DefineProperty(propertyName, PropertyAttributes.None, propertyType, Type.EmptyTypes)
        ColumnarSignatureMetadataEmitter.ApplyToProperty(property, propertyType, labeledCanonical)
        property.SetGetMethod(getter)
        property.SetSetMethod(setter)
        if isRequired {
            ApplyRequiredMemberToProperty(property)
        }

        definition := new ColumnarPropertyDef(getter, setter, propertyType, new ColumnarPropertyDefinitionToken(), true)
        owner.AutoPropertyBackingFields.Add(BackingFieldName(propertyName))
        if isStatic {
            owner.StaticProperties[propertyName] = definition
            owner.StaticFields[BackingFieldName(propertyName)] = backingField
        } else {
            owner.Properties[propertyName] = definition
            owner.Fields[BackingFieldName(propertyName)] = backingField
        }

        return definition
    }

    static func EmitGetterBody(il: ILGenerator, backingField: FieldBuilder, isStatic: bool) {
        if isStatic {
            il.Emit(OpCodes.Ldsfld, backingField)
            il.Emit(OpCodes.Ret)
            return
        }

        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldfld, backingField)
        il.Emit(OpCodes.Ret)
    }

    static func EmitSetterBody(il: ILGenerator, backingField: FieldBuilder, isStatic: bool) {
        if isStatic {
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Stsfld, backingField)
            il.Emit(OpCodes.Ret)
            return
        }

        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldarg_1)
        il.Emit(OpCodes.Stfld, backingField)
        il.Emit(OpCodes.Ret)
    }
}
