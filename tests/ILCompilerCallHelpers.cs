using System.Collections;
using System.Collections.Generic;
using System;
using System.Linq;
using System.Linq.Expressions;

namespace NSharpLang.Tests;

public enum ILCompilerCallMode
{
    Slow = 1,
    Fast = 7
}

[AttributeUsage(AttributeTargets.All, AllowMultiple = false)]
public sealed class RuntimeCoverageAttribute(int code, string[] tags) : Attribute
{
    public int Code { get; } = code;

    public string[] Tags { get; } = tags;

    public bool Enabled { get; set; }

    public ILCompilerCallMode Mode { get; set; }

    public Type? RuntimeType { get; set; }

    public AttributeTargets Targets { get; set; }
}

public static class ILCompilerCallHelpers
{
    public static int Pick(object value)
    {
        return 1;
    }

    public static int Pick(string value)
    {
        return 2;
    }

    public static int Format(int a, int b = 2, int c = 3)
    {
        return a * 100 + b * 10 + c;
    }

    public static long AddLong(long value, long delta = 5L)
    {
        return value + delta;
    }

    public static int ModeValue(ILCompilerCallMode mode = ILCompilerCallMode.Fast)
    {
        return (int)mode;
    }

    public static int Sum(params int[] values)
    {
        return values.Sum();
    }

    public static T Identity<T>(T value)
    {
        return value;
    }

    public static int ScorePair<T>((T, T) pair, Func<T, string> format)
    {
        return format(pair.Item1).Length * 10 + format(pair.Item2).Length;
    }

    public static int DescribeGeneric<T>(T value, int prefix = 1, params T[] rest)
    {
        return prefix * 100 + rest.Length * 10 + value!.ToString()!.Length;
    }

    public static int DecimalDefaultScaled(decimal value = 1.25m)
    {
        return (int)(value * 100m);
    }

    public static int NullableOrDefault(int? value = null)
    {
        return value ?? 17;
    }
}

public static class RuntimeCoverageMetadata
{
    public const int DefaultCode = 19;

    public static string Label => "runtime";

    public static ILCompilerCallMode DefaultMode => ILCompilerCallMode.Fast;

    public static AttributeTargets SupportedTargets => AttributeTargets.Class | AttributeTargets.Struct;
}

public sealed class RuntimeExpressionEntity
{
    public int Id { get; set; }

    public int OtherId { get; set; }

    public RuntimeRelatedExpressionEntity Related { get; set; } = new();

    public string Name { get; set; } = "";
}

public sealed class RuntimeRelatedExpressionEntity
{
    public ICollection<RuntimeExpressionEntity> Entities { get; set; } = new List<RuntimeExpressionEntity>();

    public RuntimeExpressionEntity? Entity { get; set; }

    public int PrincipalId { get; set; }
}

public sealed class RuntimeExpressionModelBuilder
{
    public string LastPropertyTypeName { get; private set; } = "";

    public void Entity<TEntity>(Action<RuntimeExpressionEntityBuilder<TEntity>> build)
    {
        build(new RuntimeExpressionEntityBuilder<TEntity>(this));
    }

    internal void RecordProperty(Type propertyType)
    {
        LastPropertyTypeName = propertyType.FullName ?? propertyType.Name;
    }
}

public sealed class RuntimeExpressionEntityBuilder<TEntity>(RuntimeExpressionModelBuilder owner)
{
    public RuntimeExpressionPropertyBuilder<TProperty> Property<TProperty>(Expression<Func<TEntity, TProperty>> property)
    {
        owner.RecordProperty(typeof(TProperty));
        return new RuntimeExpressionPropertyBuilder<TProperty>();
    }

    public RuntimeExpressionEntityBuilder<TEntity> HasKey(Expression<Func<TEntity, object>> key)
    {
        owner.RecordProperty(key.Body.Type);
        return this;
    }

    public RuntimeReferenceNavigationBuilder<TEntity, TRelatedEntity> HasOne<TRelatedEntity>(
        Expression<Func<TEntity, TRelatedEntity>> navigation)
    {
        return new RuntimeReferenceNavigationBuilder<TEntity, TRelatedEntity>(owner);
    }
}

public sealed class RuntimeReferenceNavigationBuilder<TEntity, TRelatedEntity>(RuntimeExpressionModelBuilder owner)
{
    public RuntimeReferenceCollectionBuilder<TRelatedEntity, TEntity> WithMany(
        Expression<Func<TRelatedEntity, IEnumerable<TEntity>>> navigation)
    {
        return new RuntimeReferenceCollectionBuilder<TRelatedEntity, TEntity>(owner);
    }

    public RuntimeReferenceReferenceBuilder<TRelatedEntity, TEntity> WithOne(
        Expression<Func<TRelatedEntity, TEntity>> navigation)
    {
        return new RuntimeReferenceReferenceBuilder<TRelatedEntity, TEntity>(owner);
    }
}

public sealed class RuntimeReferenceCollectionBuilder<TEntity, TRelatedEntity>(RuntimeExpressionModelBuilder owner)
{
    public RuntimeReferenceCollectionBuilder<TEntity, TRelatedEntity> HasPrincipalKey<TPrincipalEntity>(
        Expression<Func<TPrincipalEntity, object>> keyExpression)
    {
        return this;
    }

    public RuntimeReferenceCollectionBuilder<TEntity, TRelatedEntity> HasForeignKey<TDependentEntity>(
        Expression<Func<TDependentEntity, object>> keyExpression)
    {
        return this;
    }

    public RuntimeReferenceCollectionBuilder<TEntity, TRelatedEntity> HasConstraintName(string name)
    {
        owner.RecordProperty(typeof(RuntimeReferenceCollectionBuilder<TEntity, TRelatedEntity>));
        return this;
    }
}

public sealed class RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity>(RuntimeExpressionModelBuilder owner)
{
    public RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity> HasPrincipalKey<TPrincipalEntity>(
        Expression<Func<TPrincipalEntity, object>> keyExpression)
    {
        return this;
    }

    public RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity> HasForeignKey<TDependentEntity>(
        Expression<Func<TDependentEntity, object>> keyExpression)
    {
        return this;
    }

    public RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity> OnDelete(ILCompilerCallMode? mode)
    {
        return this;
    }

    public RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity> HasConstraintName(string name)
    {
        owner.RecordProperty(typeof(RuntimeReferenceReferenceBuilder<TEntity, TRelatedEntity>));
        return this;
    }
}

public sealed class RuntimeExpressionPropertyBuilder<TProperty>
{
    public RuntimeExpressionPropertyBuilder<TProperty> ValueGeneratedOnAdd()
    {
        return this;
    }
}

public sealed class RuntimeCoverageBag : IEnumerable<int>
{
    private readonly Dictionary<int, int> _items = new();
    private readonly List<int> _values = new();

    public static int StaticField;
    public static int StaticProperty { get; set; }

    public int Field;
    public int Property { get; set; }

    public int this[int index]
    {
        get => _items.TryGetValue(index, out var value) ? value : 0;
        set => _items[index] = value;
    }

    public int ValuesCount => _values.Count;

    public int ValuesSum => _values.Sum();

    public void Add(int value)
    {
        _values.Add(value);
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public struct RuntimeCoverageStruct
{
    public int Field;

    public int Property { get; set; }
}

public sealed class IntAddBag : IEnumerable<int>
{
    private readonly List<int> _values = new();

    public void Add(int value)
    {
        _values.Add(value);
    }

    public int Sum()
    {
        return _values.Sum();
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public sealed class IntEnqueueBag : IEnumerable<int>
{
    private readonly Queue<int> _values = new();

    public void Enqueue(int value)
    {
        _values.Enqueue(value);
    }

    public int ReadAsDigits()
    {
        var result = 0;
        foreach (var value in _values)
        {
            result = result * 10 + value;
        }

        return result;
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public sealed class IntEnumerableBox : IEnumerable<int>
{
    private readonly List<int> _values;

    public IntEnumerableBox(IEnumerable<int> values)
    {
        _values = values.ToList();
    }

    public int Signature()
    {
        return _values.Count * 100 + _values[0] * 10 + _values[^1];
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}
