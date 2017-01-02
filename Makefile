NAME = tvial/docker-mailserver:testing

all: build-no-cache generate-accounts run fixtures tests clean
all-fast: build generate-accounts run fixtures tests clean
all-fast-local: build generate-accounts run-local fixtures tests clean
no-build: generate-accounts run fixtures tests clean

build-no-cache:
	cd test/docker-openldap/ && docker build -f Dockerfile -t ldap --no-cache .
	docker build --no-cache -t $(NAME) .

build:
	cd test/docker-openldap/ && docker build -f Dockerfile -t ldap .
	docker build -t $(NAME) .

generate-accounts:
	docker run --rm -e MAIL_USER=user1@localhost.localdomain -e MAIL_PASS=mypassword -t $(NAME) /bin/sh -c 'echo "$$MAIL_USER|$$(doveadm pw -s SHA512-CRYPT -u $$MAIL_USER -p $$MAIL_PASS)"' > test/config/postfix-accounts.cf
	docker run --rm -e MAIL_USER=user2@otherdomain.tld -e MAIL_PASS=mypassword -t $(NAME) /bin/sh -c 'echo "$$MAIL_USER|$$(doveadm pw -s SHA512-CRYPT -u $$MAIL_USER -p $$MAIL_PASS)"' >> test/config/postfix-accounts.cf

run:
ifeq ($(ENABLE_LDAP),1)
	# Run ldap
	docker run -d --name ldap-for-mail \
 		-e LDAP_DOMAIN="localhost.localdomain" \
		-h mail.my-domain.com -t ldap
endif

	# Run mail container
	docker run -d --name mail \
		-v "`pwd`/test/config":/tmp/docker-mailserver \
		-v "`pwd`/test":/tmp/docker-mailserver-test \
		-v "`pwd`/test/onedir":/var/mail-state \
		-e ENABLE_CLAMAV=$(ENABLE_CLAMAV) \
		-e ENABLE_SPAMASSASSIN=$(ENABLE_SPAMASSASSIN) \
		-e ENABLE_POP3=$(ENABLE_POP3) \
		-e ENABLE_FAIL2BAN=$(ENABLE_FAIL2BAN) \
		-e ENABLE_MANAGESIEVE=$(ENABLE_MANAGESIEVE) \
		-e ENABLE_FETCHMAIL=$(ENABLE_FETCHMAIL) \
		-e ONE_DIR=$(ONE_DIR) \
		-e PERMIT_DOCKER=$(PERMIT_DOCKER) \
		-e ENABLE_LDAP=$(ENABLE_LDAP) \
		-e LDAP_SERVER_HOST=$(LDAP_SERVER_HOST) \
		-e LDAP_SEARCH_BASE=$(LDAP_SEARCH_BASE) \
		-e LDAP_BIND_DN=$(LDAP_BIND_DN) \
		-e ENABLE_SASLAUTHD=$(ENABLE_SASLAUTHD) \
		-e SASLAUTHD_MECHANISMS=$(SASLAUTHD_MECHANISMS) \
		-e SASLAUTHD_LDAP_SERVER=$(SASLAUTHD_LDAP_SERVER) \
		-e SASLAUTHD_LDAP_BIND_DN=$(SASLAUTHD_LDAP_BIND_DN) \
		-e SASLAUTHD_LDAP_PASSWORD=$(SASLAUTHD_LDAP_PASSWORD) \
		-e SASLAUTHD_LDAP_SEARCH_BASE=$(SASLAUTHD_LDAP_SEARCH_BASE) \
		-e SMTP_ONLY=$(SMTP_ONLY) \
		-e SA_TAG=$(SA_TAG) \
		-e SA_TAG2=$(SA_TAG2) \
		-e SA_KILL=$(SA_KILL) \
		-e VIRUSMAILS_DELETE_DELAY=$(VIRUSMAILS_DELETE_DELAY) \
		-e SASL_PASSWD="$(SASL_PASSWD)" \
		-e DMS_DEBUG=$(DMS_DEBUG) \
		--cap-add=NET_ADMIN \
		-h mail.my-domain.com -t $(NAME)

	# Wait for containers to fully start
	sleep 15

run-local:
	docker run -d --name mail \
		-v "`pwd`/test/config":/tmp/docker-mailserver \
		-v "`pwd`/test":/tmp/docker-mailserver-test \
		-v "`pwd`/test/onedir":/var/mail-state \
		--env-file=.env-testing \
		--cap-add=NET_ADMIN \
		--add-host=pop3.example.tld:127.0.0.1 \
		-h mail.my-domain.com -t $(NAME)
	# Wait for containers to fully start
	sleep 15

fixtures:
	# Display env configuration
	docker exec mail printenv
	cp config/postfix-accounts.cf config/postfix-accounts.cf.bak
	# Setup sieve & create filtering folder (INBOX/spam)
	docker cp "`pwd`/test/config/sieve/dovecot.sieve" mail:/var/mail/localhost.localdomain/user1/.dovecot.sieve
	docker exec mail /bin/sh -c "maildirmake.dovecot /var/mail/localhost.localdomain/user1/.INBOX.spam"
	docker exec mail /bin/sh -c "chown 5000:5000 -R /var/mail/localhost.localdomain/user1/.INBOX.spam"
	# Sending test mails
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/amavis-spam.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/amavis-virus.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-alias-external.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-alias-local.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-user.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-user-and-cc-local-alias.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-regexp-alias-external.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-regexp-alias-local.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/existing-catchall-local.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/sieve-spam-folder.txt"
	docker exec mail /bin/sh -c "nc 0.0.0.0 25 < /tmp/docker-mailserver-test/email-templates/non-existing-user.txt"
	# Wait for mails to be analyzed
	sleep 10

tests:
	# Start tests
	./test/bats/bin/bats test/tests.bats

clean:
	# Remove running test containers
	-docker rm -f \
		mail \
		fail-auth-mailer \
		ldap-for-mail

	@if [ -f config/postfix-accounts.cf.bak ]; then\
		rm -f config/postfix-accounts.cf ;\
		mv config/postfix-accounts.cf.bak config/postfix-accounts.cf ;\
	fi
	-sudo rm -rf test/onedir \
		test/config/empty \
		test/config/without-accounts \
		test/config/without-virtual \
		test/config/postfix-accounts.cf.bak
