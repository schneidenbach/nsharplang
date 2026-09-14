namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Reflection
import System.Reflection.Emit

// The iterator realization path builds an instance continuation in a generated constructor:
// `ldarg.0; ldftn MoveNextCore; newobj Action(object, IntPtr); stfld`.  This fixture builds that
// exact CLR shape through the public Reflection.Emit surface, then proves both the runtime target
// and the metadata token in the baked constructor.
class LdftnContinuationIlEvidence {
    Target: MethodInfo
    Count: int

    constructor(target: MethodInfo, count: int) {
        Target = target
        Count = count
    }
}

class LdftnContinuationResult {
    Calls: int
    TargetName: string
    TargetOwnerName: string
    TargetToken: int
    CoreToken: int
    LdftnCount: int
    DelegateTargetsMachine: bool

    constructor(
        calls: int,
        targetName: string,
        targetOwnerName: string,
        targetToken: int,
        coreToken: int,
        ldftnCount: int,
        delegateTargetsMachine: bool
    ) {
        Calls = calls
        TargetName = targetName
        TargetOwnerName = targetOwnerName
        TargetToken = targetToken
        CoreToken = coreToken
        LdftnCount = ldftnCount
        DelegateTargetsMachine = delegateTargetsMachine
    }
}

class LdftnContinuationEmitFacts {
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

    static func VoidType(): Type {
        noTypes := EmptyTypes()
        invoke := RequiredMethod(typeof(Action), "Invoke", noTypes)
        return invoke.get_ReturnType()
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

    static func RequiredConstructor(owner: Type, parameterTypes: Type[]): ConstructorInfo {
        constructor := owner.GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("Required constructor for '" + owner.get_FullName() + "' was not found.")
        }

        return constructor
    }

    static func RequiredInvocation(method: MethodInfo, receiver: object?, values: object?[]): object {
        result := method.Invoke(receiver, values)
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
        assemblyName := new AssemblyName(name + "Assembly")
        runAccess := RequiredStaticField(assemblyBuilderAccessType, "Run")
        SetArgument(assemblyArguments, 0, assemblyName)
        SetArgument(assemblyArguments, 1, runAccess)
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
            throw new InvalidOperationException("The continuation fixture owner was not a TypeBuilder.")
        }

        return owner
    }

    static func DefineField(owner: TypeBuilder, name: string, fieldType: Type): FieldBuilder {
        parameterTypes := new Type[](3)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(Type)
        parameterTypes[2] = typeof(FieldAttributes)
        defineField := RequiredMethod(typeof(TypeBuilder), "DefineField", parameterTypes)
        arguments := new object?[](3)
        SetArgument(arguments, 0, name)
        SetArgument(arguments, 1, fieldType)
        SetArgument(arguments, 2, FieldAttributes.Public)
        value := RequiredInvocation(defineField, owner, arguments)
        field := value as FieldBuilder
        if field == null {
            throw new InvalidOperationException("The continuation fixture field was not a FieldBuilder.")
        }

        return field
    }

    static func DefineMethod(owner: TypeBuilder, name: string): MethodBuilder {
        parameterTypes := new Type[](4)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(MethodAttributes)
        parameterTypes[2] = typeof(Type)
        parameterTypes[3] = typeof(Type[])
        defineMethod := RequiredMethod(typeof(TypeBuilder), "DefineMethod", parameterTypes)
        arguments := new object?[](4)
        SetArgument(arguments, 0, name)
        SetArgument(arguments, 1, MethodAttributes.Public | MethodAttributes.HideBySig)
        voidType := VoidType()
        SetArgument(arguments, 2, voidType)
        noTypes := EmptyTypes()
        SetArgument(arguments, 3, noTypes)
        value := RequiredInvocation(defineMethod, owner, arguments)
        method := value as MethodBuilder
        if method == null {
            throw new InvalidOperationException("The continuation core was not a MethodBuilder.")
        }

        return method
    }

    static func DefineConstructor(owner: TypeBuilder): ConstructorBuilder {
        parameterTypes := new Type[](3)
        parameterTypes[0] = typeof(MethodAttributes)
        parameterTypes[1] = typeof(CallingConventions)
        parameterTypes[2] = typeof(Type[])
        defineConstructor := RequiredMethod(typeof(TypeBuilder), "DefineConstructor", parameterTypes)
        arguments := new object?[](3)
        SetArgument(arguments, 0, MethodAttributes.Public | MethodAttributes.HideBySig)
        SetArgument(arguments, 1, CallingConventions.Standard)
        intTypes := OneInt32Type()
        SetArgument(arguments, 2, intTypes)
        value := RequiredInvocation(defineConstructor, owner, arguments)
        constructor := value as ConstructorBuilder
        if constructor == null {
            throw new InvalidOperationException("The continuation constructor was not a ConstructorBuilder.")
        }

        return constructor
    }

    static func Bake(owner: TypeBuilder): Type {
        noTypes := EmptyTypes()
        emptyArguments := EmptyArguments()
        createType := RequiredMethod(typeof(TypeBuilder), "CreateType", noTypes)
        bakedObject := RequiredInvocation(createType, owner, emptyArguments)
        baked := bakedObject as Type
        if baked == null {
            throw new InvalidOperationException("The continuation fixture did not bake a runtime type.")
        }

        return baked
    }

    static func ReadConstructorIl(constructor: ConstructorInfo): int[] {
        noTypes := EmptyTypes()
        emptyArguments := EmptyArguments()
        getBody := RequiredMethod(typeof(MethodBase), "GetMethodBody", noTypes)
        body := RequiredInvocation(getBody, constructor, emptyArguments)
        getBytes := RequiredMethod(body.GetType(), "GetILAsByteArray", noTypes)
        bytes := RequiredInvocation(getBytes, body, emptyArguments)
        arrayType := bytes.GetType()
        getLength := RequiredMethod(arrayType, "get_Length", noTypes)
        lengthValue := RequiredInvocation(getLength, bytes, emptyArguments)
        length := Convert.ToInt32(lengthValue)
        intTypes := OneInt32Type()
        getValue := RequiredMethod(arrayType, "GetValue", intTypes)
        values := new object?[](1)
        il := new int[](length)
        index := 0
        while index < length {
            SetArgument(values, 0, index)
            il[index] = Convert.ToInt32(RequiredInvocation(getValue, bytes, values))
            index = index + 1
        }

        return il
    }

    static func ReadInt32(il: int[], index: int): int {
        return il[index] | (il[index + 1] << 8) | (il[index + 2] << 16) | (il[index + 3] << 24)
    }

    static func LdftnEvidence(constructor: ConstructorInfo): LdftnContinuationIlEvidence {
        il := ReadConstructorIl(constructor)
        position := 0
        count := 0
        target: MethodInfo? = null
        intTypes := OneInt32Type()
        resolve := RequiredMethod(typeof(Module), "ResolveMethod", intTypes)
        tokenArguments := new object?[](1)

        while position < il.Length {
            opcode := il[position]
            position = position + 1
            if opcode == 254 {
                if position >= il.Length {
                    throw new InvalidOperationException("The continuation constructor ended after the opcode prefix.")
                }
                extension := il[position]
                position = position + 1
                if extension != 6 {
                    throw new InvalidOperationException("The continuation constructor carried an unexpected two-byte opcode.")
                }
                if position + 4 > il.Length {
                    throw new InvalidOperationException("The continuation constructor carried a truncated ldftn token.")
                }
                token := ReadInt32(il, position)
                position = position + 4
                SetArgument(tokenArguments, 0, token)
                module := constructor.get_Module()
                resolvedObject := RequiredInvocation(resolve, module, tokenArguments)
                resolved := resolvedObject as MethodInfo
                if resolved == null {
                    throw new InvalidOperationException("The ldftn token did not resolve to a method.")
                }
                target = resolved
                count = count + 1
            } else if opcode == 2 || opcode == 42 {
            } else if opcode == 40 || opcode == 115 || opcode == 125 {
                // ldarg.0 and ret carry no operands.

                // call, newobj and stfld each carry an InlineMethod/InlineField token.
                position = position + 4
            } else {
                throw new InvalidOperationException("The continuation constructor carried an unexpected one-byte opcode.")
            }
        }

        if target == null {
            throw new InvalidOperationException("The continuation constructor had no ldftn instruction.")
        }

        return new LdftnContinuationIlEvidence(target, count)
    }

    static func EmitAndInvoke(): LdftnContinuationResult {
        owner := CreateOwner("LdftnContinuationOwner")
        callsBuilder := DefineField(owner, "Calls", typeof(int))
        continuationBuilder := DefineField(owner, "<>__continuation", typeof(Action))
        coreBuilder := DefineMethod(owner, "MoveNextCore")

        // These BCL base-class views are the precise operand forms consumed by ILGenerator.Emit.
        callsHandle: FieldInfo = callsBuilder
        continuationHandle: FieldInfo = continuationBuilder
        coreHandle: MethodInfo = coreBuilder

        coreIl := coreBuilder.GetILGenerator()
        coreIl.Emit(OpCodes.Ldarg_0)
        coreIl.Emit(OpCodes.Dup)
        coreIl.Emit(OpCodes.Ldfld, callsHandle)
        coreIl.Emit(OpCodes.Ldc_I4_1)
        coreIl.Emit(OpCodes.Add)
        coreIl.Emit(OpCodes.Stfld, callsHandle)
        coreIl.Emit(OpCodes.Ret)

        constructorBuilder := DefineConstructor(owner)
        constructorIl := constructorBuilder.GetILGenerator()
        noTypes := EmptyTypes()
        objectConstructor := RequiredConstructor(typeof(object), noTypes)
        actionParameters := new Type[](2)
        actionParameters[0] = typeof(object)
        actionParameters[1] = typeof(IntPtr)
        actionConstructor := RequiredConstructor(typeof(Action), actionParameters)

        constructorIl.Emit(OpCodes.Ldarg_0)
        constructorIl.Emit(OpCodes.Call, objectConstructor)
        constructorIl.Emit(OpCodes.Ldarg_0)
        constructorIl.Emit(OpCodes.Ldarg_0)
        constructorIl.Emit(OpCodes.Ldftn, coreHandle)
        constructorIl.Emit(OpCodes.Newobj, actionConstructor)
        constructorIl.Emit(OpCodes.Stfld, continuationHandle)
        constructorIl.Emit(OpCodes.Ret)

        baked := Bake(owner)
        intTypes := OneInt32Type()
        constructor := RequiredConstructor(baked, intTypes)
        constructorArguments := new object?[](1)
        SetArgument(constructorArguments, 0, 0)
        machine := constructor.Invoke(constructorArguments)
        if machine == null {
            throw new InvalidOperationException("The baked continuation constructor returned null.")
        }

        continuationField := baked.GetField("<>__continuation")
        callsField := baked.GetField("Calls")
        if continuationField == null || callsField == null {
            throw new InvalidOperationException("The baked continuation fields were not found.")
        }
        continuationObject := continuationField.GetValue(machine)
        continuation := continuationObject as Action
        if continuation == null {
            throw new InvalidOperationException("The baked continuation field was not an Action.")
        }
        invoke := RequiredMethod(typeof(Action), "Invoke", noTypes)
        emptyArguments := EmptyArguments()
        _ = invoke.Invoke(continuation, emptyArguments)

        evidence := LdftnEvidence(constructor)
        declaringType := evidence.Target.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("The ldftn target had no declaring type.")
        }

        bakedCore := RequiredMethod(baked, "MoveNextCore", noTypes)
        return new LdftnContinuationResult(
            Convert.ToInt32(callsField.GetValue(machine)),
            evidence.Target.get_Name(),
            declaringType.get_Name(),
            evidence.Target.get_MetadataToken(),
            bakedCore.get_MetadataToken(),
            evidence.Count,
            Object.ReferenceEquals(continuation.get_Target(), machine)
        )
    }
}
