output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.book.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.bucket
}
