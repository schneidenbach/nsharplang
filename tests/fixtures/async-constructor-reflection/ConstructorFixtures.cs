namespace NSharpLang.AsyncConstructorReflectionFixtures;

public sealed class ReflectedArrayBox<T> { }

public sealed class ReflectedConstructorArrayShapes
{
    private readonly int shape;

    public ReflectedConstructorArrayShapes(ReflectedArrayBox<int[]> vector)
    {
        shape = vector is null ? 11 : 1;
    }

    public ReflectedConstructorArrayShapes(ReflectedArrayBox<int[,]> matrix)
    {
        shape = matrix is null ? 22 : 2;
    }

    public int GetShape() => shape;
}

public sealed class ReflectedRefConstructor
{
    private readonly int observed;

    public ReflectedRefConstructor(ref int value)
    {
        value += 6;
        observed = value;
    }

    public int GetValue() => observed;
}

public sealed class ReflectedOutConstructor
{
    private readonly int observed;

    public ReflectedOutConstructor(out int value)
    {
        value = 73;
        observed = value;
    }

    public int GetValue() => observed;
}

public sealed class ReflectedInConstructor
{
    private readonly int observed;

    public ReflectedInConstructor(in int value)
    {
        observed = value;
    }

    public int GetValue() => observed;
}
