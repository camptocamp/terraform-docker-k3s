output "cluster_endpoint" {
  value = format("https://%s:6443", docker_container.k3s_server.ip_address)
}

output "ingress_ip_address" {
  value = docker_container.k3s_server.ip_address
}

output "kubeconfig" {
  value = data.local_file.kubeconfig.content
}

output "kubeconfig_filename" {
  value = data.local_file.kubeconfig.filename
}
