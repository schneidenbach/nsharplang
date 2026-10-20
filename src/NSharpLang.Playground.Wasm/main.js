import { dotnet } from './_framework/dotnet.js';

const { getAssemblyExports, getConfig, runMain } = await dotnet
  .withDiagnosticTracing(false)
  .create();

const config = getConfig();
const exports = await getAssemblyExports(config.mainAssemblyName);

globalThis.NSharpPlaygroundWasm = exports.NSharpLang.Playground.Wasm.PlaygroundExports;
const referencesResponse = await fetch(new URL('./references.zip', import.meta.url));
if (!referencesResponse.ok) throw new Error(`Playground metadata references failed to load (${referencesResponse.status}).`);
const references = new Uint8Array(await referencesResponse.arrayBuffer());
let binary = '';
for (let offset = 0; offset < references.length; offset += 0x8000) {
  binary += String.fromCharCode(...references.subarray(offset, offset + 0x8000));
}
globalThis.NSharpPlaygroundWasm.RegisterMetadataReferences(btoa(binary));

await runMain();
