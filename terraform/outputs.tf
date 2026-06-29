# ==============================================================================
# SYSTEM OUTPUTS (MANDATORY)
# ==============================================================================

output "instance_id" {
  description = "VM ID for backend management"
  value       = var.use_mock_provider ? "mock-instance-${var.deployment_id}" : openstack_compute_instance_v2.gitlab_server[0].id
}

output "app_name" {
  description = "Project name"
  value       = var.app_name
}

# ==============================================================================
# PUBLIC OUTPUTS
# ==============================================================================

output "gitlab_url" {
  description = "GitLab Web-Oberfläche (HTTP)"
  value       = var.use_mock_provider ? "http://mock-ip" : "http://${openstack_networking_floatingip_v2.gitlab_fip[0].address}"
}

output "ssh_command" {
  description = "SSH-Befehl für den VM-Zugang"
  value       = var.use_mock_provider ? "ssh ubuntu@mock-ip" : "ssh -i <private_key> ubuntu@${openstack_networking_floatingip_v2.gitlab_fip[0].address}"
}

# ==============================================================================
# SENSITIVE OUTPUTS
# ==============================================================================

output "admin_credentials" {
  description = "Admin-Zugangsdaten des Dozenten (GitLab Root)"
  sensitive   = true
  value = {
    username   = local.email_to_username[var.admin_username]
    email      = var.admin_username
    password   = random_password.admin_password.result
    gitlab_url = var.use_mock_provider ? "http://mock-ip" : "http://${openstack_networking_floatingip_v2.gitlab_fip[0].address}"
  }
}

output "student_credentials" {
  description = "Zugangsdaten aller Studierenden"
  sensitive   = true
  value = {
    for email in var.students : email => {
      username   = local.email_to_username[email]
      email      = email
      password   = random_password.student_passwords[email].result
      gitlab_url = var.use_mock_provider ? "http://mock-ip" : "http://${openstack_networking_floatingip_v2.gitlab_fip[0].address}"
    }
  }
}

output "ssh_private_key" {
  description = "SSH Private Key für den VM-Zugang"
  sensitive   = true
  value       = tls_private_key.gitlab_ssh_key.private_key_openssh
}
