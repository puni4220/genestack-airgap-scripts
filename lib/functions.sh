#!/bin/bash

function init_log () {
  
  # if there's an existing log file create a backup
  if [ -f "$DEFAULT_LOG_FILE" ]; then
    # backup the existing log file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] - Log file ends; creating backup of previous log file" >> "$DEFAULT_LOG_FILE"
    LOG_BACKUP_FILE="$DEFAULT_LOG_FILE-$(date +%Y%m%d_%H%M%S)"
    mv "$DEFAULT_LOG_FILE" "$LOG_BACKUP_FILE"
  fi

  # initialize the new log file
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] - Log file created" > "$DEFAULT_LOG_FILE"
}

function write_log () {

  # obtain the log level and log message as arguments
  LOG_LEVEL="$1"
  LOG_MESSAGE="$2"

  # append the log message to the log file
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_LEVEL] - $LOG_MESSAGE" >> "$DEFAULT_LOG_FILE"
}

function clone_git_repo ()  {

  # check if the directory already exists and backup existing the directory
  if [ -d "$GENESTACK_CLONE_PATH" ]; then
    write_log "DEBUG" "Prevous clone of the repo found at $GENESTACK_CLONE_PATH"
    # backup the existing dir
    GENESTACK_BACKUP_PATH="$GENESTACK_CLONE_PATH-$(date +%Y%m%d_%H%M%S).bak"
    mv "$GENESTACK_CLONE_PATH" "$GENESTACK_BACKUP_PATH"
    write_log "INFO" "Previous repo clone backup created at $GENESTACK_BACKUP_PATH"
    # clone the repository again
    write_log "INFO" "Initiating new genestack repo clone at $GENESTACK_CLONE_PATH"
    git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
    write_log "DEBUG" "genestack repo clone successful"

  else
    # no existing clone; no backup required
    write_log "INFO" "no existing clone; cloning genestack repo at $GENESTACK_CLONE_PATH"
    git clone "${CLONE_DEFAULT_OPTIONS[@]}" "$GENESTACK_REMOTE_URL" "$GENESTACK_CLONE_PATH"
  fi
}

function parse_helm_overries () {

  # obtain the directory to parse as an argument
  YAML_FILE_DIR="$1"
  
  # temp json file
  TMP_JSON_FILE="/var/tmp/tmp.json"

  # temp helm list
  TMP_HELM_IMAGES_LIST="/var/tmp/tmp-helm-images-list.txt"

  # cd into the subdirectory
  pushd "$DEFAULT_BASE_HELM_IMAGES_PATH/$YAML_FILE_DIR" > /dev/null

  # iterate over all the yaml files into the directory and parse them
  for yaml_file in $(ls -1 .); do
    # convert the file to json and redirect the output to a tmp file
    yaml2json "$yaml_file" > "$TMP_JSON_FILE"
    if jq -e '.images.tags' "$TMP_JSON_FILE" > /dev/null; then
      # if the required path is found parse the file
      write_log "DEBUG" "parsing file $yaml_file in subdirectory $YAML_FILE_DIR"
      jq -r '.images.tags' "$TMP_JSON_FILE" > "$yaml_file".json 
      # dump the required list in a text file
      jq -r '.[]' "$yaml_file".json | sort -u | grep -iv null >> "$TMP_HELM_IMAGES_LIST"
      # remove the tmp file created
      rm -f "$TMP_JSON_FILE"
      rm -f "$yaml_file".json
    else
      # required path not found skip and remove the file
      write_log "DEBUG" "required path not found in $yaml_file in subdirectory $YAML_FILE_DIR"
      rm -f "$TMP_JSON_FILE"
    fi
  done
  popd > /dev/null
  sort -u "$TMP_HELM_IMAGES_LIST" > "$DEFAULT_GENESTACK_HELM_IMAGE_LIST"
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
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
    helm repo update &> /dev/null
  fi
}
