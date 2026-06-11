//
//  CameraView+Metal.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import MetalKit
import AVKit

@MainActor class CameraMetalView: MTKView {
    private(set) var parent: CameraManager?
    private(set) var ciContext: CIContext?
    private(set) var commandQueue: MTLCommandQueue?
    private(set) var currentFrame: CIImage?
    private(set) var focusIndicator: CameraFocusIndicatorView = .init()
    private(set) var brightnessSlider: CameraBrightnessSliderView = .init()
    private(set) var isAnimating: Bool = false
}

// MARK: Setup
extension CameraMetalView {
    func setup(parent: CameraManager) throws(MCameraError) {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else { throw .cannotSetupMetalDevice }

        self.assignInitialValues(parent: parent, metalDevice: metalDevice)
        self.configureMetalView(metalDevice: metalDevice)
        self.addToParent(parent.cameraView)
    }
}
private extension CameraMetalView {
    func assignInitialValues(parent: CameraManager, metalDevice: MTLDevice) {
        self.parent = parent
        self.ciContext = CIContext(mtlDevice: metalDevice)
        self.commandQueue = metalDevice.makeCommandQueue()
    }
    func configureMetalView(metalDevice: MTLDevice) {
        self.parent?.cameraView.alpha = 0

        self.delegate = self
        self.device = metalDevice
        self.isPaused = true
        self.enableSetNeedsDisplay = false
        self.framebufferOnly = false
        self.autoResizeDrawable = false
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
    }
}


// MARK: - ANIMATIONS



// MARK: Camera Entrance
extension CameraMetalView {
    func performCameraEntranceAnimation() { UIView.animate(withDuration: 0.33) { [self] in
        parent?.cameraView.alpha = 1
    }}
}

// MARK: Image Capture
extension CameraMetalView {
    func performImageCaptureAnimation() {
        guard let parent else { return }
        let blackMatte = createBlackMatte()

        parent.cameraView.addSubview(blackMatte)
        animateBlackMatte(blackMatte)
    }
}
private extension CameraMetalView {
    func createBlackMatte() -> UIView {
        guard let parent else { return UIView() }
        let view = UIView()
        view.frame = parent.cameraView.frame
        view.backgroundColor = .init(resource: .mijickBackgroundPrimary)
        view.alpha = 0
        return view
    }
    func animateBlackMatte(_ view: UIView) {
        UIView.animate(withDuration: 0.16, animations: { view.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.16, animations: { view.alpha = 0 }) { _ in
                view.removeFromSuperview()
            }
        }
    }
}

// MARK: Camera Flip
extension CameraMetalView {
    func beginCameraFlipAnimation() async {
        guard let parent else { return }
        let snapshot = createSnapshot()
        isAnimating = true
        insertBlurView(snapshot)
        animateBlurFlip()

        await Task.sleep(seconds: 0.01)
    }
    func finishCameraFlipAnimation() async {
        guard let parent, let blurView = parent.cameraView.viewWithTag(.blurViewTag) else { return }

        await Task.sleep(seconds: 0.44)
        UIView.animate(withDuration: 0.3, animations: { blurView.alpha = 0 }) { [self] _ in
            blurView.removeFromSuperview()
            isAnimating = false
        }
    }
}
private extension CameraMetalView {
    func createSnapshot() -> UIImage? {
        guard let currentFrame else { return nil }

        let image = UIImage(ciImage: currentFrame)
        return image
    }
    func insertBlurView(_ snapshot: UIImage?) {
        guard let parent else { return }
        let blurView = UIImageView(frame: parent.cameraView.frame)
        blurView.image = snapshot
        blurView.contentMode = .scaleAspectFill
        blurView.clipsToBounds = true
        blurView.tag = .blurViewTag
        blurView.applyBlurEffect(style: .regular)

        parent.cameraView.addSubview(blurView)
    }
    func animateBlurFlip() {
        guard let parent else { return }
        UIView.transition(with: parent.cameraView, duration: 0.44, options: cameraFlipAnimationTransition) {}
    }
}
private extension CameraMetalView {
    var cameraFlipAnimationTransition: UIView.AnimationOptions { parent?.attributes.cameraPosition == .back ? .transitionFlipFromLeft : .transitionFlipFromRight }
}

// MARK: Camera Focus
extension CameraMetalView {
    func performCameraFocusAnimation(touchPoint: CGPoint) {
        guard let parent else { return }
        removeExistingFocusIndicatorAnimations()

        // 将当前设备方向传递给两个构建器，使 UI 随屏幕方向自动适配
        focusIndicator.deviceOrientation = parent.attributes.deviceOrientation
        brightnessSlider.deviceOrientation = parent.attributes.deviceOrientation

        // 让 cameraView 裁剪超出预览区域的子视图（对焦框/亮度滑块在边缘时只显示能看见的部分）
        parent.cameraView.clipsToBounds = true

        let focusIndicator = focusIndicator.create(at: touchPoint)
        parent.cameraView.addSubview(focusIndicator)
        animateFocusIndicator(focusIndicator)
        
        // 添加亮度滑块（位置随屏幕方向适配）
        if brightnessSlider.enabled {
            let sliderView = brightnessSlider.create(at: touchPoint, focusIndicatorSize: self.focusIndicator.size, parent: parent, metalView: self)
            parent.cameraView.addSubview(sliderView)
            animateBrightnessSlider(sliderView)
            
            // 重置曝光值到0
            try? parent.setExposureTargetBias(0)
        }
    }

    func scheduleFadeOut(for view: UIView) {
        UIView.animate(withDuration: 0.44, delay: 1.44, animations: { 
            view.alpha = 0.2 
        }) { finished in
            // 若动画被 removeAllAnimations() 中断，finished = false，
            // 不启动 phase2，防止旧的动画链在旋转后继续触发，导致对焦框提前消失
            guard finished else { return }
            UIView.animate(withDuration: 0.44, delay: 1.44, animations: { 
                view.alpha = 0 
            }) { finished in
                guard finished else { return }
                // 彻底移出视图层级，防止 alpha=0 的不可见视图（特别是 BrightnessControlView）
                // 继续拦截触摸事件，导致后续点击无法触发对焦
                view.removeFromSuperview()
            }
        }
    }
    
    func cancelFadeOutAndKeepVisible() {
        guard let parent else { return }
        // 取消所有淡出动画并恢复完全可见
        if let focusView = parent.cameraView.viewWithTag(.focusIndicatorTag) {
            focusView.layer.removeAllAnimations()
            focusView.alpha = 1.0
        }
        if let sliderView = parent.cameraView.viewWithTag(.brightnessSliderTag) {
            sliderView.layer.removeAllAnimations()
            sliderView.alpha = 1.0
        }
    }
}
private extension CameraMetalView {
    func removeExistingFocusIndicatorAnimations() {
        guard let parent else { return }
        if let view = parent.cameraView.viewWithTag(.focusIndicatorTag) {
            view.removeFromSuperview()
        }
        if let view = parent.cameraView.viewWithTag(.brightnessSliderTag) {
            view.removeFromSuperview()
        }
    }
    func animateFocusIndicator(_ focusIndicator: UIImageView) {
        // 动画目标：scale 恢复到 1 并叠加旋转角度，使图标对用户视角正立
        let targetTransform = CGAffineTransform(rotationAngle: self.focusIndicator.rotationAngle)
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, animations: { focusIndicator.transform = targetTransform }) { finished in
            // 若被 removeAllAnimations() 中断（旋转时），不在此处调度淡出；
            // 由 updateFocusIndicatorOrientation 的旋转动画 completion 统一接管
            guard finished else { return }
            self.scheduleFadeOut(for: focusIndicator)
        }
    }
    func animateBrightnessSlider(_ sliderView: UIView) {
        sliderView.isUserInteractionEnabled = true
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, animations: { 
            sliderView.transform = .init(scaleX: 1, y: 1)
            sliderView.alpha = 1
        }) { _ in
            sliderView.isUserInteractionEnabled = true
            self.scheduleFadeOut(for: sliderView)
        }
    }
}

// MARK: Camera Orientation
extension CameraMetalView {
    func beginCameraOrientationAnimation(if shouldAnimate: Bool) async { if shouldAnimate {
        parent?.cameraView.alpha = 0
        await Task.sleep(seconds: 0.1)
    }}
    func finishCameraOrientationAnimation(if shouldAnimate: Bool) { if shouldAnimate {
        UIView.animate(withDuration: 0.2, delay: 0.1) { self.parent?.cameraView.alpha = 1 }
    }}
}

// MARK: Focus Indicator Orientation Update
extension CameraMetalView {
    /// 设备方向改变后调用：重置淡出计时 → 旋转对焦框 → 在新方向重建亮度滑块。
    func updateFocusIndicatorOrientation(_ newOrientation: AVCaptureVideoOrientation) {
        guard let parent else { return }

        focusIndicator.deviceOrientation = newOrientation
        brightnessSlider.deviceOrientation = newOrientation

        // ── 对焦框 ──────────────────────────────────────────────────────────
        // 1. 取消旋转前排队的淡出动画，让对焦框保持完全可见
        // 2. 动画旋转到新方向
        // 3. 旋转完成后重新排队淡出（给用户新的完整交互窗口）
        if let focusView = parent.cameraView.viewWithTag(.focusIndicatorTag) {
            focusView.layer.removeAllAnimations()
            focusView.alpha = 1.0
            let angle = focusIndicator.rotationAngle
            UIView.animate(withDuration: 0.3, delay: 0, options: .beginFromCurrentState, animations: {
                focusView.transform = CGAffineTransform(rotationAngle: angle)
            }, completion: { _ in
                self.scheduleFadeOut(for: focusView)
            })
        }

        // ── 亮度滑块 ────────────────────────────────────────────────────────
        // 位置和尺寸都依赖方向，移除旧的，以对焦框中心为触摸点重建新的
        let hadSlider = parent.cameraView.viewWithTag(.brightnessSliderTag) != nil
        parent.cameraView.viewWithTag(.brightnessSliderTag)?.removeFromSuperview()

        if hadSlider, let focusView = parent.cameraView.viewWithTag(.focusIndicatorTag) {
            let touchPoint = focusView.center
            let newSlider = brightnessSlider.create(
                at: touchPoint,
                focusIndicatorSize: focusIndicator.size,
                parent: parent,
                metalView: self
            )
            parent.cameraView.addSubview(newSlider)
            animateBrightnessSlider(newSlider)
            // 与 performCameraFocusAnimation 保持一致：重建时同步重置相机曝光
            try? parent.setExposureTargetBias(0)
        }
    }
}


// MARK: - CAPTURING FRAMES



// MARK: Capture
extension CameraMetalView: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let sampleBuffer = SendableSampleBuffer(sampleBuffer)
        // 始终通过 Task { @MainActor } 跳到主 actor，不依赖 Thread.isMainThread。
        // Thread.isMainThread 检查的是底层 POSIX 线程，而 MainActor.assumeIsolated
        // 使用 Swift Concurrency executor 校验，两者可能不一致，
        // AVFoundation delegate 回调即使在主线程也可能触发 precondition crash。
        Task { @MainActor [weak self, sampleBuffer] in
            self?.handleCaptureOutput(sampleBuffer.value)
        }
    }
}
private struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}
private extension CameraMetalView {
    func handleCaptureOutput(_ sampleBuffer: CMSampleBuffer) {
        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentFrame = captureCurrentFrame(cvImageBuffer)
        let currentFrameWithFiltersApplied = applyingFiltersToCurrentFrame(currentFrame)
        redrawCameraView(currentFrameWithFiltersApplied)
    }
    func captureCurrentFrame(_ cvImageBuffer: CVImageBuffer) -> CIImage {
        let currentFrame = CIImage(cvImageBuffer: cvImageBuffer)
        guard let parent else { return currentFrame }
        return currentFrame.oriented(parent.attributes.frameOrientation)
    }
    func applyingFiltersToCurrentFrame(_ currentFrame: CIImage) -> CIImage {
        guard let parent else { return currentFrame }
        return currentFrame.applyingFilters(parent.attributes.cameraFilters)
    }
    func redrawCameraView(_ frame: CIImage) {
        currentFrame = frame
        draw()
    }
}

// MARK: Draw
extension CameraMetalView: MTKViewDelegate {
    func draw(in view: MTKView) {
        guard let commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let ciImage = currentFrame,
              let currentDrawable = view.currentDrawable
        else { return }

        changeDrawableSize(view, ciImage)
        renderView(view, currentDrawable, commandBuffer, ciImage)
        commitBuffer(currentDrawable, commandBuffer)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
private extension CameraMetalView {
    func changeDrawableSize(_ view: MTKView, _ ciImage: CIImage) {
        view.drawableSize = ciImage.extent.size
    }
    func renderView(_ view: MTKView, _ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer, _ ciImage: CIImage) {
        // 使用非阻塞的 startTask(toRender:to:) 代替同步的 render(_:to:commandBuffer:bounds:colorSpace:)。
        // 同步版本内部会在主线程执行 dispatch_async + dispatch_group_wait，
        // 导致 QoS 继承追踪（qosWaiterSignallerInvariantCheck）崩溃。
        // startTask 仅将 GPU 命令编码进 commandBuffer，立即返回，
        // 实际渲染由后续的 commandBuffer.commit() 异步交给 GPU 完成。
        let destination = CIRenderDestination(mtlTexture: currentDrawable.texture, commandBuffer: commandBuffer)
        destination.colorSpace = CGColorSpaceCreateDeviceRGB()
        try? ciContext?.startTask(toRender: ciImage, to: destination)
    }
    func commitBuffer(_ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
