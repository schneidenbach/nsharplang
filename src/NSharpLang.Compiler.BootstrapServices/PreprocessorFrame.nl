namespace NSharpLang.Compiler

public struct Frame {
    public ParentActive: bool
    public BranchTaken: bool
    public CurrentActive: bool
    public SeenElse: bool
}
