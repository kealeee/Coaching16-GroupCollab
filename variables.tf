variable "AWS_REGION" {
  description = "Region for all resources. The ACM cert is created here too (REGIONAL API endpoint)."
  type        = string
  default     = "us-east-1"
}

variable "custom_domain_name" {
  type        = string
  description = "The Route53 custom domain name for the group URL shortener backend"
  default     = "group4-urlshortener.sctp-sandbox.com"
}