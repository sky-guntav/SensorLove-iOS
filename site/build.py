#!/usr/bin/env python3
"""sensor.love, built from this repo.

The docs are the Markdown files in docs/ and CHANGELOG.md, each a page of the site: GitHub shows the same files. The sensor
reference, docs/sensors.md, is written from the app itself, so it can never promise what the app does not send: the addresses
from Sender.space (App/Sender.swift), what each sensor does from its card (WebUI/home.html). The home page's hero is the app's own
page (monitor.html), playing its sensors.

  python3 site/build.py            writes docs/sensors.md and the site into build/site/
  python3 site/build.py --serve    the same, then serves it on http://localhost:8766
"""
import ast, functools, html, http.server, operator, os, random, re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'site'
URL = 'https://sensor.love'
DESCRIPTION = 'A free iPhone app: sensor toys that speak OSC. Motion, touch, face, hands, sound, location, weather and time, live in your own tools.'
DOCS = {'docs/getting-started.md': 'start', 'docs/sensors.md': 'sensors', 'docs/osc.md': 'osc', 'docs/ndi.md': 'ndi', 'CHANGELOG.md': 'changelog', 'docs/privacy-policy.md': 'privacy'}   # each a page: /start …
EXAMPLES = ROOT / 'examples'   # the receivers, a page of their own: /examples, each file there to download
NOT_FOUND = '<section class="lost"><div class="frogbox">{{frog}}</div><h1>NOTHING HERE</h1><p><a href="/">BACK TO SENSORLOVE</a></p></section>'
BACK = '<header class="back"><a href="/">← SENSORLOVE</a></header>'


class Stop(Exception):
    pass


def fail(why):
    raise Stop(why)


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):   # utf-8 and \n everywhere: Windows would write µ and ° in its own code page
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')


# ---------- what the app sends: Sender.space, read from its Swift ----------
EACH = 'func each(_ a: String, _ keys: [String], _ what: String) -> [[String]] { keys.map { [a + "/" + $0, what] } }'
HAND = (r'for h in (\[[^\]]*\]) \{ for \(i, k\) in (\w+)\.enumerated\(\) \{ (\w+)\.append\(\["([/\w]+)/\\\(h\)/" \+ k, '
        r'k == "gesture" \? "0-7" : i == 0 \|\| i > 8 \? "0 / 1" : "VALUE"\]\) \} \}')
DONE = 'return s.mapValues { $0.map { [OSC.root + $0[0], $0[1]] } }'


def split(e, sep):   # e cut at each sep that is outside strings and brackets
    out, depth, quoted, start, i = [], 0, False, 0, 0
    while i < len(e):
        c = e[i]
        if c == '"':
            quoted = not quoted
        elif not quoted and c in '[({':
            depth += 1
        elif not quoted and c in '])}':
            depth -= 1
        elif not quoted and not depth and e.startswith(sep, i):
            out.append(e[start:i])
            i += len(sep)
            start = i
            continue
        i += 1
    return out + [e[start:]]


def read_space(src, osc):
    """Sender.space as {sensor: [[address, what its value is], ...]}. It knows only the shapes the Swift uses there and stops on
    anything else, naming it: a change it does not follow cannot slip into the docs."""
    root = ast.literal_eval(re.search(r'static let root = ("[^"]*")', osc)[1])
    live = ast.literal_eval(re.search(r'static let live = (\[[^\]]*\])', src)[1])
    body = re.search(r'static let space: .*? = \{\n(.*?)\n    \}\(\)\n', src, re.S)[1]
    body = re.sub(r'("[^"\n]*")|//[^\n]*', lambda m: m[1] or '', body)   # comments out; strings first, so a // in one stays
    statements, cur = [], ''
    for line in body.split('\n'):   # a statement runs on until its brackets close
        cur = (cur + ' ' + line.strip()).strip()
        bare = re.sub(r'"[^"]*"', '', cur)
        if cur and all(bare.count(a) == bare.count(b) for a, b in ('[]', '{}', '()')):
            statements.append(cur)
            cur = ''
    env, out = {}, None

    def ev(e, st):
        return functools.reduce(operator.add, [term(t.strip(), st) for t in split(e, ' + ')])

    def term(t, st):
        if t == '[:]':
            return {}
        if t in env:
            return env[t]
        if '\\' not in t:   # Swift's string and array literals are Python's, but for "\(x)"
            try:
                return ast.literal_eval(t)
            except (ValueError, SyntaxError):
                pass
        m = re.fullmatch(r'each\((.+?), (\w+|\[[^\]]*\]), ("[^"]*")\)', t)
        if m and 'each' in env:
            return env['each'](ev(m[1], st), ev(m[2], st), ev(m[3], st))
        m = re.fullmatch(r'(\w+)\.map \{ \[("[^"]*") \+ \$0, ("[^"]*")\] \}', t)
        if m and m[1] in env:
            return [[ast.literal_eval(m[2]) + x, ast.literal_eval(m[3])] for x in env[m[1]]]
        fail('Sender.space: cannot read %s in: %s' % (t, st))

    for st in statements:
        m = re.fullmatch(r'(?:let|var) (.+)', st)
        if m:
            for b in split(m[1], ', '):
                n = re.fullmatch(r'(\w+)(?:: [^=]+)? = (.+)', b) or fail('Sender.space: cannot read: ' + st)
                env[n[1]] = ev(n[2], st)
            continue
        if st == EACH:
            env['each'] = lambda a, keys, what: [[a + '/' + k, what] for k in keys]
            continue
        m = re.fullmatch(r'(\w+)\[("\w+")\] = (.+)', st)
        if m and isinstance(env.get(m[1]), dict):
            env[m[1]][ast.literal_eval(m[2])] = ev(m[3], st)
            continue
        m = re.fullmatch(r'for (\w+) in (\[[^\]]*\]) \{ (\w+) \+= (.+) \}', st)
        if m and m[3] in env:
            for v in ev(m[2], st):
                env[m[1]] = v
                env[m[3]] = env[m[3]] + ev(m[4], st)
            continue
        m = re.fullmatch(HAND, st)
        if m and m[2] in env and m[3] in env:
            for h in ev(m[1], st):
                for i, k in enumerate(env[m[2]]):
                    env[m[3]].append([m[4] + '/' + h + '/' + k, '0-7' if k == 'gesture' else '0 / 1' if i == 0 or i > 8 else 'VALUE'])
            continue
        if st == DONE and isinstance(env.get('s'), dict):
            out = {k: [[root + a, u] for a, u in v] for k, v in env['s'].items()}
            continue
        fail('Sender.space: cannot read: ' + st)
    if out is None or set(out) != set(live):
        fail('Sender.space: its sensors are not the ones Sender.live reads')
    for a, u in (r for rows in out.values() for r in rows):
        if not re.fullmatch(re.escape(root) + r'(/[\w-]+)+', a) or a[-1].isdigit() or not u:   # TouchDesigner runs a number into an address ending in one
            fail('Sender.space: odd address ' + a)
    return out, live


# ---------- what the page says: the cards, the access each needs, the frog, the wizard and his garden ----------
def read_page(page):
    cards = []
    for m in re.finditer(r"\{ id:'(\w+)', nm:'([^']*)'((?:(?!\{ id:').)*?)\binfo:'((?:[^'\\]|\\.)*)'", page, re.S):
        osc = re.search(r"\bosc:'([^']*)'", m[3]) or fail('home.html: no osc on the card ' + m[1])
        cards.append((m[1], m[2], osc[1], re.sub(r'\\(.)', r'\1', m[4])))
    names = dict(re.findall(r"(\w+):'([^']*)'", re.search(r'var NAMES = \{(.*?)\};', page, re.S)[1]))
    const = lambda name: ast.literal_eval(re.search(r'\b%s = (\[.*?\]);' % name, page, re.S)[1])
    return (cards, names, const('PERMS'), const('LOGO'), (const('WIZ_BIG'), const('CAN'), const('FLOWERS')),
            {'logo': const('LOGO'), 'arc': const('LOGO_ARC')})


def sensors_md(space, cards, names, perms):
    need = {i: label for _, label, ids in perms for i in ids}
    md = ['# Sensors', '',
          '<!-- Written by site/build.py from App/Sender.swift (the addresses) and WebUI/home.html (what each sensor does). '
          'Change those and run it again; do not edit this file. -->', '',
          'Every value has its own address under `/sensorlove`, with one number in it, or one text. A destination\'s PREFIX goes '
          'right after the root: `/sensorlove/phone1/accel/x`. [OSC](osc.md) tells how the values travel.', '']
    for id, nm, scope, info in cards:   # in the cards' order, as the app shows them
        title = names.get(id, nm)
        md += ['## ' + title + (' (%s)' % nm if nm != title else ''), '', info, '']
        if id in need:
            md += ['**Permission:** %s' % need[id], '']
        if not space[id]:   # VIDEO, DEPTH: an NDI source, nothing over OSC
            md += ['**Sent as:** an NDI® source, not OSC. [NDI](ndi.md) tells how to take it in.', '']
            continue
        md += ['<details>', '<summary>Addresses <code>%s</code></summary>' % html.escape(scope), '',
               '| Address | Value |', '| --- | --- |'] + ['| `%s` | %s |' % (a, u) for a, u in space[id]] + ['', '</details>', '']
        if any(u == 'TEXT' for _, u in space[id]):
            md += ['TEXT comes as an OSC string.', '']
    return '\n'.join(md)


# ---------- Markdown, only what these docs use: anything else stops the build ----------
def slug(t):
    return re.sub(r'[^\w\- ]', '', t.lower()).strip().replace(' ', '-')


def href(t):
    if re.match(r'[a-z]+:', t) or t.startswith(('#', '/')):
        return t
    path, _, frag = t.partition('#')
    for doc, page in DOCS.items():
        if Path(path).name == Path(doc).name:
            return '/' + page + ('#' + frag if frag else '')
    folder = path.removesuffix('README.md').rstrip('/').rpartition('/')[2]   # examples/ is the page /examples, its max/ the Max section on it
    if folder == 'examples':
        return '/examples/'
    if folder and (EXAMPLES / folder).is_dir():
        return '/examples/#' + folder
    fail('a link to %s, which the site does not have' % t)


def inline(t):
    code = []

    def keep(m):
        code.append(m[1])
        return '\0%d\0' % (len(code) - 1)
    t = html.escape(re.sub(r'`([^`]+)`', keep, t), quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', lambda m: '<a href="%s">%s</a>' % (html.escape(href(html.unescape(m[2]))), m[1]), t)
    return re.sub('\0(\\d+)\0', lambda m: '<code>%s</code>' % html.escape(code[int(m[1])], quote=False), t)


def md(text, name='doc'):
    out, lines, i = [], text.split('\n'), 0
    item = re.compile(r'- |\d+\. ')
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
        elif line.startswith('```'):
            j = lines.index('```', i + 1)
            out.append('<pre><code>%s</code></pre>' % html.escape('\n'.join(lines[i + 1:j]), quote=False))
            i = j + 1
        elif re.match(r'#{1,4} ', line):
            n, t = line.index(' '), line.split(' ', 1)[1]
            out.append('<h1>%s</h1>' % inline(t) if n == 1 else '<h%d id="%s">%s</h%d>' % (n, slug(t), inline(t), n))   # GitHub's anchors
            i += 1
        elif line.startswith('<'):   # raw HTML (details, summary, a comment): GitHub shows it the same way
            out.append(line)
            i += 1
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                rows.append([c.strip() for c in lines[i].strip().strip('|').split('|')])
                i += 1
            if len(rows) < 2 or not all(re.fullmatch(r':?-+:?', c) for c in rows[1]):
                fail('%s: a table without its | --- | line' % name)
            out.append('<div class="table"><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (
                ''.join('<th>%s</th>' % inline(c) for c in rows[0]),
                ''.join('<tr>%s</tr>' % ''.join('<td>%s</td>' % inline(c) for c in r) for r in rows[2:])))
        elif item.match(line):
            tag, items = 'ol' if line[0].isdigit() else 'ul', []
            while i < len(lines) and item.match(lines[i]):
                text = item.sub('', lines[i], 1)
                i += 1
                while i < len(lines) and lines[i].startswith('  ') and lines[i].strip() and not item.match(lines[i].strip()):
                    text += ' ' + lines[i].strip()   # a long item wrapped onto the next line
                    i += 1
                items.append('<li>%s</li>' % inline(text))
            out.append('<%s>%s</%s>' % (tag, ''.join(items), tag))
        elif re.match(r'\s|>|\* |\+ |!\[|#', line):
            fail('%s: Markdown the site does not read: %s' % (name, line))
        else:
            para = []
            while i < len(lines) and lines[i].strip() and not re.match(r'#{1,4} |```|<|\||- |\d+\. ', lines[i]):
                para.append(lines[i].strip())
                i += 1
            out.append('<p>%s</p>' % inline(' '.join(para)))
    return '\n'.join(out)


# ---------- the app's figures, as dots: the frog (404), the paper wizard and his garden ----------
def cells_path(cells):
    return ''.join('M%d %dh1v1h-1z' % p for p in cells)


def dots(cells):   # a round dot in each cell: a line of no length, its round caps the dot (style.css gives it its width)
    return ''.join('M%g %gh0' % (x + .5, y + .5) for x, y in sorted(cells))


def paint(cells, art, x0, y0, keys):   # art's dots into cells {(x, y): class}, keys its characters' classes
    for y, row in enumerate(art):
        for x, c in enumerate(row):
            if c in keys:
                cells[x0 + x, y0 + y] = keys[c]


def paths(cells):   # a path for each class's dots
    groups = {}
    for p, k in cells.items():
        groups.setdefault(k, []).append(p)
    return ''.join('<path class="%s" d="%s"/>' % (k, dots(groups[k])) for k in sorted(groups))


def svg(cls, w, h, body):
    return '<svg class="%s" viewBox="0 0 %d %d" aria-hidden="true">%s</svg>' % (cls, w, h, body)


def tree_rows(n):
    """HELLO's paper fir of n tiers (treeRows in WebUI/home.html), each a cone lit left (#), shaded right (+), on its trunk (t)"""
    if not n:
        return ['.#.', '.t.']
    c = n + 1
    return [''.join('.' if abs(x - c) > t + y else '#' if x <= c else '+' for x in range(2 * c + 1)) for t in range(n) for y in range(3)] + ['.' * c + 't' + '.' * c] * 2


def frog_svg(L):
    """The top bar's frog (paintMark in WebUI/home.html), its dark-theme drawing: the outline, mouth and line; its eyes a ring round the
    ground with the glint lit"""
    body = lambda x, y: 7 <= y < 15 and 2 <= x < 25 and L[y - 7][x - 2] != '.'
    eye = lambda x, y: body(x, y) and L[y - 7][x - 2] in 'og'
    cells = [(x, 15) for x in range(27)]
    for y in range(15):
        for x in range(27):
            if not body(x, y):
                if body(x - 1, y) or body(x + 1, y) or body(x, y - 1) or body(x, y + 1):
                    cells.append((x, y))   # its outline: the body itself is the ground
            elif L[y - 7][x - 2] == 'm' or L[y - 7][x - 2] == 'g' or (L[y - 7][x - 2] == 'o' and not (eye(x - 1, y) and eye(x + 1, y) and eye(x, y - 1) and eye(x, y + 1))):
                cells.append((x, y))
    return '<svg class="frog" viewBox="0 0 27 16" role="img" aria-label="SensorLove"><path d="%s"/></svg>' % cells_path(cells)


def wizard_svg(rows, can, flowers):
    """HELLO's paper wizard (WIZ_BIG in WebUI/home.html) in the monitor's round dots, his can where HELLO holds it (can()), watering
    a flower that grows under the spout through HELLO's first stages, a shoot, two leaves, a bud, its flower (a group each, played
    in turn by style.css, which bobs him too): paper in the light (#) in ink, in shade (+) dim, his eyes (E) a path of their own,
    so they can blink"""
    him, h = {}, len(rows)
    paint(him, rows, 0, 0, {'#': 'lit', '+': 'shade', 'E': 'eyes'})
    paint(him, can, 14, 11, {'#': 'lit', '+': 'shade'})
    him[21, 13] = 'drop'
    stages = [{} for _ in flowers[:4]]
    for c, art in zip(stages, flowers):
        paint(c, art, 20, h - len(art), {'#': 'p0', '+': 'leaf'})
    return svg('wizard', WIZ_W, h, '<g class="him">%s</g><g class="bud">%s</g>' % (paths(him), ''.join('<g>%s</g>' % paths(c) for c in stages)))


WIZ_W, WIZ_AT = 23, 70   # the wizard with his can and flower, in dots; the garden starts 70 dots left of him (style.css .garden)


def garden_svg(flowers, w=392, h=16):
    """SUPPORT ME's meadow along the section's foot, in colour: HELLO's firs and flowers (WebUI/home.html), on a floor of grass.
    His spot stays bare. Each plant brings its stages, a group each (a flower's shoot, leaves, bud and on; a fir tier by tier):
    style.css shows the last, site.js grows them from his spot out (data-d: how far, in dots). w: from 70 dots left of him to a
    3840 px screen's edge, at 12 px a dot as he is. The same every build"""
    rnd, floor, plants, x, last = random.Random(5), {}, [], 0, 0
    spot = range(WIZ_AT - 1, WIZ_AT + WIZ_W + 1)
    while True:
        x += rnd.randint(0, 2)
        if rnd.random() < .18:
            kind, stages, keys = 'fir', [tree_rows(k) for k in range(rnd.randint(1, 4) + 1)], {'#': 'pine', '+': 'leaf', 't': 'bark'}
        else:
            last = (last + rnd.randint(1, 5)) % 6   # never the colour of the flower before
            kind, stages, keys = 'flower', flowers[:rnd.choice((0, 1, 2, 3, 3, 4, 4, 5, 5)) + 1], {'#': 'p%d' % last, '+': 'leaf'}
        wd = len(stages[-1][0])
        if x + wd > w:
            break
        if x < spot.stop and x + wd > spot.start:
            x = spot.stop
            continue
        cells = [{} for _ in stages]
        for c, art in zip(cells, stages):   # each stage on the floor, under the grown one's middle
            paint(c, art, x + (wd - len(art[0])) // 2, h - 1 - len(art), keys)
        plants.append((kind, abs(x + wd // 2 - WIZ_AT - WIZ_W // 2), cells))
        x += wd
    grown = {p for _, _, cells in plants for p in cells[-1]}
    for x in range(w):
        floor[x, h - 1] = 'leaf'
        if (x, h - 2) not in grown and x not in spot and rnd.random() < .45:   # tufts, some two high
            floor[x, h - 2] = 'leaf'
            if (x, h - 3) not in grown and rnd.random() < .3:
                floor[x, h - 3] = 'leaf'
    return svg('garden', w, h, paths(floor) + ''.join('<g class="plant %s" data-d="%d">%s</g>' % (kind, d, ''.join('<g>%s</g>' % paths(c) for c in cells))
                                                       for kind, d, cells in plants))


# ---------- the hero: the app's own page, fed as inside the app, drawn in its browser study's phone ----------
MONITOR_NEEDS = ('SL.recv = function', 'var tiles = ', 'function faceMove', 'var FACE_MOVES',
                 'function handLm', 'var HAND_POSES', 'function clockVals', 'function helloTap(p, f)', 'var HELLO_SAY', 'HELLO_TIP = ', 'function sizePage',
                 'var DPR =', 'var frame = ', 'pageCache', "'sensorlove.last'", '<main id="main">', 'class="sys"', 'class="home-ind"',
                 '@media (max-width:430px) { .stage { padding:0; } .phone { width:100vw; height:100dvh;',
                 'function tileOf(id)', 'function toggle(t)', 'function showTile(t)', 'function switchTheme(v)', 'function camSide()', 'var NDISET = ', "NDIVIEW = 'REAL'", 'function clamp(v)', 'if (m.ndi) { NDIST = m.ndi; }', 'if (m.thumb) { thumbGot(m.thumb); }')
MONITOR_CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
               "connect-src 'none'; base-uri 'self'; form-action 'none'")   # connect-src none: whatever the page tries, nothing leaves it


def monitor_html(page):
    for need in MONITOR_NEEDS:   # what site/monitor-boot.js, monitor.js and monitor.css lean on
        if need not in page:
            fail('the hero plays the app through home.html\'s %s, which is gone: update site/monitor*.js / .css' % need)
    if page.count('<head>') != 1 or page.count('</head>') != 1 or page.count('</body>') != 1:
        fail('home.html: the hero needs one <head>, </head> and </body> to slip its files in')
    return (page.replace('<head>', '<head>\n<meta http-equiv="Content-Security-Policy" content="%s">\n<meta name="robots" content="noindex">\n'
                         '<script src="/monitor-boot.js"></script>' % MONITOR_CSP)
            .replace('</head>', '<link rel="stylesheet" href="/monitor.css">\n</head>')
            .replace('</body>', '<script src="/monitor.js"></script>\n</body>'))


# ---------- /examples: examples/README.md, then each example's README in the order its table lists them, with its files ----------
def examples_page():
    readme = read('examples/README.md')
    order = re.findall(r'\]\((\w+)/\)', readme)
    if sorted(order) != sorted(p.name for p in EXAMPLES.iterdir() if p.is_dir()):
        fail('examples/README.md lists %s, examples/ holds others: every example needs its row' % order)
    out = [md(readme, 'examples/README.md')]
    for name in order:
        files = sorted(f for f in (EXAMPLES / name).rglob('*') if f.is_file() and f.name != 'README.md')
        for f in files:
            (OUT / f.relative_to(ROOT)).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, OUT / f.relative_to(ROOT))
        doc = re.sub(r'^(#{1,3}) ', r'#\1 ', read('examples/%s/README.md' % name), flags=re.M)   # its # Max goes under the page's # Examples
        page = re.sub(r'(<h[2-4] id=")', r'\g<1>%s-' % name, md(doc, 'examples/%s/README.md' % name))   # each has its Play and Tried: #max-play, not five #play
        title, _, rest = page.partition('\n')
        get = ' '.join('<a href="/%s" download>%s ↓</a>' % (f.relative_to(ROOT).as_posix(), f.name) for f in files)
        out.append('<section id="%s">\n%s\n%s\n%s\n</section>' % (name, title, '<p class="files">%s</p>' % get if files else '', rest))
    return '\n'.join(out)


# ---------- checks on what was built ----------
def check():
    pages = {f: f.read_text(encoding='utf-8') for f in OUT.rglob('*.html')}
    ids = {f: set(re.findall(r'\sid="([^"]+)"', h)) for f, h in pages.items()}
    for f, h in pages.items():
        for tag, ref in re.findall(r'<(\w+)\b[^>]*?\s(?:href|src)="([^"]*)"', h):
            if re.match(r'[a-z]+:', ref):
                if tag != 'a' and not ref.startswith(URL + '/'):
                    fail('%s loads %s from elsewhere' % (f.name, ref))   # nothing from other sites: no fonts, no scripts, no trackers (Google Analytics: count.js loads it)
                continue
            path, _, frag = ref.partition('#')
            target = f if not path else OUT / (path.lstrip('/') or 'index.html')
            if target.is_dir():
                target = target / 'index.html'
            if not target.exists() and target.with_suffix('.html').exists():
                target = target.with_suffix('.html')
            if not target.exists() or (frag and tag == 'a' and frag not in ids[target]):   # a frame's #: its mode (monitor.html#space), not a place
                fail('%s links to %s, which is not there' % (f.name, ref))
        for a in re.findall(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+', h):
            if not a.endswith('@sensor.love'):
                fail('%s shows the address %s: only @sensor.love ones go on the site' % (f.name, a))
    for u in re.findall(r'url\(\s*["\']?([^"\')]+)', (OUT / 'style.css').read_text(encoding='utf-8')):
        if not (u.startswith('data:') or (u.startswith('/') and (OUT / u.lstrip('/')).exists())):
            fail('style.css loads %s' % u)


def selftest(src, osc):
    assert md('# T\n\nA `<x>` & **b** [c](https://e.com).') == \
        '<h1>T</h1>\n<p>A <code>&lt;x&gt;</code> &amp; <strong>b</strong> <a href="https://e.com">c</a>.</p>'
    assert md('## Two words\n- a\n  b\n- c\n\n[s](sensors.md#face)') == \
        '<h2 id="two-words">Two words</h2>\n<ul><li>a b</li><li>c</li></ul>\n<p><a href="/sensors#face">s</a></p>'
    assert md('| A | B |\n| --- | --- |\n| `x` | 1 |') == \
        '<div class="table"><table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td><code>x</code></td><td>1</td></tr></tbody></table></div>'
    assert md('[a](../examples/README.md) [b](max/)') == '<p><a href="/examples/">a</a> <a href="/examples/#max">b</a></p>'
    for bad, why in (('- a\n  - nested', 'a nested list'), ('> a', 'a quote'), (src.replace('i > 8', 'i > 9'), 'a HAND line it does not know')):
        try:
            read_space(bad, osc) if 'static let space' in bad else md(bad)
        except Stop:
            continue
        fail('selftest: read %s without stopping' % why)


def build():
    src, osc, page = read('App/Sender.swift'), read('App/OSC.swift'), read('WebUI/home.html')
    selftest(src, osc)
    space, live = read_space(src, osc)
    cards, names, perms, logo, garden, mark = read_page(page)
    if sorted(c[0] for c in cards if c[0] in live) != sorted(live) or any(not c[3] for c in cards):
        fail('home.html: every sensor the app reads needs its card, and every card its info')
    cards = [c for c in cards if c[0] in live]
    text = sensors_md(space, cards, names, perms)
    target = ROOT / 'docs' / 'sensors.md'
    if os.environ.get('GITHUB_ACTIONS') and (not target.exists() or target.read_text(encoding='utf-8') != text):
        fail('docs/sensors.md is not what the app sends now: run python3 site/build.py and commit it')
    write(target, text)

    if OUT.exists():
        shutil.rmtree(OUT)
    template = read('site/page.html')
    body, end = read('site/index.html').split('<!-- end -->')
    body = (body.replace('{{wizard}}', wizard_svg(*garden)).replace('{{garden}}', garden_svg(garden[2])).replace('{{count}}', str(len(cards)))
            .replace('{{sensors}}', ''.join('<li>%s</li>' % html.escape(names.get(c[0], c[1])) for c in cards)))
    pages = [('index.html', 'SensorLove · Sensor Toys that Speak OSC', URL + '/', 'home', '', body, end),
             ('404.html', 'Nothing here · SensorLove', URL + '/', 'doc', BACK, NOT_FOUND.replace('{{frog}}', frog_svg(logo)), '')]
    for doc, name in DOCS.items():
        text = read(doc)
        title = re.match(r'# (?:SensorLove )?(.+)', text)[1]   # "SensorLove Privacy Policy" → "Privacy Policy · SensorLove"
        pages.append((name + '.html', '%s · SensorLove' % title, URL + '/' + name, 'doc', BACK, '<article class="doc">\n%s\n</article>' % md(text, doc), ''))
    pages.append(('examples/index.html', 'Examples · SensorLove', URL + '/examples/', 'doc', BACK, '<article class="doc">\n%s\n</article>' % examples_page(), ''))   # index.html: its files sit in examples/ beside it
    for name, title, url, cls, top, main, tail in pages:
        h = template
        theme = '#0a0908' if cls == 'home' else '#c6c0b0'   # the top of the page: the hero's night on the home page (style.css .hero), --bg on the docs
        for slot, value in (('title', title), ('description', DESCRIPTION), ('url', url), ('class', cls), ('theme', theme), ('top', top), ('body', main), ('end', tail)):
            h = h.replace('{{%s}}' % slot, value)
        write(OUT / name, h)
    write(OUT / 'monitor.html', monitor_html(page))
    mark.update(sensors=len(cards), addresses=sum(len(v) for v in space.values()))   # PAPER PLANE's lines count them
    for name, slot, value in (('monitor-boot.js', 'live', live), ('xp.js', 'app', mark)):   # from the app: every sensor it reads (no card says COMING SOON); its frog for the hero
        js = read('site/' + name)
        if "'{{%s}}'" % slot not in js:
            fail("site/%s: no '{{%s}}' to write the app's %s into" % (name, slot, slot))
        write(OUT / name, js.replace("'{{%s}}'" % slot, repr(value)))
    for src_, dst in (('WebUI/fonts/DepartureMono-Regular.woff2', 'fonts/DepartureMono-Regular.woff2'), ('WebUI/fonts/LICENSE', 'fonts/OFL.txt'),
                      ('App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png', 'icon.png'), ('site/style.css', 'style.css'), ('site/site.js', 'site.js'),
                      ('site/monitor.js', 'monitor.js'), ('site/monitor.css', 'monitor.css'), ('site/share.png', 'share.png'),   # share.png: the hero at 1200 x 630, taken once
                      ('site/gsap.min.js', 'gsap.min.js'), ('site/dt.js', 'dt.js'), ('site/count.js', 'count.js')):   # GSAP 3.15.0, as npm has it (sha512 checked): the garden's clock
        (OUT / dst).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / src_, OUT / dst)
    check()
    return len(space), sum(len(v) for v in space.values())


def serve():
    class Pages(http.server.SimpleHTTPRequestHandler):   # as GitHub Pages serves it: /privacy is privacy.html, a missing page 404.html
        def __init__(self, *a, **k):
            super().__init__(*a, directory=str(OUT), **k)

        def translate_path(self, path):
            p = super().translate_path(path)
            return p + '.html' if not os.path.exists(p) and os.path.exists(p + '.html') else p

        def end_headers(self):   # a rebuild shows on the next reload, never an old copy from the browser's cache
            self.send_header('Cache-Control', 'no-store')
            super().end_headers()

        def send_error(self, code, message=None, explain=None):
            if code != 404:
                return super().send_error(code, message, explain)
            page = (OUT / '404.html').read_bytes()
            self.send_response(404)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(page)))
            self.end_headers()
            self.wfile.write(page)
    print('build: serving build/site on http://localhost:8766')
    http.server.ThreadingHTTPServer(('127.0.0.1', 8766), Pages).serve_forever()


if __name__ == '__main__':
    try:
        sensors, rows = build()
    except Stop as e:
        sys.exit('build: %s' % e)
    print('build: %d sensors, %d addresses; docs/sensors.md and build/site/ written' % (sensors, rows))
    if '--serve' in sys.argv:
        serve()
