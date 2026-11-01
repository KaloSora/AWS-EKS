"""Offline volume cleanup checks; no authentication or external commands."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location(
    "cleanup_eks_storage", Path(__file__).resolve().parents[1] / "cleanup_eks_storage.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
FS = "fs-0123456789abcdef0"


def fixtures():
    classes, pvs, pvcs = [], [], []
    for index, (name, driver) in enumerate(helper.DRIVERS.items()):
        classes.append({"metadata": {"name": name, "annotations": {
            "meta.helm.sh/release-name": "eks-storage-classes",
            "meta.helm.sh/release-namespace": "kube-system"}}, "provisioner": driver})
        pvs.append({"metadata": {"name": f"pv-{index}"}, "spec": {
            "storageClassName": name, "persistentVolumeReclaimPolicy": "Delete",
            "csi": {"driver": driver, "volumeHandle": FS + "::fsap-001" if index else "vol-001"}}})
        pvcs.append({"metadata": {"namespace": f"ns-{index}", "name": "data"},
                     "spec": {"storageClassName": name, "volumeName": f"pv-{index}"}})
    return {"storageclasses": classes, "pv": pvs, "pvc": pvcs, "pods": []}


class FakeKubectl:
    def __init__(self, data=None, failure=None, recreate=False):
        self.data = data if data is not None else fixtures()
        self.calls = []
        self.failure = failure
        self.recreate = recreate

    def __call__(self, *args):
        self.calls.append(args)
        if self.failure and args[:2] == self.failure:
            raise subprocess.CalledProcessError(1, "kubectl")
        if args[0] == "get":
            return {"items": copy.deepcopy(self.data[args[1]])}
        resource, name = args[1:3]
        namespace = args[args.index("--namespace") + 1] if "--namespace" in args else None
        self.data[resource] = [obj for obj in self.data[resource]
            if not (obj["metadata"]["name"] == name
                    and (namespace is None or obj["metadata"].get("namespace") == namespace))]
        if self.recreate and resource == "pv" and not self.data["pv"]:
            self.data["pvc"] = [fixtures()["pvc"][0]]


class CleanupTests(unittest.TestCase):
    def test_deletes_only_selected_claims_then_volumes(self):
        fake = FakeKubectl()
        fake.data["pv"].append({"metadata": {"name": "unrelated"}, "spec": {"storageClassName": "other"}})
        fake.data["pvc"].append({"metadata": {"namespace": "other", "name": "keep"}, "spec": {"storageClassName": "other"}})
        helper.cleanup(fake, FS, 10)
        deletes = [c for c in fake.calls if c[0] == "delete"]
        self.assertEqual([c[1] for c in deletes], ["pvc", "pvc", "pv", "pv"])
        self.assertTrue(all("--timeout=10s" in c and "--wait=true" in c for c in deletes))
        self.assertEqual([obj["metadata"]["name"] for obj in fake.data["pv"]], ["unrelated"])
        self.assertEqual(fake.data["pvc"][0]["metadata"]["name"], "keep")

    def test_active_pod_blocks_all_deletion(self):
        fake = FakeKubectl()
        fake.data["pods"] = [{"metadata": {"namespace": "ns-0", "name": "app"},
            "spec": {"volumes": [{"persistentVolumeClaim": {"claimName": "data"}}]},
            "status": {"phase": "Running"}}]
        with self.assertRaisesRegex(ValueError, "Stop workload"):
            helper.cleanup(fake, FS, 10)
        self.assertFalse(any(c[0] == "delete" for c in fake.calls))

    def test_validation_failures_precede_any_mutation(self):
        for kind in ["retain", "driver", "owner", "foreign_fs", "shared_fs"]:
            with self.subTest(kind=kind):
                fake = FakeKubectl()
                if kind == "retain": fake.data["pv"][0]["spec"]["persistentVolumeReclaimPolicy"] = "Retain"
                if kind == "driver": fake.data["pv"][0]["spec"]["csi"]["driver"] = "unknown"
                if kind == "owner": fake.data["storageclasses"][0]["metadata"]["annotations"] = {}
                if kind == "foreign_fs": fake.data["pv"][1]["spec"]["csi"]["volumeHandle"] = "fs-fffffffffffffffff::fsap-1"
                if kind == "shared_fs": fake.data["pv"][1]["spec"]["storageClassName"] = "other"
                with self.assertRaises(ValueError): helper.cleanup(fake, FS, 10)
                self.assertFalse(any(c[0] == "delete" for c in fake.calls))

    def test_read_error_stops_without_deletion(self):
        fake = FakeKubectl(failure=("get", "pods"))
        with self.assertRaises(subprocess.CalledProcessError): helper.cleanup(fake, FS, 10)
        self.assertFalse(any(c[0] == "delete" for c in fake.calls))

    def test_delete_error_or_timeout_stops_before_pv_deletion(self):
        fake = FakeKubectl(failure=("delete", "pvc"))
        with self.assertRaises(subprocess.CalledProcessError): helper.cleanup(fake, FS, 10)
        self.assertFalse(any(c[:2] == ("delete", "pv") for c in fake.calls))

    def test_recreated_claim_stops_teardown(self):
        fake = FakeKubectl(recreate=True)
        with self.assertRaisesRegex(ValueError, "recreated"):
            helper.cleanup(fake, FS, 10)

    def test_empty_inventory_is_a_noop(self):
        fake = FakeKubectl({key: [] for key in fixtures()})
        helper.cleanup(fake, FS, 10)
        self.assertFalse(any(c[0] == "delete" for c in fake.calls))
