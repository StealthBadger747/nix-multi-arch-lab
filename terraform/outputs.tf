output "imported_nixos_aarch64_image_ocid" {
  value = oci_core_image.imported_nixos_aarch64_image.id
}

output "nixos_aarch64_md5" {
  value = filemd5(local.nixos_aarch64_path)
}

output "instance_public_ip" {
  value = local.instance_public_ip
}
