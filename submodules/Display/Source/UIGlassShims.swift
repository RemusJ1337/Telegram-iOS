import Foundation
import UIKit
import ObjectiveC

public final class UIGlassEffect: UIVisualEffect {
    public enum Style: Int {
        case regular
        case clear
    }
    
    public var style: Style
    public var tintColor: UIColor?
    public var isInteractive: Bool
    
    public init(style: Style) {
        self.style = style
        self.tintColor = nil
        self.isInteractive = false
        super.init()
    }
    
    public override init() {
        self.style = .regular
        self.tintColor = nil
        self.isInteractive = false
        super.init()
    }
    
    public required init?(coder: NSCoder) {
        self.style = .regular
        self.tintColor = nil
        self.isInteractive = false
        super.init(coder: coder)
    }
}

public final class UIGlassContainerEffect: UIVisualEffect {
    public var spacing: CGFloat
    
    public override init() {
        self.spacing = 0.0
        super.init()
    }
    
    public required init?(coder: NSCoder) {
        self.spacing = 0.0
        super.init(coder: coder)
    }
}

public struct UICornerRadius: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, Equatable {
    public var value: CGFloat
    
    public init(value: CGFloat) {
        self.value = value
    }
    
    public init(floatLiteral value: Double) {
        self.value = CGFloat(value)
    }
    
    public init(integerLiteral value: Int) {
        self.value = CGFloat(value)
    }
    
    public static func fixed(_ value: CGFloat) -> UICornerRadius {
        return UICornerRadius(value: value)
    }
}

public final class UICornerConfiguration: NSObject {
    public var topLeftRadius: UICornerRadius
    public var topRightRadius: UICornerRadius
    public var bottomLeftRadius: UICornerRadius
    public var bottomRightRadius: UICornerRadius
    
    public init(
        topLeftRadius: UICornerRadius = .fixed(0.0),
        topRightRadius: UICornerRadius = .fixed(0.0),
        bottomLeftRadius: UICornerRadius = .fixed(0.0),
        bottomRightRadius: UICornerRadius = .fixed(0.0)
    ) {
        self.topLeftRadius = topLeftRadius
        self.topRightRadius = topRightRadius
        self.bottomLeftRadius = bottomLeftRadius
        self.bottomRightRadius = bottomRightRadius
        super.init()
    }
    
    public static func corners(radius: UICornerRadius) -> UICornerConfiguration {
        return UICornerConfiguration(
            topLeftRadius: radius,
            topRightRadius: radius,
            bottomLeftRadius: radius,
            bottomRightRadius: radius
        )
    }
    
    public static func corners(
        topLeftRadius: UICornerRadius = .fixed(0.0),
        topRightRadius: UICornerRadius = .fixed(0.0),
        bottomLeftRadius: UICornerRadius = .fixed(0.0),
        bottomRightRadius: UICornerRadius = .fixed(0.0)
    ) -> UICornerConfiguration {
        return UICornerConfiguration(
            topLeftRadius: topLeftRadius,
            topRightRadius: topRightRadius,
            bottomLeftRadius: bottomLeftRadius,
            bottomRightRadius: bottomRightRadius
        )
    }
}

private var cornerConfigurationKey: Int?

public extension UIView {
    var cornerConfiguration: UICornerConfiguration? {
        get {
            return objc_getAssociatedObject(self, &cornerConfigurationKey) as? UICornerConfiguration
        }
        set {
            objc_setAssociatedObject(self, &cornerConfigurationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
