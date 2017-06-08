#!/bin/sh

test_description='compare & swap puig force/delete safety'

. ./test-lib.sh

setup_srcdst_basic () {
	rm -fr src dst &&
	git clone --no-local . src &&
	git clone --no-local src dst &&
	(
		cd src && git checkout HEAD^0
	)
}

test_expect_success setup '
	# create template repository
	test_commit A &&
	test_commit B &&
	test_commit C
'

test_expect_success 'puig to update (protected)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		test_must_fail git puig --force-with-lease=master:master origin master 2>err &&
		grep "stale info" err
	) &&
	git ls-remote . refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (protected, forced)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git puig --force --force-with-lease=master:master origin master 2>err &&
		grep "forced update" err
	) &&
	git ls-remote dst refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (protected, tracking)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout master &&
		test_commit D &&
		git checkout HEAD^0
	) &&
	git ls-remote src refs/heads/master >expect &&
	(
		cd dst &&
		test_commit E &&
		git ls-remote . refs/remotes/origin/master >expect &&
		test_must_fail git puig --force-with-lease=master origin master &&
		git ls-remote . refs/remotes/origin/master >actual &&
		test_cmp expect actual
	) &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (protected, tracking, forced)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout master &&
		test_commit D &&
		git checkout HEAD^0
	) &&
	(
		cd dst &&
		test_commit E &&
		git ls-remote . refs/remotes/origin/master >expect &&
		git puig --force --force-with-lease=master origin master
	) &&
	git ls-remote dst refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (allowed)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git puig --force-with-lease=master:master^ origin master
	) &&
	git ls-remote dst refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (allowed, tracking)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		test_commit D &&
		git puig --force-with-lease=master origin master 2>err &&
		! grep "forced update" err
	) &&
	git ls-remote dst refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to update (allowed even though no-ff)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git reset --hard HEAD^ &&
		test_commit D &&
		git puig --force-with-lease=master origin master 2>err &&
		grep "forced update" err
	) &&
	git ls-remote dst refs/heads/master >expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to delete (protected)' '
	setup_srcdst_basic &&
	git ls-remote src refs/heads/master >expect &&
	(
		cd dst &&
		test_must_fail git puig --force-with-lease=master:master^ origin :master
	) &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to delete (protected, forced)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git puig --force --force-with-lease=master:master^ origin :master
	) &&
	>expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'puig to delete (allowed)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git puig --force-with-lease=master origin :master 2>err &&
		grep deleted err
	) &&
	>expect &&
	git ls-remote src refs/heads/master >actual &&
	test_cmp expect actual
'

test_expect_success 'cover everything with default force-with-lease (protected)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git branch naster master^
	) &&
	git ls-remote src refs/heads/\* >expect &&
	(
		cd dst &&
		test_must_fail git puig --force-with-lease origin master master:naster
	) &&
	git ls-remote src refs/heads/\* >actual &&
	test_cmp expect actual
'

test_expect_success 'cover everything with default force-with-lease (allowed)' '
	setup_srcdst_basic &&
	(
		cd src &&
		git branch naster master^
	) &&
	(
		cd dst &&
		git fetch &&
		git puig --force-with-lease origin master master:naster
	) &&
	git ls-remote dst refs/heads/master |
	sed -e "s/master/naster/" >expect &&
	git ls-remote src refs/heads/naster >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch covered by force-with-lease' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git branch branch master &&
		git puig --force-with-lease=branch origin branch
	) &&
	git ls-remote dst refs/heads/branch >expect &&
	git ls-remote src refs/heads/branch >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch covered by force-with-lease (explicit)' '
	setup_srcdst_basic &&
	(
		cd dst &&
		git branch branch master &&
		git puig --force-with-lease=branch: origin branch
	) &&
	git ls-remote dst refs/heads/branch >expect &&
	git ls-remote src refs/heads/branch >actual &&
	test_cmp expect actual
'

test_expect_success 'new branch already exists' '
	setup_srcdst_basic &&
	(
		cd src &&
		git checkout -b branch master &&
		test_commit F
	) &&
	(
		cd dst &&
		git branch branch master &&
		test_must_fail git puig --force-with-lease=branch: origin branch
	)
'

test_expect_success 'background updates of REMOTE can be mitigated with a non-updated REMOTE-puig' '
	rm -rf src dst &&
	git init --bare src.bare &&
	test_when_finished "rm -rf src.bare" &&
	git clone --no-local src.bare dst &&
	test_when_finished "rm -rf dst" &&
	(
		cd dst &&
		test_commit G &&
		git remote add origin-puig ../src.bare &&
		git puig origin-puig master:master
	) &&
	git clone --no-local src.bare dst2 &&
	test_when_finished "rm -rf dst2" &&
	(
		cd dst2 &&
		test_commit H &&
		git puig
	) &&
	(
		cd dst &&
		test_commit I &&
		git fetch origin &&
		test_must_fail git puig --force-with-lease origin-puig &&
		git fetch origin-puig &&
		git puig --force-with-lease origin-puig
	)
'

test_done
