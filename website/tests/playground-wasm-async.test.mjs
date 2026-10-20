import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

test('the published WebAssembly playground awaits async N# functions', async () => {
  const nativeFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(input);
    if (url.protocol !== 'file:') return nativeFetch(input, init);

    return new Response(await readFile(fileURLToPath(url)), {status: 200});
  };

  try {
    await import('../static/playground/wasm/main.js');
    const wasm = globalThis.NSharpPlaygroundWasm;
    assert.ok(wasm, 'the WASM module exports were initialized');

    const source = `import System.Threading.Tasks

async func AddOne(value: int): int {
    await Task.Delay(1)
    return value + 1
}

async func main() {
    result := await AddOne(41)
    print result
}
`;
    const responseText = await wasm.RunProject(JSON.stringify([
      {name: 'Program.nl', code: source},
    ]), 'Program.nl');
    const response = JSON.parse(responseText);

    assert.equal(response.ok, true, JSON.stringify(response.diagnostics));
    assert.equal(response.exitCode, 0);
    assert.equal(response.stdout, '42\n');
    assert.equal(response.stderr, null);
    assert.equal(response.unsupportedReason, null);
  } finally {
    globalThis.fetch = nativeFetch;
  }
});
