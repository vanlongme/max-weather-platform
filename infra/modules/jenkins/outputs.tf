output "instance_id" {
  description = "Jenkins EC2 instance ID."
  value       = aws_instance.jenkins.id
}

output "instance_public_ip" {
  description = "Jenkins EC2 public IP (may change on stop/start; use EIP instead)."
  value       = aws_instance.jenkins.public_ip
}

output "instance_public_dns" {
  description = "Jenkins EC2 public DNS."
  value       = aws_instance.jenkins.public_dns
}

output "eip_address" {
  description = "Elastic IP address associated with Jenkins."
  value       = aws_eip.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins UI URL."
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
}
