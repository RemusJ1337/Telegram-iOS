import Foundation
import UIKit
import Display
import ComponentFlow
import MeshTransform

private let backdropLayerClass: NSObject? = {
    let name = ("CA" as NSString).appendingFormat("BackdropLayer")
    if let cls = NSClassFromString(name as String) as AnyObject as? NSObject {
        return cls
    }
    return nil
}()

@inline(__always)
private func getMethod<T>(object: NSObject, selector: String) -> T? {
    guard let method = object.method(for: NSSelectorFromString(selector)) else {
        return nil
    }
    return unsafeBitCast(method, to: T.self)
}

private var cachedBackdropLayerAllocMethod: (@convention(c) (AnyObject, Selector) -> NSObject?, Selector)?
private func invokeBackdropLayerCreateMethod() -> NSObject? {
    guard let backdropLayerClass = backdropLayerClass else {
        return nil
    }
    if let cachedBackdropLayerAllocMethod {
        return cachedBackdropLayerAllocMethod.0(backdropLayerClass, cachedBackdropLayerAllocMethod.1)
    } else {
        let method: (@convention(c) (AnyObject, Selector) -> NSObject?)? = getMethod(object: backdropLayerClass, selector: "alloc")
        if let method {
            let selector = NSSelectorFromString("alloc")
            cachedBackdropLayerAllocMethod = (method, selector)
            return method(backdropLayerClass, selector)
        } else {
            return nil
        }
    }
}

private var cachedBackdropLayerInitMethod: (@convention(c) (NSObject, Selector) -> NSObject?, Selector)?
private func invokeBackdropLayerInitMethod(object: NSObject) -> NSObject? {
    if let cachedBackdropLayerInitMethod {
        return cachedBackdropLayerInitMethod.0(object, cachedBackdropLayerInitMethod.1)
    } else {
        let method: (@convention(c) (AnyObject, Selector) -> NSObject?)? = getMethod(object: object, selector: "init")
        if let method {
            let selector = NSSelectorFromString("init")
            cachedBackdropLayerInitMethod = (method, selector)
            return method(object, selector)
        } else {
            return nil
        }
    }
}

public func createBackdropLayer() -> CALayer? {
    return invokeBackdropLayerCreateMethod().flatMap(invokeBackdropLayerInitMethod) as? CALayer
}

final class LegacyGlassView: UIView {
    enum Style {
        case normal
        case clear
    }
    
    private struct Params: Equatable {
        let size: CGSize
        let shape: GlassBackgroundView.Shape
        let style: Style
        let isDark: Bool
        
        init(size: CGSize, shape: GlassBackgroundView.Shape, style: Style, isDark: Bool) {
            self.size = size
            self.shape = shape
            self.style = style
            self.isDark = isDark
        }
    }
    
    private var params: Params?
    private var maskLayer: CAShapeLayer?
    
    private let blurView: UIVisualEffectView
    
    override init(frame: CGRect) {
        let blurEffect = UIBlurEffect(style: .systemMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        self.blurView = blurView
        
        super.init(frame: frame)
        
        self.layer.cornerCurve = .circular
        self.clipsToBounds = true
        
        self.addSubview(blurView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(size: CGSize, cornerRadius: CGFloat, style: Style, isDark: Bool = false, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), style: style, isDark: isDark, transition: transition)
    }

    func update(size: CGSize, shape: GlassBackgroundView.Shape, style: Style, isDark: Bool = false, transition: ComponentTransition) {
        let params = Params(size: size, shape: shape, style: style, isDark: isDark)
        if self.params == params {
            return
        }
        self.params = params
        
        transition.setFrame(view: self.blurView, frame: CGRect(origin: CGPoint(), size: size))
        let blurStyle: UIBlurEffect.Style
        switch style {
        case .clear:
            blurStyle = isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
        case .normal:
            blurStyle = isDark ? .systemMaterialDark : .systemMaterialLight
        }
        self.blurView.effect = UIBlurEffect(style: blurStyle)
        if isDark {
            self.blurView.contentView.backgroundColor = UIColor(white: 0.15, alpha: style == .clear ? 0.08 : 0.25)
        } else {
            self.blurView.contentView.backgroundColor = UIColor(white: 1.0, alpha: style == .clear ? 0.08 : 0.25)
        }
        
        switch shape {
        case let .roundedRect(cornerRadius):
            self.maskLayer = nil
            self.layer.mask = nil
            transition.setCornerRadius(layer: self.layer, cornerRadius: cornerRadius)
            self.blurView.layer.cornerRadius = cornerRadius
            self.blurView.layer.masksToBounds = cornerRadius > 0
        case let .customRoundedRect(cornerRadii):
            transition.setCornerRadius(layer: self.layer, cornerRadius: 0.0)
            self.blurView.layer.cornerRadius = 0.0
            self.blurView.layer.masksToBounds = false

            let maskLayer: CAShapeLayer
            if let current = self.maskLayer {
                maskLayer = current
            } else {
                maskLayer = CAShapeLayer()
                maskLayer.fillColor = UIColor.black.cgColor
                self.maskLayer = maskLayer
                self.layer.mask = maskLayer
            }
            transition.setFrame(layer: maskLayer, frame: CGRect(origin: CGPoint(), size: size))
            transition.setShapeLayerPath(layer: maskLayer, path: GlassBackgroundView.generateRoundedRectPath(size: size, cornerRadii: cornerRadii))
        }
    }
}
