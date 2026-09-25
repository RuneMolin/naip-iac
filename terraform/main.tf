# =============================================================================
# SHARED RESOURCES
# =============================================================================

# Shared SSH key for both clusters
resource "hcloud_ssh_key" "k8s" {
  name       = "naip-k8s-key"
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : file("${path.module}/naip-k8s-key.pub")
}

# =============================================================================
# PRIMARY CLUSTER
# =============================================================================

# Private network for primary cluster
resource "hcloud_network" "primary" {
  name     = "${var.primary_cluster_name}-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "primary" {
  network_id   = hcloud_network.primary.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = "10.0.1.0/24"
}

# Primary cluster control plane (master node)
resource "hcloud_server" "primary_master" {
  name        = "${var.primary_cluster_name}-master"
  server_type = var.node_type
  image       = "ubuntu-22.04"
  location    = var.primary_location
  ssh_keys    = [hcloud_ssh_key.k8s.id]

  network {
    network_id = hcloud_network.primary.id
    ip         = "10.0.1.2"
  }

  labels = {
    cluster = var.primary_cluster_name
    role    = "master"
    type    = "k3s"
  }

  user_data = templatefile("${path.module}/cloud-init-master.yaml", {
    k8s_version  = var.k8s_version
    cluster_name = var.primary_cluster_name
    node_ip      = "10.0.1.2"
    cluster_cidr = "10.42.0.0/16"
    service_cidr = "10.43.0.0/16"
  })
}

# Primary cluster worker nodes
resource "hcloud_server" "primary_workers" {
  count       = var.node_count
  name        = "${var.primary_cluster_name}-worker-${count.index + 1}"
  server_type = var.node_type
  image       = "ubuntu-22.04"
  location    = var.primary_location
  ssh_keys    = [hcloud_ssh_key.k8s.id]

  network {
    network_id = hcloud_network.primary.id
    ip         = "10.0.1.${10 + count.index}"
  }

  labels = {
    cluster = var.primary_cluster_name
    role    = "worker"
    type    = "k3s"
  }

  user_data = templatefile("${path.module}/cloud-init-worker.yaml", {
    master_ip    = tolist(hcloud_server.primary_master.network)[0].ip
    k8s_version  = var.k8s_version
    cluster_name = var.primary_cluster_name
  })

  depends_on = [
    hcloud_server.primary_master,
    hcloud_network_subnet.primary
  ]
}

# Primary cluster load balancer
resource "hcloud_load_balancer" "primary" {
  name               = "${var.primary_cluster_name}-lb"
  load_balancer_type = "lb11"
  location           = var.primary_location

  labels = {
    cluster = var.primary_cluster_name
  }
}

resource "hcloud_load_balancer_network" "primary" {
  load_balancer_id = hcloud_load_balancer.primary.id
  network_id       = hcloud_network.primary.id
  ip               = "10.0.1.254"
}

resource "hcloud_load_balancer_target" "primary" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.primary.id
  server_id        = hcloud_server.primary_master.id
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.primary]
}

# =============================================================================
# DR CLUSTER
# =============================================================================

# Private network for DR cluster
resource "hcloud_network" "dr" {
  name     = "${var.dr_cluster_name}-network"
  ip_range = "10.1.0.0/16"
}

resource "hcloud_network_subnet" "dr" {
  network_id   = hcloud_network.dr.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = "10.1.1.0/24"
}

# DR cluster control plane (master node)
resource "hcloud_server" "dr_master" {
  name        = "${var.dr_cluster_name}-master"
  server_type = var.node_type
  image       = "ubuntu-22.04"
  location    = var.dr_location
  ssh_keys    = [hcloud_ssh_key.k8s.id]

  network {
    network_id = hcloud_network.dr.id
    ip         = "10.1.1.2"
  }

  labels = {
    cluster = var.dr_cluster_name
    role    = "master"
    type    = "k3s"
  }

  user_data = templatefile("${path.module}/cloud-init-master.yaml", {
    k8s_version  = var.k8s_version
    cluster_name = var.dr_cluster_name
    node_ip      = "10.1.1.2"
    cluster_cidr = "10.52.0.0/16"
    service_cidr = "10.53.0.0/16"
  })
}

# DR cluster worker nodes
resource "hcloud_server" "dr_workers" {
  count       = var.node_count
  name        = "${var.dr_cluster_name}-worker-${count.index + 1}"
  server_type = var.node_type
  image       = "ubuntu-22.04"
  location    = var.dr_location
  ssh_keys    = [hcloud_ssh_key.k8s.id]

  network {
    network_id = hcloud_network.dr.id
    ip         = "10.1.1.${10 + count.index}"
  }

  labels = {
    cluster = var.dr_cluster_name
    role    = "worker"
    type    = "k3s"
  }

  user_data = templatefile("${path.module}/cloud-init-worker.yaml", {
    master_ip    = tolist(hcloud_server.dr_master.network)[0].ip
    k8s_version  = var.k8s_version
    cluster_name = var.dr_cluster_name
  })

  depends_on = [
    hcloud_server.dr_master,
    hcloud_network_subnet.dr
  ]
}

# DR cluster load balancer
resource "hcloud_load_balancer" "dr" {
  name               = "${var.dr_cluster_name}-lb"
  load_balancer_type = "lb11"
  location           = var.dr_location

  labels = {
    cluster = var.dr_cluster_name
  }
}

resource "hcloud_load_balancer_network" "dr" {
  load_balancer_id = hcloud_load_balancer.dr.id
  network_id       = hcloud_network.dr.id
  ip               = "10.1.1.254"
}

resource "hcloud_load_balancer_target" "dr" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.dr.id
  server_id        = hcloud_server.dr_master.id
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.dr]
}

# =============================================================================
# FIREWALL RULES
# =============================================================================

resource "hcloud_firewall" "primary" {
  name = "${var.primary_cluster_name}-firewall"

  # Allow SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow Kubernetes API
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow HTTP/HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow all traffic within private network
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "any"
    source_ips = [
      "10.0.0.0/16"
    ]
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "any"
    source_ips = [
      "10.0.0.0/16"
    ]
  }
}

resource "hcloud_firewall" "dr" {
  name = "${var.dr_cluster_name}-firewall"

  # Allow SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow Kubernetes API
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow HTTP/HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # Allow all traffic within private network
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "any"
    source_ips = [
      "10.1.0.0/16"
    ]
  }

  rule {
    direction = "in"
    protocol  = "udp"
    port      = "any"
    source_ips = [
      "10.1.0.0/16"
    ]
  }
}

# Attach firewalls to servers
resource "hcloud_firewall_attachment" "primary_master" {
  firewall_id = hcloud_firewall.primary.id
  server_ids  = [hcloud_server.primary_master.id]
}

resource "hcloud_firewall_attachment" "primary_workers" {
  count       = var.node_count > 0 ? 1 : 0
  firewall_id = hcloud_firewall.primary.id
  server_ids  = hcloud_server.primary_workers[*].id
}

resource "hcloud_firewall_attachment" "dr_master" {
  firewall_id = hcloud_firewall.dr.id
  server_ids  = [hcloud_server.dr_master.id]
}

resource "hcloud_firewall_attachment" "dr_workers" {
  count       = var.node_count > 0 ? 1 : 0
  firewall_id = hcloud_firewall.dr.id
  server_ids  = hcloud_server.dr_workers[*].id
}
