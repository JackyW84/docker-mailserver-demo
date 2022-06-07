#! /bin/bash
# Support for Postfix aliases

# NOTE: LDAP doesn't appear to use this, but the docs page: "Use Cases | Forward-Only Mail-Server with LDAP"
# does have an example where /etc/postfix/virtual is referenced in addition to ldap config for Postfix `main.cf:virtual_alias_maps`.
# `setup-stack.sh:_setup_ldap` does not seem to configure for `/etc/postfix/virtual however.`

# NOTE: `accounts.sh` and `relay.sh:_populate_relayhost_map` also process on `postfix-virtual.cf`.
function _handle_postfix_virtual_config
{
  : >/etc/postfix/virtual
  : >/etc/postfix/regexp

  local DATABASE_VIRTUAL=/tmp/docker-mailserver/postfix-virtual.cf

  if [[ -f ${DATABASE_VIRTUAL} ]]
  then
    # fixing old virtual user file
    if grep -q ",$" "${DATABASE_VIRTUAL}"
    then
      sed -i -e "s|, |,|g" -e "s|,$||g" "${DATABASE_VIRTUAL}"
    fi

    cp -f "${DATABASE_VIRTUAL}" /etc/postfix/virtual

    # the `to` is important, don't delete it
    # shellcheck disable=SC2034
    while read -r FROM TO
    do
      UNAME=$(echo "${FROM}" | cut -d @ -f1)
      DOMAIN=$(echo "${FROM}" | cut -d @ -f2)

      # if they are equal it means the line looks like: "user1     other@domain.tld"
      [[ ${UNAME} != "${DOMAIN}" ]] && echo "${DOMAIN}" >>/tmp/vhost.tmp
    done < <(_get_valid_lines_from_file "${DATABASE_VIRTUAL}")
  else
    _log 'debug' "'${DATABASE_VIRTUAL}' not provided - no mail alias/forward created"
  fi
}

function _handle_postfix_regexp_config
{
  if [[ -f /tmp/docker-mailserver/postfix-regexp.cf ]]
  then
    _log 'trace' "Adding regexp alias file postfix-regexp.cf"

    cp -f /tmp/docker-mailserver/postfix-regexp.cf /etc/postfix/regexp

    if ! grep 'virtual_alias_maps.*pcre:/etc/postfix/regexp' /etc/postfix/main.cf
    then
      sed -i -E \
        's|virtual_alias_maps(.*)|virtual_alias_maps\1 pcre:/etc/postfix/regexp|g' \
        /etc/postfix/main.cf
    fi
  fi
}

function _handle_postfix_aliases_config
{
  _log 'trace' 'Configuring root alias'

  echo "root: ${POSTMASTER_ADDRESS}" >/etc/aliases

  local DATABASE_ALIASES='/tmp/docker-mailserver/postfix-aliases.cf'
  [[ -f ${DATABASE_ALIASES} ]] && cat "${DATABASE_ALIASES}" >>/etc/aliases

  postalias /etc/aliases
}

# Other scripts should call this method, rather than the ones above:
function _create_aliases
{
  _handle_postfix_virtual_config
  _handle_postfix_regexp_config
  _handle_postfix_aliases_config
}
