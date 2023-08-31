terraform {
  required_version = ">= 1.2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.80.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.80.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

data "google_compute_network_endpoint_group" "example-grpc-server" {
  name = "example-grpc-server"
}

# Create the health check
resource "google_compute_health_check" "grpc-health-check" {
  name               = "grpc-health-check"
  timeout_sec        = 1
  check_interval_sec = 1
  grpc_health_check {
    port = "50051"
  }
}

# Create the firewall rule
resource "google_compute_firewall" "grpc-gke-allow-health-checks" {
  name    = "grpc-gke-allow-health-checks"
  network = "default"
  direction = "INGRESS"
  allow {
    protocol = "tcp"
    ports    = ["50051"]
  }
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["allow-health-checks"]
}

# Create the backend service
resource "google_compute_backend_service" "grpc-gke-helloworld-service" {
  name                  = "grpc-gke-helloworld-service"
  health_checks         = [google_compute_health_check.grpc-health-check.id]
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  protocol = "GRPC"
  backend {
    group                 = data.google_compute_network_endpoint_group.example-grpc-server.self_link
    balancing_mode        = "RATE"
    max_rate_per_endpoint = 5
  }
}

# Create the url map
resource "google_compute_url_map" "grpc-gke-url-map" {
  name            = "grpc-gke-url-map"
  default_service = google_compute_backend_service.grpc-gke-helloworld-service.self_link
  host_rule {
    hosts        = ["helloworld-gke:8000"]
    path_matcher = "grpc-gke-path-matcher"
  }
  path_matcher {
    name            = "grpc-gke-path-matcher"
    default_service = google_compute_backend_service.grpc-gke-helloworld-service.self_link
  }
}

# Create the target grpc proxy
resource "google_compute_target_grpc_proxy" "grpc-gke-proxy" {
  name    = "grpc-gke-proxy"
  url_map = google_compute_url_map.grpc-gke-url-map.self_link
  validate_for_proxyless = true
}

# Create the forwarding rule
resource "google_compute_global_forwarding_rule" "grpc-gke-forwarding-rule" {
  name                  = "grpc-gke-forwarding-rule"
  ip_address            = "0.0.0.0"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  port_range            = "8000"
  target                = google_compute_target_grpc_proxy.grpc-gke-proxy.self_link
  network               = "default"
}
