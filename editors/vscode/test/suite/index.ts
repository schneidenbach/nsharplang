import * as path from 'path';
import Mocha from 'mocha';
import { glob } from 'glob';

export async function run(): Promise<void> {
    const mocha = new Mocha({
        ui: 'tdd',
        color: true,
        timeout: 120_000,
        retries: 0,
        slow: 30_000,
    });

    const testsRoot = path.resolve(__dirname, '.');

    try {
        const files = await glob('**/**.test.js', { cwd: testsRoot });
        console.log(`[N# Tests] Found ${files.length} test files in ${testsRoot}`);
        for (const file of files) {
            console.log(`[N# Tests]   - ${file}`);
            mocha.addFile(path.resolve(testsRoot, file));
        }
    } catch (err) {
        console.error('[N# Tests] Failed to discover test files:', err);
        throw err;
    }

    return new Promise((resolve, reject) => {
        try {
            mocha.run(failures => {
                if (failures > 0) {
                    reject(new Error(`${failures} test(s) failed.`));
                } else {
                    resolve();
                }
            });
        } catch (err) {
            console.error('[N# Tests] Failed to run tests:', err);
            reject(err);
        }
    });
}
