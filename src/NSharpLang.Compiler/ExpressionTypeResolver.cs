using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public class ExpressionTypeResolver
{
    private readonly SemanticModel _semanticModel;

    public ExpressionTypeResolver(SemanticModel semanticModel, Dictionary<string, Type>? importedTypes = null)
    {
        _semanticModel = semanticModel;
    }

    /// <summary>
    /// Resolves the semantic TypeInfo of an expression using the Analyzer's recorded
    /// </summary>
    public TypeInfo? ResolveExpressionTypeInfo(Expression expr)
    {
        var recordedType = _semanticModel.LookupTypeAtPosition(expr.Line, expr.Column);
        if (recordedType != null && !BuiltInTypes.IsUnknown(recordedType))
            return recordedType;

        return expr switch
        {
            _ => null
        };
    }

}
