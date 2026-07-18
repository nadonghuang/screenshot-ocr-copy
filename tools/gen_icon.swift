import Cocoa
import CoreGraphics

let size = 1024
let S = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let r = CGRect(x: 0, y: 0, width: size, height: size)

// macOS squircle (continuous corner superellipse approximation via layered rounded rects)
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    // 近似 superellipse：用大圆角 + 内缩描边
    return CGPath(roundedRect: rect.insetBy(dx: rect.width*0.045, dy: rect.height*0.045),
                  cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 1) 暗色底（替代阴影：macOS 26 的 setShadow 签名变更，图标本身由系统渲染阴影）
ctx.addPath(squircle(r, radius: S*0.2237))
ctx.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.22, alpha: 1))
ctx.fillPath()

// 2) 主体渐变背景（深紫蓝 → 品红，科技感）
let path = squircle(r, radius: S*0.2237)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.28, green: 0.22, blue: 0.62, alpha: 1),  // 顶 紫
    CGColor(red: 0.16, green: 0.30, blue: 0.72, alpha: 1),  // 中 蓝
    CGColor(red: 0.08, green: 0.14, blue: 0.40, alpha: 1),  // 底 深蓝
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
ctx.restoreGState()

// 3) 顶部高光（玻璃质感）
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let gloss = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0, 0.5])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

// 4) 中心：截图选框（四角L形括号）+ 文本行
let cx: CGFloat = 512
let boxSide: CGFloat = 460
let boxX = cx - boxSide/2
let boxY = (1024 - boxSide)/2
let boxRect = CGRect(x: boxX, y: boxY, width: boxSide, height: boxSide)
let corner: CGFloat = 110
let thick: CGFloat = 34
let accent = CGColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)   // 青蓝

// 四角括号
ctx.setLineWidth(thick)
ctx.setLineCap(.round)
ctx.setStrokeColor(accent)
// 左上
ctx.addLines(between: [CGPoint(x: boxX+thick/2, y: boxY+boxSide-thick/2),
                       CGPoint(x: boxX+thick/2, y: boxY+boxSide-corner),
                       CGPoint(x: boxX+corner, y: boxY+boxSide-thick/2)])
ctx.strokePath()
// 右上
ctx.addLines(between: [CGPoint(x: boxX+boxSide-thick/2, y: boxY+boxSide-thick/2),
                       CGPoint(x: boxX+boxSide-corner, y: boxY+boxSide-thick/2),
                       CGPoint(x: boxX+boxSide-thick/2, y: boxY+boxSide-corner)])
ctx.strokePath()
// 左下
ctx.addLines(between: [CGPoint(x: boxX+thick/2, y: boxY+thick/2),
                       CGPoint(x: boxX+thick/2, y: boxY+corner),
                       CGPoint(x: boxX+corner, y: boxY+thick/2)])
ctx.strokePath()
// 右下
ctx.addLines(between: [CGPoint(x: boxX+boxSide-thick/2, y: boxY+thick/2),
                       CGPoint(x: boxX+boxSide-corner, y: boxY+thick/2),
                       CGPoint(x: boxX+boxSide-thick/2, y: boxY+corner)])
ctx.strokePath()

// 5) 文本行（代表识别出的文字）：三条横线，中间断开模拟 OCR 高亮
let lineColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
ctx.setFillColor(lineColor)
let linesY: [CGFloat] = [600, 512, 424]
let lineH: CGFloat = 30
let left = boxX + 90
let right = boxX + boxSide - 90
for (i, y) in linesY.enumerated() {
    let w = i == 1 ? (right-left)*0.62 : (right-left)   // 中间线短
    ctx.fill(CGRect(x: left, y: y, width: w, height: lineH))
}

// 中间线上叠加高亮扫描条（青色半透明，代表正在识别）
ctx.setFillColor(CGColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.35))
ctx.fill(CGRect(x: left, y: 512-6, width: (right-left), height: lineH+12))

// 6) 外圈细描边（玻璃边缘）
ctx.addPath(path)
ctx.setLineWidth(3)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
ctx.strokePath()

guard let img = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: "/Users/jznano/Desktop/开发/截图复制/build/icon_assets/icon_1024.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("icon_1024.png written")
