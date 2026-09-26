variable "custom_domain_name" {
  type        = string
  description = "The Route53 custom domain name for the group URL shortener backend"
  default     = "://sctp-sandbox.com"
}
