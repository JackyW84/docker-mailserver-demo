load "${REPOSITORY_ROOT}/test/helper/common"
load "${REPOSITORY_ROOT}/test/helper/change-detection"
load "${REPOSITORY_ROOT}/test/helper/setup"

BATS_TEST_NAME_PREFIX='[SMTP] (delivery) '
CONTAINER_NAME='dms-test_smtp-delivery'
TEST_FQDN='localhost.localdomain'

function teardown_file() { _default_teardown ; }

function setup_file() {
  _init_with_defaults

  local CONTAINER_ARGS_ENV_CUSTOM=(
    # Required not only for authentication, but delivery in these tests (via nc):
    # TODO: Properly test with DNS records configured and separate container for
    #       handling delivery (without nc). This would remove the need for this ENV:
    --env PERMIT_DOCKER=container
    # NOTE: Authentication is rejected due to default POSTSCREEN_ACTION=enforce and PERMIT_DOCKER=none
    # Non-issue when PERMIT_DOCKER is not the default `none` for these nc 0.0.0.0 tests:
    # --env POSTSCREEN_ACTION=ignore

    # Required for test 'rejects spam':
    --env ENABLE_SPAMASSASSIN=1
    --env SPAMASSASSIN_SPAM_TO_INBOX=0
    # Either SA_TAG or ENABLE_SRS=1 will pass the spamassassin X-SPAM headers test case:
    --env SA_TAG=-5.0

    # Only relevant for tests expecting to match `external.tld=`?:
    # NOTE: Disabling support in tests as it doesn't seem relevant to the test, but misleading..
    # `spam@external.tld` and `user@external.tld` are delivered with with the domain-part changed to `example.test`
    # https://github.com/roehling/postsrsd
    # --env ENABLE_SRS=1
    # Required for ENABLE_SRS=1:
    # --ulimit "nofile=$(ulimit -Sn):$(ulimit -Hn)"

    # Required for tests: 'redirects mail to external aliases' + 'rejects spam':
    --env ENABLE_AMAVIS=1

    # TODO: Relocate relevant tests to the separated clamav test file:
    # Originally relevant, but tests expecting ClamAV weren't properly implemented and didn't raise a failure.
    # --env ENABLE_CLAMAV=1
  )

  # Required for 'delivers mail to existing alias with recipient delimiter':
  mv "${TEST_TMP_CONFIG}/smtp-delivery/postfix-main.cf" "${TEST_TMP_CONFIG}/postfix-main.cf"
  mv "${TEST_TMP_CONFIG}/smtp-delivery/dovecot.cf" "${TEST_TMP_CONFIG}/dovecot.cf"

  _common_container_setup 'CONTAINER_ARGS_ENV_CUSTOM'

  _run_in_container setup email add 'added@localhost.localdomain' 'mypassword'
  assert_success
  _wait_until_change_detection_event_completes

  # Even if the Amavis port is reachable at this point, it may still refuse connections?
  _wait_for_tcp_port_in_container 10024
  _wait_for_smtp_port_in_container_to_respond

  # see https://github.com/docker-mailserver/docker-mailserver/pull/3105#issuecomment-1441055103
  # Amavis may still not be ready to receive mail, sleep a little to avoid connection failures:
  sleep 5

  ### Send mail to queue for delivery ###

  # TODO: Move to clamav tests (For use when ClamAV is enabled):
  # _repeat_in_container_until_success_or_timeout 60 "${CONTAINER_NAME}" test -e /var/run/clamav/clamd.ctl
  # _send_email 'email-templates/amavis-virus'

  # Required for 'delivers mail to existing alias':
  _send_email 'email-templates/existing-alias-external'
  # Required for 'delivers mail to existing alias with recipient delimiter':
  _send_email 'email-templates/existing-alias-recipient-delimiter'
  # Required for 'delivers mail to existing catchall':
  _send_email 'email-templates/existing-catchall-local'
  # Required for 'delivers mail to regexp alias':
  _send_email 'email-templates/existing-regexp-alias-local'

  # Required for 'rejects mail to unknown user':
  _send_email 'email-templates/non-existing-user'
  # Required for 'redirects mail to external aliases':
  _send_email 'email-templates/existing-regexp-alias-external'
  _send_email 'email-templates/existing-alias-local'
  # Required for 'rejects spam':
  _send_email 'email-templates/amavis-spam'

  # Required for 'delivers mail to existing account':
  _send_email 'email-templates/existing-user1'
  _send_email 'email-templates/existing-user2'
  _send_email 'email-templates/existing-user3'
  _send_email 'email-templates/existing-added'
  _send_email 'email-templates/existing-user-and-cc-local-alias'
  _send_email 'email-templates/sieve-spam-folder'
  _send_email 'email-templates/sieve-pipe'
}

@test "should succeed at emptying mail queue" {
  # Try catch errors preventing emptying the queue ahead of waiting:
  _run_in_container mailq
  # Amavis (Port 10024) may not have been ready when first mail was sent:
  refute_output --partial 'Connection refused'
  refute_output --partial '(unknown mail transport error)'
  _wait_for_empty_mail_queue_in_container
}

@test "should successfully authenticate with good password (plain)" {
  _send_email 'auth/smtp-auth-plain' '-w 5 0.0.0.0 465'
  assert_output --partial 'Authentication successful'
}

@test "should fail to authenticate with wrong password (plain)" {
  _send_email 'auth/smtp-auth-plain-wrong' '-w 20 0.0.0.0 465'
  assert_output --partial 'authentication failed'
}

@test "should successfully authenticate with good password (login)" {
  _send_email 'auth/smtp-auth-login' '-w 5 0.0.0.0 465'
  assert_output --partial 'Authentication successful'
}

@test "should fail to authenticate with wrong password (login)" {
  _send_email 'auth/smtp-auth-login-wrong' '-w 20 0.0.0.0 465'
  assert_output --partial 'authentication failed'
}

@test "[user: 'added'] should successfully authenticate with good password (plain)" {
  _send_email 'auth/added-smtp-auth-plain' '-w 5 0.0.0.0 465'
  assert_output --partial 'Authentication successful'
}

@test "[user: 'added'] should fail to authenticate with wrong password (plain)" {
  _send_email 'auth/added-smtp-auth-plain-wrong' '-w 20 0.0.0.0 465'
  assert_output --partial 'authentication failed'
}

@test "[user: 'added'] should successfully authenticate with good password (login)" {
  _send_email 'auth/added-smtp-auth-login' '-w 5 0.0.0.0 465'
  assert_success
  assert_output --partial 'Authentication successful'
}

@test "[user: 'added'] should fail to authenticate with wrong password (login)" {
  _send_email 'auth/added-smtp-auth-login-wrong' '-w 20 0.0.0.0 465'
  assert_output --partial 'authentication failed'
}

# TODO: Add a test covering case SPAMASSASSIN_SPAM_TO_INBOX=1 (default)
@test "delivers mail to existing account" {
  # NOTE: Matched log lines should look similar to:
  # postfix/lmtp[1274]: 0EA424ABE7D9: to=<user1@localhost.localdomain>, relay=127.0.0.1[127.0.0.1]:24, delay=0.13, delays=0.07/0.01/0.01/0.05, dsn=2.0.0, status=sent (250 2.0.0 <user1@localhost.localdomain> ixPpB+Zvv2P7BAAAUi6ngw Saved)
  local LOG_DELIVERED='postfix/lmtp.* status=sent .* Saved)'
  local FORMAT_LINES="sed 's/.* to=</</g' | sed 's/, relay.*//g' | sort | uniq -c | tr -s ' '"
  _run_in_container_bash "grep '${LOG_DELIVERED}' /var/log/mail/mail.log | ${FORMAT_LINES}"
  assert_success

  assert_output --partial '1 <added@localhost.localdomain>'
  assert_output --partial '6 <user1@localhost.localdomain>'
  assert_output --partial '1 <user1~test@localhost.localdomain>'
  assert_output --partial '2 <user2@otherdomain.tld>'
  assert_output --partial '1 <user3@localhost.localdomain>'
  _should_output_number_of_lines 5

  # NOTE: Requires ClamAV enabled and to send `amavis-virus` template:
  # assert_output --partial '1 <user1@localhost.localdomain>, orig_to=<postmaster@example.test>'
  # _should_output_number_of_lines 6
}

@test "delivers mail to existing alias" {
  _run_in_container grep 'to=<user1@localhost.localdomain>, orig_to=<alias1@localhost.localdomain>' /var/log/mail/mail.log
  assert_success
  assert_output --partial 'status=sent'
  _should_output_number_of_lines 1
}

@test "delivers mail to existing alias with recipient delimiter" {
  _run_in_container grep 'to=<user1~test@localhost.localdomain>, orig_to=<alias1~test@localhost.localdomain>' /var/log/mail/mail.log
  assert_success
  assert_output --partial 'status=sent'
  _should_output_number_of_lines 1

  _run_in_container grep 'to=<user1~test@localhost.localdomain>' /var/log/mail/mail.log
  assert_success
  refute_output --partial 'status=bounced'
}

@test "delivers mail to existing catchall" {
  _run_in_container grep 'to=<user1@localhost.localdomain>, orig_to=<wildcard@localdomain2.com>' /var/log/mail/mail.log
  assert_success
  assert_output --partial 'status=sent'
  _should_output_number_of_lines 1
}

@test "delivers mail to regexp alias" {
  _run_in_container grep 'to=<user1@localhost.localdomain>, orig_to=<test123@localhost.localdomain>' /var/log/mail/mail.log
  assert_success
  assert_output --partial 'status=sent'
  _should_output_number_of_lines 1
}

@test "user1 should have received 8 mails" {
  _run_in_container_bash "grep Subject /var/mail/localhost.localdomain/user1/new/* | sed 's/.*Subject: //g' | sed 's/\.txt.*//g' | sed 's/VIRUS.*/VIRUS/g' | sort"
  assert_success

  assert_output --partial 'Test Message existing-alias-external'
  assert_output --partial 'Test Message existing-alias-recipient-delimiter'
  assert_output --partial 'Test Message existing-catchall-local'
  assert_output --partial 'Test Message existing-regexp-alias-local'
  assert_output --partial 'Test Message existing-user-and-cc-local-alias'
  assert_output --partial 'Test Message existing-user1'
  assert_output --partial 'Test Message sieve-spam-folder'
  _should_output_number_of_lines 7

  # The virus mail has three subject lines
  # NOTE: Requires ClamAV enabled and to send amavis-virus:
  # assert_output --partial 'Test Message amavis-virus' # Should verify two lines expected with this content
  # assert_output --partial 'VIRUS'
  # _should_output_number_of_lines 11
}

@test "rejects mail to unknown user" {
  _run_in_container grep '<nouser@localhost.localdomain>: Recipient address rejected: User unknown in virtual mailbox table' /var/log/mail/mail.log
  assert_success
  _should_output_number_of_lines 1
}

@test "redirects mail to external aliases" {
  _run_in_container_bash "grep 'Passed CLEAN {RelayedInbound}' /var/log/mail/mail.log | grep -- '-> <external1@otherdomain.tld>'"
  assert_success
  assert_output --partial '<user@external.tld> -> <external1@otherdomain.tld>'
  _should_output_number_of_lines 2
  # assert_output --partial 'external.tld=user@example.test> -> <external1@otherdomain.tld>'
}

# TODO: Add a test covering case SPAMASSASSIN_SPAM_TO_INBOX=1 (default)
@test "rejects spam" {
  _run_in_container grep 'Blocked SPAM {NoBounceInbound,Quarantined}' /var/log/mail/mail.log
  assert_success
  assert_output --partial '<spam@external.tld> -> <user1@localhost.localdomain>'
  _should_output_number_of_lines 1

  # Amavis log line with SPAMASSASSIN_SPAM_TO_INBOX=0 + grep 'Passed SPAM {RelayedTaggedInbound,Quarantined}' /var/log/mail/mail.log:
  # Amavis log line with SPAMASSASSIN_SPAM_TO_INBOX=1 + grep 'Blocked SPAM {NoBounceInbound,Quarantined}' /var/log/mail/mail.log:
  # <spam@external.tld> -> <user1@localhost.localdomain>
  # Amavis log line with ENABLE_SRS=1 changes the domain-part to match in a log:
  # <SRS0=g+ca=5C=external.tld=spam@example.test> -> <user1@localhost.localdomain>
  # assert_output --partial 'external.tld=spam@example.test> -> <user1@localhost.localdomain>'
}

@test "SA - All registered domains should receive mail with spam headers (X-Spam)" {
  _run_in_container grep -ir 'X-Spam-' /var/mail/localhost.localdomain/user1/new
  assert_success

  _run_in_container grep -ir 'X-Spam-' /var/mail/otherdomain.tld/user2/new
  assert_success
}

# Dovecot does not support SMTPUTF8, so while we can send we cannot receive
# Better disable SMTPUTF8 support entirely if we can't handle it correctly
@test "not advertising smtputf8" {
  _send_email 'email-templates/smtp-ehlo'
  refute_output --partial 'SMTPUTF8'
}
