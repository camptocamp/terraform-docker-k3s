resource "docker_image" "k3s" {
  name         = "rancher/k3s:${var.k3s_version}"
  keep_locally = true
}

resource "docker_volume" "kubelet" {
  count = var.csi_support ? var.node_count : 0

  name = "k3s-agent-kubelet-${var.containers_name}-${count.index}"
}

resource "docker_container" "this" {
  count = var.node_count

  image = docker_image.k3s.latest
  name  = "k3s-agent-${var.containers_name}-${count.index}"

  restart = var.restart

  command = flatten(
    concat(
      ["agent"],
      [for label in var.node_labels : ["--node-label", label]],
      [for taint in var.node_taints : ["--node-taint", taint]],
    )
  )

  privileged = true

  networks_advanced {
    name = var.network_name
  }

  env = [
    "K3S_TOKEN=${var.k3s_token}",
    "K3S_URL=${var.k3s_url}",
  ]

  mounts {
    target = "/run"
    type   = "tmpfs"
  }

  mounts {
    target = "/var/run"
    type   = "tmpfs"
  }

  mounts {
    target = "/etc/rancher/k3s/registries.yaml"
    source = var.registries_yaml
    type   = "bind"
  }

  dynamic "mounts" {
    for_each = var.csi_support ? [1] : []

    content {
      target = "/var/lib/kubelet"
      source = docker_volume.kubelet[count.index].mountpoint
      type   = "bind"

      bind_options {
        propagation = "rshared"
      }
    }
  }
}

resource "null_resource" "destroy" {
  count = var.node_count

  triggers = {
    server_container_name = var.server_container_name
    hostname              = docker_container.this[count.index].hostname
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker exec ${self.triggers.server_container_name} kubectl drain ${self.triggers.hostname} --delete-emptydir-data --disable-eviction --ignore-daemonsets --grace-period=60"
  }
}
