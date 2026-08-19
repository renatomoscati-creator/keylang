"""A minimal reader for the OpenStep plist format Xcode still uses.

Not a general parser and not a writer. It exists so `tools/check_project.py` can
make claims about LinguaKey.xcodeproj on a machine with no Xcode, which is the
only kind of machine this project has ever been edited on.
"""
import re, sys

class P:
    def __init__(self, text):
        # strip // comments outside strings, and /* */ comments
        self.s = text
        self.i = 0
        self.n = len(text)
    def ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("/*", self.i):
                j = self.s.find("*/", self.i+2)
                if j < 0: raise ValueError("unterminated /*")
                self.i = j+2
            elif self.s.startswith("//", self.i):
                j = self.s.find("\n", self.i)
                self.i = self.n if j < 0 else j+1
            else:
                return
    def parse(self):
        self.ws()
        return self.value()
    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{": return self.dict()
        if c == "(": return self.array()
        if c == '"': return self.qstring()
        return self.bare()
    def dict(self):
        assert self.s[self.i] == "{"; self.i += 1
        out = {}
        while True:
            self.ws()
            if self.i >= self.n: raise ValueError("unterminated dict")
            if self.s[self.i] == "}":
                self.i += 1; return out
            k = self.value()
            self.ws()
            if self.s[self.i] != "=": raise ValueError(f"expected = after {k!r} at {self.i}")
            self.i += 1
            v = self.value()
            self.ws()
            if self.i < self.n and self.s[self.i] == ";": self.i += 1
            else: raise ValueError(f"expected ; after {k!r} at {self.i}")
            out[k] = v
    def array(self):
        assert self.s[self.i] == "("; self.i += 1
        out = []
        while True:
            self.ws()
            if self.i >= self.n: raise ValueError("unterminated array")
            if self.s[self.i] == ")":
                self.i += 1; return out
            out.append(self.value())
            self.ws()
            if self.i < self.n and self.s[self.i] == ",": self.i += 1
    def qstring(self):
        self.i += 1
        out = []
        while self.s[self.i] != '"':
            if self.s[self.i] == "\\":
                out.append(self.s[self.i:self.i+2]); self.i += 2
            else:
                out.append(self.s[self.i]); self.i += 1
        self.i += 1
        return "".join(out)
    def bare(self):
        m = re.compile(r"[A-Za-z0-9_./$@:+\-*<>~]+").match(self.s, self.i)
        if not m: raise ValueError(f"bad token at {self.i}: {self.s[self.i:self.i+40]!r}")
        self.i = m.end()
        return m.group(0)

def load(path):
    text = open(path, encoding="utf-8").read()
    if text.startswith("// !$*UTF8*$!"):
        text = text.split("\n", 1)[1]
    return P(text).parse()
