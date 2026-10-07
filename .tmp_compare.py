import re

A = """_allies_within _best_land_cell _cell_dist _check_fear _child_act _end_round _enemies_within _exec_llm_plan _grid_free _idx_of _is_human_side _maybe_llm_plan _poll_next _yumeiren_round_end alive_enemies_of base_usable current dash_dist_of dist human_done human_move human_moved is_charge is_dash is_spread land_aoe result_text self_skill set_rng_seed simulate skill_data skill_range spawn_child spread_cells_of targets_in_range waiting""".split()

TOPKW = ('func ', 'const ', 'var ', 'class_name ', 'extends ', '@')

def extract(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    funcs = {}
    # 找所有顶层声明起始行（行首无空白，且以关键字/@开头）
    defs = []
    for idx, ln in enumerate(lines):
        stripped = ln.lstrip('\t')
        # 顶层：非空白缩进（即行首不是 tab/space）
        if len(ln) == 0 or ln[0] not in ('\t', ' '):
            if ln.startswith('func '):
                m = re.match(r'func\s+([A-Za-z0-9_]+)', ln)
                if m:
                    defs.append((idx, m.group(1)))
    for j, (idx, name) in enumerate(defs):
        end = defs[j+1][0] if j+1 < len(defs) else len(lines)
        raw = lines[idx:end]
        # 只保留：func 定义行 + 缩进的代码行（tab/空格开头）；剔除顶层注释/空行
        body = []
        for ln in raw:
            if len(ln) > 0 and ln[0] in ('\t', ' '):
                body.append(ln)
            elif ln.startswith('func '):
                body.append(ln)
        funcs[name] = body
    return funcs

f1 = extract('scripts/combat/battle.gd')
f2 = extract('scripts/combat/battle_team.gd')

diffs = []
for name in A:
    b1 = f1.get(name)
    b2 = f2.get(name)
    if b1 is None or b2 is None:
        print(f"[MISSING] {name}: gd={b1 is not None} team={b2 is not None}")
        continue
    if b1 == b2:
        print(f"[SAME] {name}")
    else:
        diffs.append(name)
        print(f"[DIFF] {name}")
        for k in range(max(len(b1), len(b2))):
            a = b1[k] if k < len(b1) else '<EOF>'
            b = b2[k] if k < len(b2) else '<EOF>'
            if a != b:
                print(f"   gd: {a!r}")
                print(f"   tm: {b!r}")
                break

print()
print("有差异:", diffs if diffs else "（无）")
