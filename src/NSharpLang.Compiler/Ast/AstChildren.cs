using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler.Ast;

public static class AstChildren
{
    public static IEnumerable<Expression> Of(Expression expression)
        => AstChildrenCore.Of(expression).Cast<Expression>();
}
