using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Structural guard for the skipped-subtree bug class: every Expression-typed slot of every AST
/// expression record (including slots nested in aggregates such as Argument, PropertyInitializer,
/// TupleElement, MatchCase, and InterpolatedStringHole) must be reachable through
/// <see cref="AstChildren.Of"/>. Late-added children (NewExpression.ArrayLengthExpression,
/// StackAllocExpression.LengthExpression) shipped twice without any walker visiting them; this
/// test makes the third instance impossible: a new expression node hits AstChildren's throwing
/// default, and a new Expression-typed property on an existing node shows up here as an
/// unreachable sentinel.
/// </summary>
public class AstChildrenTests
{
    [Fact]
    public void EveryExpressionTypedSlot_OfEveryExpressionNode_IsEnumerated()
    {
        var expressionTypes = typeof(Expression).Assembly.GetTypes()
            .Where(type => !type.IsAbstract && typeof(Expression).IsAssignableFrom(type))
            .OrderBy(type => type.Name)
            .ToList();

        Assert.NotEmpty(expressionTypes);

        foreach (var type in expressionTypes)
        {
            var sentinels = new List<Expression>();
            var node = ConstructExpression(type, sentinels);

            var reached = new HashSet<Expression>(ReferenceEqualityComparer.Instance);
            var queue = new Queue<Expression>();
            queue.Enqueue(node);
            while (queue.Count > 0)
            {
                foreach (var child in AstChildren.Of(queue.Dequeue()))
                {
                    if (reached.Add(child))
                        queue.Enqueue(child);
                }
            }

            var missed = sentinels.Where(sentinel => !reached.Contains(sentinel)).ToList();
            Assert.True(missed.Count == 0,
                $"AstChildren.Of({type.Name}) never yields {missed.Count} Expression-typed slot(s) "
                + "of that node. Add the missing child to AstChildren.Of (and audit walkers with a "
                + "bespoke case for this node).");
        }
    }

    private static readonly NullabilityInfoContext NullabilityContext = new();

    /// <summary>
    /// Builds a value for a constructor parameter type, injecting a fresh sentinel into every
    /// Expression-typed slot (nullable or not — optional children like ArrayLengthExpression are
    /// exactly the slots this guard exists for).
    /// </summary>
    private static object? CreateValue(Type type, List<Expression> sentinels, ParameterInfo? parameter = null)
    {
        if (typeof(Expression).IsAssignableFrom(type))
            return CreateExpressionValue(type, sentinels);

        // Parameter lists belong to declarations (lambda parameters); their DefaultValue slot is
        // not a runtime child of the enclosing expression, so build them without sentinels.
        if (type == typeof(Parameter))
            return new Parameter("p", new SimpleTypeReference("int"), DefaultValue: null, IsThis: false);

        if (typeof(Pattern).IsAssignableFrom(type))
            return new IdentifierPattern("p", 0, 0); // Pattern-internal expressions are a pattern-walker concern.

        if (typeof(TypeReference).IsAssignableFrom(type))
            return new SimpleTypeReference("int");

        if (type == typeof(InterpolatedStringPart))
            return CreateValue(typeof(InterpolatedStringHole), sentinels);

        if (parameter != null && IsNullable(parameter))
            return null;

        if (type == typeof(string))
            return "x";
        if (type == typeof(int))
            return 0;
        if (type == typeof(bool))
            return false;
        if (type.IsEnum)
            return Enum.GetValues(type).GetValue(0);

        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(List<>))
        {
            var elementType = type.GetGenericArguments()[0];
            var list = (IList)Activator.CreateInstance(type)!;
            list.Add(CreateValue(elementType, sentinels));
            return list;
        }

        // Aggregate records that carry expressions (Argument, TupleElement, PropertyInitializer,
        // MatchCase, InterpolatedStringHole, ...): construct via the primary constructor so their
        // Expression-typed slots get sentinels too.
        var constructor = type.GetConstructors().SingleOrDefault()
            ?? throw new InvalidOperationException(
                $"AstChildrenTests cannot construct '{type.Name}' (no single public constructor). "
                + "Teach CreateValue about this type.");
        var arguments = constructor.GetParameters()
            .Select(ctorParameter => CreateValue(ctorParameter.ParameterType, sentinels, ctorParameter))
            .ToArray();
        return constructor.Invoke(arguments);
    }

    private static Expression CreateExpressionValue(Type type, List<Expression> sentinels)
    {
        // Slots typed as the abstract Expression get a leaf sentinel; slots demanding a concrete
        // subtype (OnSubscription.Handler is a LambdaExpression, NewExpression.Initializer is an
        // ObjectInitializerExpression) get that node, whose own slots are filled recursively.
        var value = type == typeof(Expression)
            ? new IdentifierExpression($"sentinel{sentinels.Count}", 0, 0)
            : ConstructExpression(type, sentinels);

        sentinels.Add(value);
        return value;
    }

    private static Expression ConstructExpression(Type type, List<Expression> sentinels)
    {
        var constructor = type.GetConstructors().Single();
        var arguments = constructor.GetParameters()
            .Select(ctorParameter => CreateValue(ctorParameter.ParameterType, sentinels, ctorParameter))
            .ToArray();
        return (Expression)constructor.Invoke(arguments);
    }

    private static bool IsNullable(ParameterInfo parameter)
    {
        if (Nullable.GetUnderlyingType(parameter.ParameterType) != null)
            return true;

        return !parameter.ParameterType.IsValueType
            && NullabilityContext.Create(parameter).WriteState == NullabilityState.Nullable;
    }
}
