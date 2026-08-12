# GCP-Infra

This repository deploys Ubuntu VMs on Google Cloud Platform with Terraform and installs Kubernetes using Ansible.

## Terraform

1. Update `terraform.tfvars` with your GCP `project`, `region`, `zone`, and other settings.
2. Export your SSH public key via GitHub secret or local path.
3. Run:
   ```bash
   terraform init
   terraform apply -auto-approve
   ```

## Ansible inventory generation

After Terraform deploys the VMs, generate an inventory file from Terraform outputs:

```bash
python3 scripts/terraform_to_ansible_inventory.py \
  --terraform-dir . \
  --output ansible/inventory.ini \
  --ssh-user safal \
  --ssh-key ~/.ssh/id_rsa
```

This will create `ansible/inventory.ini` with the master node in `[kube_master]`, the worker nodes in `[kube_workers]`, and the Keycloak VM in `[keycloak]`.

After deployment, you can access Keycloak securely at `https://<keycloak_load_balancer_ip>`.

> Note: this configuration uses a self-signed certificate by default, so your browser may warn about the certificate trust chain unless you use a real domain and a managed certificate.

## Run Ansible

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml
```

## Notes

- Use the same SSH private key for Ansible that matches the public key injected into the VMs.
- Terraform outputs must include `master_instance_internal_ip`, `worker_instance_internal_ips`, and `keycloak_instance_internal_ip`.
