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

resource "google_compute_target_https_proxy" "keycloak" {
  name             = "${var.instance_name_prefix}-keycloak-proxy"
  url_map          = google_compute_url_map.keycloak.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.computemonitor.self_link]
}