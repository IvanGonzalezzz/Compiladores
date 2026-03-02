#ifndef NFA_H
#define NFA_H

#include "regex.h"

typedef struct state state;

typedef struct transition {
    char symbol; 
    state *to;
    struct transition *next;
} transition;

struct state {
    int is_accept;
    transition *transitions;
};

typedef struct {
    state *start;
    state *accept;
} nfa;

nfa regex_to_nfa(regex r);
int match_nfa(nfa n, const char *input, int len);

#endif