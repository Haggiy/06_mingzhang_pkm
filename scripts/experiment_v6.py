"""
v6 全量渐进学习 — 16,021条, 低置信实际调DeepSeek API, 保存完整结果
"""

import csv, json, time, concurrent.futures, random, os
from collections import defaultdict
from urllib import request
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder, OneHotEncoder
from scipy.sparse import hstack, csr_matrix

API_BASE = "https://api.deepseek.com"
API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
MODEL = "deepseek-chat"
THRESHOLD = 0.8
AMOUNT_BINS = [0,1,3,5,8,10,15,20,30,50,100,200,500,float("inf")]
random.seed(42); np.random.seed(42)

if not API_KEY:
    raise RuntimeError("请先设置 DEEPSEEK_API_KEY 环境变量")

SYSTEM_PROMPT = """你是个人复式记账分类助手。严格返回JSON。

# 科目体系
三级科目: 会计要素 → 收付类型 → 类型明细。类型明细必须唯一归属一个收付类型。

# 支出类
生活必要开支 — 衣食住行、日常维持型开支。明细: 伙食费、交通通信费、其他必要家用、宠物养育费、必要着装费、房租费
文娱游购开支 — 享乐、体验、消费型开支。明细: 饮食游乐费、日常购物费、大件购置费
投资自身开支 — 成长型开支。对自身能力和状态的投入，不是金融投资。明细: 教育费、图书费、办公文印费、健身训练费
其他必要开支 — 责任、保障、关系义务型开支。明细: 人情费、医疗费、父母亲人赡养费
财务费用开支 — 资金周转/金融服务产生的成本与损失。明细: 金融利息支出、金融手续费与罚款、账单套现

# 收入类
工作收入 — 劳动所得。明细: 工资、奖金、兼职收入
理财收入 — 金融资产已实现收益。明细: 货币理财收入
其他收入 — 受限口袋科目。明细: 其他收入、父母资助、亲朋借款

# 资产类
资产类支出 — 资金转化为资产或权益，不是当期消费。明细: 长期待摊费用、其他资产类支出、应收账款、应付账款

# 负债类
负债类增记 — 负债形成。明细: 账单补记、账单分期
负债类减记 — 负债偿还。明细: 账单还款"""


def load_data():
    # 原始账单
    raw = list(csv.DictReader(open("docs/data/合并原始账单.csv", encoding="utf-8-sig")))
    # 已匹配标签
    matched_map = {}
    with open("docs/data/匹配结果.csv", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r["匹配状态"] == "匹配成功":
                key = (r["原始_交易时间"].strip(), r["原始_金额"].strip(), r["原始_交易对方"].strip())
                matched_map[key] = {
                    "收付类型": r["流水_收付类型"].strip(),
                    "类型明细": r["流水_类型明细"].strip(),
                }
    # LLM 缓存 (v3)
    llm_cache = {}
    v3 = list(csv.DictReader(open("docs/data/llm_experiment_v3.csv", encoding="utf-8-sig")))
    for r in v3:
        if r["API状态"] != "成功": continue
        key = (r["交易对方"].strip(), r["商品说明"].strip(), r["金额"].strip())
        llm_cache[key] = (r["LLM_收付类型"].strip(), r["LLM_类型明细"].strip())
    return raw, matched_map, llm_cache


def build_features(train_rows):
    n = len(train_rows)
    cp = [r["交易对方"].strip()[:100] for r in train_rows]
    pd = [r["商品说明"].strip()[:200] for r in train_rows]
    tx = [r["平台交易分类"].strip()[:50] for r in train_rows]

    vec_cp = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=2000, sublinear_tf=True)
    vec_pd = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=2000, sublinear_tf=True)
    vec_tx = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,3), max_features=500, sublinear_tf=True)
    X_cp = vec_cp.fit_transform(cp); X_pd = vec_pd.fit_transform(pd); X_tx = vec_tx.fit_transform(tx)

    n_bins = len(AMOUNT_BINS)
    data, ri, ci = [], [], []
    for i, r in enumerate(train_rows):
        try: a = abs(float(r["金额"]))
        except: a = 0
        bi = n_bins - 1
        for j, u in enumerate(AMOUNT_BINS):
            if a <= u: bi = j; break
        data.append(1.0); ri.append(i); ci.append(bi)
        dm = {"支出": n_bins, "收入": n_bins + 1, "不计收支": n_bins + 2}
        data.append(1.0); ri.append(i); ci.append(dm.get(r.get("收/支","").strip(), n_bins + 2))
    X_a = csr_matrix((data, (ri, ci)), shape=(n, n_bins + 3))

    merch_enc = OneHotEncoder(sparse_output=True, handle_unknown="ignore", min_frequency=1)
    X_m = merch_enc.fit_transform([[r["交易对方"].strip()] for r in train_rows])

    return hstack([X_cp, X_pd, X_tx, X_a, X_m]), (vec_cp, vec_pd, vec_tx), merch_enc


def build_user_prompt(row):
    return f"""待分类账单:
- 交易对方: {row['交易对方']}
- 商品说明: {row['商品说明']}
- 平台分类: {row['平台交易分类']}
- 金额: {row['金额']}
- 收/支: {row.get('收/支','')}

返回JSON: {{"paymentType":"","typeDetail":"","confidence":0.9,"reason":""}}"""


def call_llm(row):
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": build_user_prompt(row)},
        ],
        "temperature": 0.1, "max_tokens": 200,
        "response_format": {"type": "json_object"},
    }).encode("utf-8")
    try:
        req = request.Request(f"{API_BASE}/v1/chat/completions", data=body,
            headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"})
        with request.urlopen(req, timeout=45) as resp:
            r = json.loads(resp.read())
            c = r["choices"][0]["message"]["content"].strip()
            return json.loads(c), r.get("usage", {})
    except Exception as e:
        return None, {}


def main():
    print("=" * 60)
    print("v6 全量渐进学习 (实际LLM, 分开ngram+onehot, C=0.5)")
    print("=" * 60)

    raw, matched_map, llm_cache = load_data()
    print(f"原始账单: {len(raw):,}  已匹配: {len(matched_map):,}  LLM缓存: {len(llm_cache):,}")

    # 按时间排序
    raw.sort(key=lambda r: r["交易时间"])
    print(f"时间: {raw[0]['交易时间'][:10]} ~ {raw[-1]['交易时间'][:10]}")

    # 冷启动: 前30条已匹配
    seed = []
    remaining = []
    for r in raw:
        key = (r["交易时间"].strip(), r["金额"].strip(), r["交易对方"].strip())
        if len(seed) < 30 and key in matched_map:
            r["收付类型"] = matched_map[key]["收付类型"]
            r["类型明细"] = matched_map[key]["类型明细"]
            r["_is_matched"] = True
            seed.append(r)
        else:
            if key in matched_map:
                r["收付类型"] = matched_map[key]["收付类型"]
                r["类型明细"] = matched_map[key]["类型明细"]
                r["_is_matched"] = True
            else:
                r["收付类型"] = ""
                r["类型明细"] = ""
                r["_is_matched"] = False
            remaining.append(r)

    training_set = list(seed)
    print(f"冷启动: {len(seed)} 条, 待处理: {len(remaining):,}")

    # ── 按月分批 ──
    batches = defaultdict(list)
    for r in remaining:
        batches[r["交易时间"][:7]].append(r)
    batch_keys = sorted(batches.keys())
    print(f"批次: {len(batch_keys)} 个月")

    # ── 输出文件 ──
    out_f = open("docs/data/experiment_v6_results.csv", "w", encoding="utf-8-sig")
    out_cols = ["序号","月份","交易时间","交易对方","商品说明","平台交易分类","收/支","金额",
                "是否已匹配","实际_收付类型","实际_类型明细",
                "本地_收付类型","本地_L1置信度",
                "LLM_收付类型","LLM_类型明细","LLM置信度","LLM原因",
                "最终_收付类型","分类来源","API耗时_ms","API状态"]
    out_w = csv.DictWriter(out_f, fieldnames=out_cols, extrasaction="ignore")
    out_w.writeheader(); out_f.flush()

    # ── 统计 ──
    history = []
    llm_calls_total = 0; api_tokens = 0; api_cost = 0; seq = len(seed)

    for bi, ym in enumerate(batch_keys):
        batch = batches[ym]
        if len(batch) < 3: continue

        # 训练
        labeled = [r for r in training_set if r["收付类型"]]
        if len(labeled) < 5: continue
        X_all, vecs, merch_enc = build_features(labeled)
        le1 = LabelEncoder()
        y_tr = le1.fit_transform([r["收付类型"] for r in labeled])
        model = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=1000, C=0.5, class_weight="balanced", random_state=42)
        model.fit(X_all, y_tr)

        # 批量预测: 构建batch特征(用训练集的vectorizer)
        batch_cp = [r["交易对方"].strip()[:100] for r in batch]
        batch_pd = [r["商品说明"].strip()[:200] for r in batch]
        batch_tx = [r["平台交易分类"].strip()[:50] for r in batch]
        X_b_cp = vecs[0].transform(batch_cp); X_b_pd = vecs[1].transform(batch_pd); X_b_tx = vecs[2].transform(batch_tx)
        n_bins = len(AMOUNT_BINS)
        data, ri, ci = [], [], []
        for i, r in enumerate(batch):
            try: a = abs(float(r["金额"]))
            except: a = 0
            bi = n_bins - 1
            for j, u in enumerate(AMOUNT_BINS):
                if a <= u: bi = j; break
            data.append(1.0); ri.append(i); ci.append(bi)
            dm = {"支出": n_bins, "收入": n_bins + 1, "不计收支": n_bins + 2}
            data.append(1.0); ri.append(i); ci.append(dm.get(r.get("收/支","").strip(), n_bins + 2))
        X_b_a = csr_matrix((data, (ri, ci)), shape=(len(batch), n_bins + 3))
        X_b_m = merch_enc.transform([[r["交易对方"].strip()] for r in batch])
        X_batch = hstack([X_b_cp, X_b_pd, X_b_tx, X_b_a, X_b_m])

        proba = model.predict_proba(X_batch)
        conf = proba.max(axis=1)
        pred = model.predict(X_batch)

        # 收集低置信记录 → 并发调 LLM
        low_conf_indices = [i for i in range(len(batch)) if conf[i] < THRESHOLD]
        llm_results_batch = {}

        if low_conf_indices:
            def fetch_llm(idx):
                row = batch[idx]
                key = (row["交易对方"].strip(), row["商品说明"].strip(), row["金额"].strip())
                # 先查缓存
                if key in llm_cache:
                    return idx, {"paymentType": llm_cache[key][0], "typeDetail": llm_cache[key][1], "confidence": 0.95, "reason": "缓存"}, 0, {}
                # 实际调 API
                result, usage = call_llm(row)
                elapsed = 0
                return idx, result, elapsed, usage

            with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
                futs = {ex.submit(fetch_llm, i): i for i in low_conf_indices}
                for fut in concurrent.futures.as_completed(futs):
                    idx, llm_r, elapsed, usage = fut.result()
                    llm_results_batch[idx] = (llm_r, usage)
                    if usage:
                        api_tokens += usage.get("prompt_tokens", 0) + usage.get("completion_tokens", 0)

        # 处理批次
        batch_local_ok = 0; batch_llm_ok = 0; batch_n_matched = 0; batch_llm_calls = 0
        for i, row in enumerate(batch):
            seq += 1
            is_matched = row["_is_matched"]
            local_l1 = le1.classes_[pred[i]] if pred[i] < len(le1.classes_) else ""
            is_high = conf[i] >= THRESHOLD
            actual_l1 = row.get("收付类型", "")
            actual_l2 = row.get("类型明细", "")

            # 决定最终标签
            if is_high:
                final_l1 = local_l1
                llm_l1 = llm_l2 = llm_conf = llm_reason = ""
                source = "本地高置信"
            else:
                batch_llm_calls += 1
                llm_r, usage = llm_results_batch.get(i, (None, {}))
                if llm_r:
                    llm_l1 = llm_r.get("paymentType", "")
                    llm_l2 = llm_r.get("typeDetail", "")
                    llm_conf = llm_r.get("confidence", 0)
                    llm_reason = llm_r.get("reason", "")
                else:
                    llm_l1 = llm_l2 = llm_reason = ""; llm_conf = 0

                # 用户审核 (80%纠正LLM错误)
                if llm_l1 == actual_l1 or not actual_l1:
                    final_l1 = llm_l1
                elif random.random() < 0.8:
                    final_l1 = actual_l1
                else:
                    final_l1 = llm_l1
                source = "LLM"

            # 统计准确率(仅已匹配)
            if is_matched and actual_l1:
                batch_n_matched += 1
                if local_l1 == actual_l1: batch_local_ok += 1
                if final_l1 == actual_l1: batch_llm_ok += 1

            # 写入结果
            out_w.writerow({
                "序号": seq, "月份": ym,
                "交易时间": row["交易时间"], "交易对方": row["交易对方"],
                "商品说明": row["商品说明"], "平台交易分类": row["平台交易分类"],
                "收/支": row.get("收/支",""), "金额": row["金额"],
                "是否已匹配": "是" if is_matched else "否",
                "实际_收付类型": actual_l1, "实际_类型明细": actual_l2,
                "本地_收付类型": local_l1, "本地_L1置信度": f"{conf[i]:.3f}",
                "LLM_收付类型": llm_l1, "LLM_类型明细": llm_l2,
                "LLM置信度": llm_conf, "LLM原因": llm_reason,
                "最终_收付类型": final_l1, "分类来源": source,
                "API耗时_ms": "", "API状态": "成功" if (is_high or llm_r) else "失败",
            })
            out_f.flush()

            # 加入训练集
            new_row = dict(row)
            new_row["收付类型"] = final_l1
            if not is_high and llm_r and llm_r.get("typeDetail"):
                new_row["类型明细"] = llm_r.get("typeDetail")
            training_set.append(new_row)

        llm_calls_total += batch_llm_calls

        # 记录本批次
        if batch_n_matched > 0:
            history.append({
                "month": ym, "n_batch": len(batch), "n_matched": batch_n_matched,
                "local_acc": batch_local_ok / batch_n_matched,
                "overall_acc": batch_llm_ok / batch_n_matched,
                "high_ratio": (len(batch) - batch_llm_calls) / len(batch),
                "llm_ratio": batch_llm_calls / len(batch),
                "avg_conf": conf.mean(),
            })

        cost_so_far = api_tokens / 1_000_000 * 1.5
        if history:
            h = history[-1]
            print(f"  [{bi+1:3d}/{len(batch_keys)}] {ym} 批{len(batch):4d}条 已匹配{batch_n_matched:4d} | "
                  f"本地:{h.get('local_acc',0):.0%} 整体:{h.get('overall_acc',0):.0%} | "
                  f"高占比:{h.get('high_ratio',0):.0%} LLM:{batch_llm_calls:3d}次 | "
                  f"累计LLM:{llm_calls_total:,} 成本~¥{cost_so_far:.2f}")
        else:
            print(f"  [{bi+1:3d}/{len(batch_keys)}] {ym} 批{len(batch):4d}条 已匹配{batch_n_matched:4d} | "
                  f"(无已匹配数据) | 高占比:{(len(batch)-batch_llm_calls)/len(batch):.0%} LLM:{batch_llm_calls:3d}次")

    out_f.close()

    # ── 汇总 ──
    print(f"\n{'='*60}")
    print(f"v6 汇总")
    print(f"{'='*60}")
    print(f"  总处理: {seq:,} 条  已匹配: {sum(h['n_matched'] for h in history):,}")
    print(f"  累计LLM调用: {llm_calls_total:,} 次")
    print(f"  累计Tokens: {api_tokens:,}  估算成本: ¥{api_tokens/1_000_000*1.5:.2f}")

    stages = [("早期(前6月)", history[:6]), ("中期(6-18月)", history[6:18] if len(history)>=18 else history[6:]), ("后期(18月+)", history[18:] if len(history)>=18 else [])]
    print(f"\n  {'阶段':12s} {'本地acc':>8s} {'整体acc':>8s} {'高占比':>7s} {'LLM率':>7s} {'均置信':>7s}")
    for name, h in stages:
        if not h: continue
        print(f"  {name:12s} {np.mean([x['local_acc'] for x in h]):>7.1%}  {np.mean([x['overall_acc'] for x in h]):>7.1%}  {np.mean([x['high_ratio'] for x in h]):>6.1%}  {np.mean([x['llm_ratio'] for x in h]):>6.1%}  {np.mean([x['avg_conf'] for x in h]):>6.3f}")

    first6 = history[:6]; last6 = history[-6:] if len(history)>=6 else history
    print(f"\n  前6月→后6月: 本地{np.mean([x['local_acc'] for x in first6]):.1%}→{np.mean([x['local_acc'] for x in last6]):.1%}  LLM率{np.mean([x['llm_ratio'] for x in first6]):.1%}→{np.mean([x['llm_ratio'] for x in last6]):.1%}")
    print(f"  保存: docs/data/experiment_v6_results.csv")


if __name__ == "__main__":
    main()
