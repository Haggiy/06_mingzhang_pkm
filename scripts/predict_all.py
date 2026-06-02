"""
用最终模型对所有原始账单做预测，导出供人工核查。

输出: docs/data/预测核查.csv
- 已匹配的: 预测 vs 实际分类对比
- 未匹配的: 仅有预测
"""

import csv, numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from scipy.sparse import hstack, csr_matrix

# ── 加载训练集 ──
train_rows = []
with open("docs/data/训练数据集.csv", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        if row["收付类型"].strip() and row["类型明细"].strip():
            train_rows.append(row)
print(f"训练集: {len(train_rows):,} 条")

# ── 加载所有原始账单 ──
raw_rows = []
with open("docs/data/合并原始账单.csv", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        raw_rows.append(row)
print(f"原始账单: {len(raw_rows):,} 条")

# ── 加载匹配结果 (获取实际分类) ──
actual = {}
with open("docs/data/匹配结果.csv", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        if row["匹配状态"] == "匹配成功":
            key = (row["原始_交易时间"].strip(), row["原始_金额"].strip(), row["原始_交易对方"].strip())
            actual[key] = {
                "收付类型": row["流水_收付类型"].strip(),
                "类型明细": row["流水_类型明细"].strip(),
            }

# ── 构建特征 ──
bins = [0, 1, 3, 5, 8, 10, 15, 20, 30, 50, 100, 200, 500, float("inf")]

def make_features(rows, vec=None):
    texts = [
        f"CP:{r['交易对方'].strip()} PD:{r['商品说明'].strip()} TX:{r['平台交易分类'].strip()}"
        for r in rows
    ]
    if vec is None:
        vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=5000, sublinear_tf=True)
        X_t = vec.fit_transform(texts)
    else:
        X_t = vec.transform(texts)

    n_bins = len(bins)
    data, ri, ci = [], [], []
    for i, r in enumerate(rows):
        try:
            a = abs(float(r["金额"]))
        except ValueError:
            a = 0
        bi = n_bins - 1
        for j, u in enumerate(bins):
            if a <= u: bi = j; break
        data.append(1.0); ri.append(i); ci.append(bi)
        d = r["收/支"].strip()
        dm = {"支出": n_bins, "收入": n_bins + 1}
        data.append(1.0); ri.append(i); ci.append(dm.get(d, n_bins + 2))
    X_a = csr_matrix((data, (ri, ci)), shape=(len(rows), n_bins + 3))
    return hstack([X_t, X_a]), vec

# 构建训练特征 + 训练模型
print("构建特征 + 训练模型...")
le1 = LabelEncoder()
le2 = LabelEncoder()
y1_train = le1.fit_transform([r["收付类型"].strip() for r in train_rows])
y2_train = le2.fit_transform([r["类型明细"].strip() for r in train_rows])

X_train, vec = make_features(train_rows)

# L1
m1 = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=1000,
                         C=1.0, class_weight="balanced", random_state=42)
m1.fit(X_train, y1_train)

# 分层 L2
l2_parents = {}
for r in train_rows:
    l2_parents[r["类型明细"].strip()] = r["收付类型"].strip()

l2_models, l2_encoders = {}, {}
for l1_idx, l1_name in enumerate(le1.classes_):
    mask = y1_train == l1_idx
    if mask.sum() < 5: continue
    l2_labels = sorted(set(le2.classes_[y2_train[mask]]))
    if len(l2_labels) < 2: continue
    enc = LabelEncoder(); enc.fit(l2_labels)
    l2_y = enc.transform([le2.classes_[y2_train[i]] for i in range(len(y1_train)) if mask[i]])
    lm = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=500,
                            C=1.0, class_weight="balanced", random_state=42)
    lm.fit(X_train[mask], l2_y)
    l2_models[l1_name] = lm
    l2_encoders[l1_name] = enc

print(f"  L1: {len(le1.classes_)} 类  L2: {len(l2_models)} 个模型")

# ── 对所有原始账单做预测 ──
print(f"预测 {len(raw_rows):,} 条原始账单...")
X_raw, _ = make_features(raw_rows, vec)

y1_pred = m1.predict(X_raw)
y1_proba = m1.predict_proba(X_raw)
y1_conf = y1_proba.max(axis=1)

# 分层 L2 预测
y2_pred = np.full(len(raw_rows), -1, dtype=int)
y2_conf = np.zeros(len(raw_rows))
for l1_name, model in l2_models.items():
    l1_idx = list(le1.classes_).index(l1_name)
    mask = y1_pred == l1_idx
    if mask.sum() == 0: continue
    pred_local = model.predict(X_raw[mask])
    proba_local = model.predict_proba(X_raw[mask])
    enc = l2_encoders[l1_name]
    for j, li in enumerate(pred_local):
        local_name = enc.classes_[li]
        try:
            global_idx = list(le2.classes_).index(local_name)
            idx_in_mask = np.where(mask)[0][j]
            y2_pred[idx_in_mask] = global_idx
            y2_conf[idx_in_mask] = proba_local[j].max()
        except ValueError:
            pass

# ── 导出 ──
print("导出...")
out_cols = [
    "交易时间", "交易对方", "商品说明", "收/支", "金额",
    "平台交易分类", "来源",
    "预测_收付类型", "预测_L1置信度",
    "预测_类型明细", "预测_L2置信度",
    "实际_收付类型", "实际_类型明细",
    "匹配状态", "核对结果"
]
with open("docs/data/预测核查.csv", "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=out_cols, extrasaction="ignore")
    w.writeheader()

    for i, r in enumerate(raw_rows):
        key = (r["交易时间"].strip(), r["金额"].strip(), r["交易对方"].strip())
        act = actual.get(key, {})

        l1_pred_name = le1.classes_[y1_pred[i]] if y1_pred[i] >= 0 else ""
        l2_pred_name = le2.classes_[y2_pred[i]] if y2_pred[i] >= 0 else ""

        l1_conf_val = round(float(y1_conf[i]), 3)
        l2_conf_val = round(float(y2_conf[i]), 3) if y2_pred[i] >= 0 else 0

        # 判断预测是否正确
        if act:
            l1_correct = "✓" if l1_pred_name == act["收付类型"] else "✗"
            l2_correct = "✓" if l2_pred_name == act["类型明细"] else "✗"
            check_status = f"L1{l1_correct} L2{l2_correct}"
        else:
            check_status = "无实际分类"

        w.writerow({
            "交易时间": r["交易时间"],
            "交易对方": r["交易对方"],
            "商品说明": r["商品说明"],
            "收/支": r["收/支"],
            "金额": r["金额"],
            "平台交易分类": r["平台交易分类"],
            "来源": r["来源"],
            "预测_收付类型": l1_pred_name,
            "预测_L1置信度": l1_conf_val,
            "预测_类型明细": l2_pred_name,
            "预测_L2置信度": l2_conf_val,
            "实际_收付类型": act.get("收付类型", ""),
            "实际_类型明细": act.get("类型明细", ""),
            "匹配状态": "已匹配" if act else "未匹配",
            "核对结果": check_status,
        })

# ── 统计 ──
total = len(raw_rows)
matched = sum(1 for _ in [None] if False)  # placeholder
predictable = (y2_pred >= 0).sum()
high_l1 = (y1_conf >= 0.6).sum()
high_l2 = (y2_conf >= 0.6).sum()

print(f"\n导出完成: docs/data/预测核查.csv")
print(f"  总计: {total:,} 条")
print(f"  已匹配(有实际分类): {sum(1 for r in raw_rows if actual.get((r['交易时间'].strip(), r['金额'].strip(), r['交易对方'].strip()))):,} 条")
print(f"  L1 预测: {len(le1.classes_)} 类  L2 预测: {len(le2.classes_)} 类")
print(f"  高置信 L1(≥0.6): {high_l1:,} ({high_l1/total:.1%})")
print(f"  高置信 L2(≥0.6): {high_l2:,} ({high_l2/total:.1%})")
