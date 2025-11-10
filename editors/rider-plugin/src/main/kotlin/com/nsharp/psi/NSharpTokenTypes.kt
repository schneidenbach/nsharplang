package com.nsharp.psi

import com.intellij.lang.ASTNode
import com.intellij.psi.PsiElement
import com.intellij.psi.tree.IElementType
import com.nsharp.NSharpLanguage

class NSharpElementType(debugName: String) : IElementType(debugName, NSharpLanguage)

object NSharpTokenTypes {
    @JvmField val FUNC = NSharpElementType("FUNC")
    @JvmField val TYPE = NSharpElementType("TYPE")
    @JvmField val UNION = NSharpElementType("UNION")
    @JvmField val MATCH = NSharpElementType("MATCH")
    @JvmField val IF = NSharpElementType("IF")
    @JvmField val ELSE = NSharpElementType("ELSE")
    @JvmField val FOR = NSharpElementType("FOR")
    @JvmField val IN = NSharpElementType("IN")
    @JvmField val RETURN = NSharpElementType("RETURN")
    @JvmField val VAR = NSharpElementType("VAR")
    @JvmField val CONST = NSharpElementType("CONST")
    @JvmField val IMPORT = NSharpElementType("IMPORT")
    @JvmField val CLASS = NSharpElementType("CLASS")
    @JvmField val INTERFACE = NSharpElementType("INTERFACE")
    @JvmField val STRUCT = NSharpElementType("STRUCT")
    @JvmField val RECORD = NSharpElementType("RECORD")
    @JvmField val ASYNC = NSharpElementType("ASYNC")
    @JvmField val AWAIT = NSharpElementType("AWAIT")
    @JvmField val NEW = NSharpElementType("NEW")
    @JvmField val THIS = NSharpElementType("THIS")
    @JvmField val BASE = NSharpElementType("BASE")
    @JvmField val TRUE = NSharpElementType("TRUE")
    @JvmField val FALSE = NSharpElementType("FALSE")
    @JvmField val NULL = NSharpElementType("NULL")
    @JvmField val WHEN = NSharpElementType("WHEN")
    @JvmField val IS = NSharpElementType("IS")
    
    @JvmField val COLON_EQUALS = NSharpElementType(":=")
    @JvmField val ARROW = NSharpElementType("=>")
    @JvmField val DOT = NSharpElementType(".")
    @JvmField val COMMA = NSharpElementType(",")
    @JvmField val COLON = NSharpElementType(":")
    @JvmField val SEMICOLON = NSharpElementType(";")
    @JvmField val LPAREN = NSharpElementType("(")
    @JvmField val RPAREN = NSharpElementType(")")
    @JvmField val LBRACE = NSharpElementType("{")
    @JvmField val RBRACE = NSharpElementType("}")
    @JvmField val LBRACKET = NSharpElementType("[")
    @JvmField val RBRACKET = NSharpElementType("]")
    @JvmField val EQ = NSharpElementType("=")
    @JvmField val PLUS = NSharpElementType("+")
    @JvmField val MINUS = NSharpElementType("-")
    @JvmField val STAR = NSharpElementType("*")
    @JvmField val SLASH = NSharpElementType("/")
    @JvmField val PIPE = NSharpElementType("|")
    
    @JvmField val IDENTIFIER = NSharpElementType("IDENTIFIER")
    @JvmField val NUMBER = NSharpElementType("NUMBER")
    @JvmField val STRING = NSharpElementType("STRING")
    @JvmField val COMMENT = NSharpElementType("COMMENT")
    @JvmField val BLOCK_COMMENT = NSharpElementType("BLOCK_COMMENT")
    @JvmField val WHITESPACE = NSharpElementType("WHITESPACE")
    @JvmField val NEWLINE = NSharpElementType("NEWLINE")
    
    object Factory {
        fun createElement(node: ASTNode): PsiElement {
            return NSharpPsiElement(node)
        }
    }
}

class NSharpPsiElement(node: ASTNode) : com.intellij.extapi.psi.ASTWrapperPsiElement(node)
