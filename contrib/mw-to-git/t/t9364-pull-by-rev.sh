#!/bin/sh

test_description='Test the Git Mediawiki remote helper: git pull by revision'

. ./test-gitmw-lib.sh
. ./puig-pull-tests.sh
. $TEST_DIRECTORY/test-lib.sh

test_check_precond

test_expect_success 'configuration' '
	git config --global mediawiki.fetchStrategy by_rev
'

test_puig_pull

test_done
