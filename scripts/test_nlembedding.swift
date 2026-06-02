import Foundation
import NaturalLanguage

let sep = String(repeating: "=", count: 60)

print(sep)
print("NLEmbedding 中文语义测试 (zh-Hans, 640维)")
print(sep)

guard let emb = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) else {
    print("✗ 不可用")
    exit(1)
}
print("✓ 可用, 维度: \(emb.dimension)")

// ── 工具 ──
func cosSim(_ a: [Double], _ b: [Double]) -> Double {
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<a.count { dot += a[i]*b[i]; na += a[i]*a[i]; nb += b[i]*b[i] }
    return dot / (sqrt(na) * sqrt(nb))
}
func embVec(_ t: String) -> [Double]? { emb.vector(for: t) }
func pad(_ s: String, _ n: Int) -> String {
    String(s.prefix(n)) + String(repeating: " ", count: max(0, n - s.count))
}

// ── 测试 1: 语义相似度 ──
print("\n" + sep)
print("语义相似度")
print(sep)

let pairs: [(String, String, String)] = [
    ("星巴克咖啡", "瑞幸咖啡", "同咖啡→应近"),
    ("星巴克咖啡", "肯德基汉堡", "咖啡vs快餐→应远"),
    ("星巴克咖啡", "京东商城", "咖啡vs网购→应远"),
    ("公交地铁通勤", "滴滴打车出行", "同交通→应近"),
    ("美团外卖点餐", "饿了么点餐", "同外卖→应近"),
    ("美团外卖点餐", "健身房私教课", "外卖vs健身→应远"),
    ("菜市场买菜", "永辉超市买菜", "同买菜→应近"),
    ("支付宝转账", "微信转账", "同转账→应近"),
    ("京东购物", "淘宝天猫购物", "同网购→应近"),
    ("加油中石化", "充电特斯拉", "加油vs充电→?"),
]

for (a, b, expected) in pairs {
    guard let va = embVec(a), let vb = embVec(b) else { continue }
    let s = cosSim(va, vb)
    let bar = String(repeating: "#", count: max(0, Int(s * 35)))
    let m = s > 0.65 ? "✓" : (s > 0.4 ? "~" : "✗")
    print("  \(pad(a,18)) vs \(pad(b,18)) = \(String(format:"%.3f",s)) \(bar) \(m) \(expected)")
}

// ── 测试 2: M Stand 泛化 ──
print("\n" + sep)
print("关键测试: M Stand Coffee（新品牌，训练集未见过）")
print(sep)

guard let mstand = embVec("M Stand Coffee 冰美式拿铁") else { exit(1) }

let anchors: [(String, String)] = [
    ("咖啡", "星巴克抹茶拿铁三里屯"),
    ("外卖", "美团外卖订单付款"),
    ("购物", "京东商城网上购物"),
    ("交通", "滴滴出行快车"),
    ("健身", "Keep健身会员续费"),
    ("买菜", "盒马鲜生买菜"),
]

print()
print("  M Stand 与各类代表文本的相似度:")
print("  " + String(repeating: "-", count: 50))
for (label, text) in anchors {
    guard let v = embVec(text) else { continue }
    let s = cosSim(mstand, v)
    let bar = String(repeating: "#", count: max(0, Int(s * 40)))
    print("  vs \(pad(label,6)) (\(pad(text,24))): \(String(format:"%.3f",s)) \(bar)")
}

// ── 测试 3: 批量新商户 ──
print("\n" + sep)
print("批量新商户泛化（n-gram 模型无法识别的）")
print(sep)

let news = [
    "Peets Coffee 皮爷咖啡美式",
    "奈雪的茶霸气草莓",
    "霸王茶姬伯牙绝弦",
    "山姆会员店进口商品",
    "米其林三星法餐晚餐",
    "泡泡玛特开盲盒",
    "GymBox 私教课月卡",
    "中国石化 95号汽油 加油",
    "自如房租 押一付三",
    "特斯拉超充站充电",
]

print()
for text in news {
    guard let vt = embVec(text) else { continue }
    var bestLabel = "", bestSim = 0.0
    for (label, anchor) in anchors {
        guard let va = embVec(anchor) else { continue }
        let s = cosSim(vt, va)
        if s > bestSim { bestSim = s; bestLabel = label }
    }
    let bar = String(repeating: "#", count: max(0, Int(bestSim * 40)))
    let m = bestSim > 0.5 ? "✓" : (bestSim > 0.3 ? "~" : "✗")
    print("  \(pad(text,30)) → \(pad(bestLabel,6)) \(String(format:"%.3f",bestSim)) \(bar) \(m)")
}

// ── 测试 4: 真实账单数据 10 条 ──
print("\n" + sep)
print("真实账单数据测试（你的数据）")
print(sep)

let realCases: [(String, String)] = [
    ("MTDP-鲜果时间（世纪金源1店）", "饮品"),
    ("港滋味港式烧腊饭(科技园店)外卖订单", "餐饮"),
    ("滴滴出行-快车-机场送机", "交通"),
    ("京东-订单编号314314035808", "购物"),
    ("luckin coffee-拿铁-深圳湾店", "咖啡"),
    ("友望洗地机 1/6 分期", "大件购物"),
    ("中国平安-意外险-月缴", "保险"),
    ("美团外卖-煲仔饭-酸菜鱼", "外卖"),
    ("花小猪打车-机场", "交通"),
    ("广发信用卡-账单还款", "金融/还款"),
]

print()
for (text, expected) in realCases {
    guard let vt = embVec(text) else { print("  \(pad(text,40)) → nil"); continue }
    var best = ("", 0.0)
    for (label, anchor) in anchors {
        guard let va = embVec(anchor) else { continue }
        let s = cosSim(vt, va)
        if s > best.1 { best = (label, s) }
    }
    let bar = String(repeating: "#", count: max(0, Int(best.1 * 40)))
    let m = best.1 > 0.5 ? "✓" : (best.1 > 0.3 ? "~" : "✗")
    print("  \(pad(text,40)) → \(pad(best.0,6)) \(String(format:"%.3f",best.1)) \(bar) \(m) 预期:\(expected)")
}

print("\n" + sep)
