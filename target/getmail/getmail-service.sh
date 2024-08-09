#!/bin/bash

# shellcheck source=../scripts/helpers/log.sh
source /usr/local/bin/helpers/log.sh

# Directory, where "oldmail" files are stored.
# getmail stores its state - its "memory" of what it has seen in your POP/IMAP account - in the oldmail files.
GETMAIL_DIR=/var/lib/getmail

# Kill all child processes on EXIT.
# Otherwise 'supervisorctl restart getmail' leads to zombie 'sleep' processes.
trap 'pkill --parent $$' EXIT

function _stopService() {
  _log 'warn' "Stopping getmail service"
  exec supervisorctl stop getmail
}

# Verify the correct value for GETMAIL_POLL. Valid are any numbers greater than 0.
if ! [[ ${GETMAIL_POLL} =~ ^[0-9]+$ && ${GETMAIL_POLL} -gt 0 ]]; then
  _log 'warn' "Invalid value for GETMAIL_POLL: ${GETMAIL_POLL}"
  _stopService
fi

# If no matching filenames are found, and the shell option nullglob is disabled, the word is left unchanged.
# If the nullglob option is set, and no matches are found, the word is removed.
shopt -s nullglob

# Run each getmailrc periodically.
while :; do
  for RC_FILE in /etc/getmailrc.d/*; do
    _log 'debug' "Processing ${RC_FILE}"
    getmail --getmaildir "${GETMAIL_DIR}" --rcfile "${RC_FILE}"
  done

  # Stop service if no configuration is found.
  if [[ -z ${RC_FILE} ]]; then
    _log 'warn' 'No getmail configration found'
    _stopService
  fi

  sleep "${GETMAIL_POLL}m"
done
