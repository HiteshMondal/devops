###############################################################################
# opentofu_eks.tf — Oracle Kubernetes Engine (OKE) Cluster & Node Pool
# Always Free: VM.Standard.A1.Flex — 4 OCPU + 24 GB RAM total
# Region: ap-mumbai-1 (Mumbai)
###############################################################################

#------------------------------------------------------------------------------
# SSH Key for Node Access
#------------------------------------------------------------------------------
data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

# Alternatively generate one if none exists
resource "tls_private_key" "node_ssh" {
  count     = fileexists(pathexpand(var.ssh_public_key_path)) ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  ssh_public_key = fileexists(pathexpand(var.ssh_public_key_path)) ? (
    data.local_file.ssh_public_key.content
  ) : tls_private_key.node_ssh[0].public_key_openssh
}

#------------------------------------------------------------------------------
# OKE Cluster
#------------------------------------------------------------------------------
resource "oci_containerengine_cluster" "main" {
  compartment_id     = oci_identity_compartment.main.id
  name               = local.cluster_name
  vcn_id             = oci_core_vcn.main.id
  kubernetes_version = var.kubernetes_version
  type               = "BASIC_CLUSTER" # ENHANCED_CLUSTER adds cost

  endpoint_config {
    is_public_ip_enabled = true # Public API endpoint (needed for kubectl access)
    subnet_id            = oci_core_subnet.public.id
    nsg_ids              = [oci_core_network_security_group.lb.id]
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.public.id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = "172.16.0.0/16"
      services_cidr = "172.20.0.0/16"
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    # Persistent Volume Encryption
    persistent_volume_config {
      freeform_tags = local.freeform_tags
    }

    service_lb_config {
      freeform_tags = local.freeform_tags
    }
  }

  # Cluster-level image policy
  image_policy_config {
    is_policy_enabled = false # Enable for production with signed images
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# OKE Node Pool — ARM Ampere A1.Flex (Always Free)
# Total Always Free allocation: 4 OCPU, 24 GB RAM
# Config: 2 nodes × (2 OCPU + 12 GB RAM) = exactly the free limit
#------------------------------------------------------------------------------
resource "oci_containerengine_node_pool" "main" {
  compartment_id     = oci_identity_compartment.main.id
  cluster_id         = oci_containerengine_cluster.main.id
  name               = "${local.cluster_name}-arm-nodes"
  kubernetes_version = var.kubernetes_version

  # ARM Ampere A1 — Always Free
  node_shape = var.node_shape
  node_shape_config {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_gb
  }

  # OKE-optimized Oracle Linux image (ARM)
  node_source_details {
    source_type             = "IMAGE"
    image_id                = data.oci_core_images.oke_arm.images[0].id
    boot_volume_size_in_gbs = var.node_boot_volume_gb
  }

  # SSH access to nodes
  ssh_public_key = local.ssh_public_key

  # Distribute nodes across availability domains
  node_config_details {
    size = var.node_count

    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.private_nodes.id
      }
    }

    # Node pool-level NSG
    nsg_ids = []

    # OKE VCN-native pod networking
    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      pod_subnet_ids    = [oci_core_subnet.private_pods.id]
      pod_nsg_ids       = []
      max_pods_per_node = 31
    }

    freeform_tags = local.freeform_tags
  }

  # Node lifecycle — prevent accidental termination
  node_metadata = {
    "user_data" = base64encode(<<-EOT
      #!/bin/bash
      # Node bootstrap script
      echo "Node initialised: $(hostname)" >> /var/log/node-init.log
    EOT
    )
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Find latest OKE-compatible ARM image
#------------------------------------------------------------------------------
data "oci_core_images" "oke_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = var.node_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"

  filter {
    name   = "display_name"
    values = ["Oracle-Linux-8.*-aarch64-.*-OKE-.*"]
    regex  = true
  }
}

#------------------------------------------------------------------------------
# Get kubeconfig for the cluster
#------------------------------------------------------------------------------
data "oci_containerengine_cluster_kube_config" "main" {
  cluster_id = oci_containerengine_cluster.main.id

  depends_on = [
    oci_containerengine_cluster.main,
    oci_containerengine_node_pool.main,
  ]
}

resource "local_file" "kubeconfig" {
  content  = data.oci_containerengine_cluster_kube_config.main.content
  filename = "${path.module}/kubeconfig"

  file_permission = "0600"
}

#------------------------------------------------------------------------------
# OCI Load Balancer for Ingress (Always Free: 1 × 10 Mbps)
#------------------------------------------------------------------------------
resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "${var.project_name}-${var.environment}-lb"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10 # Always Free limit
  }

  subnet_ids     = [oci_core_subnet.public.id]
  is_private     = false
  network_security_group_ids = [oci_core_network_security_group.lb.id]

  ip_mode = "IPV4"

  freeform_tags = local.freeform_tags
}

# Backend set for HTTP
resource "oci_load_balancer_backend_set" "http" {
  name             = "http-backend-set"
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol            = "HTTP"
    url_path            = "/health"
    port                = 3000
    return_code         = 200
    interval_ms         = 30000
    timeout_in_millis   = 3000
    retries             = 3
  }
}

# HTTP listener
resource "oci_load_balancer_listener" "http" {
  name                     = "http-listener"
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  default_backend_set_name = oci_load_balancer_backend_set.http.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 300
  }
}
