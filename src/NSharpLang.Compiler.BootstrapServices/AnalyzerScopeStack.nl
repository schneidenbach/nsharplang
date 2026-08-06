namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// The analyzer's LEXICAL SCOPE STACK: the open scopes of the file being analyzed, innermost last, and
// every question the semantic phase answers by walking them.
//
// `Scope` itself was already N#. What lived in the shell was the STACK — a `Stack<Scope>` field and
// the 51 sites that pushed, popped, peeked and walked it — so this owner is the container plus its
// WALK SEMANTICS, not the element type.
//
// THE LIFO DISCIPLINE IS SEMANTIC, NOT BOOKKEEPING. Three rules are load-bearing and are the reason
// the whole stack has to move as one piece:
//
//   1. EVERY name walk runs INNERMOST FIRST and the first scope that has the name answers. A scope
//      that has the name under a different meaning still ends the walk — `IsCurrentTypeMemberReference`
//      and `IsErrorTupleResultAvailable` both answer from the scope they STOPPED at, so "keep looking"
//      versus "stop here" is a decision, not an optimisation.
//   2. TWO walks deliberately SKIP the innermost scope (`FindEnclosingNullableSymbol`,
//      `ShadowsEnclosingValueBinding`), because their question is about an ENCLOSING binding. In the
//      shell that read as `Skip(1)` and as a `ReferenceEquals`-against-`Peek()` guard respectively;
//      both are the same thing, because `Peek()` is by definition the first element a top-to-bottom
//      walk visits.
//   3. THE SCOPE STACK AND THE SEMANTIC-SCOPE-ID STACK MOVE IN LOCKSTEP. Pushing a scope opens a
//      semantic scope whose parent is the id currently on top; popping closes it. The id stack is
//      popped only when it is non-empty while the scope stack is popped unconditionally, so the two
//      can legally be at different depths — that asymmetry is reproduced exactly.
//
// The stack is SILENT. It reports no diagnostic and records nothing into the semantic model, and 23
// of the 35 shell members that touched it were silent too. The four that were not are here anyway,
// because what they record is reachable WITHOUT a callback: `BindingMap` and `SemanticModel` are
// themselves N#, so a walk that records a binding, or a push that opens a semantic scope, is handed
// the map or the model as an ARGUMENT and stays whole. Both are replaced per `Analyze` call, which is
// why they are arguments rather than fields.
//
// Declaration POLICY — `DeclareSymbol`, `DeclareType`, `CheckShadowedDeclaration`'s diagnostic, the
// file-import walk — stays in the shell for now: it reports. What moved out of it is the DECISION
// (`ShadowsEnclosingValueBinding`) and the scope ACCESS (`Peek`, `GlobalScope`).
//
// `Peek` and `Pop` on an empty stack, and `GlobalScope` on an empty stack, throw exactly what
// `Stack<Scope>.Peek()`, `Stack<Scope>.Pop()` and `Enumerable.Last()` threw. No production path
// reaches them, but a silent change from one exception to another is still a behaviour change.
class AnalyzerScopeStack {
    scopes: List<Scope>
    semanticScopeIds: List<int>

    // THE ANALYSIS CURSOR: the line of the last declaration or statement the walk reached. It exists
    // for exactly one reason — a closing scope's recorded END position is that line — so it belongs
    // with the stack that closes scopes rather than with the shell that walks. It is written from two
    // places, the declaration loop and the statement dispatch, and read from one, `Pop`.
    currentLine: int

    // The number of open scopes, exactly as `Stack<Scope>.Count`.
    Count: int => scopes.Count

    constructor() {
        scopes = new List<Scope>()
        semanticScopeIds = new List<int>()
        currentLine = 0
    }

    // ---- the stack itself ---------------------------------------------------------------------

    // Resets BOTH stacks AND the cursor: an analysis run starts with no lexical scope, no semantic
    // scope and no line reached.
    func Clear() {
        scopes.Clear()
        semanticScopeIds.Clear()
        currentLine = 0
    }

    // The walk reached this line. Every declaration and every statement announces itself, so a scope
    // that closes here ends where the last thing inside it was written.
    func NoteLine(line: int) {
        currentLine = line
    }

    // The innermost open scope.
    func Peek(): Scope {
        if scopes.Count == 0 {
            throw new InvalidOperationException("Stack empty.")
        }

        return scopes[scopes.Count - 1]
    }

    // The outermost open scope — the global scope, at the bottom of the stack.
    func GlobalScope(): Scope {
        if scopes.Count == 0 {
            throw new InvalidOperationException("Sequence contains no elements")
        }

        return scopes[0]
    }

    // Opens a lexical scope AND its semantic scope, parented to whatever semantic scope is currently
    // innermost (-1 when there is none).
    func Push(model: SemanticModel, scope: Scope, startLine: int, startColumn: int) {
        scopes.Add(scope)

        parentId := -1
        if semanticScopeIds.Count > 0 {
            parentId = semanticScopeIds[semanticScopeIds.Count - 1]
        }

        semanticScopeIds.Add(model.OpenScope(parentId, startLine, startColumn))
    }

    // Closes the innermost lexical scope, and the innermost semantic scope if there is one. The
    // semantic scope ends at the CURSOR — the last line the walk reached — and its end column is the
    // maximum int: a closing scope runs to the end of its line.
    func Pop(model: SemanticModel) {
        if scopes.Count == 0 {
            throw new InvalidOperationException("Stack empty.")
        }

        scopes.RemoveAt(scopes.Count - 1)

        if semanticScopeIds.Count > 0 {
            scopeId := semanticScopeIds[semanticScopeIds.Count - 1]
            semanticScopeIds.RemoveAt(semanticScopeIds.Count - 1)
            model.CloseScope(scopeId, currentLine, 2147483647)
        }
    }

    // A VARIABLE'S POSITION-AWARE RECORD. It goes against the innermost SEMANTIC scope when there is
    // one and against the model's flat table when there is not, and the choice is this stack's to
    // make: the id stack is what knows whether a semantic scope is open, and it is legally at a
    // different depth from the lexical stack. Every declaration in the language that binds a name to
    // a value — a parameter, a local, a loop variable, a pattern binding, a `value` in an accessor —
    // reaches the semantic model through this one door, so the two shapes cannot drift apart.
    func RecordVariable(model: SemanticModel, name: string, typeInfo: TypeInfo) {
        if HasSemanticScope() {
            model.RecordScopedVariable(CurrentSemanticScopeId(), name, typeInfo)
            return
        }

        model.RecordVariable(name, typeInfo)
    }

    // A FUNCTION'S POSITION-AWARE RECORD, and the same decision over the other table. It is here
    // rather than left behind because the two are one rule about one id stack: a shell that kept
    // half of it could drift into recording a local function against a scope its locals do not
    // share.
    func RecordFunction(model: SemanticModel, name: string, typeInfo: TypeInfo) {
        if HasSemanticScope() {
            model.RecordScopedFunction(CurrentSemanticScopeId(), name, typeInfo)
            return
        }

        model.RecordFunction(name, typeInfo)
    }

    func HasSemanticScope(): bool {
        return semanticScopeIds.Count > 0
    }

    func CurrentSemanticScopeId(): int {
        if semanticScopeIds.Count == 0 {
            return -1
        }

        return semanticScopeIds[semanticScopeIds.Count - 1]
    }

    // ---- name walks --------------------------------------------------------------------------

    // The innermost scope that binds `name` as a TYPE answers.
    func LookupType(name: string): TypeInfo? {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            candidate := new TypeInfo()
            if scope.Types.TryGetValue(name, out candidate) {
                return candidate
            }

            index = index - 1
        }

        return null
    }

    // The innermost scope that binds `name` as a SYMBOL answers.
    func LookupSymbol(name: string): TypeInfo? {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            candidate := new TypeInfo()
            if scope.Symbols.TryGetValue(name, out candidate) {
                return candidate
            }

            index = index - 1
        }

        return null
    }

    // The innermost scope ONLY — no walk. Used where a declaration asks "is this name already mine?"
    // rather than "is it visible?".
    func CurrentScopeSymbol(name: string): TypeInfo? {
        current := Peek()
        candidate := new TypeInfo()
        if current.Symbols.TryGetValue(name, out candidate) {
            return candidate
        }

        return null
    }

    // Records a binding from a type-reference position to the declaration of the innermost scope that
    // binds the name. The first scope holding the name ends the walk whether or not it knows where the
    // declaration is, so an unlocated binding is silence rather than a fall-through to an outer scope.
    func RecordTypeBinding(bindings: BindingMap, filePath: string?, name: string, line: int, column: int) {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            if scope.Types.ContainsKey(name) {
                RecordDeclarationBinding(bindings, filePath, scope, name, line, column)
                return
            }

            index = index - 1
        }
    }

    // Symbols first, then types: an identifier in scope means the VALUE, and only then the type of
    // that name. Both walks record the declaration binding they land on.
    func ResolveBindingTarget(bindings: BindingMap, filePath: string?, name: string, line: int, column: int): TypeInfo? {
        symbolIndex := scopes.Count - 1
        while symbolIndex >= 0 {
            symbolScope := scopes[symbolIndex]
            symbolCandidate := new TypeInfo()
            if symbolScope.Symbols.TryGetValue(name, out symbolCandidate) {
                RecordDeclarationBinding(bindings, filePath, symbolScope, name, line, column)
                return symbolCandidate
            }

            symbolIndex = symbolIndex - 1
        }

        typeIndex := scopes.Count - 1
        while typeIndex >= 0 {
            typeScope := scopes[typeIndex]
            typeCandidate := new TypeInfo()
            if typeScope.Types.TryGetValue(name, out typeCandidate) {
                RecordDeclarationBinding(bindings, filePath, typeScope, name, line, column)
                return typeCandidate
            }

            typeIndex = typeIndex - 1
        }

        return null
    }

    func RecordDeclarationBinding(bindings: BindingMap, filePath: string?, scope: Scope, name: string, line: int, column: int) {
        declaration := scope.GetDeclarationLocation(name)
        if declaration != null {
            bindings.RecordBinding(filePath, line, column, name.Length, declaration)
        }
    }

    // The innermost scope that binds `this` carries the type whose members are in scope.
    func CurrentTypeScope(): TypeInfo? {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            candidate := new TypeInfo()
            if scope.Symbols.TryGetValue("this", out candidate) {
                return candidate
            }

            index = index - 1
        }

        return null
    }

    // Whether a bare name reads as a member of the current type rather than as a local. The walk stops
    // at the first scope that binds the name — answering from THAT scope's kind — and also at the first
    // type-level scope, because a name not found among the locals of an instance context is a member
    // reference by elimination.
    func IsCurrentTypeMemberReference(name: string): bool {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            if scope.Symbols.ContainsKey(name) {
                return !IsLocalScopeKind(scope.Kind)
            }

            if !IsLocalScopeKind(scope.Kind) {
                return CurrentTypeScope() != null
            }

            index = index - 1
        }

        return CurrentTypeScope() != null
    }

    // ---- declaration writes into the innermost scope ------------------------------------------

    // A generic type parameter is visible BOTH as a type and as an identifier, and it must be the SAME
    // instance in both namespaces.
    func DeclareTypeParameter(name: string) {
        current := Peek()
        typeParameter := new SimpleTypeInfo(name)
        current.Types[name] = typeParameter
        current.Symbols[name] = typeParameter
    }

    // A nested type of the enclosing declaration. First declaration wins: an explicit declaration of
    // the same simple name in this scope is not overwritten.
    func DeclareNestedTypeIfAbsent(name: string, nestedType: TypeInfo) {
        current := Peek()
        if !current.Types.ContainsKey(name) {
            current.Types[name] = nestedType
        }
    }

    // ---- flow-sensitive null facts ------------------------------------------------------------

    // Whether ANY open scope has recorded a null fact for a path. This is asked separately from the
    // fact itself because a path with no fact is NOT the same as a path recorded as
    // `NullState.Unknown`: the caller falls back to the DECLARED nullability in the first case and
    // must not in the second. A nullable enum return would say both in one call, but `NullState?` is
    // off the columnar surface, so presence and value are two walks.
    func HasNullState(path: string): bool {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            if scope.NullStates.ContainsKey(path) {
                return true
            }

            index = index - 1
        }

        return false
    }

    // The innermost recorded null fact for a path. `NullState.Unknown` when no scope has one — ask
    // `HasNullState` to tell that apart from a recorded unknown.
    func NullStateOrUnknown(path: string): NullState {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            found := NullState.Unknown
            if scope.NullStates.TryGetValue(path, out found) {
                return found
            }

            index = index - 1
        }

        return NullState.Unknown
    }

    func SetNullStateInCurrentScope(path: string, state: NullState) {
        if scopes.Count == 0 || string.IsNullOrWhiteSpace(path) {
            return
        }

        current := Peek()
        current.NullStates[path] = state
    }

    // An assignment invalidates the null facts for the assigned path AND for every member path under
    // it, in EVERY open scope — an outer scope's stale fact about `x.y` would otherwise outlive the
    // write to `x`.
    func InvalidateNullFactsForAssignment(path: string) {
        memberPrefix := path + "."
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            removals := new List<string>()
            for entry in scope.NullStates {
                key := entry.Key
                if key == path || key.StartsWith(memberPrefix, StringComparison.Ordinal) {
                    removals.Add(key)
                }
            }

            removalIndex := 0
            while removalIndex < removals.Count {
                scope.NullStates.Remove(removals[removalIndex])
                removalIndex = removalIndex + 1
            }

            index = index - 1
        }
    }

    // The nullable type an identifier was DECLARED with, looked up in the ENCLOSING scopes only: the
    // innermost scope holds the narrowed type, and the question here is what was narrowed. A scope
    // that binds the name to something that is not nullable does not stop the walk.
    func FindEnclosingNullableSymbol(name: string): NullableTypeInfo? {
        index := scopes.Count - 2
        while index >= 0 {
            scope := scopes[index]
            candidate := new TypeInfo()
            if scope.Symbols.TryGetValue(name, out candidate) {
                nullable := candidate as NullableTypeInfo
                if nullable != null {
                    return nullable
                }
            }

            index = index - 1
        }

        return null
    }

    // ---- error-tuple result guards ------------------------------------------------------------

    func RegisterErrorTupleResult(resultName: string, errorName: string, line: int, column: int) {
        if scopes.Count == 0 || string.IsNullOrWhiteSpace(resultName) || resultName == "_" {
            return
        }

        current := Peek()
        current.ErrorTupleResults[resultName] = new ErrorTupleResultGuard(resultName, errorName, line, column)
    }

    // Proving an error name null makes every result guarded by that error available. The walk collects
    // from the enclosing scopes but always marks availability in the INNERMOST scope, so the fact dies
    // with the branch that established it; it stops at the first scope that binds the error name,
    // because past that point the name means something else.
    func MarkErrorTupleResultsAvailableForError(errorName: string) {
        if scopes.Count == 0 || string.IsNullOrWhiteSpace(errorName) || errorName.Contains(".") {
            return
        }

        current := Peek()
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            for entry in scope.ErrorTupleResults {
                guard := entry.Value
                if guard.ErrorName == errorName {
                    current.AvailableErrorTupleResults.Add(guard.ResultName)
                }
            }

            if scope.Symbols.ContainsKey(errorName) {
                break
            }

            index = index - 1
        }
    }

    // Assigning a guarded result over the top makes it available: the new value is not the guarded one.
    func MarkErrorTupleResultAvailableAfterAssignment(target: Expression) {
        if scopes.Count == 0 {
            return
        }

        identifier := target as IdentifierExpression
        if identifier == null {
            return
        }

        if FindErrorTupleResultGuard(identifier.Name) != null {
            current := Peek()
            current.AvailableErrorTupleResults.Add(identifier.Name)
        }
    }

    func FindErrorTupleResultGuard(resultName: string): ErrorTupleResultGuard? {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            candidate := new ErrorTupleResultGuard("", "", 0, 0)
            if scope.ErrorTupleResults.TryGetValue(resultName, out candidate) {
                return candidate
            }

            if scope.Symbols.ContainsKey(resultName) {
                break
            }

            index = index - 1
        }

        return null
    }

    // Availability is decided by whichever fact the walk meets FIRST: an availability mark says yes, a
    // guard with no mark says no, and a plain symbol binding of the same name says yes because the name
    // is no longer the guarded result. A name no scope knows about is available — it is not a guarded
    // result at all.
    func IsErrorTupleResultAvailable(resultName: string): bool {
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            if scope.AvailableErrorTupleResults.Contains(resultName) {
                return true
            }

            if scope.ErrorTupleResults.ContainsKey(resultName) {
                return false
            }

            if scope.Symbols.ContainsKey(resultName) {
                return true
            }

            index = index - 1
        }

        return true
    }

    // ---- shadowing -----------------------------------------------------------------------------

    // Whether a local or parameter declaration in the innermost scope shadows a local or parameter of
    // an ENCLOSING function/block scope. The walk stops dead at the first type-level or global scope:
    // a member or a global of the same name is not shadowing. Underscore-prefixed names opt out.
    func ShadowsEnclosingValueBinding(name: string, declaredType: TypeInfo): bool {
        if scopes.Count == 0 {
            return false
        }

        if name == "_" || name.StartsWith("_", StringComparison.Ordinal) {
            return false
        }

        current := Peek()
        if !IsLocalScopeKind(current.Kind) {
            return false
        }

        if !AnalyzerBindingFacts.IsValueBinding(name, declaredType, current.Types.ContainsKey(name)) {
            return false
        }

        index := scopes.Count - 2
        while index >= 0 {
            scope := scopes[index]
            if !IsLocalScopeKind(scope.Kind) {
                return false
            }

            outerType := new TypeInfo()
            if scope.Symbols.TryGetValue(name, out outerType) {
                if AnalyzerBindingFacts.IsValueBinding(name, outerType, scope.Types.ContainsKey(name)) {
                    return true
                }
            }

            index = index - 1
        }

        return false
    }

    // ---- suggestion inputs ---------------------------------------------------------------------

    // Every type name in scope, innermost first. The order is the suggestion policy's tie-breaker, so
    // it is behaviour.
    func AllTypeNamesInScope(): List<string> {
        names := new List<string>()
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            for entry in scope.Types {
                names.Add(entry.Key)
            }

            index = index - 1
        }

        return names
    }

    func SuggestSimilarVariableNames(typo: string): List<string> {
        candidates := new List<string>()
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            for entry in scope.Symbols {
                candidates.Add(entry.Key)
            }

            index = index - 1
        }

        suggester := new SmartSuggester(candidates)
        return suggester.SuggestSimilarNames(typo, 3)
    }

    // Callable names only, plus the compilation's extension methods, deduplicated keeping the FIRST
    // spelling. Extension methods are not scope state, so they arrive as an argument.
    func SuggestSimilarCallableNames(typo: string, extensionMethodNames: List<string>): List<string> {
        candidates := new List<string>()
        index := scopes.Count - 1
        while index >= 0 {
            scope := scopes[index]
            for entry in scope.Symbols {
                if AnalyzerCallableReferenceFacts.IsCallableReferenceType(entry.Value) {
                    candidates.Add(entry.Key)
                }
            }

            index = index - 1
        }

        extensionIndex := 0
        while extensionIndex < extensionMethodNames.Count {
            candidates.Add(extensionMethodNames[extensionIndex])
            extensionIndex = extensionIndex + 1
        }

        distinct := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            if seen.Add(candidate) {
                distinct.Add(candidate)
            }

            candidateIndex = candidateIndex + 1
        }

        suggester := new SmartSuggester(distinct)
        return suggester.SuggestSimilarNames(typo, 3)
    }

    static func IsLocalScopeKind(kind: ScopeKind): bool {
        return kind == ScopeKind.Function || kind == ScopeKind.Block
    }
}
