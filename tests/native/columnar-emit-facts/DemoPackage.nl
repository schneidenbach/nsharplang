package Demo


// The deleted `ColumnarCompiler_PackageHeader_AllowsPublicTopLevelFunction` compiled exactly this
// preamble-plus-function shape through the emit-only wrapper and invoked the result by reflection.
// Here the shape is a real file in a real project, so the whole product build — analyser included —
// has to admit `public` on a top-level function under a `package` header, and the contract beside it
// proves the function is callable from another file in the same project.
public func buildExplicit(): string {
    return "explicit"
}
