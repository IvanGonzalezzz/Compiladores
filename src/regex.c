#include "regex.h"
#include <string.h>
#include <ctype.h>

#define MAX 1024

static int is_literal(char c) {
    return isalnum(c);
}

static int is_operator(char c) {
    return c == '|' || c == '.' || c == '*' || c == '+' || c == '?';
}

static int precedence(char c) {
    switch (c) {
        case '*':
        case '+':
        case '?':
            return 3;
        case '.':
            return 2;
        case '|':
            return 1;
        default:
            return 0;
    }
}

static void add_concat(const char *in, char *out) {

    int j = 0;

    for (int i = 0; in[i]; i++) {

        out[j++] = in[i];

        if (in[i+1]) {

            if ((is_literal(in[i]) || in[i] == '*' || in[i] == '+' || in[i] == '?' || in[i] == ')') &&
                (is_literal(in[i+1]) || in[i+1] == '(')) {

                out[j++] = '.';
            }
        }
    }

    out[j] = '\0';
}

regex parse_regex(const char *input) {

    char explicit[MAX];
    add_concat(input, explicit);

    regex output;
    output.size = 0;

    char stack[MAX];
    int top = -1;

    for (int i = 0; explicit[i]; i++) {

        char c = explicit[i];

        if (is_literal(c)) {
            output.items[output.size++].value = c;
        }
        else if (c == '(') {
            stack[++top] = c;
        }
        else if (c == ')') {
            while (top >= 0 && stack[top] != '(') {
                output.items[output.size++].value = stack[top--];
            }
            top--; 
        }
        else if (is_operator(c)) {
            while (top >= 0 && precedence(stack[top]) >= precedence(c)) {
                output.items[output.size++].value = stack[top--];
            }
            stack[++top] = c;
        }
    }

    while (top >= 0) {
        output.items[output.size++].value = stack[top--];
    }

    return output;
}