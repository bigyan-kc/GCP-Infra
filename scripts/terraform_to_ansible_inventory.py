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


def build_inventory(names, ips, ssh_user, ssh_key_file, python_interp):
    if len(names) != len(ips):
        raise ValueError("Terraform outputs instance_names and instance_public_ips must have the same length.")
    if len(names) == 0:
        raise ValueError("No instances were found in Terraform outputs.")

    lines = ["[kube_master]"]
    lines.append(f"{names[0]} ansible_host={ips[0]}")
    lines.append("")

    if len(names) > 1:
        lines.append("[kube_workers]")
        for name, ip in zip(names[1:], ips[1:]):
            lines.append(f"{name} ansible_host={ip}")
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
    names = extract_output(outputs, "instance_names")
    ips = extract_output(outputs, "instance_public_ips")

    if names is None or ips is None:
        print(
            "Error: Terraform outputs must include 'instance_names' and 'instance_public_ips'.",
            file=sys.stderr,
        )
        sys.exit(1)

    inventory = build_inventory(names, ips, args.ssh_user, args.ssh_key, args.python_interpreter)
    output_path.write_text(inventory)
    print(f"Wrote Ansible inventory to {output_path}")


if __name__ == "__main__":
    main()
