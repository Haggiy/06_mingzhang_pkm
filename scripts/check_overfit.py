"""过拟合检测"""
import csv, numpy as np
from datetime import datetime
from sklearn.linear_model import LogisticRegression
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import accuracy_score
from scipy.sparse import hstack, csr_matrix

rows = []
with open("docs/data/训练数据集.csv", encoding="utf-8-sig") as f:
    for row in csv.DictReader(f):
        if row["收付类型"].strip() and row["类型明细"].strip():
            rows.append(row)

print(f"样本: {len(rows)}")

# ── 核心特征构建函数 ──
def make_features(rows, use_pm=False):
    parts = []

    # 文本 n-gram
    texts = []
    for r in rows:
        s = f"CP:{r['交易对方'].strip()} PD:{r['商品说明'].strip()} TX:{r['平台交易分类'].strip()}"
        if use_pm:
            s += f" PM:{r['收付款方式'].strip()}"
        texts.append(s)
    vec = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=5000, sublinear_tf=True)
    parts.append(vec.fit_transform(texts))

    # 商户哈希
    data, ri, ci = [], [], []
    for i, r in enumerate(rows):
        n = r["交易对方"].strip()
        if n and n != "/":
            data.append(1.0); ri.append(i); ci.append(abs(hash("M_"+n)) % 512)
    parts.append(csr_matrix((data, (ri, ci)), shape=(len(rows), 512)))

    # 金额
    bins = [0,1,3,5,8,10,15,20,30,50,100,200,500,float("inf")]
    data2, ri2, ci2 = [], [], []
    for i, r in enumerate(rows):
        a = abs(float(r["金额"]))
        bi = len(bins)-1
        for j,u in enumerate(bins):
            if a<=u: bi=j; break
        data2.append(1.0); ri2.append(i); ci2.append(bi)
        dm = {"支出":len(bins),"收入":len(bins)+1}
        data2.append(1.0); ri2.append(i); ci2.append(dm.get(r["收/支"].strip(), len(bins)+2))
    parts.append(csr_matrix((data2, (ri2, ci2)), shape=(len(rows), len(bins)+3)))

    return hstack(parts)

X = make_features(rows, use_pm=True)
le1 = LabelEncoder()
y1 = le1.fit_transform([r["收付类型"].strip() for r in rows])
ts = [r["交易时间"] for r in rows]
si = sorted(range(len(ts)), key=lambda i: ts[i])
sp = int(len(si) * 0.8)
tr, te = si[:sp], si[sp:]

print("=" * 65)
print("1. 训练集 vs 测试集")
print("=" * 65)

for c_val, label in [(0.01, "强正则"), (1.0, "中等"), (10.0, "v3最优"), (50.0, "极弱正则")]:
    m = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=1000,
                           C=c_val, class_weight="balanced", random_state=42)
    m.fit(X[tr], y1[tr])
    tr_a = accuracy_score(y1[tr], m.predict(X[tr]))
    te_a = accuracy_score(y1[te], m.predict(X[te]))
    gap = tr_a - te_a
    flag = " ⚠️" if gap > 0.10 else (" ✓" if gap < 0.05 else "")
    print(f"  C={c_val:5.2f} ({label:5s}): train={tr_a:.1%}  test={te_a:.1%}  gap={gap:+.1%}{flag}")

print()
print("=" * 65)
print("2. 不同时间切分的稳定性")
print("=" * 65)
for ratio in [0.70, 0.75, 0.80, 0.85]:
    sp2 = int(len(si) * ratio)
    tr2, te2 = si[:sp2], si[sp2:]
    m = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=1000,
                           C=10.0, class_weight="balanced", random_state=42)
    m.fit(X[tr2], y1[tr2])
    acc = accuracy_score(y1[te2], m.predict(X[te2]))
    print(f"  训练{ratio:.0%} / 测试{1-ratio:.0%}: {acc:.1%}  (n_test={len(te2)})")

print()
print("=" * 65)
print("3. 消融实验 — 逐组添加特征 (C=1.0, 无 balanced)")
print("=" * 65)

# 构建各版本
texts_base = [f"CP:{r['交易对方'].strip()} PD:{r['商品说明'].strip()} TX:{r['平台交易分类'].strip()}" for r in rows]
vec_b = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=5000, sublinear_tf=True)
Xb = vec_b.fit_transform(texts_base)

bins = [0,1,3,5,8,10,15,20,30,50,100,200,500,float("inf")]
data_a, ri_a, ci_a = [], [], []
for i, r in enumerate(rows):
    a = abs(float(r["金额"])); bi = len(bins)-1
    for j,u in enumerate(bins):
        if a<=u: bi=j; break
    data_a.append(1.0); ri_a.append(i); ci_a.append(bi)
    dm = {"支出":len(bins),"收入":len(bins)+1}
    data_a.append(1.0); ri_a.append(i); ci_a.append(dm.get(r["收/支"].strip(), len(bins)+2))
Xa = csr_matrix((data_a, (ri_a, ci_a)), shape=(len(rows), len(bins)+3))

data_m, ri_m, ci_m = [], [], []
for i, r in enumerate(rows):
    n = r["交易对方"].strip()
    if n and n != "/":
        data_m.append(1.0); ri_m.append(i); ci_m.append(abs(hash("M_"+n)) % 512)
Xm = csr_matrix((data_m, (ri_m, ci_m)), shape=(len(rows), 512))

data_x, ri_x, ci_x = [], [], []
for i, r in enumerate(rows):
    n = r["交易对方"].strip(); tx = r["平台交易分类"].strip()
    if n and n != "/":
        data_x.append(1.0); ri_x.append(i); ci_x.append(abs(hash(f"X_{n}_{tx}")) % 512)
Xx = csr_matrix((data_x, (ri_x, ci_x)), shape=(len(rows), 512))

data_t, ri_t, ci_t = [], [], []
for i, r in enumerate(rows):
    try:
        dt = datetime.strptime(r["交易时间"].strip(), "%Y-%m-%d %H:%M:%S")
    except: continue
    data_t.append(1.0); ri_t.append(i); ci_t.append(dt.weekday())
    h = dt.hour
    tod = 0 if 6<=h<10 else (1 if 10<=h<14 else (2 if 14<=h<20 else 3))
    data_t.append(1.0); ri_t.append(i); ci_t.append(7+tod)
    d = dt.day
    mseg = 0 if d<=10 else (1 if d<=20 else 2)
    data_t.append(1.0); ri_t.append(i); ci_t.append(11+mseg)
Xt = csr_matrix((data_t, (ri_t, ci_t)), shape=(len(rows), 14))

texts_pm = [f"CP:{r['交易对方'].strip()} PD:{r['商品说明'].strip()} TX:{r['平台交易分类'].strip()} PM:{r['收付款方式'].strip()}" for r in rows]
vec_pm = TfidfVectorizer(analyzer="char_wb", ngram_range=(2,4), max_features=5000, sublinear_tf=True)
Xpm = vec_pm.fit_transform(texts_pm)

versions = [
    ("仅n-gram+金额 (v1基线)",  hstack([Xb, Xa])),
    ("+收付款方式",              hstack([Xpm, Xa])),
    ("+商户哈希 (512维)",        hstack([Xpm, Xa, Xm])),
    ("+交互特征 (512维)",        hstack([Xpm, Xa, Xm, Xx])),
    ("+时间特征 (14维) = v3特征", hstack([Xpm, Xa, Xm, Xx, Xt])),
]
base_acc = None
for name, Xv in versions:
    m = LogisticRegression(multi_class="multinomial", solver="lbfgs", max_iter=500,
                           C=1.0, random_state=42)
    m.fit(Xv[tr], y1[tr])
    acc = accuracy_score(y1[te], m.predict(Xv[te]))
    if base_acc is None:
        base_acc = acc
        print(f"  {name:32s}  {acc:.1%}  (基线)")
    else:
        delta = acc - base_acc
        print(f"  {name:32s}  {acc:.1%}  ({delta:+.1%})")
