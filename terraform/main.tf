terraform {
  required_version = ">= 1.6.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
}

# ==============================================================================
# LOCALS
# ==============================================================================
locals {
  # Email → GitLab/Linux-Username:
  # Local-Part bleibt, jedes Domain-Token wird auf max. 2 Zeichen gekappt,
  # hart begrenzt auf 32 Zeichen (Linux UT_NAMESIZE).
  #   s2327001@student.dhbw-mannheim.de → s2327001_st_dh-ma_de
  #   prof1@dhbw-mannheim.de            → prof1_dh-ma_de
  email_to_username = {
    for email in concat([var.admin_username], var.students) :
    email => substr(
      lower(join("_", concat(
        [split("@", email)[0]],
        [
          for token in split(".", split("@", email)[1]) :
          join("-", [for part in split("-", token) : substr(part, 0, 2)])
        ]
      ))),
      0, 32
    )
  }
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "openstack_images_image_v2" "ubuntu" {
  count       = var.use_mock_provider ? 0 : 1
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "selected" {
  count = var.use_mock_provider ? 0 : 1
  name  = var.flavor_name
}

data "openstack_networking_network_v2" "external" {
  count    = var.use_mock_provider ? 0 : 1
  name     = var.external_network_name
  external = true
}

# ==============================================================================
# CREDENTIALS
# ==============================================================================

resource "random_password" "admin_password" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "random_password" "student_passwords" {
  for_each         = toset(var.students)
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "tls_private_key" "gitlab_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "openstack_compute_keypair_v2" "gitlab_keypair" {
  count      = var.use_mock_provider ? 0 : 1
  name       = "gitlab-keypair-${var.deployment_id}"
  public_key = tls_private_key.gitlab_ssh_key.public_key_openssh
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

resource "openstack_networking_secgroup_v2" "gitlab_access" {
  count       = var.use_mock_provider ? 0 : 1
  name        = "gitlab-access-${var.deployment_id}"
  description = "GitLab CE: SSH + HTTP"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.gitlab_access[0].id
}

resource "openstack_networking_secgroup_rule_v2" "http_ingress" {
  count             = var.use_mock_provider ? 0 : 1
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.gitlab_access[0].id
}

# ==============================================================================
# INSTANCE
# ==============================================================================

resource "openstack_compute_instance_v2" "gitlab_server" {
  count           = var.use_mock_provider ? 0 : 1
  name            = "gitlab-${var.deployment_id}"
  image_id        = data.openstack_images_image_v2.ubuntu[0].id
  flavor_id       = data.openstack_compute_flavor_v2.selected[0].id
  key_pair        = openstack_compute_keypair_v2.gitlab_keypair[0].name
  security_groups = [openstack_networking_secgroup_v2.gitlab_access[0].name]

  network {
    name = var.network_name
  }

  depends_on = [openstack_networking_floatingip_v2.gitlab_fip]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    app_name       = var.app_name
    gitlab_version = var.gitlab_version
    floating_ip    = openstack_networking_floatingip_v2.gitlab_fip[0].address
    groups         = var.gitlab_groups

    admin_username = local.email_to_username[var.admin_username]
    admin_email    = var.admin_username
    admin_password = random_password.admin_password.result

    students = [
      for email in var.students : {
        username = local.email_to_username[email]
        email    = email
        password = random_password.student_passwords[email].result
      }
    ]
  })
}

# ==============================================================================
# FLOATING IP
# ==============================================================================

resource "openstack_networking_floatingip_v2" "gitlab_fip" {
  count = var.use_mock_provider ? 0 : 1
  pool  = var.floating_ip_pool
}

resource "openstack_compute_floatingip_associate_v2" "gitlab_fip_assoc" {
  count       = var.use_mock_provider ? 0 : 1
  floating_ip = openstack_networking_floatingip_v2.gitlab_fip[0].address
  instance_id = openstack_compute_instance_v2.gitlab_server[0].id
}

# ==============================================================================
# MOCK RESOURCE
# ==============================================================================

resource "null_resource" "mock_gitlab_server" {
  count = var.use_mock_provider ? 1 : 0
  triggers = {
    deployment_id = var.deployment_id
    app_name      = var.app_name
  }
}
