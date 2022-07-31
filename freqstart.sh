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
readonly FS_VERSION='v1.0.2'
readonly FS_FILE="${0##*/}"
readonly FS_TMP="/tmp/${FS_NAME}"
readonly FS_SYMLINK="/usr/local/bin/${FS_NAME}"

FS_DIR="$(dirname "$(readlink --canonicalize-existing "${0}" 2> /dev/null)")"
readonly FS_DIR
readonly FS_DIR_PROXY="${FS_DIR}/proxy"
readonly FS_DIR_DOCKER="${FS_DIR}/docker"
readonly FS_DIR_USER_DATA="${FS_DIR}/user_data"
readonly FS_DIR_USER_DATA_STRATEGIES="${FS_DIR_USER_DATA}/strategies"
readonly FS_DIR_USER_DATA_LOGS="${FS_DIR_USER_DATA}/logs"

readonly FS_CONFIG="${FS_DIR}/${FS_NAME}.conf.json"
readonly FS_STRATEGIES="${FS_DIR}/${FS_NAME}.strategies.json"
readonly FS_AUTOUPDATE="${FS_DIR}/${FS_NAME}.autoupdate.sh"

readonly FS_NETWORK="${FS_NAME}"'_network'
readonly FS_NETWORK_SUBNET='172.35.0.0/16'
readonly FS_NETWORK_GATEWAY='172.35.0.1'

readonly FS_PROXY_BINANCE="${FS_NAME}"'_proxy_binance'
readonly FS_PROXY_BINANCE_IP='172.35.0.253'
readonly FS_PROXY_BINANCE_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}.json"
readonly FS_PROXY_BINANCE_FUTURES_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}_futures.json"
readonly FS_PROXY_BINANCE_YML="${FS_DIR}/${FS_PROXY_BINANCE}.yml"

readonly FS_PROXY_KUCOIN="${FS_NAME}"'_proxy_kucoin'
readonly FS_PROXY_KUCOIN_IP='172.35.0.252'
readonly FS_PROXY_KUCOIN_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_KUCOIN}.json"
readonly FS_PROXY_KUCOIN_YML="${FS_DIR}/${FS_PROXY_KUCOIN}.yml"

readonly FS_NGINX="${FS_NAME}"'_nginx'
readonly FS_NGINX_YML="${FS_DIR}"'/'"${FS_NAME}"'_nginx.yml'
readonly FS_NGINX_CONFD="/etc/nginx/conf.d"
readonly FS_NGINX_CONFD_FREQUI="${FS_NGINX_CONFD}"'/frequi.conf'
readonly FS_NGINX_CONFD_HTPASSWD="${FS_NGINX_CONFD}"'/.htpasswd'
readonly FS_CERTBOT="${FS_NAME}"'_certbot'

readonly FS_FREQUI="${FS_NAME}"'_frequi'
readonly FS_FREQUI_JSON="${FS_DIR_USER_DATA}/frequi.json"
readonly FS_FREQUI_SERVER_JSON="${FS_DIR_USER_DATA}/frequi_server.json"
readonly FS_FREQUI_YML="${FS_DIR}/${FS_NAME}_frequi.yml"

FS_HASH="$(xxd -l 8 -ps /dev/urandom)"
readonly FS_HASH

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

_fsDockerVarsPath_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _docker="${1}"
  local _dockerDir="${FS_DIR_DOCKER}"
  local _dockerName=''
  local _dockerTag=''
  local _dockerPath=''
  
  _dockerName="$(_fsDockerVarsName_ "${_docker}")"
  _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
  _dockerPath="${_dockerDir}/${_dockerName}_${_dockerTag}.docker"
  
  echo "${_dockerPath}"
}

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
  _token="$(curl -s "https://auth.docker.io/token?scope=repository:${_dockerRepo}:pull&service=registry.docker.io"  | jq -r '.token')"
  
  if [[ -n "${_token}" ]]; then
    curl -s --header "Accept: ${_acceptM}" --header "Accept: ${_acceptML}" --header "Authorization: Bearer ${_token}" \
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
  local _dockerPath=''
  local _dockerStatus=2
  local _dockerVersionLocal=''
  
  _dockerRepo="$(_fsDockerVarsRepo_ "${_dockerImage}")"
  _dockerTag="$(_fsDockerVarsTag_ "${_dockerImage}")"
  _dockerName="$(_fsDockerVarsName_ "${_dockerImage}")"
  _dockerCompare="$(_fsDockerVarsCompare_ "${_dockerImage}")"
  _dockerPath="$(_fsDockerVarsPath_ "${_dockerImage}")"
  
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
    elif [[ "$(_fsFile_ "${_dockerPath}")" -eq 0 ]]; then
        # if docker is not reachable try to load local backup
      docker load -i "${_dockerPath}"

      if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
        _dockerStatus=0
      fi
    fi
  fi
  
  _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"
  
  if [[ "${_dockerStatus}" -eq 0 ]]; then
      # if latest image is installed
    echo "${_dockerVersionLocal}"
  elif [[ "${_dockerStatus}" -eq 1 ]]; then
      # if image is updated
    if [[ ! -d "${FS_DIR_DOCKER}" ]]; then
      mkdir -p "${FS_DIR_DOCKER}"
    fi
    
    sudo rm -f "${_dockerPath}"
    docker save -o "${_dockerPath}" "${_dockerRepo}"':'"${_dockerTag}"
    [[ "$(_fsFile_ "${_dockerPath}")" -eq 1 ]] && _fsMsg_ "[WARNING] Cannot create backup for: ${_dockerRepo}:${_dockerTag}"
      # return local image version
    echo "${_dockerVersionLocal}"
  else
      # if image could not be installed
    _fsMsgError_ "Image not found: ${_dockerRepo}:${_dockerTag}"
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
  
	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
  
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
    sudo docker update --restart=no "${_dockerName}" > /dev/null
    sudo docker stop "${_dockerName}" > /dev/null
    sudo docker rm -f "${_dockerName}" > /dev/null
    
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
      _fsMsg_ "_ymlImage: ${_ymlImage}"
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

_fsDockerProjectPorts_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _ymlPath="${1}"
  local _dockerPorts=''
  local _dockerPort=''
  local _dockerPortDuplicate=''
  local _error=0
  
  _ymlFile="${_ymlPath##*/}"
  _ymlFileName="${_ymlFile%.*}"
  _ymlName="${_ymlFileName//-/_}"
  
  _dockerPortsYml=()
  while read -r; do
    _dockerPortsYml+=("$REPLY")
  done < <(grep -vE '^\s+#' "${_ymlPath}" \
  | grep 'ports:' -A 1 \
  | grep -oE "[0-9]{4}.*" \
  | sed "s,\",,g" \
  | sed "s,:.*,," || true)
  
  if (( ${#_dockerPortsYml[@]} )); then
    declare -A values=()
    for v in "${_dockerPortsYml[@]}"; do
      if [[ "${values["x$v"]+set}" = set ]]; then
        _fsMsg_ "Duplicate port found: ${v}"
        _error=$((_error+1))
      fi
      values["x$v"]=1
    done
    
    _dockerPortsProject=()
    while read -r; do
      _dockerPortsProject+=("$REPLY")
    done < <(docker ps -a -f name="${_ymlName}" | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")
    
    _dockerPortsAll=()
    while read -r; do
      _dockerPortsAll+=("$REPLY")
    done < <(docker ps -a | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")
    
    _dockerPortsBlocked=("$(printf '%s\n' "${_dockerPortsAll[@]}" "${_dockerPortsProject[@]}" | sort | uniq -u)")
    _dockerPortsCompare=("$(echo "${_dockerPortsYml[@]}" "${_dockerPortsBlocked[@]}" | tr ' ' '\n' | sort | uniq -D | uniq)")
    
    if (( ${#_dockerPortsCompare[@]} )); then
      for _dockerPortCompare in "${_dockerPortsCompare[@]}"; do
        if [[ "${_dockerPortCompare}" =~ ^[0-9]+$ ]]; then
          _error=$((_error+1))
          _fsMsgWarning_ "Port is already allocated: ${_dockerPortCompare}"
        fi
      done
    fi
  fi
  
	if [[ "${_error}" -eq 0 ]]; then
    echo 0
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
    _strategiesDir+=( "${FS_DIR_USER_DATA_STRATEGIES}" )
    
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
  local _configNew=''
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
  local _projectCronCmd=''
  local _projectCronUpdate=''
  local _projectFile=''
  local _projectFileType=''
  local _projectFileName=''
  local _projectName=''
  local _projectImages=1
  local _projectStrategies=1
  local _projectConfigs=1
  local _projectPorts=1
  local _projectContainers=''
  local _projectContainer=''
  local _procjectJson=''
  local _projectShell=''
  local _containerCmd=''
  local _containerRunning=''
  local _containerRestart=1
  local _containerName=''
  local _containerConfigs=''
  local _containerStrategy=''
  local _containerStrategyDir=''
  local _containerStrategyUpdate=''
  local _containerJson=''
  local _containerJsonInner=''
  local _containerConfPath=''
  local _containerApiPort=''
  local _containerApiJson=''
  local _containerLogfile=''
  local _containerLogfileTmp=''
  local _containerCount=0
  local _containerAutoupdate='false'
  local _containerAutoupdateCount=0
  local _strategyUpdate=''
  local _strategyDir=''
  local _strategyPath=''
  local _dockerCmd=''
  local _error=0
  
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
    
    if [[ "${_projectMode}" = "compose-force" ]]; then
      _projectPorts=0    
    else
      _projectPorts="$(_fsDockerProjectPorts_ "${_projectPath}")"
    fi
    
    _projectStrategies="$(_fsDockerProjectStrategies_ "${_projectPath}")"
    _projectConfigs="$(_fsDockerProjectConfigs_ "${_projectPath}")"
    _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
    
    [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectPorts}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectStrategies}" -eq 1 ]] && _error=$((_error+1))
    
    if [[ "${_error}" -eq 0 ]]; then
      if [[ "${_projectMode}" = 'compose-force' ]]; then
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} up --no-start --force-recreate ${_projectService}
      else
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} up --no-start --no-recreate ${_projectService}
      fi
    fi
  elif [[ "${_projectMode}" =~ "run" ]]; then
    _fsMsgTitle_ "Run project: ${_projectFile}"
    
    if [[ "${_projectMode}" = "run-force" ]]; then
      _projectPorts=0
    else
      _projectPorts="$(_fsDockerProjectPorts_ "${_projectPath}")"
    fi
    
    _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
    
    [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectPorts}" -eq 1 ]] && _error=$((_error+1))
    
    if [[ "${_error}" -eq 0 ]]; then
        # workaround to execute shell from variable; help: open for suggestions
      _projectShell="$(printf -- '%s\s' "${_projectArgs}" | grep -oE '^/bin/sh -c' || true)"
      
      if [[ -n "${_projectShell}" ]]; then
        _projectArgs="$(printf -- '%s' "${_projectArgs}" | sed 's,/bin/sh -c ,,')"
                
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} run --rm ${_projectService} /bin/sh -c "${_projectArgs}"
      else
        cd "${FS_DIR}" && docker-compose -f ${_projectFile} -p ${_projectName} run --rm ${_projectService} ${_projectArgs}
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
      _containerRunning="$(_fsDockerPsName_ "${_containerName}")"
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
        
          # create docker network if it does not exist; credit: https://stackoverflow.com/a/59878917
        docker network create --subnet="${FS_NETWORK_SUBNET}" --gateway "${FS_NETWORK_GATEWAY}" "${FS_NETWORK}" > /dev/null 2> /dev/null || true
        
          # connect container to docker network excl. nginx and certbot
        if [[ "${_containerName}" = "${FS_PROXY_BINANCE}" ]]; then
          docker network connect --ip "${FS_PROXY_BINANCE_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        elif [[ "${_containerName}" = "${FS_PROXY_KUCOIN}" ]]; then
          docker network connect --ip "${FS_PROXY_KUCOIN_IP}" "${FS_NETWORK}" "${_containerName}" > /dev/null 2> /dev/null || true
        elif [[ ! "${_containerName}" =~ ${FS_NGINX} ]] || [[ ! "${_containerName}" = "${FS_CERTBOT}" ]]; then
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
        _containerCmd="$(sudo docker inspect --format="{{.Config.Cmd}}" "${_projectContainer}" \
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
            _containerLogfile="${FS_DIR_USER_DATA_LOGS}"'/'"${_containerLogfile##*/}"
            
            if [[ "$(_fsFile_ "${_containerLogfile}")" -eq 0 ]]; then
                # workaround to preserve owner of file
              _containerLogfileTmp="${FS_TMP}"'/'"${_containerLogfile##*/}"'.tmp'
              touch "${_containerLogfileTmp}"
              cp --no-preserve=all "${_containerLogfileTmp}" "${_containerLogfile}"
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
              if [[ "${_containerRunning}" -eq 0 ]] && [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
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
        _containerApiPort="$(docker inspect --format="{{json .}}" "${_containerName}" | jq -r '.NetworkSettings.Ports["9999/tcp"][0].HostPort // empty')"
        _containerApiJson="$(echo "${_containerCmd}" | grep -os "${FS_FREQUI_JSON##*/}" || true)"
        
        if [[ -n "${_containerApiPort}" ]] && [[ -z "${_containerApiJson}" ]]; then
          _fsMsg_ "[WARNING] Port (${_containerApiPort}) is set but confing (${_containerApiJson}) is missing in command for FreqUI access!"
        elif [[ -z "${_containerApiPort}" ]] && [[ -n "${_containerApiJson}" ]]; then
          _fsMsg_ "[WARNING] Config (${_containerApiJson}) is set in command but port (9000-9100) is missing for FreqUI access!"
        elif [[ -z "${_containerApiPort}" ]] && [[ -z "${_containerApiJson}" ]]; then
          _fsMsg_ "Bot is not exposed to FreqUI."
        else
          _fsMsg_ "Bot is accessible via FreqUI on port: ${_containerApiPort}"
        fi
        
          # compare latest docker image with container image
        _containerImage="$(sudo docker inspect --format="{{.Config.Image}}" "${_projectContainer}")"
        _containerImageVersion="$(sudo docker inspect --format="{{.Image}}" "${_projectContainer}")"
        _dockerImageVersion="$(docker inspect --format='{{.Id}}' "${_containerImage}")"
        if [[ "${_containerRunning}" -eq 0 ]] && [[ ! "${_containerImageVersion}" = "${_dockerImageVersion}" ]]; then
          _fsMsgWarning_ 'Image is outdated: '"${_containerImage}"
          _containerRestart=0
        else
          _fsMsg_ 'Image is up-to-date: '"${_containerImage}"
        fi
        
          # start container
        if [[ "${_containerRunning}" -eq 1 ]]; then
          docker start "${_containerName}" > /dev/null
          
          # restart container if necessary
        else
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart container (recommended)?")" -eq 0 ]]; then
                # set strategy update only when container is restarted
              if [[ -n "${_strategyUpdate}" ]]; then
                _containerStrategyUpdate="${_strategyUpdate}"
              fi
              docker restart "${_containerName}" > /dev/null
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
        if [[ "${_containerRunning}" -eq 0 ]]; then
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
        sudo rm -f "${_containerConfPath}"
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
  local _strategyFileNew=''
  local _strategyUpdate=''
  local _strategyFileType=''
  local _strategyFileTypeName='unknown'
  local _strategyTmp="${FS_TMP}/${FS_HASH}_${_strategyName}"
  local _strategyDir="${FS_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
  local _strategyUrls=''
  local _strategyUrlsDeduped=''
  local _strategyUrl=''
  local _strategyPath=''
  local _strategyPathTmp=''
  local _strategyJson=''
  local _setup=0
  local _error=0
  
    # create the only necessary strategy for proxies if file doesnt exist or use strategies file from git or create your own.
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
    mkdir -p "${_strategyDir}"
    
    for _strategyUrl in "${_strategyUrlsDeduped[@]}"; do
      if [[ "$(_fsIsUrl_ "${_strategyUrl}")" -eq 0 ]]; then
        _strategyFile="$(basename "${_strategyUrl}")"
        _strategyFileType="${_strategyFile##*.}"
        _strategyPath="${_strategyDir}/${_strategyFile}"
        _strategyPathTmp="${_strategyTmp}/${_strategyFile}"
        
        if [[ "${_strategyFileType}" = "py" ]]; then
          _strategyFileTypeName="strategy"
        elif [[ "${_strategyFileType}" = "json" ]]; then
          _strategyFileTypeName="config"
        fi
        
        curl --connect-timeout 10 -s -L "${_strategyUrl}" -o "${_strategyPathTmp}"
        
        if [[ "$(_fsFileEmpty_ "${_strategyPathTmp}")" -eq 0 ]]; then
          if [[ "$(_fsFile_ "${_strategyPath}")" -eq 0 ]]; then
              # only update file if it is different
            if ! cmp --silent "${_strategyPathTmp}" "${_strategyPath}"; then
              cp -a "${_strategyPathTmp}" "${_strategyPath}"
              _setup=$((_setup+1))
              _fsFileExit_ "${_strategyPath}"
            fi
          else
            cp -a "${_strategyPathTmp}" "${_strategyPath}"
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
      
      printf '%s\n' "${_strategyJson}" | jq . | tee "${_strategyDir}/${_strategyName}.conf.json" > /dev/null
    else
      _fsMsg_ "Strategy is installed: ${_strategyName}"
    fi
  else
    _fsMsg_ "[WARNING] Strategy is not implemented: ${_strategyName}"
  fi
}

_fsDockerAutoupdate_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _projectFile="${1}"
  local _projectAutoupdate='freqstart -c '"${_projectFile}"' -a -y'
  local _projectAutoupdateMode="${2:-}" # optional: remove
  local _projectAutoupdates=""
  local _cronUpdate="0 */6 * * *" # update every 6 hours
  
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
    sudo rm -f "${FS_AUTOUPDATE}"
  else
    printf '%s\n' "${_projectAutoupdates[@]}" | tee "${FS_AUTOUPDATE}" > /dev/null
    sudo chmod +x "${FS_AUTOUPDATE}"
    _fsCrontab_ "${FS_AUTOUPDATE}" "${_cronUpdate}"
  fi
}

_fsDockerPurge_() {
  if [[ "$(_fsPkgsStatus_ "docker-ce")" -eq 0 ]]; then
    sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
    sudo docker network prune --force
    sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
  fi
}

###
# SETUP

_fsSetup_() {
  local _symlinkSource="${FS_DIR}/${FS_NAME}.sh"
  
  _fsLogo_
  _fsUser_
  _fsSetupPrerequisites_
  _fsSetupConf_
  _fsSetupNtp_
  _fsSetupFreqtrade_
  _fsSetupFrequi_
  _fsSetupBinanceProxy_
  _fsSetupKucoinProxy_
  _fsStats_
  
	if [[ "$(_fsIsSymlink_ "${FS_SYMLINK}")" -eq 1 ]]; then
    sudo rm -f "${FS_SYMLINK}"
		sudo ln -sfn "${_symlinkSource}" "${FS_SYMLINK}"
	fi
	
	if [[ "$(_fsIsSymlink_ "${FS_SYMLINK}")" -eq 1 ]]; then
		_fsMsgError_ "Cannot create symlink: ${FS_SYMLINK}"
	fi
}

# CONF

_fsSetupConf_() {
	local _domain=''
	local _url=''
	local _ipPublic=''
	local _ipPublicTemp=''
	local _ipLocal=''
  
	if [[ "$(_fsFile_ "${FS_CONFIG}")" -eq 0 ]]; then
    _domain="$(_fsValueGet_ "${FS_CONFIG}" '.domain' 2> /dev/null || true)"
    _url="$(_fsValueGet_ "${FS_CONFIG}" '.url' 2> /dev/null || true)"
    _ipPublic="$(_fsValueGet_ "${FS_CONFIG}" '.ip_public' 2> /dev/null || true)"
    _ipLocal="$(_fsValueGet_ "${FS_CONFIG}" '.ip_local' 2> /dev/null || true)"
    
      # validate public ip if set
    if [[ -n "${_ipPublic}" ]]; then
      _ipPublicTemp="$(dig +short myip.opendns.com @resolver1.opendns.com)"
      if [[ -n "${_ipPublicTemp}" ]]; then
        if [[ ! "${_ipPublic}" = "${_ipPublicTemp}" ]]; then
          _fsMsgWarning_ 'Public IP has been changed. Run FreqUI setup again!'
        fi
      else
        _fsMsgWarning_ 'Cannot retrieve public IP. Run FreqUI setup again!'
      fi
    fi    
  fi
  
  _fsFileCreate_ "${FS_CONFIG}" \
  '{' \
  '    "version": "'"${FS_VERSION}"'",' \
  '    "domain": "'"${_domain}"'",' \
  '    "url": "'"${_url}"'",' \
  '    "ip_public": "'"${_ipPublic}"'",' \
  '    "ip_local": "'"${_ipLocal}"'"' \
  '}'
}

# USER

_fsUser_() {
  local	_currentUser=''
  local	_currentUserId=''
  local _dir="${FS_DIR}"
  local _symlink="${FS_SYMLINK}"
  local _newUser=''
  local _newPath=''
  local _logout=1
  
  _currentUser="$(id -u -n)"
  _currentUserId="$(id -u)"
  
  if [[ "${_currentUserId}" -eq 0 ]]; then

    _fsMsg_ "[WARNING] Your are logged in as root."
    
      # confirmation has to be no because of non-interactive mode
    if [[ "$(_fsCaseConfirmation_ 'Skip creating a new user (not recommended)?')" -eq 1 ]]; then
      while true; do
        read -rp 'Enter your new username: ' _newUser
        
        if [[ "${_newUser}" = "" ]]; then
          _fsCaseEmpty_
        elif [[ "$(_fsIsAlphaDash_ "${_newUser}")" -eq 1 ]]; then
          _fsMsg_ "Only alpha-numeric, dash and underscore characters are allowed!"
          _newUser=''
        else
          if [[ "$(_fsCaseConfirmation_ "Is the username \"${_newUser}\" correct?")" -eq 0 ]]; then
            break
          fi
          _newUser=''
        fi
      done
      
      if [[ -n "${_newUser}" ]]; then
          # stop everything on current user; credit: https://superuser.com/a/1613980
        _fsDockerPurge_
        
        sudo adduser --gecos "" "${_newUser}" || sudo passwd "${_newUser}"
        sudo usermod -aG sudo "${_newUser}" || true
        sudo usermod -aG docker "${_newUser}" || true
        
          # no password for sudo
        echo "${_newUser} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null
        
        _newPath="$(bash -c "cd ~$(printf %q "${_newUser}") && pwd")"'/'"${FS_NAME}"
        
        if [[ ! -d "${_newPath}" ]]; then
          mkdir -p "${_newPath}"
        fi
          # copy script and content to new user and set permissions
				cp -R "${_dir}"/* "${_newPath}"
				sudo chown -R "${_newUser}":"${_newUser}" "${_newPath}"
        
          # remove symlink and current script and content
        rm -f "${_symlink}"
        rm -rf "${_dir}"
        
        if [[ "$(_fsCaseConfirmation_ "Disable \"${_currentUser}\" user (recommended)?")" -eq 0 ]]; then
          sudo usermod -L "${_currentUser}"
        fi
        
        _fsMsgTitle_ 'Files can be found in new path: '"${_newPath}"
        
        _fsCdown_ 10 'to log into your new user...'
          
          # remove temporary folder incl. scriptlock 
        sudo rm -rf "${FS_TMP}"
        
          # switch to new user
        sudo su -l "${_newUser}"
      fi
    fi
  fi

  if [[ "${_currentUserId}" -ne 0 ]]; then
      # add current user to sudo group
    if ! id -nGz "${_currentUser}" | grep -qzxF "sudo"; then
      sudo usermod -aG sudo "${_currentUser}" && sudo newgrp sudo || true
    fi
    
    if [[ -z "$(sudo -l | grep -o '(ALL : ALL) NOPASSWD: ALL')" ]]; then
      if [[ "$(_fsCaseConfirmation_ "Give permissions without entering password everytime (recommended)?")" -eq 0 ]]; then
        echo "${_currentUser} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null
      fi
    fi
  fi
}

# PREREQUISITES

_fsSetupPrerequisites_() {
  local _currentUser=''
  
  _fsMsgTitle_ "PREREQUISITES"
  
  sudo apt-get update || true # workaround if you have manually installed packages that are causing errors
  
  _fsPkgs_ "curl" "jq" "docker-ce"
  
    # add current user to docker group
  _currentUser="$(id -u -n)"
  if ! id -nGz "${_currentUser}" | grep -qzxF "docker"; then
    sudo usermod -aG docker "${_currentUser}" && sudo newgrp docker || true
  fi
  
  _fsMsg_ "Update server and install unattended-upgrades? Reboot may be required!"
  
  if [[ "$(_fsCaseConfirmation_ "Skip server update?")" -eq 0 ]]; then
    _fsMsg_ "Skipping..."
  else
    sudo apt -o Dpkg::Options::="--force-confdef" dist-upgrade -y && \
    sudo apt install -y unattended-upgrades && \
    sudo apt autoremove -y
    
    if sudo test -f /var/run/reboot-required; then
      _fsMsg_ 'A reboot is required to finish installing updates.'
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

# FIREWALL

_fsSetupFirewall_() {
  local _status=''
  local _portSSH=22
  
  _fsPkgs_ "ufw"
  
  _status="$(sudo ufw status | grep -o 'active' || true)"
  
  while true; do
    if [[ -n "${_status}" ]]; then
        # check if ufw rule for 9999 exists
      _status="$(sudo ufw status | grep -o '9999' || true)"
      
      if [[ -n "${_status}" ]]; then
        if [[ "$(_fsCaseConfirmation_ 'Skip reconfiguration of firewall?')" -eq 0 ]]; then
          _fsMsg_ 'Skipping...'
          break
        fi
      fi
    else
      if [[ "$(_fsCaseConfirmation_ 'Install firewall for Nginx proxy (recommended)?')" -eq 1 ]]; then
        break
      fi
    fi
    
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
    sudo ufw allow 9999/tcp
    sudo ufw allow 9000:9100/tcp
    yes $'y' | sudo ufw enable || true
    
    break
  done
}

# NTP

_fsSetupNtp_() {
  _fsMsgTitle_ "NTP (Timezone: UTC)"
  
  if [[ "$(_fsSetupNtpCheck_)" -eq 1 ]]; then
    _fsPkgs_ "chrony"

    if [[ "$(_fsSetupNtpCheck_)" -eq 1 ]]; then
      _fsMsgError_ "Cannot activate or synchronize NTP."
    else
      _fsMsg_ "NTP is activated and synchronized."
    fi
  else
    _fsMsg_ "NTP is active and synchronized."
  fi
}

_fsSetupNtpCheck_() {
  local timentp=''
  local timeutc=''
  local timesyn=''
  
  timentp="$(sudo timedatectl | grep -o 'NTP service: active' || true)"
  timeutc="$(sudo timedatectl | grep -o '(UTC, +0000)' || true)"
  timesyn="$(sudo timedatectl | grep -o 'System clock synchronized: yes' || true)"
  
  if [[ -z "${timentp}" ]] || [[ -z  "${timeutc}" ]] || [[ -z  "${timesyn}" ]]; then
    echo 1
  else
    echo 0
  fi
}

# FREQTRADE

_fsSetupFreqtrade_() {
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerYml="${FS_DIR}/${FS_NAME}_setup.yml"
  local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"
  local _configKey=''
  local _configSecret=''
  local _configName=''
  local _configFile=''
  local _configFileTmp=''
  
  _fsMsgTitle_ "FREQTRADE"
  
    # download original freqtrade docker project file from git repo
  if [[ ! -f "${_dockerYml}" ]]; then
    curl --connect-timeout 10 -s -L "${_dockerGit}" -o "${_dockerYml}"
    _fsFileExit_ "${_dockerYml}"
  fi
  
  if [[ ! -d "${FS_DIR_USER_DATA}" ]]; then
    mkdir -p "${FS_DIR_USER_DATA}"
    
  	if [[ ! "$(ls -A "${FS_DIR_USER_DATA}")" ]]; then
      
        # create user_data folder
      _fsDockerProject_ "${_dockerYml}" 'run-force' 'freqtrade' \
      "create-userdir --userdir /freqtrade/${FS_DIR_USER_DATA##*/}"
      
        # validate if directory exists and is not empty
      if [[ ! "$(ls -A "${FS_DIR_USER_DATA}")" ]]; then
        sudo rm -rf "${FS_DIR_USER_DATA}"
        _fsMsgError_ "Cannot create directory: ${FS_DIR_USER_DATA}"
      else
        _fsMsg_ "Directory created: ${FS_DIR_USER_DATA}"
      fi
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
          
          if [[ "$(_fsIsAlphaDash_ "${_configName}")" -eq 1 ]]; then
            _fsMsg_ "Only alpha-numeric, dash and underscore characters are allowed!"
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
      
      cp -a "${_configFileTmp}" "${_configFile}"
      rm -f "${_configFileTmp}"
      
      _fsMsg_ "Enter your exchange api KEY and SECRET to: ${_configFile}"
    fi
  fi
}

# BINANCE-PROXY
# credit: https://github.com/nightshift2k/binance-proxy

_fsSetupBinanceProxy_() {
  local _docker="nightshift2k/binance-proxy:latest"
  
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
    
      # binance proxy json file
    _fsFileCreate_ "${FS_PROXY_BINANCE_JSON}" \
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
    
      # binance proxy futures json file
    _fsFileCreate_ "${FS_PROXY_BINANCE_FUTURES_JSON}" \
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
    _fsFileCreate_ "${FS_PROXY_BINANCE_YML}" \
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
    
    _fsDockerProject_ "$(basename "${FS_PROXY_BINANCE_YML}")" 'compose-force'
    
    break
  done
}

# KUCOIN-PROXY
# credit: https://github.com/mikekonan/exchange-proxy

_fsSetupKucoinProxy_() {
  local _docker="mikekonan/exchange-proxy:latest-amd64"
  
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
    
      # kucoin proxy json file
    _fsFileCreate_ "${FS_PROXY_KUCOIN_JSON}" \
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
    _fsFileCreate_ "${FS_PROXY_KUCOIN_YML}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${FS_PROXY_KUCOIN}:" \
    "    image: ${_docker}" \
    "    container_name: ${FS_PROXY_KUCOIN}" \
    "    command: >" \
    "      -port 8980" \
    "      -verbose 1"
    
    _fsDockerProject_ "$(basename "${FS_PROXY_KUCOIN_YML}")" 'compose-force'
    
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
    
    while true; do
      if [[ "$(_fsFile_ "${_htpasswd}")" -eq 0 ]]; then
        _fsMsg_ "FreqUI login data already found."
        
        if [[ "$(_fsCaseConfirmation_ "Skip generating new FreqUI login data?")" -eq 0 ]]; then
          _fsMsg_ "Skipping..."
          break
        fi
      fi        
      
      _fsMsg_ "Create FreqUI login data now!"
      
      if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
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
        _fsCdown_ 15 'to memorize login data... Restart setup to change!'
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

_fsSetupNginxWebservice_() {
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
    if systemctl status "${_webservice}" 2> /dev/null | grep -Fq "Active: active"; then
      _fsMsgWarning_ 'Stopping webservice to avoid ip/port collisions: '"${_webservice}"

      sudo systemctl stop "${_webservice}" > /dev/null 2> /dev/null || true
      sudo systemctl disable "${_webservice}" > /dev/null 2> /dev/null || true
    fi
  done
  
  for _port in "${ports[@]}"; do 
    if [[ -n "$(sudo lsof -n -sTCP:LISTEN -i:${_port})" ]]; then
      _fsMsgWarning_ 'Stopping webservice blocking port: '"${_port}"

      sudo fuser -k "${_port}/tcp" > /dev/null 2> /dev/null
    fi
  done
}

_fsSetupNginxOpenssl_() {
  local _url=''
  local _nr=''
  local _mode=''
  local _ipConf=''
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
  
  _ipPublic="$(dig +short myip.opendns.com @resolver1.opendns.com)"
  
  while true; do
    printf -- '%s\n' \
    "? Which IP to access FreqUI:" \
    "  1) Public IP" \
    "  2) Local IP" >&2
    
    if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
      read -rp "  Choose number (default: 1): " _nr
    elif  [[ -z "${_ipPublic}" ]]; then
      _fsMsgWarning_ 'Cannot access public IP!'
      local _nr="2"
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
  _fsCrontabRemove_ "freqstart --cert -y" 
    # stop nginx domain container
  _fsDockerRemove_ "${FS_NGINX}_domain"
    # stop/disable native webservices and free blocked ports
  _fsSetupNginxWebservice_

  _fsValueUpdate_ "${FS_CONFIG}" '.domain' ''
  
    # public ip routine
  if [[ "${_mode}" = 'public' ]]; then
    _url="https://${_ipPublic}"
    _ipConf="${_ipPublic}"
    
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
    
    _ipConf="${_ipLocal}"
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
  "    hostname: ${FS_NGINX}_ip" \
  '    image: amd64/nginx:stable' \
  '    network_mode: host' \
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
  "    listen ${_ipConf}:80;" \
  "    location / {" \
  "        return 301 https://\$host\$request_uri;" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${_ipConf}:443 ssl;" \
  "    include ${_sslConf};" \
  "    include ${_sslConfParam};" \
  "    location / {" \
  "        auth_basic \"Restricted\";" \
  "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
  "        limit_req zone=auth burst=20 nodelay;" \
  '        add_header Set-Cookie "__Secure-rl-bypass='"${_bypass}"';Max-Age=31536000;Domain=$host;Path=/;Secure;HttpOnly";' \
  "        proxy_pass http://127.0.0.1:9999;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "    }" \
  "    location /api {" \
  "        return 400;" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${_ipConf}:9000-9100 ssl;" \
  "    include ${_sslConf};" \
  "    include ${_sslConfParam};" \
  "    location / {" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "    }" \
  "    location = / {" \
  "        return 400;" \
  "    }" \
  "}"
  
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
  local _cronCmd="freqstart --cert -y"
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
    _fsSetupNginxWebservice_
    
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
    "    hostname: ${FS_NGINX}_domain" \
    '    network_mode: host' \
    '    volumes:' \
    "      - ${FS_DIR_PROXY}${FS_NGINX_CONFD}:${FS_NGINX_CONFD}" \
    "      - ${FS_DIR_PROXY}/certbot/conf:/etc/letsencrypt" \
    "      - ${FS_DIR_PROXY}/certbot/www:/var/www/certbot" \
    "  ${FS_CERTBOT}:" \
    '    image: certbot/certbot:latest' \
    "    container_name: ${FS_CERTBOT}" \
    "    hostname: ${FS_CERTBOT}" \
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
      "    listen ${_domain}:80;" \
      "    server_name ${_domain};" \
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
    "    listen ${_domain}:80;" \
    "    server_name ${_domain};" \
    "    location / {" \
    "        return 301 https://\$host\$request_uri;" \
    "    }" \
    "    location /.well-known/acme-challenge {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/certbot;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_domain}:443 ssl http2;" \
    "    server_name ${_domain};" \
    "    ssl_certificate ${_sslCert};" \
    "    ssl_certificate_key ${_sslKey};" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    location /.well-known/acme-challenge {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/certbot;" \
    "    }" \
    "    location / {" \
    "        auth_basic \"Restricted\";" \
    "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
    "        limit_req zone=auth burst=20 nodelay;" \
    '        add_header Set-Cookie "__Secure-rl-bypass='"${_bypass}"';Max-Age=31536000;Domain=$host;Path=/;Secure;HttpOnly";' \
    "        proxy_pass http://127.0.0.1:9999;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "    }" \
    "    location /api {" \
    "        return 400;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_domain}:9000-9100 ssl http2;" \
    "    server_name ${_domain};" \
    "    ssl_certificate ${_sslCert};" \
    "    ssl_certificate_key ${_sslKey};" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    location / {" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "    }" \
    "    location = / {" \
    "        return 400;" \
    "    }" \
    "}"
    
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
  
  _jwt="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.jwt_secret_key")"
  _username="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.username")"
  _password="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.password")"
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
    
    if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
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
      _fsCdown_ 15 'to memorize login data... Restart setup to change!'
    fi
    
    break
  done
  
  if [[ -n "${_username}" ]] && [[ -n "${_password}" ]]; then
      # create frequi json for bots
    _fsFileCreate_ "${FS_FREQUI_JSON}" \
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
  local _frequiServerLog="${FS_DIR_USER_DATA}"'/logs/'"${FS_FREQUI}"'.log'
  local _docker="freqtradeorg/freqtrade:stable"
  
  _fsFileCreate_ "${FS_FREQUI_SERVER_JSON}" \
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
  "    \"bot_name\": \"frequi_server\"," \
  "    \"initial_state\": \"running\"" \
  "}"
  
  _fsFileCreate_ "${FS_FREQUI_YML}" \
  "---" \
  "version: '3'" \
  "services:" \
  "  ${FS_FREQUI}:" \
  "    image: ${_docker}" \
  "    container_name: ${FS_FREQUI}" \
  "    volumes:" \
  '      - "'"${FS_DIR_USER_DATA}"':/freqtrade/user_data"' \
  "    ports:" \
  '      - "127.0.0.1:9999:9999"' \
  "    tty: true" \
  "    command: >" \
  "      trade" \
  "      --logfile /freqtrade/user_data/logs/$(basename "${_frequiServerLog}")" \
  "      --strategy ${_frequiStrategy}" \
  "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_SERVER_JSON}")" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_JSON}")"
  
  _fsDockerProject_ "${FS_FREQUI_YML}" 'compose-force'
}

###
# START

_fsStart_() {
	local _yml="${1:-}"
  local _symlink="${FS_SYMLINK}"
  
  _fsLogo_
  
    # check if symlink from setup routine exist
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
		_fsMsgError_ "Start setup first!"
  fi
  
  if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
    _fsMsgError_ "Option -a or --auto cannot be used with -q or --quit."
  elif [[ "${FS_OPTS_QUIT}" -eq 0 ]] && [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
    _fsMsgError_ "Option -c or --compose cannot be used with -q or --quit."
  elif [[ -z "${_yml}" ]]; then
    _fsMsgError_ "Setting an \"example.yml\" file with -c or --compose is required."
  else
    if [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
      _fsDockerProject_ "${_yml}" "quit"
    elif [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
      _fsDockerProject_ "${_yml}" "compose"
    fi
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
  "                 |_|               ${FS_VERSION}" >&2
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
  | sed "s#real$(echo '\t')##" )"
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
  local _msg="${1:-}"
  
  _fsLogo_
  
  if [[ -n "${_msg}" ]]; then
    _fsMsgTitle_ "${_msg}"
  fi
  
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
  
  _fsStats_
  exit 0
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
  
  local _filePath="${1}"; shift
  local _input=("${@}")
  local _output=''
  local _fileTmp=''
  local _file="${_filePath##*/}"
  local _fileDir="${_filePath%/*}"
  local _fileHash=''
  
  _fileHash="$(_fsRandomHex_ 8)"
  _fileTmp="${FS_TMP}"'/'"${_fileHash}"'_'"${_file}"
  
  _output="$(printf -- '%s\n' "${_input[@]}")"
  echo "${_output}" | tee "${_fileTmp}" > /dev/null
  
  if [[ ! -d "${_fileDir}" ]]; then
    mkdir -p "${_fileDir}"
  fi
  
  if [[ "$(_fsFileEmpty_ "${_fileTmp}")" -eq 0 ]]; then
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
  _fileTmp="${FS_TMP}"'/'"${_fileHash}"'_'"${_file}"
  
  if [[ "${_fileType}" = 'json' ]]; then
      # update value for json
    _json="$(_fsValueGet_ "${_filePath}" '.')"
      # credit: https://stackoverflow.com/a/24943373
    _jsonUpdate="$(jq "${_key}"' = $newVal' --arg newVal "${_value}" <<< "${_json}")"
    
    printf '%s\n' "${_jsonUpdate}" | jq . | tee "${_fileTmp}" > /dev/null
  else
      # update value for other filetypes
    sudo cp "${_filePath}" "${_fileTmp}"
    
    if grep -qow "\"${_key}\": \".*\"" "${_fileTmp}"; then
        # "key": "value"
      sudo sed -i "s,\"${_key}\": \".*\",\"${_key}\": \"${_value}\"," "${_fileTmp}"
    elif grep -qow "\"${_key}\": \".*\"" "${_fileTmp}"; then
        # "key": value
      sudo sed -i "s,\"${_key}\": .*,\"${_key}\": ${_value}," "${_fileTmp}"
    elif grep -qow "${_key}: \".*\"" "${_fileTmp}"; then
        # key: "value"
      sudo sed -i "s,${_key}: \".*\",${_key}: \"${_value}\"," "${_fileTmp}"
    elif grep -qow "${_key}: \".*\"" "${_fileTmp}"; then
        # key: value
      sudo sed -i "s,${_key}: .*,${_key}: ${_value}," "${_fileTmp}"
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

_fsIsAlphaDash_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _string="${1}"
  local _regex='^[[:alnum:]_-]+$'
  
  if [[ $_string =~ $_regex ]]; then
    echo 0
  else
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
  _fsLogo_
  
  _fsMsgTitle_ '[WARNING] Stopp and remove all containers, networks and images!'
  
  if [[ "$(_fsCaseConfirmation_ "Are you sure you want to continue?")" -eq 0 ]]; then
      # disable and remove autoupdate
    _fsCrontabRemove_ "${FS_AUTOUPDATE}"
    sudo rm -f "${FS_AUTOUPDATE}"
      # stop and remove docker images, container and networks but keeps all files
    _fsDockerPurge_
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
          # docker setup
        mkdir -p "${FS_DIR_DOCKER}"
        curl --connect-timeout 10 -fsSL "https://get.docker.com" -o "${_getDocker}"
        _fsFileExit_ "${_getDocker}"
        sudo chmod +x "${_getDocker}"
        _fsMsg_ 'Installing docker can take some time, please be patient!'
        sudo sh "${_getDocker}"
        sudo rm -f "${_getDocker}"
        sudo apt install -y -q docker-compose
      elif [[ "${_pkg}" = 'ufw' ]]; then
          # firewall setup
        sudo apt-get install -y -q ufw
        sudo ufw logging medium > /dev/null
      elif [[ "${_pkg}" = 'chrony' ]]; then
          # ntp setup
        sudo apt install -y -q chrony
        sudo timedatectl set-timezone 'UTC'
        sudo timedatectl set-ntp true
      else
        sudo apt-get install -y -q "${_pkg}"
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

_fsIsSymlink_() {
  [[ $# -lt 1 ]] && _fsMsgError_ "Missing required argument to ${FUNCNAME[0]}"
  
	local _symlink="${1}"
    # credit: https://stackoverflow.com/a/36180056
  if [ -L "${_symlink}" ] ; then
    if [ -e "${_symlink}" ] ; then
			echo 0
    else
			sudo rm -f "${_symlink}"
      echo 1
    fi
  elif [ -e "${_symlink}" ] ; then
			sudo rm -f "${_symlink}"
      echo 1
  else
    sudo rm -f "${_symlink}"
    echo 1
  fi
}

_fsScriptLock_() {
  local _lockDir="${FS_TMP}/${FS_NAME}.lock"
  
  if [[ -n "${FS_TMP}" ]]; then
    if [[ -d "${_lockDir}" ]]; then
        # error 99 to not remove temp dir
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
        readonly c_arg="${2}"
        shift
        shift
        ;;
      --setup|-s)
        FS_OPTS_SETUP=0
        shift
        ;;
      --quit|-q)
        FS_OPTS_QUIT=0
        readonly q_arg="${2}"
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