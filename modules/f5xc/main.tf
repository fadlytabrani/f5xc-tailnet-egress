resource "local_file" "origin_pool_configs" {
  count = length(var.services)
  content = templatefile("${path.module}/templates/origin_pool.json.tftpl", {
    origin_pool_name = "${var.services[count.index].f5xc_origin_pool}-${var.origin_pool_suffixes[count.index].hex}"
    namespace        = var.k8s_namespace
    service_endpoint = var.services[count.index].service_endpoint
    exposed_port     = var.services[count.index].exposed_port
    protocol         = var.services[count.index].protocol
  })
  filename = "${var.output_dir}/${var.services[count.index].f5xc_origin_pool}-${var.origin_pool_suffixes[count.index].hex}.json"
}
