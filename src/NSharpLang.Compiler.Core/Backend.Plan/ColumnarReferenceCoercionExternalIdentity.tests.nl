namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ReferenceCoercionForeignDisposable(): Type {
    assemblyName := "NSharpTests.ForeignSystemDisposable"
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    builder := dynamicModule.DefineType(
        "System.IDisposable",
        TypeAttributes.Public | TypeAttributes.Interface | TypeAttributes.Abstract
    )
    builder.DefineMethod(
        "Dispose",
        MethodAttributes.Public | MethodAttributes.Abstract | MethodAttributes.Virtual | MethodAttributes.NewSlot | MethodAttributes.HideBySig,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    return IdentityBake(builder)
}

func ReferenceCoercionRuntimeDisposableSource(): ColumnarStructDef {
    disposableType := typeof(IDisposable)
    source := SourceCallDefinition(
        "ReferenceCoercionRuntimeDisposableSource",
        true
    )
    source.ExternalInterfaces.Add(disposableType)
    source.Builder.AddInterfaceImplementation(disposableType)
    source.DefaultCtor = source.Builder.DefineDefaultConstructor(MethodAttributes.Public)

    disposeTarget := disposableType.GetMethod("Dispose", new Type[](0))
    if disposeTarget == null {
        throw new InvalidOperationException("System.IDisposable.Dispose() was not found.")
    }
    dispose := source.Builder.DefineMethod(
        "Dispose",
        (MethodAttributes)486,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        new Type[](0)
    )
    dispose.GetILGenerator().Emit(OpCodes.Ret)
    source.Builder.DefineMethodOverride(dispose, disposeTarget)
    return source
}

test "external interface upcasts use exact assembly identity and execute for the matching runtime interface" {
    disposableType := typeof(IDisposable)
    foreignDisposable := ReferenceCoercionForeignDisposable()
    assert foreignDisposable.get_IsInterface()
    foreignFullName := foreignDisposable.get_FullName() ?? ""
    runtimeFullName := disposableType.get_FullName() ?? ""
    assert foreignFullName == runtimeFullName
    foreignIdentity := foreignDisposable.get_AssemblyQualifiedName() ?? ""
    runtimeIdentity := disposableType.get_AssemblyQualifiedName() ?? ""
    assert foreignIdentity != runtimeIdentity
    foreignAssembly := foreignDisposable.get_Assembly()
    runtimeAssembly := disposableType.get_Assembly()
    assert !Object.ReferenceEquals(foreignAssembly, runtimeAssembly)
    foreignDispose := foreignDisposable.GetMethod("Dispose", new Type[](0))
    if foreignDispose == null {
        throw new InvalidOperationException("The foreign IDisposable fixture lost its exact Dispose() member.")
    }
    assert foreignDispose.get_DeclaringType() == foreignDisposable

    source := ReferenceCoercionRuntimeDisposableSource()
    definitions := new ColumnarStructDef[](1)
    definitions[0] = source
    registry := ReferenceCoercionRegistry(definitions)

    assert ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        source.Builder,
        disposableType,
        registry
    )
    assert !ColumnarReferenceCoercionPlanner.CanUseExternalInterfaceUpcast(
        source.Builder,
        foreignDisposable,
        registry
    )

    rejectedIl := ReferenceCoercionIl("ReferenceCoercionForeignAssemblyRejected")
    rejectedOffset := ReferenceCoercionIlOffset(rejectedIl)
    assert !ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        source.Builder,
        foreignDisposable,
        registry,
        rejectedIl
    )
    assert ReferenceCoercionIlOffset(rejectedIl) == rejectedOffset

    sourceBuilder := source.Builder
    sourceBuilderType: Type = sourceBuilder
    parameterTypes := new Type[](1)
    parameterTypes[0] = sourceBuilderType
    upcast := sourceBuilder.DefineMethod(
        "AsDisposable",
        (MethodAttributes)22,
        disposableType,
        parameterTypes
    )
    upcastIl := upcast.GetILGenerator()
    upcastIl.Emit(OpCodes.Ldarg, (short)0)
    assert ColumnarReferenceCoercionPlanner.TryEmitExternalInterfaceUpcast(
        source.Builder,
        disposableType,
        registry,
        upcastIl
    )
    upcastIl.Emit(OpCodes.Ret)

    bakedSource := IdentityBake(source.Builder)
    assert disposableType.IsAssignableFrom(bakedSource)
    assert !foreignDisposable.IsAssignableFrom(bakedSource)
    constructor := bakedSource.GetConstructor(new Type[](0))
    if constructor == null {
        throw new InvalidOperationException("The source IDisposable fixture has no default constructor.")
    }
    instance := TypeOfRequiredConstruction(constructor, new object[](0))
    bakedParameterTypes := new Type[](1)
    bakedParameterTypes[0] = bakedSource
    bakedUpcast := bakedSource.GetMethod("AsDisposable", bakedParameterTypes)
    if bakedUpcast == null {
        throw new InvalidOperationException("The runtime upcast fixture was not baked.")
    }
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, instance)
    upcastResult := TypeOfRequiredInvocation(bakedUpcast, null, arguments)
    assert Object.ReferenceEquals(upcastResult, instance)
    assert disposableType.IsInstanceOfType(upcastResult)
    assert !foreignDisposable.IsInstanceOfType(upcastResult)
}
