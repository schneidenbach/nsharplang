import System
import System.Text

// Static columnar parser kernels formerly emitted through the Dogfood assembly.
// ---- LexerTokenKindScanner.nl ----
class LexerTokenKindTable {
    Kinds: int[]
    constructor(kinds: int[]) {
        Kinds = kinds
    }
}

class LexerTokenIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class LexerTokenMetadataTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Lines: int[]
    Columns: int[]
    constructor(kinds: int[], starts: int[], valueLengths: int[], lines: int[], columns: int[]) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Lines = lines
        Columns = columns
    }
}

class LexerCompactTokenMetadataTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    constructor(kinds: int[], starts: int[], valueLengths: int[]) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
    }
}

class LexerIndentStackTable {
    Indents: int[]
    constructor(indents: int[]) {
        Indents = indents
    }
}






// Insert the virtual indentation braces that the production lexer's InsertIndentationBraces
// post-pass produces, but write only the parser-consumed token metadata columns. The raw metadata
// stream still carries line/column because indentation decisions require it; the product adapter no
// longer pays for line/column output columns that the parser route never reads.

// Product columnar lexer entry: tokenize, insert indentation braces, and compact parser metadata before
// returning to the host. resultCounts[0] is the raw indentation-expanded count; resultCounts[1] is the
// compact parser-token count. This keeps the transition adapter from binding standalone lexer probe ABIs.




// Lifetime token support, mirroring the production lexer (Lexer.cs:325-328, 903-960). At an
// apostrophe, the lexer emits a single Lifetime token (ordinal 142) -- instead of a char literal --
// when the apostrophe begins an identifier (next char letter/'_', and the char after that is not a
// closing quote, distinguishing `'a` from the char literal `'a'`) AND it appears in a lifetime
// CONTEXT: the nearest preceding non-whitespace character is `<` or `,`, or the identifier word
// immediately before it is `scoped` or `returns`. These checks intentionally use the scanner's
// existing ASCII character classification (consistent with IsDigit/IsIdentifierStart elsewhere);
// the scanner-wide ASCII-vs-Unicode classification gap is tracked separately in self-host-progress.md.
// Whitespace for the lifetime-context lookback.





// Returns ((exclusive end offset) << 2) | kind, where kind is 1 = IntLiteral, 2 = FloatLiteral, and
// 3 = Unknown (the malformed-number error token). The 1/2 values double as the
// TokenType ordinals; callers map the sentinel 3 to Unknown (137). Each error branch returns the same
// span consumed by the production lexer (so NumberValueLength, which counts non-'_' chars, reproduces token text):
//   - 0x / 0b with no valid digit immediately after the prefix (a leading '_' counts as "no digit",
//     matching the production lexer) -> Unknown ending right after the prefix;
//   - a second decimal point (Lexer.cs:650-659) -> Unknown after consuming the remaining digits/dots;
//   - an exponent e/E[+/-] with no digit after it (Lexer.cs:681-684) -> Unknown ending after the sign.




// Encodes token kind and source width as kind * 4 + width to avoid tuple/out parameters.



// Character classification mirrors the production lexer's use of the BCL Unicode predicates
// (Lexer.cs: char.IsLetter at 342/905, char.IsLetterOrDigit at 567/922/926/942, char.IsDigit at
// 336/631/647/653/681/686/757, char.IsWhiteSpace at 912/1084).



// Hex digits are ASCII-only letters plus any Unicode decimal digit, matching production IsHexDigit
// (Lexer.cs:757 = char.IsDigit(c) || a-f || A-F).

// ---- ParserTypeReferences.nl ----

// Parser slice 6: the first N#-native RECURSIVE-DESCENT, tree-building parser kernel. Where slices 1-5
// produced flat top-level indices via single-pass token scans, this kernel implements the
// ParseTypeReference -> ParsePostfixTypeReference -> ParseBaseTypeReference recursion
// for the four dominant type-reference forms and emits a real parent->child AST as a flat columnar node
// table. It consumes the lexer's brace-inserted token kind/start/value-length arrays produced by
// TokenizeColumnarSourceInto and builds nodes in POST-ORDER (children before parents), so the
// root is the last node written.
//
// Supported forms (matching the concrete type-reference node ABI):
//   SimpleTypeReference   -> kind 0   e.g. int, string, A.B.C (dotted name folded to one name span)
//   GenericTypeReference  -> kind 1   e.g. List<int>, Dictionary<string, int>, List<List<int>>
//   ArrayTypeReference    -> kind 2   e.g. int[], List<int>[]
//   NullableTypeReference -> kind 3   e.g. int?, int?[] (=> Array(Nullable(inner)))
//   UnionTypeReference    -> kind 4   e.g. int | string, List<int> | string (slice 7; arms are postfix
//                                     types, and a union may itself be a generic argument: List<int | T>)
//   ByRefTypeReference    -> kind 5   e.g. &int, &List<int>, &int[] (slice 8; `&` prefixing a postfix type)
//   TupleTypeReference    -> kind 6   e.g. (int, int), (x: int, y: int) -- a `(` + >=2 comma-separated element
//                                     types + `)`. NAMED elements are ALL-OR-NOTHING (partial naming refuses,
//                                     the production-parser rule): each named element wraps in a kind 7 below.
//   NamedTupleElement     -> kind 7   `name: Type` inside a NAMED tuple type -- the element NAME in the name
//                                     slot, ONE child (the element type). Only ever a kind-6 child; canonicals
//                                     ERASE it (tuple identity is positional), the host extracts the names.
// Deferred to later rungs:
//   - FunctionTypeReference `Func<...>` -- this kernel has no source string (only token offsets),
//     so it cannot distinguish Func from any other
//     generic name; Func is therefore excluded from the corpus and will parse as a Generic node. Resolving
//     it needs the parser to gain source access (a later architectural step that also unlocks name-based
//     contextual keywords).
//
// Node-table columns (all caller-allocated to capacity >= count+1; outChildIndices likewise):
//   outNodeKinds[i]   : 0 Simple | 1 Generic | 2 Array | 3 Nullable | 4 Union | 5 ByRef | 6 Tuple
//   outNameStarts[i]  : source byte offset of the (dotted) name for Simple/Generic; -1 otherwise
//   outNameLengths[i] : name byte length; 0 when no name
//   outChildStart[i]  : index into outChildIndices where this node's child ids begin; -1 when no children
//   outChildCount[i]  : Generic = #type args; Union = #arms (>= 2); Array/Nullable/ByRef = 1; Simple = 0
//   outChildIndices[] : flattened child node-id pointers (the tree edges); each node's children occupy a
//                       CONTIGUOUS run (see the arg-stack note below)
//   outSpanStarts[i]  : source byte offset where the node's full text begins
//   outSpanLengths[i] : byte length of the node's full text (so source.Substring(start,len) is the type)
//   outResult[0]      : root node id (== nodeCount-1 by the post-order convention)
//   outResult[1]      : token index one past the consumed type (the caller's continuation cursor)
// Returns the number of nodes written, or -1 on refusal (non-identifier first token), parse failure
// (e.g. an unterminated generic), or generic-nesting depth > 64.
//
// Parser state is threaded through the recursion in a single caller-owned `ParserState` struct (a
// production parser state:
//   st.Pos = pos                 current token index
//   st.SplitGreaterDepth = splitGreaterDepth   owed `>` count from a split `>>` (RightShift) token
//   st.NodeCursor = nodeCursor          next free node-table slot
//   st.ChildCursor = childCursor         next free outChildIndices slot
//   st.OwedGreaterByteEnd = owedGreaterByteEnd  byte end of the owed second-half `>` while splitGreaterDepth > 0
//   st.ArgStackTop = argStackTop         top of the generic-argument id stack (see below)
//
// Generic arguments are gathered onto a shared LIFO `argStack` rather than appended to outChildIndices as
// they are parsed: a nested generic argument appends ITS OWN children during parsing, which would otherwise
// interleave with and fragment the outer generic's contiguous child run. Because recursion is LIFO, each
// generic records the stack top on entry, pushes each parsed argument id, then -- only after the whole
// argument list and the closing `>` are consumed -- appends that contiguous block of ids to outChildIndices
// and pops the stack. This keeps every node's children contiguous in outChildIndices with a single
// allocation per top-level parse.
//
// TokenType ordinals used (from Token.cs, sequential, zero-based): Identifier 0, Less 100, Greater 102,
// BitwiseAnd 107, BitwiseOr 108, RightShift 112, Question 115, QuestionBracket 119, Dot 124,
// LeftParen 127, LeftBracket 131, RightBracket 132, Comma 134.

class ParserState {
    Pos: int
    NodeCursor: int
    ChildCursor: int
    ArgStackTop: int
    SplitGreaterDepth: int
    OwedGreaterByteEnd: int
    // Source text for CONTEXTUAL keyword checks (e.g. `assert throws`). Optional: entries that
    // never need token text may leave it empty, in which case contextual forms simply do not
    // match (safe under-accept -> decline).
    Source: string
    constructor(pos: int, nodeCursor: int, childCursor: int, argStackTop: int, splitGreaterDepth: int, owedGreaterByteEnd: int, sourceText: string = "") {
        Pos = pos
        NodeCursor = nodeCursor
        ChildCursor = childCursor
        ArgStackTop = argStackTop
        SplitGreaterDepth = splitGreaterDepth
        OwedGreaterByteEnd = owedGreaterByteEnd
        Source = sourceText
    }
}

class ParserNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(kinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], spanStarts: int[], spanLengths: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ParserTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    constructor(kinds: int[], starts: int[], valueLengths: int[]) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
    }
}

class ParserArgumentStack {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class ParserChildIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class ParserResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class TypeReferenceCanonicalTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}

class TypeReferenceTupleNameTable {
    Names: string[]
    constructor(names: string[]) {
        Names = names
    }
}





// Consume one closing `>` for a generic argument list, including split `>>` handling:
// a single `>` (Greater 102) is consumed directly;
// a `>>` (RightShift 112) is consumed once but credits ONE owed `>` so the enclosing generic close uses the
// second half without advancing past a real token. Returns the byte end of the consumed `>`, or -1 on a
// missing close.

// ParseBaseTypeReference (Parser.cs:1828-1907) restricted to identifier-led Simple/Generic forms. Reads a
// (possibly dotted) name, then optional `<...>` generic arguments. Returns the emitted node id, or -1 on
// refusal/failure. Advances st.Pos past the consumed tokens.

// ParsePostfixTypeReference (Parser.cs:1758-1812): a base type followed by any run of `[]` (array), `?[]`
// (nullable array => Array(Nullable(inner))), and `?` (nullable) suffixes. Returns the outermost node id.

// ParseUnionTypeReference (Parser.cs:1718-1756): the top of the type grammar. A postfix type, optionally
// followed by `| postfix` arms; with at least one `|` it becomes a UnionTypeReference whose arms are the
// children (gathered on the LIFO arg-stack for contiguity, like generic args). With no `|` it returns the
// single postfix node unchanged. This is the level a generic argument and the top-level entry parse, so a
// union may appear as a generic argument (e.g. List<int | string>). Returns the node id, or -1.

// ---- ParserExpressions.nl ----

// Parser slice 10: the first EXPRESSION kernel -- the foundation of the largest parser subsystem (the
// ~17-level precedence chain in Parser.cs ParseExpression..ParsePrimaryExpression). This slice establishes
// the expression node table + the recursive structure with PRIMARY expressions only; later slices layer on
// postfix (call/index/member), unary, and the binary-operator precedence chain.
//
// Supported this slice (matching the concrete expression node ABI):
//   IntLiteralExpression    -> kind 0   (IntLiteral token 1)
//   FloatLiteralExpression  -> kind 1   (FloatLiteral token 2)
//   CharLiteralExpression   -> kind 2   (CharLiteral token 3)
//   StringLiteralExpression -> kind 3   (StringLiteral token 4, TripleQuoteStringLiteral token 5,
//                                         InterpolatedRawStringLiteral token 6)
//   BoolLiteralExpression   -> kind 4   (True 44 / False 45)
//   NullLiteralExpression   -> kind 5   (Null 46)
//   IdentifierExpression    -> kind 6   (Identifier 0)
//   ParenthesizedExpression -> kind 7   ( ( expr ) -- a single non-tuple parenthesized expression )
//   MemberAccessExpression  -> kind 8   ( obj.member -- slice 11; member name in the value span )
//   CallExpression          -> kind 9   ( callee(args) -- slice 12; children [callee, arg0, arg1, ...] )
//   IndexAccessExpression   -> kind 10  ( obj[index] -- slice 11; children [object, index] )
//   UnaryExpression         -> kind 11  ( prefix !/-/~/++/--/^ -- slice 13; operator token in value span )
//   BinaryExpression        -> kind 12  ( left OP right -- slice 14; operator token in value span; the full
//                                         left-associative precedence chain ?? || && | ^ & ==/!= rel << >> +- */% )
//   TernaryExpression       -> kind 13  ( cond ? then : else -- slice 15; children [cond, then, else] )
//   AssignmentExpression    -> kind 14  ( target OP value -- slice 15; = += -= *= /= ??=; right-associative )
//   NewExpression           -> kind 15  ( new <type> ( args ) or new <elementType>[length] -- slice 19;
//                                         children [typeRoot, arg0, ...] or [arrayTypeRoot, length];
//                                         the type child is a TYPE-kernel subtree (kinds 0-5), args are
//                                         expression subtrees. Constructor named args are kind-60 wrappers.
//                                         The host walks child[0] as a type and the
//                                         rest as expressions. Composes the type kernel via the unified st. )
//   CastExpression          -> kind 16  ( ( <type> ) operand -- hard cast; children [typeRoot, operand];
//                                         operand is a unary expression. Detected by speculatively parsing a
//                                         type after `(` and requiring `) <expr-start>` (Parser.cs
//                                         IsCastExpression); otherwise the `(` is a parenthesized expression. )
//   TupleExpression         -> kind 17  ( ( e0, e1, ... ) -- a `,` after the first parenthesised expression;
//                                         children = the element expressions (variable arity). Positional only. )
//   MatchExpression         -> kind 18  ( match <value> { <pat> => <res>, ... }; children [value, pat0, res0, ...].
//                                         Each pattern is a PRIMARY expr (literal or bare identifier). `=>` = 120. )
//   GuardedPattern          -> kind 19  ( <pattern> when <guard> -- a `when` (token 54) after a match pattern;
//                                         children [pattern, guard]. Appears ONLY as a match-case pattern slot.
//                                         The emitter tests the inner pattern, then the guard, before the result. )
//   RelationalPattern       -> kind 32  ( <op> <constant> at the start of a match pattern, op in {< <= > >=}
//                                         (tokens 100/101/102/103); operator in the value span, 1 child = the
//                                         operand. Appears ONLY as a match-case pattern slot (incl. under a guard). )
//   AndPattern              -> kind 33  ( <pat> and <pat> -- match-case combinator, children [left, right]. )
//   OrPattern               -> kind 34  ( <pat> or <pat>  -- match-case combinator, children [left, right]. )
//   NotPattern              -> kind 35  ( not <pat>       -- match-case combinator, 1 child [inner]. )
//   ObjectInitializer       -> kind 36  ( new <type> { Field: value, ... } -- children [typeRoot, name0 (Identifier
//                                         kind 6), value0, name1, value1, ...]. Constructs a fields-only struct. )
//   GenericCallee           -> kind 38  ( callee<T1, T2> before a `(` -- the callee identifier's name in the value
//                                         span, children = the TYPE-kernel type-argument roots. Only ever appears
//                                         as child[0] of a CallExpression; committed via the IsGenericCallTypeArgs
//                                         lookahead, the Parser.cs IsGenericMethodCall mirror. Kind 37 is
//                                         UnionCasePattern in ParserStatements. )
//   Lambda                  -> kind 39  ( `x => expr` / `() => expr` / `(x, y) => expr` -- the level ABOVE
//                                         assignment (ParseLambdaOrAssignmentExpression, Parser.cs:3660). The
//                                         `=>` token in the value span; children = [param Identifiers (kind 6,
//                                         zero or more), body expression root] -- paramCount = childCount - 1.
//                                         Params are UNTYPED by grammar (the production parser rejects `:` in a
//                                         lambda list); the body is an EXPRESSION at this level or a statement
//                                         BLOCK (kind 25, parsed by the statement kernel -- mutual recursion in
//                                         the other direction from statements-call-expressions). Parsed at the
//                                         full-expression entry and in call ARGUMENTS (the production's
//                                         ParseExpression positions modeled so far). Kind 40 is
//                                         TypedLocalDeclaration and 41 LocalFunctionDeclaration in
//                                         ParserStatements. )
//   BareNew                 -> kind 42  ( `new <type>` with neither `( args )` nor `{ inits }` -- children
//                                         [typeRoot (a TYPE-kernel subtree -- name scans must skip the whole
//                                         node, like kind 38)]. The brace-less union-case construction form
//                                         (`new Color.Red`, `new Opt.None<int>`); the emitter declines every
//                                         non-union-case type root. )
//   NamedTupleElement       -> kind 43  ( `name: value` inside a NAMED tuple literal `(x: 1, y: 2)` -- the
//                                         element NAME in the name slot, ONE child (the element value). Only
//                                         ever a kind-17 child; naming is ALL-OR-NOTHING per literal. The
//                                         name is metadata (not a value read) so scans traverse the child
//                                         normally. )
//   PostfixUnary            -> kind 44  ( `n++` / `n--` (Increment 113 / Decrement 114) -- the operator
//                                         token in the value span, ONE child [target]. Single wrap after the
//                                         postfix suffix chain; the target child is a VALUE expression the
//                                         scans traverse normally -- and a WRITE: the write scans treat a
//                                         kind-44 like a kind-14 assignment to its target. )
//   MustExpression          -> kind 45  ( `must <operand>` (Must 20) -- the prefix null-assert, ONE child;
//                                         unwraps a Nullable<T> to T or null-checks a reference, throwing
//                                         InvalidOperationException when null. )
//   IsExpression            -> kind 46  ( `value is Type` (Is 47) -- children [value, typeRoot]; the
//                                         typeRoot is a TYPE subtree (scans walk child 0 only). )
//   AsExpression            -> kind 47  ( `value as Type` (As 48) -- the null-propagating cast twin of
//                                         kind 46; same child shape. )
//   WithExpression          -> kind 52  ( `expr with { Field: value, ... }` (With 71) -- the kind-36
//                                         object-init pair layout with the RECEIVER in place of the type
//                                         root: children [receiver, name0 (kind 6), value0, ...]; zero
//                                         pairs = a pure clone. Kinds 48-51 are STATEMENT kinds
//                                         (throw/try/catch/lock). )
//   AwaitExpression         -> kind 53  ( `await <expr>` (Await 69) -- prefix unary, ONE child
//                                         [operand]. )
//   RefOutArgument          -> kind 54  ( `ref <expr>` / `out <expr>` inside a call argument list; the
//                                         modifier token lives in the value span, ONE child [target]. )
//   TypeOfExpression        -> kind 55  ( `typeof(Type)` (Typeof 49) -- ONE child [typeRoot], where the child is a
//                                         TYPE-kernel subtree. )
//   CheckedContextExpression -> kind 57 ( `checked(expr)` / `unchecked(expr)` (Checked 83 / Unchecked 84);
//                                         keyword token in the value span, ONE child [expr]. )
//   ArrayLiteralExpression  -> kind 58  ( `[e0, e1, ...]` (LeftBracket 131 / RightBracket 132); children
//                                         are the element expressions. Target-typed in the emitter. )
//   AnonymousObjectInitializer -> kind 59 (`new { Field: value, ... }`; children [name0 (Identifier kind 6),
//                                         value0, name1, value1, ...]. The parser records the shape; lowering is
//                                         a later backend slice, so today's emitter declines this node explicitly.)
//   NamedArgumentExpression -> kind 60 (`name: value` inside a `new <type>(...)` argument list; name in the
//                                         value span, ONE child [value]. Calls still decline named args until
//                                         call-site semantic binding owns parameter-name matching.)
//   TypeBindingPattern     -> kind 61  ( `Type name` inside a match arm; children [typeRoot, binding].)
//   NameOfExpression       -> kind 62  ( `nameof(expr)` (Nameof 50) -- ONE child [expr]. The emitter accepts
//                                         the analyzer-validated identifier/member-access target subset.)
//   TargetTypedNewExpression -> kind 63 (`new(args...)` with no explicit type; children [arg0, ...].
//                                         Lowering only accepts contexts that provide an expected type.)
// `alloc <expr>` is parsed transparently: systems analysis owns allocation-policy enforcement before this
// product handoff, and the emitter only needs the concrete expression shape.
// Deferred (refused with -1, or the chain simply STOPS at them): `?.`/`?[` null-conditional access, generic
//   method calls (callee<T>(...)), named (`name:`) call arguments outside constructor argument lists,
//   `is`/`as` type tests, range `..`; every other unlisted primary (this/base/default/...).
//   (Tuples `(a, b)` AND named tuples `(x: 1, y: 2)` PARSE — kinds 17/43; match,
//   new-expressions, object initializers, bare-new and block-bodied lambdas have their own kinds above.)
//   Literal VALUE materialization (unescaping strings/chars) is the host's job; this kernel records the
//   value token's byte span only.
//
// Node-table columns (caller-allocated to capacity >= count+1; outChildIndices likewise):
//   nodes.Kinds[i]    : 0..7 per the list above
//   nodes.ValueStarts[i]  : byte offset of the literal/identifier value token; -1 for Null/Parenthesized
//   nodes.ValueLengths[i] : value byte length; 0 when none
//   nodes.ChildStart[i]   : index into outChildIndices for children; -1 when none
//   nodes.ChildCount[i]   : Parenthesized/MemberAccess = 1; IndexAccess = 2; Call = 1 + #args; others = 0
//   outChildIndices[]  : flattened child node-id edges (post-order; root is the last node)
//   nodes.SpanStarts[i] / nodes.SpanLengths[i] : full source byte span of the node
//   outResult[0] = root node id (== nodeCount-1), outResult[1] = token index past the consumed expression
// Returns the node count, or -1 on refusal / depth > 200.
//
// ParserState `st`: st.Pos=pos, st.NodeCursor=nodeCursor, st.ChildCursor=childCursor, st.ArgStackTop=argStackTop. Calls gather the
// callee + argument node ids on the caller-owned LIFO `argStack` (recursion is LIFO) and append the
// contiguous child run after the closing `)`, exactly as the type kernel does for generic arguments.
//
// For MemberAccess/IndexAccess the value name span (member) or the two children (object, index) are appended
// directly after the object and index are fully parsed -- both are fixed-arity, so their child runs are
// contiguous without the arg-stack.
//
// TokenType ordinals (Token.cs): Identifier 0, IntLiteral 1, FloatLiteral 2, CharLiteral 3, StringLiteral 4,
// TripleQuoteStringLiteral 5, InterpolatedRawStringLiteral 6, True 44, False 45, Null 46, LeftParen 127,
// RightParen 128, Dot 124, LeftBracket 131, RightBracket 132.

class ParserExpressionNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(kinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], spanStarts: int[], spanLengths: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}





// Mirrors Parser.cs IsExpressionStart: the set of token kinds that can begin an expression. Used by the cast
// detection in ParsePrimaryExpressionNode to disambiguate `( <type> ) <expr>` (a hard cast) from a
// parenthesized expression. Kinds (TokenType ordinals, see Token.cs): Identifier 0, IntLiteral 1, FloatLiteral 2,
// CharLiteral 3, StringLiteral 4, TripleQuoteStringLiteral 5, InterpolatedRawStringLiteral 6, Must 20,
// Match 31, Default 34, Throw 37, New 41, This 42, Base 43, True 44, False 45, Null 46, Typeof 49, Nameof 50,
// Sizeof 51, Await 69, Immutable 70, Checked 83, Unchecked 84, Plus 88, Minus 89, Not 106, BitwiseNot 110,
// Increment 113, Decrement 114, LeftParen 127, LeftBracket 131, Alloc 143, Stackalloc 145.

// Mirrors Parser.cs IsGenericMethodCall (the `<`-after-callee disambiguation, Parser.cs:1993): from the `<` at
// `lessPos`, scan a candidate TYPE-ARGUMENT list — identifiers, dots (124), nullable suffixes (115),
// array brackets (131/132), commas (134), and nested `<`(100)/`>`(102)/`>>`(112) — and answer true ONLY
// when the matching close is followed
// DIRECTLY by `(` (127). Anything else (an operator, a literal, a `)` …) means the `<` is a comparison, not a
// type-argument list, so the kernel commits to a generic call only for the production generic-call shape.

// Parse a match-case PATTERN with N# pattern precedence: or > and > not > relational >
// primary. Returns the root node index, or -1 on failure. `and` 55 / `or` 56 / `not` 57 are CONTEXTUAL keywords
// valid only in pattern position. Combinators: OrPattern kind 34 [left,right], AndPattern kind 33 [left,right],
// NotPattern kind 35 [inner]; leaves are a RelationalPattern (kind 32) or an ordinary primary (literal/identifier).

// `<and-pattern> ( or <and-pattern> )*` -> left-associative OrPattern (kind 34). `or` is token 56.

// `<not-pattern> ( and <not-pattern> )*` -> left-associative AndPattern (kind 33). `and` is token 55.

// `not <not-pattern>` -> NotPattern (kind 35, 1 child); else a relational-or-primary pattern. `not` is token 57.

// A relational operator (`<` 100, `<=` 101, `>` 102, `>=` 103) at the start -> RelationalPattern (kind 32: operator
// token in the value span, 1 child = the operand primary). Otherwise an ordinary primary. (`>=` is one token, so
// there is no `>`-split here.)

// ParsePrimaryExpression (Parser.cs:4525) restricted to literals, identifiers, and ( expr ). Returns the
// emitted node id, or -1 on refusal/failure. Advances st.Pos past the consumed tokens.

// ParsePostfixExpression (Parser.cs:4312) restricted to member access (.name) and index access ([expr]).
// A primary expression followed by any run of `.member` and `[index]` suffixes. The member name and the
// two index children are appended right after the object/index are fully parsed (fixed arity => contiguous
// child runs, no arg-stack). Index expressions recurse to this postfix level (the current expression top).


// ParseUnaryExpression (Parser.cs:4223) restricted to the prefix operators: ! (Not 106), - (Negate, Minus
// 89), ~ (BitwiseNot 110), ++ (PreIncrement 113), -- (PreDecrement 114), ^ (IndexFromEnd, BitwiseXor 109).
// A prefix operator wraps a (recursively-parsed) unary operand -> UnaryExpression (kind 11, operator token
// in the value span); otherwise the operand is a postfix expression. (Prefix `+` is invalid in N# and is
// refused via the postfix/primary fall-through. Postfix ++/-- and `must` are deferred.)

// Precedence level (higher binds tighter) for a left-associative binary operator token, or 0 if the token
// is not a binary operator. Precedence chain, low->high:
// ?? (NullCoalesce) < || < && < | < ^ < & < ==,!= < <,<=,>,>= < <<,>> < +,- < *,/,%.
// `is`/`as` (type tests), range `..`, and assignment are intentionally NOT binary operators here (deferred).

// ParseBinaryExpression: precedence climbing over the binary chain. Parses a unary
// operand, then while the next token is a binary operator whose precedence >= minPrec, consumes it and
// parses the right operand at (precedence + 1) -- the left-associative formulation, producing the same
// left-leaning BinaryExpression trees. Each BinaryExpression (kind 12) records
// the operator token in the value span and has children [left, right] (fixed arity -> contiguous, no
// arg-stack). `minPrec == 1` is the full-expression entry.

// ParseTernaryExpression (Parser.cs:3916): a binary-chain condition, optionally followed by `? then : else`
// (TernaryExpression, kind 13, children [condition, then, else]). The then/else branches are full
// expressions (assignment level), making the ternary right-associative in the else branch.

// ParseAssignmentExpression (Parser.cs:3599): a ternary target, optionally followed by an assignment
// operator (= += -= *= /= ??=) and a right-hand value (AssignmentExpression, kind 14, operator token in the
// value span, children [target, value]). Right-associative: the value recurses to the assignment level, so
// a = b = c parses as a = (b = c). The full-expression entry is ParseLambdaOrAssignmentExpressionNode (the
// lambda level above this one).

// ParseLambdaOrAssignmentExpression (Parser.cs:3660): LAMBDA literals sit at the level ABOVE assignment.
// Modeled shapes (Lambda kind 39, the `=>` token in the value span, children = [param Identifiers..., body]):
//   `x => expr`     -- a bare Identifier DIRECTLY followed by Arrow 120 (the Parser.cs:3672 lookahead);
//   `() => expr`    -- empty parenthesized list (`( ) =>`);
//   `(x, y) => expr`-- a parenthesized BARE-identifier list, committed via a pure speculative scan mirroring
//                      Parser.cs IsLambdaExpression (identifiers separated by commas to `)`, then `=>`) --
//                      anything else in the list (a type annotation `:`, a default, a non-identifier) falls
//                      through to the assignment level, where `(x, y)` refuses as an unmodeled tuple.
// The BODY is an expression parsed at THIS level (a lambda can return a lambda, as in the production
// ParseExpression recursion); a BLOCK body (`=> {`) makes the body parse refuse (-1) -- statement-bodied
// lambdas are a later rung, and the refusal declines the whole program (safe under-acceptance).

// Parser slices 16-17: the STATEMENT kernel -- function bodies, the critical path for parsing the dogfood
// kernels (flat top-level functions whose bodies are statements). ParseStatementNodesCore parses ONE statement
// at a token index and COMPOSES the slice 10-15
// expression kernel: statements and expressions share ONE columnar node table (the expression table), with the
// shared expression `ParserState` (`st`) and `argStack`. Statement nodes use kinds 20+ so they never collide
// with the expression kinds 0-14. The flattened ParseStatementNodesInto ABI lives in the parity corpus.
//
// Supported statement nodes (matching the concrete statement node ABI):
//   ReturnStatement              -> kind 20  ( return [value]; 0 or 1 child = the value expression )
//   BreakStatement               -> kind 21  ( break; 0 children )
//   ContinueStatement            -> kind 22  ( continue; 0 children )
//   ExpressionStatement          -> kind 23  ( <expr>; 1 child = the expression, incl. assignment exprs )
//   VariableDeclarationStatement -> kind 24  ( name := init; name in the value span, 1 child = initializer )
//   BlockStatement               -> kind 25  ( { stmt* }; children = the statements, variable arity )
//   WhileStatement               -> kind 26  ( while cond <body>; children [condition, body] )
//   IfStatement                  -> kind 27  ( if cond <then> [else <else>]; children [cond, then, else?] )
//   ForStatement                 -> kind 28  ( for <init>; <cond>; <incr> <body>; children [init, cond, incr, body] )
//   ForeachStatement             -> kind 29  ( `foreach <var> in <coll>` or `for <var> in <coll>`; var in the value span,
//                                             children [coll, body] )
//   TupleDeconstructionStatement -> kind 30  ( n0, n1, ... := <tuple>; children [name0..nameN-1 (Identifier kind 6), value] )
//   TypedLocalDeclaration        -> kind 40  ( [let] name: Type = init; the TYPE's source span in the VALUE slot
//                                             (type trees cannot share this table — kind spaces collide), children
//                                             [name Identifier (kind 6), init root]. Kinds 31-39 belong to the
//                                             expression/pattern kernel. )
//   LocalFunctionDeclaration     -> kind 41  ( `func name(...) ... { body }` as a STATEMENT. The kernel records
//                                             ONLY the `func` keyword's byte span (value slot, no children) and
//                                             SKIPS the whole declaration (first depth-0 `{`, balanced to its
//                                             close — the struct kernel's method-skip discipline); the host
//                                             re-locates the keyword by byte offset and parses the signature +
//                                             body through the existing kernels. )
//   ThrowStatement               -> kind 48  ( throw <expr>; 1 child = the exception expression )
//   TryStatement                 -> kind 49  ( try/catch.../finally?; children [tryBlock, catch1..catchN,
//                                             finallyBlock? (a trailing kind-25 block)] )
//   CatchClause                  -> kind 50  ( one catch; value span = the exception TYPE name token, -1 for
//                                             a bare catch; children [nameIdent (kind 6)?, block] )
//   LockStatement                -> kind 51  ( lock <expr> { }; children [lockee, body]. Kinds 52-55
//                                             belong to the expression kernel (With, Await, RefOut,
//                                             TypeOf). )
//   PrintStatement               -> kind 56  ( print <expr>; 1 child = the printed expression. Lowered as
//                                             the legacy emitter did: evaluate, box a value type, call
//                                             Console.WriteLine(object). Kind 57 belongs to the expression
//                                             kernel (CheckedContextExpression); kind 58 belongs to the
//                                             expression kernel (ArrayLiteralExpression). )
//   AllowStatement               -> kind 60  ( allow(...) <body>; children [body]. The parser validates the
//                                             balanced argument list and block; lowering is a later backend
//                                             slice, so today's emitter declines this node explicitly. Kind 59
//                                             belongs to AnonymousObjectInitializer. )
//   AssertStatement              -> kind 61  ( assert <cond> [, <msg>]; children [condition, message?].
//                                             Lowered per the legacy emitter: brtrue past a
//                                             `throw new InvalidOperationException(<msg or "Assertion failed">)`. )
//   AssertThrowsStatement        -> kind 62  ( assert throws <TypeName> { body }; the exception TYPE name
//                                             token in the value span, ONE child [body block]. 63 is the
//                                             next free kind. )
//   Systems policy wrappers (`allow(...) {}`, `alloc {}`, `unsafe {}`) parse as transparent kind-25 blocks;
//                                             systems analysis owns policy semantics before emission.
// `:=` (ColonAssign 121) after a BARE identifier is the variable declaration (Kind=Let, Type=null); `=`
// (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement. An
// if/while body is ANY statement (commonly a `{ }` block, but a single statement is also valid), so the
// bodies recurse through the statement dispatcher; `else if` chains as a nested if.
//
// Deferred: parenthesised `foreach (x in y)`, const/readonly declarations, using/switch/yield,
// and statements whose expression parts use a not-yet-supported form. Block statement-list gathers child
// node ids on the LIFO `argStack` (recursion is LIFO) and appends the contiguous child run after `}`,
// exactly as calls/generics do.
//
// Node-table columns are the EXPRESSION table (see ParserExpressions.nl).
//   outResult[0] = root statement node id (== nodeCount-1), outResult[1] = token index past the statement.
// Returns the node count, or -1 on refusal / a malformed statement / an unsupported expression part.
//
// TokenType ordinals (Token.cs): Identifier 0, If 23, Else 24, For 25, Foreach 26, While 27, In 28, Return 29,
// Break 35, Continue 36, Assign 93, ColonAssign 121, LeftBrace 129, RightBrace 130, Semicolon 133, Eof 135, Newline 136.



// Dispatch + parse a single statement at st.Pos. Returns the emitted statement node id, or -1.

// The non-control-flow statements: return / break / continue / `:=` declaration / expression statement.


// ---- ParserDeclarations.nl ----

// First N#-native parser slice: extract the top-level declaration KIND sequence from the
// brace-inserted parser metadata stream produced by TokenizeColumnarSourceInto. A top-level
// declaration is a declaration keyword that appears at brace/bracket/paren depth 0 -- i.e. not nested
// inside a type body ({...}), an attribute list ([...]), or a parameter/argument list ((...)). Leading
// modifiers (public/static/...) and attributes ([Foo]) are naturally skipped because they are not
// declaration keywords; `ref struct` and `duck interface` are captured at their `struct`/`interface`
// keyword. Returns the
// number of declarations and writes each declaration's keyword TokenType ordinal into outKinds.
//
// Recognized declaration keyword ordinals (TokenType, see Token.cs): Func=7, Class=8, Struct=9,
// Interface=10, Union=12, Record=13, Enum=14, Type=72, Test=73. (The contextual `setup`/`teardown`
// declarations and preprocessor declarations are intentionally out of scope for this first slice;
// corpora that exercise this kernel avoid them.)
// Parser slice 3: the file's package name span: the dotted name after a top-level `package` keyword
// (`package A.B.C`); a file has at most one. This records the
// span covering the dotted name (first identifier start through the last identifier's end, so the host
// materializes "A.B.C"). Returns 1 and fills outResult[0]=start, outResult[1]=length when a package is
// present; returns 0 otherwise. The package keyword is only
// recognized at depth 0, before any declaration body.
class NamespaceImportTable {
    NsStarts: int[]
    NsLengths: int[]
    AliasStarts: int[]
    AliasLengths: int[]
    constructor(nsStarts: int[], nsLengths: int[], aliasStarts: int[], aliasLengths: int[]) {
        NsStarts = nsStarts
        NsLengths = nsLengths
        AliasStarts = aliasStarts
        AliasLengths = aliasLengths
    }
}

class TopLevelDeclarationModifierTable {
    Kinds: int[]
    Modifiers: int[]
    constructor(kinds: int[], modifiers: int[]) {
        Kinds = kinds
        Modifiers = modifiers
    }
}

class TopLevelDeclarationKindTable {
    Kinds: int[]
    constructor(kinds: int[]) {
        Kinds = kinds
    }
}

class TopLevelDeclarationIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}

class TopLevelStructLikeDeclarationTable {
    Indices: int[]
    ReferenceFlags: int[]
    RecordFlags: int[]
    constructor(indices: int[], referenceFlags: int[], recordFlags: int[]) {
        Indices = indices
        ReferenceFlags = referenceFlags
        RecordFlags = recordFlags
    }
}

class TopLevelColumnarFunctionDeclarationTable {
    Indices: int[]
    AsyncFlags: int[]
    constructor(indices: int[], asyncFlags: int[]) {
        Indices = indices
        AsyncFlags = asyncFlags
    }
}

class TopLevelColumnarNominalDeclarationTable {
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
    constructor(enumIndices: int[], unionIndices: int[], interfaceIndices: int[]) {
        EnumIndices = enumIndices
        UnionIndices = unionIndices
        InterfaceIndices = interfaceIndices
    }
}

class TopLevelColumnarProgramDeclarationTable {
    FuncIndices: int[]
    FuncAsyncFlags: int[]
    EnumIndices: int[]
    UnionIndices: int[]
    InterfaceIndices: int[]
    StructIndices: int[]
    StructReferenceFlags: int[]
    StructRecordFlags: int[]
    constructor(funcIndices: int[], funcAsyncFlags: int[], enumIndices: int[], unionIndices: int[], interfaceIndices: int[], structIndices: int[], structReferenceFlags: int[], structRecordFlags: int[]) {
        FuncIndices = funcIndices
        FuncAsyncFlags = funcAsyncFlags
        EnumIndices = enumIndices
        UnionIndices = unionIndices
        InterfaceIndices = interfaceIndices
        StructIndices = structIndices
        StructReferenceFlags = structReferenceFlags
        StructRecordFlags = structRecordFlags
    }
}

class TopLevelDeclarationNameTable {
    Kinds: int[]
    Indices: int[]
    NameStarts: int[]
    NameLengths: int[]
    constructor(kinds: int[], indices: int[], nameStarts: int[], nameLengths: int[]) {
        Kinds = kinds
        Indices = indices
        NameStarts = nameStarts
        NameLengths = nameLengths
    }
}

class InterfaceDeclarationTable {
    MethodFuncIndices: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(methodFuncIndices: int[], baseNameStarts: int[], baseNameLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        MethodFuncIndices = methodFuncIndices
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class EnumMemberTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
    constructor(nameStarts: int[], nameLengths: int[], valueStarts: int[], valueLengths: int[], hasValue: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        HasValue = hasValue
    }
}

class EnumMemberValueTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

class StructDeclarationTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    MethodModifierFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    constructor(fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], fieldStaticFlags: int[], fieldInitKinds: int[], fieldInitStarts: int[], fieldInitLengths: int[], methodFuncIndices: int[], methodStaticFlags: int[], methodModifierFlags: int[], ctorIndices: int[], propIndices: int[], propStaticFlags: int[], typeParamStarts: int[], typeParamLengths: int[], baseNameStarts: int[], baseNameLengths: int[]) {
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        FieldStaticFlags = fieldStaticFlags
        FieldInitKinds = fieldInitKinds
        FieldInitStarts = fieldInitStarts
        FieldInitLengths = fieldInitLengths
        MethodFuncIndices = methodFuncIndices
        MethodStaticFlags = methodStaticFlags
        MethodModifierFlags = methodModifierFlags
        CtorIndices = ctorIndices
        PropIndices = propIndices
        PropStaticFlags = propStaticFlags
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
    }
}

class PrimaryConstructorParameterTable {
    NameStarts: int[]
    NameLengths: int[]
    TypeStarts: int[]
    TypeLengths: int[]
    DefaultKinds: int[]
    DefaultStarts: int[]
    DefaultLengths: int[]
    constructor(nameStarts: int[], nameLengths: int[], typeStarts: int[], typeLengths: int[], defaultKinds: int[], defaultStarts: int[], defaultLengths: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        TypeStarts = typeStarts
        TypeLengths = typeLengths
        DefaultKinds = defaultKinds
        DefaultStarts = defaultStarts
        DefaultLengths = defaultLengths
    }
}

class ConstructorChainArgTable {
    Kinds: int[]
    Starts: int[]
    Lengths: int[]
    constructor(kinds: int[], starts: int[], lengths: int[]) {
        Kinds = kinds
        Starts = starts
        Lengths = lengths
    }
}

class UnionDeclarationTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    CaseFieldCounts: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(caseNameStarts: int[], caseNameLengths: int[], caseFieldCounts: int[], fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        CaseNameStarts = caseNameStarts
        CaseNameLengths = caseNameLengths
        CaseFieldCounts = caseFieldCounts
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class ParserDeclarationTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    constructor(kinds: int[], starts: int[], valueLengths: int[]) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
    }
}

class ParserDeclarationKindStream {
    Kinds: int[]
    constructor(kinds: int[]) {
        Kinds = kinds
    }
}

class ParserDeclarationStartKindStream {
    Kinds: int[]
    Starts: int[]
    constructor(kinds: int[], starts: int[]) {
        Kinds = kinds
        Starts = starts
    }
}

class ParserDeclarationResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}


// Parser slice 4: namespace imports. The parser processes a prefix of `package`/`import` lines
// before declarations; an `import` whose first token is an Identifier is a
// NamespaceImport (`import A.B.C [as X]`) routed to CompilationUnit.Imports, while one followed by a
// string is a FileImport routed elsewhere and skipped here. This walks that header prefix linearly
// (imports/package are at depth 0, before any brace) and records each namespace import's dotted-name
// span and optional alias span (alias start = -1 when none). The host materializes the strings.

// Parser slice 5: per-top-level-declaration modifier flags. Uses the shared modifier flag layout and
// recognizes, before a declaration keyword,
// Public/Private/Static/Internal/Protected/Virtual/Override/Abstract/Sealed/Partial/Async/File. Returns
// 0 for non-modifier tokens. (Readonly/Const/Required/Init are member-level, not declaration modifiers.)

// For each top-level declaration, record its keyword kind and its accumulated modifier flags (the
// modifier keywords appearing at depth 0 between the previous declaration and this one's keyword;
// attributes are inside brackets so they do not interfere). Matches (int)Declaration.Modifiers.
// A depth-0 `where` (53) opens a generic CONSTRAINT clause whose items may include the `class` (8) /
// `struct` (9) KEYWORDS — those are constraints, not declarations, so keyword recognition is suppressed
// from `where` until the body `{` (which also ends the signature). All three top-level scanners share
// this rule.


// Parser slice 2: like TopLevelDeclarationKindsCore, but also records each declaration's NAME span.
// A declaration's name is the token immediately after its keyword (modifiers precede the keyword, so
// nothing sits between keyword and name) when that token is an Identifier (kind 0). For `test "..."`
// the token after the keyword is a string literal, so no name is recorded (outNameStart = -1) -- the
// test string name is out of scope for this slice. The host materializes the name from
// source via outNameStarts/outNameLengths.












// Parser declaration safety guard for top-level functions. The declaration scans intentionally skip
// unknown depth-0 tokens, so this validates the token immediately before each `func` keyword: only
// recognized modifiers (`static`, `async`), a previous declaration close, a package/namespace import
// dotted header prefix, or a quoted file-import header may precede a top-level function. Returns 1
// when every function preamble is valid.



// Parser declaration utility: the compacted-token index of the `}` (130) that closes the `{` (129)
// at `open`, or -1 if `open` is not a left brace or the brace run is unbalanced. This keeps property
// accessor body delimiting in the N# parser path instead of leaving a host adapter-side scanner.

// Parser declaration utility: find the compacted-token index whose kind and source start match a
// parser-node source span. Used for local-function statement nodes, where the statement parser
// records the `func` keyword span and the adapter must re-enter the declaration parser at that token.

// Parser declaration utility: parse one computed property accessor block already discovered by
// ParseStructDeclarationCore. Returns 0 for get-only, 1 for get/set, or -1 for unsupported shapes.
// outResult: [0]=nameStart, [1]=nameLength, [2]=typeStart, [3]=typeLength,
// [4]=getBodyBraceIndex, [5]=setBodyBraceIndex-or--1.
// Flattened ParsePropertyAccessor*Into ABIs live in the parity corpus; product callers compose this
// core through ParserColumnarProperties.nl.





// Product interface declaration core. Flattened ParseInterfaceDeclaration* ABIs live in the
// parity corpus; product callers compose this core through ParserInterfaceSignatures.nl.










// Product enum declaration core. Flattened ParseEnumDeclaration* ABIs live in the parity corpus;
// product callers compose this core through ParserColumnarEnums.nl.














// Parse one struct/class/record declaration into wrapper-owned declaration tables. The flattened
// ParseStructDeclaration* ABIs live in the parity corpus; product callers compose this core directly.


// Parse a CONSTRUCTOR's chaining initializer `: this(args)` / `: base(args)`, given the constructor's identifier
// token index (`ctorIndex`, the "constructor" identifier). Scans past the param list `(...)` (balanced) to the
// optional `:`; with no `:` (or no `(` params) returns 0 with outResult[0] = 0 (no initializer). For `: this(`
// (this = 42) / `: base(` (base = 43), records each chained ARG — restricted to a SINGLE token, either a param
// IDENTIFIER (kind 0) or an INT LITERAL (kind 1) — into outArgKinds/outArgStarts/outArgLengths, separated by `,`
// (134), closed by `)` (128). outResult[0] = the initializer kind (0 = none, 1 = this, 2 = base);
// outResult[1] = the constructor BODY `{` token index, or -1 if it is missing. Returns the chained-arg count, or
// -1 on a malformed initializer or a non-{identifier,int-literal} arg (a complex expression / string /
// other literal — the host declines such a chaining ctor to the N# backend path).
// Product constructor-chain core. Flattened ParseConstructor*Into ABIs live in the parity corpus;
// product callers compose this core through ParserConstructorSignatures.nl.

// Parser slice (union bodies): parse ONE `union Name[<T, U>] { Case { f: T, ... }  Case { ... } }` declaration into
// flat parallel arrays. `unionIndex` is the compacted token index of the `union` keyword (token 12). Reads the union
// NAME (the Identifier after `union`) into outResult[0]=nameStart / outResult[1]=nameLength, an OPTIONAL generic
// type-parameter list `<T, U>` (Less 100 / Identifier 0 / Comma 134 / Greater 102 — the same bare-identifier shape
// as the struct/class kernel; spans to outTypeParamStarts/Lengths, count to outResult[2], 0 with no `<`; an inline
// constraint or empty list returns -1), then `{` (129), then a sequence of CASES until the union close `}` (130).
// Each case is either bare `CaseName` or `CaseName { field : Type, ... }`: the case name (Identifier) into
// outCaseNameStarts/Lengths[case], then either no payload or a `{` (129) containing a sequence of FIELDS —
// `Identifier : Type` where the type is a SINGLE Identifier token (a builtin like int/string, a bare user-type
// name, or one of the union's type parameters) — each delimited by an optional `,` (134), closed by the case `}`
// (130). Fields flatten ACROSS all cases into
// outFieldNameStarts/Lengths + outFieldTypeStarts/Lengths in case-then-field order; outCaseFieldCounts[case] records
// how many fields that case contributed (so the host re-segments the flat field arrays per case). Returns the case
// count, or -1 on any unexpected token — a primary-ctor `(`, a composed/array/generic field type (a non-Identifier
// after `:`), a field initializer, a missing name/colon/brace, or an empty union — so
// the host declines the whole program to the N# backend path. Slice scope: unions whose case fields are single
// builtin/bare-name/type-param-typed (the emitter further gates each field type to a supported CLR type).

// ---- ParserFunctionSignatures.nl ----

// Parser slice 9: the first declaration-level recursive-descent kernel -- it COMPOSES the slice 6-8 type
// kernel (ParserTypeReferences.nl). Given a `func` keyword token index, ParseFunctionSignatureCore parses
// the function's signature -- name, parameter names + parameter type trees, and the return type tree.
// All parameter type trees and the return type tree share ONE columnar node table (the same table the
// type kernel fills), so each is an independent root within it; the shared `ParserState` (`st`) carries
// the node/child cursors across the per-type parses while st.Pos (pos) is repositioned to each type's start.
//
// Scope this slice: parameter NAME + parameter TYPE (any form the type kernel supports: Simple / Generic /
// Array / Nullable / Union / ByRef), the `: ReturnType` return type (or none), an optional generic
// TYPE-PARAMETER list `<T, U>` between the name and `(` — each type parameter is a bare Identifier (an
// inline constraint `<T: Base>` or any non-identifier form returns -1) — and zero or more generic
// CONSTRAINT clauses `where T: Item, Item ...` after the return type (D-17b). Each constraint ITEM is
// recorded as a flat row: the owning type parameter's name span plus a code — a type-tree ROOT (>= 0)
// parsed into the shared node table, or a special-constraint sentinel (-2 `class`, -3 `struct`,
// -4 `new()`). Clause grouping is NOT preserved (the host groups rows by owner name).
// Parameter modifiers `ref` (78) and `out` (79) wrap the parsed parameter type in a ByRef type node; `params`
// (82), `this` (42), `scoped 'a` lifetime annotations, `returns 'a` return-lifetime annotations,
// and attribute lists `[...]` are skipped. Supported one-token default values are
// materialized for CLR optional-parameter metadata; richer default expressions decline.
// Deferred (the corpus avoids them): `->` return-type syntax, `returns param(...)`/`returns heap(...)`,
// expression-bodied functions with full control-flow analysis, and non-literal default values.
//
// Output:
//   outNodeKinds/... (8 columns) + outChildIndices : the shared type node table (see ParserTypeReferences.nl)
//   outParamNameStarts[p], outParamNameLengths[p]  : byte span of parameter p's name
//   outParamTypeRoots[p]                            : node id of parameter p's type tree root
//   outTypeParamStarts[t], outTypeParamLengths[t]   : byte span of generic type parameter t's name
//   outWhereNameStarts[w], outWhereNameLengths[w]   : byte span of constraint row w's OWNER type-param name
//   outWhereItemCodes[w]                            : row w's constraint — a type root (>= 0) or a special
//                                                     sentinel (-2 class, -3 struct, -4 new())
//   outResult[0] = parameter count
//   outResult[1] = return type tree root node id, or -1 when the function has no return type
//   outResult[2] = total node count written to the shared table
//   outResult[3], outResult[4] = byte span (start, length) of the function name (start -1 if anonymous)
//   outResult[5] = generic type-parameter count (0 for a non-generic function)
//   outResult[6] = the token index immediately AFTER the parsed signature (after the `where` clauses when
//                  any exist, else after the return type / the `)`), so the host can verify what follows
//                  (the body `{`, a ctor `: this/base` initializer, or an unmodelled `=>` body to decline)
//   outResult[7] = constraint row count (0 for a function with no `where` clauses)
// Returns the parameter count, or -1 on a malformed signature / a parameter type the type kernel refuses.
//
// TokenType ordinals (Token.cs): Identifier 0, This 42, Ref 78, Out 79, Params 82, Assign 93, Func 7,
// New 41, Where 53, Class 8, Struct 9, Less 100, Greater 102, Colon 122, Comma 134, LeftParen 127,
// RightParen 128, LeftBrace 129, RightBrace 130, LeftBracket 131, RightBracket 132.
// Flattened ParseFunctionSignature*Into ABIs live in the parity corpus; product callers compose the
// typed cores in this file directly.

class FunctionSignatureInfoOutputTable {
    FunctionNameTexts: string[]
    ReturnTypeTexts: string[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamModifierKinds: int[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    ParamTupleNameCounts: int[]
    ParamTupleNameTexts: string[]
    ReturnTupleNameTexts: string[]
    TypeParamTexts: string[]
    TypeParamSpecials: int[]
    TypeParamConstraintCounts: int[]
    TypeParamConstraintTypeTexts: string[]
    constructor(functionNameTexts: string[], returnTypeTexts: string[], paramNameTexts: string[], paramTypeTexts: string[], paramModifierKinds: int[], paramDefaultKinds: int[], paramDefaultTexts: string[], paramTupleNameCounts: int[], paramTupleNameTexts: string[], returnTupleNameTexts: string[], typeParamTexts: string[], typeParamSpecials: int[], typeParamConstraintCounts: int[], typeParamConstraintTypeTexts: string[]) {
        FunctionNameTexts = functionNameTexts
        ReturnTypeTexts = returnTypeTexts
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ParamModifierKinds = paramModifierKinds
        ParamDefaultKinds = paramDefaultKinds
        ParamDefaultTexts = paramDefaultTexts
        ParamTupleNameCounts = paramTupleNameCounts
        ParamTupleNameTexts = paramTupleNameTexts
        ReturnTupleNameTexts = returnTupleNameTexts
        TypeParamTexts = typeParamTexts
        TypeParamSpecials = typeParamSpecials
        TypeParamConstraintCounts = typeParamConstraintCounts
        TypeParamConstraintTypeTexts = typeParamConstraintTypeTexts
    }
}

class FunctionSignatureTupleNameScratchTable {
    Names: string[]
    constructor(names: string[]) {
        Names = names
    }
}

class FunctionSignatureNameSpanTable {
    Starts: int[]
    Lengths: int[]
    constructor(starts: int[], lengths: int[]) {
        Starts = starts
        Lengths = lengths
    }
}

class FunctionSignatureOwnerIndexTable {
    Indices: int[]
    constructor(indices: int[]) {
        Indices = indices
    }
}














class ParserFunctionParameterTable {
    NameStarts: int[]
    NameLengths: int[]
    TypeRoots: int[]
    constructor(nameStarts: int[], nameLengths: int[], typeRoots: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        TypeRoots = typeRoots
    }
}

class ParserFunctionTypeParameterTable {
    Starts: int[]
    Lengths: int[]
    constructor(starts: int[], lengths: int[]) {
        Starts = starts
        Lengths = lengths
    }
}

class ParserFunctionWhereTable {
    NameStarts: int[]
    NameLengths: int[]
    ItemCodes: int[]
    constructor(nameStarts: int[], nameLengths: int[], itemCodes: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ItemCodes = itemCodes
    }
}


// ---- ParserConstructorSignatures.nl ----

// Composed constructor-signature product core. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter. The flattened
// ParseConstructorSignatureInfoInto ABI lives in the parity corpus.

class ConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
    constructor(paramNameTexts: string[], paramTypeTexts: string[], argKinds: int[], argStarts: int[], argLengths: int[], argTexts: string[]) {
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ArgKinds = argKinds
        ArgStarts = argStarts
        ArgLengths = argLengths
        ArgTexts = argTexts
    }
}




// ---- ParserInterfaceSignatures.nl ----

// Composed interface-signature product core. ParserDeclarations.nl stays a standalone declaration parser; this
// file owns the cross-file routing that combines interface member indices, function-signature parsing, and canonical
// type text for the columnar product adapter. The flattened ParseInterfaceDeclarationSignatureInfoInto ABI lives
// in the parity corpus.

class InterfaceSignatureBaseOutputTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    TypeParamTexts: string[]
    constructor(baseNameStarts: int[], baseNameLengths: int[], baseNameTexts: string[], interfaceNameTexts: string[], typeParamTexts: string[]) {
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        BaseNameTexts = baseNameTexts
        InterfaceNameTexts = interfaceNameTexts
        TypeParamTexts = typeParamTexts
    }
}

class InterfaceSignatureMethodOutputTable {
    FuncIndices: int[]
    NameTexts: string[]
    ReturnTexts: string[]
    ParamCounts: int[]
    BodyFlags: int[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    constructor(funcIndices: int[], nameTexts: string[], returnTexts: string[], paramCounts: int[], bodyFlags: int[], paramNameTexts: string[], paramTypeTexts: string[]) {
        FuncIndices = funcIndices
        NameTexts = nameTexts
        ReturnTexts = returnTexts
        ParamCounts = paramCounts
        BodyFlags = bodyFlags
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
    }
}

class InterfaceSignatureTupleNodeTable {
    Kinds: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}



// ---- ParserLocalFunctions.nl ----

// Local-function discovery core for product columnar routing. ParseStatementNodesCore already marks a local
// function declaration as statement kind 41 with the `func` keyword's source span; this core maps direct children
// of a function body block to their compact token indices in N#, keeping the adapter out of statement-table scans.
// The flattened DirectLocalFunctionTokenIndicesInto ABI lives in the parity corpus.

class LocalFunctionTokenTable {
    Kinds: int[]
    Starts: int[]
    Count: int
    constructor(kinds: int[], starts: int[], count: int) {
        Kinds = kinds
        Starts = starts
        Count = count
    }
}

class LocalFunctionNodeTable {
    Kinds: int[]
    ValueStarts: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    constructor(kinds: int[], valueStarts: int[], childStart: int[], childCount: int[], childIndices: int[]) {
        Kinds = kinds
        ValueStarts = valueStarts
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
    }
}

class LocalFunctionResultTable {
    NodeIndices: int[]
    FuncTokenIndices: int[]
    constructor(nodeIndices: int[], funcTokenIndices: int[]) {
        NodeIndices = nodeIndices
        FuncTokenIndices = funcTokenIndices
    }
}


// ---- ParserColumnarFunctions.nl ----

// Product columnar function parser wrapper. It composes the signature rowset, statement-node rowset, and
// direct local-function discovery so the host adapter only materializes ColumnarFunctionInput containers.

class ColumnarFunctionTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarFunctionSignatureOutputTable {
    FunctionNameTexts: string[]
    ReturnTypeTexts: string[]
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ParamModifierKinds: int[]
    ParamDefaultKinds: int[]
    ParamDefaultTexts: string[]
    ParamTupleNameCounts: int[]
    ParamTupleNameTexts: string[]
    ReturnTupleNameTexts: string[]
    TypeParamTexts: string[]
    TypeParamSpecials: int[]
    TypeParamConstraintCounts: int[]
    TypeParamConstraintTypeTexts: string[]
    constructor(functionNameTexts: string[], returnTypeTexts: string[], paramNameTexts: string[], paramTypeTexts: string[], paramModifierKinds: int[], paramDefaultKinds: int[], paramDefaultTexts: string[], paramTupleNameCounts: int[], paramTupleNameTexts: string[], returnTupleNameTexts: string[], typeParamTexts: string[], typeParamSpecials: int[], typeParamConstraintCounts: int[], typeParamConstraintTypeTexts: string[]) {
        FunctionNameTexts = functionNameTexts
        ReturnTypeTexts = returnTypeTexts
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ParamModifierKinds = paramModifierKinds
        ParamDefaultKinds = paramDefaultKinds
        ParamDefaultTexts = paramDefaultTexts
        ParamTupleNameCounts = paramTupleNameCounts
        ParamTupleNameTexts = paramTupleNameTexts
        ReturnTupleNameTexts = returnTupleNameTexts
        TypeParamTexts = typeParamTexts
        TypeParamSpecials = typeParamSpecials
        TypeParamConstraintCounts = typeParamConstraintCounts
        TypeParamConstraintTypeTexts = typeParamConstraintTypeTexts
    }
}

class ColumnarFunctionBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], spanStarts: int[], spanLengths: int[]) {
        NodeKinds = nodeKinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ColumnarFunctionLocalTable {
    NodeIndices: int[]
    TokenIndices: int[]
    constructor(nodeIndices: int[], tokenIndices: int[]) {
        NodeIndices = nodeIndices
        TokenIndices = tokenIndices
    }
}

class ColumnarFunctionResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}







// ---- ParserColumnarConstructors.nl ----

// Product columnar constructor parser wrapper. It composes constructor signature/chain parsing with the
// statement-node rowset so the host adapter no longer orchestrates constructor body parsing.

class ColumnarConstructorTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
    constructor(paramNameTexts: string[], paramTypeTexts: string[], argKinds: int[], argStarts: int[], argLengths: int[], argTexts: string[]) {
        ParamNameTexts = paramNameTexts
        ParamTypeTexts = paramTypeTexts
        ArgKinds = argKinds
        ArgStarts = argStarts
        ArgLengths = argLengths
        ArgTexts = argTexts
    }
}

class ColumnarConstructorBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], spanStarts: int[], spanLengths: int[]) {
        NodeKinds = nodeKinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ColumnarConstructorResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}









// ---- ParserColumnarStructs.nl ----

// Product columnar struct/class/record parser wrapper. It keeps declaration span scratch columns inside N#,
// rejects unsupported value-type storage/property shapes and member generic/local functions, and exposes only text,
// flag, and member-index rows needed by the columnar input builder.

class ColumnarStructTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarStructScratchTable {
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    FieldInitStarts: int[]
    FieldInitLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    constructor(fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], fieldInitStarts: int[], fieldInitLengths: int[], typeParamStarts: int[], typeParamLengths: int[], baseNameStarts: int[], baseNameLengths: int[]) {
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        FieldInitStarts = fieldInitStarts
        FieldInitLengths = fieldInitLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
    }
}

class ColumnarStructOutputTable {
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    FieldStaticFlags: int[]
    FieldInitKinds: int[]
    FieldInitTexts: string[]
    MethodFuncIndices: int[]
    MethodStaticFlags: int[]
    CtorIndices: int[]
    PropIndices: int[]
    PropStaticFlags: int[]
    TypeParamTexts: string[]
    BaseNameTexts: string[]
    StructNameTexts: string[]
    constructor(fieldNameTexts: string[], fieldTypeTexts: string[], fieldStaticFlags: int[], fieldInitKinds: int[], fieldInitTexts: string[], methodFuncIndices: int[], methodStaticFlags: int[], ctorIndices: int[], propIndices: int[], propStaticFlags: int[], typeParamTexts: string[], baseNameTexts: string[], structNameTexts: string[]) {
        FieldNameTexts = fieldNameTexts
        FieldTypeTexts = fieldTypeTexts
        FieldStaticFlags = fieldStaticFlags
        FieldInitKinds = fieldInitKinds
        FieldInitTexts = fieldInitTexts
        MethodFuncIndices = methodFuncIndices
        MethodStaticFlags = methodStaticFlags
        CtorIndices = ctorIndices
        PropIndices = propIndices
        PropStaticFlags = propStaticFlags
        TypeParamTexts = typeParamTexts
        BaseNameTexts = baseNameTexts
        StructNameTexts = structNameTexts
    }
}

class ColumnarStructResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}

















// ---- ParserColumnarUnions.nl ----

// Product columnar union parser wrapper. It keeps declaration span scratch columns inside N# and exposes only
// the text/count rows needed by the columnar input builder.

class ColumnarUnionTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarUnionScratchTable {
    CaseNameStarts: int[]
    CaseNameLengths: int[]
    FieldNameStarts: int[]
    FieldNameLengths: int[]
    FieldTypeStarts: int[]
    FieldTypeLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(caseNameStarts: int[], caseNameLengths: int[], fieldNameStarts: int[], fieldNameLengths: int[], fieldTypeStarts: int[], fieldTypeLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        CaseNameStarts = caseNameStarts
        CaseNameLengths = caseNameLengths
        FieldNameStarts = fieldNameStarts
        FieldNameLengths = fieldNameLengths
        FieldTypeStarts = fieldTypeStarts
        FieldTypeLengths = fieldTypeLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class ColumnarUnionTextOutputTable {
    CaseNameTexts: string[]
    CaseFieldCounts: int[]
    FieldNameTexts: string[]
    FieldTypeTexts: string[]
    TypeParamTexts: string[]
    UnionNameTexts: string[]
    constructor(caseNameTexts: string[], caseFieldCounts: int[], fieldNameTexts: string[], fieldTypeTexts: string[], typeParamTexts: string[], unionNameTexts: string[]) {
        CaseNameTexts = caseNameTexts
        CaseFieldCounts = caseFieldCounts
        FieldNameTexts = fieldNameTexts
        FieldTypeTexts = fieldTypeTexts
        TypeParamTexts = typeParamTexts
        UnionNameTexts = unionNameTexts
    }
}

class ColumnarUnionResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}





// Mirrors UnionValueLayout.IsValueStructEmittable on the columnar union shape. A small, closed,
// payload-free, non-generic union emits as its allocation-free PUBLIC readonly tag struct. The
// columnar input builder consults this kernel so it can select the value-struct ABI instead of
// heap case classes. Eligibility holds when the
// union is non-generic, has 1..MaxValueStructCases (16) cases, and every case is payload-free (caseFieldCounts[c]
// is case c's field count; a non-zero count means the case carries a payload). Returns 1 when eligible, else 0.


// ---- ParserColumnarEnums.nl ----

// Product columnar enum parser wrapper. It keeps span/value-literal scratch columns inside N# and exposes only
// the enum/member text plus resolved int values needed by the columnar input builder.

class ColumnarEnumTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarEnumMemberScratchTable {
    NameStarts: int[]
    NameLengths: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    HasValue: int[]
    constructor(nameStarts: int[], nameLengths: int[], valueStarts: int[], valueLengths: int[], hasValue: int[]) {
        NameStarts = nameStarts
        NameLengths = nameLengths
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        HasValue = hasValue
    }
}

class ColumnarEnumTextOutputTable {
    MemberNameTexts: string[]
    MemberValues: int[]
    MemberStringValues: string[]
    EnumNameTexts: string[]
    constructor(memberNameTexts: string[], memberValues: int[], memberStringValues: string[], enumNameTexts: string[]) {
        MemberNameTexts = memberNameTexts
        MemberValues = memberValues
        MemberStringValues = memberStringValues
        EnumNameTexts = enumNameTexts
    }
}

class ColumnarEnumResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}







// ---- ParserColumnarInterfaces.nl ----

// Product columnar interface parser wrapper. It keeps base-name span scratch columns inside N#,
// rejects unsupported default-method local functions, and exposes only the interface/base text
// plus method signature rows needed by the columnar input builder.

class ColumnarInterfaceTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarInterfaceBaseScratchTable {
    BaseNameStarts: int[]
    BaseNameLengths: int[]
    TypeParamStarts: int[]
    TypeParamLengths: int[]
    constructor(baseNameStarts: int[], baseNameLengths: int[], typeParamStarts: int[], typeParamLengths: int[]) {
        BaseNameStarts = baseNameStarts
        BaseNameLengths = baseNameLengths
        TypeParamStarts = typeParamStarts
        TypeParamLengths = typeParamLengths
    }
}

class ColumnarInterfaceOutputTable {
    MethodFuncIndices: int[]
    BaseNameTexts: string[]
    InterfaceNameTexts: string[]
    MethodNameTexts: string[]
    MethodReturnTexts: string[]
    MethodParamCounts: int[]
    MethodBodyFlags: int[]
    MethodParamNameTexts: string[]
    MethodParamTypeTexts: string[]
    TypeParamTexts: string[]
    constructor(methodFuncIndices: int[], baseNameTexts: string[], interfaceNameTexts: string[], methodNameTexts: string[], methodReturnTexts: string[], methodParamCounts: int[], methodBodyFlags: int[], methodParamNameTexts: string[], methodParamTypeTexts: string[], typeParamTexts: string[]) {
        MethodFuncIndices = methodFuncIndices
        BaseNameTexts = baseNameTexts
        InterfaceNameTexts = interfaceNameTexts
        MethodNameTexts = methodNameTexts
        MethodReturnTexts = methodReturnTexts
        MethodParamCounts = methodParamCounts
        MethodBodyFlags = methodBodyFlags
        MethodParamNameTexts = methodParamNameTexts
        MethodParamTypeTexts = methodParamTypeTexts
        TypeParamTexts = typeParamTexts
    }
}

class ColumnarInterfaceResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}







// ---- ParserColumnarProperties.nl ----

// Product columnar property parser wrapper. It composes property accessor/type parsing with getter/setter
// statement-node rowsets so the host adapter no longer binds statement parsing for property bodies.

class ColumnarPropertyTokenTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}

class ColumnarPropertyTextTable {
    NameTexts: string[]
    TypeTexts: string[]
    constructor(nameTexts: string[], typeTexts: string[]) {
        NameTexts = nameTexts
        TypeTexts = typeTexts
    }
}

class ColumnarPropertyBodyTable {
    NodeKinds: int[]
    ValueStarts: int[]
    ValueLengths: int[]
    ChildStart: int[]
    ChildCount: int[]
    ChildIndices: int[]
    SpanStarts: int[]
    SpanLengths: int[]
    constructor(nodeKinds: int[], valueStarts: int[], valueLengths: int[], childStart: int[], childCount: int[], childIndices: int[], spanStarts: int[], spanLengths: int[]) {
        NodeKinds = nodeKinds
        ValueStarts = valueStarts
        ValueLengths = valueLengths
        ChildStart = childStart
        ChildCount = childCount
        ChildIndices = childIndices
        SpanStarts = spanStarts
        SpanLengths = spanLengths
    }
}

class ColumnarPropertyResultTable {
    Values: int[]
    constructor(values: int[]) {
        Values = values
    }
}






func ParserTokenCompactionIndicesCountedInto(tokenKinds: int[], tokenCount: int, resultIndices: int[]): int {
    if tokenCount < 0 {
        return -1
    }

    if tokenCount > tokenKinds.Length {
        return -1
    }

    tokens := new LexerTokenKindTable(tokenKinds)
    result := new LexerTokenIndexTable(resultIndices)
    return ParserTokenCompactionIndicesCore(tokens, result, tokenCount)
}

func ParserTokenCompactionIndicesCore(tokens: LexerTokenKindTable, result: LexerTokenIndexTable, length: int): int {
    count := 0
    i := 0

    if result.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if ParserTokenCompactionKeepsToken(tokens.Kinds[i]) {
                result.Indices[count] = i
                count = count + 1
            }

            next := i + 1
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 2
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 3
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 4
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 5
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 6
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 7
            if ParserTokenCompactionKeepsToken(tokens.Kinds[next]) {
                result.Indices[count] = next
                count = count + 1
            }

            i = i + 8
        }

        while i < length {
            if ParserTokenCompactionKeepsToken(tokens.Kinds[i]) {
                result.Indices[count] = i
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    while i < length {
        if ParserTokenCompactionKeepsToken(tokens.Kinds[i]) {
            if count >= result.Indices.Length {
                return -1
            }

            result.Indices[count] = i
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func ParserTokenCompactedMetadataCore(tokens: LexerCompactTokenMetadataTable, length: int, result: LexerCompactTokenMetadataTable): int {
    count := 0
    i := 0

    while i < length {
        if ParserTokenCompactionKeepsToken(tokens.Kinds[i]) {
            result.Kinds[count] = tokens.Kinds[i]
            result.Starts[count] = tokens.Starts[i]
            result.ValueLengths[count] = tokens.ValueLengths[i]
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func ParserTokenCompactionKeepsToken(kind: int): bool {
    return kind != 136 && kind != 138
}

func TokenizeMetadataCore(source: string, metadata: LexerTokenMetadataTable): int {
    position := 0
    length := source.Length
    count := 0
    line := 1
    column := 1

    while position < length {
        ch := source[position]

        if IsWhitespaceExceptNewline(ch) {
            position = position + 1
            column = column + 1
            continue
        }

        start := position
        tokenLine := line
        tokenColumn := column

        if ch == '\n' {
            metadata.Kinds[count] = 136
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = 1
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            position = position + 1
            line = line + 1
            column = 1
            continue
        }

        if ch == '\r' {
            metadata.Kinds[count] = 136
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = 1
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            line = line + 1
            column = 1
            continue
        }

        if ch == '#' {
            position = position + 1
            column = column + 1
            while position < length && source[position] != '\n' && source[position] != '\r' {
                position = position + 1
                column = column + 1
            }

            metadata.Kinds[count] = 138
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = position - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            continue
        }

        if ch == '/' && position + 1 < length {
            next := source[position + 1]
            if next == '/' {
                position = position + 2
                column = column + 2
                while position < length && source[position] != '\n' && source[position] != '\r' {
                    position = position + 1
                    column = column + 1
                }
                continue
            }

            if next == '*' {
                position = position + 2
                column = column + 2
                while position < length {
                    if source[position] == '*' && position + 1 < length && source[position + 1] == '/' {
                        position = position + 2
                        column = column + 2
                        break
                    }

                    if source[position] == '\r' {
                        position = position + 1
                        if position < length && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
                continue
            }
        }

        if ch == '$' && position + 1 < length && source[position + 1] == '"' {
            if position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"' {
                nextPosition := ScanRawString(source, position + 4, length)
                metadata.Kinds[count] = 6
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                while position < nextPosition {
                    if source[position] == '\r' {
                        position = position + 1
                        if position < nextPosition && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
            } else {
                nextPosition := ScanString(source, position + 1, length, true)
                metadata.Kinds[count] = 4
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                nextPosition := ScanRawString(source, position + 3, length)
                metadata.Kinds[count] = 5
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                while position < nextPosition {
                    if source[position] == '\r' {
                        position = position + 1
                        if position < nextPosition && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
            } else {
                nextPosition := ScanString(source, position, length, false)
                metadata.Kinds[count] = 4
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '\'' && IsLifetimeStartAt(source, position, length) {
            nextPosition := ScanLifetime(source, position, length)
            metadata.Kinds[count] = 142
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = nextPosition - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if ch == '\'' {
            nextPosition := ScanCharLiteral(source, position, length)
            metadata.Kinds[count] = 3
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = nextPosition - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsDigit(ch) {
            numberInfo := ScanNumberInfo(source, position, length)
            nextPosition := numberInfo >> 2
            numberKind := numberInfo & 3
            if numberKind == 3 {
                numberKind = 137
            }

            metadata.Kinds[count] = numberKind
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = NumberValueLength(source, start, nextPosition)
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsIdentifierStart(ch) {
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            metadata.Kinds[count] = KeywordKind(source, start, position - start)
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = position - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (position - start)
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorKind := operatorInfo >> 2
        operatorWidth := operatorInfo & 3
        metadata.Kinds[count] = operatorKind
        metadata.Starts[count] = start
        metadata.ValueLengths[count] = operatorWidth
        metadata.Lines[count] = tokenLine
        metadata.Columns[count] = tokenColumn
        count = count + 1
        position = position + operatorWidth
        column = column + operatorWidth
    }

    metadata.Kinds[count] = 135
    metadata.Starts[count] = position
    metadata.ValueLengths[count] = 0
    metadata.Lines[count] = line
    metadata.Columns[count] = column
    count = count + 1
    return count
}

func InsertIndentationParserMetadataCore(
    raw: LexerTokenMetadataTable,
    rawCount: int,
    output: LexerCompactTokenMetadataTable,
    indentStack: LexerIndentStackTable): int {
    outCount := 0
    stackTop := 0
    indentStack.Indents[0] = 0
    atLineStart := true
    explicitBraceDepth := 0
    parenBracketDepth := 0
    hasBaseIndent := false
    baseIndent := 0

    i := 0
    while i < rawCount {
        kind := raw.Kinds[i]
        tokenStart := raw.Starts[i]
        tokenValueLength := raw.ValueLengths[i]
        tokenColumn := raw.Columns[i]
        lineStart := tokenStart - (tokenColumn - 1)

        if kind == 136 {
            output.Kinds[outCount] = kind
            output.Starts[outCount] = tokenStart
            output.ValueLengths[outCount] = tokenValueLength
            outCount = outCount + 1
            atLineStart = true
            i = i + 1
            continue
        }

        if kind == 135 {
            while stackTop > 0 {
                stackTop = stackTop - 1
                output.Kinds[outCount] = 130
                output.Starts[outCount] = lineStart
                output.ValueLengths[outCount] = 1
                outCount = outCount + 1
            }

            output.Kinds[outCount] = kind
            output.Starts[outCount] = tokenStart
            output.ValueLengths[outCount] = tokenValueLength
            outCount = outCount + 1
            return outCount
        }

        if atLineStart {
            rawIndent := tokenColumn - 1
            if rawIndent < 0 {
                rawIndent = 0
            }

            if !hasBaseIndent && stackTop == 0 {
                baseIndent = rawIndent
                hasBaseIndent = true
            }

            currentIndent := rawIndent - baseIndent
            if currentIndent < 0 {
                currentIndent = 0
            }

            if parenBracketDepth == 0 && explicitBraceDepth == 0 {
                previousIndent := indentStack.Indents[stackTop]
                if currentIndent > previousIndent {
                    stackTop = stackTop + 1
                    indentStack.Indents[stackTop] = currentIndent
                    output.Kinds[outCount] = 129
                    output.Starts[outCount] = lineStart
                    output.ValueLengths[outCount] = 1
                    outCount = outCount + 1
                } else if currentIndent < previousIndent {
                    while stackTop > 0 && currentIndent < indentStack.Indents[stackTop] {
                        stackTop = stackTop - 1
                        output.Kinds[outCount] = 130
                        output.Starts[outCount] = lineStart
                        output.ValueLengths[outCount] = 1
                        outCount = outCount + 1
                    }
                }
            }

            atLineStart = false
        }

        if kind == 129 {
            explicitBraceDepth = explicitBraceDepth + 1
        } else if kind == 130 {
            explicitBraceDepth = explicitBraceDepth - 1
            if explicitBraceDepth < 0 {
                explicitBraceDepth = 0
            }
        } else if kind == 127 || kind == 131 {
            parenBracketDepth = parenBracketDepth + 1
        } else if kind == 128 || kind == 132 {
            parenBracketDepth = parenBracketDepth - 1
            if parenBracketDepth < 0 {
                parenBracketDepth = 0
            }
        }

        output.Kinds[outCount] = kind
        output.Starts[outCount] = tokenStart
        output.ValueLengths[outCount] = tokenValueLength
        outCount = outCount + 1
        i = i + 1
    }

    return outCount
}

func TokenizeColumnarSourceInto(source: string, rawKinds: int[], rawStarts: int[], rawValueLengths: int[], compactKinds: int[], compactStarts: int[], compactValueLengths: int[], resultCounts: int[]): int {
    if resultCounts.Length < 2 {
        return -1
    }

    rawMetadata := new LexerTokenMetadataTable(new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1), new int[](source.Length + 1))
    rawTarget := new LexerCompactTokenMetadataTable(rawKinds, rawStarts, rawValueLengths)
    tokenCount := TokenizeMetadataCore(source, rawMetadata)
    indentStack := new LexerIndentStackTable(new int[](source.Length + 2))
    rawCount := InsertIndentationParserMetadataCore(rawMetadata, tokenCount, rawTarget, indentStack)
    if rawCount < 0 {
        return -1
    }

    raw := new LexerCompactTokenMetadataTable(rawKinds, rawStarts, rawValueLengths)
    compact := new LexerCompactTokenMetadataTable(compactKinds, compactStarts, compactValueLengths)
    compactCount := ParserTokenCompactedMetadataCore(raw, rawCount, compact)
    if compactCount < 0 {
        return -1
    }

    resultCounts[0] = rawCount
    resultCounts[1] = compactCount
    return compactCount
}

func ScanString(source: string, position: int, length: int, isInterpolated: bool): int {
    position = position + 1
    interpolationDepth := 0
    nestedStringDepth := 0

    while position < length {
        ch := source[position]
        if ch == '\n' || ch == '\r' {
            return position
        }

        if isInterpolated {
            if nestedStringDepth > 0 {
                if ch == '\\' {
                    position = position + 1
                    if position < length {
                        position = position + 1
                    }
                    continue
                }

                if ch == '"' {
                    nestedStringDepth = nestedStringDepth - 1
                }

                position = position + 1
                continue
            }

            if ch == '{' {
                interpolationDepth = interpolationDepth + 1
                position = position + 1
                continue
            }

            if ch == '}' && interpolationDepth > 0 {
                interpolationDepth = interpolationDepth - 1
                position = position + 1
                continue
            }

            if ch == '"' && interpolationDepth > 0 {
                nestedStringDepth = nestedStringDepth + 1
                position = position + 1
                continue
            }

            if ch == '"' && interpolationDepth == 0 {
                return position + 1
            }
        } else if ch == '"' {
            return position + 1
        }

        if ch == '\\' {
            position = position + 1
            if position < length {
                position = position + 1
            }
        } else {
            position = position + 1
        }
    }

    return position
}

func ScanRawString(source: string, position: int, length: int): int {
    while position < length {
        if source[position] == '"' && position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
            return position + 3
        }

        position = position + 1
    }

    return position
}

func ScanCharLiteral(source: string, position: int, length: int): int {
    position = position + 1
    if position >= length || source[position] == '\n' || source[position] == '\r' {
        return position
    }

    if source[position] == '\\' {
        position = position + 1
        // Do not consume the escaped char across a line
        // break, so e.g. `'\<CR>` leaves the CR to become a separate Newline token.
        if position < length && source[position] != '\n' && source[position] != '\r' {
            position = position + 1
        }
    } else {
        position = position + 1
    }

    if position < length && source[position] == '\'' {
        position = position + 1
    }

    return position
}

func IsLifetimeLookbackWhitespace(ch: char): bool {
    return char.IsWhiteSpace(ch)
}

func MatchesScopedOrReturns(source: string, start: int, length: int): bool {
    if length == 6 {
        return source[start] == 's' && source[start + 1] == 'c' && source[start + 2] == 'o' && source[start + 3] == 'p' && source[start + 4] == 'e' && source[start + 5] == 'd'
    }

    if length == 7 {
        return source[start] == 'r' && source[start + 1] == 'e' && source[start + 2] == 't' && source[start + 3] == 'u' && source[start + 4] == 'r' && source[start + 5] == 'n' && source[start + 6] == 's'
    }

    return false
}

func IsLifetimeContextAt(source: string, position: int): bool {
    index := position - 1
    while index >= 0 && IsLifetimeLookbackWhitespace(source[index]) {
        index = index - 1
    }

    if index < 0 {
        return false
    }

    previous := source[index]
    if previous == '<' || previous == ',' {
        return true
    }

    if !IsIdentifierPart(previous) {
        return false
    }

    end := index + 1
    while index >= 0 && IsIdentifierPart(source[index]) {
        index = index - 1
    }

    wordStart := index + 1
    return MatchesScopedOrReturns(source, wordStart, end - wordStart)
}

func IsLifetimeStartAt(source: string, position: int, length: int): bool {
    if position + 1 >= length {
        return false
    }

    if !IsIdentifierStart(source[position + 1]) {
        return false
    }

    if position + 2 < length && source[position + 2] == '\'' {
        return false
    }

    return IsLifetimeContextAt(source, position)
}

func ScanLifetime(source: string, position: int, length: int): int {
    position = position + 1
    while position < length && IsIdentifierPart(source[position]) {
        position = position + 1
    }

    return position
}

func ScanNumberInfo(source: string, position: int, length: int): int {
    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'x' || source[position + 1] == 'X') {
        position = position + 2
        if position >= length || !IsHexDigit(source[position]) {
            return (position << 2) | 3
        }

        while position < length && (IsHexDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }

        return (ParserConsumeIntegerSuffix(source, position, length) << 2) | 1
    }

    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'b' || source[position + 1] == 'B') {
        position = position + 2
        if position >= length || (source[position] != '0' && source[position] != '1') {
            return (position << 2) | 3
        }

        while position < length && (source[position] == '0' || source[position] == '1' || source[position] == '_') {
            position = position + 1
        }

        return (ParserConsumeIntegerSuffix(source, position, length) << 2) | 1
    }

    isFloat := false
    while position < length && (IsDigit(source[position]) || source[position] == '.' || source[position] == '_') {
        if source[position] == '.' {
            if position + 1 < length && source[position + 1] == '.' {
                break
            }

            if position + 1 >= length || !IsDigit(source[position + 1]) {
                break
            }

            if isFloat {
                while position < length && (IsDigit(source[position]) || source[position] == '.') {
                    position = position + 1
                }

                return (position << 2) | 3
            }

            isFloat = true
        }

        position = position + 1
    }

    if position < length && (source[position] == 'e' || source[position] == 'E') {
        isFloat = true
        position = position + 1
        if position < length && (source[position] == '+' || source[position] == '-') {
            position = position + 1
        }

        if position >= length || !IsDigit(source[position]) {
            return (position << 2) | 3
        }

        while position < length && (IsDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }
    }

    if isFloat {
        return (ParserConsumeFloatSuffix(source, position, length) << 2) | 2
    }

    if position < length && (source[position] == 'm' || source[position] == 'M') {
        return ((position + 1) << 2) | 2
    }

    return (ParserConsumeIntegerSuffix(source, position, length) << 2) | 1
}

func NumberValueLength(source: string, start: int, end: int): int {
    position := start
    valueLength := 0
    while position < end {
        if source[position] != '_' {
            valueLength = valueLength + 1
        }
        position = position + 1
    }

    return valueLength
}

func ParserConsumeFloatSuffix(source: string, position: int, length: int): int {
    if position < length && (source[position] == 'f' || source[position] == 'F' || source[position] == 'd' || source[position] == 'D' || source[position] == 'm' || source[position] == 'M') {
        return position + 1
    }

    return position
}

func ParserConsumeIntegerSuffix(source: string, position: int, length: int): int {
    if position < length && (source[position] == 'u' || source[position] == 'U') {
        position = position + 1
        if position < length && (source[position] == 'l' || source[position] == 'L') {
            position = position + 1
        }
        return position
    }

    if position < length && (source[position] == 'l' || source[position] == 'L') {
        position = position + 1
        if position < length && (source[position] == 'u' || source[position] == 'U') {
            position = position + 1
        }
        return position
    }

    return position
}

func OperatorInfo(source: string, position: int, length: int): int {
    ch := source[position]
    if position + 1 < length {
        next := source[position + 1]
        if ch == ':' {
            if next == '=' {
                return 486
            }
            if next == ':' {
                return 494
            }
        }

        if ch == '=' {
            if next == '=' {
                return 394
            }
            if next == '>' {
                return 482
            }
        }

        if ch == '!' && next == '=' {
            return 398
        }

        if ch == '<' {
            if next == '=' {
                return 406
            }
            if next == '<' {
                return 446
            }
        }

        if ch == '>' {
            if next == '=' {
                return 414
            }
            if next == '>' {
                return 450
            }
        }

        if ch == '&' && next == '&' {
            return 418
        }

        if ch == '|' && next == '|' {
            return 422
        }

        if ch == '+' {
            if next == '+' {
                return 454
            }
            if next == '=' {
                return 378
            }
        }

        if ch == '-' {
            if next == '-' {
                return 458
            }
            if next == '=' {
                return 382
            }
        }

        if ch == '*' && next == '=' {
            return 386
        }

        if ch == '/' && next == '=' {
            return 390
        }

        if ch == '?' {
            if next == '?' {
                if position + 2 < length && source[position + 2] == '=' {
                    return 471
                }

                return 466
            }

            if next == '.' {
                return 474
            }

            if next == '[' {
                return 478
            }
        }

        if ch == '.' && next == '.' {
            if position + 2 < length && source[position + 2] == '.' {
                return 507
            }

            return 502
        }
    }

    if ch == '+' {
        return 353
    }

    if ch == '-' {
        return 357
    }

    if ch == '*' {
        return 361
    }

    if ch == '/' {
        return 365
    }

    if ch == '%' {
        return 369
    }

    if ch == '=' {
        return 373
    }

    if ch == '<' {
        return 401
    }

    if ch == '>' {
        return 409
    }

    if ch == '!' {
        return 425
    }

    if ch == '&' {
        return 429
    }

    if ch == '|' {
        return 433
    }

    if ch == '^' {
        return 437
    }

    if ch == '~' {
        return 441
    }

    if ch == '?' {
        return 461
    }

    if ch == ':' {
        return 489
    }

    if ch == '.' {
        return 497
    }

    if ch == '(' {
        return 509
    }

    if ch == ')' {
        return 513
    }

    if ch == '{' {
        return 517
    }

    if ch == '}' {
        return 521
    }

    if ch == '[' {
        return 525
    }

    if ch == ']' {
        return 529
    }

    if ch == ';' {
        return 533
    }

    if ch == ',' {
        return 537
    }

    return 549
}

func KeywordKind(source: string, start: int, length: int): int {
    if length < 2 {
        return 0
    }

    ch0 := source[start]

    if length == 2 {
        if ch0 == 'i' {
            if source[start + 1] == 'f' {
                return 23
            }
            if source[start + 1] == 'n' {
                return 28
            }
            if source[start + 1] == 's' {
                return 47
            }
        }
        if ch0 == 'a' && source[start + 1] == 's' {
            return 48
        }
        if ch0 == 'o' && source[start + 1] == 'r' {
            return 56
        }
    }

    if length == 3 {
        if ch0 == 'f' && source[start + 1] == 'o' && source[start + 2] == 'r' {
            return 25
        }
        if ch0 == 'l' && source[start + 1] == 'e' && source[start + 2] == 't' {
            return 19
        }
        if ch0 == 'n' {
            if source[start + 1] == 'e' && source[start + 2] == 'w' {
                return 41
            }
            if source[start + 1] == 'o' && source[start + 2] == 't' {
                return 57
            }
        }
        if ch0 == 't' && source[start + 1] == 'r' && source[start + 2] == 'y' {
            return 38
        }
        if ch0 == 'a' && source[start + 1] == 'n' && source[start + 2] == 'd' {
            return 55
        }
        if ch0 == 'o' && source[start + 1] == 'u' && source[start + 2] == 't' {
            return 79
        }
        if ch0 == 'r' && source[start + 1] == 'e' && source[start + 2] == 'f' {
            return 78
        }
    }

    if length == 4 {
        if ch0 == 'f' {
            if source[start + 1] == 'u' && source[start + 2] == 'n' && source[start + 3] == 'c' {
                return 7
            }
            if source[start + 1] == 'i' && source[start + 2] == 'l' && source[start + 3] == 'e' {
                return 81
            }
        }
        if ch0 == 'd' && source[start + 1] == 'u' && source[start + 2] == 'c' && source[start + 3] == 'k' {
            return 11
        }
        if ch0 == 'e' {
            if source[start + 1] == 'n' && source[start + 2] == 'u' && source[start + 3] == 'm' {
                return 14
            }
            if source[start + 1] == 'l' && source[start + 2] == 's' && source[start + 3] == 'e' {
                return 24
            }
        }
        if ch0 == 't' {
            if source[start + 1] == 'r' && source[start + 2] == 'u' && source[start + 3] == 'e' {
                return 44
            }
            if source[start + 1] == 'h' && source[start + 2] == 'i' && source[start + 3] == 's' {
                return 42
            }
            if source[start + 1] == 'y' && source[start + 2] == 'p' && source[start + 3] == 'e' {
                return 72
            }
        }
        if ch0 == 'b' && source[start + 1] == 'a' && source[start + 2] == 's' && source[start + 3] == 'e' {
            return 43
        }
        if ch0 == 'n' && source[start + 1] == 'u' && source[start + 2] == 'l' && source[start + 3] == 'l' {
            return 46
        }
        if ch0 == 'c' && source[start + 1] == 'a' && source[start + 2] == 's' && source[start + 3] == 'e' {
            return 33
        }
        if ch0 == 'l' && source[start + 1] == 'o' && source[start + 2] == 'c' && source[start + 3] == 'k' {
            return 80
        }
        if ch0 == 'i' && source[start + 1] == 'n' && source[start + 2] == 'i' && source[start + 3] == 't' {
            return 77
        }
        if ch0 == 'w' {
            if source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'n' {
                return 54
            }
            if source[start + 1] == 'i' && source[start + 2] == 't' && source[start + 3] == 'h' {
                return 71
            }
        }
        if ch0 == 'm' && source[start + 1] == 'u' && source[start + 2] == 's' && source[start + 3] == 't' {
            return 20
        }
    }

    if length == 5 {
        if ch0 == 'c' {
            if source[start + 1] == 'l' && source[start + 2] == 'a' && source[start + 3] == 's' && source[start + 4] == 's' {
                return 8
            }
            if source[start + 1] == 'o' && source[start + 2] == 'n' && source[start + 3] == 's' && source[start + 4] == 't' {
                return 21
            }
            if source[start + 1] == 'a' && source[start + 2] == 't' && source[start + 3] == 'c' && source[start + 4] == 'h' {
                return 39
            }
        }
        if ch0 == 'u' {
            if source[start + 1] == 'n' && source[start + 2] == 'i' && source[start + 3] == 'o' && source[start + 4] == 'n' {
                return 12
            }
            if source[start + 1] == 's' && source[start + 2] == 'i' && source[start + 3] == 'n' && source[start + 4] == 'g' {
                return 16
            }
        }
        if ch0 == 't' && source[start + 1] == 'h' && source[start + 2] == 'r' && source[start + 3] == 'o' && source[start + 4] == 'w' {
            return 37
        }
        if ch0 == 'w' {
            if source[start + 1] == 'h' && source[start + 2] == 'i' && source[start + 3] == 'l' && source[start + 4] == 'e' {
                return 27
            }
            if source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'e' {
                return 53
            }
        }
        if ch0 == 'y' && source[start + 1] == 'i' && source[start + 2] == 'e' && source[start + 3] == 'l' && source[start + 4] == 'd' {
            return 30
        }
        if ch0 == 'm' && source[start + 1] == 'a' && source[start + 2] == 't' && source[start + 3] == 'c' && source[start + 4] == 'h' {
            return 31
        }
        if ch0 == 'b' && source[start + 1] == 'r' && source[start + 2] == 'e' && source[start + 3] == 'a' && source[start + 4] == 'k' {
            return 35
        }
        if ch0 == 'f' && source[start + 1] == 'a' && source[start + 2] == 'l' && source[start + 3] == 's' && source[start + 4] == 'e' {
            return 45
        }
        if ch0 == 'a' {
            if source[start + 1] == 's' && source[start + 2] == 'y' && source[start + 3] == 'n' && source[start + 4] == 'c' {
                return 68
            }
            if source[start + 1] == 'w' && source[start + 2] == 'a' && source[start + 3] == 'i' && source[start + 4] == 't' {
                return 69
            }
            if source[start + 1] == 'l' && source[start + 2] == 'l' && source[start + 3] == 'o' && source[start + 4] == 'c' {
                return 143
            }
            if source[start + 1] == 'l' && source[start + 2] == 'l' && source[start + 3] == 'o' && source[start + 4] == 'w' {
                return 144
            }
        }
        if ch0 == 'p' && source[start + 1] == 'r' && source[start + 2] == 'i' && source[start + 3] == 'n' && source[start + 4] == 't' {
            return 52
        }
    }

    if length == 6 {
        if ch0 == 's' {
            if source[start + 1] == 't' && source[start + 2] == 'r' && source[start + 3] == 'u' && source[start + 4] == 'c' && source[start + 5] == 't' {
                return 9
            }
            if source[start + 1] == 'w' && source[start + 2] == 'i' && source[start + 3] == 't' && source[start + 4] == 'c' && source[start + 5] == 'h' {
                return 32
            }
            if source[start + 1] == 'i' && source[start + 2] == 'z' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
                return 51
            }
            if source[start + 1] == 'e' && source[start + 2] == 'a' && source[start + 3] == 'l' && source[start + 4] == 'e' && source[start + 5] == 'd' {
                return 61
            }
            if source[start + 1] == 't' && source[start + 2] == 'a' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'c' {
                return 63
            }
            if source[start + 1] == 'c' && source[start + 2] == 'o' && source[start + 3] == 'p' && source[start + 4] == 'e' && source[start + 5] == 'd' {
                return 147
            }
        }
        if ch0 == 'u' && source[start + 1] == 'n' && source[start + 2] == 's' && source[start + 3] == 'a' && source[start + 4] == 'f' && source[start + 5] == 'e' {
            return 146
        }
        if ch0 == 'r' {
            if source[start + 1] == 'e' && source[start + 2] == 'c' && source[start + 3] == 'o' && source[start + 4] == 'r' && source[start + 5] == 'd' {
                return 13
            }
            if source[start + 1] == 'e' && source[start + 2] == 't' && source[start + 3] == 'u' && source[start + 4] == 'r' && source[start + 5] == 'n' {
                return 29
            }
        }
        if ch0 == 'i' && source[start + 1] == 'm' && source[start + 2] == 'p' && source[start + 3] == 'o' && source[start + 4] == 'r' && source[start + 5] == 't' {
            return 17
        }
        if ch0 == 't' && source[start + 1] == 'y' && source[start + 2] == 'p' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
            return 49
        }
        if ch0 == 'n' && source[start + 1] == 'a' && source[start + 2] == 'm' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
            return 50
        }
        if ch0 == 'p' {
            if source[start + 1] == 'u' && source[start + 2] == 'b' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' {
                return 64
            }
            if source[start + 1] == 'a' && source[start + 2] == 'r' && source[start + 3] == 'a' && source[start + 4] == 'm' && source[start + 5] == 's' {
                return 82
            }
        }
        if ch0 == 'a' && source[start + 1] == 's' && source[start + 2] == 's' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 't' {
            return 74
        }
    }

    if length == 7 {
        if ch0 == 'p' {
            if source[start + 1] == 'a' && source[start + 2] == 'c' && source[start + 3] == 'k' && source[start + 4] == 'a' && source[start + 5] == 'g' && source[start + 6] == 'e' {
                return 18
            }
            if source[start + 1] == 'a' && source[start + 2] == 'r' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'a' && source[start + 6] == 'l' {
                return 62
            }
            if source[start + 1] == 'r' && source[start + 2] == 'i' && source[start + 3] == 'v' && source[start + 4] == 'a' && source[start + 5] == 't' && source[start + 6] == 'e' {
                return 65
            }
        }
        if ch0 == 'f' {
            if source[start + 1] == 'o' && source[start + 2] == 'r' && source[start + 3] == 'e' && source[start + 4] == 'a' && source[start + 5] == 'c' && source[start + 6] == 'h' {
                return 26
            }
            if source[start + 1] == 'i' && source[start + 2] == 'n' && source[start + 3] == 'a' && source[start + 4] == 'l' && source[start + 5] == 'l' && source[start + 6] == 'y' {
                return 40
            }
        }
        if ch0 == 'd' && source[start + 1] == 'e' && source[start + 2] == 'f' && source[start + 3] == 'a' && source[start + 4] == 'u' && source[start + 5] == 'l' && source[start + 6] == 't' {
            return 34
        }
        if ch0 == 'v' && source[start + 1] == 'i' && source[start + 2] == 'r' && source[start + 3] == 't' && source[start + 4] == 'u' && source[start + 5] == 'a' && source[start + 6] == 'l' {
            return 58
        }
        if ch0 == 'c' && source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'c' && source[start + 4] == 'k' && source[start + 5] == 'e' && source[start + 6] == 'd' {
            return 83
        }
        if ch0 == 'n' && source[start + 1] == 'e' && source[start + 2] == 'w' && source[start + 3] == 't' && source[start + 4] == 'y' && source[start + 5] == 'p' && source[start + 6] == 'e' {
            return 87
        }
    }

    if length == 8 {
        if ch0 == 'r' {
            if source[start + 1] == 'e' && source[start + 2] == 'a' && source[start + 3] == 'd' && source[start + 4] == 'o' && source[start + 5] == 'n' && source[start + 6] == 'l' && source[start + 7] == 'y' {
                return 22
            }
            if source[start + 1] == 'e' && source[start + 2] == 'q' && source[start + 3] == 'u' && source[start + 4] == 'i' && source[start + 5] == 'r' && source[start + 6] == 'e' && source[start + 7] == 'd' {
                return 76
            }
        }
        if ch0 == 'c' && source[start + 1] == 'o' && source[start + 2] == 'n' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'n' && source[start + 6] == 'u' && source[start + 7] == 'e' {
            return 36
        }
        if ch0 == 'a' && source[start + 1] == 'b' && source[start + 2] == 's' && source[start + 3] == 't' && source[start + 4] == 'r' && source[start + 5] == 'a' && source[start + 6] == 'c' && source[start + 7] == 't' {
            return 60
        }
        if ch0 == 'i' {
            if source[start + 1] == 'n' && source[start + 2] == 't' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 'n' && source[start + 6] == 'a' && source[start + 7] == 'l' {
                return 66
            }
            if source[start + 1] == 'm' && source[start + 2] == 'p' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' && source[start + 6] == 'i' && source[start + 7] == 't' {
                return 85
            }
        }
        if ch0 == 'e' && source[start + 1] == 'x' && source[start + 2] == 'p' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' && source[start + 6] == 'i' && source[start + 7] == 't' {
            return 86
        }
        if ch0 == 'o' {
            if source[start + 1] == 'p' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'a' && source[start + 5] == 't' && source[start + 6] == 'o' && source[start + 7] == 'r' {
                return 75
            }
            if source[start + 1] == 'v' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'r' && source[start + 5] == 'i' && source[start + 6] == 'd' && source[start + 7] == 'e' {
                return 59
            }
        }
    }

    if length == 9 {
        if ch0 == 'i' {
            if source[start + 1] == 'n' && source[start + 2] == 't' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 'f' && source[start + 6] == 'a' && source[start + 7] == 'c' && source[start + 8] == 'e' {
                return 10
            }
            if source[start + 1] == 'm' && source[start + 2] == 'm' && source[start + 3] == 'u' && source[start + 4] == 't' && source[start + 5] == 'a' && source[start + 6] == 'b' && source[start + 7] == 'l' && source[start + 8] == 'e' {
                return 70
            }
        }
        if ch0 == 'n' && source[start + 1] == 'a' && source[start + 2] == 'm' && source[start + 3] == 'e' && source[start + 4] == 's' && source[start + 5] == 'p' && source[start + 6] == 'a' && source[start + 7] == 'c' && source[start + 8] == 'e' {
            return 15
        }
        if ch0 == 'p' && source[start + 1] == 'r' && source[start + 2] == 'o' && source[start + 3] == 't' && source[start + 4] == 'e' && source[start + 5] == 'c' && source[start + 6] == 't' && source[start + 7] == 'e' && source[start + 8] == 'd' {
            return 67
        }
        if ch0 == 'u' && source[start + 1] == 'n' && source[start + 2] == 'c' && source[start + 3] == 'h' && source[start + 4] == 'e' && source[start + 5] == 'c' && source[start + 6] == 'k' && source[start + 7] == 'e' && source[start + 8] == 'd' {
            return 84
        }
    }

    if length == 10 {
        if ch0 == 's' && source[start + 1] == 't' && source[start + 2] == 'a' && source[start + 3] == 'c' && source[start + 4] == 'k' && source[start + 5] == 'a' && source[start + 6] == 'l' && source[start + 7] == 'l' && source[start + 8] == 'o' && source[start + 9] == 'c' {
            return 145
        }
    }

    return 0
}

func IsWhitespaceExceptNewline(ch: char): bool {
    return char.IsWhiteSpace(ch) && ch != '\n' && ch != '\r'
}

func IsIdentifierStart(ch: char): bool {
    return ch == '_' || char.IsLetter(ch)
}

func IsIdentifierPart(ch: char): bool {
    return ch == '_' || char.IsLetterOrDigit(ch)
}

func IsDigit(ch: char): bool {
    return char.IsDigit(ch)
}

func IsHexDigit(ch: char): bool {
    return IsDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}

func TypeReferenceCanonicalTextCore(source: string, nodes: TypeReferenceCanonicalTable, root: int): string {
    if root < 0 || root >= nodes.Kinds.Length {
        return "?"
    }

    kind := nodes.Kinds[root]
    if kind == 0 {
        return source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root])
    }

    if kind == 1 {
        builder := new StringBuilder(32)
        builder.Append(source.Substring(nodes.ValueStarts[root], nodes.ValueLengths[root]))
        builder.Append('<')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        builder.Append('>')
        return builder.ToString()
    }

    if kind == 2 {
        return TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "[]"
    }

    if kind == 3 {
        return TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]]) + "?"
    }

    if kind == 4 {
        builder := new StringBuilder(32)
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append('|')
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[run + i]))
            i = i + 1
        }

        return builder.ToString()
    }

    if kind == 5 {
        return "&" + TypeReferenceCanonicalTextCore(source, nodes, nodes.ChildIndices[nodes.ChildStart[root]])
    }

    if kind == 6 {
        builder := new StringBuilder(32)
        builder.Append('(')
        run := nodes.ChildStart[root]
        i := 0
        while i < nodes.ChildCount[root] {
            if i > 0 {
                builder.Append(',')
            }

            elem := nodes.ChildIndices[run + i]
            if nodes.Kinds[elem] == 7 {
                elem = nodes.ChildIndices[nodes.ChildStart[elem]]
            }

            builder.Append(TypeReferenceCanonicalTextCore(source, nodes, elem))
            i = i + 1
        }

        builder.Append(')')
        return builder.ToString()
    }

    return "?"
}

func TypeReferenceTupleElementNamesCore(source: string, nodes: TypeReferenceCanonicalTable, root: int, names: TypeReferenceTupleNameTable): int {
    if root < 0 || root >= nodes.Kinds.Length || nodes.Kinds[root] != 6 || nodes.ChildCount[root] == 0 {
        return 0
    }

    run := nodes.ChildStart[root]
    first := nodes.ChildIndices[run]
    if nodes.Kinds[first] != 7 {
        return 0
    }

    i := 0
    while i < nodes.ChildCount[root] {
        elem := nodes.ChildIndices[run + i]
        if nodes.Kinds[elem] != 7 {
            return -1
        }

        names.Names[i] = source.Substring(nodes.ValueStarts[elem], nodes.ValueLengths[elem])
        i = i + 1
    }

    return nodes.ChildCount[root]
}

func EmitTypeReferenceNode(st: ParserState, nodes: ParserNodeTable, kind: int, nameStart: int, nameLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st.NodeCursor
    nodes.Kinds[id] = kind
    nodes.ValueStarts[id] = nameStart
    nodes.ValueLengths[id] = nameLength
    nodes.ChildStart[id] = childStart
    nodes.ChildCount[id] = childCount
    nodes.SpanStarts[id] = spanStart
    nodes.SpanLengths[id] = spanLength
    st.NodeCursor = id + 1
    return id
}

func AppendTypeReferenceChild(st: ParserState, outChildIndices: ParserChildIndexTable, childId: int): int {
    slot := st.ChildCursor
    outChildIndices.Indices[slot] = childId
    st.ChildCursor = slot + 1
    return slot
}

func ConsumeGreaterForTypeNodeCore(tokens: ParserTokenTable, count: int, st: ParserState): int {
    if st.SplitGreaterDepth > 0 {
        st.SplitGreaterDepth = st.SplitGreaterDepth - 1
        return st.OwedGreaterByteEnd
    }

    pos := st.Pos
    if pos < count && tokens.Kinds[pos] == 102 {
        st.Pos = pos + 1
        return tokens.Starts[pos] + tokens.ValueLengths[pos]
    }

    if pos < count && tokens.Kinds[pos] == 112 {
        st.Pos = pos + 1
        st.SplitGreaterDepth = st.SplitGreaterDepth + 1
        st.OwedGreaterByteEnd = tokens.Starts[pos] + 2
        return tokens.Starts[pos] + 1
    }

    return -1
}

func ParseBaseTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    if depth > 64 {
        return -1
    }

    pos := st.Pos
    if pos >= count {
        return -1
    }

    // ByRef `&T`: `&` prefixing a postfix type. A byref can appear wherever a base type can
    // (a union arm, a generic argument). depth+1 bounds the degenerate `& & T` chain.
    if tokens.Kinds[pos] == 107 {
        ampStart := tokens.Starts[pos]
        st.Pos = pos + 1
        inner := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if inner < 0 {
            return -1
        }

        spanEnd := nodes.SpanStarts[inner] + nodes.SpanLengths[inner]
        childRunStart := st.ChildCursor
        AppendTypeReferenceChild(st, outChildIndices, inner)
        return EmitTypeReferenceNode(st, nodes, 5, -1, 0, childRunStart, 1, ampStart, spanEnd - ampStart)
    }

    // Tuple type `(T0, T1, ...)` (TupleTypeReference -> kind 6): a `(` introducing a comma-separated list of at
    // least TWO postfix/union element types, closed by `)`. A single `(T)` is not a tuple (no comma) -> refuse.
    // Variable arity via the LIFO arg-stack, exactly like the generic argument list.
    //
    // NAMED elements `(x: int, y: int)` are modelled ALL-OR-NOTHING (the production parser errors on partial
    // naming -- probe-pinned): each `Identifier :` prefix wraps its element type in a NamedTupleElement node
    // (kind 7, the element NAME in the name slot, ONE child = the element type). The tuple's children are then
    // either all kind-7 wrappers or all bare element types. Names are ERASED from canonicals (tuple identity is
    // positional -- .NET semantics); the host extracts them for the emitter's name->ItemN member mapping.
    if tokens.Kinds[pos] == 127 {
        tupleTypeStart := tokens.Starts[pos]
        st.Pos = pos + 1
        tupleArgBase := st.ArgStackTop

        // namedForm: -1 undecided, 1 named, 0 positional -- decided by the FIRST element, enforced after.
        namedForm := 0 - 1
        if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
            namedForm = 1
        }

        firstElemNameStart := 0 - 1
        firstElemNameLength := 0
        if namedForm == 1 {
            firstElemNameStart = tokens.Starts[st.Pos]
            firstElemNameLength = tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 2
        }
        firstElem := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if firstElem < 0 {
            st.ArgStackTop = tupleArgBase
            return -1
        }
        if namedForm == 1 {
            firstWrapRun := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, firstElem)
            firstElem = EmitTypeReferenceNode(st, nodes, 7, firstElemNameStart, firstElemNameLength, firstWrapRun, 1, firstElemNameStart, nodes.SpanStarts[firstElem] + nodes.SpanLengths[firstElem] - firstElemNameStart)
        } else {
            namedForm = 0
        }

        argStack.Values[st.ArgStackTop] = firstElem
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 134 {
            st.ArgStackTop = tupleArgBase
            return -1
        }

        while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            elemNameStart := 0 - 1
            elemNameLength := 0
            if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
                if namedForm == 0 {
                    st.ArgStackTop = tupleArgBase
                    return -1
                }
                elemNameStart = tokens.Starts[st.Pos]
                elemNameLength = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 2
            } else if namedForm == 1 {
                st.ArgStackTop = tupleArgBase
                return -1
            }
            nextElem := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
            if nextElem < 0 {
                st.ArgStackTop = tupleArgBase
                return -1
            }
            if namedForm == 1 {
                wrapRun := st.ChildCursor
                AppendTypeReferenceChild(st, outChildIndices, nextElem)
                nextElem = EmitTypeReferenceNode(st, nodes, 7, elemNameStart, elemNameLength, wrapRun, 1, elemNameStart, nodes.SpanStarts[nextElem] + nodes.SpanLengths[nextElem] - elemNameStart)
            }

            argStack.Values[st.ArgStackTop] = nextElem
            st.ArgStackTop = st.ArgStackTop + 1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            st.ArgStackTop = tupleArgBase
            return -1
        }

        tupleRightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        tupleChildCount := st.ArgStackTop - tupleArgBase
        tupleChildRunStart := st.ChildCursor
        tupleElemIdx := tupleArgBase
        while tupleElemIdx < st.ArgStackTop {
            AppendTypeReferenceChild(st, outChildIndices, argStack.Values[tupleElemIdx])
            tupleElemIdx = tupleElemIdx + 1
        }
        st.ArgStackTop = tupleArgBase

        return EmitTypeReferenceNode(st, nodes, 6, -1, 0, tupleChildRunStart, tupleChildCount, tupleTypeStart, tupleRightParenEnd - tupleTypeStart)
    }

    if tokens.Kinds[pos] != 0 {
        return -1
    }

    nameStart := tokens.Starts[pos]
    nameEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
    pos = pos + 1

    while pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
        nameEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
        pos = pos + 2
    }

    st.Pos = pos

    if pos < count && tokens.Kinds[pos] == 100 {
        st.Pos = pos + 1
        argBase := st.ArgStackTop

        firstArg := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
        if firstArg < 0 {
            return -1
        }

        argStack.Values[st.ArgStackTop] = firstArg
        st.ArgStackTop = st.ArgStackTop + 1

        while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            nextArg := ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth + 1)
            if nextArg < 0 {
                return -1
            }

            argStack.Values[st.ArgStackTop] = nextArg
            st.ArgStackTop = st.ArgStackTop + 1
        }

        greaterEnd := ConsumeGreaterForTypeNodeCore(tokens, count, st)
        if greaterEnd < 0 {
            return -1
        }

        childCount := st.ArgStackTop - argBase
        childRunStart := st.ChildCursor
        a := argBase
        while a < st.ArgStackTop {
            AppendTypeReferenceChild(st, outChildIndices, argStack.Values[a])
            a = a + 1
        }
        st.ArgStackTop = argBase

        return EmitTypeReferenceNode(st, nodes, 1, nameStart, nameEnd - nameStart, childRunStart, childCount, nameStart, greaterEnd - nameStart)
    }

    return EmitTypeReferenceNode(st, nodes, 0, nameStart, nameEnd - nameStart, -1, 0, nameStart, nameEnd - nameStart)
}

func ParsePostfixTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    baseNode := ParseBaseTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
    if baseNode < 0 {
        return -1
    }

    matched := true
    while matched {
        pos := st.Pos

        if pos + 1 < count && tokens.Kinds[pos] == 131 && tokens.Kinds[pos + 1] == 132 {
            spanStart := nodes.SpanStarts[baseNode]
            rightBracketEnd := tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 2, -1, 0, childRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st.Pos = pos + 2
        } else if pos + 1 < count && tokens.Kinds[pos] == 119 && tokens.Kinds[pos + 1] == 132 {
            spanStart := nodes.SpanStarts[baseNode]
            questionBracketStart := tokens.Starts[pos]
            rightBracketEnd := tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]

            nullableRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            nullableNode := EmitTypeReferenceNode(st, nodes, 3, -1, 0, nullableRunStart, 1, spanStart, (questionBracketStart + 1) - spanStart)

            arrayRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, nullableNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 2, -1, 0, arrayRunStart, 1, spanStart, rightBracketEnd - spanStart)
            st.Pos = pos + 2
        } else if pos < count && tokens.Kinds[pos] == 115 {
            spanStart := nodes.SpanStarts[baseNode]
            questionEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, outChildIndices, baseNode)
            baseNode = EmitTypeReferenceNode(st, nodes, 3, -1, 0, childRunStart, 1, spanStart, questionEnd - spanStart)
            st.Pos = pos + 1
        } else {
            matched = false
        }
    }

    return baseNode
}

func ParseUnionTypeReferenceNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserNodeTable, outChildIndices: ParserChildIndexTable, depth: int): int {
    firstArm := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
    if firstArm < 0 {
        return -1
    }

    if !(st.Pos < count && tokens.Kinds[st.Pos] == 108) {
        return firstArm
    }

    argBase := st.ArgStackTop
    argStack.Values[st.ArgStackTop] = firstArm
    st.ArgStackTop = st.ArgStackTop + 1

    while st.Pos < count && tokens.Kinds[st.Pos] == 108 {
        st.Pos = st.Pos + 1
        nextArm := ParsePostfixTypeReferenceNodeCore(tokens, count, st, argStack, nodes, outChildIndices, depth)
        if nextArm < 0 {
            return -1
        }

        argStack.Values[st.ArgStackTop] = nextArm
        st.ArgStackTop = st.ArgStackTop + 1
    }

    lastArm := argStack.Values[st.ArgStackTop - 1]
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendTypeReferenceChild(st, outChildIndices, argStack.Values[a])
        a = a + 1
    }
    st.ArgStackTop = argBase

    spanStart := nodes.SpanStarts[firstArm]
    spanEnd := nodes.SpanStarts[lastArm] + nodes.SpanLengths[lastArm]
    return EmitTypeReferenceNode(st, nodes, 4, -1, 0, childRunStart, childCount, spanStart, spanEnd - spanStart)
}

func EmitExpressionNode(st: ParserState, nodes: ParserExpressionNodeTable, kind: int, valueStart: int, valueLength: int, childStart: int, childCount: int, spanStart: int, spanLength: int): int {
    id := st.NodeCursor
    nodes.Kinds[id] = kind
    nodes.ValueStarts[id] = valueStart
    nodes.ValueLengths[id] = valueLength
    nodes.ChildStart[id] = childStart
    nodes.ChildCount[id] = childCount
    nodes.SpanStarts[id] = spanStart
    nodes.SpanLengths[id] = spanLength
    st.NodeCursor = id + 1
    return id
}

func AppendExpressionChild(st: ParserState, children: ParserChildIndexTable, childId: int): int {
    slot := st.ChildCursor
    children.Indices[slot] = childId
    st.ChildCursor = slot + 1
    return slot
}

func ParseArrayLiteralExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    start := st.Pos
    arrayStart := tokens.Starts[start]
    st.Pos = start + 1
    argBase := st.ArgStackTop

    if st.Pos < count && tokens.Kinds[st.Pos] != 132 {
        parsing := true
        while parsing {
            element := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if element < 0 {
                st.ArgStackTop = argBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = element
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 132 {
                    st.ArgStackTop = argBase
                    return -1
                }
            } else {
                parsing = false
            }
        }
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 132 {
        st.ArgStackTop = argBase
        return -1
    }

    arrayEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }
    st.ArgStackTop = argBase

    return EmitExpressionNode(st, nodes, 58, -1, 0, childRunStart, childCount, arrayStart, arrayEnd - arrayStart)
}

func ParseExpressionTypeReferenceNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    typeNodes := new ParserNodeTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, nodes.SpanStarts, nodes.SpanLengths)
    return ParseUnionTypeReferenceNodeCore(tokens, count, st, argStack, typeNodes, children, depth)
}

func IsExpressionStartKind(kind: int): bool {
    if kind >= 0 && kind <= 6 {
        return true
    }
    return kind == 20 || kind == 31 || kind == 34 || kind == 37 || kind == 41 || kind == 42 || kind == 43 || kind == 44 || kind == 45 || kind == 46 || kind == 49 || kind == 50 || kind == 51 || kind == 69 || kind == 70 || kind == 83 || kind == 84 || kind == 88 || kind == 89 || kind == 106 || kind == 110 || kind == 113 || kind == 114 || kind == 127 || kind == 131 || kind == 143 || kind == 145
}

func IsGenericCallTypeArgs(tokens: ParserTokenTable, count: int, lessPos: int): bool {
    i := lessPos + 1
    depth := 1
    while i < count {
        k := tokens.Kinds[i]
        if k == 0 || k == 115 || k == 124 || k == 134 || k == 131 || k == 132 {
            i = i + 1
        } else if k == 100 {
            depth = depth + 1
            i = i + 1
        } else if k == 102 {
            depth = depth - 1
            i = i + 1
            if depth == 0 {
                return i < count && tokens.Kinds[i] == 127
            }
        } else if k == 112 {
            depth = depth - 2
            i = i + 1
            if depth == 0 {
                return i < count && tokens.Kinds[i] == 127
            }
            if depth < 0 {
                return false
            }
        } else {
            return false
        }
    }
    return false
}

func ParseMatchPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    return ParseOrPatternNode(tokens, count, st, argStack, nodes, children, depth)
}

func ParseOrPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    left := ParseAndPatternNode(tokens, count, st, argStack, nodes, children, depth)
    if left < 0 {
        return -1
    }
    while st.Pos < count && tokens.Kinds[st.Pos] == 56 {
        st.Pos = st.Pos + 1
        right := ParseAndPatternNode(tokens, count, st, argStack, nodes, children, depth)
        if right < 0 {
            return -1
        }
        orChildRun := st.ChildCursor
        AppendExpressionChild(st, children, left)
        AppendExpressionChild(st, children, right)
        orSpanStart := nodes.SpanStarts[left]
        orSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
        left = EmitExpressionNode(st, nodes, 34, -1, 0, orChildRun, 2, orSpanStart, orSpanEnd - orSpanStart)
    }
    return left
}

func ParseAndPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    left := ParseNotPatternNode(tokens, count, st, argStack, nodes, children, depth)
    if left < 0 {
        return -1
    }
    while st.Pos < count && tokens.Kinds[st.Pos] == 55 {
        st.Pos = st.Pos + 1
        right := ParseNotPatternNode(tokens, count, st, argStack, nodes, children, depth)
        if right < 0 {
            return -1
        }
        andChildRun := st.ChildCursor
        AppendExpressionChild(st, children, left)
        AppendExpressionChild(st, children, right)
        andSpanStart := nodes.SpanStarts[left]
        andSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
        left = EmitExpressionNode(st, nodes, 33, -1, 0, andChildRun, 2, andSpanStart, andSpanEnd - andSpanStart)
    }
    return left
}

func ParseNotPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }
    if st.Pos < count && tokens.Kinds[st.Pos] == 57 {
        notStart := tokens.Starts[st.Pos]
        st.Pos = st.Pos + 1
        inner := ParseNotPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if inner < 0 {
            return -1
        }
        notChildRun := st.ChildCursor
        AppendExpressionChild(st, children, inner)
        notSpanEnd := nodes.SpanStarts[inner] + nodes.SpanLengths[inner]
        return EmitExpressionNode(st, nodes, 35, -1, 0, notChildRun, 1, notStart, notSpanEnd - notStart)
    }
    return ParseRelationalPatternNode(tokens, count, st, argStack, nodes, children, depth)
}

func ParseRelationalPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if st.Pos < count {
        relTok := tokens.Kinds[st.Pos]
        if relTok == 100 || relTok == 101 || relTok == 102 || relTok == 103 {
            relOpStart := tokens.Starts[st.Pos]
            relOpLen := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            relOperand := ParsePrimaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if relOperand < 0 {
                return -1
            }
            relChildRun := st.ChildCursor
            AppendExpressionChild(st, children, relOperand)
            relSpanEnd := nodes.SpanStarts[relOperand] + nodes.SpanLengths[relOperand]
            return EmitExpressionNode(st, nodes, 32, relOpStart, relOpLen, relChildRun, 1, relOpStart, relSpanEnd - relOpStart)
        }
    }
    // The non-relational pattern leaf is a POSTFIX expression (not just a primary): this is what lets an enum
    // constant `Enum.Member` parse as a MemberAccess (kind 8) in pattern position. A
    // literal/identifier still parses as before (no postfix to apply); a call/index parses but the emitter declines
    // it as a non-constant pattern.
    leaf := ParsePostfixExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    if leaf < 0 {
        return -1
    }

    // Union-case PROPERTY pattern: `<Union.Case> { bind0, bind1, ... }` -> UnionCasePattern (kind 37), children
    // [memberAccessNode, bind0 (Identifier kind 6), bind1, ...]. Fires only when the leaf is a qualified member
    // access (kind 8, e.g. `Result.Success`) immediately followed by `{` (129). Each binding is a BARE identifier
    // naming a case field; `,` (134) separates and `}` (130) closes. A renamed/nested/positional sub-pattern
    // (`{ field: <pat> }`) declines here (the `:` after a binding is neither `,` nor `}` -> -1), so required
    // columnar emission rejects the program until that source shape is modeled. The emitter (case 37) resolves the
    // case, `isinst`-tests it, and binds each named field to a local.
    if nodes.Kinds[leaf] == 8 && st.Pos < count && tokens.Kinds[st.Pos] == 129 {
        st.Pos = st.Pos + 1
        caseArgBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = leaf
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
            if tokens.Kinds[st.Pos] != 0 {
                st.ArgStackTop = caseArgBase
                return -1
            }
            bindStart := tokens.Starts[st.Pos]
            bindLen := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            bindNode := EmitExpressionNode(st, nodes, 6, bindStart, bindLen, -1, 0, bindStart, bindLen)
            argStack.Values[st.ArgStackTop] = bindNode
            st.ArgStackTop = st.ArgStackTop + 1
            if st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 134 {
                    st.ArgStackTop = caseArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
            }
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
            st.ArgStackTop = caseArgBase
            return -1
        }
        caseEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        caseChildCount := st.ArgStackTop - caseArgBase
        caseChildRun := st.ChildCursor
        caseArg := caseArgBase
        while caseArg < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[caseArg])
            caseArg = caseArg + 1
        }
        st.ArgStackTop = caseArgBase
        caseSpanStart := nodes.SpanStarts[leaf]
        return EmitExpressionNode(st, nodes, 37, -1, 0, caseChildRun, caseChildCount, caseSpanStart, caseEnd - caseSpanStart)
    }

    // Anonymous-union TYPE-BINDING pattern: `int number => ...` / `string text => ...`.
    // The first token has already parsed as an identifier leaf; when a second bare identifier follows and
    // the pattern is immediately terminated by `=>` or `when`, reinterpret the first identifier as a SIMPLE
    // type root and the second as the arm binding. Composed type-binding patterns remain deliberately
    // under-accepted until the emitter models them.
    if nodes.Kinds[leaf] == 6 && st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0
        && (tokens.Kinds[st.Pos + 1] == 120 || tokens.Kinds[st.Pos + 1] == 54) {
        bindStart := tokens.Starts[st.Pos]
        bindLen := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        typeNode := EmitExpressionNode(st, nodes, 0, nodes.ValueStarts[leaf], nodes.ValueLengths[leaf], -1, 0, nodes.SpanStarts[leaf], nodes.SpanLengths[leaf])
        bindNode := EmitExpressionNode(st, nodes, 6, bindStart, bindLen, -1, 0, bindStart, bindLen)
        bindingChildRun := st.ChildCursor
        AppendExpressionChild(st, children, typeNode)
        AppendExpressionChild(st, children, bindNode)
        bindingSpanEnd := bindStart + bindLen
        return EmitExpressionNode(st, nodes, 61, -1, 0, bindingChildRun, 2, nodes.SpanStarts[leaf], bindingSpanEnd - nodes.SpanStarts[leaf])
    }

    return leaf
}

func ParsePrimaryExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    if pos >= count {
        return -1
    }

    kind := tokens.Kinds[pos]
    tokenStart := tokens.Starts[pos]
    tokenLength := tokens.ValueLengths[pos]

    if kind == 1 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 0, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 2 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 1, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 3 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 2, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 4 || kind == 5 || kind == 6 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 3, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 44 || kind == 45 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 4, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 46 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 5, -1, 0, -1, 0, tokenStart, tokenLength)
    }
    if kind == 131 {
        return ParseArrayLiteralExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    }
    if kind == 143 {
        st.Pos = pos + 1
        return ParsePrimaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
    }
    if kind == 0 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, 6, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }
    if kind == 49 {
        typeOfStart := tokenStart
        st.Pos = pos + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }
        st.Pos = st.Pos + 1
        st.SplitGreaterDepth = 0
        typeRoot := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            return -1
        }
        typeOfEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        typeOfChildRun := st.ChildCursor
        AppendExpressionChild(st, children, typeRoot)
        return EmitExpressionNode(st, nodes, 55, -1, 0, typeOfChildRun, 1, typeOfStart, typeOfEnd - typeOfStart)
    }
    if kind == 50 {
        nameOfStart := tokenStart
        st.Pos = pos + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }
        st.Pos = st.Pos + 1
        target := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if target < 0 {
            return -1
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            return -1
        }
        nameOfEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        nameOfChildRun := st.ChildCursor
        AppendExpressionChild(st, children, target)
        return EmitExpressionNode(st, nodes, 62, -1, 0, nameOfChildRun, 1, nameOfStart, nameOfEnd - nameOfStart)
    }
    if kind == 83 || kind == 84 {
        checkedStart := tokenStart
        checkedLength := tokenLength
        st.Pos = pos + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }
        st.Pos = st.Pos + 1
        checkedValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if checkedValue < 0 {
            return -1
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            return -1
        }
        checkedEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        checkedChildRun := st.ChildCursor
        AppendExpressionChild(st, children, checkedValue)
        return EmitExpressionNode(st, nodes, 57, checkedStart, checkedLength, checkedChildRun, 1, checkedStart, checkedEnd - checkedStart)
    }
    if kind == 31 {
        // `match <value> { <pattern> => <result>, ... }` (Match token 31, Arrow `=>` token 120). MatchExpression
        // kind 18: children = [value, pat0, res0, pat1, res1, ...] (one value, then each case as a pattern/result
        // pair). The pattern is a PRIMARY expression (a literal or a bare identifier `_`/binding); the emitter
        // gates which pattern kinds it supports (richer patterns -- union-case/property/relational/`when` guards --
        // are parsed-or-refused here and decline at emit). A comma between cases is consumed when present.
        matchStart := tokenStart
        st.Pos = pos + 1
        matchArgBase := st.ArgStackTop

        matchValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if matchValue < 0 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        argStack.Values[st.ArgStackTop] = matchValue
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        st.Pos = st.Pos + 1

        matchCaseCount := 0
        while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
            // Parse the case PATTERN via the pattern-precedence chain (or > and > not > relational > primary,
            // see ParseMatchPatternNode). This yields a literal/identifier primary, a RelationalPattern (kind 32),
            // or an And/Or/Not combinator (kinds 33/34/35) over those. The `when` guard (below) then wraps it.
            matchPattern := ParseMatchPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if matchPattern < 0 {
                st.ArgStackTop = matchArgBase
                return -1
            }

            // `<pattern> when <guard>` -> GuardedPattern (kind 19): wrap the parsed pattern with its guard
            // condition so the emitter can test the pattern THEN the guard before taking the arm. The guard is a
            // full expression (it may reference a binding the pattern introduced). When absent, the bare pattern
            // node is used directly (no kind-19 wrapper), so existing match cases are unchanged.
            if st.Pos < count && tokens.Kinds[st.Pos] == 54 {
                st.Pos = st.Pos + 1
                matchGuard := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if matchGuard < 0 {
                    st.ArgStackTop = matchArgBase
                    return -1
                }
                guardChildRun := st.ChildCursor
                AppendExpressionChild(st, children, matchPattern)
                AppendExpressionChild(st, children, matchGuard)
                guardSpanStart := nodes.SpanStarts[matchPattern]
                guardSpanEnd := nodes.SpanStarts[matchGuard] + nodes.SpanLengths[matchGuard]
                matchPattern = EmitExpressionNode(st, nodes, 19, -1, 0, guardChildRun, 2, guardSpanStart, guardSpanEnd - guardSpanStart)
            }

            argStack.Values[st.ArgStackTop] = matchPattern
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos >= count || tokens.Kinds[st.Pos] != 120 {
                st.ArgStackTop = matchArgBase
                return -1
            }
            st.Pos = st.Pos + 1

            matchResult := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if matchResult < 0 {
                st.ArgStackTop = matchArgBase
                return -1
            }
            argStack.Values[st.ArgStackTop] = matchResult
            st.ArgStackTop = st.ArgStackTop + 1
            matchCaseCount = matchCaseCount + 1

            if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
            }
        }

        if matchCaseCount == 0 || st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
            st.ArgStackTop = matchArgBase
            return -1
        }
        matchEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        matchChildCount := st.ArgStackTop - matchArgBase
        matchChildRunStart := st.ChildCursor
        matchArg := matchArgBase
        while matchArg < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[matchArg])
            matchArg = matchArg + 1
        }
        st.ArgStackTop = matchArgBase

        return EmitExpressionNode(st, nodes, 18, -1, 0, matchChildRunStart, matchChildCount, matchStart, matchEnd - matchStart)
    }
    if kind == 41 {
        // `new <type> ( args )` -- the array/object construction form the dogfood kernels use
        // (e.g. new int[](length + 1)). COMPOSES the type kernel (the element/constructed type, via the
        // now-unified shared st + argStack) with the expression kernel (the positional constructor args).
        // NewExpression (kind 15): children = [typeRoot, arg0, arg1, ...]. The `new <type> { Field: value, ... }`
        // OBJECT INITIALIZER form is handled below (ObjectInitializerExpression kind 36). The `new <type>[size]`
        // sized-array form emits kind 15 with an ArrayTypeReference child and one length-expression child.
        // Target-typed `new ( ... )` and ref/out constructor arguments are still refused. Constructor named
        // arguments are recorded as kind-60 wrappers so lowering can bind supported names explicitly.
        newStart := tokenStart
        if pos + 1 < count && tokens.Kinds[pos + 1] == 129 {
            st.Pos = pos + 2
            anonArgBase := st.ArgStackTop
            while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = anonArgBase
                    return -1
                }
                anonNameStart := tokens.Starts[st.Pos]
                anonNameLen := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
                    st.ArgStackTop = anonArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                anonNameNode := EmitExpressionNode(st, nodes, 6, anonNameStart, anonNameLen, -1, 0, anonNameStart, anonNameLen)
                argStack.Values[st.ArgStackTop] = anonNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                anonValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if anonValue < 0 {
                    st.ArgStackTop = anonArgBase
                    return -1
                }
                argStack.Values[st.ArgStackTop] = anonValue
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
                st.ArgStackTop = anonArgBase
                return -1
            }
            anonEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            anonChildCount := st.ArgStackTop - anonArgBase
            anonChildRun := st.ChildCursor
            anonArg := anonArgBase
            while anonArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[anonArg])
                anonArg = anonArg + 1
            }
            st.ArgStackTop = anonArgBase
            return EmitExpressionNode(st, nodes, 59, -1, 0, anonChildRun, anonChildCount, newStart, anonEnd - newStart)
        }

        st.Pos = pos + 1
        if st.Pos < count && tokens.Kinds[st.Pos] == 127 {
            st.Pos = st.Pos + 1
            targetArgBase := st.ArgStackTop

            if st.Pos < count && tokens.Kinds[st.Pos] != 128 {
                if tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79 {
                    st.ArgStackTop = targetArgBase
                    return -1
                }

                targetFirstArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if targetFirstArg < 0 {
                    st.ArgStackTop = targetArgBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = targetFirstArg
                st.ArgStackTop = st.ArgStackTop + 1

                while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                    if st.Pos < count && (tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79) {
                        st.ArgStackTop = targetArgBase
                        return -1
                    }

                    targetNextArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                    if targetNextArg < 0 {
                        st.ArgStackTop = targetArgBase
                        return -1
                    }

                    argStack.Values[st.ArgStackTop] = targetNextArg
                    st.ArgStackTop = st.ArgStackTop + 1
                }
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                st.ArgStackTop = targetArgBase
                return -1
            }

            targetRightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            targetChildCount := st.ArgStackTop - targetArgBase
            targetChildRun := st.ChildCursor
            targetArg := targetArgBase
            while targetArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[targetArg])
                targetArg = targetArg + 1
            }
            st.ArgStackTop = targetArgBase
            return EmitExpressionNode(st, nodes, 63, -1, 0, targetChildRun, targetChildCount, newStart, targetRightParenEnd - newStart)
        }

        // The type kernel assumes splitGreaterDepth (st.SplitGreaterDepth) is 0 on entry (it is only set/cleared while
        // closing generics within a single type parse). A balanced type always leaves it 0, but reset it
        // explicitly before the call -- matching the function-signature kernel -- so the invariant never
        // relies on the caller's prior state. (st.ArgStackTop=argStackTop must NOT be reset here: the type's generic
        // args nest on the shared LIFO arg-stack above the enclosing expression's current base.)
        st.SplitGreaterDepth = 0
        typeRoot := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }

        if st.Pos < count && tokens.Kinds[st.Pos] == 131 {
            st.Pos = st.Pos + 1
            lengthExpression := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if lengthExpression < 0 {
                return -1
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 132 {
                return -1
            }
            arrayEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1

            arrayTypeChildRun := st.ChildCursor
            AppendExpressionChild(st, children, typeRoot)
            arrayTypeRoot := EmitExpressionNode(st, nodes, 2, -1, 0, arrayTypeChildRun, 1, nodes.SpanStarts[typeRoot], arrayEnd - nodes.SpanStarts[typeRoot])

            sizedArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = arrayTypeRoot
            st.ArgStackTop = st.ArgStackTop + 1
            argStack.Values[st.ArgStackTop] = lengthExpression
            st.ArgStackTop = st.ArgStackTop + 1

            sizedChildRun := st.ChildCursor
            sa := sizedArgBase
            while sa < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[sa])
                sa = sa + 1
            }
            st.ArgStackTop = sizedArgBase
            return EmitExpressionNode(st, nodes, 15, -1, 0, sizedChildRun, 2, newStart, arrayEnd - newStart)
        }

        // `new <type> { Field: value, ... }` -- OBJECT INITIALIZER (ObjectInitializerExpression kind 36): children
        // [typeRoot, name0, value0, name1, value1, ...] where each nameN is an Identifier node (kind 6, the field
        // name in its value span) and valueN is the field's value expression. Used to construct a fields-only
        // struct (the emitter zero-inits the value then assigns each named field). A `:` after the name is required.
        if st.Pos < count && tokens.Kinds[st.Pos] == 129 {
            st.Pos = st.Pos + 1
            objArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = typeRoot
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                fieldNameStart := tokens.Starts[st.Pos]
                fieldNameLen := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                fieldNameNode := EmitExpressionNode(st, nodes, 6, fieldNameStart, fieldNameLen, -1, 0, fieldNameStart, fieldNameLen)
                argStack.Values[st.ArgStackTop] = fieldNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                fieldVal := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if fieldVal < 0 {
                    st.ArgStackTop = objArgBase
                    return -1
                }
                argStack.Values[st.ArgStackTop] = fieldVal
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
                st.ArgStackTop = objArgBase
                return -1
            }
            objInitEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            objInitChildCount := st.ArgStackTop - objArgBase
            objInitChildRun := st.ChildCursor
            objArg := objArgBase
            while objArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[objArg])
                objArg = objArg + 1
            }
            st.ArgStackTop = objArgBase
            return EmitExpressionNode(st, nodes, 36, -1, 0, objInitChildRun, objInitChildCount, newStart, objInitEnd - newStart)
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            // `new <type>` with NEITHER `{ inits }` NOR `( args )` -- a BARE-NEW expression (kind 42,
            // children [typeRoot]): the brace-less construction form the pipeline accepts for union cases
            // (`new Color.Red`, `new Opt.None<int>`, `new Opt.None` adopting an expected type) -- fields
            // default. The emitter models ONLY union-case type roots for this node; every other bare-new
            // type (struct/BCL/array) declines there, so previously-unparseable programs stay declined.
            bareNewChildRun := st.ChildCursor
            AppendExpressionChild(st, children, typeRoot)
            bareNewEnd := nodes.SpanStarts[typeRoot] + nodes.SpanLengths[typeRoot]
            return EmitExpressionNode(st, nodes, 42, -1, 0, bareNewChildRun, 1, newStart, bareNewEnd - newStart)
        }
        st.Pos = st.Pos + 1

        argBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = typeRoot
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos < count && tokens.Kinds[st.Pos] != 128 {
            if tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79 {
                st.ArgStackTop = argBase
                return -1
            }

            firstArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if firstArg < 0 {
                st.ArgStackTop = argBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = firstArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                if st.Pos < count && (tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79) {
                    st.ArgStackTop = argBase
                    return -1
                }

                nextArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if nextArg < 0 {
                    st.ArgStackTop = argBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = nextArg
                st.ArgStackTop = st.ArgStackTop + 1
            }
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            st.ArgStackTop = argBase
            return -1
        }

        newRightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        newChildCount := st.ArgStackTop - argBase
        newChildRunStart := st.ChildCursor
        na := argBase
        while na < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[na])
            na = na + 1
        }
        st.ArgStackTop = argBase
        newCall := EmitExpressionNode(st, nodes, 15, -1, 0, newChildRunStart, newChildCount, newStart, newRightParenEnd - newStart)

        if st.Pos < count && tokens.Kinds[st.Pos] == 129 {
            st.Pos = st.Pos + 1
            initArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = newCall
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = initArgBase
                    return -1
                }
                initNameStart := tokens.Starts[st.Pos]
                initNameLength := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
                    st.ArgStackTop = initArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                initNameNode := EmitExpressionNode(st, nodes, 6, initNameStart, initNameLength, -1, 0, initNameStart, initNameLength)
                argStack.Values[st.ArgStackTop] = initNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                initValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if initValue < 0 {
                    st.ArgStackTop = initArgBase
                    return -1
                }
                argStack.Values[st.ArgStackTop] = initValue
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
                st.ArgStackTop = initArgBase
                return -1
            }
            initEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            initChildCount := st.ArgStackTop - initArgBase
            initChildRun := st.ChildCursor
            ia := initArgBase
            while ia < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[ia])
                ia = ia + 1
            }
            st.ArgStackTop = initArgBase
            return EmitExpressionNode(st, nodes, 36, -1, 0, initChildRun, initChildCount, newStart, initEnd - newStart)
        }

        return newCall
    }

    if kind == 127 {
        parenStart := tokenStart

        // Cast expression (Parser.cs ParsePrimaryExpression + IsCastExpression): `( <type> ) <operand>`,
        // where an expression-start token follows the `)`, is a hard cast. SPECULATIVELY parse a type from
        // after the `(`; if it is followed by `)` and an expression-start, emit a CastExpression (kind 16):
        // children = [typeRoot, operand], operand parsed as a unary expression. Otherwise roll
        // back the speculatively-emitted type nodes / child run / arg-stack and parse as a parenthesized
        // expression. The type kernel refuses type forms it does not support, which rolls back to the paren
        // path (and typically refuses there too) -- never a silently-wrong tree.
        castSaveNode := st.NodeCursor
        castSaveChild := st.ChildCursor
        castSaveArg := st.ArgStackTop
        st.Pos = pos + 1
        st.SplitGreaterDepth = 0
        castType := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
        isCast := false
        if castType >= 0 && st.Pos < count && tokens.Kinds[st.Pos] == 128 {
            if st.Pos + 1 < count && IsExpressionStartKind(tokens.Kinds[st.Pos + 1]) {
                isCast = true
            }
        }

        if isCast {
            st.Pos = st.Pos + 1
            operand := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if operand < 0 {
                return -1
            }

            castSpanEnd := nodes.SpanStarts[operand] + nodes.SpanLengths[operand]
            castChildRun := st.ChildCursor
            AppendExpressionChild(st, children, castType)
            AppendExpressionChild(st, children, operand)
            return EmitExpressionNode(st, nodes, 16, -1, 0, castChildRun, 2, parenStart, castSpanEnd - parenStart)
        }

        st.NodeCursor = castSaveNode
        st.ChildCursor = castSaveChild
        st.ArgStackTop = castSaveArg
        st.SplitGreaterDepth = 0
        st.Pos = pos + 1

        // NAMED tuple literal `(x: 1, y: 2)` (TupleExpression kind 17 whose children are kind-43
        // NamedTupleElement wrappers -- element NAME in the name slot, ONE child = the element value).
        // ALL-OR-NOTHING naming (partial naming is a production-parser error, probe-pinned) and >=2
        // elements (a single named element is not a tuple) -- refuse otherwise. Detected by the
        // `Identifier :` lookahead, which no other parenthesised expression form can start with.
        if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
            namedTupleArgBase := st.ArgStackTop
            namedScanning := true
            while namedScanning {
                if st.Pos + 1 >= count || tokens.Kinds[st.Pos] != 0 || tokens.Kinds[st.Pos + 1] != 122 {
                    st.ArgStackTop = namedTupleArgBase
                    return -1
                }
                namedElemNameStart := tokens.Starts[st.Pos]
                namedElemNameLength := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 2
                namedElemValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if namedElemValue < 0 {
                    st.ArgStackTop = namedTupleArgBase
                    return -1
                }
                namedWrapRun := st.ChildCursor
                AppendExpressionChild(st, children, namedElemValue)
                namedWrapped := EmitExpressionNode(st, nodes, 43, namedElemNameStart, namedElemNameLength, namedWrapRun, 1, namedElemNameStart, nodes.SpanStarts[namedElemValue] + nodes.SpanLengths[namedElemValue] - namedElemNameStart)
                argStack.Values[st.ArgStackTop] = namedWrapped
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                } else {
                    namedScanning = false
                }
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 128 || st.ArgStackTop - namedTupleArgBase < 2 {
                st.ArgStackTop = namedTupleArgBase
                return -1
            }
            namedTupleEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            namedTupleChildCount := st.ArgStackTop - namedTupleArgBase
            namedTupleChildRun := st.ChildCursor
            namedTupleArg := namedTupleArgBase
            while namedTupleArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[namedTupleArg])
                namedTupleArg = namedTupleArg + 1
            }
            st.ArgStackTop = namedTupleArgBase
            return EmitExpressionNode(st, nodes, 17, -1, 0, namedTupleChildRun, namedTupleChildCount, parenStart, namedTupleEnd - parenStart)
        }

        inner := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if inner < 0 {
            return -1
        }

        // A `,` after the first parenthesised expression makes this a TUPLE `( e0, e1, ... )` (TupleExpression
        // kind 17), not a parenthesised expression. Collect the comma-separated elements on the LIFO arg-stack
        // (variable arity, exactly like a block/call), then append the contiguous child run after `)`.
        if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            tupleArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = inner
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                tupleElem := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if tupleElem < 0 {
                    st.ArgStackTop = tupleArgBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = tupleElem
                st.ArgStackTop = st.ArgStackTop + 1
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                st.ArgStackTop = tupleArgBase
                return -1
            }

            tupleRightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            tupleChildCount := st.ArgStackTop - tupleArgBase
            tupleChildRunStart := st.ChildCursor
            tupleArg := tupleArgBase
            while tupleArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[tupleArg])
                tupleArg = tupleArg + 1
            }
            st.ArgStackTop = tupleArgBase
            return EmitExpressionNode(st, nodes, 17, -1, 0, tupleChildRunStart, tupleChildCount, parenStart, tupleRightParenEnd - parenStart)
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            return -1
        }

        rightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, inner)
        return EmitExpressionNode(st, nodes, 7, -1, 0, childRunStart, 1, parenStart, rightParenEnd - parenStart)
    }

    return -1
}

func ParsePostfixExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    expr := -1
    if st.Pos + 2 < count && tokens.Kinds[st.Pos] == 42 && tokens.Kinds[st.Pos + 1] == 124 && tokens.Kinds[st.Pos + 2] == 0 {
        thisStart := tokens.Starts[st.Pos]
        memberStart := tokens.Starts[st.Pos + 2]
        memberLength := tokens.ValueLengths[st.Pos + 2]
        memberEnd := memberStart + memberLength
        expr = EmitExpressionNode(st, nodes, 6, memberStart, memberLength, -1, 0, thisStart, memberEnd - thisStart)
        st.Pos = st.Pos + 3
    } else {
        expr = ParsePrimaryExpressionNode(tokens, count, st, argStack, nodes, children, depth)
        if expr < 0 {
            return -1
        }
    }

    matched := true
    while matched {
        pos := st.Pos

        if pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
            objSpanStart := nodes.SpanStarts[expr]
            memberStart := tokens.Starts[pos + 1]
            memberLength := tokens.ValueLengths[pos + 1]
            memberEnd := memberStart + memberLength
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, expr)
            expr = EmitExpressionNode(st, nodes, 8, memberStart, memberLength, childRunStart, 1, objSpanStart, memberEnd - objSpanStart)
            st.Pos = pos + 2
        } else if pos < count && tokens.Kinds[pos] == 131 {
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            index := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if index < 0 {
                return -1
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 132 {
                return -1
            }

            rightBracketEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, expr)
            AppendExpressionChild(st, children, index)
            expr = EmitExpressionNode(st, nodes, 10, -1, 0, childRunStart, 2, objSpanStart, rightBracketEnd - objSpanStart)
        } else if pos < count && tokens.Kinds[pos] == 100 && (nodes.Kinds[expr] == 6 || nodes.Kinds[expr] == 8) && IsGenericCallTypeArgs(tokens, count, pos) {
            // Explicit generic-call TYPE ARGUMENTS `callee<T1, T2>(args)` — committed when the callee is
            // a bare identifier or dotted member access and the lookahead (the Parser.cs IsGenericMethodCall mirror above) sees a
            // well-formed type-argument list whose close is followed DIRECTLY by `(`. Each argument parses as
            // a TYPE-kernel subtree on the shared table; the result is a GenericCalleeExpression (kind 38:
            // value span = the full callee name, children = the type-arg roots). The `(` branch of
            // this loop then parses the CALL with the kind-38 node as its callee, so a generic call is
            // [genericCallee, arg0, ...] exactly like a plain call. The `>>` split for a nested generic close
            // is honored via the shared st.SplitGreaterDepth owed-greater state (ConsumeGreaterForTypeNodeCore).
            calleeNameStart := nodes.ValueStarts[expr]
            calleeNameLength := nodes.ValueLengths[expr]
            objSpanStart := nodes.SpanStarts[expr]
            if nodes.Kinds[expr] == 8 {
                calleeNameStart = objSpanStart
                calleeNameLength = nodes.SpanLengths[expr]
            }
            st.Pos = pos + 1
            gArgBase := st.ArgStackTop
            st.SplitGreaterDepth = 0
            firstTypeArg := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
            if firstTypeArg < 0 {
                st.ArgStackTop = gArgBase
                return -1
            }
            argStack.Values[st.ArgStackTop] = firstTypeArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                nextTypeArg := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
                if nextTypeArg < 0 {
                    st.ArgStackTop = gArgBase
                    return -1
                }
                argStack.Values[st.ArgStackTop] = nextTypeArg
                st.ArgStackTop = st.ArgStackTop + 1
            }

            closeEnd := ConsumeGreaterForTypeNodeCore(tokens, count, st)
            if closeEnd < 0 {
                st.ArgStackTop = gArgBase
                return -1
            }

            gChildCount := st.ArgStackTop - gArgBase
            gChildRunStart := st.ChildCursor
            g := gArgBase
            while g < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[g])
                g = g + 1
            }
            st.ArgStackTop = gArgBase
            expr = EmitExpressionNode(st, nodes, 38, calleeNameStart, calleeNameLength, gChildRunStart, gChildCount, objSpanStart, closeEnd - objSpanStart)
        } else if pos < count && tokens.Kinds[pos] == 127 {
            // Call `callee(args)`: children = [callee, arg0, arg1, ...]. Like generic type arguments, the
            // callee + arg node ids are gathered on the LIFO arg-stack (each arg is a full expression that
            // appends its own descendants) and the contiguous child run is appended only after the closing
            // `)`. Named (`name:`) arguments are still deferred and refuse when the argument expression
            // leaves the colon unconsumed.
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            argBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = expr
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos < count && tokens.Kinds[st.Pos] != 128 {
                firstArg := ParseCallArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if firstArg < 0 {
                    st.ArgStackTop = argBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = firstArg
                st.ArgStackTop = st.ArgStackTop + 1

                while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                    nextArg := ParseCallArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                    if nextArg < 0 {
                        st.ArgStackTop = argBase
                        return -1
                    }

                    argStack.Values[st.ArgStackTop] = nextArg
                    st.ArgStackTop = st.ArgStackTop + 1
                }
            }

            if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                st.ArgStackTop = argBase
                return -1
            }

            rightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            childCount := st.ArgStackTop - argBase
            childRunStart := st.ChildCursor
            a := argBase
            while a < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[a])
                a = a + 1
            }
            st.ArgStackTop = argBase
            expr = EmitExpressionNode(st, nodes, 9, -1, 0, childRunStart, childCount, objSpanStart, rightParenEnd - objSpanStart)
        } else if pos + 1 < count && tokens.Kinds[pos] == 71 && tokens.Kinds[pos + 1] == 129 {
            // `expr with { Field: value, ... }` (With 71) -- WithExpression kind 52: children
            // [receiver, name0 (Identifier kind 6), value0, name1, value1, ...] -- the kind-36
            // object-initializer pair layout with the RECEIVER expression in place of the type root
            // (the production parses `with` in this same postfix loop, Parser.cs:4510). Zero pairs
            // (a pure clone) are valid. Pairs gather on the LIFO arg-stack exactly as kind 36 does.
            receiverSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 2
            wArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = expr
            st.ArgStackTop = st.ArgStackTop + 1
            while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
                if tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                wNameStart := tokens.Starts[st.Pos]
                wNameLen := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
                wNameNode := EmitExpressionNode(st, nodes, 6, wNameStart, wNameLen, -1, 0, wNameStart, wNameLen)
                argStack.Values[st.ArgStackTop] = wNameNode
                st.ArgStackTop = st.ArgStackTop + 1
                wValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if wValue < 0 {
                    st.ArgStackTop = wArgBase
                    return -1
                }
                argStack.Values[st.ArgStackTop] = wValue
                st.ArgStackTop = st.ArgStackTop + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
                }
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
                st.ArgStackTop = wArgBase
                return -1
            }
            withEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            wChildCount := st.ArgStackTop - wArgBase
            wChildRun := st.ChildCursor
            wArg := wArgBase
            while wArg < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[wArg])
                wArg = wArg + 1
            }
            st.ArgStackTop = wArgBase
            expr = EmitExpressionNode(st, nodes, 52, -1, 0, wChildRun, wChildCount, receiverSpanStart, withEnd - receiverSpanStart)
        } else {
            matched = false
        }
    }

    // Postfix `++`/`--` (Increment 113 / Decrement 114) -- a SINGLE wrap after the suffix chain
    // (PostfixUnary kind 44, the operator token in the value span, ONE child [target]; `n++++` does
    // not re-enter, matching the production grammar). The emitter validates the target (a bare
    // local/param) and keeps the expression value as the PRE-step value.
    if st.Pos < count {
        postOp := tokens.Kinds[st.Pos]
        if postOp == 113 || postOp == 114 {
            postOpStart := tokens.Starts[st.Pos]
            postOpLength := tokens.ValueLengths[st.Pos]
            postOpEnd := postOpStart + postOpLength
            st.Pos = st.Pos + 1
            postChildRun := st.ChildCursor
            AppendExpressionChild(st, children, expr)
            postSpanStart := nodes.SpanStarts[expr]
            return EmitExpressionNode(st, nodes, 44, postOpStart, postOpLength, postChildRun, 1, postSpanStart, postOpEnd - postSpanStart)
        }
    }

    return expr
}

func ParseCallArgumentNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos < count && (tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79) {
        modifierStart := tokens.Starts[st.Pos]
        modifierLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        value := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if value < 0 {
            return -1
        }

        valueEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
        childRun := st.ChildCursor
        AppendExpressionChild(st, children, value)
        return EmitExpressionNode(st, nodes, 54, modifierStart, modifierLength, childRun, 1, modifierStart, valueEnd - modifierStart)
    }

    return ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

func ParseConstructorArgumentNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos < count && (tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79) {
        return -1
    }

    if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
        nameStart := tokens.Starts[st.Pos]
        nameLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 2
        value := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if value < 0 {
            return -1
        }

        valueEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
        childRun := st.ChildCursor
        AppendExpressionChild(st, children, value)
        return EmitExpressionNode(st, nodes, 60, nameStart, nameLength, childRun, 1, nameStart, valueEnd - nameStart)
    }

    return ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

func ParseUnaryExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    if pos < count {
        k := tokens.Kinds[pos]
        // `must <operand>` (Must 20) -- the prefix null-assert (MustExpression kind 45, ONE child;
        // the operand recurses at THIS unary level so `must must x` chains like the production parser).
        if k == 20 {
            mustStart := tokens.Starts[pos]
            st.Pos = pos + 1
            mustOperand := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if mustOperand < 0 {
                return -1
            }
            mustSpanEnd := nodes.SpanStarts[mustOperand] + nodes.SpanLengths[mustOperand]
            mustChildRun := st.ChildCursor
            AppendExpressionChild(st, children, mustOperand)
            return EmitExpressionNode(st, nodes, 45, -1, 0, mustChildRun, 1, mustStart, mustSpanEnd - mustStart)
        }
        // `await <operand>` (Await 69) -- the prefix await (AwaitExpression kind 53, ONE child; the
        // operand recurses at THIS unary level, mirroring the production's prefix-unary production
        // at Parser.cs ParseUnaryExpression so `await await x` chains).
        if k == 69 {
            awaitStart := tokens.Starts[pos]
            st.Pos = pos + 1
            awaitOperand := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if awaitOperand < 0 {
                return -1
            }
            awaitSpanEnd := nodes.SpanStarts[awaitOperand] + nodes.SpanLengths[awaitOperand]
            awaitChildRun := st.ChildCursor
            AppendExpressionChild(st, children, awaitOperand)
            return EmitExpressionNode(st, nodes, 53, -1, 0, awaitChildRun, 1, awaitStart, awaitSpanEnd - awaitStart)
        }
        if k == 106 || k == 89 || k == 110 || k == 113 || k == 114 || k == 109 {
            opStart := tokens.Starts[pos]
            opLength := tokens.ValueLengths[pos]
            st.Pos = pos + 1
            operand := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if operand < 0 {
                return -1
            }

            operandSpanEnd := nodes.SpanStarts[operand] + nodes.SpanLengths[operand]
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, operand)
            return EmitExpressionNode(st, nodes, 11, opStart, opLength, childRunStart, 1, opStart, operandSpanEnd - opStart)
        }
    }

    return ParsePostfixExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

func BinaryOpPrecedence(kind: int): int {
    if kind == 116 {
        return 1
    }
    if kind == 105 {
        return 2
    }
    if kind == 104 {
        return 3
    }
    if kind == 108 {
        return 4
    }
    if kind == 109 {
        return 5
    }
    if kind == 107 {
        return 6
    }
    if kind == 98 || kind == 99 {
        return 7
    }
    if kind == 100 || kind == 101 || kind == 102 || kind == 103 {
        return 8
    }
    if kind == 111 || kind == 112 {
        return 9
    }
    if kind == 88 || kind == 89 {
        return 10
    }
    if kind == 90 || kind == 91 || kind == 92 {
        return 11
    }
    return 0
}

func ParseBinaryExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, minPrec: int, depth: int): int {
    if depth > 200 {
        return -1
    }

    left := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    if left < 0 {
        return -1
    }

    // `is` (47) / `as` (48) TYPE tests -- a single wrap binding tighter than the comparison tier (the
    // production's relational-level is/as): children [value, typeRoot] where the typeRoot is a
    // TYPE-kernel subtree (name scans walk child 0 ONLY -- type kinds collide with expression kinds).
    // IsExpression -> kind 46, AsExpression -> kind 47. Non-chaining (a second is/as after refuses
    // naturally: the bool/result re-enters the climber and 47/48 have no precedence).
    if st.Pos < count && (tokens.Kinds[st.Pos] == 47 || tokens.Kinds[st.Pos] == 48) {
        isAsKind := 46
        if tokens.Kinds[st.Pos] == 48 {
            isAsKind = 47
        }
        st.Pos = st.Pos + 1
        st.SplitGreaterDepth = 0
        isAsType := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
        if isAsType < 0 {
            return -1
        }
        isAsSpanStart := nodes.SpanStarts[left]
        isAsSpanEnd := nodes.SpanStarts[isAsType] + nodes.SpanLengths[isAsType]
        isAsChildRun := st.ChildCursor
        AppendExpressionChild(st, children, left)
        AppendExpressionChild(st, children, isAsType)
        left = EmitExpressionNode(st, nodes, isAsKind, -1, 0, isAsChildRun, 2, isAsSpanStart, isAsSpanEnd - isAsSpanStart)
    }

    keepGoing := true
    while keepGoing {
        opKind := -1
        if st.Pos < count {
            opKind = tokens.Kinds[st.Pos]
        }

        prec := BinaryOpPrecedence(opKind)
        if prec == 0 || prec < minPrec {
            keepGoing = false
        } else {
            opStart := tokens.Starts[st.Pos]
            opLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            right := ParseBinaryExpressionNode(tokens, count, st, argStack, nodes, children, prec + 1, depth + 1)
            if right < 0 {
                return -1
            }

            leftSpanStart := nodes.SpanStarts[left]
            rightSpanEnd := nodes.SpanStarts[right] + nodes.SpanLengths[right]
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, left)
            AppendExpressionChild(st, children, right)
            left = EmitExpressionNode(st, nodes, 12, opStart, opLength, childRunStart, 2, leftSpanStart, rightSpanEnd - leftSpanStart)
        }
    }

    return left
}

func ParseTernaryExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    condition := ParseBinaryExpressionNode(tokens, count, st, argStack, nodes, children, 1, depth)
    if condition < 0 {
        return -1
    }

    if st.Pos < count && tokens.Kinds[st.Pos] == 115 {
        conditionSpanStart := nodes.SpanStarts[condition]
        st.Pos = st.Pos + 1
        thenNode := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
            return -1
        }
        st.Pos = st.Pos + 1

        elseNode := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if elseNode < 0 {
            return -1
        }

        elseSpanEnd := nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, thenNode)
        AppendExpressionChild(st, children, elseNode)
        return EmitExpressionNode(st, nodes, 13, -1, 0, childRunStart, 3, conditionSpanStart, elseSpanEnd - conditionSpanStart)
    }

    return condition
}

func ParseAssignmentExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    target := ParseTernaryExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    if target < 0 {
        return -1
    }

    if st.Pos < count {
        op := tokens.Kinds[st.Pos]
        if op == 93 || op == 94 || op == 95 || op == 96 || op == 97 || op == 117 {
            opStart := tokens.Starts[st.Pos]
            opLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            value := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if value < 0 {
                return -1
            }

            targetSpanStart := nodes.SpanStarts[target]
            valueSpanEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, target)
            AppendExpressionChild(st, children, value)
            return EmitExpressionNode(st, nodes, 14, opStart, opLength, childRunStart, 2, targetSpanStart, valueSpanEnd - targetSpanStart)
        }
    }

    return target
}

func ParseLambdaOrAssignmentExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    pos := st.Pos
    isLambda := false
    if pos + 1 < count && tokens.Kinds[pos] == 0 && tokens.Kinds[pos + 1] == 120 {
        isLambda = true
    } else if pos < count && tokens.Kinds[pos] == 127 {
        scan := pos + 1
        valid := true
        if scan < count && tokens.Kinds[scan] == 128 {
            scan = scan + 1
        } else {
            scanning := true
            while scanning {
                if scan >= count || tokens.Kinds[scan] != 0 {
                    valid = false
                    scanning = false
                } else {
                    scan = scan + 1
                    if scan < count && tokens.Kinds[scan] == 128 {
                        scan = scan + 1
                        scanning = false
                    } else if scan < count && tokens.Kinds[scan] == 134 {
                        scan = scan + 1
                    } else {
                        valid = false
                        scanning = false
                    }
                }
            }
        }
        if valid && scan < count && tokens.Kinds[scan] == 120 {
            isLambda = true
        }
    }

    if !isLambda {
        return ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    }

    spanStart := tokens.Starts[st.Pos]
    argBase := st.ArgStackTop
    if tokens.Kinds[st.Pos] == 0 {
        paramNode := EmitExpressionNode(st, nodes, 6, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], -1, 0, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos])
        argStack.Values[st.ArgStackTop] = paramNode
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = st.Pos + 1
    } else {
        st.Pos = st.Pos + 1
        while st.Pos < count && tokens.Kinds[st.Pos] != 128 {
            paramNode := EmitExpressionNode(st, nodes, 6, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], -1, 0, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos])
            argStack.Values[st.ArgStackTop] = paramNode
            st.ArgStackTop = st.ArgStackTop + 1
            st.Pos = st.Pos + 1
            if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
            }
        }
        st.Pos = st.Pos + 1
    }

    arrowStart := tokens.Starts[st.Pos]
    arrowLength := tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1

    // BLOCK body `x => { ... }`: a statement BLOCK (kind 25) parsed by the statement kernel below.
    // The kernels share the node table and st/argStack conventions, so they live in this file to keep
    // imports acyclic while preserving block-bodied lambda semantics. Otherwise the body is an expression
    // parsed at THIS level (a lambda can return a lambda).
    body := -1
    if st.Pos < count && tokens.Kinds[st.Pos] == 129 {
        body = ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
    } else {
        body = ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
    }
    if body < 0 {
        st.ArgStackTop = argBase
        return -1
    }
    argStack.Values[st.ArgStackTop] = body
    st.ArgStackTop = st.ArgStackTop + 1

    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }
    childCount := st.ArgStackTop - argBase
    st.ArgStackTop = argBase
    bodySpanEnd := nodes.SpanStarts[body] + nodes.SpanLengths[body]
    return EmitExpressionNode(st, nodes, 39, arrowStart, arrowLength, childRunStart, childCount, spanStart, bodySpanEnd - spanStart)
}

func ParseBlockStatementNodeCore(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    blockStart := tokens.Starts[st.Pos]
    st.Pos = st.Pos + 1
    argBase := st.ArgStackTop

    while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
        stmt := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if stmt < 0 {
            st.ArgStackTop = argBase
            return -1
        }

        argStack.Values[st.ArgStackTop] = stmt
        st.ArgStackTop = st.ArgStackTop + 1
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
        st.ArgStackTop = argBase
        return -1
    }

    rightBraceEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - argBase
    childRunStart := st.ChildCursor
    a := argBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }
    st.ArgStackTop = argBase

    return EmitExpressionNode(st, nodes, 25, -1, 0, childRunStart, childCount, blockStart, rightBraceEnd - blockStart)
}

func ParseSystemsPolicyBlockStatementNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    start := st.Pos
    kind := tokens.Kinds[start]
    st.Pos = start + 1

    if kind == 144 {
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }

        parenDepth := 1
        st.Pos = st.Pos + 1
        while st.Pos < count && parenDepth > 0 {
            if tokens.Kinds[st.Pos] == 127 {
                parenDepth = parenDepth + 1
            } else if tokens.Kinds[st.Pos] == 128 {
                parenDepth = parenDepth - 1
            }

            st.Pos = st.Pos + 1
        }

        if parenDepth != 0 {
            return -1
        }
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
        return -1
    }

    return ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
}

func ParseStatementCoreNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    start := st.Pos
    if start >= count {
        return -1
    }

    kind := tokens.Kinds[start]

    if kind == 129 {
        return ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth)
    }

    if kind == 143 || kind == 144 || kind == 146 {
        return ParseSystemsPolicyBlockStatementNode(tokens, count, st, argStack, nodes, children, depth)
    }

    // `try { } [catch ... { }]* [finally { }]` (Try 38 / Catch 39 / Finally 40) -- TryStatement kind 49,
    // children [tryBlock, catch1..catchN, finallyBlock?] (variable arity -> LIFO arg-stack, like blocks;
    // the finally is a trailing kind-25 BLOCK child, distinguishable from the kind-50 catches by kind).
    // Each catch is a kind-50 CatchClause node: value span = the exception TYPE name token (-1 for a bare
    // catch), children [nameIdent?, block] -- the bound variable as a 0-child kind-6 identifier, so the
    // name reads as a USE in every name scan (the linter treats catch variables as always used). All FOUR
    // production catch forms (Parser.cs:3016-3051): bare `catch {`, parenthesized `catch (e: T) {` /
    // `catch (T) {` / `catch (T e) {`, and paren-less `catch e: T {`. The TYPE must be a single Identifier
    // token (the emitter's BCL exception whitelist needs no more). Zero catches are valid WITH a finally
    // (`try {} finally {}`); a try with neither refuses. All bodies must be `{ }` BLOCKS.
    if kind == 38 {
        tryStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }
        tryBlock := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if tryBlock < 0 {
            return -1
        }
        tryArgBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = tryBlock
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokens.Kinds[st.Pos] == 39 {
            catchStart := tokens.Starts[st.Pos]
            st.Pos = st.Pos + 1
            typeStart := 0 - 1
            typeLen := 0
            nameStart := 0 - 1
            nameLen := 0
            if st.Pos < count && tokens.Kinds[st.Pos] == 127 {
                st.Pos = st.Pos + 1
                if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
                    nameStart = tokens.Starts[st.Pos]
                    nameLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 2
                    if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }
                    typeStart = tokens.Starts[st.Pos]
                    typeLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                } else {
                    if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                        st.ArgStackTop = tryArgBase
                        return -1
                    }
                    typeStart = tokens.Starts[st.Pos]
                    typeLen = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 1
                    if st.Pos < count && tokens.Kinds[st.Pos] == 0 {
                        nameStart = tokens.Starts[st.Pos]
                        nameLen = tokens.ValueLengths[st.Pos]
                        st.Pos = st.Pos + 1
                    }
                }
                if st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }
                st.Pos = st.Pos + 1
            } else if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
                nameStart = tokens.Starts[st.Pos]
                nameLen = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 2
                if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                    st.ArgStackTop = tryArgBase
                    return -1
                }
                typeStart = tokens.Starts[st.Pos]
                typeLen = tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            catchBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
            if catchBody < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            catchEnd := nodes.SpanStarts[catchBody] + nodes.SpanLengths[catchBody]
            clauseChildCount := 1
            if nameStart >= 0 {
                clauseChildCount = 2
            }
            nameNode := 0 - 1
            if nameStart >= 0 {
                nameNode = EmitExpressionNode(st, nodes, 6, nameStart, nameLen, st.ChildCursor, 0, nameStart, nameLen)
            }
            clauseChildRun := st.ChildCursor
            if nameNode >= 0 {
                AppendExpressionChild(st, children, nameNode)
            }
            AppendExpressionChild(st, children, catchBody)
            clause := EmitExpressionNode(st, nodes, 50, typeStart, typeLen, clauseChildRun, clauseChildCount, catchStart, catchEnd - catchStart)
            argStack.Values[st.ArgStackTop] = clause
            st.ArgStackTop = st.ArgStackTop + 1
        }
        if st.Pos < count && tokens.Kinds[st.Pos] == 40 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            finallyBlock := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
            if finallyBlock < 0 {
                st.ArgStackTop = tryArgBase
                return -1
            }
            argStack.Values[st.ArgStackTop] = finallyBlock
            st.ArgStackTop = st.ArgStackTop + 1
        }
        childTotal := st.ArgStackTop - tryArgBase
        if childTotal < 2 {
            st.ArgStackTop = tryArgBase
            return -1
        }
        lastClause := argStack.Values[st.ArgStackTop - 1]
        tryEnd := nodes.SpanStarts[lastClause] + nodes.SpanLengths[lastClause]
        tryChildRun := st.ChildCursor
        a := tryArgBase
        while a < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[a])
            a = a + 1
        }
        st.ArgStackTop = tryArgBase
        return EmitExpressionNode(st, nodes, 49, -1, 0, tryChildRun, childTotal, tryStart, tryEnd - tryStart)
    }

    // `lock <expr> { }` (Lock 80) -- LockStatement kind 51, children [lockee, body]. The lockee parses
    // as a full expression; the body must be a `{ }` block. `using` (16) stays deferred — the columnar
    // type surface has no IDisposable values to model.
    if kind == 80 {
        lockStart := tokens.Starts[start]
        st.Pos = start + 1
        lockee := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if lockee < 0 {
            return -1
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }
        lockBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if lockBody < 0 {
            return -1
        }
        lockEnd := nodes.SpanStarts[lockBody] + nodes.SpanLengths[lockBody]
        lockChildRun := st.ChildCursor
        AppendExpressionChild(st, children, lockee)
        AppendExpressionChild(st, children, lockBody)
        return EmitExpressionNode(st, nodes, 51, -1, 0, lockChildRun, 2, lockStart, lockEnd - lockStart)
    }

    // `allow(...) { }` (Allow 144) -- AllowStatement kind 60, children [body]. The systems analyzer owns the
    // effect-list semantics; the columnar parser only validates a balanced parenthesized argument list and a
    // block body so product sources advance to the backend's explicit unsupported-statement decline.
    if kind == 144 {
        allowStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] != 127 {
            return -1
        }
        st.Pos = st.Pos + 1
        parenDepth := 1
        while st.Pos < count && parenDepth > 0 {
            if tokens.Kinds[st.Pos] == 127 {
                parenDepth = parenDepth + 1
            } else if tokens.Kinds[st.Pos] == 128 {
                parenDepth = parenDepth - 1
            }
            st.Pos = st.Pos + 1
        }
        if parenDepth != 0 {
            return -1
        }
        if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
            return -1
        }
        allowBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, depth + 1)
        if allowBody < 0 {
            return -1
        }
        allowEnd := nodes.SpanStarts[allowBody] + nodes.SpanLengths[allowBody]
        allowChildRun := st.ChildCursor
        AppendExpressionChild(st, children, allowBody)
        return EmitExpressionNode(st, nodes, 60, -1, 0, allowChildRun, 1, allowStart, allowEnd - allowStart)
    }

    if kind == 27 {
        whileStart := tokens.Starts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if condition < 0 {
            return -1
        }

        body := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if body < 0 {
            return -1
        }

        bodyEnd := nodes.SpanStarts[body] + nodes.SpanLengths[body]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, body)
        return EmitExpressionNode(st, nodes, 26, -1, 0, childRunStart, 2, whileStart, bodyEnd - whileStart)
    }

    if kind == 25 {
        forStart := tokens.Starts[start]
        st.Pos = start + 1

        // Production accepts Go-style `for <var> in <collection> { body }` as a foreach spelling. Reuse
        // the existing ForeachStatement node shape so lowering stays shared with the `foreach` keyword.
        if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 28 {
            forVarStart := tokens.Starts[st.Pos]
            forVarLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 2

            forCollection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if forCollection < 0 {
                return -1
            }

            forEachBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if forEachBody < 0 {
                return -1
            }

            forEachBodyEnd := nodes.SpanStarts[forEachBody] + nodes.SpanLengths[forEachBody]
            forEachChildRunStart := st.ChildCursor
            AppendExpressionChild(st, children, forCollection)
            AppendExpressionChild(st, children, forEachBody)
            return EmitExpressionNode(st, nodes, 29, forVarStart, forVarLength, forEachChildRunStart, 2, forStart, forEachBodyEnd - forStart)
        }

        // C-style `for <init>; <cond>; <incr> { body }`. init/incr are simple statements (a `:=` declaration or
        // an assignment expression statement); cond is an expression. All three clauses are required (an empty
        // clause makes a sub-parse refuse -> the whole statement declines). Children, in order:
        // [init, cond, incr, body] -> ForStatement kind 28.
        initNode := ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
        if initNode < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 133 {
            return -1
        }
        st.Pos = st.Pos + 1

        forCondition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if forCondition < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 133 {
            return -1
        }
        st.Pos = st.Pos + 1

        increment := ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
        if increment < 0 {
            return -1
        }

        forBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if forBody < 0 {
            return -1
        }

        forBodyEnd := nodes.SpanStarts[forBody] + nodes.SpanLengths[forBody]
        forChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, initNode)
        AppendExpressionChild(st, children, forCondition)
        AppendExpressionChild(st, children, increment)
        AppendExpressionChild(st, children, forBody)
        return EmitExpressionNode(st, nodes, 28, -1, 0, forChildRunStart, 4, forStart, forBodyEnd - forStart)
    }

    if kind == 26 {
        foreachStart := tokens.Starts[start]
        st.Pos = start + 1

        // `foreach <var> in <collection> { body }` (the no-paren, Go-style form). The loop variable name is an
        // identifier stored in the node's value span; children are [collection, body] -> ForeachStatement kind 29.
        // A parenthesised `foreach (x in y)` or a missing var/`in`/body refuses with -1 -> declines.
        if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
            return -1
        }
        foreachVarStart := tokens.Starts[st.Pos]
        foreachVarLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        if st.Pos >= count || tokens.Kinds[st.Pos] != 28 {
            return -1
        }
        st.Pos = st.Pos + 1

        collection := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if collection < 0 {
            return -1
        }

        foreachBody := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if foreachBody < 0 {
            return -1
        }

        foreachBodyEnd := nodes.SpanStarts[foreachBody] + nodes.SpanLengths[foreachBody]
        foreachChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, collection)
        AppendExpressionChild(st, children, foreachBody)
        return EmitExpressionNode(st, nodes, 29, foreachVarStart, foreachVarLength, foreachChildRunStart, 2, foreachStart, foreachBodyEnd - foreachStart)
    }

    if kind == 23 {
        ifStart := tokens.Starts[start]
        st.Pos = start + 1
        condition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if condition < 0 {
            return -1
        }

        thenNode := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        endSpan := nodes.SpanStarts[thenNode] + nodes.SpanLengths[thenNode]
        elseNode := -1
        if st.Pos < count && tokens.Kinds[st.Pos] == 24 {
            st.Pos = st.Pos + 1
            elseNode = ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if elseNode < 0 {
                return -1
            }

            endSpan = nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        }

        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, thenNode)
        ifChildCount := 2
        if elseNode >= 0 {
            AppendExpressionChild(st, children, elseNode)
            ifChildCount = 3
        }

        return EmitExpressionNode(st, nodes, 27, -1, 0, childRunStart, ifChildCount, ifStart, endSpan - ifStart)
    }

    return ParseSimpleStatementNode(tokens, count, st, argStack, nodes, children)
}

func ParseSimpleStatementNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable): int {
    start := st.Pos
    kind := tokens.Kinds[start]

    if kind == 29 {
        returnStart := tokens.Starts[start]
        returnEnd := tokens.Starts[start] + tokens.ValueLengths[start]
        st.Pos = start + 1

        if st.Pos < count && tokens.Kinds[st.Pos] != 130 && tokens.Kinds[st.Pos] != 135 && tokens.Kinds[st.Pos] != 136 {
            valueRoot := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if valueRoot < 0 {
                return -1
            }

            valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, valueRoot)
            return EmitExpressionNode(st, nodes, 20, -1, 0, childRunStart, 1, returnStart, valueEnd - returnStart)
        }

        return EmitExpressionNode(st, nodes, 20, -1, 0, -1, 0, returnStart, returnEnd - returnStart)
    }

    // `throw <expr>` (Throw 37) -- ThrowStatement kind 48, ONE child [the exception expression].
    // A bare `throw` (rethrow, catch-only) is unmodeled (-1) until the catch rung lands. Throw
    // ALWAYS EXITS: the emitter's AlwaysReturns mirror treats kind 48 like Return.
    if kind == 37 {
        throwStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }
        throwValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if throwValue < 0 {
            return -1
        }
        throwEnd := nodes.SpanStarts[throwValue] + nodes.SpanLengths[throwValue]
        throwChildRun := st.ChildCursor
        AppendExpressionChild(st, children, throwValue)
        return EmitExpressionNode(st, nodes, 48, -1, 0, throwChildRun, 1, throwStart, throwEnd - throwStart)
    }

    // `print <expr>` (Print 52) -- PrintStatement kind 56, ONE child [the printed expression]. The value
    // expression is REQUIRED (Parser.cs ParsePrintStatement demands one).
    if kind == 52 {
        printStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }
        printValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if printValue < 0 {
            return -1
        }
        printEnd := nodes.SpanStarts[printValue] + nodes.SpanLengths[printValue]
        printChildRun := st.ChildCursor
        AppendExpressionChild(st, children, printValue)
        return EmitExpressionNode(st, nodes, 56, -1, 0, printChildRun, 1, printStart, printEnd - printStart)
    }

    // `assert <cond> [, <msg>]` (Assert 74) -- AssertStatement kind 61, children [condition, message?].
    // `assert throws <TypeName> { body }` -- AssertThrowsStatement kind 62, the exception TYPE name
    // token in the value span, ONE child [body block]. `throws` is a CONTEXTUAL identifier compared
    // via st.Source (Parser.cs ParseAssertStatement checks the identifier text the same way); an
    // entry with no source text cannot match, so the throws form declines there (under-accept).
    if kind == 74 {
        assertStart := tokens.Starts[start]
        st.Pos = start + 1
        if st.Pos >= count || tokens.Kinds[st.Pos] == 130 || tokens.Kinds[st.Pos] == 135 || tokens.Kinds[st.Pos] == 136 {
            return -1
        }
        if tokens.Kinds[st.Pos] == 0 && st.Source.Length > 0
            && ParserDeclarationTokenTextEquals(st.Source, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], "throws") {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                return -1
            }
            throwsTypeStart := tokens.Starts[st.Pos]
            throwsTypeLength := tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            while st.Pos < count && tokens.Kinds[st.Pos] == 136 {
                st.Pos = st.Pos + 1
            }
            if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
                return -1
            }
            throwsBody := ParseBlockStatementNodeCore(tokens, count, st, argStack, nodes, children, 1)
            if throwsBody < 0 {
                return -1
            }
            throwsEnd := nodes.SpanStarts[throwsBody] + nodes.SpanLengths[throwsBody]
            throwsChildRun := st.ChildCursor
            AppendExpressionChild(st, children, throwsBody)
            return EmitExpressionNode(st, nodes, 62, throwsTypeStart, throwsTypeLength, throwsChildRun, 1, assertStart, throwsEnd - assertStart)
        }
        assertCondition := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if assertCondition < 0 {
            return -1
        }
        assertEnd := nodes.SpanStarts[assertCondition] + nodes.SpanLengths[assertCondition]
        assertMessage := -1
        if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            assertMessage = ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
            if assertMessage < 0 {
                return -1
            }
            assertEnd = nodes.SpanStarts[assertMessage] + nodes.SpanLengths[assertMessage]
        }
        assertChildRun := st.ChildCursor
        AppendExpressionChild(st, children, assertCondition)
        assertChildCount := 1
        if assertMessage >= 0 {
            AppendExpressionChild(st, children, assertMessage)
            assertChildCount = 2
        }
        return EmitExpressionNode(st, nodes, 61, -1, 0, assertChildRun, assertChildCount, assertStart, assertEnd - assertStart)
    }

    if kind == 35 {
        st.Pos = start + 1
        return EmitExpressionNode(st, nodes, 21, -1, 0, -1, 0, tokens.Starts[start], tokens.ValueLengths[start])
    }

    if kind == 36 {
        st.Pos = start + 1
        return EmitExpressionNode(st, nodes, 22, -1, 0, -1, 0, tokens.Starts[start], tokens.ValueLengths[start])
    }

    // Tuple DECONSTRUCTION `n0, n1, ... := <tuple>` (>= 2 names): an identifier FOLLOWED BY a comma. Each target
    // is a bare identifier (or `_` discard) emitted as an Identifier node (kind 6); the value follows `:=`. The
    // node is TupleDeconstructionStatement kind 30, children = [name0, ..., nameN-1, value]. A malformed list
    // (a non-identifier target, a missing `:=` or value) refuses with -1 -> declines.
    if kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 134 {
        deconStart := tokens.Starts[start]
        deconArgBase := st.ArgStackTop

        firstName := EmitExpressionNode(st, nodes, 6, tokens.Starts[start], tokens.ValueLengths[start], -1, 0, tokens.Starts[start], tokens.ValueLengths[start])
        argStack.Values[st.ArgStackTop] = firstName
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = start + 1

        while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
            st.Pos = st.Pos + 1
            if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
                st.ArgStackTop = deconArgBase
                return -1
            }

            nextName := EmitExpressionNode(st, nodes, 6, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], -1, 0, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos])
            argStack.Values[st.ArgStackTop] = nextName
            st.ArgStackTop = st.ArgStackTop + 1
            st.Pos = st.Pos + 1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 121 {
            st.ArgStackTop = deconArgBase
            return -1
        }
        st.Pos = st.Pos + 1

        deconValue := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if deconValue < 0 {
            st.ArgStackTop = deconArgBase
            return -1
        }

        argStack.Values[st.ArgStackTop] = deconValue
        st.ArgStackTop = st.ArgStackTop + 1
        deconValueEnd := nodes.SpanStarts[deconValue] + nodes.SpanLengths[deconValue]
        deconChildCount := st.ArgStackTop - deconArgBase
        deconChildRunStart := st.ChildCursor
        deconIdx := deconArgBase
        while deconIdx < st.ArgStackTop {
            AppendExpressionChild(st, children, argStack.Values[deconIdx])
            deconIdx = deconIdx + 1
        }
        st.ArgStackTop = deconArgBase

        return EmitExpressionNode(st, nodes, 30, -1, 0, deconChildRunStart, deconChildCount, deconStart, deconValueEnd - deconStart)
    }

    // LOCAL FUNCTION declaration (kind 41): `func name(...) ... { body }` as a statement. Record the
    // `func` keyword's byte span and SKIP the declaration: scan to the first depth-0 `{` (the signature
    // contains no braces in modeled forms; a `{` inside a default value mis-anchors the skip and the
    // resulting parse fails downstream — a safe refusal), then balanced to its close.
    if kind == 7 {
        localFuncSpanStart := tokens.Starts[start]
        localFuncSpanLength := tokens.ValueLengths[start]
        funcScan := start + 1
        while funcScan < count && tokens.Kinds[funcScan] != 129 {
            funcScan = funcScan + 1
        }
        if funcScan >= count {
            return -1
        }
        localFuncDepth := 1
        funcScan = funcScan + 1
        while funcScan < count && localFuncDepth > 0 {
            if tokens.Kinds[funcScan] == 129 {
                localFuncDepth = localFuncDepth + 1
            } else if tokens.Kinds[funcScan] == 130 {
                localFuncDepth = localFuncDepth - 1
            }
            funcScan = funcScan + 1
        }
        if localFuncDepth != 0 {
            return -1
        }
        st.Pos = funcScan
        localFuncEnd := tokens.Starts[funcScan - 1] + tokens.ValueLengths[funcScan - 1]
        return EmitExpressionNode(st, nodes, 41, localFuncSpanStart, localFuncSpanLength, -1, 0, localFuncSpanStart, localFuncEnd - localFuncSpanStart)
    }

    // TYPED local declaration (kind 40): `let name: Type = init` (Let 19) or bare `name: Type = init`.
    // Type TREES cannot share the statement node table (the type kernel's kind space 0-6 collides with
    // expression kinds), so the TYPE rides as a SOURCE SPAN in the kind-40 node's VALUE slot — the host
    // canonicalizes the span text. The span is delimited STRUCTURALLY: balanced angles (`>>` 112 closes
    // two) and ()/[] groups, ending at the first depth-0 `=` (93). Children = [name Identifier (kind 6),
    // init root]; the initializer parses at the LAMBDA level (so `let f: Func<int, int> = x => x + 1`
    // carries a kind-39 initializer the emitter types from the DECLARED type). A typed declaration with
    // no initializer never finds a depth-0 `=` and refuses; `let name := init` is unmodeled (-1).
    isTypedLocal := false
    typedNameIndex := start
    if kind == 19 && start + 2 < count && tokens.Kinds[start + 1] == 0 && tokens.Kinds[start + 2] == 122 {
        isTypedLocal = true
        typedNameIndex = start + 1
    } else if kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 122 {
        isTypedLocal = true
    }
    if isTypedLocal {
        typedNameStart := tokens.Starts[typedNameIndex]
        typedNameLength := tokens.ValueLengths[typedNameIndex]
        typeFirst := typedNameIndex + 2
        // The BARE form's type span must not start with `(` -- the production grammar REJECTS a bare
        // tuple-typed local (`t: (int, int) = ...` is a parse error; only `let t: (...)` parses --
        // probe-pinned; accepting it was a routed over-accept). The `let` form is unaffected.
        if kind == 0 && typeFirst < count && tokens.Kinds[typeFirst] == 127 {
            return -1
        }
        scanPos := typeFirst
        angleDepth := 0
        groupDepth := 0
        scanning := true
        while scanning {
            if scanPos >= count {
                return -1
            }
            k := tokens.Kinds[scanPos]
            if k == 93 && angleDepth == 0 && groupDepth == 0 {
                scanning = false
            } else {
                if k == 100 {
                    angleDepth = angleDepth + 1
                } else if k == 102 {
                    angleDepth = angleDepth - 1
                } else if k == 112 {
                    angleDepth = angleDepth - 2
                } else if k == 127 || k == 131 {
                    groupDepth = groupDepth + 1
                } else if k == 128 || k == 132 {
                    groupDepth = groupDepth - 1
                }
                if angleDepth < 0 || groupDepth < 0 {
                    return -1
                }
                scanPos = scanPos + 1
            }
        }
        if scanPos == typeFirst {
            return -1
        }
        typeSpanStart := tokens.Starts[typeFirst]
        typeSpanEnd := tokens.Starts[scanPos - 1] + tokens.ValueLengths[scanPos - 1]
        st.Pos = scanPos + 1
        typedInit := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if typedInit < 0 {
            return -1
        }
        typedNameNode := EmitExpressionNode(st, nodes, 6, typedNameStart, typedNameLength, -1, 0, typedNameStart, typedNameLength)
        typedInitEnd := nodes.SpanStarts[typedInit] + nodes.SpanLengths[typedInit]
        typedChildRunStart := st.ChildCursor
        AppendExpressionChild(st, children, typedNameNode)
        AppendExpressionChild(st, children, typedInit)
        declStart := tokens.Starts[start]
        return EmitExpressionNode(st, nodes, 40, typeSpanStart, typeSpanEnd - typeSpanStart, typedChildRunStart, 2, declStart, typedInitEnd - declStart)
    }

    if kind == 0 && start + 1 < count && tokens.Kinds[start + 1] == 121 {
        nameStart := tokens.Starts[start]
        nameLength := tokens.ValueLengths[start]
        st.Pos = start + 2
        // The `:=` initializer parses at the LAMBDA level (the full-expression entry) so `zero := () => 99`
        // yields a Lambda (kind 39) initializer; all non-lambda shapes fall through to assignment unchanged.
        initRoot := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
        if initRoot < 0 {
            return -1
        }

        initEnd := nodes.SpanStarts[initRoot] + nodes.SpanLengths[initRoot]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, initRoot)
        return EmitExpressionNode(st, nodes, 24, nameStart, nameLength, childRunStart, 1, nameStart, initEnd - nameStart)
    }

    exprRoot := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, 0)
    if exprRoot < 0 {
        return -1
    }

    exprStart := nodes.SpanStarts[exprRoot]
    exprEnd := nodes.SpanStarts[exprRoot] + nodes.SpanLengths[exprRoot]
    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, exprRoot)
    return EmitExpressionNode(st, nodes, 23, -1, 0, childRunStart, 1, exprStart, exprEnd - exprStart)
}

func ParseStatementNodesCore(source: string, tokens: ParserTokenTable, count: int, start: int, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, outResult: ParserResultTable): int {
    st := new ParserState(start, 0, 0, 0, 0, 0, source)

    root := ParseStatementCoreNode(tokens, count, st, argStack, nodes, children, 0)
    if root < 0 {
        return -1
    }

    outResult.Values[0] = root
    outResult.Values[1] = st.Pos
    return st.NodeCursor
}

func ParseColumnarExpressionInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    if outResult.Length < 3 {
        return -1
    }
    if count < 0 {
        return -1
    }

    parseCount := count
    if parseCount > 0 && tokenKinds[parseCount - 1] == 135 {
        parseCount = parseCount - 1
    }
    if parseCount <= 0 {
        return -1
    }

    tokens := new ParserTokenTable(tokenKinds, tokenStarts, tokenValueLengths)
    argStack := new ParserArgumentStack(new int[](parseCount + 1))
    nodes := new ParserExpressionNodeTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outSpanStarts, outSpanLengths)
    children := new ParserChildIndexTable(outChildIndices)
    st := new ParserState(0, 0, 0, 0, 0, 0, source)

    root := ParseLambdaOrAssignmentExpressionNode(tokens, parseCount, st, argStack, nodes, children, 0)
    if root < 0 || st.Pos != parseCount {
        return -1
    }

    outResult[0] = root
    outResult[1] = st.NodeCursor
    outResult[2] = st.ChildCursor
    return st.NodeCursor
}

func PackageNameSpanCore(tokens: ParserDeclarationTokenTable, count: int, result: ParserDeclarationResultTable): int {
    braceDepth := 0
    i := 0
    while i < count {
        kind := tokens.Kinds[i]
        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if braceDepth == 0 && kind == 18 {
            // `package` keyword: collect the dotted name that follows (identifier (. identifier)*).
            j := i + 1
            nameStart := -1
            nameEnd := -1
            while j < count && (tokens.Kinds[j] == 0 || tokens.Kinds[j] == 124) {
                if tokens.Kinds[j] == 0 {
                    if nameStart < 0 {
                        nameStart = tokens.Starts[j]
                    }

                    nameEnd = tokens.Starts[j] + tokens.ValueLengths[j]
                }

                j = j + 1
            }

            if nameStart >= 0 {
                result.Values[0] = nameStart
                result.Values[1] = nameEnd - nameStart
                return 1
            }

            return 0
        }

        i = i + 1
    }

    return 0
}

func NamespaceImportSpansCore(tokens: ParserDeclarationTokenTable, count: int, imports: NamespaceImportTable): int {
    outCount := 0
    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 136 {
            i = i + 1
            continue
        }

        if kind == 18 {
            i = i + 1
            while i < count && (tokens.Kinds[i] == 0 || tokens.Kinds[i] == 124) {
                i = i + 1
            }
            continue
        }

        if kind == 17 {
            i = i + 1
            if i < count && tokens.Kinds[i] == 0 {
                nsStart := tokens.Starts[i]
                nsEnd := tokens.Starts[i] + tokens.ValueLengths[i]
                i = i + 1
                while i < count && (tokens.Kinds[i] == 0 || tokens.Kinds[i] == 124) {
                    if tokens.Kinds[i] == 0 {
                        nsEnd = tokens.Starts[i] + tokens.ValueLengths[i]
                    }

                    i = i + 1
                }

                aliasStart := -1
                aliasLength := 0
                if i < count && tokens.Kinds[i] == 48 {
                    i = i + 1
                    if i < count && tokens.Kinds[i] == 0 {
                        aliasStart = tokens.Starts[i]
                        aliasLength = tokens.ValueLengths[i]
                        i = i + 1
                    }
                }

                imports.NsStarts[outCount] = nsStart
                imports.NsLengths[outCount] = nsEnd - nsStart
                imports.AliasStarts[outCount] = aliasStart
                imports.AliasLengths[outCount] = aliasLength
                outCount = outCount + 1
                continue
            }

            while i < count && tokens.Kinds[i] != 136 {
                i = i + 1
            }
            continue
        }

        break
    }

    return outCount
}

func ModifierFlag(kind: int): int {
    if kind == 64 {
        return 1
    }
    if kind == 65 {
        return 2
    }
    if kind == 66 {
        return 4
    }
    if kind == 67 {
        return 8
    }
    if kind == 63 {
        return 16
    }
    if kind == 58 {
        return 32
    }
    if kind == 60 {
        return 64
    }
    if kind == 61 {
        return 128
    }
    if kind == 62 {
        return 256
    }
    if kind == 68 {
        return 2048
    }
    if kind == 81 {
        return 32768
    }
    if kind == 59 {
        return 65536
    }
    return 0
}

func TopLevelDeclarationModifiersCore(tokens: ParserDeclarationKindStream, count: int, decls: TopLevelDeclarationModifierTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    pending := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause {
                flag := ModifierFlag(kind)
                if flag != 0 {
                    pending = pending | flag
                } else if IsTopLevelDeclarationKeyword(kind) && !IsRecordStructTailToken(tokens.Kinds, i) {
                    decls.Kinds[outCount] = kind
                    decls.Modifiers[outCount] = pending
                    outCount = outCount + 1
                    pending = 0
                }
            }
        }

        i = i + 1
    }

    return outCount
}

func IsTopLevelDeclarationKeyword(kind: int): bool {
    return kind == 7 || kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14 || kind == 72 || kind == 73
}

// `record struct` is ONE declaration: the Struct(9) token directly after a Record(13) token is
// the record-struct TAIL, never its own declaration head. Every declaration walker must apply
// this so counts, names, and modifiers stay aligned.
func IsRecordStructTailToken(kinds: int[], index: int): bool {
    return kinds[index] == 9 && index > 0 && kinds[index - 1] == 13
}

func TopLevelDeclarationNameSpansCore(tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationNameTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && IsTopLevelDeclarationKeyword(kind) && !IsRecordStructTailToken(tokens.Kinds, i) {
                decls.Kinds[outCount] = kind
                decls.Indices[outCount] = i
                nameIndex := i + 1
                if kind == 13 && nameIndex < count && tokens.Kinds[nameIndex] == 9 {
                    nameIndex = nameIndex + 1
                }
                if nameIndex < count && tokens.Kinds[nameIndex] == 0 {
                    decls.NameStarts[outCount] = tokens.Starts[nameIndex]
                    decls.NameLengths[outCount] = tokens.ValueLengths[nameIndex]
                } else {
                    decls.NameStarts[outCount] = -1
                    decls.NameLengths[outCount] = 0
                }

                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelDeclarationKindsCore(tokens: ParserDeclarationKindStream, count: int, decls: TopLevelDeclarationKindTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 53 {
                inWhereClause = true
            } else if !inWhereClause && IsTopLevelDeclarationKeyword(kind) && !IsRecordStructTailToken(tokens.Kinds, i) {
                decls.Kinds[outCount] = kind
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelStructLikeDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, output: TopLevelStructLikeDeclarationTable): int {
    outCount := TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 9, 1, 0, 0, output, 0)
    if outCount < 0 {
        return -1
    }

    outCount = TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 13, 0, 1, 1, output, outCount)
    if outCount < 0 {
        return -1
    }

    return TopLevelStructLikeDeclarationIndicesAppend(tokens, count, 8, 1, 1, 0, output, outCount)
}

func TopLevelColumnarNominalDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, outputs: TopLevelColumnarNominalDeclarationTable, result: ParserDeclarationResultTable): int {
    if count < 0 || count > tokens.Kinds.Length || result.Values.Length < 3 {
        return -1
    }

    enumTable := new TopLevelDeclarationIndexTable(outputs.EnumIndices)
    enumCount := TopLevelDeclarationIndicesCore(tokens, count, 14, 0, enumTable)
    if enumCount < 0 {
        return -1
    }

    unionTable := new TopLevelDeclarationIndexTable(outputs.UnionIndices)
    unionCount := TopLevelDeclarationIndicesCore(tokens, count, 12, 0, unionTable)
    if unionCount < 0 {
        return -1
    }

    interfaceTable := new TopLevelDeclarationIndexTable(outputs.InterfaceIndices)
    interfaceCount := TopLevelDeclarationIndicesCore(tokens, count, 10, 0, interfaceTable)
    if interfaceCount < 0 {
        return -1
    }

    result.Values[0] = enumCount
    result.Values[1] = unionCount
    result.Values[2] = interfaceCount
    return enumCount + unionCount + interfaceCount
}

func TopLevelColumnarProgramDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, compactTokenKinds: int[], compactTokenStarts: int[], compactTokenValueLengths: int[], compactCount: int, outFuncIndices: int[], outFuncAsyncFlags: int[], outEnumIndices: int[], outUnionIndices: int[], outInterfaceIndices: int[], outStructIndices: int[], outStructReferenceFlags: int[], outStructRecordFlags: int[], outResult: int[]): int {
    rawTokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    compactTokens := new ParserDeclarationTokenTable(compactTokenKinds, compactTokenStarts, compactTokenValueLengths)
    outputs := new TopLevelColumnarProgramDeclarationTable(outFuncIndices, outFuncAsyncFlags, outEnumIndices, outUnionIndices, outInterfaceIndices, outStructIndices, outStructReferenceFlags, outStructRecordFlags)
    result := new ParserDeclarationResultTable(outResult)
    return TopLevelColumnarProgramDeclarationIndicesCore(source, rawTokens, rawCount, compactTokens, compactCount, outputs, result)
}

func TopLevelColumnarProgramDeclarationIndicesCore(source: string, rawTokens: ParserDeclarationTokenTable, rawCount: int, compactTokens: ParserDeclarationTokenTable, compactCount: int, outputs: TopLevelColumnarProgramDeclarationTable, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    functionOutputs := new TopLevelColumnarFunctionDeclarationTable(outputs.FuncIndices, outputs.FuncAsyncFlags)
    functionResult := new ParserDeclarationResultTable(new int[](2))
    functionCount := TopLevelColumnarFunctionDeclarationIndicesCore(source, rawTokens, rawCount, compactTokens, compactCount, functionOutputs, functionResult)
    if functionCount < 0 {
        return -2
    }

    names := new TopLevelDeclarationNameTable(new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1))
    nameCount := TopLevelDeclarationNameSpansCore(rawTokens, rawCount, names)
    if nameCount != functionResult.Values[0] {
        return -3
    }

    if TopLevelTypeDeclarationNamesDistinct(source, rawTokens, rawCount, names, nameCount) == 0 {
        return -4
    }

    nominalOutputs := new TopLevelColumnarNominalDeclarationTable(outputs.EnumIndices, outputs.UnionIndices, outputs.InterfaceIndices)
    nominalResult := new ParserDeclarationResultTable(new int[](3))
    compactKindStream := new ParserDeclarationKindStream(compactTokens.Kinds)
    nominalCount := TopLevelColumnarNominalDeclarationIndicesCore(compactKindStream, compactCount, nominalOutputs, nominalResult)
    if nominalCount < 0 {
        return -5
    }

    structOutputs := new TopLevelStructLikeDeclarationTable(outputs.StructIndices, outputs.StructReferenceFlags, outputs.StructRecordFlags)
    structCount := TopLevelStructLikeDeclarationIndicesCore(compactKindStream, compactCount, structOutputs)
    if structCount < 0 {
        return -6
    }

    result.Values[0] = functionResult.Values[0]
    result.Values[1] = functionCount
    result.Values[2] = nominalResult.Values[0]
    result.Values[3] = nominalResult.Values[1]
    result.Values[4] = nominalResult.Values[2]
    result.Values[5] = structCount
    return functionCount + nominalCount + structCount
}

func TopLevelTypeDeclarationNamesDistinct(source: string, tokens: ParserDeclarationTokenTable, count: int, decls: TopLevelDeclarationNameTable, declCount: int): int {
    if declCount < 0 {
        return 0
    }

    i := 0
    while i < declCount {
        if IsTopLevelTypeDeclarationKind(decls.Kinds[i]) {
            if decls.NameStarts[i] < 0 || decls.NameLengths[i] <= 0 {
                return 0
            }

            j := i + 1
            while j < declCount {
                if IsTopLevelTypeDeclarationKind(decls.Kinds[j]) {
                    if decls.NameStarts[j] < 0 || decls.NameLengths[j] <= 0 {
                        return 0
                    }

                    if ParserDeclarationSourceSpansEqual(source, decls.NameStarts[i], decls.NameLengths[i], decls.NameStarts[j], decls.NameLengths[j]) {
                        namespaceMatch := ParserDeclarationNamespacesEqual(source, tokens, count, decls.Indices[i], decls.Indices[j])
                        if namespaceMatch != 0 {
                            return 0
                        }
                    }
                }

                j = j + 1
            }
        }

        i = i + 1
    }

    return 1
}

func IsTopLevelTypeDeclarationKind(kind: int): bool {
    return kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14
}

func TopLevelStructLikeDeclarationIndicesAppend(tokens: ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, isReference: int, isRecord: int, output: TopLevelStructLikeDeclarationTable, startCount: int): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := startCount
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 53 {
                inWhereClause = true
            } else if kind == targetKind && (suppressWhereClause == 0 || !inWhereClause) && !IsRecordStructTailToken(tokens.Kinds, i) {
                if outCount >= output.Indices.Length || outCount >= output.ReferenceFlags.Length || outCount >= output.RecordFlags.Length {
                    return -1
                }

                declReferenceFlag := isReference
                if kind == 13 && i + 1 < count && tokens.Kinds[i + 1] == 9 {
                    declReferenceFlag = 0
                }
                output.Indices[outCount] = i
                output.ReferenceFlags[outCount] = declReferenceFlag
                output.RecordFlags[outCount] = isRecord
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelColumnarFunctionDeclarationIndicesCore(source: string, rawTokens: ParserDeclarationTokenTable, rawCount: int, compactTokens: ParserDeclarationTokenTable, compactCount: int, outputs: TopLevelColumnarFunctionDeclarationTable, result: ParserDeclarationResultTable): int {
    if rawCount < 0 || compactCount < 0 || rawCount > rawTokens.Kinds.Length || rawCount > rawTokens.Starts.Length || rawCount > rawTokens.ValueLengths.Length || compactCount > compactTokens.Kinds.Length || compactCount > compactTokens.Starts.Length || compactCount > compactTokens.ValueLengths.Length || result.Values.Length < 2 {
        return -1
    }

    if TopLevelUnmodeledTestShapeExistsCore(source, rawTokens, rawCount) != 0 {
        return -1
    }

    decls := new TopLevelDeclarationKindTable(new int[](rawCount + 1))
    rawKindStream := new ParserDeclarationKindStream(rawTokens.Kinds)
    declCount := TopLevelDeclarationKindsCore(rawKindStream, rawCount, decls)
    if declCount < 0 {
        return -1
    }

    // A file whose only top-level declarations are PLAIN test declarations (a `.tests.nl` file)
    // has zero declaration keywords; that is a valid empty function list, not a refusal.
    if declCount == 0 {
        testOnlyIndices := new int[](rawCount + 1)
        testOnlyResult := new int[](1)
        if TopLevelColumnarTestDeclarationIndicesInto(source, rawTokens.Kinds, rawTokens.Starts, rawTokens.ValueLengths, rawCount, testOnlyIndices, testOnlyResult) <= 0 {
            return -1
        }

        result.Values[0] = 0
        result.Values[1] = 0
        return 0
    }

    i := 0
    while i < declCount {
        kind := decls.Kinds[i]
        if kind != 7 && kind != 14 && kind != 9 && kind != 13 && kind != 12 && kind != 8 && kind != 10 && kind != 72 {
            return -1
        }

        i = i + 1
    }

    names := new TopLevelDeclarationNameTable(new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1), new int[](rawCount + 1))
    nameCount := TopLevelDeclarationNameSpansCore(rawTokens, rawCount, names)
    if nameCount != declCount {
        return -1
    }

    if TopLevelFunctionDeclarationNamesDistinct(source, names, nameCount) == 0 {
        return -1
    }

    modifiers := new TopLevelDeclarationModifierTable(new int[](rawCount + 1), new int[](rawCount + 1))
    modifierCount := TopLevelDeclarationModifiersCore(rawKindStream, rawCount, modifiers)
    if modifierCount != declCount {
        return -1
    }

    compactKindStream := new ParserDeclarationKindStream(compactTokens.Kinds)
    indices := new TopLevelDeclarationIndexTable(outputs.Indices)
    funcCount := TopLevelDeclarationIndicesCore(compactKindStream, compactCount, 7, 0, indices)
    if funcCount < 0 || funcCount > outputs.AsyncFlags.Length {
        return -1
    }

    asyncCount := 0
    i = 0
    while i < declCount {
        if decls.Kinds[i] == 7 {
            if asyncCount >= outputs.AsyncFlags.Length {
                return -1
            }

            asyncFlag := 0
            if (modifiers.Modifiers[i] & 2048) != 0 {
                asyncFlag = 1
            }

            outputs.AsyncFlags[asyncCount] = asyncFlag
            asyncCount = asyncCount + 1
        }

        i = i + 1
    }

    if asyncCount != funcCount {
        return -1
    }

    if TopLevelFunctionPreamblesAreValidCore(compactTokens, compactCount, indices, funcCount) == 0 {
        return -1
    }

    result.Values[0] = declCount
    result.Values[1] = funcCount
    return funcCount
}

func TopLevelFunctionDeclarationNamesDistinct(source: string, decls: TopLevelDeclarationNameTable, declCount: int): int {
    if declCount < 0 {
        return 0
    }

    i := 0
    while i < declCount {
        if decls.Kinds[i] == 7 {
            if decls.NameStarts[i] < 0 || decls.NameLengths[i] <= 0 {
                return 0
            }

            j := i + 1
            while j < declCount {
                if decls.Kinds[j] == 7 {
                    if decls.NameStarts[j] < 0 || decls.NameLengths[j] <= 0 {
                        return 0
                    }

                    if ParserDeclarationSourceSpansEqual(source, decls.NameStarts[i], decls.NameLengths[i], decls.NameStarts[j], decls.NameLengths[j]) {
                        return 0
                    }
                }

                j = j + 1
            }
        }

        i = i + 1
    }

    return 1
}

func TopLevelDeclarationIndicesCore(tokens: ParserDeclarationKindStream, count: int, targetKind: int, suppressWhereClause: int, indices: TopLevelDeclarationIndexTable): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0
    inWhereClause := false

    i := 0
    while i < count {
        kind := tokens.Kinds[i]

        if kind == 129 {
            braceDepth = braceDepth + 1
            inWhereClause = false
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            if kind == 53 {
                inWhereClause = true
            } else if kind == targetKind && (suppressWhereClause == 0 || !inWhereClause) {
                if outCount >= indices.Indices.Length {
                    return -1
                }

                indices.Indices[outCount] = i
                outCount = outCount + 1
            }
        }

        i = i + 1
    }

    return outCount
}

func TopLevelFunctionPreamblePreviousToken(tokens: ParserDeclarationTokenTable, start: int): int {
    pos := start
    changed := true
    while changed {
        changed = false

        while pos >= 0 && ModifierFlag(tokens.Kinds[pos]) != 0 {
            pos = pos - 1
            changed = true
        }

        if pos >= 0 && tokens.Kinds[pos] == 132 {
            open := TopLevelFunctionPreambleAttributeOpen(tokens, pos)
            if open < 0 {
                return pos
            }

            pos = open - 1
            changed = true
        }
    }

    return pos
}

func TopLevelFunctionPreambleAttributeOpen(tokens: ParserDeclarationTokenTable, closeIndex: int): int {
    depth := 0
    pos := closeIndex
    while pos >= 0 {
        kind := tokens.Kinds[pos]
        if kind == 132 {
            depth = depth + 1
        } else if kind == 131 {
            depth = depth - 1
            if depth == 0 {
                return pos
            }
        }

        pos = pos - 1
    }

    return -1
}

func TopLevelFunctionPreamblesAreValidCore(tokens: ParserDeclarationTokenTable, count: int, indices: TopLevelDeclarationIndexTable, funcCount: int): int {
    i := 0
    while i < funcCount {
        funcIndex := indices.Indices[i]
        if funcIndex < 0 || funcIndex >= count || tokens.Kinds[funcIndex] != 7 {
            return 0
        }

        preceding := TopLevelFunctionPreamblePreviousToken(tokens, funcIndex - 1)

        if preceding >= 0 && tokens.Kinds[preceding] != 130 {
            if tokens.Kinds[preceding] == 4 {
                if preceding - 1 < 0 || tokens.Kinds[preceding - 1] != 17 {
                    if i == 0 || TopLevelExpressionBodiedFunctionEndsAt(tokens, count, indices.Indices[i - 1], funcIndex) == 0 {
                        return 0
                    }
                }

                i = i + 1
                continue
            }

            aliasWalk := preceding
            while aliasWalk >= 0 && !IsTopLevelDeclarationKeyword(tokens.Kinds[aliasWalk]) && tokens.Kinds[aliasWalk] != 15 && tokens.Kinds[aliasWalk] != 17 && tokens.Kinds[aliasWalk] != 18 {
                aliasWalk = aliasWalk - 1
            }

            if aliasWalk >= 0 && tokens.Kinds[aliasWalk] == 72 {
                i = i + 1
                continue
            }

            headerWalk := preceding
            while headerWalk >= 0 && (tokens.Kinds[headerWalk] == 0 || tokens.Kinds[headerWalk] == 124 || tokens.Kinds[headerWalk] == 48) {
                headerWalk = headerWalk - 1
            }

            // Valid header prefixes: `namespace A.B` / `import A.B[.C] [as X]` / `package A`, or a
            // FILE import with an alias — `import "path" as X` — whose walk stops at the string.
            isAliasedFileImportHeader := headerWalk >= 0 && tokens.Kinds[headerWalk] == 4
                && headerWalk - 1 >= 0 && tokens.Kinds[headerWalk - 1] == 17
            if headerWalk == preceding || headerWalk < 0 || (tokens.Kinds[headerWalk] != 15 && tokens.Kinds[headerWalk] != 17 && tokens.Kinds[headerWalk] != 18 && !isAliasedFileImportHeader) {
                if i == 0 || TopLevelExpressionBodiedFunctionEndsAt(tokens, count, indices.Indices[i - 1], funcIndex) == 0 {
                    return 0
                }
            }
        }

        i = i + 1
    }

    return 1
}

func TopLevelExpressionBodiedFunctionEndsAt(tokens: ParserDeclarationTokenTable, count: int, funcIndex: int, nextFuncIndex: int): int {
    if funcIndex < 0 || funcIndex >= count || nextFuncIndex <= funcIndex || nextFuncIndex > count || tokens.Kinds[funcIndex] != 7 {
        return 0
    }

    signatureEnd := ParseDeclarationFunctionSignatureEndCore(tokens, count, funcIndex)
    if signatureEnd < 0 || signatureEnd >= count || tokens.Kinds[signatureEnd] != 120 {
        return 0
    }

    expressionEnd := ParseDeclarationExpressionBodyEndCore(tokens, count, signatureEnd)
    if expressionEnd < 0 {
        return 0
    }

    if expressionEnd == nextFuncIndex {
        return 1
    }

    if expressionEnd + 1 == nextFuncIndex && expressionEnd < count && tokens.Kinds[expressionEnd] == 133 {
        return 1
    }

    return 0
}

func MatchingCloseBraceCore(tokens: ParserDeclarationKindStream, count: int, open: int): int {
    if open < 0 || open >= count || tokens.Kinds[open] != 129 {
        return -1
    }

    depth := 0
    i := open
    while i < count {
        kind := tokens.Kinds[i]
        if kind == 129 {
            depth = depth + 1
        } else if kind == 130 {
            depth = depth - 1
            if depth == 0 {
                return i
            }
        }

        i = i + 1
    }

    return -1
}

func TokenIndexByKindStartCore(tokens: ParserDeclarationStartKindStream, count: int, targetKind: int, targetStart: int): int {
    i := 0
    while i < count {
        if tokens.Kinds[i] == targetKind && tokens.Starts[i] == targetStart {
            return i
        }

        i = i + 1
    }

    return -1
}

func ParsePropertyAccessorInfoCore(source: string, tokens: ParserDeclarationTokenTable, count: int, propIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    if count < 0 {
        return -1
    }

    if count > tokens.Kinds.Length {
        return -1
    }

    if count > tokens.Starts.Length {
        return -1
    }

    if count > tokens.ValueLengths.Length {
        return -1
    }

    if propIndex < 0 || propIndex + 4 >= count {
        return -1
    }

    if tokens.Kinds[propIndex] != 0 || tokens.Kinds[propIndex + 1] != 122 {
        return -1
    }

    typeResult := new ParserDeclarationResultTable(new int[](2))
    typeEnd := ParseDeclarationTypeSpanCore(tokens, count, propIndex + 2, typeResult)
    if typeEnd < 0 || typeEnd >= count {
        return -1
    }

    if tokens.Kinds[typeEnd] == 120 {
        result.Values[0] = tokens.Starts[propIndex]
        result.Values[1] = tokens.ValueLengths[propIndex]
        result.Values[2] = typeResult.Values[0]
        result.Values[3] = typeResult.Values[1]
        result.Values[4] = typeEnd
        result.Values[5] = -1
        return 0
    }

    if typeEnd + 2 >= count || tokens.Kinds[typeEnd] != 129 {
        return -1
    }

    if tokens.Kinds[typeEnd + 1] != 0 || !ParserDeclarationTokenTextEquals(source, tokens.Starts[typeEnd + 1], tokens.ValueLengths[typeEnd + 1], "get") {
        return -1
    }

    if tokens.Kinds[typeEnd + 2] != 129 {
        return -1
    }

    getBodyBrace := typeEnd + 2
    kindStream := new ParserDeclarationKindStream(tokens.Kinds)
    getBodyEnd := MatchingCloseBraceCore(kindStream, count, getBodyBrace)
    if getBodyEnd < 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[propIndex]
    result.Values[1] = tokens.ValueLengths[propIndex]
    result.Values[2] = typeResult.Values[0]
    result.Values[3] = typeResult.Values[1]
    result.Values[4] = getBodyBrace
    result.Values[5] = -1

    after := getBodyEnd + 1
    if after < count && tokens.Kinds[after] == 130 {
        return 0
    }

    if after + 1 < count && tokens.Kinds[after] == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[after], tokens.ValueLengths[after], "set") && tokens.Kinds[after + 1] == 129 {
        setBodyBrace := after + 1
        setBodyEnd := MatchingCloseBraceCore(kindStream, count, setBodyBrace)
        if setBodyEnd < 0 || setBodyEnd + 1 >= count || tokens.Kinds[setBodyEnd + 1] != 130 {
            return -1
        }

        result.Values[5] = setBodyBrace
        return 1
    }

    return -1
}

// A top-level TEST-family shape the columnar route does NOT model yet: setup/teardown blocks, and
// any `test` form that is not exactly `test "<description>" {` (with-tables, skip clauses, or a
// malformed header). Well-formed plain tests are MODELED (scanned by
// TopLevelColumnarTestDeclarationIndicesInto and parsed by ParseColumnarTestInfoInto), so they no
// longer gate the declaration scan.
func TopLevelUnmodeledTestShapeExistsCore(source: string, tokens: ParserDeclarationTokenTable, count: int): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0

    i := 0
    while i < count {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            isTestHead := kind == 73
            if kind == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test") {
                nextAfterTest := ParserDeclarationNextNonNewlineTokenKind(tokens, count, i + 1)
                if nextAfterTest == 4 || nextAfterTest == 129 || ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens, i) {
                    isTestHead = true
                }
            }

            if isTestHead {
                if TopLevelPlainTestHeaderEndsAt(tokens, count, i) < 0 {
                    return 1
                }
            } else if kind == 0
                && (ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "setup")
                    || ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "teardown")) {
                nextKind := ParserDeclarationNextNonNewlineTokenKind(tokens, count, i + 1)
                atDeclarationBoundary := ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens, i)
                if nextKind == 129 || atDeclarationBoundary {
                    return 1
                }
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        }

        i = i + 1
    }

    return 0
}

// The PLAIN test header `test "<description>" {` starting at `testIndex`: returns the token index
// of the opening brace, or -1 when the shape is anything else (with-table, skip, missing pieces).
func TopLevelPlainTestHeaderEndsAt(tokens: ParserDeclarationTokenTable, count: int, testIndex: int): int {
    i := testIndex + 1
    while i < count && tokens.Kinds[i] == 136 {
        i = i + 1
    }
    if i >= count || tokens.Kinds[i] != 4 {
        return -1
    }
    i = i + 1
    while i < count && tokens.Kinds[i] == 136 {
        i = i + 1
    }
    if i >= count || tokens.Kinds[i] != 129 {
        return -1
    }
    return i
}

// Top-level NEWTYPE declarations: `type X = newtype T` (Type 72, Identifier name, Assign 93,
// Newtype 87, ONE simple underlying type token). Records the Type token index plus the name and
// underlying-type token spans. A composed underlying type (generics, arrays) is unmodeled and
// fails the scan (-1) so the host declines with a reason instead of mis-synthesizing.
func TopLevelColumnarNewtypeDeclarationIndicesInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outIndices: int[], outNameStarts: int[], outNameLengths: int[], outTypeStarts: int[], outTypeLengths: int[], outResult: int[]): int {
    if count < 0 || count > tokenKinds.Length || outIndices.Length < count + 1 || outResult.Length < 1 {
        return -1
    }

    braceDepth := 0
    outCount := 0
    i := 0
    while i < count {
        kind := tokenKinds[i]
        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if braceDepth == 0 && kind == 72
            && i + 3 < count && tokenKinds[i + 1] == 0 && tokenKinds[i + 2] == 93 && tokenKinds[i + 3] == 87 {
            if i + 4 >= count || tokenKinds[i + 4] != 0 {
                return -1
            }
            // A COMPOSED underlying type (generic `<`, array `[`, dotted access) is unmodeled.
            if i + 5 < count && (tokenKinds[i + 5] == 100 || tokenKinds[i + 5] == 131 || tokenKinds[i + 5] == 124) {
                return -1
            }
            outIndices[outCount] = i
            outNameStarts[outCount] = tokenStarts[i + 1]
            outNameLengths[outCount] = tokenValueLengths[i + 1]
            outTypeStarts[outCount] = tokenStarts[i + 4]
            outTypeLengths[outCount] = tokenValueLengths[i + 4]
            outCount = outCount + 1
        }

        i = i + 1
    }

    outResult[0] = outCount
    return outCount
}

// Records the keyword token index of every top-level PLAIN test declaration. Returns the count.
// outResult[0] mirrors the count (the flat-int ABI convention).
func TopLevelColumnarTestDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, outTestIndices: int[], outResult: int[]): int {
    if rawCount < 0 || rawCount > rawTokenKinds.Length || outTestIndices.Length < rawCount + 1 || outResult.Length < 1 {
        return -1
    }

    tokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0

    i := 0
    while i < rawCount {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            isTestHead := kind == 73
            if kind == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test") {
                nextAfterTest := ParserDeclarationNextNonNewlineTokenKind(tokens, rawCount, i + 1)
                if nextAfterTest == 4 {
                    isTestHead = true
                }
            }

            if isTestHead && TopLevelPlainTestHeaderEndsAt(tokens, rawCount, i) >= 0 {
                outTestIndices[outCount] = i
                outCount = outCount + 1
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        }

        i = i + 1
    }

    outResult[0] = outCount
    return outCount
}

// Parse one PLAIN test declaration at `testIndex`: `test "<description>" { body }`. The
// description STRING token's span lands in outResult[0]/[1] (raw, quotes included — the host
// decodes); the body block parses through the statement kernel into the caller-allocated node
// tables. outResult[2] = body root node id, outResult[3] = token index past the body. Returns the
// body node count, or -1.
func ParseColumnarTestInfoInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, testIndex: int, bodyKinds: int[], bodyValueStarts: int[], bodyValueLengths: int[], bodyChildStarts: int[], bodyChildCounts: int[], bodyChildIndices: int[], bodySpanStarts: int[], bodySpanLengths: int[], outResult: int[]): int {
    if rawCount < 0 || testIndex < 0 || testIndex >= rawCount || outResult.Length < 4 {
        return -1
    }

    declTokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    bodyBrace := TopLevelPlainTestHeaderEndsAt(declTokens, rawCount, testIndex)
    if bodyBrace < 0 {
        return -1
    }

    descIndex := testIndex + 1
    while descIndex < rawCount && rawTokenKinds[descIndex] == 136 {
        descIndex = descIndex + 1
    }
    if descIndex >= rawCount || rawTokenKinds[descIndex] != 4 {
        return -1
    }

    statementTokens := new ParserTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    argStack := new ParserArgumentStack(new int[](rawCount + 1))
    nodes := new ParserExpressionNodeTable(bodyKinds, bodyValueStarts, bodyValueLengths, bodyChildStarts, bodyChildCounts, bodySpanStarts, bodySpanLengths)
    children := new ParserChildIndexTable(bodyChildIndices)
    statementResult := new ParserResultTable(new int[](2))
    bodyNodeCount := ParseStatementNodesCore(source, statementTokens, rawCount, bodyBrace, argStack, nodes, children, statementResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    outResult[0] = rawTokenStarts[descIndex]
    outResult[1] = rawTokenValueLengths[descIndex]
    outResult[2] = statementResult.Values[0]
    outResult[3] = statementResult.Values[1]
    return bodyNodeCount
}

func ParserDeclarationNextNonNewlineTokenKind(tokens: ParserDeclarationTokenTable, count: int, startIndex: int): int {
    i := startIndex
    while i < count {
        if tokens.Kinds[i] != 136 {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens: ParserDeclarationTokenTable, index: int): bool {
    if index <= 0 {
        return true
    }

    previousKind := tokens.Kinds[index - 1]
    return previousKind == 136 || previousKind == 130 || previousKind == 133
}

func ParserDeclarationTokenTextEquals(source: string, start: int, length: int, expected: string): bool {
    if start < 0 || length != expected.Length || start + length > source.Length {
        return false
    }

    i := 0
    while i < length {
        if source[start + i] != expected[i] {
            return false
        }

        i = i + 1
    }

    return true
}

func ParseInterfaceDeclarationCore(tokens: ParserDeclarationTokenTable, count: int, interfaceIndex: int, decl: InterfaceDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := interfaceIndex
    if pos >= count || tokens.Kinds[pos] != 10 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    typeParamCount := 0
    if pos < count && tokens.Kinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 102 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.TypeParamStarts[typeParamCount] = tokens.Starts[pos]
            decl.TypeParamLengths[typeParamCount] = tokens.ValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] != 102 {
                if tokens.Kinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
            }
        }
        if pos >= count || tokens.Kinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }
        pos = pos + 1
    }
    if result.Values.Length > 4 {
        result.Values[4] = typeParamCount
    }

    baseTypeResult := new ParserDeclarationResultTable(new int[](2))
    baseCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            typeEnd := ParseDeclarationTypeSpanCore(tokens, count, pos, baseTypeResult)
            if typeEnd < 0 {
                return -1
            }
            decl.BaseNameStarts[baseCount] = baseTypeResult.Values[0]
            decl.BaseNameLengths[baseCount] = baseTypeResult.Values[1]
            baseCount = baseCount + 1
            pos = typeEnd

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }
    result.Values[2] = baseCount

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    methodCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 7 {
            return -1
        }
        decl.MethodFuncIndices[methodCount] = pos
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 7 && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] == 129 {
                depth := 1
                pos = pos + 1
                while pos < count && depth > 0 {
                    if tokens.Kinds[pos] == 129 {
                        depth = depth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        depth = depth - 1
                    }
                    pos = pos + 1
                }
                if depth != 0 {
                    return -1
                }
                break
            }
            pos = pos + 1
        }
        methodCount = methodCount + 1
    }
    if pos >= count {
        return -1
    }
    return methodCount
}

func ParseEnumMemberValuesCore(source: string, members: EnumMemberTable, memberCount: int, values: EnumMemberValueTable): bool {
    if memberCount < 0 || memberCount > values.Values.Length {
        return false
    }

    nextValue := 0
    i := 0
    while i < memberCount {
        value := nextValue
        if members.HasValue[i] != 0 {
            if !ParserDeclarationTryParseIntLiteralCore(source, members.ValueStarts[i], members.ValueLengths[i], values, i) {
                return false
            }
            value = values.Values[i]
        } else {
            values.Values[i] = value
        }

        nextValue = ParserDeclarationNextEnumValue(value)
        i = i + 1
    }

    return true
}

func ParserDeclarationSpanText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    return source.Substring(start, length)
}

func ParserDeclarationSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
    if leftStart < 0 || rightStart < 0 || leftLength != rightLength {
        return false
    }

    if leftStart + leftLength > source.Length || rightStart + rightLength > source.Length {
        return false
    }

    i := 0
    while i < leftLength {
        if source[leftStart + i] != source[rightStart + i] {
            return false
        }

        i = i + 1
    }

    return true
}

func ParserDeclarationDottedNameSpanAfter(tokens: ParserDeclarationTokenTable, count: int, nameStartIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }
    result.Values[0] = -1
    result.Values[1] = 0

    if nameStartIndex < 0 || nameStartIndex >= count || tokens.Kinds[nameStartIndex] != 0 {
        return -1
    }

    start := tokens.Starts[nameStartIndex]
    end := tokens.Starts[nameStartIndex] + tokens.ValueLengths[nameStartIndex]
    pos := nameStartIndex + 1
    expectDot := 1
    while pos < count {
        if expectDot == 1 {
            if tokens.Kinds[pos] != 124 {
                break
            }
            expectDot = 0
        } else {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            end = tokens.Starts[pos] + tokens.ValueLengths[pos]
            expectDot = 1
        }

        pos = pos + 1
    }

    if expectDot == 0 {
        return -1
    }

    result.Values[0] = start
    result.Values[1] = end - start
    return pos
}

func ParserDeclarationNamespaceSpanBefore(tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 || declarationIndex < 0 || declarationIndex > count {
        return -1
    }

    result.Values[0] = -1
    result.Values[1] = 0
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    i := 0
    nameResult := new ParserDeclarationResultTable(new int[](2))
    while i < declarationIndex {
        kind := tokens.Kinds[i]
        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 && (kind == 15 || kind == 18) {
            next := ParserDeclarationDottedNameSpanAfter(tokens, count, i + 1, nameResult)
            if next < 0 {
                return -1
            }

            result.Values[0] = nameResult.Values[0]
            result.Values[1] = nameResult.Values[1]
            i = next - 1
        }

        i = i + 1
    }

    return 1
}

func ParserDeclarationQualifiedNameText(source: string, tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int, nameStart: int, nameLength: int): string {
    name := ParserDeclarationSpanText(source, nameStart, nameLength)
    if name == "" {
        return ""
    }

    namespaceResult := new ParserDeclarationResultTable(new int[](2))
    if ParserDeclarationNamespaceSpanBefore(tokens, count, declarationIndex, namespaceResult) < 0 {
        return ""
    }

    if namespaceResult.Values[1] <= 0 {
        return name
    }

    namespaceName := ParserDeclarationSpanText(source, namespaceResult.Values[0], namespaceResult.Values[1])
    if namespaceName == "" {
        return ""
    }

    return namespaceName + "." + name
}

func ParserDeclarationNamespacesEqual(source: string, tokens: ParserDeclarationTokenTable, count: int, leftDeclarationIndex: int, rightDeclarationIndex: int): int {
    leftResult := new ParserDeclarationResultTable(new int[](2))
    rightResult := new ParserDeclarationResultTable(new int[](2))
    if ParserDeclarationNamespaceSpanBefore(tokens, count, leftDeclarationIndex, leftResult) < 0 {
        return -1
    }
    if ParserDeclarationNamespaceSpanBefore(tokens, count, rightDeclarationIndex, rightResult) < 0 {
        return -1
    }

    if leftResult.Values[1] != rightResult.Values[1] {
        return 0
    }
    if leftResult.Values[1] == 0 {
        return 1
    }
    if ParserDeclarationSourceSpansEqual(source, leftResult.Values[0], leftResult.Values[1], rightResult.Values[0], rightResult.Values[1]) {
        return 1
    }
    return 0
}

func ParserDeclarationNextEnumValue(value: int): int {
    if value == 2147483647 {
        return 0 - 2147483647 - 1
    }

    return value + 1
}

func ParserDeclarationTryParseIntLiteralCore(source: string, start: int, length: int, result: EnumMemberValueTable, resultIndex: int): bool {
    if start < 0 || length <= 0 || start + length > source.Length || resultIndex < 0 || resultIndex >= result.Values.Length {
        return false
    }

    negative := false
    index := start
    end := start + length
    if source[index] == '+' || source[index] == '-' {
        negative = source[index] == '-'
        index = index + 1
        if index >= end {
            return false
        }
    }

    value := 0
    while index < end {
        ch := source[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && index == end - 1 {
                    result.Values[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
        }

        value = value * 10 + digit
        index = index + 1
    }

    if negative {
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

func ParseEnumDeclarationCore(tokens: ParserDeclarationTokenTable, count: int, enumIndex: int, members: EnumMemberTable, result: ParserDeclarationResultTable): int {
    pos := enumIndex
    if pos >= count || tokens.Kinds[pos] != 14 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }
        pos = pos + 1
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    memberCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 0 {
            return -1
        }
        members.NameStarts[memberCount] = tokens.Starts[pos]
        members.NameLengths[memberCount] = tokens.ValueLengths[pos]
        members.HasValue[memberCount] = 0
        members.ValueStarts[memberCount] = -1
        members.ValueLengths[memberCount] = 0
        pos = pos + 1

        if pos < count && tokens.Kinds[pos] == 93 {
            pos = pos + 1
            if pos >= count || (tokens.Kinds[pos] != 1 && tokens.Kinds[pos] != 4) {
                return -1
            }
            members.HasValue[memberCount] = 1
            members.ValueStarts[memberCount] = tokens.Starts[pos]
            members.ValueLengths[memberCount] = tokens.ValueLengths[pos]
            pos = pos + 1
        }

        memberCount = memberCount + 1

        if pos < count && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    return memberCount
}

func ParserDeclarationCanonicalTypeText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    hasGenericSuffix := false
    i := 0
    while i < length {
        if source[start + i] == '<' {
            hasGenericSuffix = true
            break
        }

        i = i + 1
    }

    if !hasGenericSuffix {
        return source.Substring(start, length)
    }

    builder := new StringBuilder(length)
    i = 0
    while i < length {
        ch := source[start + i]
        if !Char.IsWhiteSpace(ch) {
            builder.Append(ch)
        }

        i = i + 1
    }

    return builder.ToString()
}

func ParserDeclarationMemberModifierKind(kind: int): int {
    if kind == 63 {
        return 2
    }
    if kind == 64 || kind == 65 || kind == 66 || kind == 67 {
        return 1
    }
    if kind == 22 || kind == 58 || kind == 59 || kind == 60 || kind == 61 || kind == 62 || kind == 68 || kind == 81 {
        return 3
    }
    return 0
}

func ParserDeclarationMemberModifierFlag(kind: int): int {
    if kind == 22 {
        return 512
    }
    return ModifierFlag(kind)
}

func ParserDeclarationModifierFlagsIncludeReadonly(flags: int): bool {
    return (flags / 512) % 2 == 1
}

func ParseMemberModifierPrefixCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, result: ParserDeclarationResultTable): int {
    if pos < 0 || pos > count || result.Values.Length < 2 {
        return -1
    }

    result.Values[0] = 0
    result.Values[1] = 0
    if result.Values.Length >= 3 {
        result.Values[2] = 0
    }
    while pos < count {
        if tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                pos = pos + 1
            }
            if bracketDepth != 0 {
                return -1
            }
            continue
        }

        modifierKind := ParserDeclarationMemberModifierKind(tokens.Kinds[pos])
        if modifierKind == 0 {
            break
        }

        if result.Values.Length >= 3 {
            flag := ParserDeclarationMemberModifierFlag(tokens.Kinds[pos])
            if flag != 0 {
                result.Values[2] = result.Values[2] | flag
            }
        }

        if modifierKind == 2 {
            if result.Values[0] == 1 {
                return -1
            }
            result.Values[0] = 1
        } else if modifierKind == 1 {
            result.Values[1] = result.Values[1] + 1
            if result.Values[1] > 1 {
                return -1
            }
        }

        pos = pos + 1
    }

    return pos
}

func ColumnarStructNativeImportModifierFlag(): int {
    return 131072
}

func ColumnarStructMethodFlagIsNativeImport(flags: int): bool {
    return (flags & ColumnarStructNativeImportModifierFlag()) != 0
}

func ParseDeclarationFunctionSignatureEndCore(tokens: ParserDeclarationTokenTable, count: int, funcIndex: int): int {
    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    parameters := new ParserFunctionParameterTable(new int[](count + 1), new int[](count + 1), new int[](count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](count + 1), new int[](count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](count + 1), new int[](count + 1), new int[](count + 1))
    signatureResult := new ParserResultTable(new int[](8))
    paramCount := ParseFunctionSignatureCore(signatureTokens, count, funcIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 {
        return -1
    }
    return signatureResult.Values[6]
}

func ColumnarStructLibraryImportAttributeSpanCore(source: string, tokens: ParserDeclarationTokenTable, memberStart: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 {
        return 0
    }

    result.Values[0] = -1
    result.Values[1] = -1
    scan := memberStart - 1
    while scan >= 0 && ParserDeclarationMemberModifierKind(tokens.Kinds[scan]) != 0 {
        scan = scan - 1
    }
    if scan < 0 || tokens.Kinds[scan] != 132 {
        return 0
    }

    attributeEnd := tokens.Starts[scan] + tokens.ValueLengths[scan]
    closeIndex := scan
    depth := 1
    scan = scan - 1
    while scan >= 0 {
        if tokens.Kinds[scan] == 132 {
            depth = depth + 1
        } else if tokens.Kinds[scan] == 131 {
            depth = depth - 1
            if depth == 0 {
                attributeStart := tokens.Starts[scan]
                if attributeStart < 0 || attributeEnd < attributeStart || attributeEnd > source.Length {
                    return 0
                }
                attributeText := source.Substring(attributeStart, attributeEnd - attributeStart)
                if attributeText.IndexOf("LibraryImport", StringComparison.Ordinal) >= 0 {
                    result.Values[0] = scan
                    result.Values[1] = closeIndex
                    return 1
                }
                return 0
            }
        }
        scan = scan - 1
    }

    return 0
}

func ColumnarStructMethodHasLibraryImportAttribute(source: string, tokens: ParserDeclarationTokenTable, memberStart: int): bool {
    spanResult := new ParserDeclarationResultTable(new int[](2))
    return ColumnarStructLibraryImportAttributeSpanCore(source, tokens, memberStart, spanResult) == 1
}

func ColumnarTokenTextEquals(source: string, tokens: ParserDeclarationTokenTable, index: int, text: string): bool {
    if index < 0 || index >= tokens.Kinds.Length {
        return false
    }
    if tokens.Starts[index] < 0 || tokens.ValueLengths[index] != text.Length {
        return false
    }
    if tokens.Starts[index] + tokens.ValueLengths[index] > source.Length {
        return false
    }

    return source.Substring(tokens.Starts[index], tokens.ValueLengths[index]) == text
}

func DecodeColumnarAttributeStringToken(source: string, tokens: ParserDeclarationTokenTable, index: int): string {
    if index < 0 || index >= tokens.Kinds.Length || tokens.Kinds[index] != 4 {
        return ""
    }

    start := tokens.Starts[index]
    length := tokens.ValueLengths[index]
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    if length >= 2 && source[start] == '"' && source[start + length - 1] == '"' {
        return source.Substring(start + 1, length - 2)
    }

    return source.Substring(start, length)
}

func ParseColumnarNativeImportInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, memberStart: int, methodName: string, outTexts: string[]): int {
    if outTexts.Length < 2 {
        return -1
    }

    tokens := new ParserDeclarationTokenTable(tokenKinds, tokenStarts, tokenValueLengths)
    spanResult := new ParserDeclarationResultTable(new int[](2))
    if ColumnarStructLibraryImportAttributeSpanCore(source, tokens, memberStart, spanResult) != 1 {
        return -1
    }

    openIndex := spanResult.Values[0]
    closeIndex := spanResult.Values[1]
    if openIndex < 0 || closeIndex <= openIndex || closeIndex >= count {
        return -1
    }

    scan := openIndex + 1
    while scan < closeIndex && !ColumnarTokenTextEquals(source, tokens, scan, "LibraryImport") {
        scan = scan + 1
    }
    if scan >= closeIndex {
        return -1
    }
    scan = scan + 1

    if scan >= closeIndex || tokenKinds[scan] != 127 {
        return -1
    }
    scan = scan + 1

    if scan >= closeIndex || tokenKinds[scan] != 4 {
        return -1
    }
    libraryName := DecodeColumnarAttributeStringToken(source, tokens, scan)
    if libraryName == "" {
        return -1
    }
    entryPointName := methodName
    scan = scan + 1

    if scan < closeIndex && tokenKinds[scan] == 134 {
        scan = scan + 1
        if scan + 2 >= closeIndex || !ColumnarTokenTextEquals(source, tokens, scan, "EntryPoint") || tokenKinds[scan + 1] != 93 || tokenKinds[scan + 2] != 4 {
            return -1
        }

        entryPointName = DecodeColumnarAttributeStringToken(source, tokens, scan + 2)
        if entryPointName == "" {
            return -1
        }
        scan = scan + 3
    }

    if scan >= closeIndex || tokenKinds[scan] != 128 {
        return -1
    }

    outTexts[0] = libraryName
    outTexts[1] = entryPointName
    return 1
}

    return false
}

func ParseDeclarationTypeSpanCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 || pos < 0 || pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }

    typeStart := tokens.Starts[pos]
    typeEnd := tokens.Starts[pos] + tokens.ValueLengths[pos]
    pos = pos + 1

    if pos < count && tokens.Kinds[pos] == 100 {
        gdepth := 0
        parenDepth := 0
        gdone := 0
        gprevIdent := 0
        while pos < count && gdone == 0 {
            gk := tokens.Kinds[pos]
            if gk == 100 {
                gdepth = gdepth + 1
                gprevIdent = 0
            } else if gk == 102 {
                gdepth = gdepth - 1
                if gdepth == 0 && parenDepth != 0 {
                    return -1
                }
                if gdepth == 0 {
                    gdone = 1
                }
                gprevIdent = 0
            } else if gk == 112 {
                gdepth = gdepth - 2
                if gdepth == 0 && parenDepth != 0 {
                    return -1
                }
                if gdepth == 0 {
                    gdone = 1
                }
                gprevIdent = 0
            } else if gk == 127 {
                parenDepth = parenDepth + 1
                gprevIdent = 0
            } else if gk == 128 {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    return -1
                }
                gprevIdent = 1
            } else if gk == 0 {
                if gprevIdent == 1 {
                    return -1
                }
                gprevIdent = 1
            } else if gk == 131 || gk == 132 || gk == 115 {
                gprevIdent = gprevIdent
            } else if gk == 122 && parenDepth > 0 {
                gprevIdent = 0
            } else if gk == 134 || gk == 124 {
                gprevIdent = 0
            } else {
                return -1
            }
            if gdepth < 0 {
                return -1
            }
            typeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
            pos = pos + 1
        }
        if gdone == 0 {
            return -1
        }
        if parenDepth != 0 {
            return -1
        }
    }

    suffixDone := 0
    while suffixDone == 0 && pos < count {
        if pos + 1 < count && tokens.Kinds[pos] == 131 && tokens.Kinds[pos + 1] == 132 {
            typeEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
            pos = pos + 2
        } else if pos + 1 < count && tokens.Kinds[pos] == 119 && tokens.Kinds[pos + 1] == 132 {
            typeEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
            pos = pos + 2
        } else if tokens.Kinds[pos] == 115 {
            typeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
            pos = pos + 1
        } else {
            suffixDone = 1
        }
    }

    result.Values[0] = typeStart
    result.Values[1] = typeEnd - typeStart
    return pos
}

func ParseDeclarationSimpleInitializerEndCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, typeResult: ParserDeclarationResultTable): int {
    if pos < 0 || pos >= count {
        return -1
    }

    kind := tokens.Kinds[pos]
    if ParseDeclarationSimpleInitializerTokenIsLiteral(kind) {
        return pos + 1
    }

    if kind == 0 {
        pos = pos + 1
        dotCount := 0
        while pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
            dotCount = dotCount + 1
            pos = pos + 2
        }
        if dotCount > 0 {
            return pos
        }
        return -1
    }

    if kind != 41 {
        return -1
    }

    pos = pos + 1
    pos = ParseDeclarationTypeSpanCore(tokens, count, pos, typeResult)
    if pos < 0 || pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }

    depth := 0
    done := 0
    while pos < count && done == 0 {
        if tokens.Kinds[pos] == 127 {
            depth = depth + 1
        } else if tokens.Kinds[pos] == 128 {
            depth = depth - 1
            if depth == 0 {
                done = 1
            }
        }

        pos = pos + 1
    }

    if done == 0 {
        return -1
    }

    return pos
}

func ParseDeclarationInitializerExpressionEndCore(tokens: ParserDeclarationTokenTable, count: int, pos: int): int {
    if pos < 0 || pos >= count {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserExpressionNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(pos, 0, 0, 0, 0, 0)
    valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= pos {
        return -1
    }

    return st.Pos
}

func ParseDeclarationSimpleInitializerTokenIsLiteral(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 2 || kind == 3 || kind == 4
}

func ParserDeclarationFieldInitializerExpressionKind(): int {
    return 1001
}

func PrimaryConstructorParameterIndexOf(source: string, parameters: PrimaryConstructorParameterTable, parameterCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < parameterCount {
        if ParserDeclarationSourceSpansEqual(source, parameters.NameStarts[i], parameters.NameLengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func ParserDeclarationDefaultMemberAccessKind(): int {
    return 1000
}

func ParserDeclarationDefaultDottedNameSupported(tokens: ParserDeclarationTokenTable, startIndex: int, endIndex: int): bool {
    if startIndex < 0 || endIndex <= startIndex || endIndex > tokens.Kinds.Length {
        return false
    }

    identifierCount := 0
    dotCount := 0
    expectIdentifier := true
    i := startIndex
    while i < endIndex {
        kind := tokens.Kinds[i]
        if expectIdentifier {
            if kind != 0 {
                return false
            }
            identifierCount = identifierCount + 1
            expectIdentifier = false
        } else {
            if kind != 124 {
                return false
            }
            dotCount = dotCount + 1
            expectIdentifier = true
        }

        i = i + 1
    }

    return !expectIdentifier && identifierCount >= 2 && dotCount >= 1
}

func ParsePrimaryConstructorParameterSpansCore(_source: string, tokens: ParserDeclarationTokenTable, count: int, leftParenIndex: int, parameters: PrimaryConstructorParameterTable, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 1 || leftParenIndex < 0 || leftParenIndex >= count || tokens.Kinds[leftParenIndex] != 127 {
        return -1
    }

    pos := leftParenIndex + 1
    paramCount := 0
    foundDefault := 0
    typeResult := new ParserDeclarationResultTable(new int[](2))

    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= parameters.NameStarts.Length
            || paramCount >= parameters.TypeStarts.Length
            || paramCount >= parameters.DefaultKinds.Length {
            return -1
        }

        if tokens.Kinds[pos] != 0 {
            return -1
        }
        parameters.NameStarts[paramCount] = tokens.Starts[pos]
        parameters.NameLengths[paramCount] = tokens.ValueLengths[pos]
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }
        pos = pos + 1

        pos = ParseDeclarationTypeSpanCore(tokens, count, pos, typeResult)
        if pos < 0 {
            return -1
        }
        parameters.TypeStarts[paramCount] = typeResult.Values[0]
        parameters.TypeLengths[paramCount] = typeResult.Values[1]
        parameters.DefaultKinds[paramCount] = -1
        parameters.DefaultStarts[paramCount] = -1
        parameters.DefaultLengths[paramCount] = 0

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenStart := pos
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount == 1 && (defaultKind == 46 || defaultKind == 44 || defaultKind == 45 || defaultKind == 1 || defaultKind == 4) {
                defaultLength = tokens.ValueLengths[defaultTokenStart]
            } else if ParserDeclarationDefaultDottedNameSupported(tokens, defaultTokenStart, pos) {
                defaultKind = ParserDeclarationDefaultMemberAccessKind()
                defaultLength = tokens.Starts[pos - 1] + tokens.ValueLengths[pos - 1] - defaultStart
            } else {
                return -1
            }

            parameters.DefaultKinds[paramCount] = defaultKind
            parameters.DefaultStarts[paramCount] = defaultStart
            parameters.DefaultLengths[paramCount] = defaultLength
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    result.Values[0] = pos + 1
    return paramCount
}

func StructDeclarationFieldIndexOf(source: string, decl: StructDeclarationTable, fieldCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < fieldCount {
        if ParserDeclarationSourceSpansEqual(source, decl.FieldNameStarts[i], decl.FieldNameLengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func ParseStructDeclarationCore(source: string, tokens: ParserDeclarationTokenTable, count: int, structIndex: int, decl: StructDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := structIndex
    if pos >= count || (tokens.Kinds[pos] != 9 && tokens.Kinds[pos] != 13 && tokens.Kinds[pos] != 8) {
        return -1
    }
    // `record struct Name` — the Struct token is the record-struct TAIL of the Record head.
    if tokens.Kinds[pos] == 13 && pos + 1 < count && tokens.Kinds[pos + 1] == 9 {
        pos = pos + 1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the type name (Less 100, Identifier 0,
    // Comma 134, Greater 102): bare comma-separated Identifiers only, the same shape as a generic
    // FUNCTION signature's list. A declaration's list cannot nest, so no `>>` splitting is needed.
    // An inline constraint (`<T: Base>`), an empty list, or any other form returns -1 (the host
    // declines to the N# backend path). Name spans go to outTypeParamStarts/Lengths; the count to
    // outResult[7] (0 with no `<`).
    typeParamCount := 0
    if pos < count && tokens.Kinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 102 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.TypeParamStarts[typeParamCount] = tokens.Starts[pos]
            decl.TypeParamLengths[typeParamCount] = tokens.ValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] != 102 {
                if tokens.Kinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
            }
        }
        if pos >= count || tokens.Kinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }
        pos = pos + 1
    }
    result.Values[7] = typeParamCount

    primaryParameters := new PrimaryConstructorParameterTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    primaryResult := new ParserDeclarationResultTable(new int[](1))
    primaryCtorParamCount := 0
    primaryAssignedFlags := new int[](count + 1)
    if pos < count && tokens.Kinds[pos] == 127 {
        primaryCtorParamCount = ParsePrimaryConstructorParameterSpansCore(source, tokens, count, pos, primaryParameters, primaryResult)
        if primaryCtorParamCount < 0 {
            return -1
        }
        pos = primaryResult.Values[0]
    }
    if result.Values.Length > 9 {
        result.Values[9] = primaryCtorParamCount
    }

    // Optional BASE / INTERFACE LIST: `class D: Base, IFace {` or `struct S: IFace<T> {` — a `:` (122)
    // after the type name followed by one or more comma-separated type references. The host resolves names
    // against type registries and decides which one, if any, is a class base versus implemented interface.
    result.Values[5] = 0
    result.Values[6] = 0
    baseTypeResult := new ParserDeclarationResultTable(new int[](2))
    baseNameCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            typeEnd := ParseDeclarationTypeSpanCore(tokens, count, pos, baseTypeResult)
            if typeEnd < 0 {
                return -1
            }
            decl.BaseNameStarts[baseNameCount] = baseTypeResult.Values[0]
            decl.BaseNameLengths[baseNameCount] = baseTypeResult.Values[1]
            if baseNameCount == 0 {
                result.Values[5] = baseTypeResult.Values[0]
                result.Values[6] = baseTypeResult.Values[1]
            }
            baseNameCount = baseNameCount + 1
            pos = typeEnd

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }
    result.Values[8] = baseNameCount

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    // Fields first (`Name : Type`), stopping at the type close `}` (130), the first method `func` (7), a
    // conversion-operator member (`implicit` 85 / `explicit` 86), or a
    // CONSTRUCTOR member — an Identifier (0) immediately followed by `(` (127). A field is `id : type` (a `:` after
    // the name), so an `id (` is unambiguously a constructor, not a field, and ends the field section. A PROPERTY
    // `id : type { get {…} [set {…}] }` — an `id : type` followed by `{` (129) — is recorded (its name token index in
    // outPropIndices) and its `{ … }` block skipped; the host parses the accessor bodies. (A field is just `id :
    // type`; the trailing `{` disambiguates a property from a field.) Single-token property types only (a composed
    // type would not present `{` at pos+3, so it falls to the field path and declines).
    fieldCount := 0
    propCount := 0
    fieldsDone := 0
    memberModifierValues := new int[](3)
    memberModifiers := new ParserDeclarationResultTable(memberModifierValues)
    fieldTypeResult := new ParserDeclarationResultTable(new int[](2))
    initializerTypeResult := new ParserDeclarationResultTable(new int[](2))
    hasInstanceInitializer := 0
    while fieldsDone == 0 && pos < count && tokens.Kinds[pos] != 130 && tokens.Kinds[pos] != 7 && tokens.Kinds[pos] != 85 && tokens.Kinds[pos] != 86 {
        memberStart := ParseMemberModifierPrefixCore(tokens, count, pos, memberModifiers)
        if memberStart < 0 || memberStart >= count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
            fieldsDone = 1
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < count && tokens.Kinds[memberStart + 1] == 127 {
            fieldsDone = 1
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 3 < count && tokens.Kinds[memberStart + 1] == 122 && tokens.Kinds[memberStart + 2] == 0 && tokens.Kinds[memberStart + 3] == 129 {
            decl.PropIndices[propCount] = memberStart
            decl.PropStaticFlags[propCount] = memberModifiers.Values[0]
            propCount = propCount + 1
            pos = memberStart + 3

            pdepth := 0
            pdone := 0
            while pos < count && pdone == 0 {
                if tokens.Kinds[pos] == 129 {
                    pdepth = pdepth + 1
                } else if tokens.Kinds[pos] == 130 {
                    pdepth = pdepth - 1
                    if pdepth == 0 {
                        pdone = 1
                    }
                }
                pos = pos + 1
            }
            if pdone == 0 {
                return -1
            }
        } else {
            if tokens.Kinds[memberStart] != 0 {
                return -1
            }
            decl.FieldNameStarts[fieldCount] = tokens.Starts[memberStart]
            decl.FieldNameLengths[fieldCount] = tokens.ValueLengths[memberStart]
            pos = memberStart + 1

            if pos >= count || tokens.Kinds[pos] != 122 {
                return -1
            }
            pos = pos + 1

            pos = ParseDeclarationTypeSpanCore(tokens, count, pos, fieldTypeResult)
            if pos < 0 {
                return -1
            }
            decl.FieldTypeStarts[fieldCount] = fieldTypeResult.Values[0]
            decl.FieldTypeLengths[fieldCount] = fieldTypeResult.Values[1]
            fieldModifierFlags := memberModifiers.Values[0]
            if ParserDeclarationModifierFlagsIncludeReadonly(memberModifiers.Values[2]) {
                fieldModifierFlags = fieldModifierFlags + 2
            }
            decl.FieldStaticFlags[fieldCount] = fieldModifierFlags
            decl.FieldInitKinds[fieldCount] = -1
            decl.FieldInitStarts[fieldCount] = -1
            decl.FieldInitLengths[fieldCount] = 0

            if pos < count && tokens.Kinds[pos] == 129 {
                decl.PropIndices[propCount] = memberStart
                decl.PropStaticFlags[propCount] = memberModifiers.Values[0]
                propCount = propCount + 1

                pdepth := 0
                pdone := 0
                while pos < count && pdone == 0 {
                    if tokens.Kinds[pos] == 129 {
                        pdepth = pdepth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        pdepth = pdepth - 1
                        if pdepth == 0 {
                            pdone = 1
                        }
                    }
                    pos = pos + 1
                }
                if pdone == 0 {
                    return -1
                }
                continue
            }

            if pos < count && tokens.Kinds[pos] == 120 {
                decl.PropIndices[propCount] = memberStart
                decl.PropStaticFlags[propCount] = memberModifiers.Values[0]
                propCount = propCount + 1
                pos = ParseDeclarationExpressionBodyEndCore(tokens, count, pos)
                if pos < 0 {
                    return -1
                }
                continue
            }

            if pos < count && tokens.Kinds[pos] == 93 {
                pos = pos + 1
                if pos >= count {
                    return -1
                }

                initKind := tokens.Kinds[pos]
                initStart := tokens.Starts[pos]
                initLength := tokens.ValueLengths[pos]
                if initKind == 0 {
                    paramIndex := PrimaryConstructorParameterIndexOf(source, primaryParameters, primaryCtorParamCount, initStart, initLength)
                    if paramIndex < 0 {
                        initEnd := ParseDeclarationSimpleInitializerEndCore(tokens, count, pos, initializerTypeResult)
                        if initEnd < 0 {
                            if memberModifiers.Values[0] == 0 {
                                return -1
                            }

                            initEnd = ParseDeclarationInitializerExpressionEndCore(tokens, count, pos)
                            if initEnd < 0 {
                                return -1
                            }
                            initKind = ParserDeclarationFieldInitializerExpressionKind()
                        }
                        initLength = tokens.Starts[initEnd - 1] + tokens.ValueLengths[initEnd - 1] - initStart
                        pos = initEnd - 1
                    } else {
                        primaryAssignedFlags[paramIndex] = 1
                    }
                } else if !ParseDeclarationSimpleInitializerTokenIsLiteral(initKind) {
                    initEnd := ParseDeclarationSimpleInitializerEndCore(tokens, count, pos, initializerTypeResult)
                    if initEnd < 0 {
                        initEnd = ParseDeclarationInitializerExpressionEndCore(tokens, count, pos)
                        if initEnd < 0 {
                            return -1
                        }
                        if memberModifiers.Values[0] != 0 {
                            initKind = ParserDeclarationFieldInitializerExpressionKind()
                        }
                    }
                    initLength = tokens.Starts[initEnd - 1] + tokens.ValueLengths[initEnd - 1] - initStart
                    pos = initEnd - 1
                }
                if memberModifiers.Values[0] == 1 {
                    if initKind == 0 || initKind == 41 {
                        return -1
                    }
                    decl.FieldInitKinds[fieldCount] = initKind
                    decl.FieldInitStarts[fieldCount] = initStart
                    decl.FieldInitLengths[fieldCount] = initLength
                } else {
                    hasInstanceInitializer = 1
                }
                pos = pos + 1
            }

            fieldCount = fieldCount + 1
        }
    }

    if (tokens.Kinds[structIndex] == 8 || tokens.Kinds[structIndex] == 13) && primaryCtorParamCount > 0 {
        paramIndex := 0
        while paramIndex < primaryCtorParamCount {
            if primaryAssignedFlags[paramIndex] == 0
                && StructDeclarationFieldIndexOf(source, decl, fieldCount, primaryParameters.NameStarts[paramIndex], primaryParameters.NameLengths[paramIndex]) < 0 {
                decl.FieldNameStarts[fieldCount] = primaryParameters.NameStarts[paramIndex]
                decl.FieldNameLengths[fieldCount] = primaryParameters.NameLengths[paramIndex]
                decl.FieldTypeStarts[fieldCount] = primaryParameters.TypeStarts[paramIndex]
                decl.FieldTypeLengths[fieldCount] = primaryParameters.TypeLengths[paramIndex]
                decl.FieldStaticFlags[fieldCount] = 0
                decl.FieldInitKinds[fieldCount] = -1
                decl.FieldInitStarts[fieldCount] = -1
                decl.FieldInitLengths[fieldCount] = 0
                fieldCount = fieldCount + 1
            }

            paramIndex = paramIndex + 1
        }
    }

    // Members next, in any order: METHODS (`func name(...): ret { body }`) and CONSTRUCTORS (`constructor(...) {
    // body }` — lexed as an Identifier followed by `(`). DELIMIT each: record its keyword/identifier token index
    // (outMethodFuncIndices for a method, outCtorIndices for a constructor), then skip its signature to the body `{`
    // and scan to the matching `}` (balanced). The host parses the signatures/bodies via the existing function
    // kernels at the recorded indices (a constructor's `(params)` and `{body}` parse via the same signature/statement
    // kernels — it has no name token and no `: ret`, so the signature kernel yields name=-1, returnRoot=-1; a
    // constructor INITIALIZER `: this(...)`/`base(...)` is skipped by the signature kernel and parsed separately
    // via ParseConstructorChainInfoCore, with the composed constructor core verifying the identifier text.
    // A member with no `{` body declines unless it is a static LibraryImport method; those carry a native-import
    // modifier bit and materialize as P/Invoke methods without managed bodies.
    methodCount := 0
    ctorCount := 0
    syntheticCtorNeeded := primaryCtorParamCount > 0 || hasInstanceInitializer == 1
    if syntheticCtorNeeded {
        decl.CtorIndices[ctorCount] = structIndex
        ctorCount = ctorCount + 1
    }
    while pos < count && tokens.Kinds[pos] != 130 {
        memberStart := ParseMemberModifierPrefixCore(tokens, count, pos, memberModifiers)
        if memberStart < 0 || memberStart >= count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
            methodFlags := memberModifiers.Values[2]
            if tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
                methodFlags = methodFlags | 16
            }
            signatureEnd := ParseDeclarationFunctionSignatureEndCore(tokens, count, memberStart)
            if signatureEnd < 0 || signatureEnd >= count {
                return -1
            }
            if tokens.Kinds[signatureEnd] != 129 && tokens.Kinds[signatureEnd] != 120 {
                if (methodFlags & 16) == 0 || !ColumnarStructMethodHasLibraryImportAttribute(source, tokens, memberStart) {
                    return -1
                }

                methodFlags = methodFlags | ColumnarStructNativeImportModifierFlag()
                decl.MethodFuncIndices[methodCount] = memberStart
                decl.MethodStaticFlags[methodCount] = methodFlags
                if decl.MethodModifierFlags.Length > methodCount {
                    decl.MethodModifierFlags[methodCount] = methodFlags
                }
                methodCount = methodCount + 1
                pos = signatureEnd
                continue
            }

            decl.MethodFuncIndices[methodCount] = memberStart
            decl.MethodStaticFlags[methodCount] = methodFlags
            if decl.MethodModifierFlags.Length > methodCount {
                decl.MethodModifierFlags[methodCount] = methodFlags
            }
            methodCount = methodCount + 1
            pos = signatureEnd
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < count && tokens.Kinds[memberStart + 1] == 127 {
            if memberModifiers.Values[0] == 1 {
                return -1
            }
            if syntheticCtorNeeded && tokens.Kinds[structIndex] == 9 {
                return -1
            }
            decl.CtorIndices[ctorCount] = memberStart
            ctorCount = ctorCount + 1
            pos = memberStart + 1
        } else if tokens.Kinds[memberStart] == 0 {
            propTypePos := memberStart + 1
            if propTypePos >= count || tokens.Kinds[propTypePos] != 122 {
                return -1
            }
            propTypePos = propTypePos + 1

            propBodyPos := ParseDeclarationTypeSpanCore(tokens, count, propTypePos, fieldTypeResult)
            if propBodyPos < 0 || propBodyPos >= count {
                return -1
            }
            if tokens.Kinds[propBodyPos] != 129 && tokens.Kinds[propBodyPos] != 120 {
                return -1
            }

            decl.PropIndices[propCount] = memberStart
            decl.PropStaticFlags[propCount] = memberModifiers.Values[0]
            propCount = propCount + 1
            pos = propBodyPos

            if tokens.Kinds[pos] == 120 {
                pos = ParseDeclarationExpressionBodyEndCore(tokens, count, pos)
                if pos < 0 {
                    return -1
                }
                continue
            }
        } else {
            return -1
        }

        while pos < count && tokens.Kinds[pos] != 129 && tokens.Kinds[pos] != 130 && tokens.Kinds[pos] != 120 {
            pos = pos + 1
        }
        if pos < count && tokens.Kinds[pos] == 120 {
            pos = ParseDeclarationExpressionBodyEndCore(tokens, count, pos)
            if pos < 0 {
                return -1
            }
            continue
        }
        if pos >= count || tokens.Kinds[pos] != 129 {
            return -1
        }

        depth := 0
        bodyDone := 0
        while pos < count && bodyDone == 0 {
            if tokens.Kinds[pos] == 129 {
                depth = depth + 1
            } else if tokens.Kinds[pos] == 130 {
                depth = depth - 1
                if depth == 0 {
                    bodyDone = 1
                }
            }
            pos = pos + 1
        }
        if bodyDone == 0 {
            return -1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    result.Values[2] = methodCount
    result.Values[3] = ctorCount
    result.Values[4] = propCount
    return fieldCount
}

func ParseDeclarationExpressionBodyEndCore(tokens: ParserDeclarationTokenTable, count: int, arrowIndex: int): int {
    if arrowIndex < 0 || arrowIndex >= count || tokens.Kinds[arrowIndex] != 120 {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserExpressionNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(arrowIndex + 1, 0, 0, 0, 0, 0)
    valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= arrowIndex + 1 {
        return -1
    }

    return st.Pos
}

func ParseConstructorChainInfoCore(tokens: ParserDeclarationTokenTable, count: int, ctorIndex: int, args: ConstructorChainArgTable, result: ParserDeclarationResultTable): int {
    result.Values[0] = 0
    result.Values[1] = -1
    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return 0
    }

    pdepth := 0
    pdone := 0
    while pos < count && pdone == 0 {
        if tokens.Kinds[pos] == 127 {
            pdepth = pdepth + 1
        } else if tokens.Kinds[pos] == 128 {
            pdepth = pdepth - 1
            if pdepth == 0 {
                pdone = 1
            }
        }
        pos = pos + 1
    }
    if pdone == 0 {
        return 0
    }

    if pos >= count || tokens.Kinds[pos] != 122 {
        if pos < count && tokens.Kinds[pos] == 129 {
            result.Values[1] = pos
        }
        return 0
    }
    pos = pos + 1

    if pos >= count {
        return -1
    }
    if tokens.Kinds[pos] == 42 {
        result.Values[0] = 1
    } else if tokens.Kinds[pos] == 43 {
        result.Values[0] = 2
    } else {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    argCount := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if tokens.Kinds[pos] != 0 && tokens.Kinds[pos] != 1 {
            return -1
        }
        args.Kinds[argCount] = tokens.Kinds[pos]
        args.Starts[argCount] = tokens.Starts[pos]
        args.Lengths[argCount] = tokens.ValueLengths[pos]
        argCount = argCount + 1
        pos = pos + 1

        if pos < count && tokens.Kinds[pos] != 128 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }
    pos = pos + 1
    if pos < count && tokens.Kinds[pos] == 129 {
        result.Values[1] = pos
    }
    return argCount
}

func ParseUnionDeclarationCore(tokens: ParserDeclarationTokenTable, count: int, unionIndex: int, decl: UnionDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := unionIndex
    if pos >= count || tokens.Kinds[pos] != 12 {
        return -1
    }
    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }
    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the union name — bare comma-separated
    // Identifiers only, the same shape as the struct/class declaration kernel. A declaration's list
    // cannot nest, so no `>>` splitting is needed.
    typeParamCount := 0
    if pos < count && tokens.Kinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 102 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }
            decl.TypeParamStarts[typeParamCount] = tokens.Starts[pos]
            decl.TypeParamLengths[typeParamCount] = tokens.ValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] != 102 {
                if tokens.Kinds[pos] != 134 {
                    return -1
                }
                pos = pos + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
            }
        }
        if pos >= count || tokens.Kinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }
        pos = pos + 1
    }
    result.Values[2] = typeParamCount

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }
    pos = pos + 1

    caseCount := 0
    totalFields := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 0 {
            return -1
        }
        decl.CaseNameStarts[caseCount] = tokens.Starts[pos]
        decl.CaseNameLengths[caseCount] = tokens.ValueLengths[pos]
        pos = pos + 1

        caseFieldCount := 0
        if pos < count && tokens.Kinds[pos] == 129 {
            pos = pos + 1

            while pos < count && tokens.Kinds[pos] != 130 {
                if tokens.Kinds[pos] != 0 {
                    return -1
                }
                decl.FieldNameStarts[totalFields] = tokens.Starts[pos]
                decl.FieldNameLengths[totalFields] = tokens.ValueLengths[pos]
                pos = pos + 1

                if pos >= count || tokens.Kinds[pos] != 122 {
                    return -1
                }
                pos = pos + 1

                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
                decl.FieldTypeStarts[totalFields] = tokens.Starts[pos]
                decl.FieldTypeLengths[totalFields] = tokens.ValueLengths[pos]
                pos = pos + 1

                totalFields = totalFields + 1
                caseFieldCount = caseFieldCount + 1

                if pos < count && tokens.Kinds[pos] != 130 {
                    if tokens.Kinds[pos] != 134 {
                        return -1
                    }
                    pos = pos + 1
                }
            }

            if pos >= count || tokens.Kinds[pos] != 130 {
                return -1
            }
            pos = pos + 1
        } else if pos >= count || (tokens.Kinds[pos] != 0 && tokens.Kinds[pos] != 130) {
            return -1
        }

        decl.CaseFieldCounts[caseCount] = caseFieldCount
        caseCount = caseCount + 1
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }
    if caseCount == 0 {
        return -1
    }
    return caseCount
}

func ParseFunctionSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, funcIndex: int, outputs: FunctionSignatureInfoOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, ownerIndices: FunctionSignatureOwnerIndexTable, tupleNames: FunctionSignatureTupleNameScratchTable, result: ParserResultTable): int {
    if outputs.FunctionNameTexts.Length < 1 || outputs.ReturnTypeTexts.Length < 1 || result.Values.Length < 6 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(tokens, count, funcIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 || signatureResult.Values[3] < 0 {
        return -1
    }

    bodyStart := signatureResult.Values[6]
    if bodyStart < 0 || bodyStart >= count {
        return -1
    }

    typeParamCount := signatureResult.Values[5]
    whereItemCount := signatureResult.Values[7]
    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length || paramCount > outputs.ParamModifierKinds.Length || paramCount > outputs.ParamDefaultKinds.Length || paramCount > outputs.ParamDefaultTexts.Length || paramCount > outputs.ParamTupleNameCounts.Length {
        return -1
    }

    defaultCount := ParseFunctionParameterDefaultsCore(source, tokens, count, funcIndex, outputs)
    if defaultCount != paramCount {
        return -1
    }

    if typeParamCount > outputs.TypeParamTexts.Length || typeParamCount > outputs.TypeParamSpecials.Length || typeParamCount > outputs.TypeParamConstraintCounts.Length {
        return -1
    }
    declaredTypeParamNames := new FunctionSignatureNameSpanTable(typeParams.Starts, typeParams.Lengths)
    if FunctionSignatureTypeParameterNamesDistinctCore(source, declaredTypeParamNames, typeParamCount) == 0 {
        return -1
    }
    declaredParamNames := new FunctionSignatureNameSpanTable(parameters.NameStarts, parameters.NameLengths)
    if FunctionSignatureParameterNamesDistinctCore(source, declaredParamNames, paramCount) == 0 {
        return -1
    }

    functionName := ""
    if funcIndex < count && tokens.Kinds[funcIndex] == 85 {
        functionName = "op_Implicit"
    } else if funcIndex < count && tokens.Kinds[funcIndex] == 86 {
        functionName = "op_Explicit"
    } else if funcIndex + 2 < count && tokens.Kinds[funcIndex + 1] == 75 {
        functionName = FunctionSignatureOperatorClrName(tokens.Kinds[funcIndex + 2], paramCount)
    } else {
        functionName = FunctionSignatureSpanText(source, signatureResult.Values[3], signatureResult.Values[4])
    }
    if functionName == "" {
        return -1
    }
    outputs.FunctionNameTexts[0] = functionName

    returnTupleNameCount := 0
    returnRoot := signatureResult.Values[1]
    if returnRoot >= 0 {
        outputs.ReturnTypeTexts[0] = TypeReferenceCanonicalTextCore(source, canonicalNodes, returnRoot)
        returnTupleNames := new TypeReferenceTupleNameTable(outputs.ReturnTupleNameTexts)
        returnTupleNameCount = TypeReferenceTupleElementNamesCore(source, canonicalNodes, returnRoot, returnTupleNames)
        if returnTupleNameCount < 0 {
            return -1
        }
    } else {
        outputs.ReturnTypeTexts[0] = "void"
    }

    flatParamTupleNameCount := 0
    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        paramRoot := parameters.TypeRoots[paramIndex]
        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, paramRoot)

        paramTupleNames := new TypeReferenceTupleNameTable(tupleNames.Names)
        tupleNameCount := TypeReferenceTupleElementNamesCore(source, canonicalNodes, paramRoot, paramTupleNames)
        if tupleNameCount < 0 || flatParamTupleNameCount + tupleNameCount > outputs.ParamTupleNameTexts.Length {
            return -1
        }

        outputs.ParamTupleNameCounts[paramIndex] = tupleNameCount
        tupleIndex := 0
        while tupleIndex < tupleNameCount {
            outputs.ParamTupleNameTexts[flatParamTupleNameCount + tupleIndex] = tupleNames.Names[tupleIndex]
            tupleIndex = tupleIndex + 1
        }

        flatParamTupleNameCount = flatParamTupleNameCount + tupleNameCount
        paramIndex = paramIndex + 1
    }

    typeParamIndex := 0
    while typeParamIndex < typeParamCount {
        typeParamName := FunctionSignatureSpanText(source, typeParams.Starts[typeParamIndex], typeParams.Lengths[typeParamIndex])
        if typeParamName == "" {
            return -1
        }

        outputs.TypeParamTexts[typeParamIndex] = typeParamName
        outputs.TypeParamSpecials[typeParamIndex] = 0
        outputs.TypeParamConstraintCounts[typeParamIndex] = 0
        typeParamIndex = typeParamIndex + 1
    }

    flatTypeConstraintCount := 0
    if whereItemCount > 0 {
        if typeParamCount == 0 {
            return -1
        }

        whereNames := new FunctionSignatureNameSpanTable(whereItems.NameStarts, whereItems.NameLengths)
        ownerIndexCount := FunctionSignatureWhereOwnerIndicesCore(source, declaredTypeParamNames, typeParamCount, whereNames, whereItemCount, ownerIndices)
        if ownerIndexCount != whereItemCount {
            return -1
        }

        typeParamIndex = 0
        while typeParamIndex < typeParamCount {
            whereIndex := 0
            while whereIndex < whereItemCount {
                if ownerIndices.Indices[whereIndex] == typeParamIndex {
                    itemCode := whereItems.ItemCodes[whereIndex]
                    if itemCode >= 0 {
                        if flatTypeConstraintCount >= outputs.TypeParamConstraintTypeTexts.Length {
                            return -1
                        }

                        outputs.TypeParamConstraintTypeTexts[flatTypeConstraintCount] = TypeReferenceCanonicalTextCore(source, canonicalNodes, itemCode)
                        outputs.TypeParamConstraintCounts[typeParamIndex] = outputs.TypeParamConstraintCounts[typeParamIndex] + 1
                        flatTypeConstraintCount = flatTypeConstraintCount + 1
                    } else if itemCode == -2 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 1
                    } else if itemCode == -3 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 2
                    } else if itemCode == -4 {
                        outputs.TypeParamSpecials[typeParamIndex] = outputs.TypeParamSpecials[typeParamIndex] | 4
                    } else {
                        return -1
                    }
                }

                whereIndex = whereIndex + 1
            }

            if (outputs.TypeParamSpecials[typeParamIndex] & 3) == 3 || (outputs.TypeParamSpecials[typeParamIndex] & 6) == 6 {
                return -1
            }

            typeParamIndex = typeParamIndex + 1
        }
    }

    result.Values[0] = returnTupleNameCount
    result.Values[1] = bodyStart
    result.Values[2] = typeParamCount
    result.Values[3] = flatTypeConstraintCount
    result.Values[4] = flatParamTupleNameCount
    result.Values[5] = whereItemCount
    return paramCount
}

func FunctionSignatureDefaultKindSupported(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 4
}

func FunctionSignatureDefaultMemberAccessKind(): int {
    return 1000
}

func FunctionSignatureDefaultDottedNameSupported(tokens: ParserTokenTable, startIndex: int, endIndex: int): bool {
    if startIndex < 0 || endIndex <= startIndex || endIndex > tokens.Kinds.Length {
        return false
    }

    identifierCount := 0
    dotCount := 0
    expectIdentifier := true
    i := startIndex
    while i < endIndex {
        kind := tokens.Kinds[i]
        if expectIdentifier {
            if kind != 0 {
                return false
            }
            identifierCount = identifierCount + 1
            expectIdentifier = false
        } else {
            if kind != 124 {
                return false
            }
            dotCount = dotCount + 1
            expectIdentifier = true
        }

        i = i + 1
    }

    return !expectIdentifier && identifierCount >= 2 && dotCount >= 1
}

func ParseFunctionParameterDefaultsCore(source: string, tokens: ParserTokenTable, count: int, funcIndex: int, outputs: FunctionSignatureInfoOutputTable): int {
    if funcIndex < 0 || funcIndex >= count || (tokens.Kinds[funcIndex] != 7 && tokens.Kinds[funcIndex] != 85 && tokens.Kinds[funcIndex] != 86) {
        return -1
    }

    pos := funcIndex + 1
    if tokens.Kinds[funcIndex] == 85 || tokens.Kinds[funcIndex] == 86 {
        if pos >= count || tokens.Kinds[pos] != 75 {
            return -1
        }
        pos = pos + 1
    } else if pos < count && tokens.Kinds[pos] == 75 {
        if pos + 1 >= count || !FunctionSignatureOperatorKindSupported(tokens.Kinds[pos + 1]) {
            return -1
        }
        pos = pos + 2
    } else if pos < count && tokens.Kinds[pos] == 0 {
        pos = pos + 1
    } else {
        return -1
    }

    while pos < count && tokens.Kinds[pos] != 127 {
        pos = pos + 1
    }
    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(0, 0, 0, 0, 0, 0)

    paramCount := 0
    foundDefault := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= outputs.ParamDefaultKinds.Length || paramCount >= outputs.ParamDefaultTexts.Length {
            return -1
        }

        while pos < count && tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                pos = pos + 1
            }
        }

        modifierKind := 0
        while pos < count && (tokens.Kinds[pos] == 78 || tokens.Kinds[pos] == 79 || tokens.Kinds[pos] == 82 || tokens.Kinds[pos] == 42) {
            if tokens.Kinds[pos] == 78 {
                modifierKind = 1
            } else if tokens.Kinds[pos] == 79 {
                modifierKind = 2
            } else if tokens.Kinds[pos] == 82 {
                modifierKind = 3
            } else if tokens.Kinds[pos] == 42 {
                modifierKind = 4
            }
            pos = pos + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }
        pos = pos + 1

        st.Pos = pos
        st.NodeCursor = 0
        st.ChildCursor = 0
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }
        pos = st.Pos
        if pos + 1 < count && tokens.Kinds[pos] == 147 && tokens.Kinds[pos + 1] == 142 {
            pos = pos + 2
        }

        outputs.ParamDefaultKinds[paramCount] = -1
        outputs.ParamDefaultTexts[paramCount] = ""
        outputs.ParamModifierKinds[paramCount] = modifierKind

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenStart := pos
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount == 1 && FunctionSignatureDefaultKindSupported(defaultKind) {
                defaultLength = tokens.ValueLengths[defaultTokenStart]
            } else if FunctionSignatureDefaultDottedNameSupported(tokens, defaultTokenStart, pos) {
                defaultKind = FunctionSignatureDefaultMemberAccessKind()
                defaultLength = tokens.Starts[pos - 1] + tokens.ValueLengths[pos - 1] - defaultStart
            } else {
                return -1
            }

            outputs.ParamDefaultKinds[paramCount] = defaultKind
            outputs.ParamDefaultTexts[paramCount] = FunctionSignatureSpanText(source, defaultStart, defaultLength)
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    return paramCount
}

func FunctionSignatureWhereOwnerIndicesCore(source: string, typeParams: FunctionSignatureNameSpanTable, typeParamCount: int, whereNames: FunctionSignatureNameSpanTable, whereItemCount: int, result: FunctionSignatureOwnerIndexTable): int {
    if typeParamCount < 0 || whereItemCount < 0 || whereItemCount > result.Indices.Length {
        return -1
    }

    w := 0
    while w < whereItemCount {
        ownerIndex := FunctionSignatureTypeParameterIndexOfCore(source, typeParams, typeParamCount, whereNames.Starts[w], whereNames.Lengths[w])
        if ownerIndex < 0 {
            return -1
        }

        result.Indices[w] = ownerIndex
        w = w + 1
    }

    return whereItemCount
}

func FunctionSignatureTypeParameterIndexOfCore(source: string, typeParams: FunctionSignatureNameSpanTable, typeParamCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < typeParamCount {
        if FunctionSignatureSourceSpansEqual(source, typeParams.Starts[i], typeParams.Lengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func FunctionSignatureTypeParameterNamesDistinctCore(source: string, typeParams: FunctionSignatureNameSpanTable, typeParamCount: int): int {
    if typeParamCount < 0 {
        return 0
    }

    i := 0
    while i < typeParamCount {
        if typeParams.Starts[i] < 0 || typeParams.Lengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < typeParamCount {
            if FunctionSignatureSourceSpansEqual(source, typeParams.Starts[i], typeParams.Lengths[i], typeParams.Starts[j], typeParams.Lengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func FunctionSignatureParameterNamesDistinctCore(source: string, parameters: FunctionSignatureNameSpanTable, paramCount: int): int {
    if paramCount < 0 {
        return 0
    }

    i := 0
    while i < paramCount {
        if parameters.Starts[i] < 0 || parameters.Lengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < paramCount {
            if FunctionSignatureSourceSpansEqual(source, parameters.Starts[i], parameters.Lengths[i], parameters.Starts[j], parameters.Lengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func FunctionSignatureSpanText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    return source.Substring(start, length)
}

func FunctionSignatureOperatorKindSupported(kind: int): bool {
    return kind == 44 || kind == 45 || kind == 88 || kind == 89 || kind == 90 || kind == 91 || kind == 92 || kind == 98 || kind == 99 || kind == 100 || kind == 101 || kind == 102 || kind == 103 || kind == 106 || kind == 107 || kind == 108 || kind == 109 || kind == 110 || kind == 111 || kind == 112 || kind == 113 || kind == 114
}

func FunctionSignatureOperatorClrName(kind: int, paramCount: int): string {
    if kind == 44 {
        if paramCount == 1 {
            return "op_True"
        }
        return ""
    }
    if kind == 45 {
        if paramCount == 1 {
            return "op_False"
        }
        return ""
    }
    if kind == 88 {
        if paramCount == 1 {
            return "op_UnaryPlus"
        }
        if paramCount == 2 {
            return "op_Addition"
        }
        return ""
    }
    if kind == 89 {
        if paramCount == 1 {
            return "op_UnaryNegation"
        }
        if paramCount == 2 {
            return "op_Subtraction"
        }
        return ""
    }
    if kind == 90 {
        if paramCount == 2 {
            return "op_Multiply"
        }
        return ""
    }
    if kind == 91 {
        if paramCount == 2 {
            return "op_Division"
        }
        return ""
    }
    if kind == 92 {
        if paramCount == 2 {
            return "op_Modulus"
        }
        return ""
    }
    if kind == 98 {
        if paramCount == 2 {
            return "op_Equality"
        }
        return ""
    }
    if kind == 99 {
        if paramCount == 2 {
            return "op_Inequality"
        }
        return ""
    }
    if kind == 100 {
        if paramCount == 2 {
            return "op_LessThan"
        }
        return ""
    }
    if kind == 101 {
        if paramCount == 2 {
            return "op_LessThanOrEqual"
        }
        return ""
    }
    if kind == 102 {
        if paramCount == 2 {
            return "op_GreaterThan"
        }
        return ""
    }
    if kind == 103 {
        if paramCount == 2 {
            return "op_GreaterThanOrEqual"
        }
        return ""
    }
    if kind == 106 {
        if paramCount == 1 {
            return "op_LogicalNot"
        }
        return ""
    }
    if kind == 107 {
        if paramCount == 2 {
            return "op_BitwiseAnd"
        }
        return ""
    }
    if kind == 108 {
        if paramCount == 2 {
            return "op_BitwiseOr"
        }
        return ""
    }
    if kind == 109 {
        if paramCount == 2 {
            return "op_ExclusiveOr"
        }
        return ""
    }
    if kind == 110 {
        if paramCount == 1 {
            return "op_OnesComplement"
        }
        return ""
    }
    if kind == 111 {
        if paramCount == 2 {
            return "op_LeftShift"
        }
        return ""
    }
    if kind == 112 {
        if paramCount == 2 {
            return "op_RightShift"
        }
        return ""
    }
    if kind == 113 {
        if paramCount == 1 {
            return "op_Increment"
        }
        return ""
    }
    if kind == 114 {
        if paramCount == 1 {
            return "op_Decrement"
        }
        return ""
    }
    return ""
}

func FunctionSignatureSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
    if leftStart < 0 || rightStart < 0 || leftLength != rightLength {
        return false
    }

    if leftStart + leftLength > source.Length || rightStart + rightLength > source.Length {
        return false
    }

    i := 0
    while i < leftLength {
        if source[leftStart + i] != source[rightStart + i] {
            return false
        }

        i = i + 1
    }

    return true
}

func ParseFunctionSignatureCore(
    tokens: ParserTokenTable,
    count: int,
    funcIndex: int,
    typeStack: ParserArgumentStack,
    nodes: ParserNodeTable,
    children: ParserChildIndexTable,
    parameters: ParserFunctionParameterTable,
    typeParams: ParserFunctionTypeParameterTable,
    whereItems: ParserFunctionWhereTable,
    outResult: ParserResultTable): int {
    funcNameStart := -1
    funcNameLength := 0
    returnRoot := -1
    conversionOperatorKind := 0
    st := new ParserState(0, 0, 0, 0, 0, 0)
    i := funcIndex + 1
    if funcIndex >= 0 && funcIndex < count && (tokens.Kinds[funcIndex] == 85 || tokens.Kinds[funcIndex] == 86) {
        conversionOperatorKind = tokens.Kinds[funcIndex]
        if i >= count || tokens.Kinds[i] != 75 {
            return -1
        }
        funcNameStart = tokens.Starts[funcIndex]
        funcNameLength = tokens.Starts[i] + tokens.ValueLengths[i] - tokens.Starts[funcIndex]
        i = i + 1
    } else if i < count && tokens.Kinds[i] == 75 {
        if i + 1 >= count || !FunctionSignatureOperatorKindSupported(tokens.Kinds[i + 1]) {
            return -1
        }
        funcNameStart = tokens.Starts[i]
        funcNameLength = tokens.Starts[i + 1] + tokens.ValueLengths[i + 1] - tokens.Starts[i]
        i = i + 2
    } else if i < count && tokens.Kinds[i] == 0 {
        funcNameStart = tokens.Starts[i]
        funcNameLength = tokens.ValueLengths[i]
        i = i + 1
    }

    // Optional generic TYPE-PARAMETER list `<T, U>`: bare comma-separated Identifiers only, with lifetime
    // parameters (`<'a>`) accepted and ignored for emission metadata. An inline constraint (`<T: Base>`),
    // an empty list, or any other form is unmodelled — return -1 (the host declines to the N# backend path).
    // With no `<`, the list is empty.
    typeParamCount := 0
    if i < count && tokens.Kinds[i] == 100 {
        i = i + 1
        typeParamItemCount := 0
        while i < count && tokens.Kinds[i] != 102 {
            if tokens.Kinds[i] == 0 {
                typeParams.Starts[typeParamCount] = tokens.Starts[i]
                typeParams.Lengths[typeParamCount] = tokens.ValueLengths[i]
                typeParamCount = typeParamCount + 1
            } else if tokens.Kinds[i] != 142 {
                return -1
            }
            typeParamItemCount = typeParamItemCount + 1
            i = i + 1

            if i < count && tokens.Kinds[i] != 102 {
                if tokens.Kinds[i] != 134 {
                    return -1
                }
                i = i + 1
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
                if i >= count || (tokens.Kinds[i] != 0 && tokens.Kinds[i] != 142) {
                    return -1
                }
            }
        }
        if i >= count || tokens.Kinds[i] != 102 || typeParamItemCount == 0 {
            return -1
        }
        i = i + 1
    }

    if conversionOperatorKind != 0 {
        st.Pos = i
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        returnRoot = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if returnRoot < 0 {
            return -1
        }
        i = st.Pos
    }

    // The parameter list `(` must follow the name (and optional type parameters) DIRECTLY. (Previously this
    // scanned blindly to the first `(`, silently skipping a `<T>` list — a generic function then declined
    // later at type resolution; the list is now parsed above, and anything ELSE in the gap is malformed and
    // declines at parse instead of at emit.)
    if i >= count || tokens.Kinds[i] != 127 {
        return -1
    }
    i = i + 1

    paramCount := 0

    while i < count && tokens.Kinds[i] != 128 {
        // Skip attribute lists `[ ... ]` (balanced).
        while i < count && tokens.Kinds[i] == 131 {
            bracketDepth := 1
            i = i + 1
            while i < count && bracketDepth > 0 {
                if tokens.Kinds[i] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[i] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                i = i + 1
            }
        }

        // `ref`/`out` are semantic: they wrap the parsed parameter type in a ByRef node. `params` and `this`
        // are signature modifiers this kernel does not otherwise model.
        byRefParameter := false
        while i < count && (tokens.Kinds[i] == 78 || tokens.Kinds[i] == 79 || tokens.Kinds[i] == 82 || tokens.Kinds[i] == 42) {
            if tokens.Kinds[i] == 78 || tokens.Kinds[i] == 79 {
                byRefParameter = true
            }
            i = i + 1
        }

        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }

        paramNameStart := tokens.Starts[i]
        paramNameLength := tokens.ValueLengths[i]
        i = i + 1

        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }
        i = i + 1

        st.Pos = i
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }
        i = st.Pos
        if byRefParameter {
            childRunStart := st.ChildCursor
            AppendTypeReferenceChild(st, children, typeRoot)
            typeSpanStart := nodes.SpanStarts[typeRoot]
            typeSpanEnd := typeSpanStart + nodes.SpanLengths[typeRoot]
            typeRoot = EmitTypeReferenceNode(st, nodes, 5, -1, 0, childRunStart, 1, typeSpanStart, typeSpanEnd - typeSpanStart)
        }
        if i + 1 < count && tokens.Kinds[i] == 147 && tokens.Kinds[i + 1] == 142 {
            i = i + 2
        }

        parameters.NameStarts[paramCount] = paramNameStart
        parameters.NameLengths[paramCount] = paramNameLength
        parameters.TypeRoots[paramCount] = typeRoot
        paramCount = paramCount + 1

        // Skip a `= default` value without parsing it (balanced to the next depth-0 `,` or `)`).
        if i < count && tokens.Kinds[i] == 93 {
            i = i + 1
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && i < count {
                k := tokens.Kinds[i]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    i = i + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        i = i + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    i = i + 1
                }
            }
        }

        // After a parameter (and its optional default), the next token must cleanly terminate the parameter
        // -- a `,` (another parameter) or `)` (end of the list). Anything else means a malformed parameter
        // (e.g. an unbalanced default value whose depth tracking overshot the list's `)`, or a deferred
        // trailing annotation): refuse with -1 rather than silently mis-parsing the rest of the signature.
        if i >= count || (tokens.Kinds[i] != 134 && tokens.Kinds[i] != 128) {
            return -1
        }

        if tokens.Kinds[i] == 134 {
            i = i + 1
        }
    }

    if i < count && tokens.Kinds[i] == 128 {
        i = i + 1
    }

    if conversionOperatorKind == 0 && i < count && tokens.Kinds[i] == 122 {
        // A `: this(...)` / `: base(...)` CONSTRUCTOR chaining initializer is NOT a return type — leave returnRoot at
        // -1 and stop; the composed constructor parser handles the initializer via ParseConstructorChainInfoCore. A regular
        // function's `: ReturnType` always has a TYPE token after `:`, never `this` (42) / `base` (43), so this
        // branch is constructor-only and leaves function-signature parsing unchanged.
        if !(i + 1 < count && (tokens.Kinds[i + 1] == 42 || tokens.Kinds[i + 1] == 43)) {
            i = i + 1
            st.Pos = i
            st.SplitGreaterDepth = 0
            st.ArgStackTop = 0
            returnRoot = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
            if returnRoot < 0 {
                return -1
            }
            i = st.Pos
        }
    }
    if i + 1 < count && tokens.Kinds[i] == 0 && tokens.Kinds[i + 1] == 142 {
        i = i + 2
    }

    // Generic CONSTRAINT clauses `where T: Item, Item ... where U: Item ...` (D-17b). Each item appends one flat row (owner name span + code); the
    // owner identifier is NOT validated against the declared type parameters here — the host resolves the
    // span against outTypeParamStarts/Lengths (the kernel cannot compare source text). A constraint TYPE
    // parses as another root in the shared node table, exactly like a parameter type; `new` must be
    // followed directly by `(` `)` or the signature is malformed.
    whereItemCount := 0
    while i < count && tokens.Kinds[i] == 53 {
        i = i + 1
        if i >= count || tokens.Kinds[i] != 0 {
            return -1
        }
        whereNameStart := tokens.Starts[i]
        whereNameLength := tokens.ValueLengths[i]
        i = i + 1
        if i >= count || tokens.Kinds[i] != 122 {
            return -1
        }
        i = i + 1

        moreItems := true
        while moreItems {
            itemCode := -1
            if i < count && tokens.Kinds[i] == 8 {
                itemCode = -2
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 9 {
                itemCode = -3
                i = i + 1
            } else if i < count && tokens.Kinds[i] == 41 {
                if i + 2 >= count || tokens.Kinds[i + 1] != 127 || tokens.Kinds[i + 2] != 128 {
                    return -1
                }
                itemCode = -4
                i = i + 3
            } else {
                st.Pos = i
                st.SplitGreaterDepth = 0
                st.ArgStackTop = 0
                itemCode = ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
                if itemCode < 0 {
                    return -1
                }
                i = st.Pos
            }

            whereItems.NameStarts[whereItemCount] = whereNameStart
            whereItems.NameLengths[whereItemCount] = whereNameLength
            whereItems.ItemCodes[whereItemCount] = itemCode
            whereItemCount = whereItemCount + 1

            if i < count && tokens.Kinds[i] == 134 {
                i = i + 1
            } else {
                moreItems = false
            }
        }
    }

    outResult.Values[0] = paramCount
    outResult.Values[1] = returnRoot
    outResult.Values[2] = st.NodeCursor
    outResult.Values[3] = funcNameStart
    outResult.Values[4] = funcNameLength
    outResult.Values[5] = typeParamCount
    outResult.Values[6] = i
    outResult.Values[7] = whereItemCount
    return paramCount
}

func ParseConstructorSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, ctorIndex: int, outputs: ConstructorSignatureOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, result: ParserResultTable): int {
    if result.Values.Length < 4 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(tokens, count, ctorIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 || signatureResult.Values[1] >= 0 || signatureResult.Values[5] != 0 || signatureResult.Values[7] != 0 {
        return -1
    }

    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length {
        return -1
    }
    if paramCount > outputs.ArgKinds.Length || paramCount > outputs.ArgTexts.Length {
        return -1
    }

    defaultCount := ParseConstructorParameterDefaultsCore(source, tokens, count, ctorIndex, outputs)
    if defaultCount != paramCount {
        return -1
    }

    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, parameters.TypeRoots[paramIndex])
        paramIndex = paramIndex + 1
    }

    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    chainArgKinds := new int[](count + 1)
    chainArgStarts := new int[](count + 1)
    chainArgLengths := new int[](count + 1)
    chainArgs := new ConstructorChainArgTable(chainArgKinds, chainArgStarts, chainArgLengths)
    chainResult := new ParserDeclarationResultTable(result.Values)
    chainArgCount := ParseConstructorChainInfoCore(declarationTokens, count, ctorIndex, chainArgs, chainResult)
    if chainArgCount < 0 {
        return -1
    }

    if outputs.ArgTexts.Length < paramCount + chainArgCount || outputs.ArgKinds.Length < paramCount + chainArgCount || outputs.ArgStarts.Length < paramCount + chainArgCount || outputs.ArgLengths.Length < paramCount + chainArgCount {
        return -1
    }

    chainArgIndex := 0
    while chainArgIndex < chainArgCount {
        chainOutputIndex := paramCount + chainArgIndex
        outputs.ArgKinds[chainOutputIndex] = chainArgs.Kinds[chainArgIndex]
        outputs.ArgStarts[chainOutputIndex] = chainArgs.Starts[chainArgIndex]
        outputs.ArgLengths[chainOutputIndex] = chainArgs.Lengths[chainArgIndex]
        outputs.ArgTexts[chainOutputIndex] = source.Substring(chainArgs.Starts[chainArgIndex], chainArgs.Lengths[chainArgIndex])
        chainArgIndex = chainArgIndex + 1
    }

    bodyBrace := result.Values[1]
    if bodyBrace < 0 || bodyBrace >= count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    result.Values[2] = paramCount
    result.Values[3] = chainArgCount
    return paramCount
}

func ConstructorSignatureDefaultKindSupported(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 4
}

func ParseConstructorParameterDefaultsCore(source: string, tokens: ParserTokenTable, count: int, ctorIndex: int, outputs: ConstructorSignatureOutputTable): int {
    if ctorIndex < 0 || ctorIndex >= count || tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }
    pos = pos + 1

    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(0, 0, 0, 0, 0, 0)

    paramCount := 0
    foundDefault := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= outputs.ArgKinds.Length || paramCount >= outputs.ArgTexts.Length {
            return -1
        }

        while pos < count && tokens.Kinds[pos] == 131 {
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }
                pos = pos + 1
            }
        }

        while pos < count && (tokens.Kinds[pos] == 78 || tokens.Kinds[pos] == 79 || tokens.Kinds[pos] == 82 || tokens.Kinds[pos] == 42) {
            pos = pos + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }
        pos = pos + 1

        st.Pos = pos
        st.NodeCursor = 0
        st.ChildCursor = 0
        st.SplitGreaterDepth = 0
        st.ArgStackTop = 0
        typeRoot := ParseUnionTypeReferenceNodeCore(tokens, count, st, typeStack, nodes, children, 0)
        if typeRoot < 0 {
            return -1
        }
        pos = st.Pos

        outputs.ArgKinds[paramCount] = -1
        outputs.ArgTexts[paramCount] = ""

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount != 1 || !ConstructorSignatureDefaultKindSupported(defaultKind) {
                return -1
            }

            outputs.ArgKinds[paramCount] = defaultKind
            outputs.ArgTexts[paramCount] = FunctionSignatureSpanText(source, defaultStart, defaultLength)
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    return paramCount
}

func ParseInterfaceDeclarationSignatureInfoCore(source: string, tokens: ParserTokenTable, count: int, interfaceIndex: int, baseOutputs: InterfaceSignatureBaseOutputTable, methodOutputs: InterfaceSignatureMethodOutputTable, typeStack: ParserArgumentStack, nodes: ParserNodeTable, children: ParserChildIndexTable, canonicalNodes: TypeReferenceCanonicalTable, tupleNodes: InterfaceSignatureTupleNodeTable, parameters: ParserFunctionParameterTable, typeParams: ParserFunctionTypeParameterTable, whereItems: ParserFunctionWhereTable, signatureResult: ParserResultTable, result: ParserResultTable): int {
    if result.Values.Length < 5 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    declaration := new InterfaceDeclarationTable(methodOutputs.FuncIndices, baseOutputs.BaseNameStarts, baseOutputs.BaseNameLengths, new int[](count + 1), new int[](count + 1))
    declarationResult := new ParserDeclarationResultTable(result.Values)
    methodCount := ParseInterfaceDeclarationCore(declarationTokens, count, interfaceIndex, declaration, declarationResult)
    if methodCount < 0 {
        return -1
    }

    baseCount := result.Values[2]
    typeParamCount := result.Values[4]
    if baseOutputs.InterfaceNameTexts.Length < 1 || baseCount > baseOutputs.BaseNameTexts.Length || typeParamCount > baseOutputs.TypeParamTexts.Length {
        return -1
    }
    declaredInterfaceTypeParamNames := new FunctionSignatureNameSpanTable(declaration.TypeParamStarts, declaration.TypeParamLengths)
    if FunctionSignatureTypeParameterNamesDistinctCore(source, declaredInterfaceTypeParamNames, typeParamCount) == 0 {
        return -1
    }

    interfaceName := ParserDeclarationSpanText(source, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }
    baseOutputs.InterfaceNameTexts[0] = interfaceName

    baseIndex := 0
    while baseIndex < baseCount {
        baseName := ParserDeclarationCanonicalTypeText(source, declaration.BaseNameStarts[baseIndex], declaration.BaseNameLengths[baseIndex])
        if baseName == "" {
            return -1
        }

        baseOutputs.BaseNameTexts[baseIndex] = baseName
        baseIndex = baseIndex + 1
    }

    typeParamIndex := 0
    while typeParamIndex < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, declaration.TypeParamStarts[typeParamIndex], declaration.TypeParamLengths[typeParamIndex])
        if typeParamName == "" {
            return -1
        }

        baseOutputs.TypeParamTexts[typeParamIndex] = typeParamName
        typeParamIndex = typeParamIndex + 1
    }

    if methodCount > methodOutputs.NameTexts.Length || methodCount > methodOutputs.ReturnTexts.Length || methodCount > methodOutputs.ParamCounts.Length || methodCount > methodOutputs.BodyFlags.Length {
        return -1
    }

    flatParamCount := 0
    methodIndex := 0
    while methodIndex < methodCount {
        paramCount := ParseFunctionSignatureCore(tokens, count, methodOutputs.FuncIndices[methodIndex], typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
        if paramCount < 0 || signatureResult.Values[3] < 0 {
            return -1
        }

        if signatureResult.Values[5] > 0 || signatureResult.Values[7] > 0 {
            return -1
        }

        afterSignature := signatureResult.Values[6]
        if afterSignature < 0 || afterSignature >= count {
            return -1
        }

        methodName := FunctionSignatureSpanText(source, signatureResult.Values[3], signatureResult.Values[4])
        if methodName == "" {
            return -1
        }
        methodOutputs.NameTexts[methodIndex] = methodName

        returnRoot := signatureResult.Values[1]
        if returnRoot >= 0 {
            if ParseInterfaceSignatureHasTupleNamesCore(tupleNodes, returnRoot) != 0 {
                return -1
            }

            methodOutputs.ReturnTexts[methodIndex] = TypeReferenceCanonicalTextCore(source, canonicalNodes, returnRoot)
        } else {
            methodOutputs.ReturnTexts[methodIndex] = "void"
        }

        if flatParamCount + paramCount > methodOutputs.ParamNameTexts.Length || flatParamCount + paramCount > methodOutputs.ParamTypeTexts.Length {
            return -1
        }

        paramIndex := 0
        while paramIndex < paramCount {
            paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
            if paramName == "" {
                return -1
            }

            paramRoot := parameters.TypeRoots[paramIndex]
            if ParseInterfaceSignatureHasTupleNamesCore(tupleNodes, paramRoot) != 0 {
                return -1
            }

            flatSlot := flatParamCount + paramIndex
            methodOutputs.ParamNameTexts[flatSlot] = paramName
            methodOutputs.ParamTypeTexts[flatSlot] = TypeReferenceCanonicalTextCore(source, canonicalNodes, paramRoot)
            paramIndex = paramIndex + 1
        }

        methodOutputs.ParamCounts[methodIndex] = paramCount
        flatParamCount = flatParamCount + paramCount

        if tokens.Kinds[afterSignature] == 129 {
            methodOutputs.BodyFlags[methodIndex] = 1
        } else if tokens.Kinds[afterSignature] == 7 || tokens.Kinds[afterSignature] == 130 {
            methodOutputs.BodyFlags[methodIndex] = 0
        } else {
            return -1
        }

        methodIndex = methodIndex + 1
    }

    result.Values[3] = flatParamCount
    return methodCount
}

func ParseInterfaceSignatureHasTupleNamesCore(nodes: InterfaceSignatureTupleNodeTable, root: int): int {
    if root < 0 || root >= nodes.Kinds.Length || nodes.Kinds[root] != 6 || nodes.ChildCount[root] == 0 {
        return 0
    }

    run := nodes.ChildStart[root]
    first := nodes.ChildIndices[run]
    if nodes.Kinds[first] != 7 {
        return 0
    }

    i := 0
    while i < nodes.ChildCount[root] {
        elem := nodes.ChildIndices[run + i]
        if nodes.Kinds[elem] != 7 {
            return -1
        }

        i = i + 1
    }

    return 1
}

func DirectLocalFunctionTokenIndicesCore(tokens: LocalFunctionTokenTable, nodes: LocalFunctionNodeTable, rootBlock: int, results: LocalFunctionResultTable): int {
    if rootBlock < 0 || rootBlock >= nodes.Kinds.Length {
        return -1
    }

    if nodes.Kinds[rootBlock] != 25 {
        return 0
    }

    childRun := nodes.ChildStart[rootBlock]
    childCount := nodes.ChildCount[rootBlock]
    if childRun < 0 || childCount < 0 {
        return -1
    }

    resultCount := 0
    childIndex := 0
    declarationTokens := new ParserDeclarationStartKindStream(tokens.Kinds, tokens.Starts)
    while childIndex < childCount {
        stmtNode := nodes.ChildIndices[childRun + childIndex]
        if stmtNode < 0 || stmtNode >= nodes.Kinds.Length {
            return -1
        }

        if nodes.Kinds[stmtNode] == 41 {
            if resultCount >= results.NodeIndices.Length || resultCount >= results.FuncTokenIndices.Length {
                return -1
            }

            funcTokenIndex := TokenIndexByKindStartCore(declarationTokens, tokens.Count, 7, nodes.ValueStarts[stmtNode])
            if funcTokenIndex < 0 {
                return -1
            }

            results.NodeIndices[resultCount] = stmtNode
            results.FuncTokenIndices[resultCount] = funcTokenIndex
            resultCount = resultCount + 1
        }

        childIndex = childIndex + 1
    }

    return resultCount
}

func ParseColumnarProductFunctionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, isLocalFunction: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamModifierKinds: int[], outParamDefaultKinds: int[], outParamDefaultTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outLocalFunctionNodeIndices: int[], outLocalFunctionTokenIndices: int[], outResult: int[]): int {
    tokens := new ColumnarFunctionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(outFunctionNameTexts, outReturnTypeTexts, outParamNameTexts, outParamTypeTexts, outParamModifierKinds, outParamDefaultKinds, outParamDefaultTexts, outParamTupleNameCounts, outParamTupleNameTexts, outReturnTupleNameTexts, outTypeParamTexts, outTypeParamSpecials, outTypeParamConstraintCounts, outTypeParamConstraintTypeTexts)
    body := new ColumnarFunctionBodyTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
    locals := new ColumnarFunctionLocalTable(outLocalFunctionNodeIndices, outLocalFunctionTokenIndices)
    result := new ColumnarFunctionResultTable(outResult)
    return ParseColumnarFunctionInfoCore(source, tokens, funcIndex, isLocalFunction, signatureOutputs, body, locals, result)
}

func ParseColumnarProductFunctionSignatureInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, funcIndex: int, outFunctionNameTexts: string[], outReturnTypeTexts: string[], outParamNameTexts: string[], outParamTypeTexts: string[], outParamModifierKinds: int[], outParamDefaultKinds: int[], outParamDefaultTexts: string[], outParamTupleNameCounts: int[], outParamTupleNameTexts: string[], outReturnTupleNameTexts: string[], outTypeParamTexts: string[], outTypeParamSpecials: int[], outTypeParamConstraintCounts: int[], outTypeParamConstraintTypeTexts: string[], outResult: int[]): int {
    tokens := new ColumnarFunctionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(outFunctionNameTexts, outReturnTypeTexts, outParamNameTexts, outParamTypeTexts, outParamModifierKinds, outParamDefaultKinds, outParamDefaultTexts, outParamTupleNameCounts, outParamTupleNameTexts, outReturnTupleNameTexts, outTypeParamTexts, outTypeParamSpecials, outTypeParamConstraintCounts, outTypeParamConstraintTypeTexts)
    return ParseColumnarFunctionSignatureOnlyInfoCore(source, tokens, funcIndex, signatureOutputs, new ColumnarFunctionResultTable(outResult))
}

func ParseColumnarFunctionSignatureOnlyInfoCore(source: string, tokens: ColumnarFunctionTokenTable, funcIndex: int, signatureOutputs: ColumnarFunctionSignatureOutputTable, result: ColumnarFunctionResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    signatureOutput := new FunctionSignatureInfoOutputTable(signatureOutputs.FunctionNameTexts, signatureOutputs.ReturnTypeTexts, signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ParamModifierKinds, signatureOutputs.ParamDefaultKinds, signatureOutputs.ParamDefaultTexts, signatureOutputs.ParamTupleNameCounts, signatureOutputs.ParamTupleNameTexts, signatureOutputs.ReturnTupleNameTexts, signatureOutputs.TypeParamTexts, signatureOutputs.TypeParamSpecials, signatureOutputs.TypeParamConstraintCounts, signatureOutputs.TypeParamConstraintTypeTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    ownerIndices := new FunctionSignatureOwnerIndexTable(new int[](tokens.Count + 1))
    tupleNames := new FunctionSignatureTupleNameScratchTable(new string[](tokens.Count + 1))
    signatureResult := new ParserResultTable(result.Values)
    return ParseFunctionSignatureInfoCore(source, signatureTokens, tokens.Count, funcIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, ownerIndices, tupleNames, signatureResult)
}

func ParseColumnarFunctionInfoCore(source: string, tokens: ColumnarFunctionTokenTable, funcIndex: int, isLocalFunction: int, signatureOutputs: ColumnarFunctionSignatureOutputTable, body: ColumnarFunctionBodyTable, locals: ColumnarFunctionLocalTable, result: ColumnarFunctionResultTable): int {
    if result.Values.Length < 9 {
        return -1
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    signatureOutput := new FunctionSignatureInfoOutputTable(signatureOutputs.FunctionNameTexts, signatureOutputs.ReturnTypeTexts, signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ParamModifierKinds, signatureOutputs.ParamDefaultKinds, signatureOutputs.ParamDefaultTexts, signatureOutputs.ParamTupleNameCounts, signatureOutputs.ParamTupleNameTexts, signatureOutputs.ReturnTupleNameTexts, signatureOutputs.TypeParamTexts, signatureOutputs.TypeParamSpecials, signatureOutputs.TypeParamConstraintCounts, signatureOutputs.TypeParamConstraintTypeTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    ownerIndices := new FunctionSignatureOwnerIndexTable(new int[](tokens.Count + 1))
    tupleNames := new FunctionSignatureTupleNameScratchTable(new string[](tokens.Count + 1))
    signatureResult := new ParserResultTable(new int[](6))
    paramCount := ParseFunctionSignatureInfoCore(source, signatureTokens, tokens.Count, funcIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, ownerIndices, tupleNames, signatureResult)
    if paramCount < 0 {
        return -1
    }
    if isLocalFunction != 0 && signatureResult.Values[2] > 0 {
        return -1
    }

    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || (tokens.Kinds[bodyBrace] != 129 && tokens.Kinds[bodyBrace] != 120) {
        return -1
    }

    bodyResult := new ColumnarFunctionResultTable(new int[](2))
    bodyNodeCount := 0
    if tokens.Kinds[bodyBrace] == 129 {
        bodyNodeCount = ParseColumnarFunctionBodyNodesCore(source, tokens, bodyBrace, body, bodyResult)
    } else {
        bodyNodeCount = ParseColumnarFunctionExpressionBodyNodesCore(tokens, bodyBrace, body, bodyResult)
    }
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
    localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
    localResults := new LocalFunctionResultTable(locals.NodeIndices, locals.TokenIndices)
    localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, bodyRoot, localResults)
    if localFunctionCount < 0 {
        return -1
    }
    if ColumnarFunctionLocalFunctionNamesDistinct(source, tokens, locals, localFunctionCount) == 0 {
        return -1
    }
    if isLocalFunction != 0 && localFunctionCount > 0 {
        return -1
    }

    result.Values[0] = signatureResult.Values[0]
    result.Values[1] = bodyBrace
    result.Values[2] = signatureResult.Values[2]
    result.Values[3] = signatureResult.Values[3]
    result.Values[4] = signatureResult.Values[4]
    result.Values[5] = signatureResult.Values[5]
    result.Values[6] = bodyRoot
    result.Values[7] = bodyNodeCount
    result.Values[8] = localFunctionCount
    return paramCount
}

func ParseColumnarFunctionBodyNodesCore(source: string, tokens: ColumnarFunctionTokenTable, bodyBrace: int, body: ColumnarFunctionBodyTable, result: ColumnarFunctionResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}

func ParseColumnarFunctionExpressionBodyNodesCore(tokens: ColumnarFunctionTokenTable, arrowIndex: int, body: ColumnarFunctionBodyTable, result: ColumnarFunctionResultTable): int {
    if arrowIndex < 0 || arrowIndex >= tokens.Count || tokens.Kinds[arrowIndex] != 120 || result.Values.Length < 2 {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    st := new ParserState(arrowIndex + 1, 0, 0, 0, 0, 0)
    valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= arrowIndex + 1 {
        return -1
    }

    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, valueRoot)
    valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
    returnNode := EmitExpressionNode(st, nodes, 20, -1, 0, childRunStart, 1, tokens.Starts[arrowIndex], valueEnd - tokens.Starts[arrowIndex])
    result.Values[0] = returnNode
    result.Values[1] = st.Pos
    return st.NodeCursor
}

func ColumnarFunctionLocalFunctionNamesDistinct(source: string, tokens: ColumnarFunctionTokenTable, locals: ColumnarFunctionLocalTable, localFunctionCount: int): int {
    if localFunctionCount < 0 {
        return 0
    }

    i := 0
    while i < localFunctionCount {
        nameToken := locals.TokenIndices[i] + 1
        if nameToken < 0 || nameToken >= tokens.Count || tokens.Kinds[nameToken] != 0 {
            return 0
        }

        j := i + 1
        while j < localFunctionCount {
            otherNameToken := locals.TokenIndices[j] + 1
            if otherNameToken < 0 || otherNameToken >= tokens.Count || tokens.Kinds[otherNameToken] != 0 {
                return 0
            }

            if ColumnarFunctionSourceSpansEqual(source, tokens.Starts[nameToken], tokens.ValueLengths[nameToken], tokens.Starts[otherNameToken], tokens.ValueLengths[otherNameToken]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarFunctionSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
    if leftStart < 0 || rightStart < 0 || leftLength != rightLength {
        return false
    }

    if leftStart + leftLength > source.Length || rightStart + rightLength > source.Length {
        return false
    }

    i := 0
    while i < leftLength {
        if source[leftStart + i] != source[rightStart + i] {
            return false
        }

        i = i + 1
    }

    return true
}

func ParseColumnarConstructorInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, ctorIndex: int, outParamNameTexts: string[], outParamTypeTexts: string[], outArgKinds: int[], outArgStarts: int[], outArgLengths: int[], outArgTexts: string[], outNodeKinds: int[], outValueStarts: int[], outValueLengths: int[], outChildStart: int[], outChildCount: int[], outChildIndices: int[], outSpanStarts: int[], outSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarConstructorTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    signatureOutputs := new ColumnarConstructorSignatureOutputTable(outParamNameTexts, outParamTypeTexts, outArgKinds, outArgStarts, outArgLengths, outArgTexts)
    body := new ColumnarConstructorBodyTable(outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, outChildIndices, outSpanStarts, outSpanLengths)
    result := new ColumnarConstructorResultTable(outResult)
    return ParseColumnarConstructorInfoCore(source, tokens, ctorIndex, signatureOutputs, body, result)
}

func ParseColumnarConstructorInfoCore(source: string, tokens: ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: ColumnarConstructorSignatureOutputTable, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    if ctorIndex >= 0 && ctorIndex < tokens.Count && (tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 9 || tokens.Kinds[ctorIndex] == 13) {
        return ParseColumnarPrimaryConstructorInfoCore(source, tokens, ctorIndex, signatureOutputs, body, result)
    }

    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    signatureOutput := new ConstructorSignatureOutputTable(signatureOutputs.ParamNameTexts, signatureOutputs.ParamTypeTexts, signatureOutputs.ArgKinds, signatureOutputs.ArgStarts, signatureOutputs.ArgLengths, signatureOutputs.ArgTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    functionSignatureResult := new ParserResultTable(new int[](8))
    signatureResult := new ParserResultTable(new int[](4))
    paramCount := ParseConstructorSignatureInfoCore(source, signatureTokens, tokens.Count, ctorIndex, signatureOutput, typeStack, nodes, children, canonicalNodes, parameters, typeParams, whereItems, functionSignatureResult, signatureResult)
    if paramCount < 0 {
        return -1
    }
    bodyBrace := signatureResult.Values[1]
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    bodyResult := new ColumnarConstructorResultTable(new int[](2))
    bodyNodeCount := ParseColumnarConstructorBodyNodesCore(source, tokens, bodyBrace, body, bodyResult)
    if bodyNodeCount <= 0 {
        return -1
    }

    bodyRoot := bodyResult.Values[0]
    if bodyRoot < 0 || bodyRoot >= bodyNodeCount {
        return -1
    }

    result.Values[0] = signatureResult.Values[0]
    result.Values[1] = bodyBrace
    result.Values[2] = signatureResult.Values[2]
    result.Values[3] = signatureResult.Values[3]
    result.Values[4] = bodyRoot
    result.Values[5] = bodyNodeCount
    return paramCount
}

func ColumnarPrimaryConstructorLiteralExpressionKind(tokenKind: int): int {
    if tokenKind == 1 {
        return 0
    }
    if tokenKind == 2 {
        return 1
    }
    if tokenKind == 3 {
        return 2
    }
    if tokenKind == 4 {
        return 3
    }
    if tokenKind == 44 || tokenKind == 45 {
        return 4
    }
    if tokenKind == 46 {
        return 5
    }

    return -1
}

func ColumnarPrimaryConstructorTypeIsNullable(source: string, typeStart: int, typeLength: int): bool {
    if typeStart < 0 || typeLength <= 0 || typeStart + typeLength > source.Length {
        return false
    }

    return source[typeStart + typeLength - 1] == '?'
}

func EmitColumnarPrimaryConstructorAssignmentNode(body: ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueKind: int, valueStart: int, valueLength: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }
    if nodeCursor + 4 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    valueNode := nodeCursor
    body.NodeKinds[valueNode] = valueKind
    body.ValueStarts[valueNode] = valueStart
    body.ValueLengths[valueNode] = valueLength
    body.ChildStart[valueNode] = -1
    body.ChildCount[valueNode] = 0
    body.SpanStarts[valueNode] = valueStart
    body.SpanLengths[valueNode] = valueLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueNode
    body.SpanStarts[assignmentNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[assignmentNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[assignmentNode] = fieldLength
    }
    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    if valueStart >= 0 {
        body.SpanLengths[statementNode] = valueStart + valueLength - fieldStart
    } else {
        body.SpanLengths[statementNode] = fieldLength
    }
    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func EmitColumnarPrimaryConstructorAssignmentRootNode(body: ColumnarConstructorBodyTable, fieldStart: int, fieldLength: int, valueRoot: int, eqStart: int, eqLength: int, nodeCursor: int, childCursor: int, result: ColumnarConstructorResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }
    if valueRoot < 0 || valueRoot >= nodeCursor || nodeCursor + 3 > body.NodeKinds.Length || childCursor + 3 > body.ChildIndices.Length {
        return -1
    }

    targetNode := nodeCursor
    body.NodeKinds[targetNode] = 6
    body.ValueStarts[targetNode] = fieldStart
    body.ValueLengths[targetNode] = fieldLength
    body.ChildStart[targetNode] = -1
    body.ChildCount[targetNode] = 0
    body.SpanStarts[targetNode] = fieldStart
    body.SpanLengths[targetNode] = fieldLength
    nodeCursor = nodeCursor + 1

    assignmentNode := nodeCursor
    body.NodeKinds[assignmentNode] = 14
    body.ValueStarts[assignmentNode] = eqStart
    body.ValueLengths[assignmentNode] = eqLength
    body.ChildStart[assignmentNode] = childCursor
    body.ChildCount[assignmentNode] = 2
    body.ChildIndices[childCursor] = targetNode
    body.ChildIndices[childCursor + 1] = valueRoot
    body.SpanStarts[assignmentNode] = fieldStart
    body.SpanLengths[assignmentNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 2
    nodeCursor = nodeCursor + 1

    statementNode := nodeCursor
    body.NodeKinds[statementNode] = 23
    body.ValueStarts[statementNode] = -1
    body.ValueLengths[statementNode] = 0
    body.ChildStart[statementNode] = childCursor
    body.ChildCount[statementNode] = 1
    body.ChildIndices[childCursor] = assignmentNode
    body.SpanStarts[statementNode] = fieldStart
    body.SpanLengths[statementNode] = body.SpanStarts[valueRoot] + body.SpanLengths[valueRoot] - fieldStart
    childCursor = childCursor + 1
    nodeCursor = nodeCursor + 1

    result.Values[0] = nodeCursor
    result.Values[1] = childCursor
    return statementNode
}

func ParseColumnarPrimaryConstructorInfoCore(source: string, tokens: ColumnarConstructorTokenTable, ctorIndex: int, signatureOutputs: ColumnarConstructorSignatureOutputTable, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    pos := ctorIndex + 1
    // `record struct Name(...)` — skip the record-struct TAIL Struct token before the name.
    if pos < tokens.Count && tokens.Kinds[ctorIndex] == 13 && tokens.Kinds[pos] == 9 {
        pos = pos + 1
    }
    if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
        return -1
    }
    pos = pos + 1

    if pos < tokens.Count && tokens.Kinds[pos] == 100 {
        gdepth := 0
        gdone := 0
        while pos < tokens.Count && gdone == 0 {
            if tokens.Kinds[pos] == 100 {
                gdepth = gdepth + 1
            } else if tokens.Kinds[pos] == 102 {
                gdepth = gdepth - 1
                if gdepth == 0 {
                    gdone = 1
                }
            } else if tokens.Kinds[pos] == 112 {
                gdepth = gdepth - 2
                if gdepth == 0 {
                    gdone = 1
                }
            }
            if gdepth < 0 {
                return -1
            }
            pos = pos + 1
        }
        if gdone == 0 {
            return -1
        }
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    primaryParameters := new PrimaryConstructorParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    primaryResult := new ParserDeclarationResultTable(new int[](1))
    paramCount := 0
    if pos < tokens.Count && tokens.Kinds[pos] == 127 {
        paramCount = ParsePrimaryConstructorParameterSpansCore(source, declarationTokens, tokens.Count, pos, primaryParameters, primaryResult)
    } else {
        primaryResult.Values[0] = pos
    }
    if paramCount < 0 || paramCount > signatureOutputs.ParamNameTexts.Length || paramCount > signatureOutputs.ParamTypeTexts.Length || paramCount > signatureOutputs.ArgKinds.Length || paramCount > signatureOutputs.ArgTexts.Length {
        return -1
    }

    p := 0
    while p < paramCount {
        paramName := ParserDeclarationSpanText(source, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p])
        paramType := ParserDeclarationCanonicalTypeText(source, primaryParameters.TypeStarts[p], primaryParameters.TypeLengths[p])
        if paramName == "" || paramType == "" {
            return -1
        }

        signatureOutputs.ParamNameTexts[p] = paramName
        signatureOutputs.ParamTypeTexts[p] = paramType
        signatureOutputs.ArgKinds[p] = primaryParameters.DefaultKinds[p]
        if primaryParameters.DefaultKinds[p] >= 0 {
            signatureOutputs.ArgTexts[p] = ParserDeclarationSpanText(source, primaryParameters.DefaultStarts[p], primaryParameters.DefaultLengths[p])
        } else {
            signatureOutputs.ArgTexts[p] = ""
        }
        p = p + 1
    }

    pos = primaryResult.Values[0]
    if pos < tokens.Count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
                return -1
            }
            pos = pos + 1
            if pos < tokens.Count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }
            break
        }
    }

    bodyBrace := pos
    if bodyBrace < 0 || bodyBrace >= tokens.Count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    statementIndices := new int[](tokens.Count + 1)
    assignedFlags := new int[](tokens.Count + 1)
    nodeCursor := 0
    childCursor := 0
    assignmentCount := 0
    cursorResult := new ColumnarConstructorResultTable(new int[](2))
    typeResult := new ParserDeclarationResultTable(new int[](2))
    memberModifierValues := new int[](2)
    memberModifiers := new ParserDeclarationResultTable(memberModifierValues)
    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    expressionNodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    expressionChildren := new ParserChildIndexTable(body.ChildIndices)
    expressionStack := new ParserArgumentStack(new int[](tokens.Count + 1))

    scan := bodyBrace + 1
    scanDone := 0
    while scanDone == 0 && scan < tokens.Count && tokens.Kinds[scan] != 130 && tokens.Kinds[scan] != 7 {
        memberStart := ParseMemberModifierPrefixCore(declarationTokens, tokens.Count, scan, memberModifiers)
        if memberStart < 0 || memberStart >= tokens.Count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || (tokens.Kinds[memberStart] == 0 && memberStart + 1 < tokens.Count && tokens.Kinds[memberStart + 1] == 127) {
            scanDone = 1
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < tokens.Count && tokens.Kinds[memberStart + 1] == 122 {
            fieldNameStart := tokens.Starts[memberStart]
            fieldNameLength := tokens.ValueLengths[memberStart]
            scan = memberStart + 2
            scan = ParseDeclarationTypeSpanCore(declarationTokens, tokens.Count, scan, typeResult)
            if scan < 0 {
                return -1
            }

            if scan < tokens.Count && tokens.Kinds[scan] == 129 {
                pdepth := 0
                pdone := 0
                while scan < tokens.Count && pdone == 0 {
                    if tokens.Kinds[scan] == 129 {
                        pdepth = pdepth + 1
                    } else if tokens.Kinds[scan] == 130 {
                        pdepth = pdepth - 1
                        if pdepth == 0 {
                            pdone = 1
                        }
                    }
                    scan = scan + 1
                }
                if pdone == 0 {
                    return -1
                }
            } else if scan < tokens.Count && tokens.Kinds[scan] == 120 {
                while scan < tokens.Count && tokens.Kinds[scan] != 136 && tokens.Kinds[scan] != 130 {
                    scan = scan + 1
                }
                if scan < tokens.Count && tokens.Kinds[scan] == 136 {
                    scan = scan + 1
                }
            } else {
                valueKind := -1
                valueStart := -1
                valueLength := 0
                eqStart := -1
                eqLength := 1
                valueRoot := -1
                if scan < tokens.Count && tokens.Kinds[scan] == 93 {
                    eqStart = tokens.Starts[scan]
                    eqLength = tokens.ValueLengths[scan]
                    scan = scan + 1
                    if scan >= tokens.Count {
                        return -1
                    }
                    if tokens.Kinds[scan] == 0 {
                        paramIndex := PrimaryConstructorParameterIndexOf(source, primaryParameters, paramCount, tokens.Starts[scan], tokens.ValueLengths[scan])
                        if paramIndex >= 0 {
                            assignedFlags[paramIndex] = 1
                            valueKind = 6
                            valueStart = tokens.Starts[scan]
                            valueLength = tokens.ValueLengths[scan]
                            scan = scan + 1
                        } else {
                            expressionState := new ParserState(scan, nodeCursor, childCursor, 0, 0, 0)
                            valueRoot = ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, expressionState, expressionStack, expressionNodes, expressionChildren, 0)
                            if valueRoot < 0 || expressionState.Pos <= scan {
                                return -1
                            }
                            nodeCursor = expressionState.NodeCursor
                            childCursor = expressionState.ChildCursor
                            scan = expressionState.Pos
                        }
                    } else {
                        valueKind = ColumnarPrimaryConstructorLiteralExpressionKind(tokens.Kinds[scan])
                        if valueKind >= 0 {
                            valueStart = tokens.Starts[scan]
                            valueLength = tokens.ValueLengths[scan]
                            scan = scan + 1
                        } else {
                            expressionState := new ParserState(scan, nodeCursor, childCursor, 0, 0, 0)
                            valueRoot = ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, expressionState, expressionStack, expressionNodes, expressionChildren, 0)
                            if valueRoot < 0 || expressionState.Pos <= scan {
                                return -1
                            }
                            nodeCursor = expressionState.NodeCursor
                            childCursor = expressionState.ChildCursor
                            scan = expressionState.Pos
                        }
                    }
                } else if ColumnarPrimaryConstructorTypeIsNullable(source, typeResult.Values[0], typeResult.Values[1]) {
                    valueKind = 5
                } else {
                    matchedParam := PrimaryConstructorParameterIndexOf(source, primaryParameters, paramCount, fieldNameStart, fieldNameLength)
                    if matchedParam >= 0 {
                        assignedFlags[matchedParam] = 1
                        valueKind = 6
                        valueStart = primaryParameters.NameStarts[matchedParam]
                        valueLength = primaryParameters.NameLengths[matchedParam]
                    }
                }

                if valueKind >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentNode(body, fieldNameStart, fieldNameLength, valueKind, valueStart, valueLength, eqStart, eqLength, nodeCursor, childCursor, cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }
                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                } else if valueRoot >= 0 && memberModifiers.Values[0] == 0 {
                    statementNode := EmitColumnarPrimaryConstructorAssignmentRootNode(body, fieldNameStart, fieldNameLength, valueRoot, eqStart, eqLength, nodeCursor, childCursor, cursorResult)
                    if statementNode < 0 || assignmentCount >= statementIndices.Length {
                        return -1
                    }
                    nodeCursor = cursorResult.Values[0]
                    childCursor = cursorResult.Values[1]
                    statementIndices[assignmentCount] = statementNode
                    assignmentCount = assignmentCount + 1
                }
            }
        } else {
            return -1
        }
    }

    if tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 13 {
        p = 0
        while p < paramCount {
            if assignedFlags[p] == 0 {
                statementNode := EmitColumnarPrimaryConstructorAssignmentNode(body, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], 6, primaryParameters.NameStarts[p], primaryParameters.NameLengths[p], -1, 1, nodeCursor, childCursor, cursorResult)
                if statementNode < 0 || assignmentCount >= statementIndices.Length {
                    return -1
                }
                nodeCursor = cursorResult.Values[0]
                childCursor = cursorResult.Values[1]
                statementIndices[assignmentCount] = statementNode
                assignmentCount = assignmentCount + 1
            }

            p = p + 1
        }
    }

    if nodeCursor >= body.NodeKinds.Length || childCursor + assignmentCount > body.ChildIndices.Length {
        return -1
    }
    root := nodeCursor
    body.NodeKinds[root] = 25
    body.ValueStarts[root] = -1
    body.ValueLengths[root] = 0
    body.ChildStart[root] = childCursor
    body.ChildCount[root] = assignmentCount
    body.SpanStarts[root] = tokens.Starts[bodyBrace]
    body.SpanLengths[root] = tokens.ValueLengths[bodyBrace]
    i := 0
    while i < assignmentCount {
        body.ChildIndices[childCursor + i] = statementIndices[i]
        i = i + 1
    }
    nodeCursor = nodeCursor + 1

    result.Values[0] = 0
    result.Values[1] = bodyBrace
    result.Values[2] = paramCount
    result.Values[3] = 0
    result.Values[4] = root
    result.Values[5] = nodeCursor
    return paramCount
}

func ParseColumnarConstructorBodyNodesCore(source: string, tokens: ColumnarConstructorTokenTable, bodyBrace: int, body: ColumnarConstructorBodyTable, result: ColumnarConstructorResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}

func ParseColumnarStructInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, structIndex: int, isReference: int, isRecord: int, outFieldNameTexts: string[], outFieldTypeTexts: string[], outFieldStaticFlags: int[], outFieldInitKinds: int[], outFieldInitTexts: string[], outMethodFuncIndices: int[], outMethodStaticFlags: int[], outCtorIndices: int[], outPropIndices: int[], outPropStaticFlags: int[], outTypeParamTexts: string[], outBaseNameTexts: string[], outStructNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarStructTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarStructScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarStructOutputTable(outFieldNameTexts, outFieldTypeTexts, outFieldStaticFlags, outFieldInitKinds, outFieldInitTexts, outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags, outTypeParamTexts, outBaseNameTexts, outStructNameTexts)
    result := new ColumnarStructResultTable(outResult)
    return ParseColumnarStructInfoCore(source, tokens, structIndex, isReference, isRecord, scratch, outputs, result)
}

func ParseColumnarStructInfoCore(source: string, tokens: ColumnarStructTokenTable, structIndex: int, isReference: int, _isRecord: int, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, result: ColumnarStructResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    decl := new StructDeclarationTable(scratch.FieldNameStarts, scratch.FieldNameLengths, scratch.FieldTypeStarts, scratch.FieldTypeLengths, outputs.FieldStaticFlags, outputs.FieldInitKinds, scratch.FieldInitStarts, scratch.FieldInitLengths, outputs.MethodFuncIndices, outputs.MethodStaticFlags, outputs.MethodStaticFlags, outputs.CtorIndices, outputs.PropIndices, outputs.PropStaticFlags, scratch.TypeParamStarts, scratch.TypeParamLengths, scratch.BaseNameStarts, scratch.BaseNameLengths)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    fieldCount := ParseStructDeclarationCore(source, declarationTokens, tokens.Count, structIndex, decl, declarationResult)
    methodCount := result.Values[2]
    propCount := result.Values[4]
    typeParamCount := result.Values[7]
    baseNameCount := result.Values[8]
    ctorCount := result.Values[3]
    if fieldCount < 0 || outputs.StructNameTexts.Length < 1 || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || fieldCount > outputs.FieldInitTexts.Length || typeParamCount > outputs.TypeParamTexts.Length || baseNameCount > outputs.BaseNameTexts.Length {
        return -1
    }
    if ColumnarStructTypeParameterNamesDistinct(source, scratch, typeParamCount) == 0 {
        return -1
    }
    if ColumnarStructFieldNamesDistinct(source, scratch, fieldCount) == 0 {
        return -1
    }
    if ColumnarStructBaseNamesDistinct(source, scratch, baseNameCount) == 0 {
        return -1
    }
    if ColumnarStructMethodMemberNamesSupported(source, tokens, scratch, outputs, fieldCount, methodCount) == 0 {
        return -1
    }
    if ColumnarStructPropertyMemberNamesDistinct(source, tokens, scratch, outputs, fieldCount, methodCount, propCount) == 0 {
        return -1
    }

    if isReference == 0 {
        instanceFieldCount := 0
        fieldSlot := 0
        while fieldSlot < fieldCount {
            if !ColumnarStructFieldFlagIsStatic(outputs.FieldStaticFlags[fieldSlot]) {
                instanceFieldCount = instanceFieldCount + 1
            }

            fieldSlot = fieldSlot + 1
        }

        if instanceFieldCount == 0 {
            return -1
        }
    }

    if typeParamCount > 0 && baseNameCount > 0 {
        return -1
    }

    i := 0
    if typeParamCount > 0 {
        while i < fieldCount {
            if ColumnarStructFieldFlagIsStatic(outputs.FieldStaticFlags[i]) {
                return -1
            }

            if ColumnarStructNameMatchesTypeParam(source, scratch, typeParamCount, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i]) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < methodCount {
            if ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i]) {
                return -1
            }

            methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[i])
            if methodName == "" {
                return -1
            }

            if ColumnarStructNameMatchesTypeParamText(source, scratch, typeParamCount, methodName) {
                return -1
            }

            i = i + 1
        }

        i = 0
        while i < propCount {
            if outputs.PropStaticFlags[i] == 1 {
                return -1
            }

            propNameIndex := outputs.PropIndices[i]
            if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
                return -1
            }

            if ColumnarStructNameMatchesTypeParam(source, scratch, typeParamCount, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex]) {
                return -1
            }

            i = i + 1
        }
    }

    methodUnsupported := ColumnarStructMethodUnsupportedStatus(source, tokens, outputs, methodCount)
    if methodUnsupported != 0 {
        return -1
    }
    ctorUnsupported := ColumnarStructConstructorUnsupportedStatus(source, tokens, outputs, ctorCount, isReference)
    if ctorUnsupported != 0 {
        return -1
    }

    structName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, structIndex, result.Values[0], result.Values[1])
    if structName == "" {
        return -1
    }
    outputs.StructNameTexts[0] = structName

    i = 0
    while i < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if typeParamName == "" {
            return -1
        }

        outputs.TypeParamTexts[i] = typeParamName
        i = i + 1
    }

    i = 0
    while i < baseNameCount {
        baseName := ParserDeclarationCanonicalTypeText(source, scratch.BaseNameStarts[i], scratch.BaseNameLengths[i])
        if baseName == "" {
            return -1
        }

        outputs.BaseNameTexts[i] = baseName
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        text := ParserDeclarationCanonicalTypeText(source, scratch.FieldTypeStarts[i], scratch.FieldTypeLengths[i])
        if text.Length == 0 {
            return -1
        }

        outputs.FieldNameTexts[i] = fieldName
        outputs.FieldTypeTexts[i] = text
        if outputs.FieldInitKinds[i] >= 0 {
            initText := source.Substring(scratch.FieldInitStarts[i], scratch.FieldInitLengths[i])
            if initText.Length == 0 {
                return -1
            }

            outputs.FieldInitTexts[i] = initText
        }

        i = i + 1
    }

    return fieldCount
}

func ColumnarStructFieldFlagIsStatic(flags: int): bool {
    return flags == 1 || flags == 3
}

func ColumnarStructMethodUnsupportedStatus(source: string, tokens: ColumnarStructTokenTable, outputs: ColumnarStructOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(new string[](1), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap), new int[](cap), new string[](cap), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarFunctionBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    locals := new ColumnarFunctionLocalTable(new int[](cap), new int[](cap))
    result := new ColumnarFunctionResultTable(new int[](9))
    methodParamCounts := new int[](methodCount + 1)
    methodParamStarts := new int[](methodCount + 1)
    methodNameTexts := new string[](methodCount + 1)
    methodParamTypeTexts := new string[](cap)
    nextMethodParamType := 0

    for i := 0; i < methodCount; i++ {
        result.Values[8] = 0
        nativeImportMethod := ColumnarStructMethodFlagIsNativeImport(outputs.MethodStaticFlags[i])
        paramCount := 0
        if nativeImportMethod {
            if !ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i]) {
                return -1
            }
            paramCount = ParseColumnarFunctionSignatureOnlyInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], signatureOutputs, result)
        } else {
            paramCount = ParseColumnarFunctionInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], 0, signatureOutputs, body, locals, result)
        }
        if paramCount < 0 {
            return -1
        }

        methodName := signatureOutputs.FunctionNameTexts[0]
        if methodName == "" {
            return -1
        }

        if nextMethodParamType + paramCount > methodParamTypeTexts.Length {
            return -1
        }

        methodParamCounts[i] = paramCount
        if ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[i]) {
            j := 0
            while j < i {
                if ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[j]) && methodParamCounts[j] == paramCount {
                    if methodName == methodNameTexts[j] {
                        sameSignature := true
                        paramSlot := 0
                        while paramSlot < paramCount {
                            if signatureOutputs.ParamTypeTexts[paramSlot] != methodParamTypeTexts[methodParamStarts[j] + paramSlot] {
                                sameSignature = false
                            }

                            paramSlot = paramSlot + 1
                        }

                        if sameSignature {
                            return 1
                        }
                    }
                }

                j = j + 1
            }
        } else {
            j := 0
            while j < i {
                if !ColumnarStructMethodFlagIsStatic(outputs.MethodStaticFlags[j]) && methodParamCounts[j] == paramCount {
                    if methodName == methodNameTexts[j] {
                        sameSignature := true
                        paramSlot := 0
                        while paramSlot < paramCount {
                            if signatureOutputs.ParamTypeTexts[paramSlot] != methodParamTypeTexts[methodParamStarts[j] + paramSlot] {
                                sameSignature = false
                            }

                            paramSlot = paramSlot + 1
                        }

                        if sameSignature {
                            return 1
                        }
                    }
                }

                j = j + 1
            }
        }
        methodNameTexts[i] = methodName
        methodParamStarts[i] = nextMethodParamType
        paramSlot := 0
        while paramSlot < paramCount {
            if signatureOutputs.ParamTypeTexts[paramSlot] == "" {
                return -1
            }

            methodParamTypeTexts[nextMethodParamType + paramSlot] = signatureOutputs.ParamTypeTexts[paramSlot]
            paramSlot = paramSlot + 1
        }
        nextMethodParamType = nextMethodParamType + paramCount
        if result.Values[2] > 0 {
            return 1
        }
        if !nativeImportMethod && result.Values[8] > 0 {
            return 1
        }
    }

    return 0
}

func ColumnarStructConstructorUnsupportedStatus(source: string, tokens: ColumnarStructTokenTable, outputs: ColumnarStructOutputTable, ctorCount: int, isReference: int): int {
    constructorTokens := new ColumnarConstructorTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := (tokens.Count + 1) * 4
    signatureOutputs := new ColumnarConstructorSignatureOutputTable(new string[](cap), new string[](cap), new int[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarConstructorBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    result := new ColumnarConstructorResultTable(new int[](6))
    localResults := new LocalFunctionResultTable(new int[](cap), new int[](cap))
    ctorParamCounts := new int[](ctorCount + 1)
    ctorParamStarts := new int[](ctorCount + 1)
    ctorParamTypeTexts := new string[](cap)
    nextCtorParamType := 0

    for i := 0; i < ctorCount; i++ {
        paramCount := ParseColumnarConstructorInfoCore(source, constructorTokens, outputs.CtorIndices[i], signatureOutputs, body, result)
        if paramCount < 0 {
            return -1
        }

        currentIsInitializerMethod := ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens, outputs.CtorIndices[i], paramCount)
        previousCtor := 0
        while previousCtor < i {
            previousIsInitializerMethod := ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens, outputs.CtorIndices[previousCtor], ctorParamCounts[previousCtor])
            if !currentIsInitializerMethod && !previousIsInitializerMethod && ctorParamCounts[previousCtor] == paramCount {
                sameSignature := true
                paramSlot := 0
                while paramSlot < paramCount {
                    if signatureOutputs.ParamTypeTexts[paramSlot] != ctorParamTypeTexts[ctorParamStarts[previousCtor] + paramSlot] {
                        sameSignature = false
                    }

                    paramSlot = paramSlot + 1
                }

                if sameSignature {
                    return 1
                }
            }

            previousCtor = previousCtor + 1
        }

        if nextCtorParamType + paramCount > ctorParamTypeTexts.Length {
            return -1
        }

        ctorParamCounts[i] = paramCount
        ctorParamStarts[i] = nextCtorParamType
        paramSlot := 0
        while paramSlot < paramCount {
            if signatureOutputs.ParamTypeTexts[paramSlot] == "" {
                return -1
            }

            ctorParamTypeTexts[nextCtorParamType + paramSlot] = signatureOutputs.ParamTypeTexts[paramSlot]
            paramSlot = paramSlot + 1
        }
        nextCtorParamType = nextCtorParamType + paramCount

        if isReference == 0 {
            if result.Values[0] != 0 || paramCount == 0 {
                return 1
            }
        }

        localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
        localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
        localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, result.Values[4], localResults)
        if localFunctionCount < 0 {
            return -1
        }
        if localFunctionCount > 0 {
            return 1
        }
    }

    return 0
}

func ColumnarStructCtorIndexIsZeroParamSynthesizedInitializer(tokens: ColumnarStructTokenTable, ctorIndex: int, paramCount: int): bool {
    if paramCount != 0 || ctorIndex < 0 || ctorIndex >= tokens.Count {
        return false
    }
    return tokens.Kinds[ctorIndex] == 8 || tokens.Kinds[ctorIndex] == 13
}

func ColumnarStructNameMatchesTypeParam(source: string, scratch: ColumnarStructScratchTable, typeParamCount: int, nameStart: int, nameLength: int): bool {
    i := 0
    while i < typeParamCount {
        if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], nameStart, nameLength) {
            return true
        }

        i = i + 1
    }

    return false
}

func ColumnarStructNameMatchesTypeParamText(source: string, scratch: ColumnarStructScratchTable, typeParamCount: int, nameText: string): bool {
    if nameText == "" {
        return false
    }

    i := 0
    while i < typeParamCount {
        typeParamName := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if typeParamName == nameText {
            return true
        }

        i = i + 1
    }

    return false
}

func ColumnarStructFieldNamesDistinct(source: string, scratch: ColumnarStructScratchTable, fieldCount: int): int {
    if fieldCount < 0 {
        return 0
    }

    i := 0
    while i < fieldCount {
        if scratch.FieldNameStarts[i] < 0 || scratch.FieldNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < fieldCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i], scratch.FieldNameStarts[j], scratch.FieldNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructBaseNamesDistinct(source: string, scratch: ColumnarStructScratchTable, baseNameCount: int): int {
    if baseNameCount < 0 {
        return 0
    }

    i := 0
    while i < baseNameCount {
        if scratch.BaseNameStarts[i] < 0 || scratch.BaseNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < baseNameCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.BaseNameStarts[i], scratch.BaseNameLengths[i], scratch.BaseNameStarts[j], scratch.BaseNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructOperatorMemberName(kind: int): string {
    if kind == 44 {
        return "operator true"
    }
    if kind == 45 {
        return "operator false"
    }
    if kind == 88 {
        return "operator +"
    }
    if kind == 89 {
        return "operator -"
    }
    if kind == 90 {
        return "operator *"
    }
    if kind == 91 {
        return "operator /"
    }
    if kind == 92 {
        return "operator %"
    }
    if kind == 98 {
        return "operator =="
    }
    if kind == 99 {
        return "operator !="
    }
    if kind == 100 {
        return "operator <"
    }
    if kind == 101 {
        return "operator <="
    }
    if kind == 102 {
        return "operator >"
    }
    if kind == 103 {
        return "operator >="
    }
    if kind == 106 {
        return "operator !"
    }
    if kind == 107 {
        return "operator &"
    }
    if kind == 108 {
        return "operator |"
    }
    if kind == 109 {
        return "operator ^"
    }
    if kind == 110 {
        return "operator ~"
    }
    if kind == 111 {
        return "operator <<"
    }
    if kind == 112 {
        return "operator >>"
    }
    if kind == 113 {
        return "operator ++"
    }
    if kind == 114 {
        return "operator --"
    }
    return ""
}

func ColumnarStructMethodMemberNameText(source: string, tokens: ColumnarStructTokenTable, funcIndex: int): string {
    if funcIndex >= 0 && funcIndex < tokens.Count {
        if tokens.Kinds[funcIndex] == 85 {
            return "op_Implicit"
        }
        if tokens.Kinds[funcIndex] == 86 {
            return "op_Explicit"
        }
    }

    methodNameIndex := funcIndex + 1
    if methodNameIndex < 0 || methodNameIndex >= tokens.Count {
        return ""
    }

    if tokens.Kinds[methodNameIndex] == 0 {
        return ParserDeclarationSpanText(source, tokens.Starts[methodNameIndex], tokens.ValueLengths[methodNameIndex])
    }

    if tokens.Kinds[methodNameIndex] == 75 {
        symbolIndex := methodNameIndex + 1
        if symbolIndex < 0 || symbolIndex >= tokens.Count {
            return ""
        }
        return ColumnarStructOperatorMemberName(tokens.Kinds[symbolIndex])
    }

    return ""
}

func ColumnarStructMethodFlagIsStatic(flags: int): bool {
    return (flags & 16) != 0
}

func ColumnarStructMethodMemberNamesSupported(source: string, tokens: ColumnarStructTokenTable, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, fieldCount: int, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[i])
        if methodName == "" {
            return 0
        }

        f := 0
        while f < fieldCount {
            if scratch.FieldNameStarts[f] < 0 || scratch.FieldNameLengths[f] <= 0 {
                return 0
            }

            fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[f], scratch.FieldNameLengths[f])
            if methodName == fieldName {
                return 0
            }

            f = f + 1
        }

        j := i + 1
        while j < methodCount {
            otherMethodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[j])
            if otherMethodName == "" {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructPropertyMemberNamesDistinct(source: string, tokens: ColumnarStructTokenTable, scratch: ColumnarStructScratchTable, outputs: ColumnarStructOutputTable, fieldCount: int, methodCount: int, propCount: int): int {
    if propCount < 0 {
        return 0
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    propertyResult := new ParserDeclarationResultTable(new int[](6))

    i := 0
    while i < propCount {
        if outputs.PropStaticFlags[i] != 0 && outputs.PropStaticFlags[i] != 1 {
            return 0
        }

        propNameIndex := outputs.PropIndices[i]
        if propNameIndex < 0 || propNameIndex >= tokens.Count || tokens.Kinds[propNameIndex] != 0 {
            return 0
        }

        propName := ParserDeclarationSpanText(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex])
        if propName == "" {
            return 0
        }

        accessorKind := ParsePropertyAccessorInfoCore(source, declarationTokens, tokens.Count, propNameIndex, propertyResult)
        if accessorKind < 0 || accessorKind > 1 {
            return 0
        }

        getAccessorName := "get_" + propName
        setAccessorName := "set_" + propName

        f := 0
        while f < fieldCount {
            if scratch.FieldNameStarts[f] < 0 || scratch.FieldNameLengths[f] <= 0 {
                return 0
            }

            if ParserDeclarationSourceSpansEqual(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex], scratch.FieldNameStarts[f], scratch.FieldNameLengths[f]) {
                return 0
            }

            f = f + 1
        }

        m := 0
        while m < methodCount {
            methodName := ColumnarStructMethodMemberNameText(source, tokens, outputs.MethodFuncIndices[m])
            if methodName == "" {
                return 0
            }

            if methodName == propName {
                return 0
            }

            if methodName == getAccessorName || (accessorKind == 1 && methodName == setAccessorName) {
                return 0
            }

            m = m + 1
        }

        j := i + 1
        while j < propCount {
            if outputs.PropStaticFlags[j] != 0 && outputs.PropStaticFlags[j] != 1 {
                return 0
            }

            otherPropNameIndex := outputs.PropIndices[j]
            if otherPropNameIndex < 0 || otherPropNameIndex >= tokens.Count || tokens.Kinds[otherPropNameIndex] != 0 {
                return 0
            }

            if ParserDeclarationSourceSpansEqual(source, tokens.Starts[propNameIndex], tokens.ValueLengths[propNameIndex], tokens.Starts[otherPropNameIndex], tokens.ValueLengths[otherPropNameIndex]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarStructTypeParameterNamesDistinct(source: string, scratch: ColumnarStructScratchTable, typeParamCount: int): int {
    if typeParamCount < 0 {
        return 0
    }

    i := 0
    while i < typeParamCount {
        if scratch.TypeParamStarts[i] < 0 || scratch.TypeParamLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < typeParamCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], scratch.TypeParamStarts[j], scratch.TypeParamLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ParseColumnarUnionInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, unionIndex: int, outCaseNameTexts: string[], outCaseFieldCounts: int[], outFieldNameTexts: string[], outFieldTypeTexts: string[], outTypeParamTexts: string[], outUnionNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarUnionTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarUnionScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarUnionTextOutputTable(outCaseNameTexts, outCaseFieldCounts, outFieldNameTexts, outFieldTypeTexts, outTypeParamTexts, outUnionNameTexts)
    result := new ColumnarUnionResultTable(outResult)
    return ParseColumnarUnionInfoCore(source, tokens, unionIndex, scratch, outputs, result)
}

func ParseColumnarUnionInfoCore(source: string, tokens: ColumnarUnionTokenTable, unionIndex: int, scratch: ColumnarUnionScratchTable, outputs: ColumnarUnionTextOutputTable, result: ColumnarUnionResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    decl := new UnionDeclarationTable(scratch.CaseNameStarts, scratch.CaseNameLengths, outputs.CaseFieldCounts, scratch.FieldNameStarts, scratch.FieldNameLengths, scratch.FieldTypeStarts, scratch.FieldTypeLengths, scratch.TypeParamStarts, scratch.TypeParamLengths)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    caseCount := ParseUnionDeclarationCore(declarationTokens, tokens.Count, unionIndex, decl, declarationResult)
    if caseCount < 0 {
        return -1
    }

    typeParamCount := result.Values[2]
    fieldCount := 0
    i := 0
    while i < caseCount {
        fieldCount = fieldCount + outputs.CaseFieldCounts[i]
        i = i + 1
    }

    if outputs.UnionNameTexts.Length < 1 || caseCount > outputs.CaseNameTexts.Length || fieldCount > outputs.FieldNameTexts.Length || fieldCount > outputs.FieldTypeTexts.Length || typeParamCount > outputs.TypeParamTexts.Length {
        return -1
    }
    if ColumnarUnionTypeParameterNamesDistinct(source, scratch, typeParamCount) == 0 {
        return -1
    }
    if ColumnarUnionCaseNamesDistinct(source, scratch, caseCount) == 0 {
        return -1
    }
    if ColumnarUnionCaseFieldNamesDistinct(source, scratch, outputs, caseCount) == 0 {
        return -1
    }

    unionName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, unionIndex, result.Values[0], result.Values[1])
    if unionName == "" {
        return -1
    }
    outputs.UnionNameTexts[0] = unionName

    i = 0
    while i < typeParamCount {
        text := ParserDeclarationSpanText(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i])
        if text == "" {
            return -1
        }

        outputs.TypeParamTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < caseCount {
        text := ParserDeclarationSpanText(source, scratch.CaseNameStarts[i], scratch.CaseNameLengths[i])
        if text == "" {
            return -1
        }

        outputs.CaseNameTexts[i] = text
        i = i + 1
    }

    i = 0
    while i < fieldCount {
        fieldName := ParserDeclarationSpanText(source, scratch.FieldNameStarts[i], scratch.FieldNameLengths[i])
        if fieldName == "" {
            return -1
        }

        fieldType := ParserDeclarationCanonicalTypeText(source, scratch.FieldTypeStarts[i], scratch.FieldTypeLengths[i])
        if fieldType == "" {
            return -1
        }

        outputs.FieldNameTexts[i] = fieldName
        outputs.FieldTypeTexts[i] = fieldType
        i = i + 1
    }

    return caseCount
}

func ColumnarUnionCaseNamesDistinct(source: string, scratch: ColumnarUnionScratchTable, caseCount: int): int {
    if caseCount < 0 {
        return 0
    }

    i := 0
    while i < caseCount {
        if scratch.CaseNameStarts[i] < 0 || scratch.CaseNameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < caseCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.CaseNameStarts[i], scratch.CaseNameLengths[i], scratch.CaseNameStarts[j], scratch.CaseNameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarUnionCaseFieldNamesDistinct(source: string, scratch: ColumnarUnionScratchTable, outputs: ColumnarUnionTextOutputTable, caseCount: int): int {
    if caseCount < 0 {
        return 0
    }

    fieldOffset := 0
    c := 0
    while c < caseCount {
        caseFieldCount := outputs.CaseFieldCounts[c]
        if caseFieldCount < 0 {
            return 0
        }

        i := 0
        while i < caseFieldCount {
            leftIndex := fieldOffset + i
            if leftIndex < 0 || leftIndex >= scratch.FieldNameStarts.Length || scratch.FieldNameStarts[leftIndex] < 0 || scratch.FieldNameLengths[leftIndex] <= 0 {
                return 0
            }

            j := i + 1
            while j < caseFieldCount {
                rightIndex := fieldOffset + j
                if rightIndex < 0 || rightIndex >= scratch.FieldNameStarts.Length {
                    return 0
                }

                if ParserDeclarationSourceSpansEqual(source, scratch.FieldNameStarts[leftIndex], scratch.FieldNameLengths[leftIndex], scratch.FieldNameStarts[rightIndex], scratch.FieldNameLengths[rightIndex]) {
                    return 0
                }

                j = j + 1
            }

            i = i + 1
        }

        fieldOffset = fieldOffset + caseFieldCount
        c = c + 1
    }

    return 1
}

func ColumnarUnionIsValueStructEmittable(caseFieldCounts: int[], caseCount: int, typeParamCount: int): int {
    if typeParamCount != 0 {
        return 0
    }

    if caseCount < 1 || caseCount > 16 {
        return 0
    }

    if caseCount > caseFieldCounts.Length {
        return 0
    }

    i := 0
    while i < caseCount {
        if caseFieldCounts[i] != 0 {
            return 0
        }

        i = i + 1
    }

    return 1
}

func ColumnarUnionTypeParameterNamesDistinct(source: string, scratch: ColumnarUnionScratchTable, typeParamCount: int): int {
    if typeParamCount < 0 {
        return 0
    }

    i := 0
    while i < typeParamCount {
        if scratch.TypeParamStarts[i] < 0 || scratch.TypeParamLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < typeParamCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.TypeParamStarts[i], scratch.TypeParamLengths[i], scratch.TypeParamStarts[j], scratch.TypeParamLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ParseColumnarEnumInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, enumIndex: int, outNameTexts: string[], outMemberValues: int[], outMemberStringValues: string[], outEnumNameTexts: string[], outResult: int[]): int {
    tokens := new ColumnarEnumTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarEnumMemberScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarEnumTextOutputTable(outNameTexts, outMemberValues, outMemberStringValues, outEnumNameTexts)
    result := new ColumnarEnumResultTable(outResult)
    return ParseColumnarEnumInfoCore(source, tokens, enumIndex, scratch, outputs, result)
}

func ParseColumnarEnumInfoCore(source: string, tokens: ColumnarEnumTokenTable, enumIndex: int, scratch: ColumnarEnumMemberScratchTable, outputs: ColumnarEnumTextOutputTable, result: ColumnarEnumResultTable): int {
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    members := new EnumMemberTable(scratch.NameStarts, scratch.NameLengths, scratch.ValueStarts, scratch.ValueLengths, scratch.HasValue)
    declarationResult := new ParserDeclarationResultTable(result.Values)
    memberCount := ParseEnumDeclarationCore(declarationTokens, tokens.Count, enumIndex, members, declarationResult)
    if memberCount < 0 {
        return -1
    }

    if ColumnarEnumMemberNamesDistinct(source, scratch, memberCount) == 0 {
        return -1
    }

    backingKind := ColumnarEnumBackingKind(source, tokens, enumIndex, scratch, memberCount)
    if backingKind < 0 {
        return -1
    }

    if result.Values.Length > 2 {
        result.Values[2] = backingKind
    }

    if backingKind == 0 {
        memberValues := new EnumMemberValueTable(outputs.MemberValues)
        if !ParseEnumMemberValuesCore(source, members, memberCount, memberValues) {
            return -1
        }
    } else if !ColumnarEnumStringMemberValues(source, scratch, memberCount, outputs) {
        return -1
    }

    if outputs.EnumNameTexts.Length < 1 || memberCount > outputs.MemberNameTexts.Length {
        return -1
    }

    enumName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, enumIndex, result.Values[0], result.Values[1])
    if enumName == "" {
        return -1
    }
    outputs.EnumNameTexts[0] = enumName

    i := 0
    while i < memberCount {
        memberName := ParserDeclarationSpanText(source, scratch.NameStarts[i], scratch.NameLengths[i])
        if memberName == "" {
            return -1
        }

        outputs.MemberNameTexts[i] = memberName
        i = i + 1
    }

    return memberCount
}

func ColumnarEnumBackingKind(source: string, tokens: ColumnarEnumTokenTable, enumIndex: int, scratch: ColumnarEnumMemberScratchTable, memberCount: int): int {
    explicitKind := -1
    pos := enumIndex + 2
    if pos < tokens.Count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        if pos >= tokens.Count || tokens.Kinds[pos] != 0 {
            return -1
        }

        if ParserDeclarationTokenTextEquals(source, tokens.Starts[pos], tokens.ValueLengths[pos], "string") {
            explicitKind = 1
        } else if ParserDeclarationTokenTextEquals(source, tokens.Starts[pos], tokens.ValueLengths[pos], "int") {
            explicitKind = 0
        } else {
            return -1
        }
    }

    backingKind := 0
    if explicitKind == 1 {
        backingKind = 1
    }

    sawIntValue := 0
    i := 0
    while i < memberCount {
        if scratch.HasValue[i] != 0 {
            valueKind := ColumnarEnumValueTokenKind(tokens, scratch.ValueStarts[i])
            if valueKind == 4 {
                if explicitKind == 0 || sawIntValue != 0 {
                    return -1
                }
                backingKind = 1
            } else if valueKind == 1 {
                if explicitKind == 1 || backingKind == 1 {
                    return -1
                }
                sawIntValue = 1
            } else {
                return -1
            }
        }

        i = i + 1
    }

    return backingKind
}

func ColumnarEnumValueTokenKind(tokens: ColumnarEnumTokenTable, valueStart: int): int {
    i := 0
    while i < tokens.Count {
        if tokens.Starts[i] == valueStart {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ColumnarEnumStringMemberValues(source: string, scratch: ColumnarEnumMemberScratchTable, memberCount: int, outputs: ColumnarEnumTextOutputTable): bool {
    if memberCount < 0 || memberCount > outputs.MemberStringValues.Length {
        return false
    }

    i := 0
    while i < memberCount {
        valueText := ""
        if scratch.HasValue[i] != 0 {
            valueText = ParserDeclarationSpanText(source, scratch.ValueStarts[i], scratch.ValueLengths[i])
        } else {
            valueText = ParserDeclarationSpanText(source, scratch.NameStarts[i], scratch.NameLengths[i])
        }

        if valueText == "" {
            return false
        }

        outputs.MemberStringValues[i] = valueText
        i = i + 1
    }

    return true
}

func ColumnarEnumMemberNamesDistinct(source: string, scratch: ColumnarEnumMemberScratchTable, memberCount: int): int {
    if memberCount < 0 {
        return 0
    }

    i := 0
    while i < memberCount {
        if scratch.NameStarts[i] < 0 || scratch.NameLengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < memberCount {
            if ParserDeclarationSourceSpansEqual(source, scratch.NameStarts[i], scratch.NameLengths[i], scratch.NameStarts[j], scratch.NameLengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ParseColumnarInterfaceInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, interfaceIndex: int, outMethodFuncIndices: int[], outBaseNameTexts: string[], outInterfaceNameTexts: string[], outMethodNameTexts: string[], outMethodReturnTexts: string[], outMethodParamCounts: int[], outMethodBodyFlags: int[], outMethodParamNameTexts: string[], outMethodParamTypeTexts: string[], outTypeParamTexts: string[], outResult: int[]): int {
    tokens := new ColumnarInterfaceTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    scratch := new ColumnarInterfaceBaseScratchTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    outputs := new ColumnarInterfaceOutputTable(outMethodFuncIndices, outBaseNameTexts, outInterfaceNameTexts, outMethodNameTexts, outMethodReturnTexts, outMethodParamCounts, outMethodBodyFlags, outMethodParamNameTexts, outMethodParamTypeTexts, outTypeParamTexts)
    result := new ColumnarInterfaceResultTable(outResult)
    return ParseColumnarInterfaceInfoCore(source, tokens, interfaceIndex, scratch, outputs, result)
}

func ParseColumnarInterfaceInfoCore(source: string, tokens: ColumnarInterfaceTokenTable, interfaceIndex: int, scratch: ColumnarInterfaceBaseScratchTable, outputs: ColumnarInterfaceOutputTable, result: ColumnarInterfaceResultTable): int {
    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    baseOutputs := new InterfaceSignatureBaseOutputTable(scratch.BaseNameStarts, scratch.BaseNameLengths, outputs.BaseNameTexts, outputs.InterfaceNameTexts, outputs.TypeParamTexts)
    methodOutputs := new InterfaceSignatureMethodOutputTable(outputs.MethodFuncIndices, outputs.MethodNameTexts, outputs.MethodReturnTexts, outputs.MethodParamCounts, outputs.MethodBodyFlags, outputs.MethodParamNameTexts, outputs.MethodParamTypeTexts)
    typeStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserNodeTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    children := new ParserChildIndexTable(new int[](tokens.Count + 1))
    canonicalNodes := new TypeReferenceCanonicalTable(nodes.Kinds, nodes.ValueStarts, nodes.ValueLengths, nodes.ChildStart, nodes.ChildCount, children.Indices)
    tupleNodes := new InterfaceSignatureTupleNodeTable(nodes.Kinds, nodes.ChildStart, nodes.ChildCount, children.Indices)
    parameters := new ParserFunctionParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](tokens.Count + 1), new int[](tokens.Count + 1), new int[](tokens.Count + 1))
    signatureResult := new ParserResultTable(new int[](8))
    interfaceResult := new ParserResultTable(result.Values)
    methodCount := ParseInterfaceDeclarationSignatureInfoCore(source, signatureTokens, tokens.Count, interfaceIndex, baseOutputs, methodOutputs, typeStack, nodes, children, canonicalNodes, tupleNodes, parameters, typeParams, whereItems, signatureResult, interfaceResult)
    if methodCount < 0 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    interfaceName := ParserDeclarationQualifiedNameText(source, declarationTokens, tokens.Count, interfaceIndex, result.Values[0], result.Values[1])
    if interfaceName == "" {
        return -1
    }
    outputs.InterfaceNameTexts[0] = interfaceName

    if ColumnarInterfaceBaseNamesDistinct(outputs, result.Values[2]) == 0 {
        return -1
    }
    if ColumnarInterfaceMethodNamesDistinct(outputs, methodCount) == 0 {
        return -1
    }
    if ColumnarInterfaceMethodParamNamesDistinct(outputs, methodCount) == 0 {
        return -1
    }

    localStatus := InterfaceDefaultMethodLocalFunctionStatus(source, tokens, outputs, methodCount)
    if localStatus != 0 {
        return -1
    }

    return methodCount
}

func ColumnarInterfaceBaseNamesDistinct(outputs: ColumnarInterfaceOutputTable, baseCount: int): int {
    if baseCount < 0 {
        return 0
    }

    i := 0
    while i < baseCount {
        if outputs.BaseNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < baseCount {
            if outputs.BaseNameTexts[i] == outputs.BaseNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodNamesDistinct(outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    i := 0
    while i < methodCount {
        if outputs.MethodNameTexts[i] == "" {
            return 0
        }

        j := i + 1
        while j < methodCount {
            if outputs.MethodNameTexts[i] == outputs.MethodNameTexts[j] {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ColumnarInterfaceMethodParamNamesDistinct(outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    if methodCount < 0 {
        return 0
    }

    paramOffset := 0
    m := 0
    while m < methodCount {
        paramCount := outputs.MethodParamCounts[m]
        if paramCount < 0 {
            return 0
        }

        i := 0
        while i < paramCount {
            leftIndex := paramOffset + i
            if leftIndex < 0 || leftIndex >= outputs.MethodParamNameTexts.Length || outputs.MethodParamNameTexts[leftIndex] == "" {
                return 0
            }

            j := i + 1
            while j < paramCount {
                rightIndex := paramOffset + j
                if rightIndex < 0 || rightIndex >= outputs.MethodParamNameTexts.Length {
                    return 0
                }

                if outputs.MethodParamNameTexts[leftIndex] == outputs.MethodParamNameTexts[rightIndex] {
                    return 0
                }

                j = j + 1
            }

            i = i + 1
        }

        paramOffset = paramOffset + paramCount
        m = m + 1
    }

    return 1
}

func InterfaceDefaultMethodLocalFunctionStatus(source: string, tokens: ColumnarInterfaceTokenTable, outputs: ColumnarInterfaceOutputTable, methodCount: int): int {
    functionTokens := new ColumnarFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, tokens.Count)
    cap := tokens.Count + 1
    signatureOutputs := new ColumnarFunctionSignatureOutputTable(new string[](1), new string[](1), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap), new int[](cap), new string[](cap), new string[](cap), new string[](cap), new int[](cap), new int[](cap), new string[](cap))
    body := new ColumnarFunctionBodyTable(new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap), new int[](cap))
    locals := new ColumnarFunctionLocalTable(new int[](cap), new int[](cap))
    result := new ColumnarFunctionResultTable(new int[](9))

    for i := 0; i < methodCount; i++ {
        bodyFlag := outputs.MethodBodyFlags[i]
        if bodyFlag == 0 {
            continue
        }
        if bodyFlag != 1 {
            return -1
        }

        paramCount := ParseColumnarFunctionInfoCore(source, functionTokens, outputs.MethodFuncIndices[i], 0, signatureOutputs, body, locals, result)
        if paramCount < 0 {
            return -1
        }
        if result.Values[8] > 0 {
            return 1
        }
    }

    return 0
}

func ParseColumnarPropertyInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, propIndex: int, outNameTexts: string[], outTypeTexts: string[], outGetNodeKinds: int[], outGetValueStarts: int[], outGetValueLengths: int[], outGetChildStart: int[], outGetChildCount: int[], outGetChildIndices: int[], outGetSpanStarts: int[], outGetSpanLengths: int[], outSetNodeKinds: int[], outSetValueStarts: int[], outSetValueLengths: int[], outSetChildStart: int[], outSetChildCount: int[], outSetChildIndices: int[], outSetSpanStarts: int[], outSetSpanLengths: int[], outResult: int[]): int {
    tokens := new ColumnarPropertyTokenTable(tokenKinds, tokenStarts, tokenValueLengths, count)
    texts := new ColumnarPropertyTextTable(outNameTexts, outTypeTexts)
    getBody := new ColumnarPropertyBodyTable(outGetNodeKinds, outGetValueStarts, outGetValueLengths, outGetChildStart, outGetChildCount, outGetChildIndices, outGetSpanStarts, outGetSpanLengths)
    setBody := new ColumnarPropertyBodyTable(outSetNodeKinds, outSetValueStarts, outSetValueLengths, outSetChildStart, outSetChildCount, outSetChildIndices, outSetSpanStarts, outSetSpanLengths)
    result := new ColumnarPropertyResultTable(outResult)
    return ParseColumnarPropertyInfoCore(source, tokens, propIndex, texts, getBody, setBody, result)
}

func ParseColumnarPropertyInfoCore(source: string, tokens: ColumnarPropertyTokenTable, propIndex: int, texts: ColumnarPropertyTextTable, getBody: ColumnarPropertyBodyTable, setBody: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    if result.Values.Length < 10 {
        return -1
    }

    if texts.NameTexts.Length < 1 || texts.TypeTexts.Length < 1 {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    propertyResult := new ParserDeclarationResultTable(new int[](6))
    accessorKind := ParsePropertyAccessorInfoCore(source, declarationTokens, tokens.Count, propIndex, propertyResult)
    if accessorKind < 0 {
        return -1
    }

    nameText := ParserDeclarationSpanText(source, propertyResult.Values[0], propertyResult.Values[1])
    if nameText == "" {
        return -1
    }

    typeText := ParserDeclarationCanonicalTypeText(source, propertyResult.Values[2], propertyResult.Values[3])
    if typeText == "" {
        return -1
    }

    texts.NameTexts[0] = nameText
    texts.TypeTexts[0] = typeText

    getBodyBrace := propertyResult.Values[4]
    if getBodyBrace < 0 || getBodyBrace >= tokens.Count || (tokens.Kinds[getBodyBrace] != 129 && tokens.Kinds[getBodyBrace] != 120) {
        return -1
    }

    getBodyResult := new ColumnarPropertyResultTable(new int[](2))
    getBodyNodeCount := 0
    if tokens.Kinds[getBodyBrace] == 129 {
        getBodyNodeCount = ParseColumnarPropertyBodyNodesCore(source, tokens, getBodyBrace, getBody, getBodyResult)
    } else {
        getBodyNodeCount = ParseColumnarPropertyExpressionBodyNodesCore(tokens, getBodyBrace, getBody, getBodyResult)
    }
    if getBodyNodeCount <= 0 {
        return -1
    }

    getBodyRoot := getBodyResult.Values[0]
    if getBodyRoot < 0 || getBodyRoot >= getBodyNodeCount {
        return -1
    }
    getLocalFunctionStatus := ColumnarPropertyDirectLocalFunctionStatus(tokens, getBody, getBodyRoot)
    if getLocalFunctionStatus != 0 {
        return -1
    }

    setBodyRoot := -1
    setBodyNodeCount := 0
    if accessorKind == 1 {
        setBodyBrace := propertyResult.Values[5]
        if setBodyBrace < 0 || setBodyBrace >= tokens.Count || tokens.Kinds[setBodyBrace] != 129 {
            return -1
        }

        setBodyResult := new ColumnarPropertyResultTable(new int[](2))
        setBodyNodeCount = ParseColumnarPropertyBodyNodesCore(source, tokens, setBodyBrace, setBody, setBodyResult)
        if setBodyNodeCount <= 0 {
            return -1
        }

        setBodyRoot = setBodyResult.Values[0]
        if setBodyRoot < 0 || setBodyRoot >= setBodyNodeCount {
            return -1
        }
        setLocalFunctionStatus := ColumnarPropertyDirectLocalFunctionStatus(tokens, setBody, setBodyRoot)
        if setLocalFunctionStatus != 0 {
            return -1
        }
    } else if accessorKind != 0 {
        return -1
    }

    result.Values[0] = propertyResult.Values[0]
    result.Values[1] = propertyResult.Values[1]
    result.Values[2] = propertyResult.Values[2]
    result.Values[3] = propertyResult.Values[3]
    result.Values[4] = getBodyBrace
    result.Values[5] = propertyResult.Values[5]
    result.Values[6] = getBodyRoot
    result.Values[7] = getBodyNodeCount
    result.Values[8] = setBodyRoot
    result.Values[9] = setBodyNodeCount
    return accessorKind
}

func ColumnarPropertyDirectLocalFunctionStatus(tokens: ColumnarPropertyTokenTable, body: ColumnarPropertyBodyTable, rootBlock: int): int {
    localTokens := new LocalFunctionTokenTable(tokens.Kinds, tokens.Starts, tokens.Count)
    localNodes := new LocalFunctionNodeTable(body.NodeKinds, body.ValueStarts, body.ChildStart, body.ChildCount, body.ChildIndices)
    cap := tokens.Count + 1
    localResults := new LocalFunctionResultTable(new int[](cap), new int[](cap))
    localFunctionCount := DirectLocalFunctionTokenIndicesCore(localTokens, localNodes, rootBlock, localResults)
    if localFunctionCount < 0 {
        return -1
    }
    if localFunctionCount > 0 {
        return 1
    }

    return 0
}

func ParseColumnarPropertyBodyNodesCore(source: string, tokens: ColumnarPropertyTokenTable, bodyBrace: int, body: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    statementTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    statementResult := new ParserResultTable(result.Values)
    return ParseStatementNodesCore(source, statementTokens, tokens.Count, bodyBrace, argStack, nodes, children, statementResult)
}

func ParseColumnarPropertyExpressionBodyNodesCore(tokens: ColumnarPropertyTokenTable, arrowIndex: int, body: ColumnarPropertyBodyTable, result: ColumnarPropertyResultTable): int {
    if arrowIndex < 0 || arrowIndex >= tokens.Count || tokens.Kinds[arrowIndex] != 120 || result.Values.Length < 2 {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    argStack := new ParserArgumentStack(new int[](tokens.Count + 1))
    nodes := new ParserExpressionNodeTable(body.NodeKinds, body.ValueStarts, body.ValueLengths, body.ChildStart, body.ChildCount, body.SpanStarts, body.SpanLengths)
    children := new ParserChildIndexTable(body.ChildIndices)
    st := new ParserState(arrowIndex + 1, 0, 0, 0, 0, 0)
    valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, tokens.Count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= arrowIndex + 1 {
        return -1
    }

    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, valueRoot)
    valueEnd := nodes.SpanStarts[valueRoot] + nodes.SpanLengths[valueRoot]
    returnNode := EmitExpressionNode(st, nodes, 20, -1, 0, childRunStart, 1, tokens.Starts[arrowIndex], valueEnd - tokens.Starts[arrowIndex])
    result.Values[0] = returnNode
    result.Values[1] = st.Pos
    return st.NodeCursor
}
