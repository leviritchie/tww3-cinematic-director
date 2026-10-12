# Generates the mod's own UI art and twui templates (dark panels, gold accents).
#   ui/cinematic_director/*.png
#   ui/templates/cd_*.twui.xml
# Run from anywhere: python tools/make_ui.py
import os, uuid
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG_DIR = os.path.join(ROOT, 'ui', 'skins', 'default', 'cinematic_director')
TPL_DIR = os.path.join(ROOT, 'ui', 'templates')
IMG = 'ui/skins/default/cinematic_director/'
BLACK = 'ui/skins/default/solid_black.png'   # vanilla, always present

# palette
BG = (14, 15, 18)
GOLD = (212, 178, 106)
GOLD_DIM = (122, 100, 64)
CREAM = 'E9E1CC'
DIM = '8F8879'
GOLDTXT = 'E0BE72'
BRIGHT = 'FFF6DE'

# --------------------------------------------------------------------------------------------
# images
# --------------------------------------------------------------------------------------------

def rgba(c, a=255): return (c[0], c[1], c[2], a)

def framed(path, size, fill, border, inner=None, top=None, alpha=240):
    """square image with a 1px border (and an optional inner hairline), used 9-sliced"""
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, size - 1, size - 1], fill=rgba(fill, alpha))
    if top:  # soft top sheen
        for y in range(size // 2):
            a = int(top * (1 - y / (size / 2)))
            d.line([(1, y + 1), (size - 2, y + 1)], fill=(255, 255, 255, a))
        im2 = Image.new('RGBA', (size, size), rgba(fill, alpha))
        im = Image.alpha_composite(im2, im)
        d = ImageDraw.Draw(im)
    d.rectangle([0, 0, size - 1, size - 1], outline=rgba(border))
    if inner:
        d.rectangle([2, 2, size - 3, size - 3], outline=rgba(inner))
    im.save(os.path.join(IMG_DIR, path))

def arrow(path, size=24, colour=GOLD):
    s = 4
    big = Image.new('RGBA', (size * s, size * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    m = size * s
    d.polygon([(m * 0.22, m * 0.12), (m * 0.86, m * 0.5), (m * 0.22, m * 0.88), (m * 0.38, m * 0.5)], fill=rgba(colour))
    big.resize((size, size), Image.LANCZOS).save(os.path.join(IMG_DIR, path))

def make_images():
    os.makedirs(IMG_DIR, exist_ok=True)
    framed('panel.png', 32, BG, GOLD_DIM, inner=(38, 35, 30), alpha=238)
    framed('panel_solid.png', 32, (20, 21, 25), GOLD, inner=(46, 42, 34), alpha=255)
    framed('card.png', 16, (24, 25, 30), (52, 48, 42), alpha=235)
    framed('btn.png', 16, (30, 32, 38), (96, 80, 52), top=18)
    framed('btn_hover.png', 16, (44, 42, 40), GOLD, top=26)
    framed('btn_down.png', 16, (20, 20, 24), GOLD)
    framed('btn_sel.png', 16, (66, 54, 32), GOLD, top=22)
    framed('btn_off.png', 16, (24, 24, 27), (50, 48, 46), alpha=200)
    arrow('arrow.png')
    Image.new('RGBA', (8, 8), (255, 255, 255, 255)).save(os.path.join(IMG_DIR, 'white.png'))

# --------------------------------------------------------------------------------------------
# icons: white symbols (tinted per state in the cd_icon template), drawn 4x and scaled down
# --------------------------------------------------------------------------------------------

import math
ICON_PX = 48

def _canvas():
    s = ICON_PX * 4
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im), s

def _rot(cx, cy, pts, ang):
    c, s_ = math.cos(ang), math.sin(ang)
    return [(cx + x * c - y * s_, cy + x * s_ + y * c) for x, y in pts]

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

def _sword(d, cx, cy, L, ang):
    """a sword centred on cx,cy, length L, point up when ang = 0"""
    w = L * 0.07
    d.polygon(_rot(cx, cy, [(-w, L * 0.25), (w, L * 0.25), (w, -L * 0.3), (0, -L * 0.5), (-w, -L * 0.3)], ang), fill=WHITE)
    d.polygon(_rot(cx, cy, [(-L * 0.2, L * 0.25), (L * 0.2, L * 0.25), (L * 0.2, L * 0.31), (-L * 0.2, L * 0.31)], ang), fill=WHITE)
    d.polygon(_rot(cx, cy, [(-w * 0.8, L * 0.31), (w * 0.8, L * 0.31), (w * 0.8, L * 0.5), (-w * 0.8, L * 0.5)], ang), fill=WHITE)

def _arrow(d, x0, y0, x1, y1, width, head):
    ang = math.atan2(y1 - y0, x1 - x0)
    ux, uy = math.cos(ang), math.sin(ang)
    bx, by = x1 - ux * head, y1 - uy * head
    d.line([(x0, y0), (bx, by)], fill=WHITE, width=int(width))
    px, py = -uy, ux
    d.polygon([(x1, y1), (bx + px * head * 0.6, by + py * head * 0.6), (bx - px * head * 0.6, by - py * head * 0.6)], fill=WHITE)

def _shield(d, cx, cy, r):
    d.polygon([(cx - r, cy - r * 0.9), (cx + r, cy - r * 0.9), (cx + r, cy), (cx, cy + r * 1.1), (cx - r, cy)], fill=WHITE)

def make_icons():
    out = {}
    def save(name, im):
        im.resize((ICON_PX, ICON_PX), Image.LANCZOS).save(os.path.join(IMG_DIR, 'i_' + name + '.png'))
        out[name] = IMG + 'i_' + name + '.png'

    im, d, s = _canvas()   # eye: watching the whole field
    d.ellipse([s * 0.06, s * 0.28, s * 0.94, s * 0.72], fill=WHITE)
    d.ellipse([s * 0.14, s * 0.34, s * 0.86, s * 0.66], fill=CLEAR)
    d.ellipse([s * 0.36, s * 0.32, s * 0.64, s * 0.68], fill=WHITE)
    save('eye', im)

    im, d, s = _canvas()   # charge: double chevron
    for ox in (0.0, 0.3):
        d.polygon([(s * (0.1 + ox), s * 0.18), (s * (0.4 + ox), s * 0.5), (s * (0.1 + ox), s * 0.82),
                   (s * (0.24 + ox), s * 0.82), (s * (0.54 + ox), s * 0.5), (s * (0.24 + ox), s * 0.18)], fill=WHITE)
    save('charge', im)

    im, d, s = _canvas()   # clash: crossed swords
    _sword(d, s * 0.42, s * 0.54, s * 0.98, math.radians(45))
    _sword(d, s * 0.58, s * 0.54, s * 0.98, math.radians(-45))
    save('clash', im)

    im, d, s = _canvas()   # duel: two blades meeting point to point, with a spark
    _sword(d, s * 0.26, s * 0.5, s * 0.62, math.radians(90))
    _sword(d, s * 0.74, s * 0.5, s * 0.62, math.radians(-90))
    c = s * 0.5
    d.polygon([(c, s * 0.12), (c + s * 0.05, s * 0.3), (c, s * 0.36), (c - s * 0.05, s * 0.3)], fill=WHITE)
    d.polygon([(c, s * 0.88), (c + s * 0.05, s * 0.7), (c, s * 0.64), (c - s * 0.05, s * 0.7)], fill=WHITE)
    save('duel', im)

    im, d, s = _canvas()   # rear: arrow into the back of a block
    d.rectangle([s * 0.18, s * 0.08, s * 0.82, s * 0.4], fill=WHITE)
    _arrow(d, s * 0.5, s * 0.95, s * 0.5, s * 0.47, s * 0.12, s * 0.22)
    save('rear', im)

    im, d, s = _canvas()   # flank: arrow into the side of a block
    d.rectangle([s * 0.5, s * 0.15, s * 0.9, s * 0.85], fill=WHITE)
    _arrow(d, s * 0.03, s * 0.5, s * 0.44, s * 0.5, s * 0.12, s * 0.22)
    save('flank', im)

    im, d, s = _canvas()   # rout: broken shield
    _shield(d, s * 0.5, s * 0.5, s * 0.38)
    d.polygon([(s * 0.52, s * 0.0), (s * 0.4, s * 0.38), (s * 0.58, s * 0.52), (s * 0.44, s * 1.0),
               (s * 0.54, s * 1.0), (s * 0.68, s * 0.52), (s * 0.5, s * 0.38), (s * 0.62, s * 0.0)], fill=CLEAR)
    save('rout', im)

    im, d, s = _canvas()   # volley: two arrows in flight
    for oy in (-0.14, 0.14):
        _arrow(d, s * 0.08, s * (0.62 + oy), s * 0.9, s * (0.38 + oy), s * 0.06, s * 0.2)
    save('volley', im)

    im, d, s = _canvas()   # spell: four-point star with a spark
    c = s * 0.46
    d.polygon([(c, s * 0.04), (c + s * 0.1, c - s * 0.1), (s * 0.88, c), (c + s * 0.1, c + s * 0.1), (c, s * 0.88),
               (c - s * 0.1, c + s * 0.1), (s * 0.04, c), (c - s * 0.1, c - s * 0.1)], fill=WHITE)
    d.ellipse([s * 0.78, s * 0.74, s * 0.96, s * 0.92], fill=WHITE)
    save('spell', im)

    im, d, s = _canvas()   # general: crown
    d.polygon([(s * 0.1, s * 0.75), (s * 0.1, s * 0.3), (s * 0.3, s * 0.52), (s * 0.5, s * 0.2), (s * 0.7, s * 0.52),
               (s * 0.9, s * 0.3), (s * 0.9, s * 0.75)], fill=WHITE)
    d.rectangle([s * 0.1, s * 0.8, s * 0.9, s * 0.9], fill=WHITE)
    save('general', im)

    im, d, s = _canvas()   # hold: shield
    _shield(d, s * 0.5, s * 0.46, s * 0.4)
    save('hold', im)

    im, d, s = _canvas()   # flag: unit banners
    d.rectangle([s * 0.18, s * 0.06, s * 0.26, s * 0.96], fill=WHITE)
    d.polygon([(s * 0.26, s * 0.08), (s * 0.9, s * 0.08), (s * 0.72, s * 0.3), (s * 0.9, s * 0.52), (s * 0.26, s * 0.52)], fill=WHITE)
    save('flag', im)

    im, d, s = _canvas()   # film: HUD mode (a film frame)
    d.rectangle([s * 0.06, s * 0.18, s * 0.94, s * 0.82], fill=WHITE)
    d.rectangle([s * 0.2, s * 0.3, s * 0.8, s * 0.7], fill=CLEAR)
    for i in range(4):
        x = s * (0.1 + i * 0.24)
        d.rectangle([x, s * 0.2, x + s * 0.06, s * 0.26], fill=CLEAR)
        d.rectangle([x, s * 0.74, x + s * 0.06, s * 0.8], fill=CLEAR)
    save('film', im)

    im, d, s = _canvas()   # up / down: the tide's trend
    d.polygon([(s * 0.5, s * 0.15), (s * 0.9, s * 0.8), (s * 0.1, s * 0.8)], fill=WHITE)
    save('up', im)
    im, d, s = _canvas()
    d.polygon([(s * 0.5, s * 0.85), (s * 0.9, s * 0.2), (s * 0.1, s * 0.2)], fill=WHITE)
    save('down', im)

    im, d, s = _canvas()   # skull: a unit destroyed
    d.ellipse([s * 0.14, s * 0.06, s * 0.86, s * 0.7], fill=WHITE)
    d.rectangle([s * 0.3, s * 0.6, s * 0.7, s * 0.9], fill=WHITE)
    d.ellipse([s * 0.26, s * 0.3, s * 0.46, s * 0.5], fill=CLEAR)
    d.ellipse([s * 0.54, s * 0.3, s * 0.74, s * 0.5], fill=CLEAR)
    for x in (0.4, 0.5, 0.6):
        d.line([(s * x, s * 0.72), (s * x, s * 0.9)], fill=CLEAR, width=int(s * 0.03))
    save('skull', im)

    im, d, s = _canvas()   # tactic: a list of orders
    for y in (0.22, 0.5, 0.78):
        d.ellipse([s * 0.06, s * (y - 0.08), s * 0.22, s * (y + 0.08)], fill=WHITE)
        d.rectangle([s * 0.32, s * (y - 0.05), s * 0.94, s * (y + 0.05)], fill=WHITE)
    save('tactic', im)

    im, d, s = _canvas()   # heart: health
    d.ellipse([s * 0.08, s * 0.14, s * 0.52, s * 0.56], fill=WHITE)
    d.ellipse([s * 0.48, s * 0.14, s * 0.92, s * 0.56], fill=WHITE)
    d.polygon([(s * 0.1, s * 0.44), (s * 0.9, s * 0.44), (s * 0.5, s * 0.9)], fill=WHITE)
    save('heart', im)
    return out

# --------------------------------------------------------------------------------------------
# twui
# --------------------------------------------------------------------------------------------

def guid(*parts):
    u = uuid.uuid5(uuid.NAMESPACE_URL, 'cinematic_director/' + '/'.join(parts)).hex.upper()
    return f'{u[0:8]}-{u[8:12]}-{u[12:16]}-{u[16:32]}'

def attrs(d):
    return ''.join(f'\n\t\t\t{k}="{v}"' for k, v in d.items() if v is not None)

def text_xml(t, ind):
    if not t: return ''
    a = {
        'textxoffset': t.get('xoff'),
        'textvalign': t.get('valign', 'Center'),
        'texthalign': t.get('halign', 'Left'),
        'texthbehaviour': t.get('behaviour'),
        'textlocalised': 'true',
        'font_m_font_name': t['font'],
        'font_m_size': t['size'],
        'font_m_colour': '#' + t['colour'] + 'FF',
        'font_m_leading': '2',
    }
    return f'\n{ind}<component_text' + ''.join(f'\n{ind}\t{k}="{v}"' for k, v in a.items() if v is not None) + '/>'

class Comp:
    """one component: images = {name: path or None (solid colour)}, states = [state dicts]"""
    def __init__(self, tpl, cid, w, h, images=None, states=None, children=(), interactive=False, docking=None, priority=None,
                 relresize=False):
        self.tpl, self.id, self.w, self.h = tpl, cid, w, h
        self.images = images or {}
        self.states = states
        self.children = list(children)
        self.interactive, self.docking, self.priority, self.relresize = interactive, docking, priority, relresize
        self.g = guid(tpl, cid)

    def sg(self, name): return guid(self.tpl, self.id, 'state', name)
    def ig(self, name): return guid(self.tpl, self.id, 'image', name)

    def xml(self):
        out = []
        first = self.sg(self.states[0]['name'])
        a = {'this': self.g, 'id': self.id, 'uniqueguid_in_template': self.g, 'offset': '0.00,0.00'}
        if self.docking:
            a['docking'] = self.docking
            a['component_anchor_point'] = '0.50,0.50'
        if self.priority: a['priority'] = self.priority
        a.update({'tooltipslocalised': 'true', 'uniqueguid': self.g})
        if self.relresize: a['isrelativeresize'] = 'true'
        a.update({'currentstate': first, 'defaultstate': first})
        out.append(f'\t\t<{self.id}{attrs(a)}>')
        out.append('\t\t\t<componentimages>')
        if self.images:
            for name, path in self.images.items():
                p = f'\n\t\t\t\t\timagepath="{path}"' if path else ''
                g = self.ig(name)
                out.append(f'\t\t\t\t<component_image\n\t\t\t\t\tthis="{g}"\n\t\t\t\t\tuniqueguid="{g}"{p}/>')
        else:
            g = self.ig('none')
            out.append(f'\t\t\t\t<component_image\n\t\t\t\t\tthis="{g}"\n\t\t\t\t\tuniqueguid="{g}"/>')
        out.append('\t\t\t</componentimages>')
        out.append('\t\t\t<states>')
        for s in self.states:
            g = self.sg(s['name'])
            inter = '\n\t\t\t\t\tinteractive="true"' if self.interactive and not s.get('off') else ''
            out.append(f'\t\t\t\t<{s["name"]}\n\t\t\t\t\tthis="{g}"\n\t\t\t\t\tname="{s["name"]}"\n\t\t\t\t\twidth="{self.w}"\n\t\t\t\t\theight="{self.h}"{inter}\n\t\t\t\t\tuniqueguid="{g}">')
            if s.get('images'):
                out.append('\t\t\t\t\t<imagemetrics>')
                for k, im in enumerate(s['images']):
                    ig = guid(self.tpl, self.id, s['name'], 'im', str(k))
                    ia = {'this': ig, 'uniqueguid': ig, 'componentimage': self.ig(im['image']),
                          'width': im.get('w', self.w), 'height': im.get('h', self.h),
                          'colour': ('#' + im['colour']) if im.get('colour') else None,
                          'tile': 'true' if im.get('margin') else None,
                          'dockpoint': im.get('dock'),
                          'canresizewidth': 'false' if im.get('fixed_w') else None,
                          'canresizeheight': 'false' if im.get('fixed_h') else None,
                          'margin': im.get('margin')}
                    out.append('\t\t\t\t\t\t<image' + ''.join(f'\n\t\t\t\t\t\t\t{k2}="{v}"' for k2, v in ia.items() if v is not None) + '/>')
                out.append('\t\t\t\t\t</imagemetrics>')
            if s.get('text'):
                out.append(text_xml(s['text'], '\t\t\t\t\t')[1:])
            if s.get('trans'):
                out.append('\t\t\t\t\t<transitionmap>')
                for idx, target in s['trans']:
                    i = f'\n\t\t\t\t\t\t\tindex="{idx}"' if idx else ''
                    out.append(f'\t\t\t\t\t\t<transition{i}\n\t\t\t\t\t\t\ttransition_m_target_state="{self.sg(target)}"/>')
                out.append('\t\t\t\t\t</transitionmap>')
            out.append(f'\t\t\t\t</{s["name"]}>')
        out.append('\t\t\t</states>')
        out.append(f'\t\t</{self.id}>')
        return '\n'.join(out)

    def hierarchy(self, ind):
        if not self.children: return f'{ind}<{self.id} this="{self.g}"/>'
        inner = '\n'.join(c.hierarchy(ind + '\t') for c in self.children)
        return f'{ind}<{self.id} this="{self.g}">\n{inner}\n{ind}</{self.id}>'

    def all(self):
        yield self
        for c in self.children: yield from c.all()

def write_template(name, comp):
    rg = guid(name, 'root')
    rs = guid(name, 'root', 'state')
    ri = guid(name, 'root', 'img')
    rm = guid(name, 'root', 'metric')
    comps = '\n'.join(c.xml() for c in comp.all())
    xml = f'''<?xml version="1.0"?>
<layout
	version="142"
	comment=""
	precache_condition="">
	<hierarchy>
		<root this="{rg}">
{comp.hierarchy(chr(9) * 3)}
		</root>
	</hierarchy>
	<components>
{comps}
		<root
			this="{rg}"
			id="root"
			uniqueguid_in_template="{rg}"
			tooltipslocalised="true"
			uniqueguid="{rg}"
			currentstate="{rs}"
			defaultstate="{rs}">
			<componentimages>
				<component_image
					this="{ri}"
					uniqueguid="{ri}"/>
			</componentimages>
			<states>
				<newstate
					this="{rs}"
					name="NewState"
					width="1600"
					height="900"
					interactive="true"
					uniqueguid="{rs}">
					<imagemetrics>
						<image
							this="{rm}"
							uniqueguid="{rm}"
							componentimage="{ri}"
							width="1440"
							height="900"
							colour="#F0F0F0FF"/>
					</imagemetrics>
				</newstate>
			</states>
		</root>
	</components>
</layout>
'''
    with open(os.path.join(TPL_DIR, name + '.twui.xml'), 'w', newline='\r\n') as f:
        f.write(xml)

# text styles
def T(font, size, colour, halign='Left', xoff=None, behaviour=None, valign='Center'):
    return {'font': font, 'size': size, 'colour': colour, 'halign': halign, 'xoff': xoff, 'behaviour': behaviour, 'valign': valign}

BODY = 'la_gioconda'
HEAD = 'brand_header'
CAPS = 'la_gioconda_uppercase'

LABEL_STATES = {
    'body': T(BODY, 14, CREAM),
    'dim': T(BODY, 13, DIM),
    'small': T(BODY, 12, DIM),
    'gold': T(BODY, 14, GOLDTXT),
    'bright': T(BODY, 14, BRIGHT),
    'title': T(HEAD, 20, GOLDTXT),
    'title_c': T(HEAD, 20, GOLDTXT, 'Center'),
    'head': T(HEAD, 16, GOLDTXT),
    'caps': T(CAPS, 11, DIM),
    'caps_gold': T(CAPS, 11, GOLDTXT),
    'body_c': T(BODY, 14, CREAM, 'Center'),
    'dim_c': T(BODY, 13, DIM, 'Center'),
    'gold_c': T(BODY, 14, GOLDTXT, 'Center'),
    'big_c': T(HEAD, 16, GOLDTXT, 'Center'),
    'small_r': T(BODY, 12, DIM, 'Right'),
    'gold_r': T(BODY, 12, GOLDTXT, 'Right'),
    'warn': T(BODY, 13, 'E08A6A'),
    'para': T(BODY, 14, CREAM, valign='Top'),
    'para_dim': T(BODY, 13, DIM, valign='Top'),
    # cinematic HUD
    'hud_name': T(HEAD, 20, BRIGHT, 'Center'),
    'hud_c': T(BODY, 15, CREAM, 'Center'),
    'hud_dim_c': T(BODY, 13, 'B8B0A0', 'Center'),
    'feed': T(BODY, 14, CREAM),
    'feed_good': T(BODY, 14, GOLDTXT),
    'feed_bad': T(BODY, 14, 'E8846A'),
    'feed_old': T(BODY, 13, DIM),
    'tide_l': T(CAPS, 12, '9CC0EC'),
    'tide_r': T(CAPS, 12, 'E8846A', 'Right'),
    'caps_c': T(CAPS, 11, GOLDTXT, 'Center'),
    # streamlined HUD
    'banner': T(BODY, 17, BRIGHT, 'Center'),
    'toast': T(BODY, 13, 'D8D0BC', 'Center'),
}

# transitions (event index: 0 mouse on, 1 mouse off, 2 button down, 3 button up, 8 released elsewhere)
def button_states(img_for, w, h):
    def st(name, img, trans, off=False):
        return {'name': name, 'images': img_for(name, img), 'trans': trans, 'off': off}
    return [
        st('active', 'normal', [(None, 'hover')]),
        st('hover', 'hover', [(1, 'active'), (2, 'down')]),
        st('down', 'down', [(1, 'down_off'), (3, 'hover')]),
        st('down_off', 'normal', [(None, 'down'), (8, 'active')]),
        st('selected', 'sel', [(None, 'selected_hover')]),
        st('selected_hover', 'sel_hover', [(1, 'selected'), (2, 'selected_down')]),
        st('selected_down', 'down', [(1, 'selected'), (3, 'selected_hover')]),
        st('inactive', 'off', [], off=True),
    ]

def make_templates():
    os.makedirs(TPL_DIR, exist_ok=True)

    # panel: 9-sliced dark panel with a gold hairline. Interactive so clicks don't fall through to the map.
    panel = Comp('cd_panel', 'cd_panel', 400, 300, images={'base': BLACK, 'bg': IMG + 'panel.png', 'solid': IMG + 'panel_solid.png'}, interactive=True,
                 states=[{'name': 'default', 'images': [{'image': 'base', 'colour': 'FFFFFFE0'}, {'image': 'bg', 'margin': '8.00,8.00,8.00,8.00'}]},
                         {'name': 'solid', 'images': [{'image': 'base', 'colour': 'FFFFFFFF'}, {'image': 'solid', 'margin': '8.00,8.00,8.00,8.00'}]}])
    write_template('cd_panel', panel)

    # card: a quieter inset box
    card = Comp('cd_card', 'cd_card', 300, 60, images={'base': BLACK, 'bg': IMG + 'card.png'},
                states=[{'name': 'default', 'images': [{'image': 'base', 'colour': 'FFFFFF60'}, {'image': 'bg', 'margin': '4.00,4.00,4.00,4.00'}]}])
    write_template('cd_card', card)

    # solid fills (dividers, highlights)
    fills = {'line': '7A644080', 'gold': 'D4B26AFF', 'active': 'D4B26A30', 'shade': '00000070', 'clear': '00000000',
             'red': 'B0483AFF', 'green': '6FA05AFF', 'blue': '4F86C6FF', 'black': '000000FF', 'dark': '0E0F12C8',
             # highlight callouts: the box tinted green (good for the player) or red (bad)
             'green_bg': '24461CD8', 'red_bg': '561A12D8'}
    fill = Comp('cd_fill', 'cd_fill', 100, 2, images={'solid': IMG + 'white.png'},
                states=[{'name': n, 'images': [{'image': 'solid', 'colour': c}]} for n, c in fills.items()])
    write_template('cd_fill', fill)

    # text label (no art). One state per text style; Lua re-applies the text after changing state.
    label = Comp('cd_label', 'cd_label', 200, 24,
                 states=[{'name': n, 'text': t} for n, t in LABEL_STATES.items()])
    write_template('cd_label', label)

    # arrow marker
    arr = Comp('cd_arrow', 'cd_arrow', 24, 24, images={'a': IMG + 'arrow.png'},
               states=[{'name': 'default', 'images': [{'image': 'a'}]}])
    write_template('cd_arrow', arr)

    # button: framed, text in a child so hover/press states never lose it
    btn_imgs = {'normal': IMG + 'btn.png', 'hover': IMG + 'btn_hover.png', 'down': IMG + 'btn_down.png',
                'sel': IMG + 'btn_sel.png', 'off': IMG + 'btn_off.png', 'base': BLACK}
    def btn_img(state, img):
        key = {'sel_hover': 'sel'}.get(img, img)
        return [{'image': 'base', 'colour': 'FFFFFFB0'}, {'image': key, 'margin': '4.00,4.00,4.00,4.00'}]
    txt = Comp('cd_button', 'txt', 160, 32, docking='Center', relresize=True,
               states=[{'name': n, 'text': LABEL_STATES[n]} for n in ('body_c', 'dim_c', 'gold_c', 'big_c')])
    btn = Comp('cd_button', 'cd_button', 160, 32, images=btn_imgs, interactive=True, children=[txt],
               states=button_states(btn_img, 160, 32))
    write_template('cd_button', btn)

    # list row: flat; hover = faint gold wash, selected = gold wash + gold edge on the left
    row_imgs = {'wash': IMG + 'white.png', 'edge': IMG + 'white.png'}
    washes = {'normal': 'FFFFFF08', 'hover': 'D4B26A22', 'down': 'D4B26A38', 'sel': 'D4B26A30', 'sel_hover': 'D4B26A44', 'off': '00000000'}
    def row_img(state, img):
        out = [{'image': 'wash', 'colour': washes[img]}]
        out.append({'image': 'edge', 'colour': 'D4B26AFF' if img in ('sel', 'sel_hover') else ('D4B26A70' if img in ('hover', 'down') else '00000000'),
                    'w': 3, 'dock': 'Center Left', 'fixed_w': True})
        return out
    rtxt = Comp('cd_row', 'txt', 260, 28, docking='Center', relresize=True,
                states=[{'name': n, 'text': dict(LABEL_STATES[n], xoff='12.00,6.00')} for n in ('body', 'dim', 'gold', 'bright')])
    row = Comp('cd_row', 'cd_row', 260, 28, images=row_imgs, interactive=True, children=[rtxt],
               states=button_states(row_img, 260, 28))
    write_template('cd_row', row)

    # icon: one state per symbol and tint ("<icon>" cream, "<icon>_good" blue, "<icon>_bad" red, "<icon>_gold", "<icon>_dim")
    tints = {'': 'F2EAD6FF', '_good': '8FB8EAFF', '_bad': 'EC8A72FF', '_gold': 'E0BE72FF', '_dim': '8F8879A0'}
    states = []
    for name in ICONS:
        for suf, col in tints.items():
            states.append({'name': name + suf, 'images': [{'image': name, 'colour': col}]})
    icon = Comp('cd_icon', 'cd_icon', 32, 32, images=ICONS, states=states)
    write_template('cd_icon', icon)

if __name__ == '__main__':
    make_images()
    ICONS = make_icons()
    make_templates()
    print('ok', sorted(os.listdir(IMG_DIR)), sorted(os.listdir(TPL_DIR)))
