function out = imageWarp(srcImage,tform,options)
% Brief: Apply geometric transformation to image
% Details:
%    弥补matlab内建函数imwarp的不足，主要是增加支持输出图像边界外像素镜像，重复填充元素
%
% Syntax:
%     out = imageWarp(srcImage,tform)
%     out = imageWarp(srcImage,tform,Name=Value)
%
% Inputs:
%    srcImage - Image to be transformed
%    tform - Geometric transformation geometric transformation object, specify
% one of "rigidtform2d","fitgeotform2d","affinetform2d", "simtform2d",
% "transltform2d", "projtform2d" build-in types.
%
% Outputs:
%    out - Transformed image
%
% Example:
%    srcImage = imread("peppers.png");
%    tform = rigidtform2d();
%    out = imageWarp(srcImage,tform,OutputView=imref2d([1000,2000]),BorderMode="BORDER_REFLECT");
%    imshow(out)
%
% See also:
%   imwarp

% Author:                          cuixingxing
% Email:                           cuixingxing150@gmail.com
% Created:                         14-Jan-2025 09:37:11
% Version history revision notes:
%                                  None
% Implementation In Matlab R2024b
% Copyright © 2025 TheMatrix.All Rights Reserved.
%
arguments
    srcImage {mustBeNonempty}
    tform (1,1) {mustBeA(tform,["rigidtform2d","fitgeotform2d",...
        "affinetform2d", "simtform2d", "transltform2d", "projtform2d"])}=rigidtform2d()

    options.RA (1,1) imref2d = imref2d(size(srcImage,[1,2])) % 等同imwarp内建函数的位置参数RA
    options.OutputView (1,1) imref2d = imref2d(size(srcImage,[1,2])) % 等同imwarp内建函数的可选参数OutputView
    options.BorderMode (1,1) {mustBeMember(options.BorderMode,...
        [ "BORDER_CONSTANT",... % !< `000000|abcdefgh|00000`  with specified `0`
        "BORDER_REPLICATE",... % !< `aaaaaa|abcdefgh|hhhhhhh`
        "BORDER_REFLECT",... % !< `fedcba|abcdefgh|hgfedcb`
        ])} = "BORDER_CONSTANT"
end

% Get the size of the input image
[rows, cols,~] = size(srcImage);

% Generate a meshgrid of output coordinates
xLimits = options.OutputView.XWorldLimits;
yLimits = options.OutputView.YWorldLimits;
x = linspace(xLimits(1),xLimits(2),options.OutputView.ImageSize(2));
y = linspace(yLimits(1),yLimits(2),options.OutputView.ImageSize(1));
[outputX, outputY] = meshgrid(x,y);

% Convert output coordinates to input image coordinates using the inverse transformation
inputCoords = transformPointsInverse(tform, [outputX(:), outputY(:)]);
[xIntrinsic, yIntrinsic] = worldToIntrinsic(options.RA,inputCoords(:,1),inputCoords(:,2));

inputX = reshape(xIntrinsic,size(outputX));
inputY = reshape(yIntrinsic,size(outputY));

switch options.BorderMode
    case "BORDER_REPLICATE"
        % Replicate the nearest edge pixel
        inputX = max(1, min(cols, inputX));
        inputY = max(1, min(rows, inputY));
    case "BORDER_REFLECT"
        % Reflect the coordinates over the boundary
        inputX = mod(inputX,2*cols);
        inputY = mod(inputY,2*rows);

        inputX(inputX>cols) = 2*cols-inputX(inputX>cols);
        inputY(inputY>rows) = 2*rows-inputY(inputY>rows);

end

if options.BorderMode~="BORDER_CONSTANT"
    inputX = min(max(1,inputX),2*cols);
    inputY = min(max(1,inputY),2*rows);
end

out = images.internal.interp2d(srcImage,inputX,inputY,"linear",0,false);
end