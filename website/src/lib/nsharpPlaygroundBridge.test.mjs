import assert from 'node:assert/strict';
import {describe, it} from 'node:test';
import {createNSharpPlaygroundBridge} from '../../static/playground/nsharp-playground-bridge.mjs';

describe('createNSharpPlaygroundBridge', () => {
  it('awaits the WebAssembly RunProject promise before parsing its response', async () => {
    let receivedFiles;
    let receivedActiveFile;
    const exported = {
      RunProject: async (filesJson, activeFile) => {
        receivedFiles = JSON.parse(filesJson);
        receivedActiveFile = activeFile;
        await Promise.resolve();
        return JSON.stringify({ok: true, stdout: '42\n'});
      },
    };

    const bridge = createNSharpPlaygroundBridge(exported);
    const pending = bridge.runProject([{name: 'Program.nl', code: 'async func main() {}'}]);
    assert.ok(pending instanceof Promise);
    assert.deepEqual(await pending, {ok: true, stdout: '42\n'});
    assert.deepEqual(receivedFiles, [{name: 'Program.nl', code: 'async func main() {}'}]);
    assert.equal(receivedActiveFile, 'Program.nl');
  });
});
