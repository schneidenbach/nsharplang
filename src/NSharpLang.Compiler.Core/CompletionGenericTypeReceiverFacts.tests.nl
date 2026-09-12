namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE EDITOR HALF OF THE CONSTRUCTED-GENERIC-TYPE RECEIVER: what a caret after `Vector<int>.`
// offers, and the two independent readings of a receiver that have to agree for it to offer
// anything.
//
// A COMPLETION READS THE RECEIVER TWICE — once from the BUFFER TEXT before the caret, which is all
// that exists while the line is half-written, and once from the parsed EXPRESSION, which is what
// carries the type. Both had a hole for this shape and each hole was invisible from the other side:
// the text scan stopped at the `>` before the dot and answered "this is not a member access at all",
// and the expression side had no reading for the node, so even the position that DID classify as a
// member access answered with no receiver. The two contracts below are that pair.
//
// THE `>` RULE IS DELIBERATELY NARROW. A `>` opens a type-argument run only where it CANNOT be the
// comparison operator — immediately before the dot, or inside a run already open — so `a>b.` still
// reads back the receiver `b`, which is the reading it has always had.
func CgtrClassify(beforeCursor: string): CompletionReceiverClassification {
    return CompletionEngineKernels.ClassifyCompletionReceiver(beforeCursor)
}

func CgtrGenericTypeExpression(name: string, argumentName: string): Expression {
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference(argumentName, 3, 20))
    return new GenericTypeExpression(new GenericTypeReference(name, arguments, 3, 5), 3, 5)
}

test "the text scan reads a constructed generic receiver back as the type the developer wrote" {
    afterDot := CgtrClassify("    x := Vector<int>.")
    assert afterDot.IsMemberAccess
    assert afterDot.Receiver == "Vector<int>"

    partialMember := CgtrClassify("    x := Vector<int>.Cou")
    assert partialMember.IsMemberAccess
    assert partialMember.Receiver == "Vector<int>"
}

test "a NESTED type argument list is read back whole, `>>` and separating comma included" {
    nested := CgtrClassify("    x := Dictionary<string, List<int>>.")
    assert nested.IsMemberAccess
    assert nested.Receiver == "Dictionary<string, List<int>>"
}

test "a QUALIFIED head keeps its namespace, because the dotted prefix is part of the type name" {
    qualified := CgtrClassify("    x := System.Numerics.Vector<int>.")
    assert qualified.IsMemberAccess
    assert qualified.Receiver == "System.Numerics.Vector<int>"
}

test "the `>` rule does not swallow a comparison: `a>b.` still reads back `b`" {
    comparison := CgtrClassify("    x := a>b.")
    assert comparison.IsMemberAccess
    assert comparison.Receiver == "b"

    spaced := CgtrClassify("    x := a > b.")
    assert spaced.IsMemberAccess
    assert spaced.Receiver == "b"
}

test "a comparison with no dot after it is not a member access at all" {
    assert CgtrClassify("    x := a < b && c > d").IsMemberAccess == false
    assert CgtrClassify("    x := lower < value && value > upper").IsMemberAccess == false
}

test "the ordinary receivers are unchanged by the angle-bracket rule" {
    assert CgtrClassify("    x := items.").Receiver == "items"
    assert CgtrClassify("    Console.Wri").Receiver == "Console"
    assert CgtrClassify("    x := builder.Append(1).").Receiver == "builder.Append()"
}

test "the parsed receiver reads back as the same text the buffer scan produced" {
    assert CompletionReceiverFacts.FormatReceiverExpression(CgtrGenericTypeExpression("Vector", "int")) == "Vector<int>"
}

test "a constructed generic receiver reflects over the definition the analyzer resolved, not a name table" {
    // `EqualityComparer<T>` is in no completion name table, and that is the point: the
    // `GenericTypeInfo` the analyzer built carries the open definition it resolved through the
    // ordinary arity-suffixed external probe, and the close happens over THAT.
    definition := typeof(EqualityComparer<int>).GetGenericTypeDefinition()
    arguments := new List<TypeInfo>()
    arguments.Add(new ReflectionTypeInfo(typeof(int)))
    receiverType := new GenericTypeInfo("EqualityComparer", arguments, new ReflectionTypeInfo(definition))

    closed := CompletionReflectionFacts.ResolveCompletionReflectionType(receiverType)
    assert closed != null
    resolved := must closed
    assert resolved == typeof(EqualityComparer<int>)
}

test "a constructed generic with no resolved definition and no table row offers nothing rather than guessing" {
    arguments := new List<TypeInfo>()
    arguments.Add(new ReflectionTypeInfo(typeof(int)))
    assert CompletionReflectionFacts.ResolveCompletionReflectionType(new GenericTypeInfo("NotATypeAnyoneKnows", arguments, null)) == null
}
