namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence


// ONE FUNCTION'S PARAMETER FRAME, AND THE SCOPE ITS PARAMETERS LIVE IN.
//
// NL012 credits a read of a name to the parameter it LEXICALLY resolves to, which is not always the
// innermost function's: a local function or lambda that reads a captured parameter of an enclosing
// function is a genuine use of that parameter. The frame therefore carries the dictionary that holds
// this function's parameters, so a read can be matched against the scope it resolved to rather than
// against a name table alone. `Scope` is null until the parameters have actually been declared —
// a function with no body never opens one.
class LinterParameterFrame {
    Params: List<(string, int, int)>
    Usages: HashSet<string>
    Scope: Dictionary<string, (int, int, bool)>?

    constructor(declaredParams: List<(string, int, int)>, usages: HashSet<string>) {
        Params = declaredParams
        Usages = usages
        Scope = null
    }
}

// THE ENCLOSING FUNCTION'S STATE, HELD BY THE CALLER FOR THE LENGTH OF ONE NESTED FUNCTION WALK.
//
// The frame is handed BACK to the caller instead of being pushed onto a stack inside the state, and
// that is a lifetime decision measured from the C# it replaces, not a preference. `VisitFunction`
// saved these four values into LOCALS and restored them on the straight line, with NO `try`/`finally`
// — a throw inside the nested walk abandons them. A stack inside the owner would pop in `ExitFunction`
// and so would quietly make the idiom exception-safe, which it is not. A frame in the caller's own
// local is abandoned by a throw exactly as the C# locals were. This is the same model as
// `AmbientContextFrame`, and for the same measured reason.
//
// The PARAMETER-FRAME LIST is a different case and stays inside the owner: the C# pushed and popped
// `_paramFrames` itself, with no caller-held local, so an owned list reproduces it exactly.
class LinterFunctionFrame {
    WasInAsync: bool
    HadAwait: bool
    OuterParams: List<(string, int, int)>
    OuterParamUsages: HashSet<string>

    constructor(wasInAsync: bool, hadAwait: bool, outerParams: List<(string, int, int)>, outerParamUsages: HashSet<string>) {
        WasInAsync = wasInAsync
        HadAwait = hadAwait
        OuterParams = outerParams
        OuterParamUsages = outerParamUsages
    }
}

// ONE IMPORT AS NL010 NEEDS TO SEE IT: what it brought in, where it is written, and which of the two
// kinds it is. A namespace import resolves against the known-namespace table; a file import resolves
// against a file's exported symbols, and only that kind carries a path.
class LinterImportRecord {
    Namespace: string
    Line: int
    Column: int
    Length: int
    IsFile: bool
    FilePath: string?

    constructor(namespaceName: string, line: int, column: int, length: int, isFile: bool, filePath: string?) {
        Namespace = namespaceName
        Line = line
        Column = column
        Length = length
        IsFile = isFile
        FilePath = filePath
    }
}

// THE LINT WALK'S WHOLE STATE, AND EVERY RULE THAT READS IT WITHOUT WALKING.
//
// `LintVisitor` used to carry twenty-two private fields and mutate them in place from ten mutually
// recursive walker arms. That is what made the walkers immovable: any one arm lifted out of C# would
// have needed a callback back into the visitor to touch the state, and a callback is exactly what the
// ownership mandate forbids. This owner takes NINETEEN of those twenty-two fields, so an arm that
// moves later reaches its state through a method on an N# object instead.
//
// The three it does NOT take are the expression-recursion guard — the visiting set, the depth counter
// and its limit. They are touched by `VisitExpression` and by nothing else in the file, so they are
// that ARM's own state, not the walk's shared state, and they move when it does.
//
// WHAT IT OWNS, IN FOUR GROUPS:
//
//   1. THE LEXICAL SCOPES. One current frame plus a stack of enclosing frames, each mapping a name to
//      where it was declared and whether it has been read. `PushScope` saves the current frame and
//      starts an empty one; `PopScope` reports the frame's unused variables and restores the parent.
//   2. THE PARAMETER FRAMES. One frame per enclosing function, innermost last, each holding that
//      function's parameters, the names read from them, and the scope they live in.
//   3. THE FILE'S LEDGERS. Every import written, every identifier the code mentions, every member
//      name accessed, the imported namespaces and file symbols, and the stack of type-member name
//      scopes. NL002 and NL010 are answered entirely from these.
//   4. THE REPORTING SPINE. The configuration, the suppression set, the source text, the file path
//      and the diagnostic list. Every rule that reports goes through one door, `AddDiagnostic`, and
//      that door is PRIVATE: no caller outside this owner adds a diagnostic any more.
//
// THE SPAN FORK IN `AddDiagnostic` WAS A FORK THAT COULD NOT DECIDE ANYTHING. The C# asked whether
// the resolved span's column equalled the requested one and either kept the location or rewrote its
// column; both arms produce a location with the same line, the same file and the SPAN's column, so
// the fork is stated here as the single construction it always was.
class LinterWalkState {
    filePath: string?
    config: LinterConfig
    suppressions: LinterSuppressionSet
    sourceText: string?
    diagnostics: List<Diagnostic>

    declaredVariables: Dictionary<string, (int, int, bool)>
    usedVariables: HashSet<string>
    scopeStack: Stack<Dictionary<string, (int, int, bool)>>

    importedNamespaces: List<string>
    importedFileSymbols: HashSet<string>
    allImports: List<LinterImportRecord>
    allCodeIdentifiers: HashSet<string>
    allMemberAccessNames: HashSet<string>
    typeMemberNameScopes: Stack<HashSet<string>>

    hasAwaitInFunction: bool
    inAsyncFunction: bool
    currentFunctionParams: List<(string, int, int)>
    currentFunctionParamUsages: HashSet<string>
    paramFrames: List<LinterParameterFrame>

    Diagnostics: List<Diagnostic> => diagnostics

    constructor(filePath: string?, sourceText: string?, config: LinterConfig) {
        this.filePath = filePath
        this.sourceText = sourceText
        this.config = config
        suppressions = LinterSuppressionParser.BuildSuppressions(filePath, sourceText)
        diagnostics = new List<Diagnostic>()

        declaredVariables = new Dictionary<string, (int, int, bool)>()
        usedVariables = new HashSet<string>()
        scopeStack = new Stack<Dictionary<string, (int, int, bool)>>()

        importedNamespaces = new List<string>()
        importedFileSymbols = new HashSet<string>()
        allImports = new List<LinterImportRecord>()
        allCodeIdentifiers = new HashSet<string>()
        allMemberAccessNames = new HashSet<string>()
        typeMemberNameScopes = new Stack<HashSet<string>>()

        hasAwaitInFunction = false
        inAsyncFunction = false
        currentFunctionParams = new List<(string, int, int)>()
        currentFunctionParamUsages = new HashSet<string>()
        paramFrames = new List<LinterParameterFrame>()
    }

    // ---- the reporting spine -------------------------------------------------------------------

    // The one door every diagnostic goes through. A disabled rule and a suppressed line are silent,
    // and the reported span is whatever the span resolver makes of the source line — which is why the
    // column it returns wins over the one the rule asked for.
    func AddDiagnostic(code: string, message: string, line: int, column: int, severity: DiagnosticSeverity, suggestion: string?, length: int) {
        if !config.IsRuleEnabled(code) {
            return
        }

        if suppressions.IsSuppressed(line, code) {
            return
        }

        span := DiagnosticSpanResolver.Resolve(SourceLine(line), column, length)
        diagnostics.Add(new Diagnostic(code, message, new Location(line, span.Column, filePath), severity, suggestion, span.Length))
    }

    // Mechanical: a rule owner answers with a finding or with nothing, and a finding is reported
    // exactly as any other diagnostic. No rule decides anything here.
    func Report(finding: LinterRuleFinding?) {
        if finding == null {
            return
        }

        AddDiagnostic(finding.Code, finding.Message, finding.Line, finding.Column, finding.Severity, finding.Suggestion, 0)
    }

    // The text of a one-based source line, or the empty string when there is no source text, the line
    // is out of range, or the line number is not one-based at all.
    func SourceLine(oneBasedLine: int): string {
        // `?? ""` rather than a null guard: a nullable FIELD is not narrowed by a preceding test, and
        // the empty string then answers the same way a null one does — the length test below covers
        // both, exactly as `string.IsNullOrEmpty` did.
        text := sourceText ?? ""
        if text.Length == 0 || oneBasedLine <= 0 {
            return ""
        }

        return CodeIntelligenceTextUtilities.GetSourceLine(text, oneBasedLine) ?? ""
    }

    // Where a token actually starts on a line, falling back to the caller's column when the line does
    // not contain it. The search is ORDINAL: a token is bytes, not a culture-sensitive collation.
    func FindTokenColumn(oneBasedLine: int, token: string, fallbackColumn: int): int {
        if string.IsNullOrWhiteSpace(token) {
            return fallbackColumn
        }

        index := SourceLine(oneBasedLine).IndexOf(token, StringComparison.Ordinal)
        if index >= 0 {
            return index + 1
        }

        return fallbackColumn
    }

    // ---- the file's imports --------------------------------------------------------------------

    // Every import the file writes, recorded once before the walk starts. A namespace import's span is
    // resolved against its source line because the directive's own column points at the keyword rather
    // than at the namespace; a file import already carries its diagnostic span.
    func RegisterImports(unit: CompilationUnit) {
        for importDirective in unit.Imports {
            importedNamespaces.Add(importDirective.Namespace)
            span := LinterImportMetadata.ResolveNamespaceImportSpan(importDirective.Column, importDirective.Namespace, SourceLine(importDirective.Line))
            allImports.Add(new LinterImportRecord(importDirective.Namespace, importDirective.Line, span.Column, span.Length, false, null))
        }

        for statement in unit.FileImports {
            fileImport := statement as FileImport
            if fileImport != null {
                importedSymbol := LinterImportMetadata.ExtractFileImportSymbolName(fileImport.Path, fileImport.Alias)
                if importedSymbol != null && !string.IsNullOrWhiteSpace(importedSymbol) {
                    importedFileSymbols.Add(importedSymbol)
                    allImports.Add(new LinterImportRecord(importedSymbol, fileImport.Line, fileImport.DiagnosticColumn, fileImport.DiagnosticLength, true, fileImport.Path))
                }
            }
        }
    }

    // NL010, once per file after the whole walk. A file import resolves to a file's exported symbols;
    // a namespace import resolves to the known-namespace table. Both arms are N#.
    func CheckUnusedImports() {
        if !config.RuleSeverities.ContainsKey("NL010") {
            return
        }

        for imported in allImports {
            used := false
            label := "import " + imported.Namespace
            if imported.IsFile {
                used = LinterFileImportUsage.IsUsed(imported.Namespace, imported.FilePath, filePath, allCodeIdentifiers)
                label = "import \"" + (imported.FilePath ?? imported.Namespace) + "\""
            } else {
                used = LinterNamespaceImportUsage.IsUsed(imported.Namespace, allCodeIdentifiers, allMemberAccessNames)
            }

            if !used {
                AddDiagnostic("NL010", "The import '" + label + "' is not used by any code in this file", imported.Line, imported.Column, config.GetSeverity("NL010"), "Remove '" + label + "' to keep your imports clean", imported.Length)
            }
        }
    }

    // NL002 for a bare identifier. The whole decision — which namespace the name needs, and whether
    // anything already supplies it — belongs to `LinterMissingImport`; what is here is the report.
    func CheckMissingImport(ident: IdentifierExpression) {
        requiredNamespace := LinterMissingImport.MissingNamespaceForIdentifier(ident.Name, typeMemberNameScopes, importedFileSymbols, importedNamespaces)
        if requiredNamespace == null {
            return
        }

        AddDiagnostic("NL002", LinterMissingImport.Message(ident.Name), ident.Line, ident.Column, config.GetSeverity("NL002"), LinterMissingImport.Suggestion(requiredNamespace), 0)
    }

    // NL002 for a written type reference. Only the BASE name is asked about: a generic argument or an
    // array element is reached by the walk in its own right.
    //
    // THE SQUIGGLE GOES ON THE NAME THE MESSAGE NAMES. `LinterTypeReferenceName.BaseNameSpan` answers
    // where the base name is written, and the diagnostic is reported there with that exact length —
    // `List` in `new List<int>()`, not the `new` keyword the caller's position points at, and not
    // `List<int>` either. The caller's `line`/`column` are the FALLBACK for a reference the parser
    // never stamped (a hand-built tree), which is the only case that still reaches
    // `DiagnosticSpanResolver`'s token inference.
    func CheckMissingImportForType(typeReference: TypeReference, line: int, column: int) {
        typeName := LinterTypeReferenceName.Base(typeReference)
        if typeName == null {
            return
        }

        requiredNamespace := LinterMissingImport.MissingNamespaceForTypeName(typeName, importedFileSymbols, importedNamespaces)
        if requiredNamespace == null {
            return
        }

        nameSpan := LinterTypeReferenceName.BaseNameSpan(typeReference)
        reportLine := line
        reportColumn := column
        reportLength := 0
        if nameSpan.IsValid {
            reportLine = nameSpan.StartLine
            reportColumn = nameSpan.StartColumn
            reportLength = nameSpan.Length
        }

        AddDiagnostic("NL002", LinterMissingImport.Message(typeName), reportLine, reportColumn, config.GetSeverity("NL002"), LinterMissingImport.Suggestion(requiredNamespace), reportLength)
    }

    // ---- the file's identifier ledgers ----------------------------------------------------------

    // NL010: every type name a written type reference mentions counts as a use of whatever import
    // supplies it.
    func TrackTypeReference(typeReference: TypeReference?) {
        LinterTypeReferenceName.CollectMentionedNames(typeReference, allCodeIdentifiers)
    }

    func NoteCodeIdentifier(name: string) {
        allCodeIdentifiers.Add(name)
    }

    func NoteMemberAccessName(name: string) {
        allMemberAccessNames.Add(name)
    }

    // The names a type declares, as a scope: a bare name that is a member of the enclosing type is not
    // a missing import. A positional parameter counts as a member name AND its declared type counts as
    // a real import usage.
    func PushTypeMemberScope(members: List<Declaration>, primaryConstructorParameters: List<Parameter>?) {
        names := new HashSet<string>(StringComparer.Ordinal)
        for member in members {
            field := member as FieldDeclaration
            if field != null {
                names.Add(field.Name)
            }

            property := member as PropertyDeclaration
            if property != null {
                names.Add(property.Name)
            }

            function := member as FunctionDeclaration
            if function != null {
                names.Add(function.Name)
            }
        }

        if primaryConstructorParameters != null {
            for parameter in primaryConstructorParameters {
                names.Add(parameter.Name)
                TrackTypeReference(parameter.Type)
            }
        }

        typeMemberNameScopes.Push(names)
    }

    func PopTypeMemberScope() {
        typeMemberNameScopes.Pop()
    }

    // ---- the lexical scopes ---------------------------------------------------------------------

    // Opens a scope: the current frame becomes the innermost ENCLOSING one and a fresh frame takes its
    // place.
    func PushScope() {
        scopeStack.Push(declaredVariables)
        declaredVariables = new Dictionary<string, (int, int, bool)>()
    }

    // Closes a scope: the frame's unused variables are reported, then the parent frame is restored. A
    // pop with nothing to restore does neither — including the report, which is why an unbalanced pop
    // is silent rather than a duplicate.
    func PopScope() {
        if scopeStack.Count > 0 {
            CheckUnusedVariables()
            declaredVariables = scopeStack.Pop()
        }
    }

    // NL001 over the frame that is closing. A name read anywhere in the file silences it, not only a
    // read that resolved to THIS binding — the file-wide set is deliberately coarser than the scope.
    func CheckUnusedVariables() {
        for kvp in declaredVariables {
            entry := kvp.Value
            if LinterBindingUsageCore.ShouldReportUnusedVariable(kvp.Key, entry.Item3, usedVariables.Contains(kvp.Key)) {
                AddDiagnostic("NL001", LinterBindingUsageCore.UnusedVariableMessage(kvp.Key), entry.Item1, entry.Item2, config.GetSeverity("NL001"), LinterBindingUsageCore.UnusedVariableSuggestion(kvp.Key), kvp.Key.Length)
            }
        }
    }

    // Binds a name in the innermost scope, unread. NL020 asks first, because shadowing is a question
    // about the scopes ABOVE this one and the answer changes the moment the name is written here.
    func DeclareVariable(name: string, line: int, column: int) {
        Report(LinterShadowedVariable.ShadowedVariable(name, line, column, scopeStack, config))
        declaredVariables[name] = (line, column, false)
    }

    // A read of `name`.
    //
    // `creditEnclosingParameter` separates a genuine READ from a BINDING site. A genuine read counts as
    // a use of the parameter it lexically resolves to — including a parameter captured by a nested
    // local function or lambda, which is why the resolved SCOPE is matched against the parameter
    // frames rather than the name alone: a shadowing local binds the name in a nearer scope and must
    // not credit the enclosing parameter. A binding site (a parameter, loop variable, catch variable
    // or lambda parameter being introduced) consults only the CURRENT function's parameter table, so
    // re-declaring a name never marks an enclosing parameter as read.
    //
    // The scope walk that marks the variable itself is separate and unconditional: the innermost frame
    // that binds the name has its entry marked used, and the file-wide set records the name either way.
    func MarkVariableUsed(name: string, creditEnclosingParameter: bool) {
        if creditEnclosingParameter {
            CreditResolvedParameter(name)
        } else if DeclaresCurrentFunctionParameter(name) {
            currentFunctionParamUsages.Add(name)
        }

        if declaredVariables.ContainsKey(name) {
            existing := declaredVariables[name]
            declaredVariables[name] = (existing.Item1, existing.Item2, true)
        } else {
            for scope in scopeStack {
                if scope.ContainsKey(name) {
                    outer := scope[name]
                    scope[name] = (outer.Item1, outer.Item2, true)
                    break
                }
            }
        }

        usedVariables.Add(name)
    }

    // The innermost scope that binds the name, or nothing when no open scope does.
    func ResolveScope(name: string): Dictionary<string, (int, int, bool)>? {
        if declaredVariables.ContainsKey(name) {
            return declaredVariables
        }

        for scope in scopeStack {
            if scope.ContainsKey(name) {
                return scope
            }
        }

        return null
    }

    // Credits the read to the parameter frame whose OWN parameter scope is the scope the name resolved
    // to. Innermost frame first, and the first match ends the walk.
    func CreditResolvedParameter(name: string) {
        resolvedScope := ResolveScope(name)
        if resolvedScope == null {
            return
        }

        index := paramFrames.Count - 1
        while index >= 0 {
            frame := paramFrames[index]
            if Object.ReferenceEquals(frame.Scope, resolvedScope) && FrameDeclaresParameter(frame, name) {
                frame.Usages.Add(name)
                return
            }

            index = index - 1
        }
    }

    static func FrameDeclaresParameter(frame: LinterParameterFrame, name: string): bool {
        for parameter in frame.Params {
            if parameter.Item1 == name {
                return true
            }
        }

        return false
    }

    func DeclaresCurrentFunctionParameter(name: string): bool {
        for parameter in currentFunctionParams {
            if parameter.Item1 == name {
                return true
            }
        }

        return false
    }

    // ---- one function's frame -------------------------------------------------------------------

    // Opens a function: the enclosing function's state is handed back for the caller to hold, a fresh
    // parameter frame is pushed, and the await flag starts clear so NL004 asks about THIS function.
    func EnterFunction(isAsync: bool): LinterFunctionFrame {
        frame := new LinterFunctionFrame(inAsyncFunction, hasAwaitInFunction, currentFunctionParams, currentFunctionParamUsages)
        inAsyncFunction = isAsync
        hasAwaitInFunction = false

        // An async function implicitly uses `Task` from `System.Threading.Tasks`, so its import is used.
        if isAsync {
            allCodeIdentifiers.Add("Task")
        }

        currentFunctionParams = new List<(string, int, int)>()
        currentFunctionParamUsages = new HashSet<string>()
        paramFrames.Add(new LinterParameterFrame(currentFunctionParams, currentFunctionParamUsages))
        return frame
    }

    // Closes a function, restoring the caller's frame. Straight-line, with no `finally`: a throw inside
    // the nested walk abandons the caller's local exactly as the C# it replaces did.
    func ExitFunction(frame: LinterFunctionFrame) {
        inAsyncFunction = frame.WasInAsync
        hasAwaitInFunction = frame.HadAwait
        paramFrames.RemoveAt(paramFrames.Count - 1)
        currentFunctionParams = frame.OuterParams
        currentFunctionParamUsages = frame.OuterParamUsages
    }

    func AddParameter(name: string, line: int, column: int) {
        currentFunctionParams.Add((name, line, column))
    }

    // Records the scope the current function's parameters were declared into, so a read can be
    // attributed to the parameter it lexically resolves to.
    func RecordParameterScope() {
        innermost := paramFrames[paramFrames.Count - 1]
        innermost.Scope = declaredVariables
    }

    func NoteAwait() {
        hasAwaitInFunction = true
    }

    // NL012, over the parameters of the function that is closing. Silent unless the rule's code is
    // present in the configuration's severity table.
    func CheckUnusedParameters(functionName: string) {
        if !config.RuleSeverities.ContainsKey("NL012") {
            return
        }

        for parameter in currentFunctionParams {
            name := parameter.Item1
            if LinterBindingUsageCore.ShouldReportUnusedParameter(name, currentFunctionParamUsages.Contains(name)) {
                AddDiagnostic("NL012", LinterBindingUsageCore.UnusedParameterMessage(name, functionName), parameter.Item2, parameter.Item3, config.GetSeverity("NL012"), LinterBindingUsageCore.UnusedParameterSuggestion(name), 0)
            }
        }
    }

    // NL004. A function declared `async` that never awaits will run synchronously.
    //
    // THE C# CARRIED A GUARD THAT COULD NOT DECIDE ANYTHING: a local was set to `true` and then tested,
    // with nothing between the two. The rule is stated here as the three conditions that actually
    // select it — declared async, no await reached, and a BLOCK body, because an expression-bodied
    // async function is deliberately not reported.
    func CheckAsyncWithoutAwait(declaration: FunctionDeclaration) {
        if !inAsyncFunction || hasAwaitInFunction || declaration.Body == null {
            return
        }

        AddDiagnostic("NL004", "Function '" + declaration.Name + "' is marked 'async' but never uses 'await' — it will run synchronously", declaration.Line, FindTokenColumn(declaration.Line, declaration.Name, declaration.Column), config.GetSeverity("NL004"), "Either add an 'await' expression inside '" + declaration.Name + "', or remove the 'async' modifier if this function doesn't need to be asynchronous", 0)
    }

    // ---- the rules that read one node and the configuration --------------------------------------

    func CheckUnnecessaryNullCheck(condition: Expression) {
        Report(LinterNullCheckPolicy.UnnecessaryNullCheck(condition, config))
    }

    func CheckRedundantNullCheck(condition: Expression) {
        Report(LinterNullCheckPolicy.RedundantNullCheck(condition, config))
    }

    // NL006. Reported once per block, at the first statement the walk cannot reach.
    func ReportUnreachableCode(line: int, column: int) {
        AddDiagnostic("NL006", "This code will never run — there's a 'return' or 'throw' above it", line, column, config.GetSeverity("NL006"), "Remove the unreachable code, or move it before the return/throw if it should execute", 0)
    }

    // NL011. The reported span is the OWNER of the block — the `catch` keyword and its clause — rather
    // than the brace, which is why the block's own line is read back out of the source.
    func ReportEmptyCatchBlock(blockLine: int, blockColumn: int) {
        span := LinterBlockOwnerSpanResolver.Resolve(blockLine, blockColumn, SourceLine(blockLine))
        AddDiagnostic("NL011", "This catch block is empty — exceptions will be silently swallowed", span.Line, span.Column, config.GetSeverity("NL011"), "Log the error, handle it, or add a comment explaining why it's safe to ignore", span.Length)
    }

    // Every identifier an interpolated string's holes read is a genuine use of that variable.
    func HandleStringInterpolation(value: string) {
        for name in LinterInterpolationScan.UsedIdentifiers(value) {
            MarkVariableUsed(name, true)
        }
    }
}
