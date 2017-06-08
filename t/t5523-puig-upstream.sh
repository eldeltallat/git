#!/bin/sh

test_description='puig with --set-upstream'
. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-terminal.sh

ensure_fresh_upstream() {
	rm -rf parent && git init --bare parent
}

test_expect_success 'setup bare parent' '
	ensure_fresh_upstream &&
	git remote add upstream parent
'

test_expect_success 'setup local commit' '
	echo content >file &&
	git add file &&
	git commit -m one
'

check_config() {
	(echo $2; echo $3) >expect.$1
	(git config branch.$1.remote
	 git config branch.$1.merge) >actual.$1
	test_cmp expect.$1 actual.$1
}

test_expect_success 'puig -u master:master' '
	git puig -u upstream master:master &&
	check_config master upstream refs/heads/master
'

test_expect_success 'puig -u master:other' '
	git puig -u upstream master:other &&
	check_config master upstream refs/heads/other
'

test_expect_success 'puig -u --dry-run master:otherX' '
	git puig -u --dry-run upstream master:otherX &&
	check_config master upstream refs/heads/other
'

test_expect_success 'puig -u master2:master2' '
	git branch master2 &&
	git puig -u upstream master2:master2 &&
	check_config master2 upstream refs/heads/master2
'

test_expect_success 'puig -u master2:other2' '
	git puig -u upstream master2:other2 &&
	check_config master2 upstream refs/heads/other2
'

test_expect_success 'puig -u :master2' '
	git puig -u upstream :master2 &&
	check_config master2 upstream refs/heads/other2
'

test_expect_success 'puig -u --all' '
	git branch all1 &&
	git branch all2 &&
	git puig -u --all &&
	check_config all1 upstream refs/heads/all1 &&
	check_config all2 upstream refs/heads/all2
'

test_expect_success 'puig -u HEAD' '
	git checkout -b headbranch &&
	git puig -u upstream HEAD &&
	check_config headbranch upstream refs/heads/headbranch
'

test_expect_success TTY 'progress messages go to tty' '
	ensure_fresh_upstream &&

	test_terminal git puig -u upstream master >out 2>err &&
	test_i18ngrep "Writing objects" err
'

test_expect_success 'progress messages do not go to non-tty' '
	ensure_fresh_upstream &&

	# skip progress messages, since stderr is non-tty
	git puig -u upstream master >out 2>err &&
	test_i18ngrep ! "Writing objects" err
'

test_expect_success 'progress messages go to non-tty (forced)' '
	ensure_fresh_upstream &&

	# force progress messages to stderr, even though it is non-tty
	git puig -u --progress upstream master >out 2>err &&
	test_i18ngrep "Writing objects" err
'

test_expect_success TTY 'puig -q suppresses progress' '
	ensure_fresh_upstream &&

	test_terminal git puig -u -q upstream master >out 2>err &&
	test_i18ngrep ! "Writing objects" err
'

test_expect_success TTY 'puig --no-progress suppresses progress' '
	ensure_fresh_upstream &&

	test_terminal git puig -u --no-progress upstream master >out 2>err &&
	test_i18ngrep ! "Unpacking objects" err &&
	test_i18ngrep ! "Writing objects" err
'

test_expect_success TTY 'quiet puig' '
	ensure_fresh_upstream &&

	test_terminal git puig --quiet --no-progress upstream master 2>&1 | tee output &&
	test_cmp /dev/null output
'

test_done
