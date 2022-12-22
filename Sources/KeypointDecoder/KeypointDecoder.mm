#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#include <iostream>
#include <vector>
#include <numeric>
#import "KeypointDecoder.h"
#import "keypoint_postprocess.h"
#import <mach/mach_time.h>
#import <CoreML/CoreML.h>

const size_t keypointsNumber = 17;
const size_t modelWidth = 192;
const size_t modelHeight = 256;
const float aspect_ratio = modelWidth * 1.0 / modelHeight;
const float pixel_std = 200.0;

@implementation KeypointDecoder

-(id) init {
  if (self = [super init]) {
    NSError *err;
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *modelUrl = [bundle URLForResource:@"vitpose-b256x192_fp16"
                               withExtension:[NSString stringWithFormat:@"%@c", @"mlmodel"]];
    
    if (@available(iOS 16.0, macOS 13.0, *)) {
      MLModelConfiguration* configuration = [MLModelConfiguration alloc];
        configuration.computeUnits = MLComputeUnitsCPUAndNeuralEngine;
      self.model = [MLModel modelWithContentsOfURL:modelUrl configuration:configuration error:&err];
    } else {
      self.model = [MLModel modelWithContentsOfURL:modelUrl error:&err];
    }
  }
  return self;
}

-(void) run: (UIImage* ) uiImage
      boxes: (float*) boxes
     boxNum: (int) boxNum
     result: (float*) result
{
  std::vector<float> _boxes(&boxes[0], boxes + boxNum);
  
  int num = (int)_boxes.size() / 4;
  
  std::vector<float> keypoints;
  
  cv::Mat image;
  UIImageToMat(uiImage, image);
  
  for (int j = 0; j < num; ++j) {
    
    std::vector<float> box = { _boxes[j*4], _boxes[j*4+1], _boxes[j*4+2], _boxes[j*4+3] };
    std::vector<float> center;
    std::vector<float> scale;
    UIImage* preUIImage = preExecute(image, box, modelWidth, modelHeight, center, scale);
    
    DEBUG_MSG("center: " << center[0] << ", " << center[1] );
    DEBUG_MSG("scale: " << scale[0] << ", " << scale[1] );
    
    std::vector<float> heatmap = [self predict:preUIImage];
    
    std::vector<float> preds = postExecute(heatmap, modelWidth, modelHeight, center, scale);
    copy(preds.begin(), preds.end(), back_inserter(keypoints) );
  }

  std::memcpy(&result[0], keypoints.data(), keypoints.size()*sizeof(float));
  
}

UIImage* preExecute(cv::Mat image,
                const std::vector<float> & box,
                int modelWidth, int modelHeight,
                std::vector<float> & center,
                std::vector<float> & scale)
{
  box2cs(box, center, scale);
  
  std::vector<int> output_size = {modelWidth, modelHeight};
  cv::Mat trans;
  std::vector<float> _scale(scale);
  _scale[0] = scale[0] * 200;
  _scale[1] = scale[1] * 200;
  get_affine_transform(center, _scale, 0, output_size, trans, 0);
  cv::Mat cropped_box;
  cv::warpAffine(image, cropped_box, trans, cv::Size(output_size[0], output_size[1]), cv::INTER_LINEAR);
  
  cv::Mat bgr;
  cv::cvtColor(cropped_box, bgr, cv::COLOR_RGB2BGR);
  
  return MatToUIImage(bgr);
}

-(std::vector<float>) predict: (UIImage*) uiImage
{
  NSError *err;
  MLFeatureValue *featureValue = [MLFeatureValue featureValueWithCGImage: uiImage.CGImage pixelsWide: modelWidth pixelsHigh: modelHeight pixelFormatType:kCVPixelFormatType_32BGRA options:nil error:&err];
  NSString *inputName = [[[[self.model modelDescription] inputDescriptionsByName] allKeys] firstObject];
  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:featureValue, inputName, nil];
  MLDictionaryFeatureProvider *input = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{inputName: featureValue} error:&err];
  id prediction = [self.model predictionFromFeatures:input error:&err];
//  NSLog(@"%@", [[prediction dictionary] objectForKey:@"output"]);
  
  MLMultiArray* mlarray = [prediction featureValueForName:@"output"].multiArrayValue;
  float* data = (float*) mlarray.dataPointer;
  int outputSize = (int)mlarray.count;
  std::vector<float> heatmap(&data[0], data + outputSize);
  return heatmap;
}

std::vector<float> postExecute(std::vector<float>& heatmap, int modelWidth, int modelHeight,
                  std::vector<float> & center, std::vector<float> & scale)
{
  uint64_t start, elapsed;
  start = mach_absolute_time();
  
  int heatmap_height = modelHeight / 4;
  int heatmap_width = modelWidth / 4;
  std::vector<int> dim = { 1, keypointsNumber, heatmap_height, heatmap_width };
  std::vector<int> idxdim{0};
  
  std::vector<float> coords(keypointsNumber * 2, 0);
  std::vector<float> maxvals(keypointsNumber, 0);
  std::vector<float> preds(keypointsNumber * 3, 0);
  std::vector<int> img_size{heatmap_width, heatmap_height};
  
  get_max_preds(heatmap,
                dim,
                coords,
                maxvals,0,0);
  
  for (int j = 0; j < dim[1]; ++j) {
    int index = j * dim[2] * dim[3];
    int px = int(coords[j * 2] + 0.5);
    int py = int(coords[j * 2 + 1] + 0.5);
    
    if (px > 0 && px < heatmap_width - 1) {
      float diff_x = heatmap[index + py * dim[3] + px + 1] -
                          heatmap[index + py * dim[3] + px - 1];
      coords[j * 2] += sign(diff_x) * 0.25;
    }
    if (py > 0 && py < heatmap_height - 1) {
      float diff_y = heatmap[index + (py + 1) * dim[3] + px] -
                          heatmap[index + (py - 1) * dim[3] + px];
      coords[j * 2+1] += sign(diff_y) * 0.25;
    }
  }
  
  std::vector<float> _scale(scale);
  _scale[0] = scale[0] * 200;
  _scale[1] = scale[1] * 200;
  
  transform_preds(coords, center, _scale, img_size, dim, preds, true);
  
  std::vector<float> results(keypointsNumber * 3, 0);
  
  for (int j = 0; j < dim[1]; ++j) {
    results[j * 3] = preds[j * 3 + 1];
    results[j * 3 + 1] = preds[j * 3 + 2];
    results[j * 3 + 2] = maxvals[j];
  }
  return results;
}

float sign(float A){
    return (A>0)-(A<0);
}
    
- (UIImage*) renderHumanPose: (UIImage*) uiImage
                   keypoints: (float*) keypoints
                   peopleNum: (int) peopleNum
                       boxes: (float*) boxes
{
  std::vector<HumanPose> poses;
  for (int i = 0; i < peopleNum; ++i) {
    HumanPose pose{
      std::vector<cv::Point2f>(keypointsNumber, cv::Point2f(-1.0f, -1.0f)),
      std::vector<float>(keypointsNumber, 0.0),
      1.0};
    for (int j = 0; j < keypointsNumber; ++j) {
      int n = i * keypointsNumber * 3 + j * 3;
      pose.keypoints[j].x = keypoints[n];
      pose.keypoints[j].y = keypoints[n + 1];
      pose.scores[j] = keypoints[n + 2];
    }
    pose.score = std::accumulate(pose.scores.begin(), pose.scores.end(), 0.0) / pose.scores.size();
    poses.push_back(pose);
    DEBUG_MSG("score: " << pose.score);
  }
  
  cv::Mat outputImg;
  UIImageToMat(uiImage, outputImg);
  cv::cvtColor(outputImg, outputImg, cv::COLOR_RGB2RGBA);
  
  static const cv::Scalar colors[keypointsNumber] =
  {
    cv::Scalar(255, 0, 0),
    cv::Scalar(255, 85, 0),
    cv::Scalar(255, 170, 0),
    cv::Scalar(255, 255, 0),
    cv::Scalar(170, 255, 0),
    cv::Scalar(85, 255, 0),
    cv::Scalar(0, 255, 0),
    cv::Scalar(0, 255, 85),
    cv::Scalar(0, 255, 170),
    cv::Scalar(0, 255, 255),
    cv::Scalar(0, 170, 255),
    cv::Scalar(0, 85, 255),
    cv::Scalar(0, 0, 255),
    cv::Scalar(85, 0, 255),
    cv::Scalar(170, 0, 255),
    cv::Scalar(255, 0, 255),
    cv::Scalar(255, 0, 170),
  };
  /*
   0: nose        1: l eye      2: r eye    3: l ear   4: r ear
   5: l shoulder  6: r shoulder 7: l elbow  8: r elbow
   9: l wrist    10: r wrist    11: l hip   12: r hip  13: l knee
   14: r knee    15: l ankle    16: r ankle
   */
  static const std::pair<int, int> keypointsOP[] = {
    {0, 1}, // nose , l_eye
    {0, 2}, // nose , r_eye
    {1, 3},
    {2, 4},
    {2, 4},
    {5, 7}, // l shoulder l elbow
    {7, 9}, // l elbow l wrist
    {6, 8}, // r shoulder r elbow
    {8, 10},// r elbow r wrist
    {11, 13},
    {13, 15},
    {12, 14},
    {14, 16},
    {5, 6}, // l shoulder r shoulder
    {11, 12}, //
    {5, 11},
    {6, 12},
  };
  
  const int stickWidth = 2;
  const cv::Point2f absentKeypoint(-1.0f, -1.0f);
  for (auto& pose : poses) {
    for (size_t keypointIdx = 0; keypointIdx < pose.keypoints.size(); keypointIdx++) {
      if (pose.keypoints[keypointIdx] != absentKeypoint) {
        cv::circle(outputImg, pose.keypoints[keypointIdx], 2, colors[keypointIdx], -1);
      }
    }
  }
  
  std::vector<std::pair<int, int>> limbKeypointsIds;
  if (!poses.empty()) {
    limbKeypointsIds.insert(limbKeypointsIds.begin(), std::begin(keypointsOP), std::end(keypointsOP));
  }
  
  cv::Mat pane = outputImg.clone();
  for (auto pose : poses) {
    for (const auto& limbKeypointsId : limbKeypointsIds) {
      std::pair<cv::Point2f, cv::Point2f> limbKeypoints(pose.keypoints[limbKeypointsId.first],
                                                        pose.keypoints[limbKeypointsId.second]);
      if (limbKeypoints.first == absentKeypoint || limbKeypoints.second == absentKeypoint) {
        continue;
      }
      
      float meanX = (limbKeypoints.first.x + limbKeypoints.second.x) / 2;
      float meanY = (limbKeypoints.first.y + limbKeypoints.second.y) / 2;
      cv::Point difference = limbKeypoints.first - limbKeypoints.second;
      double length = std::sqrt(difference.x * difference.x + difference.y * difference.y);
      int angle = static_cast<int>(std::atan2(difference.y, difference.x) * 180 / CV_PI);
      std::vector<cv::Point> polygon;
      cv::ellipse2Poly(cv::Point2d(meanX, meanY), cv::Size2d(length / 2, stickWidth), angle, 0, 360, 1, polygon);
      cv::fillConvexPoly(pane, polygon, colors[limbKeypointsId.second]);
    }
  }
  cv::addWeighted(outputImg, 0.4, pane, 0.6, 0, outputImg);
  
  std::vector<float> _boxes(&boxes[0], boxes + peopleNum * 4);
  for (int j = 0; j < peopleNum; ++j) {
    std::vector<float> box = { _boxes[j*4], _boxes[j*4+1], _boxes[j*4+2], _boxes[j*4+3] };
    cv::rectangle(outputImg, cv::Point(box[0], box[1]), cv::Point(box[2] + box[0], box[3] + box[1]), cv::Scalar(255,0,0), 2);
  }
  
  UIImage *preview = MatToUIImage(outputImg);
  outputImg.release();
  return preview;
}

std::vector<float> xywh2cs(float x, float y, float w, float h) {
  std::vector<float> center(2, 0);
  center[0] = x + w * 0.5;
  center[1] = y + h * 0.5;

  if (w > aspect_ratio * h) {
    h = w * 1.0 / aspect_ratio;
  } else if (w < aspect_ratio * h) {
    w = h * aspect_ratio;
  }
  std::vector<float> scale = {static_cast<float>(w * 1.0 / pixel_std), static_cast<float>(h * 1.0 / pixel_std)};
  if (center[0] != -1) {
    std::transform(scale.begin(), scale.end(), scale.begin(),
                   std::bind(std::multiplies<float>(), std::placeholders::_1, 1.25));
  }
  return {center[0], center[1], scale[0], scale[1]};
}

void box2cs(const std::vector<float> & box,
            std::vector<float> & center,
            std::vector<float> & scale){

  float x, y, w, h;
  x = box[0];
  y = box[1];
  w = box[2];
  h = box[3];
  const std::vector<float> & bbox = xywh2cs(x, y, w, h);

  center = { bbox[0], bbox[1] };
  scale = { bbox[2], bbox[3] };

}

struct HumanPose {
  std::vector<cv::Point2f> keypoints;
  std::vector<float> scores;
  float score;
};

@end
