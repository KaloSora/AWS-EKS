"""Offline regression tests. Never source real AWS authentication or call AWS."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT_DIR = Path(__file__).resolve().parents[1]

MOCK = r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
kind = Path(sys.argv[0]).name
with open(os.environ['TEST_TRACE'], 'a') as f:
    f.write(json.dumps([kind, *args]) + '\n')
mode = os.environ['TEST_MODE']
marker = Path(os.environ['TEST_DELETED'])
if kind == 'terraform':
    if 'console' in args:
        print(json.dumps(json.dumps({'region':'ap-southeast-1','cluster_name':'dev-eks'})))
    elif 'show' in args:
        groups = [] if mode == 'orphan' else [{'type':'aws_eks_node_group','values':{'cluster_name':'dev-eks','node_group_name':'dev-eks-general'}}]
        print(json.dumps({'values':{'root_module':{'child_modules':[{'resources':groups}]}}}))
    elif 'destroy' in args and '-target=module.eks.aws_eks_node_group.this' in args:
        if mode == 'terraform_failure': sys.exit(2)
        marker.touch()
    elif 'apply' in args and mode == 'apply_failure':
        sys.exit(2)
elif kind == 'aws':
    if args[:2] == ['eks','list-nodegroups']:
        if mode == 'access_denied':
            print('An error occurred (AccessDeniedException)', file=sys.stderr)
            sys.exit(254)
        if mode == 'absent_cluster':
            print('An error occurred (ResourceNotFoundException)', file=sys.stderr)
            sys.exit(254)
        groups = [] if marker.exists() and mode != 'lingering' else ['dev-eks-general']
        print(json.dumps({'nodegroups':groups}))
    elif args[:3] == ['eks','wait','nodegroup-deleted']:
        if mode == 'wait_failure': sys.exit(255)
    else:
        raise AssertionError(args)
'''


class LifecycleTests(unittest.TestCase):
    def run_script(self, script, mode='normal'):
        with tempfile.TemporaryDirectory(prefix='eks lifecycle test ') as tmp:
            root = Path(tmp)
            scripts = root/'project'/'script'
            scripts.mkdir(parents=True)
            (scripts.parent/'modules').mkdir()
            for name in [script, 'eks_lifecycle.sh']:
                shutil.copy2(SCRIPT_DIR/name, scripts/name)
            # This replaces the authentication script; no real auth file is read.
            (scripts/'run_aws_auth.sh').write_text('return 0\n')
            binaries = root/'bin'
            binaries.mkdir()
            for name in ['terraform','aws']:
                p = binaries/name
                p.write_text(f'#!{sys.executable}\n'+MOCK)
                p.chmod(0o755)
            jq = shutil.which('jq')
            self.assertIsNotNone(jq, 'jq is required by the scripts')
            (binaries/'jq').symlink_to(jq)
            trace = root/'trace'
            env = {
                'PATH':str(binaries)+':/usr/bin:/bin',
                'TEST_MODE':mode, 'TEST_TRACE':str(trace),
                'TEST_DELETED':str(root/'deleted'), 'TMPDIR':str(root),
            }
            result = subprocess.run(['/bin/bash',str(scripts/script)],cwd='/tmp',
                                    env=env,capture_output=True,text=True)
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            return result, calls

    def destroys(self, calls):
        return [next(arg for arg in c if arg.startswith('-target='))
                for c in calls if c[0]=='terraform' and 'destroy' in c]

    def test_destroy_order_and_wait(self):
        result,calls = self.run_script('run_infra_destroy.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.destroys(calls),[
            '-target=module.eks.aws_eks_node_group.this',
            '-target=module.eks','-target=module.ec2_nat_instance'])
        wait = next(i for i,c in enumerate(calls) if c[:4]==['aws','eks','wait','nodegroup-deleted'])
        cluster = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks' in c)
        self.assertLess(wait,cluster)

    def test_untracked_group_blocks_all_destruction(self):
        result,calls = self.run_script('run_infra_destroy.sh','orphan')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),[])
        self.assertIn('missing from the current Terraform state',result.stderr)

    def test_wait_failure_preserves_cluster_roles_and_nat(self):
        result,calls = self.run_script('run_infra_destroy.sh','wait_failure')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks.aws_eks_node_group.this'])

    def test_lingering_groups_preserve_cluster_roles_and_nat(self):
        result,calls = self.run_script('run_infra_destroy.sh','lingering')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks.aws_eks_node_group.this'])

    def test_nodegroup_destroy_failure_stops_script(self):
        result,calls = self.run_script('run_infra_destroy.sh','terraform_failure')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks.aws_eks_node_group.this'])
        self.assertNotIn('[PASS] STEP 2',result.stdout)

    def test_access_denied_is_not_treated_as_missing_cluster(self):
        result,calls = self.run_script('run_infra_destroy.sh','access_denied')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),[])

    def test_missing_cluster_allows_remaining_cleanup(self):
        result,calls = self.run_script('run_infra_destroy.sh','absent_cluster')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(self.destroys(calls)),3)

    def test_create_refuses_untracked_group(self):
        result,calls = self.run_script('run_infra_create.sh','orphan')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(any('apply' in c for c in calls if c[0]=='terraform'))

    def test_apply_failure_reports_recovery_without_destroying(self):
        result,calls = self.run_script('run_infra_create.sh','apply_failure')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Preserve state/recovery files',result.stdout+result.stderr)
        self.assertEqual(self.destroys(calls),[])
        self.assertNotIn('[PASS] STEP 2',result.stdout)

    def test_create_success(self):
        result,calls = self.run_script('run_infra_create.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(any('apply' in c for c in calls if c[0]=='terraform'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
