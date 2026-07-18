import Cocoa
import CoreGraphics

// ============================================================
// README 横幅：延续应用图标的现代苹果蓝色风格
// 左侧放大镜+文字卡片 icon 元素，右侧 App 名称 + 标语
// ============================================================

let W = 1280
let H = 320
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let canvas = CGRect(x: 0, y: 0, width: W, height: H)

// macOS squircle
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect.insetBy(dx: rect.width*0.045, dy: rect.height*0.045),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// ---------- 1) 背景：深蓝渐变（与图标同色系，但稍深以突出前景） ----------
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.10, green: 0.32, blue: 0.85, alpha: 1.0),
    CGColor(red: 0.04, green: 0.16, blue: 0.55, alpha: 1.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// ---------- 2) 左侧 App 图标元素（缩小版，squircle 造型） ----------
let iconSize: CGFloat = 220
let iconX: CGFloat = 60
let iconY = (CGFloat(H) - iconSize) / 2
let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
let iconPath = squircle(iconRect, radius: iconSize * 0.2237)

// 图标主体蓝色渐变
ctx.saveGState()
ctx.addPath(iconPath)
ctx.clip()
let iconGrad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.22, green: 0.60, blue: 1.00, alpha: 1.0),
    CGColor(red: 0.10, green: 0.42, blue: 0.95, alpha: 1.0),
    CGColor(red: 0.06, green: 0.28, blue: 0.85, alpha: 1.0),
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(iconGrad, start: CGPoint(x: iconX+iconSize/2, y: iconY+iconSize),
                       end: CGPoint(x: iconX+iconSize/2, y: iconY), options: [])
// 顶部高光
let gloss = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 0.55])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: iconX+iconSize/2, y: iconY+iconSize),
                       end: CGPoint(x: iconX+iconSize/2, y: iconY+iconSize*0.45), options: [])
ctx.restoreGState()

// 图标阴影外圈
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(iconPath)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.001))
ctx.fillPath()
ctx.restoreGState()

// 卡片
let cardScale: CGFloat = iconSize / 1024
let cardW: CGFloat = 440 * cardScale
let cardH: CGFloat = 300 * cardScale
let cardCx = iconX + iconSize/2
let cardCy = iconY + iconSize/2 - 10
let cardRect = CGRect(x: cardCx - cardW/2, y: cardCy - cardH/2, width: cardW, height: cardH)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 28*cardScale, cornerHeight: 28*cardScale, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.20))
ctx.addPath(cardPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
ctx.fillPath()
ctx.restoreGState()
// 卡片文字行
ctx.setFillColor(CGColor(red: 0.30, green: 0.38, blue: 0.52, alpha: 1.0))
let tL = cardRect.minX + 50*cardScale
let tR = cardRect.maxX - 50*cardScale
let tW = tR - tL
let rowH: CGFloat = 26*cardScale
let rows: [(y: CGFloat, w: CGFloat)] = [
    (cardRect.maxY - 70*cardScale, tW),
    (cardRect.maxY - 120*cardScale, tW * 0.68),
    (cardRect.maxY - 170*cardScale, tW * 0.88),
]
for row in rows {
    ctx.fill(CGRect(x: tL, y: row.y, width: row.w, height: rowH))
}

// 放大镜（右上方）
let lensR: CGFloat = 150 * cardScale
let lensCx = cardRect.maxX - 70*cardScale
let lensCy = cardRect.maxY - 50*cardScale
ctx.setLineWidth(46*cardScale)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
let a: CGFloat = .pi/4
let hStart = CGPoint(x: lensCx + cos(a)*(lensR-10*cardScale), y: lensCy - sin(a)*(lensR-10*cardScale))
let hEnd = CGPoint(x: hStart.x + cos(a)*150*cardScale, y: hStart.y - sin(a)*150*cardScale)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8*cardScale,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
ctx.addLines(between: [hStart, hEnd])
ctx.strokePath()
ctx.restoreGState()
ctx.setLineWidth(42*cardScale)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10*cardScale,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
ctx.addEllipse(in: CGRect(x: lensCx-lensR, y: lensCy-lensR, width: lensR*2, height: lensR*2))
ctx.strokePath()
ctx.restoreGState()
let lensInnerR = lensR - 21*cardScale
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: lensCx-lensInnerR, y: lensCy-lensInnerR,
                          width: lensInnerR*2, height: lensInnerR*2))
ctx.clip()
ctx.setFillColor(CGColor(red: 0.10, green: 0.30, blue: 0.70, alpha: 1.0))
ctx.fill(CGRect(x: lensCx-lensInnerR, y: lensCy-16*cardScale, width: lensInnerR*2*0.70, height: 32*cardScale))
ctx.fill(CGRect(x: lensCx-lensInnerR, y: lensCy+24*cardScale, width: lensInnerR*2*0.50, height: 28*cardScale))
ctx.restoreGState()

// ---------- 3) 右侧文字（App 名称 + 标语） ----------
func drawText(_ text: String, font: CTFont, color: CGColor, at point: CGPoint) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let astr = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(astr)
    ctx.saveGState()
    ctx.textPosition = point
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// 标题（大字）
guard let titleFont = CTFontCreateWithName("SFProDisplay-Bold" as CFString, 64.0, nil) as CTFont? else { exit(3) }
drawText("Screenshot OCR Copy",
         font: titleFont,
         color: CGColor(red: 1, green: 1, blue: 1, alpha: 1.0),
         at: CGPoint(x: 330, y: CGFloat(H) - 120))

// 标语
guard let subFont = CTFontCreateWithName("SFProDisplay-Regular" as CFString, 28.0, nil) as CTFont? else { exit(4) }
drawText("macOS Screenshot OCR Tool  ·  Apple Vision  ·  Zero Dependency",
         font: subFont,
         color: CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.92),
         at: CGPoint(x: 332, y: CGFloat(H) - 175))

// ---------- 输出 ----------
let outDir = "/Users/jznano/Desktop/开发/截图复制/assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let img = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: outDir + "/banner.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("✓ banner.png written (1280x320, Apple-style)")
