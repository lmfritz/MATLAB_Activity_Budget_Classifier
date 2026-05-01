% Build an event-level table of lunge depths for monthly plots
%
% Main use:
%   summarize lunge depth across deployments in monthly bins
%
% Output:
%   one row per detected lunge across all PRH files
%
% Notes:
% - This is event-based, not dive-based.
% - Lunges are retained whether they occur inside or outside a kept dive.
% - A flag is included to indicate whether each lunge falls within a kept
%   dive under the current methods settings.
%
% Lauren Fritz
% April 2026

clear; clc;

%% =========================
% USER SETTINGS
% =========================
rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
searchSubfolders = true;

% Match current methods
DIVE_THRESH_M     = 5;
MIN_DIVE_DUR_S    = 30;
LUNGE_MIN_DEPTH_M = 0;

saveOutput = true;
outFile = fullfile(rootDir, 'monthly_lunge_depth_table.csv');

%% =========================
% FIND PRH FILES
% =========================
if searchSubfolders
    prhFiles = [
        dir(fullfile(rootDir, '**', '*prh.mat'));
        dir(fullfile(rootDir, '**', '*prh10.mat'));
        dir(fullfile(rootDir, '**', '*10Hzprh.mat'))
    ];
else
    prhFiles = [
        dir(fullfile(rootDir, '*prh.mat'));
        dir(fullfile(rootDir, '*prh10.mat'));
        dir(fullfile(rootDir, '*10Hzprh.mat'))
    ];
end

prhFiles = prhFiles(~startsWith({prhFiles.name}, '._'));

% Remove duplicates if multiple patterns match the same file.
if ~isempty(prhFiles)
    key = strcat({prhFiles.folder}', filesep, {prhFiles.name}');
    [~, ia] = unique(key, 'stable');
    prhFiles = prhFiles(ia);
end

fprintf('Found %d candidate PRH files.\n', numel(prhFiles));
if isempty(prhFiles)
    error('No PRH files found.');
end

rows = {};
foragingDiveRows = {};
auditRows = {};

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

    [~, baseName, ~] = fileparts(prhFiles(fi).name);
    depStem = regexprep(baseName, 'prh(_speed)?$', '', 'ignorecase');
    depStemCompact = regexprep(depStem, '^mn\d{2}_', 'mn', 'ignorecase');
    depID = depStem;
    whaleName = depID;
    selectedLungeFile = "";
    lungeStatus = "not_checked";
    nLungesExtracted = 0;
    skipReason = "";

    if isfield(S,'p') && ~isempty(S.p)
        p = S.p(:);
    else
        warning('Skipping %s (missing p)', prhFiles(fi).name);
        skipReason = "missing_p";
        auditRows(end+1, :) = {depID, whaleName, prhFiles(fi).name, selectedLungeFile, lungeStatus, nLungesExtracted, skipReason}; %#ok<AGROW>
        continue
    end

    if isfield(S,'fs') && ~isempty(S.fs)
        fs = S.fs;
    elseif isfield(S,'fs1') && ~isempty(S.fs1)
        fs = S.fs1;
    else
        warning('Skipping %s (missing fs/fs1)', prhFiles(fi).name);
        skipReason = "missing_fs_fs1";
        auditRows(end+1, :) = {depID, whaleName, prhFiles(fi).name, selectedLungeFile, lungeStatus, nLungesExtracted, skipReason}; %#ok<AGROW>
        continue
    end

    %% ---- DN ----
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

    %% ---- tagon ----
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
        warning('Skipping %s (missing DN or tagon)', prhFiles(fi).name);
        skipReason = "missing_DN_or_tagon";
        auditRows(end+1, :) = {depID, whaleName, prhFiles(fi).name, selectedLungeFile, lungeStatus, nLungesExtracted, skipReason}; %#ok<AGROW>
        continue
    end

    N = min([numel(p), numel(DN), numel(tagon)]);
    p = p(1:N);
    DN = DN(1:N);
    tagon = tagon(1:N);

    if isfield(S,'INFO') && isstruct(S.INFO) && isfield(S.INFO,'whaleName') && ~isempty(S.INFO.whaleName)
        whaleName = S.INFO.whaleName;
    end

    %% ---- Load matching lunge file ----
    LI = [];
    try
        cand = dir(fullfile(prhFiles(fi).folder, '**', '*lunges.mat'));
        cand = cand(~startsWith({cand.name}, '._'));

        bestFile = '';
        bestScore = -Inf;
        DNmin = min(DN);
        DNmax = max(DN);

        for ii = 1:numel(cand)
            f = fullfile(cand(ii).folder, cand(ii).name);
            tmp = load(f);

            t = [];
            usedIndexFallback = false;
            if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN(:); end
            if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time(:); end
            if isempty(t) && isfield(tmp,'LungeI') && ~isempty(tmp.LungeI)
                idx = tmp.LungeI(:);
                idx = idx(idx >= 1 & idx <= N);
                if ~isempty(idx)
                    t = DN(idx);
                    usedIndexFallback = true;
                end
            end
            if isempty(t) && isfield(tmp,'LI') && ~isempty(tmp.LI)
                idx = tmp.LI(:);
                idx = idx(idx >= 1 & idx <= N);
                if ~isempty(idx)
                    t = DN(idx);
                    usedIndexFallback = true;
                end
            end
            if isempty(t) && isfield(tmp,'L') && ~isempty(tmp.L)
                t = tmp.L(:);
            end

            if isempty(t)
                continue
            end

            in = (t >= DNmin) & (t <= DNmax);
            nIn = sum(in);
            nTot = numel(t);
            frac = nIn / max(nTot,1);
            score = frac + 0.01*log1p(nIn);

            % Use name overlap as a soft preference, but never as a hard
            % requirement. This keeps DTAG folders with odd naming patterns
            % from dropping the correct lunge file before overlap is scored.
            nameMatches = contains(lower(cand(ii).name), lower(depStem)) || ...
                          contains(lower(cand(ii).name), lower(depStemCompact));
            if nameMatches
                score = score + 0.05;
            end

            % Slightly favor files that provided valid lunge indices even if
            % their absolute times were sparse or absent.
            if usedIndexFallback
                score = score + 0.02;
            end

            if score > bestScore
                bestScore = score;
                bestFile = f;
            end
        end

        % Failsafe: if lunge files exist but none had usable timing for the
        % overlap score, still try the first candidate directly and extract
        % lunge indices from it. This is especially important for older
        % DTAG/CATS files that store indices but not clean absolute times.
        if isempty(bestFile) && ~isempty(cand)
            bestFile = fullfile(cand(1).folder, cand(1).name);
            fprintf(['  No lunge file had usable timing for overlap scoring; ' ...
                'falling back to first candidate: %s\n'], bestFile);
        end

        if ~isempty(bestFile)
            fprintf('  Using lunge file: %s\n', bestFile);
            selectedLungeFile = string(bestFile);
            tmp = load(bestFile);
            [LungeI, LungeDN, LungeTimeAlt] = extract_lunge_fields_from_loaded_mat(tmp);
            lungePrhFs = [];
            lungeStartTime = [];
            if isfield(tmp,'prh_fs') && ~isempty(tmp.prh_fs)
                lungePrhFs = double(tmp.prh_fs);
            end
            if isfield(tmp,'starttime') && ~isempty(tmp.starttime)
                lungeStartTime = double(tmp.starttime);
            end

            if ~isempty(LungeDN)
                goodDN = isfinite(LungeDN);
                if any(goodDN)
                    LI = nan(size(LungeDN));
                    for j = find(goodDN(:))'
                        [~, LI(j)] = min(abs(DN - LungeDN(j)));
                    end
                end
            end

            if isempty(LI) || all(~isfinite(LI))
                if ~isempty(LungeTimeAlt)
                    goodAlt = isfinite(LungeTimeAlt);
                    if any(goodAlt)
                        LI = nan(size(LungeTimeAlt));
                        for j = find(goodAlt(:))'
                            [~, LI(j)] = min(abs(DN - LungeTimeAlt(j)));
                        end
                    end
                end
            end

            if isempty(LI) || all(~isfinite(LI))
                if ~isempty(LungeI)
                    % Some older files store valid sample indices referenced to
                    % the PRH vector even when DN fields are messy or absent.
                    LungeI = double(LungeI(:));
                    LungeI = LungeI(isfinite(LungeI));

                    % If the lunge file was generated at a different PRH
                    % sampling rate, rescale indices onto the current PRH.
                    if ~isempty(lungePrhFs) && isfinite(lungePrhFs) && lungePrhFs > 0 && abs(lungePrhFs - fs) > 1e-6
                        LungeI = round(LungeI .* (fs ./ lungePrhFs));
                    end

                    % If indices are still unusable but a start time exists,
                    % convert sample indices to datenum and then map to DN.
                    if (~any(LungeI >= 1 & LungeI <= numel(p))) && ...
                            ~isempty(lungeStartTime) && isfinite(lungeStartTime) && ...
                            ~isempty(lungePrhFs) && isfinite(lungePrhFs) && lungePrhFs > 0
                        estDN = lungeStartTime + ((LungeI - 1) ./ lungePrhFs) ./ 86400;
                        LI = nan(size(estDN));
                        for j = 1:numel(estDN)
                            [~, LI(j)] = min(abs(DN - estDN(j)));
                        end
                    else
                        LungeI = LungeI(LungeI >= 1 & LungeI <= numel(p));
                        LI = LungeI;
                    end
                end
            end

            if isempty(LI)
                LI = [];
            end

            if ~isempty(LI)
                LI = LI(:);
                LI = LI(isfinite(LI));
                LI = LI(LI >= 1 & LI <= N);
                LI = LI(p(LI) >= LUNGE_MIN_DEPTH_M);
            end

            if isempty(LI)
                fprintf(['  Selected lunge file loaded, but no valid lunge indices remained after filtering ' ...
                    '(N=%d, numel(p)=%d).\n'], N, numel(p));
                fprintf('  Available top-level fields in selected lunge file:\n');
                disp(fieldnames(tmp))
                fprintf('  Debug preview from selected lunge file:\n');
                if ~isempty(LungeI)
                    fprintf('    first LungeI values: ');
                    disp(LungeI(1:min(10,numel(LungeI)))')
                else
                    fprintf('    LungeI: empty\n');
                end
                if ~isempty(LungeDN)
                    fprintf('    first LungeDN values: ');
                    disp(LungeDN(1:min(10,numel(LungeDN)))')
                else
                    fprintf('    LungeDN: empty\n');
                end
                if ~isempty(LungeTimeAlt)
                    fprintf('    first L values: ');
                    disp(LungeTimeAlt(1:min(10,numel(LungeTimeAlt)))')
                else
                    fprintf('    L: empty\n');
                end
                if exist('lungePrhFs','var') && ~isempty(lungePrhFs)
                    fprintf('    prh_fs: %.6f\n', lungePrhFs);
                else
                    fprintf('    prh_fs: empty\n');
                end
                if exist('lungeStartTime','var') && ~isempty(lungeStartTime)
                    fprintf('    starttime: %.10f\n', lungeStartTime);
                else
                    fprintf('    starttime: empty\n');
                end
                lungeStatus = "selected_file_no_valid_indices";
            else
                lungeStatus = "lunges_loaded";
            end
        else
            lungeStatus = "no_lunge_file_selected";
        end
    catch ME
        warning('Problem loading lunge file for %s: %s', depID, ME.message);
        LI = [];
        lungeStatus = "lunge_load_error";
        skipReason = string(ME.message);
    end

    if isempty(LI)
        fprintf('  No lunges found.\n');
        if strlength(skipReason) == 0
            skipReason = "no_lunges_extracted";
        end
        auditRows(end+1, :) = {depID, whaleName, prhFiles(fi).name, selectedLungeFile, lungeStatus, nLungesExtracted, skipReason}; %#ok<AGROW>
        continue
    end

    nLungesExtracted = numel(LI);

    %% ---- Detect kept dives for context flag ----
    inDiveRaw = (p > DIVE_THRESH_M) & tagon;
    d = diff([false; inDiveRaw; false]);
    diveStarts = find(d == 1);
    diveStops  = find(d == -1) - 1;

    dur_s = (diveStops - diveStarts + 1) / fs;
    keepDive = dur_s >= MIN_DIVE_DUR_S;
    diveStarts = diveStarts(keepDive);
    diveStops  = diveStops(keepDive);

    %% ---- One row per lunge ----
    for lii = 1:numel(LI)
        li = LI(lii);
        lungeDN = DN(li);
        dv = datevec(lungeDN);
        lungeYear = dv(1);
        lungeMonth = dv(2);
        lungeDepth_m = p(li);

        containingDiveNum = nan;
        isInKeptDive = false;
        if ~isempty(diveStarts)
            di = find(diveStarts <= li & diveStops >= li, 1, 'first');
            if ~isempty(di)
                containingDiveNum = di;
                isInKeptDive = true;
            end
        end

        rows(end+1, :) = { ...
            depID, ...
            whaleName, ...
            prhFiles(fi).name, ...
            lii, ...
            lungeDN, ...
            lungeYear, ...
            lungeMonth, ...
            lungeDepth_m, ...
            isInKeptDive, ...
            containingDiveNum ...
            };
    end

    %% ---- One row per lunge-containing dive ----
    if ~isempty(diveStarts)
        for di = 1:numel(diveStarts)
            a = diveStarts(di);
            b = diveStops(di);

            thisLunges = LI(LI >= a & LI <= b);
            if isempty(thisLunges)
                continue
            end

            diveMidDN = mean([DN(a), DN(b)]);
            dv = datevec(diveMidDN);
            diveYear = dv(1);
            diveMonth = dv(2);

            foragingDiveRows(end+1, :) = { ...
                depID, ...
                whaleName, ...
                prhFiles(fi).name, ...
                di, ...
                DN(a), ...
                DN(b), ...
                diveYear, ...
                diveMonth, ...
                (b - a + 1) / fs, ...
                max(p(a:b), [], 'omitnan'), ...
                mean(p(a:b), 'omitnan'), ...
                numel(thisLunges), ...
                mean(p(thisLunges), 'omitnan') ...
                };
        end
    end

    auditRows(end+1, :) = {depID, whaleName, prhFiles(fi).name, selectedLungeFile, lungeStatus, nLungesExtracted, skipReason}; %#ok<AGROW>
end

%% =========================
% BUILD TABLE
% =========================
if isempty(rows)
    error('No lunge rows were created.');
end

lungeDepthTable = cell2table(rows, 'VariableNames', { ...
    'depID', ...
    'whaleName', ...
    'prhFile', ...
    'lungeNum', ...
    'lungeDN', ...
    'year', ...
    'month', ...
    'lungeDepth_m', ...
    'isInKeptDive', ...
    'containingDiveNum'});

foragingDiveDepthTable = cell2table(foragingDiveRows, 'VariableNames', { ...
    'depID', ...
    'whaleName', ...
    'prhFile', ...
    'diveNum', ...
    'startDN', ...
    'stopDN', ...
    'year', ...
    'month', ...
    'diveDur_s', ...
    'maxDiveDepth_m', ...
    'meanDiveDepth_m', ...
    'lungeCount', ...
    'meanLungeDepthWithinDive_m'});

deploymentAudit = cell2table(auditRows, 'VariableNames', { ...
    'depID', ...
    'whaleName', ...
    'prhFile', ...
    'selectedLungeFile', ...
    'lungeStatus', ...
    'nLungesExtracted', ...
    'skipReason'});

fprintf('\nBuilt lungeDepthTable with %d lunge events.\n', height(lungeDepthTable));
fprintf('Built foragingDiveDepthTable with %d lunge-containing dives.\n', height(foragingDiveDepthTable));

%% =========================
% SAVE
% =========================
if saveOutput
    writetable(lungeDepthTable, outFile);
    fprintf('Saved: %s\n', outFile);
    diveOutFile = fullfile(rootDir, 'monthly_foraging_dive_depth_table.csv');
    writetable(foragingDiveDepthTable, diveOutFile);
    fprintf('Saved: %s\n', diveOutFile);
    auditFile = fullfile(rootDir, 'monthly_lunge_depth_deployment_audit.csv');
    writetable(deploymentAudit, auditFile);
    fprintf('Saved: %s\n', auditFile);
end

%% =========================
% QUICK LOOK
% =========================
disp(lungeDepthTable(1:min(8,height(lungeDepthTable)), :))

function [LungeI, LungeDN, LungeTimeAlt] = extract_lunge_fields_from_loaded_mat(tmp)
% Extract lunge index/time vectors from a loaded .mat struct.
% Checks top-level fields first, then looks one level down into any scalar
% struct fields, which is common in older lunge files.

LungeI = [];
LungeDN = [];
LungeTimeAlt = [];

% Top-level first
if isfield(tmp,'LungeI') && ~isempty(tmp.LungeI), LungeI = tmp.LungeI(:); end
if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), LungeDN = tmp.LungeDN(:); end
if isempty(LungeI) && isfield(tmp,'LI') && ~isempty(tmp.LI), LungeI = tmp.LI(:); end
if isempty(LungeDN) && isfield(tmp,'time') && ~isempty(tmp.time), LungeDN = tmp.time(:); end
if isempty(LungeDN) && isfield(tmp,'L') && ~isempty(tmp.L), LungeTimeAlt = tmp.L(:); end

if ~isempty(LungeI) || ~isempty(LungeDN) || ~isempty(LungeTimeAlt)
    return
end

% One level down into scalar structs
fn = fieldnames(tmp);
for ii = 1:numel(fn)
    val = tmp.(fn{ii});
    if ~isstruct(val) || numel(val) ~= 1
        continue
    end

    if isfield(val,'LungeI') && ~isempty(val.LungeI), LungeI = val.LungeI(:); end
    if isfield(val,'LungeDN') && ~isempty(val.LungeDN), LungeDN = val.LungeDN(:); end
    if isempty(LungeI) && isfield(val,'LI') && ~isempty(val.LI), LungeI = val.LI(:); end
    if isempty(LungeDN) && isfield(val,'time') && ~isempty(val.time), LungeDN = val.time(:); end
    if isempty(LungeDN) && isfield(val,'L') && ~isempty(val.L), LungeTimeAlt = val.L(:); end

    if ~isempty(LungeI) || ~isempty(LungeDN) || ~isempty(LungeTimeAlt)
        return
    end
end
end
