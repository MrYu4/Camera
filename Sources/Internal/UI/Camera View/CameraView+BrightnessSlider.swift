//
//  CameraView+BrightnessSlider.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import UIKit
import AVKit

@MainActor class CameraBrightnessSliderView {
    var enabled: Bool = true
    var offset: CGFloat = 20
    var sliderHeight: CGFloat = 92
    var deviceOrientation: AVCaptureVideoOrientation = .portrait
}

// MARK: Create
extension CameraBrightnessSliderView {
    func create(at touchPoint: CGPoint, focusIndicatorSize: CGFloat, parent: CameraManager, metalView: CameraMetalView) -> UIView {
        let isLandscape = deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight
        // 横屏时滑块改为水平方向（宽×高互换）
        let frameWidth: CGFloat = isLandscape ? sliderHeight : 40
        let frameHeight: CGFloat = isLandscape ? 40 : sliderHeight

        let containerView = BrightnessControlView(frame: .init(x: 0, y: 0, width: frameWidth, height: frameHeight))
        containerView.deviceOrientation = deviceOrientation

        // 根据设备方向决定滑块相对于对焦框的位置
        // 原则：滑块始终出现在用户视角的「对焦框右侧」
        switch deviceOrientation {
        case .portrait:
            // 用户持正，右侧 = 屏幕 +X
            containerView.center = CGPoint(x: touchPoint.x + focusIndicatorSize / 2 + offset, y: touchPoint.y)
        case .landscapeLeft:
            // 手机顶部朝左，用户右侧 = 屏幕上方（-Y）
            containerView.center = CGPoint(x: touchPoint.x, y: touchPoint.y - focusIndicatorSize / 2 - offset)
        case .landscapeRight:
            // 手机顶部朝右，用户右侧 = 屏幕下方（+Y）
            containerView.center = CGPoint(x: touchPoint.x, y: touchPoint.y + focusIndicatorSize / 2 + offset)
        case .portraitUpsideDown:
            // 手机倒置，用户右侧 = 屏幕左侧（-X）
            containerView.center = CGPoint(x: touchPoint.x - focusIndicatorSize / 2 - offset, y: touchPoint.y)
        @unknown default:
            containerView.center = CGPoint(x: touchPoint.x + focusIndicatorSize / 2 + offset, y: touchPoint.y)
        }

        containerView.tag = .brightnessSliderTag
        containerView.alpha = 0
        containerView.transform = .init(scaleX: 0, y: 0)
        containerView.cameraManager = parent
        containerView.metalView = metalView

        // 每次创建时重置曝光值为0
        containerView.initialValue = 0.0
        containerView.currentValue = 0.0

        containerView.isUserInteractionEnabled = true
        containerView.isMultipleTouchEnabled = false
        containerView.isExclusiveTouch = true
        return containerView
    }
}

// MARK: - Brightness Control View
private class BrightnessControlView: UIView {
    weak var cameraManager: CameraManager?
    weak var metalView: CameraMetalView?
    var initialValue: Float = 0.0
    var deviceOrientation: AVCaptureVideoOrientation = .portrait

    private let lineWidth: CGFloat = 2
    private let sunIconSize: CGFloat = 16
    private var startTouchPoint: CGPoint = .zero
    private var startValue: Float = 0
    var currentValue: Float = 0.0 {
        didSet {
            setNeedsDisplay() // 值改变时重绘
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
        clipsToBounds = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 确保此视图及其区域可以接收触摸
        if self.point(inside: point, with: event) {
            return self
        }
        return super.hitTest(point, with: event)
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 扩大触摸区域
        let expandedBounds = bounds.insetBy(dx: -10, dy: -10)
        return expandedBounds.contains(point)
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        switch deviceOrientation {
        case .landscapeLeft, .landscapeRight:
            drawHorizontal(rect, context: context)
        default:
            drawVertical(rect, context: context)
        }
    }

    // MARK: 竖屏 / 倒置竖屏 — 竖向滑块
    private func drawVertical(_ rect: CGRect, context: CGContext) {
        let centerX = rect.width / 2

        let topMargin: CGFloat = sunIconSize / 2 + 2
        let bottomMargin: CGFloat = sunIconSize / 2 + 2
        let availableHeight = rect.height - topMargin - bottomMargin

        let minExposure: Float = -3.0
        let maxExposure: Float = 3.0
        let normalizedValue = (currentValue - minExposure) / (maxExposure - minExposure)

        // 倒置时高曝光在下；正常竖屏高曝光在上
        let fraction: CGFloat = deviceOrientation == .portraitUpsideDown
            ? CGFloat(normalizedValue)
            : CGFloat(1.0 - normalizedValue)
        let sunCenterY = topMargin + availableHeight * fraction

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        let lineGap: CGFloat = 4
        if sunCenterY - sunIconSize / 2 - lineGap > 0 {
            context.move(to: CGPoint(x: centerX, y: 0))
            context.addLine(to: CGPoint(x: centerX, y: sunCenterY - sunIconSize / 2 - lineGap))
            context.strokePath()
        }
        if sunCenterY + sunIconSize / 2 + lineGap < rect.height {
            context.move(to: CGPoint(x: centerX, y: sunCenterY + sunIconSize / 2 + lineGap))
            context.addLine(to: CGPoint(x: centerX, y: rect.height))
            context.strokePath()
        }

        let sunRect = CGRect(x: centerX - sunIconSize / 2,
                             y: sunCenterY - sunIconSize / 2,
                             width: sunIconSize,
                             height: sunIconSize)
        if let sunImage = UIImage(systemName: "sun.max.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: sunIconSize, weight: .medium)) {
            UIColor.systemYellow.setFill()
            sunImage.withTintColor(.systemYellow, renderingMode: .alwaysTemplate).draw(in: sunRect)
        }
    }

    // MARK: 横屏 — 水平滑块
    private func drawHorizontal(_ rect: CGRect, context: CGContext) {
        let centerY = rect.height / 2

        let leftMargin: CGFloat = sunIconSize / 2 + 2
        let rightMargin: CGFloat = sunIconSize / 2 + 2
        let availableWidth = rect.width - leftMargin - rightMargin

        let minExposure: Float = -3.0
        let maxExposure: Float = 3.0
        let normalizedValue = (currentValue - minExposure) / (maxExposure - minExposure)

        // LandscapeLeft：用户"上"= 屏幕左，高曝光 → 太阳靠左
        // LandscapeRight：用户"上"= 屏幕右，高曝光 → 太阳靠右
        let fraction: CGFloat = deviceOrientation == .landscapeLeft
            ? CGFloat(1.0 - normalizedValue)
            : CGFloat(normalizedValue)
        let sunCenterX = leftMargin + availableWidth * fraction

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        let lineGap: CGFloat = 4
        if sunCenterX - sunIconSize / 2 - lineGap > 0 {
            context.move(to: CGPoint(x: 0, y: centerY))
            context.addLine(to: CGPoint(x: sunCenterX - sunIconSize / 2 - lineGap, y: centerY))
            context.strokePath()
        }
        if sunCenterX + sunIconSize / 2 + lineGap < rect.width {
            context.move(to: CGPoint(x: sunCenterX + sunIconSize / 2 + lineGap, y: centerY))
            context.addLine(to: CGPoint(x: rect.width, y: centerY))
            context.strokePath()
        }

        let sunRect = CGRect(x: sunCenterX - sunIconSize / 2,
                             y: centerY - sunIconSize / 2,
                             width: sunIconSize,
                             height: sunIconSize)
        if let sunImage = UIImage(systemName: "sun.max.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: sunIconSize, weight: .medium)) {
            UIColor.systemYellow.setFill()
            sunImage.withTintColor(.systemYellow, renderingMode: .alwaysTemplate).draw(in: sunRect)
        }
    }
        
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        startTouchPoint = touch.location(in: self)
        // 使用滑块当前显示的值作为起始值，避免跳跃
        startValue = currentValue
        metalView?.cancelFadeOutAndKeepVisible()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let currentPoint = touch.location(in: self)

        // 根据设备方向选择对应轴向，使调节方向始终与用户"上划增亮"直觉一致
        let sensitivity: Float = 0.016
        let rawDelta: CGFloat
        switch deviceOrientation {
        case .portrait:
            // 向上（-Y）= 更亮
            rawDelta = startTouchPoint.y - currentPoint.y
        case .landscapeLeft:
            // 手机顶朝左，用户"上"= 屏幕左（-X）
            rawDelta = startTouchPoint.x - currentPoint.x
        case .landscapeRight:
            // 手机顶朝右，用户"上"= 屏幕右（+X）
            rawDelta = currentPoint.x - startTouchPoint.x
        case .portraitUpsideDown:
            // 倒置，用户"上"= 屏幕下（+Y）
            rawDelta = currentPoint.y - startTouchPoint.y
        @unknown default:
            rawDelta = startTouchPoint.y - currentPoint.y
        }

        let deltaValue = Float(rawDelta) * sensitivity
        let newValue = max(-3.0, min(3.0, startValue + deltaValue))
        currentValue = newValue
        try? cameraManager?.setExposureTargetBias(newValue)
        metalView?.cancelFadeOutAndKeepVisible()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if let focusView = metalView?.parent?.cameraView.viewWithTag(.focusIndicatorTag) {
            metalView?.scheduleFadeOut(for: focusView)
        }
        metalView?.scheduleFadeOut(for: self)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if let focusView = metalView?.parent?.cameraView.viewWithTag(.focusIndicatorTag) {
            metalView?.scheduleFadeOut(for: focusView)
        }
        metalView?.scheduleFadeOut(for: self)
    }
}
