#!/usr/bin/env bash
clear
#
# https://github.com/berndhofer/freqstart/
#
# Since this is a small project where I taught myself some bash scripts,
# you are welcome to improve the code. If you just use the script and like it,
# remember that it took a lot of time, testing and also money for infrastructure.
# You can contribute by donating to the following wallets.
# Thank you very much for that!
#
# BTC 1M6wztPA9caJbSrLxa6ET2bDJQdvigZ9hZ
# ETH 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
# BSC 0xb155f0F64F613Cd19Fb35d07D43017F595851Af5
#
# This software is for educational purposes only. Do not risk money which you are afraid to lose. 
# USE THE SOFTWARE AT YOUR OWN RISK. THE AUTHORS AND ALL AFFILIATES ASSUME NO RESPONSIBILITY FOR YOUR TRADING RESULTS.
#
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

readonly FS_NAME="freqstart"
readonly FS_VERSION='v2.0.0'
readonly FS_TMP="/tmp/${FS_NAME}"
readonly FS_SYMLINK="/usr/local/bin/${FS_NAME}"

readonly FS_DIR="$(dirname "$(readlink --canonicalize-existing "${0}" 2> /dev/null)")"
readonly FS_FILE="${0##*/}"
readonly FS_PATH="${FS_DIR}/${FS_FILE}"
readonly FS_DIR_PROXY="${FS_DIR}/proxy"
readonly FS_DIR_USER_DATA="${FS_DIR}/user_data"

readonly FS_CONFIG="${FS_DIR}/${FS_NAME}.conf.json"
readonly FS_STRATEGIES="${FS_DIR}/${FS_NAME}.strategies.json"
readonly FS_AUTOUPDATE="${FS_DIR}/${FS_NAME}.autoupdate.sh"

readonly FS_NETWORK="${FS_NAME}_network"
readonly FS_NETWORK_SUBNET='172.35.0.0/16'
readonly FS_NETWORK_GATEWAY='172.35.0.1'

readonly FS_PROXY_BINANCE="${FS_NAME}_proxy_binance"
readonly FS_PROXY_BINANCE_IP='172.35.0.253'

readonly FS_PROXY_KUCOIN="${FS_NAME}_proxy_kucoin"
readonly FS_PROXY_KUCOIN_IP='172.35.0.252'

readonly FS_NGINX="${FS_NAME}_nginx"
readonly FS_NGINX_YML="${FS_DIR}/${FS_NAME}_nginx.yml"
readonly FS_NGINX_CONFD="/etc/nginx/conf.d"
readonly FS_NGINX_CONFD_FREQUI="${FS_NGINX_CONFD}/frequi.conf"
readonly FS_NGINX_CONFD_HTPASSWD="${FS_NGINX_CONFD}/.htpasswd"

readonly FS_CERTBOT="${FS_NAME}_certbot"
readonly FS_FREQUI="${FS_NAME}_frequi"
readonly FS_HASH="$(xxd -l 8 -ps /dev/urandom)"

FS_OPTS_COMPOSE=1
FS_OPTS_SETUP=1
FS_OPTS_AUTO=1
FS_OPTS_QUIT=1
FS_OPTS_YES=1
FS_OPTS_RESET=1
FS_OPTS_CERT=1

trap _fsCleanup_ EXIT
trap '_fsErr_ "${FUNCNAME:-.}" ${LINENO}' ERR

###
# DOCKER

_fsDockerVarsRepo_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _docker="${1}"
  local _dockerRepo="${_docker%:*}"
  
  echo "${_dockerRepo}"
}

_fsDockerVarsCompare_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _docker="${1}"
  local _dockerRepo=''
  local _dockerTag=''
  local _dockerVersionLocal=''
  local _dockerVersionHub=''
  
  _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
  _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
  _dockerVersionHub="$(_fsDockerVersionHub_ "${_dockerRepo}" "${_dockerTag}")"
  _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"
  
  # compare versions
  if [[ -z "${_dockerVersionHub}" ]]; then
    echo 2 # unkown
  else
    if [[ "${_dockerVersionHub}" = "${_dockerVersionLocal}" ]]; then
      echo 0 # equal
    else
      echo 1 # greater
    fi
  fi
}

_fsDockerVarsName_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _docker="${1}"
  local _dockerRepo=''
  local _dockerName=''
  
  _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
  _dockerName="${FS_NAME}"'_'"$(echo "${_dockerRepo}" | sed "s,\/,_,g" | sed "s,\-,_,g")"
  
  echo "${_dockerName}"
}

_fsDockerVarsTag_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _docker="${1}"
  local _dockerTag="${_docker##*:}"
  
  if [[ "${_dockerTag}" = "${_docker}" ]]; then
    _dockerTag="latest"
  fi
  
  echo "${_dockerTag}"
}

_fsDockerVersionLocal_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerRepo="${1}"
  local _dockerTag="${2}"
  local _dockerVersionLocal=''
  
  if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
    _dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerRepo}:${_dockerTag}" \
    | sed 's/.*@//')"
    
    if [[ -n "${_dockerVersionLocal}" ]]; then
      echo "${_dockerVersionLocal}"
    fi
  fi
}

_fsDockerVersionHub_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerRepo="${1}"
  local _dockerTag="${2}"
  local _token=''
  local _acceptM="application/vnd.docker.distribution.manifest.v2+json"
  local _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
  local _dockerName=''
  local _dockerManifest=''
  
  _dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
  _dockerManifest="${FS_TMP}"'/'"${FS_HASH}"'_'"${_dockerName}"'_'"${_dockerTag}"'.md'
  _token="$(curl --connect-timeout 10 -s "https://auth.docker.io/token?scope=repository:${_dockerRepo}:pull&service=registry.docker.io"  | jq -r '.token')"
  
  if [[ -n "${_token}" ]]; then
    curl --connect-timeout 10 -s --header "Accept: ${_acceptM}" --header "Accept: ${_acceptML}" --header "Authorization: Bearer ${_token}" \
    -o "${_dockerManifest}" \
    -I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}"
  fi
  
  if [[ "$(_fsFile_ "${_dockerManifest}")" -eq 0 ]]; then
    _status="$(grep -o "200 OK" "${_dockerManifest}" || true)"
    
    if [[ -n "${_status}" ]]; then
      _dockerVersionHub="$(_fsValueGet_ "${_dockerManifest}" 'etag')"
      
      if [[ -n "${_dockerVersionHub}" ]]; then
        echo "${_dockerVersionHub}"
      else
        _fsMsgWarning_ 'Cannot retrieve docker manifest.'
      fi
    fi
  else
    _fsMsgWarning_ 'Cannot connect to docker hub.'
  fi
}

_fsDockerImage_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerImage="${1}"
  local _dockerRepo=''
  local _dockerTag=''
  local _dockerName=''
  local _dockerCompare=''
  local _dockerStatus=2
  local _dockerVersionLocal=''
  
  _dockerRepo="$(_fsDockerVarsRepo_ "${_dockerImage}")"
  _dockerTag="$(_fsDockerVarsTag_ "${_dockerImage}")"
  _dockerName="$(_fsDockerVarsName_ "${_dockerImage}")"
  _dockerCompare="$(_fsDockerVarsCompare_ "${_dockerImage}")"
  
  if [[ "${_dockerCompare}" -eq 0 ]]; then
      # docker hub image version is equal
    _fsMsg_ "Image is installed: ${_dockerRepo}:${_dockerTag}"
    _dockerStatus=0
  elif [[ "${_dockerCompare}" -eq 1 ]]; then
      # docker hub image version is greater
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"
    
    if [[ -n "${_dockerVersionLocal}" ]]; then
        # update from docker hub
      _fsMsg_ "Image update found for: ${_dockerRepo}:${_dockerTag}"
      
      if [[ "$(_fsCaseConfirmation_ "Do you want to update now?")" -eq 0 ]]; then
        docker pull "${_dockerRepo}"':'"${_dockerTag}"
        
        if [[ "$(_fsDockerVarsCompare_ "${_dockerImage}")" -eq 0 ]]; then
          _fsMsg_ "Updated..."
          _dockerStatus=1
        fi
      else
        _fsMsg_ "Skipping..."
        _dockerStatus=0
      fi
    else
        # install from docker hub
      docker pull "${_dockerRepo}:${_dockerTag}"
      if [[ "$(_fsDockerVarsCompare_ "${_dockerImage}")" -eq 0 ]]; then
        _fsMsg_ "Image installed: ${_dockerRepo}:${_dockerTag}"
        _dockerStatus=1
      fi
    fi
  elif [[ "${_dockerCompare}" -eq 2 ]]; then
      # docker hub image version is unknown
    if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
      _dockerStatus=0
    fi
  fi
  
  if [[ "${_dockerStatus}" -eq 2 ]]; then
      _fsMsgError_ "Image not found: ${_dockerRepo}:${_dockerTag}"
  else
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"
      # return local version docker image digest
    echo "${_dockerVersionLocal}"
  fi
}

_fsDockerImageInstalled_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerRepo="${1}"
  local _dockerTag="${2}"
  local _dockerImages=''
  
  _dockerImages="$(docker images -q "${_dockerRepo}:${_dockerTag}" 2> /dev/null)"
  
  if [[ -n "${_dockerImages}" ]]; then
      # docker image is installed
    echo 0
  else
      # docker image is not installed
    echo 1
  fi
}

_fsDockerPsName_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerName="${1}"
  local _dockerMode="${2:-}" # optional: all
  local _dockerPs=''
  local _dockerPsAll=''
  local _dockerMatch=1
  
  # credit: https://serverfault.com/a/733498
  # credit: https://stackoverflow.com/a/44731522
  if [[ "${_dockerMode}" = "all" ]]; then
    _dockerPsAll="$(docker ps -a --format '{{.Names}}' | grep -ow "${_dockerName}")" \
    || _dockerPsAll=""
    
    [[ -n "${_dockerPsAll}" ]] && _dockerMatch=0
  else
    _dockerPs="$(docker ps --format '{{.Names}}' | grep -ow "${_dockerName}")" \
    || _dockerPs=""
    
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

_fsDockerId2Name_() {
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
  if [[ "$(_fsDockerPsName_ "${_dockerName}" "all")" -eq 0 ]]; then
    docker update --restart=no "${_dockerName}" > /dev/null
    docker stop "${_dockerName}" > /dev/null
    docker rm -f "${_dockerName}" > /dev/null
    
    if [[ "$(_fsDockerPsName_ "${_dockerName}" "all")" -eq 0 ]]; then
      _fsMsgError_ "Cannot remove container: ${_dockerName}"
    fi
  fi
}

_fsDockerProjectImages_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _ymlPath="${1}"
  local _ymlImages=''
  local _ymlImagesDeduped=''
  local _ymlImage=''
  local _dockerImage=''
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
    _ymlImagesDeduped=()
    while read -r; do
    _ymlImagesDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_ymlImages[@]}")
    
    for _ymlImage in "${_ymlImagesDeduped[@]}"; do
      _dockerImage="$(_fsDockerImage_ "${_ymlImage}")"
      
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
  local _strategies=''
  local _strategiesDeduped=''
  local _strategy=''
  local _strategiesDir=''
  local _strategiesDirDeduped=''
  local _strategyDir=''
  local _strategyPath=''
  local _strategyFile=''
  local _strategyPathFound=1
  local _error=0
  
    # download or update implemented strategies
  _strategies=()
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
    _strategiesDeduped=()
    while read -r; do
      _strategiesDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_strategies[@]}")
    
      # validate optional strategy paths in project file
    _strategiesDir=()
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
    
    _strategiesDirDeduped=()
    while read -r; do
      _strategiesDirDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_strategiesDir[@]}")
    
    for _strategy in "${_strategiesDeduped[@]}"; do
      _fsDockerStrategy_ "${_strategy}"
      
      for _strategyDir in "${_strategiesDirDeduped[@]}"; do
        _strategyPath="${_strategyDir}"'/'"${_strategy}"'.py'
        _strategyFile="${_strategyPath##*/}"
        if [[ "$(_fsFile_ "${_strategyPath}")" -eq 0 ]]; then
          _strategyPathFound=0
          break
        fi
      done
      
      if [[ "${_strategyPathFound}" -eq 1 ]]; then
        _fsMsgWarning_ 'Strategy file not found: '"${_strategyFile}"
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
  local _configs=''
  local _configsDeduped=''
  local _config=''
  local _configPath=''
  local _error=0
  
  _configs=()
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
    _configsDeduped=()
    while read -r; do
      _configsDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_configs[@]}")
    
    for _config in "${_configsDeduped[@]}"; do
      _configPath="${FS_DIR}/${_config}"
      if [[ "$(_fsFile_ "${_configPath}")" -eq 1 ]]; then
        _fsMsg_ "\"$(basename "${_configPath}")\" config file does not exist."
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

_fsDockerProject_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _projectPath="${FS_DIR}/${1##*/}"
  local _projectMode="${2}" # compose, compose-force, run, run-force, validate, quit
  local _projectService="${3:-}" # optional: service
  local _projectArgs="${4:-}" # optional: args
  local _projectFile=''
  local _projectFileType=''
  local _projectFileName=''
  local _projectName=''
  local _projectImages=1
  local _projectStrategies=1
  local _projectConfigs=1
  local _projectContainers=''
  local _projectContainer=''
  local _procjectJson=''
  local _projectShell=''
  local _containerCmd=''
  local _containerActive=''
  local _containerRestart=1
  local _containerName=''
  local _containerStrategy=''
  local _containerStrategyDir=''
  local _containerStrategyUpdate=''
  local _containerJson=''
  local _containerJsonInner=''
  local _containerConfPath=''
  local _containerApiJson=''
  local _containerLogfile=''
  local _containerLogfileTmp=''
  local _containerCount=0
  local _containerAutoupdate='false'
  local _containerAutoupdateCount=0
  local _strategyUpdate=''
  local _strategyDir=''
  local _strategyPath=''
  local _regex="(${FS_PROXY_KUCOIN}|${FS_PROXY_BINANCE}|${FS_NGINX}|${FS_CERTBOT}|${FS_FREQUI})"
  local _error=0
  local _url=0
  
  _url="$(_fsValueGet_ "${FS_CONFIG}" '.url' 2> /dev/null || true)"

  
  if [[ -n "${_projectArgs}" ]]; then
    shift;shift;shift
    _projectArgs="${*:-}" # optional: args
  fi
  
  _projectFile="${_projectPath##*/}"
  _projectFileType="${_projectFile##*.}"
  _projectFileName="${_projectFile%.*}"
  _projectName="${_projectFileName//\-/\_}"
  _procjectJson=()
  _projectContainers=()
  _containerConfPath="${FS_DIR}/${_projectFileName}.conf.json"
  
    # unset filetype if its matching file
  [[ "${_projectFile}" = "${_projectFileType}" ]] && _projectFileType=''
  
    # validate project file
  if [[ -z "${_projectFileType}" ]]; then
    _fsMsgError_ "File type is missing: ${_projectFile}"
  else
    if [[ "${_projectFileType}" = 'yml' ]]; then
      if [[ "$(_fsFile_ "${_projectPath}")" -eq 1 ]]; then
        _fsMsgError_ "File not found: ${_projectFile}"
      fi
    else
      _fsMsgError_ "File type is not correct: ${_projectFile}"
    fi
  fi
  
  if [[ "${_projectMode}" =~ "compose" ]]; then
    _fsMsgTitle_ "Compose project: ${_projectFile}"
    
    _projectStrategies="$(_fsDockerProjectStrategies_ "${_projectPath}")"
    _projectConfigs="$(_fsDockerProjectConfigs_ "${_projectPath}")"
    _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
    
    [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectStrategies}" -eq 1 ]] && _error=$((_error+1))
    
    if [[ "${_error}" -eq 0 ]]; then
      if [[ "${_projectMode}" = 'compose-force' ]]; then
          # shellcheck disable=SC2015,SC2086 # ignore shellcheck
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} up --no-start --force-recreate ${_projectService} || true
      else
          # shellcheck disable=SC2015,SC2086 # ignore shellcheck
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} up --no-start --no-recreate ${_projectService} || true
      fi
    fi
  elif [[ "${_projectMode}" =~ "run" ]]; then
    _fsMsgTitle_ "Run project: ${_projectFile}"
    
    _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
    
    [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
    
    if [[ "${_error}" -eq 0 ]]; then
        # workaround to execute shell from variable; help: open for suggestions
      _projectShell="$(printf -- '%s' "${_projectArgs}" | grep -oE '^/bin/sh -c' || true)"
      
      if [[ -n "${_projectShell}" ]]; then
        _projectArgs="$(printf -- '%s' "${_projectArgs}" | sed 's,/bin/sh -c ,,')"
          # shellcheck disable=SC2015,SC2086 # ignore shellcheck
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} run --rm "${_projectService}" /bin/sh -c "${_projectArgs}" || true
      else
          # shellcheck disable=SC2015,SC2086 # ignore shellcheck
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} run --rm ${_projectService} ${_projectArgs} || true
      fi
    fi
  elif [[ "${_projectMode}" = "validate" ]]; then
    _fsMsgTitle_ "Validate project: ${_projectFile}"
    _fsCdown_ 30 "for any errors..."
  elif [[ "${_projectMode}" = "quit" ]]; then
    _fsMsgTitle_ "Quit project: ${_projectFile}"
  fi
  
  if [[ "${_error}" -eq 0 ]] && [[ ! "${_projectMode}" =~ 'run' ]]; then
    while read -r; do
      _projectContainers+=( "$REPLY" )
    done < <(cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" ps -q)
    
    for _projectContainer in "${_projectContainers[@]}"; do
      _containerName="$(_fsDockerId2Name_ "${_projectContainer}")"
      _containerActive="$(_fsDockerPsName_ "${_containerName}")"
      _containerJsonInner=''
      _strategyUpdate=''
      _containerStrategyUpdate=''
      _containerAutoupdate="$(_fsValueGet_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate')"
      
      if [[ ! "${_projectMode}" = "validate" ]]; then
        _fsMsgTitle_ 'Container: '"${_containerName}"
      fi
      
        # start container
      if [[ "${_projectMode}" =~ "compose" ]]; then
          # skip container if autostart is active but not true
        if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ ! "${_containerAutoupdate}" = 'true' ]]; then
          continue
        fi
        
        if [[ "${_containerActive}" -eq 1 ]]; then
          if [[ ! $_containerName =~ $_regex ]]; then
            if [[ "$(_fsCaseConfirmation_ "Start container?")" -eq 1 ]]; then
              _fsDockerRemove_ "${_containerName}"
              continue
            fi
          fi
        fi
        
          # create docker network if it does not exist; credit: https://stackoverflow.com/a/59878917
        docker network create --subnet="${FS_NETWORK_SUBNET}" --gateway "${FS_NETWORK_GATEWAY}" "${FS_NETWORK}" > /dev/null 2> /dev/null || true
        
          # connect container to docker network excl. nginx and certbot
        if [[ "${_containerName}" = "${FS_PROXY_BINANCE}" ]]; then
          docker network connect --ip "${FS_PROXY_BINANCE_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        elif [[ "${_containerName}" = "${FS_PROXY_KUCOIN}" ]]; then
          docker network connect --ip "${FS_PROXY_KUCOIN_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        else
          docker network connect "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        fi
        
          # set restart to no to filter faulty containers
        docker update --restart=no "${_containerName}" > /dev/null
        
          # set container to autoupdate
        if [[ "${FS_OPTS_AUTO}" -eq 1 ]] && [[ ! "${_containerAutoupdate}" = 'true' ]]; then
          if [[ "$(_fsCaseConfirmation_ "Update container automatically?")" -eq 0 ]]; then
            _containerAutoupdate='true'
          fi
        else
          _fsMsg_ 'Automatic update is activated.'
        fi
        
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
            
            if [[ "$(_fsFile_ "${_containerLogfile}")" -eq 0 ]]; then
                # workaround to preserve owner of file
              _containerLogfileTmp="${FS_TMP}"'/'"${_containerLogfile##*/}"'.tmp'
              touch "${_containerLogfileTmp}"
                # note: sudo because of freqtrade docker user
              sudo cp --no-preserve=all "${_containerLogfileTmp}" "${_containerLogfile}"
            fi
          fi
          
            # validate strategy
          _containerStrategy="$(echo "${_containerCmd}" | { grep -Eos "(\-s|\--strategy) [-A-Za-z0-9_]+ " || true; } \
          | sed "s,\--strategy,," \
          | sed "s, ,,g")"
          
          if [[ -n "${_containerStrategy}" ]]; then
            _containerStrategyDir="$(echo "${_containerCmd}" | { grep -Eos "\--strategy-path [-A-Za-z0-9_/]+ " || true; } \
            | sed "s,\-\-strategy-path,," \
            | sed "s, ,,g")"
            
            _strategyPath="${_containerStrategyDir}/${_containerStrategy}.conf.json"
            
            if [[ "$(_fsFileEmpty_ "${_strategyPath}")" -eq 0 ]]; then
              _strategyUpdate="$(_fsValueGet_ "${_strategyPath}" '.update')"
            else
              _strategyUpdate=""
            fi
            
            if [[ "$(_fsFileEmpty_ "${_containerConfPath}")" -eq 0 ]]; then
              _containerStrategyUpdate="$(_fsValueGet_ "${_containerConfPath}" '.'"${_containerName}"'.strategy_update')"
            else
              _containerStrategyUpdate=""
            fi
            
            if [[ -n "${_containerStrategyUpdate}" ]]; then
              if [[ "${_containerActive}" -eq 0 ]] && [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
                _containerRestart=0
                _fsMsgWarning_ 'Strategy is outdated: '"${_containerStrategy}"
              else
                _fsMsg_ 'Strategy is up-to-date: '"${_containerStrategy}"
              fi
            else
              _containerStrategyUpdate="${_strategyUpdate}"
              _fsMsgWarning_ 'Strategy version unkown: '"${_containerStrategy}"
            fi
          fi
        fi
        
          # check for frequi port and config
        if [[ ! $_containerName =~ $_regex ]]; then
          _containerApiJson="$(echo "${_containerCmd}" | grep -o "${FS_FREQUI}.json" || true)"
          
          if [[ -n "${_containerApiJson}" ]]; then
            _fsMsg_ "FreqUI: ${_url}/${FS_NAME}/${_containerName}"
          else
            _fsMsg_ "Bot is not exposed to FreqUI."
          fi
        fi
        
          # compare latest docker image with container image
        _containerImage="$(docker inspect --format="{{.Config.Image}}" "${_projectContainer}")"
        _containerImageVersion="$(docker inspect --format="{{.Image}}" "${_projectContainer}")"
        _dockerImageVersion="$(docker inspect --format='{{.Id}}' "${_containerImage}")"
        if [[ "${_containerActive}" -eq 0 ]] && [[ ! "${_containerImageVersion}" = "${_dockerImageVersion}" ]]; then
          _fsMsgWarning_ 'Image is outdated: '"${_containerImage}"
          _containerRestart=0
        else
          _fsMsg_ 'Image is up-to-date: '"${_containerImage}"
        fi
        
          # start container
        if [[ "${_containerActive}" -eq 1 ]]; then
          docker start "${_containerName}" > /dev/null || true
          
          # restart container if necessary
        else
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart container (recommended)?")" -eq 0 ]]; then
                # set strategy update only when container is restarted
              if [[ -n "${_strategyUpdate}" ]]; then
                _containerStrategyUpdate="${_strategyUpdate}"
              fi
              docker restart "${_containerName}" > /dev/null || true
            fi
            _containerRestart=1
          fi
        fi
        
          # create project json array; help: remove outer paranthesis from json
        _containerJsonInner="$(jq -n \
          --arg strategy "${_containerStrategy}" \
          --arg strategy_path "${_containerStrategyDir}" \
          --arg strategy_update "${_containerStrategyUpdate}" \
          --arg autoupdate "${_containerAutoupdate}" \
          '$ARGS.named' \
        )"
        _containerJson="$(jq -n \
          --argjson "${_containerName}" "${_containerJsonInner}" \
          '$ARGS.named' \
        )"
        _procjectJson[$_containerCount]="${_containerJson}"
        
          # increment container count
        _containerCount=$((_containerCount+1))
        
        # validate container
      elif [[ "${_projectMode}" = "validate" ]]; then
        if [[ "${_containerActive}" -eq 0 ]]; then
            # set restart to unless-stopped
          docker update --restart=unless-stopped "${_containerName}" > /dev/null
          
          if [[ "${_containerAutoupdate}" = 'true' ]]; then
            _containerAutoupdateCount=$((_containerAutoupdateCount+1))
          fi
          
          _fsMsg_ '[SUCCESS] Container is active: '"${_containerName}"
        else
          _fsValueUpdate_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate' 'false'
          _fsDockerRemove_ "${_containerName}"
          _fsMsgWarning_ 'Container is not active: '"${_containerName}"
        fi
        
        # stop container
      elif [[ "${_projectMode}" = "quit" ]]; then
        if [[ "$(_fsCaseConfirmation_ "Quit container?")" -eq 0 ]]; then
          _fsValueUpdate_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate' 'false'
          _fsDockerRemove_ "${_containerName}"
          if [[ "$(_fsDockerPsName_ "${_containerName}")" -eq 1 ]]; then
            _fsMsg_ "[SUCCESS] Container is removed: ${_containerName}"
          else
            _fsMsgWarning_ "Container not removed: ${_containerName}"
          fi
        else
          _fsMsg_ 'Skipping...'
        fi
      fi
    done
  fi
  
  if [[ "${_projectMode}" =~ "compose" ]]; then
    if [[ "${_error}" -eq 0 ]]; then
        # create project conf file
      if (( ${#_procjectJson[@]} )); then
        printf -- '%s\n' "${_procjectJson[@]}" | jq . | tee "${_containerConfPath}" > /dev/null
      else
        rm -f "${_containerConfPath}"
      fi
      
        # validate project
      _fsDockerProject_ "${_projectPath}" "validate"
    else
      _fsMsgWarning_ "Cannot start: ${_projectFile}"
    fi
  elif [[ "${_projectMode}" = "validate" ]]; then
      # add or remove project from autoupdate
    if [[ "${_containerAutoupdateCount}" -gt 0 ]]; then
      _fsDockerAutoupdate_ "${_projectFile}"
    else
      _fsDockerAutoupdate_ "${_projectFile}" 'remove'
    fi
    
      # clear deprecated networks
    yes $'y' | docker network prune > /dev/null || true
  elif [[ "${_projectMode}" = "quit" ]]; then
    _fsDockerAutoupdate_ "${_projectFile}" "remove"
    
    if (( ! ${#_projectContainers[@]} )); then
      _fsMsg_ "No active container in project: ${_projectFile}"
    fi
  fi
}

_fsDockerStrategy_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _strategyName="${1}"
  local _strategyFile=''
  local _strategyUpdate=''
  local _strategyTmp="${FS_TMP}/${FS_HASH}_${_strategyName}"
  local _strategyDir="${FS_DIR_USER_DATA}/strategies/${_strategyName}"
  local _strategyUrls=''
  local _strategyUrlsDeduped=''
  local _strategyUrl=''
  local _strategyPath=''
  local _strategyPathTmp=''
  local _strategyJson=''
  local _setup=0
  local _error=0
  
    # create the only necessary strategy for proxies if file doesnt exist or use strategies file from git or create your own
  if [[ "$(_fsFile_ "${FS_STRATEGIES}")" -eq 1 ]]; then
    _fsFileCreate_ "${FS_STRATEGIES}" \
    "{" \
    "  \"DoesNothingStrategy\": [" \
    "    \"https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/master/user_data/strategies/berlinguyinca/DoesNothingStrategy.py\"" \
    "  ]" \
    "}"
  fi
  
  _strategyUrls=()
  while read -r; do
  _strategyUrls+=( "$REPLY" )
  done < <(jq -r ".${_strategyName}[]?" "${FS_STRATEGIES}")
  
  _strategyUrlsDeduped=()
  if (( ${#_strategyUrls[@]} )); then
    while read -r; do
    _strategyUrlsDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_strategyUrls[@]}")
  fi
  
  if (( ${#_strategyUrlsDeduped[@]} )); then
    mkdir -p "${_strategyTmp}"
      # note: sudo because of freqtrade docker user
    sudo mkdir -p "${_strategyDir}"
    
    for _strategyUrl in "${_strategyUrlsDeduped[@]}"; do
      if [[ "$(_fsIsUrl_ "${_strategyUrl}")" -eq 0 ]]; then
        _strategyFile="${_strategyUrl##*/}"
        _strategyPath="${_strategyDir}/${_strategyFile}"
        _strategyPathTmp="${_strategyTmp}/${_strategyFile}"
        
        curl --connect-timeout 10 -s -L "${_strategyUrl}" -o "${_strategyPathTmp}"
        
        if [[ "$(_fsFileEmpty_ "${_strategyPathTmp}")" -eq 0 ]]; then
          if [[ "$(_fsFile_ "${_strategyPath}")" -eq 0 ]]; then
              # only update file if it is different
            if ! cmp --silent "${_strategyPathTmp}" "${_strategyPath}"; then
                # note: sudo because of freqtrade docker user
              sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
              _setup=$((_setup+1))
              _fsFileExit_ "${_strategyPath}"
            fi
          else
              # note: sudo because of freqtrade docker user
            sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
            _setup=$((_setup+1))
            _fsFileExit_ "${_strategyPath}"
          fi
        else
          _fsMsgWarning_ 'Downloaded strategy file was empty.'
        fi
      else
        _fsMsgWarning_ 'Cannot connect to strategy url.'
      fi
    done
        
    if [[ "${_error}" -gt 0 ]]; then
      _fsMsgWarning_ "Failed to install or update: ${_strategyName}"
    elif [[ "${_setup}" -gt 0 ]]; then
      _fsMsg_ "Strategy updated: ${_strategyName}"
      _strategyUpdate="$(_fsTimestamp_)"
      _strategyJson="$(jq -n \
        --arg update "${_strategyUpdate}" \
        '$ARGS.named' \
      )"
        # note: sudo because of freqtrade docker user
      printf '%s\n' "${_strategyJson}" | jq . | sudo tee "${_strategyDir}/${_strategyName}.conf.json" > /dev/null
    else
      _fsMsg_ "Strategy is installed: ${_strategyName}"
    fi
  else
    _fsMsgWarning_ "Strategy is not implemented: ${_strategyName}"
  fi
}

_fsDockerAutoupdate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _projectFile="${1}"
  local _projectAutoupdate='freqstart --compose '"${_projectFile}"' --auto --yes'
  local _projectAutoupdateMode="${2:-}" # optional: remove
  local _projectAutoupdates=""
  local _cronUpdate="3 */12 * * *" # update every 12 hours and 3 minutes; thanks: ECO
  
  _projectAutoupdates=()
  _projectAutoupdates+=("#!/usr/bin/env bash")
  if [[ "$(_fsFile_ "${FS_AUTOUPDATE}")" -eq 0 ]]; then
    while read -r; do
    _projectAutoupdates+=("$REPLY")
    done < <(grep -v "${_projectAutoupdate}" "${FS_AUTOUPDATE}" | sed "s,#!/usr/bin/env bash,," | sed "/^$/d")
  fi
  
  if [[ ! "${_projectAutoupdateMode}" = "remove" ]]; then
    _projectAutoupdates+=("${_projectAutoupdate}")
  fi
  
  if [[ "${#_projectAutoupdates[@]}" -lt 2 ]]; then
    _fsCrontabRemove_ "${FS_AUTOUPDATE}"
    rm -f "${FS_AUTOUPDATE}"
  else
    printf '%s\n' "${_projectAutoupdates[@]}" | tee "${FS_AUTOUPDATE}" > /dev/null
    sudo chmod +x "${FS_AUTOUPDATE}"
    
    _fsCrontab_ "${FS_AUTOUPDATE}" "${_cronUpdate}"
  fi
}

_fsDockerPurge_() {
  _fsCrontabRemove_ "${FS_AUTOUPDATE}"
  rm -f "${FS_AUTOUPDATE}"
  
  if [[ "$(_fsPkgsStatus_ "docker-ce")" -eq 0 ]]; then
        # credit: https://stackoverflow.com/a/69921248
      docker ps -a -q 2> /dev/null | xargs -I {} docker rm -f {} 2> /dev/null || true
      docker network prune --force 2> /dev/null || true
      docker image ls -q 2> /dev/null | xargs -I {} docker image rm -f {} 2> /dev/null || true
  fi
}

###
# SETUP

_fsSetup_() {
  local _link="${FS_DIR}/${FS_NAME}.sh"
  
  _fsSetupPrerequisites_
  _fsConf_
  _fsSetupUser_
  _fsSetupRootless_
  _fsSetupChrony_
  _fsSetupFreqtrade_
  _fsSetupFrequi_
  _fsSetupBinanceProxy_
  _fsSetupKucoinProxy_
  _fsStats_
  
  _fsSymlinkCreate_ "${_link}" "${FS_SYMLINK}"
}

# PREREQUISITES

_fsSetupPrerequisites_() {
  local _user=''
  
  _fsMsgTitle_ "PREREQUISITES"
  
  _user="$(id -u -n)"
  
  if ! id -nGz "${_user}" | grep -qzxF 'sudo'; then
    _fsMsgError_ 'User cannot use sudo! Login to root and run command: '"sudo usermod -a -G sudo ${_user}"
  fi
  
    # update; note: true workaround if manually installed packages are causing errors
  sudo apt update || true
  
  _fsPkgs_ "curl" "jq" "dnsutils" "lsof" "cron" "docker-ce" "docker-compose" "systemd-container" "uidmap" "dbus-user-session" "chrony" "ufw"
  
  _fsMsg_ "Update server and install unattended-upgrades. Reboot may be required!"
  
  if [[ "$(_fsCaseConfirmation_ "Skip server update?")" -eq 0 ]]; then
    _fsMsg_ "Skipping..."
  else
    sudo apt -o Dpkg::Options::="--force-confdef" dist-upgrade -y && \
    sudo apt install -y unattended-upgrades && \
    sudo apt autoremove -y
    
    if sudo test -f /var/run/reboot-required; then
      _fsMsgWarning_ 'A reboot is required to finish installing updates.'
      
      if [[ "$(_fsCaseConfirmation_ "Skip reboot now?")" -eq 0 ]]; then
        _fsMsg_ 'Skipping...'
      else
        sudo reboot
        exit 0
      fi
    else
      _fsMsg_ "A reboot is not required."
    fi
  fi
}

# USER

_fsSetupUser_() {
  local	_user=''
  local	_userId=''
  local _userTmp=''
  local _userTmpDir=''
  local _userTmpDPath=''
  local _nr=''
  
  _fsMsgTitle_ "USER"
  
  _user="$(id -u -n)"
  _userId="$(id -u)"
  
  if [[ "${_userId}" -eq 0 ]]; then
    _fsMsgWarning_ "Your are logged in as root!"
    
    while true; do
      printf -- '%s\n' \
      "? Create a new or login to existing non-root user?" \
      "  1) Create new user" \
      "  2) Login to existing non-root user" >&2
      
      read -rp "  Choose number: " _nr
      
      case ${_nr} in 
        [1])
          _fsMsg_ "Continue with 1) ..."
          ;;
        [2])
          _fsMsg_ "Continue with 2) ..."
          ;;
        *)
          _fsCaseInvalid_
          ;;
      esac
    
      while true; do
        read -rp '? Enter the username: ' _userTmp
        
        if [[ "${_userTmp}" = '' ]]; then
          _fsCaseEmpty_
        elif [[ "$(_fsIsAlphaDashUscore_ "${_userTmp}")" -eq 1 ]]; then
          _userTmp=''
        else
          if [[ "$(_fsCaseConfirmation_ "Is the username \"${_userTmp}\" correct?")" -eq 0 ]]; then
            if [[ "${_nr}" -eq 1 ]]; then
              if [[ "$(_fsUserValidate_ "${_userTmp}")" -eq 0 ]]; then
                _fsMsgWarning_ "User already exist."
                
                if [[ "$(_fsCaseConfirmation_ "Login to user \"${_userTmp}\" now?")" -eq 0 ]]; then
                  _nr=2
                  break
                else
                  _userTmp=''
                fi
              else
                break
              fi
            elif [[ "${_nr}" -eq 2 ]]; then
              if [[ "$(_fsUserValidate_ "${_userTmp}")" -eq 1 ]]; then
                _fsMsgWarning_ "User does not exist. "
                
                if [[ "$(_fsCaseConfirmation_ "Create user \"${_userTmp}\" now?")" -eq 0 ]]; then
                  _nr=1
                  break
                else
                  _userTmp=''
                fi
              else
                break
              fi
            fi
          else
            _userTmp=''
          fi
        fi
      done
      
      break
    done
    
    if [[ "${_nr}" -eq 1 ]] && [[ -n "${_userTmp}" ]]; then
        # do not add the user to the lastlog and faillog databases to avoid excessive log files
      sudo adduser --no-log-init --gecos "" "${_userTmp}"
    fi
    
      # add user to sudo group
    sudo usermod -a -G sudo "${_userTmp}" || true
    
    _userTmpDir="$(bash -c "cd ~$(printf %q "${_userTmp}") && pwd")"'/'"${FS_NAME}"
    _userTmpDPath="${_userTmpDir}/${FS_NAME}.sh"
    _userTmpSudoer="${_userTmp} ALL=(root) NOPASSWD: ${_userTmpDPath}"
    
      # append freqstart to sudoers for autoupdate
    if ! sudo -l | grep -q "${_userTmpSudoer}"; then
      echo "${_userTmpSudoer}" | sudo tee -a /etc/sudoers > /dev/null
    fi
    
    mkdir -p "${_userTmpDir}"
    
      # copy freqstart incl. strategies to new user home
    cp -a "${FS_PATH}" "${_userTmpDir}/${FS_FILE}" 2> /dev/null || true
    cp -a "${FS_STRATEGIES}" "${_userTmpDir}/${FS_STRATEGIES##*/}" 2> /dev/null || true
    
    sudo chown -R "${_userTmp}":"${_userTmp}" "${_userTmpDir}"
    sudo chmod +x "${_userTmpDPath}"

    _fsMsg_ ' +'
    _fsMsgWarning_ "Manually restart script: ${_userTmpDir}/${FS_FILE} --setup"
    _fsMsg_ ' +'
    sudo rm -rf "${FS_TMP}"
    sudo rm -f "${FS_SYMLINK}"
    
      # machinectl is needed to set $XDG_RUNTIME_DIR properly
    sudo rm -f "${FS_PATH}" && sudo machinectl shell "${_userTmp}@"
    exit 0
  else
    _fsMsgWarning_ "Your are logged in as non-root."
  fi
}

# ROOTLESS

_fsSetupRootless_() {
  local	_user=''
  local	_userId=''
  local _getDocker="${FS_DIR}"'/get-docker-rootless.sh'
  
  _fsMsgTitle_ "ROOTLESS (Docker)"
  
  _user="$(id -u -n)"
  _userId="$(id -u)"
  
  if ! sudo loginctl show-user "${_user}" 2> /dev/null | grep -q 'Linger=yes'; then
    sudo systemctl stop docker.socket docker.service || true
    sudo systemctl disable --now docker.socket docker.service || true
    sudo rm /var/run/docker.sock || true
        
    curl --connect-timeout 10 -fsSL "https://get.docker.com/rootless" -o "${_getDocker}"
    _fsFileExit_ "${_getDocker}"
    sudo chmod +x "${_getDocker}"
    sh "${_getDocker}"
    rm -f "${_getDocker}"
    
    sudo loginctl enable-linger "${_user}"
    
    _fsValueUpdate_ "${FS_CONFIG}" '.user' "${_user}"
    _fsMsg_ 'Docker rootless installed.'
    _fsMsgWarning_ 'Until you log-out/in for the first time, manual docker commands will fail.'
  else
    _fsMsg_ 'Docker rootless is installed.'
  fi
  
    # add docker variables to bashrc; note: path variable should be set but left the comment in
  if ! cat ~/.bashrc | grep -q "# ${FS_NAME}"; then
    printf -- '%s\n' \
    '' \
    "# ${FS_NAME}" \
    "#export PATH=/home/${_user}/bin:\$PATH" \
    "export DOCKER_HOST=unix:///run/user/${_userId}/docker.sock" \
    '' >> ~/.bashrc
  fi
  
    # export docker variables
  #export "PATH=/home/${_user}/bin:\$PATH"
  export "DOCKER_HOST=unix:///run/user/${_userId}/docker.sock"
}

# CHRONY

_fsSetupChrony_() {
  _fsMsgTitle_ "CHRONY"
  
  _fsPkgs_ "chrony"
  
  if [[ -n "$(chronyc activity | grep -o "200 OK" || true)" ]]; then
    _fsMsg_ "Server time is synchronized."
  else
    _fsMsgWarning_ "Server time may not be synchronized."
  fi
}

# FIREWALL

_fsSetupFirewall_() {
  local _status=''
  local _portSSH=22
  
  _fsPkgs_ "ufw"
  
  _fsMsgTitle_ 'Configurate firewall for Nginx proxy.'
  
  if [[ "$(_fsCaseConfirmation_ 'Is the default SSH port "22/tcp"?')" -eq 1 ]]; then
    while true; do
      read -rp '? SSH port (Press [ENTER] for default "22/tcp"): ' _portSSH
      case ${_portSSH} in
        '')
          _portSSH=22
          ;;
        *)
          _fsMsg_ 'Do not continue if the default SSH port is not: '"${_portSSH}"
          if [[ "$(_fsCaseConfirmation_ 'Continue?')" -eq 0 ]]; then
            break
          fi
          ;;
      esac
    done
  fi
  
  yes $'y' | sudo ufw reset || true
  sudo ufw default deny incoming
    # ports for ssh access and nginx proxy forward for frequi
  sudo ufw allow ssh
  sudo ufw allow "${_portSSH}"/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow out http
  sudo ufw allow out https
    # allow ntp sync on port 123
  sudo ufw allow 123/udp
  sudo ufw allow out 123/udp
  yes $'y' | sudo ufw enable || true
}

# FREQTRADE

_fsSetupFreqtrade_() {
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerYml="${FS_DIR}/${FS_NAME}_setup.yml"
  local _configName=''
  local _configFile=''
  local _configFileTmp=''  
  
  _fsMsgTitle_ "FREQTRADE"
  
  _fsFileCreate_ "${_dockerYml}" \
  "---" \
  "version: '3'" \
  "services:" \
  "  freqtrade:" \
  "    image: freqtradeorg/freqtrade:stable" \
  "    container_name: freqtrade" \
  "    volumes:" \
  '      - "'"${FS_DIR_USER_DATA}"':/freqtrade/user_data"'
  
  _fsFileExit_ "${_dockerYml}"
  
  if [[ ! -d "${FS_DIR_USER_DATA}" ]]; then
      # create user_data folder
    _fsDockerProject_ "${_dockerYml}" 'run-force' 'freqtrade' \
    "create-userdir --userdir /freqtrade/${FS_DIR_USER_DATA##*/}"
    
    # validate if directory exists and is not empty
    if [[ ! "$(ls -A "${FS_DIR_USER_DATA}" 2> /dev/null)" ]]; then
        # note: sudo because of freqtrade docker user
      sudo rm -rf "${FS_DIR_USER_DATA}"
      _fsMsgError_ "Cannot create directory: ${FS_DIR_USER_DATA}"
    else
      _fsMsg_ "Directory created: ${FS_DIR_USER_DATA}"
    fi
  fi
    
    # optional creation of freqtrade config
  if [[ "$(_fsCaseConfirmation_ "Skip creating a config?")" -eq 0 ]]; then
     _fsMsg_ "Skipping..."
  else
    while true; do
      _fsMsg_ "Choose a name for your config. For default name press <ENTER>."
      read -rp " (filename) " _configName
      case ${_configName} in
        "")
          _configName='config'
          ;;
        *)
          _configName="${_configName%.*}"
          
          if [[ "$(_fsIsAlphaDashUscore_ "${_configName}")" -eq 1 ]]; then
            _configName=''
          fi
          ;;
      esac
      
      if [[ -n "${_configName}" ]]; then
        _fsMsg_ "The config file name will be: ${_configName}.json"
        if [[ "$(_fsCaseConfirmation_ "Is this correct?")" -eq 0 ]]; then
          break
        fi
      fi
    done
    
    _configFile="${FS_DIR_USER_DATA}/${_configName}.json"
    _configFileTmp="${FS_DIR_USER_DATA}/${_configName}.tmp.json"
    
    if [[ "$(_fsFile_ "${_configFile}")" -eq 0 ]]; then
      _fsMsg_ "The config file already exist: ${_configFile}"
      if [[ "$(_fsCaseConfirmation_ "Replace the existing config file?")" -eq 1 ]]; then
        _configName=''
        sudo rm -f "${_dockerYml}"
      fi
    fi
    
    if [[ -n "${_configName}" ]]; then
      _fsDockerProject_ "${_dockerYml}" 'run-force' 'freqtrade' \
      "new-config --config /freqtrade/${FS_DIR_USER_DATA##*/}/${_configFileTmp##*/}"
            
      _fsFileExit_ "${_configFileTmp}"
        # note: sudo because of freqtrade docker user
      sudo cp -a "${_configFileTmp}" "${_configFile}"
      rm -f "${_configFileTmp}"
      
      _fsMsg_ "Enter your exchange api KEY and SECRET to: ${_configFile}"
    fi
  fi
}

# BINANCE-PROXY
# credit: https://github.com/nightshift2k/binance-proxy

_fsSetupBinanceProxy_() {
  local _docker="nightshift2k/binance-proxy:latest"
  local _yml="${FS_DIR}/${FS_PROXY_BINANCE}.yml"
  
  _fsMsgTitle_ 'PROXY FOR BINANCE'
  
  while true; do
    if [[ "$(_fsDockerPsName_ "${FS_PROXY_BINANCE}")" -eq 0 ]]; then
      _fsMsg_ 'Is already running. (Port: 8990-8991)'
      
      if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 0 ]]; then
        _fsMsg_ "Skipping..."
        break
      fi
    else
      if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 1 ]]; then
        _fsMsg_ "Skipping..."
        break
      fi
    fi
    
      # binance proxy json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}.json" 'sudo' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"binance\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${FS_PROXY_BINANCE_IP}:8990/api/v3\"" \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false" \
    "        }" \
    "    }" \
    "}"
    
      # binance proxy futures json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}_futures.json" 'sudo' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"binance\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${FS_PROXY_BINANCE_IP}:8991/api/v3\"" \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false" \
    "        }" \
    "    }" \
    "}"
    
      # binance proxy project file
    _fsFileCreate_ "${_yml}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${FS_PROXY_BINANCE}:" \
    "    image: ${_docker}" \
    "    container_name: ${FS_PROXY_BINANCE}" \
    "    command: >" \
    "      --port-spot=8990" \
    "      --port-futures=8991" \
    "      --verbose" \
    
    _fsDockerProject_ "$(basename "${_yml}")" 'compose-force'
    
    break
  done
}

# KUCOIN-PROXY
# credit: https://github.com/mikekonan/exchange-proxy

_fsSetupKucoinProxy_() {
  local _docker="mikekonan/exchange-proxy:latest-amd64"
  local _yml="${FS_DIR}/${FS_PROXY_KUCOIN}.yml"
  
  _fsMsgTitle_ 'PROXY FOR KUCOIN'
  
  while true; do
    if [[ "$(_fsDockerPsName_ "${FS_PROXY_KUCOIN}")" -eq 0 ]]; then
      _fsMsg_ 'Is already running. (Port: 8980)'
      
      if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 0 ]]; then
        _fsMsg_ "Skipping..."
        break
      fi
    else
      if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 1 ]]; then
        _fsMsg_ "Skipping..."
        break
      fi
    fi
    
      # kucoin proxy json file; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${FS_DIR_USER_DATA}/${FS_PROXY_KUCOIN}.json" 'sudo' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"kucoin\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"timeout\": 60000," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${FS_PROXY_KUCOIN_IP}:8980/kucoin\"," \
    "                    \"private\": \"http://${FS_PROXY_KUCOIN_IP}:8980/kucoin\"" \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"timeout\": 60000" \
    "        }" \
    "    }" \
    "}"
    
      # kucoin proxy project file
    _fsFileCreate_ "${_yml}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${FS_PROXY_KUCOIN}:" \
    "    image: ${_docker}" \
    "    container_name: ${FS_PROXY_KUCOIN}" \
    "    command: >" \
    "      -port 8980" \
    "      -verbose 1"
    
    _fsDockerProject_ "$(basename "${_yml}")" 'compose-force'
    
    break
  done
}

# NGINX

_fsSetupNginx_() {
  local _nr=''
  local _username=''
  local _password=''
  local _passwordCompare=''
  local _ipPublic=''
  local _ipPublicTemp=''
  local _ipLocal=''
  local _htpasswd="${FS_DIR_PROXY}${FS_NGINX_CONFD_HTPASSWD}"
  local _htpasswdDir="${FS_DIR_PROXY}${FS_NGINX_CONFD_HTPASSWD%/*}"
  local _sysctl="${FS_DIR}/99-${FS_NAME}.conf"
  local _sysctlSymlink="/etc/sysctl.d/${_sysctl##*/}"
  
  _ipPublic="$(_fsValueGet_ "${FS_CONFIG}" '.ip_public')"
  _ipLocal="$(_fsValueGet_ "${FS_CONFIG}" '.ip_local')"
  
  while true; do
    if [[ "$(_fsDockerPsName_ "${FS_NGINX}_ip")" -eq 0 ]] || [[ "$(_fsDockerPsName_ "${FS_NGINX}_domain")" -eq 0 ]]; then
      if [[ -n "${_ipPublic}" ]] || [[ -n "${_ipLocal}" ]]; then
        if [[ -n "${_ipPublic}" ]]; then
          _ipPublicTemp="$(dig +short myip.opendns.com @resolver1.opendns.com)"
          if [[ -n "${_ipPublicTemp}" ]]; then
            if [[ ! "${_ipPublic}" = "${_ipPublicTemp}" ]]; then
              _fsMsgWarning_ 'Public IP has been changed. Run FreqUI setup again!'
            else
              if [[ "$(_fsCaseConfirmation_ "Skip reconfiguration of Nginx proxy?")" -eq 0 ]]; then
                _fsMsg_ "Skipping..."
                break
              fi
            fi
          else
            _fsMsgWarning_ 'Cannot retrieve public IP. Run FreqUI setup again!'
          fi
        else
          if [[ "$(_fsCaseConfirmation_ "Skip reconfiguration of Nginx proxy?")" -eq 0 ]]; then
            _fsMsg_ "Skipping..."
            break
          fi
        fi
      fi
    fi
    
      # set unprivileged ports to start with 80 for rootles nginx proxy
    _fsFileCreate_ "${_sysctl}" \
    "# ${FS_NAME}" \
    '# set unprivileged ports to start with 80 for rootles nginx proxy' \
    'net.ipv4.ip_unprivileged_port_start = 80'
    
    _fsSymlinkCreate_ "${_sysctl}" "${_sysctlSymlink}"
    
    sudo sysctl -p "${_sysctlSymlink}"
    
      # create frequi login data
    while true; do
      if [[ "$(_fsFile_ "${_htpasswd}")" -eq 0 ]]; then
        _fsMsg_ "FreqUI login data already found."
        
        if [[ "$(_fsCaseConfirmation_ "Skip generating new FreqUI login data?")" -eq 0 ]]; then
          _fsMsg_ "Skipping..."
          break
        fi
      fi
      
      _fsMsg_ "Create FreqUI login data now!"
      
      if [[ "$(_fsCaseConfirmation_ "Create login data manually?")" -eq 0 ]]; then
          # create login data to access frequi
        _loginData="$(_fsLoginData_)"
        _username="$(_fsLoginDataUsername_ "${_loginData}")"
        _password="$(_fsLoginDataPassword_ "${_loginData}")"
      else
          # generate login data if first time setup is non-interactive
        _username="$(_fsRandomBase64_ 16)"
        _password="$(_fsRandomBase64_ 16)"
        _fsMsgWarning_ 'FreqUI login data created automatically:'
        _fsMsg_ "Username: ${_username}"
        _fsMsg_ "Password: ${_password}"
        _fsCdown_ 10 'to copy/memorize login data... Restart setup to change!'
      fi
      
        # create htpasswd for frequi access
      mkdir -p "${_htpasswdDir}"
      sh -c "echo -n ${_username}':' > ${_htpasswd}"
      sh -c "openssl passwd ${_password} >> ${_htpasswd}"
      
      break
    done
    
    while true; do
      printf -- '%s\n' \
      "? How to access FreqUI:" \
      "  1) IP with SSL (self-signed)" \
      "  2) Domain with SSL (truecrypt)" >&2
      
      [[ -z "${_ipPublicTemp}" ]] && _ipPublicTemp="$(dig +short myip.opendns.com @resolver1.opendns.com)"
      
      if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
        read -rp "  Choose number (default: 1): " _nr
      elif  [[ -z "${_ipPublicTemp}" ]]; then
        _fsMsgWarning_ 'Cannot access public IP!'
        local _nr="1"
      else
        local _nr="1"
      fi
      
      case ${_nr} in 
        [1])
          _fsMsg_ "Continuing with 1) ..."
          _fsSetupNginxOpenssl_
          break
          ;;
        [2])
          _fsMsg_ "Continuing with 2) ..."
          _setupNginxLetsencrypt_
          break
          ;;
        *)
          _fsCaseInvalid_
          ;;
      esac
    done
    
    break
  done
}

_fsSetupNginxUnblock_() {
  local _webservices=(
  "gitlab"
  "apache"
  "apache2"
  "nginx"
  "lighttpd"
  )
  local _webservice=''
  local ports=(
  "80"
  "443"
  "9999"
  "9000-9100"
  )
  local _port=''
  
  for _webservice in "${_webservices[@]}"; do 
      # credit: https://stackoverflow.com/a/66344638
    if sudo systemctl status "${_webservice}" 2> /dev/null | grep -Fq "Active: active"; then
      _fsMsgWarning_ 'Stopping webservice to avoid ip/port collisions: '"${_webservice}"

      sudo systemctl stop "${_webservice}" > /dev/null 2> /dev/null || true
      sudo systemctl disable "${_webservice}" > /dev/null 2> /dev/null || true
    fi
  done
  
  for _port in "${ports[@]}"; do 
    if [[ -n "$(sudo lsof -n -sTCP:LISTEN -i:"${_port}")" ]]; then
      _fsMsgWarning_ 'Stopping webservice blocking port: '"${_port}"

      sudo fuser -k "${_port}/tcp" > /dev/null 2> /dev/null || true
    fi
  done
}

_fsSetupNginxOpenssl_() {
  local _url=''
  local _nr=''
  local _mode=''
  local _ipLocals=''
  local _ipLocal=''
  local _ipLocalDelete
  local _ipLocalsDelete=('^172')
  local _bypass=''
  local _regex='^[0-9]+$'
  local _sslPrivate='/etc/ssl/private'
  local _sslKey="${_sslPrivate}"'/nginx-selfsigned.key'
  local _sslCerts='/etc/ssl/certs'
  local _sslCert="${_sslCerts}"'/nginx-selfsigned.crt'
  local _sslParam="/etc/nginx/dhparam.pem"
  local _sslSnippets='/etc/nginx/snippets'
  local _sslConf="${_sslSnippets}"'/self-signed.conf'
  local _sslConfParam="${_sslSnippets}"'/ssl-params.conf'
  
  _ipPublic="$(dig +short myip.opendns.com @resolver1.opendns.com || true)"
  [[ -z "${_ipPublic}" ]] && _ipPublic='not set'
  
  while true; do
    printf -- '%s\n' \
    "? Which IP to access FreqUI:" \
    "  1) Public IP (${_ipPublic})" \
    "  2) Local IP" >&2
    
    if  [[ "${_ipPublic}" = 'not set' ]]; then
      _fsMsgWarning_ 'Cannot access public IP!'
      local _nr="2"
    elif [[ "${FS_OPTS_YES}" -eq 1 ]]; then
      read -rp "  Choose number (default: 1): " _nr
    else
      local _nr="1"
    fi
    
    case ${_nr} in 
      [1])
        _fsMsg_ "Continuing with 1) ..."
        _mode='public'
        break
        ;;
      [2])
        _fsMsg_ "Continuing with 2) ..."
        _mode='local'
        break
        ;;
      *)
        _fsCaseInvalid_
        ;;
    esac
  done
  
    # remove autorenew certificate for domains
  _fsCrontabRemove_ "freqstart --cert --yes" 
    # stop nginx domain container
  _fsDockerRemove_ "${FS_NGINX}_domain"
    # stop/disable native webservices and free blocked ports
  _fsSetupNginxUnblock_

  _fsValueUpdate_ "${FS_CONFIG}" '.domain' ''
  
    # public ip routine
  if [[ "${_mode}" = 'public' ]]; then
    _url="https://${_ipPublic}"
    
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_public' "${_ipPublic}"
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_local' ''
    
    # local ip routine
  elif [[ "${_mode}" = 'local' ]]; then
    read -a _ipLocals <<< "$(hostname -I)"
    
    printf -- '%s\n' \
    '? Which local IP do you want to use:' >&2
    
      # remove docker ip range
    for _ipLocalDelete in "${_ipLocalsDelete[@]}"; do
      for i in "${!_ipLocals[@]}"; do
        if [[ ${_ipLocals[i]} =~ $_ipLocalDelete ]]; then
          unset '_ipLocals[i]'
        fi
      done
    done
    
      # return ip list
    for i in "${!_ipLocals[@]}"; do
      _ipLocal="${_ipLocals[i]}"
      echo "  $((i + 1))"') '"${_ipLocal}" >&2
    done
    
    while true; do
      if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
        read -rp "  Choose number (default: 1): " _url
      else
        local _url='1'
      fi
      
      if [[ -z "${_url}" ]]; then
        _fsCaseEmpty_
        shift
      elif [[ ! $_url =~ $_regex ]]; then
        _url=''
        echo 'aaa'
        _fsCaseInvalid_
      fi
      
      if [[ -n "${_url}" ]]; then
        _url="$((_url - 1))"
        
        if [[ ! "${_ipLocals[$_url]+foo}" ]]; then
          _url=''
        echo 'bbb'

          _fsCaseInvalid_
        else
          _ipLocal="${_ipLocals[$_url]}"
          _fsMsg_ 'Continuing with: '"${_ipLocal}"
          _url="https://${_ipLocal}"
          break
        fi
      fi
    done
    
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_public' ''
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_local' "${_ipLocal}"
  fi
  _fsValueUpdate_ "${FS_CONFIG}" '.url' "${_url}"
  
    # create nginx docker project file
  _fsFileCreate_ "${FS_NGINX_YML}" \
  "version: '3'" \
  'services:' \
  "  ${FS_NGINX}_ip:" \
  "    container_name: ${FS_NGINX}_ip" \
  '    image: amd64/nginx:stable' \
  "    ports:" \
  '      - "0.0.0.0:80:80"' \
  '      - "0.0.0.0:443:443"' \
  '    volumes:' \
  "      - ${FS_DIR_PROXY}${FS_NGINX_CONFD}:${FS_NGINX_CONFD}" \
  "      - ${FS_DIR_PROXY}${_sslSnippets}:${_sslSnippets}" \
  "      - ${FS_DIR_PROXY}${_sslParam}:${_sslParam}" \
  "      - ${FS_DIR_PROXY}${_sslCerts}:${_sslCerts}" \
  "      - ${FS_DIR_PROXY}${_sslPrivate}:${_sslPrivate}"
  
    # create nginx conf for ip ssl; credit: https://serverfault.com/a/1060487
  _fsFileCreate_ "${FS_DIR_PROXY}${FS_NGINX_CONFD_FREQUI}" \
  'map $http_cookie $rate_limit_key {' \
  "    default \$binary_remote_addr;" \
  '    "~__Secure-rl-bypass='"${_bypass}"'" "";' \
  "}" \
  "limit_req_status 429;" \
  "limit_req_zone \$rate_limit_key zone=auth:10m rate=1r/m;" \
  "server {" \
  "    listen 0.0.0.0:80;" \
  "    location / {" \
  "        return 301 https://\$host\$request_uri;" \
  "    }" \
  "}" \
  "server {" \
  "    listen 0.0.0.0:443 ssl;" \
  "    include ${_sslConf};" \
  "    include ${_sslConfParam};" \
  "    location / {" \
  "        resolver 127.0.0.11;" \
  "        set \$_pass ${FS_FREQUI}:9999;" \
  "        auth_basic \"Restricted\";" \
  "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
  "        limit_req zone=auth burst=20 nodelay;" \
  '        add_header Set-Cookie "__Secure-rl-bypass='"${_bypass}"';Max-Age=31536000;Domain=$host;Path=/;Secure;HttpOnly";' \
  "        proxy_pass http://\$_pass;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "    }" \
  "    location /api {" \
  "        return 400;" \
  "    }" \
  "    location ~ ^/(${FS_NAME})/([^/]+)(.*) {" \
  "        resolver 127.0.0.11;" \
  "        set \$_pass \$2:9999\$3;" \
  "        proxy_pass http://\$_pass;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "    }" \
  "}" \
  
  mkdir -p "${FS_DIR_PROXY}${_sslPrivate}"
  mkdir -p "${FS_DIR_PROXY}${_sslCerts}"
  
  _fsFileCreate_ "${FS_DIR_PROXY}${_sslConf}" \
  "ssl_certificate ${_sslCert};" \
  "ssl_certificate_key ${_sslKey};"
  
  _fsFileCreate_ "${FS_DIR_PROXY}${_sslConfParam}" \
  "ssl_protocols TLSv1.2;" \
  "ssl_prefer_server_ciphers on;" \
  "ssl_dhparam ${_sslParam};" \
  "ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;" \
  "ssl_ecdh_curve secp384r1; # Requires nginx >= 1.1.0" \
  "ssl_session_timeout 10m;" \
  "ssl_session_cache shared:SSL:10m;" \
  "ssl_session_tickets off; # Requires nginx >= 1.5.9" \
  "ssl_stapling on; # Requires nginx >= 1.3.7" \
  "ssl_stapling_verify on; # Requires nginx => 1.3.7" \
  "resolver 8.8.8.8 8.8.4.4 valid=300s;" \
  "resolver_timeout 5s;" \
  "add_header X-Frame-Options DENY;" \
  "add_header X-Content-Type-Options nosniff;" \
  "add_header X-XSS-Protection \"1; mode=block\";"
  
  while true; do
    if [[ "$(_fsFileEmpty_ "${FS_DIR_PROXY}${_sslKey}")" -eq 0 ]]; then
      if [[ "$(_fsCaseConfirmation_ "Skip generating new SSL key?")" -eq 0 ]]; then
        _fsMsg_ "Skipping..."
        break
      else
        sudo rm -f "${FS_DIR_PROXY}${_sslKey}"
        sudo rm -f "${FS_DIR_PROXY}${_sslCert}"
        sudo rm -f "${FS_DIR_PROXY}${_sslParam}"
      fi
    fi
    
    touch "${FS_DIR_PROXY}${_sslParam}"

    #sudo chown -R "${FS_ROOTLESS}":"${FS_ROOTLESS}" "${FS_DIR_PROXY}"

      # generate self-signed certificate
    _fsDockerProject_ "${FS_NGINX_YML}" 'run-force' "${FS_NGINX}_ip" \
    "/bin/sh -c" \
    "openssl req -x509 -nodes -days 358000 -newkey rsa:2048 -keyout ${_sslKey} -out ${_sslCert} -subj /CN=localhost;" \
    "openssl dhparam -out ${_sslParam} 4096"
    
    break
  done
  
    # start nginx ip container
  _fsDockerProject_ "${FS_NGINX_YML}" 'compose-force'
  
  if [[ "$(_fsDockerPsName_ "${FS_NGINX}_ip")" -eq 1 ]]; then
    _fsMsgError_ 'Nginx container is not running!'
  fi
}

_setupNginxLetsencrypt_() {
  local _domain=''
  local _domainIp=''
  local _url=''
  local _ipPublic=''
  local _sslCert=''
  local _sslKey=''
  local _bypass=''
  local _sslNginx="${FS_DIR_PROXY}/certbot/conf/options-ssl-nginx.conf"
  local _sslDhparams="${FS_DIR_PROXY}/certbot/conf/ssl-dhparams.pem"
  local _certEmail=''
  local _cronCmd="freqstart --cert --yes"
  local _cronUpdate="30 0 * * 0" # update at 0:30am UTC on sunday every week
  
  _ipPublic="$(dig +short myip.opendns.com @resolver1.opendns.com)"
  _bypass="$(_fsRandomBase64UrlSafe_ 16)"
  _domain="$(_fsValueGet_ "${FS_CONFIG}" '.domain')"
  
  while true; do
    if [[ -z "${_domain}" ]]; then
      read -rp "? Enter your domain (www.example.com): " _domain
    fi
    
    if [[ -z "${_domain}" ]]; then
      _fsCaseEmpty_
    else
      if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_domain}\" correct?")" -eq 0 ]]; then
        if host "${_domain}" 1> /dev/null 2> /dev/null; then
          _domainIp="$(host "${_domain}" | awk '/has address/ { print $4 }')"
        fi
        
        if [[ ! "${_domainIp}" = "${_ipPublic}" ]]; then
          _fsMsg_ "The domain \"${_domain}\" does not point to \"${_ipPublic}\". Review DNS and try again!"
        else
          _fsValueUpdate_ "${FS_CONFIG}" '.domain' "${_domain}"
            # register ssl certificate with an email (recommended)
          if [[ "$(_fsCaseConfirmation_ "Register SSL certificate with an email (recommended)?")" -eq 0 ]]; then
            while true; do
              read -rp "? Your email: " _certEmail
              case ${_certEmail} in
                '')
                  _fsCaseEmpty_
                  ;;
                *)
                  if [[ "$(_fsCaseConfirmation_ 'Is your email "'"${_certEmail}"'" correct?')" -eq 0 ]]; then
                    _certEmail="--email ${_certEmail}"
                    break
                  else
                    _certEmail=''
                  fi
                  ;;
              esac
            done
          else
            _certEmail="--register-unsafely-without-email"
          fi
          
          break
        fi
      fi
      
      _domain=''
    fi
  done
  
  if [[ -n "${_domain}" ]]; then
    _url="https://${_domain}"
    _sslCert="/etc/letsencrypt/live/${_domain}/fullchain.pem"
    _sslKey="/etc/letsencrypt/live/${_domain}/privkey.pem"
    
      # stop nginx ip container
    _fsDockerRemove_ "${FS_NGINX}_ip"
      # stop/disable native webservices and free blocked ports
    _fsSetupNginxUnblock_
    
    _fsValueUpdate_ "${FS_CONFIG}" '.domain' "${_domain}"
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_public' ''
    _fsValueUpdate_ "${FS_CONFIG}" '.ip_local' ''
    _fsValueUpdate_ "${FS_CONFIG}" '.url' "${_url}"
    
    mkdir -p "${FS_DIR_PROXY}/certbot/conf"
    mkdir -p "${FS_DIR_PROXY}/certbot/www"
    mkdir -p "${FS_DIR_PROXY}/certbot/conf/live/${_domain}"
    
      # credit: https://github.com/wmnnd/nginx-certbot/
    _fsFileCreate_ "${FS_NGINX_YML}" \
    "version: '3'" \
    'services:' \
    "  ${FS_NGINX}_domain:" \
    '    image: amd64/nginx:stable' \
    "    container_name: ${FS_NGINX}_domain" \
    "    ports:" \
    '      - "0.0.0.0:80:80"' \
    '      - "0.0.0.0:443:443"' \
    '    volumes:' \
    "      - ${FS_DIR_PROXY}${FS_NGINX_CONFD}:${FS_NGINX_CONFD}" \
    "      - ${FS_DIR_PROXY}/certbot/conf:/etc/letsencrypt" \
    "      - ${FS_DIR_PROXY}/certbot/www:/var/www/certbot" \
    "  ${FS_CERTBOT}:" \
    '    image: certbot/certbot:latest' \
    "    container_name: ${FS_CERTBOT}" \
    '    volumes:' \
    "      - ${FS_DIR_PROXY}/certbot/conf:/etc/letsencrypt" \
    "      - ${FS_DIR_PROXY}/certbot/www:/var/www/certbot"
    
      # download recommended TLS parameters
    if [[ "$(_fsFile_ "${_sslNginx}")" -eq 1 ]] || [[ "$(_fsFile_ "${_sslDhparams}")" -eq 1 ]]; then
      curl --connect-timeout 10 -s \
      "https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf" \
      > "${_sslNginx}"
      
      curl --connect-timeout 10 -s \
      "https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem" \
      > "${_sslDhparams}"
      
      _fsFileExit_ "${_sslNginx}"
      _fsFileExit_ "${_sslDhparams}"
    fi
    
      # workaround for first setup while missing cert files
    if [[ "$(_fsFile_ "${_sslCert}")" -eq 1 ]] || [[ "$(_fsFile_ "${_sslKey}")" -eq 1 ]]; then
      _fsFileCreate_ "${FS_DIR_PROXY}${FS_NGINX_CONFD_FREQUI}" \
      "server {" \
      "    listen 0.0.0.0:80;" \
      "    location /.well-known/acme-challenge {" \
      "        default_type \"text/plain\";" \
      "        root /var/www/certbot;" \
      "    }" \
      "}"
    fi
    
      # start nginx container
    _fsDockerProject_ "${FS_NGINX_YML}" 'compose-force' "${FS_NGINX}_domain"
    
      # create letsencrypt certificate
    _fsDockerProject_ "${FS_NGINX_YML}" 'run-force' "${FS_CERTBOT}" \
    "certonly --webroot -w /var/www/certbot ${_certEmail} -d ${_domain} --rsa-key-size 4096 --agree-tos"
    
      # create nginx conf for domain ssl; credit: https://serverfault.com/a/1060487
    _fsFileCreate_ "${FS_DIR_PROXY}${FS_NGINX_CONFD_FREQUI}" \
    'map $http_cookie $rate_limit_key {' \
    "    default \$binary_remote_addr;" \
    '    "~__Secure-rl-bypass='"${_bypass}"'" "";' \
    "}" \
    "limit_req_status 429;" \
    "limit_req_zone \$rate_limit_key zone=auth:10m rate=1r/m;" \
    "server {" \
    "    listen 0.0.0.0:80;" \
    "    location / {" \
    "        return 301 https://\$host\$request_uri;" \
    "    }" \
    "    location /.well-known/acme-challenge {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/certbot;" \
    "    }" \
    "}" \
    "server {" \
    "    listen 0.0.0.0:443 ssl http2;" \
    "    ssl_certificate ${_sslCert};" \
    "    ssl_certificate_key ${_sslKey};" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    location /.well-known/acme-challenge {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/certbot;" \
    "    }" \
    "    location / {" \
    "        resolver 127.0.0.11;" \
    "        set \$_pass ${FS_FREQUI}:9999;" \
    "        auth_basic \"Restricted\";" \
    "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
    "        limit_req zone=auth burst=20 nodelay;" \
    '        add_header Set-Cookie "__Secure-rl-bypass='"${_bypass}"';Max-Age=31536000;Domain=$host;Path=/;Secure;HttpOnly";' \
    "        proxy_pass http://\$_pass;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "    }" \
    "    location /api {" \
    "        return 400;" \
    "    }" \
    "    location ~ ^/(${FS_NAME})/([^/]+)(.*) {" \
    "        resolver 127.0.0.11;" \
    "        set \$_pass \$2:9999\$3;" \
    "        proxy_pass http://\$_pass;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "    }" \
    "}" \
    
      # start nginx domain container
    _fsDockerProject_ "${FS_NGINX_YML}" 'compose-force' "${FS_NGINX}_domain"
    
    if [[ "$(_fsDockerPsName_ "${FS_NGINX}_domain")" -eq 1 ]]; then
      _fsMsgError_ 'Nginx container is not running!'
    fi
    
      # set cron for domain autorenew certificate
    _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
  fi
}

# FREQUI

_fsSetupFrequi_() {
  local _url=''
  
  _url="$(_fsValueGet_ "${FS_CONFIG}" ".url")"
  
  _fsMsgTitle_ "FREQUI"
  
  while true; do
    if [[ "$(_fsDockerPsName_ "${FS_FREQUI}")" -eq 0 ]]; then
      _fsMsg_ "Is active: ${_url}"
      if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 0 ]]; then
        break
      fi
    else
      if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 1 ]]; then
        break
      fi
    fi
    
    _fsSetupFirewall_
    _fsSetupNginx_
    _fsSetupFrequiJson_
    _fsSetupFrequiCompose_
    
    break
  done
}

_fsSetupFrequiJson_() {
  local _jwt=''
  local _username=''
  local _password=''
  local _url=''
  local _json="${FS_DIR_USER_DATA}/${FS_FREQUI}.json"
  local _jsonServer="${FS_DIR_USER_DATA}/${FS_FREQUI}_server.json"
  
  _jwt="$(_fsValueGet_ "${_json}" ".api_server.jwt_secret_key")"
  _username="$(_fsValueGet_ "${_json}" ".api_server.username")"
  _password="$(_fsValueGet_ "${_json}" ".api_server.password")"
  _url="$(_fsValueGet_ "${FS_CONFIG}" ".url")"
  
    # generate jwt if it is not set in config
  [[ -z "${_jwt}" ]] && _jwt="$(_fsRandomBase64UrlSafe_ 32)"
  
  while true; do
    if [[ -n "${_username}" ]] || [[ -n "${_password}" ]]; then
      _fsMsg_ "API login data already found."
      
      if [[ "$(_fsCaseConfirmation_ "Skip generating new API login data?")" -eq 0 ]]; then
        break
      fi
    fi
    
    _fsMsg_ "Create API login data now!"
    
    if [[ "$(_fsCaseConfirmation_ "Create login data manually?")" -eq 0 ]]; then
      _loginData="$(_fsLoginData_)"
      _username="$(_fsLoginDataUsername_ "${_loginData}")"
      _password="$(_fsLoginDataPassword_ "${_loginData}")"
    else
        # generate login data if first time setup is non-interactive
      _username="$(_fsRandomBase64_ 16)"
      _password="$(_fsRandomBase64_ 16)"
      _fsMsgWarning_ 'API login data created automatically:'
      _fsMsg_ "Username: ${_username}"
      _fsMsg_ "Password: ${_password}"
      _fsCdown_ 10 'to copy/memorize login data... Restart setup to change!'
    fi
    
    break
  done
  
  if [[ -n "${_username}" ]] && [[ -n "${_password}" ]]; then
      # create frequi json for bots; note: sudo because of freqtrade docker user
    _fsFileCreate_ "${_json}" 'sudo' \
    '{' \
    '    "api_server": {' \
    '        "enabled": true,' \
    '        "listen_ip_address": "0.0.0.0",' \
    '        "listen_port": 9999,' \
    '        "verbosity": "error",' \
    '        "enable_openapi": false,' \
    '        "jwt_secret_key": "'"${_jwt}"'",' \
    '        "CORS_origins": ["'"${_url}"'"],' \
    '        "username": "'"${_username}"'",' \
    '        "password": "'"${_password}"'"' \
    '    }' \
    '}'
  else
    _fsMsgError_ 'Passwort or username missing!'
  fi
}

_fsSetupFrequiCompose_() {
  local _frequiStrategy='DoesNothingStrategy'
  local _frequiServerLog="${FS_DIR_USER_DATA}/logs/${FS_FREQUI}.log"
  local _docker="freqtradeorg/freqtrade:stable"
  local _json="${FS_DIR_USER_DATA}/${FS_FREQUI}.json"
  local _jsonServer="${FS_DIR_USER_DATA}/${FS_FREQUI}_server.json"
  local _yml="${FS_DIR}/${FS_FREQUI}.yml"
  
    # note: sudo because of freqtrade docker user
  _fsFileCreate_ "${_jsonServer}" 'sudo' \
  "{" \
  "    \"max_open_trades\": 1," \
  "    \"stake_currency\": \"BTC\"," \
  "    \"stake_amount\": 0.05," \
  "    \"fiat_display_currency\": \"USD\"," \
  "    \"dry_run\": true," \
  "    \"entry_pricing\": {" \
  "        \"price_side\": \"same\"," \
  "        \"use_order_book\": true," \
  "        \"order_book_top\": 1," \
  "        \"price_last_balance\": 0.0," \
  "        \"check_depth_of_market\": {" \
  "            \"enabled\": false," \
  "            \"bids_to_ask_delta\": 1" \
  "        }" \
  "    }," \
  "    \"exit_pricing\": {" \
  "        \"price_side\": \"same\"," \
  "        \"use_order_book\": true," \
  "        \"order_book_top\": 1" \
  "    }," \
  "    \"exchange\": {" \
  "        \"name\": \"binance\"," \
  "        \"key\": \"\"," \
  "        \"secret\": \"\"," \
  "        \"ccxt_config\": {}," \
  "        \"ccxt_async_config\": {" \
  "        }," \
  "        \"pair_whitelist\": [" \
  "            \"ETH/BTC\"" \
  "        ]" \
  "    }," \
  "    \"pairlists\": [" \
  "        {\"method\": \"StaticPairList\"}" \
  "    ]," \
  "    \"bot_name\": \"${FS_FREQUI}\"," \
  "    \"initial_state\": \"running\"" \
  "}"
  
  _fsFileCreate_ "${_yml}" \
  "---" \
  "version: '3'" \
  "services:" \
  "  ${FS_FREQUI}:" \
  "    image: ${_docker}" \
  "    container_name: ${FS_FREQUI}" \
  "    ports:" \
  "      - \"0.0.0.0:9999:9999\"" \
  "    volumes:" \
  "      - \"${FS_DIR_USER_DATA}:/freqtrade/user_data\"" \
  "    command: >" \
  "      trade" \
  "      --logfile /freqtrade/user_data/logs/${_frequiServerLog##*/}" \
  "      --strategy ${_frequiStrategy}" \
  "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
  "      --config /freqtrade/user_data/${_jsonServer##*/}" \
  "      --config /freqtrade/user_data/${_json##*/}"
  
  _fsDockerProject_ "${_yml}" 'compose-force'
}

###
# START

_fsStart_() {
  local _yml="${1:-}"
  local _symlink="${FS_SYMLINK}"
    
  # check if symlink from setup routine exist
  if [[ "$(_fsSymlinkValidate_ "${_symlink}")" -eq 1 ]]; then
    _fsMsgError_ "Start setup first!"
  fi
  
  _fsConf_
  
  if [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
    _fsDockerProject_ "${_yml}" "quit"
  elif [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
    _fsDockerProject_ "${_yml}" "compose"
  fi
  
  _fsStats_
}

###
# UTILITY
_fsLogo_() {
  printf -- '%s\n' \
  "    __                  _            _" \
  "   / _|_ _ ___ __ _ ___| |_ __ _ _ _| |_" \
  "  |  _| '_/ -_) _\` (__-\  _/ _\` | '_|  _|" \
  "  |_| |_| \___\__, /___/\__\__,_|_|  \__|" \
  "                 |_|    ${FS_VERSION} - rootless" >&2
}

_fsStats_() {
  local _time=''
  local _memory=''
  local _disk=''
  local _cpuCores=''
  local _cpuLoad=''
  local _cpuUsage=''
  
    # some handy stats to get you an impression how your server compares to the current possibly best location for binance
  _time="$( (time curl --connect-timeout 10 -X GET "https://api.binance.com/api/v3/exchangeInfo?symbol=BNBBTC") 2>&1 > /dev/null \
  | grep -o "real.*s" \
  | sed "s#real/\t##" )"
  _memory="$(free -m | awk 'NR==2{printf "%s/%sMB (%.2f%%)", $3,$2,$3*100/$2 }')"
  _disk="$(df -h | awk '$NF=="/"{printf "%d/%dGB (%s)", $3,$2,$5}')"
  
  _cpuCores="$(nproc)"
  _cpuLoad="$(awk '{print $3}'< /proc/loadavg)"
  _cpuUsage="$(echo | awk -v c="${_cpuCores}" -v l="${_cpuLoad}" '{print l*100/c}' | awk -F. '{print $1}')"
  
  printf -- '%s\n' \
  "" \
  "  Time to API (Binance): ${_time}" \
  "  CPU Usage: ${_cpuUsage}% (avg. 15min)" \
  "  Memory Usage: ${_memory}" \
  "  Disk Usage: ${_disk}" >&2
}

_fsUsage_() {
  printf -- '%s\n' \
  "" \
  "  Freqstart simplifies the use of Freqtrade with Docker. Including a setup guide for Freqtrade," \
  "  configurations and FreqUI with a secured SSL proxy for IP or domain. Freqtrade automatically" \
  "  installs implemented strategies based on Docker Compose files and detects necessary updates." \
  "" \
  "+ USAGE" \
  "  Start: ${FS_FILE} --compose example.yml --yes" \
  "  Quit: ${FS_FILE} --quit example.yml --yes" \
  "" \
  "+ OPTIONS" \
  "  -s, --setup     Install and update" \
  "  -c, --compose   Start docker project" \
  "  -q, --quit      Stop docker project" \
  "  -y, --yes       Yes on every confirmation" \
  "  --reset         Stop and remove all Docker images, containers und networks but keep all files" >&2
  
  exit 0
}

_fsConf_() {
  local _domain=''
  local _url=''
  local _ipPublic=''
  local _ipPublicTmp=''
  local _ipLocal=''
  local _user=''
  local _userTmp=''
  
  if [[ "$(_fsFile_ "${FS_CONFIG}")" -eq 0 ]]; then
    _domain="$(_fsValueGet_ "${FS_CONFIG}" '.domain')"
    _url="$(_fsValueGet_ "${FS_CONFIG}" '.url')"
    _ipPublic="$(_fsValueGet_ "${FS_CONFIG}" '.ip_public')"
    _ipLocal="$(_fsValueGet_ "${FS_CONFIG}" '.ip_local')"
    _userTmp="$(_fsValueGet_ "${FS_CONFIG}" '.user')"
    
      # validate public ip if set
    if [[ -n "${_ipPublic}" ]]; then
      _ipPublicTmp="$(dig +short myip.opendns.com @resolver1.opendns.com)"
      
      if [[ -n "${_ipPublicTmp}" ]]; then
        if [[ ! "${_ipPublic}" = "${_ipPublicTmp}" ]]; then
          _fsMsgWarning_ 'Public IP has been changed. Run FreqUI setup again!'
        fi
      else
        _fsMsgWarning_ 'Cannot retrieve public IP. Run FreqUI setup again!'
      fi
    fi
    
    _user="$(_fsValueGet_ "${FS_CONFIG}" '.user')"
    _userTmp="$(id -u -n)"

    if [[ -n "${_user}" ]] && [[ ! "${_user}" = "${_userTmp}" ]]; then
      _fsMsgWarning_ 'You are not logged in as docker rootless user!'
      _fsCdown_ 5 'to login as: '"${_user}"
      sudo rm -rf "${FS_TMP}"
      sudo machinectl shell "${_user}@"
      exit 0
    fi
  fi
  
  _fsFileCreate_ "${FS_CONFIG}" \
  '{' \
  '    "version": "'"${FS_VERSION}"'",' \
  '    "user": "'"${_user}"'",' \
  '    "domain": "'"${_domain}"'",' \
  '    "url": "'"${_url}"'",' \
  '    "ip_public": "'"${_ipPublic}"'",' \
  '    "ip_local": "'"${_ipLocal}"'"' \
  '}'
}

_fsFile_() {
  local _file="${1:-}" # optional: path to file
  
  if [[ -z "${_file}" ]]; then
    echo 1
  elif [[ -f "${_file}" ]]; then
    echo 0
  else
    echo 1
  fi
}

_fsFileEmpty_() {
  local _file="${1:-}" # optional: path to file
  
  if [[ "$(_fsFile_ "${_file}")" -eq 0 ]]; then
    if [[ -s "${_file}" ]]; then
      echo 0
    else
      echo 1
    fi
  else
    echo 1
  fi
}

_fsFileExit_() {
  local _file="${1:-}" # optional: path to file
  
  if [[ "$(_fsFile_ "${_file}")" -eq 1 ]]; then
    _fsMsgError_ "File does not exist: ${_file}"
  fi
}

_fsFileCreate_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"
  local _mode="${2}"
  local _input=()
  local _output=''
  local _fileTmp=''
  local _file="${_filePath##*/}"
  local _fileDir="${_filePath%/*}"
  local _fileHash=''
    
    # shift args in case of sudo
  [[ "${_mode}" = 'sudo' ]] && shift
  shift; _input=("${@}")
  
  _fileHash="$(_fsRandomHex_ 8)"
  _fileTmp="${FS_TMP}"'/'"${_fileHash}"'_'"${_file}"
  
  _output="$(printf -- '%s\n' "${_input[@]}")"
  
  echo "${_output}" | tee "${_fileTmp}" > /dev/null
  [[ "$(_fsFileEmpty_ "${_fileTmp}")" -eq 1 ]] && _fsMsgError_ 'File is empty!'
  
  if [[ "${_mode}" = 'sudo' ]]; then
    sudo mkdir -p "${_fileDir}"
    sudo cp "${_fileTmp}" "${_filePath}"
  else
    mkdir -p "${_fileDir}"
    cp "${_fileTmp}" "${_filePath}"
  fi
  
  _fsFileExit_ "${_filePath}"
}

_fsCrontab_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  local _cronJob="${2} ${_cronCmd}"
    # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -
  
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
    _fsMsgError_ "Cron not set: ${_cronCmd}"
  fi
}

_fsCrontabRemove_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
    # credit: https://stackoverflow.com/a/17975418
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -
    
    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
      _fsMsgError_ "Cron not removed: ${_cronCmd}"
    fi
  fi
}

_fsCrontabValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  
  crontab -l 2> /dev/null | grep -q "${_cronCmd}"  && echo 0 || echo 1
}

_fsValueGet_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"
  local _fileType="${_filePath##*.}"
  local _key="${2}"
  local _value=''
  
  if [[ "$(_fsFile_ "${_filePath}")" -eq 0 ]]; then
    if [[ "${_fileType}" = 'json' ]]; then
        # get value from json
      _value="$(jq -r "${_key}"' // empty' "${_filePath}")"
    else
        # get value from other filetypes
      _value="$(cat "${_filePath}" | { grep -o "${_key}\"\?: \"\?.*\"\?" || true; } \
      | sed "s,\",,g" \
      | sed "s,\s,,g" \
      | sed "s#,##g" \
      | sed "s,${_key}:,,")"
    fi
    
    if [[ -n "${_value}" ]]; then
      echo "${_value}"
    fi
  fi
}

_fsValueUpdate_() {
  [[ $# -lt 3 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"
  local _file="${_filePath##*/}"
  local _fileType="${_filePath##*.}"
  local _fileHash=''
  local _fileTmp=''
  local _json=''
  local _jsonUpdate=''
  local _key="${2}"
  local _value="${3}"
  
  _fsFileExit_ "${_filePath}"
  
  _fileHash="$(_fsRandomHex_ 8)"
  _fileTmp="${FS_TMP}/${_fileHash}_${_file}"
  
  if [[ "${_fileType}" = 'json' ]]; then
      # update value for json
    _json="$(_fsValueGet_ "${_filePath}" '.')"
      # credit: https://stackoverflow.com/a/24943373
    _jsonUpdate="$(jq "${_key}"' = $newVal' --arg newVal "${_value}" <<< "${_json}")"
    
    printf '%s\n' "${_jsonUpdate}" | jq . | tee "${_fileTmp}" > /dev/null
  else
      # update value for other filetypes
    cp "${_filePath}" "${_fileTmp}"
    
    if grep -qow "\"${_key}\": \".*\"" "${_fileTmp}"; then # "key": "value"
      sed -i "s,\"${_key}\": \".*\",\"${_key}\": \"${_value}\"," "${_fileTmp}"
    elif grep -qow "\"${_key}\": \".*\"" "${_fileTmp}"; then # "key": value
      sed -i "s,\"${_key}\": .*,\"${_key}\": ${_value}," "${_fileTmp}"
    elif grep -qow "${_key}: \".*\"" "${_fileTmp}"; then # key: "value"
      sed -i "s,${_key}: \".*\",${_key}: \"${_value}\"," "${_fileTmp}"
    elif grep -qow "${_key}: \".*\"" "${_fileTmp}"; then # key: value
      sed -i "s,${_key}: .*,${_key}: ${_value}," "${_fileTmp}"
    else
      _fsMsgError_ 'Cannot find key "'"${_key}"'" in: '"${_filePath}"
    fi
  fi
    # override file if different
  if ! cmp --silent "${_fileTmp}" "${_filePath}"; then
    cp "${_fileTmp}" "${_filePath}"
  fi
}

_fsCaseConfirmation_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _question="${1}"
  local _yesNo=''
  
  if [[ "${FS_OPTS_YES}" -eq 0 ]]; then
    printf -- '%s\n' "? ${_question} (y/n) y" >&2
    echo 0
  else
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
  fi
}

_fsCaseInvalid_() {
  _fsMsg_ 'Invalid response!'
}

_fsCaseEmpty_() {
  _fsMsg_ 'Response cannot be empty!'
}

_fsIsUrl_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _url="${1}"
    # credit: https://stackoverflow.com/a/55267709
  local _regex="^(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$"
  local _status=''
  
  if [[ $_url =~ $_regex ]]; then
      # credit: https://stackoverflow.com/a/41875657
    _status="$(curl --connect-timeout 10 -o /dev/null -Isw '%{http_code}' "${_url}")"
    
    if [[ "${_status}" = '200' ]]; then
      echo 0
    else
      echo 1
    fi
  else
    _fsMsgError_ "Url is not valid: ${_url}"
  fi
}

_fsCdown_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _secs="${1}"; shift
  local _text="${*}"
  
  while [[ "${_secs}" -gt -1 ]]; do
    if [[ "${_secs}" -gt 0 ]]; then
      printf '\r\033[K< Waiting '"${_secs}"' seconds '"${_text}" >&2
      sleep 0.5
      printf '\r\033[K> Waiting '"${_secs}"' seconds '"${_text}" >&2
      sleep 0.5
    else
      printf '\r\033[K' >&2
    fi
    : $((_secs--))
  done
}

_fsIsAlphaDashUscore_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _string="${1}"
  local _regex='^[[:alnum:]_-]+$'
  
  if [[ $_string =~ $_regex ]]; then
    echo 0
  else
    _fsMsg_ "Only alpha-numeric, dash and underscore characters are allowed!"
    echo 1
  fi
}

_fsDedupeArray_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  declare -A _tmpArray
  declare -a _uniqueArray
  local _i
  
  for _i in "$@"; do
    { [[ -z ${_i} || -n ${_tmpArray[${_i}]:-} ]]; } && continue
    _uniqueArray+=("${_i}") && _tmpArray[${_i}]=x
  done
  
  printf '%s\n' "${_uniqueArray[@]}"
}

_fsTimestamp_() {
  date +"%y%m%d%H%M%S"
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

_fsReset_() {
  _fsMsgTitle_ 'RESET'
  _fsMsgWarning_ 'Stopp and remove all containers, networks and images!'
  
  if [[ "$(_fsCaseConfirmation_ "Are you sure you want to continue?")" -eq 0 ]]; then
      # stop and remove docker images, container and networks but keeps all files
    _fsDockerPurge_
  fi
}

_fsUserValidate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _user="${1}"

  if id -u "${_user}" >/dev/null 2>&1; then
    echo 0 # user exist
  else
    echo 1 # user does not exist
  fi
}

_fsPkgs_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _pkgs=("$@")
  local _pkg=''
  local _status=''
  local _getDocker="${FS_DIR}"'/get-docker.sh'
  
  for _pkg in "${_pkgs[@]}"; do
    if [[ "$(_fsPkgsStatus_ "${_pkg}")" -eq 1 ]]; then
      if [[ "${_pkg}" = 'docker-ce' ]]; then
          # thanks: tomjrtsmith
        curl --connect-timeout 10 -fsSL "https://get.docker.com" -o "${_getDocker}"
        _fsFileExit_ "${_getDocker}"
        sudo chmod +x "${_getDocker}"
        sh "${_getDocker}"
        rm -f "${_getDocker}"
      elif [[ "${_pkg}" = 'ufw' ]]; then
          # firewall setup
        sudo apt install -y -q ufw
        sudo ufw logging medium > /dev/null
      else
        sudo apt install -y "${_pkg}"
      fi
        # validate installation
      if [[ "$(_fsPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
        _fsMsg_ "Installed: ${_pkg}"
      else
        _fsMsgError_ "Cannot install: ${_pkg}"
      fi
    fi
  done
}

_fsPkgsStatus_() {
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

_fsSymlinkCreate_() {
  [[ $# -lt 2 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"

  local _source="${1}"
  local _link="${2}"
  local _error=1

  if [[ -f "${_source}" ]]; then _error=0; fi
  if [[ -d "${_source}" ]]; then _error=0; fi
  
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

_fsScriptLock_() {
  local _lockDir="${FS_TMP}/${FS_NAME}.lock"
  
  if [[ -n "${FS_TMP}" ]]; then
    if [[ -d "${_lockDir}" ]]; then
        # set error to 99 and do not remove tmp dir
      _fsMsgError_ "Script is already running! Delete folder if this is an error: sudo rm -rf ${FS_TMP}" 99
    elif ! mkdir -p "${_lockDir}" 2> /dev/null; then
      _fsMsgError_ "Unable to acquire script lock: ${_lockDir}"
    fi
  else
    _fsMsgError_ "Temporary directory is not defined!"
  fi
}

_fsLoginData_() {
    local _username=''
    local _password=''
    local _passwordCompare=''
    
      # create username
    while true; do
      read -rp '  Enter username: ' _username >&2
      
      if [[ -n "${_username}" ]]; then
        if [[ "$(_fsCaseConfirmation_ "Is the username correct: ${_username}")" -eq 0 ]]; then
          break
        else
          _fsMsg_ "Try again!"
        fi
      fi
    done
    
      # create password - NON VERBOSE
    while true; do
      echo -n '  Enter password (ENTRY HIDDEN): ' >&2
      read -rs _password >&2
      echo >&2
      case ${_password} in 
        "")
          _fsCaseEmpty_
          ;;
        *)
          echo -n '  Enter password again (ENTRY HIDDEN): ' >&2
          read -r -s _passwordCompare >&2
          echo >&2
          if [[ ! "${_password}" = "${_passwordCompare}" ]]; then
            _fsMsg_ "The password does not match. Try again!"
            _password=''
            _passwordCompare=''
          else
            break
          fi
          ;;
      esac
    done
      # output to non-verbose functions to split login data
    echo "${_username}"':'"${_password}"
}

_fsLoginDataUsername_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _username="${1}"
  echo "$(cut -d':' -f1 <<< "${_username}")"
}

_fsLoginDataPassword_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _password="${1}"
  echo "$(cut -d':' -f2 <<< "${_password}")"
}

_fsCleanup_() {
  local _error="${?}"
  trap - ERR EXIT SIGINT SIGTERM
  
  if [[ "${_error}" -ne 99 ]]; then
      # thanks: lsiem
    rm -rf "${FS_TMP}"
    _fsCdown_ 1 'to remove script lock...'
  fi
}

_fsErr_() {
  local _error="${?}"
  
  printf -- '%s\n' "Error in ${FS_FILE} in function ${1} on line ${2}" >&2
  exit "${_error}"
}

_fsMsg_() {
  local _msg="${1}"
  
  printf -- '%s\n' \
  "  ${_msg}" >&2
}

_fsMsgTitle_() {
  local _msg="${1}"
  
  printf -- '%s\n' \
  '' \
  "+ ${_msg}" >&2
}

_fsMsgWarning_() {
  local _msg="${1}"
  
  printf -- '%s\n' \
  "! [WARNING] ${_msg}" >&2
}

_fsMsgError_() {
  local _msg="${1}"
  local -r _code="${2:-90}" # optional: set to 90
  
  printf -- '%s\n' \
  '' \
  "! [ERROR] ${_msg}" >&2
  
  exit "${_code}"
}

_fsOptions_() {
  local -r _args=("${@}")
  local _opts
  
  _opts="$(getopt --options c:,q:,s,a,y,h --long compose:,quit:,setup,auto,yes,help,reset,cert -- "${_args[@]}" 2> /dev/null)" || {
    _fsLogo_
    _fsMsgError_ "Unkown or missing argument."
  }
  
  eval set -- "${_opts}"
  while true; do
    case "${1}" in
      --compose|-c)
        FS_OPTS_COMPOSE=0
        c_arg="${2}"
        shift
        shift
        ;;
      --setup|-s)
        FS_OPTS_SETUP=0
        shift
        ;;
      --quit|-q)
        FS_OPTS_QUIT=0
        q_arg="${2}"
        shift
        shift
        ;;
      --auto|-a)
        FS_OPTS_AUTO=0
        shift
        ;;
      --yes|-y)
        FS_OPTS_YES=0
        shift
        ;;
      --reset)
        FS_OPTS_RESET=0
        shift
        ;;
      --cert)
        FS_OPTS_CERT=0
        shift
        ;;
      --help|-h)
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

###
# RUNTIME

_fsScriptLock_
_fsOptions_ "${@}"
_fsLogo_

  # validate arguments
if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
  _fsMsgError_ "Option -a or --auto cannot be used with -q or --quit."
elif [[ "${FS_OPTS_QUIT}" -eq 0 ]] && [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
  _fsMsgError_ "Option -c or --compose cannot be used with -q or --quit."
elif [[ "${FS_OPTS_COMPOSE}" -eq 0 ]] && [[ -z "${c_arg}" ]]; then
  _fsMsgError_ "Setting an \"example.yml\" file with -c or --compose is required."
elif [[ "${FS_OPTS_QUIT}" -eq 0 ]] && [[ -z "${q_arg}" ]]; then
  _fsMsgError_ "Setting an \"example.yml\" file with -q or --quit is required."
elif [[ "${FS_OPTS_SETUP}" -eq 0 ]] && [[ "${FS_OPTS_YES}" -eq 0 ]]; then
  _fsMsgError_ "Option -s or --setup cannot be used with -y or --yes."
fi

  # run code
if [[ "${FS_OPTS_CERT}" -eq 0 ]]; then
  _fsDockerProject_ "${FS_NGINX_YML}" 'run-force' "${FS_CERTBOT}" "renew"
elif [[ "${FS_OPTS_SETUP}" -eq 0 ]]; then
  _fsSetup_
elif [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
  _fsStart_ "${c_arg}"
elif [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
  _fsStart_ "${q_arg}"
elif [[ "${FS_OPTS_RESET}" -eq 0 ]]; then
  _fsReset_
else
  _fsUsage_
fi

exit 0