namespace NSharpLang.CensusEmitShapes.Tests


// A `Nullable<T>` NEEDS A NON-NULLABLE VALUE `T`, AND A STRUCT THIS COMPILATION DECLARES IS ONE.
//
// The liftable element set was a list of complete external identities plus the two source families
// added when they were needed — an enum of this compilation, and a tuple. A plain source STRUCT was
// the third, and its absence is why `e: Extent? = null` declined at
// `emit.typed-local.unsupported-type` while the same annotation over an `int`, an enum or a tuple
// emitted. Nothing about the lowering differs: `Nullable<Extent>` is a `TypeBuilderInstantiation`
// exactly as `Nullable<SourceEnum>` already was, and every handle it needs is rebound through the
// one closed-generic member owner the enum case already goes through.
// `Extent` is the struct `SourceObjectMembers.nl` declares — one declaration per namespace, and
// this fixture is about lifting it rather than about declaring another one.
func LiftedArea(flag: bool): int {
    e: Extent? = null
    if flag {
        e = new Extent { Width: 2, Height: 3 }
    }
    if e == null {
        return 0
    }
    return e.Value.Width * e.Value.Height
}

func LiftedHasValue(flag: bool): bool {
    e: Extent? = null
    if flag {
        e = new Extent { Width: 4, Height: 5 }
    }
    return e.HasValue
}

// The same lift as a PARAMETER and as a RETURN type, so the local annotation is not a shape of its
// own but the spelling every position already shares.
func WidthOf(e: Extent?): int {
    if e.HasValue {
        return e.Value.Width
    }
    return -1
}

func Square(width: int): Extent? {
    if width <= 0 {
        return null
    }
    return new Extent { Width: width, Height: width }
}

func RoundTripHeight(width: int): int {
    made := Square(width)
    if made == null {
        return 0
    }
    return made.Value.Height
}
