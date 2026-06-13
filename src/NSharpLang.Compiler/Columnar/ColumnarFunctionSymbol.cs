using System.Collections.Generic;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// A top-level function symbol produced by the columnar self-host pipeline DIRECTLY from the columnar
/// declaration + signature tables — without materializing the C# <see cref="Ast.FunctionDeclaration"/> object
/// graph. This is the first downstream stage after the parser (see docs/design/columnar-pipeline.md): the
/// declared-symbol model that name resolution queries. Signatures are canonical strings so the columnar build
/// can be parity-checked against the C# AST-derived model.
/// </summary>
internal readonly record struct ColumnarFunctionSymbol(
    string Name,
    int Modifiers,
    IReadOnlyList<string> ParameterTypes,
    string? ReturnType)
{
    /// <summary>
    /// A canonical, position-free signature string used for parity comparison and as a stable symbol key:
    /// <c>{modifiers}|{name}({paramType,...}):{returnType|void}</c>.
    /// </summary>
    internal string Signature()
    {
        var sb = new StringBuilder();
        sb.Append(Modifiers).Append('|').Append(Name).Append('(');
        for (var i = 0; i < ParameterTypes.Count; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append(ParameterTypes[i]);
        }

        sb.Append("):").Append(ReturnType ?? "void");
        return sb.ToString();
    }

    /// <summary>
    /// Canonical type string for a C# AST <see cref="TypeReference"/>, matching the columnar type canon in
    /// <see cref="NSharpCompilerDogfoodAdapter"/> exactly (so the two symbol models compare equal). Simple
    /// names verbatim; <c>Name&lt;a,b&gt;</c> generics; <c>elem[]</c> arrays; <c>elem?</c> nullable;
    /// <c>a|b</c> unions; <c>&amp;elem</c> by-ref.
    /// </summary>
    internal static string CanonicalType(TypeReference type)
    {
        switch (type)
        {
            case SimpleTypeReference s:
                return s.Name;
            case GenericTypeReference g:
            {
                var sb = new StringBuilder();
                sb.Append(g.Name).Append('<');
                for (var i = 0; i < g.TypeArguments.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    sb.Append(CanonicalType(g.TypeArguments[i]));
                }

                sb.Append('>');
                return sb.ToString();
            }
            case ArrayTypeReference a:
                return CanonicalType(a.ElementType) + "[]";
            case NullableTypeReference n:
                return CanonicalType(n.InnerType) + "?";
            case UnionTypeReference u:
            {
                var sb = new StringBuilder();
                for (var i = 0; i < u.Arms.Count; i++)
                {
                    if (i > 0) sb.Append('|');
                    sb.Append(CanonicalType(u.Arms[i]));
                }

                return sb.ToString();
            }
            case ByRefTypeReference b:
                return "&" + CanonicalType(b.InnerType);
            case TupleTypeReference t:
            {
                // `(e0,e1,...)` — parens + comma-joined element canons (no spaces), matching the columnar kernel's
                // TupleTypeReference (kind 6) canonicalization in NSharpCompilerDogfoodAdapter.ColumnarTypeCanon.
                var sb = new StringBuilder();
                sb.Append('(');
                for (var i = 0; i < t.Elements.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    sb.Append(CanonicalType(t.Elements[i].Type));
                }

                sb.Append(')');
                return sb.ToString();
            }
            case FunctionTypeReference f:
            {
                // The production parser sugars the NAME `Func` into a FunctionTypeReference (params + return);
                // render it back as the SOURCE spelling `Func<p0,...,ret>` so it matches the columnar kernel's
                // canon exactly (the kernel sees `Func<int,int>` as an ordinary Generic node and renders it
                // verbatim — it has no source text to special-case the name).
                var sb = new StringBuilder();
                sb.Append("Func<");
                for (var i = 0; i < f.ParameterTypes.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    sb.Append(CanonicalType(f.ParameterTypes[i]));
                }

                if (f.ParameterTypes.Count > 0) sb.Append(',');
                sb.Append(CanonicalType(f.ReturnType)).Append('>');
                return sb.ToString();
            }
            default:
                return "?";
        }
    }
}
