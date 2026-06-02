"""
双层分类实验 v4 — 完整语义prompt + JSON response_format
"""

import csv, json, time, concurrent.futures, random, os
from collections import defaultdict
from urllib import request

API_BASE = "https://api.deepseek.com"
API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
MODEL = "deepseek-chat"
THRESHOLD = 0.8

if not API_KEY:
    raise RuntimeError("请先设置 DEEPSEEK_API_KEY 环境变量")

SYSTEM_PROMPT = """你是个人复式记账分类助手。严格返回JSON。

# 科目体系

三级科目: 会计要素 → 收付类型 → 类型明细
类型明细必须唯一归属一个收付类型，不跨类复用。

# 支出类（按价值判断主轴）

生活必要开支 — 衣食住行、日常维持型开支。用于维持日常生活基本运行，强调生存型、维持型、日常性。
  明细: 伙食费、交通通信费、其他必要家用、宠物养育费、必要着装费、房租费

文娱游购开支 — 享乐、体验、消费型开支。体现消费欲望、体验需求和生活享受。
  明细: 饮食游乐费、日常购物费、大件购置费

投资自身开支 — 成长型开支。为了提升自己、增强能力、改善长期状态，不是享乐也不是日常生存。"投资"指对自身能力和状态的投入，不是金融投资。
  明细: 教育费、图书费、办公文印费、健身训练费

其他必要开支 — 责任、保障、关系义务型必要开支。不属于衣食住行，不属于享乐，也不属于成长投资，但具有正当性。
  明细: 人情费、医疗费、父母亲人赡养费

财务费用开支 — 因资金周转、金融服务、金融交易或金融资产处置而发生的成本与损失。
  明细: 金融利息支出、金融手续费与罚款、账单套现
  硬规则: 已实现收益进理财收入，已实现亏损进财务费用开支，未实现浮盈浮亏不进流水日记账

# 收入类（按来源分）

工作收入 — 由工作、雇佣关系或劳动活动直接带来的收入。
  明细: 工资、奖金、兼职收入

理财收入 — 金融资产处置时实现的已实现收益。只记录赎回、卖出、处置时的已实现收益。
  明细: 货币理财收入

其他收入 — 不属于工作收入、理财收入，但确实形成收入增加的其他来源。是受限口袋科目。
  明细: 其他收入、父母资助、亲朋借款

# 资产类

资产类支出 — 资金没有被当期消费掉，而是转化为仍然拥有、可持续计量的资产或权益。与普通消费的根本区别：普通消费形成当期消耗，资产类支出形成资产沉淀。
  明细: 长期待摊费用、其他资产类支出、应收账款、应付账款

# 负债类（按生命周期分）

负债类增记 — 负债的形成与来源。
  明细: 账单补记、账单分期

负债类减记 — 负债的偿还与减少。
  明细: 账单还款"""


def load_data():
    train = list(csv.DictReader(open("docs/data/训练数据集.csv", encoding="utf-8-sig")))
    preds = list(csv.DictReader(open("docs/data/预测核查.csv", encoding="utf-8-sig")))
    return train, preds


def build_index(train):
    by_merchant = defaultdict(list); by_tx_type = defaultdict(list)
    for r in train:
        by_merchant[r["交易对方"].strip()].append(r)
        by_tx_type[r["平台交易分类"].strip()].append(r)
    return by_merchant, by_tx_type


def find_similar(row, by_merchant, by_tx_type):
    m = row["交易对方"].strip(); tx = row["平台交易分类"].strip()
    try: amt = abs(float(row["金额"]))
    except: amt = 0
    sim = []
    for r in by_merchant.get(m, [])[:5]:
        if r not in sim: sim.append(r)
    cand = []
    for r in by_tx_type.get(tx, []):
        if r in sim: continue
        try: ra = abs(float(r["金额"]))
        except: ra = 0
        if amt > 0 and 0.3 < ra/amt < 3.0: cand.append(r)
    for r in cand[:3]: sim.append(r)
    return sim[:8]


def build_prompt(row, by_merchant, by_tx_type):
    sim = find_similar(row, by_merchant, by_tx_type)
    fs = "\n\n".join(
        f"示例{i+1}:\n  交易对方: {s['交易对方']}\n  商品说明: {s['商品说明']}\n  平台分类: {s['平台交易分类']}\n  金额: {s['金额']}\n  收/支: {s['收/支']}\n  → 收付类型: {s['收付类型']} | 类型明细: {s['类型明细']}"
        for i, s in enumerate(sim)
    )
    return f"""# 参考示例
{fs}

# 待分类账单
- 交易对方: {row['交易对方']}
- 商品说明: {row['商品说明']}
- 平台分类: {row['平台交易分类']}
- 金额: {row['金额']}
- 收/支: {row['收/支']}

返回JSON: {{"paymentType":"","typeDetail":"","confidence":0.9,"reason":""}}"""


def call_one(row, by_merchant, by_tx_type):
    user_prompt = build_prompt(row, by_merchant, by_tx_type)
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.1,
        "max_tokens": 200,
        "response_format": {"type": "json_object"},
    }).encode("utf-8")
    t0 = time.time()
    try:
        req = request.Request(
            f"{API_BASE}/v1/chat/completions", data=body,
            headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        )
        with request.urlopen(req, timeout=45) as resp:
            r = json.loads(resp.read())
            c = r["choices"][0]["message"]["content"].strip()
            return json.loads(c), time.time() - t0, r.get("usage", {}), None
    except Exception as e:
        return None, time.time() - t0, {}, str(e)


def main():
    print("=" * 60)
    print("v4 实验: 完整语义Prompt + JSON response_format")
    print("=" * 60)

    train, preds = load_data()
    by_merchant, by_tx_type = build_index(train)

    # ── 抽样 (同v3) ──
    matched_all = [r for r in preds if r["匹配状态"] == "已匹配" and r["实际_收付类型"].strip()]
    unmatched_all = [r for r in preds if r["匹配状态"] == "未匹配"]

    random.seed(42)
    low_conf = [r for r in matched_all if float(r["预测_L1置信度"]) < THRESHOLD]
    high_conf = [r for r in matched_all if float(r["预测_L1置信度"]) >= THRESHOLD]
    by_actual_low = defaultdict(list); by_actual_high = defaultdict(list)
    for r in low_conf: by_actual_low[r["实际_收付类型"]].append(r)
    for r in high_conf: by_actual_high[r["实际_收付类型"]].append(r)

    matched_sample = []
    for t in set(list(by_actual_low.keys()) + list(by_actual_high.keys())):
        low_n = min(len(by_actual_low.get(t, [])), max(5, int(450 * len(by_actual_low.get(t, [])) / len(low_conf)))) if by_actual_low.get(t, []) else 0
        high_n = min(len(by_actual_high.get(t, [])), max(2, int(50 * len(by_actual_high.get(t, [])) / len(high_conf)))) if by_actual_high.get(t, []) else 0
        if low_n > 0: matched_sample.extend(random.sample(by_actual_low.get(t, []), low_n))
        if high_n > 0: matched_sample.extend(random.sample(by_actual_high.get(t, []), high_n))
    matched_sample = matched_sample[:500]; random.shuffle(matched_sample)

    by_source_dir = defaultdict(list)
    for r in unmatched_all: by_source_dir[f"{r['来源']}_{r['收/支']}"].append(r)
    unmatched_sample = []
    for k, recs in sorted(by_source_dir.items(), key=lambda x: -len(x[1])):
        n = max(10, int(500 * len(recs) / len(unmatched_all))); n = min(n, len(recs))
        unmatched_sample.extend(random.sample(recs, n))
    unmatched_sample = unmatched_sample[:500]; random.shuffle(unmatched_sample)

    all_samples = matched_sample + unmatched_sample
    print(f"样本: 已匹配{len(matched_sample)} + 未匹配{len(unmatched_sample)} = {len(all_samples)}")

    # ── 并发 ──
    print(f"并发 {len(all_samples)} 条 (max_workers=30)...")
    t0 = time.time(); results = []; pt = ct = 0; errors = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
        futs = {
            ex.submit(call_one, row, by_merchant, by_tx_type): i
            for i, row in enumerate(all_samples)
        }
        for fut in concurrent.futures.as_completed(futs):
            i = futs[fut]; llm_r, elapsed, usage, err = fut.result()
            results.append((i, llm_r, elapsed, usage, err))
            pt += usage.get("prompt_tokens", 0); ct += usage.get("completion_tokens", 0)
            if err: errors.append((i, err, all_samples[i]))
            if (len(results)) % 100 == 0:
                print(f"  [{len(results):4d}/{len(all_samples)}] {time.time()-t0:.0f}s  成功:{len(results)-len(errors)} 失败:{len(errors)}")
    total = time.time() - t0; results.sort(key=lambda x: x[0])

    # ── 已匹配准确率 ──
    n_ok_l1 = n_ok_l2 = n_fail = 0
    for i, llm_r, t, u, err in results:
        if i >= 500: break  # 只看已匹配
        row = matched_sample[i]
        if llm_r is None: n_fail += 1; continue
        if llm_r.get("paymentType", "") == row["实际_收付类型"]: n_ok_l1 += 1
        if llm_r.get("typeDetail", "") == row["实际_类型明细"]: n_ok_l2 += 1
    n_m = min(500, len([r for r in results if r[0] < 500]))
    local_l1_ok = sum(1 for r in matched_sample[:n_m] if r["预测_收付类型"] == r["实际_收付类型"])

    # ── 输出 ──
    ttt = pt + ct; cost_in = pt / 1_000_000 * 1.0; cost_out = ct / 1_000_000 * 2.0
    print(f"\n{'='*60}")
    print(f"v4 结果")
    print(f"{'='*60}")
    print(f"  总耗时:    {total:.1f}s")
    print(f"  成功:      {len(all_samples)-len(errors)}  失败: {len(errors)} ({len(errors)/len(all_samples):.1%})")
    print(f"  Tokens:    {ttt:,}  (avg {ttt/len(all_samples):.0f}/条)")
    print(f"  API成本:   ¥{cost_in+cost_out:.4f}")
    print(f"")
    print(f"  {'':20s} {'本地':>8s} {'LLM':>8s} {'提升':>8s}")
    print(f"  {'L1 准确率':20s} {local_l1_ok/n_m:>7.1%}  {n_ok_l1/n_m:>7.1%}  {(n_ok_l1-local_l1_ok)/n_m:>+7.1%}")
    print(f"  {'L2 准确率':20s} {'-':>8s}  {n_ok_l2/n_m:>7.1%}")
    print(f"  失败率:     {len(errors)/len(all_samples):.1%}")
    print(f"  失败原因:   {errors[0][1][:80] if errors else '无'}")

    # 按类型
    by_type = defaultdict(lambda: {"n": 0, "local": 0, "llm": 0})
    for i, llm_r, t, u, err in results:
        if i >= 500: break
        if llm_r is None: continue
        row = matched_sample[i]; pt_actual = row["实际_收付类型"]
        by_type[pt_actual]["n"] += 1
        if row["预测_收付类型"] == pt_actual: by_type[pt_actual]["local"] += 1
        if llm_r.get("paymentType", "") == pt_actual: by_type[pt_actual]["llm"] += 1
    print(f"\n  按类型:")
    for t_name in sorted(by_type, key=lambda x: -by_type[x]["n"]):
        d = by_type[t_name]
        print(f"    {t_name:12s}: 本地{d['local']}/{d['n']}  LLM{d['llm']}/{d['n']}")


if __name__ == "__main__":
    main()
