using System;
using System.IO;
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
        var invoke = typeof(TDelegate).GetMethod(nameof(Action.Invoke))
            ?? throw new MissingMethodException(typeof(TDelegate).FullName, nameof(Action.Invoke));
        var parameterTypes = Array.ConvertAll(invoke.GetParameters(), parameter => parameter.ParameterType);
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static,
                binder: null,
                types: parameterTypes,
                modifiers: null)
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
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch (FileNotFoundException)
        {
        }

        var compilerAssemblyPath = typeof(DogfoodKernelLoader).Assembly.Location;
        var compilerDirectory = Path.GetDirectoryName(compilerAssemblyPath);
        if (string.IsNullOrWhiteSpace(compilerDirectory))
        {
            return null;
        }

        var adjacentDogfoodAssembly = Path.Combine(compilerDirectory, $"{DogfoodAssemblyName}.dll");
        return File.Exists(adjacentDogfoodAssembly)
            ? Assembly.LoadFrom(adjacentDogfoodAssembly)
            : null;
    }
}
