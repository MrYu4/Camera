//
//  CameraView+FocusIndicator.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import SwiftUI
import AVKit

@MainActor class CameraFocusIndicatorView {
    var image: UIImage = .init(resource: .mijickIconCrosshair)
    var tintColor: UIColor = .init(resource: .mijickBackgroundYellow)
    var size: CGFloat = 96
    var deviceOrientation: AVCaptureVideoOrientation = .portrait

    /// 根据设备方向计算对焦视图需要旋转的角度（UIKit 正方向为顺时针）
    var rotationAngle: CGFloat {
        switch deviceOrientation {
        case .portrait: return 0
        case .landscapeLeft: return .pi / 2   // 手机顶部朝左，顺时针 90° 使图标对用户视觉正立
        case .landscapeRight: return -.pi / 2  // 手机顶部朝右，逆时针 90°
        case .portraitUpsideDown: return .pi
        @unknown default: return 0
        }
    }
}

// MARK: Create
extension CameraFocusIndicatorView {
    func create(at touchPoint: CGPoint) -> UIImageView {
        let focusIndicator = UIImageView(image: image)
        focusIndicator.contentMode = .scaleAspectFit
        focusIndicator.tintColor = tintColor
        focusIndicator.frame.size = .init(width: size, height: size)
        focusIndicator.frame.origin.x = touchPoint.x - size / 2
        focusIndicator.frame.origin.y = touchPoint.y - size / 2
        focusIndicator.transform = .init(scaleX: 0, y: 0)
        focusIndicator.tag = .focusIndicatorTag
        return focusIndicator
    }
}
