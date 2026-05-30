using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for the <see cref="GenericSpecializer"/> policy and registry. These pin the
/// GC-safety-critical gating decisions in isolation from IL emission: which ABI boundaries are
/// eligible, which type arguments are specializable, the specialization cap, and skip logging.
/// </summary>
public class GenericSpecializerTests
{
    [Theory]
    [InlineData(AbiBoundary.ClrInternal, true)]
    [InlineData(AbiBoundary.FilePrivate, true)]
    [InlineData(AbiBoundary.Local, true)]
    [InlineData(AbiBoundary.ClrPublic, false)]
    public void IsEligibleBoundary_OnlyNonPublicBoundariesAreEligible(AbiBoundary boundary, bool expected)
    {
        Assert.Equal(expected, GenericSpecializer.IsEligibleBoundary(boundary));
    }

    [Theory]
    [InlineData(typeof(int), true)]
    [InlineData(typeof(long), true)]
    [InlineData(typeof(double), true)]
    [InlineData(typeof(bool), true)]
    [InlineData(typeof(DateTime), true)]
    [InlineData(typeof(string), false)]
    [InlineData(typeof(object), false)]
    [InlineData(typeof(int[]), false)]
    public void IsSpecializableValueType_ClassifiesTypesConservatively(Type type, bool expected)
    {
        Assert.Equal(expected, GenericSpecializer.IsSpecializableValueType(type));
    }

    [Fact]
    public void IsSpecializableValueType_RejectsOpenGenericValueTypes()
    {
        var openNullable = typeof(Nullable<>);
        Assert.False(GenericSpecializer.IsSpecializableValueType(openNullable));

        // A closed value type built from a value-type argument is specializable.
        Assert.True(GenericSpecializer.IsSpecializableValueType(typeof(int?)));
    }

    [Fact]
    public void IsSpecializableValueType_RejectsByRefLikeStructs()
    {
        // Span<T>/ReadOnlySpan<T> and ref structs are value types but cannot be boxed, stored on
        // the heap, or used as generic arguments. Specializing over them would emit unverifiable
        // IL, so they must be rejected even though IsValueType is true.
        Assert.True(typeof(Span<int>).IsByRefLike);
        Assert.False(GenericSpecializer.IsSpecializableValueType(typeof(Span<int>)));
        Assert.False(GenericSpecializer.IsSpecializableValueType(typeof(ReadOnlySpan<byte>)));
    }

    [Fact]
    public void AreSpecializableValueTypeArguments_RequiresAtLeastOneArgument()
    {
        Assert.False(GenericSpecializer.AreSpecializableValueTypeArguments(Array.Empty<Type>()));
    }

    [Fact]
    public void AreSpecializableValueTypeArguments_RejectsWhenAnyArgumentIsReferenceType()
    {
        Assert.True(GenericSpecializer.AreSpecializableValueTypeArguments(new[] { typeof(int), typeof(long) }));
        Assert.False(GenericSpecializer.AreSpecializableValueTypeArguments(new[] { typeof(int), typeof(string) }));
    }

    [Fact]
    public void Register_PublicBoundary_IsRejectedAndLogged()
    {
        var specializer = new GenericSpecializer();
        var declaration = CreateGenericFunction("Pub");

        var result = specializer.Register(
            declaration,
            AbiBoundary.ClrPublic,
            new[] { typeof(int) },
            () => throw new InvalidOperationException("Builder factory must not be invoked for rejected requests."));

        Assert.Null(result);
        Assert.Equal(0, specializer.Count);
        Assert.Single(specializer.Skipped);
        Assert.Contains("public", specializer.Skipped[0].Reason, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Register_ReferenceTypeArgument_IsRejected()
    {
        var specializer = new GenericSpecializer();
        var declaration = CreateGenericFunction("priv");

        var result = specializer.Register(
            declaration,
            AbiBoundary.FilePrivate,
            new[] { typeof(string) },
            () => throw new InvalidOperationException("Builder factory must not be invoked for rejected requests."));

        Assert.Null(result);
        Assert.Empty(specializer.Specializations);
        Assert.Single(specializer.Skipped);
    }

    [Fact]
    public void Register_IsIdempotentForSameKey()
    {
        var specializer = new GenericSpecializer();
        var declaration = CreateGenericFunction("priv");
        var (_, builder) = CreateStubMethod("priv_Int32");
        var factoryCalls = 0;

        var first = specializer.Register(declaration, AbiBoundary.FilePrivate, new[] { typeof(int) }, () =>
        {
            factoryCalls++;
            return builder;
        });

        var second = specializer.Register(declaration, AbiBoundary.FilePrivate, new[] { typeof(int) }, () =>
        {
            factoryCalls++;
            return builder;
        });

        Assert.NotNull(first);
        Assert.Same(first, second);
        Assert.Equal(1, factoryCalls);
        Assert.Equal(1, specializer.Count);
    }

    [Fact]
    public void Register_HonoursCap_AndLogsOverflow()
    {
        var specializer = new GenericSpecializer(cap: 1);
        var first = CreateGenericFunction("a");
        var second = CreateGenericFunction("b");
        var (_, firstBuilder) = CreateStubMethod("a_Int32");

        var accepted = specializer.Register(first, AbiBoundary.FilePrivate, new[] { typeof(int) }, () => firstBuilder);
        Assert.NotNull(accepted);

        var rejected = specializer.Register(
            second,
            AbiBoundary.FilePrivate,
            new[] { typeof(long) },
            () => throw new InvalidOperationException("Cap exceeded — factory must not run."));

        Assert.Null(rejected);
        Assert.Equal(1, specializer.Count);
        Assert.Contains(specializer.Skipped, s => s.Reason.Contains("cap", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void CreateSubstitution_ZipsTypeParametersWithArguments()
    {
        var declaration = CreateGenericFunction("priv", "T", "U");
        var (_, builder) = CreateStubMethod("priv_Int32_Boolean");

        var specialization = new GenericSpecialization(declaration, new[] { typeof(int), typeof(bool) }, builder);
        var substitution = specialization.CreateSubstitution();

        Assert.Equal(typeof(int), substitution["T"]);
        Assert.Equal(typeof(bool), substitution["U"]);
    }

    private static FunctionDeclaration CreateGenericFunction(string name, params string[] typeParameterNames)
    {
        var typeParameters = (typeParameterNames.Length == 0 ? new[] { "T" } : typeParameterNames)
            .Select(tp => new TypeParameter(tp))
            .ToList();

        return new FunctionDeclaration(
            name,
            new List<Parameter>(),
            ReturnType: null,
            Body: null,
            ExpressionBody: null,
            TypeParameters: typeParameters,
            Constraints: null,
            Modifiers: Modifiers.None,
            Attributes: new List<AttributeNode>(),
            IsOperatorOverload: false,
            OperatorSymbol: null,
            IsConversionOperator: false,
            IsImplicitConversion: false,
            Line: 0,
            Column: 0);
    }

    private static (TypeBuilder Type, MethodBuilder Method) CreateStubMethod(string methodName)
    {
        var assemblyName = new System.Reflection.AssemblyName($"GenericSpecializerTests_{Guid.NewGuid():N}");
        var assembly = AssemblyBuilder.DefineDynamicAssembly(assemblyName, AssemblyBuilderAccess.RunAndCollect);
        var module = assembly.DefineDynamicModule("Main");
        var type = module.DefineType("Stub");
        var method = type.DefineMethod(methodName, System.Reflection.MethodAttributes.Private | System.Reflection.MethodAttributes.Static);
        return (type, method);
    }
}
