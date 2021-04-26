output "cluster_endpoint" {
  value = format("https://%s:6443", local.cluster_endpoint)
}

output "ingress_ip_address" {
  value = docker_container.k3s_server.ip_address
}

output "kubeconfig" {
  description = "kubectl config file contents for this K3s cluster."
  value       = data.external.kubeconfig.result.kubeconfig
  sensitive   = true
}
