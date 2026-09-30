namespace Census.FreeFunctions.Yielding

// A namespace that declares its own type named `Program`, so its free functions sit on the reserved
// holder `<Program>` instead -- and a referenced `Program` here is the user's type, not the holder.
class Program {
    Name: string
}

func Yielded(): string => "yielded"
