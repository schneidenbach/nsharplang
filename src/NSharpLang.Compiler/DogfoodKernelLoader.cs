using System;
using System.Reflection;

namespace NSharpLang.Compiler;

internal static class DogfoodKernelLoader
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    internal static Type? TryGetProgramType()
    {
        var assembly = TryLoadDogfoodAssembly();
        return assembly?.GetType("Program");
    }

    internal static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    internal static TBindings? TryCreateBindings<TBindings>(Func<Type, TBindings> createBindings)
        where TBindings : class
    {
        var programType = TryGetProgramType();
        return programType == null ? null : createBindings(programType);
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
    }
}
