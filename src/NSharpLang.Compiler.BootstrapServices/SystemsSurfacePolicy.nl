namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT A DECLARED SURFACE MAY EXPOSE.
//
// Two rules ask the same question of two different declarations. A function that promises `[hot]` or
// `[boundary]` is asked what its parameters and its return type make visible to the managed world; a
// struct or record that is NOT a `ref struct` is asked whether any of its fields borrows a stack
// frame it cannot outlive. Both answer about a SIGNATURE — about what the declaration says, not about
// anything its body does — and both report under the codes the other one uses, which is why they are
// one owner and not two.
//
// THE PREFIX IS A CONDITIONAL AND IT IS THIS OWNER'S, NOT THE SINK'S. `[hot]` and `[boundary]` open
// the two NSYS070 sentences because the same hostile type is a broken promise in one and a reviewable
// handoff in the other, and the reader has to be told which. It looks like the sink's policy LABEL and
// it is not: the label has a third arm — `systems:{mode}` or `local` — for a function that is neither,
// while this prefix is only ever reached when one of the two holds, because the rule returns first
// otherwise.
//
// THE PREFERRED SEVERITY IS THIS OWNER'S TOO, AND IT IS NOT ONE CHOICE BUT THREE. The hostile-surface
// arms prefer `Error` in `[hot]` and `Warning` at a `[boundary]`; the Result-ABI arm prefers a FLAT
// `Warning` even in `[hot]`, because an oversized `Result` is guidance rather than a broken promise;
// and the ref-like-return arm prefers a FLAT `Error`, because it is only reachable in `[hot]` at all.
// Three preferences in one member is why the choice cannot be folded into the sink: the sink is told
// what a rule PREFERS and then applies the boundary and audit downgrades on top of it.
//
// THE REPORTED NAME AND THE REPORTED LENGTH COME FROM DIFFERENT PLACES, AND THAT IS DELIBERATE. A
// finding names the function by its QUALIFIED name — `Type.Method` — so a reader can find it across a
// file, but it underlines the DECLARED name, because that is the text actually present at the
// reported position. Passing the declaration and the qualified name separately is what keeps the two
// from being confused for each other.
//
// A FIELD FINDING IS A TYPE FINDING. The ref-like field rule reports through the sink's type door,
// which has no preferred severity and no hotness to label — a type is not hot — so its severity is
// the project's alone. That asymmetry belongs to the sink and is stated there; this owner simply has
// nothing to hand it.
class SystemsSurfacePolicy {
    typePolicyValue: SystemsTypePolicy
    sinkValue: SystemsFindingSink

    constructor(typePolicy: SystemsTypePolicy, sink: SystemsFindingSink) {
        typePolicyValue = typePolicy
        sinkValue = sink
    }

    // WHAT A `[hot]` OR `[boundary]` SIGNATURE MAY EXPOSE. A function that promises neither is not
    // asked at all — this is the only gate, and it is why every arm below may assume the prefix and
    // the severity are meaningful.
    //
    // `function` is the declaration, `functionName` its QUALIFIED name; see the header for why both.
    func CheckFunctionSurface(function: FunctionDeclaration, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if !isHot && !isBoundary {
            return
        }

        nameLength := Math.Max(1, function.Name.Length)

        // EVERY PARAMETER IS ASKED, AND EACH ONE REPORTS AT ITS OWN POSITION AND UNDER ITS OWN NAME'S
        // WIDTH — so a signature with three hostile parameters produces three findings, not one about
        // the function.
        parameters := function.Parameters
        index := 0
        while index < parameters.Count {
            parameter := parameters[index]
            reason := typePolicyValue.HostileSurfaceReason(parameter.Type, isHot, function.Constraints)
            if reason != null {
                sinkValue.AddForFunction("NSYS070", "boundaryLeak", SurfacePrefix(isHot) + " parameter '" + parameter.Name + "' exposes a systems-hostile type: " + reason, parameter.Line, parameter.Column, Math.Max(1, parameter.Name.Length), filePath, functionName, isHot, isBoundary, SurfaceSeverity(isHot), "Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.")
            }

            index = index + 1
        }

        returnType := function.ReturnType
        if returnType != null {
            returnReason := typePolicyValue.HostileSurfaceReason(returnType, isHot, function.Constraints)
            if returnReason != null {
                sinkValue.AddForFunction("NSYS070", "boundaryLeak", SurfacePrefix(isHot) + " return type exposes a systems-hostile shape: " + returnReason, function.Line, function.Column, nameLength, filePath, functionName, isHot, isBoundary, SurfaceSeverity(isHot), "Return Result<T,E>, Span/ReadOnlySpan with a known lifetime, a primitive, enum, or systems-safe struct.")
            }
        }

        // ASKED OF THE NULLABLE RETURN TYPE DIRECTLY, not inside the arm above: a function with no
        // written return type has no `Result` to size, and the rule says so itself rather than being
        // guarded from outside.
        resultAbiReason := typePolicyValue.ResultAbiReason(function.ReturnType)
        if resultAbiReason != null {
            sinkValue.AddForFunction("NSYS170", "resultAbi", resultAbiReason, function.Line, function.Column, nameLength, filePath, functionName, isHot, isBoundary, ErrorSeverity.Warning, "Return a smaller error/value payload or pass large data through caller-owned storage.")
        }

        // A BORROWED VIEW MAY LEAVE A `[hot]` FUNCTION ONLY WITH A WRITTEN LIFETIME. `[boundary]` is
        // not asked: this arm tests `isHot` again rather than relying on the gate, because the gate
        // admits both.
        if !isHot || returnType == null {
            return
        }

        if typePolicyValue.ContainsRefLikeType(returnType) && string.IsNullOrWhiteSpace(function.ReturnLifetime) {
            sinkValue.AddForFunction("NSYS080", "lifetime", "[hot] function returns a ref-like value with an unknown lifetime", function.Line, function.Column, nameLength, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Use `returns 'a`, `returns heap(owner)`, or return an owned value instead of a ref-like view.")
        }
    }

    // A REF-LIKE FIELD IS ONLY LEGAL INSIDE A `ref struct`. A `ref struct` is therefore not asked at
    // all, and a record is asked as though it were a struct that is not one — a record cannot be
    // declared `ref`, so the caller has nothing to pass but `false`.
    //
    // ASKED OF EVERY MEMBER, NOT ONLY THE FIELDS THAT PARSED WITH A TYPE: a field whose type is
    // missing is skipped rather than guessed at, because a systems rule that fires on unparsed source
    // reports about the parser and not about the program.
    func CheckRefLikeFields(filePath: string, typeName: string, isRefStruct: bool, members: List<Declaration>) {
        if isRefStruct {
            return
        }

        for member in members {
            field := member as FieldDeclaration
            if field == null {
                continue
            }

            fieldType := field.Type
            if fieldType == null || !typePolicyValue.IsRefLikeType(fieldType) {
                continue
            }

            sinkValue.AddForType("NSYS080", "lifetime", "ref-like field '" + field.Name + "' is only allowed inside a ref struct", filePath, field.Line, field.Column, Math.Max(1, field.Name.Length), typeName, "Declare the containing type as `ref struct`, or store a heap-safe owner such as Memory<T>/ReadOnlyMemory<T>.")
        }
    }

    // `[hot]` OUTRANKS `[boundary]` IN THE SENTENCE, as it does in the sink's label: a function
    // carrying both is told about the stricter promise it broke.
    static func SurfacePrefix(isHot: bool): string {
        if isHot {
            return "[hot]"
        }

        return "[boundary]"
    }

    // A HOT SIGNATURE IS WRONG; A BOUNDARY SIGNATURE IS FOR REVIEW. This is the rule's PREFERENCE —
    // the sink may still downgrade it, and in audit mode it always does.
    static func SurfaceSeverity(isHot: bool): ErrorSeverity {
        if isHot {
            return ErrorSeverity.Error
        }

        return ErrorSeverity.Warning
    }
}
