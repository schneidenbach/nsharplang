namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// AN AUTO-PROPERTY, AS C# EMITS ONE.
//
// Three source shapes become a compiler-written property over a compiler-written field:
//
//   * `init Name: T` — `public T Name { get; init; }`. The setter's return type carries
//     `modreq(IsExternalInit)`, the CLR's only spelling of "settable while the object is being
//     created" (see `ColumnarInitRequiredMemberEmitter`).
//   * a bare `Name: T` that `MemberStorageRules` makes a property — `public T Name { get; set; }`.
//   * the same bare member written `virtual`, `abstract` or `override` — C#'s
//     `public virtual T Name { get; set; }`, `public abstract T Name { get; set; }` and
//     `public override T Name { get; set; }`, the shape EF Core's lazy-loading proxies override.
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
//
// A DISPATCHED PROPERTY — `virtual`, `abstract`, `override` — IS THE EXCEPTION TO DIRECT ACCESS, and
// that is its whole meaning: an override replaces both accessors, so a body that read the storage
// would read the base's value while every other caller read the override's. Its storage is C#'s
// `private` field, registered under the backing-field name only, and the member itself is in
// `Properties` like a written property — so every in-assembly read, write, `+=`, `++`, object
// initializer and `with` goes through `callvirt` on the accessors. The one direct store left is the
// member's own initializer, which runs before the base constructor (as C#'s does) and therefore must
// not dispatch to an override whose type has not been constructed.
class ColumnarAutoPropertyEmitter {

    // THE INHERITANCE SHAPES, as the one number every door below reads: 0 a plain auto-property,
    // 1 `virtual`, 2 `abstract`, 3 `override`, 4 `sealed override`. The first four are the event
    // emitter's numbering, so a reader who met one meets the other.
    static func PlainProperty(): int {
        return 0
    }

    static func VirtualProperty(): int {
        return 1
    }

    static func AbstractProperty(): int {
        return 2
    }

    static func OverrideProperty(): int {
        return 3
    }

    static func SealedOverrideProperty(): int {
        return 4
    }

    // Whether the shape takes a base's slot rather than opening its own.
    static func IsOverride(inheritanceKind: int): bool {
        return inheritanceKind == OverrideProperty() || inheritanceKind == SealedOverrideProperty()
    }

    // `abstract` is asked first and `override` before `virtual`, the order the analyzer reports them
    // in, so a row that somehow carries two is read the same way by both halves. `sealed` means
    // something only beside `override`.
    static func InheritanceKindOf(isVirtual: bool, isAbstract: bool, isOverride: bool, isSealed: bool): int {
        if isAbstract {
            return AbstractProperty()
        }

        if isOverride {
            return isSealed ? SealedOverrideProperty() : OverrideProperty()
        }

        if isVirtual {
            return VirtualProperty()
        }

        return PlainProperty()
    }

    // ECMA-335 MethodAttributes: HideBySig 0x0080, SpecialName 0x0800, Static 0x0010, Virtual 0x0040,
    // NewSlot 0x0100, Abstract 0x0400, Final 0x0020. `virtual` and `abstract` each OPEN a slot
    // (Virtual|NewSlot), `abstract` supplying no IL; `override` REUSES the base's slot (Virtual, NewSlot
    // clear), which the CLR binds by name and signature exactly as it does for C#'s override, and
    // `sealed override` closes it again with Final. A plain
    // property that fills an interface's read slot takes it the way any value member does:
    // Virtual|Final|NewSlot on the GETTER only, because an interface's value member is a read slot and
    // nothing asks its setter to be virtual. A dispatched getter is already virtual, which an interface
    // slot accepts as it is.
    static func AccessorAttributeWord(visibilityWord: int, isStatic: bool, inheritanceKind: int, isGetter: bool, implementsInterfaceValueSlot: bool): int {
        word := visibilityWord | 0x0080 | 0x0800
        if isStatic {
            return word | 0x0010
        }

        if inheritanceKind == AbstractProperty() {
            return word | 0x0040 | 0x0100 | 0x0400
        }

        if inheritanceKind == VirtualProperty() {
            return word | 0x0040 | 0x0100
        }

        if inheritanceKind == OverrideProperty() {
            return word | 0x0040
        }

        if inheritanceKind == SealedOverrideProperty() {
            return word | 0x0040 | 0x0020
        }

        if isGetter && implementsInterfaceValueSlot {
            return word | 0x0040 | 0x0100 | 0x0020
        }

        return word
    }

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
    // (`ColumnarIlEmitter.TryFindInitAutoPropertyBackingField`) reach it. A dispatched property is
    // registered the same way and its storage is reached by nothing but its own accessors and its own
    // initializer (`TryFindInitializerAutoPropertyBackingField`); an abstract one has no storage at all.
    // A plain get/set property's storage
    // is registered in `Fields` under the MEMBER'S name, so every in-assembly body that names the
    // member — a read, a write, `+=`, `++`, an object initializer, `with`, record equality — reaches the
    // same storage the accessors do; `SettableAutoProperties` holds the property fact (static get/set
    // auto-properties do not exist: `MemberStorageRules` keeps statics fields).
    static func Define(owner: ColumnarStructDef, propertyName: string, propertyType: Type, isStatic: bool, visibilityWord: int, isRequired: bool, implementsInterfaceValueSlot: bool, labeledCanonical: string?, isInitOnly: bool): ColumnarAutoPropertyDefinition {
        return Define(owner, propertyName, propertyType, isStatic, visibilityWord, isRequired, implementsInterfaceValueSlot, labeledCanonical, isInitOnly, PlainProperty())
    }

    static func Define(owner: ColumnarStructDef, propertyName: string, propertyType: Type, isStatic: bool, visibilityWord: int, isRequired: bool, implementsInterfaceValueSlot: bool, labeledCanonical: string?, isInitOnly: bool, inheritanceKind: int): ColumnarAutoPropertyDefinition {
        if owner == null || propertyName == null || propertyType == null {
            throw new InvalidOperationException("Auto-property definition inputs cannot be null.")
        }

        // A static member has no slot, and an `init` accessor's in-type writes store the field
        // directly, which an override could not intercept. The analyzer refuses both (NL311); a row
        // that reaches here anyway is an internal contradiction, not a program to emit.
        isDispatched := inheritanceKind != PlainProperty()
        if isDispatched && (isStatic || isInitOnly) {
            throw new InvalidOperationException("A static or init-only auto-property cannot be virtual, abstract or overridden.")
        }

        builder := owner.Builder
        isAbstract := inheritanceKind == AbstractProperty()

        // AN ABSTRACT PROPERTY HAS NO STORAGE — its accessors are slots a derived type fills, as C#'s
        // `public abstract T Name { get; set; }` is. Every other shape owns its field: FieldAttributes
        // .Private (1) for an init or dispatched property's storage, which only its own accessors and
        // initializer reach, FieldAttributes.Assembly (3) for a plain get/set property's, which every
        // body in this assembly reaches; FieldAttributes.Static (16) for a static one.
        let backingField: FieldBuilder? = null
        if !isAbstract {
            backingFieldAttributes := isInitOnly || isDispatched ? 1 : 3
            if isStatic {
                backingFieldAttributes = backingFieldAttributes | 16
            }
            storage := ColumnarFieldMetadataEmitter.Define(builder, BackingFieldName(propertyName), propertyType, backingFieldAttributes, false, false, 0)
            ApplyCompilerGeneratedToField(storage)
            ApplyDebuggerBrowsableNever(storage)
            ColumnarSignatureMetadataEmitter.ApplyToField(storage, propertyType, labeledCanonical)
            backingField = storage
        }

        getterWord := AccessorAttributeWord(visibilityWord, isStatic, inheritanceKind, true, implementsInterfaceValueSlot)
        setterWord := AccessorAttributeWord(visibilityWord, isStatic, inheritanceKind, false, implementsInterfaceValueSlot)

        // An abstract property's accessors are slots, not compiler-written bodies, so — as in C# — they
        // carry no `[CompilerGenerated]`.
        getter := builder.DefineMethod("get_" + propertyName, (MethodAttributes)getterWord, propertyType, new Type[](0))
        if backingField != null {
            ApplyCompilerGeneratedToMethod(getter)
            EmitGetterBody(getter.GetILGenerator(), backingField, isStatic)
        }
        if implementsInterfaceValueSlot && !isStatic {
            ColumnarExplicitInterfaceImplementation.DefineNonPublicValueSlotFills(owner, getter, propertyName)
        }

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
        if backingField != null {
            ApplyCompilerGeneratedToMethod(setter)
            EmitSetterBody(setter.GetILGenerator(), backingField, isStatic)
        }

        property := builder.DefineProperty(propertyName, PropertyAttributes.None, propertyType, Type.EmptyTypes)
        ColumnarSignatureMetadataEmitter.ApplyToProperty(property, propertyType, labeledCanonical)
        property.SetGetMethod(getter)
        property.SetSetMethod(setter)
        if isRequired {
            ColumnarInitRequiredMemberEmitter.ApplyRequiredMemberToProperty(property)
        }

        definition := new ColumnarPropertyDef(getter, setter, propertyType, new ColumnarPropertyDefinitionToken(), isInitOnly)
        if !isInitOnly && !isDispatched {
            // A PLAIN GET/SET PROPERTY IS ITS STORAGE to every body in this assembly: one `Fields`
            // entry under the member's own name, and the property fact beside it (never in
            // `Properties` too).
            plainStorage := must backingField
            owner.SettableAutoProperties[propertyName] = definition
            owner.Fields[propertyName] = plainStorage
            return new ColumnarAutoPropertyDefinition(definition, property, plainStorage)
        }

        if isStatic {
            owner.StaticProperties[propertyName] = definition
        } else {
            owner.Properties[propertyName] = definition
        }

        if backingField != null {
            owner.AutoPropertyBackingFields.Add(BackingFieldName(propertyName))
            if isStatic {
                owner.StaticFields[BackingFieldName(propertyName)] = backingField
            } else {
                owner.Fields[BackingFieldName(propertyName)] = backingField
            }
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
// and the two metadata rows a written attribute may land on. An abstract property has no storage, so
// its `BackingField` is null.
class ColumnarAutoPropertyDefinition {
    Definition: ColumnarPropertyDef
    Property: PropertyBuilder
    BackingField: FieldBuilder?

    constructor(definition: ColumnarPropertyDef, property: PropertyBuilder, backingField: FieldBuilder?) {
        Definition = definition
        Property = property
        BackingField = backingField
    }
}

// AN `override` BARE MEMBER WAITING FOR ITS SLOT. Pass 0a''' records the row at its place in the field
// order and the declaration pass defines it once every slot it could take exists — a base's bare
// member and a base's written property alike, whatever order the source declares the types in.
class ColumnarDeferredOverrideAutoProperty {
    StructIndex: int
    FieldIndex: int
    FieldName: string
    FieldType: Type
    FillsInterfaceSlot: bool

    constructor(structIndex: int, fieldIndex: int, fieldName: string, fieldType: Type, fillsInterfaceSlot: bool) {
        StructIndex = structIndex
        FieldIndex = fieldIndex
        FieldName = fieldName
        FieldType = fieldType
        FillsInterfaceSlot = fillsInterfaceSlot
    }
}
