import Cocoa
import CoreGraphics

// ============================================================
// README 横幅：直接加载真实应用图标 assets/icon_1024.png
// 一次性生成 zh / en / ja 三张横幅，与各语言 README 对齐
// ============================================================

let W = 1280
let H = 320
let cs = CGColorSpaceCreateDeviceRGB()

struct BannerLang {
    let code: String            // 输出文件后缀（en 留空 → banner.png）
    let title: String
    let subtitle: String
    let titleFont: String
    let subFont: String
}

let langs: [BannerLang] = [
    BannerLang(code: "",                                                                  // 英文为主，文件名 banner.png
               title: "Screenshot OCR Copy",
               subtitle: "macOS Screenshot OCR Tool  ·  Apple Vision  ·  Zero Dependency",
               titleFont: "SFProDisplay-Bold",
               subFont: "SFProDisplay-Regular"),
    BannerLang(code: ".zh",
               title: "截图 OCR 复制",
               subtitle: "macOS 截图 OCR 工具  ·  Apple Vision  ·  零依赖",
               titleFont: "PingFangSC-Semibold",
               subFont: "PingFangSC-Regular"),
    BannerLang(code: ".ja",
               title: "スクリーンショット OCR コピー",
               subtitle: "macOS スクリーンショット OCR ツール  ·  Apple Vision  ·  依存ゼロ",
               titleFont: "HiraginoSans-W6",
               subFont: "HiraginoSans-W3"),
]

// macOS squircle（与图标外框一致的圆角）
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    return CGPath(roundedRect: rect.insetBy(dx: rect.width*0.045, dy: rect.height*0.045),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 预加载真实图标（三张横幅共用）
let iconFilePath = "/Users/jznano/Desktop/开发/截图复制/assets/icon_1024.png"
guard let nsImage = NSImage(contentsOfFile: iconFilePath) else {
    fatalError("❌ NSImage 无法加载 \(iconFilePath)")
}
guard let iconImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("❌ 无法从 NSImage 获取 CGImage")
}
print("✓ 图标加载成功: \(iconImage.width)x\(iconImage.height)")

func drawText(_ ctx: CGContext, _ text: String, font: CTFont, color: CGColor, at point: CGPoint) {
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

let outDir = "/Users/jznano/Desktop/开发/截图复制/assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// ---------- 逐语言生成 ----------
for lang in langs {
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

    // 1) 背景：深蓝渐变
    let bgGrad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.10, green: 0.32, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.04, green: 0.16, blue: 0.55, alpha: 1.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

    // 2) 左侧真实图标（squircle 裁剪 + 阴影）
    let iconSize: CGFloat = 220
    let iconX: CGFloat = 60
    let iconY = (CGFloat(H) - iconSize) / 2
    let iconRect = CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
    let iconPath = squircle(iconRect, radius: iconSize * 0.2237)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 20,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.addPath(iconPath)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.001))
    ctx.fillPath()
    ctx.restoreGState()

    // 裁剪到 squircle 后绘制真实图标（NSImage 用左上角原点，需翻转 Y 轴）
    ctx.saveGState()
    ctx.addPath(iconPath)
    ctx.clip()
    ctx.saveGState()
    ctx.translateBy(x: 0, y: iconRect.maxY + iconRect.minY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(iconImage, in: CGRect(x: iconRect.origin.x, y: 0, width: iconRect.width, height: iconRect.height))
    ctx.restoreGState()
    ctx.restoreGState()

    // 3) 右侧文字（字体名失败时退回系统默认，避免直接 exit）
    let titleFont = CTFontCreateWithName(lang.titleFont as CFString, 64.0, nil)
    let subFont = CTFontCreateWithName(lang.subFont as CFString, 28.0, nil)
    drawText(ctx, lang.title, font: titleFont,
             color: CGColor(red: 1, green: 1, blue: 1, alpha: 1.0),
             at: CGPoint(x: 330, y: CGFloat(H) - 120))
    drawText(ctx, lang.subtitle, font: subFont,
             color: CGColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.92),
             at: CGPoint(x: 332, y: CGFloat(H) - 175))

    // 4) 输出 PNG
    guard let img = ctx.makeImage() else {
        fatalError("❌ [\(lang.code.isEmpty ? "en" : lang.code)] CGContext makeImage 失败")
    }
    let fileName = lang.code.isEmpty ? "banner.png" : "banner\(lang.code).png"
    let url = URL(fileURLWithPath: outDir + "/" + fileName)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("✓ \(fileName) 已生成（1280×320）")
}
