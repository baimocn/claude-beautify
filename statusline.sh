#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  Claude Code Status Bar — 上下文窗口 & Token 消耗实时监控
#  https://github.com/your-name/claude-code-statusline
# ═══════════════════════════════════════════════════════════

cat | PYTHONIOENCODING=utf-8 python -c "
import sys, json, subprocess, shutil
sys.stdout.reconfigure(encoding='utf-8')

try:
    d = json.loads(sys.stdin.read())
except:
    sys.exit(0)

# ═══ ANSI 颜色 ═══
E  = chr(27)
RST  = f'{E}[0m'
BOLD = f'{E}[1m'
DIM  = f'{E}[2m'

FG = {
    'blk': f'{E}[30m', 'red': f'{E}[31m', 'grn': f'{E}[32m',
    'yel': f'{E}[33m', 'blu': f'{E}[34m', 'mag': f'{E}[35m',
    'cyn': f'{E}[36m', 'wht': f'{E}[37m', 'gry': f'{E}[90m',
}
FG2 = lambda n: f'{E}[38;5;{n}m'
BG2 = lambda n: f'{E}[48;5;{n}m'

# ═══ 数据提取 ═══
model = d.get('model',{}).get('display_name','') or ''
cw    = d.get('context_window',{})
up    = cw.get('used_percentage')
ws    = cw.get('context_window_size')
ci    = (cw.get('current_usage') or {}).get('input_tokens')
co    = (cw.get('current_usage') or {}).get('output_tokens')
cr    = (cw.get('current_usage') or {}).get('cache_read_input_tokens')
rl    = ((d.get('rate_limits') or {}).get('five_hour') or {}).get('used_percentage')
vm    = (d.get('vim') or {}).get('mode','') or ''
cdir  = (d.get('workspace') or {}).get('current_dir','') or ''

# ═══ 数字格式化 ═══
def fmt(n):
    if not n: return ''
    n = int(float(n))
    if n >= 1000000: return f'{n/1000000:.1f}M'
    if n >= 1000:    return f'{n/1000:.1f}K'
    return str(n)

# ═══ 进度条（20格，渐变色）══
ctx = ''
if up is not None and up != '':
    pct = float(up)
    filled = int(pct / 5)       # 20格，每格5%
    empty  = 20 - filled

    # 渐变色：绿 → 黄 → 橙 → 红
    if pct < 50:
        bar_color = FG2(82)   # 亮绿
    elif pct < 70:
        bar_color = FG2(220)  # 金黄
    elif pct < 85:
        bar_color = FG2(208)  # 橙色
    else:
        bar_color = FG2(196)  # 鲜红

    pct_color = FG2(252)      # 浅灰数字
    dim_color = FG2(240)      # 暗灰空白

    bar = f'{bar_color}{BOLD}' + '#' * filled \
        + f'{dim_color}'       + '-' * empty  \
        + RST

    warn = ''
    if pct >= 80:
        warn = f' {FG2(196)}{BOLD}!!{RST}'

    ctx = f'{FG2(249)}CTX {RST}{FG2(245)}[{RST}{bar}{FG2(245)}] {RST}{pct_color}{pct:.1f}%{RST}{warn}'

# ═══ Token 消耗 ═══
tok = ''
if ci and int(float(ci)) > 0:
    tok_in  = f'{FG2(117)}{fmt(ci)}{RST}'     # 浅蓝
    tok_out = f'{FG2(214)}{fmt(co)}{RST}'     # 橙色
    tok = f'{FG2(249)}in:{RST}{tok_in} {FG2(249)}out:{RST}{tok_out}'
    if cr and int(float(cr)) > 0:
        tok_cr = f'{FG2(114)}{fmt(cr)}{RST}'  # 绿色
        tok += f' {FG2(249)}cache:{RST}{tok_cr}'

# ═══ 窗口大小 ═══
win = ''
if ws:
    win = f'{FG2(249)}win:{RST}{FG2(252)}{fmt(ws)}{RST}'

# ═══ 目录 ═══
sdir = ''
if cdir:
    parts = cdir.replace(chr(92), '/').split('/')
    sdir = parts[-1] if len(parts) > 1 else cdir
    sdir = f'{FG2(117)}{BOLD}{sdir}{RST}'

# ═══ Git ═══
branch = ''
try:
    b = subprocess.check_output(
        ['git', '-c', 'core.fsmonitor=', 'rev-parse', '--abbrev-ref', 'HEAD'],
        stderr=subprocess.DEVNULL, cwd=cdir or None
    ).decode().strip()
    if b:
        dirty = subprocess.check_output(
            ['git', '-c', 'core.fsmonitor=', 'status', '--porcelain'],
            stderr=subprocess.DEVNULL, cwd=cdir or None
        ).decode().strip()
        icon = chr(9733) if dirty else chr(9734)  # ★ vs ☆
        color = FG2(214) if dirty else FG2(114)   # 橙 vs 绿
        branch = f'{color}{BOLD}{icon} {b}{RST}'
except:
    pass

# ═══ 5h 用量 ═══
rate = ''
if rl:
    rv = int(float(rl))
    if rv < 50:
        rc = FG2(114)
    elif rv < 75:
        rc = FG2(220)
    else:
        rc = FG2(196)
    rate = f'{FG2(249)}5h:{RST}{rc}{BOLD}{rv}%{RST}'

# ═══ 模型名 ═══
model_s = f'{FG2(141)}{BOLD}{model}{RST}' if model else ''

# ═══ Vim ═══
vim_s = f'{FG2(208)}[{vm}]{RST}' if vm else ''

# ═══ 分隔符 ═══
SEP = f' {FG2(240)}{chr(9474)}{RST} '  # 灰色 │

# ═══ 组装 ═══
parts_out = []
if model_s:  parts_out.append(model_s)
if branch:   parts_out.append(branch)
if sdir:     parts_out.append(sdir)
if win:      parts_out.append(win)
if ctx:      parts_out.append(ctx)
if tok:      parts_out.append(tok)
if rate:     parts_out.append(rate)
if vim_s:    parts_out.append(vim_s)

print(SEP.join(parts_out), end='')
"
