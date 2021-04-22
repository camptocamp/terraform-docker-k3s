locals {
  network_name = var.network_name == null ? docker_network.k3s.0.name : var.network_name
}

# Mimics https://github.com/rancher/k3s/blob/master/docker-compose.yml
resource "docker_volume" "k3s_server" {
  name = "k3s-server-${var.cluster_name}"
}

resource "docker_network" "k3s" {
  count = var.network_name == null ? 1 : 0

  name = "k3s-${var.cluster_name}"
}

resource "docker_image" "registry" {
  name         = "registry:2"
  keep_locally = true
}

resource "docker_container" "registry_mirror" {
  for_each = var.registry_mirrors

  image = docker_image.registry.latest
  name  = format("registry-%s-%s", replace(each.key, ".", "-"), var.cluster_name)

  restart = var.restart

  networks_advanced {
    name = local.network_name
  }

  env = each.value

  mounts {
    target = "/var/lib/registry"
    source = "registry"
    type   = "volume"
  }
}

resource "local_file" "registries_yaml" {
  content  = <<EOF
---
mirrors:
%{for key, registry_mirror in docker_container.registry_mirror~}
  ${key}:
    endpoint:
      - http://${registry_mirror.ip_address}:5000
%{endfor~}
EOF
  filename = "${path.module}/registries.yaml"
}

resource "docker_image" "k3s" {
  name         = "rancher/k3s:${var.k3s_version}"
  keep_locally = true
}

resource "docker_volume" "k3s_server_kubelet" {
  count = var.csi_support ? 1 : 0
  name  = "k3s-server-kubelet-${var.cluster_name}"
}

resource "docker_container" "k3s_server" {
  image = docker_image.k3s.latest
  name  = "k3s-server-${var.cluster_name}"

  restart = var.restart

  command = concat(["server"], var.server_config)

  privileged = true

  networks_advanced {
    name = local.network_name
  }

  env = [
    "K3S_TOKEN=${random_password.k3s_token.result}",
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
    source = abspath(local_file.registries_yaml.filename)
    type   = "bind"
  }

  mounts {
    target = "/var/lib/rancher/k3s"
    source = docker_volume.k3s_server.name
    type   = "volume"
  }

  dynamic "mounts" {
    for_each = var.csi_support ? [1] : []

    content {
      target = "/var/lib/kubelet"
      source = docker_volume.k3s_server_kubelet[0].mountpoint
      type   = "bind"

      bind_options {
        propagation = "rshared"
      }
    }
  }

  dynamic "ports" {
    for_each = var.server_ports

    content {
      internal = ports.value.internal
      external = ports.value.external
      ip       = ports.value.ip
      protocol = ports.value.protocol
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker exec ${self.name} kubectl drain --delete-emptydir-data --ignore-daemonsets ${self.hostname}"
  }
}

resource "docker_volume" "k3s_agent_kubelet" {
  count = var.csi_support ? var.node_count : 0

  name = "k3s-agent-kubelet-${var.cluster_name}-${count.index}"
}

resource "docker_container" "k3s_agent" {
  count = var.node_count

  image = docker_image.k3s.latest
  name  = "k3s-agent-${var.cluster_name}-${count.index}"

  restart = var.restart

  privileged = true

  networks_advanced {
    name = local.network_name
  }

  env = [
    "K3S_TOKEN=${random_password.k3s_token.result}",
    "K3S_URL=https://${docker_container.k3s_server.ip_address}:6443",
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
    source = abspath(local_file.registries_yaml.filename)
    type   = "bind"
  }

  dynamic "mounts" {
    for_each = var.csi_support ? [1] : []

    content {
      target = "/var/lib/kubelet"
      source = docker_volume.k3s_agent_kubelet[count.index].mountpoint
      type   = "bind"

      bind_options {
        propagation = "rshared"
      }
    }
  }
}

resource "null_resource" "destroy_k3s_agent" {
  count = var.node_count

  triggers = {
    server_container_name = docker_container.k3s_server.name
    hostname              = docker_container.k3s_agent[count.index].hostname
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker exec ${self.triggers.server_container_name} kubectl drain --delete-emptydir-data --ignore-daemonsets ${self.triggers.hostname}"
  }
}

resource "random_password" "k3s_token" {
  length = 16
}

resource "null_resource" "wait_for_cluster" {
  depends_on = [
    docker_container.k3s_server,
  ]

  provisioner "local-exec" {
    command     = var.wait_for_cluster_cmd
    interpreter = var.wait_for_cluster_interpreter
    environment = {
      ENDPOINT = format("https://%s:6443", coalesce(var.base_domain, docker_container.k3s_server.ip_address))
    }
  }
}

data "external" "kubeconfig" {
  program = ["sh", "${path.module}/kubeconfig.sh"]

  query = {
    container_name       = docker_container.k3s_server.name
    container_ip_address = coalesce(var.base_domain, docker_container.k3s_server.ip_address)
  }

  depends_on = [
    null_resource.wait_for_cluster,
  ]
}
