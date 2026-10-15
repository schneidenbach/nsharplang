import hashlib, json, os, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

def run_block(name, marker):
    lines = (ROOT / '.github/workflows' / name).read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if marker in line)
    start = next(i for i in range(start, len(lines)) if lines[i].strip() == 'run: |') + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    result=[]
    for line in lines[start:]:
        if line.strip() and len(line)-len(line.lstrip()) < indent:
            break
        result.append(line[indent:])
    return '\n'.join(result)

def release_flags(call):
    return [arg for arg in call if arg.startswith(('--prerelease', '--latest'))]

class CleanupTests(unittest.TestCase):
    def check_cleanup(self, number='190', state='closed', failure=''):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            mock=p/'gh'
            mock.write_text('''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open('calls.jsonl','a') as f: f.write(json.dumps(args)+'\\n')
joined=' '.join(args)
if os.environ.get('FAILURE') and os.environ['FAILURE'] in joined: sys.exit(1)
if '/pulls/' in joined: print(os.environ['STATE'])
elif '/releases?' in joined:
 print('unofficial-pr-190-100-1\\nunofficial-pr-190-200-2\\nunofficial-pr-1900-100-1\\nunofficial-main-100-1\\nv1.0.0\\nunofficial-pr-190-evil')
elif '/matching-refs/' in joined:
 print('refs/tags/unofficial-pr-190-300-1\\nrefs/tags/unofficial-pr-1900-100-1')
''')
            mock.chmod(0o755)
            env=dict(os.environ, PATH=d+':'+os.environ['PATH'], GH_REPO='owner/repo', PR_NUMBER=number, STATE=state, FAILURE=failure)
            result=subprocess.run(['bash','-c',run_block('cleanup-unofficial.yml',"Delete this closed")],env=env,cwd=d,capture_output=True,text=True)
            calls=[json.loads(line) for line in (p/'calls.jsonl').read_text().splitlines()] if (p/'calls.jsonl').exists() else []
            return result,calls
    def test_exact_namespace_and_orphan_tags(self):
        result,calls=self.check_cleanup()
        self.assertEqual(result.returncode,0,result.stderr)
        deletes=[c for c in calls if 'delete' in c or 'DELETE' in c]
        self.assertEqual(deletes,[['release','delete','unofficial-pr-190-100-1','--cleanup-tag','--yes'],['release','delete','unofficial-pr-190-200-2','--cleanup-tag','--yes'],['api','--method','DELETE','repos/owner/repo/git/refs/tags/unofficial-pr-190-300-1']])
    def test_open_pr_protected(self):
        result,calls=self.check_cleanup(state='open')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(calls),1)
    def test_invalid_input_rejected_before_api(self):
        result,calls=self.check_cleanup(number='190; echo oops')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(calls,[])
    def test_api_failure_is_not_silenced(self):
        result,calls=self.check_cleanup(failure='/releases?')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any('delete' in c for c in calls))

class PublishTests(unittest.TestCase):
    def publish(self, pr='190', state='open', head='abc123', latest='', order='ahead'):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            (p/'artifacts/vscode').mkdir(parents=True)
            for name in ('sdk.nupkg', 'vscode/nsharp.vsix'): (p/'artifacts'/name).write_text(name)
            mock=p/'gh'
            mock.write_text("""#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open('calls.jsonl','a') as f: f.write(json.dumps(args)+'\\n')
reply={'.state':'STATE','.head.sha':'HEAD','.target_commitish':'LATEST','.status':'ORDER'}.get(args[-1])
if reply and not os.environ[reply]: sys.exit('gh: Not Found (HTTP 404)')
if reply: print(os.environ[reply])
""")
            mock.chmod(0o755)
            env=dict(os.environ, PATH=d+':'+os.environ['PATH'], GH_REPO='owner/repo', RUNNER_TEMP=d, LATEST=latest, ORDER=order,
                     PR_NUMBER=pr, COMMIT='abc123', RUN_ID='100', RUN_ATTEMPT='2', STATE=state, HEAD=head)
            result=subprocess.run(['bash','-c',run_block('build.yml','name: Publish unofficial')],
                                  env=env,cwd=d,capture_output=True,text=True)
            calls=[json.loads(line) for line in (p/'calls.jsonl').read_text().splitlines()]
            self.assertEqual(result.returncode,0,result.stderr)
            return [c for c in calls if c[:2] == ['release','create']], (p/'SHA256SUMS').exists() and (p/'SHA256SUMS').read_text()
    def test_open_current_pr_publishes_unique_prerelease(self):
        calls,_=self.publish()
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][2],'unofficial-pr-190-100-2')
        self.assertEqual(release_flags(calls[0]),['--prerelease','--latest=false'])
        self.assertIn('artifacts/sdk.nupkg',calls[0])
    def test_every_asset_is_checksummed_under_its_release_name(self):
        calls,sums=self.publish()
        self.assertEqual((sums, calls[0][5].endswith('/SHA256SUMS')), (''.join(f'{hashlib.sha256(n.encode()).hexdigest()}  {Path(n).name}\n' for n in ('sdk.nupkg', 'vscode/nsharp.vsix')), True))
    def test_closed_pr_never_publishes(self):
        self.assertEqual(self.publish(state='closed'),([],False))
    def test_superseded_commit_never_publishes(self):
        self.assertEqual(self.publish(head='newer'),([],False))
    def test_main_is_the_latest_full_release_unless_older_than_latest(self):
        self.assertEqual(self.publish(pr='')[0][0][2],'unofficial-main-100-2')
        self.assertEqual([release_flags(self.publish(pr='',latest=l,order=o)[0][0]) for l,o in (('','ahead'),('old','ahead'),('old','identical'),('new','behind'))],[['--latest']]*3+[['--latest=false']])

class PackageClosureTests(unittest.TestCase):
    def validate(self, omit='', core_version='1.0.0', duplicate=False, missing_loader=False):
        import zipfile
        with tempfile.TemporaryDirectory() as d:
            names=['Sdk', 'Runtime', 'Templates', 'Compiler', 'Compiler.Driver', 'Compiler.Tooling', 'Compiler.CodeIntel', 'Compiler.Emit', 'Compiler.Plan', 'Compiler.Core', 'Compiler.Syntax', 'Compiler.Model']
            for name in names:
                if name == omit:
                    continue
                version=core_version if name == 'Compiler.Core' else '1.0.0'
                dependency=f'<dependencies><dependency id="NSharpLang.Compiler.{ {"Compiler": "Driver", "Compiler.Driver": "Tooling", "Compiler.Tooling": "CodeIntel", "Compiler.CodeIntel": "Emit", "Compiler.Emit": "Plan", "Compiler.Plan": "Core", "Compiler.Core": "Syntax"}.get(name, "Model") }" version="1.0.0" /></dependencies>' if name in ('Compiler', 'Compiler.Driver', 'Compiler.Tooling', 'Compiler.CodeIntel', 'Compiler.Emit', 'Compiler.Plan', 'Compiler.Core', 'Compiler.Syntax') else ''
                content=f'<package><metadata><id>NSharpLang.{name}</id><version>{version}</version>{dependency}</metadata></package>'
                with zipfile.ZipFile(Path(d)/f'{name}.nupkg','w') as archive:
                    archive.writestr(f'{name}.nuspec',content)
                    if name == 'Sdk' and not missing_loader:
                        archive.writestr('tools/System.Reflection.MetadataLoadContext.dll',b'fixture')
            if duplicate:
                import shutil
                shutil.copyfile(Path(d)/'Sdk.nupkg',Path(d)/'duplicate.nupkg')
            return subprocess.run(['python3',str(ROOT/'scripts/verify-release.py'),d],capture_output=True,text=True)
    def test_complete_release_resolves_internal_dependencies(self):
        result=self.validate()
        self.assertEqual(result.returncode,0,result.stderr)
    def test_missing_compiler_package_is_rejected(self):
        self.assertTrue(all(self.validate(omit=name).returncode != 0 for name in ('Compiler.Driver', 'Compiler.Tooling', 'Compiler.CodeIntel', 'Compiler.Emit', 'Compiler.Plan', 'Compiler.Core', 'Compiler.Syntax', 'Compiler.Model')))
    def test_wrong_core_version_is_rejected(self):
        self.assertNotEqual(self.validate(core_version='2.0.0').returncode,0)
    def test_missing_sdk_loader_is_rejected(self):
        self.assertNotEqual(self.validate(missing_loader=True).returncode,0)
    def test_duplicate_package_is_rejected(self):
        self.assertNotEqual(self.validate(duplicate=True).returncode,0)

if __name__=='__main__': unittest.main()
