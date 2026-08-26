namespace NSharpLang.Cli

// THE `nlc` COMMAND REGISTRY — THE ONE LIST THAT HELP, COMPLETIONS AND THE DOCS ALL ANSWER TO.
//
// These blocks replace the registry half of ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs` (29 declaration lines, 10 `Assert.`
// rows). The body read `CommandRegistry.TopLevelCommands` and `.QueryCommands`, then drove
// `Program.Execute("help")`, `QueryCommand.Execute(["help"])` and `CompletionCommand.Execute
// (["zsh"])` through a console capture and compared everything against `website/docs/
// cli-reference.md`.
//
// THE BODY IS SPLIT, AND THE SPLIT MAKES BOTH HALVES STRONGER. `Console.SetOut` declines on this
// emit path at `emit.call.static-member-unmodeled`, so the three console captures cannot be made
// here; they are in `tests/native/cli-command-contracts`, spawned against the real binary. What
// stays here is the REGISTRY ITSELF — and the deleted body never pinned it. It looped over
// whatever the registry happened to contain and checked that each name appeared elsewhere, so a
// registry that silently LOST a command would have passed: the loop would simply have had one
// less iteration, and every remaining assertion would still have held. **THE REGISTRY'S CONTENT
// IS NOW LITERAL ON THIS SIDE AND LITERAL ON THE NATIVE SIDE**, so neither can drift into the
// other.

test "the registry lists exactly 27 top-level commands, in this order" {
    commands := CommandRegistry.TopLevelCommands

    assert commands.Count == 27
    assert commands[0].Name == "build"
    assert commands[1].Name == "run"
    assert commands[2].Name == "new"
    assert commands[3].Name == "init"
    assert commands[4].Name == "test"
    assert commands[5].Name == "format"
    assert commands[6].Name == "lint"
    assert commands[7].Name == "clean"
    assert commands[8].Name == "watch"
    assert commands[9].Name == "doc"
    assert commands[10].Name == "completion"
    assert commands[11].Name == "check"
    assert commands[12].Name == "fix"
    assert commands[13].Name == "query"
    assert commands[14].Name == "daemon"
    assert commands[15].Name == "add"
    assert commands[16].Name == "tidy"
    assert commands[17].Name == "remove"
    assert commands[18].Name == "update"
    assert commands[19].Name == "publish"
    assert commands[20].Name == "tree"
    assert commands[21].Name == "audit"
    assert commands[22].Name == "env"
    assert commands[23].Name == "doctor"
    assert commands[24].Name == "restore"
    assert commands[25].Name == "pack"
    assert commands[26].Name == "help"
}

test "the registry lists exactly 19 query subcommands, in this order" {
    commands := CommandRegistry.QueryCommands

    assert commands.Count == 19
    assert commands[0].Name == "batch"
    assert commands[1].Name == "symbols"
    assert commands[2].Name == "outline"
    assert commands[3].Name == "ast"
    assert commands[4].Name == "diagnostics"
    assert commands[5].Name == "type"
    assert commands[6].Name == "inspect"
    assert commands[7].Name == "definition"
    assert commands[8].Name == "def"
    assert commands[9].Name == "references"
    assert commands[10].Name == "refs"
    assert commands[11].Name == "completions"
    assert commands[12].Name == "doc"
    assert commands[13].Name == "hover"
    assert commands[14].Name == "call-graph"
    assert commands[15].Name == "implementors"
    assert commands[16].Name == "perf"
    assert commands[17].Name == "trusted"
    assert commands[18].Name == "help"
}

test "exactly two query subcommands are ALIASES, and each names what it aliases" {
    // A FACT THE DELETED BODY COULD NOT SEE. It read only `.Name` from every spec, so the third
    // field of the record — the one that makes `nlc query def` mean `nlc query definition` — was
    // invisible to it, and a registry that dropped every alias link would have passed.
    commands := CommandRegistry.QueryCommands

    aliasCount := 0
    i := 0
    while i < commands.Count {
        if commands[i].AliasOf != null {
            aliasCount = aliasCount + 1
        }

        i = i + 1
    }

    assert aliasCount == 2
    assert commands[8].AliasOf == "definition"
    assert commands[10].AliasOf == "references"
}

test "every top-level command carries a non-empty description" {
    // The description is what `nlc help` prints beside each name; the deleted body never read one.
    commands := CommandRegistry.TopLevelCommands
    i := 0
    while i < commands.Count {
        assert commands[i].Description.Length > 0
        assert commands[i].Name.Length > 0
        i = i + 1
    }
}

test "every query subcommand carries a non-empty description, aliases included" {
    commands := CommandRegistry.QueryCommands
    i := 0
    while i < commands.Count {
        assert commands[i].Description.Length > 0
        assert commands[i].Name.Length > 0
        i = i + 1
    }

    assert commands[8].Description == "Alias for definition"
    assert commands[10].Description == "Alias for references"
}

test "no command name is repeated in either list" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. Its `Contains` loop would happily pass a registry
    // that listed `build` twice and `pack` not at all.
    topLevel := CommandRegistry.TopLevelCommands
    i := 0
    while i < topLevel.Count {
        j := i + 1
        while j < topLevel.Count {
            assert topLevel[i].Name != topLevel[j].Name
            j = j + 1
        }

        i = i + 1
    }

    queryCommands := CommandRegistry.QueryCommands
    k := 0
    while k < queryCommands.Count {
        m := k + 1
        while m < queryCommands.Count {
            assert queryCommands[k].Name != queryCommands[m].Name
            m = m + 1
        }

        k = k + 1
    }
}

test "the retired `idiom` command is in NEITHER list" {
    // The deleted body's four `DoesNotContain("idiom", …)` rows, of which THIS is the only one
    // that is about the registry. The other three are about `nlc help`, the zsh completion script
    // and the docs, and they are in `tests/native/cli-command-contracts`.
    topLevel := CommandRegistry.TopLevelCommands
    i := 0
    while i < topLevel.Count {
        assert topLevel[i].Name != "idiom"
        i = i + 1
    }

    queryCommands := CommandRegistry.QueryCommands
    j := 0
    while j < queryCommands.Count {
        assert queryCommands[j].Name != "idiom"
        j = j + 1
    }
}

test "the joined command names are space-separated with no leading or trailing space" {
    // `JoinCommandNames` is what the completion scripts are built from, and the deleted body never
    // called it. The empty case is the one that a naive `+= name + " "` gets wrong.
    // MEASURED: passing the `IReadOnlyList` PROPERTY straight into the `IEnumerable` parameter
    // declines at `emit.call.static-user-argument`. The array the property is built from widens
    // cleanly, and it is the same sequence.
    joined := CommandRegistry.JoinCommandNames(CommandRegistry.BuildTopLevelCommands())

    assert joined.StartsWith("build run new init test ")
    assert joined.EndsWith(" pack help")
    assert !joined.StartsWith(" ")
    assert !joined.EndsWith(" ")
    assert joined.Split(" ").Length == 27
}
