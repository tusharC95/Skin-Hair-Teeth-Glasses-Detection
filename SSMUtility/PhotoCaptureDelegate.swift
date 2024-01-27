/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The app's photo capture delegate object.
 */

import AVFoundation
import Photos
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
    
    private var photoData: Data?
    
    private var livePhotoCompanionMovieURL: URL?
    
    private var portraitEffectsMatteData: Data?
    
    private var semanticSegmentationMatteDataArray = [Data]()
    private var maxPhotoProcessingTime: CMTime?
    
    // Save the location of captured photos
    var location: CLLocation?
    
    let wrapper = OpenCVWrapper()
    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
    }
    
    private func didFinish() {
        if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
                do {
                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
                } catch {
                    print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
                }
            }
        }
        
        completionHandler(self)
    }
    
    func getFaceFeatures(inputImage: UIImage, ssmImage: UIImage?) {
        
        if let validSkinSegImage = ssmImage {
            let maskImage = wrapper.getRegionOfInterestFace(validSkinSegImage, inputImage)
            UIImageWriteToSavedPhotosAlbum(maskImage, nil, nil, nil)
            
        }
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
        
        // Find the semantic segmentation matte image for the specified type.
        guard var segmentationMatte = photo.semanticSegmentationMatte(for: ssmType) else { return }
        
        // Retrieve the photo orientation and apply it to the matte image.
        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
           let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            // Apply the Exif orientation to the matte image.
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
        }
        
        var imageOption: CIImageOption!
        
        // Switch on the AVSemanticSegmentationMatteType value.
        switch ssmType {
        case .hair:
            imageOption = .auxiliarySemanticSegmentationHairMatte
        case .skin:
            imageOption = .auxiliarySemanticSegmentationSkinMatte
        case .teeth:
            imageOption = .auxiliarySemanticSegmentationTeethMatte
        case .glasses:
            imageOption = .auxiliarySemanticSegmentationGlassesMatte
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
            
            Helper.sharedInstance.segmentationImageArray.append(skinDetectedOutputImage)
        }
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

        
        // A portrait effects matte gets generated only if AVFoundation detects a face.
        if var portraitEffectsMatte = photo.portraitEffectsMatte {
            if let orientation = photo.metadata[ String(kCGImagePropertyOrientation) ] as? UInt32 {
                portraitEffectsMatte = portraitEffectsMatte.applyingExifOrientation(CGImagePropertyOrientation(rawValue: orientation)!)
            }
            let portraitEffectsMattePixelBuffer = portraitEffectsMatte.mattingImage
            let portraitEffectsMatteImage = CIImage( cvImageBuffer: portraitEffectsMattePixelBuffer, options: [ .auxiliaryPortraitEffectsMatte: true ] )
            
            guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                portraitEffectsMatteData = nil
                return
            }
            portraitEffectsMatteData = context.heifRepresentation(of: portraitEffectsMatteImage,
                                                                  format: .RGBA8,
                                                                  colorSpace: perceptualColorSpace,
                                                                  options: [.portraitEffectsMatteImage: portraitEffectsMatteImage])
        } else {
            portraitEffectsMatteData = nil
        }
        
        for semanticSegmentationType in output.enabledSemanticSegmentationMatteTypes {
            handleMatteData(photo, ssmType: semanticSegmentationType)
        }
    }
    
    /// - Tag: DidFinishRecordingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }
    
    /// - Tag: DidFinishProcessingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            print("Error processing Live Photo companion movie: \(String(describing: error))")
            return
        }
        livePhotoCompanionMovieURL = outputFileURL
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
        
        
        if let validInputImage = Helper.sharedInstance.selectedImage {
            for smmImage in Helper.sharedInstance.segmentationImageArray {
                if let validImage = smmImage.resizeImageUsingVImage(size: CGSize(width: validInputImage.size.width, height: validInputImage.size.height)) {
                    getFaceFeatures(inputImage: validInputImage, ssmImage: validImage)
                }
            }
        }
        
        Helper.sharedInstance.segmentationImageArray.removeAll()
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    creationRequest.addResource(with: .photo, data: photoData, options: options)
                    
                    // Specify the location the photo was taken
                    creationRequest.location = self.location
                    // Save Portrait Effects Matte to Photos Library only if it was generated
                    for semanticSegmentationMatteData in self.semanticSegmentationMatteDataArray {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: semanticSegmentationMatteData,
                                                    options: nil)
                    }
                    
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving photo to photo library: \(error)")
                    }
                    
                    self.didFinish()
                }
                )
            } else {
                self.didFinish()
            }
        }
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

extension UIImage {
    
    func imageLeftMirror() -> UIImage {
        guard let cgImage = cgImage else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .leftMirrored)
    }
    
    func resizeImageUsingVImage(size: CGSize) -> UIImage? {
        let cgImage = self.cgImage!
        var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: nil, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue), version: 0, decode: nil, renderingIntent: CGColorRenderingIntent.defaultIntent)
        var sourceBuffer = vImage_Buffer()
        defer {
            free(sourceBuffer.data)
        }
        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, numericCast(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        // create a destination buffer
        _ = self.scale
        let destWidth = Int(size.width)
        let destHeight = Int(size.height)
        let bytesPerPixel = self.cgImage!.bitsPerPixel/8
        let destBytesPerRow = destWidth * bytesPerPixel
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: destHeight * destBytesPerRow)
        defer {
            //             destData.deallocate(capacity: destHeight * destBytesPerRow)
            //        'deallocate(capacity:)' is unavailable: Swift currently only supports freeing entire heap blocks, use deallocate() instead
            destData.deallocate()
        }
        var destBuffer = vImage_Buffer(data: destData, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destBytesPerRow)
        // scale the image
        error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, numericCast(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }
        // create a CGImage from vImage_Buffer
        var destCGImage = vImageCreateCGImageFromBuffer(&destBuffer, &format, nil, nil, numericCast(kvImageNoFlags), &error)?.takeRetainedValue()
        guard error == kvImageNoError else { return nil }
        // create a UIImage
        let resizedImage = destCGImage.flatMap { UIImage(cgImage: $0, scale: 0.0, orientation: self.imageOrientation) }
        destCGImage = nil
        return resizedImage
    }
 
    func rotate(radians: Float) -> UIImage? {
         var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
         // Trim off the extremely small float value to prevent core graphics from rounding it up
         newSize.width = floor(newSize.width)
         newSize.height = floor(newSize.height)

         UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
         let context = UIGraphicsGetCurrentContext()!

         // Move origin to middle
         context.translateBy(x: newSize.width/2, y: newSize.height/2)
         // Rotate around middle
         context.rotate(by: CGFloat(radians))
         // Draw the image at its center
         self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))

         let newImage = UIGraphicsGetImageFromCurrentImageContext()
         UIGraphicsEndImageContext()

         return newImage
     }
    
}
