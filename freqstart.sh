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
readonly FS_VERSION='v0.1.6'
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

readonly FS_BINANCE_PROXY='binance_proxy'
readonly FS_BINANCE_PROXY_JSON="${FS_DIR_USER_DATA}/${FS_BINANCE_PROXY}.json"
readonly FS_BINANCE_PROXY_FUTURES_JSON="${FS_DIR_USER_DATA}/${FS_BINANCE_PROXY}_futures.json"
readonly FS_BINANCE_PROXY_YML="${FS_DIR}/${FS_BINANCE_PROXY}.yml"

readonly FS_KUCOIN_PROXY='kucoin_proxy'
readonly FS_KUCOIN_PROXY_JSON="${FS_DIR_USER_DATA}/${FS_KUCOIN_PROXY}.json"
readonly FS_KUCOIN_PROXY_YML="${FS_DIR}/${FS_KUCOIN_PROXY}.yml"

readonly FS_FREQUI_JSON="${FS_DIR_USER_DATA}/frequi.json"
readonly FS_FREQUI_SERVER_JSON="${FS_DIR_USER_DATA}/frequi_server.json"
readonly FS_FREQUI_YML="${FS_DIR}/${FS_NAME}_frequi.yml"
FS_SERVER_WAN="$(hostname -I | awk '{ print $1 }')"
readonly FS_SERVER_WAN
FS_HASH="$(xxd -l8 -ps /dev/urandom)"
readonly FS_HASH

FS_OPTS_BOT=1
FS_OPTS_SETUP=1
FS_OPTS_AUTO=1
FS_OPTS_KILL=1
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
    
    [[ -n "${_dockerVersionLocal}" ]] && echo "${_dockerVersionLocal}"
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
	_dockerManifest="${FS_DIR_TMP}/${_dockerName}_${_dockerTag}_${FS_HASH}.json"

    # credit: https://stackoverflow.com/a/64309017
  _acceptM="application/vnd.docker.distribution.manifest.v2+json"
  _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
  _token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${_dockerRepo}:pull" | jq -r '.token')"

  curl -H "Accept: ${_acceptM}" -H "Accept: ${_acceptML}" -H "Authorization: Bearer ${_token}" -o "${_dockerManifest}" \
  -I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}"

  if [[ "$(_fsFile_ "${_dockerManifest}")" -eq 0 ]]; then
    _status="$(grep -o "200 OK" "${_dockerManifest}")"

    if [[ -n "${_status}" ]]; then
      _dockerVersionHub="$(_fsJsonGet_ "${_dockerManifest}" "etag")"
      
      if [[ -n "${_dockerVersionHub}" ]]; then
        echo "${_dockerVersionHub}"
      fi
    fi
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
      # equal
    _fsMsg_ "Image is installed: ${_dockerRepo}:${_dockerTag}"
    _dockerStatus=0
  elif [[ "${_dockerCompare}" -eq 1 ]]; then
      # greater
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"

    if [[ -n "${_dockerVersionLocal}" ]]; then
        # update from docker hub
      _fsMsg_ "Image update found for: ${_dockerRepo}:${_dockerTag}"
      
      if [[ "$(_fsCaseConfirmation_ "Do you want to update now?")" -eq 0 ]]; then
        sudo docker pull "${_dockerRepo}:${_dockerTag}"
        
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
      sudo docker pull "${_dockerRepo}:${_dockerTag}"
      if [[ "$(_fsDockerVarsCompare_ "${_dockerImage}")" -eq 0 ]]; then
        _fsMsg_ "Image installed: ${_dockerRepo}:${_dockerTag}"
        _dockerStatus=1
      fi
    fi
  elif [[ "${_dockerCompare}" -eq 2 ]]; then
      # unknown
      # if docker is not reachable try to load local backup
    if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
      _dockerStatus=0
    elif [[ "$(_fsFile_ "${_dockerPath}")" -eq 0 ]]; then
      sudo docker load -i "${_dockerPath}"

      if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
        _dockerStatus=0
      fi
    fi
  fi

  _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"

  if [[ "${_dockerStatus}" -eq 0 ]]; then
    echo "${_dockerVersionLocal}"
  elif [[ "${_dockerStatus}" -eq 1 ]]; then
    [[ ! -d "${FS_DIR_DOCKER}" ]] && sudo mkdir -p "${FS_DIR_DOCKER}"

    sudo rm -f "${_dockerPath}"
    sudo docker save -o "${_dockerPath}" "${_dockerRepo}:${_dockerTag}"
    [[ "$(_fsFile_ "${_dockerPath}")" -eq 1 ]] && _fsMsg_ "[WARNING] Cannot create backup for: ${_dockerRepo}:${_dockerTag}"
    
    echo "${_dockerVersionLocal}"
  else
    _fsMsgExit_ "Image not found: ${_dockerRepo}:${_dockerTag}"
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

_fsDockerProxyIp_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dockerName="${1}"
  
  _containerIp="$(docker inspect -f '{{ .NetworkSettings.Networks.bridge.IPAddress }}' "${_dockerName}")"
  
  if [[ -n "${_containerIp}" ]]; then
    _fsJsonSet_ "${FS_CONFIG}" "${_dockerName}" "${_containerIp}"
    echo "${_containerIp}"
  else
    _fsMsgExit_ '[FATAL] Proxy IP for "'"${_dockerName}"'" not found.'
  fi
}

_fsDockerProxyIpValidate_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _dockerName="${1}"
  local _confIp=''
  
  _confIp="$(_fsJsonGet_ "${FS_CONFIG}" "${_dockerName}")"

  if [[ -n "${_confIp}" ]]; then
    _containerIp="$(docker inspect -f '{{ .NetworkSettings.Networks.bridge.IPAddress }}' "${_dockerName}")"
  
    if [[ ! "${_confIp}" = "${_containerIp}" ]]; then
      _fsMsgTitle_ '[WARNING] Proxy IP "'"${_dockerName}"'" has changed ('"${_confIp}"' -> '"${_containerIp}"'). Run setup again!'
    fi
  fi
}

_fsDockerStop_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerName="${1}"

  sudo docker update --restart=no "${_dockerName}" >/dev/null
  sudo docker stop "${_dockerName}" >/dev/null
  sudo docker rm -f "${_dockerName}" >/dev/null
  
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
      if [[ -n "$(_fsDockerImage_ "${_ymlImage}")" ]]; then
        echo 0
      else
        echo 1
      fi
    done
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
  local _update=0
  
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

    for _strategy in "${_strategiesDeduped[@]}"; do        
      if [[ "$(_fsDockerStrategy_ "${_strategy}")" -eq 1 ]]; then
        _update=$((_update+1))
      fi
    done
  fi

  if [[ "${_update}" -eq 0 ]]; then
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

	local _projectPath="${1}"
	local _projectMode="${2}" # compose, validate, kill
	local _projectForce="${3:-}" # optional: force
  local _projectCronCmd=''
  local _projectCronUpdate=''
	local _projectFile=''
	local _projectFileName=''
  local _projectName=''
  local _projectImages=''
  local _projectStrategies=''
  local _projectConfigs=''
  local _projectPorts=''
  local _projectContainers=''
  local _projectContainer=''
  local _procjectJson=''
  local _containerCmd=''
  local _containerRunning=''
  local _containerRestart=1
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
  local _strategyUpdate=''
  local _strategyDir=''
  local _strategyPath=''
  local _error=0

  _projectPath="$(_fsIsYml_ "${_projectPath}")"

  if [[ -n "${_projectPath}" ]]; then
    _projectFile="${_projectPath##*/}"
    _projectFileName="${_projectFile%.*}"
    _projectName="${_projectFileName//\-/\_}"
    _procjectJson=()
    _projectContainers=()
    _containerConfPath="${FS_DIR}/${_projectFileName}.conf.json"

    if [[ "${_projectMode}" = "compose" ]]; then
      _fsMsgTitle_ "Validate project: ${_projectFile}"

      _projectImages="$(_fsDockerProjectImages_ "${_projectPath}")"
      _projectStrategies="$(_fsDockerProjectStrategies_ "${_projectPath}")"
      _projectConfigs="$(_fsDockerProjectConfigs_ "${_projectPath}")"
      
      yes $'y' | docker network prune >/dev/null || true

      if [[ "${_projectForce}" = "force" ]]; then
        _projectPorts=0
      else
        _projectPorts="$(_fsDockerProjectPorts_ "${_projectPath}")"
      fi

      [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
      [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
      [[ "${_projectPorts}" -eq 1 ]] && _error=$((_error+1))

      if [[ "${_error}" -eq 0 ]]; then
        if [[ "${_projectForce}" = "force" ]]; then
          cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --force-recreate --remove-orphans
        else
          cd "${FS_DIR}" && docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --no-recreate --remove-orphans
        fi
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      _fsCdown_ 30 "for any errors..."
    elif [[ "${_projectMode}" = "kill" ]]; then
      _fsMsgTitle_ "Kill project: ${_projectFile}"
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
          
            # connect container to bridge network
          docker network connect bridge "${_containerName}"
          
            # set restart to no
          sudo docker update --restart=no "${_containerName}" >/dev/null
          
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
            _strategyUpdate="$(jq '.update // empty' < "${_strategyPath}")"
            _strategyUpdate="$(echo "${_strategyUpdate}" | sed -e 's,",,g' | sed -e 's,\\n,,g')"
          else
            _strategyUpdate=""
          fi
          
          if [[ "$(_fsFileEmpty_ "${_containerConfPath}")" -eq 0 ]]; then
            _containerStrategyUpdate="$(jq '.'"${_containerName}"'[0].strategy_update // empty' < "${_containerConfPath}")"
            _containerStrategyUpdate="$(echo "${_containerStrategyUpdate}" | sed -e 's,",,g' | sed -e 's,\\n,,g')"
          else
            _containerStrategyUpdate=""
          fi
          
          if [[ -n "${_strategyUpdate}" ]]; then
            if [[ -n "${_containerStrategyUpdate}" ]]; then
              if [[ "${_containerRunning}" -eq 0 ]] && [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
                _fsMsg_ "Strategy is outdated: ${_containerName}"
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
          
            # stop container if restart is necessary
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart container?")" -eq 0 ]]; then
              if [[ -n "${_strategyUpdate}" ]]; then
                _containerStrategyUpdate="${_strategyUpdate}"
              fi
              _fsDockerStop_ "${_containerName}"
            fi
            _containerRestart=1
          fi
          
            # create project json array
          if [[ -n "${_containerStrategyUpdate}" ]]; then
            _containerJsonInner="$(jq -n \
              --arg strategy "${_containerStrategy}" \
              --arg strategy_path "${_containerStrategyDir}" \
              --arg strategy_update "${_containerStrategyUpdate}" \
              '$ARGS.named' \
            )"
            _containerJson="$(jq -n \
              --argjson "${_containerName}" "[${_containerJsonInner}]" \
              '$ARGS.named' \
            )"
            _procjectJson[$_containerCount]="${_containerJson}"
          fi
            # start container
          docker start "${_containerName}" >/dev/null
            # increment container count
          _containerCount=$((_containerCount+1))
        elif [[ "${_projectMode}" = "validate" ]]; then
          if [[ "${_containerRunning}" -eq 0 ]]; then
              # set restart to unless-stopped
            sudo docker update --restart=unless-stopped "${_containerName}" >/dev/null
            _fsMsg_ "[SUCCESS] Container is active: ${_containerName}"' (Restart: '"$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${_containerName}")"')'
          else
            _fsMsg_ "[ERROR] Container is not active: ${_containerName}"
            _fsDockerStop_ "${_containerName}"
            _error=$((_error+1))
          fi
        elif [[ "${_projectMode}" = "kill" ]]; then
          _fsMsg_ "Container is active: ${_containerName}"

          if [[ "$(_fsCaseConfirmation_ "Kill container?")" -eq 0 ]]; then
            _fsDockerStop_ "${_containerName}"
            
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
        if (( ${#_procjectJson[@]} )); then
          printf -- '%s\n' "${_procjectJson[@]}" | jq . | sudo tee "${_containerConfPath}" >/dev/null
        else
          sudo rm -f "${_containerConfPath}"
        fi
        
        _fsDockerProject_ "${_projectPath}" "validate"
      else
        _fsMsg_ "[ERROR] Cannot start: ${_projectFile}"
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      if [[ "${FS_OPTS_AUTO}" -eq 0 ]]; then
        _fsDockerAutoupdate_ "${_projectFile}"
      fi
    elif [[ "${_projectMode}" = "kill" ]]; then
      _fsDockerAutoupdate_ "${_projectFile}" "remove"
      
      if (( ! ${#_projectContainers[@]} )); then
        _fsMsg_ "No container active in project: ${_projectFile}"
      fi
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
        
        sudo curl -s -L "${_strategyUrl}" -o "${_strategyPathTmp}"
        
        if [[ "$(_fsFile_ "${_strategyPath}")" -eq 0 ]]; then
          if ! cmp --silent "${_strategyPathTmp}" "${_strategyPath}"; then
            cp -a "${_strategyPathTmp}" "${_strategyPath}"
            _strategyUpdateCount=$((_strategyUpdateCount+1))
            _fsFileExist_ "${_strategyPath}"
          fi
        else
          cp -a "${_strategyPathTmp}" "${_strategyPath}"
          _strategyUpdateCount=$((_strategyUpdateCount+1))
          _fsFileExist_ "${_strategyPath}"
        fi
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
      printf '%s\n' "${_strategyJson}" | jq . | sudo tee "${_strategyDir}/${_strategyName}.conf.json" >/dev/null
    fi
  else
    _fsMsg_ "[WARNING] Strategy is not implemented: ${_strategyName}"
  fi
}

_fsDockerAutoupdate_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _file="freqstart.autoupdate.sh"
  local _path="${FS_DIR}"'/'"${_file}"
  local _cronCmd="${_path}"
  local _cronUpdate="0 3 * * *" # update on 3am UTC
  local _projectFile="${1}"
  local _projectAutoupdate='freqstart -b '"${_projectFile}"' -y'
  local _projectAutoupdateMode="${2:-}" # optional: remove
  local _projectAutoupdates=""
  
  _projectAutoupdates=()
  _projectAutoupdates+=("#!/usr/bin/env bash")
  if [[ "$(_fsFile_ "${_path}")" -eq 0 ]]; then
    while read -r; do
    _projectAutoupdates+=("$REPLY")
    done < <(grep -v "${_projectAutoupdate}" "${_path}" | sed "s,#!/usr/bin/env bash,," | sed "/^$/d")
  fi
  
  if [[ ! "${_projectAutoupdateMode}" = "remove" ]]; then
    _projectAutoupdates+=("${_projectAutoupdate}")
    _fsMsg_ "Autoupdate activated for: ${_projectFile}"
  fi
  
  printf '%s\n' "${_projectAutoupdates[@]}" | sudo tee "${_path}" >/dev/null
  sudo chmod +x "${_path}"
  _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
  
  if [[ "${#_projectAutoupdates[@]}" -eq 1 ]]; then
    _fsCrontabRemove_ "${_cronCmd}"
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
  _fsSetupNginx_
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
    
    if [[ "$(_fsCaseConfirmation_ 'Create a new user and transfer files (recommended)?')" -eq 0 ]]; then
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
        _newPath="/home/${_newUser}/${FS_NAME}"

        sudo adduser --gecos "" "${_newUser}"
        sudo usermod -aG sudo "${_newUser}"
        sudo usermod -aG docker "${_newUser}"
        sudo passwd "${_newUser}"
          # no password for sudo
        echo "${_newUser} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers >/dev/null
        
        if [[ ! -d "${_newPath}" ]]; then
					sudo mkdir "${_newPath}"
				fi
        
				sudo cp -R "${_dir}"/* "${_newPath}"
				#sudo chown -R "${_newUser}:${_newUser}" "${_newPath}"
        find "${_newPath}" \( -user "${_currentUser}" -o ! -group "${_currentUser}" \) -print0 | xargs -0 sudo chown "${_newUser}":"${_newUser}" 
        
        sudo rm -f "${_symlink}"
        sudo rm -rf "${_dir}"
        
        if [[ "$(_fsCaseConfirmation_ "Disable \"${_currentUser}\" user (recommended)?")" -eq 0 ]]; then
          sudo usermod -L "${_currentUser}"
        fi
        
        _logout=0
      fi
    fi
  fi
  
  if ! id -nGz "${_currentUser}" | grep -qzxF "docker"; then
    sudo gpasswd -a "${_currentUser}" docker
    _logout=0
  fi
  
  if [[ "${_logout}" -eq 0 ]]; then
    _fsMsg_ 'You have to log out/in to activate the changes!'
      if [[ "$(_fsCaseConfirmation_ 'Logout now?')" -eq 0 ]]; then
          # may find a more elegant way
        sudo reboot
        exit 0
      else
        sudo gpasswd --delete "${_currentUser}" docker
        _fsMsgExit_ '[FATAL] Restart setup to continue!'
      fi
  fi
}

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
        curl -fsSL "https://get.docker.com" -o "${_getDocker}"
        sudo chmod +x "${_getDocker}"
        sudo sh "${_getDocker}"
        rm -f "${_getDocker}"
        sudo apt install -y -q docker-compose
      elif [[ "${_pkg}" = 'chrony' ]]; then
          # ntp setup
        sudo apt-get install -y -q chrony
        sudo systemctl stop chronyd
        sudo timedatectl set-timezone 'UTC'
        sudo systemctl start chronyd
        sudo timedatectl set-ntp true
        sudo systemctl restart chronyd
      elif [[ "${_pkg}" = 'ufw' ]]; then
          # firewall setup
        sudo apt-get install -y -q ufw
        sudo ufw logging medium
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
  
  _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" 2>/dev/null | grep "install ok installed")"

  if [[ -n "${_status}" ]]; then
    echo 0
  else
    echo 1
  fi
}

# PREREQUISITES

_fsDockerPrerequisites_() {
  _fsMsgTitle_ "PREREQUISITES"

  sudo apt-get update

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
  
  timentp="$(timedatectl | grep -o 'NTP service: active')"
  timeutc="$(timedatectl | grep -o '(UTC, +0000)')"
  timesyn="$(timedatectl | grep -o 'System clock synchronized: yes')"
  
  if [[ -n "${timentp}" ]] || [[ -n  "${timeutc}" ]] || [[ -n  "${timesyn}" ]]; then
    echo 0
  else
    echo 1
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
  fi
  
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
    curl -s -L "${_dockerGit}" -o "${_dockerYml}"
    _fsFileExist_ "${_dockerYml}"
  fi
}

# BINANCE-PROXY
# credit: https://github.com/nightshift2k/binance-proxy

_fsSetupBinanceProxy_() {
  local _docker="nightshift2k/binance-proxy:latest"
  local _dockerName="${FS_BINANCE_PROXY}"
  local _setup=1
  local _containerIp=''
  
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
      # binance proxy project file
    _fsFileCreate_ "${FS_BINANCE_PROXY_YML}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    container_name: ${_dockerName}" \
    "    ports:" \
    "      - \"8990-8991\"" \
    "    expose:" \
    "      - \"8990-8991\"" \
    "    tty: true" \
    "    command: >" \
    "      --port-spot=8990" \
    "      --port-futures=8991" \
    "      --verbose"
    
    #sudo ufw allow 8990:8991/tcp
    _fsDockerProject_ "$(basename "${FS_BINANCE_PROXY_YML}")" "compose" "force"
    _containerIp="$(_fsDockerProxyIp_ "${_dockerName}")"
    
      # binance proxy json file
    _fsFileCreate_ "${FS_BINANCE_PROXY_JSON}" \
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
    _fsFileCreate_ "${FS_BINANCE_PROXY_FUTURES_JSON}" \
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
  else
    _fsMsg_ "Skipping..."
  fi
}

# KUCOIN-PROXY
# credit: https://github.com/mikekonan/exchange-proxy

_fsSetupKucoinProxy_() {
  local _docker="mikekonan/exchange-proxy:latest-amd64"
  local _dockerName="${FS_KUCOIN_PROXY}"
  local _setup=1
  local _containerIp=''
    
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
      # kucoin proxy project file
    _fsFileCreate_ "${FS_KUCOIN_PROXY_YML}" \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    container_name: ${_dockerName}" \
    "    ports:" \
    "      - \"8980\"" \
    "    expose:" \
    "      - \"8980\"" \
    "    tty: true" \
    "    command: >" \
    "      -port 8980" \
    "      -verbose 1"
    
    #sudo ufw allow 8980/tcp
    _fsDockerProject_ "$(basename "${FS_KUCOIN_PROXY_YML}")" "compose" "force"
    _containerIp="$(_fsDockerProxyIp_ "${_dockerName}")"
    
      # kucoin proxy json file
    _fsFileCreate_ "${FS_KUCOIN_PROXY_JSON}" \
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
  else
    _fsMsg_ "Skipping..."
  fi
}

# NGINX

_fsSetupNginx_() {
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _nr=''
  local _setup=1
  
  _fsMsgTitle_ "NGINX (Proxy for FreqUI)"
  
  if [[ "$(_fsSetupNginxCheck_)" -eq 1 ]]; then
    _setup=0
  else
    _fsMsg_ "Is already running."
    if [[ "$(_fsCaseConfirmation_ "Skip reconfiguration?")" -eq 1 ]]; then
      _fsCrontabRemove_ "${_cronCmd}"
      _setup=0
    fi
  fi
  
  if [[ "${_setup}" -eq 0 ]];then
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
          break
          ;;
        *)
          _fsCaseInvalid_
          ;;
      esac
    done
    
    _fsSetupNginxRestart_
  else
    _fsMsg_ "Skipping..."
  fi
}

_fsSetupNginxConf_() {
  local _confPath="/etc/nginx/conf.d"
  local _confPathFrequi="${_confPath}/frequi.conf"
  local _confPathNginx="${_confPath}/default.conf"
  local _serverUrl='http://'"${FS_SERVER_WAN}" 
  
  _fsJsonSet_ "${FS_CONFIG}" 'server_wan' "${FS_SERVER_WAN}"
  _fsJsonSet_ "${FS_CONFIG}" 'server_url' "${_serverUrl}"
  _fsSetupPkgs_ "nginx"
  
  _fsFileCreate_ "${_confPathFrequi}" \
  "server {" \
  "    listen ${FS_SERVER_WAN}:80;" \
  "    server_name ${FS_SERVER_WAN};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:9999;" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${FS_SERVER_WAN}:9000-9100;" \
  "    server_name ${FS_SERVER_WAN};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "    }" \
  "}"
  
  if [[ "$(_fsFile_ "${_confPathNginx}")" -eq 0 ]]; then
    sudo mv "${_confPathNginx}" "${_confPathNginx}.disabled"
  fi
  
  sudo rm -f "/etc/nginx/sites-enabled/default"
}

_fsSetupNginxCheck_() {
  if sudo nginx -t 2>&1 | grep -qow "failed"; then
    echo 1
  else
    echo 0
  fi
}

_fsSetupNginxRestart_() {
  if [[ "$(_fsSetupNginxCheck_)" -eq 1 ]]; then
    _fsMsgExit_ "Error in nginx config file. For more info enter: nginx -t"
  fi
  
  sudo /etc/init.d/nginx stop
  sudo pkill -f nginx & wait $!
  sudo /etc/init.d/nginx start
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
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _cronUpdate="0 0 * * *"
  
  while true; do
    read -rp "? Enter your domain (www.example.com): " _serverDomain
    
    if [[ "${_serverDomain}" = "" ]]; then
      _fsCaseEmpty_
    else
      if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_serverDomain}\" correct?")" -eq 0 ]]; then
        if host "${_serverDomain}" 1>/dev/null 2>/dev/null; then
          _serverDomainIp="$(host "${_serverDomain}" | awk '/has address/ { print $4 }')"
        fi
        
        if [[ ! "${_serverDomainIp}" = "${FS_SERVER_WAN}" ]]; then
          _fsMsg_ "The domain \"${_serverDomain}\" does not point to \"${FS_SERVER_WAN}\". Review DNS and try again!"
        else
          _fsJsonSet_ "${FS_CONFIG}" 'server_domain' "${_serverDomain}"
          
          _fsSetupNginxConfSecure_ "letsencrypt"
          _fsSetupNginxCertbot_
          
          _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
          break
        fi
      fi
      _serverDomain=''
    fi
  done
}

_fsSetupNginxCertbot_() {
  local _serverDomain=''
  
  _serverDomain="$(_fsJsonGet_ "${FS_CONFIG}" 'server_domain')"
  [[ -z "${_serverDomain}" ]] && _fsMsgExit_ '[FATAL] Domain is not set.'
  
  _fsSetupPkgs_ certbot python3-certbot-nginx
  sudo certbot --nginx -d "${_serverDomain}"
}

_fsSetupNginxConfSecure_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _mode="${1}"
  local _serverDomain=''
  local _serverUrl=''
  local _confPath="/etc/nginx/conf.d"
  local _confPathNginx="${_confPath}/default.conf"
  local _confPathFrequi="${_confPath}/frequi.conf"
  
  _serverDomain="$(_fsJsonGet_ "${FS_CONFIG}" 'server_domain')"
  if [[ -n "${_serverDomain}" ]]; then
    _serverUrl='https://'"${_serverDomain}"
  else
    _serverUrl='https://'"${FS_SERVER_WAN}"
  fi
  
  _fsJsonSet_ "${FS_CONFIG}" 'server_url' "${_serverUrl}"
  
  sudo rm -f "${_confPathFrequi}"
    # thanks: Blood4rc, Hippocritical
  if [[ "${_mode}" = 'openssl' ]]; then
    _fsFileCreate_ "${_confPathFrequi}" \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;" \
    "    server_name ${FS_SERVER_WAN};" \
    "    return 301 https://\$server_name\$request_uri;" \
    "}" \
    "server {" \
    "    listen 443 ssl;" \
    "    listen [::]:443 ssl;" \
    "    server_name ${FS_SERVER_WAN};" \
    "    " \
    "    include snippets/self-signed.conf;" \
    "    include snippets/ssl-params.conf;" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${FS_SERVER_WAN}:9000-9100 ssl;" \
    "    server_name ${FS_SERVER_WAN};" \
    "    " \
    "    include snippets/self-signed.conf;" \
    "    include snippets/ssl-params.conf;" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}"
  elif [[ "${_mode}" = 'letsencrypt' ]]; then
    _fsFileCreate_ "${_confPathFrequi}" \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;   " \
    "    server_name ${_serverDomain};" \
    "    return 301 https://\$host\$request_uri;" \
    "}" \
    "server {" \
    "    listen 443 ssl http2;" \
    "    listen [::]:443 ssl http2;" \
    "    server_name ${_serverDomain};" \
    "    " \
    "    ssl_certificate /etc/letsencrypt/live/${_serverDomain}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverDomain}/privkey.pem;" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    " \
    "    # Required for LE certificate enrollment using certbot" \
    "    location '/.well-known/acme-challenge' {" \
    "        default_type \"text/plain\";" \
    "        root /var/www/html;" \
    "    }" \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_serverDomain}:9000-9100 ssl http2;" \
    "    server_name ${_serverDomain};" \
    "    " \
    "    ssl_certificate /etc/letsencrypt/live/${_serverDomain}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverDomain}/privkey.pem;" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}"
  fi
  
  [[ "$(_fsFile_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}"'.disabled'
  sudo rm -f /etc/nginx/sites-enabled/default*
}

# FREQUI

_fsSetupFrequi_() {
  local _serverUrl=''
  local _frequiCors=''
  local _frequiName="${FS_NAME}"'_frequi'
  local _setup=1
  local _nr=''
  
  _serverUrl="$(_fsJsonGet_ "${FS_CONFIG}" 'server_url')"
  _frequiCors="$(_fsJsonGet_ "${FS_CONFIG}" 'frequi_cors')"
  
  _fsMsgTitle_ "FREQUI"
  
	if [[ "$(_fsDockerPsName_ "${_frequiName}")" -eq 0 ]]; then
    if [[ -n "${_frequiCors}" ]] && [[ ! "${_serverUrl}" = "${_frequiCors}" ]]; then
      _fsMsg_ "[WARNING] Server URL has changed: ${_frequiCors} -> ${_serverUrl}"
      _fsMsg_ "Update installation..."
      _setup=0
    else
      _fsMsg_ "Is active: ${_frequiCors}"
      if [[ "$(_fsCaseConfirmation_ "Skip update?")" -eq 1 ]]; then
        _setup=0
      fi
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
      _setup=0
    fi
  fi
  
  if [[ "${_setup}" -eq 0 ]];then
    sudo ufw allow "Nginx Full"
    sudo ufw allow 9000:9100/tcp
    sudo ufw allow 9999/tcp
    _frequiCors="${_serverUrl}"
    _fsJsonSet_ "${FS_CONFIG}" 'frequi_cors' "${_frequiCors}"
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
  local _frequiCors=''
  local _setup=1
  
  _frequiCors="$(_fsJsonGet_ "${FS_CONFIG}" "frequi_cors")"
  _frequiJwt="$(_fsJsonGet_ "${FS_FREQUI_JSON}" "jwt_secret_key")"
  _frequiUsername="$(_fsJsonGet_ "${FS_FREQUI_JSON}" "username")"
  _frequiPassword="$(_fsJsonGet_ "${FS_FREQUI_JSON}" "password")"
  
  [[ -z "${_frequiJwt}" ]] && _frequiJwt="$(_fsRandomBase64UrlSafe_ 32)"
  
  if [[ -n "${_frequiUsername}" ]] || [[ -n "${_frequiPassword}" ]]; then
    _fsMsg_ "Login data already found."
    
    if [[ "$(_fsCaseConfirmation_ "Skip generating new login data?")" -eq 1 ]]; then
      _setup=0
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Create \"FreqUI\" login data?")" -eq 0 ]]; then
      _setup=0
      
      if [[ "${FS_OPTS_YES}" -eq 0 ]]; then
        _setup=1
        
        _frequiUsername="$(_fsRandomBase64_ 16)"
        _frequiPassword="$(_fsRandomBase64_ 16)"
      fi
    fi
  fi

  if [[ "${_setup}" = 0 ]]; then
    _fsMsg_ "Create your login data now!"
      # create username
    while true; do
      read -rp 'Enter username: ' _frequiUsername
      
      if [[ -n "${_frequiUsername}" ]]; then
        if [[ "$(_fsCaseConfirmation_ "Is the username correct: ${_frequiUsername}")" -eq 0 ]]; then
          break
        else
          _fsMsg_ "Try again!"
        fi
      fi
    done
      # create password - NON VERBOSE
    while true; do
      _fsMsg_ 'Enter password (ENTRY HIDDEN):'
      read -rs _frequiPassword
      echo
      case ${_frequiPassword} in 
        "")
          _fsCaseEmpty_
          ;;
        *)
          _fsMsg_ 'Enter password again: '
          read -r -s _frequiPasswordCompare
          echo
          if [[ ! "${_frequiPassword}" = "${_frequiPasswordCompare}" ]]; then
            _fsMsg_ "The password does not match. Try again!"
            _frequiPassword=""
            _frequiPasswordCompare=""
            shift
          else
            break
          fi
          ;;
      esac
    done
  fi
    # create frequi json for bots
  if [[ -n "${_frequiUsername}" ]] && [[ -n "${_frequiPassword}" ]]; then
    _fsFileCreate_ "${FS_FREQUI_JSON}" \
    "{" \
    "    \"api_server\": {" \
    "        \"enabled\": true," \
    "        \"listen_ip_address\": \"0.0.0.0\"," \
    "        \"listen_port\": 9999," \
    "        \"verbosity\": \"error\"," \
    "        \"enable_openapi\": false," \
    "        \"jwt_secret_key\": \"${_frequiJwt}\"," \
    "        \"CORS_origins\": [\"${_frequiCors}\"]," \
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
  "networks:" \
  "  freqstart:" \
  "    external: true" \
  "    name: freqstart" \
  "services:" \
  "  ${_frequiName}:" \
  "    image: ${_docker}" \
  "    container_name: ${_frequiName}" \
  "    hostname: ${_frequiName}" \
  "    volumes:" \
  "      - \"./user_data:/freqtrade/user_data\"" \
  "    ports:" \
  "      - \"127.0.0.1:9999:8080\"" \
  "    tty: true" \
  "    command: >" \
  "      trade" \
  "      --logfile /freqtrade/user_data/logs/$(basename "${_frequiServerLog}")" \
  "      --strategy ${_frequiStrategy}" \
  "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_SERVER_JSON}")" \
  "      --config /freqtrade/user_data/$(basename "${FS_FREQUI_JSON}")" \
  "    networks:" \
  "      - freqstart"
  
  _fsDockerProject_ "${FS_FREQUI_YML}" "compose" "force"
}

###
# START

_fsStart_() {
	local _yml="${1:-}"
  local _symlink="${FS_SYMLINK}"
  local _kill="${FS_OPTS_KILL}"
  
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
		_fsUsage_ "Start setup first!"
  fi
  
  _fsIntro_
  
  if [[ "${FS_OPTS_AUTO}" -eq 0 ]] && [[ "${FS_OPTS_KILL}" -eq 0 ]]; then
    _fsUsage_ "Option -a or --auto cannot be used with -k or --kill."
  elif [[ -z "${_yml}" ]]; then
    _fsUsage_ "Setting an \"example.yml\" file with -b or --bot is required."
  else
    if [[ "${_kill}" -eq 0 ]]; then
      _fsDockerProject_ "${_yml}" "kill"
    else
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
	local _frequiCors=''
	local _binanceProxy=''
	local _kucoinProxy=''
  
  printf -- '%s\n' \
  "###" \
  "# FREQSTART: ${FS_VERSION}" \
  "###" >&2
  
	if [[ "$(_fsFile_ "${FS_CONFIG}")" -eq 0 ]]; then
    _serverWan="$(_fsJsonGet_ "${FS_CONFIG}" "server_wan")"
    if [[ -n "${_serverWan}" ]] && [[ ! "${FS_SERVER_WAN}" = "${_serverWan}" ]]; then
      _fsMsgTitle_ '[WARNING] Server WAN has changed ('"${_serverWan}"' -> '"${FS_SERVER_WAN}"'). Run setup again!'
    else
      _serverWan="${FS_SERVER_WAN}"
    fi
    
    _fsDockerProxyIpValidate_ "${FS_BINANCE_PROXY}"
    _fsDockerProxyIpValidate_ "${FS_KUCOIN_PROXY}"
    
    _serverDomain="$(_fsJsonGet_ "${FS_CONFIG}" "server_domain")"
    _serverUrl="$(_fsJsonGet_ "${FS_CONFIG}" "server_url")"
    _frequiCors="$(_fsJsonGet_ "${FS_CONFIG}" "frequi_cors")"
    _binanceProxy="$(_fsJsonGet_ "${FS_CONFIG}" "${FS_BINANCE_PROXY}")"
    _kucoinProxy="$(_fsJsonGet_ "${FS_CONFIG}" "${FS_KUCOIN_PROXY}")"
  fi
  
  _fsFileCreate_ "${FS_CONFIG}" \
  "{" \
  "    \"version\": \"${FS_VERSION}\"," \
  "    \"server_wan\": \"${_serverWan}\"," \
  "    \"server_domain\": \"${_serverDomain}\"," \
  "    \"server_url\": \"${_serverUrl}\"," \
  "    \"frequi_cors\": \"${_frequiCors}\"," \
  "    \"${FS_BINANCE_PROXY}\": \"${_binanceProxy}\"," \
  "    \"${FS_KUCOIN_PROXY}\": \"${_kucoinProxy}\"" \
  "}"
}

_fsStats_() {
	local _ping
	local _memUsed
	local _memTotal
	local _time
    # some handy stats to get you an impression how your server compares to the current possibly best location for binance
	_ping="$(ping -c 1 -w15 api3.binance.com | awk -F '/' 'END {print $5}')"
	_memUsed="$(free -m | awk 'NR==2{print $3}')"
	_memTotal="$(free -m | awk 'NR==2{print $2}')"
	_time="$( (time curl -X GET "https://api.binance.com/api/v3/exchangeInfo?symbol=BNBBTC") 2>&1 > /dev/null \
  | grep -o "real.*s" \
  | sed "s#real$(echo '\t')##" )"
  
  printf -- '%s\n' \
	"###" \
  "# Ping avg. (Binance): ${_ping}ms | Vultr \"Tokyo\" Server avg.: 1.290ms" \
	"# Time to API (Binance): ${_time} | Vultr \"Tokyo\" Server avg.: 0m0.039s" \
	"# Used memory (Server): ${_memUsed}MB  (max. ${_memTotal}MB)" \
	"# Get closer to Binance? Try Vultr \"Tokyo\" Server and get \$100 usage for free:" \
	"# https://www.vultr.com/?ref=9122650-8H" \
	"###" >&2
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
  
  local _file="${1}"; shift
  local _array=("${@}")
  local _fileTmp="${FS_DIR_TMP}"'/'"${_file##*/}"
  
  printf -- '%s\n' "${_array[@]}" | sudo tee "${_fileTmp}" >/dev/null
  
  sudo cp "${_fileTmp}" "${_file}"
  _fsFileExist_ "${_file}"
}

_fsCrontab_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  local _cronJob="${2} ${_cronCmd}"
    # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -
  
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
    _fsMsgExit_ "Cron not set: ${_cronCmd}"
  fi
}

_fsCrontabRemove_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
    # credit: https://stackoverflow.com/a/17975418
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -
    
    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
      _fsMsgExit_ "Cron not removed: ${_cronCmd}"
    fi
  fi
}

_fsCrontabValidate_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
  
  crontab -l 2>/dev/null | grep -q "${_cronCmd}"  && echo 0 || echo 1
}

_fsIsYml_() {
  [[ $# -lt 1 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
	local _path="${FS_DIR}/${1##*/}"
	local _file="${_path##*/}"
	local _fileType="${_file##*.}"
  
	if [[ -n "${_fileType}" ]]; then
    if [[ "${_fileType}" = 'yml' ]]; then
      if [[ "$(_fsFile_ "${_path}")" -eq 0 ]]; then
        echo "${_path}"
      else
        _fsMsgExit_ "File not found: ${_file}"
      fi
    else
      _fsMsgExit_ "File type is not correct!"
    fi
	else
		_fsMsgExit_ "File type is missing!"
	fi
}

_fsJsonGet_() {
  [[ $# -lt 2 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue=''
  
  if [[ "$(_fsFile_ "${_jsonFile}")" -eq 0 ]]; then
    _jsonValue="$(cat "${_jsonFile}" | { grep -o "${_jsonName}\"\?: \"\?.*\"\?" || true; } \
    | sed "s,\",,g" \
    | sed "s,\s,,g" \
    | sed "s#,##g" \
    | sed "s,${_jsonName}:,,")"
    
    if [[ -n "${_jsonValue}" ]]; then
      echo "${_jsonValue}"
    fi
  fi
}

_fsJsonSet_() {
  [[ $# -lt 3 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue="${3}"
  
  _fsFileExist_ "${_jsonFile}"
  
  if grep -qow "\"${_jsonName}\": \".*\"" "${_jsonFile}"; then
    sudo sed -i "s,\"${_jsonName}\": \".*\",\"${_jsonName}\": \"${_jsonValue}\"," "${_jsonFile}"
  elif grep -qow "${_jsonName}: \".*\"" "${_jsonFile}"; then
    sudo sed -i "s,${_jsonName}: \".*\",${_jsonName}: \"${_jsonValue}\"," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": .*")" ]]; then
  #  sed -i "s,\"${_jsonName}\": .*,\"${_jsonName}\": ${_jsonValue}," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "${_jsonName}: .*")" ]]; then
  #  sed -i "s,${_jsonName}: .*,${_jsonName}: ${_jsonValue}," "${_jsonFile}"
  else
    _fsMsgExit_ "Cannot find name: ${_jsonName}"
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
    _status="$(curl -o /dev/null -Isw '%{http_code}' "${_url}")"

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
  
  _string="$(xxd -l"${_length}" -ps /dev/urandom)"
  
  echo "${_string}"
}

_fsRandomBase64_() {
  local _length="${1:-24}"
  local _string=''
  
  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64)"
  
  echo "${_string}"
}

_fsRandomBase64UrlSafe_() {
  local _length="${1:-32}"
  local _string=''
  
  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64 | tr -d = | tr + - | tr / _)"
  
  echo "${_string}"
}

_fsReset_() {
  _fsIntro_
  
  _fsMsgTitle_ '[WARNING] Stopp and remove all containers, networks and images!'
  
  if [[ "$(_fsCaseConfirmation_ "Are you sure you want to continue?")" -eq 0 ]]; then
    sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
    sudo docker network prune
    sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
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

_fsUsage_() {
  local _msg="${1:-}"
  
  if [[ -n "${_msg}" ]]; then
    printf -- '%s\n' \
    "${_msg}" \
    "" >&2
  fi
  
  printf -- '%s\n' \
  "${FS_NAME^^} ${FS_VERSION}" \
  "Freqstart simplifies the use of Freqtrade with Docker. Including a setup guide for Freqtrade," \
  "configurations and FreqUI with a secured SSL proxy for IP or domain. Freqtrade automatically" \
  "installs implemented strategies based on Docker Compose files and detects necessary updates." \
  "" \
  "USAGE" \
  "Setup: ${FS_FILE} [-s | --setup] [-y | --yes]" \
  "Start: ${FS_FILE} [-b | --bot <ARG>] [-a | --auto] [-y | --yes]" \
  "Stop:  ${FS_FILE} [-b | --bot <ARG>] [-k | --kill] [-y | --yes]" \
  "" \
  "OPTIONS" \
  "-s, --setup             Install and update" \
  "-b <ARG>, --bot <ARG>   Start docker project" \
  "-k, --kill              Kill docker project" \
  "-y, --yes               Yes on every confirmation" \
  "-a, --auto              Autoupdate docker project" \
  "--reset                 Stopp and remove all containers, networks and images" >&2
  
  exit 0
}

_fsScriptLock_() {
  local _lockDir="${FS_DIR_TMP}/${FS_NAME}.lock"
  
  if [[ -n "${FS_DIR_TMP}" ]]; then
    if ! sudo mkdir -p "${_lockDir}" 2>/dev/null; then
      _fsMsgExit_ "Unable to acquire script lock: ${_lockDir}"
    fi
  else
    _fsMsgExit_ "Temporary directory is not defined!"
  fi
}

_fsCleanup_() {
  trap - ERR EXIT SIGINT SIGTERM
    # thanks: lsiem
  sudo rm -rf "${FS_DIR_TMP}"
}

_fsErr_() {
    local _error=${?}
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
  local -r _code="${2:-90}"
  
  printf -- '%s\n' \
  "${_msg[*]}" >&2
  
  exit "${_code}"
}

_fsOptions_() {
  local -r _args=("${@}")
  local _opts
  
  _opts=$(getopt --options b:,s,k,a,y,h --long bot:,setup,kill,auto,yes,help,reset -- "${_args[@]}" 2> /dev/null) || {
    _fsUsage_
    _fsMsgExit_ "parsing options"
  }
  
  eval set -- "${_opts}"
  while true; do
    case "${1}" in
      --bot|-b)
        FS_OPTS_BOT=0
        readonly b_arg="${2}"
        shift
        shift
        ;;
      --setup|-s)
        FS_OPTS_SETUP=0
        shift
        ;;
      --kill|-k)
        FS_OPTS_KILL=0
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
        break
        ;;
      --help|-h)
        _fsUsage_
        exit 0
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
elif [[ "${FS_OPTS_BOT}" -eq 0 ]]; then
  _fsStart_ "${b_arg}"
elif [[ "${FS_OPTS_RESET}" -eq 0 ]]; then
  _fsReset_
else
  _fsUsage_
fi

exit 0