using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class SourceNominalTypeInfoFactory
{
    public static ClassDeclaration GetDeclaration(this ClassTypeInfo type)
        => (ClassDeclaration)type.Declaration;

    public static StructDeclaration GetDeclaration(this StructTypeInfo type)
        => (StructDeclaration)type.Declaration;

    public static RecordDeclaration GetDeclaration(this RecordTypeInfo type)
        => (RecordDeclaration)type.Declaration;

    public static InterfaceDeclaration GetDeclaration(this InterfaceTypeInfo type)
        => (InterfaceDeclaration)type.Declaration;
}
