import AppKit
import ApplicationServices

struct SelectionCopyMenu {
    private static let titles: Set<String> = [
        "Copy", "拷贝", "复制", "拷貝", "複製", "コピー", "복사", "Copier", "Copiar", "Copia", "Kopieren",
        "Копировать", "Kopiëren", "Kopiér", "Kopiera", "Kopioi", "Αντιγραφή", "Kopyala", "Salin", "Sao chép",
        "คัดลอก", "Копіювати", "Kopiuj", "Másolás", "Kopírovat", "Kopírovať", "Kopiraj", "Копирај",
        "Копиране", "Kopēt", "Kopijuoti", "Copiază", "העתק", "نسخ", "کپی"
    ]

    static func find(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        guard let value = attribute(application, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let menu = value as! AXUIElement
        let topLevel = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let ordered = topLevel.enumerated().sorted { abs($0.offset - 3) < abs($1.offset - 3) }.map(\.element)
        for root in ordered {
            var pending = [root]
            while let element = pending.popLast() {
                let role = attribute(element, kAXRoleAttribute) as? String
                if role == kAXMenuItemRole {
                    let identifier = attribute(element, kAXIdentifierAttribute) as? String
                    let character = attribute(element, kAXMenuItemCmdCharAttribute) as? String
                    let modifiers = attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber
                    let title = attribute(element, kAXTitleAttribute) as? String ?? ""
                    let isCopy = identifier == "copy:" || (character?.lowercased() == "c" && modifiers?.intValue == 0 && titles.contains(title))
                    if isCopy, attribute(element, kAXEnabledAttribute) as? Bool == true { return element }
                }
                let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                pending.append(contentsOf: children.reversed())
            }
        }
        return nil
    }
}
