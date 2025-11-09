using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler.ILCompiler;

/// <summary>
/// Compiles N# AST directly to IL using System.Reflection.Emit
/// </summary>
public class ILCompiler
{
    private readonly CompilationUnit _compilationUnit;
    private readonly string _assemblyName;
    private readonly string _outputPath;

    public ILCompiler(CompilationUnit compilationUnit, string assemblyName, string outputPath)
    {
        _compilationUnit = compilationUnit;
        _assemblyName = assemblyName;
        _outputPath = outputPath;
    }

    /// <summary>
    /// Compile the AST to an assembly file
    /// </summary>
    public void Compile()
    {
        // Create assembly builder
        var assemblyName = new AssemblyName(_assemblyName);
        var assemblyBuilder = AssemblyBuilder.DefineDynamicAssembly(
            assemblyName,
            AssemblyBuilderAccess.RunAndCollect);

        // Create module builder
        var moduleBuilder = assemblyBuilder.DefineDynamicModule(_assemblyName);

        // Create Program class (entry point container)
        var programType = moduleBuilder.DefineType(
            "Program",
            TypeAttributes.Public | TypeAttributes.Class);

        // Emit all top-level functions as static methods on Program class
        foreach (var declaration in _compilationUnit.Declarations)
        {
            if (declaration is FunctionDeclaration funcDecl)
            {
                EmitFunction(programType, funcDecl);
            }
        }

        // Create the type
        programType.CreateType();

        // For now, we can't save to disk with AssemblyBuilder in .NET Core/9
        // We would need to use a library like Mono.Cecil or System.Reflection.Metadata
        Console.WriteLine($"IL Compiler: Assembly '{_assemblyName}' compiled (in-memory only)");
        Console.WriteLine("Note: Saving to disk requires additional library (Mono.Cecil or System.Reflection.Metadata)");
    }

    /// <summary>
    /// Emit a function as a method
    /// </summary>
    private void EmitFunction(TypeBuilder typeBuilder, FunctionDeclaration function)
    {
        // Determine return type
        var returnType = function.ReturnType != null
            ? ResolveType(function.ReturnType)
            : typeof(void);

        // Determine parameter types
        var parameterTypes = function.Parameters
            .Select(p => ResolveType(p.Type))
            .ToArray();

        // Create method
        var methodBuilder = typeBuilder.DefineMethod(
            function.Name,
            MethodAttributes.Public | MethodAttributes.Static,
            returnType,
            parameterTypes);

        // Special case: if this is "main", make it the entry point
        if (function.Name.ToLower() == "main")
        {
            // Entry point methods should return void or int
            // and take no parameters or string[]
        }

        // Get IL generator
        var il = methodBuilder.GetILGenerator();

        // For now, emit a simple return
        // TODO: Emit the actual function body
        if (returnType == typeof(void))
        {
            il.Emit(OpCodes.Ret);
        }
        else if (returnType == typeof(int))
        {
            il.Emit(OpCodes.Ldc_I4_0); // Return 0
            il.Emit(OpCodes.Ret);
        }
        else
        {
            il.Emit(OpCodes.Ldnull); // Return null for reference types
            il.Emit(OpCodes.Ret);
        }
    }

    /// <summary>
    /// Resolve a type reference to a System.Type
    /// </summary>
    private Type ResolveType(TypeReference typeRef)
    {
        if (typeRef is SimpleTypeReference simpleType)
        {
            return simpleType.Name switch
            {
                "int" => typeof(int),
                "long" => typeof(long),
                "float" => typeof(float),
                "double" => typeof(double),
                "bool" => typeof(bool),
                "string" => typeof(string),
                "void" => typeof(void),
                "object" => typeof(object),
                _ => typeof(object) // Default to object for unknown types
            };
        }

        // TODO: Handle generic types, array types, etc.
        return typeof(object);
    }
}
