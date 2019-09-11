function save_wDat(filename, datatype, ...
    imdirection, bkgate, fshift, blowcap)
% save_wDat: load all metadata variables and pass relevant fields to wDat 
%   and save wDat(for compatibility with postprocessing steps like ROIseg)
%
% Usage:
%   save_wDat(ffilename, datatype, ...
%       imdirection, bkgate, fshift, blowcap)
%
% Args:
%   filename: file name
%   datatype: data type (2DxT, or 3DxT)
%   imdirection: Z axis direction
%   bkgate: gate to do custom background substraction
%   fshift: value to shift distribution
%   blowcap: minimun pixel value (it replaces values less than this)
%
% Notes:
% It assumes that iDat.Greenchannel is never empty

mcDat = [];
cDat = [];
wDat = [];

% load all metadata variables
load(filename, 'iDat', 'fDat', 'mcDat', 'lStim');

if contains(fDat.DataType, 'opto') && ~contains(fDat.DataType, 'prv')
    load(filename, 'cDat');
end

% stitch related
wDat.Zstitch.Zshift = [];
wDat.Zstitch.Zend = [];
wDat.Zstitch.Zidx = []; 
wDat.Zstitch.Xshift = [];
wDat.Zstitch.Yshift = [];

% motion correction
wDat.MotCor.Zshift = [];
wDat.MotCor.sXshift = [];
wDat.MotCor.sYshift = [];

% flip z-axis (3D data only)
if contains(datatype, '3DxT')
    if contains(imdirection, 'invert')
        iDat.RedChaMean = flip(iDat.RedChaMean, 3);
        iDat.GreenChaMean = flip(iDat.GreenChaMean, 3);
    end
end

% generate mean-channels
wDat.RedChaMean = iDat.RedChaMean;
wDat.GreenChaMean = iDat.GreenChaMean;

% background correction
if bkgate
    wDat.RedChaMean = wDat.RedChaMean - iDat.bs(1); 
    wDat.GreenChaMean = wDat.GreenChaMean - iDat.bs(2); 
end

if isfield(iDat, 'bs')
    wDat.bs = iDat.bs;
else
    wDat.bs = [];
end

wDat.RedChaMean = wDat.RedChaMean + fshift; 
wDat.RedChaMean(wDat.RedChaMean < blowcap) = blowcap;
wDat.GreenChaMean = wDat.GreenChaMean + fshift;
wDat.GreenChaMean(wDat.GreenChaMean < blowcap) = blowcap;

if bkgate
    wDat.prepros.bsSubs = 1;
end

% get stimuli info
wDat = getStimInfo(wDat, iDat, fDat, lStim, cDat, ...
    mcDat, strrep(filename, '_metadata', ''), ...
    1, 1, [], iDat.FrameN);

% tag and remove whole nan-planes (3D data only)
if contains(datatype, '3DxT')
    
    siz = size(wDat.GreenChaMean);
    nan_pix = isnan(wDat.GreenChaMean);
    wDat.plane2keep = sum(reshape(nan_pix, ...
        [prod(siz([1 2])) siz(3)])) ~= prod(siz([1 2]));

    if ~isempty(wDat.RedChaMean)
        wDat.RedChaMean = wDat.RedChaMean(:, :, wDat.plane2keep);
    end
    
    wDat.GreenChaMean = wDat.GreenChaMean(:, :, wDat.plane2keep);
    
end

% tag and remove nan-xy pixels
if ~isempty(wDat.RedChaMean)
    wDat.mask = max(isnan(wDat.RedChaMean), [], 3);
else
    wDat.mask = max(isnan(wDat.GreenChaMean), [], 3);
end

if ~isempty(wDat.RedChaMean)
    wDat.RedChaMean = pruneIm(wDat.RedChaMean, wDat.mask);
end
wDat.GreenChaMean = pruneIm(wDat.GreenChaMean, wDat.mask);

% bmask, use all pixels (2D data only)
if contains(datatype, '2DxT')
    wDat.bMask = ones(size(wDat.GreenChaMean(:, :, 1)));
end

% update size
wDat.fSize = [size(wDat.GreenChaMean, 1), size(wDat.GreenChaMean, 2)];

if contains(datatype, '3DxT')
    wDat.vSize = [wDat.fSize, size(wDat.GreenChaMean, 3)];
    wDat.vOrient = imdirection;
else
    wDat.vSize = [wDat.fSize, 1];
    wDat.vOrient = [];
end

save(filename, 'wDat', '-append');

end
