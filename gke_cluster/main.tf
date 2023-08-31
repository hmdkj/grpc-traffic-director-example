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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
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

# Create GKE cluster
resource "google_container_cluster" "grpc-td-cluster" {
  name     = "grpc-td-cluster"
  location = var.gcp_zone
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy { }
  initial_node_count = 10
  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
    tags = ["allow-health-checks"]
  }
}

# Retrieve an access token as the Terraform runner
data "google_client_config" "current" {}

data "google_container_cluster" "grpc-td-cluster" {
  name     = google_container_cluster.grpc-td-cluster.name
  location = var.gcp_zone
}

provider "kubernetes" {
  host  = google_container_cluster.grpc-td-cluster.endpoint
  token = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.grpc-td-cluster.master_auth[0].cluster_ca_certificate,
  )
}

# Create gRPC server deployment
resource "kubernetes_deployment" "app1" {
  metadata {
    name = "app1"
    labels = {
      run = "app1"
    }
  }
  spec {
    replicas = 3
    selector {
      match_labels = {
        run = "app1"
      }
    }
    template {
      metadata {
        labels = {
          run = "app1"
        }
      }
      spec {
        container {
          image = "grpc/java-example-hostname:1.50.2"
          name  = "app1"
          port {
            container_port = 50051
          }
        }
      }
    }
  }
}

# Configuring GKE services with NEGs
resource "kubernetes_service" "helloworld" {
  metadata {
    name = "helloworld"
    annotations = {
      # cloud.google.com/negアノテーションを付けてサービスを作成することでNEGが作成され、Pod作成時にNetwork Endpointが作成される
      "cloud.google.com/neg" = <<-EOS
        {
          "exposed_ports" : {
            "8080" : {
              "name" : "example-grpc-server"
            }
          }
        }
      EOS
    }
  }
  spec {
    selector = {
      run = kubernetes_deployment.app1.metadata.0.labels.run
    }
    port {
      port        = 8080
      target_port = 50051
    }
    type = "ClusterIP"
  }
}

# Create proxyless gRPC client
resource "kubernetes_deployment" "sleeper" {
  metadata {
    labels = {
      run = "client"
    }
    name = "sleeper"
  }
  spec {
    selector {
      match_labels = {
        run = "client"
      }
    }
    template {
      metadata {
        labels = {
          run = "client"
        }
      }
      spec {
        container {
          image             = "openjdk:8-jdk"
          image_pull_policy = "IfNotPresent"
          name              = "sleeper"
          command           = ["sleep", "365d"]
          env {
            name  = "GRPC_XDS_BOOTSTRAP"
            value = "/tmp/grpc-xds/td-grpc-bootstrap.json"
          }
          resources {
            limits = {
              cpu    = "2"
              memory = "2000Mi"
            }
            requests = {
              cpu    = "300m"
              memory = "1500Mi"
            }
          }
          volume_mount {
            mount_path = "/tmp/grpc-xds/"
            name       = "grpc-td-conf"
          }
        }
        init_container {
          args              = ["--output", "/tmp/bootstrap/td-grpc-bootstrap.json"]
          image             = "gcr.io/trafficdirector-prod/td-grpc-bootstrap:0.11.0"
          image_pull_policy = "IfNotPresent"
          name              = "grpc-td-init"
          resources {
            limits = {
              cpu    = "100m"
              memory = "100Mi"
            }

            requests = {
              cpu    = "10m"
              memory = "100Mi"
            }
          }
          volume_mount {
            mount_path = "/tmp/bootstrap/"
            name       = "grpc-td-conf"
          }
        }
        volume {
          name = "grpc-td-conf"
          empty_dir {
            medium = "Memory"
          }
        }
      }
    }
  }
}
