"""
双层分类实验 v2

- 置信度阈值 0.8（更多记录进入 LLM 分流）
- LLM 输出置信度 + 分类原因
- 保存完整 LLM 输入
- 扩大样本量到 200 条
"""

from __future__ import annotations

import csv, json, random, time, os
from collections import defaultdict
from typing import Optional
from urllib import request, error

API_BASE = "https://dashscope.aliyuncs.com/compatible-mode/v1"
API_KEY = os.environ.get("DASHSCOPE_API_KEY", "")
MODEL = "deepseek-v4-flash"
THRESHOLD = 0.8
SAMPLE_SIZE = 200

if not API_KEY:
    raise RuntimeError("请先设置 DASHSCOPE_API_KEY 环境变量")

TYPE_DETAIL_MAP = {
    "生活必要开支": ["伙食费", "交通通信费", "宠物养育费", "必要着装费", "房租费", "其他必要家用"],
    "文娱游购开支": ["饮食游乐费", "日常购物费", "大件购置费"],
    "投资自身开支": ["教育费", "图书费", "健身训练费", "办公文印费"],
    "其他必要开支": ["医疗费", "父母亲人赡养费", "人情费", "社保返还"],
    "工作收入": ["工资", "奖金", "兼职收入"],
    "理财收入": ["货币理财收入"],
    "其他收入": ["其他收入", "父母资助", "亲朋借款"],
    "资产类支出": ["长期待摊费用", "其他资产类支出", "应收账款", "应付账款"],
    "负债类增记": ["账单补记", "账单分期"],
    "负债类减记": ["账单还款"],
    "财务费用开支": ["金融利息支出", "金融手续费与罚款", "账单套现"],
}


def load_data():
    train = list(csv.DictReader(open("docs/data/训练数据集.csv", encoding="utf-8-sig")))
    preds = list(csv.DictReader(open("docs/data/预测核查.csv", encoding="utf-8-sig")))
    return train, preds


def build_index(train):
    by_merchant = defaultdict(list)
    by_tx_type = defaultdict(list)
    for r in train:
        by_merchant[r["交易对方"].strip()].append(r)
        by_tx_type[r["平台交易分类"].strip()].append(r)
    return by_merchant, by_tx_type


def find_similar(row, by_merchant, by_tx_type):
    merchant = row["交易对方"].strip()
    tx_type = row["平台交易分类"].strip()
    amount = abs(float(row["金额"]))
    similar = []
    for r in by_merchant.get(merchant, [])[:5]:
        if r not in similar:
            similar.append(r)
    candidates = []
    for r in by_tx_type.get(tx_type, []):
        if r in similar: continue
        r_amt = abs(float(r["金额"]))
        if amount > 0 and 0.3 < r_amt / amount < 3.0:
            candidates.append(r)
    for r in candidates[:3]:
        similar.append(r)
    return similar[:8]


def build_prompt(row, similar):
    type_list = "\n".join(f"  - {t}" for t in TYPE_DETAIL_MAP.keys())

    few_shot_parts = []
    for i, s in enumerate(similar[:8]):
        detail_opts = "、".join(TYPE_DETAIL_MAP.get(s["收付类型"], []))
        few_shot_parts.append(
            f"示例{i+1}:\n"
            f"  交易对方: {s['交易对方']}\n"
            f"  商品说明: {s['商品说明']}\n"
            f"  平台分类: {s['平台交易分类']}\n"
            f"  金额: {s['金额']}\n"
            f"  收/支: {s['收/支']}\n"
            f"  → 收付类型: {s['收付类型']} | 类型明细: {s['类型明细']}"
        )
    few_shot = "\n\n".join(few_shot_parts)

    return f"""根据账单信息判断收付类型和类型明细。参考示例了解分类习惯。

# 可选收付类型及对应类型明细
{chr(10).join(f"- {t}: {', '.join(d)}" for t, d in TYPE_DETAIL_MAP.items())}

# 参考示例
{few_shot}

# 待分类账单
- 交易对方: {row['交易对方']}
- 商品说明: {row['商品说明']}
- 平台分类: {row['平台交易分类']}
- 金额: {row['金额']}
- 收/支: {row['收/支']}

请返回纯JSON（不要markdown代码块）:
{{"paymentType": "收付类型", "typeDetail": "类型明细", "confidence": 0.0-1.0, "reason": "分类依据(一句话)"}}"""


def call_llm(prompt: str, retries: int = 3) -> Optional[dict]:
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "你是个人记账分类助手。严格返回JSON，不要额外文字。类型明细必须属于对应收付类型。"},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.1,
        "max_tokens": 300,
    }).encode("utf-8")

    for attempt in range(retries):
        try:
            req = request.Request(
                f"{API_BASE}/chat/completions", data=body,
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
            )
            with request.urlopen(req, timeout=15) as resp:
                result = json.loads(resp.read())
                content = result["choices"][0]["message"]["content"].strip()
                if content.startswith("```"):
                    content = content.split("\n", 1)[-1]
                    if content.endswith("```"): content = content[:-3]
                return json.loads(content)
        except (error.URLError, json.JSONDecodeError, KeyError) as e:
            if attempt < retries - 1:
                time.sleep(1 * (attempt + 1))
    return None


def main():
    print("=" * 60)
    print(f"双层分类实验 v2 (阈值{THRESHOLD}, {SAMPLE_SIZE}条, 输出置信度+原因)")
    print("=" * 60)

    random.seed(42)
    train, preds = load_data()
    print(f"\n训练集: {len(train):,}  预测结果: {len(preds):,}")

    # ── 低置信度(阈值 0.8) ──
    low_conf = [
        r for r in preds
        if r["匹配状态"] == "已匹配"
        and float(r["预测_L1置信度"]) < THRESHOLD
        and r["实际_收付类型"].strip()
    ]
    print(f"L1 低置信度(阈值{THRESHOLD}): {len(low_conf):,}")

    # ── 同时取样高置信度作为对比 ──
    high_conf = [
        r for r in preds
        if r["匹配状态"] == "已匹配"
        and float(r["预测_L1置信度"]) >= THRESHOLD
        and r["实际_收付类型"].strip()
    ]
    print(f"L1 高置信度(≥{THRESHOLD}): {len(high_conf):,}")

    # 高置信度准确率
    hc_ok = sum(1 for r in high_conf if r["预测_收付类型"] == r["实际_收付类型"])
    print(f"高置信度准确率: {hc_ok}/{len(high_conf)} = {hc_ok/len(high_conf):.1%}")

    # ── 分层抽样 200 条低置信度 ──
    by_actual = defaultdict(list)
    for r in low_conf:
        by_actual[r["实际_收付类型"]].append(r)

    sample = []
    for t, recs in sorted(by_actual.items(), key=lambda x: -len(x[1])):
        n = max(3, int(SAMPLE_SIZE * len(recs) / len(low_conf)))
        n = min(n, len(recs))
        sample.extend(random.sample(recs, n))
    sample = sample[:SAMPLE_SIZE]
    random.shuffle(sample)
    print(f"实验样本: {len(sample)} 条")

    # ── 建立索引 ──
    by_merchant, by_tx_type = build_index(train)

    # ── 打开输出文件 ──
    out_cols = [
        "交易对方", "商品说明", "平台交易分类", "金额", "收/支",
        "实际_L1", "实际_L2", "本地_L1", "本地_L2", "本地_L1置信度",
        "LLM_L1", "LLM_L2", "LLM置信度", "LLM原因",
        "本地L1对", "LLM_L1对", "本地L2对", "LLM_L2对",
        "LLM输入"
    ]
    out_f = open("docs/data/llm_experiment_v2.csv", "w", encoding="utf-8-sig")
    out_w = csv.DictWriter(out_f, fieldnames=out_cols, extrasaction="ignore")
    out_w.writeheader()

    # ── 主循环 ──
    print(f"\n调用 LLM ({MODEL})...")
    results = []
    n_loc_l1 = n_llm_l1 = n_loc_l2 = n_llm_l2 = n_fail = 0

    for i, row in enumerate(sample):
        similar = find_similar(row, by_merchant, by_tx_type)
        prompt = build_prompt(row, similar)
        llm_result = call_llm(prompt)

        local_l1 = row["预测_收付类型"]
        local_l2 = row["预测_类型明细"]
        local_conf = float(row["预测_L1置信度"])
        actual_l1 = row["实际_收付类型"]
        actual_l2 = row["实际_类型明细"]

        if llm_result:
            llm_l1 = llm_result.get("paymentType", "")
            llm_l2 = llm_result.get("typeDetail", "")
            llm_conf = llm_result.get("confidence", 0)
            llm_reason = llm_result.get("reason", "")
        else:
            llm_l1 = llm_l2 = llm_reason = ""
            llm_conf = 0
            n_fail += 1

        loc_l1_ok = local_l1 == actual_l1
        llm_l1_ok = llm_l1 == actual_l1
        loc_l2_ok = local_l2 == actual_l2
        llm_l2_ok = llm_l2 == actual_l2

        if loc_l1_ok: n_loc_l1 += 1
        if llm_l1_ok: n_llm_l1 += 1
        if loc_l2_ok: n_loc_l2 += 1
        if llm_l2_ok: n_llm_l2 += 1

        result_row = {
            "交易对方": row["交易对方"],
            "商品说明": row["商品说明"],
            "平台交易分类": row["平台交易分类"],
            "金额": row["金额"],
            "收/支": row["收/支"],
            "实际_L1": actual_l1,
            "实际_L2": actual_l2,
            "本地_L1": local_l1,
            "本地_L2": local_l2,
            "本地_L1置信度": local_conf,
            "LLM_L1": llm_l1,
            "LLM_L2": llm_l2,
            "LLM置信度": llm_conf,
            "LLM原因": llm_reason,
            "本地L1对": "✓" if loc_l1_ok else "✗",
            "LLM_L1对": "✓" if llm_l1_ok else "✗",
            "本地L2对": "✓" if loc_l2_ok else "✗",
            "LLM_L2对": "✓" if llm_l2_ok else "✗",
            "LLM输入": prompt.replace("\n", "\\n"),
        }
        results.append(result_row)
        out_w.writerow(result_row)
        out_f.flush()

        # 进度
        acc_l = n_llm_l1 / (i+1)
        acc_loc = n_loc_l1 / (i+1)
        llm_info = f"conf={llm_conf:.2f}" if isinstance(llm_conf, (int,float)) and llm_conf > 0 else ""
        print(f"  [{i+1:3d}/{len(sample)}] {row['交易对方'][:22]:22s} | "
              f"本地:{'✓' if loc_l1_ok else '✗'} LLM:{'✓' if llm_l1_ok else '✗'} {llm_info:10s} | "
              f"累计 LLM:{acc_l:.0%} 本地:{acc_loc:.0%}")

        time.sleep(0.3)

    out_f.close()
    n = len(results)

    # ── 统计 ──
    print()
    print("=" * 60)
    print(f"实验结果 (阈值{THRESHOLD}, {n}条)")
    print("=" * 60)
    print(f"  API失败: {n_fail}")
    print()
    print(f"  {'':20s} {'本地':>8s} {'LLM':>8s} {'提升':>8s}")
    print(f"  {'-'*45}")
    print(f"  {'L1 准确率':20s} {n_loc_l1/n:>7.1%}  {n_llm_l1/n:>7.1%}  {(n_llm_l1-n_loc_l1)/n:>+7.1%}")
    print(f"  {'L2 准确率':20s} {n_loc_l2/n:>7.1%}  {n_llm_l2/n:>7.1%}  {(n_llm_l2-n_loc_l2)/n:>+7.1%}")

    fixed_l1 = sum(1 for r in results if r["本地L1对"] == "✗" and r["LLM_L1对"] == "✓")
    broke_l1 = sum(1 for r in results if r["本地L1对"] == "✓" and r["LLM_L1对"] == "✗")
    print(f"\n  LLM 纠正本地错误: {fixed_l1} 条")
    print(f"  LLM 搞错本地正确: {broke_l1} 条")
    print(f"  净提升: {fixed_l1 - broke_l1} 条 ({(fixed_l1 - broke_l1)/n:+.1%})")

    # LLM 平均置信度
    llm_confs = [r["LLM置信度"] for r in results if isinstance(r["LLM置信度"], (int,float)) and r["LLM置信度"] > 0]
    if llm_confs:
        print(f"  LLM 平均置信度: {sum(llm_confs)/len(llm_confs):.3f}")

    # 推算全量
    hc_ratio = len(high_conf) / (len(high_conf) + len(low_conf))
    lc_ratio = len(low_conf) / (len(high_conf) + len(low_conf))
    overall = hc_ratio * (hc_ok/len(high_conf)) + lc_ratio * (n_llm_l1/n)
    print(f"\n  高置信(≥{THRESHOLD})占比: {hc_ratio:.1%} (准确率 {hc_ok/len(high_conf):.1%})")
    print(f"  低置信(<{THRESHOLD})占比: {lc_ratio:.1%} (LLM准确率 {n_llm_l1/n:.1%})")
    print(f"  推算全量 L1 准确率: {overall:.1%}")

    # 按类型
    print(f"\n  按实际收付类型:")
    by_type = defaultdict(lambda: {"n":0, "loc":0, "llm":0})
    for r in results:
        t = r["实际_L1"]
        by_type[t]["n"] += 1
        if r["本地L1对"] == "✓": by_type[t]["loc"] += 1
        if r["LLM_L1对"] == "✓": by_type[t]["llm"] += 1
    for t, d in sorted(by_type.items(), key=lambda x: -x[1]["n"]):
        print(f"    {t:12s}: 本地{d['loc']}/{d['n']}  LLM{d['llm']}/{d['n']}")


if __name__ == "__main__":
    main()
