//   Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <vector>

cv::Point2f get_3rd_point(cv::Point2f& a, cv::Point2f& b);
std::vector<float> get_dir(float src_point_x, float src_point_y, float rot_rad);
void affine_transform(
    float pt_x, float pt_y, cv::Mat& trans, std::vector<float>& x, int p, int num);
void get_affine_transform(std::vector<float>& center,
                             std::vector<float>& scale,
                             float rot,
                             std::vector<int>& output_size,
                             cv::Mat& trans,
                             int inv);
void transform_preds(std::vector<float>& coords,
                     std::vector<float>& center,
                     std::vector<float>& scale,
                     std::vector<int>& output_size,
                     std::vector<int>& dim,
                     std::vector<float>& target_coords,
                     bool affine);
void box_to_center_scale(std::vector<int>& box,
                         int width,
                         int height,
                         std::vector<float>& center,
                         std::vector<float>& scale);
void get_max_preds(std::vector<float>& heatmap,
                   std::vector<int>& dim,
                   std::vector<float>& preds,
                   std::vector<float>& maxvals,
                   int batchid,
                   int joint_idx);
void get_final_preds(std::vector<float>& heatmap,
                     std::vector<int>& dim,
                     std::vector<int>& idxout,
                     std::vector<int>& idxdim,
                     std::vector<float>& center,
                     std::vector<float> scale,
                     std::vector<float>& preds,
                     int batchid,
                     bool DARK = true);
void box2cs(const std::vector<float> & box,
            std::vector<float> & center,
            std::vector<float> & scale,
            std::vector<float> image_size);