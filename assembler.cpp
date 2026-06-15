#include <algorithm>
#include <cctype>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace std;

struct Line {
    int lineno;
    string label;
    string mnemonic;
    vector<string> operands;
};

using SymTable = map<string, uint8_t>;

static string toUpper(string s) {
    transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(toupper(c));
    });
    return s;
}

static string trim(const string &s) {
    size_t first = s.find_first_not_of(" \t\r\n");
    if (first == string::npos) {
        return "";
    }
    size_t last = s.find_last_not_of(" \t\r\n");
    return s.substr(first, last - first + 1);
}

static int parseReg(const string &tok, int lineno, vector<string> &errors) {
    string t = trim(tok);
    string u = toUpper(t);

    if (u == "R0") return 0;
    if (u == "R1") return 1;
    if (u == "R2") return 2;
    if (u == "R3") return 3;

    errors.push_back("error line " + to_string(lineno) + ": unknown register '" + t + "'");
    return -1;
}

static int parseImm(const string &tok, int lineno, vector<string> &errors) {
    string original = trim(tok);
    string t = original;
    if (!t.empty() && t[0] == '#') {
        t = trim(t.substr(1));
    }

    try {
        size_t pos = 0;
        long value = 0;
        if (t.size() > 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')) {
            value = stol(t, &pos, 16);
        } else {
            value = stol(t, &pos, 10);
        }

        if (pos != t.size()) {
            throw invalid_argument("trailing characters");
        }
        if (value < 0 || value > 255) {
            errors.push_back("error line " + to_string(lineno) + ": immediate " + t +
                             " out of range (0-255)");
            return -1;
        }
        return static_cast<int>(value);
    } catch (const invalid_argument &) {
        errors.push_back("error line " + to_string(lineno) + ": invalid immediate '" +
                         original + "'");
    } catch (const out_of_range &) {
        errors.push_back("error line " + to_string(lineno) + ": immediate " + t +
                         " out of range (0-255)");
    }
    return -1;
}

static string stripBrackets(string s) {
    s = trim(s);
    if (!s.empty() && s.front() == '[') {
        s = trim(s.substr(1));
    }
    if (!s.empty() && s.back() == ']') {
        s.pop_back();
    }
    return trim(s);
}

static vector<string> splitOperands(const string &s) {
    vector<string> operands;
    string tok;
    stringstream ss(s);
    while (getline(ss, tok, ',')) {
        operands.push_back(trim(tok));
    }
    return operands;
}

static Line parseLine(const string &raw, int lineno) {
    Line line{lineno, "", "", {}};

    string s = raw;
    size_t comment = s.find(';');
    if (comment != string::npos) {
        s = s.substr(0, comment);
    }
    s = trim(s);
    if (s.empty()) {
        return line;
    }

    size_t colon = s.find(':');
    if (colon != string::npos) {
        line.label = trim(s.substr(0, colon));
        s = trim(s.substr(colon + 1));
        if (s.empty()) {
            return line;
        }
    }

    size_t space = s.find_first_of(" \t");
    if (space == string::npos) {
        line.mnemonic = toUpper(s);
        return line;
    }

    line.mnemonic = toUpper(trim(s.substr(0, space)));
    string rest = trim(s.substr(space + 1));
    if (!rest.empty()) {
        line.operands = splitOperands(rest);
    }
    return line;
}

static vector<Line> lex(istream &in) {
    vector<Line> lines;
    string raw;
    int lineno = 1;
    while (getline(in, raw)) {
        lines.push_back(parseLine(raw, lineno++));
    }
    return lines;
}

static SymTable pass1(const vector<Line> &lines, vector<string> &errors) {
    SymTable sym;
    int pc = 0;

    for (const Line &line : lines) {
        if (!line.label.empty()) {
            if (sym.count(line.label) != 0) {
                errors.push_back("error line " + to_string(line.lineno) +
                                 ": duplicate label '" + line.label + "'");
            } else if (pc > 255) {
                errors.push_back("error line " + to_string(line.lineno) +
                                 ": program exceeds 256 instructions");
            } else {
                sym[line.label] = static_cast<uint8_t>(pc);
            }
        }

        if (!line.mnemonic.empty()) {
            if (pc >= 256) {
                errors.push_back("error line " + to_string(line.lineno) +
                                 ": program exceeds 256 instructions");
            }
            ++pc;
        }
    }

    return sym;
}

static bool needOperands(const Line &line, size_t count, vector<string> &errors) {
    if (line.operands.size() < count) {
        errors.push_back("error line " + to_string(line.lineno) + ": missing operand");
        return false;
    }
    return true;
}

static bool isNumericLiteral(string s) {
    s = trim(s);
    if (!s.empty() && s[0] == '#') {
        s = trim(s.substr(1));
    }
    if (s.empty()) {
        return false;
    }
    if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        return s.size() > 2 &&
               all_of(s.begin() + 2, s.end(), [](unsigned char c) { return isxdigit(c); });
    }
    return all_of(s.begin(), s.end(), [](unsigned char c) { return isdigit(c); });
}

static int parseTarget(const string &tok, int lineno, const SymTable &sym,
                       vector<string> &errors) {
    string t = trim(tok);
    if (isNumericLiteral(t)) {
        return parseImm(t, lineno, errors);
    }

    auto it = sym.find(t);
    if (it == sym.end()) {
        errors.push_back("error line " + to_string(lineno) + ": undefined label '" + t + "'");
        return -1;
    }
    return it->second;
}

static uint16_t makeWord(int opcode, int rd, int rs, int imm) {
    return static_cast<uint16_t>(((opcode & 0xf) << 12) |
                                 ((rd & 0x3) << 10) |
                                 ((rs & 0x3) << 8) |
                                 (imm & 0xff));
}

static uint16_t encode(const Line &line, const SymTable &sym, vector<string> &errors) {
    const string &m = line.mnemonic;
    if (m.empty()) {
        return 0;
    }

    if (m == "HALT") {
        return makeWord(0xf, 0, 0, 0);
    }

    if (m == "NOT") {
        if (!needOperands(line, 1, errors)) return 0;
        int rd = parseReg(line.operands[0], line.lineno, errors);
        return makeWord(0x6, rd < 0 ? 0 : rd, 0, 0);
    }

    if (m == "JMP" || m == "JZ") {
        if (!needOperands(line, 1, errors)) return 0;
        int imm = parseTarget(line.operands[0], line.lineno, sym, errors);
        return makeWord(m == "JMP" ? 0x9 : 0xa, 0, 0, imm < 0 ? 0 : imm);
    }

    if (m == "MOV") {
        if (!needOperands(line, 2, errors)) return 0;
        int rd = parseReg(line.operands[0], line.lineno, errors);
        string src = trim(line.operands[1]);
        if (!src.empty() && src[0] == '#') {
            int imm = parseImm(src, line.lineno, errors);
            return makeWord(0x1, rd < 0 ? 0 : rd, 0, imm < 0 ? 0 : imm);
        }
        int rs = parseReg(src, line.lineno, errors);
        return makeWord(0x0, rd < 0 ? 0 : rd, rs < 0 ? 0 : rs, 0);
    }

    if (m == "ADD" || m == "SUB" || m == "AND" || m == "OR") {
        if (!needOperands(line, 2, errors)) return 0;
        int opcode = 0;
        if (m == "ADD") opcode = 0x2;
        if (m == "SUB") opcode = 0x3;
        if (m == "AND") opcode = 0x4;
        if (m == "OR") opcode = 0x5;
        int rd = parseReg(line.operands[0], line.lineno, errors);
        int rs = parseReg(line.operands[1], line.lineno, errors);
        return makeWord(opcode, rd < 0 ? 0 : rd, rs < 0 ? 0 : rs, 0);
    }

    if (m == "LOAD") {
        if (!needOperands(line, 2, errors)) return 0;
        int rd = parseReg(line.operands[0], line.lineno, errors);
        int rs = parseReg(stripBrackets(line.operands[1]), line.lineno, errors);
        return makeWord(0x7, rd < 0 ? 0 : rd, rs < 0 ? 0 : rs, 0);
    }

    if (m == "STORE") {
        if (!needOperands(line, 2, errors)) return 0;
        int rs = parseReg(line.operands[0], line.lineno, errors);
        int rd = parseReg(stripBrackets(line.operands[1]), line.lineno, errors);
        return makeWord(0x8, rd < 0 ? 0 : rd, rs < 0 ? 0 : rs, 0);
    }

    errors.push_back("error line " + to_string(line.lineno) + ": unknown mnemonic '" +
                     line.mnemonic + "'");
    return 0;
}

static vector<uint16_t> pass2(const vector<Line> &lines, const SymTable &sym,
                              vector<string> &errors) {
    vector<uint16_t> words(256, 0);
    size_t pc = 0;

    for (const Line &line : lines) {
        if (line.mnemonic.empty()) {
            continue;
        }
        uint16_t word = encode(line, sym, errors);
        if (pc < words.size()) {
            words[pc] = word;
        }
        ++pc;
    }

    return words;
}

static void writeMemFile(const vector<uint16_t> &words, ostream &out) {
    for (uint16_t word : words) {
        out << hex << nouppercase << setw(4) << setfill('0') << word << '\n';
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        cerr << "usage: assembler input.asm output.mem\n";
        return 1;
    }

    ifstream in(argv[1]);
    if (!in) {
        cerr << "error: cannot open input file '" << argv[1] << "'\n";
        return 1;
    }

    vector<string> errors;
    vector<Line> lines = lex(in);
    SymTable sym = pass1(lines, errors);
    vector<uint16_t> words = pass2(lines, sym, errors);

    if (!errors.empty()) {
        for (const string &error : errors) {
            cerr << error << '\n';
        }
        return 1;
    }

    ofstream out(argv[2]);
    if (!out) {
        cerr << "error: cannot open output file '" << argv[2] << "'\n";
        return 1;
    }

    writeMemFile(words, out);
    return 0;
}
