output "network_name" {
  value       = google_compute_network.default_vpc.name
  description = "Name of the created VPC network."
}

output "subnet_name" {
  value       = google_compute_subnetwork.default_subnet.name
  description = "Name of the created subnet."
}

