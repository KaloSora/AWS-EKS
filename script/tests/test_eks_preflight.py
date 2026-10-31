"""Exercise the actual precondition resource with offline AWS-response fixtures."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]


class PreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.terraform = shutil.which('terraform')
        if not cls.terraform:
            raise unittest.SkipTest('Terraform CLI is required')
        cls.tmp = tempfile.TemporaryDirectory(prefix='eks preflight test ')
        cls.root = Path(cls.tmp.name)
        source = (PROJECT/'modules/eks_preflight.tf').read_text()
        resource = source[source.index('resource "terraform_data" "eks_preflight"'):]
        resource = resource.replace('data.aws_ec2_instance_types.eks_compatible.instance_types', 'var.compatible_types')
        (cls.root/'main.tf').write_text('''variable "eks_node_instance_types" { type = list(string) }
variable "compatible_types" { type = list(string) }
'''+resource)
        cls.env = {'PATH':'/usr/bin:/bin','CHECKPOINT_DISABLE':'1','TF_IN_AUTOMATION':'1'}
        result = subprocess.run([cls.terraform,f'-chdir={cls.root}','init','-backend=false','-no-color'],
                                env=cls.env,capture_output=True,text=True)
        if result.returncode:
            raise RuntimeError(result.stdout+result.stderr)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls,'tmp'):
            cls.tmp.cleanup()

    def check_plan(self, selected, compatible, success):
        result = subprocess.run([self.terraform,f'-chdir={self.root}','plan','-refresh=false',
            '-input=false','-no-color','-var=eks_node_instance_types='+json.dumps(selected),
            '-var=compatible_types='+json.dumps(compatible)],env=self.env,capture_output=True,text=True)
        if success:
            self.assertEqual(result.returncode,0,result.stderr)
        else:
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Resource precondition failed',result.stderr)

    def test_compatible_types_pass(self):
        self.check_plan(['t3.small'],['t3.small'],True)

    def test_rejected_type_fails(self):
        self.check_plan(['t3.medium'],[],False)

    def test_one_invalid_choice_rejects_entire_list(self):
        self.check_plan(['t3.small','t3.medium'],['t3.small'],False)

    def test_empty_selection_fails(self):
        self.check_plan([],[],False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
