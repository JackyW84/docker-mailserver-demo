load "${REPOSITORY_ROOT}/test/helper/common"
load "${REPOSITORY_ROOT}/test/helper/setup"

# Feature (ENV DOVECOT_MAILBOX_FORMAT) - Logic in `setup-stack:_setup_dovecot()`
# - Configures mail_location in 10-mail.conf to a supported dbox type
# - Then adds a cron task to purge dbox for freeing disk space (see upstream docs)

# PR: https://github.com/docker-mailserver/docker-mailserver/pull/1314
# Docs (upstream): https://doc.dovecot.org/configuration_manual/mail_location/dbox/#dbox-settings

BATS_TEST_NAME_PREFIX='[Dovecot] '

CONTAINER1_NAME='dms-test_dovecot-dbox_sdbox'
CONTAINER2_NAME='dms-test_dovecot-dbox_mdbox'

function teardown() { _default_teardown ; }

@test "(ENV DOVECOT_MAILBOX_FORMAT=sdbox) should store received mail at expected location" {
  export CONTAINER_NAME=${CONTAINER1_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(
    --env DOVECOT_MAILBOX_FORMAT=sdbox
    --env PERMIT_DOCKER=container
  )

  _init_with_defaults
  _common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  _wait_for_smtp_port_in_container

  _send_email 'existing-user1'
  _wait_for_empty_mail_queue_in_container

  # Mail received should be stored as `u.1` (one file per message)
  local MAILBOX_STORAGE='/var/mail/localhost.localdomain/user1/mailboxes/INBOX/dbox-Mails'
  _count_files_in_directory_in_container "${MAILBOX_STORAGE}" 3
  assert_output --partial "${MAILBOX_STORAGE}/dovecot.index.log"
  assert_output --partial "${MAILBOX_STORAGE}/u.1"
  assert_output --partial "${MAILBOX_STORAGE}/dovecot.index.cache"
}

@test "(ENV DOVECOT_MAILBOX_FORMAT=mdbox) should store received mail at expected location" {
  export CONTAINER_NAME=${CONTAINER2_NAME}
  local CUSTOM_SETUP_ARGUMENTS=(
    --env DOVECOT_MAILBOX_FORMAT=mdbox
    --env PERMIT_DOCKER=container
  )

  _init_with_defaults
  _common_container_setup 'CUSTOM_SETUP_ARGUMENTS'
  _wait_for_smtp_port_in_container

  _send_email 'existing-user1'
  _wait_for_empty_mail_queue_in_container

  # Mail received should be stored in `m.1` (1 or more messages)
  local MAILBOX_STORAGE='/var/mail/localhost.localdomain/user1/storage'
  _count_files_in_directory_in_container "${MAILBOX_STORAGE}" 2
  assert_output --partial "${MAILBOX_STORAGE}/dovecot.map.index.log"
  assert_output --partial "${MAILBOX_STORAGE}/m.1"
}
