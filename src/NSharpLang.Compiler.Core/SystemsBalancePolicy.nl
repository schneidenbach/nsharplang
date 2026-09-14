namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler


// WHAT A FUNCTION STILL OWES WHEN IT ENDS.
//
// Two obligations are opened inside a systems function and must be discharged before it returns: a
// buffer rented from a pool must be returned, and a disposable resource created in a local must be
// disposed. The walk records each one as it is opened and the call policy marks it discharged when it
// recognises the return or the dispose; this owner is asked, once, after the whole body has been
// walked, what is still outstanding.
//
// THE LEDGERS ARE HANDED OVER, NOT HELD. Both dictionaries are written by the statement walk and
// handed to the call policy mid-walk, so they belong to the function summary and travel here as
// arguments — the same shape `MarkResourceDisposedIfRecognized` already takes them in. What this owner
// contributes is not the bookkeeping but the VERDICT on it.
//
// "AN OBVIOUS LEXICAL PATH" IS THE PROMISE BOTH SENTENCES MAKE, and it is deliberately weaker than
// "is never returned". The discharge is recognised lexically, so a buffer handed to a helper that
// returns it is reported here; that is why both suggestions name the shapes the analyzer CAN see
// rather than telling the reader their code is wrong.
//
// WHO IS ASKED AT ALL IS THE SAME GATE FOR BOTH: a `[hot]` function, or any function in a systems
// project. A cold function in a default-profile project may leak a rented buffer without hearing
// about it, because pooling there is an ordinary optimisation and not a promise.
//
// THE TWO RULES DISAGREE ABOUT SEVERITY, AND THE DISAGREEMENT IS THE POINT. An unreturned pool buffer
// prefers `Error` in `[hot]` and `Warning` outside it — losing a rental costs throughput. An undisposed
// resource prefers `Error` EVERYWHERE, hot or not, because a leaked handle is a correctness bug at any
// temperature. The sink still applies the boundary and audit downgrades on top of both.
//
// BOTH LEDGERS ARE WALKED AS DICTIONARIES RATHER THAN THROUGH `.Values`, which is the same
// enumeration in the same order — the value collection is a view over this one — and is what the
// columnar backend emits.
class SystemsBalancePolicy {
    sinkValue: SystemsFindingSink

    constructor(sink: SystemsFindingSink) {
        sinkValue = sink
    }

    // OUTSTANDING RENTALS, IN THE ORDER THEY WERE OPENED. The ledger is keyed by variable name, so a
    // name rented twice in one function carries only its LAST rental — the second write replaces the
    // first — and the report is about the position that is still open.
    func CheckPoolBalance(poolRents: Dictionary<string, PoolRent>, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if !IsAsked(isHot) {
            return
        }

        for pair in poolRents {
            rent := pair.Value
            if rent.Returned {
                continue
            }

            sinkValue.AddForFunction("NSYS130", "pool", "pooled buffer '" + rent.VariableName + "' rented here is not returned on an obvious lexical path", rent.Line, rent.Column, Math.Max(1, rent.VariableName.Length), filePath, functionName, isHot, isBoundary, PoolSeverity(isHot), "Return the buffer in a finally block, use a recognized owner/disposable pattern, or keep pooling inside a [boundary].")
        }
    }

    // OUTSTANDING RESOURCES, AND THE SENTENCE NAMES THE KIND. The ledger records how the resource was
    // created — the `using` shape, the factory, the constructor — because "is not disposed" is only
    // actionable once the reader knows which line opened it.
    func CheckResourceBalance(resourceLocals: Dictionary<string, ResourceLocal>, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        if !IsAsked(isHot) {
            return
        }

        for pair in resourceLocals {
            resource := pair.Value
            if resource.Disposed {
                continue
            }

            sinkValue.AddForFunction("NSYS090", "resource", "disposable resource '" + resource.VariableName + "' created as " + resource.Kind + " is not disposed on an obvious lexical path", resource.Line, resource.Column, Math.Max(1, resource.VariableName.Length), filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.")
        }
    }

    // `[boundary]` DOES NOT OPEN THIS GATE BY ITSELF. A boundary in a default-profile project is not
    // asked about its obligations at all; in a systems project it is asked because every function
    // there is. The profile answer comes from the sink, which read it once at the start of the
    // analysis.
    func IsAsked(isHot: bool): bool {
        return isHot || sinkValue.IsSystemsProfile
    }

    // A LOST RENTAL IS A BROKEN PROMISE IN `[hot]` AND A COST EVERYWHERE ELSE.
    static func PoolSeverity(isHot: bool): ErrorSeverity {
        if isHot {
            return ErrorSeverity.Error
        }

        return ErrorSeverity.Warning
    }
}
