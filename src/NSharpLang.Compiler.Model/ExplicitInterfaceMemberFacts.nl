namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text


// AN EXPLICIT INTERFACE IMPLEMENTATION IS SPELLED WITH A QUALIFIED MEMBER NAME, AND THIS FILE OWNS
// WHAT THAT SPELLING MEANS.
//
// `func IEnumerable.GetEnumerator(): IEnumerator { … }` inside a type body implements the interface's
// slot and NOTHING ELSE. The member is private, final, virtual and newslot, it carries a MethodImpl
// row on that slot, and it is reachable ONLY through the interface — never through the declaring type
// and never by the casing convention, which does not apply to a member that has no accessibility to
// decide. A generic interface is written CLOSED, exactly as the implements list writes it
// (`IEnumerable<string>.GetEnumerator`).
//
// **THE DECLARED SPELLING IS THE MEMBER TABLE'S KEY, AND THAT IS THE DESIGN.** Every member table in
// the front end and the backend is keyed by the member's name; storing an explicit implementation
// under its QUALIFIED name means an ordinary lookup for `GetEnumerator` does not find it, which is
// exactly the reachability rule the feature is for — no lookup had to learn a new rule to get it, and
// overload resolution over the simple name is untouched. It is also why an implicit `GetEnumerator`
// and an explicit `IEnumerable.GetEnumerator` coexist without colliding: they are two keys.
//
// **THE CLR NAME IS A THIRD STRING, and it is not the declared one.** Metadata spells the interface
// FULLY QUALIFIED with its type arguments fully qualified too — measured against the BCL's own
// assemblies, `List<T>` carries `System.Collections.IEnumerable.GetEnumerator` and
// `Dictionary<TKey, TValue>` carries
// `System.Collections.Generic.ICollection<System.Collections.Generic.KeyValuePair<TKey,TValue>>.Add`.
// So `RuntimeInterfaceDisplayName` renders the resolved interface the way Roslyn does and
// `MetadataName` joins it to the simple name; a consumer in any .NET language then finds the member
// where it expects to.
class ExplicitInterfaceMemberFacts {

    // THE DOT IS READ AT ANGLE DEPTH ZERO. `IDictionary<string, List<int>>.Add` has dots inside its
    // type arguments in the general case (`IFoo<System.Guid>.Bar`), and a qualifier's own dots are
    // part of the qualifier — only the LAST depth-zero dot separates the interface from the member.
    static func IsExplicitMemberName(name: string): bool {
        return LastSeparatorIndex(name) > 0
    }

    static func LastSeparatorIndex(name: string): int {
        if name == null || name.Length == 0 {
            return -1
        }

        depth := 0
        last := -1
        index := 0
        while index < name.Length {
            ch := name[index]
            if ch == '<' {
                depth = depth + 1
            } else if ch == '>' {
                depth = depth - 1
            } else if ch == '.' && depth == 0 {
                last = index
            }

            index = index + 1
        }

        if last <= 0 || last >= name.Length - 1 {
            return -1
        }

        return last
    }

    // The interface as WRITTEN — `IEnumerable`, `IEnumerable<string>`, `System.Collections.IEnumerable`.
    // Empty when the name is not a qualified one, so a caller that forgot to ask gets nothing rather
    // than a wrong half.
    static func QualifierOf(name: string): string {
        separator := LastSeparatorIndex(name)
        if separator < 0 {
            return ""
        }

        return name.Substring(0, separator)
    }

    // The member's own name — the name the interface declares the slot under, and the name the slot
    // match is made on. For a name that is not qualified this is the name itself, so a caller may use
    // it unconditionally.
    static func SimpleNameOf(name: string): string {
        separator := LastSeparatorIndex(name)
        if separator < 0 {
            return name
        }

        return name.Substring(separator + 1)
    }

    // THE BARE INTERFACE NAME WITHOUT ITS TYPE ARGUMENTS, for matching a written qualifier against the
    // implements list: `IEnumerable<string>` answers `IEnumerable`, `System.Collections.IEnumerable`
    // answers `System.Collections.IEnumerable`.
    static func QualifierOpenName(qualifier: string): string {
        index := qualifier.IndexOf('<')
        if index < 0 {
            return qualifier
        }

        return qualifier.Substring(0, index)
    }

    // The LAST segment of a dotted qualifier, so a qualifier written with its namespace still matches
    // an implements list that writes the interface bare.
    static func QualifierSimpleName(qualifier: string): string {
        openName := QualifierOpenName(qualifier)
        index := openName.LastIndexOf('.')
        if index < 0 {
            return openName
        }

        return openName.Substring(index + 1)
    }

    // How many type arguments the written qualifier closes over, counted at depth one so a nested
    // argument does not add to the count. Zero for a non-generic qualifier.
    static func QualifierArity(qualifier: string): int {
        open := qualifier.IndexOf('<')
        if open < 0 {
            return 0
        }

        depth := 0
        arity := 1
        index := open
        while index < qualifier.Length {
            ch := qualifier[index]
            if ch == '<' {
                depth = depth + 1
            } else if ch == '>' {
                depth = depth - 1
                if depth == 0 {
                    return arity
                }
            } else if ch == ',' && depth == 1 {
                arity = arity + 1
            }

            index = index + 1
        }

        return arity
    }

    // Whether the written qualifier carries an argument list at all — `IEnumerable<>` and
    // `IEnumerable<T>` both do, `IEnumerable` does not. A generic interface must be written closed, so
    // this is what tells a missing argument list from a present one.
    static func QualifierIsConstructed(qualifier: string): bool {
        return qualifier.IndexOf('<') >= 0
    }

    // THE TREE READING OF THE SPELLING, for the parser that walks a `List<Token>`. It mirrors
    // `ExplicitInterfaceMemberNameEnd` in the columnar kernels token for token, and the two exist for
    // the same reason `TypeAliasKeywordFacts` has two readings: the two pipelines carry tokens
    // differently and must not disagree about where a member's name ends.
    //
    // `nameIndex` is the index of the name's FIRST identifier. The answer is the index just PAST the
    // whole qualified name, or -1 when the name is an ordinary one-token name — so a generic METHOD's
    // `<T>`, which is an argument list with no dot behind it, leaves the caller's cursor alone.
    static func QualifiedMemberNameEnd(tokens: List<Token>, nameIndex: int): int {
        if nameIndex < 0 || nameIndex >= tokens.Count || tokens[nameIndex].Type != TokenType.Identifier {
            return -1
        }

        pos := nameIndex + 1
        lastEnd := -1
        scanning := true
        while scanning {
            if pos < tokens.Count && tokens[pos].Type == TokenType.Less {
                closed := QualifierArgumentListEnd(tokens, pos)
                if closed < 0 {
                    return lastEnd
                }

                pos = closed
            }

            if pos + 1 < tokens.Count && tokens[pos].Type == TokenType.Dot && tokens[pos + 1].Type == TokenType.Identifier {
                pos = pos + 2
                lastEnd = pos
            } else {
                scanning = false
            }
        }

        return lastEnd
    }

    // `>>` is ONE token and closes TWO levels; a brace, a newline or end of file cannot appear inside a
    // type-argument list, so meeting one means the `<` was not a qualifier's.
    static func QualifierArgumentListEnd(tokens: List<Token>, lessIndex: int): int {
        depth := 0
        pos := lessIndex
        while pos < tokens.Count {
            kind := tokens[pos].Type
            if kind == TokenType.Less {
                depth = depth + 1
            } else if kind == TokenType.Greater {
                depth = depth - 1
                if depth <= 0 {
                    return pos + 1
                }
            } else if kind == TokenType.RightShift {
                depth = depth - 2
                if depth <= 0 {
                    return pos + 1
                }
            } else if kind == TokenType.LeftBrace || kind == TokenType.RightBrace || kind == TokenType.Eof || kind == TokenType.Newline {
                return -1
            }

            pos = pos + 1
        }

        return -1
    }

    // The canonical text of that name, built from the tokens' own values so the result never carries
    // the whitespace the author may have written around the punctuation — a canonical name has none,
    // which is what lets the two pipelines produce the SAME string for the same declaration.
    static func QualifiedMemberNameText(tokens: List<Token>, nameIndex: int, nameEnd: int): string {
        builder := new StringBuilder()
        index := nameIndex
        while index < nameEnd && index < tokens.Count {
            builder.Append(tokens[index].Value)
            index = index + 1
        }

        return builder.ToString()
    }

    static func MetadataName(interfaceDisplayName: string, simpleName: string): string {
        return interfaceDisplayName + "." + simpleName
    }

    // An accessor of an explicit VALUE member is named the same way its property is — the BCL carries
    // `System.Collections.IList.get_Item` beside `System.Collections.IList.Item` — so the accessor
    // prefix goes on the SIMPLE name, inside the qualification, not in front of the whole thing.
    static func MetadataAccessorName(interfaceDisplayName: string, accessorPrefix: string, simpleName: string): string {
        return interfaceDisplayName + "." + accessorPrefix + simpleName
    }

    // THE INTERFACE AS METADATA SPELLS IT. Namespace-qualified, its type arguments rendered the same
    // way recursively, and a TYPE PARAMETER rendered by its bare name — which is what the BCL's own
    // `System.Collections.Generic.ICollection<System.Collections.Generic.KeyValuePair<TKey,TValue>>.Add`
    // shows. A nested type is joined with `.` rather than reflection's `+`, because that is the name a
    // C# consumer writes and the name Roslyn emits.
    static func RuntimeInterfaceDisplayName(interfaceType: Type): string {
        if interfaceType.IsGenericParameter {
            return interfaceType.Name
        }

        if !interfaceType.IsGenericType {
            return NonGenericDisplayName(interfaceType)
        }

        builder := new StringBuilder()
        builder.Append(GenericOpenDisplayName(interfaceType))
        builder.Append('<')
        arguments := interfaceType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if index > 0 {
                builder.Append(',')
            }

            builder.Append(RuntimeInterfaceDisplayName(arguments[index]))
            index = index + 1
        }

        builder.Append('>')
        return builder.ToString()
    }

    static func NonGenericDisplayName(interfaceType: Type): string {
        fullName := interfaceType.FullName
        if fullName == null || fullName.Length == 0 {
            namespaceName := interfaceType.Namespace
            if namespaceName == null || namespaceName.Length == 0 {
                return interfaceType.Name
            }

            return namespaceName + "." + interfaceType.Name
        }

        return fullName.Replace('+', '.')
    }

    // The open name with reflection's arity suffix removed: `IEnumerable`1` is written `IEnumerable`.
    static func GenericOpenDisplayName(interfaceType: Type): string {
        name := interfaceType.Name
        tick := name.IndexOf('`')
        if tick >= 0 {
            name = name.Substring(0, tick)
        }

        declaring := interfaceType.DeclaringType
        if declaring != null {
            return RuntimeInterfaceDisplayName(declaring) + "." + name
        }

        namespaceName := interfaceType.Namespace
        if namespaceName == null || namespaceName.Length == 0 {
            return name
        }

        return namespaceName + "." + name
    }
}
