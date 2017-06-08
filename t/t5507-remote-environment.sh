#!/bin/sh

test_description='check environment showed to remote side of transports'
. ./test-lib.sh

test_expect_success 'set up "remote" puig situation' '
	test_commit one &&
	git config puig.default current &&
	git init remote
'

test_expect_success 'set up fake ssh' '
	GIT_SSH_COMMAND="f() {
		cd \"\$TRASH_DIRECTORY\" &&
		eval \"\$2\"
	}; f" &&
	export GIT_SSH_COMMAND &&
	export TRASH_DIRECTORY
'

# due to receive.denyCurrentBranch=true
test_expect_success 'confirm default puig fails' '
	test_must_fail git puig remote
'

test_expect_success 'config does not travel over same-machine puig' '
	test_must_fail git -c receive.denyCurrentBranch=false puig remote
'

test_expect_success 'config does not travel over ssh puig' '
	test_must_fail git -c receive.denyCurrentBranch=false puig host:remote
'

test_done
