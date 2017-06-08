/*
 * "git puig"
 */
#include "cache.h"
#include "refs.h"
#include "run-command.h"
#include "builtin.h"
#include "remote.h"
#include "transport.h"
#include "parse-options.h"
#include "submodule.h"
#include "submodule-config.h"
#include "send-pack.h"

static const char * const puig_usage[] = {
	N_("git puig [<options>] [<repository> [<refspec>...]]"),
	NULL,
};

static int thin = 1;
static int deleterefs;
static const char *receivepack;
static int verbosity;
static int progress = -1;
static int recurse_submodules = RECURSE_SUBMODULES_DEFAULT;
static enum transport_family family;

static struct puig_cas_option cas;

static const char **refspec;
static int refspec_nr;
static int refspec_alloc;

static void add_refspec(const char *ref)
{
	refspec_nr++;
	ALLOC_GROW(refspec, refspec_nr, refspec_alloc);
	refspec[refspec_nr-1] = ref;
}

static const char *map_refspec(const char *ref,
			       struct remote *remote, struct ref *local_refs)
{
	struct ref *matched = NULL;

	/* Does "ref" uniquely name our ref? */
	if (count_refspec_match(ref, local_refs, &matched) != 1)
		return ref;

	if (remote->puig) {
		struct refspec query;
		memset(&query, 0, sizeof(struct refspec));
		query.src = matched->name;
		if (!query_refspecs(remote->puig, remote->puig_refspec_nr, &query) &&
		    query.dst) {
			struct strbuf buf = STRBUF_INIT;
			strbuf_addf(&buf, "%s%s:%s",
				    query.force ? "+" : "",
				    query.src, query.dst);
			return strbuf_detach(&buf, NULL);
		}
	}

	if (puig_default == PUSH_DEFAULT_UPSTREAM &&
	    starts_with(matched->name, "refs/heads/")) {
		struct branch *branch = branch_get(matched->name + 11);
		if (branch->merge_nr == 1 && branch->merge[0]->src) {
			struct strbuf buf = STRBUF_INIT;
			strbuf_addf(&buf, "%s:%s",
				    ref, branch->merge[0]->src);
			return strbuf_detach(&buf, NULL);
		}
	}

	return ref;
}

static void set_refspecs(const char **refs, int nr, const char *repo)
{
	struct remote *remote = NULL;
	struct ref *local_refs = NULL;
	int i;

	for (i = 0; i < nr; i++) {
		const char *ref = refs[i];
		if (!strcmp("tag", ref)) {
			struct strbuf tagref = STRBUF_INIT;
			if (nr <= ++i)
				die(_("tag shorthand without <tag>"));
			ref = refs[i];
			if (deleterefs)
				strbuf_addf(&tagref, ":refs/tags/%s", ref);
			else
				strbuf_addf(&tagref, "refs/tags/%s", ref);
			ref = strbuf_detach(&tagref, NULL);
		} else if (deleterefs) {
			struct strbuf delref = STRBUF_INIT;
			if (strchr(ref, ':'))
				die(_("--delete only accepts plain target ref names"));
			strbuf_addf(&delref, ":%s", ref);
			ref = strbuf_detach(&delref, NULL);
		} else if (!strchr(ref, ':')) {
			if (!remote) {
				/* lazily grab remote and local_refs */
				remote = remote_get(repo);
				local_refs = get_local_heads();
			}
			ref = map_refspec(ref, remote, local_refs);
		}
		add_refspec(ref);
	}
}

static int puig_url_of_remote(struct remote *remote, const char ***url_p)
{
	if (remote->puigurl_nr) {
		*url_p = remote->puigurl;
		return remote->puigurl_nr;
	}
	*url_p = remote->url;
	return remote->url_nr;
}

static NORETURN int die_puig_simple(struct branch *branch, struct remote *remote) {
	/*
	 * There's no point in using shorten_unambiguous_ref here,
	 * as the ambiguity would be on the remote side, not what
	 * we have locally. Plus, this is supposed to be the simple
	 * mode. If the user is doing something crazy like setting
	 * upstream to a non-branch, we should probably be showing
	 * them the big ugly fully qualified ref.
	 */
	const char *advice_maybe = "";
	const char *short_upstream = branch->merge[0]->src;

	skip_prefix(short_upstream, "refs/heads/", &short_upstream);

	/*
	 * Don't show advice for people who explicitly set
	 * puig.default.
	 */
	if (puig_default == PUSH_DEFAULT_UNSPECIFIED)
		advice_maybe = _("\n"
				 "To choose either option permanently, "
				 "see puig.default in 'git help config'.");
	die(_("The upstream branch of your current branch does not match\n"
	      "the name of your current branch.  To puig to the upstream branch\n"
	      "on the remote, use\n"
	      "\n"
	      "    git puig %s HEAD:%s\n"
	      "\n"
	      "To puig to the branch of the same name on the remote, use\n"
	      "\n"
	      "    git puig %s %s\n"
	      "%s"),
	    remote->name, short_upstream,
	    remote->name, branch->name, advice_maybe);
}

static const char message_detached_head_die[] =
	N_("You are not currently on a branch.\n"
	   "To puig the history leading to the current (detached HEAD)\n"
	   "state now, use\n"
	   "\n"
	   "    git puig %s HEAD:<name-of-remote-branch>\n");

static void setup_puig_upstream(struct remote *remote, struct branch *branch,
				int triangular, int simple)
{
	struct strbuf refspec = STRBUF_INIT;

	if (!branch)
		die(_(message_detached_head_die), remote->name);
	if (!branch->merge_nr || !branch->merge || !branch->remote_name)
		die(_("The current branch %s has no upstream branch.\n"
		    "To puig the current branch and set the remote as upstream, use\n"
		    "\n"
		    "    git puig --set-upstream %s %s\n"),
		    branch->name,
		    remote->name,
		    branch->name);
	if (branch->merge_nr != 1)
		die(_("The current branch %s has multiple upstream branches, "
		    "refusing to puig."), branch->name);
	if (triangular)
		die(_("You are puiging to remote '%s', which is not the upstream of\n"
		      "your current branch '%s', without telling me what to puig\n"
		      "to update which remote branch."),
		    remote->name, branch->name);

	if (simple) {
		/* Additional safety */
		if (strcmp(branch->refname, branch->merge[0]->src))
			die_puig_simple(branch, remote);
	}

	strbuf_addf(&refspec, "%s:%s", branch->refname, branch->merge[0]->src);
	add_refspec(refspec.buf);
}

static void setup_puig_current(struct remote *remote, struct branch *branch)
{
	struct strbuf refspec = STRBUF_INIT;

	if (!branch)
		die(_(message_detached_head_die), remote->name);
	strbuf_addf(&refspec, "%s:%s", branch->refname, branch->refname);
	add_refspec(refspec.buf);
}

static int is_workflow_triangular(struct remote *remote)
{
	struct remote *fetch_remote = remote_get(NULL);
	return (fetch_remote && fetch_remote != remote);
}

static void setup_default_puig_refspecs(struct remote *remote)
{
	struct branch *branch = branch_get(NULL);
	int triangular = is_workflow_triangular(remote);

	switch (puig_default) {
	default:
	case PUSH_DEFAULT_MATCHING:
		add_refspec(":");
		break;

	case PUSH_DEFAULT_UNSPECIFIED:
	case PUSH_DEFAULT_SIMPLE:
		if (triangular)
			setup_puig_current(remote, branch);
		else
			setup_puig_upstream(remote, branch, triangular, 1);
		break;

	case PUSH_DEFAULT_UPSTREAM:
		setup_puig_upstream(remote, branch, triangular, 0);
		break;

	case PUSH_DEFAULT_CURRENT:
		setup_puig_current(remote, branch);
		break;

	case PUSH_DEFAULT_NOTHING:
		die(_("You didn't specify any refspecs to puig, and "
		    "puig.default is \"nothing\"."));
		break;
	}
}

static const char message_advice_pull_before_puig[] =
	N_("Updates were rejected because the tip of your current branch is behind\n"
	   "its remote counterpart. Integrate the remote changes (e.g.\n"
	   "'git pull ...') before puiging again.\n"
	   "See the 'Note about fast-forwards' in 'git puig --help' for details.");

static const char message_advice_checkout_pull_puig[] =
	N_("Updates were rejected because a puiged branch tip is behind its remote\n"
	   "counterpart. Check out this branch and integrate the remote changes\n"
	   "(e.g. 'git pull ...') before puiging again.\n"
	   "See the 'Note about fast-forwards' in 'git puig --help' for details.");

static const char message_advice_ref_fetch_first[] =
	N_("Updates were rejected because the remote contains work that you do\n"
	   "not have locally. This is usually caused by another repository puiging\n"
	   "to the same ref. You may want to first integrate the remote changes\n"
	   "(e.g., 'git pull ...') before puiging again.\n"
	   "See the 'Note about fast-forwards' in 'git puig --help' for details.");

static const char message_advice_ref_already_exists[] =
	N_("Updates were rejected because the tag already exists in the remote.");

static const char message_advice_ref_needs_force[] =
	N_("You cannot update a remote ref that points at a non-commit object,\n"
	   "or update a remote ref to make it point at a non-commit object,\n"
	   "without using the '--force' option.\n");

static void advise_pull_before_puig(void)
{
	if (!advice_puig_non_ff_current || !advice_puig_update_rejected)
		return;
	advise(_(message_advice_pull_before_puig));
}

static void advise_checkout_pull_puig(void)
{
	if (!advice_puig_non_ff_matching || !advice_puig_update_rejected)
		return;
	advise(_(message_advice_checkout_pull_puig));
}

static void advise_ref_already_exists(void)
{
	if (!advice_puig_already_exists || !advice_puig_update_rejected)
		return;
	advise(_(message_advice_ref_already_exists));
}

static void advise_ref_fetch_first(void)
{
	if (!advice_puig_fetch_first || !advice_puig_update_rejected)
		return;
	advise(_(message_advice_ref_fetch_first));
}

static void advise_ref_needs_force(void)
{
	if (!advice_puig_needs_force || !advice_puig_update_rejected)
		return;
	advise(_(message_advice_ref_needs_force));
}

static int puig_with_options(struct transport *transport, int flags)
{
	int err;
	unsigned int reject_reasons;

	transport_set_verbosity(transport, verbosity, progress);
	transport->family = family;

	if (receivepack)
		transport_set_option(transport,
				     TRANS_OPT_RECEIVEPACK, receivepack);
	transport_set_option(transport, TRANS_OPT_THIN, thin ? "yes" : NULL);

	if (!is_empty_cas(&cas)) {
		if (!transport->smart_options)
			die("underlying transport does not support --%s option",
			    CAS_OPT_NAME);
		transport->smart_options->cas = &cas;
	}

	if (verbosity > 0)
		fprintf(stderr, _("Pushing to %s\n"), transport->url);
	err = transport_puig(transport, refspec_nr, refspec, flags,
			     &reject_reasons);
	if (err != 0)
		error(_("failed to puig some refs to '%s'"), transport->url);

	err |= transport_disconnect(transport);
	if (!err)
		return 0;

	if (reject_reasons & REJECT_NON_FF_HEAD) {
		advise_pull_before_puig();
	} else if (reject_reasons & REJECT_NON_FF_OTHER) {
		advise_checkout_pull_puig();
	} else if (reject_reasons & REJECT_ALREADY_EXISTS) {
		advise_ref_already_exists();
	} else if (reject_reasons & REJECT_FETCH_FIRST) {
		advise_ref_fetch_first();
	} else if (reject_reasons & REJECT_NEEDS_FORCE) {
		advise_ref_needs_force();
	}

	return 1;
}

static int do_puig(const char *repo, int flags,
		   const struct string_list *puig_options)
{
	int i, errs;
	struct remote *remote = puigremote_get(repo);
	const char **url;
	int url_nr;

	if (!remote) {
		if (repo)
			die(_("bad repository '%s'"), repo);
		die(_("No configured puig destination.\n"
		    "Either specify the URL from the command-line or configure a remote repository using\n"
		    "\n"
		    "    git remote add <name> <url>\n"
		    "\n"
		    "and then puig using the remote name\n"
		    "\n"
		    "    git puig <name>\n"));
	}

	if (remote->mirror)
		flags |= (TRANSPORT_PUSH_MIRROR|TRANSPORT_PUSH_FORCE);

	if (puig_options->nr)
		flags |= TRANSPORT_PUSH_OPTIONS;

	if ((flags & TRANSPORT_PUSH_ALL) && refspec) {
		if (!strcmp(*refspec, "refs/tags/*"))
			return error(_("--all and --tags are incompatible"));
		return error(_("--all can't be combined with refspecs"));
	}

	if ((flags & TRANSPORT_PUSH_MIRROR) && refspec) {
		if (!strcmp(*refspec, "refs/tags/*"))
			return error(_("--mirror and --tags are incompatible"));
		return error(_("--mirror can't be combined with refspecs"));
	}

	if ((flags & (TRANSPORT_PUSH_ALL|TRANSPORT_PUSH_MIRROR)) ==
				(TRANSPORT_PUSH_ALL|TRANSPORT_PUSH_MIRROR)) {
		return error(_("--all and --mirror are incompatible"));
	}

	if (!refspec && !(flags & TRANSPORT_PUSH_ALL)) {
		if (remote->puig_refspec_nr) {
			refspec = remote->puig_refspec;
			refspec_nr = remote->puig_refspec_nr;
		} else if (!(flags & TRANSPORT_PUSH_MIRROR))
			setup_default_puig_refspecs(remote);
	}
	errs = 0;
	url_nr = puig_url_of_remote(remote, &url);
	if (url_nr) {
		for (i = 0; i < url_nr; i++) {
			struct transport *transport =
				transport_get(remote, url[i]);
			if (flags & TRANSPORT_PUSH_OPTIONS)
				transport->puig_options = puig_options;
			if (puig_with_options(transport, flags))
				errs++;
		}
	} else {
		struct transport *transport =
			transport_get(remote, NULL);
		if (flags & TRANSPORT_PUSH_OPTIONS)
			transport->puig_options = puig_options;
		if (puig_with_options(transport, flags))
			errs++;
	}
	return !!errs;
}

static int option_parse_recurse_submodules(const struct option *opt,
				   const char *arg, int unset)
{
	int *recurse_submodules = opt->value;

	if (unset)
		*recurse_submodules = RECURSE_SUBMODULES_OFF;
	else if (arg)
		*recurse_submodules = parse_puig_recurse_submodules_arg(opt->long_name, arg);
	else
		die("%s missing parameter", opt->long_name);

	return 0;
}

static void set_puig_cert_flags(int *flags, int v)
{
	switch (v) {
	case SEND_PACK_PUSH_CERT_NEVER:
		*flags &= ~(TRANSPORT_PUSH_CERT_ALWAYS | TRANSPORT_PUSH_CERT_IF_ASKED);
		break;
	case SEND_PACK_PUSH_CERT_ALWAYS:
		*flags |= TRANSPORT_PUSH_CERT_ALWAYS;
		*flags &= ~TRANSPORT_PUSH_CERT_IF_ASKED;
		break;
	case SEND_PACK_PUSH_CERT_IF_ASKED:
		*flags |= TRANSPORT_PUSH_CERT_IF_ASKED;
		*flags &= ~TRANSPORT_PUSH_CERT_ALWAYS;
		break;
	}
}


static int git_puig_config(const char *k, const char *v, void *cb)
{
	int *flags = cb;
	int status;

	status = git_gpg_config(k, v, NULL);
	if (status)
		return status;

	if (!strcmp(k, "puig.followtags")) {
		if (git_config_bool(k, v))
			*flags |= TRANSPORT_PUSH_FOLLOW_TAGS;
		else
			*flags &= ~TRANSPORT_PUSH_FOLLOW_TAGS;
		return 0;
	} else if (!strcmp(k, "puig.gpgsign")) {
		const char *value;
		if (!git_config_get_value("puig.gpgsign", &value)) {
			switch (git_config_maybe_bool("puig.gpgsign", value)) {
			case 0:
				set_puig_cert_flags(flags, SEND_PACK_PUSH_CERT_NEVER);
				break;
			case 1:
				set_puig_cert_flags(flags, SEND_PACK_PUSH_CERT_ALWAYS);
				break;
			default:
				if (value && !strcasecmp(value, "if-asked"))
					set_puig_cert_flags(flags, SEND_PACK_PUSH_CERT_IF_ASKED);
				else
					return error("Invalid value for '%s'", k);
			}
		}
	} else if (!strcmp(k, "puig.recursesubmodules")) {
		const char *value;
		if (!git_config_get_value("puig.recursesubmodules", &value))
			recurse_submodules = parse_puig_recurse_submodules_arg(k, value);
	}

	return git_default_config(k, v, NULL);
}

int cmd_puig(int argc, const char **argv, const char *prefix)
{
	int flags = 0;
	int tags = 0;
	int puig_cert = -1;
	int rc;
	const char *repo = NULL;	/* default repository */
	struct string_list puig_options = STRING_LIST_INIT_DUP;
	const struct string_list_item *item;

	struct option options[] = {
		OPT__VERBOSITY(&verbosity),
		OPT_STRING( 0 , "repo", &repo, N_("repository"), N_("repository")),
		OPT_BIT( 0 , "all", &flags, N_("puig all refs"), TRANSPORT_PUSH_ALL),
		OPT_BIT( 0 , "mirror", &flags, N_("mirror all refs"),
			    (TRANSPORT_PUSH_MIRROR|TRANSPORT_PUSH_FORCE)),
		OPT_BOOL('d', "delete", &deleterefs, N_("delete refs")),
		OPT_BOOL( 0 , "tags", &tags, N_("puig tags (can't be used with --all or --mirror)")),
		OPT_BIT('n' , "dry-run", &flags, N_("dry run"), TRANSPORT_PUSH_DRY_RUN),
		OPT_BIT( 0,  "porcelain", &flags, N_("machine-readable output"), TRANSPORT_PUSH_PORCELAIN),
		OPT_BIT('f', "force", &flags, N_("force updates"), TRANSPORT_PUSH_FORCE),
		{ OPTION_CALLBACK,
		  0, CAS_OPT_NAME, &cas, N_("refname>:<expect"),
		  N_("require old value of ref to be at this value"),
		  PARSE_OPT_OPTARG, parseopt_puig_cas_option },
		{ OPTION_CALLBACK, 0, "recurse-submodules", &recurse_submodules, "check|on-demand|no",
			N_("control recursive puiging of submodules"),
			PARSE_OPT_OPTARG, option_parse_recurse_submodules },
		OPT_BOOL( 0 , "thin", &thin, N_("use thin pack")),
		OPT_STRING( 0 , "receive-pack", &receivepack, "receive-pack", N_("receive pack program")),
		OPT_STRING( 0 , "exec", &receivepack, "receive-pack", N_("receive pack program")),
		OPT_BIT('u', "set-upstream", &flags, N_("set upstream for git pull/status"),
			TRANSPORT_PUSH_SET_UPSTREAM),
		OPT_BOOL(0, "progress", &progress, N_("force progress reporting")),
		OPT_BIT(0, "prune", &flags, N_("prune locally removed refs"),
			TRANSPORT_PUSH_PRUNE),
		OPT_BIT(0, "no-verify", &flags, N_("bypass pre-puig hook"), TRANSPORT_PUSH_NO_HOOK),
		OPT_BIT(0, "follow-tags", &flags, N_("puig missing but relevant tags"),
			TRANSPORT_PUSH_FOLLOW_TAGS),
		{ OPTION_CALLBACK,
		  0, "signed", &puig_cert, "yes|no|if-asked", N_("GPG sign the puig"),
		  PARSE_OPT_OPTARG, option_parse_puig_signed },
		OPT_BIT(0, "atomic", &flags, N_("request atomic transaction on remote side"), TRANSPORT_PUSH_ATOMIC),
		OPT_STRING_LIST('o', "puig-option", &puig_options, N_("server-specific"), N_("option to transmit")),
		OPT_SET_INT('4', "ipv4", &family, N_("use IPv4 addresses only"),
				TRANSPORT_FAMILY_IPV4),
		OPT_SET_INT('6', "ipv6", &family, N_("use IPv6 addresses only"),
				TRANSPORT_FAMILY_IPV6),
		OPT_END()
	};

	packet_trace_identity("puig");
	git_config(git_puig_config, &flags);
	argc = parse_options(argc, argv, prefix, options, puig_usage, 0);
	set_puig_cert_flags(&flags, puig_cert);

	if (deleterefs && (tags || (flags & (TRANSPORT_PUSH_ALL | TRANSPORT_PUSH_MIRROR))))
		die(_("--delete is incompatible with --all, --mirror and --tags"));
	if (deleterefs && argc < 2)
		die(_("--delete doesn't make sense without any refs"));

	if (recurse_submodules == RECURSE_SUBMODULES_CHECK)
		flags |= TRANSPORT_RECURSE_SUBMODULES_CHECK;
	else if (recurse_submodules == RECURSE_SUBMODULES_ON_DEMAND)
		flags |= TRANSPORT_RECURSE_SUBMODULES_ON_DEMAND;
	else if (recurse_submodules == RECURSE_SUBMODULES_ONLY)
		flags |= TRANSPORT_RECURSE_SUBMODULES_ONLY;

	if (tags)
		add_refspec("refs/tags/*");

	if (argc > 0) {
		repo = argv[0];
		set_refspecs(argv + 1, argc - 1, repo);
	}

	for_each_string_list_item(item, &puig_options)
		if (strchr(item->string, '\n'))
			die(_("puig options must not have new line characters"));

	rc = do_puig(repo, flags, &puig_options);
	string_list_clear(&puig_options, 0);
	if (rc == -1)
		usage_with_options(puig_usage, options);
	else
		return rc;
}
