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
NO_COLOR="${NO_COLOR:-}"  # true = disable color. otherwise autodetected

# FREQSTART - variables
FS_NAME="freqstart"
FS_VERSION='v0.1.1'
FS_SYMLINK="/usr/local/bin/${FS_NAME}"

FS_DIR="${__dir}"
if [[ -L "${FS_SYMLINK}" ]] && [[ -e "${FS_SYMLINK}" ]]; then
  FS_DIR="$(dirname "$(readlink -f "${FS_SYMLINK}")")"
fi
FS_DIR_TMP="/tmp/${FS_NAME}"
FS_DIR_DOCKER="${FS_DIR}/docker"
FS_DIR_USER_DATA="${FS_DIR}/user_data"
FS_DIR_USER_DATA_STRATEGIES="${FS_DIR_USER_DATA}/strategies"
FS_CONFIG="${FS_DIR}/${FS_NAME}.config.json"
FS_STRATEGIES="${FS_DIR}/${FS_NAME}.strategies.json"

FS_BINANCE_PROXY_JSON="${FS_DIR_USER_DATA}/binance_proxy.json"

FS_FREQUI_JSON="${FS_DIR_USER_DATA}/frequi.json"
FS_FREQUI_SERVER_JSON="${FS_DIR_USER_DATA}/frequi_server.json"
FS_FREQUI_YML="${FS_DIR}/${FS_NAME}_frequi.yml"

FS_SERVER_IP="$(ip a | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)"
FS_SERVER_URL=""
FS_INODE_SUM="$(ls -ali / | sed '2!d' | awk '{print $1}')"
FS_HASH="$(xxd -l8 -ps /dev/urandom)"

FS_YES=1
FS_AUTO=1
FS_KILL=1

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

function emergency () {                __b3bp_log emergency "${@}"; exit 1; }
function alert ()   { [[ "${LOG_LEVEL:-0}" -ge 1 ]] && __b3bp_log alert "${@}"; true; }
function critical ()  { [[ "${LOG_LEVEL:-0}" -ge 2 ]] && __b3bp_log critical "${@}"; true; }
function error ()   { [[ "${LOG_LEVEL:-0}" -ge 3 ]] && __b3bp_log error "${@}"; true; }
function warning ()   { [[ "${LOG_LEVEL:-0}" -ge 4 ]] && __b3bp_log warning "${@}"; true; }
function notice ()  { [[ "${LOG_LEVEL:-0}" -ge 5 ]] && __b3bp_log notice "${@}"; true; }
function info ()    { [[ "${LOG_LEVEL:-0}" -ge 6 ]] && __b3bp_log info "${@}"; true; }
function debug ()   { [[ "${LOG_LEVEL:-0}" -ge 7 ]] && __b3bp_log debug "${@}"; true; }

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
    debug "# function _fsIntro_"
  local _fsConfig="${FS_CONFIG}"
  local _dir="${FS_DIR}"
  local _fsVersion="${FS_VERSION}"
  local _serverIp="${FS_SERVER_IP}"
  local _inodeSum="${FS_INODE_SUM}"
	local _serverUrl=""
  
	if [[ "$(_fsIsFile_ "${_fsConfig}")" -eq 0 ]]; then
    _serverUrl="$(_fsJsonGet_ "${_fsConfig}" "server_url")"
  fi
  
  echo "###"
  echo "# FREQSTART: ${_fsVersion}"
  echo "# Dir: ${_dir}"
  echo "# Server ip: ${_serverIp}"
  if [[ -n "${_serverUrl}" ]]; then
    echo "# Server url: ${_serverUrl}"
    FS_SERVER_URL="${_serverUrl}"
  else
    echo "# Server url: not set"
  fi
    # credit: https://stackoverflow.com/a/51688023
  if [[ "${_inodeSum}" = "2" ]]; then
    echo "# Docker: not inside a container"
  else
    echo "# Docker: inside a container"
  fi
  echo '###'

  printf "%s\n" \
  "{" \
  "    \"version\": \"${_fsVersion}\"" \
  "    \"server_url\": \"${_serverUrl}\"" \
  "}" \
  > "${_fsConfig}"
  
  _fsFileExist_ "${_fsConfig}"
}

function _fsIsFile_() {
    debug "# function _fsIsFile_"
  local _file="${1:-}" # optional: path to file

	if [[ -z "${_file}" ]]; then
    debug "File path is empty."
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
    debug "# function _fsFileExist_"
  local _file="${1:-}" # optional: path to file

	if [[ "$(_fsIsFile_ "${_file}")" -eq 1 ]]; then
		alert "Cannot create file: ${_file}"
    exit 1
  fi
}

function _fsCrontab_() {
    debug "# function _fsCrontab_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _cronCmd
  local _cronJob

  _cronCmd="${1}"
    debug "_cronCmd: ${_cronCmd}"
  _cronJob="${2} ${_cronCmd}"
    debug "_cronJob: ${_cronJob}"
    # credit: https://stackoverflow.com/a/17975418
  ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ; echo "${_cronJob}" ) | crontab -

  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    info "Cron set: ${_cronCmd}"
  else
    alert "Cron not set: ${_cronCmd}" && exit 1
  fi
}

function _fsCrontabRemove_() {
    debug "# function _fsCrontabRemove_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
  
  local _cronCmd
  
  _cronCmd="${1}"
      debug "_cronCmd: ${_cronCmd}"
    # credit: https://stackoverflow.com/a/17975418
  if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 0 ]]; then
    ( crontab -l 2>/dev/null | grep -v -F "${_cronCmd}" || : ) | crontab -

    if [[ "$(_fsCrontabValidate_ "${_cronCmd}")" -eq 1 ]]; then
      info "Cron removed: ${_cronCmd}"
    else
      alert "Cron not removed: ${_cronCmd}" && exit 1
    fi
  else
    debug "No cron found: ${_cronCmd}"
  fi
}

function _fsCrontabValidate_() {
    debug "# function _fsCrontabValidate_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
  
  local _cronCmd
  
  _cronCmd="${1}"

  crontab -l 2>/dev/null | grep -q "${_cronCmd}"  && echo 0 || echo 1
}

function _fsIsYml_() {
    debug "# function _fsIsYml_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _dir="${FS_DIR}"
	local _path="${1}"
	local _file=""
	local _fileType=""
  
  _path="${_dir}/${_path##*/}"
    debug "_path: ${_path}"
	_file="${_path##*/}"
    debug "_file: ${_file}"
	_fileType="${_file##*.}"
    debug "_fileType: ${_fileType}"

	if [[ -n "${_fileType}" ]]; then
    if [[ "${_fileType}" = 'yml' ]]; then
      if [[ "$(_fsIsFile_ "${_path}")" -eq 0 ]]; then
        echo "${_path}"
      else
        error "File not found: ${_file}"
      fi
    else
      error "File type is not correct!"
    fi
	else
		error "File type is missing!"
	fi
}

function _fsStats_() {
    debug "# function _fsStats_"
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

	echo "###"
  echo "# Ping avg. (Binance): ${_ping}ms | Vultr \"Tokyo\" Server avg.: 1.290ms"
	echo "# Time to API (Binance): ${_time} | Vultr \"Tokyo\" Server avg.: 0m0.039s"
	echo "# Used memory (Server): ${_memUsed}MB  (max. ${_memTotal}MB)"
	echo "# Get closer to Binance? Try Vultr \"Tokyo\" Server and get \$100 usage for free:"
	echo "# https://www.vultr.com/?ref=9122650-8H"
	echo "###"
}

function _fsScriptLock_() {
    debug "# function _fsScriptLock_"
  local _lockDir=""
  local _tmpDir="${FS_DIR_TMP:-/tmp}"
  local _system="${1:-}"

  if [[ -n "${_tmpDir}" ]]; then
    if [[ "${_system}" = "system" ]]; then
      _lockDir="${_tmpDir}/$(basename "$0").lock"
    else
      _lockDir="${_tmpDir}/$(basename "$0").${UID}.lock"
    fi

    if sudo mkdir -p "${_lockDir}" 2>/dev/null; then
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
    debug "# function _fsJsonGet_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue=""
    debug "_jsonFile: ${_jsonFile}"
  if [[ "$(_fsIsFile_ "${_jsonFile}")" -eq 0 ]]; then
    _jsonValue="$(grep -o "${_jsonName}\"\?: \"\?.*\"\?" "${_jsonFile}" \
    | sed "s,\",,g" \
    | sed "s,\s,,g" \
    | sed "s#,##g" \
    | sed "s,${_jsonName}:,,")"
      debug "_jsonValue: ${_jsonValue}"
    [[ -n "${_jsonValue}" ]] && echo "${_jsonValue}"
  fi
}

function _fsJsonSet_() {
    debug "# function _fsJsonSet_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _jsonFile="${1}"
  local _jsonName="${2}"
  local _jsonValue="${3}"
    debug "_jsonFile: ${_jsonFile}"
    debug "_jsonName: ${_jsonName}"
    debug "_jsonValue: ${_jsonValue}"
    debug "_jsonValue: IMPORTANT - Do not print value for non-verbose inputs."
  _fsFileExist_ "${_jsonFile}"
  
  if grep -qow "\"${_jsonName}\": \".*\"" "${_jsonFile}"; then
      debug '"name": "value"'
    sed -i "s,\"${_jsonName}\": \".*\",\"${_jsonName}\": \"${_jsonValue}\"," "${_jsonFile}"
  elif grep -qow "${_jsonName}: \".*\"" "${_jsonFile}"; then
      debug 'name: "value"'
    sed -i "s,${_jsonName}: \".*\",${_jsonName}: \"${_jsonValue}\"," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "\"${_jsonName}\": .*")" ]]; then
  #    debug '"name": value'
  #  sed -i "s,\"${_jsonName}\": .*,\"${_jsonName}\": ${_jsonValue}," "${_jsonFile}"
  #elif [[ -n "$(cat "${_jsonFile}" | grep -o "${_jsonName}: .*")" ]]; then
  #    debug 'name: value'
  #  sed -i "s,${_jsonName}: .*,${_jsonName}: ${_jsonValue}," "${_jsonFile}"
  else
    emergency "Cannot find name: ${_jsonName}" && exit 1
  fi
}

function _fsCaseConfirmation_() {
    debug "# function _fsCaseConfirmation_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _question="${1}"
  local _yesForce="${FS_YES}"
  local _yesNo=""
  
  notice "${_question}"
  
  if [[ "${_yesForce}" -eq 0 ]]; then
    debug "Forcing confirmation with '-y' flag set."
    echo 0
  else
    while true; do
      read -rp " (y/n) " _yesNo
      
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
    debug "# function _fsIsUrl_"
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

function _fsCdown_() {
    debug "# function _fsCdown_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  _secs="${1}"; shift; _text=( "$@" )
    
  while [[ "${_secs}" -gt -1 ]]; do
    if [[ "${_secs}" -gt 0 ]]; then
      printf '\r\033[KWaiting '"${_secs}"' seconds '"${_text[*]}"
      sleep 1
    else
      printf '\r\033[K'
    fi
    : $((_secs--))
  done
}

function _fsIsAlphaDash_() {
    debug "# function _fsIsAlphaDash_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
  
  local _re='^[[:alnum:]_-]+$'
  
  if [[ ${1} =~ ${_re} ]]; then
    echo 0
  else
    echo 1
  fi
}

function _fsDedupeArray_() {
    debug "# function _fsDedupeArray_"
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

function _fsTimestamp_() {
  date +"%y%m%d%H%M%S"
}

function _fsRandomHex_() {
    debug "# function _fsRandomHex_ (16-byte (128-bit) hex)"
  local _length="${1:-16}"
  local _string=""

  _string="$(xxd -l"${_length}" -ps /dev/urandom)"
    debug "_string: ${_string}"
  echo "${_string}"
}

function _fsRandomBase64_() {
    debug "# function _fsRandomBase64_ (24-byte (196-bit) base64)"
  local _length="${1:-24}"
  local _string=""

  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64)"
    debug "_string: ${_string}"
  echo "${_string}"
}

function _fsRandomBase64UrlSafe_() {
    debug "# function _fsRandomBase64UrlSafe_ (24-byte (196-bit) base64)"
  local _length="${1:-32}"
  local _string=""

  _string="$(xxd -l"${_length}" -ps /dev/urandom | xxd -r -ps | base64 | tr -d = | tr + - | tr / _)"
    debug "_string: ${_string}"
  echo "${_string}"
}

function _fsIsSymlink_() {
    debug "# function _fsIsSymlink_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _symlink="${1}"
    debug "_symlink: ${_symlink}"
    # credit: https://stackoverflow.com/a/36180056
  if [ -L "${_symlink}" ] ; then
    if [ -e "${_symlink}" ] ; then
        debug "_symlink: Good link"
			echo 0
    else
        debug "_symlink: Broken link"
			sudo rm -f "${_symlink}"
      echo 1
    fi
  elif [ -e "${_symlink}" ] ; then
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
    debug "# function _fsStrategy_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _strategyName="${1}"
  local _strategyFile
  local _strategyFileNew
  local _strategyUpdate
  local _strategyUpdateCount=0
  local _strategyFileType
  local _strategyFileTypeName="unknown"
  local _strategyTmp="${FS_DIR_TMP}/${_strategyName}_${FS_HASH}"
  local _strategyDir="${FS_DIR_USER_DATA_STRATEGIES}/${_strategyName}"
  local _strategyUrls=()
  local _strategyUrlsDeduped=()
  local _strategyUrl
  local _strategyPath
  local _strategyPathTmp
  local _fsStrategies="${FS_STRATEGIES}"
  local _strategyJson

  if [[ "$(_fsIsFile_ "${_fsStrategies}")" -eq 1 ]]; then
    printf "%s\n" \
    "{" \
    "  \"NostalgiaForInfinityX\": [" \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/NostalgiaForInfinityX.py\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-binance.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-bybit.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-ftx.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-gateio.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-huobi.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-kucoin.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/blacklist-okx.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig-rebuy.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/exampleconfig_secret.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-binance-busd.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-binance-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-bybit-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-ftx-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-gateio-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-huobi-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-kucoin-usdt.json\"," \
    "    \"https://raw.githubusercontent.com/iterativv/NostalgiaForInfinity/main/configs/pairlist-volume-okx-usdt.json\"" \
    "  ]," \
    "  \"DoesNothingStrategy\": [" \
    "    \"https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/master/user_data/strategies/berlinguyinca/DoesNothingStrategy.py\"" \
    "  ]" \
    "}" \
    > "${_fsStrategies}"
    
    _fsFileExist_ "${_fsStrategies}"
  fi
  
  while read -r; do
  _strategyUrls+=( "$REPLY" )
  done < <(jq -r ".${_strategyName}[]?" "${_fsStrategies}")
    debug "_strategyUrls[@]:"
    debug "$(printf '%s\n' "${_strategyUrls[@]}")"
  if (( ${#_strategyUrls[@]} )); then
    while read -r; do
    _strategyUrlsDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_strategyUrls[@]}")
  fi
    debug "_strategyUrlsDeduped[@]:"
    debug "$(printf '%s\n' "${_strategyUrlsDeduped[@]}")"
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

        if [[ "$(_fsIsFile_ "${_strategyPath}")" -eq 0 ]]; then
            debug "cmp: $(cmp --silent "${_strategyPathTmp}" "${_strategyPath}")"
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
      debug "_strategyUpdateCount: ${_strategyUpdateCount}"
    if [[ "${_strategyUpdateCount}" -eq 0 ]]; then
      info "Strategy already latest version: ${_strategyName}"
    else
      warning "Strategy updated: ${_strategyName}"
      _strategyUpdate="$(_fsTimestamp_)"
        debug "_strategyUpdate: ${_strategyUpdate}"
      _strategyJson="$(jq -n \
        --arg update "${_strategyUpdate}" \
        '$ARGS.named'
      )"
        debug "_strategyJson[@]:"
        debug "$(printf '%s\n' "${_strategyJson[@]}")"
      printf "%s\n" "${_strategyJson}" | jq . > "${_strategyDir}/${_strategyName}.conf.json"
    fi
  else
    warning "Strategy not implemented: ${_strategyName}"
  fi
}


### FREQSTART - docker
##############################################################################

function _fsDockerVarsPath_() {
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

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

function _fsDockerVarsRepo_() {
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo="${_docker%:*}"
	
	echo "${_dockerRepo}"
}

function _fsDockerVarsCompare_() {
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo=""
	local _dockerTag=""
	local _dockerVersionLocal=""
	local _dockerVersionHub=""
  
  _dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	_dockerTag="$(_fsDockerVarsTag_ "${_docker}")"
	_dockerVersionHub="$(_fsDockerVersionHub_ "${_dockerRepo}" "${_dockerTag}")"
    debug "_dockerVersionHub: ${_dockerVersionHub}"
	_dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"
    debug "_dockerVersionLocal: ${_dockerVersionLocal}"

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

function _fsDockerVarsName_() {
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerRepo
	local _dockerName

	_dockerRepo="$(_fsDockerVarsRepo_ "${_docker}")"
	_dockerName="${FS_NAME}_${_dockerRepo//\//_}"
    debug "_dockerName: ${_dockerName}"
	echo "${_dockerName}"
}

function _fsDockerVarsTag_() {
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _docker="${1}"
	local _dockerTag="${_docker##*:}"

	if [[ "${_dockerTag}" = "${_docker}" ]]; then
		_dockerTag="latest"
	fi

	echo "${_dockerTag}"
}

function _fsDockerVersionLocal_() {
    debug "# function _fsDockerVersionLocal_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerVersionLocal=""
  
	if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
		_dockerVersionLocal="$(docker inspect --format='{{index .RepoDigests 0}}' "${_dockerRepo}:${_dockerTag}" \
		| sed 's/.*@//')"
    
    [[ -n "${_dockerVersionLocal}" ]] && echo "${_dockerVersionLocal}"
	fi
}

function _fsDockerVersionHub_() {
    debug "# function _fsDockerVersionHub_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerName=""
	local _dockerManifest=""
	local _dockerManifestHash="${FS_HASH}"
  local _acceptM=""
  local _acceptML=""
  local _token=""
  local _status=""
  local _dockerVersionHub=""

	_dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"
	_dockerManifest="${FS_DIR_TMP}/${_dockerName}_${_dockerTag}_${_dockerManifestHash}.json"
    debug "_dockerManifest: ${_dockerManifest}"
    # credit: https://stackoverflow.com/a/64309017
  _acceptM="application/vnd.docker.distribution.manifest.v2+json"
  _acceptML="application/vnd.docker.distribution.manifest.list.v2+json"
  _token="$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${_dockerRepo}:pull" | jq -r '.token')"

  curl -H "Accept: ${_acceptM}" -H "Accept: ${_acceptML}" -H "Authorization: Bearer ${_token}" -o "${_dockerManifest}" \
  -I -s -L "https://registry-1.docker.io/v2/${_dockerRepo}/manifests/${_dockerTag}"

  if [[ "$(_fsIsFile_ "${_dockerManifest}")" -eq 0 ]]; then
    _status="$(grep -o "200 OK" "${_dockerManifest}")"
      debug "_status: ${_status}"
    if [[ -n "${_status}" ]]; then
      _dockerVersionHub="$(_fsJsonGet_ "${_dockerManifest}" "etag")"
      
      if [[ -n "${_dockerVersionHub}" ]]; then
        echo "${_dockerVersionHub}"
      fi
    fi
  fi
}

function _fsDockerImageInstalled_() {
    debug "# function _fsDockerImageInstalled_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerRepo="${1}"
	local _dockerTag="${2}"
  local _dockerImages=""
  
  _dockerImages="$(docker images -q "${_dockerRepo}:${_dockerTag}" 2> /dev/null)"
		debug "_dockerImages: ${_dockerImages}"
	if [[ -n "${_dockerImages}" ]]; then
		echo 0
	else
		echo 1
	fi
}

function _fsDockerImageVersion_() {
    debug "# function _fsDockerImageVersion_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerImage="${1}"
  local _dockerDir="${FS_DIR_DOCKER}"
  local _dockerRepo=""
  local _dockerTag=""
  local _dockerName=""
  local _dockerCompare=""
  local _dockerPath=""
  local _dockerStatus=2
  local _dockerVersionLocal=""

  _dockerRepo="$(_fsDockerVarsRepo_ "${_dockerImage}")"
  _dockerTag="$(_fsDockerVarsTag_ "${_dockerImage}")"
  _dockerName="$(_fsDockerVarsName_ "${_dockerImage}")"
  _dockerCompare="$(_fsDockerVarsCompare_ "${_dockerImage}")"
  _dockerPath="$(_fsDockerVarsPath_ "${_dockerImage}")"

  if [[ "${_dockerCompare}" -eq 0 ]]; then
      # equal
    info "\"${_dockerRepo}:${_dockerTag}\" latest version is installed." && _dockerStatus=0
  elif [[ "${_dockerCompare}" -eq 1 ]]; then
      # greater
    _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"

    if [[ -n "${_dockerVersionLocal}" ]]; then
        # update from docker hub
      warning "\"${_dockerRepo}:${_dockerTag}\" update found."
      
      if [[ "$(_fsCaseConfirmation_ "Do you want to update now?")" -eq 0 ]]; then
        sudo docker pull "${_dockerRepo}:${_dockerTag}"
        
        if [[ "$(_fsDockerVarsCompare_ "${_dockerImage}")" -eq 0 ]]; then
          notice "\"${_dockerRepo}:${_dockerTag}\" updated and installed." && _dockerStatus=1
        fi
      else
        warning "Skipping image update..." && _dockerStatus=0
      fi
    else
        # install from docker hub
      sudo docker pull "${_dockerRepo}:${_dockerTag}"
      
      if [[ "$(_fsDockerVarsCompare_ "${_dockerImage}")" -eq 0 ]]; then
        notice "\"${_dockerRepo}:${_dockerTag}\" latest version installed." && _dockerStatus=1
      fi
    fi
  elif [[ "${_dockerCompare}" -eq 2 ]]; then
      # unknown
    warning "\"${_dockerRepo}:${_dockerTag}\" can not load online image version."
      # if docker is not reachable try to load local backup
    if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
      info "\"${_dockerRepo}:${_dockerTag}\" is installed but can not be verified." && _dockerStatus=0
    elif [[ "$(_fsIsFile_ "${_dockerPath}")" -eq 0 ]]; then
      sudo docker load -i "${_dockerPath}"
      
      if [[ "$(_fsDockerImageInstalled_ "${_dockerRepo}" "${_dockerTag}")" -eq 0 ]]; then
        notice "\"${_dockerRepo}:${_dockerTag}\" backup installed." && _dockerStatus=0
      fi
    fi
  fi

  _dockerVersionLocal="$(_fsDockerVersionLocal_ "${_dockerRepo}" "${_dockerTag}")"

  if [[ "${_dockerStatus}" -eq 0 ]]; then
    echo "${_dockerVersionLocal}"
  elif [[ "${_dockerStatus}" -eq 1 ]]; then
    if [[ ! -d "${_dockerDir}" ]]; then mkdir -p "${_dockerDir}"; fi

    sudo rm -f "${_dockerPath}"
    sudo docker save -o "${_dockerPath}" "${_dockerRepo}:${_dockerTag}"
    [[ "$(_fsIsFile_ "${_dockerPath}")" -eq 0 ]] && info "\"${_dockerRepo}:${_dockerTag}\" backup created."
    
    echo "${_dockerVersionLocal}"
  else
    alert "\"${_dockerRepo}:${_dockerTag}\" not found."
  fi
}

function _fsDockerPsName_() {
    debug "# function _fsDockerPsName_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _dockerName="${1}"
  local _dockerMode="${2:-}" # optional: all
  local _dockerPs=""
  local _dockerPsAll=""
  local _dockerMatching=1
    debug "_dockerName: ${_dockerName}"
    debug "_dockerMode (all|-): ${_dockerMode}"
    # credit: https://serverfault.com/a/733498
    # credit: https://stackoverflow.com/a/44731522
	if [[ "${_dockerMode}" = "all" ]]; then
    _dockerPsAll="$(docker ps -a --format '{{.Names}}' | grep -ow "${_dockerName}")"
      debug "_dockerPsAll: ${_dockerPsAll}"
    [[ -n "${_dockerPsAll}" ]] && _dockerMatching=0
  else
    _dockerPs="$(docker ps --format '{{.Names}}' | grep -ow "${_dockerName}")"
      debug "_dockerPs: ${_dockerPs}"
    [[ -n "${_dockerPs}" ]] && _dockerMatching=0
	fi
    debug "_dockerMatching: ${_dockerMatching}"
	if [[ "${_dockerMatching}" -eq 0 ]]; then
		echo 0
	else
		echo 1
	fi
}

function _fsDockerId2Name_() {
    debug "# function _fsDockerId2Name_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerId="${1}"
	local _dockerName=""
    debug "_dockerId: ${_dockerId}"
	_dockerName="$(sudo docker inspect --format="{{.Name}}" "${_dockerId}" | sed "s,\/,,")"
    debug "_dockerName: ${_dockerName}"
	if [[ -n "${_dockerName}" ]]; then
		echo "${_dockerName}"
	fi
}

function _fsDockerRun_() {
    debug "# function _fsDockerRun_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _dir="${FS_DIR}"
	local _dockerRepo="${1}"
	local _dockerTag="${2}"
	local _dockerRm="${3:-}" #optional: remove docker container on exit or error
	local _dockerName=""
	
  _dockerName="$(_fsDockerVarsName_ "${_dockerRepo}")"

	[[ -z "$(_fsDockerImageVersion_ "${_dockerRepo}:${_dockerTag}")" ]] && exit 1

	if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 1 ]]; then
		if [[ "${_dockerRm}" = "rm" ]]; then
			cd "${_dir}" && \
				docker run --rm -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		else
			cd "${_dir}" && \
				docker run -d --name "${_dockerName}" -it "${_dockerRepo}"':'"${_dockerTag}" 2>&1
		fi
		
    if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
			notice "\"${_dockerName}\" activated."
		else
			emergency "\"${_dockerName}\" not activated." && exit 1
		fi
	else
		info "\"${_dockerName}\" is already active."
	fi
}

function _fsDockerStop_() {
    debug "# function _fsDockerStop_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _dockerName="${1}"
    debug "_dockerName: ${_dockerName}"
  sudo docker update --restart=no "${_dockerName}" >/dev/null
  sudo docker stop "${_dockerName}" >/dev/null
  sudo docker rm -f "${_dockerName}" >/dev/null
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}" "all")" -eq 1 ]]; then
    info "Container removed: ${_dockerName}"
  else
    warning "Cannot remove container: ${_dockerName}"
    exit 1
  fi
}

function _fsDockerYmlImages_() {
    debug "# function _fsDockerYmlImages_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _path="${1}"
	local _ymlImages=""
	local _ymlImagesDeduped=""
	local _ymlImage=""

	_path="$(_fsIsYml_ "${_path}")"
    debug "_projectPath: ${_projectPath}"
  [[ -z "${_projectPath}" ]] && exit 1
  
    # credit: https://stackoverflow.com/a/39612060
  _ymlImages=()
  while read -r; do
    _ymlImages+=( "$REPLY" )
  done < <(grep "image:" "${_path}" | sed "s,\s,,g" | sed "s,image:,,g")
    debug "_ymlImages[@]:"
    debug "$(printf '%s\n' "${_ymlImages[@]}")"
  if (( ${#_ymlImages[@]} )); then
    _ymlImagesDeduped=()
    while read -r; do
    _ymlImagesDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_ymlImages[@]}")
  fi
    debug "_ymlImagesDeduped[@]:"
    debug "$(printf '%s\n' "${_ymlImagesDeduped[@]}")"
  if (( ${#_ymlImagesDeduped[@]} )); then
    for _ymlImage in "${_ymlImagesDeduped[@]}"; do
      if [[ -n "$(_fsDockerImageVersion_ "${_ymlImage}")" ]]; then
        echo 0
      else
        echo 1
      fi
    done
  fi
}

function _fsDockerYmlPorts_() {
    debug "# function _fsDockerYmlPorts_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _ymlPath="${1}"
	local _dockerPorts=""
	local _dockerPort=""
	local _dockerPortDuplicate=""
	local _error=0
  
	_ymlPath="$(_fsIsYml_ "${_ymlPath}")"
    debug "_projectPath: ${_projectPath}"
  [[ -z "${_projectPath}" ]] && exit 1
  
  _ymlFile="${_ymlPath##*/}"
  _ymlFileName="${_ymlFile%.*}"
  _ymlName="${_ymlFileName//-/_}"
    debug "_ymlName: ${_ymlName}"
  _dockerPortsYml=()
  while read -r; do
    _dockerPortsYml+=("$REPLY")
  done < <(grep 'ports:' "${_ymlPath}" -A 1 | grep -oE "[0-9]{4}.*" | sed "s,\",,g" | sed "s,:.*,,")
    debug "_dockerPortsYml[@]:"
    debug "$(printf '%s\n' "${_dockerPortsYml[@]}")"
  declare -A values=()
    # find duplicate ports in yml
  for v in "${_dockerPortsYml[@]}"; do
      if [[ "${values["x$v"]+set}" = set ]]; then
          error "Duplicate port found: ${v}"
          _error=$((_error+1))
      fi
      values["x$v"]=1
  done
  
  _dockerPortsProject=()
  while read -r; do
  _dockerPortsProject+=("$REPLY")
  done < <(sudo docker ps -a -f name="${_ymlName}" | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")
    debug "_dockerPortsProject[@]:"
    debug "$(printf '%s\n' "${_dockerPortsProject[@]}")"
  _dockerPortsAll=()
  while read -r; do
  _dockerPortsAll+=("$REPLY")
  done < <(sudo docker ps -a | awk 'NR > 1 {print $12}' | sed "s,->.*,," | sed "s,.*:,,")
    debug "_dockerPortsAll[@]:"
    debug "$(printf '%s\n' "${_dockerPortsAll[@]}")"
  _dockerPortsBlocked=("$(printf "%s\n" "${_dockerPortsAll[@]}" "${_dockerPortsProject[@]}" | sort | uniq -u)")
    debug "_dockerPortsBlocked[@]:"
    debug "$(printf '%s\n' "${_dockerPortsBlocked[@]}")"
  _dockerPortsCompare=("$(echo "${_dockerPortsYml[@]}" "${_dockerPortsBlocked[@]}" | tr ' ' '\n' | sort | uniq -D | uniq)")
    debug "_dockerPortsCompare[@]:"
    debug "$(printf '%s\n' "${_dockerPortsCompare[@]}")"
  if (( ${#_dockerPortsCompare[@]} )); then
    for _dockerPortCompare in "${_dockerPortsCompare[@]}"; do
      if [[ "${_dockerPortCompare}" =~ ^[0-9]+$ ]]; then
        _error=$((_error+1))
        error "Port is already allocated: ${_dockerPortCompare}"
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

function _fsDockerYmlStrategies_() {
    debug "# function _fsDockerYmlStrategies_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

	local _ymlPath="${1}"
	local _strategies=""
	local _strategiesDeduped=""
	local _strategy=""
  local _update=0

	_ymlPath="$(_fsIsYml_ "${_ymlPath}")"
    debug "_projectPath: ${_projectPath}"
  [[ -z "${_projectPath}" ]] && exit 1
  
  _strategies=()
  while read -r; do
    _strategies+=( "$REPLY" )
  done < <(grep "strategy" "${_ymlPath}" \
  | grep -v "strategy-path" \
  | sed "s,\=,,g" \
  | sed "s,\",,g" \
  | sed "s,\s,,g" \
  | sed "s,\-\-strategy,,g")
    debug "_strategies[@]:"
    debug "$(printf '%s\n' "${_strategies[@]}")"
  if (( ${#_strategies[@]} )); then
    _strategiesDeduped=()
    while read -r; do
      _strategiesDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_strategies[@]}")
  fi
    debug "_strategiesDeduped[@]:"
    debug "$(printf '%s\n' "${_strategiesDeduped[@]}")"
  if (( ${#_strategiesDeduped[@]} )); then
    for _strategy in "${_strategiesDeduped[@]}"; do        
      if [[ "$(_fsStrategy_ "${_strategy}")" -eq 1 ]]; then
        _update=$((_update+1))
      fi
    done
  fi
    debug "_update: ${_update}"
  if [[ "${_update}" -eq 0 ]]; then
    echo 0
  else
    echo 1
  fi
}

function _fsDockerYmlConfigs_() {
    debug "# function _fsDockerYmlConfigs_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _dir="${FS_DIR}"
	local _ymlPath="${1}"
  local _configs=""
  local _configsDeduped=""
	local _config=""
	local _configNew=""
  local _error=0

	_ymlPath="$(_fsIsYml_ "${_ymlPath}")"
    debug "_projectPath: ${_projectPath}"
  [[ -z "${_projectPath}" ]] && exit 1
  
  _configs=()
  while read -r; do
  _configs+=( "$REPLY" )
  done < <(grep -e "\-\-config" -e "\-c" "${_ymlPath}" \
  | sed "s,\=,,g" \
  | sed "s,\",,g" \
  | sed "s,\s,,g" \
  | sed "s,\-\-config,,g" \
  | sed "s,\-c,,g" \
  | sed "s,\/freqtrade\/,,g")
    debug "_configs[@]:"
    debug "$(printf '%s\n' "${_configs[@]}")"
  if (( ${#_configs[@]} )); then
    _configsDeduped=()
    while read -r; do
      _configsDeduped+=( "$REPLY" )
    done < <(_fsDedupeArray_ "${_configs[@]}")
  fi
    debug "_configsDeduped[@]:"
    debug "$(printf '%s\n' "${_configsDeduped[@]}")"
  if (( ${#_configsDeduped[@]} )); then
    for _config in "${_configsDeduped[@]}"; do
        debug "_config: ${_config}"
      _configPath="${_dir}/${_config}"
        debug "_configPath: ${_configPath}"
      if [[ "$(_fsIsFile_ "${_configPath}")" -eq 1 ]]; then
        error "\"$(basename "${_configPath}")\" config file does not exist."
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

function _fsDockerProjects_() {
    debug "# function _fsDockerProjects_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _projectDir="${FS_DIR}"
	local _projectPath="${1}"
	local _projectMode="${2}" # compose, validate, kill
	local _projectForce="${3:-}" # optional: force
	local _projectAuto="${FS_AUTO}"
  local _projectCronCmd=""
  local _projectCronUpdate=""
	local _projectFile=""
	local _projectFileName=""
  local _projectName=""
  local _projectImages=""
  local _projectStrategies=""
  local _projectConfigs=""
  local _projectPorts=""
  local _projectContainers=""
  local _projectContainer=""
  local _containerCmd=""
  local _containerRunning=""
  local _containerRestart=1
  local _containerName=""
  local _containerConfigs=""
  local _containerStrategy=""
  local _containerStrategyUpdate=""
  local _containerJson=""
  local _containerJsonInner=""
  local _containerConfPath=""
  local _containerCount=0
  local _strategyUpdate=""
  local _strategyDir=""
  local _strategyPath=""
  local _error=0

  _projectPath="$(_fsIsYml_ "${_projectPath}")"
    debug "_projectPath: ${_projectPath}"
  if [[ -n "${_projectPath}" ]]; then
    _projectFile="${_projectPath##*/}"
    _projectFileName="${_projectFile%.*}"
    _projectName="${_projectFileName//\-/_}"
      debug "_projectName: ${_projectName}"
    _projectContainers=()
    _containerConfPath="${_projectDir}/${_projectFileName}.conf.json"
    _projectCronCmd="freqstart -b ${_projectFile} -y"
    _projectCronUpdate="0 3 * * *" # update on 3am UTC

    if [[ "${_projectMode}" = "compose" ]]; then
      info "Start project: ${_projectFile}"

      sed -i "s,restart\:.*,restart\: \"no\",g" "${_projectPath}"

      _projectImages="$(_fsDockerYmlImages_ "${_projectPath}")"
          debug "_projectImages: ${_projectImages}"
      _projectStrategies="$(_fsDockerYmlStrategies_ "${_projectPath}")"
          debug "_projectStrategies: ${_projectStrategies}"
      _projectConfigs="$(_fsDockerYmlConfigs_ "${_projectPath}")"
          debug "_projectConfigs: ${_projectConfigs}"
      _projectPorts="$(_fsDockerYmlPorts_ "${_projectPath}")"
          debug "_projectPorts: ${_projectPorts}"
      [[ "${_projectImages}" -eq 1 ]] && _error=$((_error+1))
      [[ "${_projectConfigs}" -eq 1 ]] && _error=$((_error+1))
      [[ "${_projectPorts}" -eq 1 ]] && _error=$((_error+1))
        debug "_error: ${_error}"
      if [[ "${_error}" -eq 0 ]]; then
          cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up --no-start --no-recreate
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      info "Validate project: ${_projectFile}"
      _fsCdown_ 30 "for any errors..."
    elif [[ "${_projectMode}" = "kill" ]]; then
      info "Kill project: ${_projectFile}"
    fi

    if [[ "${_error}" -eq 0 ]]; then
      while read -r; do
        _projectContainers+=( "$REPLY" )
      done < <(cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" ps -q)
        debug "_projectContainers[@]:"
        debug "$(printf '%s\n' "${_projectContainers[@]}")"
      for _projectContainer in "${_projectContainers[@]}"; do
        _containerName="$(_fsDockerId2Name_ "${_projectContainer}")"
          debug "_containerName: ${_containerName}"
        if [[ "${_projectMode}" = "compose" ]]; then
          info "Validate container: ${_containerName}"
            # get container command
          _containerCmd="$(sudo docker inspect --format="{{.Config.Cmd}}" "${_projectContainer}" \
          | sed "s,\[, ,g" \
          | sed "s,\], ,g" \
          | sed "s,\",,g" \
          | sed "s,\=, ,g" \
          | sed "s,\/freqtrade\/,,g")"
            debug "_containerCmd: ${_containerCmd}"
            # compare global strategy with container strategy
          _containerStrategy="$(echo "${_containerCmd}" | grep -Eo "(\-s|\--strategy) [-A-Za-z0-9_]+ " \
          | sed "s,\--strategy,," \
          | sed "s,\s,,g")"
            debug "_containerStrategy: ${_containerStrategy}"
          _containerStrategyDir="$(echo "${_containerCmd}" | grep -Eo "\--strategy-path [-A-Za-z0-9_/]+ " \
          | sed "s,\-\-strategy-path,," \
          | sed "s,\s,,g")"
            debug "_containerStrategyDir: ${_containerStrategyDir}"
          _strategyPath="${_containerStrategyDir}/${_containerStrategy}.conf.json"
          if [[ "$(_fsIsFile_ "${_strategyPath}")" -eq 0 ]]; then
            _strategyUpdate="$(jq -r '.update' < "${_strategyPath}")"
            _strategyUpdate="$(echo "${_strategyUpdate}" | sed "s,null,," | sed "s,\s,,g" | sed "s,\n,,g")"
          else
            _strategyUpdate=""
          fi
            debug "_strategyUpdate: ${_strategyUpdate}"
          if [[ "$(_fsIsFile_ "${_containerConfPath}")" -eq 0 ]]; then
            _containerStrategyUpdate="$(jq -r ".${_containerName}[0].strategy_update" < "${_containerConfPath}")"
            _containerStrategyUpdate="$(echo "${_containerStrategyUpdate}" | sed "s,null,," | sed "s,\s,,g" | sed "s,\n,,g")"
          else
            _containerStrategyUpdate=""
          fi
            debug "_containerStrategyUpdate: ${_containerStrategyUpdate}"
          if [[ -n "${_strategyUpdate}" ]]; then
            if [[ -n "${_containerStrategyUpdate}" ]]; then
              if [[ ! "${_containerStrategyUpdate}" = "${_strategyUpdate}" ]]; then
                warning "Strategy is outdated: ${_containerStrategy}"
                _containerRestart=0
              fi
            else
              _containerStrategyUpdate="${_strategyUpdate}"
            fi
          fi
            # compare latest docker image with container image
          _containerImage="$(sudo docker inspect --format="{{.Config.Image}}" "${_projectContainer}")"
            debug "_containerImage: ${_containerImage}"
          _containerImageVersion="$(sudo docker inspect --format="{{.Image}}" "${_projectContainer}")"
            debug "_containerImageVersion: ${_containerImageVersion}"
          _dockerImageVersion="$(docker inspect --format='{{.Id}}' "${_containerImage}")"
            debug "_dockerImageVersion: ${_dockerImageVersion}"
          if [[ ! "${_containerImageVersion}" = "${_dockerImageVersion}" ]]; then
            warning "Docker image version is outdated: ${_containerName}"
            _containerRestart=0
          fi
            # stop container if restart is necessary
          if [[ "${_containerRestart}" -eq 0 ]]; then
            if [[ "$(_fsCaseConfirmation_ "Restart \"${_containerName}\" container?")" -eq 0 ]]; then
              _containerStrategyUpdate="${_strategyUpdate}"
              _fsDockerStop_ "${_containerName}"
            fi
            _containerRestart=1
          fi
            # create project json array
            debug "_containerStrategyUpdate: ${_containerStrategyUpdate}"
          _containerJsonInner="$(jq -n \
            --arg strategy "${_containerStrategy}" \
            --arg strategy_path "${_containerStrategyDir}" \
            --arg strategy_update "${_containerStrategyUpdate}" \
            '$ARGS.named'
          )"
          _containerJson="$(jq -n \
            --argjson "${_containerName}" "[${_containerJsonInner}]" \
            '$ARGS.named'
          )"
          _procjectJson[$_containerCount]="${_containerJson}"
            # increment container count
          _containerCount=$((_containerCount+1))
        elif [[ "${_projectMode}" = "validate" ]]; then
          _containerRunning="$(_fsDockerPsName_ "${_containerName}")"
            debug "_containerRunning: ${_containerRunning}"
          if [[ "${_containerRunning}" -eq 0 ]]; then
            sudo docker update --restart=on-failure "${_containerName}" >/dev/null
            info "Container is running: ${_containerName}"
          else
            error "Container is not running: ${_containerName}"
            _fsDockerStop_ "${_containerName}"
            _error=$((_error+1))
          fi
        elif [[ "${_projectMode}" = "kill" ]]; then
          if [[ "$(_fsCaseConfirmation_ "Kill \"${_containerName}\" container?")" -eq 0 ]]; then
            _fsDockerStop_ "${_containerName}"
          fi
        fi
      done
    fi
    
    if [[ "${_projectMode}" = "compose" ]]; then
      if [[ "${_error}" -eq 0 ]]; then
          printf "%s\n" "${_procjectJson[@]}" | jq . > "${_containerConfPath}"
        if [[ ${_projectForce} = "force" ]]; then
          cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up -d --force-recreate
        else
          cd "${_projectDir}" && sudo docker-compose -f "${_projectFile}" -p "${_projectName}" up -d --no-recreate
        fi
        _fsDockerProjects_ "${_projectPath}" "validate"
      else
        alert "Too many errors! Cannot start: ${_projectFile}"
      fi
    elif [[ "${_projectMode}" = "validate" ]]; then
      if [[ "${_projectAuto}" -eq 0 ]]; then
        if [[ "${_error}" -eq 0 ]]; then
          _fsCrontab_ "${_projectCronCmd}" "${_projectCronUpdate}"
        else
          alert "Not all container running. Cannot set autoupdate for project: ${_projectFile}"
        fi
      fi
    elif [[ "${_projectMode}" = "kill" ]]; then
      _fsCrontabRemove_ "${_projectCronCmd}"

      if (( ! ${#_projectContainers[@]} )); then
        info "No container running in project: ${_ymlFile}"
      fi
    fi
  fi
}

function _fsDockerKillImages_() {
    debug "# function _fsDockerKillImages_"
  _fsDockerKillContainers_
	sudo docker image ls -q | xargs -I {} sudo docker image rm -f {}
}

function _fsDockerKillContainers_() {
    debug "# function _fsDockerKillContainers_"
	sudo docker ps -a -q | xargs -I {} sudo docker rm -f {}
}


### FREQSTART - setup
##############################################################################

function _fsSetup_() {
    debug "# function _fsSetup_"
  local _symlink="${FS_SYMLINK}"
  local _symlinkSource="${FS_DIR}/${FS_NAME}.sh"

  _fsIntro_
  _fsSetupServer_
  _fsSetupNtp_
  _fsSetupFreqtrade_
  _fsSetupBinanceProxy_
  _fsSetupFrequi_
  _fsSetupExampleBot_
  _fsStats_

	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
    sudo rm -f "${_symlink}"
		sudo ln -sfn "${_symlinkSource}" "${_symlink}"
	fi
	
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 0 ]]; then
    echo
		notice 'Setup finished!'
		info "-> Run freqtrade bots with: ${FS_NAME} -b example.yml"
		info "  1. \".yml\" files can contain one or multiple bots."
		info "  2. Configs and strategies files are checked for existense."
		info "  3. Checking docker images for updates before start."
	else
		emergency "Cannot create symlink: \"${_symlink}\"" && exit 1
	fi
}

function _fsSetupPkgs_() {
    debug "# function _fsSetupPkgs_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}"

  local _pkgs=( "$@" )
  local _pkg=""
  local _status=""
  local _getDocker="${FS_DIR_DOCKER}/get-docker.sh"

  for _pkg in "${_pkgs[@]}"; do
      debug "_pkg: ${_pkg}"
    if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
      info "Already installed: ${_pkg}"
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

      if [[ "$(_fsSetupPkgsStatus_ "${_pkg}")" -eq 0 ]]; then
        info "Installed: ${_pkg}"
      else
        emergency "Cannot install: ${_pkg}" && exit 1
      fi
    fi
  done
}

function _fsSetupPkgsStatus_() {
    debug "# function _fsSetupPkgsStatus_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1
  
  local _pkg="${1}"
  local _status=""
  
  _status="$(dpkg-query -W --showformat='${Status}\n' "${_pkg}" 2>/dev/null | grep "install ok installed")"
    debug "_status: ${_status}"
  if [[ -n "${_status}" ]]; then
    echo 0
  else
    echo 1
  fi
}

function _fsSetupServer_() {
    debug "# function _fsSetupServer_"
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
    debug "# function _fsSetupNtp_"
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
    debug "# function _fsSetupNtpCheck"
  local timentp=""
  local timeutc=""
  local timesyn=""

  timentp="$(timedatectl | grep -o 'NTP service: active')"
    debug "timentp: ${timentp}"
  timeutc="$(timedatectl | grep -o '(UTC, +0000)')"
    debug "timeutc: ${timeutc}"
  timesyn="$(timedatectl | grep -o 'System clock synchronized: yes')"
    debug "timesyn: ${timesyn}"

  if [[ -n "${timentp}" ]] || [[ -n  "${timeutc}" ]] || [[ -n  "${timesyn}" ]]; then
    echo 0
  else
    echo 1
  fi
}

function _fsSetupFreqtrade_() {
    debug "# function _fsSetupFreqtrade_"
  local _dir="${FS_DIR}"
  local _docker="freqtradeorg/freqtrade:stable"
  local _dockerYml="${_dir}/${FS_NAME}_setup.yml"
  local _dockerImageStatus=""
  local _dirUserData="${FS_DIR_USER_DATA}"
  local _configKey=""
  local _configSecret=""
  local _configName=""
  local _configFile=""
  local _configFileTmp=""
  local _configFileBackup=""

  echo
  info 'SETUP FREQTRADE:'
  
  [[ -z "$(_fsDockerImageVersion_ "${_docker}")" ]] && exit 1

  if [[ ! -d "${_dirUserData}" ]]; then
    _fsSetupFreqtradeYml_
    
    cd "${_dir}" && \
    docker-compose --file "$(basename "${_dockerYml}")" run --rm freqtrade create-userdir --userdir "$(basename "${_dirUserData}")"
    if [[ ! -d "${_dirUserData}" ]]; then
      emergency "Directory cannot be created: ${_dirUserData}" && exit 1
    else
      notice "Directory created: ${_dirUserData}"
    fi
  fi

  info "A config is needed to start a bot!"

  if [[ "$(_fsCaseConfirmation_ "Skip creating a config?")" -eq 0 ]]; then
     warning "Skipping create a config..."
  else
    while true; do
      info "Choose a name for your config. For default name press <ENTER>."
      read -rp " (filename) " _configName
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
      
      if [[ -n "${_configName}" ]]; then
        info "The config file name will be: ${_configName}.json"
        if [[ "$(_fsCaseConfirmation_ "Is this correct?")" -eq 0 ]]; then
          break
        fi
      fi
    done
    
    _configFile="${_dirUserData}/${_configName}.json"
    _configFileTmp="${_dirUserData}/${_configName}.tmp.json"
    _configFileBackup="${_dirUserData}/${_configName}.bak.json"

    if [[ "$(_fsIsFile_ "${_configFile}")" -eq 0 ]]; then
      warning "The config already exist: $(basename "${_configFile}")"
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
        notice "Enter your KEY for exchange api (ENTRY HIDDEN):"
        read -rs _configKey
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
        read -rs _configSecret
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
    debug "# function _fsSetupFreqtradeYml_"
  local _dir="${FS_DIR}"
  local _dockerYml="${_dir}/${FS_NAME}_setup.yml"
  local _dockerGit="https://raw.githubusercontent.com/freqtrade/freqtrade/stable/docker-compose.yml"
    debug "_dockerYml: ${_dockerYml}"
  if [[ "$(_fsIsFile_ "${_dockerYml}")" -eq 1 ]]; then
    curl -s -L "${_dockerGit}" -o "${_dockerYml}"
    
    _fsFileExist_ "${_dockerYml}"
  fi
}

_fsSetupBinanceProxy_() {
    debug "# function _fsSetupBinanceProxy_"
  local _binanceProxy="${FS_BINANCE_PROXY_JSON}"
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

  echo
  info "SETUP BINANCE-PROXY:"
  info "(Ports: 8090-8091/tcp)"
  
  if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    info "\"${_dockerName}\" is already running."
    
    _fsDockerRun_ "${_dockerRepo}" "${_dockerTag}" "rm"
  else
    if [[ "$(_fsCaseConfirmation_ "Install \"binance-proxy\" and start now?")" -eq 0 ]]; then
      _fsDockerImageVersion_ "${_docker}"

      if [[ "$(_fsIsFile_ "${_binanceProxy}")" -eq 1 ]]; then
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
    debug "# function _fsSetupFrequi_"
  local _dockerName="${FS_NAME}_frequi"
  local _serverUrl="${FS_SERVER_URL}"
  local _frequiYml="${FS_FREQUI_YML}"
  local _yesForce="${FS_YES}"
  local _nr=""
  local _setup=1
  
  echo
  info 'FREQUI: (Webserver API)'
  
	if [[ "$(_fsDockerPsName_ "${_dockerName}")" -eq 0 ]]; then
    info "\"FreqUI\" is active: ${_serverUrl}"
    if [[ "$(_fsCaseConfirmation_ "Skip reconfigure \"FreqUI\" now?")" -eq 0 ]]; then
      _setup=1
      _fsDockerProjects_ "${_frequiYml}" "compose"
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
      info '   -> Ignore browser warnings on self signed SSL.'
      notice '  2) Yes, I want to use a domain with SSL (truecrypt)'
      info '   -> Set DNS to "'"${FS_SERVER_IP}"' first!'
      notice '  3) No, I dont want to use SSL (not recommended)'
      info '   -> Only for local use!'
      
      if [[ "${_yesForce}" -eq 1 ]]; then
        read -rp " (1/2/3) " _nr
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
    _fsSetupNginxRestart_
    _fsSetupFrequiJson_
    _fsSetupFrequiCompose_
  else
    warning "Skipping \"FreqUI\" installation..."
  fi
}

function _fsSetupNginx_() {
    debug "# function _fsSetupNginx_"
  local _confPath="/etc/nginx/conf.d"
  local _confPathFrequi="${_confPath}/frequi.conf"
  local _confPathNginx="${_confPath}/default.conf"
  local _serverName="${FS_SERVER_IP}"
    debug "_serverName: ${_serverName}"
  FS_SERVER_URL="http://${_serverName}"

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
  "    listen ${_serverName}:9000-9100;" \
  "    server_name ${_serverName};" \
  "    location / {" \
  "        proxy_set_header Host \$host;" \
  "        proxy_set_header X-Real-IP \$remote_addr;" \
  "        proxy_pass http://127.0.0.1:\$server_port;" \
  "    }" \
  "}" \
  > "${_confPathFrequi}"

  _fsFileExist_ "${_confPathFrequi}"
  [[ "$(_fsIsFile_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}.disabled"

  sudo rm -f "/etc/nginx/sites-enabled/default"
  sudo ufw allow "Nginx Full"
  sudo ufw allow 9000:9100/tcp
  sudo ufw allow 9999/tcp

  #sudo ufw allow "Nginx Full" > /dev/null
}

function _fsSetupNginxRestart_() {
    debug "# function _fsSetupNginxRestart_"
  if sudo nginx -t 2>&1 | grep -qow "failed"; then
    emergency "Error in nginx config file. For more info enter: nginx -t"
    exit 1
  fi

  sudo /etc/init.d/nginx stop
  sudo pkill -f nginx & wait $!
  sudo /etc/init.d/nginx start
}

function _fsSetupNginxOpenssl_() {
    debug "# function _fsSetupNginxOpenssl_"
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
    debug "# function _setupNginxLetsencrypt_"
  local _domain=""
  local _domainIp=""
  local _serverIp="${FS_SERVER_IP}"
  local _cronCmd="/usr/bin/certbot renew --quiet"
  local _cronUpdate="0 0 * * *"
  
  while true; do
    read -rp "Enter your domain (www.example.com): " _domain
    
    if [[ "${_domain}" = "" ]]; then
      _fsCaseEmpty_
    else
      if [[ "$(_fsCaseConfirmation_ "Is the domain \"${_domain}\" correct?")" -eq 0 ]]; then
        _domainIp="$(host "${_domain}" | awk '/has address/ { print $4 ; exit }')"
          debug "_domainIp: ${_domainIp}"
        if [[ ! "${_domainIp}" = "${_serverIp}" ]]; then
          warning "\"${_domain}\" does not point to \"${_serverIp}\". Review DNS and try again!"
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

function _fsSetupNginxCertbot_() {
    debug "# function _fsSetupNginxCertbot_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _domain="${1}"
  
  _fsSetupPkgs_ certbot python3-certbot-nginx
  
  sudo certbot --nginx -d "${_domain}"
}

function _fsSetupNginxConfSecure_() {
    debug "# function _fsSetupNginxConfSecure_"
  [[ $# == 0 ]] && emergency "Missing required argument to ${FUNCNAME[0]}" && exit 1

  local _mode="${1}"
  local _domain="${2}"
  local _confPath="/etc/nginx/conf.d"
  local _confPathNginx="${_confPath}/default.conf"
  local _confPathFrequi="${_confPath}/frequi.conf"
  local _serverName="${FS_SERVER_IP}"
  
  if [[ -n "${_domain}" ]]; then
    _serverName="${_domain}"
  fi
    debug "_serverName: ${_serverName}"

  FS_SERVER_URL="https://${_serverName}"
    debug "_mode: ${_mode}"
  sudo rm -f "${_confPathFrequi}"
    # thanks: Blood4rc, Hippocritical
  if [[ "${_mode}" = 'openssl' ]]; then
    printf "%s\n" \
    "server {" \
    "    listen 80;" \
    "    listen [::]:80;" \
    "    server_name ${_serverName};" \
    "    return 301 https://\$server_name\$request_uri;" \
    "}" \
    "server {" \
    "    listen 443 ssl;" \
    "    listen [::]:443 ssl;" \
    "    server_name ${_serverName};" \
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
    "    listen ${_serverName}:9000-9100 ssl;" \
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
    "    listen [::]:80;   " \
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
    "    listen ${_serverName}:9000-9100 ssl http2;" \
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
  
  _fsFileExist_ "${_confPathFrequi}"
  
  [[ "$(_fsIsFile_ "${_confPathNginx}")" -eq 0 ]] && sudo mv "${_confPathNginx}" "${_confPathNginx}"'.disabled'
  
  sudo rm -f /etc/nginx/sites-enabled/default*
}

function _fsSetupFrequiJson_() {
    debug "# function _fsSetupFrequiJson_"
  local _frequiJson="${FS_FREQUI_JSON}"
  local _frequiJwt=""
  local _frequiUsername=""
  local _frequiPassword=""
  local _frequiPasswordCompare=""
  local _frequiTmpUsername=""
  local _frequiTmpPassword=""
  local _frequiCors="${FS_SERVER_URL}"
  local _yesForce="${FS_YES}"
  local _setup=1
    debug "_frequiCors: ${_frequiCors}"
  _frequiJwt="$(_fsJsonGet_ "${_frequiJson}" "jwt_secret_key")"
  _frequiUsername="$(_fsJsonGet_ "${_frequiJson}" "username")"
  _frequiPassword="$(_fsJsonGet_ "${_frequiJson}" "password")"

  [[ -z "${_frequiJwt}" ]] && _frequiJwt="$(_fsRandomBase64UrlSafe_)"

  if [[ -n "${_frequiUsername}" ]] || [[ -n "${_frequiPassword}" ]]; then
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
    debug "_frequiJwt: NON VERBOSE"
    debug "_frequiUsername: NON VERBOSE"
    debug "_frequiPassword: NON VERBOSE"
  if [[ "${_setup}" = 0 ]]; then
    info "Create your login data for \"FreqUI\" now!"
      # create username
    while true; do
      read -rp 'Enter username: ' _frequiUsername
        debug "_frequiUsername: ${_frequiUsername}"
      if [[ -n "${_frequiUsername}" ]]; then
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
      read -rs _frequiPassword
      echo
      case ${_frequiPassword} in 
        "")
          _fsCaseEmpty_
          ;;
        *)
          notice 'Enter password again: '
          read -r -s _frequiPasswordCompare
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

function _fsSetupFrequiCompose_() {
    debug "# function _fsSetupFrequiCompose_"
  local _serverUrl="${FS_SERVER_URL}"
  local _fsConfig="${FS_CONFIG}"
  local _frequiYml="${FS_FREQUI_YML}"
  local _frequiJson="${FS_FREQUI_JSON}"
  local _frequiServerJson="${FS_FREQUI_SERVER_JSON}"
  local _frequiName="${FS_NAME}_frequi"
  local _frequiServerLog="${FS_DIR_USER_DATA}/logs/${_frequiName}.log"
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
  
  [[ "$(_fsIsFile_ "${_frequiServerLog}")" -eq 0 ]] &&  rm -f "${_frequiServerLog}"
  
  _fsDockerProjects_ "${_frequiYml}" "compose" "force"
}

function _fsSetupExampleBot_() {
    debug "# function _fsSetupExampleBot_"
  local _userData="${FS_DIR_USER_DATA}"
  local _botExampleName="${FS_NAME}_example"
  local _botExampleYml="${FS_DIR}/${_botExampleName}.yml"
  local _botExampleConfig=""
  local _botExampleConfigName=""
  local _frequiJson=""
  local _binanceProxyJson=""
  local _botExampleExchange=""
  local _botExampleCurrency=""
  local _botExampleKey=""
  local _botExampleSecret=""
  local _botExamplePairlist=""
  local _botExampleLog="${FS_DIR_USER_DATA}/logs/${FS_NAME}_example.log"
  local _setup=1
  local _error=0

  echo
  info 'EXAMPLE (NFI):'

  _frequiJson="$(basename "${FS_FREQUI_JSON}")"
  _binanceProxyJson="$(basename "${FS_BINANCE_PROXY_JSON}")"

  info "Creating an example bot \".yml\" file for dryrun on Binance."
  info "Incl. latest \"NostalgiaForInfinityX\" strategy, \"FreqUI\" and proxy"
    
  if [[ "$(_fsCaseConfirmation_ "Skip create an example bot?")" -eq 0 ]]; then
    warning "Skipping example bot..."
  else
    while true; do
      info "What is the name of your config file? For default name press <ENTER>."
      read -rp " (filename) " _botExampleConfigName
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
      if [[ -n "${_botExampleConfigName}" ]]; then
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
        
        _fsFileExist_ "${_botExampleYml}"
        
        [[ "$(_fsIsFile_ "${_botExampleLog}")" -eq 0 ]] &&  rm -f "${_botExampleLog}"

        info "1) The docker path is different from the real path and starts with \"/freqtrade\"."
        info "2) Add your exchange api KEY and SECRET to: \"exampleconfig_secret.json\""
        info "3) Change port number \"9001\" to an unused port between 9000-9100 in \"${_botExampleYml}\" file."
        notice "Run example bot with: ${FS_NAME} -b $(basename "${_botExampleYml}")"
      else
        alert "Too many errors. Cannot create example bot!"
      fi
    else
      warning "Skipping example bot..."
    fi
  fi
}


### FREQSTART - start
##############################################################################

function _fsStart_ {
    debug "# function _fsStart_"
	local _yml="${1:-}"
  local _symlink="${FS_SYMLINK}"
  local _kill="${FS_KILL}"

    debug "_yml: ${_yml}"
	if [[ "$(_fsIsSymlink_ "${_symlink}")" -eq 1 ]]; then
		alert 'Start setup first with: ./'"${FS_NAME}"'.sh --setup' && exit 1
  fi
  
  _fsIntro_
  if [[ -n "${_yml}" ]]; then
    if [[ "${_kill}" -eq 0 ]]; then
      _fsDockerProjects_ "${_yml}" "kill"
    else
      _fsDockerProjects_ "${_yml}" "compose"
    fi
  else
		alert 'Start bot with: ./'"${FS_NAME}"'.sh --bot example.yml' && exit 1
  fi
  _fsStats_
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
  -s --setup        Install and update
  -b --bot [arg]    Start docker project
  -k --kill         Kill docker project
  -y --yes          Yes on every confirmation
  -a --auto         Autoupdate docker project
  -n --no-color     Disable color output
  -d --debug        Enables debug mode
  -h --help         This page
EOF

# shellcheck disable=SC2015
[[ "${__helptext+x}" ]] || read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 Freqstart simplifies the use of Freqtrade with Docker. Including a setup guide for Freqtrade,
 configurations and FreqUI with a secured SSL proxy for IP or domain. Freqtrade automatically
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
  rm -rf "${FS_DIR_TMP}"
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
  # uncomment to remove docker container or images for debug
  #_fsDockerKillContainers_
  #_fsDockerKillImages_
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
  FS_YES=0
fi

# auto update mode
if [[ "${arg_a:?}" = "1" ]]; then
  FS_AUTO=0
fi

# kill mode
if [[ "${arg_k:?}" = "1" ]]; then
  FS_KILL=0
fi


### Validation. Error out if the things required for your script are not present
##############################################################################

if [[ "${arg_k:?}" = "1" ]]; then
  [[ "${arg_b:-}" ]] || help "Setting an \"example.yml\" file with -b or --bot is required."
fi


### Runtime
##############################################################################

# restrict script to run only once a time
_fsScriptLock_

if [[ "${arg_s:?}" = "1" ]]; then
  _fsSetup_
elif [[ -n "${arg_b:-}" ]]; then
  _fsStart_ "${arg_b}"
else
  help "Help using ${0}"
fi

exit 0
