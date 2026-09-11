import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

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
            import json
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
    def publish(self, pr='190', state='open', head='abc123'):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            (p/'artifacts').mkdir()
            (p/'artifacts/sdk.nupkg').write_text('test asset')
            mock=p/'gh'
            mock.write_text("""#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open('calls.jsonl','a') as f: f.write(json.dumps(args)+'\\n')
if '.state' in args: print(os.environ['STATE'])
if '.head.sha' in args: print(os.environ['HEAD'])
""")
            mock.chmod(0o755)
            env=dict(os.environ, PATH=d+':'+os.environ['PATH'], GH_REPO='owner/repo',
                     PR_NUMBER=pr, COMMIT='abc123', RUN_ID='100', RUN_ATTEMPT='2', STATE=state, HEAD=head)
            result=subprocess.run(['bash','-c',run_block('build.yml','name: Publish unofficial')],
                                  env=env,cwd=d,capture_output=True,text=True)
            import json
            calls=[json.loads(line) for line in (p/'calls.jsonl').read_text().splitlines()]
            self.assertEqual(result.returncode,0,result.stderr)
            return [c for c in calls if c[:2] == ['release','create']]
    def test_open_current_pr_publishes_unique_prerelease(self):
        calls=self.publish()
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][2],'unofficial-pr-190-100-2')
        self.assertIn('--prerelease',calls[0])
        self.assertIn('--latest=false',calls[0])
        self.assertIn('artifacts/sdk.nupkg',calls[0])
    def test_closed_pr_never_publishes(self):
        self.assertEqual(self.publish(state='closed'),[])
    def test_superseded_commit_never_publishes(self):
        self.assertEqual(self.publish(head='newer'),[])
    def test_main_has_separate_namespace(self):
        self.assertEqual(self.publish(pr='')[0][2],'unofficial-main-100-2')

class PackageClosureTests(unittest.TestCase):
    def validate(self, omit='', core_version='1.0.0', duplicate=False, missing_loader=False):
        import zipfile
        with tempfile.TemporaryDirectory() as d:
            names=['Sdk', 'Runtime', 'Templates', 'Compiler', 'Compiler.Core']
            for name in names:
                if name == omit:
                    continue
                version=core_version if name == 'Compiler.Core' else '1.0.0'
                dependency='<dependencies><dependency id="NSharpLang.Compiler.Core" version="1.0.0" /></dependencies>' if name == 'Compiler' else ''
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
    def test_missing_core_is_rejected(self):
        self.assertNotEqual(self.validate(omit='Compiler.Core').returncode,0)
    def test_wrong_core_version_is_rejected(self):
        self.assertNotEqual(self.validate(core_version='2.0.0').returncode,0)
    def test_missing_sdk_loader_is_rejected(self):
        self.assertNotEqual(self.validate(missing_loader=True).returncode,0)
    def test_duplicate_package_is_rejected(self):
        self.assertNotEqual(self.validate(duplicate=True).returncode,0)

if __name__=='__main__': unittest.main()
