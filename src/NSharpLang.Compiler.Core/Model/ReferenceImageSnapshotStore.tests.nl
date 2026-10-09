namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import YamlDotNet.Serialization

test "metadata loading uses the captured image when a reference path is rewritten before reflection" {
    sourcePath := typeof(object).Assembly.Location
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-image-race-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    copiedPath := Path.Combine(directory, Path.GetFileName(sourcePath))
    File.Copy(sourcePath, copiedPath)

    gate := new object()
    images := new ReferenceImageSnapshotStore(gate)
    resolverPaths := new List<string>()
    resolverPaths.Add(Path.Combine(RuntimeEnvironment.GetRuntimeDirectory(), "System.Runtime.dll"))
    resolverPaths.Add(copiedPath)
    resolver := new ReferenceImagePathResolver(resolverPaths.ToArray(), images, gate)
    context := new MetadataLoadContext(resolver, "System.Runtime")

    try {
        images.Capture(copiedPath)

        // Place the writer exactly after the compiler's copy and before the metadata reader asks for
        // a type row. Loading from the path here would see an invalid image; loading the captured
        // bytes must still produce the original nested type and its declaring type.
        File.WriteAllBytes(copiedPath, new byte[](0))
        fileBackedContext := new MetadataLoadContext(new PathAssemblyResolver(resolverPaths), "System.Runtime")
        try {
            pathLoadFailed := false
            try {
                fileBackedContext.LoadFromAssemblyPath(copiedPath)
            } catch {
                pathLoadFailed = true
            }
            assert pathLoadFailed, "file-backed metadata load unexpectedly survived truncating its image"
        } finally {
            fileBackedContext.Dispose()
        }

        loaded := images.LoadFromPath(context, copiedPath)
        nested := loaded.GetType("System.Collections.Generic.Dictionary`2+Entry")

        assert nested != null
        assert nested.DeclaringType != null
        assert nested.DeclaringType.FullName == "System.Collections.Generic.Dictionary`2"
        assert ReferenceImageSnapshotStore.OriginalPathOf(loaded) == Path.GetFullPath(copiedPath)
    } finally {
        context.Dispose()
        Directory.Delete(directory, true)
    }
}

test "snapshot path resolver preserves the referenced assembly identity and members" {
    yamlPath := typeof(DeserializerBuilder).Assembly.Location
    runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
    paths := new List<string>()
    for path in Directory.GetFiles(runtimeDirectory, "*.dll") {
        paths.Add(path)
    }
    paths.Add(yamlPath)

    fileIdentity := AssemblyName.GetAssemblyName(yamlPath)
    imageIdentity := ReferenceImageSnapshotStore.AssemblyNameFromImage(File.ReadAllBytes(yamlPath))
    assert imageIdentity.FullName == fileIdentity.FullName, imageIdentity.FullName + " != " + fileIdentity.FullName

    images := new ReferenceImageSnapshotStore()
    snapshotContext := ReferenceImageMetadataContext.Create(paths.ToArray(), images, new object())
    pathContext := new MetadataLoadContext(new PathAssemblyResolver(paths), "System.Runtime")
    try {
        snapshotAssembly := images.LoadFromPath(snapshotContext, yamlPath)
        pathAssembly := pathContext.LoadFromAssemblyPath(yamlPath)
        snapshotType := snapshotAssembly.GetType("YamlDotNet.Serialization.DeserializerBuilder")
        pathType := pathAssembly.GetType("YamlDotNet.Serialization.DeserializerBuilder")
        assert snapshotType != null, "snapshot resolver could not load YamlDotNet.Serialization.DeserializerBuilder"
        assert pathType != null, "path resolver could not load YamlDotNet.Serialization.DeserializerBuilder"
        assert snapshotType.GetMethod("Build") != null, "snapshot resolver loaded the wrong DeserializerBuilder surface"
        assert pathType.GetMethod("Build") != null, "path resolver loaded the wrong DeserializerBuilder surface"
    } finally {
        snapshotContext.Dispose()
        pathContext.Dispose()
    }
}

test "snapshot resolver keeps compiler model types visible through a reference image" {
    testOutputDirectory := Path.GetDirectoryName(typeof(AnalyzerMetadataLoadPolicy).Assembly.Location) ?? ""
    modelOutputDirectory := Path.GetFullPath(Path.Combine(testOutputDirectory, "../../../../../NSharpLang.Compiler.Model/bin/Debug/net10.0"))
    syntaxOutputDirectory := Path.GetFullPath(Path.Combine(testOutputDirectory, "../../../../../NSharpLang.Compiler.Syntax/bin/Debug/net10.0"))
    modelPath := Path.Combine(modelOutputDirectory, "NSharpLang.Compiler.Model.dll")
    syntaxPath := Path.Combine(syntaxOutputDirectory, "NSharpLang.Compiler.Syntax.dll")
    modelFileIdentity := AssemblyName.GetAssemblyName(modelPath)
    modelImageIdentity := ReferenceImageSnapshotStore.AssemblyNameFromImage(File.ReadAllBytes(modelPath))
    assert modelImageIdentity.FullName == modelFileIdentity.FullName, modelImageIdentity.FullName + " != " + modelFileIdentity.FullName
    paths := new List<string>()
    for path in Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll") {
        paths.Add(path)
    }
    for path in Directory.GetFiles(modelOutputDirectory, "*.dll") {
        paths.Add(path)
    }
    for path in Directory.GetFiles(syntaxOutputDirectory, "*.dll") {
        paths.Add(path)
    }

    images := new ReferenceImageSnapshotStore()
    context := ReferenceImageMetadataContext.Create(paths.ToArray(), images, new object())
    try {
        model := images.LoadFromPath(context, modelPath)
        expression := model.GetType("NSharpLang.Compiler.Ast.Expression")
        assert expression != null, "snapshot resolver did not expose the referenced compiler Expression type"

        syntax := images.LoadFromPath(context, syntaxPath)
        resultType := syntax.GetType("NSharpLang.Compiler.Columnar.ExprResult")
        assert resultType != null, "snapshot resolver did not expose the dependent syntax ExprResult type"
        node := resultType.GetField("Node")
        assert node != null, "snapshot resolver did not expose ExprResult.Node"
        assert node.FieldType.FullName == "NSharpLang.Compiler.Ast.Expression", node.FieldType.FullName

        analyzerDirectories := new List<string>()
        analyzerDirectories.Add(RuntimeEnvironment.GetRuntimeDirectory())
        analyzerDirectories.Add(modelOutputDirectory)
        analyzerDirectories.Add(syntaxOutputDirectory)
        analyzerImages := new ReferenceImageSnapshotStore()
        analyzerGate := new object()
        analyzerResolver := new AnalyzerMetadataAssemblyResolver(
            analyzerDirectories,
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase),
            new Dictionary<string, string>(StringComparer.Ordinal),
            analyzerGate,
            analyzerImages
        )
        analyzerContext := new MetadataLoadContext(analyzerResolver, "System.Runtime")
        try {
            analyzerSyntax := analyzerImages.LoadFromPath(analyzerContext, syntaxPath)
            analyzerResult := analyzerSyntax.GetType("NSharpLang.Compiler.Columnar.ExprResult")
            assert analyzerResult != null, "analyzer resolver did not expose the dependent syntax ExprResult type"
            analyzerNode := analyzerResult.GetField("Node")
            assert analyzerNode != null, "analyzer resolver did not expose ExprResult.Node"
            assert analyzerNode.FieldType.FullName == "NSharpLang.Compiler.Ast.Expression", analyzerNode.FieldType.FullName
        } finally {
            analyzerContext.Dispose()
        }
    } finally {
        context.Dispose()
    }
}
