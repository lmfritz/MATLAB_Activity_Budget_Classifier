clear; clc;

rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
outCsv  = fullfile(rootDir, 'AUTO_SurfaceIntervalFeatures_All_NEW.csv');
outXlsx = fullfile(rootDir, 'AUTO_SurfaceIntervalFeatures_All_NEW.xlsx');

% -----------------------------
% Find PRH files
% -----------------------------
files1 = dir(fullfile(rootDir, '**', '* 10Hzprh.mat'));
files2 = dir(fullfile(rootDir, '**', '*prh.mat'));
files = [files1; files2];

% remove duplicates
[~, ia] = unique(fullfile({files.folder}, {files.name}));
files = files(ia);

% remove junk / derived files
files = files(~startsWith({files.name}, '._'));
files = files(~contains({files.name}, '_speed'));

fprintf('Found %d PRH files\n', numel(files));

T = table();

for i = 1:numel(files)

    prhPath = fullfile(files(i).folder, files(i).name);
    fprintf('\n[%d/%d] %s\n', i, numel(files), prhPath);

    try
        % -----------------------------
        % Metadata available early
        % -----------------------------
        [folderPath, baseName, ext] = fileparts(prhPath);
        fileName = string([baseName ext]);
        folderStr = string(folderPath);

        S = load(prhPath);

        % -----------------------------
        % Required variables
        % -----------------------------
        if ~isfield(S, 'p') || isempty(S.p)
            fprintf('  Skipping: missing p\n');
            continue
        end
        p = S.p(:);

        if isfield(S, 'fs') && ~isempty(S.fs)
            fs = S.fs;
        elseif isfield(S, 'fs1') && ~isempty(S.fs1)
            fs = S.fs1;
        else
            fprintf('  Skipping: missing fs/fs1\n');
            continue
        end

        % -----------------------------
        % DN loader
        % -----------------------------
        DN = load_dn_anywhere(S, folderPath, baseName, numel(p));
        if isempty(DN)
            fprintf('  DN not found; continuing without absolute timestamps.\n');
        else
            fprintf('  Loaded DN.\n');
        end

        % -----------------------------
        % tagon loader
        % -----------------------------
        if isfield(S, 'tagon') && ~isempty(S.tagon) && numel(S.tagon) == numel(p)
            tagon = logical(S.tagon(:));
        else
            tagon = load_tagon_anywhere(folderPath, baseName, numel(p));
            if isempty(tagon)
                tagon = isfinite(p);
                fprintf('  tagon not found; using all finite p samples.\n');
            else
                fprintf('  Loaded tagon from separate file.\n');
            end
        end

        % -----------------------------
        % Optional variables
        % -----------------------------
        pitch = nan(size(p));
        if isfield(S, 'pitch') && ~isempty(S.pitch) && numel(S.pitch) == numel(p)
            pitch = S.pitch(:);
        end

        speed = load_speed_anywhere(S, folderPath, baseName, numel(p));
        if all(isnan(speed))
            fprintf('  Speed not found.\n');
        else
            fprintf('  Loaded speed.\n');
        end

        movement = nan(size(p));
        if isfield(S, 'Aw') && ~isempty(S.Aw) && size(S.Aw,2) == 3
            movement = sqrt(sum(S.Aw.^2, 2));
        end

        % -----------------------------
        % Define dives
        % -----------------------------
        DIVE_THRESH = 5;   % your current dive threshold
        MIN_DIVE_DUR = 1;  % seconds

        isDive = tagon & isfinite(p) & (p > DIVE_THRESH);

        diveStarts = find(diff([false; isDive]) == 1);
        diveStops  = find(diff([isDive; false]) == -1);

        if isempty(diveStarts) || numel(diveStarts) < 2
            fprintf('  Skipping: fewer than 2 dives\n');
            continue
        end

        diveDur = (diveStops - diveStarts + 1) ./ fs;
        keep = diveDur >= MIN_DIVE_DUR;
        diveStarts = diveStarts(keep);
        diveStops  = diveStops(keep);

        if numel(diveStarts) < 2
            fprintf('  Skipping: fewer than 2 dives after filtering\n');
            continue
        end

        % -----------------------------
        % Lunge indices loader
        % -----------------------------
        LI = load_lunge_indices_anywhere(folderPath, baseName, numel(p));
        if isempty(LI)
            fprintf('  No lunge indices found.\n');
        else
            fprintf('  Loaded %d lunge indices.\n', numel(LI));
        end

        % -----------------------------
        % Run interval feature function
        % -----------------------------
        out = calc_surface_interval_features(diveStarts, diveStops, LI, p, speed, movement, pitch, fs, DN);

        if isempty(out.pairTable) || height(out.pairTable) == 0
            fprintf('  No surface intervals returned.\n');
            continue
        end

        pairTbl = out.pairTable;

        % -----------------------------
        % Metadata
        % -----------------------------
        if isfield(S, 'INFO') && isstruct(S.INFO) && isfield(S.INFO, 'whaleName') && ~isempty(S.INFO.whaleName)
            whaleName = string(S.INFO.whaleName);
        else
            whaleName = "unknown";
        end

        pairTbl.whaleName = repmat(whaleName, height(pairTbl), 1);
        pairTbl.depID     = repmat(string(baseName), height(pairTbl), 1);
        pairTbl.prhPath   = repmat(string(prhPath), height(pairTbl), 1);
        pairTbl.file      = repmat(fileName, height(pairTbl), 1);
        pairTbl.folder    = repmat(folderStr, height(pairTbl), 1);

        % -----------------------------
        % Append safely
        % -----------------------------
        if isempty(T)
            T = pairTbl;
        else
            missingInRow = setdiff(T.Properties.VariableNames, pairTbl.Properties.VariableNames);
            for m = 1:numel(missingInRow)
                pairTbl.(missingInRow{m}) = missing_value_like(T.(missingInRow{m}));
            end

            newInRow = setdiff(pairTbl.Properties.VariableNames, T.Properties.VariableNames);
            for n = 1:numel(newInRow)
                T.(newInRow{n}) = repmat(missing_value_like(pairTbl.(newInRow{n})), height(T), 1);
            end

            pairTbl = pairTbl(:, T.Properties.VariableNames);
            T = [T; pairTbl];
        end

    catch ME
        warning('Error processing %s:\n%s', prhPath, ME.message);
    end
end

% -----------------------------
% Put useful columns first
% -----------------------------
wanted = ["whaleName","depID","Dive1","Dive2","PrevDiveForaging","NextDiveForaging", ...
          "PrevDiveLunges","NextDiveLunges", ...
          "SurfaceInterval_sec","SurfaceInterval_min","mean_speed_surface", ...
          "mean_movement_surface","pitch_sd_surface","max_depth_surface","prhPath"];
wanted = wanted(ismember(wanted, string(T.Properties.VariableNames)));
T = T(:, [wanted, setdiff(string(T.Properties.VariableNames), wanted, 'stable')]);

writetable(T, outXlsx);
fprintf('\nWrote: %s\n', outXlsx);

writetable(T, outCsv);
fprintf('Wrote: %s\n', outCsv);

% Quick sanity checks
if ~isempty(T)
    fprintf('\nSanity checks:\n');
    fprintf('  PrevDiveForaging TRUE count: %d\n', nnz(T.PrevDiveForaging));
    fprintf('  NextDiveForaging TRUE count: %d\n', nnz(T.NextDiveForaging));
    fprintf('  PrevDiveLunges > 0 count:    %d\n', nnz(T.PrevDiveLunges > 0));
    fprintf('  NextDiveLunges > 0 count:    %d\n', nnz(T.NextDiveLunges > 0));
end

% =========================================================================
% HELPERS
% =========================================================================

function DN = load_dn_anywhere(S, folderPath, baseName, nSamples)
    DN = [];

    % 1) In PRH directly
    if isfield(S, 'DN') && ~isempty(S.DN)
        cand = S.DN(:);
        if numel(cand) == nSamples
            DN = cand;
            return
        end
    end

    % 2) Common sidecar files
    candidates = { ...
        fullfile(folderPath, [baseName '_speed.mat']), ...
        fullfile(folderPath, [erase(baseName, 'prh') 'RMS.mat'])};

    % also look broadly
    d1 = dir(fullfile(folderPath, '*speed*.mat'));
    d2 = dir(fullfile(folderPath, '*RMS*.mat'));
    for k = 1:numel(d1)
        candidates{end+1} = fullfile(d1(k).folder, d1(k).name); %#ok<AGROW>
    end
    for k = 1:numel(d2)
        candidates{end+1} = fullfile(d2(k).folder, d2(k).name); %#ok<AGROW>
    end

    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);

    for c = 1:numel(candidates)
        thisFile = candidates{c};
        if ~exist(thisFile, 'file')
            continue
        end
        try
            D = load(thisFile);
        catch
            continue
        end

        if isfield(D, 'DN') && ~isempty(D.DN)
            cand = D.DN(:);
            if numel(cand) == nSamples
                DN = cand;
                fprintf('  Using DN from %s\n', thisFile);
                return
            end
        end
    end
end

function tagon = load_tagon_anywhere(folderPath, baseName, nSamples)
    tagon = [];

    candidates = { ...
        fullfile(folderPath, [baseName '_tagon.mat'])};

    d = dir(fullfile(folderPath, '*tagon*.mat'));
    for k = 1:numel(d)
        candidates{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
    end

    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);

    for c = 1:numel(candidates)
        thisFile = candidates{c};
        if ~exist(thisFile, 'file')
            continue
        end
        try
            T = load(thisFile);
        catch
            continue
        end

        if isfield(T, 'tagon') && ~isempty(T.tagon)
            cand = logical(T.tagon(:));
            if numel(cand) == nSamples
                tagon = cand;
                return
            end
        end
    end
end

function speed = load_speed_anywhere(S, folderPath, baseName, nSamples)
    speed = nan(nSamples, 1);

    % 1) direct in PRH
    if isfield(S, 'speed') && istable(S.speed)
        if any(strcmp('JJ', S.speed.Properties.VariableNames))
            cand = S.speed.JJ;
            if numel(cand) == nSamples
                speed = cand(:);
                return
            end
        elseif any(strcmp('FN', S.speed.Properties.VariableNames))
            cand = S.speed.FN;
            if numel(cand) == nSamples
                speed = cand(:);
                return
            end
        end
    end

    if isfield(S, 'speedJJ') && isnumeric(S.speedJJ) && numel(S.speedJJ) == nSamples
        speed = S.speedJJ(:);
        return
    end

    if isfield(S, 'speed') && isnumeric(S.speed) && numel(S.speed) == nSamples
        speed = S.speed(:);
        return
    end

    % 2) sidecar _speed file
    candidates = { ...
        fullfile(folderPath, [baseName '_speed.mat'])};

    d = dir(fullfile(folderPath, '*speed*.mat'));
    for k = 1:numel(d)
        candidates{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
    end

    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);

    for c = 1:numel(candidates)
        thisFile = candidates{c};
        if ~exist(thisFile, 'file')
            continue
        end
        try
            D = load(thisFile);
        catch
            continue
        end

        if isfield(D, 'speedJJ') && isnumeric(D.speedJJ) && numel(D.speedJJ) == nSamples
            speed = D.speedJJ(:);
            fprintf('  Using speedJJ from %s\n', thisFile);
            return
        end

        if isfield(D, 'speed') && istable(D.speed)
            if any(strcmp('JJ', D.speed.Properties.VariableNames))
                cand = D.speed.JJ;
                if numel(cand) == nSamples
                    speed = cand(:);
                    fprintf('  Using speed.JJ from %s\n', thisFile);
                    return
                end
            elseif any(strcmp('FN', D.speed.Properties.VariableNames))
                cand = D.speed.FN;
                if numel(cand) == nSamples
                    speed = cand(:);
                    fprintf('  Using speed.FN from %s\n', thisFile);
                    return
                end
            end
        end
    end
end

function LI = load_lunge_indices_anywhere(folderPath, baseName, nSamples)
    LI = [];

    candidates = { ...
        fullfile(folderPath, [baseName '_lunges.mat']), ...
        fullfile(folderPath, [baseName '_LungeInfo.mat']), ...
        fullfile(folderPath, [baseName '_lungeinfo.mat']), ...
        fullfile(folderPath, [baseName '_lungerate.mat'])};

    d = dir(fullfile(folderPath, '*lunge*.mat'));
    for k = 1:numel(d)
        candidates{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
    end

    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);

    for c = 1:numel(candidates)
        thisFile = candidates{c};
        if ~exist(thisFile, 'file')
            continue
        end

        try
            L = load(thisFile);
        catch
            continue
        end

        % Explicit known names first
        directNames = { ...
            'LungeI', 'lungeI', ...
            'LI', 'li', ...
            'lunges', 'Lunges', ...
            'lungeIdx', 'lunge_idx', 'lungeInd', 'lunge_ind', ...
            'I_lunge', 'Ilunge'};

        for j = 1:numel(directNames)
            nm = directNames{j};
            if isfield(L, nm)
                LI = sanitize_lunge_vector(L.(nm), nSamples);
                if ~isempty(LI)
                    fprintf('  Using lunge file %s field %s\n', thisFile, nm);
                    return
                end
            end
        end

        % One level down in structs
        fns = fieldnames(L);
        for j = 1:numel(fns)
            v = L.(fns{j});
            if isstruct(v)
                subf = fieldnames(v);
                for s = 1:numel(subf)
                    LI = sanitize_lunge_vector(v.(subf{s}), nSamples);
                    if ~isempty(LI)
                        fprintf('  Using lunge file %s struct %s.%s\n', thisFile, fns{j}, subf{s});
                        return
                    end
                end
            end
        end
    end
end

function v = sanitize_lunge_vector(x, nSamples)
    v = [];

    if isempty(x)
        return
    end

    if istable(x)
        if width(x) == 1
            x = x{:,1};
        else
            return
        end
    end

    if ~isnumeric(x) && ~islogical(x)
        return
    end

    x = x(:);
    x = x(isfinite(x));
    if isempty(x)
        return
    end

    if islogical(x)
        if numel(x) == nSamples
            v = find(x);
        end
        return
    end

    x = round(x);
    x = x(x >= 1 & x <= nSamples);

    if isempty(x)
        return
    end

    if numel(x) > 0.8 * nSamples
        return
    end

    v = unique(x);
end

function x = missing_value_like(col)
    if isstring(col)
        x = string(missing);
    elseif iscell(col)
        x = {[]};
    elseif isnumeric(col)
        x = NaN;
    elseif islogical(col)
        x = false;
    else
        x = string(missing);
    end
end