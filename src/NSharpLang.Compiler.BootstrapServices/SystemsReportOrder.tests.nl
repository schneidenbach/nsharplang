namespace NSharpLang.Compiler.Performance

import System.Collections.Generic

// Native contracts for THE ORDER OF EVERY ROW A SYSTEMS REPORT SHOWS A USER.
//
// These four orders were three `OrderBy` chains in `SystemsAnalyzer.cs` (`:86` the file walk, `:103`
// the trusted sites, `:244` the per-function call list) plus one insertion sort inside
// `SystemsFindingSink`. The three C# chains were the whole product-decision residue of a 1,160-line
// walk that carries ZERO sentences and ZERO `NSYS` codes, and they are the reason this owner exists.
//
// TWO OF THE THREE WERE UNPINNED BY ANYTHING, AND THAT WAS MEASURED BEFORE THE MOVE. Every pinned
// systems envelope in the repository carried `trustedSites` 0 or 1, and of its 80 pinned
// `calls=[…]` values 54 were EMPTY, 26 held exactly ONE element and NONE held two — so neither the
// trusted-site sort nor the call-list `Distinct`+`OrderBy` could be observed by any existing
// contract. The blocks below pin them, and `tests/native/systems-analysis-census` pins the same two
// through the shipped CLI.
//
// SIX THINGS THIS OWNER IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE FILE ORDER IS CASE-INSENSITIVE AND THE CALL ORDER IS CASE-SENSITIVE. They are two
// different decisions about two different kinds of string — a path off a case-insensitive
// filesystem, and a NAME whose case carries visibility in N#. Folding one or unfolding the other is
// the single most plausible mistake here, so both directions are pinned against the SAME three
// strings.
//
// (2) THE CALL LIST DE-DUPLICATES, and it de-duplicates CASE-SENSITIVELY, so `Alpha` and `alpha`
// are two calls and not one.
//
// (3) THE DE-DUPLICATION AND THE ORDER ARE ONE DOOR. A caller cannot take the order without the
// de-duplication, because a call list that reported `zeta` five times would be answering a question
// nobody asked.
//
// (4) EVERY SORT IS STABLE. Two rows at one position keep the order the walk met them in.
//
// (5) A SHORTER STRING SORTS BEFORE A LONGER ONE IT IS A PREFIX OF, in both comparisons — that is
// what `StringComparer.Ordinal` and `StringComparer.OrdinalIgnoreCase` do, and a length comparison
// written the other way round is invisible until a project has both `a.nl` and `a.nl.bak`.
//
// (6) AN EMPTY INPUT ANSWERS EMPTY, not null — every one of these feeds a JSON array a consumer
// enumerates.

func SroFiles(values: List<string>): string[] {
    return SystemsReportOrder.OrderedFiles(values)
}

func SroList(a: string, b: string, c: string): List<string> {
    values := new List<string>()
    values.Add(a)
    values.Add(b)
    values.Add(c)
    return values
}

func SroJoin(values: string[]): string {
    text := ""
    index := 0
    while index < values.Length {
        if index > 0 {
            text = text + ","
        }

        text = text + values[index]
        index = index + 1
    }

    return text
}

func SroSite(name: string, filePath: string, line: int, column: int): SystemsTrustedSite {
    return new SystemsTrustedSite(name, filePath, line, column, null, null, null, null, false, 0)
}

func SroSiteNames(sites: SystemsTrustedSite[]): string {
    text := ""
    index := 0
    while index < sites.Length {
        if index > 0 {
            text = text + ","
        }

        text = text + sites[index].Function
        index = index + 1
    }

    return text
}

// ---------------------------------------------------------------------------
// THE FILE WALK ORDER — `SystemsAnalyzer.Analyze:86`
// ---------------------------------------------------------------------------

test "THE FILE WALK ORDER IS ASCENDING BY PATH" {
    ordered := SroFiles(SroList("z.nl", "a.nl", "m.nl"))
    assert SroJoin(ordered) == "a.nl,m.nl,z.nl"
}

test "THE FILE WALK ORDER IS CASE-INSENSITIVE, NOT ORDINAL" {
    // Ordinal would answer `B_one.nl,C_three.nl,a_two.nl`, because every uppercase UTF-16 unit
    // sorts before every lowercase one. A project is not allowed to reorder its own report by
    // renaming a file's first letter.
    ordered := SroFiles(SroList("B_one.nl", "a_two.nl", "C_three.nl"))
    assert SroJoin(ordered) == "a_two.nl,B_one.nl,C_three.nl"
}

test "A SHORTER PATH WALKS BEFORE A LONGER ONE IT IS A PREFIX OF" {
    values := new List<string>()
    values.Add("a.nl.bak")
    values.Add("a.nl")
    ordered := SroFiles(values)
    assert SroJoin(ordered) == "a.nl,a.nl.bak"
}

test "AN ALREADY-ORDERED FILE SET IS LEFT ALONE" {
    ordered := SroFiles(SroList("a.nl", "b.nl", "c.nl"))
    assert SroJoin(ordered) == "a.nl,b.nl,c.nl"
}

test "A SINGLE FILE AND AN EMPTY PROJECT BOTH ANSWER" {
    single := new List<string>()
    single.Add("only.nl")
    assert SroJoin(SroFiles(single)) == "only.nl"
    assert SystemsReportOrder.OrderedFiles(new List<string>()).Length == 0
}

test "THE FILE WALK ORDER DOES NOT DE-DUPLICATE" {
    // Two compilation units cannot share a key, so nothing here should be dropping rows: the walk
    // order is an ORDER and only an order. The call list below is the one that de-duplicates.
    ordered := SroFiles(SroList("b.nl", "a.nl", "b.nl"))
    assert SroJoin(ordered) == "a.nl,b.nl,b.nl"
}

// ---------------------------------------------------------------------------
// THE TRUSTED-SITE ORDER — `SystemsAnalyzer.Analyze:103`
// ---------------------------------------------------------------------------

test "THE TRUSTED-SITE ORDER IS FILE, THEN LINE, THEN COLUMN" {
    sites := new List<SystemsTrustedSite>()
    sites.Add(SroSite("d", "b.nl", 1, 1))
    sites.Add(SroSite("c", "a.nl", 9, 1))
    sites.Add(SroSite("b", "a.nl", 2, 8))
    sites.Add(SroSite("a", "a.nl", 2, 3))
    assert SroSiteNames(SystemsReportOrder.OrderedTrustedSites(sites)) == "a,b,c,d"
}

test "THE TRUSTED-SITE FILE ORDER IS CASE-INSENSITIVE" {
    sites := new List<SystemsTrustedSite>()
    sites.Add(SroSite("upper", "B.nl", 1, 1))
    sites.Add(SroSite("lower", "a.nl", 1, 1))
    assert SroSiteNames(SystemsReportOrder.OrderedTrustedSites(sites)) == "lower,upper"
}

test "A CASE-INSENSITIVE TIE ON THE FILE FALLS THROUGH TO LINE" {
    sites := new List<SystemsTrustedSite>()
    sites.Add(SroSite("later", "a.nl", 9, 1))
    sites.Add(SroSite("earlier", "A.nl", 2, 1))
    assert SroSiteNames(SystemsReportOrder.OrderedTrustedSites(sites)) == "earlier,later"
}

test "THE TRUSTED-SITE ORDER IS STABLE AT ONE POSITION" {
    sites := new List<SystemsTrustedSite>()
    sites.Add(SroSite("first", "a.nl", 3, 3))
    sites.Add(SroSite("second", "a.nl", 3, 3))
    sites.Add(SroSite("third", "a.nl", 3, 3))
    assert SroSiteNames(SystemsReportOrder.OrderedTrustedSites(sites)) == "first,second,third"
}

test "NO TRUSTED SITES ANSWERS AN EMPTY ARRAY" {
    assert SystemsReportOrder.OrderedTrustedSites(new List<SystemsTrustedSite>()).Length == 0
}

test "THE TRUSTED-SITE ORDER DOES NOT DE-DUPLICATE TWO REVIEWS OF ONE POSITION" {
    // A trusted site is a review obligation, not a fact about a name: two of them at one position
    // are two obligations and both must be shown.
    sites := new List<SystemsTrustedSite>()
    sites.Add(SroSite("same", "a.nl", 1, 1))
    sites.Add(SroSite("same", "a.nl", 1, 1))
    assert SystemsReportOrder.OrderedTrustedSites(sites).Length == 2
}

// ---------------------------------------------------------------------------
// THE PER-FUNCTION CALL LIST — `SystemsAnalyzer.AnalyzeFunction:244`
// ---------------------------------------------------------------------------

test "THE CALL LIST IS ORDERED CASE-SENSITIVELY, NOT CASE-INSENSITIVELY" {
    // The SAME three strings the file-walk block folds. Case-insensitive would answer
    // `alpha,Alpha2,Beta`; these are three distinct functions and N# uses case to carry
    // visibility, so the report must not fold them together.
    ordered := SystemsReportOrder.OrderedCalls(SroList("alpha", "Beta", "Alpha2"))
    assert SroJoin(ordered) == "Alpha2,Beta,alpha"
}

test "THE CALL LIST DE-DUPLICATES: A HOT LOOP CALLING ONE FUNCTION FIVE TIMES RECORDS IT ONCE" {
    calls := new List<string>()
    calls.Add("zeta")
    calls.Add("alpha")
    calls.Add("zeta")
    calls.Add("alpha")
    calls.Add("zeta")
    assert SroJoin(SystemsReportOrder.OrderedCalls(calls)) == "alpha,zeta"
}

test "THE DE-DUPLICATION IS CASE-SENSITIVE, SO `Alpha` AND `alpha` ARE TWO CALLS" {
    calls := new List<string>()
    calls.Add("Alpha")
    calls.Add("alpha")
    assert SroJoin(SystemsReportOrder.OrderedCalls(calls)) == "Alpha,alpha"
}

test "A DOTTED EXTERNAL CALL ORDERS BY ITS WHOLE NAME" {
    ordered := SystemsReportOrder.OrderedCalls(SroList("Console.WriteLine", "local", "Console.Write"))
    assert SroJoin(ordered) == "Console.Write,Console.WriteLine,local"
}

test "A SHORTER CALL NAME SORTS BEFORE A LONGER ONE IT IS A PREFIX OF" {
    calls := new List<string>()
    calls.Add("Read")
    calls.Add("ReadByte")
    calls.Add("Rea")
    assert SroJoin(SystemsReportOrder.OrderedCalls(calls)) == "Rea,Read,ReadByte"
}

test "A FUNCTION THAT CALLS NOTHING ANSWERS AN EMPTY ARRAY" {
    assert SystemsReportOrder.OrderedCalls(new List<string>()).Length == 0
}

test "THE CALL LIST IS INDEPENDENT OF THE ORDER THE WALK MET THE CALLS" {
    forward := SystemsReportOrder.OrderedCalls(SroList("a", "b", "c"))
    backward := SystemsReportOrder.OrderedCalls(SroList("c", "b", "a"))
    assert SroJoin(forward) == "a,b,c"
    assert SroJoin(backward) == "a,b,c"
}

// ---------------------------------------------------------------------------
// THE TWO ORDERS ARE NOT ONE ORDER — the cross pin
// ---------------------------------------------------------------------------

test "THE FILE ORDER AND THE CALL ORDER DISAGREE ON THE SAME THREE STRINGS, AND THAT IS THE RULE" {
    files := SystemsReportOrder.OrderedFiles(SroList("alpha", "Beta", "Alpha2"))
    calls := SystemsReportOrder.OrderedCalls(SroList("alpha", "Beta", "Alpha2"))
    assert SroJoin(files) == "alpha,Alpha2,Beta"
    assert SroJoin(calls) == "Alpha2,Beta,alpha"
}

// ---------------------------------------------------------------------------
// THE COMPARISON PRIMITIVES
// ---------------------------------------------------------------------------

test "THE TWO STRING COMPARISONS ANSWER SIGNS, AND ZERO ONLY ON EQUALITY" {
    assert SystemsReportOrder.CompareOrdinal("a", "b") == -1
    assert SystemsReportOrder.CompareOrdinal("b", "a") == 1
    assert SystemsReportOrder.CompareOrdinal("a", "a") == 0
    assert SystemsReportOrder.CompareOrdinal("A", "a") == -1
    assert SystemsReportOrder.CompareOrdinalIgnoreCase("A", "a") == 0
    assert SystemsReportOrder.CompareOrdinalIgnoreCase("a", "B") == -1
    assert SystemsReportOrder.CompareOrdinal("a", "B") == 1
}

test "AN EMPTY STRING SORTS BEFORE EVERY NON-EMPTY ONE IN BOTH COMPARISONS" {
    assert SystemsReportOrder.CompareOrdinal("", "a") == -1
    assert SystemsReportOrder.CompareOrdinalIgnoreCase("", "a") == -1
    assert SystemsReportOrder.CompareOrdinal("", "") == 0
    assert SystemsReportOrder.CompareOrdinalIgnoreCase("", "") == 0
}

test "THE INT COMPARISON ANSWERS SIGNS AND NOT DIFFERENCES" {
    assert SystemsReportOrder.CompareInt(1, 9) == -1
    assert SystemsReportOrder.CompareInt(9, 1) == 1
    assert SystemsReportOrder.CompareInt(4, 4) == 0
}

// ---------------------------------------------------------------------------
// THE FINDING ORDER STILL REACHES THE SINK'S DOOR
// ---------------------------------------------------------------------------

test "THE FINDING ORDER IS THE SAME OWNER, REACHED DIRECTLY" {
    // `SystemsFindingSink.Ordered()` routes here. Its own contracts pin the door; this pins that
    // the owner answers the same rule when it is asked without a sink.
    findings := new List<SystemsFinding>()
    findings.Add(SroFinding("d", "b.nl", 1, 1))
    findings.Add(SroFinding("c", "a.nl", 9, 1))
    findings.Add(SroFinding("b", "a.nl", 2, 8))
    findings.Add(SroFinding("a", "a.nl", 2, 3))
    ordered := SystemsReportOrder.OrderedFindings(findings)
    assert ordered.Length == 4
    assert ordered[0].Message == "a"
    assert ordered[1].Message == "b"
    assert ordered[2].Message == "c"
    assert ordered[3].Message == "d"
}

func SroFinding(message: string, filePath: string, line: int, column: int): SystemsFinding {
    path := new string[](1)
    path[0] = "Fn"
    return new SystemsFinding("NSYS010", "error", "allocation", message, filePath, line, column, 1, "Fn", "[hot]", "sourceInferred", null, path)
}
