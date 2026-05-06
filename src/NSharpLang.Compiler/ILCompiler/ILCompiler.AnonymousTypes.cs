using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private readonly Dictionary<string, TypeBuilder> _anonymousObjectTypes = new(StringComparer.Ordinal);
    private int _anonymousObjectTypeCounter = 0;

    private Type ResolveNewExpressionType(NewExpression newExpr)
    {
        if (newExpr.Type != null)
        {
            return ResolveType(newExpr.Type, _currentGenericParameters);
        }

        if (_expectedExpressionType != null && _expectedExpressionType != typeof(object))
        {
            return _expectedExpressionType;
        }

        if (IsAnonymousObjectCreation(newExpr))
        {
            return GetAnonymousObjectType(newExpr);
        }

        if (_expectedExpressionType != null)
        {
            return _expectedExpressionType;
        }

        throw new NotImplementedException("Target-typed new not yet supported in IL compiler without an expected type");
    }

    private static bool IsAnonymousObjectCreation(NewExpression newExpr)
    {
        return newExpr.Type == null
            && newExpr.ConstructorArguments.Count == 0
            && newExpr.Initializer != null
            && newExpr.Initializer.Properties.All(property =>
                property.Name != null
                && property.IndexExpression == null);
    }

    private Type GetAnonymousObjectType(NewExpression newExpr)
        => GetAnonymousObjectType(newExpr, GetExpressionType);

    private Type GetAnonymousObjectType(NewExpression newExpr, Func<Expression, Type> getPropertyType)
    {
        if (_moduleBuilder == null)
        {
            throw new InvalidOperationException("Anonymous object emission requires an active module builder");
        }

        if (!IsAnonymousObjectCreation(newExpr))
        {
            throw new InvalidOperationException("Anonymous object emission requires an initializer-only target-typed new expression");
        }

        var properties = newExpr.Initializer!.Properties
            .Select(property => (Name: property.Name!, Type: getPropertyType(property.Value)))
            .ToArray();
        var shapeKey = string.Join(
            "|",
            properties.Select(property => $"{property.Name}:{GetTypeKey(property.Type)}"));

        if (_anonymousObjectTypes.TryGetValue(shapeKey, out var existingType))
        {
            return existingType;
        }

        var typeBuilder = _moduleBuilder.DefineType(
            $"<>f__AnonymousType{_anonymousObjectTypeCounter++}",
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
            typeof(object));

        _typeKeys[typeBuilder] = typeBuilder.Name;
        _generatedHelperTypes.Add(typeBuilder);
        _anonymousObjectTypes[shapeKey] = typeBuilder;

        var defaultConstructor = typeBuilder.DefineDefaultConstructor(MethodAttributes.Public);
        _constructors[GetConstructorKey(typeBuilder)] = defaultConstructor;

        foreach (var property in properties)
        {
            DefineAnonymousObjectProperty(typeBuilder, property.Name, property.Type);
        }

        return typeBuilder;
    }

    private void DefineAnonymousObjectProperty(TypeBuilder typeBuilder, string propertyName, Type propertyType)
    {
        var backingField = typeBuilder.DefineField(
            $"<{propertyName}>k__BackingField",
            propertyType,
            FieldAttributes.Private);

        var propertyBuilder = typeBuilder.DefineProperty(
            propertyName,
            PropertyAttributes.None,
            propertyType,
            Type.EmptyTypes);

        var getter = typeBuilder.DefineMethod(
            $"get_{propertyName}",
            MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
            propertyType,
            Type.EmptyTypes);
        var getterIl = getter.GetILGenerator();
        getterIl.Emit(OpCodes.Ldarg_0);
        getterIl.Emit(OpCodes.Ldfld, backingField);
        getterIl.Emit(OpCodes.Ret);

        var setter = typeBuilder.DefineMethod(
            $"set_{propertyName}",
            MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig,
            typeof(void),
            new[] { propertyType });
        var setterIl = setter.GetILGenerator();
        setterIl.Emit(OpCodes.Ldarg_0);
        setterIl.Emit(OpCodes.Ldarg_1);
        setterIl.Emit(OpCodes.Stfld, backingField);
        setterIl.Emit(OpCodes.Ret);

        propertyBuilder.SetGetMethod(getter);
        propertyBuilder.SetSetMethod(setter);

        _methods[GetMethodKey(typeBuilder, getter.Name)] = getter;
        _methods[GetMethodKey(typeBuilder, setter.Name)] = setter;
    }
}
