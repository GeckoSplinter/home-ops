locals {
  domain = "gecko.ninja"
  ipv4 = "82.122.217.40"
}

resource "cloudflare_zone" "gecko_ninja" {
  zone       = local.domain
  account_id = var.cloudflare_account_id
}

resource "cloudflare_record" "gecko_ninja" {
  zone_id = cloudflare_zone.gecko_ninja.id
  name    = "gecko-ninja-a"
  value   = local.ipv4
  type    = "A"
  ttl     = 300
}
