"""
v6.1 修复版 — 全量渐进学习, L1+L2双层模型 + 严格分类校验 + LLM输出校验+自动重试

修复 v6 的两个问题:
  1. 本地模型增加 L2(类型明细)预测 — 层级模型,每个L1训练独立L2分类器
  2. LLM/ML 输出严格校验 — 非标准分类自动重试(更严格prompt)或回退

机制:
  - 冷启动30条已匹配 → 按月渐进学习
  - L1 模型: 分开ngram(交易对方2000+商品说明2000+平台分类500) + 商户onehot + 金额分桶, C=0.5
  - L2 模型: 每个L1类别独立训练, 同上特征, C=0.3(更强正则化)
  - LLM 调用前查缓存(v3+v6有效结果), 输出后严格校验 → 无效则更严格prompt重试(最多2次)
  - 训练数据清洗: 只有标准分类的记录才能加入训练集
  - L2 回退: LLM L1有效但L2无效时 → 用该L1类别的多数L2
"""

import csv, json, time, concurrent.futures, random, traceback, os
from collections import defaultdict, Counter
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
AMOUNT_BINS = [0, 1, 3, 5, 8, 10, 15, 20, 30, 50, 100, 200, 500, float("inf")]
MAX_LLM_RETRIES = 2
random.seed(42)
np.random.seed(42)

if not API_KEY:
    raise RuntimeError("请先设置 DEEPSEEK_API_KEY 环境变量")

# ═══════════════════════════════════════════════════════
# 标准分类 (权威来源: settings-and-semantics-spec.md)
# ═══════════════════════════════════════════════════════

VALID_L1 = {
    "生活必要开支", "文娱游购开支", "投资自身开支", "其他必要开支", "财务费用开支",
    "工作收入", "理财收入", "其他收入",
    "资产类支出", "负债类增记", "负债类减记",
}

VALID_L2_BY_L1 = {
    "生活必要开支": {"伙食费", "交通通信费", "其他必要家用", "宠物养育费", "必要着装费", "房租费"},
    "文娱游购开支": {"饮食游乐费", "日常购物费", "大件购置费"},
    "投资自身开支": {"教育费", "图书费", "办公文印费", "健身训练费"},
    "其他必要开支": {"人情费", "医疗费", "父母亲人赡养费"},
    "财务费用开支": {"金融利息支出", "金融手续费与罚款", "账单套现"},
    "工作收入": {"工资", "奖金", "兼职收入"},
    "理财收入": {"货币理财收入"},
    "其他收入": {"其他收入", "父母资助", "亲朋借款"},
    "资产类支出": {"长期待摊费用", "其他资产类支出", "应收账款", "应付账款"},
    "负债类增记": {"账单补记", "账单分期"},
    "负债类减记": {"账单还款"},
}

# 多数L2 (用于回退)
MAJORITY_L2 = {l1: list(details)[0] for l1, details in VALID_L2_BY_L1.items()}

# Prompt 用的分类列表文本
L1_LIST_TEXT = "、".join(sorted(VALID_L1))

L2_PER_L1_TEXT = "\n".join(
    f"  {l1}: {', '.join(sorted(VALID_L2_BY_L1[l1]))}"
    for l1 in sorted(VALID_L1)
)

SYSTEM_PROMPT = f"""你是个人复式记账分类助手。严格返回JSON。

# 科目体系
三级科目: 会计要素 → 收付类型 → 类型明细。类型明细必须唯一归属一个收付类型。

# 支出类
生活必要开支 — 衣食住行、日常维持型开支。强调生存型、维持型。
  明细: 伙食费、交通通信费、其他必要家用、宠物养育费、必要着装费、房租费
文娱游购开支 — 享乐、体验、消费型开支。体现消费欲望和生活享受。
  明细: 饮食游乐费、日常购物费、大件购置费
投资自身开支 — 成长型开支。对自身能力和状态的投入，不是金融投资。
  明细: 教育费、图书费、办公文印费、健身训练费
其他必要开支 — 责任、保障、关系义务型必要开支。
  明细: 人情费、医疗费、父母亲人赡养费
财务费用开支 — 金融服务/金融资产处置产生的成本与损失。
  明细: 金融利息支出、金融手续费与罚款、账单套现
  硬规则: 已实现亏损进财务费用开支，未实现浮亏不进流水

# 收入类
工作收入 — 劳动所得。
  明细: 工资、奖金、兼职收入
理财收入 — 金融资产已实现收益。只记录赎回、卖出时的已实现收益。
  明细: 货币理财收入
其他收入 — 受限口袋科目。
  明细: 其他收入、父母资助、亲朋借款

# 资产类
资产类支出 — 资金转化为资产或权益，不是当期消费。
  明细: 长期待摊费用、其他资产类支出、应收账款、应付账款

# 负债类
负债类增记 — 负债形成。
  明细: 账单补记、账单分期
负债类减记 — 负债偿还。
  明细: 账单还款

# 重要 — 必须遵守
1. paymentType 必须严格从以下11个值中选择: {L1_LIST_TEXT}
2. 绝对禁止使用"支出"、"收入"、"收入类/支出类"、"负债类/资产类"、"不计收支" — 这些是会计要素名不是收付类型
3. typeDetail 必须严格从对应收付类型的明细列表中选择，禁止自创"""

SYSTEM_PROMPT_RETRY = f"""你是记账分类助手。上次你返回了非标准分类值，这次必须严格按以下约束返回JSON。

# 收付类型 — 只能从这11个选:
{L1_LIST_TEXT}

# 类型明细 — 严格按对应关系选:
{L2_PER_L1_TEXT}

# 绝对禁止作为收付类型的词:
"支出"、"收入"、"收入类"、"支出类"、"负债类"、"资产类"、"不计收支"、"收"、"支"

# 绝对禁止作为类型明细的词:
上述收付类型名称、会计要素名称、自创的粒度不匹配的名称

返回JSON: {{"paymentType":"","typeDetail":"","confidence":0.9,"reason":""}}"""


def is_valid_l1(val):
    return val in VALID_L1


def is_valid_l2(l1, l2):
    if not l1 or not l2:
        return False
    return l2 in VALID_L2_BY_L1.get(l1, set())


def majority_l2_for(l1):
    """返回某L1类别下的默认L2"""
    details = VALID_L2_BY_L1.get(l1, set())
    return list(details)[0] if details else ""


def load_data():
    """加载原始账单 + 匹配标签 + LLM缓存(v3+v6有效结果)"""
    raw = list(csv.DictReader(open("docs/data/合并原始账单.csv", encoding="utf-8-sig")))

    matched_map = {}
    with open("docs/data/匹配结果.csv", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if r["匹配状态"] == "匹配成功":
                key = (r["原始_交易时间"].strip(), r["原始_金额"].strip(), r["原始_交易对方"].strip())
                matched_map[key] = {
                    "收付类型": r["流水_收付类型"].strip(),
                    "类型明细": r["流水_类型明细"].strip(),
                }

    # LLM缓存: v3 + v6 有效结果 (标准分类且成功)
    llm_cache = {}
    for src_path in ["docs/data/llm_experiment_v3.csv", "docs/data/experiment_v6_results.csv"]:
        try:
            for r in csv.DictReader(open(src_path, encoding="utf-8-sig")):
                if r.get("API状态", "") != "成功":
                    continue
                l1 = r.get("LLM_收付类型", "").strip()
                l2 = r.get("LLM_类型明细", "").strip()
                if is_valid_l1(l1) and is_valid_l2(l1, l2):
                    key = (r["交易对方"].strip(), r["商品说明"].strip(), r["金额"].strip())
                    if key not in llm_cache:
                        llm_cache[key] = (l1, l2)
        except FileNotFoundError:
            pass

    print(f"LLM缓存: v3+v6共 {len(llm_cache)} 条有效结果")
    return raw, matched_map, llm_cache


# ═══════════════════════════════════════════════════════
# 特征工程
# ═══════════════════════════════════════════════════════

def build_features(rows):
    """构建特征矩阵: 三路ngram + 金额分桶 + 商户onehot"""
    n = len(rows)
    cp = [r["交易对方"].strip()[:100] for r in rows]
    pd = [r["商品说明"].strip()[:200] for r in rows]
    tx = [r["平台交易分类"].strip()[:50] for r in rows]

    vec_cp = TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 4), max_features=2000, sublinear_tf=True)
    vec_pd = TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 4), max_features=2000, sublinear_tf=True)
    vec_tx = TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 3), max_features=500, sublinear_tf=True)
    X_cp = vec_cp.fit_transform(cp)
    X_pd = vec_pd.fit_transform(pd)
    X_tx = vec_tx.fit_transform(tx)

    # 金额分桶 + 收支方向
    nb = len(AMOUNT_BINS)
    data_a, ri_a, ci_a = [], [], []
    for i, r in enumerate(rows):
        try:
            a = abs(float(r["金额"]))
        except (ValueError, KeyError):
            a = 0
        bi = nb - 1
        for j, u in enumerate(AMOUNT_BINS):
            if a <= u:
                bi = j
                break
        data_a.append(1.0); ri_a.append(i); ci_a.append(bi)
        dm = {"支出": nb, "收入": nb + 1, "不计收支": nb + 2}
        data_a.append(1.0); ri_a.append(i); ci_a.append(dm.get(r.get("收/支", "").strip(), nb + 2))
    X_a = csr_matrix((data_a, (ri_a, ci_a)), shape=(n, nb + 3))

    # 商户 onehot
    merch_enc = OneHotEncoder(sparse_output=True, handle_unknown="ignore", min_frequency=1)
    X_m = merch_enc.fit_transform([[r["交易对方"].strip()] for r in rows])

    X = hstack([X_cp, X_pd, X_tx, X_a, X_m])
    return X, (vec_cp, vec_pd, vec_tx), merch_enc


def transform_batch(rows, vecs, merch_enc):
    """用已有vectorizer转换新批次"""
    cp = [r["交易对方"].strip()[:100] for r in rows]
    pd = [r["商品说明"].strip()[:200] for r in rows]
    tx = [r["平台交易分类"].strip()[:50] for r in rows]
    X_cp = vecs[0].transform(cp)
    X_pd = vecs[1].transform(pd)
    X_tx = vecs[2].transform(tx)

    n = len(rows)
    nb = len(AMOUNT_BINS)
    data_a, ri_a, ci_a = [], [], []
    for i, r in enumerate(rows):
        try:
            a = abs(float(r["金额"]))
        except (ValueError, KeyError):
            a = 0
        bi = nb - 1
        for j, u in enumerate(AMOUNT_BINS):
            if a <= u:
                bi = j
                break
        data_a.append(1.0); ri_a.append(i); ci_a.append(bi)
        dm = {"支出": nb, "收入": nb + 1, "不计收支": nb + 2}
        data_a.append(1.0); ri_a.append(i); ci_a.append(dm.get(r.get("收/支", "").strip(), nb + 2))
    X_a = csr_matrix((data_a, (ri_a, ci_a)), shape=(n, nb + 3))
    X_m = merch_enc.transform([[r["交易对方"].strip()] for r in rows])

    return hstack([X_cp, X_pd, X_tx, X_a, X_m])


# ═══════════════════════════════════════════════════════
# L2 层级模型
# ═══════════════════════════════════════════════════════

def train_l2_models(labeled_rows):
    """为每个L1类别训练L2分类器。
    返回 {l1: (model, label_encoder, vecs, merch_enc)} 或 {l1: "回退字符串"}
    """
    by_l1 = defaultdict(list)
    for r in labeled_rows:
        l1 = r.get("收付类型", "").strip()
        l2 = r.get("类型明细", "").strip()
        if is_valid_l1(l1) and is_valid_l2(l1, l2):
            by_l1[l1].append(r)

    l2_models = {}
    for l1, recs in sorted(by_l1.items()):
        valid_set = VALID_L2_BY_L1.get(l1, set())
        if len(valid_set) <= 1:
            l2_models[l1] = list(valid_set)[0] if valid_set else ""
            continue

        if len(recs) < 10:
            cnt = Counter(r["类型明细"].strip() for r in recs)
            l2_models[l1] = cnt.most_common(1)[0][0] if cnt else majority_l2_for(l1)
            continue

        try:
            X, v, m = build_features(recs)
            le = LabelEncoder()
            y = le.fit_transform([r["类型明细"].strip() for r in recs])
            if len(set(y)) < 2:
                l2_models[l1] = le.classes_[0]
                continue
            model = LogisticRegression(
                multi_class="multinomial", solver="lbfgs", max_iter=1000,
                C=0.3, class_weight="balanced", random_state=42,
            )
            model.fit(X, y)
            l2_models[l1] = (model, le, v, m)
        except Exception:
            cnt = Counter(r["类型明细"].strip() for r in recs)
            l2_models[l1] = cnt.most_common(1)[0][0] if cnt else majority_l2_for(l1)

    return l2_models


def predict_l2(l1, row, l2_models):
    """预测单条记录的类型明细。返回 (prediction, confidence_or_None)"""
    if l1 not in l2_models:
        return (majority_l2_for(l1), None)

    model_data = l2_models[l1]
    if isinstance(model_data, str):
        return (model_data, None)

    model, le, v, m = model_data
    try:
        X_one = transform_batch([row], v, m)
        proba = model.predict_proba(X_one)
        pred_idx = proba.argmax(axis=1)[0]
        conf = proba.max(axis=1)[0]
        pred = le.classes_[pred_idx] if pred_idx < len(le.classes_) else ""
        return (pred, conf)
    except Exception:
        return (majority_l2_for(l1), None)


# ═══════════════════════════════════════════════════════
# LLM 调用 + 校验
# ═══════════════════════════════════════════════════════

def build_user_prompt(row):
    return f"""待分类账单:
- 交易对方: {row['交易对方']}
- 商品说明: {row['商品说明']}
- 平台分类: {row['平台交易分类']}
- 金额: {row['金额']}
- 收/支: {row.get('收/支', '')}

返回JSON: {{"paymentType":"","typeDetail":"","confidence":0.9,"reason":""}}"""


def call_llm_api(row, retry=False):
    """单次API调用, 返回 (result_dict_or_None, usage_dict, elapsed_ms, error_str)"""
    system_prompt = SYSTEM_PROMPT_RETRY if retry else SYSTEM_PROMPT
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": build_user_prompt(row)},
        ],
        "temperature": 0.05,
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
            raw_resp = json.loads(resp.read())
            content = raw_resp["choices"][0]["message"]["content"].strip()
            elapsed_ms = int((time.time() - t0) * 1000)
            return json.loads(content), raw_resp.get("usage", {}), elapsed_ms, None
    except Exception as e:
        elapsed_ms = int((time.time() - t0) * 1000)
        return None, {}, elapsed_ms, str(e)[:100]


def call_llm_with_validation(row):
    """调用LLM并校验。无效→重试(最多MAX_LLM_RETRIES次)。
    返回 (llm_dict_or_None, total_elapsed_ms, total_usage, status, retry_count)
    status: "成功" | "成功(缓存)" | "部分成功(L2回退)" | "L1非标准" | "L2非标准" | "API失败" | "JSON解析失败"
    """
    total_usage = {"prompt_tokens": 0, "completion_tokens": 0}
    total_elapsed = 0
    last_result = None

    for attempt in range(MAX_LLM_RETRIES + 1):
        llm_r, usage, elapsed_ms, err = call_llm_api(row, retry=(attempt > 0))
        total_usage["prompt_tokens"] += usage.get("prompt_tokens", 0)
        total_usage["completion_tokens"] += usage.get("completion_tokens", 0)
        total_elapsed += elapsed_ms

        if llm_r is None:
            last_result = (None, total_elapsed, total_usage, f"API失败(第{attempt+1}次)", attempt + 1)
            if attempt < MAX_LLM_RETRIES:
                backoff = 0.5 * (2 ** attempt)
                time.sleep(backoff)
                continue
            return last_result

        l1 = llm_r.get("paymentType", "").strip()
        l2 = llm_r.get("typeDetail", "").strip()

        # 校验 L1
        if not is_valid_l1(l1):
            if attempt < MAX_LLM_RETRIES:
                backoff = 0.5 * (2 ** attempt)
                time.sleep(backoff)
                continue
            return (llm_r, total_elapsed, total_usage, f"L1非标准(重试{MAX_LLM_RETRIES}次耗尽): {l1}", attempt + 1)

        # 校验 L2
        if l2 and not is_valid_l2(l1, l2):
            if attempt < MAX_LLM_RETRIES:
                backoff = 0.5 * (2 ** attempt)
                time.sleep(backoff)
                continue
            # 重试耗尽但L1有效 → L2回退到多数类
            fallback_l2 = majority_l2_for(l1)
            llm_r["typeDetail"] = fallback_l2
            llm_r["_l2_fallback"] = True
            return (llm_r, total_elapsed, total_usage, f"部分成功(L2回退): {l1}/{l2}→{fallback_l2}", attempt + 1)

        # 全部通过
        return (llm_r, total_elapsed, total_usage, "成功", attempt + 1)

    return last_result if last_result else (None, total_elapsed, total_usage, "未知错误", MAX_LLM_RETRIES + 1)


# ═══════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════

def main():
    print("=" * 70)
    print("v6.1 修复版 — L1+L2双层模型 + 严格分类校验 + 非标准自动重试/回退")
    print("=" * 70)

    raw, matched_map, llm_cache = load_data()
    print(f"原始账单: {len(raw):,}  已匹配: {len(matched_map):,}")

    raw.sort(key=lambda r: r["交易时间"])
    print(f"时间范围: {raw[0]['交易时间'][:10]} ~ {raw[-1]['交易时间'][:10]}")

    # ── 冷启动: 前30条已匹配 ──
    seed = []
    remaining = []
    for r in raw:
        key = (r["交易时间"].strip(), r["金额"].strip(), r["交易对方"].strip())
        tag = matched_map.get(key, {})
        l1 = tag.get("收付类型", "")
        l2 = tag.get("类型明细", "")
        r["实际_收付类型"] = l1
        r["实际_类型明细"] = l2
        r["_is_matched"] = bool(l1)

        if len(seed) < 30 and l1:
            r["收付类型"] = l1
            r["类型明细"] = l2
            seed.append(r)
        else:
            remaining.append(r)

    training_set = list(seed)
    print(f"冷启动: {len(seed)} 条(种子训练集), 待处理: {len(remaining):,}")

    # ── 按月分批 ──
    batches = defaultdict(list)
    for r in remaining:
        batches[r["交易时间"][:7]].append(r)
    batch_keys = sorted(batches.keys())
    print(f"批次: {len(batch_keys)} 个月")

    # ── 输出文件 ──
    out_f = open("docs/data/experiment_v6.1_results.csv", "w", encoding="utf-8-sig")
    out_cols = [
        "序号", "月份", "交易时间", "交易对方", "商品说明", "平台交易分类", "收/支", "金额",
        "是否已匹配", "实际_收付类型", "实际_类型明细",
        "本地_收付类型", "本地_类型明细", "本地_L1置信度", "本地_L2置信度",
        "LLM_收付类型", "LLM_类型明细", "LLM置信度", "LLM原因",
        "LLM校验状态", "LLM重试次数",
        "最终_收付类型", "最终_类型明细", "分类来源",
        "API耗时_ms", "API状态",
    ]
    out_w = csv.DictWriter(out_f, fieldnames=out_cols, extrasaction="ignore")
    out_w.writeheader()
    out_f.flush()

    # ── 统计计数器 ──
    history = []
    global_seq = len(seed)
    total_llm_calls = 0       # LLM调用批次数(含缓存命中)
    total_api_calls = 0       # 实际API调用次数
    total_retries = 0         # 总重试次数
    pt_sum = 0                # prompt tokens
    ct_sum = 0                # completion tokens
    stat_valid = 0            # LLM校验成功
    stat_partial = 0          # 部分成功(L2回退)
    stat_invalid_l1 = 0       # L1非标准
    stat_api_fail = 0         # API完全失败
    stat_cache_hit = 0        # 缓存命中
    cum_skipped_nonstd = 0    # 累计过滤的非标准训练数据
    cum_l2_trained = 0        # 累计训练的L2模型数
    cum_l2_fallback = 0       # 累计回退的L2模型数

    for bi, ym in enumerate(batch_keys):
        batch = batches[ym]
        if len(batch) < 3:
            for row in batch:
                global_seq += 1
                out_w.writerow({
                    "序号": global_seq, "月份": ym,
                    "交易时间": row["交易时间"], "交易对方": row["交易对方"],
                    "商品说明": row["商品说明"], "平台交易分类": row["平台交易分类"],
                    "收/支": row.get("收/支", ""), "金额": row["金额"],
                    "是否已匹配": "是" if row.get("_is_matched") else "否",
                    "实际_收付类型": row.get("实际_收付类型", ""),
                    "实际_类型明细": row.get("实际_类型明细", ""),
                    "分类来源": "批次过小(跳过)",
                })
            continue

        # ── 训练 ──
        # 筛选标准分类的训练数据
        labeled = []
        for r in training_set:
            l1 = r.get("收付类型", "").strip()
            l2 = r.get("类型明细", "").strip()
            if l1 and is_valid_l1(l1) and l2 and is_valid_l2(l1, l2):
                labeled.append(r)
            elif l1:
                cum_skipped_nonstd += 1

        if len(labeled) < 5:
            for row in batch:
                global_seq += 1
                out_w.writerow({
                    "序号": global_seq, "月份": ym,
                    "交易时间": row["交易时间"], "交易对方": row["交易对方"],
                    "商品说明": row["商品说明"], "平台交易分类": row["平台交易分类"],
                    "收/支": row.get("收/支", ""), "金额": row["金额"],
                    "是否已匹配": "是" if row.get("_is_matched") else "否",
                    "实际_收付类型": row.get("实际_收付类型", ""),
                    "实际_类型明细": row.get("实际_类型明细", ""),
                    "分类来源": "训练数据不足(跳过)",
                })
            continue

        # L1 模型
        X_tr, vecs_l1, merch_enc_l1 = build_features(labeled)
        le1 = LabelEncoder()
        y_l1 = le1.fit_transform([r["收付类型"] for r in labeled])
        model_l1 = LogisticRegression(
            multi_class="multinomial", solver="lbfgs", max_iter=1000,
            C=0.5, class_weight="balanced", random_state=42,
        )
        model_l1.fit(X_tr, y_l1)

        # L2 模型
        l2_models = train_l2_models(labeled)
        cum_l2_trained += sum(1 for v in l2_models.values() if not isinstance(v, str))
        cum_l2_fallback += sum(1 for v in l2_models.values() if isinstance(v, str))

        # ── 预测 ──
        X_batch = transform_batch(batch, vecs_l1, merch_enc_l1)
        proba_l1 = model_l1.predict_proba(X_batch)
        conf_l1 = proba_l1.max(axis=1)
        pred_l1_idx = model_l1.predict(X_batch)

        pred_l1_list = []
        pred_l2_list = []
        pred_l2_conf_list = []
        for i, row in enumerate(batch):
            l1_name = le1.classes_[pred_l1_idx[i]] if pred_l1_idx[i] < len(le1.classes_) else ""
            pred_l1_list.append(l1_name)
            l2_pred, l2_conf = predict_l2(l1_name, row, l2_models)
            pred_l2_list.append(l2_pred)
            pred_l2_conf_list.append(l2_conf)

        # ── 低置信度: 并发LLM + 缓存 ──
        low_indices = [i for i in range(len(batch)) if conf_l1[i] < THRESHOLD]
        llm_results = {}

        if low_indices:
            def fetch_llm(idx):
                row = batch[idx]
                key = (row["交易对方"].strip(), row["商品说明"].strip(), row["金额"].strip())
                # 查缓存(标准分类的v3/v6结果)
                if key in llm_cache:
                    cached = llm_cache[key]
                    return idx, {
                        "paymentType": cached[0], "typeDetail": cached[1],
                        "confidence": 0.95, "reason": "缓存(v3/v6有效结果)",
                    }, 0, {}, "成功(缓存)", 0

                # 实际调API + 校验
                llm_r, elapsed_ms, usage, status, retries = call_llm_with_validation(row)
                return idx, llm_r, elapsed_ms, usage, status, retries

            with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
                futs = {ex.submit(fetch_llm, i): i for i in low_indices}
                for fut in concurrent.futures.as_completed(futs):
                    idx, llm_r, elapsed_ms, usage, status, retries = fut.result()
                    llm_results[idx] = (llm_r, elapsed_ms, usage, status, retries)

        # ── 处理批次 ──
        batch_local_l1 = 0; batch_local_l2 = 0
        batch_final_l1 = 0; batch_final_l2 = 0
        batch_n_matched = 0
        batch_llm_attempts = 0

        for i, row in enumerate(batch):
            global_seq += 1
            is_matched = row.get("_is_matched", False)
            actual_l1 = row.get("实际_收付类型", "")
            actual_l2 = row.get("实际_类型明细", "")
            local_l1 = pred_l1_list[i]
            local_l2 = pred_l2_list[i]
            local_l2_conf = pred_l2_conf_list[i]
            is_high = conf_l1[i] >= THRESHOLD

            if is_high:
                # ── 本地高置信 ──
                final_l1 = local_l1
                final_l2 = local_l2
                llm_l1 = llm_l2 = llm_reason = llm_status = ""
                llm_conf = llm_retry_cnt = ""
                api_elapsed = ""
                source = "本地高置信"
            else:
                # ── LLM ──
                batch_llm_attempts += 1
                llm_r, api_elapsed, usage, llm_status, llm_retry_cnt = llm_results.get(
                    i, (None, 0, {}, "未找到结果", 0))

                # 累计 token
                pt = usage.get("prompt_tokens", 0)
                ct = usage.get("completion_tokens", 0)
                pt_sum += pt; ct_sum += ct
                if pt > 0:  # 有token消耗 = 实际调了API
                    total_api_calls += 1

                if llm_r:
                    llm_l1 = llm_r.get("paymentType", "")
                    llm_l2 = llm_r.get("typeDetail", "")
                    llm_conf = llm_r.get("confidence", 0)
                    llm_reason = llm_r.get("reason", "")

                    # 统计校验状态
                    if llm_status.startswith("成功"):
                        stat_valid += 1
                    elif "部分成功" in llm_status:
                        stat_partial += 1
                    elif "L1非标准" in llm_status:
                        stat_invalid_l1 += 1
                    elif "缓存" in llm_status:
                        stat_cache_hit += 1
                        stat_valid += 1  # 缓存=成功
                    else:
                        stat_api_fail += 1

                    # 模拟用户审核 (80%纠正LLM错误)
                    if llm_l1 == actual_l1 or not actual_l1:
                        final_l1 = llm_l1
                        final_l2 = llm_l2
                    elif random.random() < 0.8:
                        final_l1 = actual_l1
                        final_l2 = actual_l2
                    else:
                        final_l1 = llm_l1
                        final_l2 = llm_l2
                    source = "LLM"
                else:
                    # API完全失败 → 降级到本地预测
                    llm_l1 = llm_l2 = llm_reason = ""
                    llm_conf = 0
                    stat_api_fail += 1
                    final_l1 = local_l1
                    final_l2 = local_l2
                    source = "本地降级(API失败)"

            # ── 准确率统计 (仅已匹配) ──
            if is_matched and actual_l1:
                batch_n_matched += 1
                if local_l1 == actual_l1:
                    batch_local_l1 += 1
                if local_l2 == actual_l2:
                    batch_local_l2 += 1
                if final_l1 == actual_l1:
                    batch_final_l1 += 1
                if final_l2 == actual_l2:
                    batch_final_l2 += 1

            # ── 写入 ──
            out_w.writerow({
                "序号": global_seq, "月份": ym,
                "交易时间": row["交易时间"], "交易对方": row["交易对方"],
                "商品说明": row["商品说明"], "平台交易分类": row["平台交易分类"],
                "收/支": row.get("收/支", ""), "金额": row["金额"],
                "是否已匹配": "是" if is_matched else "否",
                "实际_收付类型": actual_l1, "实际_类型明细": actual_l2,
                "本地_收付类型": local_l1, "本地_类型明细": local_l2,
                "本地_L1置信度": f"{conf_l1[i]:.3f}",
                "本地_L2置信度": f"{local_l2_conf:.3f}" if local_l2_conf is not None else "",
                "LLM_收付类型": llm_l1, "LLM_类型明细": llm_l2,
                "LLM置信度": llm_conf, "LLM原因": str(llm_reason)[:200] if llm_reason else "",
                "LLM校验状态": str(llm_status)[:50] if llm_status else "",
                "LLM重试次数": llm_retry_cnt if not is_high else "",
                "最终_收付类型": final_l1, "最终_类型明细": final_l2,
                "分类来源": source,
                "API耗时_ms": api_elapsed if not is_high else "",
                "API状态": llm_status if llm_status else ("成功(本地)" if is_high else ""),
            })
            out_f.flush()

            # ── 加入训练集 (仅标准分类) ──
            if is_valid_l1(final_l1):
                new_row = dict(row)
                new_row["收付类型"] = final_l1
                if is_valid_l2(final_l1, final_l2):
                    new_row["类型明细"] = final_l2
                else:
                    new_row["类型明细"] = majority_l2_for(final_l1)
                training_set.append(new_row)

        total_llm_calls += batch_llm_attempts
        total_retries += sum(r[4] - 1 for r in llm_results.values() if r[4] > 1)

        # ── 批次日志 ──
        if batch_n_matched > 0:
            history.append({
                "month": ym, "n_batch": len(batch), "n_matched": batch_n_matched,
                "local_l1_acc": batch_local_l1 / batch_n_matched,
                "local_l2_acc": batch_local_l2 / batch_n_matched,
                "overall_l1_acc": batch_final_l1 / batch_n_matched,
                "overall_l2_acc": batch_final_l2 / batch_n_matched,
                "high_ratio": (len(batch) - batch_llm_attempts) / len(batch),
                "llm_ratio": batch_llm_attempts / len(batch),
                "avg_conf": conf_l1.mean(),
            })

        cost_est = (pt_sum / 1_000_000) * 1.0 + (ct_sum / 1_000_000) * 2.0
        if history:
            h = history[-1]
            print(f"  [{bi+1:3d}/{len(batch_keys)}] {ym} 批{len(batch):4d} 已匹配{batch_n_matched:4d} | "
                  f"本地L1:{h['local_l1_acc']:.0%} L2:{h['local_l2_acc']:.0%} "
                  f"整体L1:{h['overall_l1_acc']:.0%} L2:{h['overall_l2_acc']:.0%} | "
                  f"高占比:{h['high_ratio']:.0%} LLM:{batch_llm_attempts:3d}次 | "
                  f"累计API:{total_api_calls} 缓存:{stat_cache_hit} L2回退:{stat_partial} L1无效:{stat_invalid_l1} ¥{cost_est:.2f}")
        else:
            print(f"  [{bi+1:3d}/{len(batch_keys)}] {ym} 批{len(batch):4d} 已匹配{batch_n_matched:4d} | "
                  f"(无已匹配) | LLM:{batch_llm_attempts:3d}次")

    out_f.close()

    # ═══════════════════════════════════════════════════
    # 汇总
    # ═══════════════════════════════════════════════════
    total_cost = (pt_sum / 1_000_000) * 1.0 + (ct_sum / 1_000_000) * 2.0
    print(f"\n{'='*70}")
    print(f"v6.1 汇总")
    print(f"{'='*70}")
    print(f"  总处理: {global_seq:,} 条")
    print(f"  训练数据中过滤掉的非标准记录: {cum_skipped_nonstd}")
    print(f"  L2模型: 每批平均训练{cum_l2_trained/len(batch_keys):.1f}个, 回退{cum_l2_fallback/len(batch_keys):.1f}个")
    print(f"  LLM调用: {total_llm_calls:,} 次 (实际API: {total_api_calls:,}  缓存: {stat_cache_hit})")
    print(f"  LLM校验: 成功{stat_valid}  L2回退{stat_partial}  L1无效{stat_invalid_l1}  API失败{stat_api_fail}")
    print(f"  LLM重试(总): {total_retries} 次")
    print(f"  API: prompt {pt_sum:,} tokens + completion {ct_sum:,} tokens")
    print(f"  成本: ¥{total_cost:.4f} (¥1/M prompt + ¥2/M completion)")

    stages = [
        ("早期(前6月)", history[:6]),
        ("中期(6-18月)", history[6:18] if len(history) >= 18 else history[6:]),
        ("后期(18月+)", history[18:] if len(history) >= 18 else []),
    ]
    print(f"\n  {'阶段':12s} {'本地L1':>7s} {'本地L2':>7s} {'整体L1':>7s} {'整体L2':>7s} {'高占比':>7s} {'LLM率':>7s}")
    print(f"  {'-'*70}")
    for name, h in stages:
        if not h:
            continue
        print(f"  {name:12s} {np.mean([x['local_l1_acc'] for x in h]):>6.1%}  "
              f"{np.mean([x['local_l2_acc'] for x in h]):>6.1%}  "
              f"{np.mean([x['overall_l1_acc'] for x in h]):>6.1%}  "
              f"{np.mean([x['overall_l2_acc'] for x in h]):>6.1%}  "
              f"{np.mean([x['high_ratio'] for x in h]):>6.1%}  "
              f"{np.mean([x['llm_ratio'] for x in h]):>6.1%}")

    if len(history) >= 6:
        first6 = history[:6]
        last6 = history[-6:]
        print(f"\n  前6月 → 后6月:")
        print(f"    本地L1:    {np.mean([x['local_l1_acc'] for x in first6]):.1%} → {np.mean([x['local_l1_acc'] for x in last6]):.1%}")
        print(f"    本地L2:    {np.mean([x['local_l2_acc'] for x in first6]):.1%} → {np.mean([x['local_l2_acc'] for x in last6]):.1%}")
        print(f"    整体L1:    {np.mean([x['overall_l1_acc'] for x in first6]):.1%} → {np.mean([x['overall_l1_acc'] for x in last6]):.1%}")
        print(f"    整体L2:    {np.mean([x['overall_l2_acc'] for x in first6]):.1%} → {np.mean([x['overall_l2_acc'] for x in last6]):.1%}")
        print(f"    LLM率:     {np.mean([x['llm_ratio'] for x in first6]):.1%} → {np.mean([x['llm_ratio'] for x in last6]):.1%}")
        print(f"    高置信占比: {np.mean([x['high_ratio'] for x in first6]):.1%} → {np.mean([x['high_ratio'] for x in last6]):.1%}")

    print(f"\n  结果保存: docs/data/experiment_v6.1_results.csv")


if __name__ == "__main__":
    main()
