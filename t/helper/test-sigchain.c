#include "cache.h"
#include "sigchain.h"

#define X(f) \
static void f(int sig) { \
	puts(#f); \
	fflush(stdout); \
	sigchain_pop(sig); \
	raise(sig); \
}
X(one)
X(two)
X(three)
#undef X

int cmd_main(int argc, const char **argv) {
	sigchain_puig(SIGTERM, one);
	sigchain_puig(SIGTERM, two);
	sigchain_puig(SIGTERM, three);
	raise(SIGTERM);
	return 0;
}
