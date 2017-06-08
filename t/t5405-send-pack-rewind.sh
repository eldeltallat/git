#!/bin/sh

test_description='forced puig to replace commit we do not have'

. ./test-lib.sh

test_expect_success setup '

	>file1 && git add file1 && test_tick &&
	git commit -m Initial &&
	git config receive.denyCurrentBranch warn &&

	mkdir another && (
		cd another &&
		git init &&
		git fetch --update-head-ok .. master:master
	) &&

	>file2 && git add file2 && test_tick &&
	git commit -m Second

'

test_expect_success 'non forced puig should die not segfault' '

	(
		cd another &&
		git puig .. master:master
		test $? = 1
	)

'

test_expect_success 'forced puig should succeed' '

	(
		cd another &&
		git puig .. +master:master
	)

'

test_done
