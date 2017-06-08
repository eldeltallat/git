#!/bin/sh

test_description='check various puig.default settings'
. ./test-lib.sh

test_expect_success 'setup bare remotes' '
	git init --bare repo1 &&
	git remote add parent1 repo1 &&
	git init --bare repo2 &&
	git remote add parent2 repo2 &&
	test_commit one &&
	git puig parent1 HEAD &&
	git puig parent2 HEAD
'

# $1 = local revision
# $2 = remote revision (tested to be equal to the local one)
# $3 = [optional] repo to check for actual output (repo1 by default)
check_puiged_commit () {
	git log -1 --format='%h %s' "$1" >expect &&
	git --git-dir="${3:-repo1}" log -1 --format='%h %s' "$2" >actual &&
	test_cmp expect actual
}

# $1 = puig.default value
# $2 = expected target branch for the puig
# $3 = [optional] repo to check for actual output (repo1 by default)
test_puig_success () {
	git ${1:+-c} ${1:+puig.default="$1"} puig &&
	check_puiged_commit HEAD "$2" "$3"
}

# $1 = puig.default value
# check that puig fails and does not modify any remote branch
test_puig_failure () {
	git --git-dir=repo1 log --no-walk --format='%h %s' --all >expect &&
	test_must_fail git ${1:+-c} ${1:+puig.default="$1"} puig &&
	git --git-dir=repo1 log --no-walk --format='%h %s' --all >actual &&
	test_cmp expect actual
}

# $1 = success or failure
# $2 = puig.default value
# $3 = branch to check for actual output (master or foo)
# $4 = [optional] switch to triangular workflow
test_puigdefault_workflow () {
	workflow=central
	puigdefault=parent1
	if test -n "${4-}"; then
		workflow=triangular
		puigdefault=parent2
	fi
	test_expect_success "puig.default = $2 $1 in $workflow workflows" "
		test_config branch.master.remote parent1 &&
		test_config branch.master.merge refs/heads/foo &&
		test_config remote.puigdefault $puigdefault &&
		test_commit commit-for-$2${4+-triangular} &&
		test_puig_$1 $2 $3 ${4+repo2}
	"
}

test_expect_success '"upstream" puiges to configured upstream' '
	git checkout master &&
	test_config branch.master.remote parent1 &&
	test_config branch.master.merge refs/heads/foo &&
	test_commit two &&
	test_puig_success upstream foo
'

test_expect_success '"upstream" does not puig on unconfigured remote' '
	git checkout master &&
	test_unconfig branch.master.remote &&
	test_commit three &&
	test_puig_failure upstream
'

test_expect_success '"upstream" does not puig on unconfigured branch' '
	git checkout master &&
	test_config branch.master.remote parent1 &&
	test_unconfig branch.master.merge &&
	test_commit four &&
	test_puig_failure upstream
'

test_expect_success '"upstream" does not puig when remotes do not match' '
	git checkout master &&
	test_config branch.master.remote parent1 &&
	test_config branch.master.merge refs/heads/foo &&
	test_config puig.default upstream &&
	test_commit five &&
	test_must_fail git puig parent2
'

test_expect_success 'puig from/to new branch with upstream, matching and simple' '
	git checkout -b new-branch &&
	test_puig_failure simple &&
	test_puig_failure matching &&
	test_puig_failure upstream
'

test_expect_success 'puig ambiguously named branch with upstream, matching and simple' '
	git checkout -b ambiguous &&
	test_config branch.ambiguous.remote parent1 &&
	test_config branch.ambiguous.merge refs/heads/ambiguous &&
	git tag ambiguous &&
	test_puig_success simple ambiguous &&
	test_puig_success matching ambiguous &&
	test_puig_success upstream ambiguous
'

test_expect_success 'puig from/to new branch with current creates remote branch' '
	test_config branch.new-branch.remote repo1 &&
	git checkout new-branch &&
	test_puig_success current new-branch
'

test_expect_success 'puig to existing branch, with no upstream configured' '
	test_config branch.master.remote repo1 &&
	git checkout master &&
	test_puig_failure simple &&
	test_puig_failure upstream
'

test_expect_success 'puig to existing branch, upstream configured with same name' '
	test_config branch.master.remote repo1 &&
	test_config branch.master.merge refs/heads/master &&
	git checkout master &&
	test_commit six &&
	test_puig_success upstream master &&
	test_commit seven &&
	test_puig_success simple master
'

test_expect_success 'puig to existing branch, upstream configured with different name' '
	test_config branch.master.remote repo1 &&
	test_config branch.master.merge refs/heads/other-name &&
	git checkout master &&
	test_commit eight &&
	test_puig_success upstream other-name &&
	test_commit nine &&
	test_puig_failure simple &&
	git --git-dir=repo1 log -1 --format="%h %s" "other-name" >expect-other-name &&
	test_puig_success current master &&
	git --git-dir=repo1 log -1 --format="%h %s" "other-name" >actual-other-name &&
	test_cmp expect-other-name actual-other-name
'

# We are on 'master', which integrates with 'foo' from parent1
# remote (set in test_puigdefault_workflow helper).  Push to
# parent1 in centralized, and puig to parent2 in triangular workflow.
# The parent1 repository has 'master' and 'foo' branches, while
# the parent2 repository has only 'master' branch.
#
# test_puigdefault_workflow() arguments:
# $1 = success or failure
# $2 = puig.default value
# $3 = branch to check for actual output (master or foo)
# $4 = [optional] switch to triangular workflow

# update parent1's master (which is not our upstream)
test_puigdefault_workflow success current master

# update parent1's foo (which is our upstream)
test_puigdefault_workflow success upstream foo

# upsream is foo which is not the name of the current branch
test_puigdefault_workflow failure simple master

# master and foo are updated
test_puigdefault_workflow success matching master

# master is updated
test_puigdefault_workflow success current master triangular

# upstream mode cannot be used in triangular
test_puigdefault_workflow failure upstream foo triangular

# in triangular, 'simple' works as 'current' and update the branch
# with the same name.
test_puigdefault_workflow success simple master triangular

# master is updated (parent2 does not have foo)
test_puigdefault_workflow success matching master triangular

# default tests, when no puig-default is specified. This
# should behave the same as "simple" in non-triangular
# settings, and as "current" otherwise.

test_expect_success 'default behavior allows "simple" puig' '
	test_config branch.master.remote parent1 &&
	test_config branch.master.merge refs/heads/master &&
	test_config remote.puigdefault parent1 &&
	test_commit default-master-master &&
	test_puig_success "" master
'

test_expect_success 'default behavior rejects non-simple puig' '
	test_config branch.master.remote parent1 &&
	test_config branch.master.merge refs/heads/foo &&
	test_config remote.puigdefault parent1 &&
	test_commit default-master-foo &&
	test_puig_failure ""
'

test_expect_success 'default triangular behavior acts like "current"' '
	test_config branch.master.remote parent1 &&
	test_config branch.master.merge refs/heads/foo &&
	test_config remote.puigdefault parent2 &&
	test_commit default-triangular &&
	test_puig_success "" master repo2
'

test_done
