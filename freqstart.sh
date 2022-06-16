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
ENV_FS_VERSION='v0.0.4'
ENV_FS_SYMLINK="/usr/local/bin/${ENV_FS}"
ENV_FS_CONFIG="${ENV_DIR}/${ENV_FS}.config.json"
ENV_FS_STRATEGIES="${ENV_DIR}/${ENV_FS}.strategies.json"

ENV_DIR_USER_DATA="${ENV_DIR}/user_data"
ENV_DIR_USER_DATA_STRATEGIES="${ENV_DIR_USER_DATA}/strategies"
ENV_DIR_DOCKER="${ENV_DIR}/docker"
ENV_DIR_TMP="/tmp/${ENV_FS}"

ENV_BINANCE_PROXY="${ENV_DIR_USER_DATA}/binance_proxy.json"

ENV_FREQUI_JSON="${ENV_DIR_USER_DATA}/frequi.json"
ENV_FREQUI_SERVER_JSON="${ENV_DIR_USER_DATA}/frequi_server.json"
ENV_FREQUI_YML="${ENV_DIR}/${ENV_FS}_frequi.yml"

ENV_SERVER_IP="$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)"
ENV_SERVER_URL=""
ENV_INODE_SUM="$(ls -ali / | sed '2!d' | awk {'print $1'})"
ENV_HASH="$(xxd -l8 -ps /dev/urandom)"

ENV_YES=1
ENV_SETUP=1
ENV_KILL=1

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
	local _serverUrl=""
    
	[[ "$(_fsFileCheck_ "${_fsConfig}")" -eq 0 ]] && _serverUrl="$(_fsJsonGet_ "${_fsConfig}" "server_url")"    

    echo '###'
    echo '# FREQSTART: '"${_fsVersion}"
    echo '# Server ip: '"${_serverIp}"
    if [[ ! -z "${_serverUrl}" ]]; then
        echo "# Server url: ${_serverUrl}"
        ENV_SERVER_URL="${_serverUrl}"
    else
        echo "# Server url: not set"
    fi
    # credit: https://stackoverflow.com/a/51688023
    if [[ "${_inodeSum}" = '2' ]]; then
        echo '# Docker: not inside a container'
    else
        echo '# Docker: inside a container'
    fi
    echo '###'

    printf '%s\n' \
    "{" \
    "    \"version\": \"${_fsVersion}\"" \
    "    \"server_url\": \"${_serverUrl}\"" \
    "}" \
    > "${_fsConfig}"
    
    _fsFileExist_ "${_fsConfig}"
}

function _fsFileCheck_() {
        debug "function _fsFileCheck_"
    local _file="${1:-}" # optional: path to file

	if [[ -z "${_file}" ]]; then
        debug "File is empty."
        echo 1
    elif [[ -f "${_file}" ]]; then
        debug "File found: ${_file}"
        echo 0
    else
		debug "Cannot find file: ${_file}"
        echo 1
	fi
}
function _fsFileExist_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
        debug "function _fsFileExist_"
    local _file="${1:-}" # optional: path to file
    local _fileCheck=""
    local _fileCheck="$(_fsFileCheck_ "${_file}")"
        debug "_fileCheck: ${_fileCheck}"
	if [[ "${_fileCheck}" -eq 1 ]]; then
        emergency "Cannot create file: ${_file}" && exit 1
    fi
}


function _fsStats_() {
        debug "function _fsStats_"
	# some handy stats to get you an impression how your server compares to the current possibly best location for binance
	local _ping="$(ping -c 1 -w15 api3.binance.com | awk -F '/' 'END {print $5}')"
	local _memUsed="$(free -m | awk 'NR==2{print $3}')"
	local _memTotal="$(free -m | awk 'NR==2{print $2}')"
	local _time="$((time curl -X GET "https://api.binance.com/api/v3/exchangeInfo?symbol=BNBBTC") 2>&1 > /dev/null \
		| grep -o "real.*s" \
		| sed "s#real$(echo '\t')##")"

	echo "###"
    echo '# Ping avg. (Binance): '"${_ping}"'ms | Vultr "Tokyo" Server avg.: 1.290ms'
	echo '# Time to API (Binance): '"${_time}"' | Vultr "Tokyo" Server avg.: 0m0.039s'
	echo '# Used memory (Server): '"${_memUsed}"'MB  (max. '"${_memTotal}"'MB)'
	echo '# Get closer to Binance? Try Vultr "Tokyo" Server and get $100 usage for free:'
	echo '# https://www.vultr.com/?ref=9122650-8H'
	echo "###"
}

function _fsScriptLock_() {
        debug "function _fsScriptLock_"
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
            debug "Script lock activated: ${SCRIPT_LOCK}"
        else
            if declare -f "__b3bp_cleanup_before_exit" &>/dev/null; then
                emergency "Unable to acquire script lock: ${_lockDir}"
                emergency "If you trust the script isn't running, delete the lock dir"
            else
                emergency "Could not acquire script lock. If you trust the script isn't running, delete: ${_lockDir}" && exit 1
            fi
        fi
    else
        emergency "Temporary directory is not defined!" && exit 1
    fi
}

function _fsJsonGet_() {
        debug "function _fsJsonGet_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _jsonFile="${1}"
    local _jsonName="${2}"
    local _jsonValue=""
        debug "_jsonFile: ${_jsonFile}"
    if [[ "$(_fsFileCheck_ "${_jsonFile}")" -eq 0 ]]; then
        _jsonValue="$(cat "${_jsonFile}" \
        | grep -o "${_jsonName}\"\?: \"\?.*\"\?" \
        | sed "s,\",,g" \
        | sed "s,\s,,g" \
        | sed "s,${_jsonName}:,,")"
            debug "_jsonValue: ${_jsonValue}"
        if [[ ! -z "${_jsonValue}" ]]; then
            echo "${_jsonValue}"
        fi
    fi
}

function _fsJsonSet_() {
        debug "function _fsJsonSet_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _jsonFile="${1}"
    local _jsonName="${2}"
    local _jsonValue="${3}"
        debug "_jsonFile: ${_jsonFile}"
        debug "_jsonName: ${_jsonName}"
        debug "_jsonValue: ${_jsonValue}"
        debug "_jsonValue: IMPORTANT - Do not print value for non-verbose inputs."
    _fsFileExist_ "${_jsonFile}"
    
    # "name": "value"
    if [[ ! -z "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": \".*\"")" ]]; then
            debug '"name": "value"'
        sed -i "s,\"${_jsonName}\": \".*\",\"${_jsonName}\": \"${_jsonValue}\"," "${_jsonFile}"
    # name: "value"
    elif [[ ! -z "$(cat "${_jsonFile}" | grep -o "${_jsonName}: \".*\"")" ]]; then
            debug 'name: "value"'
        sed -i "s,${_jsonName}: \".*\",${_jsonName}: \"${_jsonValue}\"," "${_jsonFile}"
    # "name": value
    elif [[ ! -z "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": .*")" ]]; then
            debug '"name": value'
        sed -i "s,\"${_jsonName}\": .*,\"${_jsonName}\": ${_jsonValue}," "${_jsonFile}"
    # name: value
            debug 'name: value'
    elif [[ ! -z "$(cat "${_jsonFile}" | grep -o "${_jsonName}: .*")" ]]; then
        sed -i "s,${_jsonName}: .*,${_jsonName}: ${_jsonValue}," "${_jsonFile}"
    else
        emergency "Cannot find name: ${_jsonName}" && exit 1
    fi
}

function _fsCaseConfirmation_() {
        debug "function _fsCaseConfirmation_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _question="${1}"
    local _yesForce="${ENV_YES}"
    local _yesNo=""
    
    notice "${_question}"
    
    if [[ "${_yesForce}" -eq 0 ]]; then
        debug "Forcing confirmation with '-y' flag set."
        echo 0
    else
        while true; do
            read -p " (y/n) " _yesNo
            
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
    warning 'Response cannot be empty!'
}

function _fsIsUrl_() {
        debug "function _fsIsUrl_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _url="${1}"
        # credit: https://stackoverflow.com/a/55267709
    local _regex="^(https?|ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$"
    local _status=""

    if [[ "${_url}" =~ $_regex ]]; then
            # credit: https://stackoverflow.com/a/41875657
        _status="$(curl -o /dev/null -Isw '%{http_code}' "${_url}")"
            debug "_status: ${_status}"
        if [[ "${_status}" = "200" ]]; then
            echo 0
        else
            echo 1
        fi
    else
        emergency "Url is not valid: ${_url}" && exit 1
    fi
}

function _fsIsPort_() {
        debug "function _fsIsPort_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    _port="${1}"
        debug "_port: ${_port}"
        # credit: https://stackoverflow.com/a/32107419
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
        echo 0
    else
        emergency '"'"${_dockerPortUsed}"'" used port is not a number.' && exit 1
        echo 1
    fi
}

function _fsCdown_() {
        debug "function _fsCdown_"
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
        debug "function _fsIsAlphaDash_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    local _re='^[[:alnum:]_-]+$'
    
    if [[ ${1} =~ ${_re} ]]; then
        echo 0
    else
        echo 1
    fi
}

function _fsDedupeArray_() {
        debug "function _fsDedupeArray_"
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

function _fsRandomHex_() {
    #16-byte (128-bit) hex
        debug "function _fsRandomHex_"

    local _length="${1:-16}"
    local _string=""

    _string="$(xxd -l"${_length}" -ps /dev/urandom)"
        debug "_string: ${_string}"
    echo "${_string}"
}

function _fsRandomBase64_() {
    #24-byte (196-bit) base64
        debug "function _fsRandomBase64_"
    local _length="${1:-24}"
    local _string=""

    _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64)"
        debug "_string: ${_string}"
    echo "${_string}"
}

function _fsRandomBase64UrlSafe_() {
    #24-byte (196-bit) base64
        debug "function _fsRandomBase64UrlSafe_"

    local _length="${1:-32}"
    local _string=""

    _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64 | tr -d = | tr + - | tr / _)"
        debug "_string: ${_string}"
    echo "${_string}"
}

function _fsSymlink_() {
        debug "function _fsSymlink_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _symlink="${1}"
        debug "_symlink: ${_symlink}"
        # credit: https://stackoverflow.com/a/36180056
    if [ -L ${_symlink} ] ; then
        if [ -e ${_symlink} ] ; then
                debug "_symlink: Good link"
			echo 0
        else
                debug "_symlink: Broken link"
			sudo rm -f "${_symlink}"
            echo 1
        fi
    elif [ -e ${_symlink} ] ; then
                debug "_symlink: Not a link"
			sudo rm -f "${_symlink}"
            echo 1
    else
            debug "_symlink: Missing link"
        sudo rm -f "${_symlink}"
        echo 1
    fi
}

function _fsStrategy_() {
        debug "function _fsStrategy_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _strategyName="${1}"
    local _strategyFile=""
    local _strategyFileNew=""
    local _strategyUpdateCount=0
    local _strategyFileType=""
    local _strategyFileTypeName='unknown'
    local _strategyTmp="${ENV_DIR_TMP}/${_strategyName}_${ENV_HASH}"
    local _strategyDir="${ENV_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
    local _strategyUrls=""
    local _strategyUrlsDeduped=""
    local _strategyUrl=""
    local _fsStrategies="${ENV_FS_STRATEGIES}"
    
    if [[ "$(_fsFileCheck_"${_fsStrategies}")" -eq 1 ]]; then
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
        
        _fsFileExist_"${_fsStrategies}"
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
            if [[ "$(_fsIsUrl_ "${_strategyUrl}")" -eq 0 ]]; then
                _strategyFile="$(basename "${_strategyUrl}")"
                _strategyFileType="${_strategyFile##*.}"
                _strategyPath="${_strategyDir}/${_strategyFile}"

                if [ "${_strategyFileType}" == "py" ]; then
                    _strategyFileTypeName='strategy'
                elif [ "${_strategyFileType}" == "json" ]; then
                    _strategyFileTypeName='config'
                fi
                
                sudo curl -s -L "${_strategyUrl}" -o "${_strategyTmp}/${_strategyFile}"
            
                if [[ "$(_fsFileCheck_ "${_strategyPath}")" -eq 0 ]]; then
                    if [[ -n "$(cmp --silent "${_strategyUrl}" "${_strategyPath}")" ]]; then
                        cp -a "${_strategyTmp}/${_strategyFile}" "${_strategyPath}"
                        _strategyUpdateCount=$((_strategyUpdateCount+1))

                        info "\"${_strategyFile}\" \"${_strategyFileTypeName}\" updated."
                        
                        _fsFileExist_ "${_strategyPath}"
                    fi
                else
                    cp -a "${_strategyTmp}/${_strategyFile}" "${_strategyPath}"
                    
                    info "\"${_strategyFile}\" \"${_strategyFileTypeName}\" installed."
                    
                    _fsFileExist_ "${_strategyPath}"
                fi
            fi
        done
        
        sudo rm -rf "${_strategyTmp}"

        if [[ "${_strategyUpdateCount}" -eq 0 ]]; then
            info "\"${_strategyName}\" latest version installed."
            echo 0
        else
            notice "\"${_strategyName}\" strategy is updated. Restart bots!"
            echo 1
        fi
    else
        warning "\"${_strategyName}\" strategy not implemented."
        echo 0
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
	local _dockerRepo=""
	local _dockerTag=""
	local _dockerVersion=""
	local _dockerVersionLocal=""
	local _dockerManifest=""
    
    _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	_dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
	_dockerManifest="$(_fsDockerManifest_ "${_dockerRepo}" "${_dockerTag}")"
	
	# local version
	if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
		_dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerRepo}":"${_dockerTag}" \
		| sed 's/.*@//')"
	fi
        debug "_dockerVersionLocal: ${_dockerVersionLocal}"
	# docker version
	if [[ ! -z "${_dockerManifest}" ]]; then
		_dockerVersion="$(_fsJsonGet_ "${_dockerManifest}" "etag")"
	fi
        debug "_dockerVersion: ${_dockerVersion}"
	# compare versions
	if [[ -z "${_dockerVersion}" ]]; then
        # unkown
		echo 2
	else
		if [[ "${_dockerVersion}" = "${_dockerVersionLocal}" ]]; then
            # equal
			echo 0
		else
            # greater
			echo 1
		fi
	fi
}

function _fsDockerVarsName_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
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
        debug "function _fsDockerManifest_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerName=""
	local _dockerManifestTmp=""
    local _acceptM=""
    local _acceptML=""
    local _token=""
    local _status=""

	_dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
	_dockerManifestTmp="${ENV_DIR_TMP}/${_dockerName}_${_dockerTag}_${ENV_HASH}.json"
        debug "_dockerManifestTmp: ${_dockerManifestTmp}"
        # credit: https://stackoverflow.com/a/64309017
    _acceptM="application/vnd.docker.distribution.manifest.v2+json"
    _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
    _token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${_dockerRepo}:pull" | jq -r '.token')"

    curl -H "Accept: ${_acceptM}" -H "Accept: ${_acceptML}" -H "Authorization: Bearer ${_token}" -o "${_dockerManifestTmp}" \
    -I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}" || true && debug "Cannot receive docker manifest file."

    if [[ "$(_fsFileCheck_ "${_dockerManifestTmp}")" -eq 0 ]]; then
        _status="$(cat "${_dockerManifestTmp}" | grep -o '200 OK')"
            debug "_status: ${_status}"
        if [[ ! -z "${_status}" ]]; then
                echo "${_dockerManifestTmp}"
        fi
    fi
}

function _fsDockerImageInstalled_() {
        debug "function _fsDockerImageInstalled_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
    local _dockerImages=""
    
    _dockerImages="$(docker images -q "${_dockerRepo}:${_dockerTag}" 2> /dev/null)"
		debug "_dockerImages: ${_dockerImages}"
	if [[ ! -z "${_dockerImages}" ]]; then
		echo 0
	else
		echo 1
	fi
}

function _fsDockerYmlPorts_() {
        debug "function _fsDockerYmlPorts_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerPorts="${@}"
	local _dockerPort=""
	local _error=0
        debug "_dockerPorts[@]:"
        debug "$(printf '%s\n' "${_dockerPorts[@]}")"
    # get docker ports from yml file instead of port numbers
    for _dockerPort in ${_dockerPorts[@]}; do
		if [[ "${_dockerPort##*.}" == 'yml' ]]; then
			if [[ -f "${_dockerPort}" ]]; then
                _dockerPorts=()
                while read; do
                _dockerPorts+=( "$REPLY" )
                done < <(grep 'ports:' "${_dockerPort}" -A 1 | grep -o -E '[0-9]{4}.*' | sed 's,",,g' | sed 's,:.*,,')
				#readarray -t _dockerPorts < <(grep 'ports:' "${_dockerPort}" -A 1 | grep -o -E '[0-9]{4}.*' | sed 's,",,g' | sed 's,:.*,,')

				break
			else
				emergency "\"$(basename "${_dockerPorts}")\" file does not exist." && exit 1
			fi
		fi
	done
        debug "_dockerPorts[@]:"
        debug "$(printf '%s\n' "${_dockerPorts[@]}")"
	for _dockerPort in ${_dockerPorts[@]}; do
        if [[ "$(_fsIsPort_ "${_dockerPort}")" -eq 1 ]]; then
            _error=$((_error+1))
        fi
    done
        debug "_error: ${_error}"
	if [[ "${_error}" -eq 0 ]]; then
        printf '%s\n' "${_dockerPorts[@]}"
	fi
}

function _fsDockerPortsUsed_() {
        debug "function _fsDockerYmlPorts_"
	local _dockerPortsUsed=""
	local _dockerPortUsed=""
	local _error=0

    _dockerPortsUsed=()
	#readarray -t _dockerPortsUsed < <(docker ps -q -a | xargs -I {} docker port {} | sed 's,.*->,,' | grep -o -E '[0-9]{4}.*')
    while read; do
    _dockerPortsUsed+=( "$REPLY" )
    done < <(docker ps -q -a | xargs -I {} docker port {} | sed "s,.*->,," | grep -o -E "[0-9]{4}(.*)")
    #docker ps -q -a | xargs -I {} docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}} {{$p}} -> {{(index $conf 0).HostPort}} {{end}}' {}
        debug "_dockerPortsUsed[@]:"
        debug "$(printf '%s ' "${_dockerPortsUsed[@]}")"
	for _dockerPortUsed in ${_dockerPortsUsed[@]}; do
        if [[ "$(_fsIsPort_ "${_dockerPortUsed}")" -eq 1 ]]; then
            _error=$((_error+1))
        fi
    done
        debug "_error: ${_error}"
	if [[ "${_error}" -eq 0 ]]; then
        printf '%s\n' "${_dockerPortsUsed[@]}"
	fi
}

function _fsDockerPortCompare_() {
        debug "function _fsDockerPortCompare_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerPorts="${@}"
	local _dockerPort=""
	local _dockerPortsUsed=""
	local _dockerPortUsed=""
    local _dockerPortsCompare=""
	local _dockerPortCompare=""
	local _error=0
    
	_dockerPorts=("$(_fsDockerYmlPorts_ "${_dockerPorts}")")
	_dockerPortsUsed=("$(_fsDockerPortsUsed_)")
        debug "_dockerPorts[@]:"
        debug "$(printf '%s ' "${_dockerPorts[@]}")"
        debug "_dockerPortsUsed[@]:"
        debug "$(printf '%s ' "${_dockerPortsUsed[@]}")"
    if [[ ! -z "${_dockerPortsUsed}" ]]; then
            # credit: https://stackoverflow.com/a/28161520
        _dockerPortsCompare=("$(echo ${_dockerPorts[@]} ${_dockerPortsUsed[@]} | tr ' ' '\n' | sort | uniq -D | uniq)")

        for _dockerPortCompare in ${_dockerPortsCompare[@]}; do
            _error=$((_error+1))
            error "Port number \"${_dockerPortCompare}\" is already blocked."
        done
    fi
        debug "_error: ${_error}"
    if [[ "${_error}" -eq 0 ]]; then
        echo 0
    else
        echo 1
    fi
}

function _fsDockerImageStatus_() {
        debug "function _fsDockerImageStatus_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
    local _dockerDir="${ENV_DIR_DOCKER}"
    local _dockerRepo=""
    local _dockerTag=""
    local _dockerName=""
    local _dockerVersion=""
    local _dockerPath=""
    local _dockerStatus=2 # status: 0=install; 1=update; 2=error

    _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
    _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
    _dockerName="$(_fsDockerVarsName_ "${_docker}")"
    _dockerVersion="$(_fsDockerVarsVersion_ "${_docker}")"
    _dockerPath="$(_fsDockerVarsPath_ "${_docker}")"
        #debug "_dockerVersion: ${_dockerVersion}"
	if [[ ! -d "${_dockerDir}" ]]; then mkdir -p "${_dockerDir}"; fi

	if [[ "${_dockerVersion}" -eq 0 ]]; then
        # equal
		info "\"${_dockerName}:${_dockerTag}\" current image already installed." && _dockerStatus=0
	elif [[ "${_dockerVersion}" -eq 1 ]]; then
        # greater
        if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
			# update from docker hub
            warning "\"${_dockerName}:${_dockerTag}\" image update found."
            
            if [[ "$(_fsCaseConfirmation_ "Do you want to update now?")" -eq 0 ]]; then
                sudo docker pull "${_dockerRepo}"':'"${ENV_DOCKER_ARR[[_dockerTag]}"
                
                # make backup from local repository
                if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
                    sudo rm -f "${_dockerPath}"
                    sudo docker save -o "${_dockerPath}" "${_dockerRepo}:${_dockerTag}"
                    
                    if [[ -f "${_dockerPath}" ]]; then
                        debug "\"${_dockerRepo}:${_dockerTag}\" backup image created."
                    fi
                    
                    notice "\"${_dockerRepo}:${_dockerTag}\" image updated and installed." && _dockerStatus=1
                else
                    emergency "\"${_dockerRepo}:${_dockerTag}\" image could not be installed." && exit 1
                fi
            else
                warning "Skipping image update..." && _dockerStatus="install"
            fi
		else
			# install from docker hub
			sudo docker pull "${_dockerRepo}"':'"${_dockerTag}"
            
			# make backup from local repository
            if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
				sudo docker save -o "${_dockerPath}" "${_dockerRepo}"':'"${_dockerTag}"
                
				if [[ -f "${_dockerPath}" ]]; then
					debug "\"${_dockerRepo}:${_dockerTag}\" docker backup image created."
				fi
                
				notice "\"${_dockerRepo}:${_dockerTag}\" docker image installed." && _dockerStatus=0
			else
				emergency "\"${_dockerRepo}:${_dockerTag}\" could not be installed." && exit 1
			fi
		fi
	elif [[ "${_dockerVersion}" -eq 2 ]]; then
        # unknown
        warning "\"${_dockerName}:${_dockerTag}\" can not load online image version."
		# if docker is not reachable try to load local backup
        if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
			notice "\"${_dockerName}:${_dockerTag}\" image is installed but can not be verified." && _dockerStatus=0
		elif [[ -f "${_dockerPath}" ]]; then
			sudo docker load -i "${_dockerPath}"
            
            if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
				notice "\"${_dockerName}:${_dockerTag}\" backup image is installed." && _dockerStatus=0
			fi
		else
			emergency "\"${_dockerName}:${_dockerTag}\" can not install backup image." && exit 1
		fi
	fi
        debug "_dockerStatus (0=install; 1=update; 2=error): ${_dockerStatus}"
    # return status install, update, error
    echo "${_dockerStatus}"
}

function _fsDockerPs_() {
        debug "function _fsDockerPs_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dockerValue="${1}"
    local _dockerMode="${2:-}" #optional: show all docker container incl. non-active
    local _dockerPs=""
    local _dockerPsAll=""
    local _dockerMatching=1
        debug "_dockerValue: ${_dockerValue}"
        debug "_dockerMode (all|-): ${_dockerMode}"
        # credit: https://serverfault.com/a/733498
	if [[ "${_dockerMode}" = "all" ]]; then
        _dockerPsAll="$(docker ps -a --filter="name=${_dockerValue}" -q | xargs)"
        [[ -n ${_dockerPsAll} ]] && _dockerMatching=0
	else
        _dockerPs="$(docker ps --filter="name=${_dockerValue}" -q | xargs)"
        [[ -n ${_dockerPs} ]] && _dockerMatching=0
	fi
        debug "_dockerPs: ${_dockerPs}"
	if [[ "${_dockerMatching}" -eq 0 ]]; then
		echo 0
	else
		echo 1
	fi
}

function _fsDockerId2Name_() {
        debug "function _fsDockerId2Name_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerName=""
        debug "_dockerId: ${_dockerId}"
	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
        debug "_dockerName: ${_dockerName}"
	if [[ ! -z "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

function _fsDockerId2Port_() {
        debug "function _fsDockerId2Port_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerPort=""
        debug "_dockerId: ${_dockerId}"
	_dockerPort="$(sudo docker inspect --format="{{.Port}}" "${_dockerId}")"
        debug "_dockerPort: ${_dockerPort}"
	if [[ ! -z "${_dockerPort}" ]]; then
		echo "${_dockerPort}"
	fi
}

function _fsDockerRun_() {
        debug "function _fsDockerRun_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerRm="${3:-}" #optional: remove docker container on exit or error
	local _dockerName=""
	
    _dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"

	if [[ "$(_fsDockerImageStatus_ "${_dockerRepo}:${_dockerTag}")" -eq 1 ]]; then
        if [[ "$(_fsDockerPs_ "${_dockerName}")" -eq 0 ]]; then
            _fsDockerStop_ "${_dockerName}"
        fi
	fi

	if [[ "$(_fsDockerPs_ "${_dockerName}")" -eq 1 ]]; then
		if [[ "${_dockerRm}" = "rm" ]]; then
			cd "${_dir}" && \
				docker run --rm -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		else
			cd "${_dir}" && \
				docker run -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		fi
		
        if [[ "$(_fsDockerPs_ "${_dockerName}")" -eq 0 ]]; then
			notice "\"${_dockerName}\" activated."
		else
			emergency "\"${_dockerName}\" not activated." && exit 1
		fi
	else
		info "\"${_dockerName}\" is already active."
	fi
}

function _fsDockerStop_() {
        debug "function _fsDockerStop_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerName=""
    
	_dockerName="$(_fsDockerId2Name_ "${_dockerId}")"

    sudo docker update --restart no "${_dockerId}" 2>&1
    sudo docker stop "${_dockerId}" 2>&1
    sudo docker rm -f "${_dockerId}" 2>&1
    
    warning "  -> Container set \"restart\" to \"no\", stopped and removed: ${_dockerName}"
}

function _fsDockerYml_() {
        debug "function _fsDockerYml_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="${1}"
	local _ymlFile=""
	local _ymlFileType=""
    
    _ymlPath="${_dir}/${_ymlPath##*/}"
	_ymlFile="${_ymlPath##*/}"
	_ymlFileType="${_ymlFile##*.}"

	if [[ ! -z "${_ymlFileType}" ]]; then
        if [[ "${_ymlFileType}" = 'yml' ]]; then
            _fsFileExist_ "${_ymlPath}"

			echo "${_ymlPath}"
        else
            error "\"$(basename "${_ymlFile}")\" is not a \".yml\" file." && exit 1
        fi
	else
		error "\".yml\" file type is missing." && exit 1
	fi
}

function _fsDockerYmlImages_() {
        debug "function _fsDockerYmlImages_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _ymlPath="${1}"
	local _ymlImages=""
	local _ymlImagesDeduped=""
	local _ymlImage=""
    
	_ymlPath="$(_fsDockerYml_ "${_ymlPath}")"
        # credit: https://stackoverflow.com/a/39612060
    _ymlImages=()
    while read; do
    _ymlImages+=( "$REPLY" )
    done < <(grep "image:" "${_ymlPath}" \
    | sed "s,\s,,g" \
    | sed "s,image:,,g")
        debug "_ymlImages[@]:"
        debug "$(printf '%s\n' "${_ymlImages[@]}")"
    if [[ ! -z "${_ymlImages[@]}" ]]; then
        _ymlImagesDeduped=()
        while read; do
        _ymlImagesDeduped+=( "$REPLY" )
        done < <(_fsDedupeArray_ "${_ymlImages[@]}")
    fi
        debug "_ymlImagesDeduped[@]:"
        debug "$(printf '%s\n' "${_ymlImagesDeduped[@]}")"
    if [[ ! -z "${_ymlImagesDeduped[@]}" ]]; then
        for _ymlImage in ${_ymlImagesDeduped[@]}; do
            if [[ "$(_fsDockerImageStatus_ "${_ymlImage}")" -eq 0 ]]; then
                echo 0
            else
                echo 1
            fi
        done
    fi
}

function _fsDockerYmlStrategies_() {
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _ymlPath="${1}"
	local _ymlStrategies=""
	local _ymlStrategiesDeduped=""
	local _ymlStrategy=""

	_ymlPath="$(_fsDockerYml_ "${_ymlPath}")"

    _ymlStrategies=()
    while read; do
    _ymlStrategies+=( "$REPLY" )
    done < <(grep "strategy" "${_ymlPath}" \
    | grep -v "strategy-path" \
    | sed "s,\s,,g" \
    | sed "s,\-\-strategy,,g")
        debug "_ymlStrategies[@]:"
        debug "$(printf '%s\n' "${_ymlStrategies[@]}")"
    if [[ ! -z "${_ymlStrategies[@]}" ]]; then
        _ymlStrategiesDeduped=()
        while read; do
        _ymlStrategiesDeduped+=( "$REPLY" )
        done < <(_fsDedupeArray_ "${_ymlStrategies[@]}")
    fi
        debug "_ymlStrategiesDeduped[@]:"
        debug "$(printf '%s\n' "${_ymlStrategiesDeduped[@]}")"
    if [[ ! -z "${_ymlStrategiesDeduped[@]}" ]]; then
        for _ymlStrategy in ${_ymlStrategiesDeduped[@]}; do              
            if [[ "$(_fsStrategy_ "${_ymlStrategy}")" -eq 0 ]]; then
                echo 0
            else
                echo 1
            fi
        done
    fi
}

function _fsDockerYmlConfigs_() {
        debug "function _fsDockerYmlConfigs_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="${1}"
    local _ymlConfigsDeduped=""
    local _ymlConfigs=""
	local _ymlConfig=""
	local _ymlConfigNew=""
    local _error=0

	_ymlPath="$(_fsDockerYml_ "${_ymlPath}")"

    _ymlConfigs=()
    while read; do
    _ymlConfigs+=( "$REPLY" )
    done < <(echo "$(grep -e "\-\-config" -e "\-c" "${_ymlPath}" \
    | sed "s,\s,,g" \
    | sed "s,\-\-config,,g" \
    | sed "s,\-c,,g" \
    | sed "s,\/freqtrade\/,,g")")
        debug "_ymlConfigs[@]:"
        debug "$(printf '%s\n' "${_ymlConfigs[@]}")"
    if [[ ! -z "${_ymlConfigs[@]}" ]]; then
        _ymlConfigsDeduped=()
        while read; do
        _ymlConfigsDeduped+=( "$REPLY" )
        done < <(_fsDedupeArray_ "${_ymlConfigs[@]}")
    fi
        debug "_ymlConfigsDeduped[@]:"
        debug "$(printf '%s\n' "${_ymlConfigsDeduped[@]}")"
    if [[ ! -z "${_ymlConfigsDeduped[@]}" ]]; then
        for _ymlConfig in ${_ymlConfigsDeduped[@]}; do
                debug "_ymlConfig: ${_ymlConfig}"
            _ymlConfigNew="${_dir}/${_ymlConfig}"
                debug "_ymlConfigNew: ${_ymlConfigNew}"
            if [[ ! -f "${_ymlConfigNew}" ]]; then
                error "\"$(basename "${_ymlConfigNew}")\" config file does not exist."
                _error=$((_error+1))
            fi
        done
    fi
        debug "_error: ${_error}"
    if [[ "${_error}" -eq 0 ]]; then
        echo 0
    else
        echo 1
    fi
}

function _fsDockerComposeUp_() {
        debug "function _fsDockerComposeUp_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="${1}"
	local _ymlMode="${2:-}" #optional: force to restart container
	local _ymlFile=""
	local _ymlFileName=""
    local _ymlProject=""
    local _error=0
    local _dockerYmlImages=2
    local _dockerYmlStrategies=2
    local _dockerYmlConfigs=1

	_ymlPath="$(_fsDockerYml_ "${_ymlPath}")"
	_ymlFile="${_ymlPath##*/}"
	_ymlFileName="${_ymlFile%.*}"
    _ymlProject="$(echo "${_ymlFileName}" | sed "s,\-,_,g")"
    _dockerYmlImages="$(_fsDockerYmlImages_ "${_ymlPath}")"
    _dockerYmlStrategies="$(_fsDockerYmlStrategies_ "${_ymlPath}")"
    _dockerYmlConfigs="$(_fsDockerYmlConfigs_ "${_ymlPath}")"

    if [[ -f "${_ymlPath}" ]]; then
        notice "Start \"$(basename "${_ymlPath}")\" docker projects..."
    
        [[ "${_dockerYmlImages}" -eq 1 ]] && _ymlMode="force"
        [[ "${_dockerYmlImages}" -eq 2 ]] && _error=$((_error+1))
        [[ "${_dockerYmlStrategies}" -eq 1 ]] && _ymlMode="force"
        [[ "${_dockerYmlStrategies}" -eq 2 ]] && _error=$((_error+1))
        [[ "${_dockerYmlConfigs}" -eq 1 ]] && _error=$((_error+1))
            debug "_error: ${_error}"
            debug "_fsDockerPortCompare_: $(_fsDockerPortCompare_ "${_ymlPath}")"
        if [[ "${_error}" -eq 0 ]]; then
            if [[ "${_ymlMode}" = "force" ]]; then
                cd "${_dir}" && \
                sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" up -d --force-recreate
            else
                if [[ "$(_fsDockerPortCompare_ "${_ymlPath}")" -eq 0 ]]; then
                    cd "${_dir}" && \
                    sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" up -d
                elif [[ "$(_fsCaseConfirmation_ "Stop container that block ports?")" -eq 0 ]]; then
                    _fsDockerProjects_ "${_ymlPath}" "kill"

                    cd "${_dir}" && \
                    sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" up -d
                fi
                
            fi

            _fsDockerProjects_ "${_ymlPath}" "validate"
        else
            alert "Too many errors. Review \"$(basename "${_ymlPath}")\" and restart script!"
        fi
    fi
}

function _fsDockerComposeKill_() {
        debug "function _fsDockerComposeKill_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    local _ymlPath="${1}"
    local _ymlFile=""
    
    _ymlPath="$(_fsDockerYml_ "${_ymlPath}")"
    _ymlFile="$(basename "${_ymlPath}")"
    
    _fsFileExist_ "${_ymlPath}"
    
    notice "Kill \"${_ymlFile}\" docker projects..."
    _fsDockerProjects_ "${_ymlPath}" "kill"
}

function _fsDockerProjects_() {
        debug "function _fsDockerProjects_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _dir="${ENV_DIR}"
	local _ymlPath="${1}"
	local _ymlMode="${2}"
	local _ymlFile=""
	local _ymlFileName=""
    local _ymlProject=""
    local _dockerProjects=""
    local _dockerProject=""
    local _dockerProjectNotrunc=""
    local _dockerProjectName=""

    _ymlPath="$(_fsDockerYml_ "${_ymlPath}")"
    _ymlFile="${_ymlPath##*/}"
    _ymlFileName="${_ymlFile%.*}"
    _ymlProject="$(echo "${_ymlFileName}" | sed "s,\-,_,g")"

    if [[ -f "${_ymlPath}" ]]; then
        _dockerProjects=("$(cd "${_dir}" && \
        sudo docker-compose -f "${_ymlFile}" -p "${_ymlProject}" ps -q 2> /dev/null)")
            debug "_dockerProjects[@]:"
            debug "$(printf '%s\n' "${_dockerProjects[@]}")"
        if [[ ! -z "${_dockerProjects[@]}" ]]; then
            if [[ "${_ymlMode}" = "validate" ]]; then
                _fsCdown_ 10 'for any errors...'
            fi
        
            for _dockerProject in $_dockerProjects; do
                    debug "_dockerProject: ${_dockerProject}"
                _dockerProjectName="$(_fsDockerId2Name_ "${_dockerProject}")"
                    debug "_dockerProjectName: ${_dockerProjectName}"
                _dockerProjectNotrunc="$(docker ps -q --no-trunc | grep "${_dockerProject}")"
                    debug "_dockerProjectNotrunc: ${_dockerProjectNotrunc}"
                
                if [[ "${_ymlMode}" = "validate" ]]; then              
                        # credit: https://serverfault.com/a/935674
                    if [[ -z "${_dockerProject}" ]] || [[ -z "${_dockerProjectNotrunc}" ]]; then
                        error "\"${_dockerProjectName}\" container is not running."
                        
                        _fsDockerStop_ "${_dockerProject}"
                    else
                        notice "\"${_dockerProjectName}\" container is running."
                    fi
                elif [[ "${_ymlMode}" = "kill" ]]; then
                    if [[ "$(_fsCaseConfirmation_ "Kill \"${_dockerProjectName}\" container?")" -eq 0 ]]; then
                        _fsDockerStop_ "${_dockerProject}"
                    fi
                fi
            done
        else
            info "No docker projects found..."
        fi
    fi
}

function _fsDockerKill_() {
        debug "function _fsDockerKill_"
	_fsDockerKillContainer_
	
	sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
}

function _fsDockerKillContainer_() {
	sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
}


### FREQSTART - start
##############################################################################

function _fsStart_ {
        debug "function _fsStart_"
	local _dockerYml="${1:-}"
	local _dockerCompose="${ENV_DIR}/$(basename "${_dockerYml}")"
    local _symlink="${ENV_FS_SYMLINK}"
		
	if [[ "$(_fsSymlink_ "${_symlink}")" -eq 1 ]]; then
		alert 'Start setup first with: ./'"${ENV_FS}"'.sh --setup' && exit 1
	elif [[ "${ENV_KILL}" -eq 0 ]]; then
        _fsDockerComposeKill_ "${_dockerCompose}"
    else
        _fsDockerComposeUp_ "${_dockerCompose}"
	fi
}


### FREQSTART - setup
##############################################################################

function _fsSetup_() {
        debug "function _fsSetup_"
    local _symlink="${ENV_FS_SYMLINK}"
    local _symlinkSource="${ENV_DIR}/${ENV_FS}.sh"
    
    _fsSetupServer_
    _fsSetupNtp_
    _fsSetupFreqtrade_
    _fsSetupBinanceProxy_
    _fsSetupFrequi_
    _fsSetupExampleBot_
    
	if [[ "$(_fsSymlink_ "${_symlink}")" -eq 1 ]]; then
        sudo rm -f "${_symlink}"
		sudo ln -sfn "${_symlinkSource}" "${_symlink}"
	fi
	
	if [[ "$(_fsSymlink_ "${_symlink}")" -eq 0 ]]; then
        echo
		notice 'Setup finished!'
		info "-> Run freqtrade bots with: ${ENV_FS} -b example.yml"
		info "  1. \".yml\" files can contain one or multiple bots."
		info "  2. Configs and strategies files are checked for existense."
		info "  3. Checking docker images for updates before start."
	else
		emergency "Cannot create symlink: \"${_symlink}\"" && exit 1
	fi
}

function _fsSetupPkgs_() {
        debug "function _fsSetupPkgs_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}"

    local _pkgs="${@}"
    local _pkg=""
    local _status=""
    local _getDocker="${ENV_DIR_DOCKER}/get-docker.sh"

    for _pkg in ${_pkgs[@]}; do
            debug "_pkg: ${_pkg}"
        if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
            debug "Already installed: ${_pkg}"
        else
            if [[ "${_pkg}" = 'docker-ce' ]]; then
                # docker setup
                mkdir -p "${ENV_DIR_DOCKER}"
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

            if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
                info "Installed: ${_pkg}"
            else
                emergency "Cannot install: ${_pkg}" && exit 1
            fi
        fi
    done
}

function _fsSetupPkgsStatus_() {
        debug "function _fsDockerProjects_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
    
    local _pkg="${1}"
    local _status=""
    
    _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" 2>/dev/null | grep "install ok installed")"
        debug "_status: ${_status}"
    if [[ ! -z "${_status}" ]]; then
        echo 0
    else
        echo 1
    fi
}

function _fsSetupServer_() {
        debug "function _fsSetupServer_"
    echo
    info 'SETUP SERVER:'
    
    sudo apt-get update

    _fsSetupPkgs_ "git" "curl" "jq" "docker-ce"
    
    info 'Update server and install unattended-upgrades. Reboot may be required!'
    
    if [[ "$(_fsCaseConfirmation_ "Skip server update?")" -eq 0 ]]; then
        warning 'Skipping server update...'
    else
        sudo apt -o Dpkg::Options::="--force-confdef" dist-upgrade -y && \
        sudo apt install -y unattended-upgrades && \
        sudo apt autoremove -y

        if sudo test -f /var/run/reboot-required; then
            warning 'A reboot is required to finish installing updates.'
            if [[ "$(_fsCaseConfirmation_ "Skip reboot now?")" -eq 0 ]]; then
                warning 'Skipping reboot...'
            else
                sudo reboot
            fi
        else
            info "A reboot is not required."
        fi
    fi
}

function _fsSetupNtp_() {
        debug "function _fsSetupNtp_"
    echo
    info "SETUP NTP:"
    info "(Timezone to UTC)"

    if [[ "$(_fsSetupNtpCheck_)" = 1 ]]; then
        _fsSetupPkgs_ "chrony"
        
        if [[ "$(_fsSetupNtpCheck_)" = 1 ]]; then
            emergency 'NTP not active or not synchronized.'
        else
            notice 'NTP activated and synchronized.'
        fi
    else
        info 'NTP is active and synchronized.'
    fi
}

function _fsSetupNtpCheck_() {
        debug "function _fsSetupNtpCheck"
    local timentp=""
    local timeutc=""
    local timesyn=""

    timentp="$(timedatectl | grep -o 'NTP service: active')"
        debug "timentp: ${timentp}"
    timeutc="$(timedatectl | grep -o '(UTC, +0000)')"
        debug "timeutc: ${timeutc}"
    timesyn="$(timedatectl | grep -o 'System clock synchronized: yes')"
        debug "timesyn: ${timesyn}"

    if [[ ! -z "${timentp}" ]] || [[ ! -z  "${timeutc}" ]] || [[ ! -z  "${timesyn}" ]]; then
        echo 0
    else
        echo 1
    fi
}

function _fsSetupFreqtrade_() {
        debug "function _fsSetupFreqtrade_"
    local _dir="${ENV_DIR}"
    local _docker="freqtradeorg/freqtrade:stable"
    local _dockerYml="${_dir}/${ENV_FS}_setup.yml"
    local _dockerImageStatus=""
    local _dirUserData="${ENV_DIR_USER_DATA}"
    local _configKey=""
    local _configSecret=""
    local _configName=""
    local _configFile=""
    local _configFileTmp=""
    local _configFileBackup=""

    echo
    info 'SETUP FREQTRADE:'
    
    _fsDockerImageStatus_ "${_docker}"

    if [[ ! -d "${_dirUserData}" ]]; then
        _fsSetupFreqtradeYml_
        
        cd "${_dir}" && \
        docker-compose --file "$(basename "${_dockerYml}")" run --rm freqtrade create-userdir --userdir "$(basename "${_dirUserData}")"
    fi

    if [[ ! -d "${_dirUserData}" ]]; then
        emergency "Directory cannot be created: ${_dirUserData}" && exit 1
    else
        debug "Directory created: ${_dirUserData}"
    fi

    info "A config is needed to start a bot!"

    if [[ "$(_fsCaseConfirmation_ "Skip creating a config?")" -eq 0 ]]; then
       warning "Skipping create a config..."
    else
        while true; do
            info "Choose a name for your config. For default name press <ENTER>."
            read -p " (filename) " _configName
            case ${_configName} in
                "")
                    _configName="config"
                ;;
                *)
                    _configName="${_configName%.*}"

                    if [[ "$(_fsIsAlphaDash_ "${_configName}")" -eq 1 ]]; then
                        warning "Only alpha-numeric or dash or underscore characters are allowed!"
                        _configName=""
                    fi
                ;;
            esac
            
            if [[ ! -z "${_configName}" ]]; then
                info "The config file name will be: ${_configName}.json"
                if [[ "$(_fsCaseConfirmation_ "Is this correct?")" -eq 0 ]]; then
                    break
                fi
            fi
        done
        
        _configFile="${_dirUserData}/${_configName}.json"
        _configFileTmp="${_dirUserData}/${_configName}.tmp.json"
        _configFileBackup="${_dirUserData}/${_configName}.bak.json"

        if [[ "$(_fsFileCheck_ "${_configFile}")" -eq 0 ]]; then
            warning 'The config "'"$(basename ${_configFile})"'" already exist.'
            if [[ "$(_fsCaseConfirmation_ "Replace the existing config file?")" -eq 1 ]]; then
                _configName=""
                rm -f "${_dockerYml}"
            fi
        fi
    fi
        debug "_configName: ${_configName}"
        debug "_configFile: ${_configFile}"
        debug "_configFileTmp: ${_configFileTmp}"
        debug "_configFileBackup: ${_configFileBackup}"

    if [[ ! -z "${_configName}" ]] && [[ -d "${_dirUserData}" ]]; then
        _fsSetupFreqtradeYml_
        rm -f "${_configFileTmp}"
        
        cd "${_dir}" && \
        docker-compose --file "$(basename "${_dockerYml}")" \
        run --rm freqtrade new-config --config "$(basename "${_dirUserData}")/$(basename "${_configFileTmp}")"
        
        rm -f "${_dockerYml}"

        _fsFileExist_ "${_configFileTmp}"

        if [[ "$(_fsCaseConfirmation_ "Enter your exchange api KEY and SECRET now? (recommended)")" -eq 0 ]]; then
            while true; do
                notice "Enter your KEY for exchange api (ENTRY HIDDEN):"
                read -s _configKey
                echo
                case ${_configKey} in 
                    "")
                        _fsCaseEmpty_
                        ;;
                    *)
                        _fsJsonSet_ "${_configFileTmp}" "key" "${_configKey}"
                        info "KEY is set in: ${_configFile}"
                        break
                        ;;
                esac
            done

            while true; do
                notice 'Enter your SECRET for exchange api (ENTRY HIDDEN):'
                read -s _configSecret
                echo
                case ${_configSecret} in 
                    "")
                        _fsCaseEmpty_
                        ;;
                    *)
                        _fsJsonSet_ "${_configFileTmp}" "secret" "${_configSecret}"
                        info "SECRET is set in: ${_configFile}"
                        break
                        ;;
                esac
            done
        else
            warning "Enter your exchange api KEY and SECRET to: ${_configFile}"
        fi
        
        cp -a "${_configFileTmp}" "${_configFile}"
        cp -a "${_configFileTmp}" "${_configFileBackup}"

        rm -f "${_configFileTmp}"
    fi
}

function _fsSetupFreqtradeYml_() {
        debug "function _fsSetupFreqtradeYml_"
    local _dir="${ENV_DIR}"
    local _dockerYml="${_dir}/${ENV_FS}_setup.yml"
    local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"
        debug "_dockerYml: ${_dockerYml}"
    if [[ "$(_fsFileCheck_ "${_dockerYml}")" -eq 1 ]]; then
        curl -s -L "${_dockerGit}" -o "${_dockerYml}"
        
        _fsFileExist_ "${_dockerYml}"
    fi
}

_fsSetupBinanceProxy_() {
        debug "function _fsSetupBinanceProxy_"
    local _binanceProxy="${ENV_BINANCE_PROXY}"
    local _docker="nightshift2k/binance-proxy:latest"
    local _dockerRepo=""
    local _dockerTag=""
    local _dockerName=""
    local _dockerActive=""

        debug "_docker: ${_docker}"
    _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
        debug "_dockerRepo: ${_dockerRepo}"
    _dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
        debug "_dockerTag: ${_dockerTag}"
    _dockerName="$(_fsDockerVarsName_ "${_docker}")"
        debug "_dockerName: ${_dockerName}"
    _dockerActive="$(_fsDockerPs_ "${_dockerName}")"

    echo
    info "SETUP BINANCE-PROXY:"
    info "(Ports: 8090-8091/tcp)"
        debug "_dockerActive: ${_dockerActive}"
    if [[ "${_dockerActive}" -eq 0 ]]; then
        info "\"${_dockerName}\" is already running."
        
        _fsDockerRun_ "${_dockerRepo}" "${_dockerTag}" "rm"
    else
        if [[ "$(_fsCaseConfirmation_ "Install \"binance-proxy\" and start now?")" -eq 0 ]]; then
            _fsDockerImageStatus_ "${_docker}"

            if [[ "$(_fsFileCheck_ "${_binanceProxy}")" -eq 1 ]]; then
                printf "%s\n" \
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
                
                _fsFileExist_ "${_binanceProxy}"
            fi
            
            _fsDockerRun_ "${_dockerRepo}" "${_dockerTag}" "rm"
        else
            warning "Skipping installation..."
        fi
    fi
}

function _fsSetupFrequi_() {
        debug "function _fsSetupFrequi_"
    local _dockerName="${ENV_FS}_frequi"
    local _serverUrl="${ENV_SERVER_URL}"
    local _yesForce="${ENV_YES}"
    local _nr=""
    local _setup=1
    
    echo
    info 'FREQUI: (Webserver API)'
    
	if [[ "$(_fsDockerPs_ "${_dockerName}")" -eq 0 ]]; then
        info "\"FreqUI\" is active: ${_serverUrl}"
        if [[ "$(_fsCaseConfirmation_ "Skip reconfigure \"FreqUI\" now?")" -eq 0 ]]; then
            _setup=1
        else
            _setup=0
        fi
    else
        if [[ "$(_fsCaseConfirmation_ "Install \"FreqUI\" now?")" -eq 0 ]]; then
            _setup=0
        else
            _setup=1
        fi
    fi
        debug "_setup: ${_setup}"
    if [[ "${_setup}" -eq 0 ]];then
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
            
            if [[ "${_yesForce}" -eq 1 ]]; then
                read -p " (1/2/3) " _nr
            else
                local _nr="3"
            fi
            case ${_nr} in 
                [1])
                    info "Continuing with 1) ..."
                    _fsSetupNginxOpenssl_
                    break
                    ;;
                [2])
                    info "Continuing with 2) ..."
                    _setupNginxLetsencrypt_
                    break
                    ;;
                [3])
                    info "Continuing with 3) ..."
                    break
                    ;;
                *)
                    _fsCaseInvalid_
                    ;;
            esac
        done
        
        _fsSetupFrequiJson_
        _fsSetupFrequiCompose_
    else
        warning "Skipping \"FreqUI\" installation..."
    fi
}

function _fsSetupNginx_() {
        debug "function _fsSetupNginx_"
    local _confPath="/etc/nginx/conf.d"
    local _confPathFrequi="${_confPath}/frequi.conf"
    local _confPathNginx="${_confPath}/default.conf"
    local _serverName="${ENV_SERVER_IP}"
        debug "_serverName: ${_serverName}"
    ENV_SERVER_URL="http://${_serverName}"

    _fsSetupPkgs_ "nginx"
    printf '%s\n' \
    "server {" \
    "    listen 80;" \
    "    server_name ${_serverName};" \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:9999;" \
    "    }" \
    "}" \
    "server {" \
    "    listen 9000-9100;" \
    "    server_name ${_serverName};" \
    "    location / {" \
    "        proxy_set_header Host \$host;" \
    "        proxy_set_header X-Real-IP \$remote_addr;" \
    "        proxy_pass http://127.0.0.1:\$server_port;" \
    "    }" \
    "}" \
    > "${_confPathFrequi}"

    _fsFileExist_ "${_confPathFrequi}"
    [[ "$(_fsFileCheck_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}.disabled"

    sudo rm -f "/etc/nginx/sites-enabled/default"
    
    #sudo ufw allow http/tcp > /dev/null
    sudo ufw allow "Nginx Full" > /dev/null

    _fsSetupNginxRestart_
}

function _fsSetupNginxRestart_() {
        debug "function _fsSetupNginxRestart_"
    # kill and start again
    # >/dev/null 2>&1
    if [[ ! -z "$(sudo nginx -t 2>&1 | grep -ow "failed")" ]]; then
        emergency "Error in nginx config file."
        exit 1
    fi

    sudo /etc/init.d/nginx stop
    sudo pkill -f nginx & wait $!
    sudo /etc/init.d/nginx start
    #sudo systemctl start nginx
    #sudo nginx -s reload
    #sudo systemctl reload nginx 2>/dev/null
}

function _fsSetupNginxOpenssl_() {
        debug "function _fsSetupNginxOpenssl_"
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
        debug "function _setupNginxLetsencrypt_"
    local _domain=""
    local _domainIp=""
    local _serverIp="${ENV_SERVER_IP}"
    
    while true; do
        read -p "Enter your domain (www.example.com): " _domain
        
        if [[ "${_domain}" = "" ]]; then
            _fsCaseEmpty_
        else
            if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_domain}\" correct?")" -eq 0 ]]; then
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

function _fsSetupNginxCertbot_() {
        debug "function _fsSetupNginxCertbot_"
    [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

    local _domain="${1}"
    
    _fsSetupPkgs_ certbot python3-certbot-nginx
    
    sudo certbot --nginx -d "${_domain}"
}

function _fsSetupNginxConfSecure_() {
        debug "function _fsSetupNginxConfSecure_"
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
        "    listen 9000-9900 ssl;" \
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
        "    listen 9000-9990 ssl http2;" \
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

    #sudo ufw allow https/tcp > /dev/null
    
    sudo rm -f /etc/nginx/sites-enabled/default*

    _fsSetupNginxRestart_
}

function _fsSetupFrequiJson_() {
        debug "function _fsSetupFrequiJson_"
    local _frequiJson="${ENV_FREQUI_JSON}"
    local _frequiJwt=""
    local _frequiUsername=""
    local _frequiPassword=""
    local _frequiPasswordCompare=""
    local _frequiTmpUsername=""
    local _frequiTmpPassword=""
    local _frequiCors="${ENV_SERVER_URL}"
    local _yesForce="${ENV_YES}"
    local _setup=1
    
    _frequiJwt="$(_fsJsonGet_ "${_frequiJson}" "jwt_secret_key")"
    _frequiUsername="$(_fsJsonGet_ "${_frequiJson}" "username")"
    _frequiPassword="$(_fsJsonGet_ "${_frequiJson}" "password")"

    if [[ -z "${_frequiJwt}" ]]; then
        _frequiJwt="$(_fsRandomBase64UrlSafe_)"
    fi

    if [[ ! -z "${_frequiUsername}" ]] || [[ ! -z "${_frequiPassword}" ]]; then
        warning "Login data for \"FreqUI\" already found."
        
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
        debug "_frequiJwt: ${_frequiJwt}"
        debug "_frequiUsername: ${_frequiUsername}"
        debug "_frequiPassword: ${_frequiPassword}"
    if [[ "${_setup}" = 0 ]]; then
        info "Create your login data for \"FreqUI\" now!"
            # create username
        while true; do
            read -p 'Enter username: ' _frequiUsername
                debug "_frequiUsername: ${_frequiUsername}"
            if [[ ! -z "${_frequiUsername}" ]]; then
                if [[ "$(_fsCaseConfirmation_ "Is the username \"${_frequiUsername}\" correct?")" -eq 0 ]]; then
                    break
                else
                    info "Try again!"
                fi
            fi
        done
            # create password - NON VERBOSE
        while true; do
            notice 'Enter password (ENTRY HIDDEN):'
            read -s _frequiPassword
            echo
            case ${_frequiPassword} in 
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
        # create frequi json for bots
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

        _fsFileExist_ "${_frequiJson}"
    fi
}

function _fsSetupFrequiCompose_() {
        debug "function _fsSetupFrequiCompose_"
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
    "      --strategy-path /freqtrade/user_data/strategies/${_frequiStrategy}" \
    "      --config /freqtrade/user_data/$(basename ${_frequiJson})" \
    "      --config /freqtrade/user_data/$(basename ${_frequiServerJson})" \
    > "${_frequiYml}"

    _fsFileExist_ "${_frequiYml}"
    [[ "$(_fsFileCheck_ "${_frequiServerLog}")" -eq 0 ]] &&  rm -f "${_frequiServerLog}"
    _fsDockerComposeUp_ "${_frequiYml}" 'force'

}

function _fsSetupExampleBot_() {
        debug "function _fsSetupExampleBot_"
    local _userData="${ENV_DIR_USER_DATA}"
    local _botExampleName="${ENV_FS}_example"
    local _botExampleYml="${ENV_DIR}/${_botExampleName}.yml"
    local _botExampleConfig=""
    local _botExampleConfigName=""
    local _frequiJson=""
    local _binanceProxyJson=""
    local _botExampleExchange=""
    local _botExampleCurrency=""
    local _botExampleKey=""
    local _botExampleSecret=""
    local _botExamplePairlist=""
    local _botExampleLog="${ENV_DIR_USER_DATA}/logs/${ENV_FS}_example.log"
    local _setup=1
    local _error=0

    echo
    info 'EXAMPLE (NFI):'

    _frequiJson="$(basename "${ENV_FREQUI_JSON}")"
    _binanceProxyJson="$(basename "${ENV_BINANCE_PROXY}")"

    info "Creating an example bot \".yml\" file for dryrun on Binance."
    info "Incl. latest \"NostalgiaForInfinityX\" strategy, \"FreqUI\" and proxy"
        
    if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" -eq 0 ]]; then
        warning "Skipping example bot..."
    else
        while true; do
            info "What is the name of your config file? For default name press <ENTER>."
            read -p " (filename) " _botExampleConfigName
            case ${_botExampleConfigName} in
                "")
                    _botExampleConfigName="config"
                ;;
                *)
                    _botExampleConfigName="${_botExampleConfigName%.*}"

                    if [[ "$(_fsIsAlphaDash_ "${_botExampleConfigName}")" -eq 0 ]]; then
                        warning "Only alpha-numeric or dash or underscore characters are allowed!"
                        _botExampleConfigName=""
                    fi
                ;;
            esac
            if [[ ! -z "${_botExampleConfigName}" ]]; then
                info "The config file will be: \"${_botExampleConfigName}.json\""
                if [[ "$(_fsCaseConfirmation_ "Is this correct?")" -eq 0 ]]; then
                    _botExampleConfig="${_userData}/${_botExampleConfigName}.json"

                    if [[ -f "${_botExampleConfig}" ]]; then
                        _botExampleExchange="$(_fsJsonGet_ "${_botExampleConfig}" 'name')"
                        _botExampleCurrency="$(_fsJsonGet_ "${_botExampleConfig}" 'stake_currency')"
                        _botExampleKey="$(_fsJsonGet_ "${_botExampleConfig}" 'key')"
                        _botExampleSecret="$(_fsJsonGet_ "${_botExampleConfig}" 'secret')"
                        
                        _setup=0
                        break
                    else
                        error "\"$(basename "${_botExampleConfig}")\" config file does not exist."
                        _botExampleConfigName=""
                        
                        if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" -eq 0 ]]; then
                            _setup=1
                            break
                        fi
                    fi
                fi
            fi
        done
        
        if [[ "${_setup}" -eq 0 ]]; then
            if [[ -z "${_botExampleKey}" || -z "${_botExampleSecret}" ]]; then
                error 'Your exchange api KEY and/or SECRET is missing.'
                _error=1
            fi
            
            if [[ "${_botExampleExchange}" != 'binance' ]]; then
                error 'Only "Binance" is supported for example bot.'
                _error=1
            fi

            if [[ "${_botExampleCurrency}" == 'USDT' ]]; then
                _botExamplePairlist='pairlist-volume-binance-busd.json'
            elif [[ "${_botExampleCurrency}" == 'BUSD' ]]; then
                _botExamplePairlist='pairlist-volume-binance-busd.json'
            else
                error 'Only USDT and BUSD pairlist are supported.'
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
                
                _fsFileExist_"${_botExampleYml}"
                
                [[ "$(_fsFileCheck_ "${_botExampleLog}")" -eq 0 ]] &&  rm -f "${_botExampleLog}"

                info "1) The docker path is different from the real path and starts with \"/freqtrade\"."
                info "2) Add your exchange api KEY and SECRET to: \"exampleconfig_secret.json\""
                info "3) Change port number \"9001\" to an unused port between 9000-9100 in \"${_botExampleYml}\" file."
                notice "Run example bot with: ${ENV_FS} -b $(basename "${_botExampleYml}")"
            else
                alert "Too many errors. Cannot create example bot!"
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
  -h --help        This page
  -s --setup       Install and update
  -b --bot  [arg]  Start any ".yml" project
  -k --kill        Kill any ".yml" project
  -y --yes         Yes on every confirmation
  -n --no-color    Disable color output
  -d --debug       Enables debug mode
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
  info "~ Fin ~"
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
  #set -o xtrace
  PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  LOG_LEVEL="7"
  # Enable error backtracing
  trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
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
  ENV_YES=0
fi

# setup mode
if [[ "${arg_s:?}" = "1" ]]; then
  ENV_SETUP="true"
fi

# kill mode
if [[ "${arg_k:?}" = "1" ]]; then
  ENV_KILL="true"
fi

### Validation. Error out if the things required for your script are not present
##############################################################################

#[[ "${arg_b:-}" ]] || help "Setting an \"example.yml\" file with -b or --bot is required"

if [[ "${arg_k:?}" = "1" ]]; then
    [[ "${arg_b:-}" ]] || help "Setting an \"example.yml\" file with -b or --bot is required with -k or --kill"
fi

#[[ "${LOG_LEVEL:-}" ]] || emergency "Cannot continue without LOG_LEVEL. "


### Runtime
##############################################################################

# restrict script to run only once a time
_fsScriptLock_

# DEBUG - uncomment to remove docker container or images
#_fsDockerKillContainer_
#_fsDockerKill_

_fsIntro_
if [[ "${ENV_SETUP}" = "true" ]]; then
    _fsSetup_
else
    if [[ -n "${arg_b:-}" ]] && declare -p arg_b 2> /dev/null | grep -q '^declare \-a'; then
      for bot in "${arg_b[@]}"; do
        _fsStart_ "${bot}"
      done
    elif [[ -n "${arg_b:-}" ]]; then
        help "Help using ${0}"
    else
        help "Help using ${0}"
    fi
fi
_fsStats_
exit 0
