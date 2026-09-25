// `in` PARAMETERS — read-only by reference.
//
// `in x: T` hands the callee the CALLER's storage instead of a copy, and promises the callee will not
// write to it. Reach for it when a parameter is a large `struct` and the copy costs more than the
// indirection; for a reference type or a machine word it buys nothing.
//
// The word is OPTIONAL at the call site, which is the whole difference from `ref`: `ref` warns the
// reader that their variable may change, and an `in` parameter cannot change it, so there is nothing
// to warn about.
import System


// Four doubles: big enough that copying it is real work, small enough to read in an example.
struct Matrix {
    A: double
    B: double
    C: double
    D: double

    func Show(): string {
        return "[" + A.ToString() + " " + B.ToString() + "; " + C.ToString() + " " + D.ToString() + "]"
    }
}

class Geometry {

    // The parameter is read, never written. `in` says so in the signature, and the compiler holds the
    // callee to it: assigning `m`, assigning `m.A`, or passing `m` on as a `ref` argument are all
    // NL309.
    static func Determinant(in m: Matrix): double {
        return m.A * m.D - m.B * m.C
    }

    static func Trace(in m: Matrix): double {
        return m.A + m.D
    }

    // Needing a changed value is not a reason to drop `in`: copy it. The copy is this function's own
    // and costs exactly what a by-value parameter would have cost — but only on the path that needs it.
    static func Scaled(in m: Matrix, factor: double): Matrix {
        return new Matrix { A: m.A * factor, B: m.B * factor, C: m.C * factor, D: m.D * factor }
    }
}

func main() {
    m := new Matrix { A: 1.0, B: 2.0, C: 3.0, D: 4.0 }

    Console.WriteLine("m           = " + m.Show())
    Console.WriteLine("determinant = " + Geometry.Determinant(m).ToString())

    // Identical call, with the word written. Say it when the reader benefits from seeing that a large
    // value is not being copied here.
    Console.WriteLine("trace       = " + Geometry.Trace(in m).ToString())

    doubled := Geometry.Scaled(m, 2.0)
    Console.WriteLine("scaled x2   = " + doubled.Show())
    Console.WriteLine("m unchanged = " + m.Show())
}
