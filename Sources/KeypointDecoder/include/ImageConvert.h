#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
//#ifdef __OBJC__
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
//#endif

#ifndef ImageConvert_h
#define ImageConvert_h
@interface ImageConvert : NSObject

-(CVImageBufferRef) getImageBufferFromMat: (cv::Mat) mat;

@end
#endif /* ImageConvert_h */
