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
      version = "4.15.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "http" "ipv4_lookup_raw" {
  url = "http://ipv4.icanhazip.com"
}
