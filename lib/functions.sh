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
