% Identify behavioral states and create an activity budget for a tag deployment
%
% Behavioral states:
%   1 = recovery
%   2 = surface active
%   3 = resting
%   4 = traveling
%   5 = foraging
%   6 = exploring
%
% Classification framework:
% - Deep dives containing a lunge are classified as foraging for the full dive
% - Shallow lunges (shallower than 5 m) are classified as foraging within a ±30 s buffer
% - Surface intervals are classified as recovery, resting, or surface active
% - Non-foraging dives are classified as resting, traveling, or exploring
%
% =========================================================
% VERSION: 2026-04-17
% Auto state classifier v2 (6-state hybrid)
% Foraging logic updated to distinguish deep-dive vs shallow buffered foraging
% Surface state classification updated using bout-based rules
% Resting retained as both a surface and subsurface low-energy state
%
% Lauren Fritz
% University of California Santa Cruz
% =========================================================
%
% Input:
%   - 5 Hz (DTAG) or 10 Hz (CATS) PRH .mat file
%
% Outputs:
%   Section 2:
%       - Lunge .mat file
%       - Behavior state .mat file
%       - Activity budget figure
%   Section 3:
%       - Error check variable and command window report for behavior states
%       - Returns indices and description of suspected errors
%   Section 4:
%       - Behavior state .xlsx file
%   Section 5:
%       - Behavior state .xlsx file with durations (if all behaviors have start and finish) 

%% 1. Load Data
clear; % clears the workspace

% Start where you left off?
atLast = true; % this will look for a variable called progressIndex
M = 10; % number of minutes to display per window

% Variables that will be saved in the Lunge file
notes = '';
creator = 'DEC';
primary_cue = 'speedJJ';

% State labels
manualStates = {'resting','traveling','foraging','exploring'};
autoStates   = {'recovery','surface active','resting','traveling','foraging','exploring'};

try
    drive = 'CATS'; % name of drive where files are located
    folder = 'CATS/CATS/tag_analysis/data_processed'; %#ok<NASGU>
    a = getdrives;
    for i = 1:length(a)
        [~,vol] = system(['vol ' a{i}(1) ':']);
        if strfind(vol, drive) %#ok<STREMP>
            vol = a{i}(1);
            break
        end
    end
catch
end

cf = pwd; %#ok<NASGU>
[filename,fileloc] = uigetfile('*.mat', 'Select the PRH file to analyze');
cd(fileloc);

disp('Loading Data, will take some time');
load(fullfile(fileloc, filename));   % loads PRH variables

% --- Standardize sampling rate ---
if exist('fs','var') && ~isempty(fs)
    fs = fs;
elseif exist('fs1','var') && ~isempty(fs1)
    fs = fs1;
else
    error('No sampling rate found in loaded PRH file (expected fs or fs1).');
end

fprintf('Sampling rate: %.2f Hz\n', fs);

% --- Speed diagnostics ---
if exist('speed','var') && isstruct(speed)
    disp(fieldnames(speed))
    if isfield(speed,'JJ')
        fprintf('speed.JJ finite count: %d\n', sum(isfinite(speed.JJ(:))));
    end
    if isfield(speed,'FN')
        fprintf('speed.FN finite count: %d\n', sum(isfinite(speed.FN(:))));
    end
end

%% ---- Build speedJJ and speedFN (Dave Cade style, struct OR table) ----
% Ensure vectors are columns
p = p(:);
DN = DN(:);
tagon = tagon(:);

speedJJ = nan(size(p));
speedFN = nan(size(p));

if exist('speed','var') && ~isempty(speed)

    % ---------- speed stored as TABLE ----------
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

    % ---------- speed stored as STRUCT ----------
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
% ---- Jerk proxy (use njerk if you have it, else diff fallback) ----
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

% Match lengths
J = J(:);
if numel(J) < numel(p), J(end+1:numel(p)) = J(end); end
if numel(J) > numel(p), J = J(1:numel(p)); end

% ---- Movement proxy used by AUTO classifier ----
mov = speedJJ;
if all(isnan(mov))
    mov = J;
end

% baseName for matching lunge file
[~, baseName, ~] = fileparts(filename);

%% ---- Load lunges file (single robust block) ----
% If none found / none usable, proceed with LI=[] (no lunges)
LungeI = [];
LungeDN = [];
LungeC = [];
LI = [];
L = [];
LC = [];

depID = regexp(baseName,'^[^ ]+','match','once');

% ---- Define whaleName robustly (used for outputs) ----
whaleName = depID;  % default fallback

if exist('INFO','var') && isstruct(INFO) && isfield(INFO,'whaleName') && ~isempty(INFO.whaleName)
    whaleName = INFO.whaleName;
end

whaleName = regexprep(whaleName, '[^\w\-]+', '_');

searchRoot = fileloc;     % same folder as PRH
useSubfolders = false;    % set true if lunges may be deeper in subfolders

if useSubfolders
    cand = dir(fullfile(searchRoot, '**', ['*' depID '*lunges.mat']));
else
    cand = dir(fullfile(searchRoot, ['*' depID '*lunges.mat']));
end
cand = cand(~startsWith({cand.name}, '._')); % remove mac metadata

bestFile = '';
bestScore = -Inf;

if isempty(cand)
    warning('No lunge files found for depID=%s. Proceeding with NO LUNGES.', depID);
else
    DNmin = min(DN);
    DNmax = max(DN);

    for k = 1:numel(cand)
        f = fullfile(cand(k).folder, cand(k).name);

        % load minimally
        tmp = load(f);

        % pull a time vector from common names (datenum-like)
        t = [];
        if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN; end
        if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time; end

        % If only indices exist, we can still use them (convert indices to DN later)
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
            continue; % can't score
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

%% Load lunges from selected file (if any)

if ~isempty(bestFile) && isfile(bestFile)

    tmp = load(bestFile);
    disp('Lunge file variables:');
    disp(fieldnames(tmp));

    if isfield(tmp,'LungeI'),  LungeI  = tmp.LungeI(:);  end
    if isfield(tmp,'LungeDN'), LungeDN = tmp.LungeDN(:); end
    if isfield(tmp,'LungeC'),  LungeC  = tmp.LungeC(:);  end

    if isempty(LungeI) && isfield(tmp,'LI'),   LungeI  = tmp.LI(:);   end
    if isempty(LungeDN) && isfield(tmp,'time'), LungeDN = tmp.time(:); end

    % Build LI (preferred) from LungeDN, else from LungeI
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

    % L = datenum timestamps for plotting
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

    else
    % keep initialized empty lunge variables
end

fprintf('FINAL lunges used: LI=%d\n', numel(LI));

%% ---- Load geoPtrack KML (same folder as PRH) ----
kmlLat = [];
kmlLon = [];

kmlFile = '';
candKML = dir(fullfile(fileloc, [depID '*geoPtrack.kml']));   % e.g., mn180227-40geoPtrack.kml
candKML = candKML(~startsWith({candKML.name}, '._'));         % remove mac metadata

if ~isempty(candKML)
    kmlFile = fullfile(candKML(1).folder, candKML(1).name);
    fprintf('Found geoPtrack KML: %s\n', kmlFile);

        try
        [kmlLat, kmlLon] = read_geoPtrack_kml_simple(kmlFile);
        catch ME
            warning('Failed to read KML file %s: %s', kmlFile, ME.message);
        end
else
    fprintf('No geoPtrack KML found for depID=%s in %s\n', depID, fileloc);
end

%% Auto State Classifier (v2, 6-state hybrid)

% ---- Initialize behavior-picker variables (needed for Section 2 plotting) ----
BehaviorState = [];        % current active state (1-4) or empty
BehaviorText  = '';        % text label for current state
Bcolors       = 'rgkc';    % 4 states: resting/traveling/foraging/exploring

% If no prior saved behavior audit exists, initialize empty vectors
if ~exist('behI','var');  behI  = []; end
if ~exist('behT','var');  behT  = []; end
if ~exist('behS','var');  behS  = []; end
if ~exist('behSS','var'); behSS = []; end

% ---------- USER DEFINITIONS ----------
% Foraging  = any segment containing >=1 detected lunge; if a lunge occurs
%             within a dive, the entire dive is classified as foraging.
% Resting   = low-energy behavior lasting at least REST_MIN_BOUT_S,
%             characterized by low movement and low speed, and not foraging.
% Traveling = non-foraging movement during dives that is not low-energy.
% Surface_active = non-resting surface intervals that are not classified as recovery.
% Exploring = non-foraging, non-resting dives that are not classified as traveling.

% ---------- PARAMETERS (EDIT HERE) ----------
DIVE_THRESH_M        = 5;      % dive if p > this (m)
MIN_DIVE_DUR_S       = 0;      % ignore tiny excursions as dives

% Resting / recovery knob:
% If you want "recovery counted as resting" -> set REST_MIN_BOUT_S = 0
% If you want only clear resting bouts       -> set REST_MIN_BOUT_S = 180 (or 300, etc.)
REST_MIN_BOUT_S      = 30;       % <<< THIS is where minRestDur_s comes from
REST_MOV_PCTL        = 45;      % low-movement threshold = this percentile of mov (on-animal)
REST_SMOOTH_S        = 10;      % smooth movement to reduce flicker

% ---------- MOVEMENT PROXY ----------
% Use speedJJ if available; fallback to J (jerk proxy)
mov = speedJJ;
if ~exist('mov','var') || isempty(mov) || all(~isfinite(mov))
    mov = J;
end

% ---------- ALIGN VECTORS (DEFENSIVE) ----------
p     = p(:);
DN    = DN(:);
tagon = tagon(:);
mov   = mov(:);

N = min([numel(p), numel(DN), numel(tagon), numel(mov)]);
p     = p(1:N);
DN    = DN(1:N);
tagon = tagon(1:N);
mov   = mov(1:N);

% ---------- LUNGE FILTER (Tyson et al.) ----------
% LI must exist from your lunge-loading block above
if exist('LI','var') && ~isempty(LI)
    LI = LI(:);
    LI = LI(LI>=1 & LI<=N);
else
    LI = [];
end

% ---------- 1) DIVE DETECTION ----------
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

% ---------- 2) FORAGING ----------
% Rule:
% - if a lunge occurs during a detected dive, classify the whole dive as foraging
% - if a lunge occurs outside a dive (shallow), classify a 30 s buffer around the lunge as foraging

deepForageMask    = false(N,1);
shallowForageMask = false(N,1);
forageMask        = false(N,1);

FORAGE_BUFFER_SHALLOW_S = 30;
forageBufferN = round(FORAGE_BUFFER_SHALLOW_S * fs);

if exist('LI','var') && ~isempty(LI)
    LI = LI(:);
    LI = LI(LI >= 1 & LI <= N);

    for ii = 1:numel(LI)
        li = LI(ii);

        % Case 1: lunge occurs during a detected dive
        if inDive(li)
            % find the dive containing this lunge
            di = find(diveStarts <= li & diveStops >= li, 1, 'first');

            if ~isempty(di)
                a = diveStarts(di);
                b = diveStops(di);
                deepForageMask(a:b) = true;
            end

        % Case 2: lunge occurs outside a dive (shallow)
        else
            a = max(1, li - forageBufferN);
            b = min(N, li + forageBufferN);
            shallowForageMask(a:b) = true;
        end
    end
end

% final combined foraging mask
forageMask = deepForageMask | shallowForageMask;

% optional diagnostics
fprintf('Deep-dive foraging minutes: %.2f\n', sum(deepForageMask & tagon)/fs/60);
fprintf('Shallow-buffer foraging minutes: %.2f\n', sum(shallowForageMask & tagon)/fs/60);
fprintf('Shallow-buffer samples outside dives: %d\n', nnz(shallowForageMask & ~inDive));
% ---------- LOW-ENERGY THRESHOLDS ----------
w = max(1, round(REST_SMOOTH_S * fs));
movS = mov;

if any(isfinite(movS))
    movFill = movS;
    movFill(~isfinite(movFill)) = prctile(movFill(isfinite(movFill)), 5);
    movS = runmean(movFill, w);
    movS(~isfinite(mov)) = nan;
end

valid = tagon & isfinite(movS);

lowMovThresh = prctile(movS(valid), REST_MOV_PCTL);

if exist('speedJJ','var') && any(isfinite(speedJJ))
    speed = speedJJ(:);
    lowSpeedThresh = prctile(speed(valid & isfinite(speed)), 25);
else
    speed = nan(size(movS));
    lowSpeedThresh = nan;
end

% ---------- 3) RESTING (LOW-ENERGY STATE) ----------
restMask = false(N,1);

lowEnergy = tagon ...
    & isfinite(movS) & (movS <= lowMovThresh) ...
    & (~isfinite(speed) | speed <= lowSpeedThresh);

% enforce minimum duration
minRestN = max(1, round(REST_MIN_BOUT_S * fs));

dr = diff([false; lowEnergy; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;

for k = 1:numel(rs)
    dur = re(k) - rs(k) + 1;
    if dur >= minRestN
        restMask(rs(k):re(k)) = true;
    end
end

% never override foraging
restMask(forageMask) = false;

% ---------- 4) DIVE STATES ----------
travelMask = false(N,1);
exploreMask = false(N,1);

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    % skip foraging dives
    if any(forageMask(a:b))
        continue
    end

    fracRest = mean(restMask(a:b), 'omitnan');
    meanMov  = mean(movS(a:b), 'omitnan');

    if exist('speed','var') && any(isfinite(speed(a:b)))
        meanSpd = mean(speed(a:b), 'omitnan');
    else
        meanSpd = nan;
    end

    % 1) traveling: directional / active non-foraging dive
    if (~isnan(meanSpd) && meanSpd > lowSpeedThresh * 1.2) || ...
       (~isnan(meanMov) && meanMov > lowMovThresh * 1.2)
        travelMask(a:b) = true;

    % 2) resting: mostly low-energy dive
    elseif fracRest >= 0.8 && (~isnan(meanSpd) && meanSpd < lowSpeedThresh)
        % clear previous assignment in this dive
        travelMask(a:b) = false;
        exploreMask(a:b) = false;
        restMask(a:b) = true;

    % 3) otherwise exploring
    else
        exploreMask(a:b) = true;
    end
end

% ---------- 5) SURFACE STATES (BOUT-BASED) ----------
% override any previous classification within surface bouts
surface = tagon & ~inDive;

RECOVERY_MAX_S = 20;
REST_SURFACE_MIN_S = 150;

recoveryMask      = false(N,1);
surfaceActiveMask = false(N,1);

% find contiguous surface bouts
dSurf = diff([false; surface; false]);
surfStarts = find(dSurf == 1);
surfStops  = find(dSurf == -1) - 1;

nSurfBouts = numel(surfStarts);

% optional summary variables for diagnostics
surfDur_s    = nan(nSurfBouts,1);
surfPrevDive = false(nSurfBouts,1);
surfLabel    = strings(nSurfBouts,1);

for si = 1:nSurfBouts
    a = surfStarts(si);
    b = surfStops(si);

    dur_s = (b - a + 1) / fs;
    surfDur_s(si) = dur_s;

    if a > 1
        surfPrevDive(si) = inDive(a-1);
    end

    fracRest = mean(restMask(a:b), 'omitnan');

    % clear surface region first
    restMask(a:b) = false;
    recoveryMask(a:b) = false;
    surfaceActiveMask(a:b) = false;

    % classify whole surface bout
    if dur_s < RECOVERY_MAX_S && surfPrevDive(si)
        recoveryMask(a:b) = true;
        surfLabel(si) = "recovery";

    elseif dur_s > REST_SURFACE_MIN_S || fracRest >= 0.3
        restMask(a:b) = true;
        surfLabel(si) = "resting";

    else
        surfaceActiveMask(a:b) = true;
        surfLabel(si) = "surface_active";
    end
end

% ---------- FINAL STATE VECTOR ----------
% priority enforced above via mask exclusion:
% foraging > resting > recovery > traveling > exploring > surface active

restMask(forageMask) = false;
recoveryMask(forageMask | restMask) = false;
travelMask(forageMask | restMask | recoveryMask) = false;
exploreMask(forageMask | restMask | recoveryMask | travelMask) = false;
surfaceActiveMask(forageMask | restMask | recoveryMask | travelMask | exploreMask) = false;

state = nan(N,1);

state(recoveryMask)      = 1;
state(surfaceActiveMask) = 2;
state(restMask)          = 3;
state(travelMask)        = 4;
state(forageMask)        = 5;
state(exploreMask)       = 6;

% ---------- BUILD DIVE-LEVEL VARIABLES FOR PLOTTING ----------

isForagingDive = false(nDives,1);
isTravelDive   = false(nDives,1);
isRestDive     = false(nDives,1);
isExploreDive  = false(nDives,1);
diveLungeCount = zeros(nDives,1);

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    if ~isempty(LI)
        thisCount = sum(LI >= a & LI <= b);
    else
        thisCount = 0;
    end

    diveLungeCount(di) = thisCount;
    s = state(a:b);
    s = s(~isnan(s));
    
    if isempty(s)
        continue
    end
    
    % most frequent state
    domState = mode(s);
    
    isTravelDive(di)  = (domState == 4);
    isRestDive(di)    = (domState == 3);
    isExploreDive(di) = (domState == 6);
    isForagingDive(di)= any(s == 5);
end

%% Build auto-state bouts from vectors

autoStartI = [];
autoEndI   = [];
autoState  = [];

valid = tagon & ~isnan(state);

% Only look at valid samples
s = state;
s(~valid) = NaN;

% Start = where state becomes non-NaN or changes
startIdx = find(~isnan(s) & ([true; s(2:end) ~= s(1:end-1)]));

% End = where state changes or ends
endIdx = [startIdx(2:end)-1; find(~isnan(s),1,'last')];

% Store
autoStartI = startIdx;
autoEndI   = endIdx;
autoState  = s(startIdx);

if isempty(autoStartI)
    warning('No auto-state bouts found.');
else
    % diagnostics below
    fprintf('\n--- AUTO CLASSIFIER SUMMARY ---\n');

    % Core counts
    fprintf('Valid lunges: %d\n', numel(LI));
    fprintf('Dives kept: %d\n', nDives);
    
    % Parameters
    fprintf('Rest min bout (s): %.1f\n', REST_MIN_BOUT_S);
    
    % Time summary (minutes)
    fprintf('Recovery minutes: %.2f\n', sum(state==1 & tagon)/fs/60);
    fprintf('Surface active minutes: %.2f\n', sum(state==2 & tagon)/fs/60);
    fprintf('Rest minutes: %.2f\n', sum(state==3 & tagon)/fs/60);
    fprintf('Travel minutes: %.2f\n', sum(state==4 & tagon)/fs/60);
    fprintf('Forage minutes: %.2f\n', sum(state==5 & tagon)/fs/60);
    fprintf('Explore minutes: %.2f\n', sum(state==6 & tagon)/fs/60);
    
    % Sanity check: total classified time
    totalMin = sum(tagon)/fs/60;
    classifiedMin = sum(~isnan(state) & tagon)/fs/60;
    fprintf('Total tag-on minutes: %.2f\n', totalMin);
    fprintf('Classified minutes: %.2f\n', classifiedMin);
    fprintf('Unclassified minutes: %.2f\n', totalMin - classifiedMin);
    fprintf('-------------------------------\n');
end

%% Activity budget
labels = ["recovery","surface_active","resting","traveling","foraging","exploring"];

valid = tagon & ~isnan(state);
totalValid = sum(valid);

pct = nan(1,6);

if totalValid > 0
    for s = 1:6
        pct(s) = 100 * sum(state(valid) == s) / totalValid;
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

% ---- SAFETY: define pct/labels if missing ----
if ~exist('labels','var') || isempty(labels)
    labels = ["recovery","surface active","resting","traveling","foraging","exploring"];
end

if ~exist('pct','var') || isempty(pct)
    if exist('state','var') && exist('tagon','var') && any(tagon)
        valid = tagon & ~isnan(state);
        totalValid = sum(valid);

        pct = nan(1,6);
        if totalValid > 0
            for s = 1:6
                pct(s) = 100 * sum(state(valid) == s) / totalValid;
            end
        else
            error('No valid classified samples found to compute activity budget.');
        end
    else
        error('pct is missing and state/tagon not available to compute it.');
    end
end

% ---- Total tag-on hours ----
tagOnHours = NaN;
if exist('tagon','var') && exist('fs','var') && any(tagon)
    tagOnHours = sum(tagon)/fs/3600;
end

fig = figure('Color','w','Units','normalized','Position',[0.2 0.2 0.45 0.55]);

axPie = axes('Parent', fig);
axPie.Position = [0.12 0.22 0.76 0.66];

stateColors = [
    0.90 0.62 0.00;   % recovery = orange
    0.34 0.71 0.91;   % surface active = light blue
    0.25 0.20 0.65;   % resting = purple
    0.80 0.47 0.65;   % traveling = magenta
    0.50 0.78 0.35;   % foraging = green
    0.95 0.90 0.20    % exploring = yellow
];

h = pie(axPie, pct);
title(axPie, 'Activity budget', 'FontWeight', 'bold');

patchHandles = findobj(h, 'Type', 'Patch');
patchHandles = flipud(patchHandles);

for k = 1:min(numel(patchHandles), size(stateColors,1))
    patchHandles(k).FaceColor = stateColors(k,:);
end

legtxt = strings(1,numel(labels));
for k = 1:numel(labels)
    legtxt(k) = sprintf('%s (%.1f%%)', labels(k), pct(k));
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
if exist('DN','var') && ~isempty(DN)
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

% Optional export
% exportgraphics(fig, fullfile(fileloc, [whaleName '_ActivityBudget.png']), 'Resolution', 300);

%% 2. Plot auto-classified behavior with navigation
% Uses the same time system as the original code:
% plot in datenum (DN), then relabel ticks with datestr()

if ~exist('progressIndex','var')
    progressIndex = find(tagon,1);
end

i = progressIndex;

while true

    % --- Compute window ---
    e = min(find(p(i+M*60*fs:end) < 10, 1, 'first') + i + (M+1)*60*fs - 1, length(p));
    if isempty(e) || isnan(e)
        e = length(p);
    end

    I = max(i-60*fs, 1):e;
    tagonI = false(size(p));
    tagonI(I) = true;
    tagonI = tagon & tagonI;

    figure(101); clf

    %% ---------------- TOP PANEL ----------------
    subplot(3,1,1);
    [ax1,~,hJ] = plotyy(DN(I), p(I), DN(I), J(I));
    set(ax1(1), 'ydir', 'rev', 'nextplot', 'add', 'ylim', [-5 max(p(tagonI))]);
    set(ax1(2), 'ycolor', 'm', 'ylim', [0 1.2*max(J(tagonI))]);
    set(hJ, 'color', 'm');

    ylabel(ax1(1), 'Depth');
    ylabel(ax1(2), 'Jerk');
    set(ax1, 'xlim', [DN(I(1)) DN(I(end))]);

    hold(ax1(1), 'on')

    stateColors = [
        0.90 0.62 0.00;   % 1 recovery = orange
        0.34 0.71 0.91;   % 2 surface active = light blue
        0.75 0.45 0.65;   % 3 resting = mauve
        0.28 0.24 0.70;   % 4 traveling = indigo
        0.50 0.78 0.35;   % 5 foraging = green
        0.95 0.90 0.20    % 6 exploring = yellow
    ];

    stateNames = { ...
        'Recovery', ...
        'Surface active', ...
        'Resting', ...
        'Traveling', ...
        'Foraging', ...
        'Exploring'};

    yl = get(ax1(1), 'ylim');

    % --- Shade auto behavioral states on depth plot ---
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

        x1 = DN(sI);
        x2 = DN(eI);

        patch(ax1(1), ...
            [x1 x2 x2 x1], ...
            [yl(1) yl(1) yl(2) yl(2)], ...
            stateColors(thisState,:), ...
            'FaceAlpha', 0.18, ...
            'EdgeColor', 'none');
    end

    % --- Lunge markers on depth panel ---
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

    % --- State color key ---
    hStateLegend = gobjects(6,1);
    for ss = 1:6
        hStateLegend(ss) = plot(ax1(1), NaN, NaN, 's', ...
            'MarkerSize', 8, ...
            'MarkerFaceColor', stateColors(ss,:), ...
            'MarkerEdgeColor', stateColors(ss,:));
    end
    legend(ax1(1), hStateLegend, stateNames, 'Location', 'eastoutside', 'FontSize', 8);

    uistack(findobj(ax1(1), 'Type', 'line'), 'top')

    % Fix x-axis labels using same system as original code
    set(ax1(1), 'xticklabel', datestr(get(ax1(1), 'xtick'), 'mm/dd HH:MM:SS'));
    set(ax1(2), 'xticklabel', datestr(get(ax1(2), 'xtick'), 'mm/dd HH:MM:SS'));

    title(filename(1:end-11));

    %% ---------------- MIDDLE PANEL ----------------
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

    % Lunge markers on pitch panel
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

    %% ---------------- BOTTOM PANEL ----------------
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

    % Lunge markers on speed panel
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

    %% ---------------- LINKED VERTICAL CURSOR ----------------
% Add a vertical guide line that follows the mouse across all panels

% make sure all x-limits are aligned
linkaxes([ax1(1), ax2(1), s3], 'x');

% current x-limits
xl = xlim(ax1(1));

% create one vertical line per panel
hold(ax1(1), 'on');
hCursor1 = plot(ax1(1), [xl(1) xl(1)], ylim(ax1(1)), 'k--', 'LineWidth', 1);

hold(ax2(1), 'on');
hCursor2 = plot(ax2(1), [xl(1) xl(1)], ylim(ax2(1)), 'k--', 'LineWidth', 1);

hold(s3, 'on');
hCursor3 = plot(s3, [xl(1) xl(1)], ylim(s3), 'k--', 'LineWidth', 1);

% send cursor lines behind markers/lines if needed
uistack(hCursor1, 'bottom');
uistack(hCursor2, 'bottom');
uistack(hCursor3, 'bottom');

% update function
set(gcf, 'WindowButtonMotionFcn', @(src,evt) updateVerticalCursor(src, ax1(1), ax2(1), s3, hCursor1, hCursor2, hCursor3));

%% ---------------- ALIGN PANEL WIDTHS ----------------
% Use the left/top axis from each panel for alignment
drawnow;

pos1 = get(ax1(1), 'Position');
pos2 = get(ax2(1), 'Position');
pos3 = get(s3,    'Position');

% Make all panels use the same left edge and width as the bottom panel
newLeft  = pos3(1);
newWidth = pos3(3);

set(ax1(1), 'Position', [newLeft pos1(2) newWidth pos1(4)]);
set(ax1(2), 'Position', [newLeft pos1(2) newWidth pos1(4)]);  % paired plotyy axis

set(ax2(1), 'Position', [newLeft pos2(2) newWidth pos2(4)]);
set(ax2(2), 'Position', [newLeft pos2(2) newWidth pos2(4)]);  % paired plotyy axis

set(s3,     'Position', [newLeft pos3(2) newWidth pos3(4)]);

    %% ---------------- NAVIGATION ----------------
    fprintf('ENTER = forward | b = back | q = quit\n');

    wasKey = waitforbuttonpress;

    if wasKey
        key = get(gcf, 'CurrentCharacter');

        switch key
            case char(13) % ENTER
                i = e;

            case 'b' % back
                i = max(1, i - M*60*fs);

            case 'q' % quit
                progressIndex = i;
                break
        end
    end

end 


function updateVerticalCursor(fig, axTop, axMid, axBot, h1, h2, h3)

    % figure object currently under pointer
    obj = hittest(fig);
    if isempty(obj) || ~isgraphics(obj)
        return
    end

    % find which axes the pointer is over
    ax = ancestor(obj, 'axes');
    if isempty(ax) || ~ismember(ax, [axTop, axMid, axBot])
        return
    end

    % x-position from the active axes
    cp = get(ax, 'CurrentPoint');
    x = cp(1,1);

    % ignore if outside x-limits
    xl = xlim(axTop);
    if x < xl(1) || x > xl(2)
        return
    end

    % update all three vertical lines
    set(h1, 'XData', [x x], 'YData', ylim(axTop));
    set(h2, 'XData', [x x], 'YData', ylim(axMid));
    set(h3, 'XData', [x x], 'YData', ylim(axBot));

end