import { dotnet } from './_framework/dotnet.js';

const { getAssemblyExports, getConfig, runMain } = await dotnet
  .withDiagnosticTracing(false)
  .create();

const config = getConfig();
const exports = await getAssemblyExports(config.mainAssemblyName);

globalThis.NSharpPlaygroundWasm = exports.NSharpLang.Playground.Wasm.PlaygroundExports;

await runMain();
