# 00-secrets.yaml
resource "local_file" "secrets" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("${path.module}/templates/secrets.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/00-secrets.yaml"
}

# 01-serviceaccount.yaml
resource "local_file" "serviceaccount" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("${path.module}/templates/serviceaccount.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/01-serviceaccount.yaml"
}

# 02-role.yaml
resource "local_file" "role" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("${path.module}/templates/role.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/02-role.yaml"
}

# 03-rolebinding.yaml
resource "local_file" "rolebinding" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("${path.module}/templates/rolebinding.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/03-rolebinding.yaml"
}

# 04-service.yaml
resource "local_file" "service" {
  content = templatefile("${path.module}/templates/service.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/04-service.yaml"
}

# 05-configmap.yaml
resource "local_file" "configmap" {
  content = templatefile("${path.module}/templates/configmap.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${var.output_dir}/05-configmap.yaml"
}

# 06-statefulset.yaml
resource "local_file" "statefulset" {
  content = templatefile("${path.module}/templates/statefulset.yaml.tftpl", {
    tailnets           = var.tailnets
    k8s_namespace      = var.k8s_namespace
    container_registry = var.container_registry
  })
  filename = "${var.output_dir}/06-statefulset.yaml"
}

# configuration-summary.md
resource "local_file" "configuration_summary" {
  content = templatefile("${path.module}/templates/configuration-summary.md.tftpl", {
    tailnets      = var.tailnets
    k8s_namespace = var.k8s_namespace
    pool_name_map = var.pool_name_map
  })
  filename = "${var.summary_output_dir}/configuration-summary.md"
}
