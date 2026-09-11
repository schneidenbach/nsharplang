namespace NSharpLang.Compiler.Columnar


// Owns the columnar node-text compatibility rule shared by compiler phases. A synthetic legacy
// equals node carries no source slice, so its single-character token is reconstructed here; every
// other node delegates to the original source-backed table read.
class ColumnarNodeTextFacts {
    static func Text(nodes: ColumnarNodeTable, source: string, node: int): string {
        if nodes.Kind(node) == 14 && nodes.ValueStart(node) < 0 && nodes.ValueLengths[node] == 1 {
            return "="
        }
        return nodes.Text(source, node)
    }
}
