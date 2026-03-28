###############################################################################
# opentofu_vpc.tf — OCI VCN, Subnets, Gateways, Security Lists, NSGs
# Oracle Cloud — ap-mumbai-1 (Mumbai) | Always Free Tier
###############################################################################

#------------------------------------------------------------------------------
# Virtual Cloud Network (VCN)
#------------------------------------------------------------------------------
resource "oci_core_vcn" "main" {
  compartment_id = oci_identity_compartment.main.id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-${var.environment}-vcn"
  dns_label      = replace("${var.project_name}${var.environment}", "-", "")

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------
resource "oci_core_internet_gateway" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-igw"
  enabled        = true

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# NAT Gateway — Always Free (1 free NAT GW per region!)
#------------------------------------------------------------------------------
resource "oci_core_nat_gateway" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-nat-gw"
  block_traffic  = false

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Service Gateway — free access to OCI services without internet
#------------------------------------------------------------------------------
data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-svc-gw"

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Route Tables
#------------------------------------------------------------------------------
# Public route table — via Internet Gateway
resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = local.freeform_tags
}

# Private route table — via NAT Gateway + Service Gateway
resource "oci_core_route_table" "private" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-private-rt"

  route_rules {
    network_entity_id = oci_core_nat_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  route_rules {
    network_entity_id = oci_core_service_gateway.main.id
    destination       = data.oci_core_services.all_oci_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Security Lists
#------------------------------------------------------------------------------
# Public security list (Load Balancer subnet)
resource "oci_core_security_list" "public" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-public-sl"

  # Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound traffic"
  }

  # HTTP
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
    description = "Allow HTTP from internet"
  }

  # HTTPS
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
    description = "Allow HTTPS from internet"
  }

  # Health check from OCI LB
  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/16"
    tcp_options {
      min = 8080
      max = 8080
    }
    description = "Allow OCI LB health checks"
  }

  freeform_tags = local.freeform_tags
}

# Private node security list (OKE worker nodes)
resource "oci_core_security_list" "private_nodes" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-nodes-sl"

  # Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound"
  }

  # Allow intra-VCN (node-to-node, control plane to nodes)
  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr
    description = "Allow intra-VCN traffic"
  }

  # OKE control plane health checks
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 10250
      max = 10250
    }
    description = "OKE kubelet health check"
  }

  freeform_tags = local.freeform_tags
}

# Private DB security list (Autonomous Database)
resource "oci_core_security_list" "private_db" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-db-sl"

  # Allow all outbound
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all outbound"
  }

  # PostgreSQL / Oracle DB from private node subnet only
  ingress_security_rules {
    protocol = "6"
    source   = var.private_node_subnet_cidr
    tcp_options {
      min = 1521
      max = 1522
    }
    description = "Oracle DB from OKE nodes"
  }

  # TLS PostgreSQL
  ingress_security_rules {
    protocol = "6"
    source   = var.private_node_subnet_cidr
    tcp_options {
      min = 5432
      max = 5432
    }
    description = "PostgreSQL from OKE nodes"
  }

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------
# Public Subnet — Load Balancer
resource "oci_core_subnet" "public" {
  compartment_id    = oci_identity_compartment.main.id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.public_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]

  prohibit_public_ip_on_vnic  = false # Public IPs allowed

  freeform_tags = local.freeform_tags
}

# Private Subnet — OKE Worker Nodes
resource "oci_core_subnet" "private_nodes" {
  compartment_id    = oci_identity_compartment.main.id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.private_node_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-nodes-subnet"
  dns_label         = "nodes"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private_nodes.id]

  prohibit_public_ip_on_vnic = true # No public IPs on worker nodes

  freeform_tags = local.freeform_tags
}

# Private Subnet — OKE Pods (VCN-native pod networking)
resource "oci_core_subnet" "private_pods" {
  compartment_id    = oci_identity_compartment.main.id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.private_pod_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-pods-subnet"
  dns_label         = "pods"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private_nodes.id]

  prohibit_public_ip_on_vnic = true

  freeform_tags = local.freeform_tags
}

# Private Subnet — Autonomous Database
resource "oci_core_subnet" "private_db" {
  compartment_id    = oci_identity_compartment.main.id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.private_db_subnet_cidr
  display_name      = "${var.project_name}-${var.environment}-db-subnet"
  dns_label         = "db"
  route_table_id    = oci_core_route_table.private.id
  security_list_ids = [oci_core_security_list.private_db.id]

  prohibit_public_ip_on_vnic = true

  freeform_tags = local.freeform_tags
}

#------------------------------------------------------------------------------
# Network Security Group (NSG) for OKE Load Balancer
#------------------------------------------------------------------------------
resource "oci_core_network_security_group" "lb" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project_name}-${var.environment}-lb-nsg"

  freeform_tags = local.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "lb_https_ingress" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
  description = "HTTPS from internet"
}

resource "oci_core_network_security_group_security_rule" "lb_http_ingress" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
  description = "HTTP from internet"
}

resource "oci_core_network_security_group_security_rule" "lb_egress" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Allow all outbound from LB"
}
