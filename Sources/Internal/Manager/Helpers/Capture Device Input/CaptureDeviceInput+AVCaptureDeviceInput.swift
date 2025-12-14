//
//  CaptureDeviceInput+AVCaptureDeviceInput.swift of MijickCamera
//
//  Created by Tomasz Kurylik. Sending ❤️ from Kraków!
//    - Mail: tomasz.kurylik@mijick.com
//    - GitHub: https://github.com/FulcrumOne
//    - Medium: https://medium.com/@mijick
//
//  Copyright ©2024 Mijick. All rights reserved.


import AVKit

extension AVCaptureDeviceInput: CaptureDeviceInput {
    static func get(mediaType: AVMediaType, position: AVCaptureDevice.Position?) -> Self? {
        let device: AVCaptureDevice? = {
            switch mediaType {
            case .audio:
                return AVCaptureDevice.default(for: .audio)
                
            case .video where position == .front:
                return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                
            case .video where position == .back:
                // 优先使用超广角摄像头以支持 0.5x 缩放
                // 如果不可用，尝试虚拟多摄像头设备
                let selectedDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)
                
                return selectedDevice
                
            default:
                fatalError()
            }
        }()

        guard let device, let deviceInput = try? Self(device: device) else { return nil }
        return deviceInput
    }
}
