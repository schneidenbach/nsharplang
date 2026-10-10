namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Collections.Generic


// LAMBDAS AT A CONSTRUCTOR, AND A CALL WHOSE CALLEE IS A VALUE.
//
// Three shapes emitted everywhere except where they were written here:
//
//   * a THIS-capturing lambda stored in a field BY THE CONSTRUCTOR. The placement planner refused a
//     constructor body's `this` on the grounds that binding a delegate to it would capture a copy —
//     true of a VALUE type, whose `this` is a pointer into the constructor's own storage, and not of
//     a reference type, where `ldarg.0` is the object being constructed and every later method sees
//     the same reference. The identical assignment in a method emitted, so the refusal read as "this
//     line is fine over there".
//   * a LAMBDA LITERAL WRITTEN AT A SOURCE CONSTRUCTOR'S ARGUMENT. Constructor arguments were emitted
//     by a hand-written subset of the call path's rules, so the lambda reached the plain expression
//     door with no delegate to take a signature from and declined as an unsupported node kind.
//   * A CALL WHOSE CALLEE IS ITSELF A CALL. `Make(prefix)("y")` names no member and no binding, and
//     the delegate-invoke door read a delegate out of a NAME. The callee is an ordinary expression
//     whose value is the delegate.
class Greeter {
    Name: string
    Greet: Func<string>
    Shout: Func<string, string>

    constructor(name: string) {
        this.Name = name
        this.Greet = () => this.Name + "!"
        this.Shout = suffix => this.Name + suffix
    }

    func Rebind() {
        this.Greet = () => "re:" + this.Name
    }
}

// A constructor closure over the constructor's own PARAMETERS, which is the display-class path
// rather than the direct `ldarg.0; ldftn` one.
class StepCounter {
    Start: int
    Next: Func<int>

    constructor(start: int, step: int) {
        this.Start = start
        this.Next = () => start + step
    }
}

class Runner {
    Maker: Func<string>

    constructor(maker: Func<string>) {
        this.Maker = maker
    }

    func Run(): string {
        return this.Maker()
    }
}

func GreetingOf(name: string): string {
    greeter := new Greeter(name)
    return greeter.Greet()
}

func ShoutOf(name: string, suffix: string): string {
    greeter := new Greeter(name)
    return greeter.Shout(suffix)
}

func Rebound(name: string): string {
    greeter := new Greeter(name)
    greeter.Rebind()
    return greeter.Greet()
}

func NextOf(start: int, step: int): int {
    counter := new StepCounter(start, step)
    return counter.Next()
}

// A lambda literal written DIRECTLY at a source constructor's argument, and one that captures.
func RunnerSaying(word: string): string {
    runner := new Runner(() => "said:" + word)
    return runner.Run()
}

func ConstantRunner(): string {
    runner := new Runner(() => "constant")
    return runner.Run()
}

// ── a call whose callee is a value ────────────────────────────────────────────────────────────
func Make(prefix: string): Func<string, string> {
    return s => prefix + s
}

func InvokedDirectly(): string {
    return Make("a-")("y")
}

func InvokedFromAList(): string {
    makers := new List<Func<string, string>>()
    makers.Add(Make("first-"))
    makers.Add(Make("second-"))
    return makers[1]("y")
}
