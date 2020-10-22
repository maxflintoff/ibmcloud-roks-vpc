provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
  generation       = var.generation
}

resource "ibm_resource_group" "rg_create" {
  name = var.resource_group

  count = var.create_resource_group ? 1 : 0
}

data "ibm_resource_group" "rg_load" {
  name = var.resource_group

  count = var.create_resource_group ? 0 : 1
}

locals {
  rg_id = var.create_resource_group ? ibm_resource_group.rg_create[0].id : data.ibm_resource_group.rg_load[0].id
}

resource "ibm_is_vpc" "vpc" {
  name                      = "${var.cluster_name}-vpc"
  resource_group            = local.rg_id
  tags                      = var.tags
  address_prefix_management = "auto"
}

data "ibm_is_zones" "vpc_zones" {
  region = var.region
}

resource "ibm_is_public_gateway" "gateways" {

  for_each = toset(data.ibm_is_zones.vpc_zones.zones)

  name           = "${var.cluster_name}-pgw-${each.key}"
  vpc            = ibm_is_vpc.vpc.id
  zone           = each.value
  tags           = var.tags
  resource_group = local.rg_id
}

resource "ibm_is_subnet" "subnets" {

  for_each = toset(data.ibm_is_zones.vpc_zones.zones)

  name                     = "${var.cluster_name}-sub-${each.key}"
  vpc                      = ibm_is_vpc.vpc.id
  zone                     = each.value
  resource_group           = local.rg_id
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateways[each.value].id
}

resource "ibm_is_security_group_rule" "worker_nodeports_udp" {

  group     = ibm_is_vpc.vpc.default_security_group
  direction = "inbound"
  remote    = "0.0.0.0/0"
  udp {
    port_min = 30000
    port_max = 32767
  }
}

resource "ibm_is_security_group_rule" "worker_nodeports_tcp" {

  group     = ibm_is_vpc.vpc.default_security_group
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 30000
    port_max = 32767
  }
}

resource "ibm_resource_instance" "cos_instance" {
  name              = "${var.cluster_name}-cos"
  resource_group_id = local.rg_id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
}

locals {
  ocp_version = "${var.oc_version}_openshift"
}

resource "ibm_container_vpc_cluster" "cluster" {
  name         = var.cluster_name
  vpc_id       = ibm_is_vpc.vpc.id
  kube_version = local.ocp_version
  entitlement  = var.entitlement
  flavor       = var.worker_flavor
  worker_count = var.workers_per_zone
  worker_labels = {
    "pool"   = "default"
    "flavor" = var.worker_flavor
  }
  resource_group_id = local.rg_id
  tags              = var.tags
  cos_instance_crn  = ibm_resource_instance.cos_instance.crn
  wait_till         = "OneWorkerNodeReady"

  dynamic "zones" {
    for_each = ibm_is_subnet.subnets

    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }
}

resource "ibm_container_vpc_worker_pool" "ocs_pool" {

  depends_on = [
    ibm_is_volume.ocs_vol_pool
  ]

  cluster           = ibm_container_vpc_cluster.cluster.id
  resource_group_id = local.rg_id
  worker_pool_name  = "ocs_pool"
  flavor            = var.ocs_flavor
  vpc_id            = ibm_is_vpc.vpc.id
  worker_count      = 1
  entitlement       = var.entitlement
  labels = {
    "pool"   = "ocs"
    "flavor" = var.ocs_flavor
  }

  dynamic "zones" {
    for_each = ibm_is_subnet.subnets

    content {
      subnet_id = zones.value.id
      name      = zones.value.zone
    }
  }
}

resource "ibm_is_volume" "ocs_vol_pool" {

  for_each = toset(data.ibm_is_zones.vpc_zones.zones)

  name           = "${var.cluster_name}-ocs-pool-${each.key}"
  profile        = "10iops-tier"
  zone           = each.value
  capacity       = 512
  tags           = var.tags
  resource_group = local.rg_id
}

resource "null_resource" "initalise_cli" {

  provisioner "local-exec" {
    command = <<-EOT
      ibmcloud login --apikey ${var.ibmcloud_api_key} -g ${local.rg_id} -r ${var.region} -q;
      ibmcloud oc cluster config -c ${ibm_container_vpc_cluster.cluster.id} --admin -q;
      ibmcloud oc cluster addon disable vpc-block-csi-driver -c ${ibm_container_vpc_cluster.cluster.id} -f;
    EOT
  }
}

data "external" "get_worker_details" {

  depends_on = [
    ibm_is_volume.ocs_vol_pool,
    ibm_container_vpc_worker_pool.ocs_pool
  ]

  program = ["/bin/bash", "-c", "ibmcloud ks worker ls -c ${ibm_container_vpc_cluster.cluster.id} --worker-pool ocs_pool --output json -q | jq -c '.[] | {(.location): .id}' | jq --slurp --null-input 'inputs | add'"]
}

resource "null_resource" "wait_label_ocs_nodes" {
  depends_on = [
    null_resource.initalise_cli,
    data.external.get_worker_details
  ]

  provisioner "local-exec" {
    command = <<-EOT
    until [ $(oc get nodes -l pool=ocs --no-headers -o name | wc -l) = 3 ]; do echo "waiting for nodes" && sleep 5; done;
    oc label node -l pool=ocs cluster.ocs.openshift.io/openshift-storage='' --overwrite;
    EOT
  }
}

resource "null_resource" "bind_ocs_volumes" {

  depends_on = [
    null_resource.initalise_cli,
    data.external.get_worker_details,
    null_resource.wait_label_ocs_nodes
  ]

  for_each = ibm_is_volume.ocs_vol_pool

  provisioner "local-exec" {
    command = <<-EOT
    ibmcloud oc storage attachment create -c ${ibm_container_vpc_cluster.cluster.id} --volume ${each.value.id} -w ${data.external.get_worker_details.result[each.key]};
    EOT
  }
}

resource "null_resource" "sleep" {

  depends_on = [
    null_resource.bind_ocs_volumes
  ]

  provisioner "local-exec" {
    command = <<-EOT
    sleep 1200;
    EOT
  }
}

data "external" "get_disk_ids" {

  depends_on = [
    null_resource.bind_ocs_volumes,
    ibm_container_vpc_cluster.cluster,
    null_resource.sleep
  ]

  program = ["/bin/bash", "-c", "echo \"$(for i in $(oc get node -l cluster.ocs.openshift.io/openshift-storage= -o jsonpath='{ .items[*].metadata.name }'); do oc debug node/$${i} -q -- chroot /host ls -l /dev/disk/by-id/ | grep -E 'vdd'; done)\" | jq --raw-input '[split(\" \") | .[9]] | map({ (.): . }) | add'  |  jq --slurp 'add'"]
}

locals {
  disk_ids    = values(data.external.get_disk_ids.result)
  pv_template = templatefile("${path.module}/ocs/los-pv.tmpl", { devices = local.disk_ids })
  los_sub_template = templatefile("${path.module}/ocs/los-subscription.tmpl", { oc_version = var.oc_version })
  ocs_sub_template = templatefile("${path.module}/ocs/ocs-subscription.tmpl", { oc_version = var.oc_version })
}

resource "null_resource" "create_pvs" {

  depends_on = [
    data.external.get_disk_ids
  ]

  provisioner "local-exec" {
    command = <<-EOT
    echo "${local.los_sub_template}" | oc create -f -
    sleep 180;
    echo "${local.pv_template}" | oc create -f -
    EOT
  }
}

resource "null_resource" "create_ocs" {

  depends_on = [
    ibm_container_vpc_worker_pool.ocs_pool,
    null_resource.create_pvs
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "${local.ocs_sub_template}" | oc create -f -
      sleep 180;
      oc create -f ./ocs/ocs-storagecluster.yaml;
      sleep 60;
      oc patch DaemonSet/csi-cephfsplugin -n openshift-storage --patch "$(cat ./ocs/csi-cephfsplugin-ds-patch.json)";
      oc patch DaemonSet/csi-rbdplugin -n openshift-storage --patch "$(cat ./ocs/csi-rbdplugin-ds-patch.json)";
      oc patch ClusterRole/system:node --patch "$(cat ./ocs/systemnode-clusterrole-patch.json)";
    EOT
  }
}

resource "null_resource" "patch_registry" {

  depends_on = [
    null_resource.create_ocs
  ]

  provisioner "local-exec" {
    command = <<-EOT
      oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"disableRedirect":true}}' --type=merge;
    EOT
  }
}