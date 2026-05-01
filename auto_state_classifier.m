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
% - Deep dives containing a lunge are classified as foraging for the full dive
% - Shallow lunges (shallower than 5 m) are classified as foraging within a +/-30 s buffer
% - Each dive keeps its assigned state for 20 s after surfacing
% - Remaining surface intervals are classified as resting or surface active
% - Resting requires low speed, low pitch variability, low movement, and a minimum bout duration
% - Non-foraging dives are classified as resting, traveling, or exploring
%
% =========================================================
% VERSION: 2026-04-19
% Auto state classifier v3 (5-state hybrid, no recovery)
% Foraging logic distinguishes deep-dive vs shallow buffered foraging
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
clear;

atLast = true; %#ok<NASGU>
M = 10; % number of minutes to display per window

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
[filename,fileloc] = uigetfile('*.mat', 'Select the PRH file to analyze');
cd(fileloc);

disp('Loading Data, will take some time');
load(fullfile(fileloc, filename));

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
useSubfolders = false;

if useSubfolders
    cand = dir(fullfile(searchRoot, '**', ['*' depID '*lunges.mat']));
else
    cand = dir(fullfile(searchRoot, ['*' depID '*lunges.mat']));
end
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
        if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN; end
        if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time; end

        if isempty(t) && isfield(tmp,'LungeI') && ~isempty(tmp.LungeI)
            ii = tmp.LungeI(:);
            ii = ii(ii >= 1 & ii <= numel(DN));
            if ~isempty(ii), t = DN(ii); end
        end

        if isempty(t) && isfield(tmp,'LI') && ~isempty(tmp.LI)
            ii = tmp.LI(:);
            ii = ii(ii >= 1 & ii <= numel(DN));
            if ~isempty(ii), t = DN(ii); end
        end

        if isempty(t) && isfield(tmp,'L') && ~isempty(tmp.L)
            t = tmp.L;
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
        if nIn == 0
            score = score - 1;
        end

        if score > bestScore
            bestScore = score;
            bestFile = f;
        end
    end

    if isempty(bestFile)
        warning('Lunge files exist but none had usable timing. Proceeding with NO LUNGES.');
    else
        fprintf('\nSelected lunges file (best time overlap):\n%s\nScore=%.3f\n\n', bestFile, bestScore);
    end
end

if ~isempty(bestFile) && isfile(bestFile)
    tmp = load(bestFile);
    disp('Lunge file variables:');
    disp(fieldnames(tmp));

    if isfield(tmp,'LungeI'),  LungeI  = tmp.LungeI(:);  end
    if isfield(tmp,'LungeDN'), LungeDN = tmp.LungeDN(:); end
    if isfield(tmp,'LungeC'),  LungeC  = tmp.LungeC(:);  end

    if isempty(LungeI) && isfield(tmp,'LI'),    LungeI  = tmp.LI(:); end
    if isempty(LungeDN) && isfield(tmp,'time'), LungeDN = tmp.time(:); end

    if ~isempty(LungeDN)
        LI = nan(size(LungeDN));
        for j = 1:numel(LungeDN)
            [~,LI(j)] = min(abs(DN - LungeDN(j)));
        end
        LI = LI(:);
    elseif ~isempty(LungeI)
        LI = LungeI(:);
    else
        LI = [];
    end

    LI = LI(LI>=1 & LI<=numel(p));

    if ~isempty(LungeDN)
        L = LungeDN(:);
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
MIN_DIVE_DUR_S             = 0;
FORAGE_BUFFER_SHALLOW_S    = 30;
POST_DIVE_EXT_S            = 20;
REST_SPEED_MAX_MPS         = 2.0;
REST_MIN_BOUT_S            = 30;
MOV_SMOOTH_S               = 10;
PITCH_VAR_WIN_S            = 10;
REST_MOV_PCTL              = 30;
REST_PITCHVAR_PCTL         = 30;
TRAVEL_SPEED_MIN_MPS       = 1.5;
TRAVEL_TURNRATE_MAX_DEGPS  = 35;
TRAVEL_MAX_DEPTH_M         = 50;
TRAVEL_MAX_DEPTH_M         = 50;
SUBSURFACE_REST_FRAC       = 0.8;

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
nDives = numel(diveStarts);

inDive = false(N,1);
for di = 1:nDives
    inDive(diveStarts(di):diveStops(di)) = true;
end

deepForageMask    = false(N,1);
shallowForageMask = false(N,1);
forageMask        = false(N,1);

forageBufferN = round(FORAGE_BUFFER_SHALLOW_S * fs);
if ~isempty(LI)
    for ii = 1:numel(LI)
        li = LI(ii);
        if inDive(li)
            di = find(diveStarts <= li & diveStops >= li, 1, 'first');
            if ~isempty(di)
                deepForageMask(diveStarts(di):diveStops(di)) = true;
            end
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

postDiveN = round(POST_DIVE_EXT_S * fs);
postDiveWindowMask = false(N,1);
for di = 1:nDives
    a = diveStops(di) + 1;
    b = min(N, diveStops(di) + postDiveN);

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
else
    lowMovThresh = nanmedian(movS);
    lowPitchVarThresh = nanmedian(pitchVar);
end

fprintf('Rest threshold reference minutes: %.2f\n', sum(refMask)/fs/60);
fprintf('Rest movement threshold (p%d): %.4f\n', REST_MOV_PCTL, lowMovThresh);
fprintf('Rest pitch-var threshold (p%d): %.4f deg\n', REST_PITCHVAR_PCTL, lowPitchVarThresh);
lowMov   = isfinite(movS) & movS <= lowMovThresh;
lowPitch = isfinite(pitchVar) & pitchVar <= lowPitchVarThresh;

restCandidate = tagon & ~forageMask & lowSpeed & lowMov & lowPitch;
restMaskBase = false(N,1);
minRestN = max(1, round(REST_MIN_BOUT_S * fs));
dr = diff([false; restCandidate; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;
for k = 1:numel(rs)
    if (re(k) - rs(k) + 1) >= minRestN
        restMaskBase(rs(k):re(k)) = true;
    end
end

travelMask   = false(N,1);
exploreMask  = false(N,1);
restDiveMask = false(N,1);
diveState    = nan(nDives,1);

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    if any(forageMask(a:b))
        diveState(di) = 4;
        continue
    end

    fracRest = mean(restMaskBase(a:b), 'omitnan');
    meanSpd  = mean(speedTrace(a:b), 'omitnan');
    meanTurnRate = mean(turnRateS(a:b), 'omitnan');
    maxDiveDepth = max(p(a:b), [], 'omitnan');

    if fracRest >= SUBSURFACE_REST_FRAC && meanSpd <= REST_SPEED_MAX_MPS
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
    extA = diveStops(di) + 1;
    extB = min(N, diveStops(di) + postDiveN);

    if extA > N || extA > extB
        continue
    end

    nextDiveStart = inf;
    if di < nDives
        nextDiveStart = diveStarts(di+1);
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

surfaceRemainder = tagon & ~inDive & ~postDiveCarryMask & ~forageMask;
restMaskSurface = false(N,1);
surfaceActiveMask = false(N,1);

surfaceRestCandidate = surfaceRemainder & lowSpeed & lowMov & lowPitch;
dr = diff([false; surfaceRestCandidate; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;
for k = 1:numel(rs)
    if (re(k) - rs(k) + 1) >= minRestN
        restMaskSurface(rs(k):re(k)) = true;
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

%% Save binary/context variables for later analyses
isSurface        = tagon & ~inDive;
isSubsurface     = tagon & inDive;
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
    a = diveStarts(di);
    b = diveStops(di);

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

sampleSummaryByState = table( ...
    strings(5,1), nan(5,1), ...
    nan(5,1), nan(5,1), nan(5,1), ...
    nan(5,1), nan(5,1), nan(5,1), ...
    nan(5,1), nan(5,1), nan(5,1), ...
    nan(5,1), nan(5,1), nan(5,1), ...
    nan(5,1), nan(5,1), nan(5,1), ...
    'VariableNames', { ...
    'State','nSamples', ...
    'speed_mean','speed_sd','speed_median', ...
    'mov_mean','mov_sd','mov_median', ...
    'pitchVar_mean','pitchVar_sd','pitchVar_median', ...
    'turnRate_mean','turnRate_sd','turnRate_median', ...
    'depth_mean','depth_sd','depth_median'});

sampleSummaryByState.State = string(stateNames(:));

for ss = 1:5
    idx = tagon & (state == ss);

    sp = speedTrace(idx);
    mv = movS(idx);
    pv = pitchVar(idx);
    tv = turnRateS(idx);
    dp = p(idx);

    sampleSummaryByState.nSamples(ss) = sum(idx);

    sampleSummaryByState.speed_mean(ss)   = mean(sp, 'omitnan');
    sampleSummaryByState.speed_sd(ss)     = std(sp, 'omitnan');
    sampleSummaryByState.speed_median(ss) = median(sp, 'omitnan');

    sampleSummaryByState.mov_mean(ss)     = mean(mv, 'omitnan');
    sampleSummaryByState.mov_sd(ss)       = std(mv, 'omitnan');
    sampleSummaryByState.mov_median(ss)   = median(mv, 'omitnan');

    sampleSummaryByState.pitchVar_mean(ss)   = mean(pv, 'omitnan');
    sampleSummaryByState.pitchVar_sd(ss)     = std(pv, 'omitnan');
    sampleSummaryByState.pitchVar_median(ss) = median(pv, 'omitnan');

    sampleSummaryByState.turnRate_mean(ss)   = mean(tv, 'omitnan');
    sampleSummaryByState.turnRate_sd(ss)     = std(tv, 'omitnan');
    sampleSummaryByState.turnRate_median(ss) = median(tv, 'omitnan');

    sampleSummaryByState.depth_mean(ss)   = mean(dp, 'omitnan');
    sampleSummaryByState.depth_sd(ss)     = std(dp, 'omitnan');
    sampleSummaryByState.depth_median(ss) = median(dp, 'omitnan');
end

disp('=== SAMPLE-LEVEL STATE SUMMARY ===')
disp(sampleSummaryByState)

boutDur_s = (autoEndI - autoStartI + 1) / fs;
boutSummaryByState = table( ...
    strings(5,1), nan(5,1), nan(5,1), nan(5,1), nan(5,1), ...
    'VariableNames', {'State','nBouts','dur_mean_s','dur_sd_s','dur_median_s'});
boutSummaryByState.State = string(stateNames(:));

for ss = 1:5
    d = boutDur_s(autoState == ss);
    boutSummaryByState.nBouts(ss)       = numel(d);
    boutSummaryByState.dur_mean_s(ss)   = mean(d, 'omitnan');
    boutSummaryByState.dur_sd_s(ss)     = std(d, 'omitnan');
    boutSummaryByState.dur_median_s(ss) = median(d, 'omitnan');
end

disp('=== BOUT-LEVEL DURATION SUMMARY ===')
disp(boutSummaryByState)

writetable(sampleSummaryByState, fullfile(fileloc, [whaleName '_StateSampleSummary.csv']));
writetable(boutSummaryByState, fullfile(fileloc, [whaleName '_StateBoutSummary.csv']));

plotVals = {speedTrace, movS, pitchVar, turnRateS, p};
plotNames = {'Speed','Movement','Pitch variability','Turn rate (deg/s)','Depth'};

for vv = 1:numel(plotVals)
    vals = plotVals{vv};
    validPlot = tagon & ~isnan(state) & isfinite(vals);
    if ~any(validPlot)
        continue
    end

    figure('Color','w');
    boxplot(vals(validPlot), state(validPlot), 'Labels', stateNames);
    ylabel(plotNames{vv});
    title(['QC by state: ' plotNames{vv}]);
    xtickangle(20)
end

%% Activity budget
labels = ["surface_active","resting","traveling","foraging","exploring"];
valid = tagon & ~isnan(state);
totalValid = sum(valid);
pct = nan(1,5);

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
figLabels = ["surface active","resting","traveling","foraging","exploring"];
tagOnHours = NaN;
if any(tagon)
    tagOnHours = sum(tagon)/fs/3600;
end

fig = figure('Color','w','Units','normalized','Position',[0.2 0.2 0.45 0.55]);
axPie = axes('Parent', fig);
axPie.Position = [0.12 0.22 0.76 0.66];

stateColors = [
    0.34 0.71 0.91;
    0.25 0.20 0.65;
    0.80 0.47 0.65;
    0.50 0.78 0.35;
    0.95 0.90 0.20
];

h = pie(axPie, pct);
title(axPie, 'Activity budget', 'FontWeight', 'bold');

patchHandles = findobj(h, 'Type', 'Patch');
patchHandles = flipud(patchHandles);
for k = 1:min(numel(patchHandles), size(stateColors,1))
    patchHandles(k).FaceColor = stateColors(k,:);
end

legtxt = strings(1,numel(figLabels));
for k = 1:numel(figLabels)
    legtxt(k) = sprintf('%s (%.1f%%)', figLabels(k), pct(k));
end
legend(axPie, legtxt, 'Location', 'southoutside');

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

%% Plot auto-classified behavior with navigation
if ~exist('progressIndex','var') || isempty(progressIndex)
    progressIndex = find(tagon,1);
end

i = progressIndex;
while true
    e = min(find(p(i+M*60*fs:end) < 10, 1, 'first') + i + (M+1)*60*fs - 1, length(p));
    if isempty(e) || isnan(e)
        e = length(p);
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

    hStateLegend = gobjects(5,1);
    for ss = 1:5
        hStateLegend(ss) = plot(ax1(1), NaN, NaN, 's', ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', stateColors(ss,:), ...
            'MarkerEdgeColor', stateColors(ss,:));
    end
    legend(ax1(1), hStateLegend, stateNames, 'Location', 'eastoutside', 'FontSize', 8);

    uistack(findobj(ax1(1), 'Type', 'line'), 'top')
    set(ax1(1), 'xticklabel', datestr(get(ax1(1), 'xtick'), 'mm/dd HH:MM:SS'));
    set(ax1(2), 'xticklabel', datestr(get(ax1(2), 'xtick'), 'mm/dd HH:MM:SS'));
    title(filename(1:end-11));

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

    fprintf('ENTER = forward | b = back | q = quit\n');

    wasKey = waitforbuttonpress;
    if wasKey
        key = get(gcf, 'CurrentCharacter');
        switch key
            case char(13)
                i = e;
            case 'b'
                i = max(1, i - M*60*fs);
            case 'q'
                progressIndex = i; %#ok<NASGU>
                break
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
