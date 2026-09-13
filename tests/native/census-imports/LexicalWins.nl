namespace Census.Imports.Left.Nested


// A DECLARATION IN THE FILE'S OWN NAMESPACE WINS OUTRIGHT OVER ANY IMPORT, so a file that declares
// `Marker` here means THIS one whatever it imports. The companion test executes that choice.
class Marker {
    func Side(): string {
        return "nested"
    }
}
