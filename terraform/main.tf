terraform {
  required_providers {
    oci = {
      source = "opentofu/oci"
      version = ">=6.3.0"
    }
  }
}

provider "oci" {
  user_ocid = "ocid1.user.oc1..aaaaaaaacglct34z7ifhk6zbx5x4idgcnixl5f5l7ydwzathnymjtfqi36fq"
  tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaa3whclbabtpx6ivlsui76iicxrvlxv3zts2zp2bwh6ibstrcdmsda"
  private_key_path = "./.oci/oracle.pem"
  fingerprint = "6d:ac:eb:de:ed:33:b1:bb:7c:61:91:f1:69:3b:91:94"
  region = "us-ashburn-1"
}

# Use a data source to reference the existing bucket
data "oci_objectstorage_bucket" "image_bucket" {
  name           = "nixos-image-bucket"
  namespace      = var.namespace
}

# Resource to upload the image to the bucket
resource "oci_objectstorage_object" "nixos_image" {
  bucket    = data.oci_objectstorage_bucket.image_bucket.name
  namespace = var.namespace
  object    = "nixos.qcow2"
  source    = "./result/nixos.qcow2"

  # Add content_md5 to force re-upload if the local file changes
  content_md5 = base64encode(filemd5("./result/nixos.qcow2"))

  # Use metadata to store the hex-encoded MD5 for change detection
  metadata = {
    md5_hex = filemd5("./result/nixos.qcow2")
  }

  # # Add a lifecycle rule to handle errors
  # lifecycle {
  #   ignore_changes = [content_md5]
  # }
}

# Output the MD5 hash for reference
output "nixos_image_md5" {
  value = filemd5("./result/nixos.qcow2")
}

# Resource to import the image
resource "oci_core_image" "imported_image" {
  compartment_id = var.compartment_ocid
  display_name   = "Headscale NixOS Image"

  image_source_details {
    source_type    = "objectStorageTuple"
    namespace_name = var.namespace
    bucket_name    = data.oci_objectstorage_bucket.image_bucket.name
    object_name    = oci_objectstorage_object.nixos_image.object
  }

  # Optional: Launch mode for the image
  launch_mode = "PARAVIRTUALIZED"

  # Add a dependency on the object resource
  depends_on = [oci_objectstorage_object.nixos_image]
}

# # Resource to import the image
# resource "oci_core_image" "imported_image" {
#   compartment_id = "ocid1.compartment.oc1..aaaaaaaaegdsylob7sbivyixrfjbqj76awi5bd2gvgptdtgcumg23rl7w2jq"
#   display_name   = "Headscale NixOS Image"

#   image_source_details {
#     source_type    = "objectStorageTuple"
#     namespace_name = "idlzjn2xkhld"
#     bucket_name    = "nixos-image-bucket"
#     object_name    = "nixos-image.qcow2"
#   }

#   # Optional: Launch mode for the image
#   launch_mode = "NATIVE"
# }

# Output the OCID of the imported image
output "imported_image_ocid" {
  value = oci_core_image.imported_image.id
}


# Select instance shape based on workspace
# locals {
#   ssh_username            = "opc"
#   instance_shape          = "VM.Standard.A1.Flex"
#   cpu_cores_count         = "4"
#   memory_in_gbs           = "22"
#   boot_volume_vpus_per_gb = "120"
#   os_image_ocid           = oci_core_image.imported_image.id
#   server_type             = "arm"
#   instance_public_ip      = oci_core_instance.instance.public_ip
#   instance_ids            = oci_core_instance.instance[*].id
#   availability_domain     = "xHzH:US-ASHBURN-AD-3"
# }
# locals {
#   ssh_username            = "opc"
#   instance_shape          = "VM.Standard.E4.Flex"
#   cpu_cores_count         = "2"
#   memory_in_gbs           = "4"
#   boot_volume_vpus_per_gb = "50"
#   os_image_ocid           = oci_core_image.imported_image.id
#   instance_public_ip      = oci_core_instance.instance.public_ip
#   instance_ids            = oci_core_instance.instance[*].id
#   availability_domain     = "xHzH:US-ASHBURN-AD-3"
# }
locals {
  ssh_username            = "opc"
  instance_shape          = "VM.Standard.E2.1.Micro"
  cpu_cores_count         = "1"
  memory_in_gbs           = "1"
  boot_volume_vpus_per_gb = "10"
  os_image_ocid           = oci_core_image.imported_image.id
  instance_public_ip      = oci_core_instance.instance.public_ip
  instance_ids            = oci_core_instance.instance[*].id
  availability_domain     = "xHzH:US-ASHBURN-AD-3"
}


data "oci_identity_availability_domains" "ads" {
    compartment_id = var.tenancy_ocid
}

resource "oci_core_vcn" "terraform_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "Terraform VCN"
  dns_label      = "tfvcn"
}

resource "oci_core_internet_gateway" "internet_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "Internet Gateway"
}

resource "oci_core_route_table" "public_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "Public Route Table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.internet_gateway.id
  }
}

resource "oci_core_security_list" "allow_ssh_http_https" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "Allow SSH/HTTP/HTTPS"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "terraform_subnet" {
  cidr_block        = "10.0.1.0/24"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.terraform_vcn.id
  display_name      = "Terraform Subnet"
  security_list_ids = [oci_core_security_list.allow_ssh_http_https.id]
  route_table_id    = oci_core_route_table.public_route_table.id
}

resource "oci_core_instance" "instance" {
  availability_domain = local.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "${var.instance_name}-${terraform.workspace}"
  shape               = local.instance_shape

  source_details {
    source_type             = "image"
    source_id               = local.os_image_ocid
    boot_volume_vpus_per_gb = local.boot_volume_vpus_per_gb
  }

  shape_config {
    memory_in_gbs = local.memory_in_gbs
    ocpus         = local.cpu_cores_count
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.terraform_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
  }

  launch_options {
    network_type                 = "PARAVIRTUALIZED"
    boot_volume_type             = "PARAVIRTUALIZED"
    is_pv_encryption_in_transit_enabled = false
    firmware                     = "UEFI_64"
  }

  lifecycle {
    replace_triggered_by = [
      oci_core_image.imported_image.id,
      oci_objectstorage_object.nixos_image.metadata["md5_hex"]
    ]
  }
}

output "instance_public_ip" {
  value = local.instance_public_ip
}
