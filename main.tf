
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

resource "google_compute_global_address" "keycloak_lb_ip" {
  name = "${var.instance_name_prefix}-keycloak-lb-ip"
}

resource "google_compute_health_check" "keycloak" {
  name                = "${var.instance_name_prefix}-keycloak-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 8080
    request_path = "/"
  }
}

resource "google_compute_instance_group" "keycloak" {
  name      = "${var.instance_name_prefix}-keycloak-ig"
  zone      = var.zone
  network   = google_compute_network.default_vpc.self_link
  instances = [google_compute_instance.keycloak.self_link]
  named_port {
    name = "http"
    port = 8080
  }
}

resource "google_compute_backend_service" "keycloak" {
  name          = "${var.instance_name_prefix}-keycloak-backend"
  protocol      = "HTTP"
  port_name     = "http"
  timeout_sec   = 30
  enable_cdn    = false
  health_checks = [google_compute_health_check.keycloak.self_link]
  backend {
    group = google_compute_instance_group.keycloak.self_link
  }
}

resource "google_compute_url_map" "keycloak" {
  name            = "${var.instance_name_prefix}-keycloak-urlmap"
  default_service = google_compute_backend_service.keycloak.self_link
}

resource "tls_private_key" "keycloak_lb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "keycloak_lb" {
  subject {
    common_name = var.keycloak_domain_name != "" ? var.keycloak_domain_name : "localhost"
  }

  validity_period_hours = 8760
  early_renewal_hours   = 720
  allowed_uses = [
    "server_auth",
    "key_encipherment",
    "digital_signature",
  ]
  private_key_pem = tls_private_key.keycloak_lb.private_key_pem
}

resource "google_compute_ssl_certificate" "keycloak" {
  name        = "${var.instance_name_prefix}-keycloak-ssl-cert"
  private_key = tls_private_key.keycloak_lb.private_key_pem
  certificate = tls_self_signed_cert.keycloak_lb.cert_pem
}

resource "google_compute_target_https_proxy" "keycloak" {
  name             = "${var.instance_name_prefix}-keycloak-proxy"
  url_map          = google_compute_url_map.keycloak.self_link
  ssl_certificates = [google_compute_ssl_certificate.keycloak.self_link]
}

resource "google_compute_global_forwarding_rule" "keycloak" {
  name                  = "${var.instance_name_prefix}-keycloak-lb"
  ip_address            = google_compute_global_address.keycloak_lb_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.keycloak.self_link
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}

resource "google_compute_disk" "keycloak_data" {
  count = var.keycloak_disk_create ? 1 : 0
  name  = "${var.instance_name_prefix}-keycloak-data"
  type  = "pd-ssd"
  zone  = var.zone
  size  = 50
}

data "google_compute_disk" "existing_keycloak" {
  count = var.keycloak_disk_create ? 0 : (var.keycloak_disk_name != "" ? 1 : 0)
  name  = var.keycloak_disk_name
  zone  = var.zone
}

locals {
  keycloak_disk_self_link = var.keycloak_disk_create ? google_compute_disk.keycloak_data[0].self_link : (var.keycloak_disk_name != "" ? data.google_compute_disk.existing_keycloak[0].self_link : "")
  keycloak_disk_name      = var.keycloak_disk_create ? google_compute_disk.keycloak_data[0].name : var.keycloak_disk_name
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

  attached_disk {
    source      = local.keycloak_disk_self_link
    device_name = "keycloak-data"
    mode        = "READ_WRITE"
  }

  tags = ["keycloak"]

  metadata = var.ssh_public_key != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(var.ssh_public_key))
    } : var.ssh_public_key_path != "" ? {
    ssh-keys = format("%s:%s", var.ssh_username, trimspace(file(var.ssh_public_key_path)))
  } : {}

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -eux
    DISK_NAME="${local.keycloak_disk_name}"
    if [ -z "${local.keycloak_disk_name}" ]; then
      echo "No disk name provided; skipping mount script"
      exit 0
    fi

    # Attempt to find the device under /dev/disk/by-id
    DEVICE_PATH=""
    if [ -e /dev/disk/by-id/google-${local.keycloak_disk_name} ]; then
      DEVICE_PATH=$(readlink -f /dev/disk/by-id/google-${local.keycloak_disk_name})
    else
      # fallback: find any by-id entry that contains the disk name
      ENTRY=$(ls -1 /dev/disk/by-id | grep "${local.keycloak_disk_name}" | head -n1 || true)
      if [ -n "$ENTRY" ]; then
        DEVICE_PATH=$(readlink -f /dev/disk/by-id/$ENTRY)
      fi
    fi

    if [ -z "$DEVICE_PATH" ]; then
      echo "Disk device for $DISK_NAME not found; exiting"
      exit 0
    fi

    if ! blkid "$DEVICE_PATH" >/dev/null 2>&1; then
      mkfs.ext4 -F "$DEVICE_PATH"
    fi

    mkdir -p /opt/keycloak/data
    if ! mountpoint -q /opt/keycloak/data; then
      mount "$DEVICE_PATH" /opt/keycloak/data
    fi
    chown -R 1000:0 /opt/keycloak/data || true

    UUID=$(blkid -s UUID -o value "$DEVICE_PATH") || true
    if [ -n "$UUID" ] && ! grep -q "$UUID" /etc/fstab; then
      echo "UUID=$UUID /opt/keycloak/data ext4 defaults 0 2" >> /etc/fstab
    fi
  EOF

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