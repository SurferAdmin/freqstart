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
FS_DIR=$(dirname "$(readlink --canonicalize-existing "${0}" 2> /dev/null)")
readonly FS_FILE="${0##*/}"

FS_NAME="freqstart"
FS_VERSION='v0.1.4'
FS_SYMLINK="/usr/local/bin/${FS_NAME}"

FS_DIR_TMP="/tmp/${FS_NAME}"
FS_DIR_DOCKER="${FS_DIR}/docker"
FS_DIR_USER_DATA="${FS_DIR}/user_data"
FS_DIR_USER_DATA_STRATEGIES="${FS_DIR_USER_DATA}/strategies"
FS_CONFIG="${FS_DIR}/${FS_NAME}.config.json"
FS_STRATEGIES="${FS_DIR}/${FS_NAME}.strategies.json"

FS_BINANCE_PROXY_JSON="${FS_DIR_USER_DATA}/binance_proxy.json"
FS_BINANCE_PROXY_FUTURES_JSON="${FS_DIR_USER_DATA}/binance_proxy_futures.json"
FS_BINANCE_PROXY_YML="${FS_DIR}/${FS_NAME}_binance_proxy.yml"
FS_KUCOIN_PROXY_JSON="${FS_DIR_USER_DATA}/kucoin_proxy.json"
FS_KUCOIN_PROXY_YML="${FS_DIR}/${FS_NAME}_kucoin_proxy.yml"

FS_FREQUI_JSON="${FS_DIR_USER_DATA}/frequi.json"
FS_FREQUI_SERVER_JSON="${FS_DIR_USER_DATA}/frequi_server.json"
FS_FREQUI_YML="${FS_DIR}/${FS_NAME}_frequi.yml"

FS_SERVER_WAN="$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)"
FS_SERVER_LAN="$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | grep -v ${FS_SERVER_WAN} | head -1)"
FS_SERVER_URL="http://${FS_SERVER_WAN}"
FS_HASH="$(xxd -l8 -ps /dev/urandom)"

FS_OPTS_BOT=1
FS_OPTS_SETUP=1
FS_OPTS_AUTO=1
FS_OPTS_KILL=1
FS_OPTS_YES=1

trap _fsCleanup_ EXIT
trap '_fsErr_ "${FUNCNAME:-.}" ${LINENO}' ERR

###
# DOCKER

_fsDockerVarsPath_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerDir="${FS_DIR_DOCKER}"
	local _dockerName
  local _dockerTag
	local _dockerPath

	_dockerName="$(_fsDockerVarsName_ "${_docker}")"
	_dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
	_dockerPath="${_dockerDir}/${_dockerName}_${_dockerTag}.docker"

	echo "${_dockerPath}"
}

_fsDockerVarsRepo_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerRepo="${_docker%:*}"
	
	echo "${_dockerRepo}"
}

_fsDockerVarsCompare_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerRepo=""
	local _dockerTag=""
	local _dockerVersionLocal=""
	local _dockerVersionHub=""

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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerRepo
	local _dockerName

	_dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	_dockerName="${FS_NAME}"'_'"$(echo ${_dockerRepo} | sed "s,\/,_,g" | sed "s,\-,_,g")"

	echo "${_dockerName}"
}

_fsDockerVarsTag_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerTag="${_docker##*:}"

	if [[ "${_dockerTag}" = "${_docker}" ]]; then
		_dockerTag="latest"
	fi

	echo "${_dockerTag}"
}

_fsDockerVersionLocal_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerVersionLocal
  
	if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
		_dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerRepo}:${_dockerTag}" \
		| sed 's/.*@//')"
    
    [[ -n "${_dockerVersionLocal}" ]] && echo "${_dockerVersionLocal}"
	fi
}

_fsDockerVersionHub_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerName
	local _dockerManifest
	local _dockerManifestHash="${FS_HASH}"
  local _acceptM
  local _acceptML
  local _token
  local _status
  local _dockerVersionHub

	_dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
	_dockerManifest="${FS_DIR_TMP}/${_dockerName}_${_dockerTag}_${_dockerManifestHash}.json"

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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerImage="${1}"
  local _dockerDir="${FS_DIR_DOCKER}"
  local _dockerRepo
  local _dockerTag
  local _dockerName
  local _dockerCompare
  local _dockerPath
  local _dockerStatus=2
  local _dockerVersionLocal

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
    [[ ! -d "${_dockerDir}" ]] && sudo mkdir -p "${_dockerDir}"

    sudo rm -f "${_dockerPath}"
    sudo docker save -o "${_dockerPath}" "${_dockerRepo}:${_dockerTag}"
    [[ "$(_fsFile_ "${_dockerPath}")" -eq 1 ]] && _fsMsg_ "[WARNING] Cannot create backup for: ${_dockerRepo}:${_dockerTag}"
    
    echo "${_dockerVersionLocal}"
  else
    _fsMsgExit_ "Image not found: ${_dockerRepo}:${_dockerTag}"
  fi
}

_fsDockerImageInstalled_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
  local _dockerImages
  
  _dockerImages="$(docker images -q "${_dockerRepo}:${_dockerTag}" 2> /dev/null)"

	if [[ -n "${_dockerImages}" ]]; then
		echo 0
	else
		echo 1
	fi
}

_fsDockerPsName_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _dockerName="${1}"
  local _dockerMode="${2:-}" # optional: all
  local _dockerPs
  local _dockerPsAll
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerId="${1}"
	local _dockerName

	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
	if [[ -n "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

_fsDockerIpInternal_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _docker="${1}"
	local _dockerIp

  _dockerIp="$(sudo docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${_docker})"
	if [[ -n "${_dockerIp}" ]]; then
		echo "${_dockerIp}"
	fi
}

_fsDockerStop_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

	local _dockerName="${1}"

  sudo docker update --restart=no "${_dockerName}" >/dev/null
  sudo docker stop "${_dockerName}" >/dev/null
  sudo docker rm -f "${_dockerName}" >/dev/null
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}" "all")" -eq 0 ]]; then
    _fsMsgExit_ "[FATAL] Cannot remove container: ${_dockerName}"
  fi
}

_fsDockerProjectImages_() {
	local _path="${1}"
	local _ymlImages
	local _ymlImagesDeduped
	local _ymlImage

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
	local _ymlPath="${1}"
	local _dockerPorts=""
	local _dockerPort=""
	local _dockerPortDuplicate=""
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
	local _ymlPath="${1}"
	local _strategies
	local _strategiesDeduped
	local _strategy
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
  local _dir="${FS_DIR}"
	local _ymlPath="${1}"
  local _configs
  local _configsDeduped
	local _config
	local _configNew
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
      _configPath="${_dir}/${_config}"
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _projectDir="${FS_DIR}"
	local _projectPath="${1}"
	local _projectMode="${2}" # compose, validate, kill
	local _projectForce="${3:-}" # optional: force
	local _projectAuto="${FS_OPTS_AUTO}"
  local _projectCronCmd
  local _projectCronUpdate
	local _projectFile
	local _projectFileName
  local _projectName
  local _projectImages
  local _projectStrategies
  local _projectConfigs
  local _projectPorts
  local _projectContainers
  local _projectContainer
  local _procjectJson
  local _containerCmd
  local _containerRunning
  local _containerRestart=1
  local _containerName
  local _containerConfigs
  local _containerStrategy
  local _containerStrategyUpdate
  local _containerJson
  local _containerJsonInner
  local _containerConfPath
  local _containerCount=0
  local _strategyUpdate
  local _strategyDir
  local _strategyPath
  local _error=0

  _projectPath="$(_fsIsYml_ "${_projectPath}")"

  if [[ -n "${_projectPath}" ]]; then
    _projectFile="${_projectPath##*/}"
    _projectFileName="${_projectFile%.*}"
    _projectName="${_projectFileName//\-/\_}"
    #_projectName="${FS_NAME}"
    _procjectJson=()
    _projectContainers=()
    _containerConfPath="${_projectDir}/${_projectFileName}.conf.json"

    if [[ "${_projectMode}" = "compose" ]]; then
      _fsMsgTitle_ "Validate project: ${_projectFile}"
        # set restart to no
      sed -i "s,restart\:.*,restart\: \"no\",g" "${_projectPath}"

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

      if [[ "${_error}" -eq 0 ]]; then
        cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --no-recreate
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      _fsCdown_ 30 "for any errors..."
    elif [[ "${_projectMode}" = "kill" ]]; then
      _fsMsgTitle_ "Kill project: ${_projectFile}"
    fi

    if [[ "${_error}" -eq 0 ]]; then
      while read -r; do
        _projectContainers+=( "$REPLY" )
      done < <(cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" ps -q)

      for _projectContainer in "${_projectContainers[@]}"; do
        _containerName="$(_fsDockerId2Name_ "${_projectContainer}")"
        if [[ "${_projectMode}" = "compose" ]]; then
          _fsMsgTitle_ "Validate container: ${_containerName}"
          _containerJsonInner=""
          _strategyUpdate=""
          _containerStrategyUpdate=""

            # get container command
          _containerCmd="$(sudo docker inspect --format="{{.Config.Cmd}}" "${_projectContainer}" \
          | sed "s,\[, ,g" \
          | sed "s,\], ,g" \
          | sed "s,\",,g" \
          | sed "s,\=, ,g" \
          | sed "s,\/freqtrade\/,,g")"

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
              if [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
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
          if [[ ! "${_containerImageVersion}" = "${_dockerImageVersion}" ]]; then
            _fsMsg_ "Docker image version is outdated: ${_containerName}"
            _containerRestart=0
          fi

            # stop container if restart is necessary
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart container?")" -eq 0 ]]; then
              if [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
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

            # increment container count
          _containerCount=$((_containerCount+1))
        elif [[ "${_projectMode}" = "validate" ]]; then
          _containerRunning="$(_fsDockerPsName_ "${_containerName}")"

          if [[ "${_containerRunning}" -eq 0 ]]; then
            sudo docker update --restart=on-failure "${_containerName}" >/dev/null
            _fsMsg_ "Container is active: ${_containerName}"
          else
            _fsMsg_ "[ERROR] Container is not active: ${_containerName}"
            _fsDockerStop_ "${_containerName}"
            _error=$((_error+1))
          fi
        elif [[ "${_projectMode}" = "kill" ]]; then
          if [[ "$(_fsCaseConfirmation_ "Kill container?")" -eq 0 ]]; then
            _fsDockerStop_ "${_containerName}"
          fi
        fi
      done
    fi
    
    if [[ "${_projectMode}" = "compose" ]]; then
      if [[ "${_error}" -eq 0 ]]; then
        if (( ${#_procjectJson[@]} )); then
          printf '%s\n' "${_procjectJson[@]}" | jq . > "${_containerConfPath}"
        else
          sudo rm -f "${_containerConfPath}"
        fi
        
        if [[ "${_projectForce}" = "force" ]]; then
          cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up -d --force-recreate
        else
          cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up -d --no-recreate
        fi

        _fsDockerProject_ "${_projectPath}" "validate"
      else
        _fsMsg_ "[ERROR] Cannot start: ${_projectFile}"
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      if [[ "${_projectAuto}" -eq 0 ]]; then
        _fsDockerAutoupdate_ "${_projectFile}"
      fi
    elif [[ "${_projectMode}" = "kill" ]]; then
      _fsDockerAutoupdate_ "${_projectFile}" "remove"

      if (( ! ${#_projectContainers[@]} )); then
        _fsMsg_ "No container active in project: ${_ymlFile}"
      fi
    fi
    
  fi
}

_fsDockerStrategy_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _strategyName="${1}"
  local _strategyFile
  local _strategyFileNew
  local _strategyUpdate
  local _strategyUpdateCount=0
  local _strategyFileType
  local _strategyFileTypeName="unknown"
  local _strategyTmp="${FS_DIR_TMP}/${_strategyName}_${FS_HASH}"
  local _strategyDir="${FS_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
  local _strategyUrls
  local _strategyUrlsDeduped
  local _strategyUrl
  local _strategyPath
  local _strategyPathTmp
  local _fsStrategies="${FS_STRATEGIES}"
  local _strategyJson

  if [[ "$(_fsFile_ "${_fsStrategies}")" -eq 1 ]]; then
    printf '%s\n' \
    "{" \
    "  \"DoesNothingStrategy\": [" \
    "    \"https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/master/user_data/strategies/berlinguyinca/DoesNothingStrategy.py\"" \
    "  ]" \
    "}" \
    > "${_fsStrategies}"
    _fsFileExist_ "${_fsStrategies}"
  fi
  
  _strategyUrls=()
  while read -r; do
  _strategyUrls+=( "$REPLY" )
  done < <(jq -r ".${_strategyName}[]?" "${_fsStrategies}")

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
      printf '%s\n' "${_strategyJson}" | jq . > "${_strategyDir}/${_strategyName}.conf.json"
    fi
  else
    _fsMsg_ "[WARNING] Strategy is not implemented: ${_strategyName}"
  fi
}

_fsDockerAutoupdate_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _dir="${FS_DIR}"
  local _file="freqstart.autoupdate.sh"
  local _path="${_dir}/${_file}"
  local _cronCmd="${_path}"
  local _cronUpdate="0 3 * * *" # update on 3am UTC
  local _projectFile="${1}"
  local _projectAutoupdate="freqstart -b ${_projectFile} -y"
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

  printf '%s\n' "${_projectAutoupdates[@]}" > "${_path}"
  sudo chmod +x "${_path}"
  _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
    
  if [[ "${#_projectAutoupdates[@]}" -eq 1 ]]; then
    _fsCrontabRemove_ "${_cronCmd}"
  fi
}

_fsDockerKillImages_() {
  _fsDockerKillContainers_
	sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
}

_fsDockerKillContainers_() {
	sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
}

###
# SETUP

_fsSetup_() {
  local _symlink="${FS_SYMLINK}"
  local _symlinkSource="${FS_DIR}/${FS_NAME}.sh"

  _fsIntro_
  _fsDockerPrerequisites_
  _fsSetupNtp_
  _fsSetupFreqtrade_
  _fsSetupNginx_
  _fsSetupFrequi_
  _fsSetupBinanceProxy_
  _fsSetupKucoinProxy_
  _fsSetupExampleBot_
  _fsStats_

	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
    sudo rm -f "${_symlink}"
		sudo ln -sfn "${_symlinkSource}" "${_symlink}"
	fi
	
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
		_fsMsgExit_ "Cannot create symlink: ${_symlink}"
	fi
}

_fsSetupPkgs_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _pkgs=("$@")
  local _pkg
  local _status
  local _getDocker="${FS_DIR}/get-docker.sh"

  for _pkg in "${_pkgs[@]}"; do
    if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
      _fsMsg_ "Already installed: ${_pkg}"
    else
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _pkg="${1}"
  local _status=""
  
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
  local timentp
  local timeutc
  local timesyn

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
  local _dir="${FS_DIR}"
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerYml="${_dir}/${FS_NAME}_setup.yml"
  local _dockerImageStatus
  local _dirUserData="${FS_DIR_USER_DATA}"
  local _configKey
  local _configSecret
  local _configName
  local _configFile
  local _configFileTmp
  local _configFileBackup

  _fsMsgTitle_ "FREQTRADE"

  if [[ ! -d "${_dirUserData}" ]]; then
    _fsSetupFreqtradeYml_
    
    cd "${_dir}" && \
    docker-compose --file "$(basename "${_dockerYml}")" run --rm freqtrade create-userdir --userdir "$(basename "${_dirUserData}")"
    if [[ ! -d "${_dirUserData}" ]]; then
      _fsMsgExit_ "Directory cannot be created: ${_dirUserData}"
    else
      _fsMsg_ "Directory created: ${_dirUserData}"
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
          _configName="config"
        ;;
        *)
          _configName="${_configName%.*}"

          if [[ "$(_fsIsAlphaDash_ "${_configName}")" -eq 1 ]]; then
            _fsMsg_ "Only alpha-numeric or dash or underscore characters are allowed!"
            _configName=""
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
    
    _configFile="${_dirUserData}/${_configName}.json"
    _configFileTmp="${_dirUserData}/${_configName}.tmp.json"
    _configFileBackup="${_dirUserData}/${_configName}.bak.json"

    if [[ "$(_fsFile_ "${_configFile}")" -eq 0 ]]; then
      _fsMsg_ "The config already exist: $(basename "${_configFile}")"
      if [[ "$(_fsCaseConfirmation_ "Replace the existing config file?")" -eq 1 ]]; then
        _configName=""
        rm -f "${_dockerYml}"
      fi
    fi

    if [[ -n "${_configName}" ]] && [[ -d "${_dirUserData}" ]]; then
      _fsSetupFreqtradeYml_
      rm -f "${_configFileTmp}"
      
      cd "${_dir}" && \
      docker-compose --file "$(basename "${_dockerYml}")" \
      run --rm freqtrade new-config --config "$(basename "${_dirUserData}")/$(basename "${_configFileTmp}")"
      
      rm -f "${_dockerYml}"

      _fsFileExist_ "${_configFileTmp}"

      if [[ "$(_fsCaseConfirmation_ "Enter your exchange api KEY and SECRET now? (recommended)")" -eq 0 ]]; then
        while true; do
          _fsMsg_ "Enter your KEY for exchange api (ENTRY HIDDEN):"
          read -rs _configKey
          echo
          case ${_configKey} in 
            "")
              _fsCaseEmpty_
              ;;
            *)
              _fsJsonSet_ "${_configFileTmp}" "key" "${_configKey}"
              _fsMsg_ "KEY is set in: ${_configFile}"
              break
              ;;
          esac
        done

        while true; do
          _fsMsg_ 'Enter your SECRET for exchange api (ENTRY HIDDEN):'
          read -rs _configSecret
          echo
          case ${_configSecret} in 
            "")
              _fsCaseEmpty_
              ;;
            *)
              _fsJsonSet_ "${_configFileTmp}" "secret" "${_configSecret}"
              _fsMsg_ "SECRET is set in: ${_configFile}"
              break
              ;;
          esac
        done
      else
        _fsMsg_ "Enter your exchange api KEY and SECRET to: ${_configFile}"
      fi
      
      cp -a "${_configFileTmp}" "${_configFile}"
      cp -a "${_configFileTmp}" "${_configFileBackup}"

      rm -f "${_configFileTmp}"
    fi
  fi
}

_fsSetupFreqtradeYml_() {
  local _dir="${FS_DIR}"
  local _dockerYml="${_dir}/${FS_NAME}_setup.yml"
  local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"

  if [[ "$(_fsFile_ "${_dockerYml}")" -eq 1 ]]; then
    curl -s -L "${_dockerGit}" -o "${_dockerYml}"
    _fsFileExist_ "${_dockerYml}"
  fi
}

# BINANCE-PROXY
# credit: https://github.com/nightshift2k/binance-proxy

_fsSetupBinanceProxy_() {
  local _json="${FS_BINANCE_PROXY_JSON}"
  local _jsonFutures="${FS_BINANCE_PROXY_FUTURES_JSON}"
  local _yml="${FS_BINANCE_PROXY_YML}"
  local _docker="nightshift2k/binance-proxy:latest"
  local _dockerName
  local _dockerIP
  local _setup=1
  local _serverUrl="${FS_SERVER_URL}"
  local _serverLan="${FS_SERVER_LAN}"

  _dockerName="$(_fsDockerVarsName_ "${_docker}")"

  _fsMsgTitle_ "PROXY FOR BINANCE (Ports: 8090-8091/tcp)"

  if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    _fsMsg_ "Is already running."
    if [[ "$(_fsCaseConfirmation_ "Update installation?")" -eq 0 ]]; then
      _setup=0
    fi
  elif [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
    _setup=0
  fi

  if [[ "${_setup}" -eq 0 ]]; then
    printf -- '%s\n' \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    restart: no" \
    "    container_name: ${_dockerName}" \
    "    hostname: ${_dockerName}" \
    "    ports:" \
    "      - \"127.0.0.1:8990-8991:8090-8091\"" \
    "    tty: true" \
    "    command: >" \
    "      --verbose" \
    > "${_yml}"
    _fsFileExist_ "${_yml}"
    
    printf -- '%s\n' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"binance\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${_serverLan}:8990/api/v3\"," \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false" \
    "        }" \
    "    }" \
    "}" \
    > "${_json}"
    _fsFileExist_ "${_json}"

    printf -- '%s\n' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"binance\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"http://${_serverLan}:8991/api/v3\"," \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false" \
    "        }" \
    "    }" \
    "}" \
    > "${_jsonFutures}"
    _fsFileExist_ "${_jsonFutures}"

    sudo ufw allow 8990:8991/tcp
    _fsDockerProject_ "$(basename "${_yml}")" "compose" "force"
  else
    _fsMsg_ "Skipping..."
  fi
}

# KUCOIN-PROXY
# credit: https://github.com/mikekonan/exchange-proxy

_fsSetupKucoinProxy_() {
  local _json="${FS_KUCOIN_PROXY_JSON}"
  local _yml="${FS_KUCOIN_PROXY_YML}"
  local _docker="mikekonan/exchange-proxy:latest-amd64"
  local _dockerName
  local _setup=1
  local _serverUrl="${FS_SERVER_URL}"

  _dockerName="$(_fsDockerVarsName_ "${_docker}")"

  _fsMsgTitle_ "PROXY FOR KUCOIN (Ports: 8180/tcp)"

  if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    _fsMsg_ "Is already running."
    if [[ "$(_fsCaseConfirmation_ "Update installation?")" -eq 0 ]]; then
      _setup=0
    fi
  elif [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
    _setup=0
  fi

  if [[ "${_setup}" -eq 0 ]]; then
    printf -- '%s\n' \
    "{" \
    "    \"exchange\": {" \
    "        \"name\": \"kucoin\"," \
    "        \"ccxt_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"timeout\": 60000," \
    "            \"urls\": {" \
    "                \"api\": {" \
    "                    \"public\": \"${_serverUrl}:8980/kucoin\"," \
    "                    \"private\": \"${_serverUrl}:8980/kucoin\"" \
    "                }" \
    "            }" \
    "        }," \
    "        \"ccxt_async_config\": {" \
    "            \"enableRateLimit\": false," \
    "            \"timeout\": 60000" \
    "        }" \
    "    }" \
    "}" \
    > "${_json}"
    _fsFileExist_ "${_json}"

    printf -- '%s\n' \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${_dockerName}:" \
    "    image: ${_docker}" \
    "    restart: no" \
    "    container_name: ${_dockerName}" \
    "    ports:" \
    "      - \"127.0.0.1:8980:8080\"" \
    "    tty: true" \
    "    command: >" \
    "      -verbose 1" \
    > "${_yml}"
    _fsFileExist_ "${_yml}"

    sudo ufw allow 8980/tcp
    _fsDockerProject_ "$(basename "${_yml}")" "compose" "force"
  else
    _fsMsg_ "Skipping..."
  fi
}

# NGINX

_fsSetupNginx_() {
  local _yesForce="${FS_OPTS_YES}"
  local _nr=""
  local _setup=1

  _fsMsgTitle_ "NGINX PROXY"

  if [[ "$(_fsSetupNginxCheck_)" -eq 1 ]]; then
    _setup=0
  else
    _fsMsg_ "Is already running."
    if [[ "$(_fsCaseConfirmation_ "Skip reconfiguration?")" -eq 1 ]]; then
      _setup=0
    fi
  fi

  if [[ "${_setup}" -eq 0 ]];then
    _fsSetupNginxNossl_

    while true; do
      printf -- '%s\n' \
      "? Secure the connection to FreqUI?" \
      "  1) Yes, I want to use an IP with SSL (openssl)" \
      "  2) Yes, I want to use a domain with SSL (truecrypt)" \
      "  3) No, I dont want to use SSL (not recommended)" >&2

      if [[ "${_yesForce}" -eq 1 ]]; then
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

_fsSetupNginxNossl_() {
  local _confPath="/etc/nginx/conf.d"
  local _confPathFrequi="${_confPath}/frequi.conf"
  local _confPathNginx="${_confPath}/default.conf"
  local _serverWan="${FS_SERVER_WAN}"
  local _serverLan="${FS_SERVER_LAN}"

  FS_SERVER_URL="http://${_serverWan}"

  _fsSetupPkgs_ "nginx"
  printf '%s\n' \
  "server {" \
  "    listen 80;" \
  "    server_name ${_serverWan};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:9999;" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${_serverWan}:9000-9100;" \
  "    server_name ${_serverWan};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "    }" \
  "}" \
  "server {" \
  "    listen ${_serverLan}:8990-8991;" \
  "    listen ${_serverLan}:8980;" \
  "    server_name ${_serverLan};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "    }" \
  "}" \
  > "${_confPathFrequi}"

  _fsFileExist_ "${_confPathFrequi}"
  [[ "$(_fsFile_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}.disabled"

  sudo rm -f "/etc/nginx/sites-enabled/default"
  sudo ufw allow "Nginx Full"
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

  printf '%s\n' \
  "ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;" \
  "ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;" \
  > '/etc/nginx/snippets/self-signed.conf'
  
  printf '%s\n' \
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
  "add_header X-XSS-Protection \"1; mode=block\";" \
  > '/etc/nginx/snippets/ssl-params.conf'
}

_setupNginxLetsencrypt_() {
  local _domain
  local _domainIp
  local _serverWan="${FS_SERVER_WAN}"
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _cronUpdate="0 0 * * *"
  
  while true; do
    read -rp "? Enter your domain (www.example.com): " _domain
    
    if [[ "${_domain}" = "" ]]; then
      _fsCaseEmpty_
    else
      if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_domain}\" correct?")" -eq 0 ]]; then
        _domainIp="$(host "${_domain}" | awk '/has address/ { print $4 ; exit }')"

        if [[ ! "${_domainIp}" = "${_serverWan}" ]]; then
          _fsMsg_ "The domain \"${_domain}\" does not point to \"${_serverWan}\". Review DNS and try again!"
        else
          _fsSetupNginxConfSecure_ "letsencrypt" "${_domain}"
          _fsSetupNginxCertbot_ "${_domain}"

          _fsCrontab_ "${_cronCmd}" "${_cronUpdate}"
          break
        fi
      fi
      _domain=""
    fi
  done
}

_fsSetupNginxCertbot_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _domain="${1}"
  _fsSetupPkgs_ certbot python3-certbot-nginx
  sudo certbot --nginx -d "${_domain}"
}

_fsSetupNginxConfSecure_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _mode="${1}"
  local _domain="${2}"
  local _confPath="/etc/nginx/conf.d"
  local _confPathNginx="${_confPath}/default.conf"
  local _confPathFrequi="${_confPath}/frequi.conf"
  local _serverWan="${FS_SERVER_WAN}"
  local _serverLan="${FS_SERVER_LAN}"
  
  if [[ -n "${_domain}" ]]; then
    _serverWan="${_domain}"
  fi

  FS_SERVER_URL="https://${_serverWan}"

  sudo rm -f "${_confPathFrequi}"
    # thanks: Blood4rc, Hippocritical
  if [[ "${_mode}" = 'openssl' ]]; then
    printf '%s\n' \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;" \
    "    server_name ${_serverWan};" \
    "    return 301 https://\$server_name\$request_uri;" \
    "}" \
    "server {" \
    "    listen 443 ssl;" \
    "    listen [::]:443 ssl;" \
    "    server_name ${_serverWan};" \
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
    "    listen ${_serverWan}:9000-9100 ssl;" \
    "    server_name ${_serverWan};" \
    "    " \
    "    include snippets/self-signed.conf;" \
    "    include snippets/ssl-params.conf;" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_serverLan}:8990-8991;" \
    "    listen ${_serverLan}:8980;" \
    "    server_name ${_serverLan};" \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    > "${_confPathFrequi}"
  elif [[ "${_mode}" = 'letsencrypt' ]]; then
    printf '%s\n' \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;   " \
    "    server_name ${_serverWan};" \
    "    return 301 https://\$host\$request_uri;" \
    "}" \
    "server {" \
    "    listen 443 ssl http2;" \
    "    listen [::]:443 ssl http2;" \
    "    server_name ${_serverWan};" \
    "    " \
    "    ssl_certificate /etc/letsencrypt/live/${_serverWan}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverWan}/privkey.pem;" \
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
    "    listen ${_serverWan}:9000-9100 ssl http2;" \
    "    server_name ${_serverWan};" \
    "    " \
    "    ssl_certificate /etc/letsencrypt/live/${_serverWan}/fullchain.pem;" \
    "    ssl_certificate_key /etc/letsencrypt/live/${_serverWan}/privkey.pem;" \
    "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
    "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_serverLan}:8990-8991;" \
    "    listen ${_serverLan}:8980;" \
    "    server_name ${_serverLan};" \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    > "${_confPathFrequi}"
  fi
  
  _fsFileExist_ "${_confPathFrequi}"
  [[ "$(_fsFile_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}"'.disabled'
  sudo rm -f /etc/nginx/sites-enabled/default*
}

# FREQUI

_fsSetupFrequi_() {
  local _serverUrl="${FS_SERVER_URL}"
  local _frequiYml="${FS_FREQUI_YML}"
  local _nr=""
  local _setup=1
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerName

  _dockerName="$(_fsDockerVarsName_ "${_docker}")"

  _fsMsgTitle_ "FREQUI"

	if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    _fsMsg_ "Is active: ${_serverUrl}"
    if [[ "$(_fsCaseConfirmation_ "Skip reconfiguration?")" -eq 0 ]]; then
      _fsDockerProject_ "${_frequiYml}" "compose"
    else
      _setup=0
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Install now?")" -eq 0 ]]; then
      _setup=0
    fi
  fi

  if [[ "${_setup}" -eq 0 ]];then
    sudo ufw allow 9000:9100/tcp
    sudo ufw allow 9999/tcp 
    _fsSetupFrequiJson_
    _fsSetupFrequiCompose_
  fi
}

_fsSetupFrequiJson_() {
  local _frequiJson="${FS_FREQUI_JSON}"
  local _frequiJwt
  local _frequiUsername
  local _frequiPassword
  local _frequiPasswordCompare
  local _frequiTmpUsername
  local _frequiTmpPassword
  local _frequiCors="${FS_SERVER_URL}"
  local _yesForce="${FS_OPTS_YES}"
  local _setup=1

  _frequiJwt="$(_fsJsonGet_ "${_frequiJson}" "jwt_secret_key")"
  _frequiUsername="$(_fsJsonGet_ "${_frequiJson}" "username")"
  _frequiPassword="$(_fsJsonGet_ "${_frequiJson}" "password")"

  [[ -z "${_frequiJwt}" ]] && _frequiJwt="$(_fsRandomBase64UrlSafe_)"

  if [[ -n "${_frequiUsername}" ]] || [[ -n "${_frequiPassword}" ]]; then
    _fsMsg_ "Login data for \"FreqUI\" already found."
    
    if [[ "$(_fsCaseConfirmation_ "Skip generating new login data?")" -eq 1 ]]; then
      _setup=0
    fi
  else
    if [[ "$(_fsCaseConfirmation_ "Create \"FreqUI\" login data?")" -eq 0 ]]; then
      _setup=0
      
      if [[ "${_yesForce}" -eq 0 ]]; then
        _setup=1

        _frequiUsername="$(_fsRandomBase64_ 16)"
        _frequiPassword="$(_fsRandomBase64_ 16)"
      fi
    fi
  fi

  if [[ "${_setup}" = 0 ]]; then
    _fsMsg_ "Create your login data for \"FreqUI\" now!"
      # create username
    while true; do
      read -rp 'Enter username: ' _frequiUsername

      if [[ -n "${_frequiUsername}" ]]; then
        if [[ "$(_fsCaseConfirmation_ "Is the username \"${_frequiUsername}\" correct?")" -eq 0 ]]; then
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
    printf '%s\n' \
    "{" \
    "    \"api_server\": {" \
    "        \"enabled\": true," \
    "        \"listen_ip_address\": \"0.0.0.0\"," \
    "        \"listen_port\": 8080," \
    "        \"verbosity\": \"error\"," \
    "        \"enable_openapi\": false," \
    "        \"jwt_secret_key\": \"${_frequiJwt}\"," \
    "        \"CORS_origins\": [\"${_frequiCors}\"]," \
    "        \"username\": \"${_frequiUsername}\"," \
    "        \"password\": \"${_frequiPassword}\"" \
    "    }" \
    "}" \
    > "${_frequiJson}"

    _fsFileExist_ "${_frequiJson}"
  fi
}

_fsSetupFrequiCompose_() {
  local _serverUrl="${FS_SERVER_URL}"
  local _fsConfig="${FS_CONFIG}"
  local _frequiYml="${FS_FREQUI_YML}"
  local _frequiJson="${FS_FREQUI_JSON}"
  local _frequiServerJson="${FS_FREQUI_SERVER_JSON}"
  local _frequiServerLog
  local _frequiStrategy='DoesNothingStrategy'
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerName

  _dockerName="$(_fsDockerVarsName_ "${_docker}")"
  _frequiServerLog="${FS_DIR_USER_DATA}/logs/${_dockerName}.log"

  _fsJsonSet_ "${_fsConfig}" 'server_url' "${_serverUrl}"

  printf '%s\n' \
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
  "}" \
  > "${_frequiServerJson}"
  _fsFileExist_ "${_frequiServerJson}"

  printf -- '%s\n' \
  "---" \
  "version: '3'" \
  "services:" \
  "  ${_dockerName}:" \
  "    image: ${_docker}" \
  "    restart: unless-stopped" \
  "    container_name: ${_dockerName}" \
  "    volumes:" \
  "      - \"./user_data:/freqtrade/user_data\"" \
  "    ports:" \
  "      - \"127.0.0.1:9999:8080\"" \
  "    tty: true" \
  "    " \
  "    command: >" \
  "      trade" \
  "      --logfile /freqtrade/user_data/logs/$(basename "${_frequiServerLog}")" \
  "      --strategy ${_frequiStrategy}" \
  "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
  "      --config /freqtrade/user_data/$(basename "${_frequiServerJson}")" \
  "      --config /freqtrade/user_data/$(basename "${_frequiJson}")" \
  > "${_frequiYml}"
  _fsFileExist_ "${_frequiYml}"
  
  [[ "$(_fsFile_ "${_frequiServerLog}")" -eq 0 ]] &&  rm -f "${_frequiServerLog}"
  
  _fsDockerProject_ "${_frequiYml}" "compose" "force"
}

# EXAMPLE BOT

_fsSetupExampleBot_() {
  local _userData="${FS_DIR_USER_DATA}"
  local _botExampleName="${FS_NAME}_example"
  local _botExampleYml="${FS_DIR}/${_botExampleName}.yml"
  local _botExampleConfig
  local _botExampleConfigName
  local _frequiJson
  local _binanceProxyJson
  local _botExampleExchange
  local _botExampleCurrency
  local _botExampleKey
  local _botExampleSecret
  local _botExamplePairlist
  local _botExampleLog="${FS_DIR_USER_DATA}/logs/${FS_NAME}_example.log"
  local _setup=1
  local _error=0

  _fsMsgTitle_ "EXAMPLE BOT (for NostalgiaForInfinityX)"

  _frequiJson="$(basename "${FS_FREQUI_JSON}")"
  _binanceProxyJson="$(basename "${FS_BINANCE_PROXY_JSON}")"

  if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" -eq 0 ]]; then
    _fsMsg_ "Skipping..."
  else
    while true; do
      _fsMsg_ "What is the name of your config file?"
      read -rp " (filename) " _botExampleConfigName
      case ${_botExampleConfigName} in
        "")
          _fsCaseEmpty_
          ;;
        *)
          _botExampleConfigName="${_botExampleConfigName%.*}"
          if [[ "$(_fsIsAlphaDash_ "${_botExampleConfigName}")" -eq 1 ]]; then
            _fsMsg_ "Only alpha-numeric or dash or underscore characters are allowed!"
            _botExampleConfigName=""
          else
            _botExampleConfig="${_userData}/${_botExampleConfigName}.json"
            if [[ ! -f "${_botExampleConfig}" ]]; then
              _fsMsg_ "Config file does not exist!"
              _botExampleConfigName=""
              _botExampleConfig=""
              shift
            else
              break
            fi
          fi
          ;;
      esac
    done
  
    _botExampleExchange="$(_fsJsonGet_ "${_botExampleConfig}" 'name')"
    _botExampleCurrency="$(_fsJsonGet_ "${_botExampleConfig}" 'stake_currency')"
    _botExampleKey="$(_fsJsonGet_ "${_botExampleConfig}" 'key')"
    _botExampleSecret="$(_fsJsonGet_ "${_botExampleConfig}" 'secret')"
  
    if [[ -z "${_botExampleKey}" || -z "${_botExampleSecret}" ]]; then
      _fsMsg_ 'Your exchange api KEY and/or SECRET is missing.'
      _error=1
    fi
    
    if [[ "${_botExampleExchange}" != 'binance' ]]; then
      _fsMsg_ 'Only "Binance" is supported for example bot.'
      _error=1
    fi

    if [[ "${_botExampleCurrency}" == 'USDT' ]]; then
      _botExamplePairlist='pairlist-volume-binance-busd.json'
    elif [[ "${_botExampleCurrency}" == 'BUSD' ]]; then
      _botExamplePairlist='pairlist-volume-binance-busd.json'
    else
      _fsMsg_ 'Only USDT and BUSD pairlist are supported.'
      _error=1
    fi
  
    if [[ "${_error}" -eq 0 ]]; then
      printf -- '%s\n' \
      "---" \
      "version: '3'" \
      "services:" \
      "  ${_botExampleName}:" \
      "    image: freqtradeorg/freqtrade:stable" \
      "    restart: \"unless-stopped\"" \
      "    container_name: ${_botExampleName}" \
      "    volumes:" \
      "      - \"./user_data:/freqtrade/user_data\"" \
      "    ports:" \
      "      - \"127.0.0.1:9001:8080\"" \
      "    tty: true" \
      "    " \
      "    command: >" \
      "      trade" \
      "      --dry-run" \
      "      --db-url sqlite:////freqtrade/user_data/${_botExampleName}.sqlite" \
      "      --logfile /freqtrade/user_data/logs/${_botExampleName}.log" \
      "      --strategy NostalgiaForInfinityX" \
      "      --strategy-path /freqtrade/user_data/strategies/NostalgiaForInfinityX" \
      "      --config /freqtrade/user_data/$(basename "${_botExampleConfig}")" \
      "      --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/exampleconfig.json" \
      "      --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/${_botExamplePairlist}" \
      "      --config /freqtrade/user_data/strategies/NostalgiaForInfinityX/blacklist-binance.json" \
      "      --config /freqtrade/user_data/${_frequiJson}" \
      "      --config /freqtrade/user_data/${_binanceProxyJson}" \
      > "${_botExampleYml}"
      _fsFileExist_ "${_botExampleYml}"
      
      [[ "$(_fsFile_ "${_botExampleLog}")" -eq 0 ]] &&  rm -f "${_botExampleLog}"

      _fsMsg_ "1) The docker path is different from the real path and starts with \"/freqtrade\"."
      _fsMsg_ "2) Add your exchange api KEY and SECRET to: \"exampleconfig_secret.json\""
      _fsMsg_ "3) Change port number \"9001\" to an unused port between 9000-9100 in \"${_botExampleYml}\" file."
      _fsMsg_ "Run example bot with: ${FS_NAME} -b $(basename "${_botExampleYml}")"
    else
      _fsMsg_ "Too many errors. Cannot create example bot!"
    fi
  fi
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
  local _fsConfig="${FS_CONFIG}"
  local _dir="${FS_DIR}"
  local _fsVersion="${FS_VERSION}"
	local _serverUrl

	if [[ "$(_fsFile_ "${_fsConfig}")" -eq 0 ]]; then
    _serverUrl="$(_fsJsonGet_ "${_fsConfig}" "server_url")"
    if [[ -n "${_serverUrl}" ]]; then
      FS_SERVER_URL="${_serverUrl}"
    fi
  fi

  printf '%s\n' \
  "{" \
  "    \"version\": \"${_fsVersion}\"" \
  "    \"server_url\": \"${_serverUrl}\"" \
  "}" \
  > "${_fsConfig}"
  _fsFileExist_ "${_fsConfig}"

  printf -- '%s\n' \
  "###" \
  "# FREQSTART: ${_fsVersion}" \
  "# SERVER WAN: ${FS_SERVER_WAN}" \
  "# SERVER LAN: ${FS_SERVER_LAN}" \
  "# SERVER URL: ${FS_SERVER_URL}" \
  "###" >&2
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

_fsCrontab_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _cronCmd="${1}"
  local _cronJob="${2} ${_cronCmd}"
    # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -

  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    _fsMsg_ "Cron set: ${_cronCmd}"
  else
    _fsMsgExit_ "Cron not set: ${_cronCmd}"
  fi
}

_fsCrontabRemove_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _cronCmd="${1}"
    # credit: https://stackoverflow.com/a/17975418
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -

    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
      _fsMsg_ "Cron removed: ${_cronCmd}"
    else
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _dir="${FS_DIR}"
	local _path="${_dir}/${1##*/}"
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue=""

  if [[ "$(_fsFile_ "${_jsonFile}")" -eq 0 ]]; then
    _jsonValue="$(grep -o "${_jsonName}\"\?: \"\?.*\"\?" "${_jsonFile}" \
    | sed "s,\",,g" \
    | sed "s,\s,,g" \
    | sed "s#,##g" \
    | sed "s,${_jsonName}:,,")"

    [[ -n "${_jsonValue}" ]] && echo "${_jsonValue}"
  fi
}

_fsJsonSet_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue="${3}"

  _fsFileExist_ "${_jsonFile}"
  
  if grep -qow "\"${_jsonName}\": \".*\"" "${_jsonFile}"; then
    sed -i "s,\"${_jsonName}\": \".*\",\"${_jsonName}\": \"${_jsonValue}\"," "${_jsonFile}"
  elif grep -qow "${_jsonName}: \".*\"" "${_jsonFile}"; then
    sed -i "s,${_jsonName}: \".*\",${_jsonName}: \"${_jsonValue}\"," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": .*")" ]]; then
  #  sed -i "s,\"${_jsonName}\": .*,\"${_jsonName}\": ${_jsonValue}," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "${_jsonName}: .*")" ]]; then
  #  sed -i "s,${_jsonName}: .*,${_jsonName}: ${_jsonValue}," "${_jsonFile}"
  else
    _fsMsgExit_ "Cannot find name: ${_jsonName}"
  fi
}

_fsCaseConfirmation_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _question="${1}"
  local _yesForce="${FS_OPTS_YES}"
  local _yesNo

  if [[ "${_yesForce}" -eq 0 ]]; then
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
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  local _url="${1}"
    # credit: https://stackoverflow.com/a/55267709
  local _regex="^(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$"
  local _status=""

  if [[ "${_url}" =~ $_regex ]]; then
      # credit: https://stackoverflow.com/a/41875657
    _status="$(curl -o /dev/null -Isw '%{http_code}' "${_url}")"

    if [[ "${_status}" = "200" ]]; then
      echo 0
    else
      echo 1
    fi
  else
    _fsMsgExit_ "Url is not valid: ${_url}"
  fi
}

_fsCdown_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

  _secs="${1}"; shift; _text=("$@")
    
  while [[ "${_secs}" -gt -1 ]]; do
    if [[ "${_secs}" -gt 0 ]]; then
      printf '\r\033[K< Waiting '"${_secs}"' seconds '"${_text[*]}" >&2
      sleep 0.5
      printf '\r\033[K> Waiting '"${_secs}"' seconds '"${_text[*]}" >&2
      sleep 0.5
    else
      printf '\r\033[K' >&2
    fi
    : $((_secs--))
  done
}

_fsIsAlphaDash_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
  local _string="${1}"
  local _regex='^[[:alnum:]_-]+$'
  
  if [[ ${_string} =~ $_regex ]]; then
    echo 0
  else
    echo 1
  fi
}

_fsDedupeArray_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"
  
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
  local _string

  _string="$(xxd -l"${_length}" -ps /dev/urandom)"

  echo "${_string}"
}

_fsRandomBase64_() {
  local _length="${1:-24}"
  local _string

  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64)"

  echo "${_string}"
}

_fsRandomBase64UrlSafe_() {
  local _length="${1:-32}"
  local _string

  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64 | tr -d = | tr + - | tr / _)"

  echo "${_string}"
}

_fsIsSymlink_() {
  [[ $# == 0 ]] && _fsMsgExit_ "Missing required argument to ${FUNCNAME[0]}"

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
    _fsMsg_ "${_msg}"
    _fsMsg_ ""
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
  "-a, --auto              Autoupdate docker project" >&2
  
  exit 0
}

_fsScriptLock_() {
  local _tmpDir="${FS_DIR_TMP}"
  local _lockDir="${_tmpDir}/${FS_NAME}.lock"

  if [[ -n "${_tmpDir}" ]]; then
    if ! sudo mkdir -p "${_lockDir}" 2>/dev/null; then
      _fsMsgExit_ "Unable to acquire script lock: ${_lockDir}"
    fi
  else
    _fsMsgExit_ "Temporary directory is not defined!"
  fi
}

_fsCleanup_() {
  trap - ERR EXIT SIGINT SIGTERM
  rm -rf "${FS_DIR_TMP}"
}

_fsErr_() {
    local _error=${?}
    printf -- '%s\n' "Error in ${FS_FILE} in function ${1} on line ${2}" >&2
    exit ${_error}
}

_fsMsg_() {
  local -r _msg=("${@}")
  printf -- '%s\n' \
  "  ${_msg[@]}" >&2
}

_fsMsgTitle_() {
  local -r _msg=("${@}")
  printf -- '%s\n' \
  "- ${_msg[@]}" >&2
}

_fsMsgExit_() {
  local -r _msg="${1}"
  local -r _code="${2:-90}"
  
  printf -- '%s\n' \
  "${_msg}" >&2

  exit "${_code}"
}

_fsOptions_() {
  local -r _args=("${@}")
  local _opts

  _opts=$(getopt --options b:,s,k,a,y,h --long bot:,setup,kill,auto,yes,help -- "${_args[@]}" 2> /dev/null) || {
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
      --help|-h)
        _fsUsage_
        exit 0
        shift
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

#_fsDockerKillContainers_
#_fsDockerKillImages_
_fsScriptLock_
_fsOptions_ "${@}"

if [[ ${FS_OPTS_SETUP} -eq 0 ]]; then
  _fsSetup_
elif [[ ${FS_OPTS_BOT} -eq 0 ]]; then
  _fsStart_ "${b_arg}"
else
  _fsUsage_
fi

exit 0