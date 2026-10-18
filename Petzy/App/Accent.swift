import SwiftUI
import UIKit

/// Акцент приложения. Тёплый в свежем виде и светлее в тёмном: на тёмном фоне
/// тёмный акцент нечитаем, поэтому два значения, а не одно.
enum Accent {
    static let light = UIColor(red: 0.77, green: 0.42, blue: 0.25, alpha: 1)
    static let dark = UIColor(red: 0.91, green: 0.58, blue: 0.42, alpha: 1)

    static let color = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}
