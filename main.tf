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

resource "google_compute_address" "keycloak_lb_ip" {
  name   = "${var.instance_name_prefix}-keycloak-lb-ip"
  region = var.region
}

resource "google_compute_http_health_check" "keycloak" {
  name                = "${var.instance_name_prefix}-keycloak-health-check"
  request_path        = "/"
  port                = 8080
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
}

resource "google_compute_target_pool" "keycloak" {
  name          = "${var.instance_name_prefix}-keycloak-pool"
  region        = var.region
  health_checks = [google_compute_http_health_check.keycloak.self_link]
  instances     = [google_compute_instance.keycloak.self_link]
}

resource "google_compute_forwarding_rule" "keycloak" {
  name                  = "${var.instance_name_prefix}-keycloak-lb"
  region                = var.region
  ip_address            = google_compute_address.keycloak_lb_ip.address
  port_range            = "8080"
  target                = google_compute_target_pool.keycloak.self_link
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}

resource "google_compute_instance" "bastion" {
  name         = "${var.instance_name_prefix}-bastion"
  machine_type = var.bastion_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.instance_image
      size  = var.boot_disk_size
    }
  }

  tags = ["bastion"]

  metadata = var.ssh_public_key != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(var.ssh_public_key))
    } : var.ssh_public_key_path != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(file(var.ssh_public_key_path)))
  } : {}

  network_interface {
    network    = google_compute_network.default_vpc.self_link
    subnetwork = google_compute_subnetwork.public_subnet.self_link
    access_config {}
  }
}

resource "google_compute_instance" "master" {
  name         = "${var.instance_name_prefix}-master"
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
    subnetwork = google_compute_subnetwork.private_subnet.self_link
  }
}

resource "google_compute_instance" "keycloak" {
  name         = "${var.instance_name_prefix}-keycloak"
  machine_type = var.keycloak_machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = var.instance_image
      size  = var.boot_disk_size
    }
  }

  tags = ["keycloak"]

  metadata = var.ssh_public_key != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(var.ssh_public_key))
    } : var.ssh_public_key_path != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(file(var.ssh_public_key_path)))
  } : {}

  network_interface {
    network    = google_compute_network.default_vpc.self_link
    subnetwork = google_compute_subnetwork.private_subnet.self_link
  }
}

resource "google_compute_instance" "worker" {
  count        = var.node_count_worker
  name         = "${var.instance_name_prefix}-worker-${count.index + 1}"
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
    subnetwork = google_compute_subnetwork.private_subnet.self_link
  }
}