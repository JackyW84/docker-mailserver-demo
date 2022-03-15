#! /bin/bash

# ### DMS Logging Functionality
#
# This function provides the logging for scripts used by DMS.
# It adheres to the convention for log levels (trace as the
# highest level, then debug, info, warning and last but not
# least, error, the lowest log level).
#
# Furthermore, calling `_notify 'always' ...` will log a
# message independently of the log level. This should only
# be used in `start-mailserver.sh`.
#
# #### Arguments
#
# $1  :: the log level to log the message with
# $2+ :: the message
#
# #### Panics
#
# If the first argument is not set or not valid, an error
# message is logged. Moreover, of there is no second argument
# an error message is also logged. The function will in all
# of the above mentioned cases return with exit code 1.
function _notify
{
  if [[ -z ${1+set} ]]
  then
    _notify 'error' "Call to '_notify' without log level happened, but is not valid"
    return 1
  fi

  if [[ -z ${2+set} ]]
  then
    _notify 'error' "Call to '_notify' without message happened, but is not valid"
    return 1
  fi

  local MESSAGE LEVEL_AS_INT RESET='\e[0m'
  MESSAGE="${RESET}["

  case "${LOG_LEVEL}" in
    ( 'trace'  ) LEVEL_AS_INT=5 ;;
    ( 'debug'  ) LEVEL_AS_INT=4 ;;
    ( 'info'   ) LEVEL_AS_INT=3 ;;
    ( 'warn'   ) LEVEL_AS_INT=2 ;;
    ( 'error'  ) LEVEL_AS_INT=1 ;;
  esac

  case "${1}" in
    ( 'trace' )
      [[ ${LEVEL_AS_INT} -ge 5 ]] || return 0
      local LGRAY='\e[37m'
      MESSAGE+="  ${LGRAY}TRACE  "
      ;;

    ( 'debug' )
      [[ ${LEVEL_AS_INT} -ge 4 ]] || return 0
      local LBLUE='\e[94m'
      MESSAGE+="  ${LBLUE}DEBUG  "
      ;;

    ( 'info' )
      [[ ${LEVEL_AS_INT} -ge 3 ]] || return 0
      local BLUE='\e[34m'
      MESSAGE+="   ${BLUE}INF   "
      ;;

    ( 'warn' )
      [[ ${LEVEL_AS_INT} -ge 2 ]] || return 0
      local LYELLOW='\e[93m'
      MESSAGE+=" ${LYELLOW}WARNING "
      ;;

    ( 'error' )
      [[ ${LEVEL_AS_INT} -ge 1 ]] || return 0
      local RED='\e[91m'
      MESSAGE+="  ${RED}ERROR  " ;;

    ( 'always' )
      MESSAGE+="         "
      ;;

    ( * )
      _notify 'error' \
        "Call to '_notify' with invalid log level" \
        "argument '${1}'"
      ;;

  esac

  shift 1
  MESSAGE+="${RESET}]  |  ${*}"

  echo -e "${MESSAGE}"
  return 0
}
