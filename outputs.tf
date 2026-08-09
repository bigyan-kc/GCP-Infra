output "network_name" {
  value       = google_compute_network.default_vpc.name
  description = "Name of the created VPC network."
}

output "subnet_name" {
  value       = google_compute_subnetwork.default_subnet.name
  description = "Name of the created subnet."
}

output "master_instance_names" {
  value       = [google_compute_instance.master.name]
  description = "Names of the created master VM instance."
}

output "master_instance_public_ip" {
  value       = google_compute_instance.master.network_interface[0].access_config[0].nat_ip
  description = "Public IP address of the master VM instance."
}

output "master_instance_internal_ip" {
  value       = google_compute_instance.master.network_interface[0].network_ip
  description = "Internal IP address of the master VM instance."
}


output "worker_instance_public_ips" {
  value       = [for instance in google_compute_instance.worker : instance.network_interface[0].access_config[0].nat_ip]
  description = "Public IP addresses of the worker VM instances."
}

output "worker_instance_internal_ips" {
  value       = [for instance in google_compute_instance.worker : instance.network_interface[0].network_ip]
  description = "Internal IP addresses of the worker VM instances."
}

output "bastion_public_ip" {
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
  description = "Public IP address of the bastion host."
}



