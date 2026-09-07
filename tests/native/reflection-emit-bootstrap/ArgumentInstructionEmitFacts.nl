namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection
import System.Reflection.Emit

// The migrated argument helper retains the original C# instruction selection exactly: load slots
// 0..3 have dedicated opcodes, the three helper families use byte operands through 255, and their
// long forms consume the existing int overload above that boundary. This fixture emits one real
// method per observation so the tests can inspect the baked bytes and invoke the same body.
class ArgumentInstructionObservation {
    Il: int[]
    Result: int

    constructor(il: int[], result: int) {
        Il = il
        Result = result
    }
}

class ArgumentInstructionEmitFacts {
    static func SetArgument(values: object?[], index: int, value: object?) {
        values[index] = value
    }

    static func EmptyTypes(): Type[] {
        return new Type[](0)
    }

    static func EmptyArguments(): object?[] {
        return new object?[](0)
    }

    static func OneInt32Type(): Type[] {
        types := new Type[](1)
        types[0] = typeof(int)
        return types
    }

    static func RequiredRuntimeType(name: string): Type {
        value := Type.GetType(name)
        if value == null {
            throw new InvalidOperationException("Required runtime type '" + name + "' was not found.")
        }
        return value
    }

    static func RequiredMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
        method := owner.GetMethod(name, parameterTypes)
        if method == null {
            throw new InvalidOperationException("Required method '" + owner.get_FullName() + "." + name + "' was not found.")
        }
        return method
    }

    static func RequiredInvocation(method: MethodInfo, receiver: object?, arguments: object?[]): object {
        result := method.Invoke(receiver, arguments)
        if result == null {
            throw new InvalidOperationException("Required reflection invocation returned null.")
        }
        return result
    }

    static func RequiredStaticField(owner: Type, name: string): object {
        field := owner.GetField(name)
        if field == null {
            throw new InvalidOperationException("Required static field '" + owner.get_FullName() + "." + name + "' was not found.")
        }
        value := field.GetValue(null)
        if value == null {
            throw new InvalidOperationException("Required static field '" + owner.get_FullName() + "." + name + "' was null.")
        }
        return value
    }

    static func CreateOwner(name: string): TypeBuilder {
        assemblyBuilderType := RequiredRuntimeType("System.Reflection.Emit.AssemblyBuilder")
        assemblyBuilderAccessType := RequiredRuntimeType("System.Reflection.Emit.AssemblyBuilderAccess")
        moduleBuilderType := RequiredRuntimeType("System.Reflection.Emit.ModuleBuilder")

        assemblyParameterTypes := new Type[](2)
        assemblyParameterTypes[0] = typeof(AssemblyName)
        assemblyParameterTypes[1] = assemblyBuilderAccessType
        defineAssembly := RequiredMethod(assemblyBuilderType, "DefineDynamicAssembly", assemblyParameterTypes)
        assemblyArguments := new object?[](2)
        SetArgument(assemblyArguments, 0, new AssemblyName(name + "Assembly"))
        SetArgument(assemblyArguments, 1, RequiredStaticField(assemblyBuilderAccessType, "Run"))
        assembly := RequiredInvocation(defineAssembly, null, assemblyArguments)

        moduleParameterTypes := new Type[](1)
        moduleParameterTypes[0] = typeof(string)
        defineModule := RequiredMethod(assemblyBuilderType, "DefineDynamicModule", moduleParameterTypes)
        moduleArguments := new object?[](1)
        SetArgument(moduleArguments, 0, name + "Module")
        module := RequiredInvocation(defineModule, assembly, moduleArguments)

        typeParameterTypes := new Type[](2)
        typeParameterTypes[0] = typeof(string)
        typeParameterTypes[1] = typeof(TypeAttributes)
        defineType := RequiredMethod(moduleBuilderType, "DefineType", typeParameterTypes)
        typeArguments := new object?[](2)
        SetArgument(typeArguments, 0, name)
        SetArgument(typeArguments, 1, TypeAttributes.Public)
        ownerObject := RequiredInvocation(defineType, module, typeArguments)
        owner := ownerObject as TypeBuilder
        if owner == null {
            throw new InvalidOperationException("The argument instruction fixture owner was not a TypeBuilder.")
        }
        return owner
    }

    static func DefineMethod(owner: TypeBuilder, name: string, parameterTypes: Type[]): MethodBuilder {
        definitionTypes := new Type[](4)
        definitionTypes[0] = typeof(string)
        definitionTypes[1] = typeof(MethodAttributes)
        definitionTypes[2] = typeof(Type)
        definitionTypes[3] = typeof(Type[])
        defineMethod := RequiredMethod(typeof(TypeBuilder), "DefineMethod", definitionTypes)
        arguments := new object?[](4)
        SetArgument(arguments, 0, name)
        SetArgument(arguments, 1, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig)
        SetArgument(arguments, 2, typeof(int))
        SetArgument(arguments, 3, parameterTypes)
        value := RequiredInvocation(defineMethod, owner, arguments)
        method := value as MethodBuilder
        if method == null {
            throw new InvalidOperationException("The argument instruction fixture method was not a MethodBuilder.")
        }
        return method
    }

    static func Bake(owner: TypeBuilder): Type {
        createType := RequiredMethod(typeof(TypeBuilder), "CreateType", EmptyTypes())
        bakedObject := RequiredInvocation(createType, owner, EmptyArguments())
        baked := bakedObject as Type
        if baked == null {
            throw new InvalidOperationException("The argument instruction fixture did not bake a runtime type.")
        }
        return baked
    }

    static func ReadIl(method: MethodInfo): int[] {
        getBody := RequiredMethod(typeof(MethodBase), "GetMethodBody", EmptyTypes())
        body := RequiredInvocation(getBody, method, EmptyArguments())
        getBytes := RequiredMethod(body.GetType(), "GetILAsByteArray", EmptyTypes())
        bytes := RequiredInvocation(getBytes, body, EmptyArguments())
        arrayType := bytes.GetType()
        getLength := RequiredMethod(arrayType, "get_Length", EmptyTypes())
        length := Convert.ToInt32(RequiredInvocation(getLength, bytes, EmptyArguments()))
        getValue := RequiredMethod(arrayType, "GetValue", OneInt32Type())
        indexArguments := new object?[](1)
        result := new int[](length)
        index := 0
        while index < length {
            SetArgument(indexArguments, 0, index)
            result[index] = Convert.ToInt32(RequiredInvocation(getValue, bytes, indexArguments))
            index = index + 1
        }
        return result
    }

    static func ParameterTypes(count: int): Type[] {
        types := new Type[](count)
        index := 0
        while index < types.Length {
            types[index] = typeof(int)
            index = index + 1
        }
        return types
    }

    static func InvocationArguments(count: int): object?[] {
        arguments := new object?[](count)
        index := 0
        while index < arguments.Length {
            // Every slot has a unique answer, including the 255/256 boundary.
            SetArgument(arguments, index, index * 7 + 3)
            index = index + 1
        }
        return arguments
    }

    static func EffectiveOrdinal(index: int): int {
        // The original helper has no negative guard: its explicit byte conversion wraps -1 to 255.
        if index == -1 {
            return 255
        }
        return index
    }

    static func NameSuffix(index: int): string {
        if index == -1 {
            return "NegativeOne"
        }
        return index.ToString()
    }

    // These three helpers are the exact connected source surface being unblocked.
    static func EmitLoad(il: ILGenerator, index: int) {
        if index == 0 {
            il.Emit(OpCodes.Ldarg_0)
        } else if index == 1 {
            il.Emit(OpCodes.Ldarg_1)
        } else if index == 2 {
            il.Emit(OpCodes.Ldarg_2)
        } else if index == 3 {
            il.Emit(OpCodes.Ldarg_3)
        } else if index <= 255 {
            il.Emit(OpCodes.Ldarg_S, (byte)index)
        } else {
            il.Emit(OpCodes.Ldarg, index)
        }
    }

    static func EmitStore(il: ILGenerator, index: int) {
        if index <= 255 {
            il.Emit(OpCodes.Starg_S, (byte)index)
        } else {
            il.Emit(OpCodes.Starg, index)
        }
    }

    static func EmitLoadAddress(il: ILGenerator, index: int) {
        if index <= 255 {
            il.Emit(OpCodes.Ldarga_S, (byte)index)
        } else {
            il.Emit(OpCodes.Ldarga, index)
        }
    }

    static func ObserveLoad(index: int): ArgumentInstructionObservation {
        suffix := NameSuffix(index)
        ordinal := EffectiveOrdinal(index)
        parameterTypes := ParameterTypes(ordinal + 1)
        owner := CreateOwner("ArgumentLoad" + suffix)
        builder := DefineMethod(owner, "Load", parameterTypes)
        il := builder.GetILGenerator()
        EmitLoad(il, index)
        il.Emit(OpCodes.Ret)

        baked := Bake(owner)
        method := RequiredMethod(baked, "Load", parameterTypes)
        value := Convert.ToInt32(RequiredInvocation(method, null, InvocationArguments(ordinal + 1)))
        return new ArgumentInstructionObservation(ReadIl(method), value)
    }

    static func ObserveStore(index: int): ArgumentInstructionObservation {
        suffix := NameSuffix(index)
        ordinal := EffectiveOrdinal(index)
        parameterTypes := ParameterTypes(ordinal + 1)
        owner := CreateOwner("ArgumentStore" + suffix)
        builder := DefineMethod(owner, "Store", parameterTypes)
        il := builder.GetILGenerator()
        il.Emit(OpCodes.Ldc_I4, 12345)
        EmitStore(il, index)
        EmitLoad(il, index)
        il.Emit(OpCodes.Ret)

        baked := Bake(owner)
        method := RequiredMethod(baked, "Store", parameterTypes)
        value := Convert.ToInt32(RequiredInvocation(method, null, InvocationArguments(ordinal + 1)))
        return new ArgumentInstructionObservation(ReadIl(method), value)
    }

    static func ObserveLoadAddress(index: int): ArgumentInstructionObservation {
        suffix := NameSuffix(index)
        ordinal := EffectiveOrdinal(index)
        parameterTypes := ParameterTypes(ordinal + 1)
        owner := CreateOwner("ArgumentAddress" + suffix)
        builder := DefineMethod(owner, "Address", parameterTypes)
        il := builder.GetILGenerator()
        EmitLoadAddress(il, index)
        il.Emit(OpCodes.Ldind_I4)
        il.Emit(OpCodes.Ret)

        baked := Bake(owner)
        method := RequiredMethod(baked, "Address", parameterTypes)
        value := Convert.ToInt32(RequiredInvocation(method, null, InvocationArguments(ordinal + 1)))
        return new ArgumentInstructionObservation(ReadIl(method), value)
    }

    static func FormatIl(il: int[]): string {
        result := ""
        index := 0
        while index < il.Length {
            if index > 0 {
                result = result + "|"
            }
            result = result + il[index].ToString()
            index = index + 1
        }
        return result
    }
}
