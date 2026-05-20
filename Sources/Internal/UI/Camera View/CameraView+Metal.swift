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

        let focusIndicator = focusIndicator.create(at: touchPoint)
        parent.cameraView.addSubview(focusIndicator)
        animateFocusIndicator(focusIndicator)
        
        // 添加亮度滑块（紧贴对焦图标右侧）
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
        }) { _ in
            UIView.animate(withDuration: 0.44, delay: 1.44, animations: { 
                view.alpha = 0 
            })
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
        UIView.animate(withDuration: 0.44, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, animations: { focusIndicator.transform = .init(scaleX: 1, y: 1) }) { _ in
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


// MARK: - CAPTURING FRAMES



// MARK: Capture
extension CameraMetalView: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let sampleBuffer = SendableSampleBuffer(sampleBuffer)

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handleCaptureOutput(sampleBuffer.value)
            }
            return
        }

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
    func renderView(_ view: MTKView, _ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer, _ ciImage: CIImage) { ciContext?.render(
        ciImage,
        to: currentDrawable.texture,
        commandBuffer: commandBuffer,
        bounds: .init(origin: .zero, size: view.drawableSize),
        colorSpace: CGColorSpaceCreateDeviceRGB()
    )}
    func commitBuffer(_ currentDrawable: any CAMetalDrawable, _ commandBuffer: any MTLCommandBuffer) {
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
}
