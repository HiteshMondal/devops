###############################################################################
# opentofu_outputs.tf — Output Values
# Oracle Cloud Infrastructure — Always Free Tier
###############################################################################

#------------------------------------------------------------------------------
# Compartment
#------------------------------------------------------------------------------
output "compartment_id" {
  description = "OCI Compartment OCID"
  value       = oci_identity_compartment.main.id
}

output "compartment_name" {
  description = "OCI Compartment name"
  value       = oci_identity_compartment.main.name
}

#------------------------------------------------------------------------------
# VCN & Networking
#------------------------------------------------------------------------------
output "vcn_id" {
  description = "VCN OCID"
  value       = oci_core_vcn.main.id
}

output "vcn_cidr" {
  description = "VCN CIDR block"
  value       = oci_core_vcn.main.cidr_blocks[0]
}

output "public_subnet_id" {
  description = "Public subnet OCID (Load Balancer)"
  value       = oci_core_subnet.public.id
}

output "private_node_subnet_id" {
  description = "Private node subnet OCID (OKE worker nodes)"
  value       = oci_core_subnet.private_nodes.id
}

output "private_pod_subnet_id" {
  description = "Private pod subnet OCID (OKE VCN-native pods)"
  value       = oci_core_subnet.private_pods.id
}

output "private_db_subnet_id" {
  description = "Private DB subnet OCID (Autonomous Database)"
  value       = oci_core_subnet.private_db.id
}

output "load_balancer_ip" {
  description = "OCI Load Balancer public IP"
  value       = oci_load_balancer_load_balancer.main.ip_address_details[*].ip_address
}

#------------------------------------------------------------------------------
# OKE Cluster
#------------------------------------------------------------------------------
output "oke_cluster_id" {
  description = "OKE cluster OCID"
  value       = oci_containerengine_cluster.main.id
}

output "oke_cluster_name" {
  description = "OKE cluster name"
  value       = oci_containerengine_cluster.main.name
}

output "oke_kubernetes_version" {
  description = "Kubernetes version running on OKE"
  value       = oci_containerengine_cluster.main.kubernetes_version
}

output "oke_cluster_endpoint" {
  description = "OKE Kubernetes API server endpoint"
  value       = oci_containerengine_cluster.main.endpoints[0].public_endpoint
}

output "oke_node_pool_id" {
  description = "OKE node pool OCID"
  value       = oci_containerengine_node_pool.main.id
}

output "oke_node_shape" {
  description = "OKE worker node shape"
  value       = oci_containerengine_node_pool.main.node_shape
}

output "kubeconfig_path" {
  description = "Path to generated kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "kubeconfig_command" {
  description = "OCI CLI command to generate kubeconfig"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.main.id} --file $HOME/.kube/config --region ${var.oci_region} --token-version 2.0.0"
}

#------------------------------------------------------------------------------
# Autonomous Database
#------------------------------------------------------------------------------
output "adb_id" {
  description = "Autonomous Database OCID"
  value       = oci_database_autonomous_database.main.id
}

output "adb_display_name" {
  description = "Autonomous Database display name"
  value       = oci_database_autonomous_database.main.display_name
}

output "adb_db_name" {
  description = "Autonomous Database name"
  value       = oci_database_autonomous_database.main.db_name
}

output "adb_connection_strings" {
  description = "Autonomous Database connection strings"
  value       = oci_database_autonomous_database.main.connection_strings
  sensitive   = true
}

output "adb_private_endpoint" {
  description = "Autonomous Database private endpoint IP"
  value       = oci_database_autonomous_database.main.private_endpoint_ip
  sensitive   = true
}

output "adb_wallet_path" {
  description = "Path to downloaded ADB wallet ZIP (for mTLS connections)"
  value       = local_file.adb_wallet.filename
}

output "adb_k8s_secret_path" {
  description = "Path to ADB Kubernetes secret manifest"
  value       = local_file.adb_k8s_secret_manifest.filename
}

output "adb_service_console_url" {
  description = "Autonomous Database service console URL"
  value       = oci_database_autonomous_database.main.service_console_url
}

output "adb_is_free_tier" {
  description = "Confirms ADB is Always Free tier"
  value       = oci_database_autonomous_database.main.is_free_tier
}

#------------------------------------------------------------------------------
# SSH Access
#------------------------------------------------------------------------------
output "ssh_private_key" {
  description = "Generated SSH private key (only if no key file was provided)"
  value       = length(tls_private_key.node_ssh) > 0 ? tls_private_key.node_ssh[0].private_key_pem : "Using provided SSH key"
  sensitive   = true
}

#------------------------------------------------------------------------------
# Cost Summary (informational)
#------------------------------------------------------------------------------
output "cost_summary" {
  description = "Estimated monthly cost on Oracle Cloud Always Free Tier"
  value = {
    oke_cluster        = "$0.00 (BASIC_CLUSTER is always free)"
    arm_nodes_2x       = "$0.00 (VM.Standard.A1.Flex — 4 OCPU + 24 GB Always Free)"
    autonomous_database = "$0.00 (1 ADB, 20 GB Always Free — no time limit)"
    load_balancer      = "$0.00 (1 × 10 Mbps LB Always Free)"
    nat_gateway        = "$0.00 (1 NAT GW Always Free)"
    object_storage     = "$0.00 (10 GB Always Free)"
    outbound_data      = "$0.00 (10 GB/month Always Free)"
    vault_default      = "$0.00 (Default Vault is free)"
    monitoring         = "$0.00 (Basic monitoring free)"
    total_estimate     = "$0.00/month — All resources within Always Free limits"
    note               = "Exceeding Always Free limits will incur charges. Monitor usage in OCI Console."
  }
}

#------------------------------------------------------------------------------
# Next Steps
#------------------------------------------------------------------------------
output "next_steps" {
  description = "Commands to run after infrastructure is provisioned"
  value = <<-EOT
    # 1. Configure kubectl
    oci ce cluster create-kubeconfig \
      --cluster-id ${oci_containerengine_cluster.main.id} \
      --file $HOME/.kube/config \
      --region ${var.oci_region} \
      --token-version 2.0.0

    # 2. Verify cluster access
    kubectl get nodes

    # 3. Apply ADB credentials to cluster
    kubectl apply -f ${local_file.adb_k8s_secret_manifest.filename}

    # 4. Deploy application
    kubectl apply -k kubernetes/overlays/prod/

    # 5. Check deployment
    kubectl get all -n ${var.app_namespace}
  EOT
}
