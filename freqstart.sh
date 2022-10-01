#!/usr/bin/env bash
clear
#
# Copyright (c) https://github.com/freqstart/freqstart/
#
# You are welcome to improve the code. If you just use the script and like it,
# remember that it took a lot of time, testing and also money for infrastructure.
# You can contribute by donating to the following wallets:
#
# BTC 1M6wztPA9caJbSrLxa6ET2bDJQdvigZ9hZ
# ETH 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
# BSC 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

readonly FS_NAME="freqstart"
readonly FS_VERSION='v3.0.0'
readonly FS_TMP="/tmp/${FS_NAME}"
readonly FS_SYMLINK="/usr/local/bin/${FS_NAME}"
readonly FS_FILE="${FS_NAME}.sh"

FS_DIR="$(dirname "$(readlink --canonicalize-existing "${0}" 2> /dev/null)")"
readonly FS_DIR
readonly FS_PATH="${FS_DIR}/${FS_FILE}"
readonly FS_DIR_USER_DATA="${FS_DIR}/user_data"
readonly FS_AUTO="${FS_PATH} --auto"

readonly FS_NETWORK="${FS_NAME}_network"
readonly FS_NETWORK_SUBNET='172.35.0.0/16'
readonly FS_NETWORK_GATEWAY='172.35.0.1'

readonly FS_PROXY_BINANCE="${FS_NAME}_binance"
readonly FS_PROXY_BINANCE_YML="${FS_DIR}/${FS_PROXY_BINANCE}.yml"
readonly FS_PROXY_BINANCE_IP='172.35.0.253'
readonly FS_PROXY_KUCOIN="${FS_NAME}_kucoin"
readonly FS_PROXY_KUCOIN_YML="${FS_DIR}/${FS_PROXY_KUCOIN}.yml"
readonly FS_PROXY_KUCOIN_IP='172.35.0.252'

readonly FS_NGINX="${FS_NAME}_nginx"
readonly FS_NGINX_YML="${FS_DIR}/${FS_NAME}_nginx.yml"
readonly FS_NGINX_CONFD="/etc/nginx/conf.d"
readonly FS_NGINX_CONFD_FREQUI="${FS_NGINX_CONFD}/frequi.conf"
readonly FS_NGINX_CONFD_HTPASSWD="${FS_NGINX_CONFD}/.htpasswd"
readonly FS_CERTBOT="${FS_NAME}_certbot"
readonly FS_CERTBOT_CRON="${FS_PATH} --cert"
readonly FS_FREQUI="${FS_NAME}_frequi"

readonly FS_STRATEGIES="${FS_DIR}/${FS_NAME}_strategies.json"
readonly FS_STRATEGIES_CUSTOM="${FS_DIR}/${FS_NAME}_strategies_custom.json"
readonly FS_STRATEGIES_URL="https://raw.githubusercontent.com/freqstart/freqstart/stable/freqstart_strategies.json"

readonly FS_REGEX="(${FS_PROXY_KUCOIN}|${FS_PROXY_BINANCE}|${FS_NGINX}|${FS_CERTBOT}|${FS_FREQUI})"

FS_HASH="$(xxd -l 8 -ps /dev/urandom)"
readonly FS_HASH

trap _fsCleanup_ EXIT
trap '_fsErr_ "${FUNCNAME:-.}" ${LINENO}' ERR

#
# DOCKER
#

_fsDockerVersionCompare_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerImage="${1}"
  local _dockerVersionLocal=''
  local _dockerVersionHub=''
  
  _dockerVersionHub="$(_fsDockerVersionHub_ "${_dockerImage}")"
  _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerImage}")"
  
  if [[ -z "${_dockerVersionHub}" ]]; then
    # unkown
    echo 2
  else
    if [[ "${_dockerVersionHub}" = "${_dockerVersionLocal}" ]]; then
      # equal
      echo 0
    else
      # greater
      echo 1
    fi
  fi
}

_fsDockerVersionLocal_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerImage="${1}"
  local _dockerVersionLocal=''
  
  if [[ -n "$(docker images -q "${_dockerImage}")" ]]; then
    _dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerImage}" \
    | sed 's/.*@//')"
    
    if [[ -n "${_dockerVersionLocal}" ]]; then
      echo "${_dockerVersionLocal}"
    fi
  fi
}

_fsDockerVersionHub_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerImage="${1}"
  local _dockerRepo="${_dockerImage%:*}"
  local _dockerTag="${_dockerImage##*:}"
  local _dockerUrl=''
  local _token=''
  local _acceptM="application/vnd.docker.distribution.manifest.v2+json"
  local _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
  local _dockerName=''
  local _dockerManifest=''
  
  _dockerUrl="https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}"
  _dockerName="${FS_NAME}"'_'"$(echo "${_dockerRepo}" | sed "s,\/,_,g" | sed "s,\-,_,g")"
  _dockerManifest="${FS_TMP}/${FS_HASH}_${_dockerName}_${_dockerTag}.md"
  _token="$(curl --connect-timeout 10 -s "https://auth.docker.io/token?scope=repository:${_dockerRepo}:pull&service=registry.docker.io"  | jq -r '.token' || true)"
  
  if [[ -n "${_token}" ]]; then
    curl --connect-timeout 10 -s --header "Accept: ${_acceptM}" --header "Accept: ${_acceptML}" --header "Authorization: Bearer ${_token}" \
    -o "${_dockerManifest}" -I -s -L "${_dockerUrl}" \
    || _fsMsgError_ "Download failed: ${_dockerUrl}"
  fi
  
  if [[ -f "${_dockerManifest}" ]]; then    
    _dockerVersionHub="$(grep -oE 'etag: "(.*)"' "${_dockerManifest}" \
    | sed 's,\",,g' \
    | sed 's,etag: ,,' \
    || true)"
    
    if [[ -n "${_dockerVersionHub}" ]]; then
      echo "${_dockerVersionHub}"
    else
      _fsMsgError_ 'Cannot retrieve docker manifest.'
    fi
  else
    _fsMsgError_ 'Cannot connect to docker hub.'
  fi
}

_fsDockerVersionImage_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerImage="${1}"
  local _dockerCompare=''
  local _dockerStatus=2
  local _dockerVersionLocal=''
  
  _dockerCompare="$(_fsDockerVersionCompare_ "${_dockerImage}")"
  
  if [[ "${_dockerCompare}" -eq 0 ]]; then
    # docker hub image version is equal
    _dockerStatus=0
  elif [[ "${_dockerCompare}" -eq 1 ]]; then
    # docker hub image version is greater
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerImage}")"
    
    if [[ -n "${_dockerVersionLocal}" ]]; then
      # update from docker hub      
      docker pull "${_dockerImage}"
      if [[ "$(_fsDockerVersionCompare_ "${_dockerImage}")" -eq 0 ]]; then
        _dockerStatus=1
      fi
    else
      # install from docker hub
      docker pull "${_dockerImage}"
      
      if [[ "$(_fsDockerVersionCompare_ "${_dockerImage}")" -eq 0 ]]; then
        _dockerStatus=1
      fi
    fi
  elif [[ "${_dockerCompare}" -eq 2 ]]; then
    # docker hub image version is unknown
    if [[ -n "$(docker images -q "${_dockerImage}")" ]]; then
      _dockerStatus=0
    fi
  fi
  
  if [[ "${_dockerStatus}" -eq 2 ]]; then
      _fsMsgError_ "Image not found: ${_dockerImage}"
  else
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerImage}")"
    # return local version docker image digest
    echo "${_dockerVersionLocal}"
  fi
}

_fsDockerContainerPs_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerName="${1}"
  local _dockerMode="${2:-}" # optional: all
  local _dockerPs=''
  local _dockerPsAll=''
  local _dockerMatch=1
  
  # credit: https://serverfault.com/a/733498
  # credit: https://stackoverflow.com/a/44731522
  if [[ "${_dockerMode}" = "all" ]]; then
    _dockerPsAll="$(docker ps -a --format '{{.Names}}' | grep -ow "${_dockerName}" || true)"
    [[ -n "${_dockerPsAll}" ]] && _dockerMatch=0
  else
    _dockerPs="$(docker ps --format '{{.Names}}' | grep -ow "${_dockerName}" || true)"
    [[ -n "${_dockerPs}" ]] && _dockerMatch=0
  fi
  
  if [[ "${_dockerMatch}" -eq 0 ]]; then
    # docker container exist
    echo 0
  else
    # docker container does not exist
    echo 1
  fi
}

_fsDockerContainerName_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerId="${1}"
  local _dockerName=''
  
  _dockerName="$(docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
  
  if [[ -n "${_dockerName}" ]]; then
    # return docker container name
    echo "${_dockerName}"
  fi
}

_fsDockerRemove_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerName="${1}"
  
  # stop and remove active and non-active docker container
  if [[ "$(_fsDockerContainerPs_ "${_dockerName}" "all")" -eq 0 ]]; then
    docker update --restart=no "${_dockerName}" > /dev/null
    docker stop "${_dockerName}" > /dev/null
    docker rm -f "${_dockerName}" > /dev/null
    
    if [[ "$(_fsDockerContainerPs_ "${_dockerName}" "all")" -eq 0 ]]; then
      _fsMsgError_ "Cannot remove container: ${_dockerName}"
    fi
  fi
}

_fsDockerProjectImages_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _ymlPath="${1}"
  local _ymlImages=''
  local _ymlImagesDeduped=()
  local _ymlImage=''
  local _dockerImage=''
  local _error=0
  
  # credit: https://stackoverflow.com/a/39612060
  _ymlImages=()
  while read -r; do
    _ymlImages+=( "$REPLY" )
  done < <(grep -vE '^\s+#' "${_ymlPath}" \
  | grep 'image:' \
  | sed "s,\s,,g" \
  | sed "s,image:,,g" || true)
  
  if (( ${#_ymlImages[@]} )); then
    while read -r; do
    _ymlImagesDeduped+=( "$REPLY" )
    done < <(_fsArrayDedupe_ "${_ymlImages[@]}")
    
    for _ymlImage in "${_ymlImagesDeduped[@]}"; do
      _dockerImage="$(_fsDockerVersionImage_ "${_ymlImage}")"
      
      if [[ -z "${_dockerImage}" ]]; then
        _error=$((_error+1))
      fi
    done
    
    if [[ "${_error}" -eq 0 ]]; then
      echo 0
    else
      echo 1
    fi
  else
    echo 1
  fi
}

_fsDockerProjectStrategies_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _ymlPath="${1}"
  local _strategies=()
  local _strategiesDeduped=()
  local _strategy=''
  local _strategiesDir=()
  local _strategiesDirDeduped=()
  local _strategyDir=''
  local _strategyPath=''
  local _strategyFile=''
  local _strategyPathFound=1
  local _error=0
  
  # download or update implemented strategies
  while read -r; do
    _strategies+=( "$REPLY" )
  done < <(grep -vE '^\s+#' "${_ymlPath}" \
  | grep "strategy" \
  | grep -v "strategy-path" \
  | sed "s,\=,,g" \
  | sed "s,\",,g" \
  | sed "s,\s,,g" \
  | sed "s,\-\-strategy,,g" || true)
  
  if (( ${#_strategies[@]} )); then
    while read -r; do
      _strategiesDeduped+=( "$REPLY" )
    done < <(_fsArrayDedupe_ "${_strategies[@]}")
    
    # validate optional strategy paths in project file
    while read -r; do
      _strategiesDir+=( "$REPLY" )
    done < <(grep -vE '^\s+#' "${_ymlPath}" \
    | grep "strategy-path" \
    | sed "s,\=,,g" \
    | sed "s,\",,g" \
    | sed "s,\s,,g" \
    | sed "s,\-\-strategy-path,,g" \
    | sed "s,^/[^/]*,${FS_DIR}," || true)
    
    # add default strategy path
    _strategiesDir+=( "${FS_DIR_USER_DATA}/strategies" )
    
    while read -r; do
      _strategiesDirDeduped+=( "$REPLY" )
    done < <(_fsArrayDedupe_ "${_strategiesDir[@]}")
    
    for _strategy in "${_strategiesDeduped[@]}"; do
      _fsDockerStrategy_ "${_strategy}"
      
      for _strategyDir in "${_strategiesDirDeduped[@]}"; do
        _strategyPath="${_strategyDir}"'/'"${_strategy}"'.py'
        _strategyFile="${_strategyPath##*/}"
        if [[ -f "${_strategyPath}" ]]; then
          _strategyPathFound=0
          break
        fi
      done
      
      if [[ "${_strategyPathFound}" -eq 1 ]]; then
        _fsMsg_ 'Strategy file not found: '"${_strategyFile}"
        _error=$((_error+1))
      fi
      
      _strategyPathFound=1
    done
  fi
  
  if [[ "${_error}" -eq 0 ]]; then
    echo 0
  else
    echo 1
  fi
}

_fsDockerProjectConfigs_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _ymlPath="${1}"
  local _configs=()
  local _configsDeduped=()
  local _config=''
  local _configPath=''
  local _error=0
  
  while read -r; do
    _configs+=( "$REPLY" )
  done < <(grep -vE '^\s+#' "${_ymlPath}" \
  | grep -e "\-\-config" -e "\-c" \
  | sed "s,\=,,g" \
  | sed "s,\",,g" \
  | sed "s,\s,,g" \
  | sed "s,\-\-config,,g" \
  | sed "s,\-c,,g" \
  | sed "s,\/freqtrade\/,,g" || true)
  
  if (( ${#_configs[@]} )); then
    while read -r; do
      _configsDeduped+=( "$REPLY" )
    done < <(_fsArrayDedupe_ "${_configs[@]}")
    
    for _config in "${_configsDeduped[@]}"; do
      _configPath="${FS_DIR}/${_config}"
      if [[ ! -f "${_configPath}" ]]; then
        _fsMsg_ "Config file does not exist: ${_configPath##*/}"
        _error=$((_error+1))
      fi
    done
  fi
  
  if [[ "${_error}" -eq 0 ]]; then
    echo 0
  else
    echo 1
  fi
}

_fsDockerProjectCompose_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _project="${1}"
  local _projectService="${2:-}" # optional: service
  local _projectFile="${_project##*/}"
  local _projectFileName="${_projectFile%.*}"
  local _projectName="${_projectFileName//\-/\_}"
  local _projectImages=1
  local _projectStrategies=1
  local _projectConfigs=1
  local _projectContainers=()
  local _projectContainer=''
  
  local _containerActive=''
  local _containerName=''
  local _containerCmd=''
  local _containerLogfile=''
  
  local _error=0

  _projectStrategies="$(_fsDockerProjectStrategies_ "${_project}")"
  _projectConfigs="$(_fsDockerProjectConfigs_ "${_project}")"
  _projectImages="$(_fsDockerProjectImages_ "${_project}")"
  
  [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
  [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
  [[ "${_projectStrategies}" -eq 1 ]] && _error=$((_error+1))
  
  if [[ "${_error}" -eq 0 ]]; then
    # shellcheck disable=SC2015,SC2086 # ignore shellcheck
    docker compose -f ${_project} -p ${_projectName} up --no-start --no-recreate ${_projectService} > /dev/null 2> /dev/null || true

    while read -r; do
      _projectContainers+=( "$REPLY" )
    done < <(docker compose -f "${_project}" -p "${_projectName}" ps -q)

    for _projectContainer in "${_projectContainers[@]}"; do
      _containerName="$(_fsDockerContainerName_ "${_projectContainer}")"
      _containerActive="$(_fsDockerContainerPs_ "${_containerName}")"
      
        if [[ "${FS_OPTS_AUTO}" -eq 1 ]]; then
          if [[ ! "${_containerName}" =~ $FS_REGEX ]]; then
            if [[ "$(_fsCaseConfirmation_ "Start container: ${_containerName}")" -eq 1 ]]; then
              if [[ "${_containerActive}" -eq 1 ]]; then
                _fsDockerRemove_ "${_containerName}"
              fi
              _fsMsg_ 'Skipping...'
              continue
            fi
          else
            _fsMsg_ "Start container: ${_containerName}"
          fi
        fi
        
        # create docker network; credit: https://stackoverflow.com/a/59878917
        docker network create --subnet="${FS_NETWORK_SUBNET}" --gateway "${FS_NETWORK_GATEWAY}" "${FS_NETWORK}" > /dev/null 2> /dev/null || true
        
        # connect container to docker network
        if [[ "${_containerName}" = "${FS_PROXY_BINANCE}" ]]; then
          docker network connect --ip "${FS_PROXY_BINANCE_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        elif [[ "${_containerName}" = "${FS_PROXY_KUCOIN}" ]]; then
          docker network connect --ip "${FS_PROXY_KUCOIN_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        else
          docker network connect "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        fi
        
        # set restart to no to filter faulty containers
        docker update --restart=no "${_containerName}" > /dev/null
        
        # get container command
        _containerCmd="$(docker inspect --format="{{.Config.Cmd}}" "${_projectContainer}" \
        | sed "s,\[, ,g" \
        | sed "s,\], ,g" \
        | sed "s,\",,g" \
        | sed "s,\=, ,g" \
        | sed "s,\/freqtrade\/,,g")"
        
      if [[ -n "${_containerCmd}" ]]; then
        # remove logfile
        _containerLogfile="$(echo "${_containerCmd}" | { grep -Eos "\--logfile [-A-Za-z0-9_/]+.log " || true; } \
        | sed "s,\--logfile,," \
        | sed "s, ,,g")"
        
        if [[ -n "${_containerLogfile}" ]]; then
          _containerLogfile="${FS_DIR_USER_DATA}/logs/${_containerLogfile##*/}"
          sudo rm -f "${_containerLogfile}"
        fi
        
        # check for frequi port and config
        if [[ ! "${_containerName}" =~ $FS_REGEX ]]; then
          _containerApiJson="$(echo "${_containerCmd}" | grep -o "${FS_FREQUI}.json" || true)"
          
          if [[ -n "${_containerApiJson}" ]]; then
            if [[ "$(_fsDockerContainerPs_ "${FS_FREQUI}")" -eq 0 ]]; then
              _fsMsg_ "API url: /${FS_NAME}/${_containerName}"
            else
              _fsMsg_ "FreqUI is not active!"
            fi
          fi
        fi
      fi
        
      # start container
      if [[ "${_containerActive}" -eq 1 ]]; then
        docker start "${_containerName}" > /dev/null
      else
        docker restart "${_containerName}" > /dev/null
      fi
    done
  fi
}

_fsDockerProjectRun_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _project="${1}"
  local _projectService="${2:-}" # optional: service
  shift;shift;_projectArgs="${*:-}" # optional: arguments
  local _projectFile="${_project##*/}"
  local _projectFileName="${_projectFile%.*}"
  local _projectName="${_projectFileName//\-/\_}"
  local _projectImages=1
  local _projectShell=''
  
  local _error=0
  
  _projectImages="$(_fsDockerProjectImages_ "${_project}")"
  
  [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
  
  if [[ "${_error}" -eq 0 ]]; then
    # workaround to execute shell from variable; help: open for suggestions
    _projectShell="$(printf -- '%s' "${_projectArgs}" | grep -oE '^/bin/sh -c' || true)"
    
    if [[ -n "${_projectShell}" ]]; then
      _projectArgs="$(printf -- '%s' "${_projectArgs}" | sed 's,/bin/sh -c ,,')"
      # shellcheck disable=SC2015,SC2086 # ignore shellcheck
      docker compose -f ${_project} -p ${_projectName} run --rm "${_projectService}" /bin/sh -c "${_projectArgs}"
    else
      # shellcheck disable=SC2015,SC2086 # ignore shellcheck
      docker compose -f ${_project} -p ${_projectName} run --rm ${_projectService} ${_projectArgs}
    fi
  fi
}

_fsDockerProjectValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _project="${1}"
  local _projectFile="${_project##*/}"
  local _projectFileName="${_projectFile%.*}"
  local _projectName="${_projectFileName//\-/\_}"
  local _projectContainers=()
  local _projectContainer=''
  local _containerActive=''
  local _containerName=''
    
  while read -r; do
    _projectContainers+=( "$REPLY" )
  done < <(docker compose -f "${_project}" -p "${_projectName}" ps -q)

  for _projectContainer in "${_projectContainers[@]}"; do
    _containerName="$(_fsDockerContainerName_ "${_projectContainer}")"
    _containerActive="$(_fsDockerContainerPs_ "${_containerName}")"
    
      if [[ "${_containerActive}" -eq 0 ]]; then
        # set restart to unless-stopped
        docker update --restart=unless-stopped "${_containerName}" > /dev/null
        _fsMsg_ '[SUCCESS] Container is active: '"${_containerName}"
      else
        _fsDockerRemove_ "${_containerName}"
        _fsMsg_ '[WARNING] Container is not active: '"${_containerName}"
      fi
  done
  
  # update every 12 hours and 3 minutes
  _fsCrontab_ "3 */12 * * *" "${FS_AUTO}"
  # clear orphaned networks
  yes $'y' | docker network prune > /dev/null || true
}

_fsDockerProjectQuit_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _project="${1}"
  local _projectFile="${_project##*/}"
  local _projectFileName="${_projectFile%.*}"
  local _projectName="${_projectFileName//\-/\_}"
  local _projectContainers=()
  local _projectContainer=''
  local _containerActive=''
  local _containerName=''
  
  while read -r; do
    _projectContainers+=( "$REPLY" )
  done < <(docker compose -f "${_project}" -p "${_projectName}" ps -q)

  for _projectContainer in "${_projectContainers[@]}"; do
    _containerName="$(_fsDockerContainerName_ "${_projectContainer}")"
    _containerActive="$(_fsDockerContainerPs_ "${_containerName}")"
    
    if [[ "$(_fsCaseConfirmation_ "Quit container: ${_containerName}")" -eq 0 ]]; then
      _fsDockerRemove_ "${_containerName}"
      if [[ "$(_fsDockerContainerPs_ "${_containerName}")" -eq 1 ]]; then
        _fsMsg_ "[SUCCESS] Container is removed: ${_containerName}"
      else
        _fsMsg_ "[WARNING] Container not removed: ${_containerName}"
      fi
    else
      _fsMsg_ 'Skipping...'
    fi
  done
}

_fsDockerStrategy_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _strategyName="${1}"
  local _strategyFile=''
  local _strategyTmp="${FS_TMP}/${FS_HASH}_${_strategyName}"
  local _strategyDir="${FS_DIR_USER_DATA}/strategies/${_strategyName}"
  local _strategyUrls=()
  local _strategyUrlsDeduped=()
  local _strategyUrl=''
  local _strategyPath=''
  local _strategyPathTmp=''
  local _strategiesTmp="${FS_TMP}/${FS_HASH}_${FS_STRATEGIES##*/}"
  
  # create the strategy config
  _fsDownload_ "${FS_STRATEGIES_URL}" "${_strategiesTmp}"

  # update strategie file if necessary
  if ! cmp --silent "${_strategiesTmp}" "${FS_STRATEGIES}"; then
    cp -a "${_strategiesTmp}" "${FS_STRATEGIES}"
  fi
  
  if [[ -f "${FS_STRATEGIES}" ]]; then
    
    while read -r; do
    _strategyUrls+=( "$REPLY" )
    done < <(jq -r ".${_strategyName}[]?"' // empty' "${FS_STRATEGIES}")
    
      # add custom strategies from file
    if [[ -f "${FS_STRATEGIES_CUSTOM}" ]]; then
      while read -r; do
      _strategyUrls+=( "$REPLY" )
      done < <(jq -r ".${_strategyName}[]?"' // empty' "${FS_STRATEGIES_CUSTOM}")
    fi
    
    if (( ${#_strategyUrls[@]} )); then
      while read -r; do
      _strategyUrlsDeduped+=( "$REPLY" )
      done < <(_fsArrayDedupe_ "${_strategyUrls[@]}")
    fi
    
    if (( ${#_strategyUrlsDeduped[@]} )); then
      mkdir -p "${_strategyTmp}"
      # note: sudo because of freqtrade docker user
      sudo mkdir -p "${_strategyDir}"
      
      for _strategyUrl in "${_strategyUrlsDeduped[@]}"; do
        _strategyFile="${_strategyUrl##*/}"
        _strategyPath="${_strategyDir}/${_strategyFile}"
        _strategyPathTmp="${_strategyTmp}/${_strategyFile}"
        
        _fsDownload_ "${_strategyUrl}" "${_strategyPathTmp}"
        
        # check if strategy file already exist
        if [[ -f "${_strategyPath}" ]]; then
          # only update if temp file is different and not empty
          if [ -s _strategyPathTmp ]; then
            if ! cmp --silent "${_strategyPathTmp}" "${_strategyPath}"; then
              sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
            fi
          fi
        else
          sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
        fi
      done
    else
      _fsMsg_ "[WARNING] Strategy not implemented: ${_strategyName}"
    fi
  else
    _fsMsgError_ "Strategy config file not found!"
  fi
}

_fsDockerProject_() {
  local _projects=("${@}")
  local _project=''
  
  if (( ! ${#_projects[@]} )); then
    readarray -d '' _projects < <(find "${FS_DIR}" -maxdepth 1 ! -name "${FS_NAME}*" -name "*.yml" -print0)
  fi
    
  if (( ${#_projects[@]} )); then
    if [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
      for _project in "${_projects[@]}"; do
          _fsDockerProjectQuit_ "${_project}"
      done
    else
      for _project in "${_projects[@]}"; do
          _fsDockerProjectCompose_ "${_project}"
      done
      
      _fsCdown_ 30 "for any errors..."
      
      for _project in "${_projects[@]}"; do
          _fsDockerProjectValidate_ "${_project}"
      done
    fi
  else
    _fsMsg_ "[WARNING] No docker project files found."
  fi
}

_fsDockerReset_() {
  _fsCrontabRemove_ "${FS_AUTO}"
  _fsCrontabRemove_ "${FS_CERTBOT_CRON}"
  
  # credit: https://stackoverflow.com/a/69921248
  docker ps -a -q 2> /dev/null | xargs -I {} docker rm -f {} 2> /dev/null || true
  docker network prune --force 2> /dev/null || true
  docker image ls -q 2> /dev/null | xargs -I {} docker image rm -f {} 2> /dev/null || true
}

#
# SETUP
#

_fsSetupUser_() {
  local	_user=''
  local	_userId=''
  local	_userSudoer=''
  local	_userSudoerFile=''
  local _userTmp=''
  local _userTmpDir=''
  local _userTmpDPath=''
  local _getDocker="${FS_DIR}/get-docker-rootless.sh"
  
  _userId="$(id -u)"
  _user="$(id -u -n)"
  _userSudoer="${_user} ALL=(ALL:ALL) NOPASSWD: ALL"
  _userSudoerFile="/etc/sudoers.d/${_user}"
  
  # validate if current user is root
  if [[ "${_userId}" -eq 0 ]]; then
    _fsMsg_ "You are logged in as root user!"
    _fsMsg_ "Create a new user or log in to an existing non-root user."
    
    while true; do
      read -rp '? Username: ' _userTmp
      
      if [[ -z "${_userTmp}" ]]; then
        _fsCaseEmpty_
      else
        if [[ "$(_fsCaseConfirmation_ "Is the username \"${_userTmp}\" correct?")" -eq 0 ]]; then
          # validate if user exist
          if id -u "${_userTmp}" >/dev/null 2>&1; then
            _fsMsg_ "User \"${_userTmp}\" already exist."
            
            if [[ "$(_fsCaseConfirmation_ "Login to user \"${_userTmp}\" now?")" -eq 0 ]]; then
              break
            else
              _userTmp=''
            fi
          else
            _fsMsg_ "User \"${_userTmp}\" does not exist."

            if [[ "$(_fsCaseConfirmation_ "Create user \"${_userTmp}\" now?")" -eq 0 ]]; then
              sudo adduser --gecos '' "${_userTmp}"
              break
            else
              _userTmp=''
            fi
          fi
        else
          _userTmp=''
        fi
      fi
    done
    
    # validate if user exist
    if id -u "${_userTmp}" >/dev/null 2>&1; then            
      # add user to sudo group
      sudo usermod -a -G sudo "${_userTmp}" || true
      
      _userTmpDir="$(bash -c "cd ~$(printf %q "${_userTmp}") && pwd")/${FS_NAME}"
      _userTmpPath="${_userTmpDir}/${FS_NAME}.sh"
      
      mkdir -p "${_userTmpDir}"
      
      # copy freqstart to new user home
      cp -a "${FS_PATH}" "${_userTmpDir}/${FS_FILE}" 2> /dev/null || true      
      sudo chown -R "${_userTmp}":"${_userTmp}" "${_userTmpDir}"
      sudo chmod +x "${_userTmpPath}"
      
      # lock password of root user
      if [[ "$(_fsCaseConfirmation_ "Disable password for \"${_user}\" user (recommended)?")" -eq 0 ]]; then
        sudo usermod -L "${_user}"
      fi
      
      _fsMsg_ "#"
      _fsMsg_ "# Continue setup with: ${_userTmpDir}/${FS_FILE} --setup"
      _fsMsg_ "#"
      
      # remove scriptlock and symlink
      rm -rf "${FS_TMP}"
      sudo rm -f "${FS_SYMLINK}"
      
      # machinectl is needed to set $XDG_RUNTIME_DIR properly
      sudo rm -f "${FS_PATH}" && sudo machinectl shell "${_userTmp}@"
      exit 0
    else
      _fsMsgError_ "Cannot create user: ${_userTmp}"
    fi
  else
    # validate if user can use sudo
    if ! id -nGz "${_user}" | grep -qzxF 'sudo'; then
      _fsMsgError_ 'User cannot use "sudo". Log in as "root" and run the following command: '"usermod -a -G sudo ${_user}"
    fi
    
    if ! sudo grep -q "${_userSudoer}" "${_userSudoerFile}" 2> /dev/null; then
      echo "${_userSudoer}" | sudo tee "/etc/sudoers.d/${_user}" > /dev/null
    fi
  fi
}

_fsSetupPrerequisites_() {
  local _upgradesConf="/etc/apt/apt.conf.d/50unattended-upgrades"
  
  # install and validate all required packages
  _setupPkgs_ "curl" "cron" "docker-ce" "systemd-container" "uidmap" "dbus-user-session" "jq"
  
  # setup unattended server upgrades
  if [[ ! -f "${_upgradesConf}" ]]; then
    sudo apt -o Dpkg::Options::="--force-confdef" dist-upgrade -y && \
    sudo apt install -y unattended-upgrades && \
    sudo apt autoremove -y
    sudo dpkg-reconfigure -plow unattended-upgrades
  fi
  
  # shellcheck disable=SC2002 # ignore shellcheck
  if ! sudo cat "${_upgradesConf}" | grep -q "# ${FS_NAME}"; then
    # add automatic reboots to upgrade config
    printf -- '%s\n' \
    '' \
    "// ${FS_NAME}" \
    'Unattended-Upgrade::Automatic-Reboot "true";' \
    '' | sudo tee -a "${_upgradesConf}" > /dev/null
  fi
}

_fsSetupRootless_() {
  local	_user=''
  local	_userId=''
  local _userBashrc=''
  local _getDocker="${FS_DIR}/get-docker.sh"
  local _getDockerUrl="https://get.docker.com/rootless"
  
  _user="$(id -u -n)"
  _userId="$(id -u)"
  _userBashrc="$(getent passwd "${_user}" | cut -d: -f6)/.bashrc"

  # validate if linger is set for current user
  if ! sudo loginctl show-user "${_user}" 2> /dev/null | grep -q 'Linger=yes'; then
    sudo systemctl stop docker.socket docker.service || true
    sudo systemctl disable --now docker.socket docker.service || true
    sudo rm /var/run/docker.sock || true
    
    _fsDownload_ "${_getDockerUrl}" "${_getDocker}"
    sudo chmod +x "${_getDocker}"
    sh "${_getDocker}"
    rm -f "${_getDocker}"
    
    sudo loginctl enable-linger "${_user}"
  fi
  
  # shellcheck disable=SC2002 # ignore shellcheck
  if ! cat "${_userBashrc}" | grep -q "# ${FS_NAME}"; then
    # add docker variables to bashrc; note: path variable should be set but left the comment in
    printf -- '%s\n' \
    '' \
    "# ${FS_NAME}" \
    "#export PATH=/home/${_user}/bin:\$PATH" \
    "export DOCKER_HOST=unix:///run/user/${_userId}/docker.sock" \
    '' >> "${_userBashrc}"
  fi
  
  # export docker host for initial setup and crontab
  export "DOCKER_HOST=unix:///run/user/${_userId}/docker.sock"
}

_setupPkgs_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _pkgs=("$@")
  local _pkgsList=''
  local _pkg=''
  local _status=''
  local _getDocker="${FS_DIR}/get-docker.sh"
  local _getDockerUrl="https://get.docker.com"
  local _error=0
  local _update=0
  
  for _pkg in "${_pkgs[@]}"; do
    if [[ "$(_setupPkgsValidate_ "${_pkg}")" -eq 1 ]]; then
      _update=$((_update+1))
    fi
  done

  if [[ "${_update}" -gt 0 ]]; then
    sudo apt update || true
  fi

  for _pkg in "${_pkgs[@]}"; do
    if [[ "$(_setupPkgsValidate_ "${_pkg}")" -eq 1 ]]; then
      if [[ "${_pkg}" = 'docker-ce' ]]; then
        _fsDownload_ "${_getDockerUrl}" "${_getDocker}"
        sudo chmod +x "${_getDocker}"
        sh "${_getDocker}"
        rm -f "${_getDocker}"
      else
        sudo apt install -y -q "${_pkg}"
      fi
    fi
    
    if [[ "$(_setupPkgsValidate_ "${_pkg}")" -eq 1 ]]; then
      _error=$((_error+1))
      _fsMsg_ "Cannot install: ${_pkg}"
    fi
  done
  
  if [[ "${_error}" -gt 0 ]]; then
    _fsMsgError_ "Not all required software packages are installed."
  fi
}

_setupPkgsValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _pkg="${1}"
  local _status=''
  
  _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" 2> /dev/null | grep "install ok installed" || true)"
  
  if [[ -n "${_status}" ]]; then
    echo 0
  else
    echo 1
  fi
}

# FREQTRADE
# credit: https://github.com/freqtrade/freqtrade
_setupFreqtrade_() {
  local _yml="${FS_DIR}/${FS_NAME}_freqtrade.yml"
  
  if [[ ! -d "${FS_DIR_USER_DATA}" ]]; then
    _fsFileCreate_ "${_yml}" \
    '---' \
    "version: '3'" \
    'services:' \
    '  freqtrade:' \
    '    image: freqtradeorg/freqtrade:latest' \
    '    container_name: freqtrade' \
    '    volumes:' \
    '      - "'"${FS_DIR_USER_DATA}"':/freqtrade/user_data"'
    
    # create user_data folder
    _fsDockerProjectRun_ "${_yml}" 'freqtrade' \
    "create-userdir --userdir /freqtrade/${FS_DIR_USER_DATA##*/}"
    
    sudo rm -f "${_yml}"
  fi
}

# BINANCE-PROXY; credit: https://github.com/nightshift2k/binance-proxy
_setupBinanceProxy_() {  
  if [[ "$(_fsDockerContainerPs_ "${FS_PROXY_BINANCE}")" -eq 1 ]]; then
    # binance proxy json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}.json" \
    '{' \
    '    "exchange": {' \
    '        "name": "binance",' \
    '        "ccxt_config": {' \
    '            "enableRateLimit": false,' \
    '            "urls": {' \
    '                "api": {' \
    '                    "public": "http://'"${FS_PROXY_BINANCE_IP}"':8990/api/v3"' \
    '                }' \
    '            }' \
    '        },' \
    '        "ccxt_async_config": {' \
    '            "enableRateLimit": false' \
    '        }' \
    '    }' \
    '}'
    
    # binance proxy futures json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}_futures.json" \
    '{' \
    '    "exchange": {' \
    '        "name": "binance",' \
    '        "ccxt_config": {' \
    '            "enableRateLimit": false,' \
    '            "urls": {' \
    '                "api": {' \
    '                    "public": "http://'"${FS_PROXY_BINANCE_IP}"':8991/api/v3"' \
    '                }' \
    '            }' \
    '        },' \
    '        "ccxt_async_config": {' \
    '            "enableRateLimit": false' \
    '        }' \
    '    }' \
    '}'
    
    # binance proxy project file
    _fsFileCreate_ "${FS_PROXY_BINANCE_YML}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${FS_PROXY_BINANCE}:" \
    "    image: nightshift2k/binance-proxy:latest" \
    "    container_name: ${FS_PROXY_BINANCE}" \
    "    command: >" \
    "      --port-spot=8990" \
    "      --port-futures=8991" \
    "      --verbose" \
    
    _fsDockerProject_ "${FS_PROXY_BINANCE_YML}"
  fi
  
  if [[ "$(_fsDockerContainerPs_ "${FS_PROXY_BINANCE}")" -eq 0 ]]; then
    _fsMsg_ "Binance proxy is active: --config /freqtrade/user_data/${FS_PROXY_BINANCE}.json"
  fi
}

# KUCOIN-PROXY; credit: https://github.com/mikekonan/exchange-proxy
_setupKucoinProxy_() {  
  if [[ "$(_fsDockerContainerPs_ "${FS_PROXY_KUCOIN}")" -eq 1 ]]; then
    # kucoin proxy json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_KUCOIN}.json" \
    '{' \
    '    "exchange": {' \
    '        "name": "kucoin",' \
    '        "ccxt_config": {' \
    '            "enableRateLimit": false,' \
    '            "timeout": 60000,' \
    '            "urls": {' \
    '                "api": {' \
    '                    "public": "http://'"${FS_PROXY_KUCOIN_IP}"':8980/kucoin",' \
    '                    "private": "http://'"${FS_PROXY_KUCOIN_IP}"':8980/kucoin"' \
    '                }' \
    '            }' \
    '        },' \
    '        "ccxt_async_config": {' \
    '            "enableRateLimit": false,' \
    '            "timeout": 60000' \
    '        }' \
    '    }' \
    '}'
    
    # kucoin proxy project file
    _fsFileCreate_ "${FS_PROXY_KUCOIN_YML}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${FS_PROXY_KUCOIN}:" \
    "    image: mikekonan/exchange-proxy:latest-${FS_ARCHITECTURE}" \
    "    container_name: ${FS_PROXY_KUCOIN}" \
    "    command: >" \
    "      -port 8980" \
    "      -verbose 1"
    
    _fsDockerProject_ "${FS_PROXY_KUCOIN_YML}"
  fi
  
  if [[ "$(_fsDockerContainerPs_ "${FS_PROXY_KUCOIN}")" -eq 0 ]]; then
    _fsMsg_ "Kucoin proxy is active: --config /freqtrade/user_data/${FS_PROXY_KUCOIN}.json"
  fi
}


#
# FUNCTIONAL
#

_fsLogo_() {
  printf -- '%s\n' \
  "    __                  _            _" \
  "   / _|_ _ ___ __ _ ___| |_ __ _ _ _| |_" \
  "  |  _| '_/ -_) _\` (__-\  _/ _\` | '_|  _|" \
  "  |_| |_| \___\__, /___/\__\__,_|_|  \__|" \
  "                 |_|               ${FS_VERSION}" \
  "" >&2
}

_fsArchitecture_() {
  local _os=''
  local _osCmd=''
  local _osSupported=1
  local _architecture=''
  local _architectureCmd=''
  local _architectureSupported=1
  
  _osCmd="$(uname -s || true)"
  _architectureCmd="$(uname -m || true)"

  if [[ -n "${_osCmd}" ]]; then
    case ${_osCmd} in
      Darwin)
        _os='osx'
        ;;
      Linux)
        _os='linux'
        _osSupported=0
        ;;
      CYGWIN*|MINGW32*|MSYS*|MINGW*)
        _os='windows'
        ;;
      *)
        _os='unkown'
        _fsMsg_ '[ERROR] Unable to determine operating system.'
        exit 1
        ;;
    esac
  fi
  
  if [[ -n "${_architectureCmd}" ]]; then
    case ${_architectureCmd} in
      i386|i686)
        _architecture='386'
        ;;
      x86_64)
        _architecture='amd64'
        _architectureSupported=0
        ;;
      arm)
        if dpkg --print-architecture | grep -q 'arm64'; then
          _architecture='arm64'
        else
          _architecture='arm'
        fi
        ;;
      *)
        _architecture='unkown'
        _fsMsg_ '[ERROR] Unable to determine architecture.'
        exit 1
    esac
  fi

  if [[ "${_osSupported}" -eq 1 ]] || [[ "${_architectureSupported}" -eq 1 ]]; then
    _fsMsg_ "[WARNING] Your OS (${_os}/${_architecture}) may not be fully supported."
    
    if [[ "FS_OPTS_DEBUG" -eq 1 ]]; then
      _fsMsg_ 'Bypass this warning with: --debug'
      exit 1
    fi
  else
    echo "${_architecture}"
  fi
}

_fsFileCreate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _file="${1}"
  local _input=()
  local _output=''

  shift; _input=("${@}")
  _output="$(printf -- '%s\n' "${_input[@]}")"
  echo "${_output}" | sudo tee "${_file}" > /dev/null
}

_fsDownload_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _url="${1}"
  local _output="${2}"

  curl --connect-timeout 10 -fsSL "${_url}" -o "${_output}" || _fsMsgError_ "Download failed: ${_url}"
}

_fsRandomHex_() {
  local _length="${1:-16}"
  local _string=''
  
  _string="$(xxd -l "${_length}" -ps /dev/urandom)"
  
  echo "${_string}"
}

_fsRandomBase64_() {
  local _length="${1:-24}"
  local _string=''
  
  _string="$(xxd -l "${_length}" -ps /dev/urandom | xxd -r -ps | base64)"
  echo "${_string}"
}

_fsRandomBase64UrlSafe_() {
  local _length="${1:-32}"
  local _string=''
  
  _string="$(xxd -l "${_length}" -ps /dev/urandom | xxd -r -ps | base64 | tr -d = | tr + - | tr / _)"
  
  echo "${_string}"
}

_fsErr_() {
  local _error="${?}"
  
  printf -- '%s\n' "Error in ${FS_FILE} in function ${1} on line ${2}" >&2
  exit "${_error}"
}

_fsScriptlock_() {
  local _lockDir="${FS_TMP}/${FS_NAME}.lock"
  
  if [[ -d "${_lockDir}" ]]; then
    # set error to 99 and do not remove tmp dir for debugging
    _fsMsgError_ "Script is already running: sudo rm -rf ${FS_TMP}" 99
  elif ! mkdir -p "${_lockDir}" 2> /dev/null; then
    _fsMsgError_ "Unable to acquire script lock: ${_lockDir}"
  fi
}

_fsCleanup_() {
  local _error="${?}"
  local _user=''
  local _userTmp=''
  
  # workaround for freqtrade user_data permissions
  if [[ -d "${FS_DIR_USER_DATA}" ]]; then
    _user="$(id -u -n)"
    # shellcheck disable=SC2012 # ignore shellcheck
    _userTmp="$(ls -ld "${FS_DIR_USER_DATA}" | awk 'NR==1 {print $3}')"
    
    sudo chown -R "${_userTmp}:${_user}" "${FS_DIR_USER_DATA}"
    sudo chmod -R g+w "${FS_DIR_USER_DATA}"
  fi
  
  trap - ERR EXIT SIGINT SIGTERM
  
  if [[ "${_error}" -ne 99 ]]; then
    rm -rf "${FS_TMP}"
    _fsCdown_ 1 'to remove script lock...'
  fi
}

_fsCaseConfirmation_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _question="${1}"
  local _yesNo=''
  
  while true; do
    read -rp "? ${_question} (y/n) " _yesNo
    case ${_yesNo} in
      [Yy]*)
        echo 0
        break
        ;;
      [Nn]*)
        echo 1
        break
        ;;
      *)
        _fsCaseInvalid_
        ;;
    esac
  done
}

_fsCaseInvalid_() {
  _fsMsg_ 'Invalid response!'
}

_fsCaseEmpty_() {
  _fsMsg_ 'Response cannot be empty!'
}

_fsMsg_() {
  local _msg="${1:-}"
  
  printf -- '%s\n' \
  "  ${_msg}" >&2
}

_fsMsgError_() {
  local _msg="${1:-}"
  local -r _code="${2:-90}"
  
  printf -- '%s\n' \
  '' \
  "! [ERROR] ${_msg}" >&2
  
  exit "${_code}"
}

_fsCdown_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _secs="${1}"; shift
  local _text="${*}"
  
  while [[ "${_secs}" -gt -1 ]]; do
    if [[ "${_secs}" -gt 0 ]]; then
      # shellcheck disable=SC2059 # ignore shellcheck
      printf '\r\033[K< Waiting '"${_secs}"' seconds '"${_text}" >&2
      sleep 0.5
      # shellcheck disable=SC2059 # ignore shellcheck
      printf '\r\033[K> Waiting '"${_secs}"' seconds '"${_text}" >&2
      sleep 0.5
    else
      printf '\r\033[K' >&2
    fi
    : $((_secs--))
  done
}

_fsSymlinkCreate_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _source="${1}"
  local _link="${2}"
  local _error=1

  [[ -f "${_source}" || -d "${_source}" ]] && _error=0
  
  if [[ "${_error}" -eq 0 ]]; then
    if [[ "$(_fsSymlinkValidate_ "${_link}")" -eq 1 ]]; then
      sudo ln -sfn "${_source}" "${_link}"
    fi
    
    if [[ "$(_fsSymlinkValidate_ "${_link}")" -eq 1 ]]; then
      _fsMsgError_ "Cannot create symlink: ${_link}"
    fi
  else
    _fsMsgError_ "Symlink source does not exist: ${_source}"
  fi
}

_fsSymlinkValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _link="${1}"
  
  # credit: https://stackoverflow.com/a/36180056
  if [ -L "${_link}" ] ; then
    if [ -e "${_link}" ] ; then
      echo 0
    else
      sudo rm -f "${_link}"
      echo 1
    fi
  elif [ -e "${_link}" ] ; then
    sudo rm -f "${_link}"
    echo 1
  else
    sudo rm -f "${_link}"
    echo 1
  fi
}

_fsArrayDedupe_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local -a _array=()
  local -A _arrayTmp=()
  local _i=''
  
  for _i in "$@"; do
    { [[ -z ${_i} || -n ${_arrayTmp[${_i}]:-} ]]; } && continue
    _array+=("${_i}") && _arrayTmp[${_i}]=x
  done
  
  printf -- '%s\n' "${_array[@]}"
}

_fsArrayShuffle_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _array=("${@}")
  local _arrayTmp=''
  local _i=''
  local _size=''
  local _max=''
  local _rand=''
  
  # credit: https://mywiki.wooledge.org/BashFAQ/026
  _size=${#_array[@]}
  
  for ((_i=_size-1; _i>0; _i--)); do
    _max=$(( 32768 / (_i+1) * (_i+1) ))
    while (( (_rand=RANDOM) >= _max )); do :; done
    _rand=$(( _rand % (_i+1) ))
    _arrayTmp=${_array[_i]} _array[_i]=${_array[_rand]} _array[_rand]=$_arrayTmp
  done
  
  printf -- '%s\n' "${_array[@]}"
}

_fsCrontab_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronTime="${1}"
  local _cronCmd="${2}"
  local _cronJob="${_cronTime} ${_cronCmd}"
  
  # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -
  
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
    _fsMsgError_ "Cron not set: ${_cronCmd}"
  fi
}

_fsCrontabRemove_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    # credit: https://stackoverflow.com/a/17975418
    ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -
    
    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
      _fsMsg_ "Cron not removed: ${_cronCmd}"
    fi
  fi
}

_fsCrontabValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  
  if crontab -l 2> /dev/null | grep -q "${_cronCmd}"; then
    echo 0
  else
    echo 1
  fi
}

_fsOptions_() {
  local -r _args=("${@}")
  local _opts
  
  _opts="$(getopt --options a,d,q,r --long auto,debug,quit,reset -- "${_args[@]}" 2> /dev/null)" || {
    _fsMsgError_ "Unkown or missing argument."
  }
  
  eval set -- "${_opts}"
  while true; do
    case "${1}" in
      --auto|-a)
        FS_OPTS_AUTO=0
        break
        ;;
      --debug|-d)
        FS_OPTS_DEBUG=0
        shift
        ;;
      --quit|-q)
        FS_OPTS_QUIT=0
        break
        ;;
      --reset|-r)
        FS_OPTS_RESET=0
        break
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done
}

#
# RUNTIME
#

_fsLogo_
_fsScriptlock_

FS_ARCHITECTURE="$(_fsArchitecture_)"
FS_OPTS_QUIT=1
FS_OPTS_RESET=1
FS_OPTS_DEBUG=1
FS_OPTS_AUTO=1

_fsOptions_ "${@}"

exit 1

if [[ "${FS_OPTS_RESET}" -eq 0 ]]; then
  _fsDockerReset_
else
  _fsSetupPrerequisites_
  _fsSetupUser_
  _fsSetupRootless_
  _setupFreqtrade_
  _fsSymlinkCreate_ "${FS_PATH}" "${FS_SYMLINK}"  
  _setupBinanceProxy_
  _setupKucoinProxy_
  _fsDockerProject_
fi

exit 0