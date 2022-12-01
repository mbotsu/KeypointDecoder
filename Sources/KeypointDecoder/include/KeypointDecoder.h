#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>

#ifndef KeypointDecoder_h
#define KeypointDecoder_h

#ifdef OBJC_DEBUG
#define DEBUG_MSG(str) do { std::cout << str << std::endl; } while( false )
#else
#define DEBUG_MSG(str) do { } while ( false )
#endif

@interface KeypointDecoder : NSObject

-(void) run: (UIImage* ) uiImage
      boxes: (float*) boxes
     boxNum: (int) boxNum
     result: (float*) result;

- (UIImage*) renderHumanPose: (UIImage*) uiImage
                   keypoints: (float*) keypoints
                   peopleNum: (int) peopleNum
                       boxes: (float*) boxes;

@property (strong, nonatomic) MLModel *model;

@end

#endif /* KeypointDecoder_h */
