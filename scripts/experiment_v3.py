"""
双层分类实验 v3 — 500已匹配 + 500未匹配, 保存完整结果供人工核查
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

TYPE_DETAIL_MAP = {
    "生活必要开支": ["伙食费","交通通信费","宠物养育费","必要着装费","房租费","其他必要家用"],
    "文娱游购开支": ["饮食游乐费","日常购物费","大件购置费"],
    "投资自身开支": ["教育费","图书费","健身训练费","办公文印费"],
    "其他必要开支": ["医疗费","父母亲人赡养费","人情费","社保返还"],
    "工作收入": ["工资","奖金","兼职收入"],
    "理财收入": ["货币理财收入"],
    "其他收入": ["其他收入","父母资助","亲朋借款"],
    "资产类支出": ["长期待摊费用","其他资产类支出","应收账款","应付账款"],
    "负债类增记": ["账单补记","账单分期"],
    "负债类减记": ["账单还款"],
    "财务费用开支": ["金融利息支出","金融手续费与罚款","账单套现"],
}

# ── 加载 ──
train = list(csv.DictReader(open("docs/data/训练数据集.csv", encoding="utf-8-sig")))
by_merchant = defaultdict(list); by_tx_type = defaultdict(list)
for r in train:
    by_merchant[r["交易对方"].strip()].append(r)
    by_tx_type[r["平台交易分类"].strip()].append(r)

preds = list(csv.DictReader(open("docs/data/预测核查.csv", encoding="utf-8-sig")))
matched_all = [r for r in preds if r["匹配状态"]=="已匹配" and r["实际_收付类型"].strip()]
unmatched_all = [r for r in preds if r["匹配状态"]=="未匹配"]

random.seed(42)

# ── 抽样 ──
low_conf = [r for r in matched_all if float(r["预测_L1置信度"])<THRESHOLD]
high_conf = [r for r in matched_all if float(r["预测_L1置信度"])>=THRESHOLD]
by_actual_low = defaultdict(list); by_actual_high = defaultdict(list)
for r in low_conf: by_actual_low[r["实际_收付类型"]].append(r)
for r in high_conf: by_actual_high[r["实际_收付类型"]].append(r)

matched_sample = []
for t in TYPE_DETAIL_MAP.keys():
    low_n = min(len(by_actual_low.get(t,[])), max(5, int(450*len(by_actual_low.get(t,[]))/len(low_conf)))) if by_actual_low.get(t,[]) else 0
    high_n = min(len(by_actual_high.get(t,[])), max(2, int(50*len(by_actual_high.get(t,[]))/len(high_conf)))) if by_actual_high.get(t,[]) else 0
    if low_n>0: matched_sample.extend(random.sample(by_actual_low.get(t,[]), low_n))
    if high_n>0: matched_sample.extend(random.sample(by_actual_high.get(t,[]), high_n))
matched_sample = matched_sample[:500]; random.shuffle(matched_sample)

by_source_dir = defaultdict(list)
for r in unmatched_all: by_source_dir[f"{r['来源']}_{r['收/支']}"].append(r)
unmatched_sample = []
for k, recs in sorted(by_source_dir.items(), key=lambda x: -len(x[1])):
    n = max(10, int(500*len(recs)/len(unmatched_all))); n = min(n, len(recs))
    unmatched_sample.extend(random.sample(recs, n))
unmatched_sample = unmatched_sample[:500]; random.shuffle(unmatched_sample)

all_samples = matched_sample + unmatched_sample
print(f"样本: 已匹配{len(matched_sample)} + 未匹配{len(unmatched_sample)} = {len(all_samples)}")

# ── 工具 ──
def find_similar(row):
    m=row["交易对方"].strip(); tx=row["平台交易分类"].strip()
    try: amt=abs(float(row["金额"]))
    except: amt=0
    sim=[]
    for r in by_merchant.get(m,[])[:5]:
        if r not in sim: sim.append(r)
    cand=[]
    for r in by_tx_type.get(tx,[]):
        if r in sim: continue
        try: ra=abs(float(r["金额"]))
        except: ra=0
        if amt>0 and 0.3<ra/amt<3.0: cand.append(r)
    for r in cand[:3]: sim.append(r)
    return sim[:8]

def build_prompt(row):
    sim=find_similar(row)
    tl="\n".join(f"  - {t}" for t in TYPE_DETAIL_MAP.keys())
    fs="\n\n".join(f"示例{i+1}:\n  交易对方: {s['交易对方']}\n  商品说明: {s['商品说明']}\n  平台分类: {s['平台交易分类']}\n  金额: {s['金额']}\n  收/支: {s['收/支']}\n  → 收付类型: {s['收付类型']} | 类型明细: {s['类型明细']}" for i,s in enumerate(sim))
    return f"""根据账单信息判断收付类型和类型明细。

# 可选收付类型
{tl}

# 参考示例
{fs}

# 待分类账单
- 交易对方: {row['交易对方']}
- 商品说明: {row['商品说明']}
- 平台分类: {row['平台交易分类']}
- 金额: {row['金额']}
- 收/支: {row['收/支']}

返回JSON: {{"paymentType":"","typeDetail":"","confidence":0.9,"reason":""}}"""

def call_one(row):
    body=json.dumps({"model":MODEL,"messages":[
        {"role":"system","content":"你是记账分类助手。严格返回JSON。"},
        {"role":"user","content":build_prompt(row)}
    ],"temperature":0.1,"max_tokens":200}).encode()
    t0=time.time()
    try:
        req=request.Request(f"{API_BASE}/v1/chat/completions",data=body,
            headers={"Authorization":f"Bearer {API_KEY}","Content-Type":"application/json"})
        with request.urlopen(req,timeout=45) as resp:
            r=json.loads(resp.read()); c=r["choices"][0]["message"]["content"].strip()
            if c.startswith("```"): c=c.split("\n",1)[-1]; c=c[:-3]
            return json.loads(c),time.time()-t0,r.get("usage",{}),None,build_prompt(row)
    except Exception as e:
        return None,time.time()-t0,{},str(e),build_prompt(row)

# ── 输出 CSV ──
OUT_COLS = [
    "序号","匹配状态","来源","交易时间","交易对方","商品说明","平台交易分类",
    "收/支","金额","收付款方式",
    "实际_收付类型","实际_类型明细",
    "本地_收付类型","本地_类型明细","本地_L1置信度",
    "LLM_收付类型","LLM_类型明细","LLM置信度","LLM原因",
    "本地L1对","LLM_L1对","本地L2对","LLM_L2对",
    "API耗时_ms","API状态",
    "LLM原始输出","LLM输入",
]

out_f = open("docs/data/llm_experiment_v3.csv", "w", encoding="utf-8-sig")
writer = csv.DictWriter(out_f, fieldnames=OUT_COLS, extrasaction="ignore")
writer.writeheader()
out_f.flush()

# ── 并发 ──
print(f"并发 {len(all_samples)} 条 (max_workers=30)...")
t0=time.time(); pt=ct=0; n_ok=0; n_fail=0
with concurrent.futures.ThreadPoolExecutor(max_workers=30) as ex:
    futs={ex.submit(call_one,row):i for i,row in enumerate(all_samples)}
    for fut in concurrent.futures.as_completed(futs):
        i=futs[fut]; llm_r,elapsed,usage,err,prompt=fut.result()
        pt+=usage.get("prompt_tokens",0); ct+=usage.get("completion_tokens",0)
        row=all_samples[i]; is_matched = i < 500

        if llm_r is None: n_fail+=1
        else: n_ok+=1

        # 构建输出行
        out_row = {
            "序号": i+1,
            "匹配状态": "已匹配" if is_matched else "未匹配",
            "来源": row.get("来源","") or row.get("原始_来源",""),
            "交易时间": row.get("交易时间","") or row.get("原始_交易时间",""),
            "交易对方": row.get("交易对方","") or row.get("原始_交易对方",""),
            "商品说明": row.get("商品说明","") or row.get("原始_商品说明",""),
            "平台交易分类": row.get("平台交易分类","") or row.get("原始_平台交易分类",""),
            "收/支": row.get("收/支","") or row.get("原始_收/支",""),
            "金额": row.get("金额","") or row.get("原始_金额",""),
            "收付款方式": row.get("收付款方式","") or row.get("原始_收付款方式",""),
            "实际_收付类型": row.get("实际_收付类型",""),
            "实际_类型明细": row.get("实际_类型明细",""),
            "本地_收付类型": row.get("预测_收付类型",""),
            "本地_类型明细": row.get("预测_类型明细",""),
            "本地_L1置信度": row.get("预测_L1置信度",""),
            "LLM_收付类型": llm_r.get("paymentType","") if llm_r else "",
            "LLM_类型明细": llm_r.get("typeDetail","") if llm_r else "",
            "LLM置信度": llm_r.get("confidence","") if llm_r else "",
            "LLM原因": llm_r.get("reason","") if llm_r else err if err else "",
            "本地L1对": "✓" if row.get("预测_收付类型","")==row.get("实际_收付类型","") else ("✗" if row.get("实际_收付类型","") else ""),
            "LLM_L1对": "✓" if (llm_r and llm_r.get("paymentType","")==row.get("实际_收付类型","")) else ("✗" if (llm_r and row.get("实际_收付类型","")) else ""),
            "本地L2对": "✓" if row.get("预测_类型明细","")==row.get("实际_类型明细","") else ("✗" if row.get("实际_类型明细","") else ""),
            "LLM_L2对": "✓" if (llm_r and llm_r.get("typeDetail","")==row.get("实际_类型明细","")) else ("✗" if (llm_r and row.get("实际_类型明细","")) else ""),
            "API耗时_ms": int(elapsed*1000),
            "API状态": "失败" if llm_r is None else "成功",
            "LLM原始输出": json.dumps(llm_r, ensure_ascii=False) if llm_r else (err or ""),
            "LLM输入": prompt.replace("\n","\\n"),
        }
        writer.writerow(out_row)
        out_f.flush()

        if (i+1) % 100 == 0:
            total_t = time.time()-t0
            print(f"  [{i+1:4d}/{len(all_samples)}] {total_t:.0f}s  成功:{n_ok} 失败:{n_fail}")

total=time.time()-t0; out_f.close()
ttt=pt+ct
cost_total = pt/1_000_000*1.0 + ct/1_000_000*2.0

print(f"\n{'='*60}")
print(f"v3 保存完成: docs/data/llm_experiment_v3.csv")
print(f"{'='*60}")
print(f"  总耗时: {total:.1f}s  成功: {n_ok}  失败: {n_fail}")
print(f"  Tokens: {ttt:,}  成本: ¥{cost_total:.4f}")
print(f"  月均(普通用户): ¥{cost_total/len(all_samples)*188:.4f}")
