//
//  ViewController.swift
//  insta360_
//
//  Created by Ibrahim on 12/26/22.
//

import UIKit
import INSCameraSDK

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let btn = UIButton(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        btn.setTitle("Show camera", for: .normal)
        btn.setTitleColor(.blue, for: .normal)
        btn.center = .init(x: 200, y: 200)
        btn.addTarget(self, action: #selector(showCamera), for: .touchUpInside)
        
        view.addSubview(btn)
        
        view.backgroundColor = .lightGray
        
    }
    
    @objc func showCamera() {
        let vc = Insta360ViewController()
        vc.modalPresentationStyle = .fullScreen
        let navc = UINavigationController(rootViewController: vc)
        present(navc, animated: true)
    }

    
}

class Insta360ViewController: UIViewController {
    
    private var mediaSession: INSCameraMediaSession?
    private var previewPlayer: INSCameraPreviewPlayer?
    private var storageState: INSCameraStorageStatus?
    private var videoEncode: INSVideoEncode?
    private var batteryState: INSCameraBatteryStatus?
    
    private var infoLabel: UILabel!
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        videoEncode = INSVideoEncode.H264
        mediaSession = INSCameraMediaSession()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        mediaSession?.stopRunning() { error in
            if let error {
                print("stop media session with err: \(error)")
            }
        }
        
        INSCameraManager.socket().removeObserver(self, forKeyPath: "cameraState")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        title = " Insta 360 camera"
        
        setup()
        
        sendHeartbeats()
        
        captureButton()
        
        INSCameraManager.socket().addObserver(self, forKeyPath: "cameraState", options: .new, context: nil)
        
        setupRenderView()
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if (INSCameraManager.shared().currentCamera != nil) {
            weak var weakSelf = self
            fetchOptions() {
                weakSelf?.updateConfiguration()
                weakSelf?.runMediaSession()
            }
        }
    }
    
    private func cameraInfo() {
        infoLabel = UILabel(frame: CGRect(x: 16, y: view.frame.height - 150, width: view.frame.width - 32, height: 200))
        view.addSubview(infoLabel)
        infoLabel.numberOfLines = 0
        infoLabel.text = "camera info"
        infoLabel.font = .systemFont(ofSize: 11, weight: .light)
        infoLabel.text = """
        Free space: \(((storageState!.freeSpace) / (1024*1000000)))GB/\((storageState!.totalSpace / (1024*1000000)))GB
        Battery: \(batteryState!.batteryLevel)%
        """
        
    }
    
    private func captureButton() {
        let capture = UIButton(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
        view.addSubview(capture)
        capture.setTitle("Capture", for: .normal)
        capture.setTitleColor(.red, for: .normal)

        capture.center = CGPoint(x: 200, y: 150)
        
        capture.addTarget(self, action: #selector(takePicture), for: .touchUpInside)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        stop()
    }
    
    /// convert (photo or video) resource uri to http url via http tunnel and Wi-Fi socket
    func INSHTTPURLForResourceURI(_ uri: String) -> URL? {
        URL(string: uri)
    }
    
    /// convert local http url to (photo or video) resource uri
    func INSResourceURIFromHTTPURL(_ url: URL) -> String? {
        nil
    }
    
    /// connect camera via WiFi
    private func setup() {
        INSCameraManager.socket().setup()
    }
    
    @objc func takePicture() {
        let option = INSTakePictureOptions()
        option.mode = INSPhotoMode.aeb
        option.aebevBias = [NSNumber(value: 0), NSNumber(value: -2), NSNumber(value: -1), NSNumber(value: 1), NSNumber(value: 2)]
        option.generateManually = true
        
        INSCameraManager.shared().commandManager.takePicture(with: option) { [weak self] error, photoInfo in
            if error != nil {
                print("capture error", error?.localizedDescription)
                return
            }
            
            if let uri = photoInfo?.uri, let hdrUris = photoInfo?.hdrUris {
                print("URL", self?.INSHTTPURLForResourceURI(uri))
            }
        }
    }
    
    /// won't listen on Insta360 cameras any more
    private func stop() {
        INSCameraManager.socket().shutdown()
    }
    
    /// When you connect your camera via wifi, you need to send heartbeat information to the camera at 2 Hz (every 500ms).
    private func sendHeartbeats() {
        INSCameraManager.socket().commandManager.sendHeartbeats(with: nil)
    }
    
    /// Once the cameraState changes to INSCameraStateConnected, your app is able to send commands to the camera.
    private func cameraState() {
        let state = INSCameraManager.shared().cameraState
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if !(object is INSCameraManager) {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        let manager = object as? INSCameraManager
        
        if keyPath == "cameraState" {
            let state = INSCameraState(rawValue: (change?[NSKeyValueChangeKey.newKey] as? NSNumber)?.uintValue ?? 0)
            switch state {
                case .found:
                    print("Found")
                case .connected:
                    startSendingHeartbeats()
                case .connectFailed:
                    stopSendingHeartbeats()
                default:
                    stopSendingHeartbeats()
            }
        }
        
    }
    
    private func startSendingHeartbeats() {
        runMediaSession()
    }
    
    private func stopSendingHeartbeats() {
        mediaSession?.stopRunning(completion: nil)
    }
    
    
    func fetchOptions(withCompletion completion: (() -> Void)? = nil) {
        weak var weakSelf = self
        let optionTypes = [
            NSNumber(value: INSCameraOptionsType.storageState.rawValue),
            NSNumber(value: INSCameraOptionsType.videoEncode.rawValue),
            NSNumber(value: INSCameraOptionsType.batteryStatus.rawValue),
        ]
        
        INSCameraManager.shared().commandManager.getOptionsWithTypes(optionTypes) { error, options, successTypes in
            if options == nil {
                completion?()
                return
            }
            weakSelf?.storageState = options?.storageStatus
            weakSelf?.videoEncode = options?.videoEncode
            weakSelf?.batteryState = options?.batteryStatus
            completion?()
        }
    }
    
    func updateConfiguration() {
        // main stream resolution
        mediaSession?.expectedVideoResolution = INSVideoResolution1920x960x30
        
        // secondary stream resolution
        mediaSession?.expectedVideoResolutionSecondary = INSVideoResolution960x480x30
        
        // use main stream or secondary stream to preview
        mediaSession?.previewStreamType = INSPreviewStreamType.secondary
        
        // audio sample rate
        mediaSession?.expectedAudioSampleRate = INSAudioSampleRate.rate48000Hz
        
        // preview stream encode
        mediaSession?.videoStreamEncode = INSVideoEncode.H264
        
        // gyroscope correction mode
        // If you are in panoramic preview, use `INSGyroPlayModeDefault`.
        // If you are in wide angle preview, use `INSGyroPlayModeFootageMotionSmooth`.
        mediaSession?.gyroPlayMode = INSGyroPlayMode.normal
        
        mediaSession?.expectedVideoResolution = .init(width: Int(view.frame.width), height: Int(view.frame.height/2.0), fps: 30)
        
        cameraInfo()
    }
    
    func runMediaSession() {
        guard INSCameraManager.shared().cameraState == INSCameraState.connected else { return }
        
        guard let mediaSession else { return }
        
        weak var weakSelf = self
        
        if mediaSession.running {
            view.isUserInteractionEnabled = false
            mediaSession.commitChanges() { error in
                if let error {
                    print("###commitChanges media session with error: \(error)")
                }
                weakSelf?.view.isUserInteractionEnabled = true
                if let error {
                    print("###commitChanges media failed", error.localizedDescription)
                }
            }
        } else {
            view.isUserInteractionEnabled = false
            mediaSession.startRunning() { error in
                if let error {
                    print("###start running media session with error: \(error)")
                }
                weakSelf?.view.isUserInteractionEnabled = true
                if let error {
                    weakSelf!.previewPlayer!.play(withSmoothBuffer: false)
                }
            }
        }
    }
    
    func setupRenderView() {
        let height = view.bounds.height * 0.5
        let frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        
        previewPlayer = INSCameraPreviewPlayer(frame: frame, renderType: INSRenderType.sphericalPanoRender)
        previewPlayer?.play(withGyroTimestampAdjust: 30.0)
        previewPlayer?.delegate = self
        previewPlayer?.renderView.layer.borderWidth = 1
        previewPlayer?.renderView.layer.borderColor = UIColor.blue.cgColor
        view.addSubview(previewPlayer!.renderView)
        
        mediaSession?.plug(previewPlayer!)
        
        // adjust field of view parameters
        let offset = INSCameraManager.shared().currentCamera?.settings?.mediaOffset
        if (offset != nil) {
            let rawValue = INSLensOffset(offset: offset!).lensType
            if rawValue == INSLensType.oneX2.rawValue ||
                rawValue == INSLensType.oneR577Wide.rawValue ||
                rawValue == INSLensType.oneR283Wide.rawValue {
                
                previewPlayer?.renderView.enablePanGesture = false
                previewPlayer?.renderView.enablePinchGesture = false
                
                previewPlayer?.renderView.render.camera?.xFov = 37
                previewPlayer?.renderView.render.camera?.distance = 700
            }
        }
        
    }
    
}

extension Insta360ViewController: INSCameraPreviewPlayerDelegate {
    
    func offset(toPlay player: INSCameraPreviewPlayer) -> String? {
        guard let mediaOffset = INSCameraManager.shared().currentCamera?.settings?.mediaOffset else { return "## media offset not available" }
        
        if ((INSCameraManager.shared().currentCamera?.name == kInsta360CameraNameOneX) ||
            (INSCameraManager.shared().currentCamera?.name == kInsta360CameraNameOneR) ||
            (INSCameraManager.shared().currentCamera?.name == kInsta360CameraNameOneX2)) &&
            INSLensOffset.isValidOffset(mediaOffset) {
            return INSOffsetCalculator.convertOffset(mediaOffset, to: INSOffsetConvertType.oneX3040_2_2880)
        }
        return mediaOffset
    }
    
    /// Using INSOffsetParser to get the INSOffsetParameter internal parameters
    private func internalParameters(from url: URL) {
        let parser = INSImageInfoParser(url: url)
        
        if parser.open() {
            let extraInfo = parser.extraInfo
            let offsetParser = INSOffsetParser(offset: (extraInfo?.metadata!.offset)!,
                                               width: Int32((extraInfo?.metadata!.dimension.width)!),
                                               height: Int32((extraInfo?.metadata!.dimension.height)!))
            
            for param in offsetParser.parameters! {
                print("Internal parameters: \(param)")
            }
        }
    }
    
}
