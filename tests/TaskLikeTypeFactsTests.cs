using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class TaskLikeTypeFactsTests
{
    [Fact]
    public void TaskLikeTypeFacts_OwnsUnitTaskLikeClassification()
    {
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("Task")));
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("System.Threading.Tasks.ValueTask")));
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeType(new GenericTypeInfo("Task", new List<TypeInfo>())));
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeType(new ExternalTypeInfo("System.Threading.Tasks.Task")));

        Assert.False(TaskLikeTypeFacts.IsUnitTaskLikeType(
            new GenericTypeInfo("Task", new List<TypeInfo> { BuiltInTypes.String })));
        Assert.False(TaskLikeTypeFacts.IsUnitTaskLikeType(BuiltInTypes.String));
    }

    [Fact]
    public void TaskLikeTypeFacts_OwnsTaskLikeTypeReferenceClassification()
    {
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new SimpleTypeReference("ValueTask")));
        Assert.True(TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(
            new GenericTypeReference("System.Threading.Tasks.Task", new List<TypeReference>())));

        Assert.False(TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(
            new GenericTypeReference("Task", new List<TypeReference> { new SimpleTypeReference("string") })));
        Assert.False(TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new SimpleTypeReference("string")));
        Assert.False(TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(null));
    }

    [Fact]
    public void TaskLikeTypeFacts_OwnsTaskLikeResultTypeExtraction()
    {
        var sourceResult = TaskLikeTypeFacts.GetTaskLikeResultType(
            new GenericTypeInfo("Task", new List<TypeInfo> { BuiltInTypes.String }));

        Assert.True(sourceResult.Found);
        Assert.Equal(BuiltInTypes.String, sourceResult.SourceResultType);

        var none = TaskLikeTypeFacts.GetTaskLikeResultType(BuiltInTypes.String);

        Assert.False(none.Found);
        Assert.Null(none.SourceResultType);
    }
}
