# Task 023 S2.1(f): completed parity proof and shared-empty follow-up — 2026-09-04

**PASS: 94 emitted N# assemblies compare identically under the whole-PE normalizer in all four
arms; zero missing assemblies and zero project-outcome differences.** This completes the missing
proof for `dc3131202` and covers the allocation correction in `08c67e468`. Integration gating and
merging remain the coordinator's work; this evidence is not a product-gate result.

## Revisions and measured coverage

| arm | compiler source revision | corpus source revision | projects passing / discovered | emitted N# assemblies | native tests passed / failed |
|---|---|---|---|---|---|
| a — pristine pre | `51fa6592b3ffc393fb1bc5f3ede571c5129f4c11` | `dc31312024ca1b0897d4065dc693ca740ef2b92d` | 73 / 75 | 94 | 2,117 / 0 |
| b — independent pre control | same pre compiler, fresh corpus archive | same corpus | 73 / 75 | 94 | 2,117 / 0 |
| c — historical S2.1(f) | `dc31312024ca1b0897d4065dc693ca740ef2b92d` | same corpus | 73 / 75 | 94 | 2,117 / 0 |
| d — shared-empty follow-up | `08c67e4689a3cbfff4c7fe13d3be5f4418b414c0` | same corpus | 73 / 75 | 94 | 2,117 / 0 |

`a/b`, `a/c`, `a/d`, and `c/d` each measured **94 compared, IL_DIFFS=0, ONLY_PRE=0,
ONLY_POST=0, OUTCOME_DIFFS=0**. The independent pristine control was checked before accepting
pre/post evidence. The fixed corpus comes from committed git; every compiler and supporting binary
is built from its stated committed revision. No source file is temporarily reverted in the worktree.

The 94 outputs are **73 direct corpus assemblies plus 21 systems-proof assemblies** emitted by
nested native-test processes. Compiler, runtime, third-party, and two copied Playground dependency
assemblies are excluded explicitly, never confused with compiler-produced corpus output. The 75
projects come from committed `project.yml` files under `examples`, `tests`, and `templates`;
`.tests.nl` projects run through `nlc test`, and other projects through `nlc build`. This slice claims
native-test execution and PE parity; it does not claim that every built executable was separately run.

The only two declines are `templates/nsharp-systems-cli` and `templates/nsharp-systems-lib`:
`ReadOnlySpan<byte>.Slice(0, 4)` is analyzed with two `uint` arguments and reports NL402;
the CLI template additionally reports NSYS050. Full normalized diagnostics and exit code 1 are
identical in every arm. No missing dependency is accepted as a decline.

Supporting coverage is measured: `ownership-audit` **18/18**, `lsp-lifetime` **3/3**,
`playground-diagnostic-spans` **116/116**, `playground-tooling-surfaces` **33/33**, and the
project-relative refint fixture **1/1** in every finalized arm. No IDE code changed or visual IDE
claim is made by this backend parity run. No timing claim is made from the compile-time tests.

## The proof instruments and their limits

The inherited `nl98_ilnorm.py` is unchanged (SHA256 `534ad423c57eed3fb2e733e5e80d1e2a1579230253e2b36a306f713d28cde63a`). It compares every PE byte after
zeroing COFF timestamps, the optional-header checksum, debug timestamps/payloads, and the metadata
`#GUID` heap. It does not normalize method bodies, signatures, table rows, token operands, branches,
exception regions, or ordinary metadata strings. This is one writer before/after a declaration-owner
move; it is not the body-key/scope normalizer required for the future second writer.

The comparator requires nonempty identical path sets and compares normalized SHA256 values. Every
project's command, exit code, test counts, and output are compared; only arm paths, elapsed times,
ANSI color sequences, trailing whitespace, and blank lines are normalized in textual output.
Build failures, zero-test runs, lost assemblies, different failures, and missing summaries cannot
produce a successful final verdict. The normalizer source, build inputs, emitted-file inventories,
and compiler/dependency hashes are retained with the raw logs.

Non-vacuity is executed, not assumed. The recorded prediction changes only `Program::Hi` in
`examples/01-hello-world`: the `ldc.i4.s` operand at IL offset `0x000a` changes **42 → 43**.
Exactly one raw byte and exactly one normalized assembly change. The original and mutant both exit 0;
stdout changes only from `hi returned 42` to `hi returned 43`. The other 93 normalized assemblies
remain identical. Original corpus files are never mutated.

Three harness setup errors were rejected before the final verdict: an out-of-repository CLI snapshot
broke `AppContext.BaseDirectory` root discovery; copying only refint omitted the paired runtime
implementation; and copied Playground binaries inflated the corpus count. Final arms use repo-shaped
CLI copies with committed Playground, LanguageServer, BootstrapServices refint, and its paired
`bin/Debug/net10.0` runtime output. The first three arms' already-emitted relative-DLL fixture was
replayed after supplying that missing runtime file; the original failure logs/outcomes are retained,
and all manifests and comparisons were regenerated. The final arm starts with the complete setup.

## Allocation review and correction

The historical change used `new string[](0)` when a constraint row is absent, where C# previously
used `Array.Empty<string>()`. PE equality of user programs cannot detect this compiler allocation.
A direct `Array.Empty<string>()` N# probe declines at `emit.call.generic-unresolved`.
A cache on the existing planner is spellable using a static readonly field initialized by a factory;
the read must be qualified as `ColumnarGenericConstraintPlanner.emptyTypeConstraints`.

Commit `08c67e468` adds that cache and an identity contract. The emitted initializer calls the factory
once and stores the array; missing-row reads use `ldsfld`; present rows preserve their original object.
The cache and factory use lowercase names, but **the existing declaration emitter makes their CLR
metadata public**, as it does for the surrounding N# members. This corrects the earlier source-level
“private” description; no new helper class/service or visibility-policy change is introduced.

The focused estate passed **3/3**: the new shared-reference contract and the two short-row contracts.
An independent native identity probe fails **0/1** on `dc3131202` and passes **1/1** on `08c67e468`.
The complete historical estate is **7,632/7,632**; the final estate is **7,633/7,633**, zero failures
and zero skips. `dev.sh --build-only` and the root formatter pass. C# files and both ratchet keys are
unchanged by the cache correction. The final product gate remains the coordinator's checkpoint.

## Proof files

The persistent proof directory is `/private/tmp/nsharp-023-s21f-proof-20260904`. Key artifacts:

- `verdict.json`; `compare-a-b.json`, `compare-a-c.json`, `compare-a-d.json`, `compare-c-d.json`.
- `compiler-pre.json`, `compiler-post.json`, `compiler-final.json`: git revisions and SHA256 of each
  CLI/dependency file; `environment.json` pins .NET SDK 10.0.105 and the packaged SDK bytes.
- `out/{a,b,c,d}/summary.json`, `outcomes.json`, `assemblies.json`, `logs/`, and `asm/` retain full
  commands, outcomes, inventories, and copied PE bytes. `outcomes-before-runtime-pair.json` and
  `relative-dll-before-runtime-pair.log` retain the rejected dependency setup in the first three arms.
- `estate.log`, `estate-final.log`, `cache-focused-estate.log`, `cache-format.log`, `format-final.log`.
- `nonvacuity-prediction.json`, `nonvacuity.json`, `nonvacuity-before.il.txt`, `nonvacuity-after.il.txt`.
- `cache-identity-before.log`, `cache-identity-after.log`, `cache-final-planner.il.txt` and the cached
  array probe sources/logs retain the allocation evidence.

The [committed PE manifest](2026-09-04-s21f-pe-manifest.json.txt) preserves the exact 94 paths and
all four arms' raw hashes plus their shared normalized hashes. The harness below preserves every
script required to reproduce the proof even if the external directory is later removed.

## Reproduction

Save the following fenced scripts under a fresh proof directory. `H` is inferred from each script's
location; adjust `S` in `run-prepost.py` if the worktree moves. Keep the stated commit revisions.
Create `run_prepost.py` as a symlink to `run-prepost.py`, then run:

```bash
python3 -u run-prepost.py > run.log 2>&1 && python3 -u finalize-proof.py > finalize.log 2>&1
```

Read `verdict.json` only after both commands exit zero. The scripts clear stale verdicts, use fresh
archives, require real test totals, and fail on any unmatched outcome or assembly. The fixture-repair
phase is harmless on a clean reproduction, whose complete dependency setup already passes it.

### run-prepost.py

```python
#!/usr/bin/env python3
"""Reconstructed 023/S2.1f pre/pre/post proof; never mutates the owned worktree."""
import hashlib, io, json, os, pathlib, re, shutil, subprocess, sys, tarfile, time
from nl98_ilnorm import normalise
H = pathlib.Path(__file__).resolve().parent
S = pathlib.Path('/private/tmp/nsharp-agent-wt/023-s2')
POST = subprocess.check_output(['git', 'rev-parse', 'dc3131202'], cwd=S, text=True).strip()
PRE = subprocess.check_output(['git', 'rev-parse', POST + '^'], cwd=S, text=True).strip()
ENV = dict(os.environ, DOTNET_SYSTEM_NET_DISABLEIPV6='1')
SKIP = {'Compiler.dll', 'NSharpLang.Compiler.BootstrapServices.dll', 'NSharpLang.Runtime.dll',
        'Mono.Cecil.dll', 'NSharpLang.Build.Tasks.dll', 'Cli.dll', 'NSharpLang.LanguageServer.dll', 'NSharpLang.Playground.dll'}
PREFIXES = ('Microsoft.', 'Swashbuckle.', 'xunit.', 'System.', 'Newtonsoft.', 'YamlDotNet')
def sha(data): return hashlib.sha256(data).hexdigest()
def log(s): print(time.strftime('%Y-%m-%dT%H:%M:%S%z'), s, flush=True)
def command(args, cwd, logfile):
    log('RUN ' + ' '.join(str(a) for a in args))
    with open(logfile, 'w') as f:
        p = subprocess.run(args, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, env=ENV)
    log('EXIT ' + str(p.returncode) + ' ' + str(logfile))
    if p.returncode: raise RuntimeError(str(logfile) + ' exit ' + str(p.returncode))
def archive(rev, target):
    if target.exists(): shutil.rmtree(target)
    target.mkdir(parents=True)
    data = subprocess.check_output(['git', 'archive', rev], cwd=S)
    with tarfile.open(fileobj=io.BytesIO(data)) as tf: tf.extractall(target)
    return sha(data)
def build(rev, arm):
    source = H/'source'
    archive_sha = archive(rev, source)
    command(['dotnet', 'build', 'src/NSharpLang.Cli', '-c', 'Debug', '-v:m', '--disable-build-servers', '-nr:false'], source, H/('cli-' + arm + '.log'))
    for name, project in [('playground','src/NSharpLang.Playground'),('language-server','src/NSharpLang.LanguageServer')]:
        command(['dotnet','build',project,'-c','Debug','-v:m','--disable-build-servers','-nr:false'],source,H/(name+'-'+arm+'.log'))
    support = H/'support'/arm
    if support.exists(): shutil.rmtree(support)
    for rel in ['src/NSharpLang.Playground/bin/Debug/net10.0','src/NSharpLang.LanguageServer/bin/Debug/net10.0','src/NSharpLang.Compiler.BootstrapServices/obj/Debug/net10.0/refint','src/NSharpLang.Compiler.BootstrapServices/bin/Debug/net10.0']:
        target = support/rel
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(source/rel,target)
    snapshot = H/'cli'/arm
    if snapshot.exists(): shutil.rmtree(snapshot)
    shutil.copytree(source/'src/NSharpLang.Cli/bin/Debug/net10.0', snapshot)
    files = {str(p.relative_to(snapshot)): sha(p.read_bytes()) for p in sorted(snapshot.rglob('*')) if p.is_file()}
    (H/('compiler-' + arm + '.json')).write_text(json.dumps({'revision': rev, 'archive_sha256': archive_sha, 'files': files, 'support_files': {str(p.relative_to(support)): sha(p.read_bytes()) for p in sorted(support.rglob('*')) if p.is_file()}}, indent=2)+'\n')
    return snapshot/'Cli.dll'
def canonical(text, tree, cli):
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    text = text.replace(str(tree), '<corpus>').replace(str(cli.parent), '<compiler>').replace(str(S), '<worktree>')
    text = re.sub(r'\[\d+(?:\.\d+)?s\]', '[elapsed]', text)
    text = re.sub(r'Tests (?:completed|failed) in \d+(?:\.\d+)?s', 'Tests finished in <elapsed>', text)
    text = re.sub(r'\(\d+(?:\.\d+)? ?ms\)', '(<elapsed>)', text)
    return '\n'.join(line.rstrip() for line in text.splitlines() if line.strip())
def sweep(cli, arm):
    tree, out = H/'trees'/arm, H/'out'/arm
    corpus_sha = archive(POST, tree)
    if out.exists(): shutil.rmtree(out)
    (out/'asm').mkdir(parents=True)
    (out/'logs').mkdir()
    support = H/'support'/cli.parent.name
    shutil.copytree(support,tree,dirs_exist_ok=True)
    dep = tree/'src/NSharpLang.Cli/bin/Debug/net10.0'
    dep.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(cli.parent, dep)
    cli = dep/'Cli.dll'
    projects = sorted(p for top in ('examples','tests','templates') for p in (tree/top).rglob('project.yml') if not ({'bin','obj'} & set(p.relative_to(tree).parts)))
    outcomes = []
    for i, pj in enumerate(projects, 1):
        d = pj.parent; rel = str(d.relative_to(tree)); cmd = 'test' if list(d.glob('*.tests.nl')) else 'build'
        args = ['dotnet', str(cli), cmd, '--project', str(d)]
        p = subprocess.run(args, cwd=S, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=ENV, text=True)
        (out/'logs'/(rel.replace('/', '_')+'.log')).write_text(p.stdout)
        counts = re.findall(r'Passed: (\d+), Failed: (\d+), Skipped: (\d+), Total: (\d+)', p.stdout)
        if cmd == 'test' and p.returncode == 0 and (not counts or int(counts[-1][3]) == 0):
            raise RuntimeError('Non-verdict test run: ' + rel)
        outcomes.append({'project': rel, 'command': cmd, 'exit': p.returncode, 'counts': counts,
                         'output': canonical(p.stdout, tree, cli)})
        (out/'outcomes.json').write_text(json.dumps(outcomes, indent=2)+'\n')
        log(f'ARM={arm} {i}/{len(projects)} {rel} cmd={cmd} rc={p.returncode}' + (' counts='+str(counts[-1]) if counts else ''))
    assemblies = {}
    excluded = []
    for p in sorted(tree.rglob('*.dll')):
        rel = p.relative_to(tree)
        if rel.parts[0] == 'src' or 'bin' not in rel.parts or not p.is_file(): continue
        name = p.name[6:] if p.name.startswith('tests_') else p.name
        if name in SKIP or name.startswith(PREFIXES):
            excluded.append(str(rel)); continue
        # Preserve paths. No flattening collision can hide a missing assembly.
        dest = out/'asm'/rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)
        norm, fields = normalise(p.read_bytes())
        if not fields: raise RuntimeError('Not a normalized PE: ' + str(rel))
        assemblies[str(rel)] = {'raw_sha256': sha(p.read_bytes()), 'normal_sha256': sha(norm), 'bytes': p.stat().st_size, 'zeroed': fields}
    summary = {'arm': arm, 'corpus_revision': POST, 'corpus_archive_sha256': corpus_sha, 'targets': len(projects),
               'passed_projects': sum(x['exit'] == 0 for x in outcomes), 'assemblies': len(assemblies),
               'failures': [x['project'] for x in outcomes if x['exit']], 'excluded': excluded}
    (out/'assemblies.json').write_text(json.dumps(assemblies, indent=2)+'\n')
    (out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    log('SWEEP ' + json.dumps({k:v for k,v in summary.items() if k != 'excluded'}))
def compare(a, b):
    aa = json.loads((H/'out'/a/'assemblies.json').read_text()); bb = json.loads((H/'out'/b/'assemblies.json').read_text())
    keys_a, keys_b = set(aa), set(bb)
    diffs = sorted(k for k in keys_a & keys_b if aa[k]['normal_sha256'] != bb[k]['normal_sha256'])
    oa = json.loads((H/'out'/a/'outcomes.json').read_text()); ob = json.loads((H/'out'/b/'outcomes.json').read_text())
    outcome_diffs = [{'before':x, 'after':y} for x,y in zip(oa,ob) if x != y]
    report = {'comparison': a+'-'+b, 'compared': len(keys_a & keys_b), 'IL_DIFFS':len(diffs), 'diffs':diffs,
              'only_before': sorted(keys_a-keys_b), 'only_after': sorted(keys_b-keys_a),
              'outcome_diffs': outcome_diffs, 'project_counts': [len(oa),len(ob)]}
    (H/('compare-'+a+'-'+b+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    log(f'COMPARE={a}-{b} ASSEMBLIES={len(keys_a & keys_b)} IL_DIFFS={len(diffs)} ONLY_PRE={len(keys_a-keys_b)} ONLY_POST={len(keys_b-keys_a)} OUTCOME_DIFFS={len(outcome_diffs)}')
    assert keys_a and keys_a == keys_b and not diffs, 'Assembly parity failed'
    assert len(oa) == len(ob) and not outcome_diffs, 'Project outcome parity failed'
def main():
    log(f'PRE={PRE} POST={POST} CORPUS={POST}')
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=S), 'Owned worktree must remain clean'
    for p in H.glob('compare-*.json'): p.unlink()
    for name in ['verdict.json','estate.log','format.log']:
        (H/name).unlink(missing_ok=True)
    precli = build(PRE,'pre')
    sweep(precli,'a')
    sweep(precli,'b')
    compare('a','b')
    postcli = build(POST,'post')
    sweep(postcli,'c')
    compare('a','c')
    source=H/'source'
    command(['dotnet','restore','src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj','-p:NSharpExcludeTests=false','--force-evaluate','-v:q'],source,H/'estate-restore.log')
    command(['dotnet','test','src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj','-p:NSharpExcludeTests=false','--no-restore','-v:q','--nologo'],source,H/'estate.log')
    command(['dotnet',str(postcli),'format','--check','--project','.'],S,H/'format.log')
    log('VERDICT=OK (non-vacuity proof required separately)')
if __name__ == '__main__':
    try: main()
    except BaseException as e:
        log('VERDICT=FAILED '+repr(e)); raise
```

### finalize-proof.py

```python
#!/usr/bin/env python3
"""Repair only the missing paired runtime fixture, then verify the committed cache follow-up."""
import hashlib,json,pathlib,re,shutil,subprocess
import run_prepost as proof
H,S=proof.H,proof.S
(H/'verdict.json').unlink(missing_ok=True)
FIX=subprocess.check_output(['git','rev-parse','08c67e468'],cwd=S,text=True).strip()
def collect(arm):
    tree,out=H/'trees'/arm,H/'out'/arm
    assemblies={}; excluded=[]
    for p in sorted(tree.rglob('*.dll')):
        rel=p.relative_to(tree)
        if rel.parts[0]=='src' or 'bin' not in rel.parts or not p.is_file(): continue
        name=p.name[6:] if p.name.startswith('tests_') else p.name
        if name in proof.SKIP or name.startswith(proof.PREFIXES): excluded.append(str(rel)); continue
        data=p.read_bytes();norm,fields=proof.normalise(data)
        assert fields, str(rel)
        dest=out/'asm'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
        assemblies[str(rel)]={'raw_sha256':proof.sha(data),'normal_sha256':proof.sha(norm),'bytes':len(data),'zeroed':fields}
    (out/'assemblies.json').write_text(json.dumps(assemblies,indent=2)+'\n')
    summary=json.loads((out/'summary.json').read_text());outcomes=json.loads((out/'outcomes.json').read_text())
    summary.update(passed_projects=sum(r['exit']==0 for r in outcomes),assemblies=len(assemblies),failures=[r['project'] for r in outcomes if r['exit']],excluded=excluded)
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    proof.log('RECOLLECT '+json.dumps({k:v for k,v in summary.items() if k!='excluded'}))
def repair(arm,compiler):
    tree,out=H/'trees'/arm,H/'out'/arm
    rel='src/NSharpLang.Compiler.BootstrapServices/bin/Debug/net10.0/NSharpLang.Compiler.BootstrapServices.dll'
    src=H/'cli'/compiler/'NSharpLang.Compiler.BootstrapServices.dll'
    target=H/'support'/compiler/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    target=tree/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,target)
    manifest=H/('compiler-'+compiler+'.json');data=json.loads(manifest.read_text());support=H/'support'/compiler
    data['support_files']={str(f.relative_to(support)):proof.sha(f.read_bytes()) for f in sorted(support.rglob('*')) if f.is_file()}
    manifest.write_text(json.dumps(data,indent=2)+'\n')
    project='tests/fixtures/external-static-relative-dll';cli=tree/'src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll'
    logfile=out/'logs/tests_fixtures_external-static-relative-dll.log'
    shutil.copy2(logfile,out/'relative-dll-before-runtime-pair.log')
    shutil.copy2(out/'outcomes.json',out/'outcomes-before-runtime-pair.json')
    p=subprocess.run(['dotnet',str(cli),'test','--project',str(tree/project)],cwd=S,env=proof.ENV,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    logfile.write_text(p.stdout)
    counts=re.findall(r'Passed: (\d+), Failed: (\d+), Skipped: (\d+), Total: (\d+)',p.stdout)
    assert p.returncode==0 and counts==[('1','0','0','1')],p.stdout
    row={'project':project,'command':'test','exit':p.returncode,'counts':counts,'output':proof.canonical(p.stdout,tree,cli)}
    outcomes=json.loads((out/'outcomes.json').read_text())
    outcomes=[row if r['project']==project else r for r in outcomes]
    (out/'outcomes.json').write_text(json.dumps(outcomes,indent=2)+'\n')
    collect(arm)
def estate(name,total):
    source=H/'source';project='src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj'
    proof.command(['dotnet','restore',project,'-p:NSharpExcludeTests=false','--force-evaluate','-v:q'],source,H/(name+'-restore.log'))
    proof.command(['dotnet','test',project,'-p:NSharpExcludeTests=false','--no-restore','-v:q','--nologo'],source,H/(name+'.log'))
    text=(H/(name+'.log')).read_text()
    match=re.search(r'Failed:\s*(\d+), Passed:\s*(\d+), Skipped:\s*(\d+), Total:\s*(\d+)',text)
    assert match and tuple(map(int,match.groups()))==(0,total,0,total),text
for arm,compiler in [('a','pre'),('b','pre'),('c','post')]:repair(arm,compiler)
proof.compare('a','b')
proof.compare('a','c')
# The original runner has already run the historical estate; reject an empty or truncated verdict.
text=(H/'estate.log').read_text()
assert re.search(r'Failed:\s*0, Passed:\s*7632, Skipped:\s*0, Total:\s*7632',text),text
cli=proof.build(FIX,'final')
proof.sweep(cli,'d')
proof.compare('a','d')
proof.compare('c','d')
estate('estate-final',7633)
proof.command(['dotnet',str(cli),'format','--check','--project','.'],S,H/'format-final.log')
proof.command(['python3',str(H/'nonvacuity.py')],S,H/'nonvacuity.log')
expected_declines=['templates/nsharp-systems-cli','templates/nsharp-systems-lib']
for arm in 'abcd':
    observed=json.loads((H/'out'/arm/'summary.json').read_text())
    assert (observed['targets'],observed['passed_projects'],observed['assemblies'])==(75,73,94),observed
    assert observed['failures']==expected_declines,observed
    outcomes=json.loads((H/'out'/arm/'outcomes.json').read_text())
    assert sum(int(r['counts'][-1][0]) for r in outcomes if r['counts'])==2117
    assert sum(int(r['counts'][-1][1]) for r in outcomes if r['counts'])==0
summary={'verdict':'PASS','pre':proof.PRE,'historical_post':proof.POST,'final':FIX,'corpus':proof.POST,'corpus_outputs':94,
         'targets_per_arm':75,'passing_projects_per_arm':73,'expected_declines':['templates/nsharp-systems-cli','templates/nsharp-systems-lib'],
         'comparisons':['a-b','a-c','a-d','c-d'],'IL_DIFFS':0,'estate_historical':7632,'estate_final':7633,'normalizer_mutation_differences':1}
(H/'verdict.json').write_text(json.dumps(summary,indent=2)+'\n')
proof.log('FINAL '+json.dumps(summary))
```

### nonvacuity.py

```python
#!/usr/bin/env python3
"""Before mutation: Hi's ldc.i4.s operand 42->43 must change exactly Hello.dll and runtime output."""
import hashlib, json, pathlib, re, shutil, struct, subprocess
from nl98_ilnorm import normalise
H=pathlib.Path(__file__).resolve().parent
base=H/'trees/a/examples/01-hello-world/bin/Debug/net10.0'
mut=H/'mutation'
if mut.exists(): shutil.rmtree(mut)
shutil.copytree(base,mut)
p=mut/'Hello.dll'
b=bytearray(p.read_bytes())
original=bytes(b)
il=subprocess.check_output(['ilspycmd','-il',str(p)],text=True)
(H/'nonvacuity-before.il.txt').write_text(il)
m=re.search(r'// Method begins at RVA 0x([0-9a-fA-F]+)\s*// Header size: (\d+).*?IL_([0-9a-fA-F]+): ldc\.i4\.s 42\s*IL_[0-9a-fA-F]+: ret\s*} // end of method Program::Hi',il,re.S)
assert m, 'Could not uniquely locate Hi ldc.i4.s 42'
rva, header, instruction=int(m[1],16),int(m[2]),int(m[3],16)
u16=lambda o:struct.unpack_from('<H',b,o)[0]
u32=lambda o:struct.unpack_from('<I',b,o)[0]
pe=u32(0x3c); coff=pe+4; section=coff+20+u16(coff+16)
body=None
for i in range(u16(coff+2)):
    s=section+i*40; va=u32(s+12); size=max(u32(s+8),u32(s+16))
    if va <= rva < va+size: body=u32(s+20)+rva-va
assert body is not None
pos=body+header+instruction
assert b[pos:pos+2] == b'\x1f\x2a', (pos,b[pos:pos+2])
prediction={'assembly':'examples/01-hello-world/bin/Debug/net10.0/Hello.dll','method':'Program::Hi',
            'IL_offset':instruction,'PE_operand_offset':pos+1,'from':42,'to':43,
            'expected_assembly_differences':1,'expected_output_replacement':['hi returned 42','hi returned 43']}
(H/'nonvacuity-prediction.json').write_text(json.dumps(prediction,indent=2)+'\n')
b[pos+1]=43
p.write_bytes(b)
assert sum(x!=y for x,y in zip(original,b))==1
assert normalise(original)[0] != normalise(b)[0]
manifest=json.loads((H/'out/a/assemblies.json').read_text())
differences=[]
for key, row in manifest.items():
    data=bytes(b) if key==prediction['assembly'] else (H/'out/a/asm'/key).read_bytes()
    if hashlib.sha256(normalise(data)[0]).hexdigest()!=row['normal_sha256']: differences.append(key)
assert differences==[prediction['assembly']], differences
pre=subprocess.run(['dotnet',str(base/'Hello.dll')],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
post=subprocess.run(['dotnet',str(p)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
assert pre.returncode==post.returncode==0
assert 'hi returned 42' in pre.stdout
assert post.stdout==pre.stdout.replace('hi returned 42','hi returned 43')
assert pre.stderr==post.stderr
il_post=subprocess.check_output(['ilspycmd','-il',str(p)],text=True)
(H/'nonvacuity-after.il.txt').write_text(il_post)
assert il_post==il.replace('IL_000a: ldc.i4.s 42','IL_000a: ldc.i4.s 43')
report={'verdict':'PASS','compared':len(manifest),'IL_DIFFS':len(differences),'differences':differences,
        'raw_bytes_changed':1,'before_stdout':pre.stdout,'after_stdout':post.stdout,'exit_codes':[pre.returncode,post.returncode],
        'original_sha256':hashlib.sha256(original).hexdigest(),'mutated_sha256':hashlib.sha256(b).hexdigest()}
(H/'nonvacuity.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
```

### nl98_ilnorm.py

```python
#!/usr/bin/env python3
"""PE NORMALISER — REBUILT after /private/tmp took `nl82_ilnorm.py` with it.

Two builds of the SAME source are never byte-identical: the MVID is a fresh GUID, the COFF header
carries a timestamp, the optional header carries a checksum, and the debug directory carries a PDB
GUID, age and path. Everything else is the emitted content. This zeroes exactly those volatile
fields and leaves the rest untouched, so a byte comparison afterwards is a comparison of what the
compiler produced.

It is VALIDATED BY THE SWEEP'S OWN CONTROL: two runs of the SAME CLI over two fresh archives must
normalise to identical bytes. If the control differs, this normaliser is incomplete and no A-vs-B
number it produces is evidence.
"""
import struct


def _u16(b, o):
    return struct.unpack_from('<H', b, o)[0]


def _u32(b, o):
    return struct.unpack_from('<I', b, o)[0]


def normalise(data):
    """Return (normalised bytes, list of field names zeroed)."""
    b = bytearray(data)
    zeroed = []
    if len(b) < 0x40 or b[0:2] != b'MZ':
        return bytes(b), zeroed
    pe = _u32(b, 0x3C)
    if pe + 24 > len(b) or b[pe:pe + 4] != b'PE\0\0':
        return bytes(b), zeroed

    coff = pe + 4
    # COFF TimeDateStamp
    struct.pack_into('<I', b, coff + 4, 0)
    zeroed.append('coff.TimeDateStamp')

    n_sections = _u16(b, coff + 2)
    opt_size = _u16(b, coff + 16)
    opt = coff + 20
    magic = _u16(b, opt)
    plus = magic == 0x20B
    # Optional-header CheckSum sits at +64 in both PE32 and PE32+
    struct.pack_into('<I', b, opt + 64, 0)
    zeroed.append('optional.CheckSum')

    dd_off = opt + (112 if plus else 96)
    n_dd = _u32(b, opt + (108 if plus else 92))

    sections = []
    sec_off = opt + opt_size
    for i in range(n_sections):
        s = sec_off + i * 40
        if s + 40 > len(b):
            break
        vsize = _u32(b, s + 8)
        vaddr = _u32(b, s + 12)
        rsize = _u32(b, s + 16)
        raddr = _u32(b, s + 20)
        sections.append((vaddr, vsize, raddr, rsize))

    def rva_to_off(rva):
        for vaddr, vsize, raddr, rsize in sections:
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return raddr + (rva - vaddr)
        return None

    # ---- debug directory (index 6): timestamp, and the CodeView GUID/age/path payload ----
    if n_dd > 6:
        dbg_rva = _u32(b, dd_off + 6 * 8)
        dbg_size = _u32(b, dd_off + 6 * 8 + 4)
        off = rva_to_off(dbg_rva) if dbg_rva else None
        if off is not None:
            count = dbg_size // 28
            for i in range(count):
                e = off + i * 28
                if e + 28 > len(b):
                    break
                struct.pack_into('<I', b, e + 4, 0)          # TimeDateStamp
                data_size = _u32(b, e + 16)
                data_off = _u32(b, e + 24)                    # PointerToRawData
                if data_off and data_off + data_size <= len(b):
                    b[data_off:data_off + data_size] = b'\0' * data_size
            zeroed.append(f'debug.directory[{count}]')

    # ---- CLI metadata #GUID heap (the MVID) ----
    if n_dd > 14:
        cli_rva = _u32(b, dd_off + 14 * 8)
        cli_off = rva_to_off(cli_rva) if cli_rva else None
        if cli_off is not None and cli_off + 72 <= len(b):
            md_rva = _u32(b, cli_off + 8)
            md_off = rva_to_off(md_rva)
            if md_off is not None and b[md_off:md_off + 4] == b'BSJB':
                ver_len = _u32(b, md_off + 12)
                p = md_off + 16 + ver_len
                p += 2                                        # flags
                n_streams = _u16(b, p)
                p += 2
                for _ in range(n_streams):
                    s_off = _u32(b, p)
                    s_size = _u32(b, p + 4)
                    p += 8
                    end = p
                    while end < len(b) and b[end] != 0:
                        end += 1
                    name = bytes(b[p:end]).decode('ascii', 'replace')
                    p = end + 1
                    p = (p + 3) & ~3                          # 4-byte aligned
                    if name == '#GUID':
                        start = md_off + s_off
                        b[start:start + s_size] = b'\0' * s_size
                        zeroed.append('metadata.#GUID')

    return bytes(b), zeroed
```
