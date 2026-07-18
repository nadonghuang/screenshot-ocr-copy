import Cocoa
import CoreGraphics

// ⚠️ 已废弃：图标设计源已迁移至 assets/icon.svg（柔和拟物化 squircle）。
//    本脚本生成的是旧版扁平风格，保留仅作历史参考，不参与构建流程。
//    改图标请编辑 icon.svg → 渲染覆盖 icon_1024.png → ./build.sh。

// ============================================================
// 极简苹果官方风应用图标：蓝渐变 squircle + 文档卡片 + OCR 扫描光带
// 参考：Notes / Pages / Finder 的极简视觉语言
// ============================================================

let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let r = CGRect(x: 0, y: 0, width: size, height: size)

// macOS squircle（连续圆角超椭圆近似）
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect.insetBy(dx: rect.width*0.045, dy: rect.height*0.045),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let path = squircle(r, radius: S*0.2237)

// ---------- 1) 主体：明亮蓝色渐变（苹果系统蓝） ----------
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.24, green: 0.62, blue: 1.00, alpha: 1.0),  // 亮蓝（顶）
    CGColor(red: 0.11, green: 0.44, blue: 0.96, alpha: 1.0),  // 中蓝
    CGColor(red: 0.07, green: 0.30, blue: 0.88, alpha: 1.0),  // 深蓝（底）
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
ctx.restoreGState()

// ---------- 2) 极轻微顶部光泽（玻璃质感，非常克制） ----------
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let gloss = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 0.5])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 512), options: [])
ctx.restoreGState()

// ---------- 3) 中心：白色文档卡片（代表被识别的文字区域） ----------
let cardW: CGFloat = 480
let cardH: CGFloat = 360
let cardX = (S - cardW) / 2
let cardY = (S - cardH) / 2
let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 32, cornerHeight: 32, transform: nil)

// 卡片阴影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
ctx.addPath(cardPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
ctx.fillPath()
ctx.restoreGState()

// ---------- 4) 卡片上的文字行（三行，代表识别出的文字） ----------
ctx.setFillColor(CGColor(red: 0.32, green: 0.40, blue: 0.55, alpha: 1.0))  // 深蓝灰
let textLeft = cardX + 56
let textRight = cardX + cardW - 56
let textW = textRight - textLeft
let rowH: CGFloat = 28
let rows: [(y: CGFloat, w: CGFloat)] = [
    (cardY + cardH - 92, textW * 0.95),
    (cardY + cardH - 150, textW * 0.68),
    (cardY + cardH - 208, textW * 0.85),
]
for row in rows {
    ctx.fill(CGRect(x: textLeft, y: row.y, width: row.w, height: rowH))
}

// ---------- 5) OCR 扫描光带（贯穿卡片，代表文字识别） ----------
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
// 主光带
let beamY: CGFloat = cardY + cardH - 270
let beamGrad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.10, green: 0.45, blue: 1.0, alpha: 0.0),
    CGColor(red: 0.10, green: 0.55, blue: 1.0, alpha: 1.0),
    CGColor(red: 0.10, green: 0.45, blue: 1.0, alpha: 0.0),
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(beamGrad, start: CGPoint(x: cardX, y: beamY), end: CGPoint(x: cardX + cardW, y: beamY), options: [])
// 光带高光细线
ctx.setFillColor(CGColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.9))
ctx.fill(CGRect(x: cardX, y: beamY - 2, width: cardW, height: 4))
ctx.restoreGState()

// ---------- 6) 外圈细描边（玻璃边缘） ----------
ctx.addPath(path)
ctx.setLineWidth(3)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.strokePath()

// ---------- 输出 ----------
let outDir = "/Users/jznano/Desktop/开发/截图复制/build/icon_assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let img = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: outDir + "/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("✓ icon_1024.png written (minimal Apple style: blue squircle + document + scan beam)")
