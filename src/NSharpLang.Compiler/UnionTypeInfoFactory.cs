using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class UnionTypeInfoFactory
{
    public static UnionTypeInfo FromDeclaration(UnionDeclaration declaration)
        => new(new UnionDeclarationInfo(
            declaration.Name,
            declaration.TypeParameters,
            declaration.Cases,
            declaration.Line,
            declaration.Column));
}
