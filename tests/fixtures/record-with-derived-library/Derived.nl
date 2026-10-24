namespace NSharpLang.RecordWith.Library

// This record is compiled in its own project and derives from the N# record in
// record-with-library. It exercises the referenced-record base metadata contract.
record DetailedStatus: Status {
    Revision: int
}
