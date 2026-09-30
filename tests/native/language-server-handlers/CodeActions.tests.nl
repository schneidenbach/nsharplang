namespace NSharpLang.LanguageServerHandlers.Tests

import System
import OmniSharp.Extensions.LanguageServer.Protocol.Models

func LshActionEditText(action: CodeAction): string {
    edit := action.Edit
    if edit == null {
        throw new InvalidOperationException("Code action did not provide a workspace edit.")
    }

    changes := edit.Changes
    if changes == null {
        throw new InvalidOperationException("Workspace edit did not provide changes.")
    }

    for edits in changes.Values {
        for textEdit in edits {
            return textEdit.NewText
        }
    }

    throw new InvalidOperationException("Workspace edit did not contain a text edit.")
}

test "NL209 code actions expose both enabled member and free-function edits" {
    docs := LshNewDocs()
    uri := "file:///test/code_action_ambiguous_member_free.nl"
    source := LshBody(
        """
namespace Probe

func Foo(): string => "free"

class Widget {
    func Foo(): string => "member"
    func Run(): string => Foo()
}

"""
    )
    LshOpen(docs, uri, source)

    line := 6
    column := LshLineColumn(source, line, "Foo")
    actions := LshCodeActions(docs, uri, line, column, "Foo".Length, "NL209")
    assert actions != null

    memberActionFound := false
    freeFunctionActionFound := false
    actionCount := 0
    for item in actions {
        assert item.IsCodeAction
        action := item.CodeAction
        if action == null {
            throw new InvalidOperationException("NL209 result did not contain a code action.")
        }

        assert action.Disabled == null
        if action.Title == "Call the member with this.Foo(...)" {
            assert LshActionEditText(action) == "this."
            memberActionFound = true
        } else if action.Title == "Call the free function with Probe.Foo(...)" {
            assert LshActionEditText(action) == "Probe.Foo"
            freeFunctionActionFound = true
        }
        actionCount = actionCount + 1
    }

    assert actionCount == 2
    assert memberActionFound
    assert freeFunctionActionFound
}

test "NL209 read-position code actions qualify a member value and a free-function group" {
    docs := LshNewDocs()
    uri := "file:///test/code_action_ambiguous_member_free_read.nl"
    source := LshBody(
        """
namespace Probe

func Foo(): string => "free"

class Widget {
    Foo: string = "member"
    func Read(): string {
        value := Foo
        return value
    }
}
"""
    )
    LshOpen(docs, uri, source)

    line := 7
    column := LshLineColumn(source, line, "Foo")
    actions := LshCodeActions(docs, uri, line, column, "Foo".Length, "NL209")
    assert actions != null

    memberActionFound := false
    freeFunctionActionFound := false
    actionCount := 0
    for item in actions {
        action := item.CodeAction
        if action != null {
            if action.Title == "Use the member this.Foo" {
                assert LshActionEditText(action) == "this."
                memberActionFound = true
            } else if action.Title == "Use the free-function group Probe.Foo" {
                assert LshActionEditText(action) == "Probe.Foo"
                freeFunctionActionFound = true
            }
            actionCount = actionCount + 1
        }
    }

    assert actionCount == 2
    assert memberActionFound
    assert freeFunctionActionFound
}

test "NL209 code actions qualify a static member through its type" {
    docs := LshNewDocs()
    uri := "file:///test/code_action_ambiguous_static_member_free.nl"
    source := LshBody(
        """
namespace Probe

func Foo(): string => "free"

class Widget {
    static func Foo(): string => "member"
    static func Run(): string => Foo()
}
"""
    )
    LshOpen(docs, uri, source)

    line := 6
    column := LshLineColumn(source, line, "Foo")
    actions := LshCodeActions(docs, uri, line, column, "Foo".Length, "NL209")
    assert actions != null

    memberActionFound := false
    for item in actions {
        action := item.CodeAction
        if action != null && action.Title == "Call the member with Probe.Widget.Foo(...)" {
            assert action.Disabled == null
            assert LshActionEditText(action) == "Probe.Widget.Foo"
            memberActionFound = true
        }
    }

    assert memberActionFound
}
