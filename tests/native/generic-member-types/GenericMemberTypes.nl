namespace NSharpLang.GenericMemberTypes.Tests

import System.Collections.Generic


// AN EXTERNAL GENERIC CLOSED OVER THE DECLARING TYPE'S OWN TYPE PARAMETER.
//
// `List<T>` and `Dictionary<string, T>` already resolved as member types. Two shapes did not, and
// neither had anything to do with the family involved:
//
//   * A NULLABLE ANNOTATION. `List<T>?` declined where `List<T>` resolved, because the walk that
//     knows about type parameters had no `?` branch at all — the annotation was simply part of the
//     name. Every reference type in this language may be written `T?`, so the annotation must be
//     read wherever the type is.
//   * THE DELEGATE FAMILIES. `Action<T>` and `Func<T, TResult>` were handed to the walk that does
//     NOT know about type parameters, so `T` was an unknown name. They are ordinary constructed
//     external generics and now resolve on the same walk as everything else.
//
// Everything here is a member of a GENERIC type whose own parameter appears inside an external
// generic. The fields are read and written and the delegates are called, so a type that merely
// resolved without being storable or loadable would not survive these tests.
class Holder<T> {
    items: List<T>
    lookup: Dictionary<string, T>
    optionalItems: List<T>?
    onEach: Action<T>?
    readonly pick: Func<T, bool>

    constructor(items: List<T>, lookup: Dictionary<string, T>, pick: Func<T, bool>) {
        this.items = items
        this.lookup = lookup
        this.optionalItems = null
        this.onEach = null
        this.pick = pick
    }

    Items: List<T> => items
    Lookup: Dictionary<string, T> => lookup
    OptionalItems: List<T>? => optionalItems
    OnEach: Action<T>? => onEach
    Pick: Func<T, bool> => pick

    func Add(item: T) {
        items.Add(item)
    }

    func Adopt(more: List<T>?) {
        optionalItems = more
    }

    func Listen(listener: Action<T>?) {
        onEach = listener
    }

    // Calling a delegate closed over the declaring type's own parameter. The `Invoke` handle cannot
    // be asked for by name on a builder-bound instantiation, so it is rebound from the open
    // definition — and the signature is read from the instantiation's own generic arguments.
    func Announce(item: T): bool {
        current := onEach
        if current != null {
            current(item)
        }
        chooser := pick
        return chooser(item)
    }

    func Selected(): List<T> {
        chooser := pick
        chosen := new List<T>()
        for item in items {
            if chooser(item) {
                chosen.Add(item)
            }
        }
        return chosen
    }
}

// The same shapes as a PARAMETER, a LOCAL and a RETURN type of a generic free function, not just as
// fields, so the admissibility rule is proved where the type is spelled and not only where it is
// stored.
func FirstMatch<T>(items: List<T>, pick: Func<T, bool>, fallback: T): T {
    chooser: Func<T, bool> = pick
    for item in items {
        if chooser(item) {
            return item
        }
    }
    return fallback
}

func Sink<T>(items: List<T>, listener: Action<T>) {
    for item in items {
        listener(item)
    }
}

// CALLING A DELEGATE, IN EVERY SPELLING AND FROM EVERY STORAGE.
//
// `d.Invoke(x)` and `d(x)` are the same call — `Invoke` is an ordinary instance method of the
// delegate's own type — and neither one cared which storage the delegate came out of. Both facts had
// holes:
//
//   * `.Invoke` ON A DELEGATE OVER A TYPE PARAMETER declined. `Action<T>` inside `Holder<T>` is a
//     `TypeBuilderInstantiation`; the runtime call resolver already rebinds `Invoke` from the open
//     definition for one of those, but then refused the SUBSTITUTED signature because `T` is a
//     generic parameter — the very parameter the substitution had just put there.
//   * A BARE CALL ON A DELEGATE FIELD (`pick(item)` without copying to a local first) declined at
//     `emit.call.bare-unresolved`: the bare-call arm only looked at locals, parameters and lifted
//     captures.
//
// A method of the same name still beats a delegate field of that name, which `Shadowed` pins.
class Caller<T> {
    readonly pick: Func<T, bool>
    readonly onEach: Action<T>
    readonly plain: Action
    readonly counted: Action<int>

    constructor(pick: Func<T, bool>, onEach: Action<T>, plain: Action, counted: Action<int>) {
        this.pick = pick
        this.onEach = onEach
        this.plain = plain
        this.counted = counted
    }

    // `.Invoke` written out, on a field whose type closes an external delegate over `T`.
    func PickByInvokeOnField(item: T): bool {
        return pick.Invoke(item)
    }

    // The same call through a local, which is where the delegate had to be copied before.
    func PickByInvokeOnLocal(item: T): bool {
        current := pick
        return current.Invoke(item)
    }

    // The bare spelling, straight off the field.
    func PickByFieldCall(item: T): bool {
        return pick(item)
    }

    // The bare spelling with the receiver written.
    func PickByThisFieldCall(item: T): bool {
        return this.pick(item)
    }

    func AnnounceByInvoke(item: T) {
        onEach.Invoke(item)
    }

    func AnnounceByFieldCall(item: T) {
        onEach(item)
    }

    // A non-generic delegate field, at arity zero and at arity one.
    func FirePlain() {
        plain()
    }

    func FireCounted(value: int) {
        counted.Invoke(value)
    }
}

// A METHOD BEATS A FIELD OF THE SAME NAME. `Handle` is both a delegate field and a method here, and
// `Handle(1)` must be the method — the same order the language holds everywhere else.
class Shadowed {
    readonly Handler: Action<int>
    log: int

    constructor(handler: Action<int>) {
        Handler = handler
        log = 0
    }

    Log: int => log

    func Handle(value: int) {
        log = log + value
    }

    func RunMethod(value: int) {
        Handle(value)
    }

    func RunField(value: int) {
        Handler(value)
    }
}

// `receiver?.Member(args)` — THE NULL-CONDITIONAL CALL.
//
// The receiver is evaluated once, tested for null, and the call is skipped entirely when it is null.
// The result follows C#'s rule: a `void` member leaves nothing, a reference-typed one answers `null`,
// and a non-nullable value-typed one is lifted to `T?` because "skipped" has to be representable.
class Conditional<T> {
    onEach: Action<T>?
    pick: Func<T, bool>?
    counter: Counter?

    constructor(onEach: Action<T>?, pick: Func<T, bool>?, counter: Counter?) {
        this.onEach = onEach
        this.pick = pick
        this.counter = counter
    }

    // Void, straight off the field.
    func AnnounceIfListening(item: T) {
        onEach?.Invoke(item)
    }

    // Void, through a local — the shape a claim-once detach uses.
    func AnnounceThroughLocal(item: T) {
        current := onEach
        current?.Invoke(item)
    }

    // A value result, lifted to `bool?`.
    func PickIfPossible(item: T): bool? {
        return pick?.Invoke(item)
    }

    // An ordinary instance member on a source type, with a reference result.
    func LabelOrNull(): string? {
        return counter?.Describe()
    }

    // An ordinary instance member with a value result, lifted the same way.
    func CountOrNull(): int? {
        return counter?.Read()
    }
}

// A source type with an ordinary instance method, so the null-conditional call is proved on
// something other than a delegate.
class Counter {
    count: int

    constructor(count: int) {
        this.count = count
    }

    func Read(): int {
        return count
    }

    func Describe(): string {
        return "count"
    }
}
