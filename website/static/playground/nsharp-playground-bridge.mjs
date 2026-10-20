function encodeFiles(files) {
  return JSON.stringify((files ?? []).map((file) => ({
    name: file.name ?? file.Name ?? 'Program.nl',
    code: file.code ?? file.Code ?? '',
  })));
}

export function createNSharpPlaygroundBridge(exported) {
  return {
    getCatalog: () => JSON.parse(exported.GetCatalog()),
    check: (source) => JSON.parse(exported.Check(source ?? '')),
    checkProject: (files, activeFile) =>
      JSON.parse(exported.CheckProject(encodeFiles(files), activeFile ?? 'Program.nl')),
    runProject: async (files, activeFile) =>
      JSON.parse(await exported.RunProject(encodeFiles(files), activeFile ?? 'Program.nl')),
    format: (source, fileName) =>
      JSON.parse(exported.Format(source ?? '', fileName ?? 'Program.nl')),
    complete: (files, fileName, line, column) =>
      JSON.parse(exported.Complete(encodeFiles(files), fileName ?? 'Program.nl', line ?? 1, column ?? 0)),
    hover: (files, fileName, line, column) =>
      JSON.parse(exported.Hover(encodeFiles(files), fileName ?? 'Program.nl', line ?? 1, column ?? 0)),
    version: () => JSON.parse(exported.Version()),
  };
}
