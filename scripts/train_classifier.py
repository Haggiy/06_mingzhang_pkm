"""
训练导入智能分类模型 · 最终版

特征: n-gram 文本 + 细化金额分桶
模型: 分层 L2 + 类别权重平衡 + C=1.0
"""

from __future__ import annotations

import csv, sys, numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import accuracy_score
from scipy.sparse import hstack, csr_matrix

DATA_FILE = "docs/data/训练数据集.csv"
NGRAM_RANGE = (2, 4)
MAX_FEATURES = 5000
CONFIDENCE_THRESHOLD = 0.6
np.random.seed(42)

# 细化金额分桶
AMOUNT_BINS = [0, 1, 3, 5, 8, 10, 15, 20, 30, 50, 100, 200, 500, float("inf")]


def load_data(filepath: str) -> list[dict]:
    rows = []
    with open(filepath, "r", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            if row["收付类型"].strip() and row["类型明细"].strip():
                rows.append(row)
    return rows


def build_features(rows: list[dict]) -> csr_matrix:
    n = len(rows)

    # 文本 n-gram
    texts = [
        f"CP:{r['交易对方'].strip()} PD:{r['商品说明'].strip()} TX:{r['平台交易分类'].strip()}"
        for r in rows
    ]
    vec = TfidfVectorizer(
        analyzer="char_wb", ngram_range=NGRAM_RANGE,
        max_features=MAX_FEATURES, sublinear_tf=True,
    )
    X_text = vec.fit_transform(texts)

    # 金额分桶 + 方向
    n_bins = len(AMOUNT_BINS)
    data, ri, ci = [], [], []
    for i, r in enumerate(rows):
        amt = abs(float(r["金额"]))
        bi = n_bins - 1
        for j, upper in enumerate(AMOUNT_BINS):
            if amt <= upper:
                bi = j
                break
        data.append(1.0); ri.append(i); ci.append(bi)
        d = r["收/支"].strip()
        dm = {"支出": n_bins, "收入": n_bins + 1}
        data.append(1.0); ri.append(i); ci.append(dm.get(d, n_bins + 2))
    X_amount = csr_matrix((data, (ri, ci)), shape=(n, n_bins + 3))

    return hstack([X_text, X_amount])


def class_metrics(y_true, y_pred, label_names):
    results = {}
    for i, name in enumerate(label_names):
        mt = y_true == i; mp = y_pred == i
        tp = (mt & mp).sum(); s = mt.sum(); pc = mp.sum()
        prec = tp / pc if pc > 0 else 0
        rec = tp / s if s > 0 else 0
        f1 = 2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0
        results[name] = (prec, rec, f1, s)
    return results


def main():
    print("=" * 60)
    print("训练导入智能分类模型 · 最终版")
    print("  特征: n-gram + 金额分桶  |  C=1.0  |  分层L2 + balanced")
    print("=" * 60)

    # ── 加载 ──
    print("\n[1/4] 加载数据...")
    rows_all = load_data(DATA_FILE)
    print(f"  有效样本: {len(rows_all):,}")

    # ── 特征 ──
    print("[2/4] 构建特征...")
    X = build_features(rows_all)
    n_bins = len(AMOUNT_BINS)
    print(f"  总维度: {X.shape[1]}  (文本{MAX_FEATURES} + 金额{n_bins+3})")

    le1 = LabelEncoder(); le2 = LabelEncoder()
    y1_all = le1.fit_transform([r["收付类型"].strip() for r in rows_all])
    y2_all = le2.fit_transform([r["类型明细"].strip() for r in rows_all])
    print(f"  L1: {len(le1.classes_)} 类  L2: {len(le2.classes_)} 类")

    # ── 时间划分 ──
    print("[3/4] 时间划分 (80/20)...")
    ts = [r["交易时间"] for r in rows_all]
    si = sorted(range(len(ts)), key=lambda i: ts[i])
    sp = int(len(si) * 0.8)
    train_idx = si[:sp]; test_idx = si[sp:]
    print(f"  训练: {len(train_idx):,}  测试: {len(test_idx):,}")

    X_tr, X_te = X[train_idx], X[test_idx]
    y1_tr, y1_te = y1_all[train_idx], y1_all[test_idx]
    y2_tr, y2_te = y2_all[train_idx], y2_all[test_idx]

    # ── Level 1 ──
    print("\n[4/4] 训练...")
    print("\n  ─── Level 1: 收付类型 ───")
    m1 = LogisticRegression(
        multi_class="multinomial", solver="lbfgs", max_iter=1000,
        C=1.0, class_weight="balanced", random_state=42,
    )
    m1.fit(X_tr, y1_tr)

    # 训练集准确率(检查过拟合)
    tr_acc = accuracy_score(y1_tr, m1.predict(X_tr))

    y1_pred = m1.predict(X_te)
    y1_proba = m1.predict_proba(X_te)
    y1_conf = y1_proba.max(axis=1)

    acc1 = accuracy_score(y1_te, y1_pred)
    high1 = y1_conf >= CONFIDENCE_THRESHOLD
    acc1h = accuracy_score(y1_te[high1], y1_pred[high1]) if high1.any() else 0

    print(f"  训练: {tr_acc:.1%}  测试: {acc1:.1%}  (间隔: {tr_acc-acc1:+.1%})")
    print(f"  高置信(≥{CONFIDENCE_THRESHOLD}): {acc1h:.1%} (覆盖{high1.mean():.1%})")

    l1_metrics = class_metrics(y1_te, y1_pred, le1.classes_)
    print(f"\n  {'类别':18s} {'f1':>6s} {'prec':>6s} {'rec':>6s} {'sup':>6s}")
    print(f"  {'-'*44}")
    for name in sorted(l1_metrics, key=lambda n: -l1_metrics[n][3]):
        p, r, f, s = l1_metrics[name]
        print(f"  {name:18s} {f:6.2f} {p:6.1%} {r:6.1%} {s:6d}")

    # ── 分层 Level 2 ──
    print("\n  ─── Level 2: 类型明细 (分层) ───")

    l2_parents = {}
    for r in rows_all:
        l2_parents[r["类型明细"].strip()] = r["收付类型"].strip()

    l2_models, l2_encoders, l2_test_ix_map = {}, {}, {}
    for l1_idx, l1_name in enumerate(le1.classes_):
        train_mask = y1_tr == l1_idx
        if train_mask.sum() < 5:
            continue
        l2_labels = sorted(set(le2.classes_[y2_tr[train_mask]]))
        if len(l2_labels) < 2:
            continue
        l2_enc = LabelEncoder(); l2_enc.fit(l2_labels)
        l2_train_y = l2_enc.transform([
            le2.classes_[y2_tr[i]] for i in range(len(train_idx)) if train_mask[i]
        ])
        l2_model = LogisticRegression(
            multi_class="multinomial", solver="lbfgs", max_iter=500,
            C=1.0, class_weight="balanced", random_state=42,
        )
        l2_model.fit(X_tr[train_mask], l2_train_y)
        l2_models[l1_name] = l2_model
        l2_encoders[l1_name] = l2_enc
        l2_test_ix_map[l1_name] = np.where(y1_te == l1_idx)[0]

    y2_hier_pred = np.full(len(test_idx), -1)
    y2_hier_conf = np.zeros(len(test_idx), dtype=float)
    for l1_name, model in l2_models.items():
        ix = l2_test_ix_map[l1_name]
        if len(ix) == 0:
            continue
        pred_local = model.predict(X_te[ix])
        proba_local = model.predict_proba(X_te[ix])
        l2_enc = l2_encoders[l1_name]
        for j, li in enumerate(pred_local):
            global_idx = list(le2.classes_).index(l2_enc.classes_[li])
            y2_hier_pred[ix[j]] = global_idx
            y2_hier_conf[ix[j]] = proba_local[j].max()

    valid2 = y2_hier_pred >= 0
    acc2 = accuracy_score(y2_te[valid2], y2_hier_pred[valid2])
    high2 = (y2_hier_conf >= CONFIDENCE_THRESHOLD) & valid2
    acc2h = accuracy_score(y2_te[high2], y2_hier_pred[high2]) if high2.any() else 0

    print(f"  准确率: {acc2:.1%}  高置信: {acc2h:.1%} (覆盖{high2.sum()/valid2.sum():.1%})")

    l2_metrics = class_metrics(y2_te[valid2], y2_hier_pred[valid2], le2.classes_)
    print(f"\n  {'类别':20s} {'f1':>6s} {'prec':>6s} {'rec':>6s} {'sup':>6s}")
    print(f"  {'-'*46}")
    for name in sorted(l2_metrics, key=lambda n: -l2_metrics[n][3]):
        p, r, f, s = l2_metrics[name]
        if s > 0:
            print(f"  {name:20s} {f:6.2f} {p:6.1%} {r:6.1%} {s:6d}")

    # 无测试样本的类
    no_test = [n for n in sorted(l2_metrics, key=lambda n: -l2_metrics[n][3]) if l2_metrics[n][3] == 0]
    if no_test:
        print(f"  (无测试样本: {', '.join(no_test)})")

    # L1正确时L2
    l1_correct = y1_pred == y1_te
    l1c_valid = l1_correct & valid2
    joint = accuracy_score(y2_te[l1c_valid], y2_hier_pred[l1c_valid]) if l1c_valid.any() else 0

    # 各L1类下L2
    print(f"\n  各 L1 类下的 L2 准确率:")
    for l1_name in sorted(l2_models.keys()):
        ix = l2_test_ix_map[l1_name]
        vix = ix[np.isin(ix, np.where(valid2)[0])]
        if len(vix) == 0:
            continue
        acc = (y2_hier_pred[vix] == y2_te[vix]).mean()
        print(f"    {l1_name:12s}: {acc:.1%}  (n={len(vix)})")

    # ── 最终结论 ──
    print()
    print("=" * 60)
    print("最终结论")
    print("=" * 60)
    print(f"  特征维度:    {X.shape[1]} (仅 n-gram + 金额)")
    print(f"  C 值:        1.0")
    print(f"  训练/测试间隔: {tr_acc-acc1:+.1%}")
    print(f"  ─────────────────────────────")
    print(f"  Level 1:     {acc1:.1%}")
    print(f"  Level 2:     {acc2:.1%}")
    print(f"  L1正确时 L2:  {joint:.1%}")
    print(f"  联合准确率:   {acc1 * joint:.1%}")
    print(f"  L1 低置信留空: {(y1_conf < 0.6).mean():.1%}")
    print(f"  L2 低置信留空: {(y2_hier_conf[valid2] < 0.6).mean():.1%}")


if __name__ == "__main__":
    main()
