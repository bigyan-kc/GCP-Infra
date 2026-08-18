resource "google_compute_ssl_certificate" "keycloak" {
  name        = "${var.instance_name_prefix}-keycloak-ssl-cert"
  private_key = tls_private_key.keycloak_lb.private_key_pem
  certificate = tls_self_signed_cert.keycloak_lb.cert_pem
}

resource "google_compute_managed_ssl_certificate" "computemonitor" {
  name = "computemonitor-cert"

  managed {
    domains = [
      "computemonitor.net",
      "www.computemonitor.net",
      "app.computemonitor.net"
    ]
  }
}

resource "google_compute_global_forwarding_rule" "keycloak" {
  name                  = "${var.instance_name_prefix}-keycloak-lb"
  ip_address            = data.google_compute_global_address.keycloak_lb_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.keycloak.self_link
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}

resource "google_compute_target_https_proxy" "keycloak" {
  name             = "${var.instance_name_prefix}-keycloak-proxy"
  url_map          = google_compute_url_map.keycloak.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.computemonitor.self_link]
}



# ---------------------------------------------------------
# Network Load Balancer for Kubernetes API
# Uses the SAME global static IP as Keycloak
# TCP 6443
# ---------------------------------------------------------




# Unmanaged instance group containing the Kubernetes master
resource "google_compute_instance_group" "k8s_master" {
  name = "${var.instance_name_prefix}-k8s-master-ig"
  zone = google_compute_instance.master.zone

  instances = [
    google_compute_instance.master.self_link
  ]
}

# Regional static IP for the Kubernetes API network LB
resource "google_compute_address" "k8s_api" {
  name   = "${var.instance_name_prefix}-k8s-api-ip"
  region = var.region
}

# Target pool for the Network (TCP) Load Balancer
resource "google_compute_target_pool" "k8s_api" {
  name      = "${var.instance_name_prefix}-k8s-api-tp"
  region    = var.region
  instances = [google_compute_instance.master.self_link]
}

# Regional forwarding rule for TCP 6443
resource "google_compute_forwarding_rule" "k8s_api" {
  name                  = "${var.instance_name_prefix}-k8s-api-fr"
  region                = var.region
  ip_address            = google_compute_address.k8s_api.address
  port_range            = "6443"
  target                = google_compute_target_pool.k8s_api.self_link
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}
