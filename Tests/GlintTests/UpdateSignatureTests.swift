import Testing
import Foundation
@testable import Glint

struct UpdateSignatureTests {
    @Test func testUpdatesKeepTheSigningIdentityAcrossDifferentBinaries() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".cache/signature-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try await fixture(in: root, version: "1")
        let update = try await fixture(in: root, version: "2")
        #expect(try Data(contentsOf: current.appendingPathComponent("Contents/MacOS/Glint")) != Data(contentsOf: update.appendingPathComponent("Contents/MacOS/Glint")))
        try UpdateSignature.validate(update, replacing: current)

        try await NativeProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", update.path])
        #expect(throws: (any Error).self) { try UpdateSignature.validate(update, replacing: current) }
        let original = try Data(contentsOf: current.appendingPathComponent("Contents/MacOS/Glint"))
        #expect(UpdateService.install(arguments: ["Glint", "--install-update", update.path, current.path, String(getpid())]) == 1)
        #expect(try Data(contentsOf: current.appendingPathComponent("Contents/MacOS/Glint")) == original)
    }

    @Test func testTamperedAndUnsignedUpdatesAreRejected() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".cache/signature-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try await fixture(in: root, version: "1")
        let update = try await fixture(in: root, version: "2")
        try Data("modified".utf8).write(to: update.appendingPathComponent("Contents/Resources/content.txt"))
        #expect(throws: (any Error).self) { try UpdateSignature.validate(update, replacing: current) }

        try await NativeProcess.run("/usr/bin/codesign", ["--remove-signature", update.path])
        #expect(throws: (any Error).self) { try UpdateSignature.validate(update, replacing: current) }
    }

    private func fixture(in root: URL, version: String) async throws -> URL {
        let app = root.appendingPathComponent("v\(version)/Glint.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.skywalker144.glint", "CFBundleExecutable": "Glint", "CFBundlePackageType": "APPL", "CFBundleVersion": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("original".utf8).write(to: contents.appendingPathComponent("Resources/content.txt"))
        let source = app.deletingLastPathComponent().appendingPathComponent("main.c")
        try Data("int main(void) { return \(version); }".utf8).write(to: source)
        try await NativeProcess.run("/usr/bin/xcrun", ["clang", source.path, "-o", contents.appendingPathComponent("MacOS/Glint").path])
        try await NativeProcess.run("/bin/bash", ["scripts/signing.sh", "sign", app.path])
        return app
    }
}
