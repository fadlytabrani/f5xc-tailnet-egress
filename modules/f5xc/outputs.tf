output "origin_pool_files" {
  description = "List of generated F5 XC origin pool JSON configuration file paths"
  value = [
    for index, service in var.services : {
      f5xc_origin_pool        = service.f5xc_origin_pool
      f5xc_origin_pool_unique = "${service.f5xc_origin_pool}-${var.origin_pool_suffixes[index].hex}"
      json_file_path          = "${var.output_dir}/${service.f5xc_origin_pool}-${var.origin_pool_suffixes[index].hex}.json"
      tailnet_name            = service.tailnet_name
      service_endpoint        = service.service_endpoint
      exposed_port            = service.exposed_port
    }
  ]
}
