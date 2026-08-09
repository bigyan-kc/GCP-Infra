terraform {
  backend "gcs" {
    bucket = "gcp-infra-bigyan"
    prefix = "terraform/state"
  }
}
