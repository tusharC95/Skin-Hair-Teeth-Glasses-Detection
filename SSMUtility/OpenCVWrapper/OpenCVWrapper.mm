//
//  Wrapper.m
//  SkinColorDetection
//
//  Created by Prerna Chavan on 28/07/21.
//

// Import OpenCV headers BEFORE any Apple headers to avoid NO macro conflict
#ifdef __cplusplus
#import <opencv2/core/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/highgui/highgui.hpp>
#import <opencv2/video/background_segm.hpp>
#endif

// Now import Apple headers
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <opencv2/imgcodecs/ios.h>

#import "OpenCVWrapper.h"

using namespace cv;
using namespace std;

@interface OpenCVWrapper ()

@property (assign) BOOL prepared;

@end

@interface UIImage (OpenCVWrapper)
- (void)convertToMat: (cv::Mat *)pMat;
@end

@implementation UIImage (OpenCVWrapper)
- (void)convertToMat: (cv::Mat *)pMat {
    if (self.imageOrientation == UIImageOrientationRight) {
        UIImageToMat([UIImage imageWithCGImage:self.CGImage scale:1.0 orientation:UIImageOrientationUp], *pMat);
        cv::rotate(*pMat, *pMat, cv::ROTATE_90_CLOCKWISE);
    } else if (self.imageOrientation == UIImageOrientationLeft) {
        UIImageToMat([UIImage imageWithCGImage:self.CGImage scale:1.0 orientation:UIImageOrientationUp], *pMat);
        cv::rotate(*pMat, *pMat, cv::ROTATE_90_COUNTERCLOCKWISE);
    } else {
        UIImageToMat(self, *pMat);
        if (self.imageOrientation == UIImageOrientationDown) {
            cv::rotate(*pMat, *pMat, cv::ROTATE_180);
        }
    }
}
@end

@implementation OpenCVWrapper {
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _prepared = NO;
    }
    
    return self;
}

#ifdef __cplusplus

-(UIImage*)getRegionOfInterestFace:(UIImage*)ssmInputImage :(UIImage*)originalInputImage
{
    cv::Mat ssmInputImageMat;
    [ssmInputImage convertToMat: &ssmInputImageMat];
    
    cv::Mat originalInputImageMat;
    [originalInputImage convertToMat: &originalInputImageMat];
    std::vector<std::vector<cv::Point> > pointListTotal;
    std::vector<std::vector<cv::Point>> edgeContours;
    Mat onlyCroppedAreaMat;
    cv::Mat ssmInputImageHLS;
    
    Mat mask(originalInputImageMat.size(),CV_8UC1, cv::Scalar(0));
    int sensitivity = 50;
    
    Scalar lower_white = Scalar(0, 255-sensitivity, 0);
    Scalar upper_white = Scalar(255, 255, sensitivity);
    
    cvtColor(ssmInputImageMat,ssmInputImageMat,COLOR_BGR2HLS);
    inRange(ssmInputImageMat, lower_white, upper_white, mask);
    originalInputImageMat.copyTo(onlyCroppedAreaMat,mask);
    
    UIImage *croppedImage = MatToUIImage(onlyCroppedAreaMat);
    
    return croppedImage ;
}

#endif

@end

