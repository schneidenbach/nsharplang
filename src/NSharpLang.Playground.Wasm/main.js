import { dotnet } from './_framework/dotnet.js';

const { getAssemblyExports, getConfig, runMain } = await dotnet.withDiagnosticTracing(false).create();
const exports = await getAssemblyExports(getConfig().mainAssemblyName);
globalThis.NSharpPlaygroundWasm = exports.NSharpLang.Playground.Wasm.PlaygroundExports; const response = await fetch(new URL('./references.zip', import.meta.url));
if (!response.ok) throw new Error(`Playground metadata references failed to load (${response.status}).`);
const references = new Uint8Array(await response.arrayBuffer()); let binary = '';
for (let offset = 0; offset < references.length; offset += 0x8000) binary += String.fromCharCode(...references.subarray(offset, offset + 0x8000));
globalThis.NSharpPlaygroundWasm.RegisterMetadataReferences(btoa(binary)); await runMain();
