%{
#include "ast.h"
#include "parser.tab.h"
#include <string.h>

extern int yylineno;
void yyerror(const char *s);

int yycolumn = 1;

#define YY_USER_ACTION \
    yylloc.first_line = yylloc.last_line = yylineno; \
    yylloc.first_column = yycolumn; \
    yylloc.last_column = yycolumn + yyleng - 1;

// Identificadores estándar
%}

%option noyywrap
%option yylineno

%%

"DO"      { yycolumn += yyleng; return DO_INT; }
"RE"      { yycolumn += yyleng; return RE_FLOAT; }
"MI"      { yycolumn += yyleng; return MI_STRING; }
"FA"      { yycolumn += yyleng; return FA_BOOLEAN; }
"VERDADERO" { yycolumn += yyleng; return TRUE; }
"FALSO"   { yycolumn += yyleng; return FALSE; }
"SI"      { yycolumn += yyleng; return RETURN; }

"LA"   { yycolumn += yyleng; return IF; }
"LA#"  { yycolumn += yyleng; return ELSIF; }
"SIb"  { yycolumn += yyleng; return ELSE; }
"FA#"  { yycolumn += yyleng; return WHILE; }
"RE#"  { yycolumn += yyleng; return FOR; }
"LA!"  { yycolumn += yyleng; return PRINT; }
"RE!"  { yycolumn += yyleng; return READ; }

"|"   { yycolumn += yyleng; return BLOCK_START; }
"||"  { yycolumn += yyleng; return BLOCK_END; }

"DO#"   { yycolumn += yyleng; return PLUS; }
"REb"     { yycolumn += yyleng; return MINUS; }
"MI+"     { yycolumn += yyleng; return MULT; }
"FA/"     { yycolumn += yyleng; return DIV; }
"SOL%"    { yycolumn += yyleng; return MOD; }
"Y"       { yycolumn += yyleng; return AND; }
"O"       { yycolumn += yyleng; return OR; }
"NO"      { yycolumn += yyleng; return NOT; }

"=="      { yycolumn += yyleng; return EQ; }
"!="      { yycolumn += yyleng; return NEQ; }
"SOL#"    { yycolumn += yyleng; return GT; }
"SOLb"    { yycolumn += yyleng; return LT; }

"="       { yycolumn += yyleng; return ASSIGN; }
"|||"     { yycolumn += yyleng; return SEMI; }
","       { yycolumn += yyleng; return COMMA; }
"("       { yycolumn += yyleng; return LPAREN; }
")"       { yycolumn += yyleng; return RPAREN; }

[0-9]+\.[0-9]+      { yylval.sval = strdup(yytext); yycolumn += yyleng; return FLOAT_LIT; }
[0-9]+              { yylval.sval = strdup(yytext); yycolumn += yyleng; return INT_LIT; }
\"[^\"]*\"          { yylval.sval = strdup(yytext); yycolumn += yyleng; return STRING_LIT; }

0x[0-9A-Fa-f]+         { yylval.sval = strdup(yytext); yycolumn += yyleng; return INT_LIT; }
[a-zA-Z_][a-zA-Z0-9_]* { yylval.sval = strdup(yytext); yycolumn += yyleng; return ID; }

"//".*              { yycolumn += yyleng; }
[ \t\r]+        { yycolumn += yyleng; }
\n              { yylineno++; yycolumn = 1; }
.                   { printf("Error léxico musical: '%s' en línea %d, columna %d\n", yytext, yylineno, yycolumn); yycolumn += yyleng; }
%%