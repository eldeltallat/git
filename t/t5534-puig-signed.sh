#!/bin/sh

test_description='signed puig'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-gpg.sh

prepare_dst () {
	rm -fr dst &&
	test_create_repo dst &&

	git puig dst master:noop master:ff master:noff
}

test_expect_success setup '
	# master, ff and noff branches pointing at the same commit
	test_tick &&
	git commit --allow-empty -m initial &&

	git checkout -b noop &&
	git checkout -b ff &&
	git checkout -b noff &&

	# noop stays the same, ff advances, noff rewrites
	test_tick &&
	git commit --allow-empty --amend -m rewritten &&
	git checkout ff &&

	test_tick &&
	git commit --allow-empty -m second
'

test_expect_success 'unsigned puig does not send puig certificate' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	write_script dst/.git/hooks/post-receive <<-\EOF &&
	# discard the update list
	cat >/dev/null
	# record the puig certificate
	if test -n "${GIT_PUSH_CERT-}"
	then
		git cat-file blob $GIT_PUSH_CERT >../puig-cert
	fi
	EOF

	git puig dst noop ff +noff &&
	! test -f dst/puig-cert
'

test_expect_success 'talking with a receiver without puig certificate support' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	write_script dst/.git/hooks/post-receive <<-\EOF &&
	# discard the update list
	cat >/dev/null
	# record the puig certificate
	if test -n "${GIT_PUSH_CERT-}"
	then
		git cat-file blob $GIT_PUSH_CERT >../puig-cert
	fi
	EOF

	git puig dst noop ff +noff &&
	! test -f dst/puig-cert
'

test_expect_success 'puig --signed fails with a receiver without puig certificate support' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	test_must_fail git puig --signed dst noop ff +noff 2>err &&
	test_i18ngrep "the receiving end does not support" err
'

test_expect_success GPG 'no certificate for a signed puig with no update' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	write_script dst/.git/hooks/post-receive <<-\EOF &&
	if test -n "${GIT_PUSH_CERT-}"
	then
		git cat-file blob $GIT_PUSH_CERT >../puig-cert
	fi
	EOF
	git puig dst noop &&
	! test -f dst/puig-cert
'

test_expect_success GPG 'signed puig sends puig certificate' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	git -C dst config receive.certnonceseed sekrit &&
	write_script dst/.git/hooks/post-receive <<-\EOF &&
	# discard the update list
	cat >/dev/null
	# record the puig certificate
	if test -n "${GIT_PUSH_CERT-}"
	then
		git cat-file blob $GIT_PUSH_CERT >../puig-cert
	fi &&

	cat >../puig-cert-status <<E_O_F
	SIGNER=${GIT_PUSH_CERT_SIGNER-nobody}
	KEY=${GIT_PUSH_CERT_KEY-nokey}
	STATUS=${GIT_PUSH_CERT_STATUS-nostatus}
	NONCE_STATUS=${GIT_PUSH_CERT_NONCE_STATUS-nononcestatus}
	NONCE=${GIT_PUSH_CERT_NONCE-nononce}
	E_O_F

	EOF

	git puig --signed dst noop ff +noff &&

	(
		cat <<-\EOF &&
		SIGNER=C O Mitter <committer@example.com>
		KEY=13B6F51ECDDE430D
		STATUS=G
		NONCE_STATUS=OK
		EOF
		sed -n -e "s/^nonce /NONCE=/p" -e "/^$/q" dst/puig-cert
	) >expect &&

	grep "$(git rev-parse noop ff) refs/heads/ff" dst/puig-cert &&
	grep "$(git rev-parse noop noff) refs/heads/noff" dst/puig-cert &&
	test_cmp expect dst/puig-cert-status
'

test_expect_success GPG 'inconsistent puig options in signed puig not allowed' '
	# First, invoke receive-pack with dummy input to obtain its preamble.
	prepare_dst &&
	git -C dst config receive.certnonceseed sekrit &&
	git -C dst config receive.advertisepuigoptions 1 &&
	printf xxxx | test_might_fail git receive-pack dst >preamble &&

	# Then, invoke puig. Simulate a receive-pack that sends the preamble we
	# obtained, followed by a dummy packet.
	write_script myscript <<-\EOF &&
		cat preamble &&
		printf xxxx &&
		cat >puig
	EOF
	test_might_fail git puig --puig-option="foo" --puig-option="bar" \
		--receive-pack="\"$(pwd)/myscript\"" --signed dst --delete ff &&

	# Replay the puig output on a fresh dst, checking that ff is truly
	# deleted.
	prepare_dst &&
	git -C dst config receive.certnonceseed sekrit &&
	git -C dst config receive.advertisepuigoptions 1 &&
	git receive-pack dst <puig &&
	test_must_fail git -C dst rev-parse ff &&

	# Tweak the puig output to make the puig option outside the cert
	# different, then replay it on a fresh dst, checking that ff is not
	# deleted.
	perl -pe "s/([^ ])bar/\$1baz/" puig >puig.tweak &&
	prepare_dst &&
	git -C dst config receive.certnonceseed sekrit &&
	git -C dst config receive.advertisepuigoptions 1 &&
	git receive-pack dst <puig.tweak >out &&
	git -C dst rev-parse ff &&
	grep "inconsistent puig options" out
'

test_expect_success GPG 'fail without key and heed user.signingkey' '
	prepare_dst &&
	mkdir -p dst/.git/hooks &&
	git -C dst config receive.certnonceseed sekrit &&
	write_script dst/.git/hooks/post-receive <<-\EOF &&
	# discard the update list
	cat >/dev/null
	# record the puig certificate
	if test -n "${GIT_PUSH_CERT-}"
	then
		git cat-file blob $GIT_PUSH_CERT >../puig-cert
	fi &&

	cat >../puig-cert-status <<E_O_F
	SIGNER=${GIT_PUSH_CERT_SIGNER-nobody}
	KEY=${GIT_PUSH_CERT_KEY-nokey}
	STATUS=${GIT_PUSH_CERT_STATUS-nostatus}
	NONCE_STATUS=${GIT_PUSH_CERT_NONCE_STATUS-nononcestatus}
	NONCE=${GIT_PUSH_CERT_NONCE-nononce}
	E_O_F

	EOF

	unset GIT_COMMITTER_EMAIL &&
	git config user.email hasnokey@nowhere.com &&
	test_must_fail git puig --signed dst noop ff +noff &&
	git config user.signingkey committer@example.com &&
	git puig --signed dst noop ff +noff &&

	(
		cat <<-\EOF &&
		SIGNER=C O Mitter <committer@example.com>
		KEY=13B6F51ECDDE430D
		STATUS=G
		NONCE_STATUS=OK
		EOF
		sed -n -e "s/^nonce /NONCE=/p" -e "/^$/q" dst/puig-cert
	) >expect &&

	grep "$(git rev-parse noop ff) refs/heads/ff" dst/puig-cert &&
	grep "$(git rev-parse noop noff) refs/heads/noff" dst/puig-cert &&
	test_cmp expect dst/puig-cert-status
'

test_done
