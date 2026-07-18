namespace NSharpLang.Compiler

import System.Collections.Generic

test "source generics cannot impersonate runtime loop sequence shapes by name" {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    sourceList := new GenericTypeInfo(
        "List",
        arguments,
        new SimpleTypeInfo("source List"))

    assert LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
        sourceList,
        false) == null
}
