function outImage = imageInterp(inImage,mapX,mapY,options)
arguments
    inImage 
    mapX 
    mapY 
    options.FillValues (1,1) double {mustBeInRange(options.FillValues,0,255)}=0
    options.BorderMode (1,1) string {mustBeMember(options.BorderMode,["BORDER_CONSTANT","BORDER_REPLICATE","BORDER_REFLECT"])} = "BORDER_CONSTANT"
end
[h,w,~] = size(inImage);

switch options.BorderMode
    case "BORDER_CONSTANT"
        % 使用固定值填充边界
        outImage = images.internal.interp2d(inImage,mapX,mapY,"linear",options.FillValues,false);
        
    case "BORDER_REPLICATE"
        % 限制坐标到图像范围内，实现边界复制
        mapX_clamped = max(1, min(w, mapX));
        mapY_clamped = max(1, min(h, mapY));
        % out = interp2(1:w, 1:h, inImage, mapX_clamped, mapY_clamped, 'linear');
        outImage = images.internal.interp2d(inImage,mapX_clamped,mapY_clamped,"linear",options.FillValues,false);
        
    case "BORDER_REFLECT"
        % 反射坐标处理
        mapX_reflect = reflectCoordinates(mapX, w);
        mapY_reflect = reflectCoordinates(mapY, h);
        % out = interp2(1:w, 1:h, inImage, mapX_reflect, mapY_reflect, 'linear');
        outImage = images.internal.interp2d(inImage,mapX_reflect,mapY_reflect,"linear",options.FillValues,false);
    otherwise
        error('Invalid border mode: %s', borderMode);
end
end


% 辅助函数：反射坐标处理
function coord = reflectCoordinates(coord, maxVal)
% 将坐标反射到1到maxVal的范围内
coord = 2*maxVal - coord;
coord = mod(coord - 1, 2*(maxVal - 1)) + 1;
coord = maxVal - abs(maxVal - coord);
coord = max(1, min(maxVal, coord));
end