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
        expression = sys.stdin.read()
        assert 'nat_instance_enable = var.nat_instance_enable' in expression
        if mode == 'console_failure': sys.exit(2)
        context = {'region':'ap-southeast-1','cluster_name':'dev-eks',
                   'nat_instance_enable':json.loads(os.environ['TEST_NAT_ENABLED'])}
        if mode == 'invalid_nat': context['nat_instance_enable'] = 'false'
        if mode == 'missing_nat': context.pop('nat_instance_enable')
        print(json.dumps(json.dumps(context)))
    elif 'show' in args:
        if mode == 'state_failure': sys.exit(2)
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
    elif args[:2] == ['eks','update-kubeconfig']:
        if mode == 'kubeconfig_failure': sys.exit(2)
        Path(args[args.index('--kubeconfig') + 1]).write_text('# mock kubeconfig\n')
    else:
        raise AssertionError(args)
'''


class LifecycleTests(unittest.TestCase):
    def run_script(self, script, mode='normal', auto_approve='true', confirm=None, nat_enabled=True):
        with tempfile.TemporaryDirectory(prefix='eks lifecycle test ') as tmp:
            root = Path(tmp)
            scripts = root/'project'/'script'
            scripts.mkdir(parents=True)
            (scripts.parent/'modules').mkdir()
            for name in ['dev.tfvars', 'dev.s3.tfbackend']:
                (scripts.parent/'modules'/name).write_text('# fixture\n')
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
                'TF_AUTO_APPROVE':auto_approve,
                'TEST_MODE':mode, 'TEST_TRACE':str(trace),
                'TEST_NAT_ENABLED':json.dumps(nat_enabled),
                'TEST_DELETED':str(root/'deleted'), 'TMPDIR':str(root),
            }
            if auto_approve is None:
                env.pop('TF_AUTO_APPROVE')
            result = subprocess.run(['/bin/bash',str(scripts/script)],cwd='/tmp',
                                    env=env,input=confirm if confirm is not None else "",capture_output=True,text=True)
            calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            kubeconfig = scripts.parent/'modules'/'eks_kube_config'/'config'
            result.kubeconfig_path = str(kubeconfig)
            result.kubeconfig_mode = kubeconfig.stat().st_mode & 0o777 if kubeconfig.exists() else None
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
        self.assertFalse(any(c[:3] == ['aws', 'eks', 'update-kubeconfig'] for c in calls))

    def test_create_success(self):
        result,calls = self.run_script('run_infra_create.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(any('apply' in c for c in calls if c[0]=='terraform'))

    def test_kubeconfig_is_created_after_apply_with_private_permissions(self):
        result, calls = self.run_script('run_infra_create.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        update = next(c for c in calls if c[:3] == ['aws', 'eks', 'update-kubeconfig'])
        self.assertEqual(update[3:], [
            '--region', 'ap-southeast-1', '--name', 'dev-eks',
            '--alias', 'dev-eks', '--kubeconfig', result.kubeconfig_path,
        ])
        apply = next(i for i, c in enumerate(calls) if c[0] == 'terraform' and 'apply' in c)
        self.assertGreater(calls.index(update), apply)
        self.assertEqual(result.kubeconfig_mode, 0o600)
        # Evaluate each printed example with a mock kubectl to verify shell quoting
        # for the fixture's path containing spaces, without contacting a cluster.
        for line in result.stdout.splitlines():
            if line.startswith('  kubectl '):
                command = 'kubectl() { printf "%s\\n" "$@"; }; ' + line.strip()
                parsed = subprocess.run(['/bin/bash', '-c', command], capture_output=True, text=True, check=True)
                self.assertEqual(parsed.stdout.splitlines()[:4], [
                    '--kubeconfig', result.kubeconfig_path, '--context', 'dev-eks',
                ])
        self.assertIn('get nodes', result.stdout)
        self.assertIn('get pods -n kube-system', result.stdout)

    def test_kubeconfig_failure_does_not_report_completion_or_rollback(self):
        result, calls = self.run_script('run_infra_create.sh', 'kubeconfig_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('infrastructure has not been rolled back', result.stderr)
        self.assertNotIn('CREATE COMPLETED', result.stdout)
        self.assertNotIn('[PASS] STEP 2', result.stdout)
        self.assertEqual(self.destroys(calls), [])


    def test_destroy_requires_confirmation_by_default(self):
        result,calls = self.run_script('run_infra_destroy.sh', auto_approve='false', confirm='no\n')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.destroys(calls),[])
        self.assertIn('Destroy cancelled.',result.stdout)

    def test_destroy_confirmation_eof_cancels(self):
        result,calls = self.run_script('run_infra_destroy.sh', auto_approve='false')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.destroys(calls),[])

    def test_destroy_confirmation_accepts_exact_keyword(self):
        result,calls = self.run_script('run_infra_destroy.sh', auto_approve='false', confirm='destroy\n')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(self.destroys(calls)),3)

    def test_create_preserves_terraform_confirmation_by_default(self):
        result,calls = self.run_script('run_infra_create.sh', auto_approve=None)
        self.assertEqual(result.returncode,0,result.stderr)
        apply = next(c for c in calls if c[0]=='terraform' and 'apply' in c)
        self.assertNotIn('-auto-approve',apply)

    def test_create_auto_approve_option(self):
        result,calls = self.run_script('run_infra_create.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        apply = next(c for c in calls if c[0]=='terraform' and 'apply' in c)
        self.assertIn('-auto-approve',apply)

    def test_invalid_auto_approve_fails_before_cloud_calls(self):
        result,calls = self.run_script('run_infra_destroy.sh', auto_approve='yes')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(calls,[])
        self.assertIn('must be true or false',result.stderr)

    def test_nat_status_for_both_scripts_and_boolean_values(self):
        for script in ['run_infra_create.sh', 'run_infra_destroy.sh']:
            for enabled in [True, False]:
                with self.subTest(script=script, enabled=enabled):
                    result, calls = self.run_script(script, nat_enabled=enabled)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    status = f'NAT instance enabled: {str(enabled).lower()} (Terraform configuration)'
                    self.assertIn(status, result.stdout)
                    mutation = 'apply' if script == 'run_infra_create.sh' else 'destroy'
                    self.assertLess(result.stdout.index(status), result.stdout.index('STEP 1/'))
                    self.assertTrue(any(mutation in c for c in calls if c[0] == 'terraform'))
                    if script == 'run_infra_create.sh':
                        explanation = 'Verify NAT cloud-init readiness' if enabled else 'NAT creation is disabled'
                        self.assertIn(explanation, result.stdout)
                        if not enabled:
                            self.assertIn('S3 Gateway endpoint alone is insufficient', result.stdout)
                            self.assertIn('this apply can remove it', result.stdout)
                    else:
                        self.assertIn('regardless of this setting', result.stdout)
                        self.assertIn(f'nat_instance_enable={str(enabled).lower()}', result.stdout)
                        self.assertEqual(self.destroys(calls)[-1], '-target=module.ec2_nat_instance')

    def test_nat_context_errors_stop_before_aws_or_mutations(self):
        for script in ['run_infra_create.sh', 'run_infra_destroy.sh']:
            for mode in ['console_failure', 'invalid_nat', 'missing_nat']:
                with self.subTest(script=script, mode=mode):
                    result, calls = self.run_script(script, mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(c[0] == 'aws' for c in calls))
                    self.assertFalse(any('apply' in c or 'destroy' in c for c in calls if c[0] == 'terraform'))
                    self.assertNotIn('COMPLETED', result.stdout)

    def test_state_read_failure_stops_create_and_destroy(self):
        for script in ['run_infra_create.sh', 'run_infra_destroy.sh']:
            with self.subTest(script=script):
                result, calls = self.run_script(script, 'state_failure')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any('apply' in c or 'destroy' in c for c in calls if c[0] == 'terraform'))
                self.assertNotIn('COMPLETED', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
