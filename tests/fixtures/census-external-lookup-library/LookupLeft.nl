namespace Census.Lookup.Left


// One of two namespaces that declare `Widget`. A consumer importing both has a tie (NL209); one that
// names either relative to the enclosing namespace (`Left.Widget`) has none.
class Widget {
    func Who(): string {
        return "left"
    }
}
