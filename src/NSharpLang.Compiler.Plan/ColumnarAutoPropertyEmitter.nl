namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// AN AUTO-PROPERTY, AS C# EMITS ONE.
//
// Two source shapes become a compiler-written property over a compiler-written field:
//
//   * `init Name: T` — `public T Name { get; init; }`. The setter's return type carries
//     `modreq(IsExternalInit)`, the CLR's only spelling of "settable while the object is being
//     created" (see `ColumnarInitRequiredMemberEmitter`).
//   * a bare `Name: T` that `MemberStorageRules` makes a property — `public T Name { get; set; }`.
//
// The metadata is C#'s, row for row: a `<Name>k__BackingField` stamped `[CompilerGenerated]` and
// `[DebuggerBrowsable(DebuggerBrowsableState.Never)]`, `get_Name`/`set_Name` stamped
// `[CompilerGenerated]`, and a `PropertyInfo` row carrying the member's attributes, its nullability
// and its tuple element names. That is what EF Core, System.Text.Json, model binding, a debugger and
// a decompiler all recognise as an auto-property.
//
// ONE DIFFERENCE IS DELIBERATE, and it is the backing field's accessibility for a get/set property.
// C# makes it `private`; N# makes it `assembly`. The accessors are the member's contract to every
// OTHER assembly, and inside this one the emitter reads and writes the storage directly — the same
// instruction a JIT makes of the trivial accessor once it inlines it, but at every tier and in every
// body, including a field initializer and a primary-constructor store that run before the base
// constructor, where calling a virtual-free setter on a not-yet-constructed `this` is not verifiable.
// Nothing outside the assembly can name the field: the name is unspellable in N# and C# alike, and a
// reflection-driven framework (EF Core's backing-field convention) finds it by name whatever its
// accessibility. An `init` property keeps C#'s `private` field: it is written only by the declaring
// type's own bodies and through the init accessor.
class ColumnarAutoPropertyEmitter {

    // THE BACKING FIELD'S NAME. C#'s own spelling, and deliberately unspellable in N# source: the
    // storage behind an auto-property is not a member the author wrote.
    static func BackingFieldName(propertyName: string): string {
        return "<" + propertyName + ">k__BackingField"
    }

    // DEFINE THE WHOLE MEMBER — backing field, both accessors, both bodies, and the `PropertyInfo` —
    // as one operation, so no caller can register half an auto-property.
    //
    // `labeledCanonical` is the property's type AS WRITTEN. A property is a PUBLIC signature position,
    // so its `?`s have to reach metadata or a consumer in another assembly reads the whole thing back
    // as non-null; the backing field carries the same annotation for the reader that walks fields.
    //
    // Registration differs by kind. An `init` property is in `Properties` and its storage is registered
    // under its backing-field name, so only the declaring type's own writes
    // (`ColumnarIlEmitter.TryFindInitAutoPropertyBackingField`) reach it. A get/set property's storage
    // is registered in `Fields` under the MEMBER'S name, so every in-assembly body that names the
    // member — a read, a write, `+=`, `++`, an object initializer, `with`, record equality — reaches the
    // same storage the accessors do; `SettableAutoProperties` holds the property fact (static get/set
    // auto-properties do not exist: `MemberStorageRules` keeps statics fields).
    static func Define(owner: ColumnarStructDef, propertyName: string, propertyType: Type, isStatic: bool, visibilityWord: int, isRequired: bool, implementsInterfaceValueSlot: bool, labeledCanonical: string?, isInitOnly: bool): ColumnarAutoPropertyDefinition {
        if owner == null || propertyName == null || propertyType == null {
            throw new InvalidOperationException("Auto-property definition inputs cannot be null.")
        }

        builder := owner.Builder
        // FieldAttributes.Private (1) for an init property's storage, FieldAttributes.Assembly (3)
        // for a get/set property's; FieldAttributes.Static (16) for a static one.
        backingFieldAttributes := isInitOnly ? 1 : 3
        if isStatic {
            backingFieldAttributes = backingFieldAttributes | 16
        }
        backingField := ColumnarFieldMetadataEmitter.Define(builder, BackingFieldName(propertyName), propertyType, backingFieldAttributes, false, false, 0)
        ApplyCompilerGeneratedToField(backingField)
        ApplyDebuggerBrowsableNever(backingField)
        ColumnarSignatureMetadataEmitter.ApplyToField(backingField, propertyType, labeledCanonical)

        // HideBySig 0x0080, SpecialName 0x0800, Static 0x0010 — the same word an ordinary accessor
        // carries. An auto-property that fills an interface's read slot takes that slot the way any
        // other value member does: Virtual|Final|NewSlot on the GETTER only, because an interface's
        // value member is a read slot and nothing asks its setter to be virtual.
        getterWord := visibilityWord | 0x0080 | 0x0800
        setterWord := getterWord
        if isStatic {
            getterWord = getterWord | 0x0010
            setterWord = setterWord | 0x0010
        } else if implementsInterfaceValueSlot {
            getterWord = getterWord | 0x0040 | 0x0100 | 0x0020
        }

        getter := builder.DefineMethod("get_" + propertyName, (MethodAttributes)getterWord, propertyType, new Type[](0))
        ApplyCompilerGeneratedToMethod(getter)
        EmitGetterBody(getter.GetILGenerator(), backingField, isStatic)

        setterParameters := new Type[](1)
        setterParameters[0] = propertyType
        setter := builder.DefineMethod(
            "set_" + propertyName,
            (MethodAttributes)setterWord,
            CallingConventions.Standard,
            ColumnarTypeOfPlanner.RequiredVoidType(),
            ColumnarInitRequiredMemberEmitter.SetterReturnModifiersFor(isInitOnly),
            null,
            setterParameters,
            null,
            null
        )
        setter.DefineParameter(1, ParameterAttributes.None, "value")
        ApplyCompilerGeneratedToMethod(setter)
        EmitSetterBody(setter.GetILGenerator(), backingField, isStatic)

        property := builder.DefineProperty(propertyName, PropertyAttributes.None, propertyType, Type.EmptyTypes)
        ColumnarSignatureMetadataEmitter.ApplyToProperty(property, propertyType, labeledCanonical)
        property.SetGetMethod(getter)
        property.SetSetMethod(setter)
        if isRequired {
            ColumnarInitRequiredMemberEmitter.ApplyRequiredMemberToProperty(property)
        }

        definition := new ColumnarPropertyDef(getter, setter, propertyType, new ColumnarPropertyDefinitionToken(), isInitOnly)
        if !isInitOnly {
            // A GET/SET PROPERTY IS ITS STORAGE to every body in this assembly: one `Fields` entry under
            // the member's own name, and the property fact beside it (never in `Properties` too).
            owner.SettableAutoProperties[propertyName] = definition
            owner.Fields[propertyName] = backingField
            return new ColumnarAutoPropertyDefinition(definition, property, backingField)
        }

        owner.AutoPropertyBackingFields.Add(BackingFieldName(propertyName))
        if isStatic {
            owner.StaticProperties[propertyName] = definition
            owner.StaticFields[BackingFieldName(propertyName)] = backingField
        } else {
            owner.Properties[propertyName] = definition
            owner.Fields[BackingFieldName(propertyName)] = backingField
        }

        return new ColumnarAutoPropertyDefinition(definition, property, backingField)
    }

    // WHETHER A FIELD HANDLE IS AN AUTO-PROPERTY'S STORAGE. The name is the proof: `<Name>k__BackingField`
    // cannot be written in N# or C#, so no declared field has it. A body that reads such a field reads
    // a PROPERTY's value, which is a copy — so it is never "direct storage" a mutating call or a
    // by-address hop may take the address of.
    static func IsBackingField(field: FieldInfo?): bool {
        if field == null {
            return false
        }

        name := field.Name
        return name.StartsWith("<", StringComparison.Ordinal) && name.EndsWith(">k__BackingField", StringComparison.Ordinal)
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

    static func ApplyCompilerGeneratedToField(field: FieldBuilder) {
        field.SetCustomAttribute(ColumnarInitRequiredMemberEmitter.CompilerGeneratedAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
    }

    static func ApplyCompilerGeneratedToMethod(method: MethodBuilder) {
        method.SetCustomAttribute(ColumnarInitRequiredMemberEmitter.CompilerGeneratedAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
    }

    // `[DebuggerBrowsable(DebuggerBrowsableState.Never)]`: a debugger shows the property and hides
    // the storage, so a watch window lists `Name` once rather than twice. The enum argument is its
    // underlying `int`, `Never` being 0.
    static func ApplyDebuggerBrowsableNever(field: FieldBuilder) {
        attributeType := typeof(object).Assembly.GetType("System.Diagnostics.DebuggerBrowsableAttribute")
        stateType := typeof(object).Assembly.GetType("System.Diagnostics.DebuggerBrowsableState")
        if attributeType == null || stateType == null {
            throw new InvalidOperationException("The DebuggerBrowsableAttribute runtime type was not found.")
        }

        parameters := new Type[](1)
        parameters[0] = stateType
        constructor := attributeType.GetConstructor(parameters)
        if constructor == null {
            throw new InvalidOperationException("The DebuggerBrowsableAttribute(DebuggerBrowsableState) constructor was not found.")
        }

        field.SetCustomAttribute(constructor, ColumnarAttributeBlobs.OneInt32(0))
    }
}

// What `ColumnarAutoPropertyEmitter.Define` produced: the property fact the emitter's tables hold,
// and the two metadata rows a written attribute may land on.
class ColumnarAutoPropertyDefinition {
    Definition: ColumnarPropertyDef
    Property: PropertyBuilder
    BackingField: FieldBuilder

    constructor(definition: ColumnarPropertyDef, property: PropertyBuilder, backingField: FieldBuilder) {
        Definition = definition
        Property = property
        BackingField = backingField
    }
}
