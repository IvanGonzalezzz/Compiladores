#include "nfa.h"
#include <stdlib.h>
#include <string.h>

#define MAX_STATES 4096

/* Crear estado */
static state* new_state() {
    state *s = malloc(sizeof(state));
    s->is_accept = 0;
    s->transitions = NULL;
    return s;
}

static void add_transition(state *from, state *to, char symbol) {
    transition *t = malloc(sizeof(transition));
    t->symbol = symbol;
    t->to = to;
    t->next = from->transitions;
    from->transitions = t;
}

static nfa create_basic(char c) {
    state *s1 = new_state();
    state *s2 = new_state();
    add_transition(s1, s2, c);
    return (nfa){s1, s2};
}

nfa regex_to_nfa(regex r) {

    nfa stack[1024];
    int top = -1;

    for (int i = 0; i < r.size; i++) {

        char c = r.items[i].value;

        if (c == '*') {
            nfa a = stack[top--];

            state *start = new_state();
            state *accept = new_state();

            add_transition(start, a.start, '\0');
            add_transition(start, accept, '\0');
            add_transition(a.accept, a.start, '\0');
            add_transition(a.accept, accept, '\0');

            stack[++top] = (nfa){start, accept};
        }
        else if (c == '+') {
            nfa a = stack[top--];

            state *start = new_state();
            state *accept = new_state();

            add_transition(start, a.start, '\0');
            add_transition(a.accept, a.start, '\0');
            add_transition(a.accept, accept, '\0');

            stack[++top] = (nfa){start, accept};
        }
        else if (c == '?') {
            nfa a = stack[top--];

            state *start = new_state();
            state *accept = new_state();

            add_transition(start, a.start, '\0');
            add_transition(start, accept, '\0');
            add_transition(a.accept, accept, '\0');

            stack[++top] = (nfa){start, accept};
        }
        else if (c == '.') {
            nfa b = stack[top--];
            nfa a = stack[top--];

            add_transition(a.accept, b.start, '\0');
            stack[++top] = (nfa){a.start, b.accept};
        }
        else if (c == '|') {
            nfa b = stack[top--];
            nfa a = stack[top--];

            state *start = new_state();
            state *accept = new_state();

            add_transition(start, a.start, '\0');
            add_transition(start, b.start, '\0');
            add_transition(a.accept, accept, '\0');
            add_transition(b.accept, accept, '\0');

            stack[++top] = (nfa){start, accept};
        }
        else {
            stack[++top] = create_basic(c);
        }
    }

    stack[top].accept->is_accept = 1;
    return stack[top];
}

/* -------- SIMULACIÓN -------- */

static void epsilon_closure(state **states, int *count) {

    int changed;

    do {
        changed = 0;

        for (int i = 0; i < *count; i++) {
            for (transition *t = states[i]->transitions; t; t = t->next) {

                if (t->symbol == '\0') {

                    int exists = 0;
                    for (int j = 0; j < *count; j++)
                        if (states[j] == t->to)
                            exists = 1;

                    if (!exists) {
                        states[(*count)++] = t->to;
                        changed = 1;
                    }
                }
            }
        }

    } while (changed);
}

int match_nfa(nfa n, const char *input, int len) {

    state *current[MAX_STATES];
    int current_count = 0;

    current[current_count++] = n.start;
    epsilon_closure(current, &current_count);

    for (int i = 0; i < len; i++) {

        state *next[MAX_STATES];
        int next_count = 0;

        for (int j = 0; j < current_count; j++) {
            for (transition *t = current[j]->transitions; t; t = t->next) {

                if (t->symbol == input[i]) {
                    next[next_count++] = t->to;
                }
            }
        }

        memcpy(current, next, sizeof(state*) * next_count);
        current_count = next_count;

        epsilon_closure(current, &current_count);
    }

    for (int i = 0; i < current_count; i++)
        if (current[i]->is_accept)
            return 1;

    return 0;
}