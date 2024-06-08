terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "gecko-ninja"
    workspaces {
      name = "home-ops-cloudflare"
    }
  }
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.32.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.3"
    }
  }
  required_version = ">= 1.3.0"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
