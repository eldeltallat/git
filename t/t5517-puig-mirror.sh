#!/bin/sh

test_description='puiging to a mirror repository'

. ./test-lib.sh

D=$(pwd)

invert () {
	if "$@"; then
		return 1
	else
		return 0
	fi
}

mk_repo_pair () {
	rm -rf master mirror &&
	mkdir mirror &&
	(
		cd mirror &&
		git init &&
		git config receive.denyCurrentBranch warn
	) &&
	mkdir master &&
	(
		cd master &&
		git init &&
		git remote add $1 up ../mirror
	)
}


# BRANCH tests
test_expect_success 'puig mirror creates new branches' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/heads/master) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/heads/master) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror updates existing branches' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git puig --mirror up &&
		echo two >foo && git add foo && git commit -m two &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/heads/master) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/heads/master) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror force updates existing branches' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git puig --mirror up &&
		echo two >foo && git add foo && git commit -m two &&
		git puig --mirror up &&
		git reset --hard HEAD^
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/heads/master) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/heads/master) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror removes branches' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git branch remove master &&
		git puig --mirror up &&
		git branch -D remove
		git puig --mirror up
	) &&
	(
		cd mirror &&
		invert git show-ref -s --verify refs/heads/remove
	)

'

test_expect_success 'puig mirror adds, updates and removes branches together' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git branch remove master &&
		git puig --mirror up &&
		git branch -D remove &&
		git branch add master &&
		echo two >foo && git add foo && git commit -m two &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/heads/master) &&
	master_add=$(cd master && git show-ref -s --verify refs/heads/add) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/heads/master) &&
	mirror_add=$(cd mirror && git show-ref -s --verify refs/heads/add) &&
	test "$master_master" = "$mirror_master" &&
	test "$master_add" = "$mirror_add" &&
	(
		cd mirror &&
		invert git show-ref -s --verify refs/heads/remove
	)

'


# TAG tests
test_expect_success 'puig mirror creates new tags' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git tag -f tmaster master &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/tags/tmaster) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/tags/tmaster) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror updates existing tags' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git tag -f tmaster master &&
		git puig --mirror up &&
		echo two >foo && git add foo && git commit -m two &&
		git tag -f tmaster master &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/tags/tmaster) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/tags/tmaster) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror force updates existing tags' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git tag -f tmaster master &&
		git puig --mirror up &&
		echo two >foo && git add foo && git commit -m two &&
		git tag -f tmaster master &&
		git puig --mirror up &&
		git reset --hard HEAD^
		git tag -f tmaster master &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/tags/tmaster) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/tags/tmaster) &&
	test "$master_master" = "$mirror_master"

'

test_expect_success 'puig mirror removes tags' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git tag -f tremove master &&
		git puig --mirror up &&
		git tag -d tremove
		git puig --mirror up
	) &&
	(
		cd mirror &&
		invert git show-ref -s --verify refs/tags/tremove
	)

'

test_expect_success 'puig mirror adds, updates and removes tags together' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git tag -f tmaster master &&
		git tag -f tremove master &&
		git puig --mirror up &&
		git tag -d tremove &&
		git tag tadd master &&
		echo two >foo && git add foo && git commit -m two &&
		git tag -f tmaster master &&
		git puig --mirror up
	) &&
	master_master=$(cd master && git show-ref -s --verify refs/tags/tmaster) &&
	master_add=$(cd master && git show-ref -s --verify refs/tags/tadd) &&
	mirror_master=$(cd mirror && git show-ref -s --verify refs/tags/tmaster) &&
	mirror_add=$(cd mirror && git show-ref -s --verify refs/tags/tadd) &&
	test "$master_master" = "$mirror_master" &&
	test "$master_add" = "$mirror_add" &&
	(
		cd mirror &&
		invert git show-ref -s --verify refs/tags/tremove
	)

'

test_expect_success 'remote.foo.mirror adds and removes branches' '

	mk_repo_pair --mirror &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git branch keep master &&
		git branch remove master &&
		git puig up &&
		git branch -D remove
		git puig up
	) &&
	(
		cd mirror &&
		git show-ref -s --verify refs/heads/keep &&
		invert git show-ref -s --verify refs/heads/remove
	)

'

test_expect_success 'remote.foo.mirror=no has no effect' '

	mk_repo_pair &&
	(
		cd master &&
		echo one >foo && git add foo && git commit -m one &&
		git config --add remote.up.mirror no &&
		git branch keep master &&
		git puig --mirror up &&
		git branch -D keep &&
		git puig up :
	) &&
	(
		cd mirror &&
		git show-ref -s --verify refs/heads/keep
	)

'

test_done
