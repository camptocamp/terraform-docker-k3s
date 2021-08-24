variable "k3s_version" {
  description = "The K3s version to use"
  type        = string
}

variable "containers_name" {
  description = "The name of the containers of this worker group"
  type        = string
}

variable "network_name" {
  description = "Docker network to use. Creates a new one if null."
  type        = string
}

variable "k3s_token" {
  description = "The K3S_TOKEN to use"
  type        = string
}

variable "k3s_url" {
  description = "The K3S_URL to use"
  type        = string
}

variable "registries_yaml" {
  description = "The path of the registries.yaml file to use"
  type        = string
}

variable "server_container_name" {
  description = "The name of the K3s server's container"
  type        = string
}

variable "node_count" {
  description = "Number of nodes to deploy"
  type        = number
}

variable "node_labels" {
  description = "Registering and starting kubelet with set of labels"
  type        = list(string)
  default     = []
}

variable "node_taints" {
  description = "Registering kubelet with set of taints"
  type        = list(string)
  default     = []
}

variable "restart" {
  description = "Restart policy for the cluster."
  type        = string
  default     = "unless-stopped"
}

variable "csi_support" {
  description = "Container Storage Interface requires /var/lib/kubelet to be mounted with rshared propagation, that can cause some issues."
  type        = bool
  default     = false
}
