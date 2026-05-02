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

struct Symbol {
    std::string name;
    std::string type;
    std::string category;
    int scope_level;
    bool used = false;
    std::vector<std::string> param_types;
};

std::vector<std::map<std::string, Symbol>> scopes;
std::string current_function_type = "";
std::vector<std::string> errores;
std::vector<Symbol> all_symbols;
std::string promote(std::string a, std::string b);

void push_scope() { scopes.push_back({}); }
void pop_scope() { scopes.pop_back(); }
void error_semantico(std::string msg, int line);


bool is_numeric(const std::string& t);
bool has_return(Node* n);

void declare_var(const std::string& id, const std::string& type, const std::string& category="variable") {
    if (scopes.back().count(id)){
        error_semantico("variable redeclarada: " + id, yylineno);
        return;
    }

    Symbol s;
    s.name = id;
    s.type = type;
    s.category = category;
    s.scope_level = scopes.size() - 1;

    scopes.back()[id] = s;
    all_symbols.push_back(s);
}

Symbol* lookup_symbol(const std::string& id) {
    for (int i = scopes.size()-1; i >= 0; --i) {
        if (scopes[i].count(id)) {
            scopes[i][id].used = true;
            for (auto &s : all_symbols) {
                if (s.name == id &&
                    s.scope_level == scopes[i][id].scope_level) {
                    s.used = true;
                    break;
                }
            }

            return &scopes[i][id];
        }
    }
    return nullptr;
}

void error_semantico(std::string msg, int line) {
    errores.push_back(
        "semantic error: " + msg + " at line " + std::to_string(line)
    );
}


std::vector<std::string> current_param_types;
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
%type <nptr> arg_list

%left OR
%left AND
%precedence NOT
%left EQ NEQ GT LT
%left PLUS MINUS
%left MULT DIV MOD

%start program

%%

arg_list:
    %empty { $$ = new Node("Args"); }
    | expression {
        $$ = new Node("Args");
        $$->add_child($1);
    }
    | arg_list COMMA expression {
        $1->add_child($3);
        $$ = $1;
    }
;

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
    type ID LPAREN 
    {
        Symbol f;
        f.name = $2;
        f.type = $1->value;
        f.category = "function";
        f.scope_level = scopes.size() - 1;

        if (scopes.back().count($2)) {
            error_semantico("función redeclarada: " + std::string($2), @2.first_line);
        } else {
            scopes.back()[$2] = f;
            all_symbols.push_back(f);
        }
        current_param_types.clear();

        push_scope();
        current_function_type = $1->value;
    }
    parameter_list RPAREN block {

        for (auto &s : all_symbols) {
            if (s.name == $2 && s.category == "function") {
                s.param_types = current_param_types;
                break;
            }
        }

        $$ = new Node("Function", $2);
        $$->value = $1->value;

        if ($5) $$->add_child($5);
        $$->add_child($7);

        current_function_type = "";
        pop_scope();
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
        current_param_types.push_back($1->value);
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
        Symbol* sym = lookup_symbol($3);
        if (!sym) {
            error_semantico("variable no declarada", @1.first_line);
        }
        std::string t = sym ? sym->type : "error";
        $$ = new Node("Read", $3);
    }

    | if_statement

    | WHILE LPAREN expression RPAREN block {
    $$ = new Node("While");

    if ($3->value == "error" || $5->value == "error") {
        $$->value = "error";
    }
    else if ($3->value != "bool") {
        error_semantico("WHILE requiere condición booleana", @3.first_line);
        $$->value = "error";
    }

    $$->add_child($3);
    $$->add_child($5);
}

    | for_loop

    | RETURN expression SEMI {
        if (current_function_type == "")
        error_semantico("return fuera de función", @1.first_line);

        else if ($2->value != "error" &&
                current_function_type != $2->value)
            error_semantico("tipo de retorno incorrecto", @2.first_line);

        $$ = new Node("Return");
        $$->add_child($2);
    }
;

declaration:
    type ID ASSIGN expression {
        if ($1->value == "int" && $4->value == "float") {
            error_semantico("pérdida de precisión (float -> int)", @2.first_line);
        }
        else if ($1->value != $4->value &&
                !($1->value == "float" && $4->value == "int")) {
            error_semantico("asignación incompatible", @2.first_line);
        }
        declare_var($2, $1->value);

        $$ = new Node("Declaration", $2);
        $$->value = $1->value;

        Node* expr = $4;
        if ($1->value == "float" && $4->value == "int") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($4);
            expr = cast;
        }

        $$->add_child(expr);
    }
    | type ID {
        declare_var($2, $1->value);
        $$ = new Node("Declaration", $2);
        $$->value = $1->value;
    }
;

assignment:
    ID ASSIGN expression {
           Symbol* sym = lookup_symbol($1);
        std::string t = sym ? sym->type : "error";

        Node* expr = $3;
        $$ = new Node("Assignment", $1);

        if (!sym) {
            error_semantico("variable no declarada", @1.first_line);
            $$->value = "error";
        }
        else if ($3->value == "error") {
            $$->value = "error";
        }
        else {
            if (t == "float" && $3->value == "int") {
                Node* cast = new Node("IntToFloat");
                cast->add_child($3);
                expr = cast;
            }
            else if (t != $3->value) {
                error_semantico("tipos incompatibles", @3.first_line);
                $$->value = "error";
            }
        }

        $$->add_child(expr);
    }
;

if_statement:
    IF LPAREN expression RPAREN block elsif_list {
        $$ = new Node("If");

        if ($3->value == "error" || $5->value == "error") {
            $$->value = "error";
        }
        else if ($3->value != "bool") {
            error_semantico("IF requiere condición booleana", @3.first_line);
            $$->value = "error";
        }

        $$->add_child($3);
        $$->add_child($5);

        if ($6) $$->add_child($6);
    }

    | IF LPAREN expression RPAREN block elsif_list ELSE block {
        $$ = new Node("If");

        if ($3->value == "error" || $5->value == "error" || $8->value == "error") {
            $$->value = "error";
        }
        else if ($3->value != "bool") {
            error_semantico("IF requiere condición booleana", @3.first_line);
            $$->value = "error";
        }

        $$->add_child($3);
        $$->add_child($5);

        Node* e = new Node("Else");
        e->add_child($8);
        $$->add_child(e);
    }
;
;

elsif_list:
    %empty { $$ = nullptr; }
    | elsif_list ELSIF LPAREN expression RPAREN block {
    Node* n = new Node("ElseIf");

    if ($4->value == "error" || $6->value == "error") {
        n->value = "error";
    }
    else if ($4->value != "bool") {
        error_semantico("ELSIF requiere condición booleana", @4.first_line);
        n->value = "error";
    }

    n->add_child($4);
    n->add_child($6);

    if ($1) { 
        $1->add_child(n); 
        $$ = $1; 
    }
    else {
        $$ = new Node("ElseIfList");
        $$->add_child(n);
    }
}
;

for_loop:
    FOR LPAREN assignment SEMI expression SEMI assignment RPAREN block {
        $$ = new Node("For");

        if ($5->value == "error" || $3->value == "error" || $7->value == "error" || $9->value == "error") {
            $$->value = "error";
        }
        else if ($5->value != "bool") {
            error_semantico("FOR requiere condición booleana", @5.first_line);
            $$->value = "error";
        }

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
    |  BLOCK_START {
        push_scope();
    }
    BLOCK_END {
        $$ = new Node("EmptyBlock");
        pop_scope();
    }
;

expression:
    INT_LIT { $$ = new Node("Int",$1); $$->value="int"; }
  | FLOAT_LIT { $$ = new Node("Float",$1); $$->value="float"; }
  | STRING_LIT { $$ = new Node("String",$1); $$->value="string"; }
  | TRUE { $$ = new Node("Bool","true"); $$->value="bool"; }
  | FALSE { $$ = new Node("Bool","false"); $$->value="bool"; }

  |  ID {
    Symbol* sym = lookup_symbol($1);

    if (sym && sym->category == "function") {
        error_semantico("función usada como variable", @1.first_line);
        $$ = new Node("Id",$1);
        $$->value = "error";
    }
    else{
    if (!sym) {
        error_semantico("variable no declarada", @1.first_line);
    }

    std::string t = sym ? sym->type : "error";

    $$ = new Node("Id",$1);
    $$->value = t;
    }
    }

  | expression PLUS expression {
    if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Add");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
    error_semantico("operación aritmética inválida", @2.first_line);
    $$ = new Node("Add");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    } else {
        Node* left = $1;
        Node* right = $3;

        std::string t = promote($1->value, $3->value);

        if ($1->value == "int" && $3->value == "float") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($1);
            left = cast;
        }
        else if ($1->value == "float" && $3->value == "int") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($3);
            right = cast;
        }

        $$ = new Node("Add");
        $$->add_child(left);
        $$->add_child(right);
        $$->value = t;
    }
    }

  | expression MINUS expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Sub");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
        error_semantico("operación aritmética inválida", @2.first_line);
        $$ = new Node("Sub");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else {
        Node* left = $1;
        Node* right = $3;

        std::string t = promote($1->value, $3->value);

        if ($1->value == "int" && $3->value == "float") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($1);
            left = cast;
        }
        else if ($1->value == "float" && $3->value == "int") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($3);
            right = cast;
        }

        $$ = new Node("Sub");
        $$->add_child(left);
        $$->add_child(right);
        $$->value = t;
    }
    }

  | expression MULT expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Mul");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
        error_semantico("operación aritmética inválida", @2.first_line);
        $$ = new Node("Mul");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else {
        Node* left = $1;
        Node* right = $3;

        std::string t = promote($1->value, $3->value);

        if ($1->value == "int" && $3->value == "float") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($1);
            left = cast;
        }
        else if ($1->value == "float" && $3->value == "int") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($3);
            right = cast;
        }

        $$ = new Node("Mul");
        $$->add_child(left);
        $$->add_child(right);
        $$->value = t;
    }
    }

  | expression DIV expression {
       if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Div");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
        error_semantico("operación aritmética inválida", @2.first_line);
        $$ = new Node("Div");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else {
        Node* left = $1;
        Node* right = $3;

        std::string t = promote($1->value, $3->value);

        if ($1->value == "int" && $3->value == "float") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($1);
            left = cast;
        }
        else if ($1->value == "float" && $3->value == "int") {
            Node* cast = new Node("IntToFloat");
            cast->add_child($3);
            right = cast;
        }

        $$ = new Node("Div");
        $$->add_child(left);
        $$->add_child(right);
        $$->value = t;
    }
    }

  | expression MOD expression {
         if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Mod");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if ($1->value != "int" || $3->value != "int") {
        error_semantico("MOD solo acepta enteros", @2.first_line);
        $$ = new Node("Mod");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else {
        $$ = new Node("Mod");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "int";
    }
    }

  /* RELACIONALES */
  | expression EQ expression {
        if ($1->value == "error" || $3->value == "error") {
       $$ = new Node("Eq");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else if ($1->value != $3->value) {
        error_semantico("tipos incompatibles en comparación", @2.first_line);
        $$ = new Node("Eq");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "error";
    }
    else {
        $$ = new Node("Eq");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
    }

  | expression NEQ expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Neq");
        $$->value = "error";
    }
    else if ($1->value != $3->value) {
        error_semantico("tipos incompatibles en comparación", @2.first_line);
        $$ = new Node("Neq");
        $$->value = "error";
    }
    else {
        $$ = new Node("Neq");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
    }

  | expression GT expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Gt");
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
        error_semantico("comparación inválida", @2.first_line);
        $$ = new Node("Gt");
        $$->value = "error";
    }
    else {
        $$ = new Node("Gt");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
}

  | expression LT expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Lt");
        $$->value = "error";
    }
    else if (!is_numeric($1->value) || !is_numeric($3->value)) {
        error_semantico("comparación inválida", @2.first_line);
        $$ = new Node("Lt");
        $$->value = "error";
    }
    else {
        $$ = new Node("Lt");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
    }

  /* LÓGICOS */
  | expression AND expression {
       if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("And");
        $$->value = "error";
    }
    else if ($1->value != "bool" || $3->value != "bool") {
        error_semantico("AND requiere booleanos", @2.first_line);
        $$ = new Node("And");
        $$->value = "error";
    }
    else {
        $$ = new Node("And");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
    }

  | expression OR expression {
        if ($1->value == "error" || $3->value == "error") {
        $$ = new Node("Or");
        $$->value = "error";
    }
    else if ($1->value != "bool" || $3->value != "bool") {
        error_semantico("OR requiere booleanos", @2.first_line);
        $$ = new Node("Or");
        $$->value = "error";
    }
    else {
        $$ = new Node("Or");
        $$->add_child($1);
        $$->add_child($3);
        $$->value = "bool";
    }
    }

  | NOT expression {
        if ($2->value == "error") {
        $$ = new Node("Not");
        $$->value = "error";
    }
    else if ($2->value != "bool") {
        error_semantico("NOT requiere booleano", @1.first_line);
        $$ = new Node("Not");
        $$->value = "error";
    }
    else {
        $$ = new Node("Not");
        $$->add_child($2);
        $$->value = "bool";
    }
    }

  | LPAREN expression RPAREN { $$ = $2; }

  | ID LPAREN arg_list RPAREN {
    Symbol* sym = lookup_symbol($1);

    if (!sym) {
        error_semantico("función no declarada: " + std::string($1), @1.first_line);
        $$ = new Node("Call", $1);
        $$->value = "error";
    }
    else if (sym->category != "function") {
        error_semantico("identificador no es función: " + std::string($1), @1.first_line);
        $$ = new Node("Call", $1);
        $$->value = "error";
    }
    else {
        bool has_error = false;

        if ($3->children.size() != sym->param_types.size()) {
            error_semantico("número incorrecto de argumentos", @1.first_line);
            has_error = true;
        } else {
            for (size_t i = 0; i < $3->children.size(); ++i) {
                std::string arg_t = $3->children[i]->value;
                std::string param_t = sym->param_types[i];

                if (arg_t == "error") {
                    has_error = true;
                    continue;
                }

                if (arg_t != param_t &&
                    !(param_t == "float" && arg_t == "int")) {
                    error_semantico("tipo de argumento incorrecto", @1.first_line);
                    has_error = true;
                }
            }
        }

        $$ = new Node("Call", $1);
        $$->add_child($3);

        if (has_error)
            $$->value = "error";
        else
            $$->value = sym->type;
    }
    }
;

%%

std::string promote(std::string a, std::string b) {
    if (a == "error" || b == "error") return "error";

    if (a == b) return a;

    if ((a == "int" && b == "float") ||
        (a == "float" && b == "int"))
        return "float";

    return "error";
}

bool is_numeric(const std::string& t) {
    return t == "int" || t == "float";
}

void yyerror(const char *s) {
    std::cerr << "syntax error: " << s
              << " at line " << yylloc.first_line
              << ", column " << yylloc.first_column
              << std::endl;
}

bool has_invalid_return(Node* n) {
    if (!n) return false;

    if (n->type == "Return" && !n->children.empty())
        return true;

    for (auto c : n->children)
        if (has_invalid_return(c))
            return true;

    return false;
}

void check_returns(Node* n, std::string expected) {
    if (!n) return;

    if (n->type == "Function") {

        std::string func_type = n->value;

        if (func_type != "void") {
            if (!has_return(n)) {
                error_semantico("función sin return", 0);
            }
        }

        if (func_type == "void") {
            if (has_invalid_return(n)) {
                error_semantico("función void no debe retornar valor", 0);
            }
        }

        for (auto c : n->children)
            check_returns(c, func_type);

        return;
    }

    if (n->type == "Return") {
        if (expected == "") {
            error_semantico("return fuera de función", 0);
        }
        else {
            if (!n->children.empty()) {
                std::string return_type = n->children[0]->value;

                if (return_type != "error" &&
                    return_type != expected &&
                    !(expected == "float" && return_type == "int")) {

                    error_semantico("tipo de retorno incorrecto", 0);
                }
            }
        }
    }

    for (auto c : n->children)
        check_returns(c, expected);
}

void semantic_check(Node* n) {
    if (!n) return;

    for (auto child : n->children) {
        semantic_check(child);

        if (child->value == "error") {
            n->value = "error";
        }
    }
}

bool has_return(Node* n) {
    if (!n) return false;

    if (n->type == "Return")
        return true;

    if (n->type == "Statements") {
        for (auto c : n->children) {
            if (has_return(c))
                return true;
        }
        return false;
    }
    if (n->type == "If") {
        if (n->children.size() < 2)
            return false;

        Node* then_block = n->children[1];

        bool then_has = has_return(then_block);
        bool else_has = false;

        for (auto c : n->children) {
            if (c->type == "Else") {
                else_has = has_return(c->children[0]);
            }
        }
        return then_has && else_has;
    }

    if (n->type == "ElseIfList") {
        for (auto c : n->children) {
            if (!has_return(c))
                return false;
        }
        return true;
    }

    for (auto c : n->children) {
        if (has_return(c))
            return true;
    }

    return false;
}
int main() {
    std::cout << "--- Parser Musical ---" << std::endl;

    if (yyparse() == 0) {
        semantic_check(root);
        check_returns(root, "");

        if (!errores.empty()) {
            std::cout << "\n--- Errores semánticos ---\n";
            for (auto& e : errores)
                std::cout << e << std::endl;
        } else {
            std::cout << "\nPrograma semánticamente válido\n";

            if (root) {
                std::cout << "\n--- AST generado ---\n";
                root->print();
                root->gen_dot("ast.dot");
            }
        }
    }

    for (auto& s : all_symbols) {
        if (!s.used && s.category == "variable") {
            std::cout << "warning: variable '" << s.name 
                      << "' declarada pero no usada\n";
        }
    }

    return 0;
}