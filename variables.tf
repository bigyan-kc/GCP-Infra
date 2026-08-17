variable "project" {
  type        = string
  description = "GCP project ID where resources will be created."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region for regional resources."
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "GCP zone for zonal resources."
}

variable "credentials_file" {
  type        = string
  default     = ""
  description = "Path to a GCP service account JSON key file. Leave blank to use gcloud or environment credentials."
}

variable "network_name" {
  type        = string
  default     = "tf-gcp-network"
  description = "Name of the VPC network."
}

variable "subnet_name" {
  type        = string
  default     = "tf-private-subnet"
  description = "Name of the private subnet for Kubernetes nodes."
}

variable "subnet_cidr_range" {
  type        = string
  default     = "10.0.0.0/24"
  description = "CIDR range for the private subnet."
}

variable "public_subnet_name" {
  type        = string
  default     = "tf-public-subnet"
  description = "Name of the public subnet for the bastion host."
}

variable "public_subnet_cidr_range" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR range for the public subnet."
}

variable "bastion_machine_type" {
  type        = string
  default     = "e2-small"
  description = "Machine type for the bastion host."
}

variable "keycloak_machine_type" {
  type        = string
  default     = "e2-small"
  description = "Machine type for the Keycloak identity provider VM."
}

variable "keycloak_domain_name" {
  type        = string
  default     = ""
  description = "Optional domain name for Keycloak HTTPS load balancer. If set, this will be used in the self-signed certificate Subject Alternative Name."
}

variable "instance_name" {
  type        = string
  default     = "tf-web-server"
  description = "Name of the compute instance."
}

variable "machine_type" {
  type        = string
  default     = "e2-small"
  description = "Machine type for the VM instance."
}

variable "instance_image" {
  type        = string
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
  description = "Boot disk image for the compute instance."
}

variable "ssh_username" {
  type        = string
  default     = "safal"
  description = "Username for the SSH key that will be injected into the instance metadata."
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "SSH public key content injected into instance metadata. Use this for CI secrets."
}

variable "ssh_public_key_path" {
  type        = string
  default     = ""
  description = "Path to the local SSH public key file to inject into instance metadata."
}

variable "instance_name_prefix" {
  type        = string
  default     = "tf-ubuntu"
  description = "Prefix used for naming the Ubuntu VM instances."
}

variable "node_count_worker" {
  type        = number
  default     = 1
  description = "Number of Kubernetes worker nodes to create."
}

variable "boot_disk_size" {
  type        = number
  default     = 20
  description = "Boot disk size in GB for each VM instance."
}

variable "keycloak_disk_create" {
  type        = bool
  default     = false
  description = "If true, Terraform will create a new PD for Keycloak. If false, set keycloak_disk_name to an existing disk."
}

variable "keycloak_disk_name" {
  type        = string
  default     = ""
  description = "Name of an existing GCE persistent disk to attach to the Keycloak VM when keycloak_disk_create is false."
}

variable "api_allowed_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR ranges allowed to access the Kubernetes API LB. Restrict this to your laptop IPs in production."
}
