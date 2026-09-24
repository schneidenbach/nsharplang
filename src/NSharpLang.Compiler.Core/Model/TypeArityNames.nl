namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE ONE SPELLING OF "A TYPE NAME PLUS ITS GENERIC ARITY".
//
// A CLR type's identity is (namespace, name, generic arity), not (namespace, name): `Subscription`
// and `Subscription<T>` are two different types that may sit side by side in one assembly, and a
// consumer written in any other .NET language expects exactly that. Metadata already spells the pair
// as a single string — `Subscription``1 — and the analyzer's external probe, the columnar binding
// scope and the assembly catalog all speak that spelling for referenced assemblies.
//
// This is that spelling, stated once, for SOURCE declarations as well. An arity KEY is what the
// declaration tables are keyed by, what a reference is looked up under, and what the emitter writes
// into metadata; the DISPLAY name is what a diagnostic, a hover and a go-to-definition span carry.
// The two differ only for a generic type, and every caller that shows a name to a person must ask
// for the display form.
//
// THE ZERO CASE IS THE BARE NAME, deliberately. A non-generic type's key is its name unchanged, so
// every table that held bare names before still holds them, and a caller that never asks about
// generics never sees a backtick. `Key(name, 0)` and `Key(name, -1)` (an arity nobody could compute)
// are both the bare name: an unknown arity must not invent a new identity.
class TypeArityNames {

    // `Subscription` at arity 0, `Subscription``1 at arity 1. A name that ALREADY carries an arity
    // suffix is returned unchanged, so composing a key twice is the same as composing it once.
    static func Key(name: string, arity: int): string {
        if name == null || name.Length == 0 || arity <= 0 || HasArity(name) {
            return name
        }

        return name + "`" + arity.ToString()
    }

    // Whether a name carries a metadata arity suffix: a backtick followed by at least one digit, and
    // nothing after them. A name that merely contains a backtick is not one.
    static func HasArity(name: string): bool {
        return SuffixStart(name) > 0
    }

    // `Subscription``1 -> `Subscription`; `Subscription` -> `Subscription`. This is the DISPLAY name:
    // every diagnostic message, hover, completion label and go-to-definition span length is computed
    // from it and never from the key.
    static func Display(name: string): string {
        start := SuffixStart(name)
        if start <= 0 {
            return name
        }

        return name.Substring(0, start)
    }

    // The arity a key encodes: 0 for a bare name, N for `Name``N. A key is the only input; this never
    // inspects a declaration.
    static func ArityOf(name: string): int {
        start := SuffixStart(name)
        if start <= 0 {
            return 0
        }

        arity := 0
        if !int.TryParse(name.Substring(start + 1), out arity) {
            return 0
        }

        return arity
    }

    // The index of the arity backtick, or -1 when the name carries no suffix. A leading backtick is
    // not a suffix — a key always has a name in front of it.
    static func SuffixStart(name: string): int {
        if name == null || name.Length < 3 {
            return -1
        }

        tick := name.LastIndexOf('`')
        if tick <= 0 || tick == name.Length - 1 {
            return -1
        }

        index := tick + 1
        while index < name.Length {
            if !char.IsDigit(name[index]) {
                return -1
            }

            index = index + 1
        }

        return tick
    }

    // "1" for one arity, "1 and 2" for two, "1, 2 and 3" for more: the sentence fragment an
    // arity-mismatch diagnostic ends with, so the reader is told what IS available rather than only
    // what is not.
    static func DescribeArities(arities: List<int>): string {
        text := ""
        index := 0
        while index < arities.Count {
            if index > 0 {
                if index == arities.Count - 1 {
                    text = text + " and "
                } else {
                    text = text + ", "
                }
            }

            text = text + arities[index].ToString()
            index = index + 1
        }

        return text
    }

    // "'Subscription'", "'Subscription' or 'Subscription<T>'", "'A', 'B' or 'C'": every spelling of a
    // name that IS declared, quoted, for a suggestion that offers the reader a working alternative
    // rather than a rule.
    static func DescribeWrittenForms(name: string, arities: List<int>): string {
        text := ""
        index := 0
        while index < arities.Count {
            if index > 0 {
                if index == arities.Count - 1 {
                    text = text + " or "
                } else {
                    text = text + ", "
                }
            }

            text = text + "'" + WrittenForm(name, arities[index]) + "'"
            index = index + 1
        }

        return text
    }

    // How a type of this arity is WRITTEN in N# source: `Subscription`, `Subscription<T>`,
    // `Pair<T1, T2>`. Diagnostics that offer an alternative spelling use this so the suggestion can
    // be typed as it is read.
    static func WrittenForm(name: string, arity: int): string {
        display := Display(name)
        if arity <= 0 {
            return display
        }

        text := display + "<"
        index := 0
        while index < arity {
            if index > 0 {
                text = text + ", "
            }

            if arity == 1 {
                text = text + "T"
            } else {
                text = text + "T" + (index + 1).ToString()
            }

            index = index + 1
        }

        return text + ">"
    }
}
