using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class EnumTypeInfoFactory
{
    public static EnumTypeInfo FromDeclaration(EnumDeclaration declaration)
    {
        var members = declaration.Members
            .Select(CreateMemberInfo)
            .ToList();

        return new EnumTypeInfo(new EnumDeclarationInfo(
            declaration.Name,
            members,
            declaration.Type,
            declaration.Line,
            declaration.Column));
    }

    private static EnumMemberInfo CreateMemberInfo(EnumMember member)
    {
        var valueKind = EnumMemberValueKind.None;
        string? valueText = null;

        switch (member.Value)
        {
            case StringLiteralExpression stringLiteral:
                valueKind = EnumMemberValueKind.String;
                valueText = stringLiteral.Value;
                break;
            case IntLiteralExpression intLiteral:
                valueKind = EnumMemberValueKind.Integer;
                valueText = intLiteral.Value;
                break;
        }

        return new EnumMemberInfo(
            member.Name,
            member.Line,
            member.Column,
            valueKind,
            valueText);
    }
}
