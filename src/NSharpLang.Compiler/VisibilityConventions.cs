using System;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public static class VisibilityConventions
{
    public static bool IsExportedIdentifier(string? name)
    {
        return !string.IsNullOrEmpty(name) && char.IsUpper(name[0]);
    }

    public static bool IsExportedIdentifier(string? name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return true;
        }

        if (modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Protected)
            || modifiers.HasFlag(Modifiers.Internal)
            || modifiers.HasFlag(Modifiers.File))
        {
            return false;
        }

        return IsExportedIdentifier(name);
    }

    public static bool HasExplicitVisibility(Modifiers modifiers)
    {
        // Explicit visibility modifiers are interop/migration escape hatches that
        // override casing, including `private PascalCase` to force a symbol hidden.
        return modifiers.HasFlag(Modifiers.Public)
            || modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Protected)
            || modifiers.HasFlag(Modifiers.Internal)
            || modifiers.HasFlag(Modifiers.File);
    }

    public static string GetTopLevelTypeVisibilityKeyword(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return "public";
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return "internal";
        }

        return IsExportedIdentifier(name, modifiers) ? "public" : "internal";
    }

    public static string GetNestedTypeVisibilityKeyword(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return "public";
        }

        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return "protected internal";
        }

        if (modifiers.HasFlag(Modifiers.Private))
        {
            return "private";
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return "protected";
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return "internal";
        }

        return IsExportedIdentifier(name, modifiers) ? "public" : "private";
    }

    public static string GetMemberVisibilityKeyword(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return "public";
        }

        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return "protected internal";
        }

        if (modifiers.HasFlag(Modifiers.Private))
        {
            return "private";
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return "protected";
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return "internal";
        }

        // Lowercase members are unexported by convention but remain assembly-visible
        // in emitted CLR so same-project N# calls/object initializers continue to work.
        return IsExportedIdentifier(name, modifiers) ? "public" : "internal";
    }

    public static TypeAttributes GetTopLevelTypeAttributes(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return TypeAttributes.Public;
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return TypeAttributes.NotPublic;
        }

        return IsExportedIdentifier(name, modifiers) ? TypeAttributes.Public : TypeAttributes.NotPublic;
    }

    public static TypeAttributes GetNestedTypeAttributes(string name, Modifiers modifiers)
    {
        if (modifiers.HasFlag(Modifiers.Public))
        {
            return TypeAttributes.NestedPublic;
        }

        if (modifiers.HasFlag(Modifiers.Protected) && modifiers.HasFlag(Modifiers.Internal))
        {
            return TypeAttributes.NestedFamORAssem;
        }

        if (modifiers.HasFlag(Modifiers.Private))
        {
            return TypeAttributes.NestedPrivate;
        }

        if (modifiers.HasFlag(Modifiers.Protected))
        {
            return TypeAttributes.NestedFamily;
        }

        if (modifiers.HasFlag(Modifiers.Internal) || modifiers.HasFlag(Modifiers.File))
        {
            return TypeAttributes.NestedAssembly;
        }

        return IsExportedIdentifier(name, modifiers) ? TypeAttributes.NestedPublic : TypeAttributes.NestedPrivate;
    }

    public static MethodAttributes GetMemberMethodAttributes(string name, Modifiers modifiers)
    {
        return GetMemberVisibilityKeyword(name, modifiers) switch
        {
            "private" => MethodAttributes.Private,
            "protected internal" => MethodAttributes.FamORAssem,
            "protected" => MethodAttributes.Family,
            "internal" => MethodAttributes.Assembly,
            _ => MethodAttributes.Public
        };
    }

    public static FieldAttributes GetMemberFieldAttributes(string name, Modifiers modifiers)
    {
        return GetMemberVisibilityKeyword(name, modifiers) switch
        {
            "private" => FieldAttributes.Private,
            "protected internal" => FieldAttributes.FamORAssem,
            "protected" => FieldAttributes.Family,
            "internal" => FieldAttributes.Assembly,
            _ => FieldAttributes.Public
        };
    }
}

