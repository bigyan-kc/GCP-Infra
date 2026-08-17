resource "google_compute_network" "default_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr_range
  region        = var.region
  network       = google_compute_network.default_vpc.self_link
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = var.public_subnet_name
  ip_cidr_range = var.public_subnet_cidr_range
  region        = var.region
  network       = google_compute_network.default_vpc.self_link
}

resource "google_compute_router" "nat_router" {
  name    = "${var.network_name}-nat-router"
  network = google_compute_network.default_vpc.self_link
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_firewall" "ssh_firewall" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]
}

resource "google_compute_firewall" "kube_firewall" {
  name    = "${var.network_name}-allow-kube"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["6443", "10250"]
  }

  allow {
    protocol = "udp"
    ports = [
      "8472" # Calico VXLAN
    ]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
  target_tags   = ["ubuntu-node"]
}

resource "google_compute_firewall" "internal_ssh" {
  name    = "${var.network_name}-allow-internal-ssh"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.public_subnet_cidr_range]
  target_tags   = ["ubuntu-node", "keycloak"]
}

resource "google_compute_firewall" "keycloak_http" {
  name    = "${var.network_name}-allow-keycloak"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["keycloak"]
}


resource "google_compute_firewall" "k8s_api_allow" {
  name    = "${var.instance_name_prefix}-allow-k8s-api"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = var.api_allowed_cidrs
  target_tags   = ["ubuntu-node"]
}