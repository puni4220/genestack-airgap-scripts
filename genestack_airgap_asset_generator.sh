#!/bin/bash

set -euo pipefail
set -E

# import functions and constants
source "$(dirname "$(readlink -f "$0")")/lib/constants.vars"
source "$(dirname "$(readlink -f "$0")")/lib/functions.sh"

function main () {

  # initiate the log file
  #init_log

  # if required clone the repo
  clone_git_repo

  #for base_helm_subdir in "${DEFAULT_BASE_HELM_SUBDIRS[@]}"; do
    # call the function to iterate over the list of subdirs
  #  parse_helm_overries "$base_helm_subdir"
  #done

  }

function print_log () {

  # This function prints the message provided as an argument
  local log_level="$1"
  local log_message="$2"

  # Print log message with log level and timestamp
  #echo -e "\e[36m$(date '+%Y-%m-%d %H:%M:%S') [$log_level] - $(echo "$log_message" | sed 's/  */ /g')\e[0m"

  # Check if debug logs are enabled
  if [[ "$log_level" == "DEBUG" ]]; then
    if [[ "$ENABLE_DEBUG" == "TRUE" ]]; then
      echo -e "\e[32m$(date '+%Y-%m-%d %H:%M:%S') [$log_level] - $(echo "$log_message" | sed 's/  */ /g')\e[0m"
    fi
  elif [[ "$log_level" != "DEBUG" ]]; then
    echo -e "\e[36m$(date '+%Y-%m-%d %H:%M:%S') [$log_level] - $(echo "$log_message" | sed 's/  */ /g')\e[0m"
  fi
}

function clone_git_repo ()  {

  # In this function if required we clone the genestack repository
  
  print_log "INFO" "Checking if the repo needs to be cloned"

  # check if the directory already exists and backup existing the directory
  if [ -d "$GENESTACK_CLONE_PATH" ]; then
    print_log "DEBUG" "Previous clone of the repo found at $GENESTACK_CLONE_PATH"
    
    if [[ "$FORCE_GENESTACK_CLONE" == "YES" ]]; then
      # backup the existing dir if force clone is enabled
      print_log "INFO" "Force clone of genestack repo enabled; creating backup"
      GENESTACK_BACKUP_PATH="$GENESTACK_CLONE_PATH-$(date +%Y%m%d_%H%M%S).bak"
      mv "$GENESTACK_CLONE_PATH" "$GENESTACK_BACKUP_PATH"
      print_log "INFO" "Previous repo clone backup created at $GENESTACK_BACKUP_PATH"
      # clone the repository again
      print_log "INFO" "Initiating new genestack repo clone at $GENESTACK_CLONE_PATH"
      print_log "DEBUG" "Cloning the repo with options ${CLONE_DEFAULT_OPTIONS[@]}"
      git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
      print_log "DEBUG" "genestack repo clone successful"
    
    else
      # force clone is not enabled
      print_log "INFO" "Previous clone of the repo found and force clone is not enabled"
    fi
  
  else
    # no existing clone; no backup required
    print_log "INFO" "no existing clone; cloning genestack repo at $GENESTACK_CLONE_PATH"
    print_log "DEBUG" "Cloning the repo with options ${CLONE_DEFAULT_OPTIONS[@]}"
    git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
  fi
}

function generate_list_storage () {

  # In this function we handle the generation of container
  # images required for storage components. Below are the 
  # storage services for which the list is currently generated
  # 1) longhorn
  # 2) rook-ceph
  # 3) topolvm

  # Declare the local variables for helm charts
  local tmp_helm_values="/tmp/Values.yaml"
  local tmp_helm_chart_yaml="/tmp/Chart.yaml"



  print_log "INFO" "Generate required image list for storage components"

  # Generate the list of container images for longhorn

  print_log "INFO" "Generating required images for longhorn"
  
  # First obtain the version of helm chart for longhorn from
  # the helm-chart-versions.yaml from the genestack repo
  helm_chart_version=$(grep 'longhorn:' "$GENESTACK_CHART_VERSION_FILE" | \
    sed 's/.*longhorn: *//')

  # If the tmp values.yaml exists remove it first
  if [ -f "$tmp_helm_values" ]; then
    rm -f "$tmp_helm_values"
  fi

  # For longhorn we don't override the images in a local helm
  # overrides file; pull the values.yaml file for the version
  # of longhorn helm chart directly from github for obtaining
  # the required container images for longhorn
  curl -o "$tmp_helm_values" \
    -sL "$GITHUB_BASE_URL/longhorn/charts/refs/tags/longhorn-$helm_chart_version/charts/longhorn/values.yaml"

  print_log "INFO" "Generate the list of required container images for longhorn \
    from values.yaml file"
  # From the values.yaml for longhorn extract the required images for longhorn
  yaml2json "$tmp_helm_values" | jq -r '.image.longhorn' | jq -r '.[] | "\(.repository)':'\(.tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  print_log "INFO" "Generate the list of required container images for longhorn csi"
  # From the values.yaml for longhorn extra the required images for longhorn csi
  yaml2json "$tmp_helm_values" | jq -r '.image.csi' | jq -r '.[] | "\(.repository)':'\(.tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the list of container images for rook-ceph

  print_log "INFO" "Generating required images for rook-ceph"

  # For rook-ceph we have multiple images
  # 1) rook-ceph-operator: defined in base-kustomize/rook-operator/base/operator.yaml 
  # 2) rook-ceph-cluster: defined in base-kustomize/rook-cluster/base/rook-cluster.yaml
  # 3) rook-ceph-csi-images: defined in spec.go inside the Github repo for rook-ceph-operator
  # 4) rook-ceph-toolbox: defined in base-kustomize/rook-cluster/base/toolbox.yaml

  print_log "INFO" "Generate the required image for rook-ceph-operator"
  
  # Obtain the image for rook-ceph-operator from kustomize operator.yaml
  rook_ceph_operator_image=$(egrep "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rook-operator/base/operator.yaml" | \
    awk '{print $2}')

  print_log "INFO" "Generate the required image for rook-ceph-cluster"

  # Obtain the required image for rook-ceph-cluster from kustomize rook-cluster.yaml
  rook_ceph_cluster_image=$(egrep "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rook-cluster/base/rook-cluster.yaml" | \
    awk '{print $2}')

  print_log "INFO" "Generate the required image for rook-ceph-toolbox"

  # Obtain the required image for rook-ceph-toolbox
  rook_ceph_toolbox_image=$(egrep "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rook-cluster/base/toolbox.yaml" | \
    awk '{print $2}')

  # Obtain the tag for the rook-ceph-operator container image
  rook_ceph_operator_tag=$(echo "$rook_ceph_operator_image" | \
    cut -d ":" -f2)

  print_log "INFO" "Generate the required images for rook-ceph-csi"

  # Download the spec.go file from Github for rook-ceph-operator based on the rook-ceph-operator tag
  rook_ceph_csi_images=$(curl -sL "$GITHUB_BASE_URL/rook/rook/$rook_ceph_operator_tag/pkg/operator/ceph/csi/spec.go" | \
    grep 'Default.*Image' | awk -F'"' '{print $2}')

  # Append the container images for rook-ceph to the list
  echo -e "$rook_ceph_operator_image\n$rook_ceph_cluster_image\
	  \n$rook_ceph_toolbox_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Append the images for rook-ceph-csi to the list
  echo "$rook_ceph_csi_images" | tr ' ' '\n' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the list of container images for topolvm
 
  print_log "INFO" "Generating required images for topolvm"

  # By default for topolvm no helm overrides are specified for
  # container images and it falls back to the images specified
  # in Chart.yaml. Also there is no helm chart version specified
  # for topolvm so we use the master on Github

  # if Chart.yaml already exists remove it
  if [ -f "$tmp_helm_chart_yaml" ]; then
    rm -f "$tmp_helm_chart_yaml"
  fi

  # By default the helm chart version should be master
  helm_chart_version="main"

  # Download the Chart.yaml from Github for the topolvm helm chart
  curl -o "$tmp_helm_chart_yaml" \
    -sL "$GITHUB_BASE_URL/topolvm/topolvm/refs/heads/$helm_chart_version/charts/topolvm/Chart.yaml"

  # From the Chart.yaml extract extract the required images
  yaml2json "$tmp_helm_chart_yaml" | jq -r ".annotations" | jq '."artifacthub.io/images"' | \
    sed -e 's/\\n/\n/g' | sed 's/"//g' | grep -oP 'image: \K.*' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

}

function generate_list_infrastructure () {

  # In this function we handle the generation of container
  # images required for infrastructure components. Below are the 
  # infrastructure services for which the list is currently generated
  # 1) rabbitmq
  # 2) mariadb
  # 3) memcached
  # 4) envoy-proxy (Gateway API)
  # 5) kube-ovn
  # 6) metallb
  # 7) libvirt

  print_log "INFO" "Generate required image list for infrastructure components"

  # Generate the list of container images for rabbitmq

  print_log "INFO" "Generating required images for rabbitmq"

  # For rabbitmq we have:
  # 1) rabbitmq-operator image
  # 2) rabbitmq-topology-operator image
  # 3) rabbitmq-cluster image

  print_log "INFO" "Generate the required image for rabbitmq-operator"

  # For rabbitmq-operator we obtain the URL from the manifest provided
  # by base-kustomize/rabbitmq-operator/base/kustomization.yaml and then 
  # from the URL we obtain the operator image
  rabbitmq_operator_url=$(grep -i https "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-operator/base/kustomization.yaml" | \
    awk '{print $2}')
  
  rabbitmq_operator_image=$(curl -sL "$rabbitmq_operator_url" | egrep -w "image: .*" | \
    awk '{print $2}')

  print_log "INFO" "Generate the required image for rabbitmq-topology-operator"

  # For rabbitmq-topology-operator we obtain the URL from the manifest
  # provided by base-kustomize/rabbitmq-topology-operator/base/kustomization.yaml
  # and then from the URL we obtain the image
  rabbitmq_topo_operator_image=$(curl -sL "$(grep -i https \
    "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/rabbitmq-topology-operator/base/kustomization.yaml"  | \
    awk '{print $2}')" | egrep -w "image: .*" | awk '{print $2}')

  print_log "INFO" "Generate the required image for rabbitmq-cluster"

  # For the rabbitmq-cluster image we need to obtain it from main.go file
  # for the rabbitmq-operator from Github; the image will depend upon the 
  # version of the rabbitmq-operator being deployed; we obtain the tag 
  # for the rabbitmq-operator
  rabbitmq_operator_version=$(echo "$rabbitmq_operator_url" | grep -oP 'v\d+\.\d+\.\d+')

  # Obtain the image from main.go based on the rabbitmq_operator_version
  rabbitmq_cluster_image=$(curl -sL "$GITHUB_BASE_URL/rabbitmq/cluster-operator/refs/tags/$rabbitmq_operator_version/main.go" | \
    awk -F'"' '/defaultRabbitmqImage/ && /management/ {print $2}')
  
  # Append the images to the list
  echo "$rabbitmq_operator_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$rabbitmq_topo_operator_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$rabbitmq_cluster_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the list of container images for mariadb

  print_log "INFO" "Generating required images for mariadb"

  # For rabbitmq we have:
  # 1) mariadb-operator image
  # 2) mariadb-cluster image
  # 3) mariadb-backup image

  print_log "INFO" "Generating required image for mariadb-operator"

  # For mariadb-operator image; the image is specified in 
  # base-helm-configs/mariadb-operator/mariadb-operator-helm-overrides.yaml
  mariadb_operator_image=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/mariadb-operator/mariadb-operator-helm-overrides.yaml" | \
    jq -r '.image.repository')

  # For the tag for the mariadb-operator image; the default is to
  # use the version of the helm chart for the mariadb-operator
  mariadb_operator_image_tag=$(grep 'mariadb-operator:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*mariadb-operator: *//')

  print_log "INFO" "Generating required image for mariadb-cluster"

  # For mariadb-cluster image; the image is directly specified in
  # base-kustomize/mariadb-cluster/base/mariadb-replication.yaml
  mariadb_cluster_image=$(yaml2json "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/mariadb-cluster/base/mariadb-replication.yaml" | \
    jq -r '.spec.image')

  print_log "INFO" "Generating required image for mariadb-backup"
  
  # For mariadb-backup image; we determine the image from the configmap
  # for the version of helm chart for the mariadb-operator from Github
  mariadb_backup_image=$(curl -sL "$GITHUB_BASE_URL/mariadb-operator/mariadb-operator/refs/tags/$mariadb_operator_image_tag/deploy/charts/mariadb-operator/templates/configmap.yaml" | \
    grep "MARIADB_OPERATOR_IMAGE" | awk '{print $2}')

  # Append the images to the list
  echo "$mariadb_operator_image:$mariadb_operator_image_tag" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$mariadb_cluster_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$mariadb_backup_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the list of container images for memcached

  print_log "INFO" "Generating required images for memcached"

  # for memcached we have the image defined in helm overrides
  # base-helm-configs/memcached/memcached-helm-overrides.yaml
  memcached_cluster_image=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/memcached/memcached-helm-overrides.yaml" | \
    jq -r '.image | "\(.registry)/\(.repository)':'\(.tag)"')

  # Append the images to the list
  echo "$memcached_cluster_image" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  print_log "INFO" "Generating requird images for envoyproxy-gateway"

  # For envoyproxy-gateway we would need to download the helm chart
  # and then extract the required images from the Values.yaml;
  
  # First obtain the version of the helm chart from helm-chart-versions.yaml
  envoy_chart_version=$(grep 'envoy:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*envoy: *//')

  # If the directory for helm chart already exists remove it
  if [ -d "/var/tmp/envoyproxy" ]; then
    rm -rf "/var/tmp/envoyproxy"
  fi

  # Pull the helm chart and untar it in the directory
  helm pull oci://docker.io/envoyproxy/gateway-helm --version "$envoy_chart_version" --untar \
    --untardir /var/tmp/envoyproxy &> /dev/null

  # Find the helm chart directory
  helm_chart_dir=$(find /var/tmp/envoyproxy/ -mindepth 1 -maxdepth 1 -type d)

  # Within the helm chart directory find the values.yaml
  helm_values_yaml=$(find "$helm_chart_dir" -iname "values.yaml" -type f)

  # From the helm values extract the required images
  yaml2json "$helm_values_yaml" | jq -r '.global.images' | jq -r '.[] | "\(.image)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Cleanup the tmp helm chart directory for envoyproxy-gateway
  rm -rf /var/tmp/envoyproxy || true

  # Generate the list of container images for kube-ovn

  print_log "INFO" "Generating required images for kube-ovn"

  # For kube-ovn we have defined the required container images
  # in base-helm-configs/kube-ovn/kube-ovn-helm-overrides.yaml

  kube_ovn_helm_registry=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/kube-ovn/kube-ovn-helm-overrides.yaml" | \
    jq -r '.global.registry.address')

  kube_ovn_tag=$(yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/kube-ovn/kube-ovn-helm-overrides.yaml" | \
    jq -r '.global.images.kubeovn.tag')

  # For kube-ovn we have 2 images 
  # 1) kube-ovn
  # 2) vpc-nat-gateway

  # Append the images to the list
  echo "$kube_ovn_helm_registry/kube-ovn:$kube_ovn_tag" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  echo "$kube_ovn_helm_registry/vpc-nat-gateway:$kube_ovn_tag" >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the list of container images for metallb

  print_log "INFO" "Generating the required images for metallb"

  # For metallb we have
  # 1) controller
  # 2) speaker
  # 3) rbacProxy
  # 4) frr

  # We can obtain the values.yaml directly for the metallb helm chart
  # from Github for the version of helm chart for metallb we need

  # Obtain the version of helm chart for metallb
  metallb_chart_version=$(grep 'metallb:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*metallb: *//')

  # If tmp values.yaml already exists remove the tmp and the download the file
  if [ -f "$TMP_HELM_VALUES_YAML" ]; then
    rm -f "$TMP_HELM_VALUES_YAML"
  fi

  curl -o "$TMP_HELM_VALUES_YAML" \
    -sL "$GITHUB_BASE_URL/metallb/metallb/refs/tags/$metallb_chart_version/charts/metallb/values.yaml"
 
  # Append the values to the list
  yaml2json "$TMP_HELM_VALUES_YAML" | jq -r --arg tag "$metallb_chart_version" '"\(.controller.image.repository):\($tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  yaml2json "$TMP_HELM_VALUES_YAML" | jq -r --arg tag "$metallb_chart_version" '"\(.speaker.image.repository):\($tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  yaml2json "$TMP_HELM_VALUES_YAML" | jq -r '"\(.prometheus.rbacProxy.repository):\(.prometheus.rbacProxy.tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  yaml2json "$TMP_HELM_VALUES_YAML" | jq -r '"\(.speaker.frr.image.repository):\(.speaker.frr.image.tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
}

function generate_list_additional () {

  # In this function we handle the generation of container
  # images required for additional services. Below are the service
  # for which the list of container images are generated
  # 1) redis
  # 2) OVN 

  # Generate the list of container images for redis

  print_log "INFO" "Generating the required images for redis"

  # For redis we have
  # 1) redis-operator 
  # 2) redis-sentinel
  # 3) redis-exporter
  # 4) redis-replication

  # For redis-operator download the helm chart because there's
  # a difference in the container image on Github and in the
  # helm values.yaml file

  # First obtain the version of redis-operator from the 
  # helm-chart-versions.yaml
  redis_chart_version=$(grep 'redis-operator:' "$GENESTACK_CHART_VERSION_FILE" | sed 's/.*redis-operator: *//')

  # If the directory for helm chart already exists remove the directory
  # and then download the helm chart
  if [ -d "/var/tmp/redis" ]; then
    rm -rf "/var/tmp/redis"
  fi

  # Add the helm repo for redis-operator chart
  helm repo add redis-operator https://ot-container-kit.github.io/helm-charts/ &> /dev/null
  helm repo update &> /dev/null

  # Download the helm chart for redis-operator
  helm pull redis-operator/redis-operator --version "$redis_chart_version" \
    --untar --untardir "/var/tmp/redis" 

  # Find the helm chart directory
  helm_chart_dir=$(find "/var/tmp/redis" -mindepth 1 -maxdepth 1 -type d)

  # Find the helm values.yaml for redis-operator
  helm_values_yaml=$(find "$helm_chart_dir" -mindepth 1 -maxdepth 1 -iname "values.yaml" -type f)

  # From the values.yaml extract the required container images for redis-operator
  yaml2json "$helm_values_yaml" | jq -r --arg tag "$redis_chart_version" '"\(.redisOperator.imageName):\($tag)"' \
    >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  
  # For redis-replication and redis-exporter the container image is
  # in base-helm-configs/redis-operator-replication/redis-replication-helm-overrides.yaml
  yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/redis-operator-replication/redis-replication-helm-overrides.yaml" | \
    jq -r '.redisReplication | "\(.image):\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/redis-operator-replication/redis-replication-helm-overrides.yaml" | \
    jq -r '.redisExporter | "\(.image):\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST" 

  # For redis-sentinel and redis-exporter the container image is 
  # in base-helm-configs/redis-sentinel/redis-sentinel-helm-overrides.yaml
  yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/redis-sentinel/redis-sentinel-helm-overrides.yaml" | \
    jq -r '.redisSentinel | "\(.image):\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
  yaml2json "$DEFAULT_BASE_HELM_IMAGES_PATH/redis-sentinel/redis-sentinel-helm-overrides.yaml" | \
    jq -r '.redisExporter | "\(.image):\(.tag)"' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  # Generate the requird list of images for OVN
  
  print_log "INFO" "Generating the required images for OVN"

  # For ovn the required container images are in
  # base-kustomize/ovn/base/ovn-setup.yaml
  grep -w "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/ovn/base/ovn-setup.yaml" | awk '{ print $2}' | \
    sed 's/"//g' | sort -u >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

  print_log "INFO" "Generating the required images for ovn-backup"

  # For ovn backup the requird container images are 
  # in base-kustomize/ovn-backup/base/ovn-backup.yaml
  grep -w "image:" "$DEFAULT_BASE_KUSTOMIZE_IMAGES_PATH/ovn-backup/base/ovn-backup.yaml" | \
    awk '{print $2}' >> "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"

}

# set the trap for the error handling function
trap 'error_handler' ERR
main
generate_list_storage
generate_list_infrastructure
generate_list_additional
