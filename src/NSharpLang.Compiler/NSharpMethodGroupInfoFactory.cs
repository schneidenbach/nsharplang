using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class NSharpMethodGroupInfoFactory
{
    public static NSharpMethodGroupInfo FromDeclarations(IEnumerable<FunctionDeclaration> declarations)
        => new(declarations.Cast<object>().ToList());

    public static IReadOnlyList<FunctionDeclaration> GetDeclarations(NSharpMethodGroupInfo methodGroup)
        => methodGroup.Declarations.OfType<FunctionDeclaration>().ToList();

    public static void AddDeclaration(NSharpMethodGroupInfo methodGroup, FunctionDeclaration declaration)
        => methodGroup.Declarations.Add(declaration);
}
