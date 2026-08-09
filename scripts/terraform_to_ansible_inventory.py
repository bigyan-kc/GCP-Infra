#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


def run_terraform_output(dir_path: Path) -> dict:
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=str(dir_path),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(
            "Error: terraform output failed. Run `terraform apply` first and verify your Terraform configuration.",
            file=sys.stderr,
        )
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print("Error: failed to parse terraform output JSON:", exc, file=sys.stderr)
        sys.exit(1)


def extract_output(outputs: dict, name: str):
    entry = outputs.get(name)
    if entry is None:
        return None
    return entry.get("value")


def build_inventory(master_ip, worker_ips, keycloak_ip, ssh_user, ssh_key_file, python_interp):
    if not master_ip:
        raise ValueError("Terraform output 'master_instance_internal_ip' is required.")
    if worker_ips is None:
        raise ValueError("Terraform output 'worker_instance_internal_ips' is required.")
    if keycloak_ip is None:
        raise ValueError("Terraform output 'keycloak_instance_internal_ip' is required.")

    lines = ["[kube_master]"]
    lines.append(f"kube-master ansible_host={master_ip}")
    lines.append("")

    if worker_ips:
        lines.append("[kube_workers]")
        for i, ip in enumerate(worker_ips, start=1):
            lines.append(f"kube-worker{i} ansible_host={ip}")
        lines.append("")

    lines.append("[keycloak]")
    lines.append(f"keycloak ansible_host={keycloak_ip}")
    lines.append("")

    lines.append("[all:vars]")
    lines.append(f"ansible_user={ssh_user}")
    lines.append(f"ansible_ssh_private_key_file={ssh_key_file}")
    lines.append(f"ansible_python_interpreter={python_interp}")
    lines.append("ansible_become=yes")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an Ansible inventory file from Terraform outputs."
    )
    parser.add_argument(
        "--terraform-dir",
        default=".",
        help="Terraform working directory containing the state and outputs.",
    )
    parser.add_argument(
        "--output",
        default="ansible/inventory.ini",
        help="Path to write the generated Ansible inventory file.",
    )
    parser.add_argument(
        "--ssh-user",
        default="safal",
        help="SSH user for Ansible connections.",
    )
    parser.add_argument(
        "--ssh-key",
        default="~/.ssh/id_rsa",
        help="SSH private key file for Ansible connections.",
    )
    parser.add_argument(
        "--python-interpreter",
        default="/usr/bin/python3",
        help="Python interpreter path on the target hosts.",
    )
    args = parser.parse_args()

    terraform_dir = Path(args.terraform_dir).resolve()
    output_path = Path(args.output).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    outputs = run_terraform_output(terraform_dir)
    master_ip = extract_output(outputs, "master_instance_internal_ip")
    worker_ips = extract_output(outputs, "worker_instance_internal_ips")
    keycloak_ip = extract_output(outputs, "keycloak_instance_internal_ip")

    if master_ip is None or worker_ips is None or keycloak_ip is None:
        print(
            "Error: Terraform outputs must include 'master_instance_internal_ip', 'worker_instance_internal_ips', and 'keycloak_instance_internal_ip'.",
            file=sys.stderr,
        )
        sys.exit(1)

    inventory = build_inventory(master_ip, worker_ips, keycloak_ip, args.ssh_user, args.ssh_key, args.python_interpreter)
    output_path.write_text(inventory)
    print(f"Wrote Ansible inventory to {output_path}")


if __name__ == "__main__":
    main()
