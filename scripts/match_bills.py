"""
用 (交易时间秒, 金额) 匹配合并原始账单和已处理流水账。

输入:
  - docs/data/合并原始账单.csv  (原始账单, 16,021条)
  - docs/data/已处理账单_副本.xlsx (已处理流水, 15,180条)

输出:
  - docs/data/匹配结果.csv  (匹配成功 + 未匹配的原始 + 未匹配的流水)
"""

from __future__ import annotations

import csv
import os
import sys
from datetime import datetime
from collections import defaultdict

RAW_FILE = "docs/data/合并原始账单.csv"
LEDGER_FILE = "docs/data/已处理账单_副本.xlsx"
OUTPUT_FILE = "docs/data/匹配结果.csv"

# 输出列
OUTPUT_COLS = [
    # 匹配信息
    "匹配状态",
    # 原始账单字段
    "原始_交易时间", "原始_交易对方", "原始_商品说明", "原始_收/支",
    "原始_金额", "原始_收付款方式", "原始_交易状态", "原始_备注",
    "原始_平台交易分类", "原始_交易单号", "原始_商户单号", "原始_对方账号",
    "原始_来源", "原始_文件名",
    # 已处理账单字段
    "流水_日期", "流水_收付手段", "流水_金额", "流水_收付类型",
    "流水_类型明细", "流水_备注", "流水_yyyymm",
]


def parse_ledger_date(val) -> datetime | None:
    """解析已处理账单的日期字段"""
    if val is None:
        return None
    if isinstance(val, datetime):
        return val
    if isinstance(val, str):
        val = val.strip()
        for fmt in ["%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S", "%Y-%m-%d", "%Y/%m/%d"]:
            try:
                return datetime.strptime(val, fmt)
            except ValueError:
                continue
    return None


def parse_raw_date(val: str) -> datetime | None:
    """解析原始账单的日期字符串"""
    val = val.strip()
    for fmt in ["%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S"]:
        try:
            return datetime.strptime(val, fmt)
        except ValueError:
            continue
    return None


def main():
    print("=" * 60)
    print("匹配原始账单 与 已处理流水账")
    print("  匹配键: 时间(秒) + 金额(完全一致)")
    print("=" * 60)

    # ── 1. 读取原始账单 ──
    print("\n[1/3] 读取原始账单...")
    raw_rows = []
    with open(RAW_FILE, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_rows.append(row)
    print(f"  原始账单: {len(raw_rows):,} 条")

    # ── 2. 读取已处理流水 ──
    print("[2/3] 读取已处理流水...")
    import openpyxl
    wb = openpyxl.load_workbook(LEDGER_FILE, read_only=True)
    ws = wb.active
    ledger_rows = []
    for row in ws.iter_rows(min_row=2, values_only=True):  # 跳过表头
        if row[0] is None:
            continue
        dt = parse_ledger_date(row[0])
        amount = row[2]
        if dt is None or amount is None:
            continue
        ledger_rows.append({
            "日期": dt,
            "金额": float(amount),
            "收付手段": str(row[1]) if row[1] else "",
            "收付类型": str(row[3]) if row[3] else "",
            "类型明细": str(row[4]) if row[4] else "",
            "备注": str(row[5]) if row[5] else "",
            "yyyymm": str(row[6]) if row[6] else "",
        })
    print(f"  已处理流水: {len(ledger_rows):,} 条")

    # ── 3. 建立索引并匹配 ──
    print("[3/3] 匹配中...")

    # 流水按 (时间秒, 金额) 建立索引
    # 可能有重复键（同秒同金额的不同流水行），用列表存储
    ledger_index: dict[tuple, list[dict]] = defaultdict(list)
    for lr in ledger_rows:
        key = (lr["日期"], round(lr["金额"], 2))
        ledger_index[key].append(lr)

    print(f"  流水唯一键: {len(ledger_index):,}")

    matched_raw = set()       # 已匹配的原始行索引
    matched_ledger = set()    # 已匹配的流水行 id()

    output_rows = []

    # 对每条原始账单尝试匹配
    for i, rr in enumerate(raw_rows):
        raw_dt = parse_raw_date(rr["交易时间"])
        raw_amount_str = rr["金额"].strip()
        if not raw_dt or not raw_amount_str:
            output_rows.append(make_output("原始时间或金额为空", rr, None))
            continue

        try:
            raw_amount = round(float(raw_amount_str), 2)
        except ValueError:
            output_rows.append(make_output("原始金额解析失败", rr, None))
            continue

        key = (raw_dt, raw_amount)
        candidates = ledger_index.get(key, [])

        if not candidates:
            output_rows.append(make_output("未匹配", rr, None))
            continue

        # 找到第一个未被占用的候选
        found = False
        for cand in candidates:
            if id(cand) not in matched_ledger:
                matched_raw.add(i)
                matched_ledger.add(id(cand))
                output_rows.append(make_output("匹配成功", rr, cand))
                found = True
                break

        if not found:
            output_rows.append(make_output("未匹配(候选已被占用)", rr, None))

    # 添加未匹配的流水行
    for lr in ledger_rows:
        if id(lr) not in matched_ledger:
            output_rows.append(make_output("仅流水", None, lr))

    # ── 4. 写入结果 ──
    print(f"\n写入 {OUTPUT_FILE} ...")
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=OUTPUT_COLS, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(output_rows)

    # ── 5. 统计 ──
    matched_count = sum(1 for r in output_rows if r["匹配状态"] == "匹配成功")
    raw_unmatched = sum(1 for r in output_rows if r["匹配状态"].startswith("未匹配"))
    ledger_only = sum(1 for r in output_rows if r["匹配状态"] == "仅流水")
    other = len(output_rows) - matched_count - raw_unmatched - ledger_only

    print()
    print("=" * 60)
    print("匹配结果")
    print(f"  匹配成功:     {matched_count:>8,} 条")
    print(f"  原始未匹配:   {raw_unmatched:>8,} 条")
    print(f"  仅流水(无原始): {ledger_only:>8,} 条")
    print(f"  其他:         {other:>8,} 条")
    print(f"  ─────────────────────")
    print(f"  总计:         {len(output_rows):>8,} 条")

    matched_ali = sum(1 for r in output_rows
                      if r["匹配状态"] == "匹配成功" and r.get("原始_来源") == "支付宝")
    matched_wx = sum(1 for r in output_rows
                     if r["匹配状态"] == "匹配成功" and r.get("原始_来源") == "微信")
    print(f"    其中支付宝匹配: {matched_ali:,}  微信匹配: {matched_wx:,}")

    # 分析未匹配原因
    no_time = sum(1 for r in output_rows if r["匹配状态"] == "原始时间或金额为空")
    bad_amount = sum(1 for r in output_rows if r["匹配状态"] == "原始金额解析失败")
    no_match = sum(1 for r in output_rows if r["匹配状态"] == "未匹配")
    occupied = sum(1 for r in output_rows if r["匹配状态"] == "未匹配(候选已被占用)")
    print(f"\n原始未匹配明细:")
    print(f"  时间/金额为空: {no_time}")
    print(f"  金额解析失败:  {bad_amount}")
    print(f"  无匹配:        {no_match}")
    print(f"  候选被占用:    {occupied}")


def make_output(status: str, raw: dict | None, ledger: dict | None) -> dict:
    """构造输出行"""
    row = {"匹配状态": status}
    if raw:
        row["原始_交易时间"] = raw.get("交易时间", "")
        row["原始_交易对方"] = raw.get("交易对方", "")
        row["原始_商品说明"] = raw.get("商品说明", "")
        row["原始_收/支"] = raw.get("收/支", "")
        row["原始_金额"] = raw.get("金额", "")
        row["原始_收付款方式"] = raw.get("收付款方式", "")
        row["原始_交易状态"] = raw.get("交易状态", "")
        row["原始_备注"] = raw.get("备注", "")
        row["原始_平台交易分类"] = raw.get("平台交易分类", "")
        row["原始_交易单号"] = raw.get("交易单号", "")
        row["原始_商户单号"] = raw.get("商户单号", "")
        row["原始_对方账号"] = raw.get("对方账号", "")
        row["原始_来源"] = raw.get("来源", "")
        row["原始_文件名"] = raw.get("原始文件名", "")
    if ledger:
        row["流水_日期"] = ledger["日期"].strftime("%Y-%m-%d %H:%M:%S")
        row["流水_收付手段"] = ledger["收付手段"]
        row["流水_金额"] = ledger["金额"]
        row["流水_收付类型"] = ledger["收付类型"]
        row["流水_类型明细"] = ledger["类型明细"]
        row["流水_备注"] = ledger["备注"]
        row["流水_yyyymm"] = ledger["yyyymm"]
    return row


if __name__ == "__main__":
    main()
