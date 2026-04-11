using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private sealed record DeclaredTypeInfo(string Name, Declaration Declaration, string? ContainingTypeName);

    private IEnumerable<DeclaredTypeInfo> EnumerateDeclaredTypes()
    {
        foreach (var declaration in _compilationUnit.Declarations)
        {
            foreach (var declaredType in EnumerateDeclaredTypes(declaration, containingTypeName: null))
            {
                yield return declaredType;
            }
        }
    }

    private IEnumerable<DeclaredTypeInfo> EnumerateDeclaredTypes(Declaration declaration, string? containingTypeName)
    {
        var name = GetDeclaredTypeName(declaration);
        if (string.IsNullOrWhiteSpace(name))
        {
            yield break;
        }

        var typeName = containingTypeName == null ? name : $"{containingTypeName}.{name}";
        yield return new DeclaredTypeInfo(typeName, declaration, containingTypeName);

        foreach (var nestedDeclaration in GetNestedTypeDeclarations(declaration))
        {
            foreach (var nestedType in EnumerateDeclaredTypes(nestedDeclaration, typeName))
            {
                yield return nestedType;
            }
        }
    }

    private bool TryGetDeclaredTypeInfo(string declaredTypeName, out DeclaredTypeInfo declaredType)
    {
        var match = EnumerateDeclaredTypes()
            .FirstOrDefault(candidate => string.Equals(candidate.Name, declaredTypeName, StringComparison.Ordinal));
        if (match == null)
        {
            declaredType = null!;
            return false;
        }

        declaredType = match;
        return true;
    }

    private string GetDeclaredTypeMetadataName(string typeName)
    {
        if (!TryGetDeclaredTypeInfo(typeName, out var declaredType) || declaredType.ContainingTypeName == null)
        {
            return typeName;
        }

        return GetDeclaredTypeMetadataName(declaredType.ContainingTypeName) + "+" + GetDeclaredTypeName(declaredType.Declaration);
    }

    private static IEnumerable<Declaration> GetNestedTypeDeclarations(Declaration declaration)
    {
        return declaration switch
        {
            ClassDeclaration classDeclaration => classDeclaration.Members.Where(IsTypeDeclaration),
            StructDeclaration structDeclaration => structDeclaration.Members.Where(IsTypeDeclaration),
            RecordDeclaration recordDeclaration => recordDeclaration.Members.Where(IsTypeDeclaration),
            InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Members.Where(IsTypeDeclaration),
            _ => Array.Empty<Declaration>()
        };
    }

    private static bool IsTypeDeclaration(Declaration declaration)
    {
        return declaration is ClassDeclaration
            or StructDeclaration
            or RecordDeclaration
            or InterfaceDeclaration
            or EnumDeclaration
            or UnionDeclaration
            or NewtypeDeclaration;
    }

    private static TypeAttributes GetNestedTypeVisibilityAttributes(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Private))
        {
            return TypeAttributes.NestedPrivate;
        }

        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return TypeAttributes.NestedFamORAssem;
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return TypeAttributes.NestedFamily;
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return TypeAttributes.NestedAssembly;
        }

        if (modifiers.HasFlag(Modifiers.Public))
        {
            return TypeAttributes.NestedPublic;
        }

        return !string.IsNullOrEmpty(name) && char.IsUpper(name[0])
            ? TypeAttributes.NestedPublic
            : TypeAttributes.NestedPrivate;
    }

    private bool IsStringEnumContainer(TypeBuilder typeBuilder)
    {
        return _stringEnumContainers.TryGetValue(GetTypeKey(typeBuilder), out var stringEnumContainer)
            && ReferenceEquals(stringEnumContainer, typeBuilder);
    }

    private Type GetDeclaredStaticFieldType(TypeBuilder staticTypeBuilder, string memberName, FieldInfo staticField)
    {
        var fieldKey = GetFieldKey(staticTypeBuilder, memberName);
        if (!_fieldConstants.ContainsKey(fieldKey))
        {
            return staticField.FieldType;
        }

        return IsStringEnumContainer(staticTypeBuilder) ? typeof(string) : staticTypeBuilder;
    }

    private bool TryEmitDeclaredStaticConstant(TypeBuilder staticTypeBuilder, string memberName)
    {
        var fieldKey = GetFieldKey(staticTypeBuilder, memberName);
        if (!_fieldConstants.TryGetValue(fieldKey, out var constantValue))
        {
            return false;
        }

        EmitConstantValue(constantValue, IsStringEnumContainer(staticTypeBuilder) ? typeof(string) : typeof(int));
        return true;
    }

    private void DeclareNestedTypes(TypeBuilder containingTypeBuilder, IReadOnlyList<Declaration> members, string containingTypeName)
    {
        foreach (var nestedDeclaration in members.Where(IsTypeDeclaration))
        {
            switch (nestedDeclaration)
            {
                case ClassDeclaration classDeclaration:
                    DeclareClass(containingTypeBuilder, classDeclaration, $"{containingTypeName}.{classDeclaration.Name}");
                    break;
                case StructDeclaration structDeclaration:
                    DeclareStruct(containingTypeBuilder, structDeclaration, $"{containingTypeName}.{structDeclaration.Name}");
                    break;
                case RecordDeclaration recordDeclaration:
                    DeclareRecord(containingTypeBuilder, recordDeclaration, $"{containingTypeName}.{recordDeclaration.Name}");
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    DeclareInterface(containingTypeBuilder, interfaceDeclaration, $"{containingTypeName}.{interfaceDeclaration.Name}");
                    break;
                case EnumDeclaration enumDeclaration:
                    DeclareEnum(containingTypeBuilder, enumDeclaration, $"{containingTypeName}.{enumDeclaration.Name}");
                    break;
                case UnionDeclaration unionDeclaration:
                    DeclareUnion(containingTypeBuilder, unionDeclaration, $"{containingTypeName}.{unionDeclaration.Name}");
                    break;
                case NewtypeDeclaration newtypeDeclaration:
                    DeclareRecord(
                        containingTypeBuilder,
                        CreateSyntheticNewtypeRecord(newtypeDeclaration),
                        $"{containingTypeName}.{newtypeDeclaration.Name}");
                    break;
            }
        }
    }

    private void DeclareNestedTypeMembers(IReadOnlyList<Declaration> members, string containingTypeName)
    {
        foreach (var nestedDeclaration in members.Where(IsTypeDeclaration))
        {
            switch (nestedDeclaration)
            {
                case ClassDeclaration classDeclaration:
                    DeclareClassMembers(classDeclaration, $"{containingTypeName}.{classDeclaration.Name}");
                    break;
                case StructDeclaration structDeclaration:
                    DeclareStructMembers(structDeclaration, $"{containingTypeName}.{structDeclaration.Name}");
                    break;
                case RecordDeclaration recordDeclaration:
                    DeclareRecordMembers(recordDeclaration, $"{containingTypeName}.{recordDeclaration.Name}");
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    DeclareInterfaceMembers(interfaceDeclaration, $"{containingTypeName}.{interfaceDeclaration.Name}");
                    break;
                case NewtypeDeclaration newtypeDeclaration:
                    DeclareRecordMembers(
                        CreateSyntheticNewtypeRecord(newtypeDeclaration),
                        $"{containingTypeName}.{newtypeDeclaration.Name}");
                    break;
            }
        }
    }

    private void EmitNestedTypeBodies(IReadOnlyList<Declaration> members, string containingTypeName)
    {
        foreach (var nestedDeclaration in members.Where(IsTypeDeclaration))
        {
            switch (nestedDeclaration)
            {
                case ClassDeclaration classDeclaration:
                    EmitClassBodies(classDeclaration, $"{containingTypeName}.{classDeclaration.Name}");
                    break;
                case StructDeclaration structDeclaration:
                    EmitStructBodies(structDeclaration, $"{containingTypeName}.{structDeclaration.Name}");
                    break;
                case RecordDeclaration recordDeclaration:
                    EmitRecordBodies(recordDeclaration, $"{containingTypeName}.{recordDeclaration.Name}");
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    EmitInterfaceBodies(interfaceDeclaration, $"{containingTypeName}.{interfaceDeclaration.Name}");
                    break;
                case UnionDeclaration unionDeclaration:
                    EmitUnionBodies(unionDeclaration, $"{containingTypeName}.{unionDeclaration.Name}");
                    break;
                case NewtypeDeclaration newtypeDeclaration:
                    EmitRecordBodies(
                        CreateSyntheticNewtypeRecord(newtypeDeclaration),
                        $"{containingTypeName}.{newtypeDeclaration.Name}");
                    break;
            }
        }
    }

    private void EmitInterfaceBodies(InterfaceDeclaration interfaceDeclaration, string? declaredTypeName = null)
    {
        EmitNestedTypeBodies(interfaceDeclaration.Members, declaredTypeName ?? interfaceDeclaration.Name);
    }

    private void DeclareClass(TypeBuilder containingTypeBuilder, ClassDeclaration classDeclaration, string typeName)
    {
        if (_types.ContainsKey(typeName))
        {
            return;
        }

        var typeAttributes = GetNestedTypeVisibilityAttributes(classDeclaration.Name, classDeclaration.Modifiers) | TypeAttributes.Class;
        if (classDeclaration.Modifiers.HasFlag(Modifiers.Abstract))
        {
            typeAttributes |= TypeAttributes.Abstract;
        }

        if (classDeclaration.Modifiers.HasFlag(Modifiers.Sealed))
        {
            typeAttributes |= TypeAttributes.Sealed;
        }

        var typeBuilder = containingTypeBuilder.DefineNestedType(classDeclaration.Name, typeAttributes);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, classDeclaration.Attributes);

        RegisterType(typeName, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, classDeclaration.TypeParameters);

        var allBaseTypes = new List<Type>();
        if (classDeclaration.BaseClass != null)
        {
            allBaseTypes.Add(ResolveType(classDeclaration.BaseClass, genericParameters));
        }

        allBaseTypes.AddRange(classDeclaration.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)));
        allBaseTypes.AddRange(GetMatchingDuckInterfaces(classDeclaration.Members).Select(interfaceDecl => ResolveDuckInterfaceType(interfaceDecl, genericParameters)));

        Type? baseType = null;
        foreach (var candidateType in allBaseTypes)
        {
            if (candidateType.IsInterface)
            {
                TrackInterfaceImplementation(typeBuilder,candidateType);
            }
            else if (candidateType.IsClass)
            {
                if (baseType != null)
                {
                    throw new InvalidOperationException($"Class {typeName} cannot have multiple base classes");
                }

                baseType = candidateType;
            }
        }

        if (baseType != null)
        {
            typeBuilder.SetParent(baseType);
        }

        DeclareNestedTypes(typeBuilder, classDeclaration.Members, typeName);
    }

    private void DeclareStruct(TypeBuilder containingTypeBuilder, StructDeclaration structDeclaration, string typeName)
    {
        if (_types.ContainsKey(typeName))
        {
            return;
        }

        var typeBuilder = containingTypeBuilder.DefineNestedType(
            structDeclaration.Name,
            GetNestedTypeVisibilityAttributes(structDeclaration.Name, structDeclaration.Modifiers) | TypeAttributes.Sealed,
            typeof(ValueType));
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, structDeclaration.Attributes);

        RegisterType(typeName, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, structDeclaration.TypeParameters);

        foreach (var interfaceType in structDeclaration.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
        {
            TrackInterfaceImplementation(typeBuilder,interfaceType);
        }

        foreach (var duckInterface in GetMatchingDuckInterfaces(structDeclaration.Members))
        {
            TrackInterfaceImplementation(typeBuilder,ResolveDuckInterfaceType(duckInterface, genericParameters));
        }

        DeclareNestedTypes(typeBuilder, structDeclaration.Members, typeName);
    }

    private void DeclareInterface(TypeBuilder containingTypeBuilder, InterfaceDeclaration interfaceDeclaration, string typeName)
    {
        if (_types.ContainsKey(typeName))
        {
            return;
        }

        var typeBuilder = containingTypeBuilder.DefineNestedType(
            interfaceDeclaration.Name,
            GetNestedTypeVisibilityAttributes(interfaceDeclaration.Name, interfaceDeclaration.Modifiers)
            | TypeAttributes.Interface
            | TypeAttributes.Abstract);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, interfaceDeclaration.Attributes);

        RegisterType(typeName, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, interfaceDeclaration.TypeParameters);

        foreach (var baseInterface in interfaceDeclaration.BaseInterfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
        {
            TrackInterfaceImplementation(typeBuilder,baseInterface);
        }

        DeclareNestedTypes(typeBuilder, interfaceDeclaration.Members, typeName);
    }

    private void DeclareEnum(TypeBuilder containingTypeBuilder, EnumDeclaration enumDeclaration, string typeName)
    {
        if (_enumTypes.ContainsKey(typeName) || _stringEnumContainers.ContainsKey(typeName))
        {
            return;
        }

        if (enumDeclaration.Type == EnumType.String)
        {
            var stringEnumType = containingTypeBuilder.DefineNestedType(
                enumDeclaration.Name,
                GetNestedTypeVisibilityAttributes(enumDeclaration.Name, enumDeclaration.Modifiers)
                | TypeAttributes.Class
                | TypeAttributes.Abstract
                | TypeAttributes.Sealed);

            RegisterStringEnumContainer(typeName, stringEnumType);

            foreach (var member in enumDeclaration.Members)
            {
                var fieldBuilder = stringEnumType.DefineField(
                    member.Name,
                    typeof(string),
                    FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal | FieldAttributes.HasDefault);

                var constantValue = member.Value is StringLiteralExpression stringLiteral
                    ? stringLiteral.Value.Trim('"')
                    : member.Name;
                fieldBuilder.SetConstant(constantValue);
                _fields[GetFieldKey(stringEnumType, member.Name)] = fieldBuilder;
                _fieldConstants[GetFieldKey(stringEnumType, member.Name)] = constantValue;
            }

            return;
        }

        if (_moduleBuilder == null)
        {
            throw new InvalidOperationException("Nested enum emission requires an active module builder");
        }

        var enumType = containingTypeBuilder.DefineNestedType(
            enumDeclaration.Name,
            GetNestedTypeVisibilityAttributes(enumDeclaration.Name, enumDeclaration.Modifiers)
            | TypeAttributes.Sealed,
            typeof(Enum));
        ApplyCustomAttributes(enumType.SetCustomAttribute, enumDeclaration.Attributes);

        enumType.DefineField(
            "value__",
            typeof(int),
            FieldAttributes.Private | FieldAttributes.SpecialName | FieldAttributes.RTSpecialName);

        _enumTypes[typeName] = enumType;
        _typeKeys[enumType] = typeName;

        var nextValue = 0;
        foreach (var member in enumDeclaration.Members)
        {
            var constantValue = member.Value switch
            {
                IntLiteralExpression intLiteral => int.Parse(intLiteral.Value),
                _ => nextValue
            };

            var fieldBuilder = enumType.DefineField(
                member.Name,
                enumType,
                FieldAttributes.Public | FieldAttributes.Static | FieldAttributes.Literal | FieldAttributes.HasDefault);
            fieldBuilder.SetConstant(constantValue);
            _fields[GetFieldKey(enumType, member.Name)] = fieldBuilder;
            _fieldConstants[GetFieldKey(enumType, member.Name)] = constantValue;
            nextValue = constantValue + 1;
        }
    }

    private void DeclareUnion(TypeBuilder containingTypeBuilder, UnionDeclaration unionDeclaration, string typeName)
    {
        if (_types.ContainsKey(typeName))
        {
            return;
        }

        var unionType = containingTypeBuilder.DefineNestedType(
            unionDeclaration.Name,
            GetNestedTypeVisibilityAttributes(unionDeclaration.Name, unionDeclaration.Modifiers)
            | TypeAttributes.Class
            | TypeAttributes.Abstract);
        ApplyCustomAttributes(unionType.SetCustomAttribute, unionDeclaration.Attributes);
        RegisterType(typeName, unionType);

        var unionCtor = unionType.DefineConstructor(
            MethodAttributes.Family,
            CallingConventions.Standard,
            Type.EmptyTypes);
        _constructors[GetConstructorKey(unionType)] = unionCtor;

        foreach (var unionCase in unionDeclaration.Cases)
        {
            var caseType = unionType.DefineNestedType(
                unionCase.Name,
                TypeAttributes.NestedPublic | TypeAttributes.Class | TypeAttributes.Sealed,
                unionType);

            var caseKey = $"{typeName}.{unionCase.Name}";
            RegisterType(caseKey, caseType);
            var defaultCaseCtor = caseType.DefineConstructor(
                MethodAttributes.Public,
                CallingConventions.Standard,
                Type.EmptyTypes);
            _constructors[GetConstructorKey(caseType)] = defaultCaseCtor;

            var defaultConstructorDeclaration = new ConstructorDeclaration(
                new List<Parameter>(),
                new BlockStatement(new List<Statement>(), unionCase.Line, unionCase.Column),
                Initializer: null,
                Modifiers.None,
                new List<AttributeNode>(),
                unionCase.Line,
                unionCase.Column);
            RegisterDeclaredConstructorOverload(GetConstructorKey(caseType), defaultConstructorDeclaration, defaultCaseCtor);

            var caseParameters = unionCase.Properties?
                .Select(property => new Parameter(
                    property.Name,
                    property.Type,
                    DefaultValue: null,
                    IsThis: false))
                .ToList();
            var caseParameterTypes = caseParameters?
                .Select(parameter => ResolveType(parameter.Type))
                .ToArray()
                ?? Type.EmptyTypes;
            if (caseParameters != null)
            {
                var caseCtor = caseType.DefineConstructor(
                    MethodAttributes.Public,
                    CallingConventions.Standard,
                    caseParameterTypes);
                for (int i = 0; i < caseParameters.Count; i++)
                {
                    caseCtor.DefineParameter(i + 1, GetParameterAttributes(caseParameters[i]), caseParameters[i].Name);
                }

                var syntheticConstructor = new ConstructorDeclaration(
                    caseParameters,
                    new BlockStatement(new List<Statement>(), unionCase.Line, unionCase.Column),
                    Initializer: null,
                    Modifiers.None,
                    new List<AttributeNode>(),
                    unionCase.Line,
                    unionCase.Column);
                RegisterDeclaredConstructorOverload(GetConstructorKey(caseType), syntheticConstructor, caseCtor);
            }

            if (unionCase.Properties == null)
            {
                continue;
            }

            foreach (var property in unionCase.Properties)
            {
                var fieldType = ResolveType(property.Type);
                var fieldBuilder = caseType.DefineField(
                    property.Name,
                    fieldType,
                    FieldAttributes.Public);
                _fields[GetFieldKey(caseType, property.Name)] = fieldBuilder;
            }
        }
    }

    private void DeclareRecord(TypeBuilder containingTypeBuilder, RecordDeclaration recordDeclaration, string typeName)
    {
        if (_types.ContainsKey(typeName))
        {
            return;
        }

        TypeAttributes typeAttributes;
        Type? baseType;

        if (recordDeclaration.IsStruct)
        {
            typeAttributes = GetNestedTypeVisibilityAttributes(recordDeclaration.Name, recordDeclaration.Modifiers) | TypeAttributes.Sealed;
            baseType = typeof(ValueType);
        }
        else
        {
            typeAttributes = GetNestedTypeVisibilityAttributes(recordDeclaration.Name, recordDeclaration.Modifiers)
                | TypeAttributes.Class
                | TypeAttributes.Sealed;
            baseType = typeof(object);
        }

        var typeBuilder = containingTypeBuilder.DefineNestedType(
            recordDeclaration.Name,
            typeAttributes,
            baseType);
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, recordDeclaration.Attributes);

        RegisterType(typeName, typeBuilder);
        var genericParameters = DeclareTypeGenericParameters(typeBuilder, recordDeclaration.TypeParameters);

        foreach (var interfaceType in recordDeclaration.Interfaces.Select(typeReference => ResolveType(typeReference, genericParameters)))
        {
            TrackInterfaceImplementation(typeBuilder,interfaceType);
        }

        foreach (var duckInterface in GetMatchingDuckInterfaces(recordDeclaration.Members))
        {
            TrackInterfaceImplementation(typeBuilder,ResolveDuckInterfaceType(duckInterface, genericParameters));
        }

        DeclareNestedTypes(typeBuilder, recordDeclaration.Members, typeName);
    }
}
