//
//  ViewController.swift
//  CardScanner
//
//  Created by Reed Carson on 5/14/18.
//  Copyright © 2018 Reed Carson. All rights reserved.
//

import UIKit
import AVFoundation
import FirebaseMLVision

class ViewController: UIViewController {
    
    //MARK: - Outlets
    @IBOutlet weak var cardDetectionArea: UIView!
    @IBOutlet weak var detectButton: UIButton!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var overlayView: UIView!
    @IBOutlet weak var isDetectingIndicatorView: UIView!
    
    @IBOutlet weak var captureCurrentFrameButton: UIButton!
    @IBOutlet weak var scannedTextDisplayTextView: UITextView!
    
    //MARK: - AV Properties
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var dataOutput: AVCaptureVideoDataOutput?
    private var currentCMSampleBuffer: CMSampleBuffer?
    
    var captureSampleBufferRate = 5
    
    //MARK: - Private properties
    private var bufferImageForSizing: UIImage?
    private var outputIsOn = false {
        didSet {
            guard isDetectingIndicatorView != nil else { return }
            isDetectingIndicatorView.backgroundColor = outputIsOn ? .green : .yellow
        }
    }
    private var outputCounter = 0
    private var debugFrames = [UIView]()
    
    private var visionHandler: VisionHandler!
    
    var videoOrientation: AVCaptureVideoOrientation = .landscapeRight
    var visionOrientation: VisionDetectorImageOrientation = .rightTop
    
    var cardElements = [CardElement]()
    
    var possibleTitles = [String]()
    
    var detectedText = [String]() {
        didSet {
            var text = ""
            for _text in detectedText {
                text += "\(_text)\n\n"
            }
            scannedTextDisplayTextView.text = text
        }
    }
    
    struct CardElement {
        var text: String
        var frame: CGRect
    }
    
    private let dataOutputQueue = DispatchQueue(label: "com.carsonios.captureQueue")
    
    //MARK: - Orientation Properties
    override var shouldAutorotate: Bool {
        return true
    }

    //MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let man = ApiManager()
       // man.request()
        man.getPriceForProductID("439725") {
            result in
            switch result {
            case .error(let error):
                print(error)
            case .success(let json):
                if let results = json["results"] as? [[String:Any]] {
                    if let productId = results[0]["productId"] as? String {
                        print("PRODUCT ID \(productId)")

                    }
                }
            }
            
        }
        
        visionHandler = VisionHandler()
        
        isDetectingIndicatorView.backgroundColor = .yellow
        captureCurrentFrameButton.backgroundColor = .red
        captureCurrentFrameButton.layer.borderColor = UIColor.black.cgColor
        captureCurrentFrameButton.layer.borderWidth = 2
        
        overlayView.backgroundColor = .clear
        
        scannedTextDisplayTextView.text = ""
        scannedTextDisplayTextView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        setupCamera()
        
        cardDetectionArea.layer.borderWidth = 2
        cardDetectionArea.layer.borderColor = UIColor.red.cgColor
        cardDetectionArea.backgroundColor = .clear
    }
    
    override func viewDidLayoutSubviews() {
        videoPreviewLayer?.frame = view.bounds
        isDetectingIndicatorView.layer.cornerRadius = isDetectingIndicatorView.bounds.height / 2
        
        captureCurrentFrameButton.layer.cornerRadius = captureCurrentFrameButton.bounds.height / 2
    }
    
    //MARK: - Private Methods
    private func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("Capture Device not found")
            return
        }
        
        do {
            try captureDevice.lockForConfiguration()
            captureDevice.focusMode = .continuousAutoFocus
            captureDevice.unlockForConfiguration()
        } catch let error {
            print("capture device config error: \(error)")
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            captureSession = AVCaptureSession()
            captureSession?.addInput(input)
            
            captureSession?.sessionPreset = AVCaptureSession.Preset.hd1920x1080
            
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            videoPreviewLayer?.connection?.videoOrientation = videoOrientation

            dataOutput = AVCaptureVideoDataOutput()
            dataOutput?.setSampleBufferDelegate(self, queue: dataOutputQueue)
            dataOutput?.alwaysDiscardsLateVideoFrames = true
            dataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

            previewView.layer.addSublayer(videoPreviewLayer!)
            captureSession?.commitConfiguration()
            captureSession?.startRunning()
        } catch let error {
            print("ERROR: \(error)")
        }
    }
    
    private func toggleDataOuput(_ on: Bool) {
        guard let output = dataOutput else {
            return
        }
        if on {
            if captureSession?.canAddOutput(output) ?? false {
                captureSession?.addOutput(output)
            }
        } else {
            captureSession?.removeOutput(output)
        }
    }
    
    private func addDebugFrameToView(_ elementFrame: CGRect) {
        let view = UIView(frame: elementFrame)
        view.layer.borderColor = UIColor.red.cgColor
        view.layer.borderWidth = 2
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let elementFrameCenter = CGPoint(x: elementFrame.width/2, y: elementFrame.height/2)
        var overlappingFrameIndices = [Int]()
        for (i, debugFrame) in debugFrames.enumerated() {
            if debugFrame.bounds.contains(elementFrameCenter) {
                overlappingFrameIndices.append(i)
            }
        }
        
        overlappingFrameIndices.forEach { (i) in
            if debugFrames.count >= i {
                debugFrames[i].removeFromSuperview()
            }
        }
        DispatchQueue.main.async {
            self.overlayView.addSubview(view)
        }
        debugFrames.append(view)
    }
    
    private func processSampleBuffer(_ buffer: CMSampleBuffer) {
        visionHandler.processBuffer(buffer, withOrientation: visionOrientation, { (result) in
            switch result {
            case .success(let visionText):
                self.handleVisionTextResults(visionText)
            case .error(let error):
                print("Error processing sample buffer: \(error)")
                self.scannedTextDisplayTextView.text = "\n\n Error processing sample buffer: \(error)"
            }
        })
    }
    
    private func processVisionText(_ visionText: [VisionText]) {
        for feature in visionText {
            if let block = feature as? VisionTextBlock {
                for line in block.lines {

                    let adjustedFrame = self.getAdjustedVisionElementFrame(line.frame)
                    if self.cardDetectionArea.frame.contains(adjustedFrame.origin) {
                        let cardElement = CardElement(text: line.text, frame: line.frame)
                        self.detectedText.append(line.text)
                        self.cardElements.append(cardElement)
                        self.addDebugFrameToView(adjustedFrame)
                        print("line \(line.text)")
                    }
                }
            }
        }
    }
    
    private func handleVisionTextResults(_ visionText: [VisionText]) {
        for feature in visionText {
            if let block = feature as? VisionTextBlock {
                for line in block.lines {
                    let adjustedFrame = self.getAdjustedVisionElementFrame(line.frame)
                    if self.cardDetectionArea.frame.contains(adjustedFrame.origin) {
                        self.addDebugFrameToView(adjustedFrame)
                        let cardElement = CardElement(text: line.text, frame: line.frame)
                        self.detectedText.append(line.text)
                        self.cardElements.append(cardElement)
                        if let upperLeftElements = self.getUpperLeftElements(self.cardElements) {
                            let upperLeftElementText = upperLeftElements.map{$0.text}
                            let frequencyFilteredText = self.getTopResultsForLines(upperLeftElementText, resultsLimit: 5, withMinimumFrequency: 5)
                            var displayText = ""
                            frequencyFilteredText.forEach{displayText += "\($0)\n\n"}
                            self.scannedTextDisplayTextView.text = displayText
                        }
                        
                       

                        print("line \(line.text)")
                    }
                }
            }
        }
    }
    
    private func clear() {
        for view in debugFrames {
            view.removeFromSuperview()
        }
        detectedText = []
    }
    
    //MARK: - Utility methods
    private func getAdjustedVisionElementFrame(_ elementFrame: CGRect) -> CGRect {
        let screen = UIScreen.main.bounds
        var frame = elementFrame
        if let image = self.bufferImageForSizing {
            let xRatio = screen.width / image.size.width
            let yRatio = screen.height / image.size.height
            frame = CGRect(x: frame.minX * xRatio, y: frame.minY * yRatio, width: frame.width * xRatio, height: frame.height * yRatio)
        }
        return frame
    }
    
    private func getImageFromBuffer(_ buffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            print("Could not create pixel buffer")
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return UIImage(ciImage: ciImage)
    }
    
    //MARK: - IBActions
    @IBAction func detectButtonAction(_ sender: Any) {
        toggleDataOuput(!outputIsOn)
        outputIsOn = !outputIsOn
    }
    
    @IBAction func clearDebugFrames(_ sender: UIButton) {
        clear()
    }
    
    @IBAction func captureCurrentFrameAction(_ sender: Any) {
        
        toggleDataOuput(false)
        clear()
        
        guard let buffer = currentCMSampleBuffer else {
            self.scannedTextDisplayTextView.text = "no current sample buffer"
            print("no current sample buffer")
            return
        }
        
        visionHandler.processBuffer(buffer, withOrientation: visionOrientation) { (result) in
            switch result {
            case .success(let visionText):
                self.handleVisionTextResults(visionText)
            case .error(let error):
                self.scannedTextDisplayTextView.text = "Error processing sample buffer: \(error)"
                print("Error processing sample buffer: \(error)")
            }
        }
    }
    
    //MARK: - Sorting
    ///needs to be able to return of array of matches for upper left.
    ///what defines upper left? can i look for origin within top left box?
    func getUpperLeftElements(_ cardElements: [CardElement]) -> [CardElement]? {
        let sortedElements = cardElements.sorted {
            return ($0.frame.origin.y < $1.frame.origin.y) && ($0.frame.origin.x < $1.frame.origin.x)
        }
        
        guard let topLeftMostElement = sortedElements[safe: 0] else {
            return nil
        }
        
        let topLeftElements = sortedElements.filter {topLeftMostElement.frame.intersects($0.frame)}
        return topLeftElements + [topLeftMostElement]
    }
    
    ///for minimum frequency, probably should use a relative appearence rate rather than hard amount of appearances
    private func getMostFrequentTextResultForLines(_ textLines: [String], withMinimumFrequency minFrequency: Int = 2) -> (text: String, frequency: Int)? {
        var mostOccuringTexts = [String:Int]()
        
        for text in textLines {
            let currentValue = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (currentValue + 1)
        }
        
        let textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}

        let sortedByFrequency = textsWithMinimumFrequency.sorted {$0.value > $1.value}
        guard let mostFrequentText = sortedByFrequency[safe: 0]?.key, let frequency = sortedByFrequency[safe: 0]?.value else {
            return nil
        }

        print("most frequent text: \(mostFrequentText) - occuring \(frequency) times")
        return (mostFrequentText, frequency)
    }
    
    private func getTopResultsForLines(_ textLines: [String], resultsLimit limit: Int, withMinimumFrequency minFrequency: Int = 2) -> [String] {
        var mostOccuringTexts = [String:Int]()
        
        for text in textLines {
            let currentValue = mostOccuringTexts[text] ?? 0
            mostOccuringTexts[text] = (currentValue + 1)
        }
        
        var textsWithMinimumFrequency = mostOccuringTexts.filter {$0.value > minFrequency}
        
        var topResults: [(String, Int)] {
            var results = [(String, Int)]()
            for (element, frequency) in textsWithMinimumFrequency {
                results.append((element, frequency))
            }
            return results
        }
        
        let resultsSortedByFrequency = topResults.sorted{$0.1 > $1.1}
        let topResultsWithLimit = Array(resultsSortedByFrequency.prefix(limit))
        return topResultsWithLimit.map{ $0.0 }
    }
}

//MARK: - Extensions
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if bufferImageForSizing == nil {
            bufferImageForSizing = getImageFromBuffer(sampleBuffer)
        }
        
        outputCounter += 1
        if outputCounter > captureSampleBufferRate {
            currentCMSampleBuffer = sampleBuffer
            processSampleBuffer(sampleBuffer)
            outputCounter = 0
        }
    }
}

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeRight: return .landscapeRight
        case .landscapeLeft: return .landscapeLeft
        case .portrait: return .portrait
        default: return nil
        }
    }
}
