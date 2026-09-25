namespace Census.SafeCasts.Tests

// `x as T` IS `T?` — AND A NARROWED ONE IS `T` AGAIN.
//
// Every function below dereferences or passes on the result of an `as` only after proving it present,
// so this file COMPILING is half of each contract (before the rule, nothing here needed a check, and
// the unchecked twins in `SafeCasts.tests.nl` compiled in silence). The runtime half is that the cast
// still answers null when the value is not a `T`, which is why the proofs matter.
class Animal {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

class Dog: Animal {
    constructor(name: string): base(name) {
    }

    func Bark(): string => Name + " barks"
}

func Speak(dog: Dog): string => dog.Bark()

func BarkIfDog(animal: Animal): string {
    dog := animal as Dog
    if dog != null {
        return dog.Bark() + "/" + Speak(dog)
    }
    return "not a dog"
}

func BarkOrReturn(animal: Animal): string {
    dog := animal as Dog
    if dog == null {
        return "not a dog"
    }
    return Speak(dog)
}

func BarkThroughPattern(value: object): string {
    if value is Dog dog {
        return dog.Bark()
    }
    return "not a dog"
}

func BarkOrFallback(animal: Animal): string {
    dog := animal as Dog ?? new Dog("stand-in")
    return dog.Bark()
}

func NameIfDog(animal: Animal): string? {
    return (animal as Dog)?.Name
}

// An upcast cannot fail, so the reference it hands back is as present as the one it was given.
func UpcastName(dog: Dog): string {
    animal := dog as Animal
    return animal.Name
}

func TextHash(text: string): int {
    boxed := text as object
    return boxed.GetHashCode()
}
