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

@MainActor class CameraBrightnessSliderView {
    var enabled: Bool = true
    var offset: CGFloat = 20
    var sliderHeight: CGFloat = 92
}

// MARK: Create
extension CameraBrightnessSliderView {
    func create(at touchPoint: CGPoint, focusIndicatorSize: CGFloat, parent: CameraManager, metalView: CameraMetalView) -> UIView {
        let containerView = BrightnessControlView(frame: .init(x: 0, y: 0, width: 40, height: sliderHeight))
        containerView.center = CGPoint(x: touchPoint.x + focusIndicatorSize / 2 + offset, y: touchPoint.y)
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
    
    private let lineWidth: CGFloat = 2
    private let sunIconSize: CGFloat = 16
    private var startTouchY: CGFloat = 0
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
        
        let centerX = rect.width / 2
        
        // 添加边距，防止太阳图标在极点时被遮挡
        let topMargin: CGFloat = sunIconSize / 2 + 2
        let bottomMargin: CGFloat = sunIconSize / 2 + 2
        let availableHeight = rect.height - topMargin - bottomMargin
        
        // 将曝光值 (-3.0 到 3.0) 映射到 Y 坐标，考虑边距
        // 曝光值 3.0 -> 顶部边距, 0.0 -> 中间, -3.0 -> 底部边距
        let minExposure: Float = -3.0
        let maxExposure: Float = 3.0
        let normalizedValue = (currentValue - minExposure) / (maxExposure - minExposure) // 0.0 到 1.0
        let sunCenterY = topMargin + availableHeight * CGFloat(1.0 - normalizedValue) // 反转，因为 Y 坐标向下增加
        
        // 绘制竖线样式
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        
        // 上方竖线（从顶部到太阳图标上方）
        let lineGap: CGFloat = 4
        if sunCenterY - sunIconSize / 2 - lineGap > 0 {
            context.move(to: CGPoint(x: centerX, y: 0))
            context.addLine(to: CGPoint(x: centerX, y: sunCenterY - sunIconSize / 2 - lineGap))
            context.strokePath()
        }
        
        // 下方竖线（从太阳图标下方到底部）
        if sunCenterY + sunIconSize / 2 + lineGap < rect.height {
            context.move(to: CGPoint(x: centerX, y: sunCenterY + sunIconSize / 2 + lineGap))
            context.addLine(to: CGPoint(x: centerX, y: rect.height))
            context.strokePath()
        }
        
        // 中间太阳图标（位置根据曝光值变化）
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
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        startTouchY = touch.location(in: self).y
        // 使用滑块当前显示的值作为起始值，而不是相机的曝光值
        // 这样可以确保滑动速度一致，不会因为相机曝光值和显示值不同步而出现跳跃
        startValue = currentValue
        
        // 取消淡出动画，保持显示
        metalView?.cancelFadeOutAndKeepVisible()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let currentY = touch.location(in: self).y
        let deltaY = startTouchY - currentY  // 向上为正
        
        // 进一步降低灵敏度：需要滑动整个滑块高度(92pt)才能改变约1.5曝光值
        // 这样从-3到+3需要滑动约4倍滑块高度，提供更精细的控制
        let sensitivity: Float = 0.016
        let deltaValue = Float(deltaY) * sensitivity
        var newValue = startValue + deltaValue
        
        // 限制范围 -3.0 到 3.0
        newValue = max(-3.0, min(3.0, newValue))
        
        currentValue = newValue // 更新当前值，触发重绘
        try? cameraManager?.setExposureTargetBias(newValue)
        metalView?.cancelFadeOutAndKeepVisible()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        // 重新安排淡出动画
        if let focusView = metalView?.parent.cameraView.viewWithTag(.focusIndicatorTag) {
            metalView?.scheduleFadeOut(for: focusView)
        }
        metalView?.scheduleFadeOut(for: self)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        // 重新安排淡出动画
        if let focusView = metalView?.parent.cameraView.viewWithTag(.focusIndicatorTag) {
            metalView?.scheduleFadeOut(for: focusView)
        }
        metalView?.scheduleFadeOut(for: self)
    }
}
