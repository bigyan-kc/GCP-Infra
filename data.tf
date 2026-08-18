data "google_compute_global_address" "keycloak_lb_ip" {
  name = "keycloak-lb-ip"
}

data "google_compute_address" "k8s_api" {
  name   = "k8s-api-ip"
  region = var.region
}