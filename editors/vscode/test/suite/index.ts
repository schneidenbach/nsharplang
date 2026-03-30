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

    // TEST_SUITE: comma-separated list of suite names to run.
    // e.g. TEST_SUITE=extension,hover,errorCases npm test
    // If unset, all test files are loaded.
    const suiteFilter = process.env.TEST_SUITE?.split(',').map(s => s.trim()).filter(Boolean);

    // TEST_GREP: Mocha grep pattern to filter individual tests by name.
    // e.g. TEST_GREP="cross-file" npm test
    const grepPattern = process.env.TEST_GREP;
    if (grepPattern) {
        try {
            mocha.grep(new RegExp(grepPattern));
        } catch (err) {
            throw new Error(`TEST_GREP contains invalid regex "${grepPattern}": ${err}`);
        }
        console.log(`[N# Tests] Grep filter: ${grepPattern}`);
    }

    try {
        const allFiles = await glob('**/**.test.js', { cwd: testsRoot });

        const files = suiteFilter
            ? allFiles.filter(f => {
                const name = path.basename(f, '.test.js');
                return suiteFilter.includes(name);
            })
            : allFiles;

        if (suiteFilter) {
            console.log(`[N# Tests] Suite filter: ${suiteFilter.join(', ')}`);
            console.log(`[N# Tests] Matched ${files.length} of ${allFiles.length} test files`);
        } else {
            console.log(`[N# Tests] Found ${files.length} test files in ${testsRoot}`);
        }

        for (const file of files) {
            console.log(`[N# Tests]   - ${file}`);
            mocha.addFile(path.resolve(testsRoot, file));
        }

        if (files.length === 0 && suiteFilter) {
            const available = allFiles.map(f => path.basename(f, '.test.js')).join(', ');
            throw new Error(
                `TEST_SUITE filter "${suiteFilter.join(',')}" matched 0 of ${allFiles.length} test files.\n` +
                `Available suites: ${available}`
            );
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
