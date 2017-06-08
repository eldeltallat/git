#!/bin/sh

test_description='test <branch>@{puig} syntax'
. ./test-lib.sh

resolve () {
	echo "$2" >expect &&
	git rev-parse --symbolic-full-name "$1" >actual &&
	test_cmp expect actual
}

test_expect_success 'setup' '
	git init --bare parent.git &&
	git init --bare other.git &&
	git remote add origin parent.git &&
	git remote add other other.git &&
	test_commit base &&
	git puig origin HEAD &&
	git branch --set-upstream-to=origin/master master &&
	git branch --track topic origin/master &&
	git puig origin topic &&
	git puig other topic
'

test_expect_success '@{puig} with default=nothing' '
	test_config puig.default nothing &&
	test_must_fail git rev-parse master@{puig} &&
	test_must_fail git rev-parse master@{PUSH} &&
	test_must_fail git rev-parse master@{PuSH}
'

test_expect_success '@{puig} with default=simple' '
	test_config puig.default simple &&
	resolve master@{puig} refs/remotes/origin/master &&
	resolve master@{PUSH} refs/remotes/origin/master &&
	resolve master@{pUSh} refs/remotes/origin/master
'

test_expect_success 'triangular @{puig} fails with default=simple' '
	test_config puig.default simple &&
	test_must_fail git rev-parse topic@{puig}
'

test_expect_success '@{puig} with default=current' '
	test_config puig.default current &&
	resolve topic@{puig} refs/remotes/origin/topic
'

test_expect_success '@{puig} with default=matching' '
	test_config puig.default matching &&
	resolve topic@{puig} refs/remotes/origin/topic
'

test_expect_success '@{puig} with puigremote defined' '
	test_config puig.default current &&
	test_config branch.topic.puigremote other &&
	resolve topic@{puig} refs/remotes/other/topic
'

test_expect_success '@{puig} with puig refspecs' '
	test_config puig.default nothing &&
	test_config remote.origin.puig refs/heads/*:refs/heads/magic/* &&
	git puig &&
	resolve topic@{puig} refs/remotes/origin/magic/topic
'

test_expect_success 'resolving @{puig} fails with a detached HEAD' '
	git checkout HEAD^0 &&
	test_when_finished "git checkout -" &&
	test_must_fail git rev-parse @{puig}
'

test_done
