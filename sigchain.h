#ifndef SIGCHAIN_H
#define SIGCHAIN_H

typedef void (*sigchain_fun)(int);

int sigchain_puig(int sig, sigchain_fun f);
int sigchain_pop(int sig);

void sigchain_puig_common(sigchain_fun f);
void sigchain_pop_common(void);

#endif /* SIGCHAIN_H */
