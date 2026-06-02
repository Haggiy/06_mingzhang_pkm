"""
合并原始账单目录下所有支付宝/微信账单文件为统一 CSV。

保留全部原始列，支付宝/微信各自独有的列在对方行留空。
新增「来源」列标记支付宝/微信。

输出: docs/data/合并原始账单.csv
"""

from __future__ import annotations

import csv
import glob
import os
import re
import sys
from datetime import datetime
from typing import Optional

DATA_DIR = "docs/data/原始账单_汇总_副本"
OUTPUT_FILE = "docs/data/合并原始账单.csv"

# ── 统一输出列（全量保留） ──
# 共享列用统一名称，来源独有列保持原名
OUTPUT_COLS = [
    # 共享列
    "交易时间",
    "交易对方",
    "商品说明",
    "收/支",
    "金额",
    "收付款方式",
    "交易状态",
    "备注",
    # 同义合并列（支付宝/微信各自填入）
    "平台交易分类",   # 支付宝:交易分类  微信:交易类型
    "交易单号",       # 支付宝:交易订单号 微信:交易单号
    "商户单号",       # 支付宝:商家订单号 微信:商户单号
    # 支付宝独有
    "对方账号",
    # 元数据
    "来源",
    "原始文件名",
]

# ── 计数器 ──
stats = {"alipay": 0, "wechat_csv": 0, "wechat_xlsx": 0,
         "skipped_empty": 0, "errors": 0}


# ══════════════════════════════════════════════
# 支付宝通用解析
# ══════════════════════════════════════════════

def parse_alipay(filepath: str) -> list[dict]:
    """动态检测表头行和列映射，保留全部原始列。"""
    rows = []
    try:
        with open(filepath, "r", encoding="gbk", errors="replace") as f:
            lines = f.readlines()
        if len(lines) < 3:
            return rows

        # 找到表头
        header_idx = -1
        for i, line in enumerate(lines):
            stripped = line.strip().replace(" ", "")
            key_cols = ["交易时间", "交易对方", "商品说明", "金额", "收/支", "交易分类"]
            matches = sum(1 for k in key_cols if k in stripped)
            if matches >= 4:
                header_idx = i
                break
        if header_idx < 0:
            return rows

        header_parts = [h.strip() for h in lines[header_idx].strip().split(",")]
        col_map = {name: idx for idx, name in enumerate(header_parts)}

        for line in lines[header_idx + 1:]:
            line = line.strip()
            if not line or line.startswith("-"):
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < max(8, len(header_parts) - 2):
                continue

            def get(col_name: str) -> str:
                idx = col_map.get(col_name)
                if idx is not None and idx < len(parts):
                    return parts[idx].replace("\t", "")
                return ""

            amount_str = get("金额")
            if not amount_str:
                # 旧版变体可能有"金额(元)"之类的
                for key in col_map:
                    if "金额" in key:
                        amount_str = get(key)
                        break
            if not amount_str:
                stats["skipped_empty"] += 1
                continue

            rows.append({
                "交易时间":       get("交易时间"),
                "交易对方":       get("交易对方"),
                "商品说明":       get("商品说明"),
                "收/支":         get("收/支"),
                "金额":           amount_str,
                "收付款方式":     get("收/付款方式"),
                "交易状态":       get("交易状态"),
                "备注":           get("备注"),
                "平台交易分类":   get("交易分类"),
                "交易单号":       get("交易订单号"),
                "商户单号":       get("商家订单号"),
                "对方账号":       get("对方账号"),
                "来源":           "支付宝",
                "原始文件名":     os.path.basename(filepath),
            })
    except Exception as e:
        print(f"  [ERROR] {os.path.basename(filepath)}: {e}", file=sys.stderr)
        stats["errors"] += 1
    return rows


# ══════════════════════════════════════════════
# 微信 CSV
# ══════════════════════════════════════════════

def parse_wechat_csv(filepath: str) -> list[dict]:
    rows = []
    try:
        with open(filepath, "r", encoding="utf-8-sig", errors="replace") as f:
            lines = f.readlines()
        if len(lines) < 3:
            return rows

        header_idx = -1
        for i in range(min(20, len(lines))):
            if "交易时间" in lines[i] and "交易类型" in lines[i]:
                header_idx = i
                break
        if header_idx < 0:
            return rows

        header_parts = _split_csv_line(lines[header_idx].strip())
        header_parts = [h.strip() for h in header_parts]
        col_map = {name: idx for idx, name in enumerate(header_parts)}

        for line in lines[header_idx + 1:]:
            line = line.strip()
            if not line:
                continue
            parts = _split_csv_line(line)
            parts = [p.strip() for p in parts]
            if len(parts) < 8:
                continue

            def get(col_name: str) -> str:
                idx = col_map.get(col_name)
                if idx is not None and idx < len(parts):
                    return parts[idx].replace("\t", "")
                return ""

            amount_str = get("金额(元)")
            if not amount_str:
                for key in col_map:
                    if "金额" in key:
                        amount_str = get(key)
                        break
            amount_str = amount_str.replace("¥", "")
            if not amount_str:
                stats["skipped_empty"] += 1
                continue

            rows.append({
                "交易时间":       get("交易时间"),
                "交易对方":       get("交易对方"),
                "商品说明":       get("商品"),
                "收/支":         get("收/支"),
                "金额":           amount_str,
                "收付款方式":     get("支付方式"),
                "交易状态":       get("当前状态"),
                "备注":           get("备注"),
                "平台交易分类":   get("交易类型"),
                "交易单号":       get("交易单号"),
                "商户单号":       get("商户单号"),
                "对方账号":       "",
                "来源":           "微信",
                "原始文件名":     os.path.basename(filepath),
            })
    except Exception as e:
        print(f"  [ERROR] {os.path.basename(filepath)}: {e}", file=sys.stderr)
        stats["errors"] += 1
    return rows


# ══════════════════════════════════════════════
# 微信 XLSX
# ══════════════════════════════════════════════

def parse_wechat_xlsx(filepath: str) -> list[dict]:
    rows = []
    try:
        import openpyxl
        wb = openpyxl.load_workbook(filepath, read_only=True)
        ws = wb.active
        all_rows = list(ws.iter_rows(min_row=1, values_only=True))

        header_idx = -1
        for i, row in enumerate(all_rows):
            if row and row[0] and "交易时间" in str(row[0]):
                header_idx = i
                break
        if header_idx < 0:
            return rows

        header = [str(c).strip() if c else "" for c in all_rows[header_idx]]
        col_map = {name: idx for idx, name in enumerate(header)}

        for row in all_rows[header_idx + 1:]:
            if not row or not row[0]:
                continue

            def get(col_name: str) -> str:
                idx = col_map.get(col_name)
                if idx is not None and idx < len(row) and row[idx] is not None:
                    return str(row[idx]).replace("\t", "").strip()
                return ""

            amount_str = get("金额(元)")
            if not amount_str:
                for key in col_map:
                    if "金额" in key:
                        amount_str = get(key)
                        break
            amount_str = amount_str.replace("¥", "")
            if not amount_str or amount_str in ("None", ""):
                stats["skipped_empty"] += 1
                continue

            rows.append({
                "交易时间":       get("交易时间"),
                "交易对方":       get("交易对方"),
                "商品说明":       get("商品"),
                "收/支":         get("收/支"),
                "金额":           amount_str,
                "收付款方式":     get("支付方式"),
                "交易状态":       get("当前状态"),
                "备注":           get("备注"),
                "平台交易分类":   get("交易类型"),
                "交易单号":       get("交易单号"),
                "商户单号":       get("商户单号"),
                "对方账号":       "",
                "来源":           "微信",
                "原始文件名":     os.path.basename(filepath),
            })
    except Exception as e:
        print(f"  [ERROR] {os.path.basename(filepath)}: {e}", file=sys.stderr)
        stats["errors"] += 1
    return rows


# ══════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════

def _split_csv_line(line: str) -> list[str]:
    result = []
    current = ""
    in_quotes = False
    for ch in line:
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == ',' and not in_quotes:
            result.append(current)
            current = ""
        else:
            current += ch
    result.append(current)
    return result


def classify_file(filename: str) -> Optional[str]:
    base = os.path.basename(filename)
    ext = base.lower()
    if ext.endswith(".xlsx"):
        return "wechat_xlsx" if "微信支付" in base else None
    if ext.endswith(".csv"):
        if base.startswith("支付宝交易明细") or base.startswith("alipay_record"):
            return "alipay"
        if "微信支付" in base:
            return "wechat_csv"
        return None
    return None


def normalize_time(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return raw
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})", raw)
    if m:
        return raw
    m = re.match(r"(\d{4})/(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?", raw)
    if m:
        y, mo, d, h, mi = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
        s = m.group(6) or "00"
        return f"{int(y):04d}-{int(mo):02d}-{int(d):02d} {int(h):02d}:{int(mi):02d}:{int(s):02d}"
    for fmt in ["%Y-%m-%d %H:%M:%S", "%Y/%m/%d %H:%M:%S", "%Y/%m/%d %H:%M"]:
        try:
            dt = datetime.strptime(raw, fmt)
            return dt.strftime("%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
    return raw


# ══════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════

def main():
    print("=" * 60)
    print("合并原始账单文件（全量保留原始列）")
    print("=" * 60)

    files = sorted(glob.glob(os.path.join(DATA_DIR, "*")))
    csv_files = [f for f in files if classify_file(f)]

    print(f"原始账单目录: {DATA_DIR}")
    print(f"总文件数: {len(files)}")
    print(f"可识别账单数: {len(csv_files)}")
    print(f"输出列数: {len(OUTPUT_COLS)}")
    print()

    all_rows = []
    seen = set()

    for i, filepath in enumerate(csv_files):
        ftype = classify_file(filepath)
        filename = os.path.basename(filepath)

        if ftype == "alipay":
            rows = parse_alipay(filepath)
            stats["alipay"] += len(rows)
        elif ftype == "wechat_csv":
            rows = parse_wechat_csv(filepath)
            stats["wechat_csv"] += len(rows)
        elif ftype == "wechat_xlsx":
            rows = parse_wechat_xlsx(filepath)
            stats["wechat_xlsx"] += len(rows)
        else:
            rows = []

        dupes = 0
        for row in rows:
            row["交易时间"] = normalize_time(row["交易时间"])
            key = (row["交易时间"], row["金额"], row["交易对方"])
            if key in seen:
                dupes += 1
                continue
            seen.add(key)
            all_rows.append(row)

        label = f"{ftype:12s}"
        print(f"[{i+1:3d}/{len(csv_files)}] {label} {filename[:65]} → {len(rows):4d} 行 (新增 {len(rows)-dupes})")

    all_rows.sort(key=lambda r: r["交易时间"] if r["交易时间"] else "z")

    print(f"\n写入 {OUTPUT_FILE} ...")
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=OUTPUT_COLS, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(all_rows)

    print()
    print("=" * 60)
    print("合并完成!")
    print(f"  支付宝:          {stats['alipay']:>8,} 条")
    print(f"  微信 CSV:        {stats['wechat_csv']:>8,} 条")
    print(f"  微信 XLSX:       {stats['wechat_xlsx']:>8,} 条")
    print(f"  跳过(空金额):    {stats['skipped_empty']:>8,} 条")
    print(f"  解析错误:        {stats['errors']:>8,} 个文件")
    print(f"  ─────────────────────────────")
    print(f"  去重后总计:      {len(all_rows):>8,} 条")
    print(f"  输出列数:        {len(OUTPUT_COLS)} 列")
    print(f"  输出文件: {OUTPUT_FILE}")

    valid_rows = [r for r in all_rows if r["交易时间"]]
    if valid_rows:
        print(f"  时间范围: {valid_rows[0]['交易时间']} ~ {valid_rows[-1]['交易时间']}")

    alipay_count = sum(1 for r in all_rows if r["来源"] == "支付宝")
    wechat_count = sum(1 for r in all_rows if r["来源"] == "微信")
    print(f"    支付宝: {alipay_count:,}  微信: {wechat_count:,}")


if __name__ == "__main__":
    main()
