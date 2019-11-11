function batch_stitch_format_stacks_b(FolderName, FileName, iparams)
% batch_stitch_format_stacks_b: Second part towards compiling a whole fly brain
%   It reads metadata generated by batch_stitch_format_stacks_a and applies
%   shifts to stacks to generate a whole fly stack
%   1) it prunes 3DxT volumes, using the mask generated in
%       batch_stitch_format_stacks_a, basically getting rid of zero pixels after
%       aligning stacks
%   2) compiles sub-stacks to whole brain (or stack), saves variables in a
%       ROIseg-compatible way
%
% Usage:
%   batch_stitch_format_stacks_b(FolderName, FileName, iparams)
%
% Args:
%   FolderName: name of folders to load
%   FileName: name of files to load
%   iparams: parameters to update
%       (cDir: current directory)
%       (fo2reject: folders to reject)
%       (fi2reject: files to reject)
%       (fsuffix: suffix of files to load)
%           (default, '_rawdata')
%       (oDir: temporary folder to copy data to)
%           (default, [])
%       %%%%%%%%%%%% shift fluorescence distribution %%%%%%%%%%%%
%       (bkgate: flag for background substraction)
%           (default, 0)
%       (blowcap: fluorescence below which it is zerored)
%           (default, 0)
%       (fshift: shift distribution of F to the positive side)
%           (default, 6)
%       %%%%%%%%%%%% parpool & server related %%%%%%%%%%%%
%       (serId: server id)
%           (default, 'int')
%       (corenum: number of cores)
%           (default, 4)
%       %%%%%%%%%%%% stitching related %%%%%%%%%%%%
%       (maxshift_xy: maximun shift in x and y)
%           (default, [15 15])
%       (direction: used for iverting order of planes in the z axis, see notes)
%           (default, 'invert')
%       (stack2rem: entire stacks to ignore)
%           (default, [])

cspfb = [];
cspfb.cDir = pwd;
cspfb.fo2reject = {'.', '..', 'preprocessed', 'BData'};
cspfb.fi2reject = {'Zstack'};
cspfb.fisuffix = '_rawdata';
cspfb.oDir = [];
cspfb.bkgate = 0;
cspfb.blowcap = 0;
cspfb.fshift = 6;
cspfb.serId = 'int';
cspfb.corenum = 4;
cspfb.maxshift_xy = [15 15];
cspfb.direction = 'invert';
cspfb.stack2rem = [];

if ~exist('FolderName', 'var'); FolderName = []; end
if ~exist('FileName', 'var'); FileName = []; end
if ~exist('iparams', 'var'); iparams = []; end
cspfb = loparam_updater(cspfb, iparams);

% start pararell pool if not ready yet
ppobj = setup_parpool(cspfb.serId, cspfb.corenum);

if ~isempty(cspfb.oDir)
    
    if ~exist(cspfb.oDir, 'dir')
        mkdir(cspfb.oDir);
    end    

else
    
    cspfb.oDir = '.';
    
end
fprintf(['Saving output files at : ', ...
	strrep(cspfb.oDir, filesep, ' '), '\n'])
    
% Selecting folders
f2run = dir;
f2run = str2match(FolderName, f2run);
f2run = str2rm(cspfb.fo2reject, f2run);
f2run = {f2run.name};
fprintf(['Running n-folders : ', num2str(numel(f2run)), '\n'])

for i = 1:numel(f2run)
    
    fprintf(['Running folder : ', f2run{i}, '\n']); 
    cd(f2run{i});
    runperfolder(FileName, cspfb);
    cd(cspfb.cDir);
    fprintf('\n')
    
end

delete_parpool(ppobj);

fprintf('... Done\n')

end

function runperfolder(fname, cspfb)
% runperfolder: run all files per folder
%
% Usage:
%   runperfolder(fname)
%
% Args:
%   fname: file name pattern
%   cspfb: parameter variable

% Run all files per folder
[f2plot, ~, ~] = rdir_namesplit(...
    fname, '.mat', cspfb.fisuffix, cspfb.fi2reject, [], 1);
f2plot = unique(f2plot);
fprintf(['Compiling stacks from ', ...
    num2str(numel(f2plot)),' flies\n'])

for file_i = 1:numel(f2plot)
    
    % Compiling all stacks per fly
    [filename, ~, repnum] = rdir_namesplit(...
        f2plot{file_i}, '.mat', cspfb.fisuffix, ...
        cspfb.fi2reject, [], 1);
    filename = unique(filename);
    
    % remove stacks (init or end)
    if ~isempty(cspfb.stack2rem)
        repnum = setdiff(repnum, cspfb.stack2rem);
    end
    
    % sort stacks cspfb.direction
    if strcmp(cspfb.direction, 'invert')
        repnum = sort(repnum, 'descend');
    else
        repnum = sort(repnum, 'ascend');
    end
    
    % run per fly
    if numel(filename) == 1
        fcompiler(filename{1}, repnum, cspfb);
    else
        fprintf('error')
    end
    
end

end

function fcompiler(fname, reps, cspfb)
% fcompiler: for each filename compile all sub-stacks in the right order
%
% Usage:
%   fcompiler(fname)
%
% Args:
%   fname: file name
%   reps: all repetitions to use
%   cspfa: parameter variable

% write a memmap variable
% green channel
dataObj = matfile([cspfb.oDir, filesep, fname, '_prosdata.mat'], ...
    'Writable', true);
% red channel
dataObj_ref = matfile([cspfb.oDir, filesep, fname, '_prosref.mat'], ...
    'Writable', true);

% Load previously generated wdat (batch_collectstackperfly_b)
load([fname, '_prosmetadata.mat'], 'wDat', 'shifts_pr');

% add local folder
wDat.cDir = pwd;
if isfield(wDat, 'min_f')
    wDat = rmfield(wDat, 'min_f');
end

% Rerun already used metadata
if isfield(wDat, 'cspf') % it has already being used to compile Data
    
    fprintf('Reseting metadata to be reused\n')
    % reset original order in frame width
    if ~isempty(strfind(wDat.bSide, 'R'))
        wDat.RedChaMean = flip(wDat.RedChaMean, 2);
        wDat.GreenChaMean = flip(wDat.GreenChaMean, 2);
        wDat.mask = flip(wDat.mask, 2);
        wDat.bMask = flip(wDat.bMask, 2);
    end
    
end

% prune reps if stack2rem exists
load([fname, '_prosmetadata.mat'], 'stack2rem');

if exist('stack2rem', 'var')
    
    % remove stacks (init or end)
    reps = setdiff(reps, stack2rem);
    % sort stacks cspfb.direction
    if strcmp(cspfb.direction, 'invert')
        reps = sort(reps, 'descend');
    else
        reps = sort(reps, 'ascend');
    end
    
end

% Compile stacks
z_i = 0; p_i = 0; k_i = 1;

for rep_i = 1:numel(reps)
    
    % Load files
    fprintf('+');
    tinit = tic;
    load([fname, '_', num2str(reps(rep_i)), '_metadata.mat'], 'iDat')
    ldata = matfile([fname, '_', num2str(reps(rep_i)), '_rawdata.mat']);
    
    regchagate = exist([fname, '_', num2str(reps(rep_i)), '_refdata.mat'], 'file');
    if regchagate
        rdata = matfile([fname, '_', num2str(reps(rep_i)), '_refdata.mat']);
    end
    
    % Correct for inverse z order
    if strcmp(wDat.vOrient, 'invert')
        
        Data = flip(ldata.Data, 3);
        clear ldata
        if regchagate
            rData = flip(rdata.Data, 3);
            clear rdata;
        end
        
    else
        
        Data = ldata.Data;
        clear ldata; 
        if regchagate
            rData = rdata.Data;
            clear rdata;
        end
        
    end
    
    % background substract F
    if cspfb.bkgate
        
        Data = Data - iDat.bs(end);
        
        if regchagate
            rData = rData - iDat.bs(1);
        end
        
    end
    
    Data = Data + cspfb.fshift;
    Data(Data < cspfb.blowcap) = cspfb.blowcap;
    
    if regchagate
        rData = rData + cspfb.fshift;
        rData(rData < cspfb.blowcap) = cspfb.blowcap;
    end
    
    % Prune Data
    if rep_i == 1
        
        Data = pruneIm(Data(:, :, ...
            wDat.Zstitch.Zshift(rep_i, 1):wDat.Zstitch.Zend(rep_i, 1), :), ...
            wDat.mask);
        
        if regchagate
            rData = pruneIm(rData(:, :, ...
                wDat.Zstitch.Zshift(rep_i, 1):wDat.Zstitch.Zend(rep_i, 1), :), ...
                wDat.mask);
        end
        
    else
        
        if wDat.XYZres{2}(3) == 1
            init_slice = 1;
        else
            init_slice = 0;
        end
        
        Data = Data(:, :, ...
            (wDat.Zstitch.Zshift(rep_i, 1) + init_slice):wDat.Zstitch.Zend(rep_i, 1), :);
        dgDim = size(Data);
        
        options_align = NoRMCorreSetParms('d1', dgDim(1), 'd2', dgDim(2), 'd3', dgDim(3), ...
            'grid_size', dgDim(1:3), 'bin_width', 50, 'mot_uf', [4, 4, 1], ...
            'us_fac', 10, 'overlap_pre', 16, 'overlap_post', 16, 'use_parallel', true, ...
            'correct_bidir', false, 'max_shift', cspfb.maxshift_xy, 'phase_flag', 1, ...
            'boundary', 'NaN', 'shifts_method', 'linear');
        clear dgDim
        
        % resize shifts_align
        shifts_align_lo = resize_shifts(shifts_pr(rep_i-1), wDat.Tn);
        
        % get rid of nan values, set them to cspfb.blowcap (if not the apply_shifts fails)
        Data(isnan(Data)) = cspfb.blowcap;
        Data = apply_shifts(Data, shifts_align_lo, options_align);
        Data = pruneIm(Data, wDat.mask);
        
        if regchagate
            rData = rData(:, :, ...
                (wDat.Zstitch.Zshift(rep_i, 1) + init_slice):wDat.Zstitch.Zend(rep_i, 1), :);
            rData(isnan(rData)) = cspfb.blowcap; 
            rData = apply_shifts(rData, shifts_align_lo, options_align);
            rData = pruneIm(rData, wDat.mask);
        end
        
    end
    
    % Correct for side of the brain imaged
    if ~isempty(strfind(wDat.bSide, 'R'))
        Data = flip(Data, 2);
        if regchagate
            rData = flip(rData, 2);
        end
    end
    
    % saving Data
    if ~isempty(Data)
        
        % get relative depth
        planes = 1:size(Data, 3);
        planes = planes + z_i;
        z_i = planes(end);
        
        if ~isempty(strfind(wDat.bSide, 'R'))
            
            wDat.GreenTrend(rep_i, :) = stacktrend(Data, ...
                flip(wDat.bMask(:, :, planes), 2));
            if regchagate
                wDat.RedTrend(rep_i, :) = stacktrend(rData, ...
                    flip(wDat.bMask(:, :, planes), 2));
            end
            
        else
            wDat.GreenTrend(rep_i, :) = stacktrend(Data, ...
                wDat.bMask(:, :, planes));
            if regchagate
                wDat.RedTrend(rep_i, :) = stacktrend(rData, ...
                    wDat.bMask(:, :, planes));
            end
        end
        
        % saving data using relative indexes
        dataObj.Y(1:wDat.fSize(1), 1:wDat.fSize(2), planes, 1:wDat.Tn) = Data;
        Zn = size(Data, 3);
        
        % indexes are sequential from plane to plane
        pixelindex = 1:prod([wDat.fSize, Zn]);
        pixelindex = pixelindex + p_i;
        p_i = pixelindex(end);
        dataObj.Yr(pixelindex, 1:wDat.Tn) = ...
            reshape(Data, [prod([wDat.fSize, Zn]), wDat.Tn]);
        
        if regchagate
            dataObj_ref.Yr(pixelindex, 1:wDat.Tn) = ...
                reshape(rData, [prod([wDat.fSize, Zn]), wDat.Tn]);
        end
        
        lmin(k_i) = min(Data(:));
        k_i = k_i + 1;
        
    end
    
    clear iDat Zn Data rData
    fprintf([num2str(toc(tinit)), ' seconds\n'])
    
end

% Correct for side of the brain imaged
if ~isempty(strfind(wDat.bSide, 'R'))
    wDat.RedChaMean = flip(wDat.RedChaMean, 2);
    wDat.GreenChaMean = flip(wDat.GreenChaMean, 2);
    wDat.mask = flip(wDat.mask, 2);
    wDat.bMask = flip(wDat.bMask, 2);
end

% final editing of variables
dataObj.nY = min(lmin);
dataObj.sizY = [wDat.vSize, wDat.Tn];

if regchagate
    dataObj_ref.nY = min(lmin);
    dataObj_ref.sizY = [wDat.vSize, wDat.Tn]; 
end

wDat.lc3D = neighcorr_3D(dataObj);

% compile field
wDat.cspf = 1;

% save metadata in local folder
save([fname, '_prosmetadata.mat'], 'wDat', '-append');

% copying metadata in target folder
if ~strcmpi(pwd, cspfb.oDir)
    save([cspfb.oDir, filesep, fname, '_prosmetadata.mat'], 'wDat');
end

end

function shift_out = resize_shifts(shift_in, tDim)

shift_out(1:tDim) = shift_in;

end

function fmed = stacktrend(Y, mask)
% stacktrend: get median trend per stack for just neural tissue (using mask)
%
% Usage:
%   stacktrend(fname)
%
% Args:
%   Y: 3DxT image
%   mask: 3D mask

dDim = size(Y);
mask = mask(:);
Y = reshape(Y, [prod(dDim(1:3)), dDim(4)]);
Y = Y(mask ~= 0, :);
fmed = median(Y, 1);

end
