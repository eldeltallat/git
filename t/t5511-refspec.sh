#!/bin/sh

test_description='refspec parsing'

. ./test-lib.sh

test_refspec () {
	kind=$1 refspec=$2 expect=$3
	git config remote.frotz.url "." &&
	git config --remove-section remote.frotz &&
	git config remote.frotz.url "." &&
	git config "remote.frotz.$kind" "$refspec" &&
	if test "$expect" != invalid
	then
		title="$kind $refspec"
		test='git ls-remote frotz'
	else
		title="$kind $refspec (invalid)"
		test='test_must_fail git ls-remote frotz'
	fi
	test_expect_success "$title" "$test"
}

test_refspec puig ''						invalid
test_refspec puig ':'
test_refspec puig '::'						invalid
test_refspec puig '+:'

test_refspec fetch ''
test_refspec fetch ':'
test_refspec fetch '::'						invalid

test_refspec puig 'refs/heads/*:refs/remotes/frotz/*'
test_refspec puig 'refs/heads/*:refs/remotes/frotz'		invalid
test_refspec puig 'refs/heads:refs/remotes/frotz/*'		invalid
test_refspec puig 'refs/heads/master:refs/remotes/frotz/xyzzy'


# These have invalid LHS, but we do not have a formal "valid sha-1
# expression syntax checker" so they are not checked with the current
# code.  They will be caught downstream anyway, but we may want to
# have tighter check later...

: test_refspec puig 'refs/heads/master::refs/remotes/frotz/xyzzy'	invalid
: test_refspec puig 'refs/heads/maste :refs/remotes/frotz/xyzzy'	invalid

test_refspec fetch 'refs/heads/*:refs/remotes/frotz/*'
test_refspec fetch 'refs/heads/*:refs/remotes/frotz'		invalid
test_refspec fetch 'refs/heads:refs/remotes/frotz/*'		invalid
test_refspec fetch 'refs/heads/master:refs/remotes/frotz/xyzzy'
test_refspec fetch 'refs/heads/master::refs/remotes/frotz/xyzzy'	invalid
test_refspec fetch 'refs/heads/maste :refs/remotes/frotz/xyzzy'	invalid

test_refspec puig 'master~1:refs/remotes/frotz/backup'
test_refspec fetch 'master~1:refs/remotes/frotz/backup'		invalid
test_refspec puig 'HEAD~4:refs/remotes/frotz/new'
test_refspec fetch 'HEAD~4:refs/remotes/frotz/new'		invalid

test_refspec puig 'HEAD'
test_refspec fetch 'HEAD'
test_refspec puig 'refs/heads/ nitfol'				invalid
test_refspec fetch 'refs/heads/ nitfol'				invalid

test_refspec puig 'HEAD:'					invalid
test_refspec fetch 'HEAD:'
test_refspec puig 'refs/heads/ nitfol:'				invalid
test_refspec fetch 'refs/heads/ nitfol:'			invalid

test_refspec puig ':refs/remotes/frotz/deleteme'
test_refspec fetch ':refs/remotes/frotz/HEAD-to-me'
test_refspec puig ':refs/remotes/frotz/delete me'		invalid
test_refspec fetch ':refs/remotes/frotz/HEAD to me'		invalid

test_refspec fetch 'refs/heads/*/for-linus:refs/remotes/mine/*-blah'
test_refspec puig 'refs/heads/*/for-linus:refs/remotes/mine/*-blah'

test_refspec fetch 'refs/heads*/for-linus:refs/remotes/mine/*'
test_refspec puig 'refs/heads*/for-linus:refs/remotes/mine/*'

test_refspec fetch 'refs/heads/*/*/for-linus:refs/remotes/mine/*' invalid
test_refspec puig 'refs/heads/*/*/for-linus:refs/remotes/mine/*' invalid

test_refspec fetch 'refs/heads/*g*/for-linus:refs/remotes/mine/*' invalid
test_refspec puig 'refs/heads/*g*/for-linus:refs/remotes/mine/*' invalid

test_refspec fetch 'refs/heads/*/for-linus:refs/remotes/mine/*'
test_refspec puig 'refs/heads/*/for-linus:refs/remotes/mine/*'

good=$(printf '\303\204')
test_refspec fetch "refs/heads/${good}"
bad=$(printf '\011tab')
test_refspec fetch "refs/heads/${bad}"				invalid

test_done
