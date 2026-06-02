"""
v5 渐进学习实验 v2 — 加入商户 onehot 特征
"""

import csv, random, numpy as np
from collections import defaultdict
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder, OneHotEncoder
from sklearn.metrics import accuracy_score
from scipy.sparse import hstack, csr_matrix

THRESHOLD = 0.8
USER_CORRECTION_RATE = 0.8
AMOUNT_BINS = [0, 1, 3, 5, 8, 10, 15, 20, 30, 50, 100, 200, 500, float("inf")]
random.seed(42)
np.random.seed(42)

# ── 加载 ──
all_rows = []
with open("docs/data/训练数据集.csv", encoding="utf-8-sig") as f:
    for r in csv.DictReader(f):
        if r["收付类型"].strip() and r["类型明细"].strip():
            all_rows.append(r)
all_rows.sort(key=lambda r: r["交易时间"])

# LLM 缓存
llm_map = {}
v3_rows = list(csv.DictReader(open("docs/data/llm_experiment_v3.csv", encoding="utf-8-sig")))
for r in v3_rows:
    if r["API状态"] != "成功": continue
    key = (r["交易对方"].strip(), r["商品说明"].strip(), r["金额"].strip())
    llm_map[key] = (r["LLM_收付类型"].strip(), r["LLM_类型明细"].strip())

print(f"数据: {len(all_rows)} 条, LLM缓存: {len(llm_map)} 条")


# ── 特征构建 (每批次重建) ──
def build_features(train_rows, batch_rows):
    """用 train_rows fit encoder, 然后 transform train + batch。三路独立 ngram + 商户 onehot。"""
    n_tr = len(train_rows); n_ba = len(batch_rows)
    all_r = train_rows + batch_rows

    # 三路独立 ngram
    cp_texts = [r["交易对方"].strip() for r in all_r]
    pd_texts = [r["商品说明"].strip() for r in all_r]
    tx_texts = [r["平台交易分类"].strip() for r in all_r]

    vec_cp = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=2000, sublinear_tf=True)
    vec_pd = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=2000, sublinear_tf=True)
    vec_tx = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,3), max_features=500, sublinear_tf=True)
    X_cp = vec_cp.fit_transform(cp_texts)
    X_pd = vec_pd.fit_transform(pd_texts)
    X_tx = vec_tx.fit_transform(tx_texts)

    # 金额
    n_bins = len(AMOUNT_BINS)
    data, ri, ci = [], [], []
    for i, r in enumerate(all_r):
        try: a = abs(float(r["金额"]))
        except: a = 0
        bi = n_bins - 1
        for j, u in enumerate(AMOUNT_BINS):
            if a <= u: bi = j; break
        data.append(1.0); ri.append(i); ci.append(bi)
        dm = {"支出": n_bins, "收入": n_bins + 1}
        data.append(1.0); ri.append(i); ci.append(dm.get(r["收/支"].strip(), n_bins + 2))
    X_a = csr_matrix((data, (ri, ci)), shape=(len(all_r), n_bins + 3))

    # 商户 onehot
    merch_enc = OneHotEncoder(sparse_output=True, handle_unknown="ignore", min_frequency=1)
    X_m = merch_enc.fit_transform([[r["交易对方"].strip()] for r in all_r])

    X_all = hstack([X_cp, X_pd, X_tx, X_a, X_m])
    return X_all[:n_tr], X_all[n_tr:], (vec_cp, vec_pd, vec_tx), merch_enc


# ── 冷启动 ──
COLD_START = 30
seed_rows = all_rows[:COLD_START]
training_set = list(seed_rows)

# 按月分批
remaining = all_rows[COLD_START:]
batches = defaultdict(list)
for r in remaining:
    batches[r["交易时间"][:7]].append(r)
batch_keys = sorted(batches.keys())

print(f"冷启动: {COLD_START} 条, 批次: {len(batch_keys)} 个月")


# ── 渐进模拟 ──
history = []

for bi, ym in enumerate(batch_keys):
    batch = batches[ym]
    if len(batch) < 3: continue

    # 构建特征
    X_tr, X_ba, vec, merch_enc = build_features(training_set, batch)

    # 训练
    le1 = LabelEncoder()
    y_tr = le1.fit_transform([r["收付类型"].strip() for r in training_set])
    model = LogisticRegression(
        multi_class="multinomial", solver="lbfgs", max_iter=1000,
        C=0.5, class_weight="balanced", random_state=42,
    )
    model.fit(X_tr, y_tr)

    # 预测
    proba = model.predict_proba(X_ba)
    conf = proba.max(axis=1)
    y_pred = model.predict(X_ba)

    n_batch = len(batch)
    n_high = (conf >= THRESHOLD).sum()
    n_low = n_batch - n_high
    local_ok = 0; llm_ok = 0; llm_calls = 0

    for i in range(n_batch):
        actual_label = batch[i]["收付类型"].strip()
        pred_label = le1.classes_[y_pred[i]]
        is_high = conf[i] >= THRESHOLD

        # 决定最终标签
        if is_high:
            final_label = pred_label
        else:
            llm_calls += 1
            key = (batch[i]["交易对方"].strip(), batch[i]["商品说明"].strip(), batch[i]["金额"].strip())
            llm_label = llm_map[key][0] if key in llm_map else actual_label
            if llm_label == actual_label:
                final_label = llm_label
            elif random.random() < USER_CORRECTION_RATE:
                final_label = actual_label
            else:
                final_label = llm_label

        if pred_label == actual_label: local_ok += 1
        if final_label == actual_label: llm_ok += 1

        # 加入训练集
        new_row = dict(batch[i])
        new_row["收付类型"] = final_label
        if not is_high:
            key = (batch[i]["交易对方"].strip(), batch[i]["商品说明"].strip(), batch[i]["金额"].strip())
            if key in llm_map:
                llm_detail = llm_map[key][1]
                actual_detail = batch[i]["类型明细"].strip()
                if llm_detail == actual_detail:
                    new_row["类型明细"] = llm_detail
                elif random.random() < USER_CORRECTION_RATE:
                    new_row["类型明细"] = actual_detail
                else:
                    new_row["类型明细"] = llm_detail
        training_set.append(new_row)

    history.append({
        "batch": bi + 1, "month": ym,
        "n_batch": n_batch, "n_training": len(training_set) - n_batch,
        "local_acc": local_ok / n_batch,
        "overall_acc": llm_ok / n_batch,
        "high_ratio": n_high / n_batch,
        "avg_conf": conf.mean(),
        "llm_calls": llm_calls,
        "llm_ratio": llm_calls / n_batch,
    })


# ── 输出 ──
print(f"\n{'='*75}")
print(f"v5 分开ngram+商户onehot C=0.5 渐进学习 (共{len(history)}个月)")
print(f"{'='*75}")

stages = [
    ("早期(前6月)", history[:6]),
    ("中期(6-18月)", history[6:18] if len(history) >= 18 else history[6:]),
    ("后期(18月+)", history[18:] if len(history) >= 18 else []),
]

print(f"\n  {'阶段':12s} {'本地acc':>8s} {'整体acc':>8s} {'高占比':>7s} {'LLM率':>7s} {'平均置信':>8s}")
print(f"  {'-'*55}")
for name, h in stages:
    if not h: continue
    print(f"  {name:12s} {np.mean([x['local_acc'] for x in h]):>7.1%}  "
          f"{np.mean([x['overall_acc'] for x in h]):>7.1%}  "
          f"{np.mean([x['high_ratio'] for x in h]):>6.1%}  "
          f"{np.mean([x['llm_ratio'] for x in h]):>6.1%}  "
          f"{np.mean([x['avg_conf'] for x in h]):>7.3f}")

total_llm = sum(x["llm_calls"] for x in history)
total_rec = sum(x["n_batch"] for x in history)

# 趋势
first6 = history[:6] if len(history) >= 6 else history
last6 = history[-6:] if len(history) >= 6 else history
print(f"\n  {'='*75}")
print(f"  趋势 (前6月 → 后6月)")
print(f"  {'='*75}")
print(f"  本地准确率:  {np.mean([x['local_acc'] for x in first6]):.1%} → {np.mean([x['local_acc'] for x in last6]):.1%}")
print(f"  整体准确率:  {np.mean([x['overall_acc'] for x in first6]):.1%} → {np.mean([x['overall_acc'] for x in last6]):.1%}")
print(f"  高置信占比:  {np.mean([x['high_ratio'] for x in first6]):.1%} → {np.mean([x['high_ratio'] for x in last6]):.1%}")
print(f"  LLM调用率:   {np.mean([x['llm_ratio'] for x in first6]):.1%} → {np.mean([x['llm_ratio'] for x in last6]):.1%}")
print(f"  平均置信度:  {np.mean([x['avg_conf'] for x in first6]):.3f} → {np.mean([x['avg_conf'] for x in last6]):.3f}")
print(f"  总LLM调用:   {total_llm}/{total_rec} ({total_llm/total_rec:.1%})")

# 逐月
print(f"\n  {'月':6s} {'批':>4s} {'训练集':>7s} {'本地':>5s} {'整体':>5s} {'高占比':>5s} {'LLM':>4s} {'置信':>5s}")
print(f"  {'-'*50}")
for h in history:
    print(f"  {h['month']:6s} {h['n_batch']:4d} {h['n_training']:7,d} {h['local_acc']:>4.0%} "
          f"{h['overall_acc']:>4.0%} {h['high_ratio']:>4.0%} {h['llm_calls']:4d} {h['avg_conf']:>4.2f}")
