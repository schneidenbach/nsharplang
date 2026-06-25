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
        // Explicit visibility modifiers are interop escape hatches that
        // override casing, including `private PascalCase` to force a symbol hidden.
        return modifiers.HasFlag(Modifiers.Public)
            || modifiers.HasFlag(Modifiers.Private)
            || modifiers.HasFlag(Modifiers.Protected)
            || modifiers.HasFlag(Modifiers.Internal)
            || modifiers.HasFlag(Modifiers.File);
    }

}
