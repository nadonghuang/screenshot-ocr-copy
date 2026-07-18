import Cocoa
import CoreGraphics

// ============================================================
// README 横幅：直接加载真实应用图标 assets/icon_1024.png
// 保证横幅与图标永远同步
// ============================================================

let W = 1280
let H = 320
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// macOS squircle（与图标外框一致的圆角）
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect.insetBy(dx: rect.width*0.045, dy: rect.height*0.045),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// ---------- 1) 背景：深蓝渐变（衬托白色图标） ----------
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.10, green: 0.32, blue: 0.85, alpha: 1.0),
    CGColor(red: 0.04, green: 0.16, blue: 0.55, alpha: 1.0),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// ---------- 2) 加载真实图标 ----------
let iconFilePath = "/Users/jznano/Desktop/开发/截图复制/assets/icon_1024.png"
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: iconFilePath) as CFURL, nil),
      let iconImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("❌ 无法加载 \(iconFilePath)，请先生成图标")
}

// ---------- 3) 左侧：绘制真实图标（带 squircle 裁剪 + 阴影） ----------
let iconSize: CGFloat = 220
let iconX: CGFloat = 60
let iconY = (CGFloat(H) - iconSize) / 2
let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
let iconPath = squircle(iconRect, radius: iconSize * 0.2237)

// 阴影外圈
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(iconPath)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.001))
ctx.fillPath()
ctx.restoreGState()

// 裁剪到 squircle 后绘制真实图标
ctx.saveGState()
ctx.addPath(iconPath)
ctx.clip()
ctx.draw(iconImage, in: iconRect)
ctx.restoreGState()

// ---------- 4) 右侧文字 ----------
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

// 标题
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
print("✓ banner.png 已生成（直接使用真实图标，1280x320）")
