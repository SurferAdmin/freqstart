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
# Based on a template by BASH3 Boilerplate v2.4.1
# http://bash3boilerplate.sh/#authors
#
# The MIT License (MIT)
# Copyright (c) 2013 Kevin van Zonneveld and contributors
#
# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
#set -o xtrace

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  __i_am_main_script="0" # false

  if [[ "${__usage+x}" ]]; then
    if [[ "${BASH_SOURCE[1]}" = "${0}" ]]; then
      __i_am_main_script="1" # true
    fi

    __b3bp_external_usage="true"
    __b3bp_tmp_source_idx=1
  fi
else
  __i_am_main_script="1" # true
  [[ "${__usage+x}" ]] && unset -v __usage
  [[ "${__helptext+x}" ]] && unset -v __helptext
fi

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")"
__base="$(basename "${__file}" .sh)"
# shellcheck disable=SC2034,SC2015
__invocation="$(printf %q "${__file}")$( (($#)) && printf ' %q' "$@" || true)"

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

# FREQSTART - variables
ENV_DIR="${__dir}"

ENV_FS="freqstart"
ENV_FS_VERSION='v0.0.1'
ENV_FS_SYMLINK="/user/local/bin/${ENV_FS}"
ENV_FS_CONFIG="${ENV_DIR}/${ENV_FS}.config.json"
ENV_FS_STRATEGIES="${ENV_DIR}/${ENV_FS}.strategies.json"

ENV_DIR_USER_DATA="${ENV_DIR}/user_data"
ENV_DIR_USER_DATA_STRATEGIES="${ENV_DIR_USER_DATA}/strategies"
ENV_DIR_DOCKER="${ENV_DIR}/docker"
ENV_DIR_TMP="/tmp/${ENV_FS}"

ENV_BINANCE_PROXY="${ENV_DIR_USER_DATA}"'/binance_proxy.json'

ENV_FREQUI_JSON="${ENV_DIR_USER_DATA}/frequi.json"
ENV_FREQUI_SERVER_JSON="${ENV_DIR_USER_DATA}/frequi_server.json"
ENV_FREQUI_YML="${ENV_DIR}/${ENV_FS}_frequi.yml"

ENV_SERVER_IP="$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)"
ENV_SERVER_URL=""
ENV_INODE_SUM="$(ls -ali / | sed '2!d' | awk {'print $1'})"
ENV_HASH="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')"
ENV_YES="false"
ENV_MODE="false"

### Functions
##############################################################################

function __b3bp_log () {
  local log_level="${1}"
  shift

  # shellcheck disable=SC2034
  local color_debug="\\x1b[35m"
  # shellcheck disable=SC2034
  local color_info="\\x1b[32m"
  # shellcheck disable=SC2034
  #local color_notice="\\x1b[34m"
  local color_notice="\\x1b[36m"
  # shellcheck disable=SC2034
  local color_warning="\\x1b[33m"
  # shellcheck disable=SC2034
  local color_error="\\x1b[31m"
  # shellcheck disable=SC2034
  local color_critical="\\x1b[1;31m"
  # shellcheck disable=SC2034
  local color_alert="\\x1b[1;37;41m"
  # shellcheck disable=SC2034
  local color_emergency="\\x1b[1;4;5;37;41m"

  local colorvar="color_${log_level}"

  local color="${!colorvar:-${color_error}}"
  local color_reset="\\x1b[0m"

  if [[ "${NO_COLOR:-}" = "true" ]] || { [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]]; } || [[ ! -t 2 ]]; then
    if [[ "${NO_COLOR:-}" != "false" ]]; then
      # Don't use colors on pipes or non-recognized terminals
      color=""; color_reset=""
    fi
  fi

  # all remaining arguments are to be printed
  local log_line=""

  while IFS=$'\n' read -r log_line; do
    echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" 1>&2
  done <<< "${@:-}"
}

function emergency () {                                __b3bp_log emergency "${@}"; exit 1; }
function alert ()     { [[ "${LOG_LEVEL:-0}" -ge 1 ]] && __b3bp_log alert "${@}"; true; }
function critical ()  { [[ "${LOG_LEVEL:-0}" -ge 2 ]] && __b3bp_log critical "${@}"; true; }
function error ()     { [[ "${LOG_LEVEL:-0}" -ge 3 ]] && __b3bp_log error "${@}"; true; }
function warning ()   { [[ "${LOG_LEVEL:-0}" -ge 4 ]] && __b3bp_log warning "${@}"; true; }
function notice ()    { [[ "${LOG_LEVEL:-0}" -ge 5 ]] && __b3bp_log notice "${@}"; true; }
function info ()      { [[ "${LOG_LEVEL:-0}" -ge 6 ]] && __b3bp_log info "${@}"; true; }
function debug ()     { [[ "${LOG_LEVEL:-0}" -ge 7 ]] && __b3bp_log debug "${@}"; true; }

function help () {
  echo "" 1>&2
  echo " ${*}" 1>&2
  echo "" 1>&2
  echo "  ${__usage:-No usage available}" 1>&2
  echo "" 1>&2

  if [[ "${__helptext:-}" ]]; then
    echo " ${__helptext}" 1>&2
    echo "" 1>&2
  fi

  exit 1
}

### FREQSTART - utilities
##############################################################################


function _fsIntro_() {
    local _fsConfig="${ENV_FS_CONFIG}"
    local _fsVersion="${ENV_FS_VERSION}"
    local _serverIp="${ENV_SERVER_IP}"
    local _inodeSum="${ENV_INODE_SUM}"
	local _serverUrl="$(_fsJsonGet_ "${_fsConfig}" 'server_url')"    

    info '###'
    info '# FREQSTART: '"${_fsVersion}"
    info '# Server ip: '"${_serverIp}"
    if [[ ! -z "${_serverUrl}" ]]; then
        info "# Server url: ${_serverUrl}"
    else
        info "# Server url: not set"
    fi
    # credit: https://stackoverflow.com/a/51688023
    if [[ "${_inodeSum}" = '2' ]]; then
        info '# Docker: not inside a container'
    else
        warning '# Docker: inside a container'
    fi
    info '###'

    printf '%s\n' \
    "{" \
    "    \"version\": \"${_fsVersion}\"" \
    "    \"server_url\": \"${_serverUrl}\"" \
    "}" \
    > "${_fsConfig}"

	if [[ ! -f "${_fsConfig}" ]]; then
		emergency "Cannot create \"$(basename "${_fsConfig}")\" file." && exit 1
	fi
}

function _fsStats_() {
	# some handy stats to get you an impression how your server compares to the current possibly best location for binance
	local _ping="$(ping -c 1 -w15 api3.binance.com | awk -F '/' 'END {print $5}')"
	local _memUsed="$(free -m | awk 'NR==2{print $3}')"
	local _memTotal="$(free -m | awk 'NR==2{print $2}')"
	local _time="$((time curl -X GET "https://api.binance.com/api/v3/exchangeInfo?symbol=BNBBTC") 2>&1 > /dev/null \
		| grep -o "real.*s" \
		| sed "s#real$(echo '\t')##")"

	info "###"
    info '# Ping avg. (Binance): '"${_ping}"'ms | Vultr "Tokyo" Server avg.: 1.290ms'
	info '# Time to API (Binance): '"${_time}"' | Vultr "Tokyo" Server avg.: 0m0.039s'
	info '# Used memory (Server): '"${_memUsed}"'MB  (max. '"${_memTotal}"'MB)'
	info '# Get closer to Binance? Try Vultr "Tokyo" Server and get $100 usage for free:'
	notice '# https://www.vultr.com/?ref=9122650-8H'
	info "###"
}

function _fsAcquireScriptLock_() {
    local _lockDir=""
    local _tmpDir="${ENV_DIR_TMP:-/tmp}"

    if [[ ! -z "${_tmpDir}" ]]; then
        if [[ "${1:-}" == 'system' ]]; then
            _lockDir="${_tmpDir}/$(basename "$0").lock"
        else
            _lockDir="${_tmpDir}/$(basename "$0").${UID}.lock"
        fi

        if command mkdir -p "${_lockDir}" 2>/dev/null; then
            readonly SCRIPT_LOCK="${_lockDir}"
            debug "Acquired script lock: ${SCRIPT_LOCK}"
        else
            if declare -f "__b3bp_cleanup_before_exit" &>/dev/null; then
                emergency "Unable to acquire script lock: ${_lockDir}"
                emergency "If you trust the script isn't running, delete the lock dir"
            else
                printf "%s\n" "ERROR: Could not acquire script lock. If you trust the script isn't running, delete: ${_lockDir}"
                exit 1
            fi

        fi
    else
        emergency "Temporary directory is not defined!" && exit 1
    fi
}

function _fsJsonGet_() {
    [[ $# == 0 ]] && debug "Missing required argument to ${FUNCNAME[0]}"

    local _jsonFile="${1:-}"
    local _jsonName="${2}"
    local _jsonValue=""
    
    if [[ -f "${_jsonFile}" ]]; then
    
        _jsonValue="$(cat "${_jsonFile}" \
        | grep -o "${_jsonName}\"\?: \".*\"" \
        | sed "s,\",,g" \
        | sed "s,\s,,g" \
        | sed "s,${_jsonName}:,,")"

        if [[ ! -z "${_jsonValue}" ]]; then
            echo "${_jsonValue}"
        else
            debug "\"${_jsonName}\" empty value."
            echo
        fi
    else
        debug '"'"${_jsonFile}"'" file does not exist.'
        echo
    fi
    
    exit 1
}

function _fsJsonSet_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && return 1

    local _jsonFile="${1}"
    local _jsonName="${2}"
    local _jsonValue="${3}"

    # IMPORTANT - do not echo value for non-verbose inputs
    if [[ -f "${_jsonFile}" ]]; then
        if [[ ! -z "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": \".*\"")" ]]; then
                sed -i "s,\"${_jsonName}\": \".*\",\"${_jsonName}\": \"${_jsonValue}\"," "${_jsonFile}"
        elif [[ ! -z "$(cat "${_jsonFile}" | grep -o "${_jsonName}: \".*\"")" ]]; then
                sed -i "s,${_jsonName}: \".*\",${_jsonName}: \"${_jsonValue}\"," "${_jsonFile}"
        else
            emergency '"'"${_jsonFile}"'" can not find "'"${_jsonName}"'" name.' && exit 1
        fi
        
        if [[ ! "$(_fsJsonGet_ "${_jsonFile}" "${_jsonName}")" = "${_jsonValue}" ]]; then
            emergency '"'"${_jsonFile}"'" can not set value for "'"${_jsonName}"'" name.' && exit 1
        fi
    else
        emergency '"'"${_jsonFile}"'" file does not exist.' && exit 1
    fi
}

function _fsCaseConfirmation_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _yesNo=""
    
    notice "${1}"
    
    if [[ "${ENV_YES}" = "true" ]]; then
        debug "Forcing confirmation with '-y' flag set"
        echo "true"
    else
        while true; do
            read -p " (y/n) " _yesNo
            
            case "${_yesNo}" in
                [Yy]*)
                    echo "true"
                    break
                    ;;
                [Nn]*)
                    echo "false"
                    break
                    ;;
                *)
                    warning "Please answer yes or no."
                    ;;
            esac
        done
    fi
}

function _fsCaseInvalid_() {
    warning 'Invalid response!'
}

function _fsCaseEmpty_() {
    input 'Input can not be empty!'
}

function _fsUrlValidate_() {
    local _url="${1}"
    # credit: https://stackoverflow.com/a/55267709
    local _regex="^(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$"
    local _status=""

    if [[ "${_url}" =~ $_regex ]]; then
        # credit: https://stackoverflow.com/a/41875657
        _status="$(curl -o /dev/null -Isw '%{http_code}' "${_url}")"
        
        if [[ "${_status}" = '200' ]]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

function _fsCdown_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    _secs="${1}"; shift; _text="${@}"
        
    while [[ "${_secs}" -gt -1 ]]; do
        if [[ "${_secs}" -gt 0 ]]; then
            printf '\r\033[KWaiting '"${_secs}"' seconds '"${_text}"
            sleep 1
        else
            printf '\r\033[K'
        fi
        : $((_secs--))
    done
}

function _fsIsAlphaDash_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    local _re='^[[:alnum:]_-]+$'
    
    if [[ ${1} =~ ${_re} ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function _fsDedupeArray_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    declare -A _tmpArray
    declare -a _uniqueArray
    local _i
    
    for _i in "$@"; do
        { [[ -z ${_i} || -n ${_tmpArray[${_i}]:-} ]]; } && continue
        _uniqueArray+=("${_i}") && _tmpArray[${_i}]=x
    done
    
    printf '%s\n' "${_uniqueArray[@]}"
}

function _fsDate_() {
    echo "$(date +%y%m%d%H)"
}

function _fsHash_() {
    local _fsHash="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')"
    echo "${_fsHash}"
}

function _fsPasswd_() {
    local _fsPasswd="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 ; echo '')"
    echo "${_fsPasswd}"
}

function _fsSecret_() {
    local _fsSecret="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32 ; echo '')"
    echo "${_fsSecret}"
}

function _fsSymlink_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _symlink="${1}"
	# credit: https://stackoverflow.com/a/36180056
	if [ -L "${_symlink}" ] ; then
		if [ -e "${_symlink}" ] ; then
			echo "true"
		else
			sudo rm -f "${_symlink}"
            echo "false"
		fi
	elif [ -e "${_symlink}" ] ; then
		sudo rm -f "${_symlink}"
        echo "false"
	else
        echo "true"
	fi
}


### FREQSTART - docker
##############################################################################

function _fsDockerVarsPath_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerDir="${ENV_DIR_DOCKER}"
	local _dockerName="$(_fsDockerVarsName_ "${_docker}")"
	local _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
	local _dockerPath="${_dockerDir}/${_dockerName}_${_dockerTag}.docker"

	echo "${_dockerPath}"
}

function _fsDockerVarsRepo_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo="${_docker%:*}"
	
	echo "${_dockerRepo}"
}

function _fsDockerVarsVersion_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	local _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
	local _dockerVersion="$(_fsDockerVersionCompare_ "${_dockerRepo}" "${_dockerTag}")"
    
	echo "${_dockerVersion}"
}

function _fsDockerVarsName_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo=$(_fsDockerVarsRepo_ "${_docker}")
	local _dockerName="${ENV_FS}_$(echo "${_dockerRepo}" | sed 's,\/,_,')"
	echo "${_dockerName}"
}

function _fsDockerVarsTag_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerTag="${_docker##*:}"

	if [[ "${_dockerTag}" == "${_docker}" ]]; then
		_dockerTag='latest'
	fi

	echo "${_dockerTag}"
}

function _fsDockerManifest_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
	local _dockerManifestTmp="${ENV_DIR_TMP}/${_dockerName}_${_dockerTag}_${ENV_HASH}.json"

	if [[ ! -f "${_dockerManifestTmp}" ]]; then
		# credit: https://stackoverflow.com/a/64309017
		local acceptM="application/vnd.docker.distribution.manifest.v2+json"
		local acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
		local token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${_dockerRepo}:pull" \
			| jq -r '.token')"
		curl -H "Accept: ${acceptM}" \
			-H "Accept: ${acceptML}" \
			-H "Authorization: Bearer $token" \
			-o "${_dockerManifestTmp}" \
			-I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}"
		if [[ -f "${_dockerManifestTmp}" ]] && [[ ! -z "$(echo | cat "${_dockerManifestTmp}" | grep -o '200 OK')" ]]; then
			echo "${_dockerManifestTmp}"
		fi
	elif [[ ! -z "$(cat "${_dockerManifestTmp}" | grep -o '200 OK')" ]]; then
		echo "${_dockerManifestTmp}"
	fi
}

function _fsDockerInspectImage_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
		
	if [[ -n "$(docker inspect --type=image "${_dockerRepo}":"${_dockerTag}" > /dev/null 2>&1)" ]]; then
		echo "true"
	else
		echo "false"
	fi
}

function _fsDockerInspectPort_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _ports="${@}"
	local _portsUnique=''
	local _portsUsed=''
	local _port=''
	local _portSeen=''
	local _portUsed=''
	local _error=''

	for _port in "${_ports[@]}"; do
		if [[ "${_port##*.}" == 'yml' ]]; then
			if [[ -f "${_port}" ]]; then
				readarray -t _ports < <(grep 'ports:' "${_port}" -A 1 \
					| grep -o -E '[0-9]{4}.*' \
					| sed 's,",,g' \
					| sed 's,:.*,,')

				# credit: https://stackoverflow.com/a/22055411
				_portsUnique=$(printf '%s\n' "${_ports[@]}" \
					| awk '!($0 in _portSeen){_portSeen[$0];c++} END {print c}')

				if (( _portsUnique != "${#_ports[@]}" )); then
					_error '"'$(echo $(printf '%s\n' "${_ports[@]}" \
					| awk '!($0 in _portSeen){_portSeen[$0];next} 1') \
					| sed 's# #", "#')'" duplicate ports found in "'$(basename "${_port}")'".'
					
					_error='true'
				fi
				
				break
			else
				warning "\"$(basename "${_ports}")\" file does not exist."
                _error='true'
			fi
		fi
	done

	readarray -t _portsUsed < <(docker ps -q \
	| xargs -I {} docker port {} \
	| sed 's,.*->,,' \
	| grep -o -E '[0-9]{4}.*')

	# alternative: docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}} {{$p}} -> {{(index $conf 0).HostPort}} {{end}}' $INSTANCE_ID
	#printf '%s ' "${_portsUsed[@]}"; printf '\n'

	for _portUsed in "${_portsUsed[@]}"; do
		for _port in "${_ports[@]}"; do
			# credit: https://stackoverflow.com/a/32107419
			if [[ ! "${_port}" =~ ^[0-9]+$ ]]; then
				emergency ' "'"${_port}"'" port is not a number.' && exit 1
			fi
			
			if [[ ! "${_portUsed}" =~ ^[0-9]+$ ]]; then
				emergency '"'"${_portUsed}"'" used port is not a number.' && exit 1
			fi
		
			if [[ "${_portUsed}" == "${_port}" ]]; then
				error "\"${_port}\" is already blocked."
				_error='true'
			fi
		done
	done

	if [[ "${_error}" == 'true' ]]; then
		echo "false"
	else
		echo "true"
	fi
}

function _fsDockerVersionCompare_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerVersion=""
	local _dockerVersionLocal=""
	
	# local version
	if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
		_dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerRepo}":"${_dockerTag}" \
		| sed 's/.*@//')"
	fi
	
	# docker version
	if [[ "$(_fsDockerManifest_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
		_dockerVersion="$(_fsJsonGet_ "${_fsDockerManifest_}" "etag")"
	fi
	
	# compare versions
	if [[ "${_dockerVersion}" = "" ]]; then
		echo 'unkown'
	else
		if [[ "${_dockerVersion}" = "${_dockerVersionLocal}" ]]; then
			echo 'equal'
		else
			echo 'greater'
		fi
	fi
}

function _fsDockerImage_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
    local _dockerDir="${ENV_DIR_DOCKER}"
    local _dockerRepo="$(_fsDockerVarsPath_ "${_docker}")"
    local _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
    local _dockerName="$(_fsDockerVarsName_ "${_docker}")"
    local _dockerVersion="$(_fsDockerVarsVersion_ "${_docker}")"

	if [[ ! -d "${_dockerDir}" ]]; then mkdir -p "${_dockerDir}"; fi
	
	if [[ "${_dockerVersion}" = "greater" ]]; then
        if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
			# update from docker hub

            warning '"'"${_dockerName}"':'"${_dockerTag}"'" image update found.'
            
            if [[ "$(_fsCaseConfirmation_ "Do you want to update now?")" = "true" ]]; then
                echo
                sudo docker pull "${_dockerRepo}"':'"${ENV_DOCKER_ARR[[_dockerTag]}"
                echo
                
                # make backup from local repository
                if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
                    sudo rm -f "${_dockerPath}"
                    sudo docker save -o "${_dockerPath}" "${_dockerRepo}"':'"${_dockerTag}"
                    
                    if [[ -f "${_dockerPath}" ]]; then
                        notice '"'"${_dockerName}"':'"${_dockerTag}"'" backup image created.'
                    fi
                    
                    notice '"'"${_dockerName}"':'"${_dockerTag}"'" image updated and installed.' && echo "update"
                else
                    emergency '"'"${_dockerName}"':'"${_dockerTag}"'" image could not be installed.' && exit 1
                fi
            else
                warning '"'"${_dockerName}"':'"${_dockerTag}"'" skipping image update...' && echo "install"
            fi
		else
			# install from docker hub
			echo
			sudo docker pull "${_dockerRepo}"':'"${_dockerTag}"
			echo
            
			# make backup from local repository
            if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
				sudo docker save -o "${_dockerPath}" "${_dockerRepo}"':'"${_dockerTag}"
                
				if [[ -f "${_dockerPath}" ]]; then
					debug '"'"${_dockerRepo}"':'"${_dockerTag}"'" docker backup image created.'
				fi
                
				notice '"'"${_dockerRepo}"':'"${_dockerTag}"'" docker image installed.' && echo "install"
			else
				emergency '"'"${_dockerRepo}"':'"${_dockerTag}"'" could not be installed.' && exit 1
			fi
		fi
	elif [[ "${_dockerVersion}" = "unknown" ]]; then
		warning '"'"${_dockerRepo}"':'"${_dockerTag}"'" can not load online image version.'
        
		# if docker is not reachable try to load local backup
        if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
			notice '"'"${_dockerRepo}"':'"${_dockerTag}"'" image is installed but can not be verified.' && echo "install"
		elif [[ -f "${_dockerPath}" ]]; then
			sudo docker load -i "${_dockerPath}"
            
            if [[ "$(_fsDockerInspectImage_ "${_dockerRepo}" "${_dockerTag}")" = "true" ]]; then
				notice '"'"${_dockerRepo}"':'"${_dockerTag}"'" backup image is installed but can not be verified.' && echo "install"
			fi
		else
			emergency '"'"${_dockerRepo}"':'"${_dockerTag}"'" can not install backup image.' && exit 1
		fi
	elif [[ "${_dockerVersion}" = "equal" ]]; then
		notice '"'"${_dockerRepo}"':'"${_dockerTag}"'" current image already installed.' && echo "install"
	fi
}

function _fsDockerPs_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _value="${1}"
	local _all="${2:-}"
    local _dockerPs=""
	
	if [[ "${_all}" == 'all' ]]; then
		_dockerPs="$(sudo docker ps -a | grep -ow "${_value}")"
	else
		_dockerPs="$(sudo docker ps | grep -ow "${_value}")"
	fi

	if [[ ! -z "${_dockerPs}" ]]; then
		echo "true"
	else
		echo "false"
	fi
}

function _fsDockerId2Name_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerName=""

	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed 's,/,,')"
	
	if [[ ! -z "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

function _fsDockerId2Port_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerName=""

	_dockerName="$(sudo docker inspect --format="{{.Port}}" "${_dockerId}")"
	
	if [[ ! -z "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

function _fsDockerStop_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	_dockerName="${1}"

	if [[ "$(_fsDockerPs_ "${_dockerName}")" = "true" ]]; then
		sudo docker stop "${_dockerName}" && \
		sudo docker rm "${_dockerName}"
	fi
}

function _fsDockerRun_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerRm="${3:-}"
	local _dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"

	if [[ "$(_fsDockerImage_ "${_dockerRepo}"':'"${_dockerTag}")" = "update" ]]; then
		_fsDockerStop_ "${_dockerName}"
	fi

	if [[ "$(_fsDockerPs_ "${_dockerName}")" = "false" ]]; then
		if [[ "${_dockerRm}" == 'rm' ]]; then
			cd "${_dir}" && \
				docker run --rm -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		else
			cd "${_dir}" && \
				docker run -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		fi
		
        if [[ "$(_fsDockerPs_ "${_dockerName}")" = "true" ]]; then
			info '"'"${_dockerName}"'" activated.'
		else
			emergency '"'"${_dockerName}"'" not activated.' && exit 1
		fi
	else
		info '"'"${_dockerName}"'" is already active.'
	fi
}

function _fsDockerComposeInspect_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="$(_fsDockerYml_ "${1}")"
	local _ymlFile="${_ymlPath##*/}"
	local _ymlFileName="${_ymlFile%.*}"
	local _ymlFileType="${_ymlFile##*.}"
	#local _ymlDir="${_ymlPath%/*}"
	local _ymlProjectName="$(echo "${_ymlFileName}" | sed "s,-,_,g")"
	local _dockerProjects=''
	local _dockerProject=''
	local _dockerProjectNotrunc=''

    if [[ -f "${_ymlPath}" ]]; then
        echo
        _fsCdown_ 10 'for any bot errors...'
        echo
        
        _dockerProjects=("$(cd "${_dir}" && \
        sudo docker-compose -f "${_ymlFile}" -p "${_ymlProjectName}" ps -q 2> /dev/null)")
        
        for _dockerProject in "${_dockerProjects[@]}"; do
            _dockerProjectNotrunc="$(docker ps -q --no-trunc | grep "${_dockerProject}")"

            # credit: https://serverfault.com/a/935674
            if [[ -z "${_dockerProject}" ]] || [[ -z "${_dockerProjectNotrunc}" ]]; then
                error "\"$(_fsDockerId2Name_ "${_dockerProject}")\" container is not running."
                
                sudo docker update --restart no "${_dockerProject}" > /dev/null
                sudo docker stop "${_dockerProject}" > /dev/null
                sudo docker rm -f "${_dockerProject}" > /dev/null
                warning "  -> Set container \"restart\" to \"no\", stopped and removed."
            else
                notice "\"$(_fsDockerId2Name_ "${_dockerProject}")\" container is running."
            fi
            echo
        done
    fi
}

function _fsDockerYml_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="${_dir}/${1##*/}"
	local _ymlFile="${_ymlPath##*/}"
	local _ymlFileType="${_ymlFile##*.}"

	if [[ ! -z "${_ymlFileType}" ]]; then
    	if [[ ! "${_ymlFileType}" = 'yml' ]]; then
			emergency "\"$(basename "${_ymlFile}")\" is not a \".yml\" file." && exit 1
		elif [[ ! -f "${_ymlPath}" ]]; then
			emergency "\"$(basename "${_ymlFile}")\" does not exist." && exit 1
		else
			echo "${_ymlPath}"
		fi
	else
		emergency "\".yml\" parameter is missing." && exit 1
	fi
}

function _fsDockerCompose_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="$(_fsDockerYml_ "${1}")"
	local _ymlForce="${2:-}"
	local _ymlFile="${_ymlPath##*/}"
	local _ymlFileName="${_ymlFile%.*}"
	local _ymlFileType="${_ymlFile##*.}"
	local _ymlContainer=""
    local _ymlProject="$(echo "${_ymlFileName}" | sed "s,\-,_,g")"
	local _ymlPorts=""
	local _ymlPort=""
	local _ymlImages=""
	local _ymlImagesDeduped=""
	local _ymlImage=""
	local _ymlStrategies=""
	local _ymlStrategiesDeduped=""
	local _ymlStrategy=""
    local _ymlConfigsDeduped=""
    local _ymlConfigs=""
	local _ymlConfig=""
	local _ymlConfigNew=""
	local _error=""

    if [[ -f "${_ymlPath}" ]]; then
        notice 'Starting "'"${_ymlFile}"'" now...'
    
        if [[ ! "${_ymlForce}" = "force" ]]; then
            if [[ "$(_fsDockerInspectPort_ "${_ymlPath}")" = "false" ]]; then
                _error='true'
            fi
        fi

        # images
        # credit: https://stackoverflow.com/a/39612060
        _ymlImages=()
        while read; do
        _ymlImages+=( "$REPLY" )
        done < <(grep "image:" "${_ymlPath}" \
        | sed "s,\s,,g" \
        | sed "s,image:,,")
        
        if [[ ! -z "${_ymlImages[@]}" ]]; then
            _ymlImagesDeduped=()
            while read; do
            _ymlImagesDeduped+=( "$REPLY" )
            done < <(_fsDedupeArray_ "${_ymlImages[@]}")
        fi
        
        if [[ ! -z "${_ymlImagesDeduped[@]}" ]]; then
            for _ymlImage in "${_ymlImagesDeduped[@]}"; do
                _fsDockerImage_ "${_ymlImage}"
            done
        fi
        
        # strategies
        _ymlStrategies=()
        while read; do
        _ymlStrategies+=( "$REPLY" )
        done < <(grep "strategy" "${_ymlPath}" \
        | grep -v "strategy-path" \
        | sed "s,\s,,g" \
        | sed "s,\-\-strategy,,")

        if [[ ! -z "${_ymlStrategies[@]}" ]]; then
            _ymlStrategiesDeduped=()
            while read; do
            _ymlStrategiesDeduped+=( "$REPLY" )
            done < <(_fsDedupeArray_ "${_ymlStrategies[@]}")
        fi

        if [[ ! -z "${_ymlStrategiesDeduped[@]}" ]]; then
            for _ymlStrategy in "${_ymlStrategiesDeduped[@]}"; do              
                _setupStrategy_ "${_ymlStrategy}"
            done
        fi
        
        # configs
        _ymlConfigs=()
        while read; do
        _ymlConfigs+=( "$REPLY" )
        done < <(echo "$(grep -e "\-\-config" -e "\-c" "${_ymlPath}" \
        | sed "s,\s,,g" \
        | sed "s,\-\-config,," \
        | sed "s,\-c,," \
        | sed "s,\/freqtrade\/,,")")

        if [[ ! -z "${_ymlConfigs[@]}" ]]; then
            _ymlConfigsDeduped=()
            while read; do
            _ymlConfigsDeduped+=( "$REPLY" )
            done < <(_fsDedupeArray_ "${_ymlConfigs[@]}")
        fi

        if [[ ! -z "${_ymlConfigsDeduped[@]}" ]]; then
            for _ymlConfig in "${_ymlConfigsDeduped[@]}"; do   
                _ymlConfigNew="${_dir}/${_ymlConfig}"
                
                if [[ ! -f "${_ymlConfigNew}" ]]; then
                    error "\"$(basename "${_ymlConfigNew}")\" config file does not exist."
                    _error='true'
                fi
            done
        fi
    
        # compose
        if [[ "${_error}" != 'true' ]]; then		
            if [[ "${_ymlForce}" == 'force' ]]; then
                cd "${_dir}" && \
                sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" up -d --force-recreate
            else
                cd "${_dir}" && \
                sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" up -d			
            fi
            
            if [[ "$(_fsDockerComposeInspect_ "${_ymlPath}")" = "true" ]]; then
                notice "\"${_ymlFile}\" docker started."
            else
                error "\"${_ymlFile}\" docker not started."
            fi
        else
            error "\"${_ymlFile}\" docker not started."
        fi
	fi
}

function _fsDockerKill_() {
	_fsDockerKillContainer_
	
	sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
}

function _fsDockerKillContainer_() {
	sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
}


### FREQSTART - start
##############################################################################

function _fsStart_ {
	local _dockerYml="${1:-}"
	local _dockerCompose="${ENV_DIR}/$(basename "${_dockerYml}")"
		
	if [[ "$(_fsSymlink_ "${ENV_FS_SYMLINK}")" = "false" ]]; then
		error 'Start setup first with: ./'"${ENV_FS}"'.sh --setup' && exit 1
	else
        _fsDockerCompose_ "${_dockerCompose}"
	fi
}

### FREQSTART - setup
##############################################################################

function _fsSetup_() {
    _fsSetupServer_
    _fsSetupNtp_
    _fsSetupFreqtrade_
    _fsSetupBinanceProxy_
    _fsSetupFrequi_
    _fsSetupExampleBot_
    
	if [[ "$(_fsSymlink_ "${ENV_FS_SYMLINK}")" = "false" ]]; then
		sudo ln -sf "${ENV_DIR}/${ENV_FS}.sh" "${ENV_FS_SYMLINK}"
	fi
	
	if [[ "$(_fsSymlink_ "${ENV_FS_SYMLINK}")" = "true" ]]; then
        echo
		notice 'Setup finished!'
		info "-> Run freqtrade bots with: ${ENV_FS} -b example.yml"
		info "  1. \".yml\" files can contain one or multiple bots."
		info "  2. Configs and strategies files are checked for existense."
		info "  3. Checking docker images for updates before start."
	else
		emergency "Cannot create \"${ENV_FS}\" symlink." && exit 1
	fi
}

function _fsSetupPkgs_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}"

    local _pkgs=("${@}")
    local _pkg=""
    local _status=""

    for _pkg in "${_pkgs[@]}"; do
        _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" | grep "install ok installed")"
        if [[ -z "${_status}" ]]; then
            if [[ "${_pkg}" = 'docker-ce' ]]; then
                # docker setup
                sudo apt-get remove docker docker-engine docker.io containerd runc
                sudo apt-get install -y -q apt-transport-https ca-certificates curl gnupg-agent software-properties-common
                sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
                sudo apt-get update
                sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io
                adduser user
                usermod -aG docker user
                systemctl restart docker
                systemctl enable docker
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

            _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" | grep "install ok installed")"
            if [[ -z "${_status}" ]]; then
                emergency '"'"$_pkg"'" is not installed.'
            else
                info '"'"$_pkg"'" is installed.'
            fi
        else
            info '"'"$_pkg"'" is already installed.'
        fi
    done
}

function _fsSetupServer_() {
    info 'SETUP SERVER:'
    
    sudo apt-get update

    _fsSetupPkgs_ git curl jq docker-ce
    
    info 'Update server and install unattended-upgrades. Reboot may be required!'
    
    if [[ "$(_fsCaseConfirmation_ "Skip server update?")" = "true" ]]; then
        warning 'Skipping server update...'
    else
        sudo apt -o Dpkg::Options::="--force-confdef" dist-upgrade -y && \
        sudo apt install -y unattended-upgrades && \
        sudo apt autoremove -y

        if sudo test -f /var/run/reboot-required; then
            warning 'A reboot is required to finish installing updates.'
            if [[ "$(__fsCaseConfirmation_ "Skip reboot now?")" = "true" ]]; then
                warning 'Skipping reboot...'
            else
                sudo reboot
            fi
        else
            info "A reboot is not required. Exiting..."
        fi
    fi
}

function _fsSetupNtp_() {
    echo
    info 'SETUP NTP: (Timezone to UTC)'

    if [[ _fsSetupNtpCheck = "false" ]]; then
        _fsSetupPkgs_ 'chrony'
        
        if [[ _fsSetupNtpCheck = "false" ]]; then
            emergency 'NTP not active or not synchronized.'
        else
            info  'NTP activated and synchronized.'
        fi
    else
        info 'NTP is active and synchronized.'
    fi
}

function _fsSetupNtpCheck {
    local timentp="$(timedatectl | grep -o 'NTP service: active')"
    local timeutc="$(timedatectl | grep -o '(UTC, +0000)')"
    local timesyn="$(timedatectl | grep -o 'System clock synchronized: yes')"
    
    if [[ ! -z "${timentp}" ]] || [[ ! -z  "${timeutc}" ]] || [[ ! -z  "${timesyn}" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

function _fsSetupFreqtrade_() {
    local _docker="freqtradeorg/freqtrade:stable"
    local _dockerYml="${ENV_DIR}/${ENV_FS}_setup.yml"
    local _dirUserData="${ENV_DIR_USER_DATA}"
    local _configKey=""
    local _configSecret=""
    local _configName=""
    local _configFile=""
    local _configFileNew=""

    echo
    info 'SETUP FREQTRADE:'
    
    _fsDockerImage_ "${_docker}" > /dev/null

    if [[ ! -d "${_dirUserData}" ]] && [[ -f "${_dockerYml}" ]]; then
        _fsSetupFreqtradeYml_
        
        cd "${ENV_DIR}" && \
        docker-compose --file "$(basename "${_dockerYml}")" \
        run --rm freqtrade create-userdir --userdir "$(basename "${_dirUserData}")" \
        || true
                
        if [[ ! -d "${_dirUserData}" ]]; then
            emergency '"'"${_dirUserData}"'" directory can not be created.' && exit 1
        else
            info '"'"${_dirUserData}"'" directory created.'
        fi
    fi
    
    info "A config is needed to start a bot!"

    if [[ "$(_fsCaseConfirmation_ "Skip creating a config?")" = "true" ]]; then
       warning "Skipping create a config..."
    else
        while true; do
            info "Choose a name for your config. For default name press <ENTER>."
            read -p " (filename) " _configName
            case "${_configName}" in
                "")
                    _configName="config"
                ;;
                *)
                    _configName="${_configName%.*}"

                    if [[ "$(_fsIsAlphaDash_ "${_configName}")" = "false" ]]; then
                        warning "Only alpha-numeric or dash or underscore characters are allowed!"
                        _configName=""
                    fi
                ;;
            esac
            if [[ ! -z "${_configName}" ]]; then
                info "The config file will be: \"${_configName}.json\""
                if [[ "$(_fsCaseConfirmation_ "Is this correct?")" = "true" ]]; then
                    break
                fi
            fi
        done
        
        _configFile="${_dirUserData}/${_configName}.json"
        _configFileNew="${_dirUserData}/${_configName}.new.json"
        _configFileBackup="${_dirUserData}/${_configName}.bak.json"

        if [[ -f "${_configFile}" ]]; then
            warning 'The config "'"$(basename ${_configFile})"'" already exist.'
            if [[ "$(_fsCaseConfirmation_ "Replace the existing config file?")" = "false" ]]; then
                _configName=""
                rm -f "${_dockerYml}"
            fi
        fi
    fi

    if [[ ! -z "${_configName}" ]] && [[ -d "${_dirUserData}" ]] && [[ -f "${_dockerYml}" ]]; then
        _fsSetupFreqtradeYml_
        rm -f "${_configFileNew}"
        
        cd "${ENV_DIR}" && \
        docker-compose --file "$(basename "${_dockerYml}")" \
        run --rm freqtrade new-config --config "$(basename "${_dirUserData}")/$(basename "${_configFileNew}")" \

        rm -f "${_dockerYml}"

        if [[ -f "${_configFileNew}" ]]; then

            if [[ "$(_fsCaseConfirmation_ 'Enter your exchange api KEY and SECRET now? (recommended)')" = "true" ]]; then
                while true; do
                    notice 'Enter your KEY for exchange api (ENTRY HIDDEN):'
                    read -s _configKey
                    echo
                    case "${_configKey}" in 
                        '')
                            _fsCaseEmpty_
                            ;;
                        *)
                            _fsJsonSet_ "${_configFileNew}" 'key' "${_configKey}" && \
                            info "\"$(basename "${_configFile}")\" KEY is set."
                            break
                            ;;
                    esac
                done

                while true; do
                    notice 'Enter your SECRET for exchange api (ENTRY HIDDEN):'
                    read -s _configSecret
                    echo
                    case "${_configSecret}" in 
                        '')
                            _fsCaseEmpty_
                            ;;
                        *)
                            _fsJsonSet_ "${_configFileNew}" 'secret' "${_configSecret}" && \
                            info "\"$(basename "${_configFile}")\" SECRET is set."
                            break
                            ;;
                    esac
                done
            else
                warning 'Enter your exchange api KEY and SECRET manually to: "'"$(basename "${_configFile}")"'"'
            fi
            
            cp -a "${_configFileNew}" "${_configFile}"
            cp -a "${_configFileNew}" "${_configFileBackup}"

            rm -f "${_configFileNew}"
        else
            emergency '"'"$(basename "${_configFile}")"'" config file does not exist.' && exit 1
        fi
    fi
}

function _fsSetupFreqtradeYml_() {
    local _dockerYml="${ENV_DIR}/${ENV_FS}_setup.yml"
    local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"

    if [[ ! -f "${_dockerYml}" ]]; then
        curl -s -L "${_dockerGit}" -o "${_dockerYml}" || emergency "Cannot reach: ${_dockerGit}" && exit 1
        
        if [[ -f "${_dockerYml}" ]]; then
            info '"'"${_dockerYml}"'" file created.'
        else
            emergency '"'"${_dockerYml}"'" file can not be created.' && exit 1
        fi
    fi
}

_fsSetupBinanceProxy_() {
    local _binanceProxy="${ENV_BINANCE_PROXY}"
    local _docker="nightshift2k/binance-proxy:latest"
    local _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
    local _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
    local _dockerName="$(_fsDockerVarsName_ "${_docker}")"

    echo
    info 'SETUP BINANCE-PROXY: (Ports: 8090-8091/tcp)'

    if [[ "$(_fsDockerPs_ "${_dockerName}")" = "true" ]]; then
        notice "\"${_dockerName}\" is already running, checking for updates..."
        
        _fsDockerRun_ "${_dockerRepo}" "${_dockerTag}" 'rm'
    else
        if [[ "$(_fsCaseConfirmation_ "Install \"binance-proxy\" and start now?")" = "true" ]]; then
            if [[ ! -f "${_binanceProxy}" ]]; then
                printf '%s\n' \
                "{" \
                "    \"exchange\": {" \
                "        \"name\": \"binance\"," \
                "        \"ccxt_config\": {" \
                "            \"enableRateLimit\": false," \
                "            \"urls\": {" \
                "                \"api\": {" \
                "                    \"public\": \"http://127.0.0.1:8090/api/v3\"" \
                "                }" \
                "            }" \
                "        }," \
                "        \"ccxt_async_config\": {" \
                "            \"enableRateLimit\": false" \
                "        }" \
                "    }" \
                "}" \
                > "${_binanceProxy}"
                
                if [[ ! -f "${_binanceProxy}" ]]; then
                    emergency "Can not create \"$(basename "${_binanceProxy}")\" file." && exit 1
                else
                    info "\"$(basename "${_binanceProxy}")\" file created."
                fi
            else
                info "\"$(basename "${_binanceProxy}")\" already exist."
            fi
            
            _fsDockerRun_ "${_dockerRepo}" "${_dockerTag}" 'rm'
        else
            warning 'Skip "binance-proxy" installation...'
        fi
    fi
}

function _fsSetupFrequi_() {
    #local _frequiYml="${ENV_FREQUI_YML}"
    local _frequiName="${ENV_FS}_frequi"
    local _nr=""
    local _setup=""
    
    echo
    info 'FREQUI: (Webserver API)'
    
	if [[ "$(_fsDockerPs_ "${_frequiName}")" = "true" ]]; then
    #if [[ "$(_fsDockerInspectPort_ "${_frequiYml}")" = "false" ]]; then
        if [[ "$(_fsCaseConfirmation_ "Skip reconfigure \"FreqUI\" now?")" = "true" ]]; then
            _setup="false"
        fi
    else
        if [[ "$(_fsCaseConfirmation_ "Install \"FreqUI\" now?")" = "true" ]]; then
            _setup="true"
        fi
    fi

    if [[ "${_setup}" = "true" ]];then
        _fsSetupPkgs_ 'ufw'
        _fsSetupNginx_
        
        while true; do
            info 'Secure the connection to "FreqUI"?'
            notice '  1) Yes, I want to use an IP with SSL (openssl)'
            info '     -> Ignore browser warnings on self signed SSL.'
            notice '  2) Yes, I want to use a domain with SSL (truecrypt)'
            info '     -> Set DNS to "'"${ENV_SERVER_IP}"' first!'
            notice '  3) No, I dont want to use SSL (not recommended)'
            info '     -> Only for local use!'
            
            if [[ ! "${ENV_YES}" = "true" ]]; then
                read -p " (1/2/3) " _nr
            else
                local _nr="3"
            fi
            case "${_nr}" in 
                ['1'])
                    info "Continuing with 1) ..."
                    _fsSetupNginxOpenssl_
                    break
                    ;;
                ['2'])
                    info "Continuing with 2) ..."
                    _setupNginxLetsencrypt_
                    break
                    ;;
                ['3'])
                    info "Continuing with 3) ..."
                    break
                    ;;
                *)
                    _fsCaseInvalid_
                    ;;
            esac
        done
        
        _setupFrequiJson_
        _setupFrequiCompose_
    else
        warning "Skipping \"FreqUI\" installation..."
    fi
}

_fsSetupNginx_() {
    local _confPath="/etc/nginx/conf.d"
    local _confPathFrequi="${_confPath}/frequi.conf"
    local _confPathNginx="${_confPath}/default.conf"
    local _serverName="${ENV_SERVER_IP}"
    
    ENV_SERVER_URL="http://${_serverName}"

    _fsSetupPkgs_ "nginx"

    printf '%s\n' \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;" \
    "    server_name ${_serverName};" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "    }" \
    "}" \
    "server {" \
    "    listen ${_serverName}:9000-9100;" \
    "    server_name ${_serverName};" \
    "    " \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    > "${_confPathFrequi}"

    if [ -f "${_confPathNginx}" ]; then sudo mv "${_confPathNginx}" "${_confPathNginx}"'.disabled'; fi

    sudo rm -f /etc/nginx/sites-enabled/default
    
    sudo ufw allow http/tcp > /dev/null
    sudo ufw allow "Nginx Full" > /dev/null

    _fsSetupNginxRestart_
}

_fsSetupNginxRestart_() {
    # kill and start again
    sudo pkill -f nginx & wait $! >/dev/null 2>&1
    sudo systemctl start nginx >/dev/null 2>&1
    sudo nginx -s reload >/dev/null 2>&1
}

_fsSetupNginxOpenssl_() {
    _fsSetupNginxConfSecure_ 'openssl'

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
    local _domain=""
    local _domainIp=""
    local _serverIp="${ENV_SERVER_IP}"
    
    while true; do
        read -p "Enter your domain (www.example.com): " _domain
        
        if [[ "${_domain}" = "" ]]; then
            _fsCaseEmpty_
        else
            if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_domain}\" correct?")" = "true" ]]; then
                _domainIp="$(ping -c 1 -w15 "${_domain}" | awk 'NR==1{print $3}' | sed "s,(,," | sed "s,),,")"
                
                if [[ ! "${_domainIp}" = "${_serverIp}" ]]; then
                    warning "\"${_domain}\" does not point to \"${_serverIp}\". Review DNS and try again!"
                else
                    _fsSetupNginxConfSecure_ 'letsencrypt' "${_domain}"
                    _fsSetupNginxCertbot_ "${_domain}"

                    break
                fi
            fi
            
            _domain=""
        fi
    done
}

_fsSetupNginxCertbot_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _domain="${1}"
    
    _fsSetupPkgs_ certbot python3-certbot-nginx
    
    sudo certbot --nginx -d "${_domain}"
}

_fsSetupNginxConfSecure_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _mode="${1}"
    local _domain="${2}"
    local _confPath="/etc/nginx/conf.d"
    local _confPathNginx="${_confPath}/default.conf"
    local _confPathFrequi="${_confPath}/frequi.conf"
    local _serverName="${ENV_SERVER_IP}"
    
    if [[ ! -z "${_domain}" ]]; then
        _serverName="${_domain}"
    fi
    
    ENV_SERVER_URL="https://${_serverName}"

    # thanks: Blood4rc, Hippocritical
    if [[ "${_mode}" = 'openssl' ]]; then
        printf '%s\n' \  
        "server {" \
        "    listen 80;" \
        "    listen [::]:80;" \
        "    server_name ${_serverName};" \
        "    return 301 https://\$server_name\$request_uri;" \
        "}" \
        "server {" \
        "    listen 443 ssl;" \
        "    listen [::]:443 ssl;" \
        "    server_name ${server_name};" \
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
        "    listen ${server_name}:9000-9100 ssl;" \
        "    server_name ${_serverName};" \
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
        > "${_confPathFrequi}"
    elif [[ "${_mode}" = 'letsencrypt' ]]; then
        printf '%s\n' \
        "server {" \
        "    listen 80;" \
        "    listen [::]:80;     " \
        "    server_name ${_serverName};" \
        "    return 301 https://\$host\$request_uri;" \
        "}" \
        "server {" \
        "    listen 443 ssl http2;" \
        "    listen [::]:443 ssl http2;" \
        "    server_name ${_serverName};" \
        "    " \
        "    ssl_certificate /etc/letsencrypt/live/${_serverName}/fullchain.pem;" \
        "    ssl_certificate_key /etc/letsencrypt/live/${_serverName}/privkey.pem;" \
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
        "    listen ${_serverName}:9000-9990 ssl http2;" \
        "    server_name ${_serverName};" \
        "    " \
        "    ssl_certificate /etc/letsencrypt/live/${_serverName}/fullchain.pem;" \
        "    ssl_certificate_key /etc/letsencrypt/live/${_serverName}/privkey.pem;" \
        "    include /etc/letsencrypt/options-ssl-nginx.conf;" \
        "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;" \
        "    " \
        "    location / {" \
        "        proxy_set_header Host \$host;" \
        "        proxy_set_header X-Real-IP \$remote_addr;" \
        "        proxy_pass http://127.0.0.1:\$server_port;" \
        "    }" \
        "}" \
        > "${_confPathFrequi}"
    fi
    
    if [ -f "${_confPathNginx}" ]; then sudo mv "${_confPathNginx}" "${_confPathNginx}"'.disabled'; fi

    sudo ufw allow https/tcp > /dev/null
    
    sudo rm -f /etc/nginx/sites-enabled/default

    _fsSetupNginxRestart_
}

_setupFrequiJson_() {
    local _frequiJson="${ENV_FREQUI_JSON}"
    local _frequiJwt="$(_fsJsonGet_ "${_frequiJson}" 'jwt_secret_key')"
    local _frequiUsername="$(_fsJsonGet_ "${_frequiJson}" 'username')"
    local _frequiPassword="$(_fsJsonGet_ "${_frequiJson}" 'password')"
    local _frequiPasswordCompare=""
    local _frequiTmpUsername=""
    local _frequiTmpPassword=""
    local _frequiCors="${ENV_SERVER_URL}"
    local _yesNo="${ENV_YES}"
    local _setup="false"

    if [[ "${_frequiJwt}" = "" ]]; then
        _frequiJwt="$(_fsSecret_)"
    fi

    if [[ ! -z "${_frequiUsername}" ]] || [[ ! -z "${_frequiPassword}" ]]; then
        warning "Login data for \"FreqUI\" already found."
        
        if [[ "$(_fsCaseConfirmation_ "Skip generating new login data?")" = "false" ]]; then
            notice "Create your login data for \"FreqUI\" now!"
            _setup="true"
        fi
    else
        _setup="true"
    fi
    
    if [[ "${_setup}" = "true" ]]; then
        # create username
        while true; do
            read -p 'Enter username: ' _frequiUsername
            
            if [[ ! "${_frequiUsername}" = "" ]]; then
                read -p 'Is the username "'"${_frequiUsername}"'" correct? (y/n) ' _yesNo
            else
                _yesNo=""
            fi
            
            case "${_yesNo}" in 
                [Yy]*)
                    break
                    ;;
                [Nn]*)
                    info "Try again!"
                    ;;
                "")
                    _fsCaseEmpty_
                    ;;
                *)
                    _fsCaseInvalid_
                    ;;
            esac
        done
        
        # create password - NON VERBOSE
        while true; do
            notice 'Enter password (ENTRY HIDDEN):'
            read -s _frequiPassword
            echo
            case "${_frequiPassword}" in 
                "")
                    _fsCaseEmpty_
                    ;;
                *)
                    notice 'Enter password again: '
                    read -s _frequiPasswordCompare
                    echo
                    if [[ ! "${_frequiPassword}" = "${_frequiPasswordCompare}" ]]; then
                        warning "The password does not match. Try again!"
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

    if [[ ! -z "${_frequiUsername}" ]] && [[ ! -z "${_frequiPassword}" ]]; then
        printf '%s\n' \
        "{" \
        "    \"api_server\": {" \
        "        \"enabled\": true," \
        "        \"listen_ip_address\": \"0.0.0.0\"," \
        "        \"listen_port\": 8080," \
        "        \"verbosity\": \"error\"," \
        "        \"enable_openapi\": false," \
        "        \"jwt_secret_key\": \"${_frequiJwt}\"," \
        "        \"CORS_origins\": [\"${_frequiCors}:9999\"]," \
        "        \"username\": \"${_frequiUsername}\"," \
        "        \"password\": \"${_frequiPassword}\"" \
        "    }" \
        "}" \
        > "${_frequiJson}"

        
        if [[ ! -f "${_frequiJson}" ]]; then
            emergency "Can not create \"$(basename "${_frequiJson}")\" config file." && exit 1
        fi
    fi
}

_setupFrequiCompose_() {
    local _serverUrl="${ENV_SERVER_URL}"
    local _fsConfig="${ENV_FS_CONFIG}"
    local _frequiYml="${ENV_FREQUI_YML}"
    local _frequiJson="${ENV_FREQUI_JSON}"
    local _frequiServerJson="${ENV_FREQUI_SERVER_JSON}"
    local _frequiName="${ENV_FS}_frequi"
    local _frequiServerLog="${ENV_DIR_USER_DATA}/logs/${_frequiName}.log"
    local _frequiStrategy='DoesNothingStrategy'
    
    info "Starting \"FreqUI\" docker..."
    
    _fsJsonSet_ "${_fsConfig}" 'server_url' "${_serverUrl}"

    printf '%s\n' \
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
    "    \"bot_name\": \"frequi-server\"," \
    "    \"initial_state\": \"running\"" \
    "}" \
    > "${_frequiServerJson}"
    
    if [[ ! -f "${_frequiServerJson}" ]]; then
        emergency "Can not create \"$(basename "${_frequiServerJson}")\" config file." && exit 1
    fi

    printf -- '%s\n' \
    "---" \
    "version: '3'" \
    "services:" \
    "  ${_frequiName}:" \
    "    image: freqtradeorg/freqtrade:stable" \
    "    restart: unless-stopped" \
    "    container_name: ${_frequiName}" \
    "    volumes:" \
    "    - \"./user_data:/freqtrade/user_data\"" \
    "    ports:" \
    "      - \"127.0.0.1:9999:8080\"" \
    "    tty: true" \
    "    " \
    "    command: >" \
    "      trade" \
    "      --logfile /freqtrade/user_data/logs/$(basename ${_frequiServerLog})" \
    "      --strategy ${_frequiStrategy}" \
    "      --strategy-path /freqtrade/user_data/${_frequiStrategy}" \
    "      --config /freqtrade/user_data/$(basename ${_frequiJson})" \
    "      --config /freqtrade/user_data/$(basename ${_frequiServerJson})" \
    > "${_frequiYml}"

    if [[ -f "${_frequiYml}" ]]; then
        if [[ -f "${_frequiServerLog}" ]]; then
            rm -f "${_frequiServerLog}"
        fi
        
        _fsDockerCompose_ "${_frequiYml}" 'force'
    else
        emergency "\"$(basename "${_frequiYml}")\" file not found." && exit 1
    fi
}

_setupStrategy_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _strategyName="${1}"
    local _strategyFile=""
    local _strategyFileNew=""
    local _strategyFileCount=0
    local _strategyFileType=""
    local _strategyFileTypeName='unknown'
    local _strategyTmp="${ENV_DIR_TMP}/${_strategyName}_${ENV_HASH}"
    local _strategyDir="${ENV_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
    local _strategyUrls=""
    local _strategyUrlsDeduped=""
    local _strategyUrl=""
    local _fsStrategies="${ENV_FS_STRATEGIES}"
    
    if [[ ! -f "${_fsStrategies}" ]]; then
        printf '%s\n' \
        "{" \
        "    \"NostalgiaForInfinityX\": [" \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/NostalgiaForInfinityX.py\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-binance.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-bybit.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-ftx.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-gateio.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-huobi.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-kucoin.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-okx.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig-rebuy.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig_secret.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-binance-busd.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-binance-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-bybit-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-ftx-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-gateio-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-huobi-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-kucoin-usdt.json\"," \
        "        \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-okx-usdt.json\"" \
        "    ]," \
        "    \"DoesNothingStrategy\": [" \
        "        \"https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/master/user_data/strategies/berlinguyinca/DoesNothingStrategy.py\"" \
        "    ]" \
        "}" \
        > "${_fsStrategies}"
    fi
    
    _strategyUrls=()
    while read; do
    _strategyUrls+=( "$REPLY" )
    done < <(jq -r ".${_strategyName}[]?" "${_fsStrategies}")

    if [[ ! -z "${_strategyUrls[@]}" ]]; then
        _strategyUrlsDeduped=()
        while read; do
        _strategyUrlsDeduped+=( "$REPLY" )
        done < <(_fsDedupeArray_ "${_strategyUrls[@]}")
    fi

    #readarray -t _strategyUrls < <(jq -r ".${_strategyName}[]?" "${_fsStrategies}")
    
    if [[ ! -z "${_strategyUrlsDeduped[@]}" ]]; then
        sudo mkdir -p "${_strategyTmp}"
        sudo mkdir -p "${_strategyDir}"

        for _strategyUrl in "${_strategyUrlsDeduped[@]}"; do
            if [[ "$(_fsUrlValidate_ "${_strategyUrl}")" = "true" ]]; then
                _strategyFile="$(basename "${_strategyUrl}")"
                _strategyFileNew="${_strategyDir}/${_strategyFile}"
                _strategyFileType="${_strategyFile##*.}"

                if [ "${_strategyFileType}" == "py" ]; then
                    _strategyFileTypeName='strategy'
                elif [ "${_strategyFileType}" == "json" ]; then
                    _strategyFileTypeName='config'
                fi
                
                sudo curl -s -L "${_strategyUrl}" -o "${_strategyTmp}/${_strategyFile}"
            
                if [[ -f "${_strategyFileNew}" ]]; then
                    if [[ -n "$(cmp --silent "${_strategyUrl}" "${_strategyFileNew}")" ]]; then
                        cp -a "${_strategyTmp}/${_strategyFile}" "${_strategyFileNew}"
                        _strategyFileCount=$((_strategyFileCount+1))

                        info "\"${_strategyFile}\" \"${_strategyFileTypeName}\" updated."
                    fi
                else
                    cp -a "${_strategyTmp}/${_strategyFile}" "${_strategyFileNew}"
                    _strategyFileCount=$((_strategyFileCount+1))
                    
                    info "\"${_strategyFile}\" \"${_strategyFileTypeName}\" installed."
                fi
            fi
        done
        
        sudo rm -rf "${_strategyTmp}"

        if [[ "${_strategyFileCount}" -eq 0 ]]; then
            notice "\"${_strategyName}\" latest version installed."
        else
            notice "\"${_strategyName}\" strategy is updated. Restart bots!"
        fi
    else
        warning "\"${_strategyName}\" strategy not implemented."
    fi
}

_fsSetupExampleBot_() {
    local _userData="${ENV_DIR_USER_DATA}"
    local _botExampleYml="${ENV_DIR}/${ENV_FS}_example.yml"
    local _botExampleConfig=""
    local _botExampleConfigName=""
    local _frequiJson="$(basename "${ENV_FREQUI_JSON}")"
    local _binanceProxyJson="$(basename "${ENV_BINANCE_PROXY}")"
    local _botExampleExchange=""
    local _botExampleCurrency=""
    local _botExampleKey=""
    local _botExampleSecret=""
    local _botExamplePairlist=""
    local _botExampleLog="${ENV_DIR_USER_DATA}/logs/${ENV_FS}_example.log"
    local _setup=""
    local _error=""

    echo
    info 'EXAMPLE (NFI):'

    info "Creating an example bot \".yml\" file for dryrun on Binance."
    info "Incl. latest \"NostalgiaForInfinityX\" strategy, \"FreqUI\" and proxy"
        
    if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" = "true" ]]; then
        warning "Skipping example bot..."
    else
        while true; do
            info "What is the name of your config file? For default name press <ENTER>."
            read -p " (filename) " _botExampleConfigName
            case "${_configName}" in
                "")
                    _botExampleConfigName="config"
                ;;
                *)
                    _botExampleConfigName="${_botExampleConfigName%.*}"

                    if [[ "$(_fsIsAlphaDash_ "${_botExampleConfigName}")" = "false" ]]; then
                        warning "Only alpha-numeric or dash or underscore characters are allowed!"
                        _botExampleConfigName=""
                    fi
                ;;
            esac
            if [[ ! -z "${_botExampleConfigName}" ]]; then
                info "The config file will be: \"${_botExampleConfigName}.json\""
                if [[ "$(_fsCaseConfirmation_ "Is this correct?")" = "true" ]]; then
                    _botExampleConfig="${_userData}/${_botExampleConfigName}.json"

                    if [[ -f "${_botExampleConfig}" ]]; then
                        _botExampleExchange="$(_fsJsonGet_ "${_botExampleConfig}" 'name')"
                        _botExampleCurrency="$(_fsJsonGet_ "${_botExampleConfig}" 'stake_currency')"
                        _botExampleKey="$(_fsJsonGet_ "${_botExampleConfig}" 'key')"
                        _botExampleSecret="$(_fsJsonGet_ "${_botExampleConfig}" 'secret')"
                        
                        _setup="true"
                        break
                    else
                        error "\"$(basename "${_botExampleConfig}")\" config file does not exist."
                        _botExampleConfigName=""
                        
                        if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" = "true" ]]; then
                            _setup='false'
                            break
                        fi
                    fi
                fi
            fi
        done
        
        if [[ "${_setup}" = "true" ]]; then
            if [[ -z "${_botExampleKey}" || -z "${_botExampleSecret}" ]]; then
                error 'Restart setup and create an example config with your API key and secret.'
                _error='true'
            fi
            
            if [[ "${_botExampleExchange}" != 'binance' ]]; then
                error 'Only "Binance" is supported for example bot.'
                _error='true'
            fi

            if [[ "${_botExampleCurrency}" == 'USDT' ]]; then
                _botExamplePairlist='pairlist-volume-binance-busd.json'
            elif [[ "${_botExampleCurrency}" == 'BUSD' ]]; then
                _botExamplePairlist='pairlist-volume-binance-busd.json'
            else
                error 'Only USDT and BUSD pairlist are supported.'
                _error='true'
            fi
        
            if [[ ! "${_error}" = "true" ]]; then
                printf -- '%s\n' \
                "---" \
                "version: '3'" \
                "services:" \
                "  ${env_fsdocker}-example:" \
                "    image: freqtradeorg/freqtrade:stable" \
                "    restart: \"no\"" \
                "    container_name: ${env_fsdocker}-example" \
                "    volumes:" \
                "      - \"./user_data:/freqtrade/user_data\"" \
                "    ports:" \
                "      - \"127.0.0.1:9001:8080\"" \
                "    tty: true" \
                "    " \
                "    command: >" \
                "      trade" \
                "      --logfile /freqtrade/user_data/logs/${env_fsdocker}-example.log" \
                "      --strategy NostalgiaForInfinityX" \
                "      --strategy-path /freqtrade/user_data/NostalgiaForInfinityX" \
                "      --config /freqtrade/user_data/$(basename "${_botExampleConfig}")" \
                "      --config /freqtrade/user_data/NostalgiaForInfinityX/exampleconfig.json" \
                "      --config /freqtrade/user_data/NostalgiaForInfinityX/${_botExamplePairlist}" \
                "      --config /freqtrade/user_data/NostalgiaForInfinityX/blacklist-binance.json" \
                "      --config /freqtrade/user_data/${_frequiJson}" \
                "      --config /freqtrade/user_data/${_binanceProxyJson}" \
                > "${_botExampleYml}"
                
                if [[ ! -f "${_botExampleYml}" ]]; then
                    emergency "\"$(basename "${_botExampleYml}")\" file could not be created." && exit 1
                else
                    if [[ -f "${_botExampleLog}" ]]; then
                        rm -f "${_botExampleLog}"
                    fi

                    info "1) The docker path is different from the real path and starts with \"/freqtrade\"."
                    info "2) Add your exchange api KEY and SECRET to: \"exampleconfig_secret.json\""
                    info "3) Change port number \"9001\" to an unused port between 9000-9100 in \"${_botExampleYml}\" file."
                    notice "Run example bot with: ${ENV_FS} -b $(basename "${_botExampleYml}")"
                fi
            fi
        else
            warning "Skipping example bot..."
        fi
    fi
}

### Parse commandline options
##############################################################################

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
# - A short option must be preset for every long option; but every short option
#   need not have a long option
# - `--` is respected as the separator between options and arguments
# - We do not bash-expand defaults, so setting '~/app' as a default will not resolve to ${HOME}.
#   you can use bash variables to work around this (so use ${HOME} instead)

# shellcheck disable=SC2015
[[ "${__usage+x}" ]] || read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -v               Enable verbose mode, print script as it is executed
  -d --debug       Enables debug mode
  -h --help        This page
  -n --no-color    Disable color output
  -y --yes         Yes
  -s --setup       Setup
  -b --bot  [arg]  Bot to process. Can be repeated.
EOF

# shellcheck disable=SC2015
[[ "${__helptext+x}" ]] || read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 Freqstart simplifies the use of Freqtrade with Docker. Including a simple setup guide for Freqtrade,
 configurations and FreqUI with a secured SSL proxy for IPs and domains. Freqtrade also automatically
 installs implemented strategies based on Docker Compose files and detects necessary updates.
EOF

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read -r __b3bp_tmp_line; do
  if [[ "${__b3bp_tmp_line}" =~ ^- ]]; then
    # fetch single character version of option string
    __b3bp_tmp_opt="${__b3bp_tmp_line%% *}"
    __b3bp_tmp_opt="${__b3bp_tmp_opt:1}"

    # fetch long version if present
    __b3bp_tmp_long_opt=""

    if [[ "${__b3bp_tmp_line}" = *"--"* ]]; then
      __b3bp_tmp_long_opt="${__b3bp_tmp_line#*--}"
      __b3bp_tmp_long_opt="${__b3bp_tmp_long_opt%% *}"
    fi

    # map opt long name to+from opt short name
    printf -v "__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}" '%s' "${__b3bp_tmp_opt}"
    printf -v "__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt}" '%s' "${__b3bp_tmp_long_opt//-/_}"

    # check if option takes an argument
    if [[ "${__b3bp_tmp_line}" =~ \[.*\] ]]; then
      __b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
      __b3bp_tmp_init=""  # it has an arg. init with ""
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "1"
    elif [[ "${__b3bp_tmp_line}" =~ \{.*\} ]]; then
      __b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
      __b3bp_tmp_init=""  # it has an arg. init with ""
      # remember that this option requires an argument
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
    else
      __b3bp_tmp_init="0" # it's a flag. init with 0
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "0"
    fi
    __b3bp_tmp_opts="${__b3bp_tmp_opts:-}${__b3bp_tmp_opt}"

    if [[ "${__b3bp_tmp_line}" =~ ^Can\ be\ repeated\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Can\ be\ repeated\. ]]; then
      # remember that this option can be repeated
      printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "1"
    else
      printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "0"
    fi
  fi

  [[ "${__b3bp_tmp_opt:-}" ]] || continue

  if [[ "${__b3bp_tmp_line}" =~ ^Default= ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Default= ]]; then
    # ignore default value if option does not have an argument
    __b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}"
    if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
      # take default
      __b3bp_tmp_init="${__b3bp_tmp_line##*Default=}"
      # strip double quotes from default argument
      __b3bp_tmp_re='^"(.*)"$'
      if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
        __b3bp_tmp_init="${BASH_REMATCH[1]}"
      else
        # strip single quotes from default argument
        __b3bp_tmp_re="^'(.*)'$"
        if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
          __b3bp_tmp_init="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  fi

  if [[ "${__b3bp_tmp_line}" =~ ^Required\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Required\. ]]; then
    # remember that this option requires an argument
    printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
  fi

  # Init var with value unless it is an array / a repeatable
  __b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
  [[ "${!__b3bp_tmp_varname}" = "0" ]] && printf -v "arg_${__b3bp_tmp_opt:0:1}" '%s' "${__b3bp_tmp_init}"
done <<< "${__usage:-}"

# run getopts only if options were specified in __usage
if [[ "${__b3bp_tmp_opts:-}" ]]; then
  # Allow long options like --this
  __b3bp_tmp_opts="${__b3bp_tmp_opts}-:"

  # Reset in case getopts has been used previously in the shell.
  OPTIND=1

  # start parsing command line
  set +o nounset # unexpected arguments will cause unbound variables
                 # to be dereferenced
  # Overwrite $arg_<flag> defaults with the actual CLI options
  while getopts "${__b3bp_tmp_opts}" __b3bp_tmp_opt; do
    [[ "${__b3bp_tmp_opt}" = "?" ]] && help "Invalid use of script: ${*} "

    if [[ "${__b3bp_tmp_opt}" = "-" ]]; then
      # OPTARG is long-option-name or long-option=value
      if [[ "${OPTARG}" =~ .*=.* ]]; then
        # --key=value format
        __b3bp_tmp_long_opt=${OPTARG/=*/}
        # Set opt to the short option corresponding to the long option
        __b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}"
        printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
        OPTARG=${OPTARG#*=}
      else
        # --key value format
        # Map long name to short version of option
        __b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${OPTARG//-/_}"
        printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
        # Only assign OPTARG if option takes an argument
        __b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt}"
        __b3bp_tmp_varvalue="${!__b3bp_tmp_varname}"
        [[ "${__b3bp_tmp_varvalue}" != "0" ]] && __b3bp_tmp_varvalue="1"
        printf -v "OPTARG" '%s' "${@:OPTIND:${__b3bp_tmp_varvalue}}"
        # shift over the argument if argument is expected
        ((OPTIND+=__b3bp_tmp_varvalue))
      fi
      # we have set opt/OPTARG to the short value and the argument as OPTARG if it exists
    fi

    __b3bp_tmp_value="${OPTARG}"

    __b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
    if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
      # repeatables
      # shellcheck disable=SC2016
      if [[ -z "${OPTARG}" ]]; then
        # repeatable flags, they increcemnt
        __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
        debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
          # shellcheck disable=SC2004
        __b3bp_tmp_value=$((${!__b3bp_tmp_varname} + 1))
        printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"
      else
        # repeatable args, they get appended to an array
        __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}[@]"
        debug "cli arg ${__b3bp_tmp_varname} append ${__b3bp_tmp_value}"
        declare -a "${__b3bp_tmp_varname}"='("${!__b3bp_tmp_varname}" "${__b3bp_tmp_value}")'
      fi
    else
      # non-repeatables
      __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
      __b3bp_tmp_default="${!__b3bp_tmp_varname}"

      if [[ -z "${OPTARG}" ]]; then
        __b3bp_tmp_value=$((__b3bp_tmp_default + 1))
      fi

      printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"

      debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
    fi
  done
  set -o nounset # no more unbound variable references expected

  shift $((OPTIND-1))

  if [[ "${1:-}" = "--" ]] ; then
    shift
  fi
fi


### Automatic validation of required option arguments
##############################################################################

for __b3bp_tmp_varname in ${!__b3bp_tmp_has_arg_*}; do
  # validate only options which required an argument
  [[ "${!__b3bp_tmp_varname}" = "2" ]] || continue

  __b3bp_tmp_opt_short="${__b3bp_tmp_varname##*_}"
  __b3bp_tmp_varname="arg_${__b3bp_tmp_opt_short}"
  [[ "${!__b3bp_tmp_varname}" ]] && continue

  __b3bp_tmp_varname="__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt_short}"
  printf -v "__b3bp_tmp_opt_long" '%s' "${!__b3bp_tmp_varname}"
  [[ "${__b3bp_tmp_opt_long:-}" ]] && __b3bp_tmp_opt_long=" (--${__b3bp_tmp_opt_long//_/-})"

  help "Option -${__b3bp_tmp_opt_short}${__b3bp_tmp_opt_long:-} requires an argument"
done


### Cleanup Environment variables
##############################################################################

for __tmp_varname in ${!__b3bp_tmp_*}; do
  unset -v "${__tmp_varname}"
done

unset -v __tmp_varname


### Externally supplied __usage. Nothing else to do here
##############################################################################

if [[ "${__b3bp_external_usage:-}" = "true" ]]; then
  unset -v __b3bp_external_usage
  return
fi


### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit () {
  rm -rf "${ENV_DIR_TMP}"
  info "..."
}
trap __b3bp_cleanup_before_exit EXIT

# requires `set -o errtrace`
__b3bp_err_report() {
    local error_code=${?}
    error "Error in ${__file} in function ${1} on line ${2}"
    exit ${error_code}
}
# Uncomment the following line for always providing an error backtrace
trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR


### Command-line argument switches (like -d for debugmode, -h for showing helppage)
##############################################################################

# debug mode
if [[ "${arg_d:?}" = "1" ]]; then
  set -o xtrace
  PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  LOG_LEVEL="7"
  # Enable error backtracing
  trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
fi

# verbose mode
if [[ "${arg_v:?}" = "1" ]]; then
  set -o verbose
fi

# no color mode
if [[ "${arg_n:?}" = "1" ]]; then
  NO_COLOR="true"
fi

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
  # Help exists with code 1
  help "Help using ${0}"
fi

# force yes mode
if [[ "${arg_y:?}" = "1" ]]; then
  ENV_YES="true"
fi

# setup mode
if [[ "${arg_s:?}" = "1" ]]; then
  ENV_MODE="setup"
fi


### Validation. Error out if the things required for your script are not present
##############################################################################

#[[ "${arg_b:-}" ]] || help "Setting an \"example.yml\" file with -b or --bot is required"
#[[ "${LOG_LEVEL:-}" ]] || emergency "Cannot continue without LOG_LEVEL. "


### Runtime
##############################################################################

_fsAcquireScriptLock_
#_fsDockerKillContainer_
#_fsDockerKill_

_fsIntro_
echo
if [[ "${ENV_MODE}" = "setup" ]]; then
    _fsSetup_
else
    if [[ -n "${arg_b:-}" ]] && declare -p arg_b 2> /dev/null | grep -q '^declare \-a'; then
      for ymlFile in "${arg_b[@]}"; do
        _fsStart_ "${ymlFile}"
      done
    elif [[ -n "${arg_b:-}" ]]; then
      info "arg_b: ${arg_b}"
    else
      info "arg_b: 0"
    fi
fi
echo
_fsStats_
exit 0
