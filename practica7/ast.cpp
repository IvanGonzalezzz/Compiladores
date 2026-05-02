#include "ast.h"

Node::Node(std::string type, std::string value) {
    this->type = type;
    this->value = value;
}

void Node::add_child(Node* child) {
    if (child)
        children.push_back(child);
}

void Node::print(int indent) {
    for (int i = 0; i < indent; i++) std::cout << "  ";

    std::cout << type;
    if (value != "") std::cout << " (" << value << ")";
    std::cout << std::endl;

    for (auto child : children) {
        if (child) child->print(indent + 1);
    }
}

void Node::gen_dot(const std::string& filename) {
    std::ofstream out(filename);
    out << "digraph AST {\n";

    int id = 0;
    gen_dot_rec(out, id);

    out << "}\n";
}

void Node::gen_dot_rec(std::ofstream& out, int& id) {
    int my_id = id++;

    out << "node" << my_id << " [label=\""
        << type;

    if (value != "") out << ":" << value;

    out << "\"];\n";

    for (auto child : children) {
        if (child) {
            int child_id = id;
            child->gen_dot_rec(out, id);
            out << "node" << my_id << " -> node" << child_id << ";\n";
        }
    }
}