using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

internal static class AnonymousUnionShimSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static bool TryDeclaresShims(
        IReadOnlyList<Parameter> parameters,
        Func<TypeReference, bool> isTwoArmAnonymousUnion,
        out bool declaresShims)
    {
        declaresShims = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var parameterCount = parameters.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(parameterCount);

        try
        {
            var unionParameterCount = 0;
            for (var i = 0; i < parameterCount; i++)
            {
                var parameter = parameters[i];
                if (!isTwoArmAnonymousUnion(parameter.Type))
                {
                    continue;
                }

                var hasDisallowedModifier =
                    parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out or Ast.ParameterModifier.Params;
                scratch.ParameterFlags[unionParameterCount] = hasDisallowedModifier ? 2 : 1;
                unionParameterCount++;
            }

            var result = bindings.AnonymousUnionDeclaresPublicShim(
                scratch.ParameterFlags,
                unionParameterCount);
            if (result is not 0 and not 1)
                return false;

            declaresShims = result != 0;
            return true;
        }
        catch
        {
            declaresShims = false;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<AnonymousUnionDeclaresPublicShim>(
                programType,
                "AnonymousUnionDeclaresPublicShim")));

    private delegate int AnonymousUnionDeclaresPublicShim(int[] parameterFlags, int count);

    private sealed record Bindings(AnonymousUnionDeclaresPublicShim AnonymousUnionDeclaresPublicShim);

    private sealed class Scratch
    {
        internal int[] ParameterFlags = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ParameterFlags.Length < count)
            {
                ParameterFlags = new int[count];
            }
        }
    }
}
