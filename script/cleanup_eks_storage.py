#!/usr/bin/env python3
"""Remove disposable EKS storage using normal CSI reclamation, never force flags.

Called only after the destroy script's confirmation. Stop workload controllers
first; this helper refuses volumes referenced by non-terminal Pods. All API
failures and bounded deletion timeouts stop the caller before cluster teardown.
"""
import argparse
import json
import subprocess
import sys


DRIVERS = {"ebs-sc": "ebs.csi.aws.com", "efs-sc": "efs.csi.aws.com"}


def inventory(classes, pvs, pvcs, pods, file_system_id):
    for sc in classes:
        name = sc["metadata"]["name"]
        if name in DRIVERS:
            annotations = sc["metadata"].get("annotations", {})
            if (sc.get("provisioner") != DRIVERS[name]
                    or annotations.get("meta.helm.sh/release-name") != "eks-storage-classes"
                    or annotations.get("meta.helm.sh/release-namespace") != "kube-system"):
                raise ValueError(f"StorageClass ownership/provisioner mismatch: {name}")
    volumes = []
    for pv in pvs:
        spec = pv["spec"]
        csi = spec.get("csi", {})
        sc = spec.get("storageClassName")
        same_efs = (file_system_id and csi.get("driver") == "efs.csi.aws.com"
                    and csi.get("volumeHandle", "").split(":")[0] == file_system_id)
        if same_efs and sc not in DRIVERS:
            raise ValueError("Another StorageClass references the EFS being destroyed")
        if sc not in DRIVERS:
            continue
        name = pv["metadata"]["name"]
        if csi.get("driver") != DRIVERS[sc]:
            raise ValueError(f"CSI driver mismatch: {name}")
        if sc == "efs-sc" and (not file_system_id or not same_efs):
            raise ValueError(f"EFS file system does not match Terraform state: {name}")
        if spec.get("persistentVolumeReclaimPolicy") != "Delete":
            raise ValueError(f"PV {name} does not use Delete; review its reclaim policy explicitly")
        volumes.append(name)
    claims = {(p["metadata"]["namespace"], p["metadata"]["name"])
              for p in pvcs if p["spec"].get("storageClassName") in DRIVERS
              or p["spec"].get("volumeName") in volumes}
    for pod in pods:
        if pod.get("status", {}).get("phase") in {"Succeeded", "Failed"}:
            continue
        namespace = pod["metadata"]["namespace"]
        for volume in pod["spec"].get("volumes", []):
            claim = volume.get("persistentVolumeClaim", {}).get("claimName")
            if (namespace, claim) in claims:
                raise ValueError(f"Stop workload using PVC {namespace}/{claim}: Pod {pod['metadata']['name']}")
            csi = volume.get("csi", {})
            if file_system_id and csi.get("driver") == "efs.csi.aws.com":
                raise ValueError("Review inline EFS Pod volumes before destroying the file system")
    return sorted(claims), sorted(volumes)


def cleanup(kubectl, file_system_id, timeout):
    def snapshot():
        return inventory(
            kubectl("get", "storageclasses", "-o", "json")["items"],
            kubectl("get", "pv", "-o", "json")["items"],
            kubectl("get", "pvc", "--all-namespaces", "-o", "json")["items"],
            kubectl("get", "pods", "--all-namespaces", "-o", "json")["items"],
            file_system_id,
        )

    claims, volumes = snapshot()  # Validate the entire inventory before mutating.
    for namespace, name in claims:
        print(f"Deleting disposable PVC: {namespace}/{name}", flush=True)
        kubectl("delete", "pvc", name, "--namespace", namespace,
                "--ignore-not-found=true", "--wait=true", f"--timeout={timeout}s")
    for name in volumes:
        print(f"Waiting for disposable PV and CSI reclamation: {name}", flush=True)
        kubectl("delete", "pv", name, "--ignore-not-found=true",
                "--wait=true", f"--timeout={timeout}s")
    remaining_claims, remaining_volumes = snapshot()
    if remaining_claims or remaining_volumes:
        raise ValueError("Storage was recreated or reclamation is incomplete; stop controllers and retry")
    print("Disposable PV/PVC cleanup completed.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--efs-file-system-id", default="")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    def kubectl(*command):
        result = subprocess.run(
            ["kubectl", "--kubeconfig", args.kubeconfig, "--context", args.context,
             "--request-timeout=30s", *command], check=True, text=True,
            stdout=subprocess.PIPE,
        )
        return json.loads(result.stdout) if command[0] == "get" else None

    try:
        cleanup(kubectl, args.efs_file_system_id, args.timeout)
    except (ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"[ERROR] Storage cleanup stopped: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
