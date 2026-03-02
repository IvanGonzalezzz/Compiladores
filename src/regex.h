#ifndef REGEX_H
#define REGEX_H

typedef struct {
    char value;
} token;

typedef struct {
    token items[1024];
    int size;
} regex;

regex parse_regex(const char *input);

#endif