% Identify behavioral states and create an activity budget for a tag deployment
%
% Behavioral states:
%   1 = surface active
%   2 = resting
%   3 = traveling
%   4 = foraging
%   5 = exploring
%
% Classification framework:
% - Substantial dives containing a deep lunge are classified as foraging for the full dive
% - Near-threshold / shallow lunges (<= 6 m) are classified as foraging within a +/-30 s buffer
% - Each dive keeps its assigned state for 20 s after surfacing
% - Remaining surface intervals are classified as resting or surface active
% - Resting requires low speed, low pitch variability, low movement, and a minimum bout duration
% - Non-foraging dives are classified as resting, traveling, or exploring
%
% =========================================================
% VERSION: 2026-04-22
% Auto state classifier v3 (5-state hybrid, no recovery)
% Foraging logic distinguishes deep-dive vs shallow buffered foraging
% Dive-state windows are extended on both entry and exit to reduce shallow-edge artifacts
% Minimum kept dive duration is 30 s
% Post-dive carryover assigns first 20 s after a dive to that dive's state
% Surface classification uses resting vs surface active only
%
% Lauren Fritz
% University of California Santa Cruz
% =========================================================
%
% Input:
%   - 5 Hz (DTAG) or 10 Hz (CATS) PRH .mat file
%
% Outputs:
%   - Activity budget .csv file
%   - Activity budget figure
%   - Interactive behavior plot

%% 1. Load Data
if exist('prhPath', 'var') && ~isempty(prhPath)
    clearvars -except prhPath BATCH_MODE MAKE_ACTIVITY_FIGURE MAKE_INTERACTIVE_PLOT ...
        USE_POOLED_REST_THRESHOLDS POOLED_REST_THRESH_FILE ...
        EXPORT_REST_REFERENCE_SAMPLES REST_REFERENCE_SAMPLE_STRIDE_S
else
    clear;
end

if ~exist('BATCH_MODE', 'var') || isempty(BATCH_MODE)
    BATCH_MODE = false;
end
if ~exist('MAKE_ACTIVITY_FIGURE', 'var') || isempty(MAKE_ACTIVITY_FIGURE)
    MAKE_ACTIVITY_FIGURE = ~BATCH_MODE;
end
if ~exist('MAKE_INTERACTIVE_PLOT', 'var') || isempty(MAKE_INTERACTIVE_PLOT)
    MAKE_INTERACTIVE_PLOT = ~BATCH_MODE;
end

atLast = true; %#ok<NASGU>
M = 10; % default number of minutes to display per window

notes = ''; %#ok<NASGU>
creator = 'DEC'; %#ok<NASGU>
primary_cue = 'speedJJ'; %#ok<NASGU>

manualStates = {'resting','traveling','foraging','exploring'}; %#ok<NASGU>
autoStates   = {'surface active','resting','traveling','foraging','exploring'}; %#ok<NASGU>

try
    drive = 'CATS';
    folder = 'CATS/CATS/tag_analysis/data_processed'; %#ok<NASGU>
    a = getdrives;
    for i = 1:length(a)
        [~,vol] = system(['vol ' a{i}(1) ':']);
        if strfind(vol, drive) %#ok<STREMP>
            vol = a{i}(1); %#ok<NASGU>
            break
        end
    end
catch
end

cf = pwd; %#ok<NASGU>
if exist('prhPath', 'var') && ~isempty(prhPath)
    [fileloc, name, ext] = fileparts(prhPath);
    filename = [name ext];
    if isempty(fileloc)
        fileloc = pwd;
    end
else
    [filename,fileloc] = uigetfile('*.mat', 'Select the PRH file to analyze');
    if isequal(filename,0) || isequal(fileloc,0)
        error('No PRH file selected.');
    end
    prhPath = fullfile(fileloc, filename);
end
cd(fileloc);

disp('Loading Data, will take some time');
load(prhPath);

if exist('fs','var') && ~isempty(fs)
    fs = fs;
elseif exist('fs1','var') && ~isempty(fs1)
    fs = fs1;
else
    error('No sampling rate found in loaded PRH file (expected fs or fs1).');
end

fprintf('Sampling rate: %.2f Hz\n', fs);

if exist('speed','var') && isstruct(speed)
    disp(fieldnames(speed))
    if isfield(speed,'JJ')
        fprintf('speed.JJ finite count: %d\n', sum(isfinite(speed.JJ(:))));
    end
    if isfield(speed,'FN')
        fprintf('speed.FN finite count: %d\n', sum(isfinite(speed.FN(:))));
    end
end

% Recover DTAG companion variables when they are not stored directly in the
% PRH file. Many older DTAG deployments keep DN in an RMS file and tagon in
% a separate tagon file.
[~, baseName, ~] = fileparts(filename);
depStem = regexprep(baseName, 'prh(_speed)?$', '', 'ignorecase');
depStemCompact = regexprep(depStem, '^mn\d{2}_', 'mn', 'ignorecase');

if ~exist('DN','var') || isempty(DN)
    DN = [];
    cand = dir(fullfile(fileloc, '*.mat'));
    names = {cand.name};
    keep = contains(lower(names), lower(depStem)) | ...
           contains(lower(names), lower(depStemCompact));
    cand = cand(keep);

    for ii = 1:numel(cand)
        nm = cand(ii).name;
        if contains(lower(nm), 'rms')
            f = fullfile(cand(ii).folder, nm);
            fprintf('Trying DN from %s\n', nm);
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

if ~exist('tagon','var') || isempty(tagon)
    tagon = [];
    cand = dir(fullfile(fileloc, '*.mat'));
    names = {cand.name};
    keep = contains(lower(names), lower(depStem)) | ...
           contains(lower(names), lower(depStemCompact));
    cand = cand(keep);

    for ii = 1:numel(cand)
        nm = cand(ii).name;
        if contains(lower(nm), 'tagon')
            f = fullfile(cand(ii).folder, nm);
            fprintf('Trying tagon from %s\n', nm);
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

if ~exist('DN','var') || isempty(DN)
    error('No DN found in PRH or companion files for %s.', filename);
end
if ~exist('tagon','var') || isempty(tagon)
    error('No tagon found in PRH or companion files for %s.', filename);
end

%% Build speedJJ and speedFN
p = p(:);
DN = DN(:);
tagon = tagon(:);

speedJJ = nan(size(p));
speedFN = nan(size(p));

if exist('speed','var') && ~isempty(speed)
    if istable(speed)
        vars = speed.Properties.VariableNames;

        if ismember('JJ', vars) && ~isempty(speed.JJ)
            raw = speed.JJ(:);
            if any(isfinite(raw))
                tmp = raw;
                tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                tmp = runmean(tmp, max(1, round(fs/2)));
                tmp(isnan(raw)) = nan;
                n = min(numel(tmp), numel(speedJJ));
                speedJJ(1:n) = tmp(1:n);
            end
        end

        if ismember('FN', vars) && ~isempty(speed.FN)
            raw = speed.FN(:);
            if any(isfinite(raw))
                tmp = raw;
                tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                tmp = runmean(tmp, max(1, round(fs/2)));
                tmp(isnan(raw)) = nan;
                n = min(numel(tmp), numel(speedFN));
                speedFN(1:n) = tmp(1:n);
            end
        end

    elseif isstruct(speed)
        if isfield(speed,'JJ') && ~isempty(speed.JJ)
            raw = speed.JJ(:);
            if any(isfinite(raw))
                tmp = raw;
                tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                tmp = runmean(tmp, max(1, round(fs/2)));
                tmp(isnan(raw)) = nan;
                n = min(numel(tmp), numel(speedJJ));
                speedJJ(1:n) = tmp(1:n);
            end
        end

        if isfield(speed,'FN') && ~isempty(speed.FN)
            raw = speed.FN(:);
            if any(isfinite(raw))
                tmp = raw;
                tmp(isnan(tmp)) = min(tmp(isfinite(tmp)));
                tmp = runmean(tmp, max(1, round(fs/2)));
                tmp(isnan(raw)) = nan;
                n = min(numel(tmp), numel(speedFN));
                speedFN(1:n) = tmp(1:n);
            end
        end
    end
end

fprintf('  finite speedJJ: %d | finite speedFN: %d\n', ...
    sum(isfinite(speedJJ)), sum(isfinite(speedFN)));

%% Jerk proxy
if exist('njerk','file') == 2 && exist('Aw','var') && ~isempty(Aw)
    J = njerk(Aw, fs);
    J = J(:);
else
    if exist('Aw','var') && ~isempty(Aw)
        dAw = [zeros(1,size(Aw,2)); diff(Aw)];
        J = sqrt(sum(dAw.^2,2)) * fs;
    else
        J = nan(size(p));
    end
end

J = J(:);
if numel(J) < numel(p), J(end+1:numel(p)) = J(end); end
if numel(J) > numel(p), J = J(1:numel(p)); end

mov = speedJJ;
if all(isnan(mov))
    mov = J;
end

[~, baseName, ~] = fileparts(filename);

%% Load lunges file
LungeI = [];
LungeDN = [];
LungeC = [];
LI = [];
L = [];
LC = [];

depID = regexp(baseName,'^[^ ]+','match','once');

whaleName = depID;
if exist('INFO','var') && isstruct(INFO) && isfield(INFO,'whaleName') && ~isempty(INFO.whaleName)
    whaleName = INFO.whaleName;
end
whaleName = regexprep(whaleName, '[^\w\-]+', '_');

searchRoot = fileloc;
cand = dir(fullfile(searchRoot, '**', '*lunges.mat'));
cand = cand(~startsWith({cand.name}, '._'));

bestFile = '';
bestScore = -Inf;

if isempty(cand)
    warning('No lunge files found for depID=%s. Proceeding with NO LUNGES.', depID);
else
    DNmin = min(DN);
    DNmax = max(DN);

    for k = 1:numel(cand)
        f = fullfile(cand(k).folder, cand(k).name);
        tmp = load(f);

        t = [];
        usedIndexFallback = false;
        [tmpLungeI, tmpLungeDN, tmpLungeTimeAlt] = extract_lunge_fields_from_loaded_mat(tmp);

        if ~isempty(tmpLungeDN), t = tmpLungeDN(:); end
        if isempty(t) && ~isempty(tmpLungeTimeAlt), t = tmpLungeTimeAlt(:); end
        if isempty(t) && ~isempty(tmpLungeI)
            ii = double(tmpLungeI(:));
            ii = ii(ii >= 1 & ii <= numel(DN));
            if ~isempty(ii)
                t = DN(ii);
                usedIndexFallback = true;
            end
        end

        if isempty(t)
            continue
        end

        t = t(:);
        in = (t >= DNmin) & (t <= DNmax);
        nIn = sum(in);
        nTot = numel(t);
        frac = nIn / max(nTot,1);
        score = frac + 0.01*log1p(nIn);

        nameMatches = contains(lower(cand(k).name), lower(depStem)) || ...
                      contains(lower(cand(k).name), lower(depStemCompact)) || ...
                      contains(lower(cand(k).folder), lower(depStem)) || ...
                      contains(lower(cand(k).folder), lower(depStemCompact));
        if nameMatches
            score = score + 0.05;
        end
        if usedIndexFallback
            score = score + 0.02;
        end
        if nIn == 0 && ~usedIndexFallback
            score = score - 1;
        end

        if score > bestScore
            bestScore = score;
            bestFile = f;
        end
    end

    if isempty(bestFile)
        bestFile = fullfile(cand(1).folder, cand(1).name);
        fprintf(['No lunge file had usable timing for overlap scoring; ' ...
            'falling back to first candidate: %s\n'], bestFile);
    else
        fprintf('\nSelected lunges file (best time overlap):\n%s\nScore=%.3f\n\n', bestFile, bestScore);
    end
end

if ~isempty(bestFile) && isfile(bestFile)
    fprintf('Using lunge file: %s\n', bestFile);
    tmp = load(bestFile);
    disp('Lunge file variables:');
    disp(fieldnames(tmp));

    if isfield(tmp,'LungeC'),  LungeC  = tmp.LungeC(:);  end
    [LungeI, LungeDN, LungeTimeAlt] = extract_lunge_fields_from_loaded_mat(tmp);
    lungePrhFs = [];
    lungeStartTime = [];
    if isfield(tmp,'prh_fs') && ~isempty(tmp.prh_fs)
        lungePrhFs = double(tmp.prh_fs);
    end
    if isfield(tmp,'starttime') && ~isempty(tmp.starttime)
        lungeStartTime = double(tmp.starttime);
    end
    if isfield(tmp,'LungeC'),  LungeC  = tmp.LungeC(:);  end

    if ~isempty(LungeDN)
        goodDN = isfinite(LungeDN);
        if any(goodDN)
            LI = nan(size(LungeDN));
            for j = find(goodDN(:))'
                [~,LI(j)] = min(abs(DN - LungeDN(j)));
            end
        end
    end

    if (isempty(LI) || all(~isfinite(LI))) && ~isempty(LungeTimeAlt)
        goodAlt = isfinite(LungeTimeAlt);
        if any(goodAlt)
            LI = nan(size(LungeTimeAlt));
            for j = find(goodAlt(:))'
                [~,LI(j)] = min(abs(DN - LungeTimeAlt(j)));
            end
        end
    end

    if (isempty(LI) || all(~isfinite(LI))) && ~isempty(LungeI)
        LungeI = double(LungeI(:));
        LungeI = LungeI(isfinite(LungeI));

        if ~isempty(lungePrhFs) && isfinite(lungePrhFs) && lungePrhFs > 0 && abs(lungePrhFs - fs) > 1e-6
            LungeI = round(LungeI .* (fs ./ lungePrhFs));
        end

        if (~any(LungeI >= 1 & LungeI <= numel(p))) && ...
                ~isempty(lungeStartTime) && isfinite(lungeStartTime) && ...
                ~isempty(lungePrhFs) && isfinite(lungePrhFs) && lungePrhFs > 0
            estDN = lungeStartTime + ((LungeI - 1) ./ lungePrhFs) ./ 86400;
            LI = nan(size(estDN));
            for j = 1:numel(estDN)
                [~, LI(j)] = min(abs(DN - estDN(j)));
            end
        else
            LI = LungeI;
        end
    end

    if isempty(LI)
        LI = [];
    end

    if ~isempty(LI)
        LI = LI(:);
        LI = LI(isfinite(LI));
        LI = LI(LI>=1 & LI<=numel(p));
    end

    if ~isempty(LungeDN)
        L = LungeDN(:);
    elseif ~isempty(LungeTimeAlt)
        L = LungeTimeAlt(:);
    elseif ~isempty(LI)
        L = DN(LI);
    else
        L = [];
    end

    if ~isempty(LungeC)
        LC = LungeC(:);
    else
        LC = nan(size(LI));
    end
    if numel(LC) ~= numel(LI); LC = nan(size(LI)); end

    if isempty(LI)
        fprintf(['Selected lunge file loaded, but no valid lunge indices remained after filtering ' ...
            '(N=%d, numel(p)=%d).\n'], numel(p), numel(p));
        fprintf('Available top-level fields in selected lunge file:\n');
        disp(fieldnames(tmp))
        fprintf('Debug preview from selected lunge file:\n');
        if ~isempty(LungeI)
            fprintf('  first LungeI values: ');
            disp(LungeI(1:min(10,numel(LungeI)))')
        else
            fprintf('  LungeI: empty\n');
        end
        if ~isempty(LungeDN)
            fprintf('  first LungeDN values: ');
            disp(LungeDN(1:min(10,numel(LungeDN)))')
        else
            fprintf('  LungeDN: empty\n');
        end
        if ~isempty(LungeTimeAlt)
            fprintf('  first L values: ');
            disp(LungeTimeAlt(1:min(10,numel(LungeTimeAlt)))')
        else
            fprintf('  L: empty\n');
        end
        if ~isempty(lungePrhFs)
            fprintf('  prh_fs: %.6f\n', lungePrhFs);
        else
            fprintf('  prh_fs: empty\n');
        end
        if ~isempty(lungeStartTime)
            fprintf('  starttime: %.10f\n', lungeStartTime);
        else
            fprintf('  starttime: empty\n');
        end
    end
end

fprintf('FINAL lunges used: LI=%d\n', numel(LI));

%% Load geoPtrack KML
kmlLat = [];
kmlLon = [];
kmlFile = '';
candKML = dir(fullfile(fileloc, [depID '*geoPtrack.kml']));
candKML = candKML(~startsWith({candKML.name}, '._'));

if ~isempty(candKML)
    kmlFile = fullfile(candKML(1).folder, candKML(1).name);
    fprintf('Found geoPtrack KML: %s\n', kmlFile);
    try
        [kmlLat, kmlLon] = read_geoPtrack_kml_simple(kmlFile); %#ok<NASGU,ASGLU>
    catch ME
        warning('Failed to read KML file %s: %s', kmlFile, ME.message);
    end
else
    fprintf('No geoPtrack KML found for depID=%s in %s\n', depID, fileloc);
end

%% Auto State Classifier (v3, 5-state hybrid, no recovery)
BehaviorState = [];
BehaviorText  = '';
Bcolors       = 'rgkc'; %#ok<NASGU>

if ~exist('behI','var');  behI  = []; end %#ok<NASGU>
if ~exist('behT','var');  behT  = []; end %#ok<NASGU>
if ~exist('behS','var');  behS  = []; end %#ok<NASGU>
if ~exist('behSS','var'); behSS = []; end %#ok<NASGU>

DIVE_THRESH_M              = 5;
DIVE_ENTRY_EXT_M           = 1;
DIVE_EXIT_EXT_M            = 1;
MIN_DIVE_DUR_S             = 30;
MERGE_DIVE_GAP_S           = 10;
MIN_DEEP_FORAGE_DIVE_DUR_S = 10;
FORAGE_BUFFER_SHALLOW_S    = 30;
POST_DIVE_EXT_S            = 20;
REST_SPEED_MAX_MPS         = 2.0;
REST_MIN_BOUT_S            = 30;
REST_GAP_FILL_S            = 60;
REST_FLANK_LOOK_S          = 5;
MIN_STATE_BOUT_S           = 5;
SURFACE_ACTIVE_TO_REST_MAX_S = 5;
SURFACE_ACTIVE_TO_REST_MAX_DEPTH_M = 1;
SURFACE_ACTIVE_TO_FORAGE_MAX_S = 15;
SURFACE_ACTIVE_TO_FORAGE_MAX_DEPTH_M = 6;
PRE_FORAGE_SURFACE_GAP_S     = 5;
MOV_SMOOTH_S               = 10;
PITCH_VAR_WIN_S            = 10;
REST_MOV_PCTL              = 60;
REST_PITCHVAR_PCTL         = 70;
REST_DIVE_MOV_PCTL         = 80;
REST_DIVE_PITCHVAR_PCTL    = 80;
REST_DIVE_TURNRATE_MAX_DEGPS = 20;
SURFACE_REST_LOW_SPEED_FRAC = 0.8;
SURFACE_REST_TURNRATE_MAX_DEGPS = 20;
USE_POOLED_REST_THRESHOLDS = true;
POOLED_REST_THRESH_FILE = fullfile(fileloc, 'pooled_rest_thresholds.csv');
EXPORT_REST_REFERENCE_SAMPLES = false;
REST_REFERENCE_SAMPLE_STRIDE_S = 10;
TRAVEL_SPEED_MIN_MPS       = 1.5;
TRAVEL_TURNRATE_MAX_DEGPS  = 35;
TRAVEL_MAX_DEPTH_M         = 50;
SUBSURFACE_REST_FRAC       = 0.6;

p      = p(:);
DN     = DN(:);
tagon  = tagon(:);
pitch  = pitch(:);
if exist('head','var') && ~isempty(head)
    head = head(:);
else
    head = nan(size(p));
end

if exist('speedJJ','var') && ~isempty(speedJJ)
    speedTrace = speedJJ(:);
else
    speedTrace = nan(size(p));
end

mov = speedTrace;
if isempty(mov) || all(~isfinite(mov))
    mov = J(:);
    movementSource = "jerk";
else
    movementSource = "speedJJ";
end

N = min([numel(p), numel(DN), numel(tagon), numel(mov), numel(pitch), numel(head)]);
p          = p(1:N);
DN         = DN(1:N);
tagon      = tagon(1:N);
mov        = mov(1:N);
pitch      = pitch(1:N);
head       = head(1:N);
speedTrace = speedTrace(1:N);

if ~isempty(LI)
    LI = LI(:);
    LI = LI(LI >= 1 & LI <= N);
else
    LI = [];
end

inDiveRaw = (p > DIVE_THRESH_M) & tagon;
d = diff([false; inDiveRaw; false]);
diveStarts = find(d == 1);
diveStops  = find(d == -1) - 1;

dur_s = (diveStops - diveStarts + 1) / fs;
keep = dur_s >= MIN_DIVE_DUR_S;
diveStarts = diveStarts(keep);
diveStops  = diveStops(keep);

% Merge adjacent kept dives that are separated by only a brief shallow gap.
% This prevents one biological dive from being split into multiple bouts
% when depth briefly crosses above the 5 m threshold.
if numel(diveStarts) > 1
    mergeGapN = round(MERGE_DIVE_GAP_S * fs);
    mergedStarts = diveStarts(1);
    mergedStops  = diveStops(1);

    for di = 2:numel(diveStarts)
        gapN = diveStarts(di) - mergedStops(end) - 1;
        if gapN <= mergeGapN
            mergedStops(end) = diveStops(di);
        else
            mergedStarts(end+1,1) = diveStarts(di); %#ok<AGROW>
            mergedStops(end+1,1)  = diveStops(di); %#ok<AGROW>
        end
    end

    diveStarts = mergedStarts;
    diveStops  = mergedStops;
end

nDives = numel(diveStarts);

diveStateStarts = diveStarts;
diveStateStops  = diveStops;
for di = 1:nDives
    a = diveStarts(di);
    prevStop = 0;
    if di > 1
        prevStop = diveStops(di-1);
    end

    j = a;
    while j > (prevStop + 1) && tagon(j-1) && p(j-1) > DIVE_ENTRY_EXT_M
        j = j - 1;
    end
    diveStateStarts(di) = j;

    b = diveStops(di);
    nextStart = N + 1;
    if di < nDives
        nextStart = diveStarts(di+1);
    end

    j = b;
    while j < (nextStart - 1) && tagon(j+1) && p(j+1) > DIVE_EXIT_EXT_M
        j = j + 1;
    end
    diveStateStops(di) = j;
end

inDive = false(N,1);
for di = 1:nDives
    inDive(diveStarts(di):diveStops(di)) = true;
end

inDiveStateWindow = false(N,1);
for di = 1:nDives
    inDiveStateWindow(diveStateStarts(di):diveStateStops(di)) = true;
end

deepForageMask    = false(N,1);
shallowForageMask = false(N,1);
forageMask        = false(N,1);
deepForageDive    = false(nDives,1);

forageBufferN = round(FORAGE_BUFFER_SHALLOW_S * fs);
if ~isempty(LI)
    for ii = 1:numel(LI)
        li = LI(ii);

        % Match the lunge to the extended dive-state window rather than the
        % strict >5 m dive mask, so entry-phase lunges at ~1-5 m are still
        % treated as belonging to that dive.
        di = find(diveStateStarts <= li & diveStateStops >= li, 1, 'first');
        if ~isempty(di)
            diveDurThis = (diveStops(di) - diveStarts(di) + 1) / fs;
        else
            diveDurThis = nan;
        end

        % If the lunge occurs within a substantial containing dive window,
        % classify that whole dive as foraging. Only lunges that do not
        % belong to a substantial dive get the local +/-30 s buffer.
        if ~isempty(di) && inDiveStateWindow(li) && ...
                diveDurThis >= MIN_DEEP_FORAGE_DIVE_DUR_S
            deepForageMask(diveStateStarts(di):diveStateStops(di)) = true;
            deepForageDive(di) = true;
        else
            a = max(1, li - forageBufferN);
            b = min(N, li + forageBufferN);
            shallowForageMask(a:b) = true;
        end
    end
end
forageMask = deepForageMask | shallowForageMask;

fprintf('Deep-dive foraging minutes: %.2f\n', sum(deepForageMask & tagon)/fs/60);
fprintf('Shallow-buffer foraging minutes: %.2f\n', sum(shallowForageMask & tagon)/fs/60);

% Optional lunge audit summary for debugging edge cases.
if ~isempty(LI)
    fprintf('\n--- LUNGE AUDIT ---\n');
    for ii = 1:numel(LI)
        li = LI(ii);
        di = find(diveStateStarts <= li & diveStateStops >= li, 1, 'first');

        if isempty(di)
            fprintf(['Lunge %d | idx=%d | time=%s | depth=%.2f m | ' ...
                'assigned=shallow_buffer (not in any kept dive)\n'], ...
                ii, li, datestr(DN(li), 'mm/dd HH:MM:SS.FFF'), p(li));
            continue
        end

        diveDurThis = (diveStops(di) - diveStarts(di) + 1) / fs;
        if deepForageDive(di)
            assignStr = 'deep_dive_forage';
        else
            assignStr = 'shallow_buffer';
        end

        fprintf(['Lunge %d | idx=%d | time=%s | depth=%.2f m | dive=%d | ' ...
            'diveStart=%s | diveStop=%s | diveDur=%.1f s | assigned=%s\n'], ...
            ii, li, datestr(DN(li), 'mm/dd HH:MM:SS.FFF'), p(li), di, ...
            datestr(DN(diveStateStarts(di)), 'mm/dd HH:MM:SS.FFF'), ...
            datestr(DN(diveStateStops(di)), 'mm/dd HH:MM:SS.FFF'), ...
            diveDurThis, assignStr);
    end
    fprintf('-------------------\n\n');
end

postDiveN = round(POST_DIVE_EXT_S * fs);
postDiveWindowMask = false(N,1);
for di = 1:nDives
    a = diveStateStops(di) + 1;
    b = min(N, diveStateStops(di) + postDiveN);

    if a > N || a > b
        continue
    end

    nextDiveStart = inf;
    if di < nDives
        nextDiveStart = diveStarts(di+1);
    end
    b = min(b, nextDiveStart - 1);

    idx = a:b;
    idx = idx(~inDive(idx) & tagon(idx));
    if ~isempty(idx)
        postDiveWindowMask(idx) = true;
    end
end

wMov = max(1, round(MOV_SMOOTH_S * fs));
movS = mov;
if any(isfinite(movS))
    movFill = movS;
    movFill(~isfinite(movFill)) = prctile(movFill(isfinite(movFill)), 5);
    movS = runmean(movFill, wMov);
    movS(~isfinite(mov)) = nan;
end

wPitch = max(3, round(PITCH_VAR_WIN_S * fs));
pitchDeg = pitch * 180/pi;
pitchVar = movstd(pitchDeg, wPitch, 'omitnan');
pitchVar = pitchVar(:);
if numel(pitchVar) > N
    pitchVar = pitchVar(1:N);
end

% Treat heading as circular data and summarize directional stability
% using absolute turn rate rather than raw heading variance.
turnRateS = nan(N,1);
if any(isfinite(head))
    headRad = head(:);
    dHead = nan(size(headRad));

    validPairs = isfinite(headRad(1:end-1)) & isfinite(headRad(2:end));
    tmp = angle(exp(1i*headRad(2:end)) ./ exp(1i*headRad(1:end-1)));
    dHead(2:end) = tmp;
    dHead(~[false; validPairs]) = nan;

    turnRate = abs(dHead) * 180/pi * fs; % deg/s
    turnRateS = movmean(turnRate, wPitch, 'omitnan');
    turnRateS = turnRateS(:);
    if numel(turnRateS) > N
        turnRateS = turnRateS(1:N);
    elseif numel(turnRateS) < N
        turnRateS(end+1:N) = nan;
    end
end

lowSpeed = isfinite(speedTrace) & speedTrace <= REST_SPEED_MAX_MPS;

refMask = tagon ...
    & ~forageMask ...
    & ~postDiveWindowMask ...
    & lowSpeed ...
    & isfinite(movS) ...
    & isfinite(pitchVar);
if any(refMask)
    lowMovThresh = prctile(movS(refMask), REST_MOV_PCTL);
    lowPitchVarThresh = prctile(pitchVar(refMask), REST_PITCHVAR_PCTL);
    restDiveMovThresh = prctile(movS(refMask), REST_DIVE_MOV_PCTL);
    restDivePitchVarThresh = prctile(pitchVar(refMask), REST_DIVE_PITCHVAR_PCTL);
else
    lowMovThresh = nanmedian(movS);
    lowPitchVarThresh = nanmedian(pitchVar);
    restDiveMovThresh = nanmedian(movS);
    restDivePitchVarThresh = nanmedian(pitchVar);
end

pooledThresholdsUsed = false;
if USE_POOLED_REST_THRESHOLDS
    pooledCandidates = string({ ...
        POOLED_REST_THRESH_FILE, ...
        fullfile(fileparts(fileloc), 'pooled_rest_thresholds.csv'), ...
        fullfile('/Volumes/CATS/CATS/tag_analysis/data_processed', 'pooled_rest_thresholds.csv')});
    pooledCandidates = unique(pooledCandidates, 'stable');
    pooledFile = "";

    for k = 1:numel(pooledCandidates)
        if isfile(pooledCandidates(k))
            pooledFile = pooledCandidates(k);
            break
        end
    end

    if strlength(pooledFile) > 0
        pooledT = readtable(pooledFile);
        pooledUse = pooledT(strcmp(string(pooledT.movementSource), movementSource), :);
        if isempty(pooledUse)
            pooledUse = pooledT(strcmp(string(pooledT.movementSource), "all"), :);
        end

        if ~isempty(pooledUse)
            lowMovThresh = pooledUse.lowMovThresh(1);
            lowPitchVarThresh = pooledUse.lowPitchVarThresh(1);
            restDiveMovThresh = pooledUse.restDiveMovThresh(1);
            restDivePitchVarThresh = pooledUse.restDivePitchVarThresh(1);
            pooledThresholdsUsed = true;
            fprintf('Using pooled rest thresholds from: %s\n', pooledFile);
            fprintf('Pooled threshold movement source: %s\n', string(pooledUse.movementSource(1)));
        else
            warning('Pooled rest threshold file found but no row matched movementSource=%s or all. Using deployment-specific thresholds.', movementSource);
        end
    else
        warning('USE_POOLED_REST_THRESHOLDS=true, but no pooled_rest_thresholds.csv was found. Using deployment-specific thresholds.');
    end
end

fprintf('Rest threshold reference minutes: %.2f\n', sum(refMask)/fs/60);
fprintf('Rest movement source: %s\n', movementSource);
fprintf('Pooled rest thresholds used: %d\n', pooledThresholdsUsed);
fprintf('Rest movement threshold (p%d): %.4f\n', REST_MOV_PCTL, lowMovThresh);
fprintf('Rest pitch-var threshold (p%d): %.4f deg\n', REST_PITCHVAR_PCTL, lowPitchVarThresh);
fprintf('Rest dive mean-movement threshold (p%d): %.4f\n', REST_DIVE_MOV_PCTL, restDiveMovThresh);
fprintf('Rest dive mean-pitch-var threshold (p%d): %.4f deg\n', REST_DIVE_PITCHVAR_PCTL, restDivePitchVarThresh);
fprintf('Rest dive turn-rate max: %.2f deg/s\n', REST_DIVE_TURNRATE_MAX_DEGPS);
fprintf('Surface rest low-speed fraction min: %.2f\n', SURFACE_REST_LOW_SPEED_FRAC);
fprintf('Surface rest turn-rate max: %.2f deg/s\n', SURFACE_REST_TURNRATE_MAX_DEGPS);
lowMov   = isfinite(movS) & movS <= lowMovThresh;
lowPitch = isfinite(pitchVar) & pitchVar <= lowPitchVarThresh;

if EXPORT_REST_REFERENCE_SAMPLES
    refI = find(refMask);
    if ~isempty(refI)
        strideN = max(1, round(REST_REFERENCE_SAMPLE_STRIDE_S * fs));
        refI = refI(1:strideN:end);

        restRefT = table( ...
            repmat(string(depID), numel(refI), 1), ...
            repmat(string(whaleName), numel(refI), 1), ...
            repmat(movementSource, numel(refI), 1), ...
            DN(refI), ...
            p(refI), ...
            speedTrace(refI), ...
            movS(refI), ...
            pitchVar(refI), ...
            turnRateS(refI), ...
            'VariableNames', {'depID','whaleName','movementSource','DN', ...
            'depth_m','speed_mps','movS','pitchVar_deg','turnRate_deg_s'});

        writetable(restRefT, fullfile(fileloc, [whaleName '_RestThresholdReferenceSamples.csv']));
    end

    restThreshT = table( ...
        string(depID), string(whaleName), movementSource, pooledThresholdsUsed, ...
        sum(refMask)/fs/60, lowMovThresh, lowPitchVarThresh, ...
        restDiveMovThresh, restDivePitchVarThresh, ...
        'VariableNames', {'depID','whaleName','movementSource','pooledThresholdsUsed', ...
        'referenceMinutes','lowMovThresh','lowPitchVarThresh', ...
        'restDiveMovThresh','restDivePitchVarThresh'});

    writetable(restThreshT, fullfile(fileloc, [whaleName '_RestThresholdsUsed.csv']));
end

restCandidate = tagon & ~forageMask & lowSpeed & lowMov & lowPitch;
restMaskBase = false(N,1);
minRestN = max(1, round(REST_MIN_BOUT_S * fs));
dr = diff([false; restCandidate; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;
for k = 1:numel(rs)
    durBout = re(k) - rs(k) + 1;
    meanSpdBout = mean(speedTrace(rs(k):re(k)), 'omitnan');
    if durBout >= minRestN && meanSpdBout <= REST_SPEED_MAX_MPS
        restMaskBase(rs(k):re(k)) = true;
    end
end

travelMask   = false(N,1);
exploreMask  = false(N,1);
restDiveMask = false(N,1);
diveState    = nan(nDives,1);

for di = 1:nDives
    a = diveStateStarts(di);
    b = diveStateStops(di);

    % Only true dive-associated lunges should upgrade the whole dive to
    % foraging. Shallow buffered foraging can overlap a dive edge, but that
    % overlap alone should not convert the entire dive into foraging.
    if deepForageDive(di)
        diveState(di) = 4;
        continue
    end

    fracRest = mean(restMaskBase(a:b), 'omitnan');
    meanSpd  = mean(speedTrace(a:b), 'omitnan');
    meanMovDive = mean(movS(a:b), 'omitnan');
    meanPitchVarDive = mean(pitchVar(a:b), 'omitnan');
    meanTurnRate = mean(turnRateS(a:b), 'omitnan');
    maxDiveDepth = max(p(a:b), [], 'omitnan');

    isRestBySampleFraction = fracRest >= SUBSURFACE_REST_FRAC && ...
        meanSpd <= REST_SPEED_MAX_MPS;

    % Some biologically resting dives fail the sample-by-sample rest mask
    % because descent/ascent or brief spikes break up otherwise quiet dives.
    % This dive-level check lets the whole non-foraging dive be resting when
    % its average speed, movement, pitch variability, and turn rate are low.
    isRestByDiveProfile = ...
        ~isnan(meanSpd) && meanSpd <= REST_SPEED_MAX_MPS && ...
        ~isnan(meanMovDive) && meanMovDive <= restDiveMovThresh && ...
        ~isnan(meanPitchVarDive) && meanPitchVarDive <= restDivePitchVarThresh && ...
        (isnan(meanTurnRate) || meanTurnRate <= REST_DIVE_TURNRATE_MAX_DEGPS);

    if isRestBySampleFraction || isRestByDiveProfile
        restDiveMask(a:b) = true;
        diveState(di) = 2;
    elseif (~isnan(meanSpd) && meanSpd >= TRAVEL_SPEED_MIN_MPS) && ...
           (~isnan(meanTurnRate) && meanTurnRate <= TRAVEL_TURNRATE_MAX_DEGPS) && ...
           (~isnan(maxDiveDepth) && maxDiveDepth <= TRAVEL_MAX_DEPTH_M)
        travelMask(a:b) = true;
        diveState(di) = 3;
    else
        exploreMask(a:b) = true;
        diveState(di) = 5;
    end
end

postDiveCarryMask = false(N,1);

for di = 1:nDives
    extA = diveStateStops(di) + 1;
    extB = min(N, diveStateStops(di) + postDiveN);

    if extA > N || extA > extB
        continue
    end

    nextDiveStart = inf;
    if di < nDives
        nextDiveStart = diveStateStarts(di+1);
    end
    extB = min(extB, nextDiveStart - 1);

    surfaceExt = extA:extB;
    surfaceExt = surfaceExt(~inDive(surfaceExt) & tagon(surfaceExt));
    if isempty(surfaceExt)
        continue
    end

    postDiveCarryMask(surfaceExt) = true;
    switch diveState(di)
        case 2
            restDiveMask(surfaceExt) = true;
        case 3
            travelMask(surfaceExt) = true;
        case 4
            forageMask(surfaceExt) = true;
        case 5
            exploreMask(surfaceExt) = true;
    end
end

surfaceAll = tagon & ~inDiveStateWindow & ~forageMask;
surfaceRemainder = surfaceAll & ~postDiveCarryMask;
restMaskSurface = false(N,1);
surfaceActiveMask = false(N,1);

% First classify whole surface bouts as resting when their overall profile
% is quiet. This catches calm surface intervals that are interrupted by
% brief speed/movement spikes and would otherwise fail the sample-level mask.
dSurf = diff([false; surfaceRemainder; false]);
surfStarts = find(dSurf == 1);
surfStops  = find(dSurf == -1) - 1;
for k = 1:numel(surfStarts)
    a = surfStarts(k);
    b = surfStops(k);
    durBout = b - a + 1;

    if durBout < minRestN
        continue
    end

    meanSpdBout = mean(speedTrace(a:b), 'omitnan');
    meanMovBout = mean(movS(a:b), 'omitnan');
    meanPitchVarBout = mean(pitchVar(a:b), 'omitnan');
    meanTurnRateBout = mean(turnRateS(a:b), 'omitnan');
    fracLowSpeedBout = mean(lowSpeed(a:b), 'omitnan');

    isSurfaceRestByProfile = ...
        ~isnan(meanSpdBout) && meanSpdBout <= REST_SPEED_MAX_MPS && ...
        ~isnan(fracLowSpeedBout) && fracLowSpeedBout >= SURFACE_REST_LOW_SPEED_FRAC && ...
        ~isnan(meanMovBout) && meanMovBout <= restDiveMovThresh && ...
        ~isnan(meanPitchVarBout) && meanPitchVarBout <= restDivePitchVarThresh && ...
        (isnan(meanTurnRateBout) || meanTurnRateBout <= SURFACE_REST_TURNRATE_MAX_DEGPS);

    if isSurfaceRestByProfile
        restMaskSurface(a:b) = true;
    end
end

surfaceRestCandidate = surfaceRemainder & lowSpeed & lowMov & lowPitch;
dr = diff([false; surfaceRestCandidate; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;
for k = 1:numel(rs)
    durBout = re(k) - rs(k) + 1;
    meanSpdBout = mean(speedTrace(rs(k):re(k)), 'omitnan');
    if durBout >= minRestN && meanSpdBout <= REST_SPEED_MAX_MPS
        restMaskSurface(rs(k):re(k)) = true;
    end
end

maxRestGapN = max(1, round(REST_GAP_FILL_S * fs));
flankLookN = max(1, round(REST_FLANK_LOOK_S * fs));
surfaceNonRest = surfaceAll & ~restMaskSurface;
restAny = restMaskSurface | restDiveMask;
dg = diff([false; surfaceNonRest; false]);
gs = find(dg == 1);
ge = find(dg == -1) - 1;
for k = 1:numel(gs)
    a = gs(k);
    b = ge(k);
    gapLen = b - a + 1;

    if gapLen > maxRestGapN || a == 1 || b == N
        continue
    end

    leftA = max(1, a - flankLookN);
    leftB = a - 1;
    rightA = b + 1;
    rightB = min(N, b + flankLookN);

    hasLeftRest = (leftA <= leftB) && any(restAny(leftA:leftB));
    hasRightRest = (rightA <= rightB) && any(restAny(rightA:rightB));

    if hasLeftRest && hasRightRest
        restMaskSurface(a:b) = true;
    end
end

surfaceActiveMask(surfaceRemainder & ~restMaskSurface) = true;

restMask = restDiveMask | restMaskSurface;
restMask(forageMask) = false;
travelMask(forageMask | restMask) = false;
exploreMask(forageMask | restMask | travelMask) = false;
surfaceActiveMask(forageMask | restMask | travelMask | exploreMask) = false;

state = nan(N,1);
state(surfaceActiveMask) = 1;
state(restMask)          = 2;
state(travelMask)        = 3;
state(forageMask)        = 4;
state(exploreMask)       = 5;

minStateBoutN = max(1, round(MIN_STATE_BOUT_S * fs));
changed = true;
while changed
    changed = false;

    s = state;
    s(~tagon) = nan;

    startMask = false(size(s));
    startMask(1) = ~isnan(s(1));
    for k = 2:numel(s)
        if ~isnan(s(k)) && (isnan(s(k-1)) || s(k) ~= s(k-1))
            startMask(k) = true;
        end
    end

    boutStarts = find(startMask);
    if isempty(boutStarts)
        break
    end
    boutEnds = [boutStarts(2:end)-1; find(~isnan(s), 1, 'last')];

    for k = 2:numel(boutStarts)-1
        a = boutStarts(k);
        b = boutEnds(k);
        boutLen = b - a + 1;

        leftState = s(boutStarts(k-1));
        rightState = s(boutStarts(k+1));

        if boutLen <= minStateBoutN && leftState == rightState
            state(a:b) = leftState;
            changed = true;
            break
        end
    end
end

maxSurfaceActiveToRestN = max(1, round(SURFACE_ACTIVE_TO_REST_MAX_S * fs));
changed = true;
while changed
    changed = false;

    s = state;
    s(~tagon) = nan;

    startMask = false(size(s));
    startMask(1) = ~isnan(s(1));
    for k = 2:numel(s)
        if ~isnan(s(k)) && (isnan(s(k-1)) || s(k) ~= s(k-1))
            startMask(k) = true;
        end
    end

    boutStarts = find(startMask);
    if isempty(boutStarts)
        break
    end
    boutEnds = [boutStarts(2:end)-1; find(~isnan(s), 1, 'last')];

    for k = 1:numel(boutStarts)
        a = boutStarts(k);
        b = boutEnds(k);
        boutLen = b - a + 1;
        thisState = s(a);
        meanDepthBout = mean(p(a:b), 'omitnan');

        if thisState ~= 1 || boutLen > maxSurfaceActiveToRestN || ...
                ~isfinite(meanDepthBout) || meanDepthBout > SURFACE_ACTIVE_TO_REST_MAX_DEPTH_M
            continue
        end

        leftIsRest = (k > 1) && (s(boutStarts(k-1)) == 2);
        rightIsRest = (k < numel(boutStarts)) && (s(boutStarts(k+1)) == 2);

        if leftIsRest || rightIsRest
            state(a:b) = 2;
            changed = true;
            break
        end
    end
end

maxSurfaceActiveToForageN = max(1, round(SURFACE_ACTIVE_TO_FORAGE_MAX_S * fs));
maxPreForageSurfaceGapN = max(0, round(PRE_FORAGE_SURFACE_GAP_S * fs));
changed = true;
while changed
    changed = false;

    s = state;
    s(~tagon) = nan;

    startMask = false(size(s));
    startMask(1) = ~isnan(s(1));
    for k = 2:numel(s)
        if ~isnan(s(k)) && (isnan(s(k-1)) || s(k) ~= s(k-1))
            startMask(k) = true;
        end
    end

    boutStarts = find(startMask);
    if isempty(boutStarts)
        break
    end
    boutEnds = [boutStarts(2:end)-1; find(~isnan(s), 1, 'last')];

    for k = 1:numel(boutStarts)
        a = boutStarts(k);
        b = boutEnds(k);
        boutLen = b - a + 1;
        thisState = s(a);
        meanDepthBout = mean(p(a:b), 'omitnan');

        if thisState ~= 1 || boutLen > maxSurfaceActiveToForageN || ...
                ~isfinite(meanDepthBout) || meanDepthBout > SURFACE_ACTIVE_TO_FORAGE_MAX_DEPTH_M
            continue
        end

        leftIsForage = (k > 1) && (s(boutStarts(k-1)) == 4);
        rightIsForage = (k < numel(boutStarts)) && (s(boutStarts(k+1)) == 4);
        nextDiveIsForage = false;

        nextDive = find(diveStateStarts > b, 1, 'first');
        if ~isempty(nextDive)
            gapN = diveStateStarts(nextDive) - b - 1;
            nextDiveIsForage = gapN <= maxPreForageSurfaceGapN && ...
                isfinite(diveState(nextDive)) && diveState(nextDive) == 4;
        end

        if leftIsForage || rightIsForage || nextDiveIsForage
            state(a:b) = 4;
            changed = true;
            break
        end
    end
end

% Final hard constraint: no within-dive state fragmentation. Later
% smoothing/relabeling passes can occasionally overwrite parts of a real
% dive, so force each dive window back to its assigned dive-level state
% before saving outputs and building plots. Local +/-30 s buffered
% foraging is preserved only for lunges that are not part of a substantial
% containing dive.
fragmentedDiveCount = 0;
fragmentedDiveSamples = 0;
for di = 1:nDives
    if ~isfinite(diveState(di))
        continue
    end

    a = diveStateStarts(di);
    b = diveStateStops(di);

    thisDiveState = state(a:b);
    thisDiveState = thisDiveState(isfinite(thisDiveState));
    uniqueStates = unique(thisDiveState);
    if numel(uniqueStates) > 1 || any(thisDiveState ~= diveState(di))
        fragmentedDiveCount = fragmentedDiveCount + 1;
        fragmentedDiveSamples = fragmentedDiveSamples + (b - a + 1);
    end

    state(a:b) = diveState(di);
end

if fragmentedDiveCount > 0
    fprintf(['Collapsed %d fragmented dives back to their assigned ' ...
        'dive-level state (%d samples total).\n'], ...
        fragmentedDiveCount, fragmentedDiveSamples);
end

% Re-apply shallow buffered foraging only outside substantial dive windows.
outsideDiveWindowShallowForage = shallowForageMask & ~inDiveStateWindow;
state(outsideDiveWindowShallowForage) = 4;

%% Save binary/context variables for later analyses
% Rebuild masks from the final state vector so exports match the classifier
% after short-bout smoothing and shallow surface-active -> resting updates.
surfaceActiveMask = (state == 1);
restMask          = (state == 2);
travelMask        = (state == 3);
forageMask        = (state == 4);
exploreMask       = (state == 5);

% Split final resting into surface vs subsurface from the final state.
restMaskSurface = restMask & ~inDiveStateWindow;
restDiveMask    = restMask & inDiveStateWindow; %#ok<NASGU>

isSurface        = tagon & ~inDiveStateWindow;
isSubsurface     = tagon & inDiveStateWindow;
isPostDive       = postDiveCarryMask;
isResting        = restMask;
isSurfaceResting = restMaskSurface;
isTraveling      = travelMask;
isForaging       = forageMask;
isExploring      = exploreMask;
isSurfaceActive  = surfaceActiveMask;

contextVars = struct();
contextVars.depID = depID;
contextVars.whaleName = whaleName;
contextVars.DN = DN;
contextVars.fs = fs;
contextVars.tagon = tagon;
contextVars.state = state;
contextVars.isSurface = isSurface;
contextVars.isSubsurface = isSubsurface;
contextVars.isPostDive = isPostDive;
contextVars.isResting = isResting;
contextVars.isSurfaceResting = isSurfaceResting;
contextVars.isTraveling = isTraveling;
contextVars.isForaging = isForaging;
contextVars.isExploring = isExploring;
contextVars.isSurfaceActive = isSurfaceActive;
contextVars.inDive = inDive;
contextVars.inDiveStateWindow = inDiveStateWindow;
contextVars.postDiveWindowMask = postDiveWindowMask;
contextVars.deepForageMask = deepForageMask;
contextVars.shallowForageMask = shallowForageMask;
contextVars.restMaskBase = restMaskBase;
contextVars.restMaskSurface = restMaskSurface;
contextVars.turnRateS = turnRateS;

save(fullfile(fileloc, [whaleName '_BehaviorContextVars.mat']), 'contextVars');

contextT = table(DN, tagon, state, isSurface, isSubsurface, isPostDive, ...
    isResting, isSurfaceResting, isTraveling, isForaging, isExploring, ...
    isSurfaceActive, ...
    'VariableNames', {'DN','TagOn','State','IsSurface','IsSubsurface', ...
    'IsPostDive','IsResting','IsSurfaceResting','IsTraveling', ...
    'IsForaging','IsExploring','IsSurfaceActive'});
writetable(contextT, fullfile(fileloc, [whaleName '_BehaviorContextVars.csv']));

isForagingDive = false(nDives,1);
isTravelDive   = false(nDives,1);
isRestDive     = false(nDives,1);
isExploreDive  = false(nDives,1);
diveLungeCount = zeros(nDives,1); %#ok<NASGU>

for di = 1:nDives
    a = diveStateStarts(di);
    b = diveStateStops(di);

    if ~isempty(LI)
        diveLungeCount(di) = sum(LI >= a & LI <= b);
    end

    sDive = state(a:b);
    sDive = sDive(~isnan(sDive));
    if isempty(sDive)
        continue
    end

    isForagingDive(di) = any(sDive == 4);
    domState = mode(sDive);
    isRestDive(di)     = (domState == 2);
    isTravelDive(di)   = (domState == 3);
    isExploreDive(di)  = (domState == 5);
end

%% Build auto-state bouts from vectors
autoStartI = [];
autoEndI   = [];
autoState  = [];

validState = tagon & ~isnan(state);
s = state;
s(~validState) = NaN;

startMask = false(size(s));
startMask(1) = ~isnan(s(1));
for k = 2:numel(s)
    if ~isnan(s(k)) && (isnan(s(k-1)) || s(k) ~= s(k-1))
        startMask(k) = true;
    end
end

autoStartI = find(startMask);
if ~isempty(autoStartI)
    autoEndI = [autoStartI(2:end)-1; find(~isnan(s), 1, 'last')];
    autoState = s(autoStartI);
else
    warning('No auto-state bouts found.');
end

if ~isempty(autoStartI)
    fprintf('\n--- AUTO CLASSIFIER SUMMARY ---\n');
    fprintf('Valid lunges: %d\n', numel(LI));
    fprintf('Dives kept: %d\n', nDives);
    fprintf('Post-dive carryover (s): %.1f\n', POST_DIVE_EXT_S);
    fprintf('Rest min bout (s): %.1f\n', REST_MIN_BOUT_S);
    fprintf('Rest speed max (m/s): %.2f\n', REST_SPEED_MAX_MPS);
    fprintf('Travel speed min (m/s): %.2f\n', TRAVEL_SPEED_MIN_MPS);
    fprintf('Travel turn-rate max (deg/s): %.2f\n', TRAVEL_TURNRATE_MAX_DEGPS);
    fprintf('Travel max depth (m): %.2f\n', TRAVEL_MAX_DEPTH_M);
    fprintf('Surface active minutes: %.2f\n', sum(state==1 & tagon)/fs/60);
    fprintf('Rest minutes: %.2f\n', sum(state==2 & tagon)/fs/60);
    fprintf('Travel minutes: %.2f\n', sum(state==3 & tagon)/fs/60);
    fprintf('Forage minutes: %.2f\n', sum(state==4 & tagon)/fs/60);
    fprintf('Explore minutes: %.2f\n', sum(state==5 & tagon)/fs/60);
    totalMin = sum(tagon)/fs/60;
    classifiedMin = sum(~isnan(state) & tagon)/fs/60;
    fprintf('Total tag-on minutes: %.2f\n', totalMin);
    fprintf('Classified minutes: %.2f\n', classifiedMin);
    fprintf('Unclassified minutes: %.2f\n', totalMin - classifiedMin);
    fprintf('-------------------------------\n');
end

%% State-level QC summaries
stateNames = {'surface_active','resting','traveling','foraging','exploring'};
stateFigNames = {'surface active','resting','traveling','foraging','exploring'};
allStates = 1:numel(stateNames);
validClassified = tagon & ~isnan(state);
presentStates = allStates(arrayfun(@(ss) any(state(validClassified) == ss), allStates));

if isempty(presentStates)
    warning('No classified states detected. Summary tables and legends will be empty.');
end

sampleSummaryByState = table( ...
    strings(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    'VariableNames', { ...
    'State','nSamples', ...
    'speed_mean','speed_sd','speed_median', ...
    'mov_mean','mov_sd','mov_median', ...
    'pitchVar_mean','pitchVar_sd','pitchVar_median', ...
    'turnRate_mean','turnRate_sd','turnRate_median', ...
    'depth_mean','depth_sd','depth_median'});

sampleSummaryByState.State = string(stateNames(presentStates))';

for ii = 1:numel(presentStates)
    ss = presentStates(ii);
    idx = tagon & (state == ss);

    sp = speedTrace(idx);
    mv = movS(idx);
    pv = pitchVar(idx);
    tv = turnRateS(idx);
    dp = p(idx);

    sampleSummaryByState.nSamples(ii) = sum(idx);

    sampleSummaryByState.speed_mean(ii)   = mean(sp, 'omitnan');
    sampleSummaryByState.speed_sd(ii)     = std(sp, 'omitnan');
    sampleSummaryByState.speed_median(ii) = median(sp, 'omitnan');

    sampleSummaryByState.mov_mean(ii)     = mean(mv, 'omitnan');
    sampleSummaryByState.mov_sd(ii)       = std(mv, 'omitnan');
    sampleSummaryByState.mov_median(ii)   = median(mv, 'omitnan');

    sampleSummaryByState.pitchVar_mean(ii)   = mean(pv, 'omitnan');
    sampleSummaryByState.pitchVar_sd(ii)     = std(pv, 'omitnan');
    sampleSummaryByState.pitchVar_median(ii) = median(pv, 'omitnan');

    sampleSummaryByState.turnRate_mean(ii)   = mean(tv, 'omitnan');
    sampleSummaryByState.turnRate_sd(ii)     = std(tv, 'omitnan');
    sampleSummaryByState.turnRate_median(ii) = median(tv, 'omitnan');

    sampleSummaryByState.depth_mean(ii)   = mean(dp, 'omitnan');
    sampleSummaryByState.depth_sd(ii)     = std(dp, 'omitnan');
    sampleSummaryByState.depth_median(ii) = median(dp, 'omitnan');
end

disp('=== SAMPLE-LEVEL STATE SUMMARY ===')
disp(sampleSummaryByState)

boutDur_s = (autoEndI - autoStartI + 1) / fs;
boutSummaryByState = table( ...
    strings(numel(presentStates),1), nan(numel(presentStates),1), ...
    nan(numel(presentStates),1), nan(numel(presentStates),1), nan(numel(presentStates),1), ...
    'VariableNames', {'State','nBouts','dur_mean_s','dur_sd_s','dur_median_s'});
boutSummaryByState.State = string(stateNames(presentStates))';

for ii = 1:numel(presentStates)
    ss = presentStates(ii);
    d = boutDur_s(autoState == ss);
    boutSummaryByState.nBouts(ii)       = numel(d);
    boutSummaryByState.dur_mean_s(ii)   = mean(d, 'omitnan');
    boutSummaryByState.dur_sd_s(ii)     = std(d, 'omitnan');
    boutSummaryByState.dur_median_s(ii) = median(d, 'omitnan');
end

disp('=== BOUT-LEVEL DURATION SUMMARY ===')
disp(boutSummaryByState)

writetable(sampleSummaryByState, fullfile(fileloc, [whaleName '_StateSampleSummary.csv']));
writetable(boutSummaryByState, fullfile(fileloc, [whaleName '_StateBoutSummary.csv']));

plotVals = {speedTrace, movS, pitchVar, turnRateS, p};
plotNames = {'Speed','Movement','Pitch variability','Turn rate (deg/s)','Depth'};
stateColors = [
    0.34 0.71 0.91;
    0.25 0.20 0.65;
    0.80 0.47 0.65;
    0.50 0.78 0.35;
    0.95 0.90 0.20
];

if MAKE_ACTIVITY_FIGURE
    for vv = 1:numel(plotVals)
        vals = plotVals{vv};
        validPlot = tagon & ~isnan(state) & isfinite(vals);
        if ~any(validPlot)
            continue
        end

        figure('Color','w');
        boxplot(vals(validPlot), state(validPlot));
        ax = gca;
        ax.XTick = presentStates;
        ax.XTickLabel = stateNames(presentStates);
        ylabel(plotNames{vv});
        title(['QC by state: ' plotNames{vv}]);
        xtickangle(20)
    end
end

%% Activity budget
labels = ["surface_active","resting","traveling","foraging","exploring"];
valid = tagon & ~isnan(state);
totalValid = sum(valid);
pct = zeros(1,5);

if totalValid > 0
    for ss = 1:5
        pct(ss) = 100 * sum(state(valid) == ss) / totalValid;
    end
else
    warning('No valid (tagon) samples found.');
end

budgetT = table(labels', pct', 'VariableNames', {'State','Percent'});
budgetT.depID = repmat(string(depID), height(budgetT), 1);
budgetT = movevars(budgetT, 'depID', 'Before', 'State');
disp(budgetT);
writetable(budgetT, fullfile(fileloc, [whaleName '_AutoActivityBudget.csv']));

%% Activity budget figure
if MAKE_ACTIVITY_FIGURE
    tagOnHours = NaN;
    if any(tagon)
        tagOnHours = sum(tagon)/fs/3600;
    end

    fig = figure('Color','w','Units','normalized','Position',[0.2 0.2 0.45 0.55]);
    axPie = axes('Parent', fig);
    axPie.Position = [0.12 0.22 0.76 0.66];

    % For visualization, split resting into surface and subsurface components.
    % The CSV above keeps the original 5-state budget; this pie simply shows
    % where resting occurred relative to the 5 m dive threshold.
    pieLabels = ["surface active","surface resting","subsurface resting", ...
        "traveling","foraging","exploring"];
    piePct = zeros(1,6);
    if totalValid > 0
        surfaceRestPie = valid & state == 2 & p <= DIVE_THRESH_M;
        subsurfaceRestPie = valid & state == 2 & p > DIVE_THRESH_M;

        piePct(1) = 100 * sum(valid & state == 1) / totalValid;
        piePct(2) = 100 * sum(surfaceRestPie) / totalValid;
        piePct(3) = 100 * sum(subsurfaceRestPie) / totalValid;
        piePct(4) = 100 * sum(valid & state == 3) / totalValid;
        piePct(5) = 100 * sum(valid & state == 4) / totalValid;
        piePct(6) = 100 * sum(valid & state == 5) / totalValid;
    end

    pieColors = [
        0.34 0.71 0.91;   % surface active
        0.43 0.38 0.78;   % surface resting = lighter purple
        0.25 0.20 0.65;   % subsurface resting = darker purple
        0.80 0.47 0.65;   % traveling
        0.50 0.78 0.35;   % foraging
        0.95 0.90 0.20    % exploring
    ];

    plotSlices = find(piePct > 0);
    if ~isempty(plotSlices)
        h = pie(axPie, piePct(plotSlices));
        title(axPie, 'Activity budget', 'FontWeight', 'bold');

        % pie() returns patch/text handles in plotting order, so color slices
        % directly by plotSlices. Using findobj can reverse/scramble the order.
        patchHandles = h(arrayfun(@(hh) strcmp(get(hh, 'Type'), 'patch'), h));
        for k = 1:min(numel(patchHandles), numel(plotSlices))
            thisSlice = plotSlices(k);
            patchHandles(k).FaceColor = pieColors(thisSlice,:);
            if thisSlice == 2 || thisSlice == 3
                patchHandles(k).EdgeColor = [0.15 0.12 0.40];
                patchHandles(k).LineStyle = ':';
                patchHandles(k).LineWidth = 1.5;
            end
        end

        legtxt = strings(1,numel(plotSlices));
        for k = 1:numel(plotSlices)
            ss = plotSlices(k);
            legtxt(k) = sprintf('%s (%.1f%%)', pieLabels(ss), piePct(ss));
        end
        legend(axPie, legtxt, 'Location', 'southoutside');
    else
        text(axPie, 0.5, 0.5, 'No classified behavior', ...
            'HorizontalAlignment', 'center', ...
            'FontWeight', 'bold');
        axis(axPie, 'off');
    end

    metaLines = {};
    if exist('INFO','var')
        if isfield(INFO,'whaleName')
            metaLines{end+1} = sprintf('Whale: %s', INFO.whaleName);
        end
        if isfield(INFO,'tagID')
            metaLines{end+1} = sprintf('Tag: %s', INFO.tagID);
        end
    end
    if ~isempty(DN)
        metaLines{end+1} = sprintf('Start: %s', datestr(min(DN),'yyyy-mm-dd HH:MM'));
        metaLines{end+1} = sprintf('End: %s', datestr(max(DN),'yyyy-mm-dd HH:MM'));
    end
    if isfinite(tagOnHours)
        metaLines{end+1} = sprintf('Tag-on time: %.2f hours', tagOnHours);
    end

    if ~isempty(metaLines)
        annotation(fig,'textbox',[0.08 0.03 0.84 0.08], ...
            'String', strjoin(metaLines,'   |   '), ...
            'EdgeColor', 'none', ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 10);
    end
end

%% Plot auto-classified behavior with navigation
if MAKE_INTERACTIVE_PLOT
if ~exist('progressIndex','var') || isempty(progressIndex)
    progressIndex = find(tagon,1);
end

i = progressIndex;
windowMin = M;
while true
    windowSamples = max(1, round(windowMin * 60 * fs));
    searchStart = min(length(p), i + windowSamples);

    if searchStart < length(p)
        relEnd = find(p(searchStart:end) < 10, 1, 'first');
    else
        relEnd = [];
    end

    if isempty(relEnd) || isnan(relEnd)
        e = min(length(p), i + windowSamples);
    else
        e = min(length(p), searchStart + relEnd - 1);
    end

    I = max(i-60*fs, 1):e;
    tagonI = false(size(p));
    tagonI(I) = true;
    tagonI = tagon & tagonI;

    figure(101); clf

    subplot(3,1,1);
    [ax1,~,hJ] = plotyy(DN(I), p(I), DN(I), J(I));
    set(ax1(1), 'ydir', 'rev', 'nextplot', 'add', 'ylim', [-5 max(p(tagonI))]);
    set(ax1(2), 'ycolor', 'm', 'ylim', [0 1.2*max(J(tagonI))]);
    set(hJ, 'color', 'm');

    ylabel(ax1(1), 'Depth');
    ylabel(ax1(2), 'Jerk');
    set(ax1, 'xlim', [DN(I(1)) DN(I(end))]);
    hold(ax1(1), 'on')

    stateNames = {'Surface active','Resting','Traveling','Foraging','Exploring'};
    yl = get(ax1(1), 'ylim');

    for k = 1:length(autoStartI)
        thisState = autoState(k);
        if isnan(thisState)
            continue
        end

        thisState = round(thisState);
        if thisState < 1 || thisState > size(stateColors,1)
            continue
        end

        if autoEndI(k) < I(1) || autoStartI(k) > I(end)
            continue
        end

        sI = max(autoStartI(k), I(1));
        eI = min(autoEndI(k), I(end));

        patch(ax1(1), [DN(sI) DN(eI) DN(eI) DN(sI)], ...
            [yl(1) yl(1) yl(2) yl(2)], ...
            stateColors(thisState,:), ...
            'FaceAlpha', 0.18, ...
            'EdgeColor', 'none');
    end

    if ~isempty(L)
        colors = 'rbk';
        for c = 1:3
            II = find(LC == c);
            if ~isempty(II)
                plot(ax1(1), L(II), p(LI(II)), [colors(c) 's'], ...
                    'markerfacecolor', colors(c));
            end
        end
    end

    plotLegendStates = presentStates;
    hStateLegend = gobjects(numel(plotLegendStates),1);
    for ii = 1:numel(plotLegendStates)
        ss = plotLegendStates(ii);
        hStateLegend(ii) = plot(ax1(1), NaN, NaN, 's', ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', stateColors(ss,:), ...
            'MarkerEdgeColor', stateColors(ss,:));
    end
    if ~isempty(hStateLegend)
        legend(ax1(1), hStateLegend, stateNames(plotLegendStates), 'Location', 'eastoutside', 'FontSize', 8);
    end

    uistack(findobj(ax1(1), 'Type', 'line'), 'top')
    set(ax1(1), 'xticklabel', datestr(get(ax1(1), 'xtick'), 'mm/dd HH:MM:SS'));
    set(ax1(2), 'xticklabel', datestr(get(ax1(2), 'xtick'), 'mm/dd HH:MM:SS'));
    title(baseName, 'Interpreter', 'none');

    subplot(3,1,2);
    [ax2,hPitch,hRoll] = plotyy(DN(I), pitch(I)*180/pi, DN(I), roll(I)*180/pi);
    set(ax2(1), 'nextplot', 'add', 'ycolor', 'g', 'ylim', [-90 90]);
    set(ax2(2), 'nextplot', 'add', 'ycolor', 'k', 'ylim', [-180 180]);

    ylabel(ax2(1), 'Pitch');
    ylabel(ax2(2), 'Roll / Head');

    set(hPitch, 'color', 'g');
    set(hRoll,  'color', 'r', 'linestyle', '-');
    plot(ax2(2), DN(I), head(I)*180/pi, 'b.', 'markersize', 4);
    set(ax2, 'xlim', [DN(I(1)) DN(I(end))]);

    if ~isempty(L)
        colors = 'rbk';
        for c = 1:3
            II = find(LC == c);
            if ~isempty(II)
                plot(ax2(1), L(II), pitch(LI(II))*180/pi, [colors(c) 's'], ...
                    'markerfacecolor', colors(c));
            end
        end
    end

    set(ax2(1), 'xticklabel', datestr(get(ax2(1), 'xtick'), 'HH:MM:SS'));
    set(ax2(2), 'xticklabel', datestr(get(ax2(2), 'xtick'), 'HH:MM:SS'));

    s3 = subplot(3,1,3);
    hold(s3, 'on')

    if exist('speedJJ','var') && any(isfinite(speedJJ(I)))
        plot(s3, DN(I), speedJJ(I), 'b');
    else
        plot(s3, DN(I), mov(I), 'b');
    end

    if exist('speedFN','var') && any(isfinite(speedFN(I)))
        plot(s3, DN(I), speedFN(I), 'g');
    end

    if ~isempty(L)
        colors = 'rbk';
        for c = 1:3
            II = find(LC == c);
            if ~isempty(II)
                plot(s3, L(II), speedJJ(LI(II)), [colors(c) 's'], ...
                    'markerfacecolor', colors(c));
            end
        end
    end

    mx = max(speedJJ(tagonI), [], 'omitnan');
    if isempty(mx) || ~isfinite(mx) || mx <= 0
        mx = max(speedJJ(I), [], 'omitnan');
    end
    if isempty(mx) || ~isfinite(mx) || mx <= 0
        mx = 1;
    end

    set(s3, 'ylim', [0 1.1*mx], 'xlim', [DN(I(1)) DN(I(end))]);
    set(s3, 'xticklabel', datestr(get(s3, 'xtick'), 'HH:MM:SS'));
    ylabel(s3, 'Speed');
    hold(s3, 'off')

    linkaxes([ax1(1), ax2(1), s3], 'x');

    xl = xlim(ax1(1));
    hold(ax1(1), 'on');
    hCursor1 = plot(ax1(1), [xl(1) xl(1)], ylim(ax1(1)), 'k--', 'LineWidth', 1);
    hold(ax2(1), 'on');
    hCursor2 = plot(ax2(1), [xl(1) xl(1)], ylim(ax2(1)), 'k--', 'LineWidth', 1);
    hold(s3, 'on');
    hCursor3 = plot(s3, [xl(1) xl(1)], ylim(s3), 'k--', 'LineWidth', 1);
    yl1 = ylim(ax1(1));
    hBoutLabel = text(ax1(1), xl(1), yl1(1) + 0.06 * (yl1(2) - yl1(1)), '', ...
        'FontWeight', 'bold', ...
        'Color', 'k', ...
        'BackgroundColor', 'w', ...
        'Margin', 4, ...
        'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'left', ...
        'Clipping', 'on');
    hStatsBox = annotation(gcf, 'textbox', [0.84 0.18 0.15 0.34], ...
        'String', '', ...
        'FitBoxToText', 'off', ...
        'EdgeColor', [0.6 0.6 0.6], ...
        'BackgroundColor', 'w', ...
        'FontSize', 8, ...
        'Interpreter', 'none');

    uistack(hCursor1, 'bottom');
    uistack(hCursor2, 'bottom');
    uistack(hCursor3, 'bottom');

    set(gcf, 'WindowButtonMotionFcn', ...
        @(src,evt) updateVerticalCursor(src, ax1(1), ax2(1), s3, hCursor1, hCursor2, hCursor3, ...
        hBoutLabel, hStatsBox, DN, autoStartI, autoEndI, autoState, stateNames, ...
        p, speedTrace, J, pitch, roll, head, turnRateS));

    drawnow;

    pos1 = get(ax1(1), 'Position');
    pos2 = get(ax2(1), 'Position');
    pos3 = get(s3,    'Position');
    newLeft  = pos3(1);
    newWidth = pos3(3);

    set(ax1(1), 'Position', [newLeft pos1(2) newWidth pos1(4)]);
    set(ax1(2), 'Position', [newLeft pos1(2) newWidth pos1(4)]);
    set(ax2(1), 'Position', [newLeft pos2(2) newWidth pos2(4)]);
    set(ax2(2), 'Position', [newLeft pos2(2) newWidth pos2(4)]);
    set(s3,     'Position', [newLeft pos3(2) newWidth pos3(4)]);

    fprintf(['ENTER = forward window | b = back window | rightarrow = +1 hour | leftarrow = -1 hour | ' ...
        'uparrow = zoom out | downarrow = zoom in | q = quit | window = %.1f min\n'], windowMin);

    wasKey = waitforbuttonpress;
    if wasKey
        key = get(gcf, 'CurrentKey');
        switch key
            case {'return','enter'}
                i = e;
            case 'b'
                i = max(1, i - windowSamples);
            case 'rightarrow'
                i = min(length(p), i + round(3600 * fs));
            case 'leftarrow'
                i = max(1, i - round(3600 * fs));
            case 'uparrow'
                windowMin = min(120, windowMin * 2);
            case 'downarrow'
                windowMin = max(2, windowMin / 2);
            case 'q'
                progressIndex = i; %#ok<NASGU>
                break
        end
    end
end
end

function updateVerticalCursor(fig, axTop, axMid, axBot, h1, h2, h3, hLabel, hStatsBox, DN, autoStartI, autoEndI, autoState, stateNames, p, speedTrace, J, pitch, roll, head, turnRateS)
    obj = hittest(fig);
    if isempty(obj) || ~isgraphics(obj)
        return
    end

    ax = ancestor(obj, 'axes');
    if isempty(ax) || ~ismember(ax, [axTop, axMid, axBot])
        return
    end

    cp = get(ax, 'CurrentPoint');
    x = cp(1,1);
    xl = xlim(axTop);

    if x < xl(1) || x > xl(2)
        return
    end

    set(h1, 'XData', [x x], 'YData', ylim(axTop));
    set(h2, 'XData', [x x], 'YData', ylim(axMid));
    set(h3, 'XData', [x x], 'YData', ylim(axBot));

    if isempty(DN) || isempty(autoStartI)
        set(hLabel, 'String', '', 'Position', [x ylim(axTop(1)) 0]);
        set(hStatsBox, 'String', '');
        return
    end

    [~, idx] = min(abs(DN - x));
    boutK = find(autoStartI <= idx & autoEndI >= idx, 1, 'first');

    yl = ylim(axTop);
    yText = yl(1) + 0.06 * (yl(2) - yl(1));

    if isempty(boutK)
        set(hLabel, 'String', '', 'Position', [x yText 0]);
        stateStr = 'n/a';
    else
        thisState = autoState(boutK);
        if isfinite(thisState) && thisState >= 1 && thisState <= numel(stateNames)
            labelStr = sprintf('Bout %d | %s', boutK, stateNames{thisState});
            stateStr = stateNames{thisState};
        else
            labelStr = sprintf('Bout %d', boutK);
            stateStr = 'n/a';
        end
        set(hLabel, 'String', labelStr, 'Position', [x yText 0]);
    end

    timeStr = datestr(DN(idx), 'mm/dd HH:MM:SS.FFF');
    depthVal = p(idx);
    speedVal = speedTrace(idx);
    jerkVal = J(idx);
    pitchVal = pitch(idx) * 180/pi;
    rollVal = roll(idx) * 180/pi;
    headVal = head(idx) * 180/pi;
    turnVal = turnRateS(idx);

    if isempty(boutK)
        boutStr = 'n/a';
    else
        boutStr = sprintf('%d', boutK);
    end

    statsStr = sprintf(['Time: %s\n' ...
        'Index: %d\n' ...
        'Bout: %s\n' ...
        'State: %s\n' ...
        'Depth: %.2f m\n' ...
        'Speed: %.2f\n' ...
        'Jerk: %.2f\n' ...
        'Pitch: %.1f deg\n' ...
        'Roll: %.1f deg\n' ...
        'Head: %.1f deg\n' ...
        'Turn: %.1f deg/s'], ...
        timeStr, idx, boutStr, stateStr, depthVal, speedVal, jerkVal, ...
        pitchVal, rollVal, headVal, turnVal);
    set(hStatsBox, 'String', statsStr);
end

function [LungeI, LungeDN, LungeTimeAlt] = extract_lunge_fields_from_loaded_mat(tmp)
% Extract lunge index/time vectors from a loaded .mat struct.
% Checks top-level fields first, then looks one level down into any scalar
% struct fields, which is common in older lunge files.

LungeI = [];
LungeDN = [];
LungeTimeAlt = [];

if isfield(tmp,'LungeI') && ~isempty(tmp.LungeI), LungeI = tmp.LungeI(:); end
if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), LungeDN = tmp.LungeDN(:); end
if isempty(LungeI) && isfield(tmp,'LI') && ~isempty(tmp.LI), LungeI = tmp.LI(:); end
if isempty(LungeDN) && isfield(tmp,'time') && ~isempty(tmp.time), LungeDN = tmp.time(:); end
if isempty(LungeDN) && isfield(tmp,'L') && ~isempty(tmp.L), LungeTimeAlt = tmp.L(:); end

if ~isempty(LungeI) || ~isempty(LungeDN) || ~isempty(LungeTimeAlt)
    return
end

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
