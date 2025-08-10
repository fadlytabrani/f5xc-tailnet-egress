terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# Generate Service for multi-tailnet egress - Envoy
resource "local_file" "envoy_service" {
  content = templatefile("./envoy/templates/service.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/04-service.yaml"
}

# Generate RBAC resources only if any tailnet uses k8s secrets - Envoy
resource "local_file" "envoy_serviceaccount" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/templates/serviceaccount.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/01-serviceaccount.yaml"
}

resource "local_file" "envoy_role" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/templates/role.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/02-role.yaml"
}

resource "local_file" "envoy_rolebinding" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/templates/rolebinding.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/03-rolebinding.yaml"
}



# Generate secrets for tailnets that use k8s secrets - Envoy
resource "local_file" "envoy_secrets" {
  count = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? 1 : 0
  content = templatefile("./envoy/templates/secrets.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/00-secrets.yaml"
}



# Generate ConfigMap - Envoy
resource "local_file" "envoy_configmap" {
  content = templatefile("./envoy/templates/configmap.yaml.tftpl", {
    tailnets = var.tailnets
  })
  filename = "${path.module}/outputs/envoy/manifests/05-configmap.yaml"
}



# Generate StatefulSet - Envoy
resource "local_file" "envoy_statefulset" {
  content = templatefile(
    anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret])
    ? "./envoy/templates/statefulset-secrets.yaml.tftpl"
    : "./envoy/templates/statefulset.yaml.tftpl",
    {
      tailnets      = var.tailnets
      k8s_namespace = var.k8s_namespace
    }
  )
  filename = "${path.module}/outputs/envoy/manifests/06-statefulset.yaml"
}



# Generate configuration summary documentation - Envoy
resource "local_file" "envoy_configuration_summary_doc" {
  content = templatefile("./envoy/templates/configuration-summary.md.tftpl", {
    tailnets      = var.tailnets
    k8s_namespace = var.k8s_namespace
  })
  filename = "${path.module}/outputs/envoy/configuration-summary.md"
}


