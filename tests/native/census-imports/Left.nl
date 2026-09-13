namespace Census.Imports.Left


// ONE HALF OF A DELIBERATE COLLISION. `Marker` and `Box<T>` are spelled here and in
// `Census.Imports.Right` so that a file importing both has to say which it means — the shape NL209
// reports and the shape these contracts execute.
class Marker {
    func Side(): string {
        return "left"
    }
}

class Box<T> {
    func Side(): string {
        return "left"
    }
}
