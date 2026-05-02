#ifndef AST_H
#define AST_H

#include <iostream>
#include <vector>
#include <string>
#include <fstream>

class Node {
public:
    std::string type;
    std::string value;
    std::string name;
    std::vector<Node*> children;

    Node(std::string type) : type(type) {}
    Node(std::string type, std::string name) : type(type), name(name) {}

    void add_child(Node* child) {
        if (child) children.push_back(child);
    }

    void print(int depth = 0) {
        for (int i = 0; i < depth; i++) std::cout << "  ";
        std::cout << type;

        if (!name.empty()) std::cout << "(" << name << ")";
        if (!value.empty()) std::cout << " : " << value;

        std::cout << std::endl;

        for (auto c : children)
            c->print(depth + 1);
    }

    int to_dot(std::ofstream& out, int& id) {
        int my_id = id++;
        out << "  node" << my_id << " [label=\"" << type;

        if (!name.empty()) out << "\\n" << name;
        if (!value.empty()) out << "\\n" << value;

        out << "\"];\n";

        for (auto c : children) {
            int child_id = c->to_dot(out, id);
            out << "  node" << my_id << " -> node" << child_id << ";\n";
        }

        return my_id;
    }

    void gen_dot(const std::string& filename) {
        std::ofstream out(filename);
        out << "digraph AST {\n";
        int id = 0;
        to_dot(out, id);
        out << "}\n";
        out.close();
    }
};

#endif