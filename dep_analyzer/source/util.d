module util;
import std.string;

string truncateModuleName(string s) {
    auto idx = s.lastIndexOf('.');
    return (idx != -1) ? s[idx + 1 .. $] : s;
}