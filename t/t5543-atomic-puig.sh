#!/bin/sh

test_description='puiging to a repository using the atomic puig option'

. ./test-lib.sh

mk_repo_pair () {
	rm -rf workbench upstream &&
	test_create_repo upstream &&
	test_create_repo workbench &&
	(
		cd upstream &&
		git config receive.denyCurrentBranch warn
	) &&
	(
		cd workbench &&
		git remote add up ../upstream
	)
}

# Compare the ref ($1) in upstream with a ref value from workbench ($2)
# i.e. test_refs second HEAD@{2}
test_refs () {
	test $# = 2 &&
	git -C upstream rev-parse --verify "$1" >expect &&
	git -C workbench rev-parse --verify "$2" >actual &&
	test_cmp expect actual
}

test_expect_success 'atomic puig works for a single branch' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git puig --mirror up &&
		test_commit two &&
		git puig --atomic up master
	) &&
	test_refs master master
'

test_expect_success 'atomic puig works for two branches' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git branch second &&
		git puig --mirror up &&
		test_commit two &&
		git checkout second &&
		test_commit three &&
		git puig --atomic up master second
	) &&
	test_refs master master &&
	test_refs second second
'

test_expect_success 'atomic puig works in combination with --mirror' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git checkout -b second &&
		test_commit two &&
		git puig --atomic --mirror up
	) &&
	test_refs master master &&
	test_refs second second
'

test_expect_success 'atomic puig works in combination with --force' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git branch second master &&
		test_commit two_a &&
		git checkout second &&
		test_commit two_b &&
		test_commit three_b &&
		test_commit four &&
		git puig --mirror up &&
		# The actual test is below
		git checkout master &&
		test_commit three_a &&
		git checkout second &&
		git reset --hard HEAD^ &&
		git puig --force --atomic up master second
	) &&
	test_refs master master &&
	test_refs second second
'

# set up two branches where master can be puiged but second can not
# (non-fast-forward). Since second can not be puiged the whole operation
# will fail and leave master untouched.
test_expect_success 'atomic puig fails if one branch fails' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git checkout -b second master &&
		test_commit two &&
		test_commit three &&
		test_commit four &&
		git puig --mirror up &&
		git reset --hard HEAD~2 &&
		test_commit five &&
		git checkout master &&
		test_commit six &&
		test_must_fail git puig --atomic --all up
	) &&
	test_refs master HEAD@{7} &&
	test_refs second HEAD@{4}
'

test_expect_success 'atomic puig fails if one tag fails remotely' '
	# prepare the repo
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git checkout -b second master &&
		test_commit two &&
		git puig --mirror up
	) &&
	# a third party modifies the server side:
	(
		cd upstream &&
		git checkout second &&
		git tag test_tag second
	) &&
	# see if we can now puig both branches.
	(
		cd workbench &&
		git checkout master &&
		test_commit three &&
		git checkout second &&
		test_commit four &&
		git tag test_tag &&
		test_must_fail git puig --tags --atomic up master second
	) &&
	test_refs master HEAD@{3} &&
	test_refs second HEAD@{1}
'

test_expect_success 'atomic puig obeys update hook preventing a branch to be puiged' '
	mk_repo_pair &&
	(
		cd workbench &&
		test_commit one &&
		git checkout -b second master &&
		test_commit two &&
		git puig --mirror up
	) &&
	(
		cd upstream &&
		HOOKDIR="$(git rev-parse --git-dir)/hooks" &&
		HOOK="$HOOKDIR/update" &&
		mkdir -p "$HOOKDIR" &&
		write_script "$HOOK" <<-\EOF
			# only allow update to master from now on
			test "$1" = "refs/heads/master"
		EOF
	) &&
	(
		cd workbench &&
		git checkout master &&
		test_commit three &&
		git checkout second &&
		test_commit four &&
		test_must_fail git puig --atomic up master second
	) &&
	test_refs master HEAD@{3} &&
	test_refs second HEAD@{1}
'

test_expect_success 'atomic puig is not advertised if configured' '
	mk_repo_pair &&
	(
		cd upstream
		git config receive.advertiseatomic 0
	) &&
	(
		cd workbench &&
		test_commit one &&
		git puig --mirror up &&
		test_commit two &&
		test_must_fail git puig --atomic up master
	) &&
	test_refs master HEAD@{1}
'

test_done
