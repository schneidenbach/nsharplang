namespace NSharpLang.Compiler

struct Frame {
    ParentActive: bool
    BranchTaken: bool
    CurrentActive: bool
    SeenElse: bool
}
