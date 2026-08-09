resource "google_compute_network" "default_vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "default_subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr_range
  region        = var.region
  network       = google_compute_network.default_vpc.self_link
}

resource "google_compute_firewall" "ssh_firewall" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.default_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22", "6443", "10250"]
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

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ubuntu-node"]
}

resource "google_compute_instance" "nodes" {
  count        = var.node_count
  name         = "${var.instance_name_prefix}-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.instance_image
      size  = var.boot_disk_size
    }
  }

  tags = ["ubuntu-node"]

  metadata = var.ssh_public_key != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(var.ssh_public_key))
    } : var.ssh_public_key_path != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(file(var.ssh_public_key_path)))
  } : {}

  network_interface {
    network    = google_compute_network.default_vpc.self_link
    subnetwork = google_compute_subnetwork.default_subnet.self_link
    access_config {}
  }
}