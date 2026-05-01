

%% build_kmeans_dive_features_rewrite.m
% Build a dive-level feature table from PRH files for k-means clustering
%
% Output: one row per dive across all PRH files%
%
% Features included:
%   - maxDepth_m
%   - meanDepth_m
%   - diveDur_s
%   - meanMov
%   - sdMov
%   - pitchSD_deg
%   - rollSD_deg
%   - headSD_deg
%   - meanSpeedJJ
%   - meanSpeedFN
%   - lungeCount
%   - hasLunge
%
% Lauren Fritz
% April 2026

clear; clc;

%% =========================
% USER SETTINGS
% =========================
rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
searchSubfolders = true;

DIVE_THRESH_M     = 5;    % dive if depth > this
MIN_DIVE_DUR_S    = 0;   % minimum dive duration in seconds
LUNGE_MIN_DEPTH_M = 0;    % ignore lunges shallower than this
MOV_SMOOTH_S      = 0.5;  % smoothing window for speed-derived movement proxy

saveOutput = true;
outFile = fullfile(rootDir, 'kmeans_dive_features.csv');

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
% PREALLOCATE RESULT CONTAINER
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

    if isfield(S,'p') && ~isempty(S.p)
        p = S.p(:);
    else
        warning('Skipping %s (missing p)', prhFiles(fi).name);
        continue
    end

    if isfield(S,'fs') && ~isempty(S.fs)
        fs = S.fs;
    else
        warning('Skipping %s (missing fs)', prhFiles(fi).name);
        continue
    end

    %% ---- DN: try PRH first, then search RMS-like files ----
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

    %% ---- tagon: try PRH first, then search TAGON-like files ----
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
    roll  = nan(size(p));
    head  = nan(size(p));
    Aw    = [];

    if isfield(S,'pitch') && ~isempty(S.pitch), pitch = S.pitch(:); end
    if isfield(S,'roll')  && ~isempty(S.roll),  roll  = S.roll(:);  end
    if isfield(S,'head')  && ~isempty(S.head),  head  = S.head(:);  end
    if isfield(S,'Aw')    && ~isempty(S.Aw),    Aw    = S.Aw;       end

    %% ---- Speed handling ----
    speedJJ = nan(size(p));
    speedFN = nan(size(p));

    if isfield(S,'speed') && ~isempty(S.speed)
        if istable(S.speed)
            vars = S.speed.Properties.VariableNames;

            if ismember('JJ', vars) && ~isempty(S.speed.JJ)
                raw = S.speed.JJ(:);
                if any(isfinite(raw))
                    tmp = raw;
                    tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                    tmp = runmean(tmp, max(1, round(MOV_SMOOTH_S * fs)));
                    tmp(isnan(raw)) = nan;
                    n = min(numel(tmp), numel(speedJJ));
                    speedJJ(1:n) = tmp(1:n);
                end
            end

            if ismember('FN', vars) && ~isempty(S.speed.FN)
                raw = S.speed.FN(:);
                if any(isfinite(raw))
                    tmp = raw;
                    tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                    tmp = runmean(tmp, max(1, round(MOV_SMOOTH_S * fs)));
                    tmp(isnan(raw)) = nan;
                    n = min(numel(tmp), numel(speedFN));
                    speedFN(1:n) = tmp(1:n);
                end
            end

        elseif isstruct(S.speed)
            if isfield(S.speed,'JJ') && ~isempty(S.speed.JJ)
                raw = S.speed.JJ(:);
                if any(isfinite(raw))
                    tmp = raw;
                    tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                    tmp = runmean(tmp, max(1, round(MOV_SMOOTH_S * fs)));
                    tmp(isnan(raw)) = nan;
                    n = min(numel(tmp), numel(speedJJ));
                    speedJJ(1:n) = tmp(1:n);
                end
            end

            if isfield(S.speed,'FN') && ~isempty(S.speed.FN)
                raw = S.speed.FN(:);
                if any(isfinite(raw))
                    tmp = raw;
                    tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                    tmp = runmean(tmp, max(1, round(MOV_SMOOTH_S * fs)));
                    tmp(isnan(raw)) = nan;
                    n = min(numel(tmp), numel(speedFN));
                    speedFN(1:n) = tmp(1:n);
                end
            end
        end
    end
fprintf('  finite speedJJ: %d | finite speedFN: %d\n', ...
        sum(isfinite(speedJJ)), sum(isfinite(speedFN)));

    %% ---- Align lengths ----
    N = min([numel(p), numel(DN), numel(tagon), numel(pitch), numel(roll), ...
             numel(head), numel(speedJJ), numel(speedFN)]);
    p       = p(1:N);
    DN      = DN(1:N);
    tagon   = tagon(1:N);
    pitch   = pitch(1:N);
    roll    = roll(1:N);
    head    = head(1:N);
    speedJJ = speedJJ(1:N);
    speedFN = speedFN(1:N);

    %% ---- Build movement proxy ----
    mov = speedJJ;
    if all(~isfinite(mov))
        if ~isempty(Aw)
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

    %% ---- Deployment / whale metadata ----
    depID = regexp(baseName,'^[^ ]+','match','once');
    whaleName = depID;
    if isfield(S,'INFO') && isstruct(S.INFO) && isfield(S.INFO,'whaleName') && ~isempty(S.INFO.whaleName)
        whaleName = S.INFO.whaleName;
    end

    %% ---- Load matching lunge file, if present ----
    LI = [];
    try
        cand = dir(fullfile(prhFiles(fi).folder, ['*' depID '*lunges.mat']));
        cand = cand(~startsWith({cand.name}, '._'));

        bestFile = '';
        bestScore = -Inf;
        DNmin = min(DN);
        DNmax = max(DN);

        for ii = 1:numel(cand)
            f = fullfile(cand(ii).folder, cand(ii).name);
            tmp = load(f);

            t = [];
            if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN(:); end
            if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time(:); end
            if isempty(t) && isfield(tmp,'LungeI') && ~isempty(tmp.LungeI)
                idx = tmp.LungeI(:);
                idx = idx(idx>=1 & idx<=N);
                t = DN(idx);
            end
            if isempty(t) && isfield(tmp,'LI') && ~isempty(tmp.LI)
                idx = tmp.LI(:);
                idx = idx(idx>=1 & idx<=N);
                t = DN(idx);
            end

            if isempty(t)
                continue
            end

            in = (t >= DNmin) & (t <= DNmax);
            nIn = sum(in);
            nTot = numel(t);
            frac = nIn / max(nTot,1);
            score = frac + 0.01*log1p(nIn);

            if score > bestScore
                bestScore = score;
                bestFile = f;
            end
        end

        if ~isempty(bestFile)
            tmp = load(bestFile);
            LungeI = [];
            LungeDN = [];

            if isfield(tmp,'LungeI') && ~isempty(tmp.LungeI), LungeI = tmp.LungeI(:); end
            if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), LungeDN = tmp.LungeDN(:); end
            if isempty(LungeI) && isfield(tmp,'LI') && ~isempty(tmp.LI), LungeI = tmp.LI(:); end
            if isempty(LungeDN) && isfield(tmp,'time') && ~isempty(tmp.time), LungeDN = tmp.time(:); end

            if ~isempty(LungeDN)
                LI = nan(size(LungeDN));
                for j = 1:numel(LungeDN)
                    [~, LI(j)] = min(abs(DN - LungeDN(j)));
                end
            elseif ~isempty(LungeI)
                LI = LungeI;
            else
                LI = [];
            end

            LI = LI(:);
            LI = LI(LI >= 1 & LI <= N);
            LI = LI(p(LI) >= LUNGE_MIN_DEPTH_M);
        end
    catch ME
        warning('Problem loading lunge file for %s: %s', depID, ME.message);
        LI = [];
    end
%% ---- Detect dives ----
    inDiveRaw = (p > DIVE_THRESH_M) & tagon;
    d = diff([false; inDiveRaw; false]);
    diveStarts = find(d == 1);
    diveStops  = find(d == -1) - 1;

    if isempty(diveStarts)
        fprintf('  No dives found.\n');
        continue
    end

    dur_s = (diveStops - diveStarts + 1) / fs;
    keepDive = dur_s >= MIN_DIVE_DUR_S;
    diveStarts = diveStarts(keepDive);
    diveStops  = diveStops(keepDive);

    nDives = numel(diveStarts);
    fprintf('  Kept %d dives.\n', nDives);
    if nDives == 0
        continue
    end

    %% ---- Build one row per dive ----
    for di = 1:nDives
        a = diveStarts(di);
        b = diveStops(di);

        diveDur_s   = (b - a + 1) / fs;
        maxDepth_m  = max(p(a:b), [], 'omitnan');
        meanDepth_m = mean(p(a:b), 'omitnan');

        meanMov = mean(mov(a:b), 'omitnan');
        sdMov   = std(mov(a:b), 'omitnan');

        pitchMean_deg = mean(pitch(a:b) * 180/pi, 'omitnan');
        pitchSD_deg   = std(pitch(a:b) * 180/pi, 'omitnan');

        rollMean_deg = mean(roll(a:b) * 180/pi, 'omitnan');
        rollSD_deg   = std(roll(a:b) * 180/pi, 'omitnan');

        headMean_deg = mean(head(a:b) * 180/pi, 'omitnan');
        headSD_deg   = std(head(a:b) * 180/pi, 'omitnan');

        meanSpeedJJ = mean(speedJJ(a:b), 'omitnan');
        meanSpeedFN = mean(speedFN(a:b), 'omitnan');

        if ~isempty(LI)
            lungeCount = sum(LI >= a & LI <= b);
        else
            lungeCount = 0;
        end
        hasLunge = lungeCount > 0;

        rows(end+1, :) = { ...
            depID, ...
            whaleName, ...
            prhFiles(fi).name, ...
            di, ...
            DN(a), ...
            DN(b), ...
            diveDur_s, ...
            maxDepth_m, ...
            meanDepth_m, ...
            meanMov, ...
            sdMov, ...
            pitchMean_deg, ...
            pitchSD_deg, ...
            rollMean_deg, ...
            rollSD_deg, ...
            headMean_deg, ...
            headSD_deg, ...
            meanSpeedJJ, ...
            meanSpeedFN, ...
            lungeCount, ...
            hasLunge ...
            };
    end
end

%% =========================
% BUILD TABLE
% =========================
if isempty(rows)
    error('No dive rows were created.');
end

diveFeatures = cell2table(rows, 'VariableNames', { ...
    'depID', ...
    'whaleName', ...
    'prhFile', ...
    'diveNum', ...
    'startDN', ...
    'stopDN', ...
    'diveDur_s', ...
    'maxDepth_m', ...
    'meanDepth_m', ...
    'meanMov', ...
    'sdMov', ...
    'pitchMean_deg', ...
    'pitchSD_deg', ...
    'rollMean_deg', ...
    'rollSD_deg', ...
    'headMean_deg', ...
    'headSD_deg', ...
    'meanSpeedJJ', ...
    'meanSpeedFN', ...
    'lungeCount', ...
    'hasLunge'});

fprintf('\nBuilt diveFeatures table with %d dives.\n', height(diveFeatures));

%% =========================
% OPTIONAL CLEANUP
% =========================
numericVars = {'diveDur_s','maxDepth_m','meanDepth_m','meanMov','sdMov', ...
               'pitchMean_deg','pitchSD_deg','rollMean_deg','rollSD_deg', ...
               'headMean_deg','headSD_deg','meanSpeedJJ','meanSpeedFN','lungeCount'};

X = diveFeatures{:, numericVars};
badRow = all(~isfinite(X), 2);

if any(badRow)
    fprintf('Removing %d rows with all numeric features missing.\n', sum(badRow));
    diveFeatures(badRow, :) = [];
end

%% =========================
% SAVE
% =========================
if saveOutput
    writetable(diveFeatures, outFile);
    fprintf('Saved: %s\n', outFile);
end

%% =========================
% QUICK LOOK
% =========================
disp(diveFeatures(1:min(8,height(diveFeatures)), :))