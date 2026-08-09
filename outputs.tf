output "network_name" {
  value       = google_compute_network.default_vpc.name
  description = "Name of the created VPC network."
}

output "subnet_name" {
  value       = google_compute_subnetwork.default_subnet.name
  description = "Name of the created subnet."
}

output "instance_names" {
  value = [for instance in google_compute_instance.nodes : instance.name]
  description = "Names of the created Ubuntu VM instances."
}

output "instance_public_ips" {
  value = [for instance in google_compute_instance.nodes : instance.network_interface[0].access_config[0].nat_ip]
  description = "Public IP addresses of the created VM instances."
}

output "instance_internal_ips" {
  value = [for instance in google_compute_instance.nodes : instance.network_interface[0].network_ip]
  description = "Internal IP addresses of the created VM instances."
}

