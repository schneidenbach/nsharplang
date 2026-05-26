let playgroundPromise;

function encodeFiles(files) {
  return JSON.stringify((files ?? []).map((file) => ({
    name: file.name ?? file.Name ?? 'Program.nl',
    code: file.code ?? file.Code ?? '',
  })));
}

export async function loadNSharpPlayground() {
  if (!playgroundPromise) {
    playgroundPromise = (async () => {
      await import(new URL('wasm/main.js', import.meta.url).href);
      const exported = globalThis.NSharpPlaygroundWasm;
      if (!exported) {
        throw new Error('N# playground WASM exports were not initialized.');
      }

      return {
        getCatalog: () => JSON.parse(exported.GetCatalog()),
        check: (source) => JSON.parse(exported.Check(source ?? '')),
        checkProject: (files, activeFile) => JSON.parse(exported.CheckProject(encodeFiles(files), activeFile ?? 'Program.nl')),
        runProject: (files, activeFile) => JSON.parse(exported.RunProject(encodeFiles(files), activeFile ?? 'Program.nl')),
        format: (source, fileName) => JSON.parse(exported.Format(source ?? '', fileName ?? 'Program.nl')),
        complete: (files, fileName, line, column) =>
          JSON.parse(exported.Complete(encodeFiles(files), fileName ?? 'Program.nl', line ?? 1, column ?? 0)),
        hover: (files, fileName, line, column) =>
          JSON.parse(exported.Hover(encodeFiles(files), fileName ?? 'Program.nl', line ?? 1, column ?? 0)),
        version: () => JSON.parse(exported.Version()),
      };
    })();
  }

  return playgroundPromise;
}

globalThis.loadNSharpPlayground = loadNSharpPlayground;
