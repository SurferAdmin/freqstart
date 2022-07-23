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
readonly FS_VERSION='v0.1.9'
FS_DIR="$(dirname "$(readlink --canonicalize-existing "${0}" 2> /dev/null)")"
readonly FS_DIR
readonly FS_FILE="${0##*/}"
readonly FS_SYMLINK="/usr/local/bin/${FS_NAME}"
readonly FS_DIR_TMP="/tmp/${FS_NAME}"
readonly FS_DIR_DOCKER="${FS_DIR}/docker"
readonly FS_DIR_USER_DATA="${FS_DIR}/user_data"
readonly FS_DIR_USER_DATA_STRATEGIES="${FS_DIR_USER_DATA}/strategies"
readonly FS_DIR_USER_DATA_LOGS="${FS_DIR_USER_DATA}/logs"
readonly FS_CONFIG="${FS_DIR}/${FS_NAME}.conf.json"
readonly FS_STRATEGIES="${FS_DIR}/${FS_NAME}.strategies.json"

readonly FS_PROXY='freqstart_proxy'
readonly FS_PROXY_SUBNET='172.99.0.0/16'
readonly FS_PROXY_BINANCE='binance_proxy'
readonly FS_PROXY_BINANCE_IP='172.99.0.200'
readonly FS_PROXY_BINANCE_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}.json"
readonly FS_PROXY_BINANCE_FUTURES_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_BINANCE}_futures.json"
readonly FS_PROXY_BINANCE_YML="${FS_DIR}/${FS_PROXY_BINANCE}.yml"
readonly FS_PROXY_KUCOIN='kucoin_proxy'
readonly FS_PROXY_KUCOIN_IP='172.99.0.201'
readonly FS_PROXY_KUCOIN_JSON="${FS_DIR_USER_DATA}/${FS_PROXY_KUCOIN}.json"
readonly FS_PROXY_KUCOIN_YML="${FS_DIR}/${FS_PROXY_KUCOIN}.yml"

readonly FS_NGINX_CONFD="/etc/nginx/conf.d"
readonly FS_NGINX_CONFD_FREQUI="${FS_NGINX_CONFD}"'/frequi.conf'
readonly FS_NGINX_CONFD_DEFAULT="${FS_NGINX_CONFD}"'/default.conf'
readonly FS_NGINX_CONFD_HTPASSWD="${FS_NGINX_CONFD}"'/.htpasswd'

readonly FS_FREQUI_JSON="${FS_DIR_USER_DATA}/frequi.json"
readonly FS_FREQUI_SERVER_JSON="${FS_DIR_USER_DATA}/frequi_server.json"
readonly FS_FREQUI_YML="${FS_DIR}/${FS_NAME}_frequi.yml"
FS_SERVER_WAN="$(hostname -I | awk '{ print $1 }')"
readonly FS_SERVER_WAN
FS_HASH="$(xxd -l 8 -ps /dev/urandom)"
readonly FS_HASH

FS_OPTS_COMPOSE=1
FS_OPTS_SETUP=1
FS_OPTS_AUTO=1
FS_OPTS_QUIT=1
FS_OPTS_YES=1
FS_OPTS_RESET=1

trap _fsCleanup_ EXIT
trap '_fsErr_ "${FUNCNAME:-.}" ${LINENO}' ERR

###
# DOCKER

_fsDockerVarsPath_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _docker="${1}"
  local _dockerRepo="${_docker%:*}"
	
	echo "${_dockerRepo}"
}

_fsDockerVarsCompare_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerRepo=''
	local _dockerName=''

	_dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	_dockerName="${FS_NAME}"'_'"$(echo "${_dockerRepo}" | sed "s,\/,_,g" | sed "s,\-,_,g")"

	echo "${_dockerName}"
}

_fsDockerVarsTag_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerTag="${_docker##*:}"

	if [[ "${_dockerTag}" = "${_docker}" ]]; then
		_dockerTag="latest"
	fi

	echo "${_dockerTag}"
}

_fsDockerVersionLocal_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _dockerRepo="${1}"
  local _dockerTag="${2}"
  local _dockerName=''
  local _dockerManifest=''
  local _acceptM=''
  local _acceptML=''
  local _token=''
  local _status=''
  local _dockerVersionHub=''

	_dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
	_dockerManifest="${FS_DIR_TMP}"'/'"${FS_HASH}"'_'"${_dockerName}"'_'"${_dockerTag}"'.md'

    # credit: https://stackoverflow.com/a/64309017
  _acceptM="application/vnd.docker.distribution.manifest.v2+json"
  _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
  _token="$(curl --connect-timeout 10 -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${_dockerRepo}:pull" | jq -r '.token' || true)"

  if [[ -n "${_token}" ]]; then
    sudo curl --connect-timeout 10 -H "Accept: ${_acceptM}" -H "Accept: ${_acceptML}" -H "Authorization: Bearer ${_token}" -o "${_dockerManifest}" \
    -I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}" || true
  fi

  if [[ "$(_fsFile_ "${_dockerManifest}")" -eq 0 ]]; then
    _status="$(grep -o "200 OK" "${_dockerManifest}")"

    if [[ -n "${_status}" ]]; then
      _dockerVersionHub="$(_fsValueGet_ "${_dockerManifest}" 'etag')"
      
      if [[ -n "${_dockerVersionHub}" ]]; then
        echo "${_dockerVersionHub}"
      fi
    fi
  else
    _fsMsg_ '[WARNING] Cannot connect to docker hub.'
  fi
}

_fsDockerImage_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
      sudo mkdir -p "${FS_DIR_DOCKER}"
    fi

    sudo rm -f "${_dockerPath}"
    docker save -o "${_dockerPath}" "${_dockerRepo}"':'"${_dockerTag}"
    [[ "$(_fsFile_ "${_dockerPath}")" -eq 1 ]] && _fsMsg_ "[WARNING] Cannot create backup for: ${_dockerRepo}:${_dockerTag}"
    
    echo "${_dockerVersionLocal}"
  else
      # if image could not be installed
    _fsMsgExit_ "[FATAL] Image not found: ${_dockerRepo}:${_dockerTag}"
  fi
}

_fsDockerImageInstalled_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
  local _dockerImages=''
  
  _dockerImages="$(docker images -q "${_dockerRepo}:${_dockerTag}" 2> /dev/null)"

	if [[ -n "${_dockerImages}" ]]; then
		echo 0
	else
		echo 1
	fi
}

_fsDockerPsName_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
		echo 0
	else
		echo 1
	fi
}

_fsDockerId2Name_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerId="${1}"
	local _dockerName=''

	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
	if [[ -n "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

_fsDockerStop_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerName="${1}"

  sudo docker update --restart=no "${_dockerName}" > /dev/null
  sudo docker stop "${_dockerName}" > /dev/null
  sudo docker rm -f "${_dockerName}" > /dev/null
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}" "all")" -eq 0 ]]; then
    _fsMsgExit_ "[FATAL] Cannot remove container: ${_dockerName}"
  fi
}

_fsDockerProjectImages_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _path="${1}"
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
  done < <(grep "image:" "${_path}" \
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

_fsDockerProjectPorts_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
  done < <(grep 'ports:' "${_ymlPath}" -A 1 \
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
    done < <(sudo docker ps -a -f name="${_ymlName}" | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")

    _dockerPortsAll=()
    while read -r; do
      _dockerPortsAll+=("$REPLY")
    done < <(sudo docker ps -a | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")

    _dockerPortsBlocked=("$(printf '%s\n' "${_dockerPortsAll[@]}" "${_dockerPortsProject[@]}" | sort | uniq -u)")
    _dockerPortsCompare=("$(echo "${_dockerPortsYml[@]}" "${_dockerPortsBlocked[@]}" | tr ' ' '\n' | sort | uniq -D | uniq)")

    if (( ${#_dockerPortsCompare[@]} )); then
      for _dockerPortCompare in "${_dockerPortsCompare[@]}"; do
        if [[ "${_dockerPortCompare}" =~ ^[0-9]+$ ]]; then
          _error=$((_error+1))
          _fsMsg_ "Port is already allocated: ${_dockerPortCompare}"
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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
  
    # download or update implemented strategies in project file
  _strategies=()
  while read -r; do
    _strategies+=( "$REPLY" )
  done < <(grep "strategy" "${_ymlPath}" \
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
    done < <(grep "strategy-path" "${_ymlPath}" \
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
        _fsMsg_ '[ERROR] Strategy file not found: '"${_strategyFile}"
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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _ymlPath="${1}"
  local _configs=''
  local _configsDeduped=''
  local _config=''
  local _configNew=''
  local _error=0
  
  _configs=()
  while read -r; do
    _configs+=( "$REPLY" )
  done < <(grep -e "\-\-config" -e "\-c" "${_ymlPath}" \
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
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _projectPath="${FS_DIR}/${1##*/}"
  local _projectMode="${2}" # compose, validate, quit
  local _projectForce="${3:-}" # optional: force
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
  local _containerCmd=''
  local _containerRunning=''
  local _containerRestart=1
  local _containerRestartPolicy=''
  local _containerName=''
  local _containerConfigs=''
  local _containerStrategy=''
  local _containerStrategyUpdate=''
  local _containerJson=''
  local _containerJsonInner=''
  local _containerConfPath=''
  local _containerLogfile=''
  local _containerLogfileTmp=''
  local _containerCount=0
  local _containerAutoupdate='false'
  local _containerUpdateCount=0
  local _strategyUpdate=''
  local _strategyDir=''
  local _strategyPath=''
  local _error=0
  
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
    _fsMsgExit_ "[ERROR] File type is missing: ${_projectFile}"
  else
    if [[ "${_projectFileType}" = 'yml' ]]; then
      if [[ "$(_fsFile_ "${_projectPath}")" -eq 1 ]]; then
        _fsMsgExit_ "[ERROR] File not found: ${_projectFile}"
      fi
    else
      _fsMsgExit_ "[ERROR] File type is not correct: ${_projectFile}"
    fi
  fi
  
  if [[ "${_projectMode}" = "compose" ]]; then
    _fsMsgTitle_ "Compose project: ${_projectFile}"

    _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
    _projectStrategies="$(_fsDockerProjectStrategies_ "${_projectPath}")"
    _projectConfigs="$(_fsDockerProjectConfigs_ "${_projectPath}")"
    
    if [[ "${_projectForce}" = "force" ]]; then
      _projectPorts=0
    else
      _projectPorts="$(_fsDockerProjectPorts_ "${_projectPath}")"
    fi

    [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectPorts}" -eq 1 ]] && _error=$((_error+1))
    [[ "${_projectStrategies}" -eq 1 ]] && _error=$((_error+1))

    if [[ "${_error}" -eq 0 ]]; then
      if [[ "${_projectForce}" = "force" ]]; then
        cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --force-recreate --remove-orphans
      else
        cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --no-recreate --remove-orphans
      fi
    fi
  elif [[ "${_projectMode}" = "validate" ]]; then
    _fsMsgTitle_ "Validate project: ${_projectFile}"
    _fsCdown_ 30 "for any errors..."
  elif [[ "${_projectMode}" = "quit" ]]; then
    _fsMsgTitle_ "Quit project: ${_projectFile}"
  fi

  if [[ "${_error}" -eq 0 ]]; then
    while read -r; do
      _projectContainers+=( "$REPLY" )
    done < <(cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" ps -q)

    for _projectContainer in "${_projectContainers[@]}"; do

      _containerName="$(_fsDockerId2Name_ "${_projectContainer}")"
      _containerRunning="$(_fsDockerPsName_ "${_containerName}")"

      if [[ "${_projectMode}" = "compose" ]]; then
        _containerJsonInner=''
        _strategyUpdate=''
        _containerStrategyUpdate=''
        _containerAutoupdate="$(_fsValueGet_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate')"

        _fsMsgTitle_ 'Container: '"${_containerName}"

          # connect container to proxy network
        docker network create --subnet="${FS_PROXY_SUBNET}" "${FS_PROXY}" > /dev/null 2> /dev/null || true
        if [[ "${_containerName}" = "${FS_PROXY_BINANCE}" ]]; then
          docker network connect --ip "${FS_PROXY_BINANCE_IP}" "${FS_PROXY}" "${_containerName}" > /dev/null 2> /dev/null || true
        elif [[ "${_containerName}" = "${FS_PROXY_KUCOIN}" ]]; then
          docker network connect --ip "${FS_PROXY_KUCOIN_IP}" "${FS_PROXY}" "${_containerName}" > /dev/null 2> /dev/null || true
        else
          docker network connect "${FS_PROXY}" "${_containerName}" > /dev/null 2> /dev/null || true
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
        
          # remove logfile
        _containerLogfile="$(echo "${_containerCmd}" | { grep -Eos "\--logfile [-A-Za-z0-9_/]+.log " || true; } \
        | sed "s,\--logfile,," \
        | sed "s, ,,g")"
        _containerLogfile="${FS_DIR_USER_DATA_LOGS}"'/'"${_containerLogfile##*/}"
        
        if [[ "$(_fsFile_ "${_containerLogfile}")" -eq 0 ]]; then
            # workaround to preserve owner of file
          _containerLogfileTmp="${FS_DIR_TMP}"'/'"${_containerLogfile##*/}"'.tmp'
          sudo touch "${_containerLogfileTmp}"
          sudo cp --no-preserve=all "${_containerLogfileTmp}" "${_containerLogfile}"
        fi
        
          # validate strategy
        _containerStrategy="$(echo "${_containerCmd}" | { grep -Eos "(\-s|\--strategy) [-A-Za-z0-9_]+ " || true; } \
        | sed "s,\--strategy,," \
        | sed "s, ,,g")"
        
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

        if [[ -n "${_strategyUpdate}" ]]; then
          if [[ -n "${_containerStrategyUpdate}" ]]; then
            if [[ "${_containerRunning}" -eq 0 ]] && [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
              _fsMsg_ "Strategy is outdated: ${_containerStrategy}"
              _containerRestart=0
            fi
          else
            _containerStrategyUpdate="${_strategyUpdate}"
          fi
        fi
        
          # compare latest docker image with container image
        _containerImage="$(sudo docker inspect --format="{{.Config.Image}}" "${_projectContainer}")"
        _containerImageVersion="$(sudo docker inspect --format="{{.Image}}" "${_projectContainer}")"
        _dockerImageVersion="$(docker inspect --format='{{.Id}}' "${_containerImage}")"
        if [[ "${_containerRunning}" -eq 0 ]] && [[ ! "${_containerImageVersion}" = "${_dockerImageVersion}" ]]; then
          _fsMsg_ "Image is outdated: ${_containerName}"
          _containerRestart=0
        fi

        if [[ "${_containerRunning}" -eq 1 ]]; then
            # start container
          docker start "${_containerName}" > /dev/null
        else
            # overrule restart if autoupdate is false
          if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ ! "${_containerAutoupdate}" = 'true' ]]; then
            _containerRestart=1
          fi
          
            # restart container if necessary
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart container (recommended)?")" -eq 0 ]]; then
                # set strategy update only when container is restarted
              if [[ -n "${_strategyUpdate}" ]]; then
                _containerStrategyUpdate="${_strategyUpdate}"
              fi
                # restart container
              docker restart "${_containerName}" > /dev/null
            fi
            _containerRestart=1
          fi
        fi

          # create project json array
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
      elif [[ "${_projectMode}" = "validate" ]]; then
        if [[ "${_containerRunning}" -eq 0 ]]; then
            # set restart to unless-stopped
          docker update --restart=unless-stopped "${_containerName}" > /dev/null
          _containerRestartPolicy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${_containerName}")"
          
          _containerAutoupdate="$(_fsValueGet_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate')"
          if [[ "${_containerAutoupdate}" = 'true' ]]; then
            _containerUpdateCount=$((_containerUpdateCount+1))
          fi
          
          _fsMsg_ "[SUCCESS] Container is active: ${_containerName}"' (Restart: '"${_containerRestartPolicy}"')'
        else
          _fsMsg_ "[ERROR] Container is not active: ${_containerName}"
          _fsDockerStop_ "${_containerName}"
          _error=$((_error+1))
        fi
      elif [[ "${_projectMode}" = "quit" ]]; then
        _fsMsg_ "Container is active: ${_containerName}"

        if [[ "$(_fsCaseConfirmation_ "Quit container?")" -eq 0 ]]; then
          _fsDockerStop_ "${_containerName}"
          _fsValueUpdate_ "${_containerConfPath}" '.'"${_containerName}"'.autoupdate' 'false'
          
          if [[ "$(_fsDockerPsName_ "${_containerName}")" -eq 1 ]]; then
            _fsMsg_ "[SUCCESS] Container is removed: ${_containerName}"
          else
            _fsMsg_ "[ERROR] Container not removed: ${_containerName}"
          fi
        fi
      fi
    done
  fi
  
  if [[ "${_projectMode}" = "compose" ]]; then
    if [[ "${_error}" -eq 0 ]]; then
        # create project conf file
      if (( ${#_procjectJson[@]} )); then
        printf -- '%s\n' "${_procjectJson[@]}" | jq . | sudo tee "${_containerConfPath}" > /dev/null
      else
        sudo rm -f "${_containerConfPath}"
      fi
        # validate project
      _fsDockerProject_ "${_projectPath}" "validate"
    else
      _fsMsg_ "[ERROR] Cannot start: ${_projectFile}"
    fi
  elif [[ "${_projectMode}" = "validate" ]]; then
    if [[ "${_error}" -eq 0 ]]; then
      if [[ "${_containerUpdateCount}" -gt 0 ]]; then
        _fsDockerAutoupdate_ "${_projectFile}"
      else
        _fsDockerAutoupdate_ "${_projectFile}" 'remove'
      fi
    else
      _fsDockerAutoupdate_ "${_projectFile}" 'remove'
    fi
      # clear unused networks
    yes $'y' | docker network prune > /dev/null || true
  elif [[ "${_projectMode}" = "quit" ]]; then
    _fsDockerAutoupdate_ "${_projectFile}" "remove"
    
    if (( ! ${#_projectContainers[@]} )); then
      _fsMsg_ "No container active in project: ${_projectFile}"
    fi
  fi
}

_fsDockerStrategy_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _strategyName="${1}"
  local _strategyFile=''
  local _strategyFileNew=''
  local _strategyUpdate=''
  local _strategyUpdateCount=0
  local _strategyFileType=''
  local _strategyFileTypeName="unknown"
  local _strategyTmp="${FS_DIR_TMP}/${_strategyName}_${FS_HASH}"
  local _strategyDir="${FS_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
  local _strategyUrls=''
  local _strategyUrlsDeduped=''
  local _strategyUrl=''
  local _strategyPath=''
  local _strategyPathTmp=''
  local _strategyJson=''
  
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
    sudo mkdir -p "${_strategyTmp}"
    sudo mkdir -p "${_strategyDir}"
    
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
        
        sudo curl --connect-timeout 10 -s -L "${_strategyUrl}" -o "${_strategyPathTmp}"
        
        if [[ "$(_fsFile_ "${_strategyPath}")" -eq 0 ]]; then
            # only update file if it is different
          if ! cmp --silent "${_strategyPathTmp}" "${_strategyPath}"; then
            sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
            _strategyUpdateCount=$((_strategyUpdateCount+1))
            _fsFileExist_ "${_strategyPath}"
          fi
        else
          sudo cp -a "${_strategyPathTmp}" "${_strategyPath}"
          _strategyUpdateCount=$((_strategyUpdateCount+1))
          _fsFileExist_ "${_strategyPath}"
        fi
      else
        _fsMsg_ '[WARNING] Cannot connect to strategy url.'
      fi
    done
    
    sudo rm -rf "${_strategyTmp}"
    
    if [[ "${_strategyUpdateCount}" -eq 0 ]]; then
      _fsMsg_ "Strategy is installed: ${_strategyName}"
    else
      _fsMsg_ "Strategy updated: ${_strategyName}"
      _strategyUpdate="$(_fsTimestamp_)"
      _strategyJson="$(jq -n \
        --arg update "${_strategyUpdate}" \
        '$ARGS.named' \
      )"
      printf '%s\n' "${_strategyJson}" | jq . | sudo tee "${_strategyDir}/${_strategyName}.conf.json" > /dev/null
    fi
  else
    _fsMsg_ "[WARNING] Strategy is not implemented: ${_strategyName}"
  fi
}

_fsDockerAutoupdate_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _file="freqstart.autoupdate.sh"
  local _path="${FS_DIR}"'/'"${_file}"
  local _projectFile="${1}"
  local _projectAutoupdate='freqstart -c '"${_projectFile}"' -a -y'
  local _projectAutoupdateMode="${2:-}" # optional: remove
  local _projectAutoupdates=""
  local _cronCmd="${_path}"
  local _cronUpdate="0 3 * * *" # update on 3am UTC
  
  _projectAutoupdates=()
  _projectAutoupdates+=("#!/usr/bin/env bash")
  if [[ "$(_fsFile_ "${_path}")" -eq 0 ]]; then
    while read -r; do
    _projectAutoupdates+=("$REPLY")
    done < <(grep -v "${_projectAutoupdate}" "${_path}" | sed "s,#!/usr/bin/env bash,," | sed "/^$/d")
  fi
  
  if [[ ! "${_projectAutoupdateMode}" = "remove" ]]; then
    _projectAutoupdates+=("${_projectAutoupdate}")
  fi
  
  printf '%s\n' "${_projectAutoupdates[@]}" | sudo tee "${_path}" > /dev/null
  sudo chmod +x "${_path}"
  _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
  
  if [[ "${#_projectAutoupdates[@]}" -eq 1 ]]; then
    _fsCrontabRemove_ "${_cronCmd}"
  fi
}

_fsDockerPurge_() {
    if [[ "$(_fsSetupPkgsStatus_ "docker-ce")" -eq 0 ]]; then
      sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
      sudo docker network prune --force
      sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
    fi
}

###
# SETUP

_fsSetup_() {
  local _symlinkSource="${FS_DIR}/${FS_NAME}.sh"

  _fsIntro_
  _fsUser_
  _fsDockerPrerequisites_
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
		_fsMsgExit_ "Cannot create symlink: ${FS_SYMLINK}"
	fi
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

  sudo groupadd docker > /dev/null 2>&1 || true

  if [[ "${_currentUserId}" -eq 0 ]]; then
    _fsMsg_ "Your are logged in as root."
    
    if [[ "$(_fsCaseConfirmation_ 'Skip creating a new user?')" -eq 1 ]]; then
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
          # stop everything on current user
        _fsDockerPurge_
          # credit: https://superuser.com/a/1613980
        sudo adduser --gecos "" "${_newUser}" || sudo passwd "${_newUser}"
        sudo usermod -aG sudo "${_newUser}"
        sudo usermod -aG docker "${_newUser}"
        
          # no password for sudo
        echo "${_newUser} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers > /dev/null
        
        _newPath="$(bash -c "cd ~$(printf %q "${_newUser}") && pwd")"'/'"${FS_NAME}"
        
        if [[ ! -d "${_newPath}" ]]; then
          sudo mkdir "${_newPath}"
        fi
        
				sudo cp -R "${_dir}"/* "${_newPath}"
				sudo chown -R "${_newUser}":"${_newUser}" "${_newPath}"
        
        sudo rm -f "${_symlink}"
        sudo rm -rf "${_dir}"
        
        if [[ "$(_fsCaseConfirmation_ "Disable \"${_currentUser}\" user (recommended)?")" -eq 0 ]]; then
          sudo usermod -L "${_currentUser}"
        fi
        
        _fsMsgTitle_ 'Files can be found in new path: '"${_newPath}"
        _logout=0
      fi
    fi
  fi  
  
  if ! id -nGz "${_currentUser}" | grep -qzxF "docker"; then
    sudo usermod -aG docker "${_currentUser}"
    _logout=0
  fi
  
  if [[ "${_logout}" -eq 0 ]]; then
    _fsMsg_ 'You have to log out/in to activate the changes!'
    _fsCdown_ 10 'to reboot...'
      # may find a more elegant way but it does its job
    sudo reboot && exit 0
  fi
}

# PACKAGES

_fsSetupPkgs_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _pkgs=("$@")
  local _pkg=''
  local _status=''
  local _getDocker="${FS_DIR}/get-docker.sh"

  for _pkg in "${_pkgs[@]}"; do
    if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 1 ]]; then
      if [[ "${_pkg}" = 'docker-ce' ]]; then
          # docker setup
        mkdir -p "${FS_DIR_DOCKER}"
        sudo curl --connect-timeout 10 -fsSL "https://get.docker.com" -o "${_getDocker}"
        _fsFileExist_ "${_getDocker}"
        sudo chmod +x "${_getDocker}"
        sudo sh "${_getDocker}"
        rm -f "${_getDocker}"
        sudo apt install -y -q docker-compose
      elif [[ "${_pkg}" = 'chrony' ]]; then
          # ntp setup
        sudo apt-get install -y -q chrony
          # thanks: lsiem
        sudo systemctl unmask systemd-timesyncd.service
        sudo systemctl stop chronyd
        sudo timedatectl set-timezone 'UTC'
        sudo systemctl start chronyd
        sudo timedatectl set-ntp true
        sudo systemctl restart chronyd
      elif [[ "${_pkg}" = 'ufw' ]]; then
          # firewall setup
        sudo apt-get install -y -q ufw
        sudo ufw logging medium > /dev/null
        yes $'y' | sudo ufw enable
      else
        sudo apt-get install -y -q "${_pkg}"
      fi
        # validate installation
      if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
        _fsMsg_ "Installed: ${_pkg}"
      else
        _fsMsgExit_ "[FATAL] Cannot install: ${_pkg}"
      fi
    fi
  done
}

_fsSetupPkgsStatus_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _pkg="${1}"
  local _status=''
  
  _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" 2> /dev/null | grep "install ok installed")"

  if [[ -n "${_status}" ]]; then
    echo 0
  else
    echo 1
  fi
}

# PREREQUISITES

_fsDockerPrerequisites_() {
  _fsMsgTitle_ "PREREQUISITES"

  sudo apt-get update || true

  _fsSetupPkgs_ "git" "curl" "jq" "docker-ce" "ufw"
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

# NTP

_fsSetupNtp_() {
  _fsMsgTitle_ "NTP (Timezone: UTC)"
  
  if [[ "$(_fsSetupNtpCheck_)" = 1 ]]; then
    _fsSetupPkgs_ "chrony"
    
    if [[ "$(_fsSetupNtpCheck_)" = 1 ]]; then
      _fsMsgExit_ "[FATAL] Cannot activate or synchronize."
    else
      _fsMsg_ "Activated and synchronized."
    fi
  else
    _fsMsg_ "Is active and synchronized."
  fi
}

_fsSetupNtpCheck_() {
  local timentp=''
  local timeutc=''
  local timesyn=''
  
  timentp="$(sudo timedatectl | grep -o 'NTP service: active')"
  timeutc="$(sudo timedatectl | grep -o '(UTC, +0000)')"
  timesyn="$(sudo timedatectl | grep -o 'System clock synchronized: yes')"
  
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
  local _dockerImageStatus=''
  local _configKey=''
  local _configSecret=''
  local _configName=''
  local _configFile=''
  local _configFileTmp=''
  
  _fsMsgTitle_ "FREQTRADE"
  
  if [[ ! -d "${FS_DIR_USER_DATA}" ]]; then
    _fsSetupFreqtradeYml_
    
    cd "${FS_DIR}" && \
    docker-compose --file "$(basename "${_dockerYml}")" run --rm freqtrade create-userdir --userdir "$(basename "${FS_DIR_USER_DATA}")"
    if [[ ! -d "${FS_DIR_USER_DATA}" ]]; then
      _fsMsgExit_ "Directory cannot be created: ${FS_DIR_USER_DATA}"
    else
      _fsMsg_ "Directory created: ${FS_DIR_USER_DATA}"
    fi
    
    sudo rm -f "${_dockerYml}"
  fi
  
  sudo chmod -R g+w "${FS_DIR_USER_DATA}"
  
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
      _fsSetupFreqtradeYml_
      
      cd "${FS_DIR}" && \
      docker-compose --file "$(basename "${_dockerYml}")" \
      run --rm freqtrade new-config --config "$(basename "${FS_DIR_USER_DATA}")/$(basename "${_configFileTmp}")"
      
      sudo rm -f "${_dockerYml}"
      
      _fsFileExist_ "${_configFileTmp}"
      
      sudo cp -a "${_configFileTmp}" "${_configFile}"
      sudo rm -f "${_configFileTmp}"
      
      _fsMsg_ "Enter your exchange api KEY and SECRET to: ${_configFile}"
    fi
  fi
}

_fsSetupFreqtradeYml_() {
  local _dockerYml="${FS_DIR}/${FS_NAME}_setup.yml"
  local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"

  if [[ "$(_fsFile_ "${_dockerYml}")" -eq 1 ]]; then
    sudo curl --connect-timeout 10 -s -L "${_dockerGit}" -o "${_dockerYml}"
    _fsFileExist_ "${_dockerYml}"
  fi
}

# BINANCE-PROXY
# credit: https://github.com/nightshift2k/binance-proxy

_fsSetupBinanceProxy_() {
  local _docker="nightshift2k/binance-proxy:latest"
  local _dockerName="${FS_PROXY_BINANCE}"
  local _containerIp="${FS_PROXY_BINANCE_IP}"
  local _setup=1

  _fsMsgTitle_ 'PROXY FOR BINANCE'
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    _fsMsg_ 'Is already running. (Port: 8990-8991)'
    if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 1 ]]; then
      _setup=0
    fi
  elif [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
    _setup=0
  fi
  
  if [[ "${_setup}" -eq 0 ]]; then
      # binance proxy json file
    _fsFileCreate_ "${FS_PROXY_BINANCE_JSON}" \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"binance\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${_containerIp}:8990/api/v3\"" \
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
    "                    \"public\": \"http://${_containerIp}:8991/api/v3\"" \
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
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    container_name: ${_dockerName}" \
    "    tty: true" \
    "    command: >" \
    "      --port-spot=8990" \
    "      --port-futures=8991" \
    "      --verbose" \
    
    _fsDockerProject_ "$(basename "${FS_PROXY_BINANCE_YML}")" "compose" "force"
  else
    _fsMsg_ "Skipping..."
  fi
}

# KUCOIN-PROXY
# credit: https://github.com/mikekonan/exchange-proxy

_fsSetupKucoinProxy_() {
  local _docker="mikekonan/exchange-proxy:latest-amd64"
  local _dockerName="${FS_PROXY_KUCOIN}"
  local _containerIp="${FS_PROXY_KUCOIN_IP}"
  local _setup=1

  _fsMsgTitle_ 'PROXY FOR KUCOIN'
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    _fsMsg_ 'Is already running. (Port: 8980)'
    
    if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 1 ]]; then
      _setup=0
    fi
  elif [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
    _setup=0
  fi
  
  if [[ "${_setup}" -eq 0 ]]; then
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
    "                    \"public\": \"http://${_containerIp}:8980/kucoin\"," \
    "                    \"private\": \"http://${_containerIp}:8980/kucoin\"" \
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
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    container_name: ${_dockerName}" \
    "    tty: true" \
    "    command: >" \
    "      -port 8980" \
    "      -verbose 1"
    
    _fsDockerProject_ "$(basename "${FS_PROXY_KUCOIN_YML}")" "compose" "force"
  else
    _fsMsg_ "Skipping..."
  fi
}

# NGINX

_fsSetupNginx_() {
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _nr=''

    _fsSetupNginxConf_
    
    while true; do
      printf -- '%s\n' \
      "? Secure the connection to FreqUI?" \
      "  1) Yes, I want to use an IP with SSL (openssl)" \
      "  2) Yes, I want to use a domain with SSL (truecrypt)" \
      "  3) No, I dont want to use SSL (not recommended)" >&2
      
      if [[ "${FS_OPTS_YES}" -eq 1 ]]; then
        read -rp "  (1/2/3) " _nr
      else
        local _nr="3"
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
        [3])
          _fsMsg_ "Continuing with 3) ..."
          sudo ufw allow http > /dev/null
          break
          ;;
        *)
          _fsCaseInvalid_
          ;;
      esac
    done
    
    _fsSetupNginxRestart_
}

_fsSetupNginxConf_() {
  local _serverUrl='http://'"${FS_SERVER_WAN}"
  local _auth=''
  local _username=''
  local _password=''
  local _passwordCompare=''
  local _setup=1

  _fsValueUpdate_ "${FS_CONFIG}" '.server_url' "${_serverUrl}"
  _fsSetupPkgs_ "nginx"
  
  if [[ "$(_fsFile_ "${FS_NGINX_CONFD_HTPASSWD}")" -eq 0 ]]; then
    if [[ "$(_fsCaseConfirmation_ "Skip generating new server login data?")" -eq 1 ]]; then
      _setup=0
    fi
  else
    _fsMsg_ "Create server login data now!"
    _setup=0
  fi
  
  if [[ "${_setup}" -eq 0 ]];then
    _loginData="$(_fsLoginData_)"
    _username="$(_fsLoginDataUsername_ "${_loginData}")"
    _password="$(_fsLoginDataPassword_ "${_loginData}")"
    
      # create htpasswd for proxy access
    sudo rm -f "${FS_NGINX_CONFD_HTPASSWD}"
    sudo sh -c "echo -n ${_username}':' > ${FS_NGINX_CONFD_HTPASSWD}"
    sudo sh -c "openssl passwd ${_password} >> ${FS_NGINX_CONFD_HTPASSWD}"
  fi
    
    # create nginx conf for non ssl
  _fsFileCreate_ "${FS_NGINX_CONFD_FREQUI}" \
  "server {" \
  "    listen ${FS_SERVER_WAN}:80;" \
  "    server_name ${FS_SERVER_WAN};" \
  "    location / {" \
  "        proxy_pass http://127.0.0.1:9999;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "        auth_basic \"Restricted\";" \
  "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${FS_SERVER_WAN}:9000-9100;" \
  "    server_name ${FS_SERVER_WAN};" \
  "    location / {" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-NginX-Proxy true;" \
  "        proxy_redirect off;" \
  "    }" \
  "}"
  
  if [[ "$(_fsFile_ "${FS_NGINX_CONFD_DEFAULT}")" -eq 0 ]]; then
    sudo mv "${FS_NGINX_CONFD_DEFAULT}" "${FS_NGINX_CONFD_DEFAULT}.disabled"
  fi
  
  sudo rm -f "/etc/nginx/sites-enabled/default"
}

_fsSetupNginxCheck_() {
  if [[ "$(_fsSetupPkgsStatus_ 'nginx')" -eq 1 ]]; then
    echo 1
  elif sudo nginx -t 2>&1 | grep -qo "failed"; then
    echo 1
  else
    echo 0
  fi
}

_fsSetupNginxRestart_() {
  if [[ "$(_fsSetupNginxCheck_)" -eq 1 ]]; then
    _fsMsgExit_ "Error in nginx config file. For more info enter: sudo nginx -t"
  fi
  
  sudo /etc/init.d/nginx stop > /dev/null
  sudo pkill -f nginx & wait $! > /dev/null
  sudo /etc/init.d/nginx start > /dev/null
}

_fsSetupNginxOpenssl_() {
  _fsSetupNginxConfSecure_ "openssl"
  
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com" \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt
  
  sudo openssl dhparam -out /etc/nginx/dhparam.pem 4096
  
  _fsFileCreate_ '/etc/nginx/snippets/self-signed.conf' \
  "ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;" \
  "ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;"
  
  _fsFileCreate_ '/etc/nginx/snippets/ssl-params.conf' \
  "ssl_protocols TLSv1.2;" \
  "ssl_prefer_server_ciphers on;" \
  "ssl_dhparam /etc/nginx/dhparam.pem;" \
  "ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;" \
  "ssl_ecdh_curve secp384r1; # Requires nginx >= 1.1.0" \
  "ssl_session_timeout  10m;" \
  "ssl_session_cache shared:SSL:10m;" \
  "ssl_session_tickets off; # Requires nginx >= 1.5.9" \
  "ssl_stapling on; # Requires nginx >= 1.3.7" \
  "ssl_stapling_verify on; # Requires nginx => 1.3.7" \
  "resolver 8.8.8.8 8.8.4.4 valid=300s;" \
  "resolver_timeout 5s;" \
  "# Disable strict transport security for now. You can uncomment the following" \
  "# line if you understand the implications." \
  "# add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\";" \
  "add_header X-Frame-Options DENY;" \
  "add_header X-Content-Type-Options nosniff;" \
  "add_header X-XSS-Protection \"1; mode=block\";"
}

_setupNginxLetsencrypt_() {
  local _serverDomain=''
  local _serverDomainIp=''
  
  _serverDomain="$(_fsValueGet_ "${FS_CONFIG}" '.server_domain')"
  
  _fsSetupPkgs_ 'certbot' 'python3-certbot-nginx'
  
  while true; do
    if [[ -z "${_serverDomain}" ]]; then
      read -rp "? Enter your domain (www.example.com): " _serverDomain
    fi
    
    if [[ -z "${_serverDomain}" ]]; then
      _fsCaseEmpty_
    else
      if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_serverDomain}\" correct?")" -eq 0 ]]; then
        if host "${_serverDomain}" 1> /dev/null 2> /dev/null; then
          _serverDomainIp="$(host "${_serverDomain}" | awk '/has address/ { print $4 }')"
        fi
        
        if [[ ! "${_serverDomainIp}" = "${FS_SERVER_WAN}" ]]; then
          _fsMsg_ "The domain \"${_serverDomain}\" does not point to \"${FS_SERVER_WAN}\". Review DNS and try again!"
        else
          _fsValueUpdate_ "${FS_CONFIG}" '.server_domain' "${_serverDomain}"

          _fsSetupNginxConfSecure_ "letsencrypt"
          break
        fi
      fi
      _serverDomain=''
    fi
  done
}

_fsSetupNginxConfSecure_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _mode="${1}"
  local _serverDomain=''
  local _serverUrl=''
  local _sslCert=''
  local _sslCertKey=''
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _cronUpdate="0 0 * * *"
  
  _serverDomain="$(_fsValueGet_ "${FS_CONFIG}" '.server_domain')"
  
  if [[ -n "${_serverDomain}" ]]; then
    _serverUrl='https://'"${_serverDomain}"
  else
    _serverUrl='https://'"${FS_SERVER_WAN}"
  fi
  
  _sslCert="/etc/letsencrypt/live/${_serverDomain}/fullchain.pem"
  _sslCertKey="/etc/letsencrypt/live/${_serverDomain}/privkey.pem"
  
  _fsValueUpdate_ "${FS_CONFIG}" '.server_url' "${_serverUrl}"
  
  sudo rm -f "${FS_NGINX_CONFD_FREQUI}"
    # thanks: Blood4rc, Hippocritical
  if [[ "${_mode}" = 'openssl' ]]; then
      # create nginx conf for ip ssl
    _fsFileCreate_ "${FS_NGINX_CONFD_FREQUI}" \
    "server {" \
    "    listen ${FS_SERVER_WAN}:443 ssl;" \
    "    server_name ${FS_SERVER_WAN};" \
    "    include snippets/self-signed.conf;" \
    "    include snippets/ssl-params.conf;" \
    "    location / {" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "        auth_basic \"Restricted\";" \
    "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${FS_SERVER_WAN}:9000-9100 ssl;" \
    "    server_name ${FS_SERVER_WAN};" \
    "    include snippets/self-signed.conf;" \
    "    include snippets/ssl-params.conf;" \
    "    location / {" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "    }" \
    "}"
  elif [[ "${_mode}" = 'letsencrypt' ]]; then
      # workaround for first setup while missing cert files
    if [[ "$(_fsFile_ "${_sslCert}")" -eq 1 ]] || [[ "$(_fsFile_ "${_sslCertKey}")" -eq 1 ]]; then
      _fsFileCreate_ "${FS_NGINX_CONFD_FREQUI}" \
      "server {" \
      "    listen 80;" \
      "    server_name ${_serverDomain};" \
      "    location '/.well-known/acme-challenge' {" \
      "        default_type \"text/plain\";" \
      "        root /var/www/html;" \
      "    }" \
      "}"
      _fsSetupNginxRestart_
    fi
      # start letsencrypt routine
    sudo certbot --nginx -d "${_serverDomain}"
      # add cron to automatically renew cert file
    _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
    
    # create nginx conf for domain ssl
    _fsFileCreate_ "${FS_NGINX_CONFD_FREQUI}" \
    "server {" \
    "    listen ${_serverDomain}:443 ssl http2;" \
    "    server_name ${_serverDomain};" \
    "    ssl_certificate /etc/letsencrypt/live/${_serverDomain}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverDomain}/privkey.pem;" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    # Required for LE certificate enrollment using certbot" \
    "    location '/.well-known/acme-challenge' {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/html;" \
    "    }" \
    "    location / {" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-NginX-Proxy true;" \
    "        proxy_redirect off;" \
    "        auth_basic \"Restricted\";" \
    "        auth_basic_user_file ${FS_NGINX_CONFD_HTPASSWD};" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_serverDomain}:9000-9100 ssl http2;" \
    "    server_name ${_serverDomain};" \
    "    ssl_certificate /etc/letsencrypt/live/${_serverDomain}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverDomain}/privkey.pem;" \
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
    "}"
  fi
  
  sudo ufw delete allow http > /dev/null
  sudo ufw deny http > /dev/null
  sudo ufw allow https > /dev/null
}

# FREQUI

_fsSetupFrequi_() {
  local _frequiName="${FS_NAME}"'_frequi'
  local _serverUrl=''
  local _setup=1
  local _nr=''
  
  _serverUrl="$(_fsValueGet_ "${FS_CONFIG}" ".server_url")"

  _fsMsgTitle_ "FREQUI"
  
	if [[ "$(_fsDockerPsName_ "${_frequiName}")" -eq 0 ]]; then
    _fsMsg_ "Is active: ${_serverUrl}"
    if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 1 ]]; then
      _setup=0
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
      _setup=0
    fi
  fi
  
  if [[ "${_setup}" -eq 0 ]];then
    _fsSetupNginx_
    
      # allow port range for containers that use frequi
    sudo ufw allow 9000:9100/tcp > /dev/null
      # allow port for frequi container
    sudo ufw allow 9999/tcp > /dev/null

    _fsSetupFrequiJson_
    _fsSetupFrequiCompose_
  fi
}

_fsSetupFrequiJson_() {
  local _frequiJwt=''
  local _frequiUsername=''
  local _frequiPassword=''
  local _frequiPasswordCompare=''
  local _frequiTmpUsername=''
  local _frequiTmpPassword=''
  local _serverUrl=''
  local _serverWan=''
  local _setup=1
  
  _frequiJwt="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.jwt_secret_key")"
  _frequiUsername="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.username")"
  _frequiPassword="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".api_server.password")"
  _serverWan="$(_fsValueGet_ "${FS_FREQUI_JSON}" ".server_wan")"
  _serverUrl="$(_fsValueGet_ "${FS_CONFIG}" ".server_url")"

    # generate jwt if it is not set in config
  [[ -z "${_frequiJwt}" ]] && _frequiJwt="$(_fsRandomBase64UrlSafe_ 32)"
  
  if [[ -n "${_frequiUsername}" ]] || [[ -n "${_frequiPassword}" ]]; then
    _fsMsg_ "Login data already found."
    
    if [[ "$(_fsCaseConfirmation_ "Skip generating new FreqUI login data?")" -eq 1 ]]; then
      _setup=0
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Create login data now?")" -eq 0 ]]; then
      _setup=0
    else
      _setup=1
        # generate login data if first time setup is non-interactive
      _frequiUsername="$(_fsRandomBase64_ 16)"
      _frequiPassword="$(_fsRandomBase64_ 16)"
      _fsMsg_ '[WARNING] Login data created automatically. Edit login data in: '"${FS_FREQUI_JSON}"
    fi
  fi

  if [[ "${_setup}" = 0 ]]; then
    _loginData="$(_fsLoginData_)"
    _frequiUsername="$(_fsLoginDataUsername_ "${_loginData}")"
    _frequiPassword="$(_fsLoginDataPassword_ "${_loginData}")"
  fi
  
  if [[ -n "${_frequiUsername}" ]] && [[ -n "${_frequiPassword}" ]]; then
      # create frequi json for bots
    _fsFileCreate_ "${FS_FREQUI_JSON}" \
    "{" \
    "    \"api_server\": {" \
    "        \"enabled\": true," \
    "        \"listen_ip_address\": \"0.0.0.0\"," \
    "        \"listen_port\": 9999," \
    "        \"verbosity\": \"error\"," \
    "        \"enable_openapi\": false," \
    "        \"jwt_secret_key\": \"${_frequiJwt}\"," \
    "        \"CORS_origins\": [\"${_serverUrl}\"]," \
    "        \"username\": \"${_frequiUsername}\"," \
    "        \"password\": \"${_frequiPassword}\"" \
    "    }" \
    "}"
  else
    _fsMsgExit_ '[FATAL] Passwort or username missing!'
  fi
}

_fsSetupFrequiCompose_() {
  local _frequiStrategy='DoesNothingStrategy'
  local _frequiName="${FS_NAME}"'_frequi'
  local _frequiServerLog="${FS_DIR_USER_DATA}"'/logs/'"${_frequiName}"'.log'
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
  "  ${_frequiName}:" \
  "    image: ${_docker}" \
  "    container_name: ${_frequiName}" \
  "    volumes:" \
  "      - \"./user_data:/freqtrade/user_data\"" \
  "    ports:" \
  "      - \"127.0.0.1:9999:9999\"" \
  "    tty: true" \
  "    command: >" \
  "      trade" \
  "      --logfile /freqtrade/user_data/logs/$(basename "${_frequiServerLog}")" \
  "      --strategy ${_frequiStrategy}" \
  "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_SERVER_JSON}")" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_JSON}")"
  
  _fsDockerProject_ "${FS_FREQUI_YML}" "compose" "force"
}

###
# START

_fsStart_() {
	local _yml="${1:-}"
  local _symlink="${FS_SYMLINK}"
    
    # check if symlink from setup routine exist
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
		_fsUsage_ "Start setup first!"
  fi
  
  
  if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ "${FS_OPTS_QUIT}" -eq 0 ]]; then
    _fsUsage_ "[ERROR] Option -a or --auto cannot be used with -q or --quit."
  elif [[ "${FS_OPTS_QUIT}" -eq 0 ]] && [[ "${FS_OPTS_COMPOSE}" -eq 0 ]]; then
    _fsUsage_ "[ERROR] Option -c or --compose cannot be used with -q or --quit."
  elif [[ -z "${_yml}" ]]; then
    _fsUsage_ "[ERROR] Setting an \"example.yml\" file with -c or --compose is required."
  else
    _fsIntro_

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

_fsIntro_() {
	local _serverWan=''
	local _serverDomain=''
	local _serverUrl=''
  
  printf -- '%s\n' \
  "###" \
  "# ${FS_NAME^^}: ${FS_VERSION}" \
  "###" >&2
  
	if [[ "$(_fsFile_ "${FS_CONFIG}")" -eq 0 ]]; then
    _serverWan="$(_fsValueGet_ "${FS_CONFIG}" ".server_wan")"
    if [[ -n "${_serverWan}" ]] && [[ ! "${FS_SERVER_WAN}" = "${_serverWan}" ]]; then
      _fsMsgTitle_ '[WARNING] Server WAN has changed ('"${_serverWan}"' -> '"${FS_SERVER_WAN}"'). Run setup again!'
    else
      _serverWan="${FS_SERVER_WAN}"
    fi
    
    _serverDomain="$(_fsValueGet_ "${FS_CONFIG}" ".server_domain")"
    _serverUrl="$(_fsValueGet_ "${FS_CONFIG}" ".server_url")"
  fi
  
  _fsFileCreate_ "${FS_CONFIG}" \
  "{" \
  "    \"version\": \"${FS_VERSION}\"," \
  "    \"server_wan\": \"${_serverWan}\"," \
  "    \"server_domain\": \"${_serverDomain}\"," \
  "    \"server_url\": \"${_serverUrl}\"" \
  "}"
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
	"###" \
	"# Time to API (Binance): ${_time}" \
	"# CPU Usage: ${_cpuUsage}% (avg. 15min)" \
	"# Memory Usage: ${_memory}" \
	"# Disk Usage: ${_disk}" \
	"###" >&2
}

_fsUsage_() {
  local _msg="${@:-}"
  
  if [[ -n "${_msg}" ]]; then
    printf -- '%s\n' \
    "  ${_msg}" \
    "" >&2
  fi
  
  printf -- '%s\n' \
  "###" \
  "# ${FS_NAME^^}: ${FS_VERSION}" \
  "###" \
  "" \
  "  Freqstart simplifies the use of Freqtrade with Docker. Including a setup guide for Freqtrade," \
  "  configurations and FreqUI with a secured SSL proxy for IP or domain. Freqtrade automatically" \
  "  installs implemented strategies based on Docker Compose files and detects necessary updates." \
  "" \
  "- USAGE" \
  "  Start: ${FS_FILE} --compose example.yml --yes" \
  "  Quit: ${FS_FILE} --compose example.yml --quit --yes" \
  "" \
  "- OPTIONS" \
  "  -s, --setup     Install and update" \
  "  -c, --compose   Start docker project" \
  "  -q, --quit      Stop docker project" \
  "  -y, --yes       Yes on every confirmation" \
  "  --reset         Stop and remove all Docker images, containers und networks but keep all files" \
  "" >&2
  
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
  
	if [[ -z "${_file}" ]]; then
    echo 1
  elif [[ -s "${_file}" ]]; then
    echo 0
  else
    echo 1
	fi
}

_fsFileExist_() {
  local _file="${1:-}" # optional: path to file
  
	if [[ "$(_fsFile_ "${_file}")" -eq 1 ]]; then
		_fsMsg_ "Cannot create file: ${_file}"
    exit 1
  fi
}

_fsFileCreate_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"; shift
  local _array=("${@}")
  local _fileTmp=''
  local _file="${_filePath##*/}"
  local _fileDir="${_filePath%/*}"
  local _fileHash=''

  _fileHash="$(_fsRandomHex_ 8)"
  _fileTmp="${FS_DIR_TMP}"'/'"${_fileHash}"'_'"${_file}"

  printf -- '%s\n' "${_array[@]}" | sudo tee "${_fileTmp}" > /dev/null
  
  if [[ ! -d "${_fileDir}" ]]; then
    sudo mkdir -p "${_fileDir}"
  fi
  
  sudo cp "${_fileTmp}" "${_filePath}"
  
  _fsFileExist_ "${_filePath}"
}

_fsCrontab_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  local _cronJob="${2} ${_cronCmd}"
    # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -
  
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
    _fsMsgExit_ "Cron not set: ${_cronCmd}"
  fi
}

_fsCrontabRemove_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
    # credit: https://stackoverflow.com/a/17975418
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    ( crontab -l 2> /dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -
    
    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
      _fsMsgExit_ "Cron not removed: ${_cronCmd}"
    fi
  fi
}

_fsCrontabValidate_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  
  crontab -l 2> /dev/null | grep -q "${_cronCmd}"  && echo 0 || echo 1
}

_fsValueGet_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"
  local _fileType="${_filePath##*.}"
  local _key="${2}"
  local _value=''

  if [[ "$(_fsFile_ "${_filePath}")" -eq 0 ]]; then
    if [[ "${_fileType}" = 'json' ]]; then
        # get value from json
      _value="$(jq -r "${_key}"' // empty' "${_filePath}" 2> /dev/null || true)"
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
  [[ $# -lt 3 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _filePath="${1}"
  local _file="${_filePath##*/}"
  local _fileType="${_filePath##*.}"
  local _fileHash=''
  local _fileTmp=''
  local _json=''
  local _jsonUpdate=''
  local _key="${2}"
  local _value="${3}"

  _fsFileExist_ "${_filePath}"
  
  _fileHash="$(_fsRandomHex_ 8)"
  _fileTmp="${FS_DIR_TMP}"'/'"${_fileHash}"'_'"${_file}"
  
  if [[ "${_fileType}" = 'json' ]]; then
      # update value for json
    _json="$(_fsValueGet_ "${_filePath}" '.')"
      # credit: https://stackoverflow.com/a/24943373
    _jsonUpdate="$(jq "${_key}"' = $newVal' --arg newVal "${_value}" <<< "${_json}")"

    printf '%s\n' "${_jsonUpdate}" | jq . | sudo tee "${_fileTmp}" > /dev/null
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
      _fsMsgExit_ '[FATAL] Cannot find key "'"${_key}"'" in: '"${_filePath}"
    fi
  fi
    # override file if different
  if ! cmp --silent "${_fileTmp}" "${_filePath}"; then
    sudo cp "${_fileTmp}" "${_filePath}"
  fi
}

_fsCaseConfirmation_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _url="${1}"
    # credit: https://stackoverflow.com/a/55267709
  local _regex="^(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$"
  local _status=''
  
  if [[ "${_url}" =~ $_regex ]]; then
      # credit: https://stackoverflow.com/a/41875657
    _status="$(curl --connect-timeout 10 -o /dev/null -Isw '%{http_code}' "${_url}")"

    if [[ "${_status}" = '200' ]]; then
      echo 0
    else
      echo 1
    fi
  else
    _fsMsgExit_ "Url is not valid: ${_url}"
  fi
}

_fsCdown_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
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
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _string="${1}"
  local _regex='^[[:alnum:]_-]+$'
  
  if [[ ${_string} =~ $_regex ]]; then
    echo 0
  else
    echo 1
  fi
}

_fsDedupeArray_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
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
  _fsIntro_
  
  _fsMsgTitle_ '[WARNING] Stopp and remove all containers, networks and images!'
  
  if [[ "$(_fsCaseConfirmation_ "Are you sure you want to continue?")" -eq 0 ]]; then
    _fsDockerPurge_
  fi
}

_fsIsSymlink_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
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
  local _lockDir="${FS_DIR_TMP}/${FS_NAME}.lock"
  
  if [[ -n "${FS_DIR_TMP}" ]]; then
    if [[ -d "${_lockDir}" ]]; then
        # error 99 to not remove temp dir
      _fsMsgExit_ "[FATAL] Script is already running! Delete folder if this is an error: sudo rm -rf ${FS_DIR_TMP}" 99
    elif ! sudo mkdir -p "${_lockDir}" 2> /dev/null; then
      _fsMsgExit_ "[FATAL] Unable to acquire script lock: ${_lockDir}"
    fi
  else
    _fsMsgExit_ "[FATAL] Temporary directory is not defined!"
  fi
}

_fsLoginData_() {
    local _username=''
    local _password=''
    local _passwordCompare=''
    
    _fsMsg_ "Create your login data now!"
    
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
    
    echo "${_username}"':'"${_password}"
}

_fsLoginDataUsername_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _username="${1}"
  echo "$(cut -d':' -f1 <<< "${_username}")"
}

_fsLoginDataPassword_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _password="${1}"
  echo "$(cut -d':' -f2 <<< "${_password}")"
}

_fsCleanup_() {
  local _error="${?}"
  trap - ERR EXIT SIGINT SIGTERM
  if [[ "${_error}" -ne 99 ]]; then
    _fsMsg_ 'Cleanup...'
      # thanks: lsiem
    sudo rm -rf "${FS_DIR_TMP}"
  fi
}

_fsErr_() {
    local _error="${?}"
    printf -- '%s\n' "Error in ${FS_FILE} in function ${1} on line ${2}" >&2
    exit ${_error}
}

_fsMsg_() {
  local -r _msg="${1}"
  printf -- '%s\n' \
  "  ${_msg}" >&2
}

_fsMsgTitle_() {
  local -r _msg="${1}"
  printf -- '%s\n' \
  "- ${_msg}" >&2
}

_fsMsgExit_() {
  local -r _msg="${1}"
  local -r _code="${2:-90}" # optional: set to 90
  
  printf -- '%s\n' \
  "${_msg[*]}" >&2
  
  exit "${_code}"
}

_fsOptions_() {
  local -r _args=("${@}")
  local _opts
  
  _opts="$(getopt --options c:,q:,s,a,y,h --long compose:,quit:,setup,auto,yes,help,reset -- "${_args[@]}" 2> /dev/null)" || {
    _fsUsage_ "[FATAL] Unkown or missing argument."
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

if [[ "${FS_OPTS_SETUP}" -eq 0 ]]; then
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