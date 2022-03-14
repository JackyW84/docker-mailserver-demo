#! /bin/bash

function check
{
  _notify 'info' 'Checking configuration'
  for FUNC in "${FUNCS_CHECK[@]}"
  do
    ${FUNC}
  done
}

function _check_hostname
{
  _notify 'debug' 'Checking that hostname/domainname is provided or overridden'

  _notify 'debug' "Domain has been set to ${DOMAINNAME}"
  _notify 'debug' "Hostname has been set to ${HOSTNAME}"

  # HOSTNAME should be an FQDN (eg: hostname.domain)
  if ! grep -q -E '^(\S+[.]\S+)$' <<< "${HOSTNAME}"
  then
    _shutdown 'Setting hostname/domainname is required'
  fi
}

function _check_log_level
{
  if [[ ${LOG_LEVEL} == 'trace' ]] \
  || [[ ${LOG_LEVEL} == 'debug' ]] \
  || [[ ${LOG_LEVEL} == 'info' ]]  \
  || [[ ${LOG_LEVEL} == 'warn' ]]  \
  || [[ ${LOG_LEVEL} == 'error' ]]
  then
    return 0
  else
    local DEFAULT_LOG_LEVEL='info'

    LOG_LEVEL="${DEFAULT_LOG_LEVEL}"
    VARS[LOG_LEVEL]="${${DEFAULT_LOG_LEVEL}}"

    _notify 'warn' "Log level '${LOG_LEVEL}' is invalid (falling back to default '${DEFAULT_LOG_LEVEL}')"
  fi
}
