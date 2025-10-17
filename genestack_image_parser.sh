#!/bin/bash

set -euo pipefail

# import functions and constants
source "$(pwd)/lib/constants.sh"
source "$(pwd)/lib/functions.sh"

function main () {

  # initiate the log file first
  init_log

  # call the function to clone git repo
  clone_git_repo

  for base_helm_subdir in "${DEFAULT_BASE_HELM_SUBDIRS[@]}"; do
    # call the function to iterate over the list of subdirs
    parse_helm_overries "$base_helm_subdir"
  done

  }

function special_case () {

  # in this function we will handle special cases like mariadb, rabbitmq, memcached 
  # special case variable for mariadb-operator
  MARIADB_OPERATOR_IMAGE_NAME=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/mariadb-operator/mariadb-operator-helm-overrides.yaml" | jq -r '.image.repository')
  MARIADB_OPERATOR_IMAGE_TAG=$(grep 'mariadb-operator:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*mariadb-operator: *//')

  # special case variable for mariadb cluster image
  MARIADB_CLUSTER_IMAGE=$(yaml2json "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/mariadb-cluster/base/mariadb-replication.yaml" | jq -r '.spec.image')

  # append the values to the existing list
  echo "$MARIADB_OPERATOR_IMAGE_NAME:$MARIADB_OPERATOR_IMAGE_TAG" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$MARIADB_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST" 

  # obtain the URL for rabbitmq-operator image
  rabbitmq_operator_url=$(grep -i https "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-operator/base/kustomization.yaml" | awk '{print $2}')

  # obtain the IMAGE for rabbitmq-operator
  RABBITMQ_OPERATOR_IMAGE=$(curl -s -L "$rabbitmq_operator_url" | egrep -w "image: .*" | awk '{print $2}')

  # obtain the URL for rabbitmq-topology-operator image
  rabbitmq_topology_operator_url=$(grep -i https "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-topology-operator/base/kustomization.yaml"  | awk '{print $2}')

  # obtain the IMAGE for rabbitmq-topology-operator
  RABBITMQ_TOPOLOGY_OPERATOR_IMAGE=$(curl -s -L "$rabbitmq_topology_operator_url" | egrep -w "image: .*" | awk '{print $2}')

  # obtain the version for the rabbitmq-cluster-operator
  rabbitmq_operator_version=$(echo "$rabbitmq_operator_url" | grep -oP 'v\d+\.\d+\.\d+')

  # try to obtain the default rabbitmq image from rabbitmq operator
  RABBITMQ_CLUSTER_IMAGE=$(curl -s "https://raw.githubusercontent.com/rabbitmq/cluster-operator/refs/tags/$rabbitmq_operator_version/main.go" | grep -w defaultRabbitmqImage | grep management | awk '{print $3}' | sed 's/"//g')

  # append the values to the existing list
  echo "$RABBITMQ_OPERATOR_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$RABBITMQ_TOPOLOGY_OPERATOR_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$RABBITMQ_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # obtain the image for memcached
  MEMCACHED_CLUSTER_IMAGE=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/memcached/memcached-helm-overrides.yaml" | jq -r '.image | "\(.registry)/\(.repository)':'\(.tag)"')

  # append the values to the existing list
  echo "$MEMCACHED_CLUSTER_IMAGE" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
}

function special_case_helm_repo () {

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
main
special_case
special_case_helm_repo
