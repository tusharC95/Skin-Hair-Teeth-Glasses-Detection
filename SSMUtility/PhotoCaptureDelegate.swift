/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The app's photo capture delegate object.
 */

import AVFoundation
import UIKit
import Accelerate

class PhotoCaptureProcessor: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let livePhotoCaptureHandler: (Bool) -> Void
    
    lazy var context = CIContext()
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private let photoProcessingHandler: (Bool) -> Void
    
    private let photoSavedHandler: (Int, Error?) -> Void
    
    private var photoData: Data?
    private var maxPhotoProcessingTime: CMTime?
    
    let wrapper = OpenCVWrapper()
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void,
         photoSavedHandler: @escaping (Int, Error?) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.photoSavedHandler = photoSavedHandler
    }
    
    private func didFinish() {
        completionHandler(self)
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    /*
     This extension adopts all of the AVCapturePhotoCaptureDelegate protocol methods.
     */
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }
        
        // Show a spinner if processing time exceeds one second.
        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            photoProcessingHandler(true)
        }
    }
    
    func handleMatteData(_ photo: AVCapturePhoto, ssmType: AVSemanticSegmentationMatte.MatteType) {
        
        // Check if this feature type is selected by the user
        guard isFeatureSelected(ssmType) else {
            print("Skipping \(ssmType) - not selected by user")
            return
        }
        
        // Find the semantic segmentation matte image for the specified type.
        guard var segmentationMatte = photo.semanticSegmentationMatte(for: ssmType) else { return }
        
        // Retrieve the photo orientation and apply it to the matte image.
        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
           let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            // Apply the Exif orientation to the matte image.
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
        }
        
        var imageOption: CIImageOption!
        var featureTypeName: String = ""
        
        // Switch on the AVSemanticSegmentationMatteType value.
        switch ssmType {
        case .hair:
            imageOption = .auxiliarySemanticSegmentationHairMatte
            featureTypeName = "Hair"
        case .skin:
            imageOption = .auxiliarySemanticSegmentationSkinMatte
            featureTypeName = "Skin"
        case .teeth:
            imageOption = .auxiliarySemanticSegmentationTeethMatte
            featureTypeName = "Teeth"
        case .glasses:
            imageOption = .auxiliarySemanticSegmentationGlassesMatte
            featureTypeName = "Glasses"
        default:
            print("This semantic segmentation type is not supported!")
            return
        }
        
        let ciImage = CIImage(cvImageBuffer: segmentationMatte.mattingImage, options: [imageOption: true])
        
        // Get the HEIF representation of this image.
        guard let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let imageData = context.heifRepresentation(of: ciImage,
                                                         format: .RGBA8,
                                                         colorSpace: linearColorSpace,
                                                         options: [.depthImage: ciImage]) else { return }
        
        if let skinDetectedImage = UIImage(data: imageData) {
            let newImage = self.sFunc_imageFixOrientation(img: skinDetectedImage)
            let ciimage = CIImage(cgImage: newImage.cgImage!)
            var skinDetectedOutputImage = UIImage()
            
            
            let flipped = ciimage.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            skinDetectedOutputImage = self.convert(cmage: flipped)
            
            // Store with feature type name for correct labeling
            Helper.sharedInstance.segmentationImages[featureTypeName] = skinDetectedOutputImage
        }
    }
    
    /// Check if a semantic segmentation type is selected by the user
    private func isFeatureSelected(_ ssmType: AVSemanticSegmentationMatte.MatteType) -> Bool {
        let selectedTypes = Helper.sharedInstance.selectedMatteTypes
        return selectedTypes.contains(ssmType)
    }
    
    /// - Tag: DidFinishProcessingPhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoProcessingHandler(false)
        
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        } else {
            photoData = photo.fileDataRepresentation()
        }
        
        if let validImage = UIImage(data: photoData!) {
            
            let flippedImage = validImage.imageLeftMirror()
            let rotatedImage = flippedImage.rotate(radians: .pi*2)!
            Helper.sharedInstance.selectedImage = rotatedImage
        }
        
        for semanticSegmentationType in output.enabledSemanticSegmentationMatteTypes {
            handleMatteData(photo, ssmType: semanticSegmentationType)
        }
    }
    
    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }
        
        guard let photoData = photoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        
        // Save images to sandboxed storage
        let captureDate = Date()
        var savedCount = 0
        
        // Save original photo
        if let validInputImage = Helper.sharedInstance.selectedImage {
            if ImageStorageManager.shared.saveImage(validInputImage, featureType: nil, captureDate: captureDate) != nil {
                savedCount += 1
            }
            
            // Process and save feature images using the dictionary (correct feature mapping)
            for (featureType, smmImage) in Helper.sharedInstance.segmentationImages {
                if let validImage = smmImage.resizeImageUsingVImage(size: CGSize(width: validInputImage.size.width, height: validInputImage.size.height)) {
                    // Extract the feature and save with correct label
                    let maskImage = wrapper.getRegionOfInterestFace(validImage, validInputImage)
                    if ImageStorageManager.shared.saveImage(maskImage, featureType: featureType, captureDate: captureDate) != nil {
                        savedCount += 1
                    }
                }
            }
        }
        
        Helper.sharedInstance.segmentationImages.removeAll()
        
        // Call completion handler
        if savedCount > 0 {
            self.photoSavedHandler(savedCount, nil)
        } else {
            self.photoSavedHandler(0, NSError(domain: "Unmask Lab", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save images"]))
                    }
                    
                    self.didFinish()
    }
    
    func sFunc_imageFixOrientation(img: UIImage) -> UIImage {
        
        if img.imageOrientation == UIImage.Orientation.up {
            return img
        }
        
        var transform: CGAffineTransform = CGAffineTransform.identity
        
        if img.imageOrientation == UIImage.Orientation.down
            || img.imageOrientation == UIImage.Orientation.downMirrored {
            
            transform = transform.translatedBy(x: img.size.width, y: img.size.height)
            transform = transform.rotated(by: CGFloat(Double.pi))
        }
        
        if img.imageOrientation == UIImage.Orientation.left
            || img.imageOrientation == UIImage.Orientation.leftMirrored {
            
            transform = transform.translatedBy(x: img.size.width, y: 0)
            transform = transform.rotated(by: CGFloat(Double.pi/2))
        }
        
        if img.imageOrientation == UIImage.Orientation.right
            || img.imageOrientation == UIImage.Orientation.rightMirrored {
            
            transform = transform.translatedBy(x: 0, y: img.size.height)
            transform = transform.rotated(by: CGFloat(-Double.pi/2))
        }
        
        if img.imageOrientation == UIImage.Orientation.upMirrored
            || img.imageOrientation == UIImage.Orientation.downMirrored {
            
            transform = transform.translatedBy(x: img.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        }
        
        if img.imageOrientation == UIImage.Orientation.leftMirrored
            || img.imageOrientation == UIImage.Orientation.rightMirrored {
            
            transform = transform.translatedBy(x: img.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        }
        
        let ctx: CGContext = CGContext(data: nil, width: Int(img.size.width), height: Int(img.size.height),
                                       bitsPerComponent: img.cgImage!.bitsPerComponent, bytesPerRow: 0,
                                       space: img.cgImage!.colorSpace!,
                                       bitmapInfo: img.cgImage!.bitmapInfo.rawValue)!
        
        ctx.concatenate(transform)
        
        if img.imageOrientation == UIImage.Orientation.left
            || img.imageOrientation == UIImage.Orientation.leftMirrored
            || img.imageOrientation == UIImage.Orientation.right
            || img.imageOrientation == UIImage.Orientation.rightMirrored {
            
            ctx.draw(img.cgImage!, in: CGRect(x: 0, y: 0, width: img.size.height, height: img.size.width))
            
        } else {
            ctx.draw(img.cgImage!, in: CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height))
        }
        
        let cgimg: CGImage = ctx.makeImage()!
        let imgEnd: UIImage = UIImage(cgImage: cgimg)
        
        return imgEnd
    }
    
    func convert(cmage: CIImage) -> UIImage {
        
        let context: CIContext = CIContext.init(options: nil)
        let cgImage: CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image: UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
}
