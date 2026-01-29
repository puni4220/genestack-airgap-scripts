#!/bin/bash

function error_handler () {

  # define the required parameters for the function
  exit_code="$?"
  line_number="${BASH_LINENO[0]}"
  source_file="${BASH_SOURCE[1]}"
  func_name="${FUNCNAME[1]}"

  # provide details regarding the error
  echo -e "\e[31m-----------------------------------" >&2
  echo -e "Error in script: $(basename "${BASH_SOURCE[1]}")" >&2
  echo -e "Failed at line: $line_number" >&2
  echo -e "Function Name: $func_name" >&2
  echo -e "Exit code: $exit_code" >&2
  echo -e "-----------------------------------\e[0m" >&2

  exit "$exit_code"
}

function helm_values_parser_generic () {

  # obtain the required function arguments
  BASE_HELM_CHART_VERSION="$1"
  BASE_HELM_CHART_DIR="$2"
  BASE_VALUES_JSON="$BASE_HELM_CHART_DIR/values.json"
  TMP_IMG_LIST="$BASE_HELM_CHART_DIR/image_list.txt"  

  # within the base helm chart directory obtain 
  # the base helm values file
  helm_values_file=$(find "$BASE_HELM_CHART_DIR" -mindepth 1 -maxdepth 1 \
	             -iname "values.yaml" -type f)

  # convert the values.yaml file to values.json in
  # the base helm chart directory
  yaml2json "$helm_values_file" > "$BASE_VALUES_JSON"

  # from the json values file extract the required paths 
  # for generating the list of images
  jq -c paths "$BASE_VALUES_JSON" | \
  awk -v IGNORECASE=1 '/image/ && !/pull|sha|digest/' | \
  tr -d '[]"\"' | tr ',' '.' | sed 's/^/./' > "$BASE_HELM_CHART_DIR/image_paths.txt"

  # extract the images based on the paths from values.json
  while IFS= read -r path; do
	
    # check if the line in the file ends with image
    if [[ "$path" =~ \.image$ || "$path" =~ \image$ || "$path" =~ Image$ ]]; then
      
      # check if the path has a registry key but not a tag key
      if jq -e "$path".registry "$BASE_VALUES_JSON" &> /dev/null && ! jq -e "$path".tag "$BASE_VALUES_JSON" &> /dev/null; then
	# check if the path is for kubectl image
	if [[ "$path" =~ "kubectlImage" ]]; then
	  kube_version_tag=$(curl -sL "$GITHUB_BASE_URL/rackerlabs/genestack/refs/heads/main/ansible/inventory/genestack/group_vars/k8s_cluster/k8s-cluster.yml" | \
                             grep -i kube_version | awk '{print $2}')
          jq -r "$path" "$BASE_VALUES_JSON" | jq -r --arg tag "$kube_version_tag" '"\(.registry)/\(.repository):\($tag)"' \
	  >> "$TMP_IMG_LIST"
	else
	  jq -r "$path" "$BASE_VALUES_JSON" | jq -r --arg tag "$BASE_HELM_CHART_VERSION" '"\(.registry)/\(.repository):\($tag)"' \
          >> "$TMP_IMG_LIST"      
        fi
      # check if the path has a tag key but not the registry key
      elif jq -e "$path".tag "$BASE_VALUES_JSON" &> /dev/null && ! jq -e "$path".registry "$BASE_VALUES_JSON" &> /dev/null; then
        jq -r "$path" "$BASE_VALUES_JSON" | jq -r '"\(.repository):\(.tag)"' >> "$TMP_IMG_LIST"
      # check if the path has both registry and tag key
      elif jq -e "$path".registry "$BASE_VALUES_JSON" &> /dev/null && jq -e "$path".tag "$BASE_VALUES_JSON" &> /dev/null; then
        jq -r "$path" "$BASE_VALUES_JSON" | jq -r '"\(.registry)/\(.repository):\(.tag)"' >> "$TMP_IMG_LIST"
      fi
    fi
  done < "$BASE_HELM_CHART_DIR/image_paths.txt"
}



function add_helm_repo () {

  # obtain the repo name and url as an argument
  HELM_REPO_NAME="$1"
  HELM_REPO_URL="$2"
  HELM_REPO_VERSION="$3"

  # check if the URL starts with "oci://"
  if [[ "$HELM_REPO_URL" == "oci://"* ]]; then
    helm pull "$HELM_REPO_URL" --version "$HELM_REPO_VERSION" --untar --untardir /var/tmp/"$HELM_REPO_NAME" &> /dev/null
    # since we have already pulled the repo return from the function
    return 0
  else
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" &> /dev/null
    helm repo update &> /dev/null
  fi
}


function init_log () {
  local basedir="${HOME}/logs/genestack-airgap-scripts"
  local source_file="${BASH_SOURCE[1]/.sh}"
  mkdir -p ${basedir}

  touch ${basedir}/${source_file}.$$
  export LOG_FILE=${basedir}/${source_file}.$$
}

function write_log () {
  local sev="$1"
  local msg="$2"

  echo "$(date) [$sev] $msg" >> $LOG_FILE
}

function installYaml2json () {

  wget -q -O /usr/local/bin/yaml2json https://github.com/bronze1man/yaml2json/releases/download/v1.3.5/yaml2json_linux_amd64
  chmod +x /usr/local/bin/yaml2json

  write_log INFO "Installed /usr/local/bin/yaml2json"
}
