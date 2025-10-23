#!/bin/bash

set -euo pipefail
set -E

# import functions and constants
source "$(dirname "$(readlink -f "$0")")/lib/constants.vars"
source "$(dirname "$(readlink -f "$0")")/lib/functions.sh"

function main () {

  # initiate the log file
  init_log

  # if required clone the repo
  clone_git_repo

  for base_helm_subdir in "${DEFAULT_BASE_HELM_SUBDIRS[@]}"; do
    # call the function to iterate over the list of subdirs
    parse_helm_overries "$base_helm_subdir"
  done

  }

function clone_git_repo ()  {

  # check if the directory already exists and backup existing the directory
  if [ -d "$GENESTACK_CLONE_PATH" ]; then
    write_log "DEBUG" "Previous clone of the repo found at $GENESTACK_CLONE_PATH"
    if [[ "$FORCE_GENESTACK_CLONE" == "YES" ]]; then
      # backup the existing dir if force clone is enabled
      write_log "INFO" "Force clone of genestack repo enabled; creating backup"
      GENESTACK_BACKUP_PATH="$GENESTACK_CLONE_PATH-$(date +%Y%m%d_%H%M%S).bak"
      mv "$GENESTACK_CLONE_PATH" "$GENESTACK_BACKUP_PATH"
      write_log "INFO" "Previous repo clone backup created at $GENESTACK_BACKUP_PATH"
      # clone the repository again
      write_log "INFO" "Initiating new genestack repo clone at $GENESTACK_CLONE_PATH"
      git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
      write_log "DEBUG" "genestack repo clone successful"
    else
      # force clone is not enabled
      write_log "INFO" "Previous clone of the repo found and force clone is not enabled"
    fi
  else
    # no existing clone; no backup required
    write_log "INFO" "no existing clone; cloning genestack repo at $GENESTACK_CLONE_PATH"
    git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
  fi
}

function special_case_infra_storage_kustomize () {

  # in this function we will handle special cases like mariadb, rabbitmq, memcached 
  # special case variable for mariadb-operator
  write_log "INFO" "processing the required images for storage and infra services: mariadb, rabbitmq, memcached and rook-ceph"
  write_log "INFO" "deriving required images for mariadb: mariadb-operator, mariadb-cluster and mariadb-backup"
  write_log "DEBUG" "deriving the image name for mariadb-operator from mariadb-operator-helm-overrides.yaml"
  MARIADB_OPERATOR_IMAGE_NAME=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/mariadb-operator/mariadb-operator-helm-overrides.yaml" | jq -r '.image.repository')
  write_log "DEBUG" "deriving the mariadb-operator image tag from helm-chart-versions.yaml"
  MARIADB_OPERATOR_IMAGE_TAG=$(grep 'mariadb-operator:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*mariadb-operator: *//')

  # special case variable for mariadb-backup image
  write_log "DEBUG" "deriving required image for mariadb-backup from the configmap on github"
  MARIADB_BACKUP_IMAGE=$(curl -sL "$GITHUB_BASE_URL/mariadb-operator/mariadb-operator/refs/tags/$MARIADB_OPERATOR_IMAGE_TAG/deploy/charts/mariadb-operator/templates/configmap.yaml" | grep MARIADB_OPERATOR_IMAGE | awk '{print $2}')

  # special case variable for mariadb cluster image
  write_log "DEBUG" "deriving required image for mariadb-cluster from mariadb-replication.yaml"
  MARIADB_CLUSTER_IMAGE=$(yaml2json "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/mariadb-cluster/base/mariadb-replication.yaml" | jq -r '.spec.image')

  # append the values to the existing list
  echo "$MARIADB_OPERATOR_IMAGE_NAME:$MARIADB_OPERATOR_IMAGE_TAG" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$MARIADB_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST" 
  echo "$MARIADB_BACKUP_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  write_log "INFO" "all required images for mariadb processed and appended to the list"

  # obtain the URL for rabbitmq-operator image
  write_log "INFO" "deriving the required images for rabbitmq: rabbitmq-operator, rabbitmq-topology-operator and rabbitmq-cluster"
  write_log "DEBUG" "derive the rabbitmq-operator manifest URL from rabbitmq-operator kustomization.yaml"
  rabbitmq_operator_url=$(grep -i https "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-operator/base/kustomization.yaml" | awk '{print $2}')

  # obtain the IMAGE for rabbitmq-operator
  write_log "DEBUG" "derive the rabbitmq-operator image from the manifest URL"
  RABBITMQ_OPERATOR_IMAGE=$(curl -sL "$rabbitmq_operator_url" | egrep -w "image: .*" | awk '{print $2}')

  # obtain the URL for rabbitmq-topology-operator image
  write_log "DEBUG" "derive the rabbitmq-topology-operator manifest URL from rabbitmq-operator kustomization.yaml"
  rabbitmq_topology_operator_url=$(grep -i https "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-topology-operator/base/kustomization.yaml"  | awk '{print $2}')

  # obtain the IMAGE for rabbitmq-topology-operator
  write_log "DEBUG" "derive the rabbitmq-topology-operator image from the manifest URL"
  RABBITMQ_TOPOLOGY_OPERATOR_IMAGE=$(curl -sL "$rabbitmq_topology_operator_url" | egrep -w "image: .*" | awk '{print $2}')

  # obtain the version for the rabbitmq-cluster-operator
  write_log "DEBUG" "derive the rabbitmq-operator version from the URL"
  rabbitmq_operator_version=$(echo "$rabbitmq_operator_url" | grep -oP 'v\d+\.\d+\.\d+')

  # try to obtain the default rabbitmq image from rabbitmq operator
  write_log "DEBUG" "derive the required rabbitmq-cluster image from github"
  RABBITMQ_CLUSTER_IMAGE=$(curl -sL "$GITHUB_BASE_URL/rabbitmq/cluster-operator/refs/tags/$rabbitmq_operator_version/main.go" | grep -w defaultRabbitmqImage | grep management | awk '{print $3}' | sed 's/"//g')

  # append the values to the existing list
  echo "$RABBITMQ_OPERATOR_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$RABBITMQ_TOPOLOGY_OPERATOR_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$RABBITMQ_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  write_log "INFO" "all required images for rabbitmq processed and appended to the list"

  # obtain the image for memcached
  write_log "INFO" "deriving the required image for memcached"
  MEMCACHED_CLUSTER_IMAGE=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/memcached/memcached-helm-overrides.yaml" | jq -r '.image | "\(.registry)/\(.repository)':'\(.tag)"')

  # append the values to the existing list
  echo "$MEMCACHED_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  write_log "INFO" "all required images for memcached processed and appended to the list"

  # obtain the images required for rook-ceph cluster
  write_log "INFO" "deriving the required images for rook-ceph-operator and rook-ceph cluster"
  write_log "DEBUG" "deriving the required image for rook-ceph-operator from operator.yaml"
  ROOK_CEPH_OPERATOR_IMAGE=$(egrep "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rook-operator/base/operator.yaml" | awk '{print $2}')

  # obtain the tag for the rook-ceph-operator image
  write_log "DEBUG" "obtain the tag for the rook-ceph-operator-image"
  rook_ceph_operator_tag=$(echo "$ROOK_CEPH_OPERATOR_IMAGE" | cut -d ":" -f2)
  
  # from the tag determine the required images for csi plugins for rook-ceph cluster from github
  write_log "DEBUG" "derive the required images for rook-ceph cluster from github based on operator image tag"
  ROOK_CEPH_CSI_IMAGES=$(curl -sL "$GITHUB_BASE_URL/rook/rook/$rook_ceph_operator_tag/pkg/operator/ceph/csi/spec.go" | grep 'Default.*Image' | awk -F'"' '{print $2}')

  # determine the required image for rook-ceph cluster
  write_log "DEBUG" "deriving the required image for rook-ceph cluster"
  ROOK_CEPH_CLUSTER_IMAGE=$(egrep "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rook-cluster/base/rook-cluster.yaml" | awk '{print $2}')

  # append the values to the existing list
  echo "$ROOK_CEPH_OPERATOR_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$ROOK_CEPH_CSI_IMAGES" | tr " " "\n" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$ROOK_CEPH_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  write_log "INFO" "all required images for rook-ceph processed and appended to the list"

}

function special_case_infra_storage_helm_repo () {

  # in this function we will handle special cases which required helm pull to fetch the details
  for helm_repo_name in "${!HELM_CHARTS[@]}"; do
    # special case for envoy-gateway
    # call the function to add helm repo 
    if [[ "$helm_repo_name" == "envoy-gateway" ]]; then
      # obtain the helm chart version for envoy-gateway
      helm_chart_version=$(grep 'envoy:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*envoy: *//')
      # call the function with the required values
      if [ -d "/var/tmp/$helm_repo_name" ]; then
        # if the dir already exists remove the existing dir
	rm -rf "/var/tmp/$helm_repo_name"
      fi
      add_helm_repo "$helm_repo_name" "${HELM_CHARTS["$helm_repo_name"]}" "$helm_chart_version"
      # obtain the subdir for the helm repo
      helm_repo_subdir=$(find "/var/tmp/$helm_repo_name" -maxdepth 1 -type d | tail -1)
      # obtain the values file for the helm repo
      helm_yaml_values=$(find "$helm_repo_subdir" -maxdepth 1 -type f -iname values.yaml)
      yaml2json "$helm_yaml_values" | jq -r '.global.images' | jq -r '.[] | "\(.image)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
    
    # special case for longhorn
    elif [[ "$helm_repo_name" == "longhorn" ]]; then
      # obtain the helm chart version for longhorn
      helm_chart_version=$(grep 'longhorn:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*longhorn: *//')
      # call the function with the required values
      add_helm_repo "$helm_repo_name" "${HELM_CHARTS["$helm_repo_name"]}" "$helm_chart_version"
      # the function will only add helm repo; pull down the chart
      if [ -d "/var/tmp/$helm_repo_name" ]; then
	# if the dir already exists remove the existing directory
	rm -rf "/var/tmp/$helm_repo_name"
      fi
      helm pull "$helm_repo_name/longhorn" --version "$helm_chart_version" --untar --untardir "/var/tmp/$helm_repo_name" &> /dev/null
      # obtain the subdir for the helm repo
      helm_repo_subdir=$(find "/var/tmp/$helm_repo_name" -maxdepth 1 -type d | tail -1)
      # obtain the values file for the helm repo
      helm_values_yaml=$(find "$helm_repo_subdir" -maxdepth 1 -type f -iname values.yaml)
      yaml2json "$helm_values_yaml" | jq -r '.image.longhorn' | jq -r '.[] | "\(.repository)':'\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
      yaml2json "$helm_values_yaml" | jq -r '.image.csi' | jq -r '.[] | "\(.repository)':'\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
    
    # special case for metallb
    elif [[ "$helm_repo_name" == "metallb" ]]; then
      # obtain the chart version for metallb
      helm_chart_version=$(grep 'metallb:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*metallb: *//')
      # all the function with the required values
      add_helm_repo "$helm_repo_name" "${HELM_CHARTS["$helm_repo_name"]}" "$helm_chart_version"
      # if the helm chart repo dir already exists; remove the existing dir
      if [ -d "/var/tmp/$helm_repo_name" ]; then
        rm -rf "/var/tmp/$helm_repo_name"
      fi
      # pull the helm chart and untar the chart in the directory
      helm pull "$helm_repo_name/metallb" --version "$helm_chart_version" --untar --untardir "/var/tmp/$helm_repo_name" &> /dev/null
      # obtain the subdir for the helm repo
      helm_repo_subdir=$(find "/var/tmp/$helm_repo_name" -maxdepth 1 -type d | tail -1)
      # obtain the values file for the helm repo
      helm_values_yaml=$(find "$helm_repo_subdir" -maxdepth 1 -type f -iname values.yaml)
      # metallb doesn't provide the tag for controller and speaker images in values.yaml and they default to appVersion in chart
      yaml2json "$helm_values_yaml" | jq -r --arg tag "$helm_chart_version" '"\(.controller.image.repository):\($tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
      yaml2json "$helm_values_yaml" | jq -r --arg tag "$helm_chart_version" '"\(.speaker.image.repository):\($tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
      yaml2json "$helm_values_yaml" | jq -r '"\(.speaker.frr.image.repository):\(.speaker.frr.image.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
    fi
done
}

# set the trap for the error handling function
trap 'error_handler' ERR
main
special_case_infra_storage_kustomize
special_case_infra_storage_helm_repo
