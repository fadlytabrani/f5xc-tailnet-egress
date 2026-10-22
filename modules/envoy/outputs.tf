output "manifest_files" {
  description = "Generated Kubernetes manifest file paths for Envoy"
  value = {
    service     = "${var.output_dir}/04-service.yaml"
    configmap   = "${var.output_dir}/05-configmap.yaml"
    statefulset = "${var.output_dir}/06-statefulset.yaml"
    rbac_files = anytrue([for tailnet in var.tailnets : tailnet.use_k8s_secret]) ? [
      "${var.output_dir}/00-secrets.yaml",
      "${var.output_dir}/01-serviceaccount.yaml",
      "${var.output_dir}/02-role.yaml",
      "${var.output_dir}/03-rolebinding.yaml"
    ] : []
  }
}

output "configuration_summary" {
  description = "Path to Envoy configuration summary document"
  value       = "${var.summary_output_dir}/configuration-summary.md"
}
