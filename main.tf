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
    "K3S_KUBECONFIG_OUTPUT=/output/kubeconfig.yaml",
    "K3S_KUBECONFIG_MODE=666",
  ]

  mounts {
    target = "/output"
    source = abspath(path.cwd)
    type   = "bind"
  }

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

  provisioner "local-exec" {
    when    = destroy
    command = "rm ${path.cwd}/kubeconfig.yaml"
  }
}

resource "null_resource" "provisioner" {
  count = var.csi_support ? 1 : 0

  depends_on = [
    docker_container.k3s_server,
    docker_container.k3s_agent,
  ]

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl -n argocd delete application --all; kubectl -n cluster-operators delete deployments --all; for kind in daemonsets statefulsets deployments cronjobs jobs horizontalpodautoscaler service; do kubectl delete $kind --all --all-namespaces; done; for i in `seq 1 60`; do test `kubectl get pods --all-namespaces | wc -l` -eq 0 && exit 0 || true; sleep 5; done; echo TIMEOUT && exit 1"

    environment = {
      KUBECONFIG = "${path.cwd}/kubeconfig.yaml"
    }
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
      ENDPOINT = format("https://%s:6443", docker_container.k3s_server.ip_address)
    }
  }
}

resource "null_resource" "wait_for_kubeconfig" {
  depends_on = [
    null_resource.wait_for_cluster,
  ]

  provisioner "local-exec" {
    command = "for i in `seq 1 60`; do test -f ${path.cwd}/kubeconfig.yaml && exit 0 || true; sleep 5; done; echo TIMEOUT && exit 1"
  }
}

resource "null_resource" "fix_kubeconfig" {
  depends_on = [
    null_resource.wait_for_kubeconfig,
  ]

  provisioner "local-exec" {
    command = "sed -i -e 's/127.0.0.1/${docker_container.k3s_server.ip_address}/' ${path.cwd}/kubeconfig.yaml"
  }
}

data "local_file" "kubeconfig" {
  filename = "${path.cwd}/kubeconfig.yaml"

  depends_on = [
    null_resource.fix_kubeconfig,
  ]
}
