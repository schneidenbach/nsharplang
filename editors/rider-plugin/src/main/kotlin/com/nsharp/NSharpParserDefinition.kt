package com.nsharp

import com.intellij.lang.ASTNode
import com.intellij.lang.ParserDefinition
import com.intellij.lang.PsiParser
import com.intellij.lexer.Lexer
import com.intellij.openapi.project.Project
import com.intellij.psi.FileViewProvider
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import com.intellij.psi.tree.IFileElementType
import com.intellij.psi.tree.TokenSet
import com.nsharp.lexer.NSharpLexer
import com.nsharp.parser.NSharpParser
import com.nsharp.psi.NSharpFile
import com.nsharp.psi.NSharpTokenTypes

class NSharpParserDefinition : ParserDefinition {
    override fun createLexer(project: Project?): Lexer = NSharpLexer()
    override fun createParser(project: Project?): PsiParser = NSharpParser()
    override fun getFileNodeType(): IFileElementType = FILE
    override fun getCommentTokens(): TokenSet = COMMENTS
    override fun getStringLiteralElements(): TokenSet = STRINGS
    override fun createElement(node: ASTNode): PsiElement = NSharpTokenTypes.Factory.createElement(node)
    override fun createFile(viewProvider: FileViewProvider): PsiFile = NSharpFile(viewProvider)
    
    companion object {
        val FILE = IFileElementType(NSharpLanguage)
        val COMMENTS = TokenSet.create(NSharpTokenTypes.COMMENT, NSharpTokenTypes.BLOCK_COMMENT)
        val STRINGS = TokenSet.create(NSharpTokenTypes.STRING)
    }
}
