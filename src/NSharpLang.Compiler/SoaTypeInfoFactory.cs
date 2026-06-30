using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class SoaTypeInfoFactory
{
    public static SoaRecordTypeInfo FromDeclaration(SoaRecordDeclaration declaration)
        => new(CreateDeclarationInfo(declaration));

    public static SoaRecordDeclarationInfo CreateDeclarationInfo(SoaRecordDeclaration declaration)
    {
        var columns = declaration.Columns
            .Select(column => new SoaColumnInfo(
                column.Name,
                column.Type,
                column.Line,
                column.Column))
            .ToList();

        return new SoaRecordDeclarationInfo(
            declaration.Name,
            columns,
            declaration.Line,
            declaration.Column);
    }
}
