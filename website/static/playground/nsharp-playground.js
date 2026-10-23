import {createNSharpPlaygroundBridge} from './nsharp-playground-bridge.mjs';

let playgroundPromise;

export async function loadNSharpPlayground() {
  if (!playgroundPromise) {
    playgroundPromise = (async () => {
      await import(new URL('wasm/main.js', import.meta.url).href);
      const exported = globalThis.NSharpPlaygroundWasm;
      if (!exported) {
        throw new Error('N# playground WASM exports were not initialized.');
      }

      return createNSharpPlaygroundBridge(exported);
    })();
  }

  return playgroundPromise;
}

globalThis.loadNSharpPlayground = loadNSharpPlayground;
