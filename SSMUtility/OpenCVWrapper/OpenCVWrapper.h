//
//  OpenCVWrapper.h
//  SSMUtility
//
//  Created by Tushar Chitnavis on 26/12/21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject
-(UIImage*)getRegionOfInterestFace:(UIImage*)ssmInputImage :(UIImage*)originalInputImage;
@end

NS_ASSUME_NONNULL_END
