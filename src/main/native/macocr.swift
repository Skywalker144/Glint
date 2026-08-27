// macOS 原生 OCR：从 stdin 读取图片，用 Vision 识别文字，按阅读顺序输出到 stdout。
// 被 Electron 主进程（ocr.js）首次使用时用 swiftc 编译并缓存。

import Foundation
import AppKit
import Vision

func tryRecognize(_ cgImage: CGImage, languages: [String]) -> [VNRecognizedTextObservation]? {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  request.recognitionLanguages = languages
  let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
  do {
    try handler.perform([request])
  } catch {
    return nil
  }
  return request.results
}

func recognize(_ cgImage: CGImage) -> [String] {
  // 优先中英日韩；若某语言在当前系统不支持导致失败，退回中英文。
  let observations =
    tryRecognize(cgImage, languages: ["zh-Hans", "zh-Hant", "en-US", "ja", "ko"])
    ?? tryRecognize(cgImage, languages: ["zh-Hans", "en-US"])
    ?? []

  // boundingBox 原点在左下：y 大的在上。先上后下、再左后右，拼出阅读顺序。
  let sorted = observations.sorted { a, b in
    let ay = a.boundingBox.midY, by = b.boundingBox.midY
    if abs(ay - by) > 0.012 { return ay > by }
    return a.boundingBox.minX < b.boundingBox.minX
  }
  return sorted.compactMap { $0.topCandidates(1).first?.string }
}

let data = FileHandle.standardInput.readDataToEndOfFile()
guard !data.isEmpty,
      let image = NSImage(data: data),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  FileHandle.standardError.write("cannot decode image\n".data(using: .utf8)!)
  exit(1)
}

let text = recognize(cg).joined(separator: "\n")
FileHandle.standardOutput.write(text.data(using: .utf8)!)
