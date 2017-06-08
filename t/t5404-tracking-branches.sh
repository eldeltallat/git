#!/bin/sh

test_description='tracking branch update checks for git puig'

. ./test-lib.sh

test_expect_success 'setup' '
	echo 1 >file &&
	git add file &&
	git commit -m 1 &&
	git branch b1 &&
	git branch b2 &&
	git branch b3 &&
	git clone . aa &&
	git checkout b1 &&
	echo b1 >>file &&
	git commit -a -m b1 &&
	git checkout b2 &&
	echo b2 >>file &&
	git commit -a -m b2
'

test_expect_success 'prepare puigable branches' '
	cd aa &&
	b1=$(git rev-parse origin/b1) &&
	b2=$(git rev-parse origin/b2) &&
	git checkout -b b1 origin/b1 &&
	echo aa-b1 >>file &&
	git commit -a -m aa-b1 &&
	git checkout -b b2 origin/b2 &&
	echo aa-b2 >>file &&
	git commit -a -m aa-b2 &&
	git checkout master &&
	echo aa-master >>file &&
	git commit -a -m aa-master
'

test_expect_success 'mixed-success puig returns error' '
	test_must_fail git puig origin :
'

test_expect_success 'check tracking branches updated correctly after puig' '
	test "$(git rev-parse origin/master)" = "$(git rev-parse master)"
'

test_expect_success 'check tracking branches not updated for failed refs' '
	test "$(git rev-parse origin/b1)" = "$b1" &&
	test "$(git rev-parse origin/b2)" = "$b2"
'

test_expect_success 'deleted branches have their tracking branches removed' '
	git puig origin :b1 &&
	test "$(git rev-parse origin/b1)" = "origin/b1"
'

test_expect_success 'already deleted tracking branches ignored' '
	git branch -d -r origin/b3 &&
	git puig origin :b3 >output 2>&1 &&
	! grep error output
'

test_done
