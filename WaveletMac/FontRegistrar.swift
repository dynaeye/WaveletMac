import CoreText
import Foundation

enum FontRegistrar {
    private static let fontNames = ["Archivo", "Inter", "NotoSansSC", "SpaceMono"]

    static func registerBundledFonts(bundle: Bundle = .main) {
        for name in fontNames {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
