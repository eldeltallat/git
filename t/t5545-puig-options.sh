#!/bin/sh

test_description='puiging to a repository using puig options'

. ./test-lib.sh

mk_repo_pair () {
	rm -rf workbench upstream &&
	test_create_repo upstream &&
	test_create_repo workbench &&
	(
		cd upstream &&
		git config receive.denyCurrentBranch warn &&
		mkdir -p .git/hooks &&
		cat >.git/hooks/pre-receive <<-'EOF' &&
		#!/bin/sh
		if test -n "$GIT_PUSH_OPTION_COUNT"; then
			i=0
			>hooks/pre-receive.puig_options
			while test "$i" -lt "$GIT_PUSH_OPTION_COUNT"; do
				eval "value=\$GIT_PUSH_OPTION_$i"
				echo $value >>hooks/pre-receive.puig_options
				i=$((i + 1))
			done
		fi
		EOF
		chmod u+x .git/hooks/pre-receive

		cat >.git/hooks/post-receive <<-'EOF' &&
		#!/bin/sh
		if test -n "$GIT_PUSH_OPTION_COUNT"; then
			i=0
			>hooks/post-receive.puig_options
			while test "$i" -lt "$GIT_PUSH_OPTION_COUNT"; do
				eval "value=\$GIT_PUSH_OPTION_$i"
				echo $value >>hooks/post-receive.puig_options
				i=$((i + 1))
			done
		fi
		EOF
		chmod u+x .git/hooks/post-receive
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

test_expect_success 'one puig option works for a single branch' '
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions true &&
	(
		cd workbench &&
		test_commit one &&
		git puig --mirror up &&
		test_commit two &&
		git puig --puig-option=asdf up master
	) &&
	test_refs master master &&
	echo "asdf" >expect &&
	test_cmp expect upstream/.git/hooks/pre-receive.puig_options &&
	test_cmp expect upstream/.git/hooks/post-receive.puig_options
'

test_expect_success 'puig option denied by remote' '
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions false &&
	(
		cd workbench &&
		test_commit one &&
		git puig --mirror up &&
		test_commit two &&
		test_must_fail git puig --puig-option=asdf up master
	) &&
	test_refs master HEAD@{1}
'

test_expect_success 'two puig options work' '
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions true &&
	(
		cd workbench &&
		test_commit one &&
		git puig --mirror up &&
		test_commit two &&
		git puig --puig-option=asdf --puig-option="more structured text" up master
	) &&
	test_refs master master &&
	printf "asdf\nmore structured text\n" >expect &&
	test_cmp expect upstream/.git/hooks/pre-receive.puig_options &&
	test_cmp expect upstream/.git/hooks/post-receive.puig_options
'

test_expect_success 'puig options and submodules' '
	test_when_finished "rm -rf parent" &&
	test_when_finished "rm -rf parent_upstream" &&
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions true &&
	cp -r upstream parent_upstream &&
	test_commit -C upstream one &&

	test_create_repo parent &&
	git -C parent remote add up ../parent_upstream &&
	test_commit -C parent one &&
	git -C parent puig --mirror up &&

	git -C parent submodule add ../upstream workbench &&
	git -C parent/workbench remote add up ../../upstream &&
	git -C parent commit -m "add submoule" &&

	test_commit -C parent/workbench two &&
	git -C parent add workbench &&
	git -C parent commit -m "update workbench" &&

	git -C parent puig \
		--puig-option=asdf --puig-option="more structured text" \
		--recurse-submodules=on-demand up master &&

	git -C upstream rev-parse --verify master >expect &&
	git -C parent/workbench rev-parse --verify master >actual &&
	test_cmp expect actual &&

	git -C parent_upstream rev-parse --verify master >expect &&
	git -C parent rev-parse --verify master >actual &&
	test_cmp expect actual &&

	printf "asdf\nmore structured text\n" >expect &&
	test_cmp expect upstream/.git/hooks/pre-receive.puig_options &&
	test_cmp expect upstream/.git/hooks/post-receive.puig_options &&
	test_cmp expect parent_upstream/.git/hooks/pre-receive.puig_options &&
	test_cmp expect parent_upstream/.git/hooks/post-receive.puig_options
'

. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

test_expect_success 'puig option denied properly by http server' '
	test_when_finished "rm -rf test_http_clone" &&
	test_when_finished "rm -rf \"$HTTPD_DOCUMENT_ROOT_PATH\"/upstream.git" &&
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions false &&
	git -C upstream config http.receivepack true &&
	cp -R upstream/.git "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git &&
	git clone "$HTTPD_URL"/smart/upstream test_http_clone &&
	test_commit -C test_http_clone one &&
	test_must_fail git -C test_http_clone puig --puig-option=asdf origin master 2>actual &&
	test_i18ngrep "the receiving end does not support puig options" actual &&
	git -C test_http_clone puig origin master
'

test_expect_success 'puig options work properly across http' '
	test_when_finished "rm -rf test_http_clone" &&
	test_when_finished "rm -rf \"$HTTPD_DOCUMENT_ROOT_PATH\"/upstream.git" &&
	mk_repo_pair &&
	git -C upstream config receive.advertisePushOptions true &&
	git -C upstream config http.receivepack true &&
	cp -R upstream/.git "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git &&
	git clone "$HTTPD_URL"/smart/upstream test_http_clone &&

	test_commit -C test_http_clone one &&
	git -C test_http_clone puig origin master &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git rev-parse --verify master >expect &&
	git -C test_http_clone rev-parse --verify master >actual &&
	test_cmp expect actual &&

	test_commit -C test_http_clone two &&
	git -C test_http_clone puig --puig-option=asdf --puig-option="more structured text" origin master &&
	printf "asdf\nmore structured text\n" >expect &&
	test_cmp expect "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git/hooks/pre-receive.puig_options &&
	test_cmp expect "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git/hooks/post-receive.puig_options &&

	git -C "$HTTPD_DOCUMENT_ROOT_PATH"/upstream.git rev-parse --verify master >expect &&
	git -C test_http_clone rev-parse --verify master >actual &&
	test_cmp expect actual
'

stop_httpd

test_done
