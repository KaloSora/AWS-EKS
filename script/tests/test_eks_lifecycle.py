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
cicd_deleted = marker.with_name('cicd-deleted')
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
        if mode == 'storage_state_failure':
            shows = [json.loads(line) for line in Path(os.environ['TEST_TRACE']).read_text().splitlines()]
            if sum(c[0] == 'terraform' and 'show' in c for c in shows) > 1: sys.exit(2)
        if mode == 'ingress_state_failure':
            shows = [json.loads(line) for line in Path(os.environ['TEST_TRACE']).read_text().splitlines()]
            if sum(c[0] == 'terraform' and 'show' in c for c in shows) >= 3: sys.exit(2)
        if mode == 'app_state_failure':
            shows = [json.loads(line) for line in Path(os.environ['TEST_TRACE']).read_text().splitlines()]
            if sum(c[0] == 'terraform' and 'show' in c for c in shows) >= 4: sys.exit(2)
        if mode == 'cicd_state_failure':
            shows = [json.loads(line) for line in Path(os.environ['TEST_TRACE']).read_text().splitlines()]
            if sum(c[0] == 'terraform' and 'show' in c for c in shows) >= 5: sys.exit(2)
        groups = [] if mode == 'orphan' else [{'type':'aws_eks_node_group','values':{'cluster_name':'dev-eks','node_group_name':'dev-eks-general'}}]
        if mode not in ['storage_untracked', 'absent_cluster', 'absent_cluster_with_ingress', 'absent_cluster_with_aws_lb', 'absent_cluster_with_app', 'absent_cluster_with_cicd', 'absent_cluster_with_karpenter']:
            groups.append({'type':'helm_release', 'address':'module.eks_storage.helm_release.storage_classes'})
        if mode not in ['ingress_untracked', 'absent_cluster', 'absent_cluster_with_aws_lb', 'absent_cluster_with_app', 'absent_cluster_with_cicd', 'absent_cluster_with_karpenter']:
            groups.append({'mode':'managed', 'type':'aws_iam_role', 'address':'module.eks_ingress.aws_iam_role.controller'})
            if mode != 'ingress_iam_only':
                groups.append({'mode':'managed', 'type':'helm_release', 'address':'module.eks_ingress.helm_release.aws_load_balancer_controller'})
        if mode in ['app_tracked', 'app_destroy_failure', 'absent_cluster_with_app']:
            groups.append({'mode':'managed', 'type':'kubernetes_namespace',
                           'address':'module.app.kubernetes_namespace.environment["dev"]'})
        if mode in ['cicd_tracked', 'cicd_partial', 'cicd_destroy_failure',
                    'cicd_lb_pending', 'absent_cluster_with_cicd']:
            groups.append({'mode':'managed', 'type':'kubernetes_namespace',
                           'address':'module.eks_cicd.kubernetes_namespace.component["argocd"]'})
            if mode != 'cicd_partial':
                groups.append({'mode':'managed', 'type':'kubernetes_ingress_v1',
                               'address':'module.eks_cicd.kubernetes_ingress_v1.argocd[0]'})
        if mode in ['cicd_tracked', 'karpenter_destroy_failure', 'absent_cluster_with_karpenter']:
            groups.append({'mode':'managed', 'type':'helm_release',
                           'address':'module.karpenter.helm_release.component[0]'})
        groups.append({'type':'aws_efs_file_system', 'address':'module.eks_efs.aws_efs_file_system.this', 'values':{'id':'fs-0123456789abcdef0'}})
        print(json.dumps({'values':{'root_module':{'child_modules':[{'resources':groups}]}}}))
    elif 'destroy' in args and '-target=module.eks_cicd' in args:
        if mode == 'cicd_destroy_failure': sys.exit(2)
        cicd_deleted.touch()
    elif 'destroy' in args and '-target=module.karpenter' in args:
        if mode == 'karpenter_destroy_failure': sys.exit(2)
    elif 'destroy' in args and '-target=module.app' in args:
        if mode == 'app_destroy_failure': sys.exit(2)
    elif 'destroy' in args and '-target=module.eks_ingress' in args:
        if mode == 'ingress_destroy_failure': sys.exit(2)
    elif 'destroy' in args and '-target=module.eks_efs' in args:
        if mode == 'efs_destroy_failure': sys.exit(2)
    elif 'destroy' in args and '-target=module.eks_storage' in args:
        if mode == 'storage_destroy_failure': sys.exit(2)
    elif 'destroy' in args and '-target=module.eks.aws_eks_node_group.this' in args:
        if mode == 'terraform_failure': sys.exit(2)
        marker.touch()
    elif 'apply' in args and mode == 'karpenter_apply_failure' and '-target=module.karpenter' in args:
        sys.exit(2)
    elif 'apply' in args and mode == 'cicd_apply_failure' and '-target=module.eks_cicd' in args:
        sys.exit(2)
    elif 'apply' in args and mode == 'app_apply_failure' and '-target=module.app' in args:
        sys.exit(2)
    elif 'apply' in args and mode == 'ingress_apply_failure' and '-target=module.eks_ingress' in args:
        sys.exit(2)
    elif 'apply' in args and mode == 'storage_apply_failure' and '-target=module.eks_storage' in args:
        sys.exit(2)
    elif 'apply' in args and mode == 'apply_failure':
        sys.exit(2)
elif kind == 'kubectl':
    if 'api-resources' in args:
        if mode == 'ingress_discovery_failure': sys.exit(2)
        if mode != 'ingress_crd_absent': print('targetgroupbindings.elbv2.k8s.aws')
    elif 'get' in args:
        resource = args[args.index('get') + 1]
        if mode == 'cleanup_failure' and resource == 'storageclasses': sys.exit(2)
        if resource == 'ingresses.networking.k8s.io,services':
            if mode == 'ingress_query_failure': sys.exit(2)
            if mode == 'ingress_invalid_json': print('{}'); sys.exit(0)
            items = []
            if mode == 'cicd_tracked' and not cicd_deleted.exists():
                items = [{'kind':'Ingress','metadata':{'namespace':'argocd','name':'argocd'}}]
            if mode == 'remaining_ingress':
                items = [{'kind':'Ingress','metadata':{'namespace':'app','name':'web'}}]
            if mode == 'remaining_lb_service':
                items = [{'kind':'Service','metadata':{'namespace':'app','name':'web'},'spec':{'type':'LoadBalancer'}}]
            if mode == 'ordinary_service':
                items = [{'kind':'Service','metadata':{'namespace':'app','name':'web'},'spec':{'type':'ClusterIP'}}]
            print(json.dumps({'items':items}))
        elif resource == 'targetgroupbindings.elbv2.k8s.aws':
            if mode == 'tgb_query_failure': sys.exit(2)
            items = [{'metadata':{'namespace':'app','name':'web'}}] if mode == 'remaining_tgb' else []
            print(json.dumps({'items':items}))
        else:
            print(json.dumps({'items':[]}))
    else:
        raise AssertionError(args)
elif kind == 'aws':
    if args[:2] == ['resourcegroupstaggingapi','get-resources']:
        assert 'Key=elbv2.k8s.aws/cluster,Values=dev-eks' in args
        assert 'elasticloadbalancing:loadbalancer' in args
        assert 'elasticloadbalancing:targetgroup' in args
        assert '--no-paginate' not in args
        if mode == 'ingress_aws_failure': sys.exit(254)
        if mode == 'ingress_aws_invalid_json': print('{}'); sys.exit(0)
        remaining = ['arn:aws:elasticloadbalancing:ap-southeast-1:123456789012:loadbalancer/app/web/fixture'] if mode in ['remaining_aws_lb', 'absent_cluster_with_aws_lb', 'cicd_lb_pending'] else []
        print(json.dumps(remaining))
    elif args[:2] == ['eks','describe-cluster']:
        if mode == 'cluster_lookup_failure': sys.exit(254)
        if mode.startswith('absent_cluster'):
            print('An error occurred (ResourceNotFoundException)', file=sys.stderr)
            sys.exit(254)
        print('dev-eks')
    elif args[:2] == ['eks','list-nodegroups']:
        if mode == 'access_denied':
            print('An error occurred (AccessDeniedException)', file=sys.stderr)
            sys.exit(254)
        if mode.startswith('absent_cluster'):
            print('An error occurred (ResourceNotFoundException)', file=sys.stderr)
            sys.exit(254)
        groups = [] if marker.exists() and mode != 'lingering' else ['dev-eks-general']
        print(json.dumps({'nodegroups':groups}))
    elif args[:3] == ['eks','wait','nodegroup-deleted']:
        if mode == 'wait_failure': sys.exit(255)
    elif args[:2] == ['eks','update-kubeconfig']:
        if mode in ['kubeconfig_failure', 'absent_cluster_with_storage']: sys.exit(2)
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
            for name in [script, 'eks_lifecycle.sh', 'cleanup_eks_storage.py']:
                shutil.copy2(SCRIPT_DIR/name, scripts/name)
            # This replaces the authentication script; no real auth file is read.
            (scripts/'run_aws_auth.sh').write_text('return 0\n')
            binaries = root/'bin'
            binaries.mkdir()
            for name in ['terraform','aws','kubectl']:
                p = binaries/name
                p.write_text(f'#!{sys.executable}\n'+MOCK)
                p.chmod(0o755)
            (binaries/'python3').symlink_to(sys.executable)
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
                                    env=env,input=confirm if confirm is not None else ("destroy\n" if auto_approve == "true" else ""),capture_output=True,text=True)
            calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            kubeconfig = scripts.parent/'modules'/'eks_kubeconfig'/'config'
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
            '-target=module.eks_ingress', '-target=module.eks_storage', '-target=module.eks_efs', '-target=module.eks.aws_eks_node_group.this',
            '-target=module.eks','-target=module.ec2_nat_instance'])
        wait = next(i for i,c in enumerate(calls) if c[:4]==['aws','eks','wait','nodegroup-deleted'])
        cluster = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks' in c)
        self.assertLess(wait,cluster)
        update = next(i for i,c in enumerate(calls) if c[:3] == ['aws','eks','update-kubeconfig'])
        storage = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks_storage' in c)
        ingress = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks_ingress' in c)
        inventory = next(i for i,c in enumerate(calls) if c[:2] == ['aws','resourcegroupstaggingapi'])
        self.assertLess(update, inventory)
        self.assertLess(inventory, ingress)
        self.assertLess(ingress, storage)
        self.assertLess(update,storage)
        self.assertLess(storage,wait)
        cleanup = [i for i,c in enumerate(calls) if c[0] == 'kubectl']
        efs = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks_efs' in c)
        nodes = next(i for i,c in enumerate(calls) if 'destroy' in c and '-target=module.eks.aws_eks_node_group.this' in c)
        self.assertTrue(cleanup)
        self.assertLess(max(cleanup), storage)
        self.assertLess(storage, efs)
        self.assertLess(efs, nodes)

    def test_volume_cleanup_failure_preserves_storage_nodes_and_nat(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'cleanup_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress'])
        self.assertIn('Storage cleanup stopped', result.stderr)
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_efs_destroy_failure_preserves_nodes_cluster_and_nat(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'efs_destroy_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress', '-target=module.eks_storage', '-target=module.eks_efs'])
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_cluster_lookup_failure_preserves_all_resources(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'cluster_lookup_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), [])

    def test_untracked_group_blocks_all_destruction(self):
        result,calls = self.run_script('run_infra_destroy.sh','orphan')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),[])
        self.assertIn('missing from the current Terraform state',result.stderr)

    def test_wait_failure_preserves_cluster_roles_and_nat(self):
        result,calls = self.run_script('run_infra_destroy.sh','wait_failure')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks_ingress', '-target=module.eks_storage', '-target=module.eks_efs', '-target=module.eks.aws_eks_node_group.this'])

    def test_lingering_groups_preserve_cluster_roles_and_nat(self):
        result,calls = self.run_script('run_infra_destroy.sh','lingering')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks_ingress', '-target=module.eks_storage', '-target=module.eks_efs', '-target=module.eks.aws_eks_node_group.this'])

    def test_nodegroup_destroy_failure_stops_script(self):
        result,calls = self.run_script('run_infra_destroy.sh','terraform_failure')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),['-target=module.eks_ingress', '-target=module.eks_storage', '-target=module.eks_efs', '-target=module.eks.aws_eks_node_group.this'])
        self.assertNotIn('[PASS] STEP 8',result.stdout)

    def test_access_denied_is_not_treated_as_missing_cluster(self):
        result,calls = self.run_script('run_infra_destroy.sh','access_denied')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.destroys(calls),[])

    def test_missing_cluster_allows_remaining_cleanup(self):
        result,calls = self.run_script('run_infra_destroy.sh','absent_cluster')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(self.destroys(calls)),4)

    def test_app_destroy_follows_volume_cleanup_and_precedes_storage(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'app_tracked')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destroys(calls), [
            '-target=module.eks_ingress', '-target=module.app',
            '-target=module.eks_storage', '-target=module.eks_efs',
            '-target=module.eks.aws_eks_node_group.this', '-target=module.eks',
            '-target=module.ec2_nat_instance',
        ])
        app = next(i for i, c in enumerate(calls) if 'destroy' in c and '-target=module.app' in c)
        cleanup = [i for i, c in enumerate(calls) if c[0] == 'kubectl']
        self.assertLess(max(cleanup), app)
        self.assertIn('all resources inside app namespaces', result.stdout)

    def test_app_destroy_failure_stops_before_storage_nodes_and_nat(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'app_destroy_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress', '-target=module.app'])
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_app_state_failure_and_absent_cluster_block_teardown(self):
        for mode in ['app_state_failure', 'absent_cluster_with_app']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destroys(calls), [])
                self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_app_apply_failure_stops_without_rollback_or_completion(self):
        result, calls = self.run_script('run_infra_create.sh', 'app_apply_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Application namespace apply failed', result.stderr)
        self.assertNotIn('CREATE COMPLETED', result.stdout)
        self.assertNotIn('[PASS] STEP 5', result.stdout)
        self.assertEqual(self.destroys(calls), [])

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
        targets = [next(arg for arg in c if arg.startswith('-target='))
                   for c in calls if c[0] == 'terraform' and 'apply' in c]
        self.assertEqual(targets, [
            '-target=module.eks', '-target=module.eks_storage', '-target=module.eks_ingress',
            '-target=module.app', '-target=module.karpenter', '-target=module.eks_cicd',
        ])
        update = next(i for i, c in enumerate(calls) if c[:3] == ['aws', 'eks', 'update-kubeconfig'])
        storage = next(i for i, c in enumerate(calls) if 'apply' in c and '-target=module.eks_storage' in c)
        self.assertLess(update, storage)
        ingress = next(i for i,c in enumerate(calls) if 'apply' in c and '-target=module.eks_ingress' in c)
        self.assertLess(storage, ingress)

    def test_cicd_apply_failure_stops_without_rollback_or_completion(self):
        result, calls = self.run_script('run_infra_create.sh', 'cicd_apply_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CI/CD apply failed', result.stderr)
        self.assertNotIn('CREATE COMPLETED', result.stdout)
        self.assertEqual(self.destroys(calls), [])

    def test_destroy_cicd_before_ingress_inventory_and_controller(self):
        for mode in ['cicd_tracked', 'cicd_partial']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.destroys(calls)[:2], ['-target=module.eks_cicd', '-target=module.eks_ingress'])
                kubeconfig = next(i for i, call in enumerate(calls) if call[:3] == ['aws', 'eks', 'update-kubeconfig'])
                cicd = next(i for i, call in enumerate(calls) if '-target=module.eks_cicd' in call)
                inventory = next(i for i, call in enumerate(calls) if call[:2] == ['aws', 'resourcegroupstaggingapi'])
                controller = next(i for i, call in enumerate(calls) if '-target=module.eks_ingress' in call)
                self.assertLess(kubeconfig, cicd)
                self.assertLess(cicd, inventory)
                self.assertLess(inventory, controller)
                targets = self.destroys(calls)
                if mode == 'cicd_tracked':
                    self.assertEqual(targets[2:5], [
                        '-target=module.karpenter', '-target=module.eks_storage', '-target=module.eks_efs',
                    ])
                else:
                    self.assertNotIn('-target=module.karpenter', targets)

    def test_karpenter_apply_failure_stops_before_cicd(self):
        result, calls = self.run_script('run_infra_create.sh', 'karpenter_apply_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Karpenter apply failed', result.stderr)
        self.assertFalse(any('apply' in call and '-target=module.eks_cicd' in call for call in calls))
        self.assertNotIn('CREATE COMPLETED', result.stdout)

    def test_karpenter_cleanup_failure_preserves_dependencies(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'karpenter_destroy_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress', '-target=module.karpenter'])
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_cicd_destroy_failure_or_pending_alb_preserves_controller_and_cluster(self):
        for mode in ['cicd_destroy_failure', 'cicd_lb_pending']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destroys(calls), ['-target=module.eks_cicd'])
                self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_cicd_state_failure_or_absent_cluster_stops_teardown(self):
        for mode in ['cicd_state_failure', 'absent_cluster_with_cicd', 'absent_cluster_with_karpenter']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destroys(calls), [])
                self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_storage_apply_failure_stops_without_rollback_or_completion(self):
        result, calls = self.run_script('run_infra_create.sh', 'storage_apply_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Storage apply failed', result.stderr)
        self.assertNotIn('CREATE COMPLETED', result.stdout)
        self.assertNotIn('[PASS] STEP 3', result.stdout)
        self.assertEqual(self.destroys(calls), [])

    def test_storage_destroy_failure_preserves_nodes_cluster_and_nat(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'storage_destroy_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress', '-target=module.eks_storage'])
        self.assertNotIn('DESTROY COMPLETED', result.stdout)
        self.assertFalse(any(c[:4] == ['aws', 'eks', 'wait', 'nodegroup-deleted'] for c in calls))

    def test_destroy_kubeconfig_failure_stops_before_mutations(self):
        for mode in ['kubeconfig_failure', 'absent_cluster_with_storage']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destroys(calls), [])
                self.assertIn('No destroy step has run', result.stderr)
                self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_destroy_skips_untracked_release_but_still_checks_volumes(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'storage_untracked')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destroys(calls), [
            '-target=module.eks_ingress', '-target=module.eks_efs', '-target=module.eks.aws_eks_node_group.this', '-target=module.eks',
            '-target=module.ec2_nat_instance',
        ])
        self.assertTrue(any(c[:3] == ['aws', 'eks', 'update-kubeconfig'] for c in calls))

    def test_storage_state_read_failure_stops_before_destroy(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'storage_state_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), [])
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_auto_approval_still_requires_destroy_confirmation(self):
        for confirm in ['', 'no\n']:
            with self.subTest(confirm=confirm):
                result, calls = self.run_script('run_infra_destroy.sh', confirm=confirm)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.destroys(calls), [])
                self.assertFalse(any(c[:3] == ['aws', 'eks', 'update-kubeconfig'] for c in calls))
                self.assertIn('Destroy cancelled.', result.stdout)

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
        self.assertEqual(len(self.destroys(calls)),6)

    def test_create_preserves_terraform_confirmation_by_default(self):
        result,calls = self.run_script('run_infra_create.sh', auto_approve=None)
        self.assertEqual(result.returncode,0,result.stderr)
        applies = [c for c in calls if c[0]=='terraform' and 'apply' in c]
        self.assertEqual(len(applies), 6)
        self.assertTrue(all('-auto-approve' not in c for c in applies))

    def test_create_auto_approve_option(self):
        result,calls = self.run_script('run_infra_create.sh')
        self.assertEqual(result.returncode,0,result.stderr)
        applies = [c for c in calls if c[0]=='terraform' and 'apply' in c]
        self.assertEqual(len(applies), 6)
        self.assertTrue(all('-auto-approve' in c for c in applies))

    def test_invalid_auto_approve_fails_before_cloud_calls(self):
        result,calls = self.run_script('run_infra_destroy.sh', auto_approve='yes')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(calls,[])
        self.assertIn('must be true or false',result.stderr)

    def test_ingress_apply_failure_stops_without_rollback_or_completion(self):
        result, calls = self.run_script('run_infra_create.sh', 'ingress_apply_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Ingress Controller apply failed', result.stderr)
        self.assertNotIn('CREATE COMPLETED', result.stdout)
        self.assertNotIn('[PASS] STEP 4', result.stdout)
        self.assertEqual(self.destroys(calls), [])

    def test_ingress_destroy_failure_preserves_storage_nodes_and_nat(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'ingress_destroy_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destroys(calls), ['-target=module.eks_ingress'])
        self.assertFalse(any(c[0] == 'kubectl' and 'pv' in c for c in calls))
        self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_ingress_cleanup_errors_stop_before_any_teardown(self):
        modes = ['remaining_ingress', 'remaining_lb_service', 'remaining_tgb',
                 'remaining_aws_lb', 'ingress_query_failure', 'tgb_query_failure',
                 'ingress_discovery_failure', 'ingress_aws_failure',
                 'ingress_invalid_json', 'ingress_aws_invalid_json', 'ingress_state_failure']
        for mode in modes:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.destroys(calls), [])
                self.assertFalse(any(c[0] == 'kubectl' and 'delete' in c for c in calls))
                self.assertNotIn('DESTROY COMPLETED', result.stdout)

    def test_ingress_iam_only_partial_apply_is_cleaned(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'ingress_iam_only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.destroys(calls)[0], '-target=module.eks_ingress')

    def test_untracked_ingress_module_is_skipped_after_inventory(self):
        result, calls = self.run_script('run_infra_destroy.sh', 'ingress_untracked')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('-target=module.eks_ingress', self.destroys(calls))
        self.assertTrue(any(c[:2] == ['aws','resourcegroupstaggingapi'] for c in calls))

    def test_absent_tgb_crd_and_ordinary_service_do_not_block_cleanup(self):
        for mode in ['ingress_crd_absent', 'ordinary_service']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                if mode == 'ingress_crd_absent':
                    self.assertFalse(any('targetgroupbindings.elbv2.k8s.aws' in c for c in calls))

    def test_destroy_default_auto_approve_is_false_and_cancellation_is_preserved(self):
        result, calls = self.run_script('run_infra_destroy.sh', auto_approve=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Auto approve       : false', result.stdout)
        self.assertIn('Destroy cancelled.', result.stdout)
        self.assertEqual(self.destroys(calls), [])

    def test_absent_cluster_with_ingress_or_aws_residue_stops_cleanup(self):
        for mode in ['absent_cluster_with_ingress', 'absent_cluster_with_aws_lb', 'absent_cluster_with_app']:
            with self.subTest(mode=mode):
                result, calls = self.run_script('run_infra_destroy.sh', mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destroys(calls), [])
                self.assertNotIn('DESTROY COMPLETED', result.stdout)
                self.assertFalse(any(c[0] == 'kubectl' for c in calls))

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
