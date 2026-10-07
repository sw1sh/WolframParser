#!/usr/bin/env python3
"""Hold the doc sources' code cells to the cell rules of docs/DOC_GUIDE.md.

Adapted from PureMath's scripts/check_enumerations.py and scripts/check_showcase.py
for pages that build with "EvaluateSeparator" -> None, where state threads from a
page's first cell to its last.

Reports
  compound   a cell of two or more top-level statements, separated by ';' or one
             per line: every output but the last is hidden, and a binding the
             reader never sees belongs in its own captioned cell;
  bundle     a cell whose shown value is a list literal of two or more calls or
             property lookups - several outputs behind one, each of which belongs
             in its own cell;
  caption    a cell follows another with no sentence between, and the first is not a
             binding, a definition or a side effect the second goes on to use - each
             shown value gets its own lead-in;
  showcase   on a Symbol page, the first cell that uses the page's symbol does not
             show it bare: a function applied with nothing applied to the result
             (Sym[...], optionally bound as x = Sym[...]), or - for a symbol that is
             a value, whose Usage reads "[Sym]() is ..." - the symbol itself or its
             Keys.
Not reported: a `#| eval: false` cell, which is a listing and never evaluated; a cell
of delayed definitions only (f[x_] := ...), which have no value to show; and a
`#| collapse: true` cell that shows nothing (its last statement ends in ';'), a hidden
setup cell of helper definitions.

Usage: python3 dev/check-doc-cells.py [page.md ...]; without arguments every page
under docs/. Exits 1 when anything is reported.
"""
import glob, os, re, sys

CELL = re.compile(r'^```wl\n(.*?)\n```$', re.S | re.M)
HINT = re.compile(r'<!-- =>.*?-->', re.S)
# a line ending in one of these continues on the next; a line starting with one
# of these continues the line before
CONTINUES = tuple('~+-*/=<>|&,@.^:?!')
CONTINUATION = tuple('~+*/=<>|&,@.^:?)]}')


def options(cell):
    return [l.strip() for l in cell.split('\n') if l.strip().startswith('#|')]


def body(cell):
    return '\n'.join(l for l in cell.split('\n') if not l.strip().startswith('#|'))


def strip_comments(s):
    out, depth, instr, i = '', 0, False, 0
    while i < len(s):
        if not instr and s.startswith('(*', i):
            depth += 1
            i += 2
            continue
        if depth and s.startswith('*)', i):
            depth -= 1
            i += 2
            continue
        if depth:
            i += 1
            continue
        if s[i] == '"' and (i == 0 or s[i - 1] != '\\'):
            instr = not instr
        out += s[i]
        i += 1
    return out


def statements(s):
    """Top-level statements, each with its trailing ';' when it has one."""
    s = strip_comments(s)
    out, cur, depth, instr = [], '', 0, False
    for i, ch in enumerate(s):
        if ch == '"' and (i == 0 or s[i - 1] != '\\'):
            instr = not instr
        if not instr:
            if ch in '[({':
                depth += 1
            elif ch in '])}':
                depth -= 1
            elif ch == ';' and depth == 0:
                out.append(cur.strip() + ';')
                cur = ''
                continue
            elif ch == '\n' and depth == 0:
                prev, rest = cur.rstrip(), s[i + 1:].lstrip()
                if prev and rest and not prev.endswith(CONTINUES) and not rest.startswith(CONTINUATION):
                    out.append(prev.strip())
                    cur = ''
                    continue
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return [x for x in out if x.strip(' ;\n')]


def matching(s, open_at):
    """index of the bracket closing the one at open_at, or -1"""
    depth, instr = 0, False
    for i in range(open_at, len(s)):
        ch = s[i]
        if ch == '"' and s[i - 1] != '\\':
            instr = not instr
        if instr:
            continue
        if ch in '[({':
            depth += 1
        elif ch in '])}':
            depth -= 1
            if depth == 0:
                return i
    return -1


def elements(s):
    inner, parts, cur, depth, instr = s[1:-1], [], '', 0, False
    for i, ch in enumerate(inner):
        if ch == '"' and (i == 0 or inner[i - 1] != '\\'):
            instr = not instr
        if not instr:
            if ch in '[({':
                depth += 1
            elif ch in '])}':
                depth -= 1
            elif ch == ',' and depth == 0:
                parts.append(cur.strip())
                cur = ''
                continue
        cur += ch
    parts.append(cur.strip())
    return parts


def definition(st):
    """a delayed definition - f[x_] := ..., x /: f[x] := ..., f[x_] ^:= ... - shows nothing"""
    st = strip_comments(st)
    depth, instr = 0, False
    for i, ch in enumerate(st):
        if ch == '"' and (i == 0 or st[i - 1] != '\\'):
            instr = not instr
        if instr:
            continue
        if ch in '[({':
            depth += 1
        elif ch in '])}':
            depth -= 1
        elif depth == 0 and st.startswith(':=', i) and not st.startswith(':=', i - 1):
            return True
    return False


def shown(cell):
    """the statement whose value the cell shows, or None when it shows nothing"""
    st = statements(body(cell))
    return None if not st or st[-1].endswith(';') else st[-1]


def unbound(s):
    return re.sub(r'^[A-Za-z$][A-Za-z0-9$]*\s*=(?![=!])\s*', '', s)


def bundle(cell):
    s = shown(cell)
    if s is None:
        return None
    s = unbound(s)
    if not (s.startswith('{') and matching(s, 0) == len(s) - 1):
        return None
    els = elements(s)
    output_like = lambda e: re.match(r'^[A-Za-z$][A-Za-z0-9$`]*(\[.*\])?\[', e, re.S) is not None
    return els if len(els) >= 2 and all(output_like(e) for e in els) else None


def bare(sym, cell, value):
    s = shown(cell)
    if s is None:
        return False
    s = unbound(s)
    if value and s in (sym, f'Keys[{sym}]'):
        return True
    return s.startswith(sym + '[') and matching(s, len(sym)) == len(s) - 1


def setup(cell):
    """a binding, a definition or a side effect, which the next cell may use without a caption"""
    st = statements(body(cell))
    last = st[-1] if st else ''
    return (not st or last.endswith(';') or definition(last) or last.startswith('Needs[')
            or re.match(r'^[A-Za-z$][A-Za-z0-9$]*(\[[^\]]*\])?\s*=(?![=!])', last) is not None)


def check(path):
    text = open(path).read()
    issues = []
    fenced = list(CELL.finditer(text))
    for a, b in zip(fenced, fenced[1:]):
        if not HINT.sub('', text[a.end():b.start()]).strip() and not setup(a.group(1)):
            issues.append(f'caption: no lead-in before: {body(b.group(1)).strip().splitlines()[0][:80]}')
    cells = [m.group(1) for m in fenced if '#| eval: false' not in options(m.group(1))]
    for c in cells:
        st = statements(body(c))
        if len(st) >= 2 and not all(definition(x) for x in st) and \
                not ('#| collapse: true' in options(c) and st[-1].endswith(';')):
            issues.append(f'compound: {len(st)} statements in one cell: {st[0].splitlines()[0][:80]}')
        els = bundle(c)
        if els:
            issues.append(f'bundle: {len(els)} outputs in one cell: {shown(c).splitlines()[-1][:80]}')
    m = re.search(r'^Name:\s*(\S+)', text, re.M)
    if m and re.search(r'^Template:\s*Symbol\s*$', text, re.M):
        sym = m.group(1)
        value = re.search(r'^## Usage\s*\n\s*(<code>)?\[' + re.escape(sym) + r'\]\(\)(</code>)? is\b', text, re.M) is not None
        use = re.compile(r'(?<![A-Za-z0-9`$])' + re.escape(sym) + (r'(?![A-Za-z0-9`$])' if value else r'\s*\['))
        uses = [c for c in cells if use.search(strip_comments(body(c)))]
        if uses and not bare(sym, uses[0], value):
            first = (shown(uses[0]) or statements(body(uses[0]))[-1]).splitlines()
            issues.append(f'showcase: first use is not bare: {first[0][:80]}')
    return issues


root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
paths = sys.argv[1:] or sorted(p for p in glob.glob(os.path.join(root, 'docs', '**', '*.md'), recursive=True)
                               if open(p).read().lstrip().startswith('---'))
bad = 0
for p in paths:
    for issue in check(p):
        bad += 1
        print(f'{os.path.relpath(p, root)}: {issue}')
print(f'check-doc-cells: {bad} issue(s) across {len(paths)} page(s)')
sys.exit(1 if bad else 0)
