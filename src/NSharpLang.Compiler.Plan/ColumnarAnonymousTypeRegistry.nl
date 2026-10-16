namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// ONE ANONYMOUS-OBJECT SHAPE, AS THE TYPE THAT CARRIES IT.
//
// `new { Name: "Alice", Age: 30 }` is a value of a type nobody can name, and C# answers what that type
// is the same way every time: a sealed, internal, GENERIC class per ordered list of property NAMES,
// closed over the property TYPES at each creation. `new { Name: "Bob", Age: 4 }` and
// `new { Name: 1.5, Age: "x" }` share one template — `<>f__AnonymousType0<<Name>j__TPar,
// <Age>j__TPar>` — and differ only in its instantiation. That is not an optimisation: it is what lets
// an anonymous object carry a value whose type is a type PARAMETER of the method that creates it,
// which no non-generic synthesized class could hold.
//
// The template is the whole contract C# gives an anonymous type: a constructor that takes every
// property in written order, read-only properties over `initonly` fields, VALUE equality through
// `EqualityComparer<T>.Default` for `Equals(object)` and `GetHashCode()`, and the
// `{ Name = Alice, Age = 30 }` rendering for `ToString()`.
class ColumnarAnonymousTypeTemplate {
    Names: string[]
    Builder: TypeBuilder
    Fields: FieldBuilder[]
    Getters: MethodBuilder[]
    Constructor: ConstructorBuilder

    constructor(names: string[], builder: TypeBuilder, fields: FieldBuilder[], getters: MethodBuilder[], constructorBuilder: ConstructorBuilder) {
        Names = names
        Builder = builder
        Fields = fields
        Getters = getters
        Constructor = constructorBuilder
    }

    func IndexOf(name: string): int {
        for index := 0; index < Names.Length; index++ {
            if Names[index] == name {
                return index
            }
        }
        return -1
    }

    // The type one creation produces. An empty shape has no type parameters and IS its own type.
    func Close(propertyTypes: Type[]): Type {
        if Names.Length == 0 {
            return Builder
        }
        return Builder.MakeGenericType(propertyTypes)
    }

    func ConstructorOn(closedType: Type): ConstructorInfo {
        if Names.Length == 0 {
            return Constructor
        }
        return TypeBuilder.GetConstructor(closedType, Constructor)
    }

    // A property's getter and type on a CLOSED instantiation. The type is the instantiation's type
    // argument, never the getter's own return type: a rebound getter still reports the open
    // `<Name>j__TPar`.
    func GetterOn(closedType: Type, index: int): MethodInfo => TypeBuilder.GetMethod(closedType, Getters[index])

    static func PropertyTypeOn(closedType: Type, index: int): Type => closedType.GetGenericArguments()[index]
}

// EVERY ANONYMOUS-OBJECT TEMPLATE ONE ASSEMBLY PASS DEFINES, KEYED BY ITS ORDERED PROPERTY NAMES.
//
// One registry lives on the emit session's `ColumnarEmitContext`, so every body of the assembly —
// a free function, a member, a lambda — that writes the same shape reaches the SAME template, which
// is what makes two such objects the same CLR type and therefore comparable and storable together.
// Templates are defined on first use and appended to the session's synthesized-type list, which bakes
// them with the closure display classes before the assembly is written.
class ColumnarAnonymousTypeRegistry {
    // C#'s own multiplier for the property-by-property hash.
    private static readonly s_hashMultiplier: int = -1521134295

    private readonly module: ModuleBuilder
    private readonly synthesizedTypes: List<TypeBuilder>
    private readonly templatesByShape: Dictionary<string, ColumnarAnonymousTypeTemplate>
    private readonly templatesByBuilder: Dictionary<TypeBuilder, ColumnarAnonymousTypeTemplate>

    constructor(moduleBuilder: ModuleBuilder, synthesizedTypeSink: List<TypeBuilder>) {
        module = moduleBuilder
        synthesizedTypes = synthesizedTypeSink
        templatesByShape = new Dictionary<string, ColumnarAnonymousTypeTemplate>(StringComparer.Ordinal)
        templatesByBuilder = new Dictionary<TypeBuilder, ColumnarAnonymousTypeTemplate>()
    }

    // Property names are identifiers, so a comma can never be part of one and the joined list is an
    // unambiguous key.
    static func ShapeKey(names: string[]): string {
        return String.Join(",", names)
    }

    func GetOrDefine(names: string[]): ColumnarAnonymousTypeTemplate {
        key := ShapeKey(names)
        let existing: ColumnarAnonymousTypeTemplate? = null
        if templatesByShape.TryGetValue(key, out existing) && existing != null {
            return existing
        }

        template := DefineTemplate(names, templatesByShape.Count)
        templatesByShape[key] = template
        templatesByBuilder[template.Builder] = template
        synthesizedTypes.Add(template.Builder)
        return template
    }

    // The template behind a type, whether the type is the (non-generic) empty template itself or an
    // instantiation of a generic one.
    func TryFind(candidate: Type?, out template: ColumnarAnonymousTypeTemplate?): bool {
        template = null
        if candidate == null {
            return false
        }

        let builder: TypeBuilder? = candidate as TypeBuilder
        if builder == null && candidate.IsGenericType && !candidate.IsGenericTypeDefinition {
            builder = candidate.GetGenericTypeDefinition() as TypeBuilder
        }

        if builder == null {
            return false
        }

        return templatesByBuilder.TryGetValue(builder, out template)
    }

    func IsAnonymousType(candidate: Type?): bool {
        let template: ColumnarAnonymousTypeTemplate? = null
        return TryFind(candidate, out template)
    }

    // A READ of `obj.Name`: the getter rebound onto the receiver's instantiation and the property's
    // closed type. An anonymous property has no setter, so there is no write counterpart.
    func TryResolveProperty(receiverType: Type?, name: string, out getter: MethodInfo?, out propertyType: Type?): bool {
        getter = null
        propertyType = null
        let template: ColumnarAnonymousTypeTemplate? = null
        if receiverType == null || !TryFind(receiverType, out template) || template == null || receiverType.IsGenericTypeDefinition {
            return false
        }

        index := template.IndexOf(name)
        if index < 0 {
            return false
        }

        getter = template.GetterOn(receiverType, index)
        propertyType = ColumnarAnonymousTypeTemplate.PropertyTypeOn(receiverType, index)
        return true
    }

    private func DefineTemplate(names: string[], ordinal: int): ColumnarAnonymousTypeTemplate {
        builder := module.DefineType(
            "<>f__AnonymousType" + ordinal.ToString(),
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object)
        )
        builder.SetCustomAttribute(ColumnarInitRequiredMemberEmitter.CompilerGeneratedAttributeConstructor(), ColumnarAttributeBlobs.NoArgument())
        builder.SetCustomAttribute(DebuggerDisplayAttributeConstructor(), ColumnarAttributeBlobs.StringWithNamedStringProperty(DebuggerDisplayText(names), "Type", "<Anonymous Type>"))

        typeParameters := new Type[names.Length]
        if names.Length > 0 {
            parameterNames := new string[names.Length]
            for index := 0; index < names.Length; index++ {
                parameterNames[index] = "<" + names[index] + ">j__TPar"
            }
            parameterBuilders := builder.DefineGenericParameters(parameterNames)
            for index := 0; index < parameterBuilders.Length; index++ {
                typeParameters[index] = parameterBuilders[index]
            }
        }

        fields := new FieldBuilder[names.Length]
        for index := 0; index < names.Length; index++ {
            fields[index] = builder.DefineField("<" + names[index] + ">i__Field", typeParameters[index], FieldAttributes.Private | FieldAttributes.InitOnly)
        }

        // Inside a generic definition every reference to its own members goes through the CURRENT
        // instantiation — `<>f__AnonymousType0<!0, !1>` — never through the open definition.
        selfType := ColumnarSourceSelfInstantiation.Of(builder)
        boundFields := new FieldInfo[names.Length]
        for index := 0; index < names.Length; index++ {
            boundFields[index] = ColumnarSourceSelfInstantiation.BindField(fields[index])
        }

        constructorBuilder := DefineConstructor(builder, names, typeParameters, boundFields)
        getters := new MethodBuilder[names.Length]
        for index := 0; index < names.Length; index++ {
            getter := builder.DefineMethod(
                "get_" + names[index],
                MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName,
                typeParameters[index],
                System.Type.EmptyTypes
            )
            getterIl := getter.GetILGenerator()
            getterIl.Emit(OpCodes.Ldarg_0)
            getterIl.Emit(OpCodes.Ldfld, boundFields[index])
            getterIl.Emit(OpCodes.Ret)
            property := builder.DefineProperty(names[index], PropertyAttributes.None, typeParameters[index], System.Type.EmptyTypes)
            property.SetGetMethod(getter)
            getters[index] = getter
        }

        DefineEquals(builder, selfType, typeParameters, boundFields)
        DefineGetHashCode(builder, names, typeParameters, boundFields)
        DefineToString(builder, names, typeParameters, boundFields)
        return new ColumnarAnonymousTypeTemplate(names, builder, fields, getters, constructorBuilder)
    }

    private static func DefineConstructor(builder: TypeBuilder, names: string[], typeParameters: Type[], boundFields: FieldInfo[]): ConstructorBuilder {
        constructorBuilder := builder.DefineConstructor(
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.SpecialName | MethodAttributes.RTSpecialName,
            CallingConventions.Standard,
            typeParameters
        )
        for index := 0; index < names.Length; index++ {
            constructorBuilder.DefineParameter(index + 1, ParameterAttributes.None, names[index])
        }

        objectConstructor := typeof(object).GetConstructor(System.Type.EmptyTypes) ?? throw new InvalidOperationException("System.Object has no parameterless constructor.")
        il := constructorBuilder.GetILGenerator()
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Call, objectConstructor)
        for index := 0; index < names.Length; index++ {
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Ldarg, (short)(index + 1))
            il.Emit(OpCodes.Stfld, boundFields[index])
        }
        il.Emit(OpCodes.Ret)
        return constructorBuilder
    }

    // `this == value || (value is Self other && EqualityComparer<T0>.Default.Equals(f0, other.f0) && ...)`.
    private static func DefineEquals(builder: TypeBuilder, selfType: Type, typeParameters: Type[], boundFields: FieldInfo[]) {
        objectParameters := new Type[1]
        objectParameters[0] = typeof(object)
        equals := builder.DefineMethod(
            "Equals",
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.Virtual,
            typeof(bool),
            objectParameters
        )
        equals.DefineParameter(1, ParameterAttributes.None, "value")
        il := equals.GetILGenerator()
        other := il.DeclareLocal(selfType)
        returnTrue := il.DefineLabel()
        returnFalse := il.DefineLabel()
        il.Emit(OpCodes.Ldarg_1)
        il.Emit(OpCodes.Isinst, selfType)
        il.Emit(OpCodes.Stloc, other)
        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldloc, other)
        il.Emit(OpCodes.Beq, returnTrue)
        il.Emit(OpCodes.Ldloc, other)
        il.Emit(OpCodes.Brfalse, returnFalse)
        for index := 0; index < boundFields.Length; index++ {
            comparerType := ComparerTypeFor(typeParameters[index])
            il.Emit(OpCodes.Call, ComparerMember(comparerType, "get_Default", 0))
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Ldfld, boundFields[index])
            il.Emit(OpCodes.Ldloc, other)
            il.Emit(OpCodes.Ldfld, boundFields[index])
            il.Emit(OpCodes.Callvirt, ComparerMember(comparerType, "Equals", 2))
            il.Emit(OpCodes.Brfalse, returnFalse)
        }
        il.MarkLabel(returnTrue)
        il.Emit(OpCodes.Ldc_I4_1)
        il.Emit(OpCodes.Ret)
        il.MarkLabel(returnFalse)
        il.Emit(OpCodes.Ldc_I4_0)
        il.Emit(OpCodes.Ret)
    }

    // `hash = seed; hash = hash * -1521134295 + EqualityComparer<Ti>.Default.GetHashCode(fi)` per
    // property, unchecked, exactly as C# writes it.
    private static func DefineGetHashCode(builder: TypeBuilder, names: string[], typeParameters: Type[], boundFields: FieldInfo[]) {
        hash := builder.DefineMethod(
            "GetHashCode",
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.Virtual,
            typeof(int),
            System.Type.EmptyTypes
        )
        il := hash.GetILGenerator()
        il.Emit(OpCodes.Ldc_I4, HashSeed(names))
        for index := 0; index < boundFields.Length; index++ {
            comparerType := ComparerTypeFor(typeParameters[index])
            il.Emit(OpCodes.Ldc_I4, s_hashMultiplier)
            il.Emit(OpCodes.Mul)
            il.Emit(OpCodes.Call, ComparerMember(comparerType, "get_Default", 0))
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Ldfld, boundFields[index])
            il.Emit(OpCodes.Callvirt, ComparerMember(comparerType, "GetHashCode", 1))
            il.Emit(OpCodes.Add)
        }
        il.Emit(OpCodes.Ret)
    }

    // `string.Format(null, "{{ Name = {0}, Age = {1} }}", new object[] { f0, f1 })`. A null property
    // renders as nothing, which is what `string.Format` does with a null argument and what C# prints.
    private static func DefineToString(builder: TypeBuilder, names: string[], typeParameters: Type[], boundFields: FieldInfo[]) {
        toString := builder.DefineMethod(
            "ToString",
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.Virtual,
            typeof(string),
            System.Type.EmptyTypes
        )
        il := toString.GetILGenerator()
        if names.Length == 0 {
            il.Emit(OpCodes.Ldstr, "{ }")
            il.Emit(OpCodes.Ret)
            return
        }

        formatParameters := new Type[3]
        formatParameters[0] = typeof(IFormatProvider)
        formatParameters[1] = typeof(string)
        formatParameters[2] = typeof(object[])
        format := typeof(string).GetMethod("Format", formatParameters) ?? throw new InvalidOperationException("String.Format(IFormatProvider, string, object[]) was not found.")
        il.Emit(OpCodes.Ldnull)
        il.Emit(OpCodes.Ldstr, ToStringFormat(names))
        il.Emit(OpCodes.Ldc_I4, names.Length)
        il.Emit(OpCodes.Newarr, typeof(object))
        for index := 0; index < boundFields.Length; index++ {
            il.Emit(OpCodes.Dup)
            il.Emit(OpCodes.Ldc_I4, index)
            il.Emit(OpCodes.Ldarg_0)
            il.Emit(OpCodes.Ldfld, boundFields[index])
            il.Emit(OpCodes.Box, typeParameters[index])
            il.Emit(OpCodes.Stelem_Ref)
        }
        il.Emit(OpCodes.Call, format)
        il.Emit(OpCodes.Ret)
    }

    // `{{ Name = {0}, Age = {1} }}` — the composite format whose output is `{ Name = Alice, Age = 30 }`.
    static func ToStringFormat(names: string[]): string {
        text := "{{ "
        for index := 0; index < names.Length; index++ {
            if index > 0 {
                text = text + ", "
            }
            text = text + names[index] + " = {" + index.ToString() + "}"
        }
        return text + " }}"
    }

    // `\{ Name = {Name}, Age = {Age} }` — the debugger evaluates each `{Name}` hole against the object.
    static func DebuggerDisplayText(names: string[]): string {
        if names.Length == 0 {
            return "\\{ }"
        }
        text := "\\{ "
        for index := 0; index < names.Length; index++ {
            if index > 0 {
                text = text + ", "
            }
            text = text + names[index] + " = {" + names[index] + "}"
        }
        return text + " }"
    }

    // A deterministic 32-bit FNV-1a over the ordered names, each followed by a comma. `String.GetHashCode`
    // is randomized per process, and an emitted constant must not change from one build of the same
    // source to the next. The arithmetic runs in `long` and is reduced modulo 2^32 at every step, so
    // it never relies on wrap-around.
    static func HashSeed(names: string[]): int {
        hash: long = 2166136261L
        for name in names {
            for index := 0; index < name.Length; index++ {
                hash = ((hash ^ (long)name[index]) * 16777619L) % 4294967296L
            }
            hash = ((hash ^ 44L) * 16777619L) % 4294967296L
        }
        if hash >= 2147483648L {
            hash = hash - 4294967296L
        }
        return (int)hash
    }

    private static func ComparerTypeFor(elementType: Type): Type {
        typeArguments := new Type[1]
        typeArguments[0] = elementType
        return typeof(EqualityComparer<int>).GetGenericTypeDefinition().MakeGenericType(typeArguments)
    }

    // `EqualityComparer<T>`'s `get_Default`, `Equals(T, T)` or `GetHashCode(T)`, rebound onto the
    // comparer closed over one of the template's own type parameters.
    private static func ComparerMember(comparerType: Type, name: string, parameterCount: int): MethodInfo {
        definition := typeof(EqualityComparer<int>).GetGenericTypeDefinition()
        for method in definition.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly) {
            parameters := method.GetParameters()
            if method.Name != name || parameters.Length != parameterCount {
                continue
            }
            if parameterCount > 0 && !parameters[0].ParameterType.IsGenericParameter {
                continue
            }
            return ColumnarClosedGenericMemberResolver.ResolveMethod(comparerType, method)
        }
        throw new InvalidOperationException("EqualityComparer<T>." + name + " was not found.")
    }

    private static func DebuggerDisplayAttributeConstructor(): ConstructorInfo {
        parameters := new Type[1]
        parameters[0] = typeof(string)
        return typeof(System.Diagnostics.DebuggerDisplayAttribute).GetConstructor(parameters) ?? throw new InvalidOperationException("DebuggerDisplayAttribute(string) was not found.")
    }
}
