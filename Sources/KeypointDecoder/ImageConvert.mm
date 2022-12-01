#import "ImageConvert.h"

@implementation ImageConvert

-(CVImageBufferRef) getImageBufferFromMat: (cv::Mat) mat {

    cv::cvtColor(mat, mat, cv::COLOR_BGR2BGRA);

    int width = mat.cols;
    int height = mat.rows;

    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithInt:width], kCVPixelBufferWidthKey,
                             [NSNumber numberWithInt:height], kCVPixelBufferHeightKey,
                             nil];

    CVPixelBufferRef imageBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorMalloc, width, height, kCVPixelFormatType_32BGRA, (CFDictionaryRef) CFBridgingRetain(options), &imageBuffer);


    NSParameterAssert(status == kCVReturnSuccess && imageBuffer != NULL);

    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *base = CVPixelBufferGetBaseAddress(imageBuffer) ;
    memcpy(base, mat.data, mat.total()*4);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    return imageBuffer;
}

@end
