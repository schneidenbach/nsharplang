using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private sealed class SoaRecordRuntimeInfo
    {
        public SoaRecordRuntimeInfo(
            SoaRecordDeclaration declaration,
            TypeBuilder builder,
            FieldBuilder lengthField,
            FieldBuilder capacityField,
            IReadOnlyDictionary<string, FieldBuilder> columnFields,
            IReadOnlyDictionary<string, Type> columnElementTypes)
        {
            Declaration = declaration;
            Builder = builder;
            LengthField = lengthField;
            CapacityField = capacityField;
            ColumnFields = columnFields;
            ColumnElementTypes = columnElementTypes;
        }

        public SoaRecordDeclaration Declaration { get; }
        public TypeBuilder Builder { get; }
        public FieldBuilder LengthField { get; }
        public FieldBuilder CapacityField { get; }
        public IReadOnlyDictionary<string, FieldBuilder> ColumnFields { get; }
        public IReadOnlyDictionary<string, Type> ColumnElementTypes { get; }
    }

    private readonly Dictionary<TypeBuilder, SoaRecordRuntimeInfo> _soaRecordsByBuilder = new();

    private void DeclareSoaRecord(ModuleBuilder moduleBuilder, SoaRecordDeclaration soaRecord)
    {
        if (_types.ContainsKey(soaRecord.Name))
        {
            return;
        }

        var typeBuilder = moduleBuilder.DefineType(
            soaRecord.Name,
            GetTypeVisibilityAttributes(soaRecord.Name, soaRecord.Modifiers)
                | TypeAttributes.Sealed
                | TypeAttributes.SequentialLayout
                | TypeAttributes.BeforeFieldInit,
            typeof(ValueType));
        ApplyCustomAttributes(typeBuilder.SetCustomAttribute, soaRecord.Attributes);
        ApplyNullableContextAttribute(typeBuilder.SetCustomAttribute);

        RegisterType(soaRecord.Name, typeBuilder);

        var columnFields = new Dictionary<string, FieldBuilder>(StringComparer.Ordinal);
        var columnElementTypes = new Dictionary<string, Type>(StringComparer.Ordinal);
        foreach (var column in soaRecord.Columns)
        {
            var elementType = ResolveType(column.Type);
            var field = typeBuilder.DefineField(column.Name, elementType.MakeArrayType(), FieldAttributes.Public);
            _fields[GetFieldKey(typeBuilder, column.Name)] = field;
            columnFields[column.Name] = field;
            columnElementTypes[column.Name] = elementType;
        }

        var lengthField = typeBuilder.DefineField("length", typeof(int), FieldAttributes.Public);
        var capacityField = typeBuilder.DefineField("capacity", typeof(int), FieldAttributes.Public);
        _fields[GetFieldKey(typeBuilder, "length")] = lengthField;
        _fields[GetFieldKey(typeBuilder, "capacity")] = capacityField;

        var info = new SoaRecordRuntimeInfo(
            soaRecord,
            typeBuilder,
            lengthField,
            capacityField,
            columnFields,
            columnElementTypes);
        _soaRecordsByBuilder[typeBuilder] = info;

        DefineSoaCapacityConstructor(info);
        DefineSoaWrapMethod(info);
        DefineSoaEnsureCapacityMethod(info);
        DefineSoaAddMethod(info);
        DefineSoaClearMethod(info);
        DefineSoaCopyRowMethod(info);
    }

    private void DefineSoaCapacityConstructor(SoaRecordRuntimeInfo info)
    {
        var constructor = info.Builder.DefineConstructor(
            MethodAttributes.Public,
            CallingConventions.Standard,
            new[] { typeof(int) });
        constructor.DefineParameter(1, ParameterAttributes.None, "capacity");
        _constructors[GetConstructorKey(info.Builder)] = constructor;

        var il = constructor.GetILGenerator();
        var validCapacityLabel = il.DefineLabel();

        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Bge, validCapacityLabel);
        EmitSoaArgumentException(il, $"capacity for {info.Declaration.Name} must be non-negative");
        il.MarkLabel(validCapacityLabel);

        foreach (var column in info.Declaration.Columns)
        {
            var elementType = info.ColumnElementTypes[column.Name];
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldarg_1);
            il.Emit(OpCodes.Newarr, elementType);
            il.Emit(OpCodes.Stfld, info.ColumnFields[column.Name]);
        }

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Stfld, info.LengthField);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Stfld, info.CapacityField);

        il.Emit(OpCodes.Ret);
    }

    private void DefineSoaWrapMethod(SoaRecordRuntimeInfo info)
    {
        var parameterTypes = info.Declaration.Columns
            .Select(column => info.ColumnElementTypes[column.Name].MakeArrayType())
            .Concat(new[] { typeof(int) })
            .ToArray();
        var method = info.Builder.DefineMethod(
            "wrap",
            MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig,
            info.Builder,
            parameterTypes);
        _methods[GetMethodKey(info.Builder, "wrap")] = method;

        var synthetic = CreateSyntheticSoaFunction(
            "wrap",
            info.Declaration.Columns
                .Select(column => new Parameter(
                    column.Name,
                    new ArrayTypeReference(column.Type),
                    DefaultValue: null,
                    IsThis: false,
                    Line: column.Line,
                    Column: column.Column))
                .Concat(new[]
                {
                    new Parameter(
                        "length",
                        new SimpleTypeReference("int", info.Declaration.Line, info.Declaration.Column),
                        DefaultValue: null,
                        IsThis: false,
                        Line: info.Declaration.Line,
                        Column: info.Declaration.Column)
                })
                .ToList(),
            new SimpleTypeReference(info.Declaration.Name, info.Declaration.Line, info.Declaration.Column),
            Modifiers.Static);
        RegisterDeclaredMethodOverload(GetMethodKey(info.Builder, "wrap"), synthetic, method);

        for (var i = 0; i < info.Declaration.Columns.Count; i++)
        {
            method.DefineParameter(i + 1, ParameterAttributes.None, info.Declaration.Columns[i].Name);
        }
        method.DefineParameter(parameterTypes.Length, ParameterAttributes.None, "length");

        var il = method.GetILGenerator();
        var resultLocal = il.DeclareLocal(info.Builder);
        var capacityLocal = il.DeclareLocal(typeof(int));
        var invalidLengthLabel = il.DefineLabel();
        var nullColumnLabel = il.DefineLabel();
        var mismatchLabel = il.DefineLabel();
        var afterCapacityLabel = il.DefineLabel();

        il.Emit(OpCodes.Ldloca_S, resultLocal);
        il.Emit(OpCodes.Initobj, info.Builder);

        var lengthArg = info.Declaration.Columns.Count;
        il.Emit(OpCodes.Ldarg, lengthArg);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Blt, invalidLengthLabel);

        if (info.Declaration.Columns.Count == 0)
        {
            il.Emit(OpCodes.Ldarg, lengthArg);
            il.Emit(OpCodes.Stloc, capacityLocal);
        }
        else
        {
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Brfalse, nullColumnLabel);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldlen);
            il.Emit(OpCodes.Conv_I4);
            il.Emit(OpCodes.Stloc, capacityLocal);

            for (var i = 1; i < info.Declaration.Columns.Count; i++)
            {
                il.Emit(OpCodes.Ldarg, i);
                il.Emit(OpCodes.Brfalse, nullColumnLabel);
                il.Emit(OpCodes.Ldarg, i);
                il.Emit(OpCodes.Ldlen);
                il.Emit(OpCodes.Conv_I4);
                il.Emit(OpCodes.Ldloc, capacityLocal);
                il.Emit(OpCodes.Bne_Un, mismatchLabel);
            }
        }

        il.Emit(OpCodes.Ldarg, lengthArg);
        il.Emit(OpCodes.Ldloc, capacityLocal);
        il.Emit(OpCodes.Ble, afterCapacityLabel);
        il.Emit(OpCodes.Br, invalidLengthLabel);
        il.MarkLabel(afterCapacityLabel);

        for (var i = 0; i < info.Declaration.Columns.Count; i++)
        {
            var column = info.Declaration.Columns[i];
            il.Emit(OpCodes.Ldloca_S, resultLocal);
            il.Emit(OpCodes.Ldarg, i);
            il.Emit(OpCodes.Stfld, info.ColumnFields[column.Name]);
        }

        il.Emit(OpCodes.Ldloca_S, resultLocal);
        il.Emit(OpCodes.Ldarg, lengthArg);
        il.Emit(OpCodes.Stfld, info.LengthField);

        il.Emit(OpCodes.Ldloca_S, resultLocal);
        il.Emit(OpCodes.Ldloc, capacityLocal);
        il.Emit(OpCodes.Stfld, info.CapacityField);

        il.Emit(OpCodes.Ldloc, resultLocal);
        il.Emit(OpCodes.Ret);

        il.MarkLabel(nullColumnLabel);
        EmitSoaArgumentException(il, $"columns for {info.Declaration.Name}.wrap cannot be null");

        il.MarkLabel(invalidLengthLabel);
        EmitSoaArgumentException(il, $"length for {info.Declaration.Name}.wrap must be between 0 and column length");

        il.MarkLabel(mismatchLabel);
        EmitSoaArgumentException(il, $"column lengths for {info.Declaration.Name} do not match");
    }

    private void DefineSoaEnsureCapacityMethod(SoaRecordRuntimeInfo info)
    {
        var method = info.Builder.DefineMethod(
            "ensureCapacity",
            MethodAttributes.Public | MethodAttributes.HideBySig,
            typeof(void),
            new[] { typeof(int) });
        _methods[GetMethodKey(info.Builder, "ensureCapacity")] = method;
        method.DefineParameter(1, ParameterAttributes.None, "capacity");
        RegisterDeclaredMethodOverload(
            GetMethodKey(info.Builder, "ensureCapacity"),
            CreateSyntheticSoaFunction(
                "ensureCapacity",
                new List<Parameter>
                {
                    new(
                        "capacity",
                        new SimpleTypeReference("int", info.Declaration.Line, info.Declaration.Column),
                        DefaultValue: null,
                        IsThis: false,
                        Line: info.Declaration.Line,
                        Column: info.Declaration.Column)
                },
                null,
                Modifiers.None),
            method);

        var il = method.GetILGenerator();
        var doneLabel = il.DefineLabel();
        var validCapacityLabel = il.DefineLabel();
        var afterRequiredLabel = il.DefineLabel();
        var afterMinimumLabel = il.DefineLabel();
        var newCapacityLocal = il.DeclareLocal(typeof(int));

        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Bge, validCapacityLabel);
        EmitSoaArgumentException(il, $"capacity for {info.Declaration.Name}.ensureCapacity must be non-negative");
        il.MarkLabel(validCapacityLabel);

        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, info.CapacityField);
        il.Emit(OpCodes.Ble, doneLabel);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, info.CapacityField);
        il.Emit(OpCodes.Ldc_I4_2);
        il.Emit(OpCodes.Mul);
        il.Emit(OpCodes.Stloc, newCapacityLocal);

        il.Emit(OpCodes.Ldloc, newCapacityLocal);
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Bge, afterRequiredLabel);
        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Stloc, newCapacityLocal);
        il.MarkLabel(afterRequiredLabel);

        il.Emit(OpCodes.Ldloc, newCapacityLocal);
        il.Emit(OpCodes.Ldc_I4_4);
        il.Emit(OpCodes.Bge, afterMinimumLabel);
        il.Emit(OpCodes.Ldc_I4_4);
        il.Emit(OpCodes.Stloc, newCapacityLocal);
        il.MarkLabel(afterMinimumLabel);

        foreach (var column in info.Declaration.Columns)
        {
            var elementType = info.ColumnElementTypes[column.Name];
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldflda, info.ColumnFields[column.Name]);
            il.Emit(OpCodes.Ldloc, newCapacityLocal);
            il.Emit(OpCodes.Call, GetArrayResizeMethod(elementType));
        }

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldloc, newCapacityLocal);
        il.Emit(OpCodes.Stfld, info.CapacityField);

        il.MarkLabel(doneLabel);
        il.Emit(OpCodes.Ret);
    }

    private void DefineSoaAddMethod(SoaRecordRuntimeInfo info)
    {
        var method = info.Builder.DefineMethod(
            "add",
            MethodAttributes.Public | MethodAttributes.HideBySig,
            typeof(int),
            Type.EmptyTypes);
        _methods[GetMethodKey(info.Builder, "add")] = method;
        RegisterDeclaredMethodOverload(
            GetMethodKey(info.Builder, "add"),
            CreateSyntheticSoaFunction("add", new List<Parameter>(), new SimpleTypeReference("int"), Modifiers.None),
            method);

        var il = method.GetILGenerator();
        var oldLengthLocal = il.DeclareLocal(typeof(int));
        var validLengthIncrementLabel = il.DefineLabel();

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, info.LengthField);
        il.Emit(OpCodes.Stloc, oldLengthLocal);

        il.Emit(OpCodes.Ldloc, oldLengthLocal);
        il.Emit(OpCodes.Ldc_I4, int.MaxValue);
        il.Emit(OpCodes.Bne_Un, validLengthIncrementLabel);
        EmitSoaArgumentException(il, $"length for {info.Declaration.Name}.add is too large");
        il.MarkLabel(validLengthIncrementLabel);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldloc, oldLengthLocal);
        il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(OpCodes.Add);
        il.Emit(OpCodes.Call, _methods[GetMethodKey(info.Builder, "ensureCapacity")]);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldloc, oldLengthLocal);
        il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(OpCodes.Add);
        il.Emit(OpCodes.Stfld, info.LengthField);

        il.Emit(OpCodes.Ldloc, oldLengthLocal);
        il.Emit(OpCodes.Ret);
    }

    private void DefineSoaClearMethod(SoaRecordRuntimeInfo info)
    {
        var method = info.Builder.DefineMethod(
            "clear",
            MethodAttributes.Public | MethodAttributes.HideBySig,
            typeof(void),
            Type.EmptyTypes);
        _methods[GetMethodKey(info.Builder, "clear")] = method;
        RegisterDeclaredMethodOverload(
            GetMethodKey(info.Builder, "clear"),
            CreateSyntheticSoaFunction("clear", new List<Parameter>(), null, Modifiers.None),
            method);

        var il = method.GetILGenerator();
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Stfld, info.LengthField);
        il.Emit(OpCodes.Ret);
    }

    private void DefineSoaCopyRowMethod(SoaRecordRuntimeInfo info)
    {
        var method = info.Builder.DefineMethod(
            "copyRow",
            MethodAttributes.Public | MethodAttributes.HideBySig,
            typeof(void),
            new[] { typeof(int), typeof(int) });
        _methods[GetMethodKey(info.Builder, "copyRow")] = method;
        method.DefineParameter(1, ParameterAttributes.None, "from");
        method.DefineParameter(2, ParameterAttributes.None, "to");
        RegisterDeclaredMethodOverload(
            GetMethodKey(info.Builder, "copyRow"),
            CreateSyntheticSoaFunction(
                "copyRow",
                new List<Parameter>
                {
                    new("from", new SimpleTypeReference("int"), null, false),
                    new("to", new SimpleTypeReference("int"), null, false)
                },
                null,
                Modifiers.None),
            method);

        var il = method.GetILGenerator();
        var requiredLocal = il.DeclareLocal(typeof(int));
        var validSourceLabel = il.DefineLabel();
        var validTargetLabel = il.DefineLabel();
        var validSourceRangeLabel = il.DefineLabel();
        var validTargetIncrementLabel = il.DefineLabel();
        var keepLengthLabel = il.DefineLabel();

        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Bge, validSourceLabel);
        EmitSoaArgumentException(il, $"source row for {info.Declaration.Name}.copyRow must be non-negative");
        il.MarkLabel(validSourceLabel);

        il.Emit(OpCodes.Ldarg_2);
        il.Emit(OpCodes.Ldc_I4_0);
        il.Emit(OpCodes.Bge, validTargetLabel);
        EmitSoaArgumentException(il, $"target row for {info.Declaration.Name}.copyRow must be non-negative");
        il.MarkLabel(validTargetLabel);

        il.Emit(OpCodes.Ldarg_1);
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, info.LengthField);
        il.Emit(OpCodes.Blt, validSourceRangeLabel);
        EmitSoaArgumentException(il, $"source row for {info.Declaration.Name}.copyRow must be less than length");
        il.MarkLabel(validSourceRangeLabel);

        il.Emit(OpCodes.Ldarg_2);
        il.Emit(OpCodes.Ldc_I4, int.MaxValue);
        il.Emit(OpCodes.Bne_Un, validTargetIncrementLabel);
        EmitSoaArgumentException(il, $"target row for {info.Declaration.Name}.copyRow is too large");
        il.MarkLabel(validTargetIncrementLabel);

        il.Emit(OpCodes.Ldarg_2);
        il.Emit(OpCodes.Ldc_I4_1);
        il.Emit(OpCodes.Add);
        il.Emit(OpCodes.Stloc, requiredLocal);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldloc, requiredLocal);
        il.Emit(OpCodes.Call, _methods[GetMethodKey(info.Builder, "ensureCapacity")]);

        foreach (var column in info.Declaration.Columns)
        {
            var elementType = info.ColumnElementTypes[column.Name];
            var field = info.ColumnFields[column.Name];
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, field);
            il.Emit(OpCodes.Ldarg_2);
            il.Emit(OpCodes.Ldarg_0);
            il.Emit(OpCodes.Ldfld, field);
            il.Emit(OpCodes.Ldarg_1);
            EmitArrayElementLoad(il, elementType);
            EmitArrayElementStore(il, elementType);
        }

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, info.LengthField);
        il.Emit(OpCodes.Ldloc, requiredLocal);
        il.Emit(OpCodes.Bge, keepLengthLabel);

        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldloc, requiredLocal);
        il.Emit(OpCodes.Stfld, info.LengthField);

        il.MarkLabel(keepLengthLabel);
        il.Emit(OpCodes.Ret);
    }

    private static void EmitSoaArgumentException(ILGenerator il, string message)
    {
        var argumentExceptionConstructor = typeof(ArgumentException).GetConstructor(new[] { typeof(string) })!;
        il.Emit(OpCodes.Ldstr, message);
        il.Emit(OpCodes.Newobj, argumentExceptionConstructor);
        il.Emit(OpCodes.Throw);
    }

    private bool TryGetSoaRecordInfo(Type type, out SoaRecordRuntimeInfo info)
    {
        if (type is TypeBuilder direct && _soaRecordsByBuilder.TryGetValue(direct, out info!))
        {
            return true;
        }

        info = null!;
        return false;
    }

    private bool TryResolveSoaRowColumnAccess(
        MemberAccessExpression memberAccess,
        out IndexAccessExpression rowAccess,
        out SoaRecordRuntimeInfo info,
        out FieldBuilder columnField,
        out Type elementType)
    {
        if (memberAccess.Object is IndexAccessExpression { IsNullConditional: false } indexAccess
            && TryGetSoaRecordInfo(GetExpressionType(indexAccess.Object), out info!)
            && info.ColumnFields.TryGetValue(memberAccess.MemberName, out columnField!)
            && info.ColumnElementTypes.TryGetValue(memberAccess.MemberName, out elementType!))
        {
            rowAccess = indexAccess;
            return true;
        }

        rowAccess = null!;
        info = null!;
        columnField = null!;
        elementType = null!;
        return false;
    }

    private bool TryGetSoaRowColumnType(MemberAccessExpression memberAccess, out Type elementType)
    {
        if (TryResolveSoaRowColumnAccess(memberAccess, out _, out _, out _, out elementType!))
        {
            return true;
        }

        elementType = null!;
        return false;
    }

    private bool TryEmitSoaRowColumnLoad(MemberAccessExpression memberAccess)
    {
        if (!TryResolveSoaRowColumnAccess(memberAccess, out var rowAccess, out _, out var columnField, out var elementType))
        {
            return false;
        }

        EmitExpression(rowAccess.Object);
        _currentIL!.Emit(OpCodes.Ldfld, columnField);
        EmitExpressionWithExpectedType(rowAccess.Index, typeof(int));
        EmitArrayElementLoad(elementType);
        return true;
    }

    private bool TryEmitSoaRowColumnAssignment(AssignmentExpression assignment, MemberAccessExpression memberAccess, bool leaveValueOnStack)
    {
        if (!TryResolveSoaRowColumnAccess(memberAccess, out var rowAccess, out _, out var columnField, out var elementType))
        {
            return false;
        }

        EmitExpression(rowAccess.Object);
        _currentIL!.Emit(OpCodes.Ldfld, columnField);
        var arrayLocal = _currentIL.DeclareLocal(columnField.FieldType);
        _currentIL.Emit(OpCodes.Stloc, arrayLocal);

        EmitExpressionWithExpectedType(rowAccess.Index, typeof(int));
        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        if (assignment.Operator == AssignmentOperator.NullCoalesceAssign)
        {
            _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
            _currentIL.Emit(OpCodes.Ldloc, indexLocal);
            EmitArrayElementLoad(elementType);
            var currentValueLocal = _currentIL.DeclareLocal(elementType);
            _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

            if (!elementType.IsValueType || Nullable.GetUnderlyingType(elementType) != null)
            {
                var hasValueLabel = _currentIL.DefineLabel();
                var endLabel = _currentIL.DefineLabel();

                EmitBranchIfHasValue(elementType, currentValueLocal, hasValueLabel);
                if (assignment.Value is DefaultExpression)
                {
                    EmitDefaultValue(elementType);
                }
                else
                {
                    EmitExpressionWithExpectedType(assignment.Value, elementType);
                }

                _currentIL.Emit(OpCodes.Stloc, currentValueLocal);
                _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
                _currentIL.Emit(OpCodes.Ldloc, indexLocal);
                _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
                EmitArrayElementStore(elementType);
                _currentIL.Emit(OpCodes.Br, endLabel);

                _currentIL.MarkLabel(hasValueLabel);
                _currentIL.MarkLabel(endLabel);
            }

            if (leaveValueOnStack)
            {
                _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
            }

            return true;
        }

        if (assignment.Operator != AssignmentOperator.Assign)
        {
            _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
            _currentIL.Emit(OpCodes.Ldloc, indexLocal);
            EmitArrayElementLoad(elementType);
            EmitExpressionWithExpectedType(assignment.Value, elementType);
            EmitCompoundAssignmentOperation(assignment.Operator, elementType);
        }
        else if (assignment.Value is DefaultExpression)
        {
            EmitDefaultValue(elementType);
        }
        else
        {
            EmitExpressionWithExpectedType(assignment.Value, elementType);
        }

        var valueLocal = _currentIL.DeclareLocal(elementType);
        _currentIL.Emit(OpCodes.Stloc, valueLocal);

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, valueLocal);
        EmitArrayElementStore(elementType);

        if (leaveValueOnStack)
        {
            _currentIL.Emit(OpCodes.Ldloc, valueLocal);
        }

        return true;
    }

    private bool TryEmitSoaRowColumnIncrementOrDecrement(
        MemberAccessExpression memberAccess,
        int delta,
        bool isPost,
        bool leaveValueOnStack)
    {
        if (!TryResolveSoaRowColumnAccess(memberAccess, out var rowAccess, out _, out var columnField, out var elementType))
        {
            return false;
        }

        EmitExpression(rowAccess.Object);
        _currentIL!.Emit(OpCodes.Ldfld, columnField);
        var arrayLocal = _currentIL.DeclareLocal(columnField.FieldType);
        _currentIL.Emit(OpCodes.Stloc, arrayLocal);

        EmitExpressionWithExpectedType(rowAccess.Index, typeof(int));
        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        EmitArrayElementLoad(elementType);
        var currentValueLocal = _currentIL.DeclareLocal(elementType);
        _currentIL.Emit(OpCodes.Stloc, currentValueLocal);

        LocalBuilder? expressionValueLocal = null;
        if (leaveValueOnStack && isPost)
        {
            expressionValueLocal = currentValueLocal;
        }

        _currentIL.Emit(OpCodes.Ldloc, currentValueLocal);
        EmitIncrementDelta(delta, elementType);
        var updatedValueLocal = _currentIL.DeclareLocal(elementType);
        _currentIL.Emit(OpCodes.Stloc, updatedValueLocal);

        _currentIL.Emit(OpCodes.Ldloc, arrayLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, updatedValueLocal);
        EmitArrayElementStore(elementType);

        if (leaveValueOnStack)
        {
            _currentIL.Emit(OpCodes.Ldloc, expressionValueLocal ?? updatedValueLocal);
        }

        return true;
    }

    private static FunctionDeclaration CreateSyntheticSoaFunction(
        string name,
        List<Parameter> parameters,
        TypeReference? returnType,
        Modifiers modifiers)
    {
        return new FunctionDeclaration(
            name,
            parameters,
            returnType,
            null,
            null,
            null,
            null,
            modifiers,
            new List<AttributeNode>(),
            false,
            null,
            false,
            false,
            0,
            0);
    }

    private static MethodInfo GetArrayResizeMethod(Type elementType)
    {
        return typeof(Array)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .Single(method =>
                method.Name == nameof(Array.Resize)
                && method.IsGenericMethodDefinition
                && method.GetParameters().Length == 2)
            .MakeGenericMethod(elementType);
    }

    private static void EmitArrayElementLoad(ILGenerator il, Type elementType)
    {
        if (elementType.IsValueType || elementType.IsGenericParameter)
        {
            il.Emit(OpCodes.Ldelem, elementType);
        }
        else
        {
            il.Emit(OpCodes.Ldelem_Ref);
        }
    }

    private static void EmitArrayElementStore(ILGenerator il, Type elementType)
    {
        if (elementType.IsValueType || elementType.IsGenericParameter)
        {
            il.Emit(OpCodes.Stelem, elementType);
        }
        else
        {
            il.Emit(OpCodes.Stelem_Ref);
        }
    }
}
