%{
#include "ast.h"
#include "parser.tab.h"
#include <iostream>
#include <string>
#include <map>
#include <vector>

extern int yylex();
extern int yylineno;
extern YYLTYPE yylloc;

void yyerror(const char *s);

Node* root;

std::vector<std::map<std::string, std::string>> scopes;
std::string current_function_type = "";

void push_scope() { scopes.push_back({}); }
void pop_scope() { scopes.pop_back(); }

void declare_var(const std::string& id, const std::string& type) {
    if (scopes.back().count(id))
        std::cerr << "warning: variable redeclarada: " << id << std::endl;

    scopes.back()[id] = type;
}

std::string lookup_var(const std::string& id) {
    for (int i = scopes.size()-1; i >= 0; --i) {
        if (scopes[i].count(id))
            return scopes[i][id];
    }
    return "";
}

void error_semantico(std::string msg, int line) {
    std::cerr << "semantic error: " << msg
              << " at line " << line << std::endl;
    exit(1);
}
%}

%define parse.error detailed
%locations

%union {
    char* sval;
    Node* nptr;
}

%token <sval> ID INT_LIT FLOAT_LIT STRING_LIT
%token DO_INT RE_FLOAT MI_STRING FA_BOOLEAN RETURN
%token IF ELSIF ELSE WHILE FOR
%token BLOCK_START BLOCK_END
%token PLUS MINUS MULT DIV MOD EQ NEQ GT LT
%token ASSIGN SEMI COMMA LPAREN RPAREN
%token PRINT READ
%token TRUE FALSE
%token AND OR NOT

%type <nptr> program mixed_list mixed_item function_definition
%type <nptr> parameter_list parameter type declaration statement_list
%type <nptr> statement expression if_statement block
%type <nptr> elsif_list for_loop assignment

%left OR
%left AND
%precedence NOT
%left EQ NEQ GT LT
%left PLUS MINUS
%left MULT DIV MOD

%%

program:
    { push_scope(); }
    mixed_list { root = $2; pop_scope(); }
;

mixed_list:
    mixed_item { $$ = new Node("Program"); $$->add_child($1); }
    | mixed_list mixed_item { $1->add_child($2); $$ = $1; }
;

mixed_item:
    function_definition
    | statement
;

function_definition:
    type ID LPAREN parameter_list RPAREN block {
        $$ = new Node("Function", $2);
        $$->value = $1->value;
        current_function_type = $1->value;

        if ($4) $$->add_child($4);
        $$->add_child($6);

        current_function_type = "";
    }
;

parameter_list:
    %empty { $$ = nullptr; }
    | parameter {
        $$ = new Node("Parameters");
        $$->add_child($1);
    }
    | parameter_list COMMA parameter {
        $1->add_child($3);
        $$ = $1;
    }
;

parameter:
    type ID {
        declare_var($2, $1->value);
        $$ = new Node("Parameter", $2);
        $$->add_child($1);
    }
;

type:
    DO_INT      { $$ = new Node("Type","int"); $$->value="int"; }
  | RE_FLOAT    { $$ = new Node("Type","float"); $$->value="float"; }
  | MI_STRING   { $$ = new Node("Type","string"); $$->value="string"; }
  | FA_BOOLEAN  { $$ = new Node("Type","bool"); $$->value="bool"; }
;

statement_list:
    statement { $$ = new Node("Statements"); $$->add_child($1); }
    | statement_list statement { $1->add_child($2); $$ = $1; }
;

statement:
    declaration SEMI
    | assignment SEMI
    | expression SEMI

    | PRINT LPAREN expression RPAREN SEMI {
        $$ = new Node("Print");
        $$->add_child($3);
    }

    | READ LPAREN ID RPAREN SEMI {
        if (lookup_var($3) == "")
            error_semantico("variable no declarada", @3.first_line);
        $$ = new Node("Read", $3);
    }

    | if_statement

    | WHILE LPAREN expression RPAREN block {
        if ($3->value != "bool")
            error_semantico("WHILE requiere condición booleana", @3.first_line);

        $$ = new Node("While");
        $$->add_child($3);
        $$->add_child($5);
    }

    | for_loop

    | RETURN expression SEMI {
        if (current_function_type != "" && current_function_type != $2->value)
            error_semantico("tipo de retorno incorrecto", @2.first_line);

        $$ = new Node("Return");
        $$->add_child($2);
    }
;

declaration:
    type ID ASSIGN expression {
        if ($1->value != $4->value)
            error_semantico("asignación incompatible", @2.first_line);

        declare_var($2, $1->value);

        $$ = new Node("Declaration", $2);
        $$->value = $1->value;
        $$->add_child($4);
    }
    | type ID {
        declare_var($2, $1->value);
        $$ = new Node("Declaration", $2);
        $$->value = $1->value;
    }
;

assignment:
    ID ASSIGN expression {
        std::string t = lookup_var($1);
        if (t == "")
            error_semantico("variable no declarada", @1.first_line);

        if (t != $3->value)
            error_semantico("tipos incompatibles", @3.first_line);

        $$ = new Node("Assignment", $1);
        $$->add_child($3);
    }
;

if_statement:
    IF LPAREN expression RPAREN block elsif_list {
        if ($3->value != "bool")
            error_semantico("IF requiere condición booleana", @3.first_line);

        $$ = new Node("If");
        $$->add_child($3);
        $$->add_child($5);
        if ($6) $$->add_child($6);
    }
    | IF LPAREN expression RPAREN block elsif_list ELSE block {
        if ($3->value != "bool")
            error_semantico("IF requiere condición booleana", @3.first_line);

        $$ = new Node("If");
        $$->add_child($3);
        $$->add_child($5);

        Node* e = new Node("Else");
        e->add_child($8);
        $$->add_child(e);
    }
;

elsif_list:
    %empty { $$ = nullptr; }
    | elsif_list ELSIF LPAREN expression RPAREN block {
        if ($4->value != "bool")
            error_semantico("ELSIF requiere condición booleana", @4.first_line);

        Node* n = new Node("ElseIf");
        n->add_child($4);
        n->add_child($6);

        if ($1) { $1->add_child(n); $$ = $1; }
        else {
            $$ = new Node("ElseIfList");
            $$->add_child(n);
        }
    }
;

for_loop:
    FOR LPAREN assignment SEMI expression SEMI assignment RPAREN block {
        if ($5->value != "bool")
            error_semantico("FOR requiere condición booleana", @5.first_line);

        $$ = new Node("For");

        Node* h = new Node("Header");
        h->add_child($3);
        h->add_child($5);
        h->add_child($7);

        $$->add_child(h);
        $$->add_child($9);
    }
;

block:
    BLOCK_START { push_scope(); }
    statement_list BLOCK_END {
        $$ = $3;
        pop_scope();
    }
    | BLOCK_START BLOCK_END {
        $$ = new Node("EmptyBlock");
    }
;

expression:
    INT_LIT { $$ = new Node("Int",$1); $$->value="int"; }
  | FLOAT_LIT { $$ = new Node("Float",$1); $$->value="float"; }
  | STRING_LIT { $$ = new Node("String",$1); $$->value="string"; }
  | TRUE { $$ = new Node("Bool","true"); $$->value="bool"; }
  | FALSE { $$ = new Node("Bool","false"); $$->value="bool"; }

  | ID {
        std::string t = lookup_var($1);
        if (t == "")
            error_semantico("variable no declarada", @1.first_line);
        $$ = new Node("Id",$1);
        $$->value = t;
    }

  | expression PLUS expression {
        if ($1->value != $3->value)
            error_semantico("tipos incompatibles en suma", @2.first_line);
        $$ = new Node("Add"); $$->add_child($1); $$->add_child($3);
        $$->value=$1->value;
    }

  | expression MINUS expression {
        if ($1->value != $3->value)
            error_semantico("tipos incompatibles en resta", @2.first_line);
        $$ = new Node("Sub"); $$->add_child($1); $$->add_child($3);
        $$->value=$1->value;
    }

  | expression MULT expression {
        if ($1->value != $3->value)
            error_semantico("tipos incompatibles en multiplicación", @2.first_line);
        $$ = new Node("Mul"); $$->add_child($1); $$->add_child($3);
        $$->value=$1->value;
    }

  | expression DIV expression {
        if ($1->value != $3->value)
            error_semantico("tipos incompatibles en división", @2.first_line);
        $$ = new Node("Div"); $$->add_child($1); $$->add_child($3);
        $$->value=$1->value;
    }

  | expression MOD expression {
        if ($1->value != "int" || $3->value != "int")
            error_semantico("MOD solo acepta enteros", @2.first_line);
        $$ = new Node("Mod"); $$->add_child($1); $$->add_child($3);
        $$->value="int";
    }

  /* RELACIONALES */
  | expression EQ expression {
        if ($1->value != $3->value)
            error_semantico("comparación incompatible", @2.first_line);
        $$ = new Node("Eq"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  | expression NEQ expression {
        if ($1->value != $3->value)
            error_semantico("comparación incompatible", @2.first_line);
        $$ = new Node("Neq"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  | expression GT expression {
        if ($1->value != $3->value)
            error_semantico("comparación incompatible", @2.first_line);
        $$ = new Node("Gt"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  | expression LT expression {
        if ($1->value != $3->value)
            error_semantico("comparación incompatible", @2.first_line);
        $$ = new Node("Lt"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  /* LÓGICOS */
  | expression AND expression {
        if ($1->value != "bool" || $3->value != "bool")
            error_semantico("AND requiere booleanos", @2.first_line);
        $$ = new Node("And"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  | expression OR expression {
        if ($1->value != "bool" || $3->value != "bool")
            error_semantico("OR requiere booleanos", @2.first_line);
        $$ = new Node("Or"); $$->add_child($1); $$->add_child($3);
        $$->value="bool";
    }

  | NOT expression {
        if ($2->value != "bool")
            error_semantico("NOT requiere booleano", @1.first_line);
        $$ = new Node("Not"); $$->add_child($2);
        $$->value="bool";
    }

  | LPAREN expression RPAREN { $$ = $2; }
;

%%

void yyerror(const char *s) {
    std::cerr << "syntax error: " << s
              << " at line " << yylloc.first_line
              << ", column " << yylloc.first_column
              << std::endl;
}

int main() {
    std::cout << "--- Parser Musical ---" << std::endl;

    if (yyparse() == 0) {
        std::cout << "\n--- AST generado ---" << std::endl;
        if (root) {
            root->print();
            root->gen_dot("ast.dot");
        }
    }
    return 0;
}