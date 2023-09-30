locals {
  domain = "gecko.ninja"
}

resource "cloudflare_zone" "gecko_ninja" {
  zone       = local.domain
  account_id = var.cloudflare_account_id
}

resource "cloudflare_record" "gecko_ninja" {
  zone_id = cloudflare_zone.gecko_ninja.id
  name    = "gecko-ninja-a"
  value   = data.http.ipv4_lookup_raw.body
  type    = "A"
  ttl     = 300
}
