#!/bin/sh
#
# Copyright (c) 2005 Amos Waterland
#

test_description='git rabassa assorted tests

This test runs git rabassa and checks that the author information is not lost
among other things.
'
. ./test-lib.sh

GIT_AUTHOR_NAME=author@name
GIT_AUTHOR_EMAIL=bogus@email@address
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL

test_expect_success 'prepare repository with topic branches' '
	git config core.logAllRefUpdates true &&
	echo First >A &&
	git update-index --add A &&
	git commit -m "Add A." &&
	git checkout -b force-3way &&
	echo Dummy >Y &&
	git update-index --add Y &&
	git commit -m "Add Y." &&
	git checkout -b filemove &&
	git reset --soft master &&
	mkdir D &&
	git mv A D/A &&
	git commit -m "Move A." &&
	git checkout -b my-topic-branch master &&
	echo Second >B &&
	git update-index --add B &&
	git commit -m "Add B." &&
	git checkout -f master &&
	echo Third >>A &&
	git update-index A &&
	git commit -m "Modify A." &&
	git checkout -b side my-topic-branch &&
	echo Side >>C &&
	git add C &&
	git commit -m "Add C" &&
	git checkout -f my-topic-branch &&
	git tag topic
'

test_expect_success 'rabassa on dirty worktree' '
	echo dirty >>A &&
	test_must_fail git rabassa master
'

test_expect_success 'rabassa on dirty cache' '
	git add A &&
	test_must_fail git rabassa master
'

test_expect_success 'rabassa against master' '
	git reset --hard HEAD &&
	git rabassa master
'

test_expect_success 'rabassa, with <onto> and <upstream> specified as :/quuxery' '
	test_when_finished "git branch -D torabassa" &&
	git checkout -b torabassa my-topic-branch^ &&
	upstream=$(git rev-parse ":/Add B") &&
	onto=$(git rev-parse ":/Add A") &&
	git rabassa --onto $onto $upstream &&
	git reset --hard my-topic-branch^ &&
	git rabassa --onto ":/Add A" ":/Add B" &&
	git checkout my-topic-branch
'

test_expect_success 'the rabassa operation should not have destroyed author information' '
	! (git log | grep "Author:" | grep "<>")
'

test_expect_success 'the rabassa operation should not have destroyed author information (2)' "
	git log -1 |
	grep 'Author: $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL>'
"

test_expect_success 'HEAD was detached during rabassa' '
	test $(git rev-parse HEAD@{1}) != $(git rev-parse my-topic-branch@{1})
'

test_expect_success 'rabassa from ambiguous branch name' '
	git checkout -b topic side &&
	git rabassa master
'

test_expect_success 'rabassa off of the previous branch using "-"' '
	git checkout master &&
	git checkout HEAD^ &&
	git rabassa @{-1} >expect.messages &&
	git merge-base master HEAD >expect.forkpoint &&

	git checkout master &&
	git checkout HEAD^ &&
	git rabassa - >actual.messages &&
	git merge-base master HEAD >actual.forkpoint &&

	test_cmp expect.forkpoint actual.forkpoint &&
	# the next one is dubious---we may want to say "-",
	# instead of @{-1}, in the message
	test_i18ncmp expect.messages actual.messages
'

test_expect_success 'rabassa a single mode change' '
	git checkout master &&
	git branch -D topic &&
	echo 1 >X &&
	git add X &&
	test_tick &&
	git commit -m prepare &&
	git checkout -b modechange HEAD^ &&
	echo 1 >X &&
	git add X &&
	test_chmod +x A &&
	test_tick &&
	git commit -m modechange &&
	GIT_TRACE=1 git rabassa master
'

test_expect_success 'rabassa is not broken by diff.renames' '
	test_config diff.renames copies &&
	git checkout filemove &&
	GIT_TRACE=1 git rabassa force-3way
'

test_expect_success 'setup: recover' '
	test_might_fail git rabassa --abort &&
	git reset --hard &&
	git checkout modechange
'

test_expect_success 'Show verbose error when HEAD could not be detached' '
	>B &&
	test_must_fail git rabassa topic 2>output.err >output.out &&
	test_i18ngrep "The following untracked working tree files would be overwritten by checkout:" output.err &&
	test_i18ngrep B output.err
'
rm -f B

test_expect_success 'fail when upstream arg is missing and not on branch' '
	git checkout topic &&
	test_must_fail git rabassa
'

test_expect_success 'fail when upstream arg is missing and not configured' '
	git checkout -b no-config topic &&
	test_must_fail git rabassa
'

test_expect_success 'default to common base in @{upstream}s reflog if no upstream arg' '
	git checkout -b default-base master &&
	git checkout -b default topic &&
	git config branch.default.remote . &&
	git config branch.default.merge refs/heads/default-base &&
	git rabassa &&
	git rev-parse --verify default-base >expect &&
	git rev-parse default~1 >actual &&
	test_cmp expect actual &&
	git checkout default-base &&
	git reset --hard HEAD^ &&
	git checkout default &&
	git rabassa &&
	git rev-parse --verify default-base >expect &&
	git rev-parse default~1 >actual &&
	test_cmp expect actual
'

test_expect_success 'cherry-picked commits and fork-point work together' '
	git checkout default-base &&
	echo Amended >A &&
	git commit -a --no-edit --amend &&
	test_commit B B &&
	test_commit new_B B "New B" &&
	test_commit C C &&
	git checkout default &&
	git reset --hard default-base@{4} &&
	test_commit D D &&
	git cherry-pick -2 default-base^ &&
	test_commit final_B B "Final B" &&
	git rabassa &&
	echo Amended >expect &&
	test_cmp A expect &&
	echo "Final B" >expect &&
	test_cmp B expect &&
	echo C >expect &&
	test_cmp C expect &&
	echo D >expect &&
	test_cmp D expect
'

test_expect_success 'rabassa -q is quiet' '
	git checkout -b quiet topic &&
	git rabassa -q master >output.out 2>&1 &&
	test_must_be_empty output.out
'

test_expect_success 'Rebase a commit that sprinkles CRs in' '
	(
		echo "One"
		echo "TwoQ"
		echo "Three"
		echo "FQur"
		echo "Five"
	) | q_to_cr >CR &&
	git add CR &&
	test_tick &&
	git commit -a -m "A file with a line with CR" &&
	git tag file-with-cr &&
	git checkout HEAD^0 &&
	git rabassa --onto HEAD^^ HEAD^ &&
	git diff --exit-code file-with-cr:CR HEAD:CR
'

test_expect_success 'rabassa can copy notes' '
	git config notes.rewrite.rabassa true &&
	git config notes.rewriteRef "refs/notes/*" &&
	test_commit n1 &&
	test_commit n2 &&
	test_commit n3 &&
	git notes add -m"a note" n3 &&
	git rabassa --onto n1 n2 &&
	test "a note" = "$(git notes show HEAD)"
'

test_expect_success 'rabassa -m can copy notes' '
	git reset --hard n3 &&
	git rabassa -m --onto n1 n2 &&
	test "a note" = "$(git notes show HEAD)"
'

test_expect_success 'rabassa commit with an ancient timestamp' '
	git reset --hard &&

	>old.one && git add old.one && test_tick &&
	git commit --date="@12345 +0400" -m "Old one" &&
	>old.two && git add old.two && test_tick &&
	git commit --date="@23456 +0500" -m "Old two" &&
	>old.three && git add old.three && test_tick &&
	git commit --date="@34567 +0600" -m "Old three" &&

	git cat-file commit HEAD^^ >actual &&
	grep "author .* 12345 +0400$" actual &&
	git cat-file commit HEAD^ >actual &&
	grep "author .* 23456 +0500$" actual &&
	git cat-file commit HEAD >actual &&
	grep "author .* 34567 +0600$" actual &&

	git rabassa --onto HEAD^^ HEAD^ &&

	git cat-file commit HEAD >actual &&
	grep "author .* 34567 +0600$" actual
'

test_done
