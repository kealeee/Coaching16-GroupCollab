variable "AWS_REGION" {
  description = "Region for all resources. The ACM cert is created here too (REGIONAL API endpoint)."
  type        = string
  default     = "us-east-1"
}

variable "OIDC_ROLE" {
  description = "The ARN of the OIDC role to be used."
  type        = string
  default     = "arn:aws:iam::255945442255:role/coaching16_group4"
}