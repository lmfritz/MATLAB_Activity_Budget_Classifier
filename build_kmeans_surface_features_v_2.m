%% build_surface_kmeans_features_rewrite.m
% Build a surface-bout feature table for k-means clustering
%
% Output: one row per surface bout
%
% Main goal:
%   evaluate whether surface behavior separates into biologically
%   interpretable groups such as low-activity, directed surface movement,
%   and variable active surface behavior
%
% Lauren Fritz
% April 2026

clear; clc;

%% =========================
% USER SETTINGS
% =========================
rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
searchSubfolders = true;

SURFACE_THRESH_M  = 10;   % surface if p <= this
DIVE_THRESH_M     = 5;    % dive if p > this
MIN_DIVE_DUR_S    = 30;   % only count dives >= this duration
MIN_SURF_BOUT_S   = 30;   % only keep surface bouts >= this duration
MOV_SMOOTH_S      = 0.5;  % smoothing window for speed-derived movement proxy

saveOutput = true;
outFile = fullfile(rootDir, 'surface_kmeans_features.csv');

%% =========================
% FIND PRH FILES
% =========================
if searchSubfolders
    prhFiles = dir(fullfile(rootDir, '**', '*prh.mat'));
else
    prhFiles = dir(fullfile(rootDir, '*prh.mat'));
end

prhFiles = prhFiles(~startsWith({prhFiles.name}, '._'));

fprintf('Found %d candidate PRH files.\n', numel(prhFiles));
if isempty(prhFiles)
    error('No PRH files found.');
end

%% =========================
% PREALLOCATE
% =========================
rows = {};

%% =========================
% LOOP THROUGH FILES
% =========================
for fi = 1:numel(prhFiles)
    prhPath = fullfile(prhFiles(fi).folder, prhFiles(fi).name);
    fprintf('\n[%d/%d] Loading %s\n', fi, numel(prhFiles), prhFiles(fi).name);

    try
        S = load(prhPath);
    catch ME
        warning('Could not load file: %s\n%s', prhPath, ME.message);
        continue
    end

    %% ---- Core variables, allowing companion files ----
    [~, baseName, ~] = fileparts(prhFiles(fi).name);
    depStem = regexprep(baseName, 'prh(_speed)?$', '', 'ignorecase');
    depStemCompact = regexprep(depStem, '^mn\d{2}_', 'mn', 'ignorecase');

    if ~isfield(S,'p') || isempty(S.p)
        warning('Skipping %s (missing p)', prhFiles(fi).name);
        continue
    end
    if ~isfield(S,'fs') || isempty(S.fs)
        warning('Skipping %s (missing fs)', prhFiles(fi).name);
        continue
    end
    p  = S.p(:);
    fs = S.fs;

    %% ---- DN: try PRH first, then companions ----
    DN = [];
    if isfield(S,'DN') && ~isempty(S.DN)
        DN = S.DN(:);
    else
        cand = dir(fullfile(prhFiles(fi).folder, '*.mat'));
        names = {cand.name};
        keep = contains(lower(names), lower(depStem)) | ...
               contains(lower(names), lower(depStemCompact));
        cand = cand(keep);

        for ii = 1:numel(cand)
            nm = cand(ii).name;
            if contains(lower(nm), 'rms')
                f = fullfile(cand(ii).folder, nm);
                fprintf('  Trying DN from %s\n', nm);
                R = load(f);

                if isfield(R,'DN') && ~isempty(R.DN)
                    DN = R.DN(:);
                    break
                elseif isfield(R,'dn') && ~isempty(R.dn)
                    DN = R.dn(:);
                    break
                end
            end
        end
    end

    %% ---- tagon: try PRH first, then companions ----
    tagon = [];
    if isfield(S,'tagon') && ~isempty(S.tagon)
        tagon = S.tagon(:);
    else
        cand = dir(fullfile(prhFiles(fi).folder, '*.mat'));
        names = {cand.name};
        keep = contains(lower(names), lower(depStem)) | ...
               contains(lower(names), lower(depStemCompact));
        cand = cand(keep);

        for ii = 1:numel(cand)
            nm = cand(ii).name;
            if contains(lower(nm), 'tagon')
                f = fullfile(cand(ii).folder, nm);
                fprintf('  Trying tagon from %s\n', nm);
                Ttag = load(f);

                if isfield(Ttag,'tagon') && ~isempty(Ttag.tagon)
                    tagon = Ttag.tagon(:);
                    break
                elseif isfield(Ttag,'TAGON') && ~isempty(Ttag.TAGON)
                    tagon = Ttag.TAGON(:);
                    break
                end
            end
        end
    end

    if isempty(DN) || isempty(tagon)
        missingNeeded = {};
        if isempty(DN), missingNeeded{end+1} = 'DN'; end
        if isempty(tagon), missingNeeded{end+1} = 'tagon'; end
        warning('Skipping %s (missing: %s)', prhFiles(fi).name, strjoin(missingNeeded, ', '));
        continue
    end

    %% ---- Optional vars ----
    pitch = nan(size(p));
    if isfield(S,'pitch') && ~isempty(S.pitch)
        pitch = S.pitch(:);
    end

    %% ---- Speed handling ----
    speedJJ = nan(size(p));
    speedFN = nan(size(p));

    if isfield(S,'speed') && ~isempty(S.speed)
        if istable(S.speed)
            vars = S.speed.Properties.VariableNames;
            if ismember('JJ', vars) && ~isempty(S.speed.JJ)
                speedJJ = S.speed.JJ(:);
            end
            if ismember('FN', vars) && ~isempty(S.speed.FN)
                speedFN = S.speed.FN(:);
            end
        elseif isstruct(S.speed)
            if isfield(S.speed,'JJ') && ~isempty(S.speed.JJ)
                speedJJ = S.speed.JJ(:);
            end
            if isfield(S.speed,'FN') && ~isempty(S.speed.FN)
                speedFN = S.speed.FN(:);
            end
        end
    end
%% ---- Align lengths ----
    N = min([numel(p), numel(DN), numel(tagon), numel(pitch), numel(speedJJ), numel(speedFN)]);
    p       = p(1:N);
    DN      = DN(1:N);
    tagon   = tagon(1:N);
    pitch   = pitch(1:N);
    speedJJ = speedJJ(1:N);
    speedFN = speedFN(1:N);

    %% ---- Build movement proxy ----
    mov = speedJJ;
    if any(isfinite(speedJJ))
        tmp = speedJJ;
        tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
        tmp = runmean(tmp, max(1, round(MOV_SMOOTH_S * fs)));
        tmp(isnan(speedJJ)) = nan;
        mov = tmp(:);
    else
        if isfield(S,'Aw') && ~isempty(S.Aw)
            Aw = S.Aw;
            try
                if exist('njerk','file') == 2
                    J = njerk(Aw, fs);
                    J = J(:);
                else
                    dAw = [zeros(1,size(Aw,2)); diff(Aw)];
                    J = sqrt(sum(dAw.^2,2)) * fs;
                end

                if numel(J) < N
                    J(end+1:N) = J(end);
                elseif numel(J) > N
                    J = J(1:N);
                end

                mov = J(:);
            catch
                mov = nan(N,1);
            end
        else
            mov = nan(N,1);
        end
    end

    %% ---- Deployment metadata ----
    depID = regexp(baseName,'^[^ ]+','match','once');
    whaleName = depID;
    if isfield(S,'INFO') && isstruct(S.INFO) && isfield(S.INFO,'whaleName') && ~isempty(S.INFO.whaleName)
        whaleName = S.INFO.whaleName;
    end

    %% ---- Define dives from depth and duration ----
    inDiveRaw = (p > DIVE_THRESH_M) & tagon;
    d = diff([false; inDiveRaw; false]);
    diveStarts = find(d == 1);
    diveStops  = find(d == -1) - 1;

    dur_s = (diveStops - diveStarts + 1) / fs;
    keepDive = dur_s >= MIN_DIVE_DUR_S;
    diveStarts = diveStarts(keepDive);
    diveStops  = diveStops(keepDive);

    inDive = false(N,1);
    for di = 1:numel(diveStarts)
        inDive(diveStarts(di):diveStops(di)) = true;
    end
%% ---- Define surface bouts ----
    surfaceMask = tagon & ~inDive & (p <= SURFACE_THRESH_M);
    d2 = diff([false; surfaceMask; false]);
    surfStarts = find(d2 == 1);
    surfStops  = find(d2 == -1) - 1;

    if isempty(surfStarts)
        fprintf('  No surface bouts found.\n');
        continue
    end

    surfDur_s = (surfStops - surfStarts + 1) / fs;
    keepSurf = surfDur_s >= MIN_SURF_BOUT_S;
    surfStarts = surfStarts(keepSurf);
    surfStops  = surfStops(keepSurf);

    nSurf = numel(surfStarts);
    fprintf('  Kept %d surface bouts.\n', nSurf);
    if nSurf == 0
        continue
    end

    %% ---- Build one row per surface bout ----
    for si = 1:nSurf
        a = surfStarts(si);
        b = surfStops(si);

        boutDur_s = (b - a + 1) / fs;

        meanDepth_m = mean(p(a:b), 'omitnan');
        maxDepth_m  = max(p(a:b), [], 'omitnan');
        sdDepth_m   = std(p(a:b), 'omitnan');

        meanMov = mean(mov(a:b), 'omitnan');
        sdMov   = std(mov(a:b), 'omitnan');

        meanSpeedJJ = mean(speedJJ(a:b), 'omitnan');
        sdSpeedJJ   = std(speedJJ(a:b), 'omitnan');

        meanSpeedFN = mean(speedFN(a:b), 'omitnan');
        sdSpeedFN   = std(speedFN(a:b), 'omitnan');

        pitchMean_deg = mean(pitch(a:b) * 180/pi, 'omitnan');
        pitchSD_deg   = std(pitch(a:b) * 180/pi, 'omitnan');

        prevDive = find(diveStops < a, 1, 'last');
        if isempty(prevDive)
            prevDiveDur_s   = nan;
            prevDiveDepth_m = nan;
        else
            prevDiveDur_s = (diveStops(prevDive) - diveStarts(prevDive) + 1) / fs;
            prevDiveDepth_m = max(p(diveStarts(prevDive):diveStops(prevDive)), [], 'omitnan');
        end

        rows(end+1, :) = { ...
            depID, ...
            whaleName, ...
            prhFiles(fi).name, ...
            si, ...
            DN(a), ...
            DN(b), ...
            boutDur_s, ...
            meanDepth_m, ...
            maxDepth_m, ...
            sdDepth_m, ...
            meanMov, ...
            sdMov, ...
            meanSpeedJJ, ...
            sdSpeedJJ, ...
            meanSpeedFN, ...
            sdSpeedFN, ...
            pitchMean_deg, ...
            pitchSD_deg, ...
            prevDiveDur_s, ...
            prevDiveDepth_m ...
            };
    end
end

%% =========================
% BUILD TABLE
% =========================
if isempty(rows)
    error('No surface rows were created.');
end

surfaceFeatures = cell2table(rows, 'VariableNames', { ...
    'depID', ...
    'whaleName', ...
    'prhFile', ...
    'surfaceBoutNum', ...
    'startDN', ...
    'stopDN', ...
    'boutDur_s', ...
    'meanDepth_m', ...
    'maxDepth_m', ...
    'sdDepth_m', ...
    'meanMov', ...
    'sdMov', ...
    'meanSpeedJJ', ...
    'sdSpeedJJ', ...
    'meanSpeedFN', ...
    'sdSpeedFN', ...
    'pitchMean_deg', ...
    'pitchSD_deg', ...
    'prevDiveDur_s', ...
    'prevDiveDepth_m' ...
    });

fprintf('\nBuilt surfaceFeatures table with %d bouts.\n', height(surfaceFeatures));

%% =========================
% OPTIONAL CLEANUP
% =========================
numericVars = {'boutDur_s','meanDepth_m','maxDepth_m','sdDepth_m', ...
               'meanMov','sdMov','meanSpeedJJ','sdSpeedJJ', ...
               'meanSpeedFN','sdSpeedFN','pitchMean_deg','pitchSD_deg', ...
               'prevDiveDur_s','prevDiveDepth_m'};

X = surfaceFeatures{:, numericVars};
badRow = all(~isfinite(X), 2);

if any(badRow)
    fprintf('Removing %d rows with all numeric features missing.\n', sum(badRow));
    surfaceFeatures(badRow,:) = [];
end

%% =========================
% SAVE
% =========================
if saveOutput
    writetable(surfaceFeatures, outFile);
    fprintf('Saved: %s\n', outFile);
end

%% =========================
% QUICK LOOK
% =========================
disp(surfaceFeatures(1:min(8,height(surfaceFeatures)), :))