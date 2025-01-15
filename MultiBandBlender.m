classdef MultiBandBlender<handle
    % Brief: 多频段融合器，用于全景拼接overlap区域或者拼接缝，消除色差，平滑过渡
    % Details:
    %    实现等同于OpenCV中的MultiBandBlender融合器，prepare,feed,blend三个公有外部函数接口
    % https://github.com/opencv/opencv/blob/e29a70c17fc23c09eb2fc45ac7902ea37ad77802/modules/stitching/src/blenders.cpp#L325
    % 支持多幅图像一并融合
    %
    % Reference:
    % https://www.uio.no/studier/emner/matnat/its/nedlagte-emner/UNIK4690/v17/forelesninger/lecture_2_3_blending.pdf

    % Author:                          cuixingxing
    % Email:                           cuixingxing150@gmail.com
    % Created:                         13-Jan-2025 13:53:43
    % Version history revision notes:
    %                                  None
    % Implementation In Matlab R2024b
    % Copyright © 2025 TheMatrix.All Rights Reserved.
    %

    properties(Access=public)
        num_bands % 金字塔层数，层数越大，接缝越平滑过渡，计算量增大，一般取值2~10之间
        dst_roi % 最终全景大图的ROI，形如[x,y,width,height]，单位：像素
    end

    properties(Access=private,Hidden=true)
        dst_
        dst_mask_
        dst_pyr_laplace_
        dst_band_weights_
    end

    methods
        function obj = MultiBandBlender(num_bands)
            arguments
                num_bands (1,1) {mustBePositive,mustBeInteger}
            end
            obj.num_bands = num_bands;
        end

        function obj = prepare(obj, dst_roi)
            % Brief:设置融合器在最终的全景大图上生成的ROI位置，即全景图像左上角坐标为dst_roi(1:2)，
            % 宽度为dst_roi(3),高度为dst_roi(4)
            % Details:
            %    None
            % Arguments:
            %    obj - [MultiBandBlender] type
            %    dst_roi - [1,4] size,[double] type,destination panorama
            %    position.
            % Outputs:
            %    obj - [MultiBandBlender] type

            % Prepare the destination image and pyramid structures
            obj.dst_roi = dst_roi;
            max_len = max(dst_roi(3), dst_roi(4));
            obj.num_bands = min(ceil(log2(max_len)), obj.num_bands);

            obj.dst_ = zeros(dst_roi(4), dst_roi(3), 3, 'double');
            obj.dst_mask_ = zeros(dst_roi(4), dst_roi(3), 'logical');

            % Initialize pyramid structures
            obj.dst_pyr_laplace_ = cell(1, obj.num_bands + 1);
            obj.dst_pyr_laplace_{1} = obj.dst_;

            obj.dst_band_weights_ = cell(1, obj.num_bands + 1);
            obj.dst_band_weights_{1} = zeros(dst_roi(4), dst_roi(3));

            for i = 2:obj.num_bands + 1
                obj.dst_pyr_laplace_{i} = zeros(ceil(dst_roi(4)/2^(i-1)), ceil(dst_roi(3)/2^(i-1)),3);
                obj.dst_band_weights_{i} = zeros(ceil(dst_roi(4)/2^(i-1)), ceil(dst_roi(3)/2^(i-1)));
            end
        end

        function obj = feed(obj, img, mask, tl)
            % Brief: Feed an image and its mask into the blender
            % Details:
            %    None
            % Arguments:
            %    obj - [MultiBandBlender] type
            %    img - [m,n,3] size,[uint8] type,Image to be blended (in uint8 type 3-channel format)
            %    mask - [m,n,1] size,[logical] type,Mask for the image (logical format)
            %    tl - [1,2] size,[double] type,Top-left corner of the image
            % Outputs:
            %    obj - [MultiBandBlender] type

            arguments
                obj MultiBandBlender
                img (:,:,3) uint8
                mask (:,:,1) logical
                tl (1,2) {mustBeNumeric} = [1,1]
            end

            % Ensure the image and mask have correct types
            assert(isa(img, 'uint8') && size(img, 3) == 3, 'Image must be uint8-bit and have 3 channels.');
            assert(islogical(mask) && size(mask, 3) == 1, 'Mask must be of logical type and have 1 channel.');

            [h,w,~] = size(img);
            [hm,wm] = size(mask);
            assert(h==hm&& w==wm,'Image and Mask must have same size.');
            assert(tl(1)>=obj.dst_roi(1)&& tl(1)+w-1<=obj.dst_roi(1)+obj.dst_roi(3)&&...
                tl(2)>=obj.dst_roi(2)&& tl(2)+h-1<=obj.dst_roi(2)+obj.dst_roi(4),'Image ROI must be inside global dst_roi.');

            img = im2double(img);
            mask = im2double(mask);

            % Create Laplacian pyramid for the image with border
            src_pyr_laplace = createLaplacePyr(obj, img);

            % Normalize the mask and create the Gaussian pyramid for the weight map
            weight_pyr_gauss = createGaussianPyr(obj, mask);

            tl = tl - obj.dst_roi(1:2) + 1;

            % Add weighted layers to the destination pyramids
            for i = 1:obj.num_bands + 1
                curr_tl = max(round(tl./2^(i-1)),1);
                [currHeight,currWidth] = size(weight_pyr_gauss{i});

                rowRange = curr_tl(2):curr_tl(2)+currHeight-1;
                colRange = curr_tl(1):curr_tl(1)+currWidth-1;

                % Update the Laplacian pyramid and weight map with smoother blending
                obj.dst_pyr_laplace_{i}(rowRange, colRange, :) = ...
                    obj.dst_pyr_laplace_{i}(rowRange, colRange, :) + ...
                    src_pyr_laplace{i}(rowRange, colRange, :) .* weight_pyr_gauss{i};

                obj.dst_band_weights_{i}(rowRange, colRange) = ...
                    obj.dst_band_weights_{i}(rowRange, colRange) + weight_pyr_gauss{i};
            end
        end


        function [dst, dst_mask] = blend(obj)
            % Brief: 获取全景图像dst及mask图像dst_mask

            % Normalize dst_pyr_laplace_
            for i = 1:obj.num_bands+1
                obj.dst_pyr_laplace_{i} = obj.dst_pyr_laplace_{i} ./ (obj.dst_band_weights_{i} + eps);
            end
            obj.dst_mask_ = obj.dst_band_weights_{1} > 0;

            % Restore image from Laplacian pyramids
            dst = restoreImageFromLaplacePyr(obj);
            dst = im2uint8(dst);

            % Apply the final mask
            dst_mask = obj.dst_mask_;
        end
    end

    methods(Hidden)
        % Helper functions for creating pyramids
        % 创建高斯金字塔
        function weightPyrGauss = createGaussianPyr(obj, mask)
            weightPyrGauss = cell(1, obj.num_bands + 1);
            weightPyrGauss{1} = mask;

            % 使用impyramid函数生成高斯金字塔
            for i = 2:obj.num_bands + 1
                weightPyrGauss{i} = impyramid(weightPyrGauss{i-1}, 'reduce');
                % Apply smoothing to avoid hard edges
                % weightPyrGauss{i} = imgaussfilt(weightPyrGauss{i}, 1);
            end
        end

        % 创建拉普拉斯金字塔
        function srcPyrLaplace = createLaplacePyr(obj, img)
            srcPyrLaplace = cell(1, obj.num_bands + 1);
            srcPyrLaplace{1} = img;

            % 生成高斯金字塔
            gaussianPyr = cell(1, obj.num_bands + 1);
            gaussianPyr{1} = img;
            for i = 2:obj.num_bands + 1
                gaussianPyr{i} = impyramid(gaussianPyr{i-1}, 'reduce');
            end

            % 计算拉普拉斯金字塔
            for i = 1:obj.num_bands
                pyramidImg = impyramid(gaussianPyr{i+1}, 'expand');
                pyramidImg = imresize(pyramidImg, size(gaussianPyr{i}, [1, 2]));
                srcPyrLaplace{i} = gaussianPyr{i} - pyramidImg;
            end

            % 最后一层只是高斯金字塔的最后一层
            srcPyrLaplace{obj.num_bands + 1} = gaussianPyr{obj.num_bands + 1};
        end

        % 从拉普拉斯金字塔恢复图像
        function dst = restoreImageFromLaplacePyr(obj)
            dst = obj.dst_pyr_laplace_{end};
            for i = obj.num_bands:-1:1
                pyramidImg = impyramid(dst, 'expand');
                pyramidImg = imresize(pyramidImg, size(obj.dst_pyr_laplace_{i}, [1, 2]));
                dst = pyramidImg + obj.dst_pyr_laplace_{i};
            end
            mask = cat(3,obj.dst_mask_,obj.dst_mask_,obj.dst_mask_);
            dst(~mask)=0;
        end
    end
end
