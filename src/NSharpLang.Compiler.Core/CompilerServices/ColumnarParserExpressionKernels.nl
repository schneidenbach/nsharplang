import System.Collections.Generic
import NSharpLang.Compiler.Columnar


// EXPRESSIONS AND PATTERNS: the precedence chain from primary to assignment, the pattern grammar,
// and the lambda and event-subscription forms beside them.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.

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
//                                         span, children = [the CALLEE EXPRESSION (kind 6 or kind 8), then the
//                                         TYPE-kernel type-argument roots]. Child 0 is what every consumer reads
//                                         the receiver from, through ColumnarGenericCalleeFacts; the type-argument
//                                         ordinal is therefore child 1 + n and the type-argument COUNT is
//                                         ChildCount - 1. Only ever appears
//                                         as child[0] of a CallExpression; committed via the IsGenericCallTypeArgs
//                                         lookahead, the Parser.cs IsGenericMethodCall mirror. Kind 37 is
//                                         UnionCasePattern in ParserStatements. )
//   GenericTypeReceiver     -> kind 70  ( Name<T1, T2> before a `.` -- a CONSTRUCTED GENERIC TYPE in receiver
//                                         position (`Vector<int>.Count`). The kind-38 shape MINUS the callee
//                                         child -- the
//                                         full dotted head name in the value span, children = the TYPE-kernel
//                                         type-argument roots alone -- and committed via the IsGenericTypeReceiverArgs
//                                         lookahead, which differs from kind 38's only in requiring a `.` close
//                                         instead of a `(`. It names a TYPE, so there is no receiver expression to
//                                         carry. Only ever appears as child[0] of a MemberAccess;
//                                         the planners resolve it as a TYPE, never as a value. )
//   AsyncLambda             -> kind 78  ( `async x => …` / `async () => …` / `async (x, y) => …` --
//                                         the kind-39 shape with the `async` keyword in front. The
//                                         distinct kind marks the body as one whose value the target
//                                         delegate's task-like return WRAPS, exactly as an `async
//                                         func`'s declared return is wrapped. )
//   Lambda                  -> kind 39  ( `x => expr` / `() => expr` / `(x, y) => expr` /
//                                         `(x: T) => expr` -- the level ABOVE
//                                         assignment (ParseLambdaOrAssignmentExpression, Parser.cs:3660). The
//                                         `=>` token in the value span; children = [param Identifiers (kind 6,
//                                         zero or more), body expression root] -- paramCount = childCount - 1.
//                                         A typed parameter's annotation is validated by the semantic AST parser;
//                                         its parameter node's FULL span preserves the annotation while its value span
//                                         remains the name. The body is an EXPRESSION at this level or a statement
//                                         BLOCK (kind 25, parsed by the statement kernel -- mutual recursion in
//                                         the other direction from statements-call-expressions). Parsed at the
//                                         full-expression entry and in EVERY ARGUMENT POSITION: a call argument,
//                                         a CONSTRUCTOR argument (`new Lazy<int>(() => 1)`), an indexer
//                                         argument, an object-, anonymous-object- or `with`-initializer value,
//                                         an array or tuple literal element, and an ASSIGNMENT's right-hand
//                                         side (`map[k] = v => ...`, `this.handler = v => ...`). Kind 40 is
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
//   IsExpression            -> kind 46  ( `value is Type [name]` (Is 47) -- children [value, typeRoot]; the
//                                         typeRoot is a TYPE subtree (scans walk child 0 only). The optional
//                                         PATTERN VARIABLE is the value span: present = the declared name,
//                                         absent = (-1, 0). `as` (kind 47) never carries one. )
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
//   NamedArgumentExpression -> kind 60 (`name: value` in ANY argument list -- a call, a `new <type>(...)`,
//                                         a `base(...)`/`this(...)` chain; the PARAMETER name in the value
//                                         span, ONE child [argument]. The child is a whole argument, so a
//                                         named `out`/`ref` argument keeps its kind-54 wrapper underneath
//                                         the name. Lowering binds the name to a parameter position.)
//   TypeBindingPattern     -> kind 61  ( `Type name` inside a match arm; children [typeRoot, binding].)
//   NameOfExpression       -> kind 62  ( `nameof(expr)` (Nameof 50) -- ONE child [expr]. The emitter accepts
//                                         the analyzer-validated identifier/member-access target subset.)
//   TargetTypedNewExpression -> kind 63 (`new(args...)` with no explicit type; children [arg0, ...].
//                                         Lowering only accepts contexts that provide an expected type.)
//   SpreadArgumentExpression -> kind 64 (`...expr` (DotDotDot 126) inside a call argument list; keyword token
//                                         in the value span, ONE child [expr].)
//   ListPattern             -> kind 65  (`[pat0, .. rest, patN]` inside a match arm; children are element
//                                         patterns and at most one kind-66 slice pattern.)
//   SlicePattern            -> kind 66  (`..` / `.. name` inside a ListPattern; optional binding name in the
//                                         value span, no children.)
//   ObjectPattern           -> kind 67  (`{ Prop, Prop: pat }` inside a match arm; children are kind-68
//                                         property pattern entries.)
//   PropertyPattern         -> kind 68  (`Prop` / `Prop: pat` inside object or union-case property patterns;
//                                         property name in the value span, optional ONE child [pat].)
//   BaseMemberExpression    -> kind 71  ( `base.Member` -- the member NAME in the value span, NO children,
//                                         the span running from `base` through the name. The shape of the
//                                         `this.Member` arm above it, with its own kind because the two
//                                         dispatch differently: a member reached through `base` is bound
//                                         NON-VIRTUALLY to the base's declaration, so it must never be
//                                         mistaken for the `this` form. `base.M(args)` is a CallExpression
//                                         over one of these; `base.P` on its own is the node itself. )
//   NullGuardExpression     -> kind 75  ( the receiver of a `?.` access (QuestionDot 118) -- ONE child
//                                         [receiver], no value span, the receiver's own span. The access
//                                         itself stays a kind-8 MemberAccess over it (and a kind-9 Call over
//                                         that for `a?.M(x)`), so only the SHORT CIRCUIT is new. )
//   ThisExpression          -> kind 82  ( a bare `this` (This 42) -- the CURRENT INSTANCE as a value. NO
//                                         children and NO value span; the enclosing declaration supplies the
//                                         type. `this.Member` is collapsed to a bare identifier before this
//                                         kind is reached, so only a `this` that stands alone is one. )
//   DefaultExpression       -> kind 74  ( `default` (Default 34) -- the target-typed zero value; NO children
//                                         and NO value span, exactly like the null literal (kind 5). The
//                                         written-type form is spelled as an annotation in N# (`x: T = default`),
//                                         so the keyword never carries a type child. )
//   ThrowExpression         -> kind 83  ( `throw <exception>` in VALUE position -- ONE child (the
//                                         exception expression), no value span, the span running from
//                                         the `throw` keyword through the operand. The grammar admits
//                                         it in exactly three places: the right operand of `??`, either
//                                         arm of a conditional, and an expression body (an arrow-bodied
//                                         `func`/property, or a lambda's). It is worth NOTHING -- the
//                                         position it sits in supplies the type. Statement-position
//                                         `throw` stays kind 48. )
//   RangeExpression         -> kind 69  (`start..end`, `start..`, `..end`, `..`; DotDot token in the
//                                         value span. Children are the present endpoint expressions; with
//                                         one child, compare its span start to the DotDot span to classify
//                                         start-only vs end-only.)
// `alloc <expr>` is parsed transparently: systems analysis owns allocation-policy enforcement before this
// product handoff, and the emitter only needs the concrete expression shape.
// Deferred (refused with -1, or the chain simply STOPS at them): `?[` null-conditional INDEXING, generic
//   method calls (callee<T>(...)),
//   `is`/`as` type tests; every other unlisted primary (`base.Member` is kind 71, `default` is kind 74
//   and a bare `this` is kind 82).
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

// The expression- and statement-node-kind ledgers moved to `ColumnarNodeKinds.nl`, where the
// statement half finally has a name too.
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

// ParseRangeExpression (Parser.cs:3934): a unary expression optionally followed by DotDot and an optional
// end unary expression, or an open-start range beginning with DotDot. Range endpoints stop at expression
// separators (`)`, `]`, `}`, `:`, `,`, `;`, EOF/newline) so `xs[..]`, `xs[5..]`, and ternaries inside
// indexers retain their enclosing punctuation.

// Precedence level (higher binds tighter) for a left-associative binary operator token, or 0 if the token
// is not a binary operator. Precedence chain, low->high:
// ?? (NullCoalesce) < || < && < | < ^ < & < ==,!= < <,<=,>,>= < <<,>> < +,- < *,/,%.
// `is`/`as` (type tests), range `..`, and assignment are intentionally NOT binary operators here.

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
//   `(x, y) => expr` / `(x: T) => expr` -- a parenthesized identifier list, optionally carrying an
//                      explicit type after `:`, committed via a pure speculative scan. Defaults and
//                      non-identifiers still fall through to the assignment level.
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
//   TypedForeachStatement        -> kind 76  ( `for <var>: <Type> in <coll>` / `foreach <var>: <Type> in <coll>` — the
//                                             ANNOTATED loop variable. Type trees cannot share this table (kind spaces
//                                             collide), so the TYPE's source span rides in the VALUE slot exactly as
//                                             kind 40's does, and children are [name Identifier (kind 6), coll, body].
//                                             The element is converted to the annotation once per iteration. )
//   TupleDeconstructionStatement -> kind 30  ( `n0, n1, ... := <tuple>` and `(n0, n1, ...) := <tuple>`, with `=`
//                                         as well as `:=`; children [name0..nameN-1 (Identifier kind 6), value].
//                                         The OPERATOR token is the value span: `:=` declares, `=` assigns. )
//   TypedLocalDeclaration        -> kind 40  ( [let] name: Type = init; the TYPE's source span in the VALUE slot
//                                             (type trees cannot share this table — kind spaces collide), children
//                                             [name Identifier (kind 6), init root]. Kinds 31-39 belong to the
//                                             expression/pattern kernel. )
//   LocalFunctionDeclaration     -> kind 41  ( `func name(...) ... { body }` — or `... => expression` — as a
//                                             STATEMENT. The kernel records ONLY the `func` keyword's byte
//                                             span (value slot, no children) and
//                                             SKIPS the whole declaration: to the first depth-0 `{` balanced to
//                                             its close (the struct kernel's method-skip discipline), or to the
//                                             end of the expression behind a depth-0 `=>`. The host re-locates
//                                             the keyword by byte offset and parses the signature + body
//                                             through the existing kernels. )
//   ThrowStatement               -> kind 48  ( throw <expr>; 1 child = the exception expression.
//                                             ZERO children = a bare `throw` — the RETHROW of the
//                                             exception the enclosing `catch` handler is running for,
//                                             lowered to IL `rethrow` so the original stack survives. )
//   TryStatement                 -> kind 49  ( try/catch.../finally?; children [tryBlock, catch1..catchN,
//                                             finallyBlock? (a trailing kind-25 block)] )
//   CatchClause                  -> kind 50  ( one catch; value span = the exception TYPE name token, -1 for
//                                             a bare catch; children [nameIdent (kind 6)?,
//                                             filter (kind 84)?, block (kind 25)]. The block is ALWAYS
//                                             last and all three slots are distinguishable by kind, so a
//                                             reader takes the body as the last child and asks the two
//                                             leading slots what they are rather than counting them. )
//   CatchFilterClause            -> kind 84  ( `when <expr>` on a catch -- ONE child, the guard expression.
//                                             A WRAPPER rather than a bare child so that a guard which is
//                                             itself a bare name cannot be mistaken for the clause's
//                                             optional kind-6 binding. Appears ONLY as a kind-50 child.
//                                             Lowered to a real CLR filter block: the guard runs on the
//                                             first pass, BEFORE any unwinding, which is the whole
//                                             observable difference from catch-and-rethrow. )
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
//                                             token in the value span, ONE child [body block]. Kind 63 belongs
//                                             to the expression kernel (TargetTypedNewExpression); kind 64 belongs
//                                             to the expression kernel (SpreadArgumentExpression). )
//   UsingStatement               -> kind 77  ( `using <resource> { body }` / `using x := e { body }` /
//                                             `using x: T := e { body }` / `using x := e` with NO body (the
//                                             using DECLARATION, disposed at the end of the ENCLOSING block).
//                                             Children [resource] or [resource, body]: the resource is a
//                                             kind-24 or kind-40 local DECLARATION when the statement binds
//                                             it and an ordinary expression when it does not, so the two
//                                             forms are told apart by the child's KIND. Kind 81 is the
//                                             `await using` twin -- same shape, released through
//                                             `IAsyncDisposable.DisposeAsync()`. )
//   OffStatement                 -> kind 80  ( `off <handle>` -- the UNSUBSCRIBE, ONE child [the handle
//                                             expression]. The contextual `off` is committed only when an
//                                             IDENTIFIER follows it (ColumnarParserRecovery.IsOffStatementStart's
//                                             rule), so a local named `off` keeps every other spelling.
//                                             Detaching an already-detached handle is a no-op at runtime. )
//   AwaitForeachStatement        -> kind 73  ( `await foreach <var> in <coll> { body }` -- the Await 69 +
//                                             Foreach 26 two-token dispatch (Parser.cs:2249). Same shape as
//                                             kind 29: var name in the value span, children [coll, body];
//                                             the distinct kind marks asynchronous enumeration. A statement
//                                             `await <expr>` whose lookahead is NOT `foreach` stays an
//                                             ExpressionStatement over AwaitExpression kind 53. )
//   Systems policy wrappers (`allow(...) {}`, `alloc {}`, `unsafe {}`) parse as transparent kind-25 blocks;
//                                             systems analysis owns policy semantics before emission.
// `:=` (ColonAssign 121) after a BARE identifier is the variable declaration (Kind=Let, Type=null); `=`
// (Assign 93) is an assignment EXPRESSION wrapped in an ExpressionStatement. An
// if/while body is ANY statement (commonly a `{ }` block, but a single statement is also valid), so the
// bodies recurse through the statement dispatcher; `else if` chains as a nested if.
//
// Deferred: parenthesised `foreach (x in y)` / `await foreach (x in y)`, const/readonly declarations, switch,
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

// THE ONE BOUNDED TYPE-ARGUMENT-LIST SCAN BOTH `<` DISAMBIGUATIONS SHARE -- the columnar twin of
// `ColumnarParserRecovery.ScanTypeArgumentListClose`, whose header comment carries the full rule.
// From the `<` at `lessPos`, walk a candidate type-argument list and answer the index of the token
// AFTER its matching close, or -1 when the run cannot be a type-argument list at all. A type argument
// is a whole TYPE: identifiers (0) and `.`-qualified names (124), nested generics with `>>` (112)
// spending two levels of depth, array ranks (131/132), nullable suffixes (115/119) and tuples.
// A `(` (127) group is admitted only as a TUPLE type -- it needs a comma (134) of its own paren depth
// before its `)` (128) -- and a `:` (122) only inside such a group, where it names an element.
func ScanTypeArgsClose(tokens: ParserTokenTable, count: int, lessPos: int): int {
    i := lessPos + 1
    if i >= count {
        return -1
    }

    firstKind := tokens.Kinds[i]
    if firstKind != 0 && firstKind != 127 {
        return -1
    }

    depth := 1
    // One entry per open tuple group: whether that group has yet seen a comma of its own.
    parenCommas := new List<bool>()
    while i < count {
        k := tokens.Kinds[i]
        if k == 0 || k == 115 || k == 119 || k == 124 || k == 131 || k == 132 {
            i = i + 1
        } else if k == 134 {
            if parenCommas.Count > 0 {
                parenCommas[parenCommas.Count - 1] = true
            }

            i = i + 1
        } else if k == 122 {
            if parenCommas.Count == 0 {
                return -1
            }

            i = i + 1
        } else if k == 127 {
            parenCommas.Add(false)
            i = i + 1
        } else if k == 128 {
            if parenCommas.Count == 0 || !parenCommas[parenCommas.Count - 1] {
                return -1
            }

            parenCommas.RemoveAt(parenCommas.Count - 1)
            i = i + 1
        } else if k == 100 {
            depth = depth + 1
            i = i + 1
        } else if k == 102 {
            depth = depth - 1
            i = i + 1
            if depth == 0 {
                if parenCommas.Count != 0 {
                    return -1
                }

                return i
            }
        } else if k == 112 {
            depth = depth - 2
            i = i + 1
            if depth == 0 {
                if parenCommas.Count != 0 {
                    return -1
                }

                return i
            }

            if depth < 0 {
                return -1
            }
        } else {
            return -1
        }
    }

    return -1
}

// The CONSTRUCTED GENERIC TYPE RECEIVER half: the matching close is followed DIRECTLY by a `.` (124).
// That trailing dot is the whole disambiguation -- `Vector<int>.Count` is a receiver, while
// `a < b && c > d` and `x < y.Z` are comparisons and answer false here. The two predicates are
// mutually exclusive by their close token.
func IsGenericTypeReceiverArgs(tokens: ParserTokenTable, count: int, lessPos: int): bool {
    closePos := ScanTypeArgsClose(tokens, count, lessPos)
    return closePos >= 0 && closePos < count && tokens.Kinds[closePos] == 124
}

// The generic METHOD CALL half: the matching close is followed DIRECTLY by a `(` (127).
func IsGenericCallTypeArgs(tokens: ParserTokenTable, count: int, lessPos: int): bool {
    closePos := ScanTypeArgsClose(tokens, count, lessPos)
    return closePos >= 0 && closePos < count && tokens.Kinds[closePos] == 127
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
    if st.Pos < count && tokens.Kinds[st.Pos] == 129 {
        return ParseObjectPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
    }

    if st.Pos < count && tokens.Kinds[st.Pos] == 131 {
        return ParseListPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
    }

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

    // Union-case PROPERTY pattern: `<Union.Case> { field, field: pat, ... }` -> UnionCasePattern (kind 37),
    // children [memberAccessNode, propertyPattern0, ...]. Fires only when the leaf is a qualified member access
    // (kind 8, e.g. `Result.Success`) immediately followed by `{` (129). Each property entry is kind 68 and may
    // carry a nested pattern; a bare property entry binds the field to a same-named local.
    if nodes.Kinds[leaf] == 8 && st.Pos < count && tokens.Kinds[st.Pos] == 129 {
        st.Pos = st.Pos + 1
        caseArgBase := st.ArgStackTop
        argStack.Values[st.ArgStackTop] = leaf
        st.ArgStackTop = st.ArgStackTop + 1
        while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
            bindNode := ParsePropertyPatternEntryNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if bindNode < 0 {
                st.ArgStackTop = caseArgBase
                return -1
            }

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
    if nodes.Kinds[leaf] == 6 && st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && (tokens.Kinds[st.Pos + 1] == 120 || tokens.Kinds[st.Pos + 1] == 54) {
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

func ParseObjectPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 129 {
        return -1
    }

    objectStart := tokens.Starts[st.Pos]
    st.Pos = st.Pos + 1
    objectArgBase := st.ArgStackTop

    while st.Pos < count && tokens.Kinds[st.Pos] != 130 {
        entry := ParsePropertyPatternEntryNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if entry < 0 {
            st.ArgStackTop = objectArgBase
            return -1
        }

        argStack.Values[st.ArgStackTop] = entry
        st.ArgStackTop = st.ArgStackTop + 1

        if st.Pos < count && tokens.Kinds[st.Pos] != 130 {
            if tokens.Kinds[st.Pos] != 134 {
                st.ArgStackTop = objectArgBase
                return -1
            }

            st.Pos = st.Pos + 1
        }
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 130 {
        st.ArgStackTop = objectArgBase
        return -1
    }

    objectEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - objectArgBase
    childRun := st.ChildCursor
    a := objectArgBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }

    st.ArgStackTop = objectArgBase
    return EmitExpressionNode(st, nodes, 67, -1, 0, childRun, childCount, objectStart, objectEnd - objectStart)
}

func ParsePropertyPatternEntryNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
        return -1
    }

    propStart := tokens.Starts[st.Pos]
    propLength := tokens.ValueLengths[st.Pos]
    propEnd := propStart + propLength
    st.Pos = st.Pos + 1
    childRun := -1
    childCount := 0

    if st.Pos < count && tokens.Kinds[st.Pos] == 122 {
        st.Pos = st.Pos + 1
        pattern := ParseMatchPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if pattern < 0 {
            return -1
        }

        childRun = st.ChildCursor
        AppendExpressionChild(st, children, pattern)
        childCount = 1
        propEnd = nodes.SpanStarts[pattern] + nodes.SpanLengths[pattern]
    }

    return EmitExpressionNode(st, nodes, 68, propStart, propLength, childRun, childCount, propStart, propEnd - propStart)
}

func ParseListPatternNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 131 {
        return -1
    }

    listStart := tokens.Starts[st.Pos]
    st.Pos = st.Pos + 1
    listArgBase := st.ArgStackTop

    if st.Pos < count && tokens.Kinds[st.Pos] != 132 {
        parsing := true
        while parsing {
            pattern := -1
            if st.Pos < count && tokens.Kinds[st.Pos] == 125 {
                sliceStart := tokens.Starts[st.Pos]
                sliceLength := tokens.ValueLengths[st.Pos]
                st.Pos = st.Pos + 1
                bindStart := -1
                bindLength := 0
                sliceEnd := sliceStart + sliceLength
                if st.Pos < count && tokens.Kinds[st.Pos] == 0 {
                    bindStart = tokens.Starts[st.Pos]
                    bindLength = tokens.ValueLengths[st.Pos]
                    sliceEnd = bindStart + bindLength
                    st.Pos = st.Pos + 1
                }

                pattern = EmitExpressionNode(st, nodes, 66, bindStart, bindLength, -1, 0, sliceStart, sliceEnd - sliceStart)
            } else {
                pattern = ParseMatchPatternNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if pattern < 0 {
                    st.ArgStackTop = listArgBase
                    return -1
                }
            }

            argStack.Values[st.ArgStackTop] = pattern
            st.ArgStackTop = st.ArgStackTop + 1

            if st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                if st.Pos < count && tokens.Kinds[st.Pos] == 132 {
                    st.ArgStackTop = listArgBase
                    return -1
                }
            } else {
                parsing = false
            }
        }
    }

    if st.Pos >= count || tokens.Kinds[st.Pos] != 132 {
        st.ArgStackTop = listArgBase
        return -1
    }

    listEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    childCount := st.ArgStackTop - listArgBase
    childRun := st.ChildCursor
    a := listArgBase
    while a < st.ArgStackTop {
        AppendExpressionChild(st, children, argStack.Values[a])
        a = a + 1
    }

    st.ArgStackTop = listArgBase
    return EmitExpressionNode(st, nodes, 65, -1, 0, childRun, childCount, listStart, listEnd - listStart)
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
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IntLiteralExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }

    if kind == 2 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.FloatLiteralExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }

    if kind == 3 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.CharLiteralExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }

    if kind == 4 || kind == 5 || kind == 6 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.StringLiteralExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }

    if kind == 44 || kind == 45 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.BoolLiteralExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
    }

    if kind == 46 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.NullLiteralExpression, -1, 0, -1, 0, tokenStart, tokenLength)
    }

    // `default` (Default 34) — the null literal's twin: a keyword primary with no operand whose TYPE
    // comes from the position it is written in. It is recorded with no value span for the same reason
    // `null` is, and its full source span is the keyword.
    if kind == 34 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.DefaultExpression, -1, 0, -1, 0, tokenStart, tokenLength)
    }

    // A BARE `this` (This 42). The `this.Member` and `this[...]` prefixes never reach here — the postfix
    // parser collapses the member form one level up — so this arm sees only the keyword standing on its
    // own as a value, and it records the keyword's own span with no value text, like `null` and `default`.
    if kind == 42 {
        st.Pos = pos + 1
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.ThisExpression, -1, 0, -1, 0, tokenStart, tokenLength)
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
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IdentifierExpression, tokenStart, tokenLength, -1, 0, tokenStart, tokenLength)
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
                anonValue := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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
                targetFirstArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if targetFirstArg < 0 {
                    st.ArgStackTop = targetArgBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = targetFirstArg
                st.ArgStackTop = st.ArgStackTop + 1

                while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                    st.Pos = st.Pos + 1
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
        if st.Pos < count && tokens.Kinds[st.Pos] == 129 && st.Pos != st.UsingBodyBrace {
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
                fieldVal := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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
            firstArg := ParseConstructorArgumentNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if firstArg < 0 {
                st.ArgStackTop = argBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = firstArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
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

        if st.Pos < count && tokens.Kinds[st.Pos] == 129 && st.Pos != st.UsingBodyBrace {
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
                initValue := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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

            // `(<identifier>)..end` is a parenthesized range start, not a cast whose operand
            // begins with `..`. Open-start ranges are expression starts everywhere else.
            //
            // AND the operand must begin on the closing paren's OWN LINE. N# has no statement
            // terminator, so a newline between the `)` and the next token is a STATEMENT BOUNDARY --
            // `print(c.Count)` followed on the next line by `sum := 0` is two statements, never a cast
            // of `sum` to the type `c.Count`. This mirrors ColumnarParserRecovery.IsCastExpression so
            // the diagnostic front end and this emit front end read one grammar. Entry points that
            // carry no source text (st.Source empty) cannot see the break and keep the same-line-only
            // reading they had; every STATEMENT route passes source.
            if st.Pos + 1 < count && tokens.Kinds[st.Pos + 1] != 125 && IsExpressionStartKind(tokens.Kinds[st.Pos + 1]) && !ParserSourceHasLineBreakBetween(st.Source, tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos], tokens.Starts[st.Pos + 1]) {
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

        // A TUPLE ELEMENT'S NAME IS DECIDED PER ELEMENT, NOT FOR THE WHOLE LITERAL.
        // A `name: value` element becomes a kind-43 NamedTupleElement wrapper -- element NAME in the
        // name slot, ONE child = the element value -- and a positional element is its bare value, so
        // `(null, last, IsConstructor: true)` mixes the two exactly as C# does. The all-or-nothing
        // reading this replaced refused every mixed literal outright. Detected by the `Identifier :`
        // lookahead, which no other parenthesised expression element form can start with.
        firstNameStart := 0
        firstNameLength := 0
        firstNamed := st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122
        if firstNamed {
            firstNameStart = tokens.Starts[st.Pos]
            firstNameLength = tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 2
        }

        inner := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if inner < 0 {
            return -1
        }

        if firstNamed {
            firstWrapRun := st.ChildCursor
            AppendExpressionChild(st, children, inner)
            inner = EmitExpressionNode(st, nodes, 43, firstNameStart, firstNameLength, firstWrapRun, 1, firstNameStart, nodes.SpanStarts[inner] + nodes.SpanLengths[inner] - firstNameStart)
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
                elemNameStart := 0
                elemNameLength := 0
                elemNamed := st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122
                if elemNamed {
                    elemNameStart = tokens.Starts[st.Pos]
                    elemNameLength = tokens.ValueLengths[st.Pos]
                    st.Pos = st.Pos + 2
                }

                tupleElem := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
                if tupleElem < 0 {
                    st.ArgStackTop = tupleArgBase
                    return -1
                }

                if elemNamed {
                    elemWrapRun := st.ChildCursor
                    AppendExpressionChild(st, children, tupleElem)
                    tupleElem = EmitExpressionNode(st, nodes, 43, elemNameStart, elemNameLength, elemWrapRun, 1, elemNameStart, nodes.SpanStarts[tupleElem] + nodes.SpanLengths[tupleElem] - elemNameStart)
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

        // A single element is not a tuple. Unnamed, it is the parenthesized expression below; NAMED, it
        // is a shape with no meaning at all and the columnar parse refuses it.
        if firstNamed || st.Pos >= count || tokens.Kinds[st.Pos] != 128 {
            return -1
        }

        rightParenEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, inner)
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.ParenthesizedExpression, -1, 0, childRunStart, 1, parenStart, rightParenEnd - parenStart)
    }

    return -1
}

// DOES THE TOKEN AT `index` BEGIN A NEW SOURCE LINE? The answer is the text between the previous
// token's end and this token's start: whitespace and comments, and a line break if there is one. The
// scan is bounded by that gap, so the common same-line answer costs a character or two.
//
// The first token of a run begins no chain continuation and answers false, and so does a table with
// no source text.
func ParserTokenBeginsLine(tokens: ParserTokenTable, index: int): bool {
    source := tokens.Source ?? ""
    if source.Length == 0 || index <= 0 || index >= tokens.Starts.Length {
        return false
    }

    gapEnd := tokens.Starts[index]
    if gapEnd > source.Length {
        gapEnd = source.Length
    }

    scan := tokens.Starts[index - 1] + tokens.ValueLengths[index - 1]
    if scan < 0 {
        scan = 0
    }

    while scan < gapEnd {
        if source[scan] == '\n' {
            return true
        }

        scan = scan + 1
    }

    return false
}

func ParsePostfixExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    expr := -1
    if st.Pos + 2 < count && tokens.Kinds[st.Pos] == 42 && tokens.Kinds[st.Pos + 1] == 124 && tokens.Kinds[st.Pos + 2] == 0 {
        thisStart := tokens.Starts[st.Pos]
        memberStart := tokens.Starts[st.Pos + 2]
        memberLength := tokens.ValueLengths[st.Pos + 2]
        memberEnd := memberStart + memberLength
        expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IdentifierExpression, memberStart, memberLength, -1, 0, thisStart, memberEnd - thisStart)

        st.Pos = st.Pos + 3
    } else if st.Pos + 2 < count && tokens.Kinds[st.Pos] == 43 && tokens.Kinds[st.Pos + 1] == 124 && tokens.Kinds[st.Pos + 2] == 0 {

        // `base.Member` (Base 43, Dot 124, Identifier 0) -- the same two-token prefix shape as the
        // `this.` arm above, into a node kind of its own. The receiver is still argument zero, but the
        // member it names is looked up in the BASE and dispatched non-virtually, and a kind that a
        // planner could confuse with `this` would silently turn `base.M()` into infinite recursion.
        baseStart := tokens.Starts[st.Pos]
        baseMemberStart := tokens.Starts[st.Pos + 2]
        baseMemberLength := tokens.ValueLengths[st.Pos + 2]
        baseMemberEnd := baseMemberStart + baseMemberLength
        expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.BaseMemberExpression, baseMemberStart, baseMemberLength, -1, 0, baseStart, baseMemberEnd - baseStart)

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

        if pos < count && tokens.Kinds[pos] != 124 && tokens.Kinds[pos] != 118 && ParserTokenBeginsLine(tokens, pos) {

            // A NEW LINE ENDS THE CHAIN (ParsePostfix :4411 — `Current().Line > Previous().Line` with
            // no continuing `.` / `?.`). Only Dot 124 and QuestionDot 118 carry an access chain across
            // a line break. A `[`, `(`, `<` or `with` that OPENS a line begins the next thing in the
            // file — most often the next member's `[Attribute]` list after an expression-bodied member
            // — and reading it as a suffix silently rewrites the program instead of failing.
            matched = false
        } else if pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
            objSpanStart := nodes.SpanStarts[expr]
            memberStart := tokens.Starts[pos + 1]
            memberLength := tokens.ValueLengths[pos + 1]
            memberEnd := memberStart + memberLength
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, expr)
            expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.MemberAccessExpression, memberStart, memberLength, childRunStart, 1, objSpanStart, memberEnd - objSpanStart)

            st.Pos = pos + 2
        } else if pos + 1 < count && tokens.Kinds[pos] == 118 && tokens.Kinds[pos + 1] == 0 {

            // `receiver?.member` (QuestionDot 118) -- the `.` branch above with the receiver wrapped in a
            // NULL GUARD (kind 75). Everything that reads an access reads the SAME kind-8 node it always
            // did, and a following `(` still makes the ordinary kind-9 call over it, so `a?.M(x)` needs no
            // shape of its own. What the guard adds is a place for the SHORT CIRCUIT: it is the node that
            // tests the receiver once and, when it is null, abandons the rest of the chain.
            objSpanStart := nodes.SpanStarts[expr]
            guardSpanLength := nodes.SpanLengths[expr]
            guardChildRun := st.ChildCursor
            AppendExpressionChild(st, children, expr)
            guard := EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.NullGuardExpression, -1, 0, guardChildRun, 1, objSpanStart, guardSpanLength)
            memberStart := tokens.Starts[pos + 1]
            memberLength := tokens.ValueLengths[pos + 1]
            memberEnd := memberStart + memberLength
            childRunStart := st.ChildCursor
            AppendExpressionChild(st, children, guard)
            expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.MemberAccessExpression, memberStart, memberLength, childRunStart, 1, objSpanStart, memberEnd - objSpanStart)

            st.Pos = pos + 2
        } else if pos < count && tokens.Kinds[pos] == 131 {
            objSpanStart := nodes.SpanStarts[expr]
            st.Pos = pos + 1
            index := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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
            expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IndexAccessExpression, -1, 0, childRunStart, 2, objSpanStart, rightBracketEnd - objSpanStart)
        } else if pos < count && tokens.Kinds[pos] == 100 && (nodes.Kinds[expr] == 6 || nodes.Kinds[expr] == 8) && IsGenericTypeReceiverArgs(tokens, count, pos) {

            // `Name<Args>.` / `A.B.Name<Args>.` -- a CONSTRUCTED GENERIC TYPE RECEIVER (kind 70), the
            // `.`-closed twin of the kind-38 generic callee below and built exactly like it: value
            // span = the full dotted head name, children = the TYPE-kernel type-argument roots, the
            // `>>` split honoured through the shared owed-greater state. The `.` branch of this loop
            // then reads the member off it, so `Vector<int>.Count` is a MemberAccess over a kind-70
            // node and the planners resolve the receiver as a TYPE instead of a value.
            receiverNameStart := nodes.ValueStarts[expr]
            receiverNameLength := nodes.ValueLengths[expr]
            receiverSpanStart := nodes.SpanStarts[expr]
            if nodes.Kinds[expr] == 8 {
                receiverNameStart = receiverSpanStart
                receiverNameLength = nodes.SpanLengths[expr]
            }

            st.Pos = pos + 1
            receiverArgBase := st.ArgStackTop
            st.SplitGreaterDepth = 0
            firstReceiverArg := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
            if firstReceiverArg < 0 {
                st.ArgStackTop = receiverArgBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = firstReceiverArg
            st.ArgStackTop = st.ArgStackTop + 1

            while st.SplitGreaterDepth == 0 && st.Pos < count && tokens.Kinds[st.Pos] == 134 {
                st.Pos = st.Pos + 1
                nextReceiverArg := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
                if nextReceiverArg < 0 {
                    st.ArgStackTop = receiverArgBase
                    return -1
                }

                argStack.Values[st.ArgStackTop] = nextReceiverArg
                st.ArgStackTop = st.ArgStackTop + 1
            }

            receiverCloseEnd := ConsumeGreaterForTypeNodeCore(tokens, count, st)
            if receiverCloseEnd < 0 {
                st.ArgStackTop = receiverArgBase
                return -1
            }

            receiverChildCount := st.ArgStackTop - receiverArgBase
            receiverChildRunStart := st.ChildCursor
            r := receiverArgBase
            while r < st.ArgStackTop {
                AppendExpressionChild(st, children, argStack.Values[r])
                r = r + 1
            }

            st.ArgStackTop = receiverArgBase
            expr = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.GenericTypeReceiverExpression, receiverNameStart, receiverNameLength, receiverChildRunStart, receiverChildCount, receiverSpanStart, receiverCloseEnd - receiverSpanStart)
        } else if pos < count && tokens.Kinds[pos] == 100 && (nodes.Kinds[expr] == 6 || nodes.Kinds[expr] == 8) && IsGenericCallTypeArgs(tokens, count, pos) {

            // Explicit generic-call TYPE ARGUMENTS `callee<T1, T2>(args)` — committed when the callee is
            // a bare identifier or dotted member access and the lookahead (the Parser.cs IsGenericMethodCall mirror above) sees a
            // well-formed type-argument list whose close is followed DIRECTLY by `(`. Each argument parses as
            // a TYPE-kernel subtree on the shared table; the result is a GenericCalleeExpression (kind 38:
            // value span = the full callee name, children = [callee expression, type-arg roots...]). The
            // `(` branch of
            // this loop then parses the CALL with the kind-38 node as its callee, so a generic call is
            // [genericCallee, arg0, ...] exactly like a plain call. The `>>` split for a nested generic close
            // is honored via the shared st.SplitGreaterDepth owed-greater state (ConsumeGreaterForTypeNodeCore).
            //
            // CHILD 0 IS THE CALLEE EXPRESSION ITSELF — the kind-6 identifier or the kind-8 member access
            // the type arguments were written on — and it is the node every consumer reads the RECEIVER
            // from (`ColumnarGenericCalleeFacts`). The value span is kept unchanged beside it because the
            // dotted-name tiers still read the written spelling, but a receiver that is not a plain name
            // (`MakeList().OfType<string>()`, `services.AddSingleton<A>().AddSingleton<B>()`) is reachable
            // only structurally: re-reading the span text would hand a resolver source that has already
            // evaluated something.
            calleeNameStart := nodes.ValueStarts[expr]
            calleeNameLength := nodes.ValueLengths[expr]
            objSpanStart := nodes.SpanStarts[expr]
            if nodes.Kinds[expr] == 8 {
                calleeNameStart = objSpanStart
                calleeNameLength = nodes.SpanLengths[expr]
            }

            st.Pos = pos + 1
            gArgBase := st.ArgStackTop
            argStack.Values[st.ArgStackTop] = expr
            st.ArgStackTop = st.ArgStackTop + 1
            st.SplitGreaterDepth = 0
            firstTypeArg := ParseExpressionTypeReferenceNode(tokens, count, st, argStack, nodes, children, 0)
            if firstTypeArg < 0 {
                st.ArgStackTop = gArgBase
                return -1
            }

            argStack.Values[st.ArgStackTop] = firstTypeArg
            st.ArgStackTop = st.ArgStackTop + 1

            // Owed-`>` discipline (see the type kernel's argument loop): a split `>>` close must not
            // let the raw cursor's `,` read as another type argument.
            while st.SplitGreaterDepth == 0 && st.Pos < count && tokens.Kinds[st.Pos] == 134 {
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
            // `)`. A `name:` argument becomes a kind-60 NamedArgumentExpression wrapper around the
            // argument it names, so the call's child run is still [callee, arg0, arg1, ...].
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
                wValue := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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
    if st.Pos < count && !ParserTokenBeginsLine(tokens, st.Pos) {
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

    if st.Pos < count && tokens.Kinds[st.Pos] == 126 {
        spreadStart := tokens.Starts[st.Pos]
        spreadLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1
        value := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if value < 0 {
            return -1
        }

        valueEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
        childRun := st.ChildCursor
        AppendExpressionChild(st, children, value)
        return EmitExpressionNode(st, nodes, 64, spreadStart, spreadLength, childRun, 1, spreadStart, valueEnd - spreadStart)
    }

    // `name: <argument>` -- a NAMED argument (NamedArgumentExpression kind 60: the parameter name in the
    // value span, ONE child [argument]). The child is a full call argument of its own, so a named
    // `ref`/`out` argument (`TryParse(s, result: out parsed)`) keeps its kind-54 wrapper underneath the
    // name. A spread cannot be named -- `...` names no parameter -- and recursing here would accept
    // `f(name: ...xs)`, so the child is parsed at the modifier level, not at this one.
    if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
        nameStart := tokens.Starts[st.Pos]
        nameLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 2
        named := ParseCallArgumentModifierOrValueNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if named < 0 {
            return -1
        }

        namedEnd := nodes.SpanStarts[named] + nodes.SpanLengths[named]
        namedChildRun := st.ChildCursor
        AppendExpressionChild(st, children, named)
        return EmitExpressionNode(st, nodes, 60, nameStart, nameLength, namedChildRun, 1, nameStart, namedEnd - nameStart)
    }

    return ParseCallArgumentModifierOrValueNode(tokens, count, st, argStack, nodes, children, depth)
}

// The `ref`/`out`/`in` modifier layer of a call argument, shared by the positional and the named forms:
// `ref <expr>` / `out <expr>` / `in <expr>` (Ref 78 / Out 79 / In 28) becomes a RefOutArgument (kind 54,
// the modifier token in the value span, ONE child [target]); anything else is an ordinary argument
// expression.
//
// `in` IS OPTIONAL AT A CALL SITE and `ref`/`out` are not, which is a rule the CALLEE's signature owns
// rather than this layer: a plain argument reaching an `in` parameter is admitted by the score, and
// writing the word is the caller saying out loud what the signature already said. Kind 28 is the same
// token `for x in xs` reads; an argument list is not a position that reading can occur in.
func ParseCallArgumentModifierOrValueNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos < count && (tokens.Kinds[st.Pos] == 78 || tokens.Kinds[st.Pos] == 79 || tokens.Kinds[st.Pos] == 28) {
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

    if st.Pos + 1 < count && tokens.Kinds[st.Pos] == 0 && tokens.Kinds[st.Pos + 1] == 122 {
        nameStart := tokens.Starts[st.Pos]
        nameLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 2
        value := ParseCallArgumentModifierOrValueNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if value < 0 {
            return -1
        }

        valueEnd := nodes.SpanStarts[value] + nodes.SpanLengths[value]
        childRun := st.ChildCursor
        AppendExpressionChild(st, children, value)
        return EmitExpressionNode(st, nodes, 60, nameStart, nameLength, childRun, 1, nameStart, valueEnd - nameStart)
    }

    return ParseCallArgumentModifierOrValueNode(tokens, count, st, argStack, nodes, children, depth)
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
            return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.UnaryExpression, opStart, opLength, childRunStart, 1, opStart, operandSpanEnd - opStart)
        }
    }

    return ParsePostfixExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

func IsRangeExpressionEndKind(kind: int): bool {
    return kind == 122 || kind == 128 || kind == 130 || kind == 132 || kind == 133 || kind == 134 || kind == 135 || kind == 136
}

func ParseRangeExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    if st.Pos < count && tokens.Kinds[st.Pos] == 125 {
        dotDotStart := tokens.Starts[st.Pos]
        dotDotLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        endNode := -1
        rangeEnd := dotDotStart + dotDotLength
        if st.Pos < count && !IsRangeExpressionEndKind(tokens.Kinds[st.Pos]) {
            endNode = ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if endNode < 0 {
                return -1
            }

            rangeEnd = nodes.SpanStarts[endNode] + nodes.SpanLengths[endNode]
        }

        childRun := st.ChildCursor
        childCount := 0
        if endNode >= 0 {
            AppendExpressionChild(st, children, endNode)
            childCount = 1
        }

        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.RangeExpression, dotDotStart, dotDotLength, childRun, childCount, dotDotStart, rangeEnd - dotDotStart)
    }

    startNode := ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    if startNode < 0 {
        return -1
    }

    if st.Pos < count && tokens.Kinds[st.Pos] == 125 {
        dotDotStart := tokens.Starts[st.Pos]
        dotDotLength := tokens.ValueLengths[st.Pos]
        st.Pos = st.Pos + 1

        endNode := -1
        rangeEnd := dotDotStart + dotDotLength
        if st.Pos < count && !IsRangeExpressionEndKind(tokens.Kinds[st.Pos]) {
            endNode = ParseUnaryExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if endNode < 0 {
                return -1
            }

            rangeEnd = nodes.SpanStarts[endNode] + nodes.SpanLengths[endNode]
        }

        childRun := st.ChildCursor
        AppendExpressionChild(st, children, startNode)
        childCount := 1
        if endNode >= 0 {
            AppendExpressionChild(st, children, endNode)
            childCount = 2
        }

        rangeStart := nodes.SpanStarts[startNode]
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.RangeExpression, dotDotStart, dotDotLength, childRun, childCount, rangeStart, rangeEnd - rangeStart)
    }

    return startNode
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

    left := ParseRangeExpressionNode(tokens, count, st, argStack, nodes, children, depth)
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
        // THE PATTERN VARIABLE (`value is Type name`) LIVES IN THE VALUE SPAN. `as` never has one, and
        // `is` has no other use for the slot, so the binding needs no extra child — which matters because
        // a kind-46 child run is [value, typeRoot] and every scan walks child 0 as a value and child 1 as
        // a TYPE. Absent, the slot stays (-1, 0), exactly as before.
        //
        // The name must sit on the SAME LINE as the end of the type: statements are newline-terminated,
        // so an identifier opening the next line starts a new statement. This is the production parser's
        // gate (ColumnarParserRecovery.ParseRelational), and WITHOUT it the columnar kernel used to stop
        // the expression at the type and leave `name` to be read as a fresh statement — `return o is string s && s.Length > 0`
        // silently became a `return` followed by an unreachable expression statement.
        isAsBindingStart := -1
        isAsBindingLength := 0
        if isAsKind == 46 && st.Pos < count && tokens.Kinds[st.Pos] == 0 && !ParserSourceHasLineBreakBetween(st.Source, isAsSpanEnd, tokens.Starts[st.Pos]) {
            isAsBindingStart = tokens.Starts[st.Pos]
            isAsBindingLength = tokens.ValueLengths[st.Pos]
            isAsSpanEnd = isAsBindingStart + isAsBindingLength
            st.Pos = st.Pos + 1
        }

        isAsChildRun := st.ChildCursor
        AppendExpressionChild(st, children, left)
        AppendExpressionChild(st, children, isAsType)
        left = EmitExpressionNode(st, nodes, isAsKind, isAsBindingStart, isAsBindingLength, isAsChildRun, 2, isAsSpanStart, isAsSpanEnd - isAsSpanStart)
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
            // `x ?? throw e` — the FALLBACK of a null-coalesce may be a throw expression (kind 83),
            // and `??` (116) is the only operator whose right operand may be: it is the one whose
            // result the LEFT side already decides, so a fallback that produces nothing still leaves
            // the expression with a type. Every other operator needs a value on both sides.
            right := -1
            if opKind == 116 && st.Pos < count && tokens.Kinds[st.Pos] == 37 {
                right = ParseThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            } else {
                right = ParseBinaryExpressionNode(tokens, count, st, argStack, nodes, children, prec + 1, depth + 1)
            }

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

// `throw <exception>` in VALUE position -- ThrowExpression kind 83, ONE child (the exception
// expression), no value span, the span running from the `throw` keyword through the operand.
//
// It is NOT reached from the expression precedence chain: a throw expression is worth nothing, so
// the only places it can stand are the ones where some OTHER operand supplies the type. Each of
// those three callers asks for one BY NAME at the exact token where the grammar admits it -- the
// right operand of `??`, either arm of a conditional, and an expression body -- so `1 + throw e`
// never parses here at all. The operand is a full assignment-level expression, exactly as the
// statement form's is, and a bare `throw` (no operand) is refused: the rethrow is a statement.
func ParseThrowExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 || st.Pos >= count || tokens.Kinds[st.Pos] != 37 {
        return -1
    }

    throwStart := tokens.Starts[st.Pos]
    st.Pos = st.Pos + 1
    operand := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
    if operand < 0 {
        return -1
    }

    operandEnd := nodes.SpanStarts[operand] + nodes.SpanLengths[operand]
    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, operand)
    return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.ThrowExpression, -1, 0, childRunStart, 1, throwStart, operandEnd - throwStart)
}

// A value position that ADMITS a throw expression: `throw` (37) opens one, anything else is an
// ordinary assignment-level expression. The three grammar positions all read exactly this way.
func ParseValueOrThrowExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if st.Pos < count && tokens.Kinds[st.Pos] == 37 {
        return ParseThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    }

    return ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

// The EXPRESSION-BODY twin of the position above. An arrow body sits at the LAMBDA level rather than
// the assignment level (`=> x => x + 1` returns a lambda), so the non-throw fall-through is the
// lambda-level entry; the throw arm is the same one.
func ParseBodyValueOrThrowExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if st.Pos < count && tokens.Kinds[st.Pos] == 37 {
        return ParseThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    }

    return ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
}

func ParseTernaryExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    condition := ParseBinaryExpressionNode(tokens, count, st, argStack, nodes, children, 1, depth)
    if condition < 0 {
        return -1
    }

    if st.Pos < count && tokens.Kinds[st.Pos] == 115 {
        conditionSpanStart := nodes.SpanStarts[condition]
        st.Pos = st.Pos + 1
        // EITHER ARM MAY BE A THROW (kind 83) -- `flag ? value : throw e` and its mirror. An arm that
        // throws contributes nothing to the join, so the OTHER arm decides what the conditional is
        // worth; both arms throwing has no type at all and the analyzer refuses it.
        thenNode := ParseValueOrThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if thenNode < 0 {
            return -1
        }

        if st.Pos >= count || tokens.Kinds[st.Pos] != 122 {
            return -1
        }

        st.Pos = st.Pos + 1

        elseNode := ParseValueOrThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
        if elseNode < 0 {
            return -1
        }

        elseSpanEnd := nodes.SpanStarts[elseNode] + nodes.SpanLengths[elseNode]
        childRunStart := st.ChildCursor
        AppendExpressionChild(st, children, condition)
        AppendExpressionChild(st, children, thenNode)
        AppendExpressionChild(st, children, elseNode)
        return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.TernaryExpression, -1, 0, childRunStart, 3, conditionSpanStart, elseSpanEnd - conditionSpanStart)
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
            value := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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

// `on` is a CONTEXTUAL keyword, committed on exactly the shape ColumnarParserRecovery.IsOnSubscriptionStart
// commits on: the identifier `on` followed by an identifier, `this` or `base`. Every other spelling — a local
// named `on`, `on = 1`, `on.Length` — stays an ordinary expression. An entry with no source text cannot compare
// the token, so the contextual form simply does not match there (safe under-accept -> decline).
func ParserTokenIsOnKeyword(tokens: ParserTokenTable, count: int, st: ParserState, pos: int): bool {
    if pos + 1 >= count || tokens.Kinds[pos] != 0 || st.Source.Length == 0 || !ParserDeclarationTokenTextEquals(st.Source, tokens.Starts[pos], tokens.ValueLengths[pos], "on") {
        return false
    }

    next := tokens.Kinds[pos + 1]
    return next == 0 || next == 42 || next == 43
}

// `off <handle>`, the same contextual rule (ColumnarParserRecovery.IsOffStatementStart): the identifier
// `off` followed by an IDENTIFIER.
func ParserTokenIsOffKeyword(tokens: ParserTokenTable, count: int, st: ParserState, pos: int): bool {
    return pos + 1 < count && tokens.Kinds[pos] == 0 && st.Source.Length > 0 && ParserDeclarationTokenTextEquals(st.Source, tokens.Starts[pos], tokens.ValueLengths[pos], "off") && tokens.Kinds[pos + 1] == 0
}

// THE EVENT TARGET (ColumnarParserRecovery.ParseEventTarget's mirror): a primary plus a `.member` /
// `[index]` chain that deliberately STOPS before a `(`, so the handler lambda's own parameter list is
// never swallowed as a call argument list. `this.Member` collapses to the bare member read exactly as
// the postfix parser collapses it, and `base.Member` keeps its kind-71 identity so the emitter binds
// non-virtually. A NULL-CONDITIONAL link (`?.` 118 / `?[` 119) is refused: a subscription that may not
// happen has no handle to answer with, and the analyzer reports that shape at its own position.
// Returns the chain root, or -1.
func ParseEventTargetNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    target := -1
    if st.Pos + 2 < count && tokens.Kinds[st.Pos] == 42 && tokens.Kinds[st.Pos + 1] == 124 && tokens.Kinds[st.Pos + 2] == 0 {
        thisStart := tokens.Starts[st.Pos]
        thisMemberStart := tokens.Starts[st.Pos + 2]
        thisMemberLength := tokens.ValueLengths[st.Pos + 2]
        target = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IdentifierExpression, thisMemberStart, thisMemberLength, -1, 0, thisStart, thisMemberStart + thisMemberLength - thisStart)
        st.Pos = st.Pos + 3
    } else if st.Pos + 2 < count && tokens.Kinds[st.Pos] == 43 && tokens.Kinds[st.Pos + 1] == 124 && tokens.Kinds[st.Pos + 2] == 0 {
        baseStart := tokens.Starts[st.Pos]
        baseMemberStart := tokens.Starts[st.Pos + 2]
        baseMemberLength := tokens.ValueLengths[st.Pos + 2]
        target = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.BaseMemberExpression, baseMemberStart, baseMemberLength, -1, 0, baseStart, baseMemberStart + baseMemberLength - baseStart)
        st.Pos = st.Pos + 3
    } else {
        if st.Pos >= count || tokens.Kinds[st.Pos] != 0 {
            return -1
        }

        rootStart := tokens.Starts[st.Pos]
        rootLength := tokens.ValueLengths[st.Pos]
        target = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IdentifierExpression, rootStart, rootLength, -1, 0, rootStart, rootLength)
        st.Pos = st.Pos + 1
    }

    scanning := true
    while scanning {
        pos := st.Pos
        if pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
            targetSpanStart := nodes.SpanStarts[target]
            memberStart := tokens.Starts[pos + 1]
            memberLength := tokens.ValueLengths[pos + 1]
            memberChildRun := st.ChildCursor
            AppendExpressionChild(st, children, target)
            target = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.MemberAccessExpression, memberStart, memberLength, memberChildRun, 1, targetSpanStart, memberStart + memberLength - targetSpanStart)
            st.Pos = pos + 2
        } else if pos < count && tokens.Kinds[pos] == 131 {
            targetSpanStart := nodes.SpanStarts[target]
            st.Pos = pos + 1
            indexRoot := ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
            if indexRoot < 0 || st.Pos >= count || tokens.Kinds[st.Pos] != 132 {
                return -1
            }

            closeEnd := tokens.Starts[st.Pos] + tokens.ValueLengths[st.Pos]
            st.Pos = st.Pos + 1
            indexChildRun := st.ChildCursor
            AppendExpressionChild(st, children, target)
            AppendExpressionChild(st, children, indexRoot)
            target = EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.IndexAccessExpression, -1, 0, indexChildRun, 2, targetSpanStart, closeEnd - targetSpanStart)
        } else {
            scanning = false
        }
    }

    return target
}

// `on <target> <handler>` -> OnSubscriptionExpression kind 79, children [target, handler]. The handler
// parses at the FULL-EXPRESSION level, so a block-bodied lambda, an expression-bodied lambda, a
// delegate-typed name and a call that returns a delegate all reach the same node slot.
//
// A BARE NAME IS A TARGET TOO, because `on this.Changed` IS one: `ParseEventTargetNode` collapses
// `this.Member` to the bare member read exactly as the postfix parser does, so refusing an
// identifier root refused the enclosing type's own event — `on this.Changed (…) => { … }` and
// `on Changed (…) => { … }` both declined the whole declaration at `parse.struct`. The C# AST parser
// beside this one already builds the node for that shape, so refusing here was the two parsers
// disagreeing about one program. Whether the name IS an event is the analyzer's and the emitter's
// question, and both answer it by name at the enclosing type.
func ParseOnSubscriptionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    onStart := tokens.Starts[st.Pos]
    onLength := tokens.ValueLengths[st.Pos]
    st.Pos = st.Pos + 1
    target := ParseEventTargetNode(tokens, count, st, argStack, nodes, children, depth + 1)
    if target < 0 {
        return -1
    }

    targetKind := nodes.Kinds[target]
    if targetKind != ColumnarExpressionNodeKind.MemberAccessExpression && targetKind != ColumnarExpressionNodeKind.BaseMemberExpression && targetKind != ColumnarExpressionNodeKind.IdentifierExpression {
        return -1
    }

    handler := ParseLambdaOrAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
    if handler < 0 {
        return -1
    }

    handlerEnd := nodes.SpanStarts[handler] + nodes.SpanLengths[handler]
    childRunStart := st.ChildCursor
    AppendExpressionChild(st, children, target)
    AppendExpressionChild(st, children, handler)
    return EmitExpressionNode(st, nodes, ColumnarExpressionNodeKind.OnSubscriptionExpression, onStart, onLength, childRunStart, 2, onStart, handlerEnd - onStart)
}

// Return the comma/right-paren delimiter after one typed lambda parameter, or -1 when the tokens do
// not contain a balanced type reference. The production AST parser owns the exact type grammar and
// diagnostics; this kernel only has to preserve the expression boundary after that validation.
func ScanTypedLambdaParameterEnd(tokens: ParserTokenTable, count: int, start: int): int {
    pos := start
    angleDepth := 0
    groupDepth := 0
    bracketDepth := 0
    sawTypeToken := false
    while pos < count {
        kind := tokens.Kinds[pos]
        if angleDepth == 0 && groupDepth == 0 && bracketDepth == 0 && (kind == 134 || kind == 128) {
            return sawTypeToken ? pos : -1
        }
        sawTypeToken = true
        if kind == 100 {
            angleDepth += 1
        } else if kind == 102 {
            if angleDepth <= 0 {
                return -1
            }
            angleDepth -= 1
        } else if kind == 112 {
            if angleDepth < 2 {
                return -1
            }
            angleDepth -= 2
        } else if kind == 127 {
            groupDepth += 1
        } else if kind == 128 {
            if groupDepth <= 0 {
                return -1
            }
            groupDepth -= 1
        } else if kind == 131 {
            bracketDepth += 1
        } else if kind == 132 {
            if bracketDepth <= 0 {
                return -1
            }
            bracketDepth -= 1
        }
        pos += 1
    }
    return -1
}

func ParseLambdaOrAssignmentExpressionNode(tokens: ParserTokenTable, count: int, st: ParserState, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, depth: int): int {
    if depth > 200 {
        return -1
    }

    // `on target.Event (…) => …` is a keyword-led form of its own and is answered before anything
    // else at this level.
    if ParserTokenIsOnKeyword(tokens, count, st, st.Pos) {
        return ParseOnSubscriptionNode(tokens, count, st, argStack, nodes, children, depth)
    }

    // `async` (68) BEFORE a lambda makes it an ASYNC lambda — the same three parameter shapes, a
    // different node kind (78), and a body whose value the delegate's task-like return wraps. The
    // keyword is consumed here and the lambda scan below runs from the token after it, so an `async`
    // that is NOT followed by a lambda falls through to the assignment level unchanged.
    lambdaStart := st.Pos
    isAsync := false
    if st.Pos < count && tokens.Kinds[st.Pos] == 68 {
        isAsync = true
        st.Pos = st.Pos + 1
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
                    if scan < count && tokens.Kinds[scan] == 122 {
                        scan = ScanTypedLambdaParameterEnd(tokens, count, scan + 1)
                        if scan < 0 {
                            valid = false
                            scanning = false
                        }
                    }
                    if !valid {
                        continue
                    }
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
        st.Pos = lambdaStart
        return ParseAssignmentExpressionNode(tokens, count, st, argStack, nodes, children, depth)
    }

    spanStart := tokens.Starts[lambdaStart]
    argBase := st.ArgStackTop
    if tokens.Kinds[st.Pos] == 0 {
        paramNode := EmitExpressionNode(st, nodes, 6, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos], -1, 0, tokens.Starts[st.Pos], tokens.ValueLengths[st.Pos])
        argStack.Values[st.ArgStackTop] = paramNode
        st.ArgStackTop = st.ArgStackTop + 1
        st.Pos = st.Pos + 1
    } else {
        st.Pos = st.Pos + 1
        while st.Pos < count && tokens.Kinds[st.Pos] != 128 {
            parameterIndex := st.Pos
            parameterSpanEnd := tokens.Starts[parameterIndex] + tokens.ValueLengths[parameterIndex]
            st.Pos = st.Pos + 1
            if st.Pos < count && tokens.Kinds[st.Pos] == 122 {
                st.Pos = ScanTypedLambdaParameterEnd(tokens, count, st.Pos + 1)
                if st.Pos < 0 {
                    st.ArgStackTop = argBase
                    return -1
                }
                lastTypeToken := st.Pos - 1
                parameterSpanEnd = tokens.Starts[lastTypeToken] + tokens.ValueLengths[lastTypeToken]
            }
            // ValueSpan remains the parameter's identifier. Span includes a written annotation so
            // the emitter can resolve an untargeted typed lambda without inventing a parallel AST.
            paramNode := EmitExpressionNode(st, nodes, 6, tokens.Starts[parameterIndex], tokens.ValueLengths[parameterIndex], -1, 0, tokens.Starts[parameterIndex], parameterSpanEnd - tokens.Starts[parameterIndex])
            argStack.Values[st.ArgStackTop] = paramNode
            st.ArgStackTop = st.ArgStackTop + 1
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
        // An expression body may BE a throw (`x => throw new ArgumentException(...)`, kind 83): the
        // delegate's declared return type is what the body would otherwise have produced, so nothing
        // else has to supply one.
        body = ParseBodyValueOrThrowExpressionNode(tokens, count, st, argStack, nodes, children, depth + 1)
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
    lambdaKind := 39
    if isAsync {
        lambdaKind = 78
    }

    return EmitExpressionNode(st, nodes, lambdaKind, arrowStart, arrowLength, childRunStart, childCount, spanStart, bodySpanEnd - spanStart)
}
