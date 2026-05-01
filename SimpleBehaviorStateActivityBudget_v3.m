% % Identify behavioral states (resting, traveling, foraging, exploring) and create an activity budget for tag
% deployment
% March 2, 2026 Messing Around with pie chart and putting a map inset into
% the figure
% =========================================================
% VERSION: 2026-02-27
% Auto state classifier v1
% Foraging & traveling validated.
% Resting under refinement (currently minimal).
% Lauren Fritz
% University of California Santa Cruz
% =========================================================
% 
% Input - 10hz PRH mat file
% Outputs - Section 2: Lunge .mat file, behavior state .mat file, activity
%           budget pie chart.
%           Section 3: Error check variable and command window report for behavior states.
%           Returns indices and description of suspected errors.
%           Section 4: Behavior state .xlsx file (same format as .mat file)
%           Section 5: Behavior state .xlsx file with durations (if all
%           behaviors have start and finish)
%           
% 
% 
%% 1. Load Data
clear; % clears the workspace
%Start where you left off?
atLast = true; %this will look for a variable called progressIndex
M = 10; % number of minutes
% Variables that will be saved in the Lunge file
notes = '';
creator = 'DEC';
primary_cue = 'speedJJ';
% Set behavioral state names (Q/W/E/R)
states = {'resting','traveling','foraging','exploring'};

try
    drive = 'CATS'; % name of drive where files are located. This is the black hard drive that used to be NAN_Backup
    folder = 'CATS/CATS/tag_analysis/data_processed'; % folder in the drive where the cal files are located (and where you want to look for files) %'Users\Dave\Documents\Programs\MATLAB\Tagging\CATS cal';%
    % make finding the files easier
    a = getdrives;
    for i = 1:length(a)
        [~,vol]=system(['vol ' a{i}(1) ':']);
        if strfind(vol,drive); vol = a{i}(1); break; end
    end
catch
end

cf = pwd;
[filename,fileloc]=uigetfile('*.mat', 'Select the PRH file to analyze');
cd(fileloc);

disp('Loading Data, will take some time');
load(fullfile(fileloc, filename));   % loads PRH variables
whos

whos speed
if exist('speed','var') && isstruct(speed)
    disp(fieldnames(speed))
    if isfield(speed,'JJ'), fprintf('speed.JJ finite count: %d\n', sum(isfinite(speed.JJ(:)))); end
    if isfield(speed,'FN'), fprintf('speed.FN finite count: %d\n', sum(isfinite(speed.FN(:)))); end
end

%% Build speedJJ and J (runmean version)

% Ensure vectors are columns
p = p(:);
DN = DN(:);
tagon = tagon(:);

%% ---- Build speedJJ and speedFN (Dave Cade style, struct OR table) ----
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

% ---- speedFN from speed.FN (robust with NaNs) ----
speedFN = nan(size(p));   % default

if exist('speed','var') && isstruct(speed) && isfield(speed,'FN') && ~isempty(speed.FN)
    raw = speed.FN(:);

    if ~all(isnan(raw))
        tmp = raw;
        tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));
        tmp = runmean(tmp, max(1,round(fs/2)));
        tmp(isnan(raw)) = nan;

        n = min(numel(tmp), numel(speedFN));
        speedFN(1:n) = tmp(1:n);
    end
end

% ---- Movement proxy used by AUTO classifier ----
mov = speedJJ;
if all(isnan(mov))
    mov = J;
end

% baseName for matching lunge file
[~, baseName, ~] = fileparts(filename);

% ---- Load lunges file (single robust block) ----
LungeI = [];
LungeDN = [];
LungeC = [];
lungesFile = 'mn180105-22alunges.mat';  % IMPORTANT: define no matter what

depID = regexp(baseName,'^[^ ]+','match','once');

% ---- Define whaleName robustly (used for outputs) ----
whaleName = depID;  % default fallback

if exist('INFO','var') && isstruct(INFO) && isfield(INFO,'whaleName') && ~isempty(INFO.whaleName)
    whaleName = INFO.whaleName;
elseif exist('whaleName','var') && ~isempty(whaleName)
    % keep existing
else
    % last-resort: use baseName (sanitized)
    whaleName = regexprep(baseName, '\s+', '_');
end

whaleName = regexprep(whaleName, '[^\w\-]+', '_');

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
        % Option A (best if you have Mapping Toolbox)
        [kmlLat, kmlLon] = read_geoPtrack_kml_simple(kmlFile);

    catch ME
    end
else
    fprintf('No geoPtrack KML found for depID=%s in %s\n', depID, fileloc);
end

% =========================
% PICK BEST-MATCH LUNGES FILE (OPTIONAL)
% If none found / none usable, proceed with LI=[] (no lunges)
% =========================

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
    DNmin = min(DN); DNmax = max(DN);

    for k = 1:numel(cand)
        f = fullfile(cand(k).folder, cand(k).name);

        % load minimally
        tmp = load(f);

        % pull a time vector from common names (datenum-like)
        t = [];
        if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN; end
        if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time; end

        % If only indices exist, we can still use them (convert indices to DN later)
        if isempty(t) && isfield(tmp,'LungeI') && ~isempty(tmp.LungeI), t = DN(tmp.LungeI(:)); end
        if isempty(t) && isfield(tmp,'LI')     && ~isempty(tmp.LI),     t = DN(tmp.LI(:));     end
        if isempty(t) && isfield(tmp,'L')      && ~isempty(tmp.L),      t = tmp.L;            end

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
% =========================
% LOAD LUNGES FROM THE SELECTED FILE (if any)
% =========================
LI = [];
L = [];
LC = [];

if ~isempty(bestFile) && isfile(bestFile)

    tmp = load(bestFile);
    disp('Lunge file variables:');
    disp(fieldnames(tmp));

    LungeI = [];
    LungeDN = [];
    LungeC = [];

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
    % Explicitly: no lunges
    LI = [];
    L  = [];
    LC = [];
end

fprintf('FINAL lunges used: LI=%d\n', numel(LI));

%% ===============================
% AUTO STATE CLASSIFIER (v1, 4-state)
% Place directly after: disp('Section 1 finished: Data Loaded');
% ================================

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
% Foraging  = any dive (depth > 10 m) with >=1 detected lunge
%            BUT ignore lunges shallower than 10 m (Tyson et al.)
% Traveling = dives with max depth between 10–50 m AND no (valid) lunges
% Resting   = surface intervals (NOT in a dive), depth <10 m, low movement,
%            with a minimum bout duration you choose (recovery question)
% Exploring = anything on-animal not otherwise classified

% ---------- PARAMETERS (EDIT HERE) ----------
DIVE_THRESH_M        = 10;      % dive if p > this (m)
MIN_DIVE_DUR_S       = 0;      % ignore tiny excursions as dives
TRAVEL_MIN_M         = 10;
TRAVEL_MAX_M         = 50;

LUNGE_MIN_DEPTH_M    = 10;      % Tyson et al: ignore lunges shallower than this

% Resting / recovery knob:
% If you want "recovery counted as resting" -> set REST_MIN_BOUT_S = 0
% If you want only clear resting bouts       -> set REST_MIN_BOUT_S = 180 (or 300, etc.)
REST_MIN_BOUT_S      = 30;       % <<< THIS is where minRestDur_s comes from
REST_DEPTH_MAX_M     = 10;      % resting depth band (0–10 m)
REST_MOV_PCTL        = 35;      % low-movement threshold = this percentile of mov (on-animal)
REST_SMOOTH_S        = 10;      % smooth movement to reduce flicker
REST_GAPFILL_S       = 10;       % fill short gaps inside a bout

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
    LI = LI(p(LI) >= LUNGE_MIN_DEPTH_M);   % ignore shallow lunges
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

% ---------- 2) DIVE-LEVEL LABELS: FORAGING vs TRAVELING ----------
forageMask = false(N,1);
travelMask = false(N,1);

PITCH_SD_TRAVEL_MAX = 20;   % tune this

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    mx = max(p(a:b), [], 'omitnan');
    hasLunge = ~isempty(LI) && any(LI >= a & LI <= b);
    pitchSD = std(pitch(a:b)*180/pi, 'omitnan');

    if hasLunge
        forageMask(a:b) = true;

    elseif mx >= TRAVEL_MIN_M && mx <= TRAVEL_MAX_M && pitchSD <= PITCH_SD_TRAVEL_MAX
        travelMask(a:b) = true;

    end
end

% ---------- 2b) BUILD DIVE-LEVEL VARIABLES FOR PLOTTING ----------
diveStartDN = DN(diveStarts);
diveStopDN  = DN(diveStops);

isForagingDive = false(nDives,1);
isTravelDive   = false(nDives,1);
diveLungeCount = zeros(nDives,1);

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    mx = max(p(a:b), [], 'omitnan');

    if ~isempty(LI)
        thisCount = sum(LI >= a & LI <= b);
    else
        thisCount = 0;
    end

    diveLungeCount(di) = thisCount;
    isForagingDive(di) = thisCount > 0;
    isTravelDive(di)   = (thisCount == 0) && (mx >= TRAVEL_MIN_M) && (mx <= TRAVEL_MAX_M);
end


% ---------- 3) RESTING (SURFACE ONLY) ----------

% low-movement threshold from on-animal samples (surface-only is also OK; keeping on-animal is robust)
w = max(1, round(REST_SMOOTH_S * fs));
movS = mov;

if any(isfinite(movS))
    movFill = movS;
    movFill(~isfinite(movFill)) = prctile(movFill(isfinite(movFill)), 5);
    movS = runmean(movFill, w);
    movS(~isfinite(mov)) = nan;   % restore NaNs
end

% low-movement threshold from SURFACE samples only
surfaceOnly = tagon & (p <= REST_DEPTH_MAX_M) & isfinite(movS);

if any(surfaceOnly)
    restThresh = prctile(movS(surfaceOnly), REST_MOV_PCTL);
else
    warning('No valid surface samples for resting threshold; falling back to all tag-on samples.');
    fallback = tagon & isfinite(movS);
    restThresh = prctile(movS(fallback), REST_MOV_PCTL);
end

surfaceInterval = tagon & ~inDive;

restCand = surfaceInterval ...
    & (p >= 0) & (p <= REST_DEPTH_MAX_M) ...
    & isfinite(movS) & (movS <= restThresh);

% fill short gaps
gapFillN = max(0, round(REST_GAPFILL_S * fs));
restFilled = restCand;

dr = diff([false; restCand; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;

if numel(rs) >= 2 && gapFillN > 0
    for k = 1:(numel(rs)-1)
        gapStart = re(k) + 1;
        gapStop  = rs(k+1) - 1;
        gapLen   = gapStop - gapStart + 1;
        if gapLen > 0 && gapLen <= gapFillN
            restFilled(gapStart:gapStop) = true;
        end
    end
end

% enforce minimum bout duration
minRestN = max(0, round(REST_MIN_BOUT_S * fs));
restMask = false(N,1);

dr = diff([false; restFilled; false]);
rs = find(dr == 1);
re = find(dr == -1) - 1;

durN = re - rs + 1;
keep = durN >= max(1, minRestN);

for kk = find(keep)'
    restMask(rs(kk):re(kk)) = true;
end

% ensure resting never overwrites dives
restMask(inDive) = false;

% ---------- 4) BUILD FINAL STATE VECTOR ----------
exploreMask = inDive & tagon & ~forageMask & ~travelMask;

state = nan(N,1);
state(restMask)    = 1;
state(travelMask)  = 2;
state(forageMask)  = 3;
state(exploreMask) = 4;


% state codes:
% 1 = resting, 2 = traveling, 3 = foraging, 4 = exploring

%% ---------- BUILD AUTO STATE BOUTS FROM state VECTOR (ROBUST) ----------

autoStartI = [];
autoEndI   = [];
autoState  = [];

valid = tagon & ~isnan(state);

% Only look at valid samples
s = state;
s(~valid) = NaN;

% Find transitions
d = diff([NaN; s; NaN]);

% Start = where state becomes non-NaN or changes
startIdx = find(~isnan(s) & ([true; s(2:end) ~= s(1:end-1)]));

% End = where state changes or ends
endIdx = [startIdx(2:end)-1; find(~isnan(s),1,'last')];

% Store
autoStartI = startIdx;
autoEndI   = endIdx;
autoState  = s(startIdx);

if isempty(autoStartI)
    return
end

% ---------- OPTIONAL QUICK DIAGNOSTICS ----------
fprintf('\n--- AUTO CLASSIFIER SUMMARY ---\n');
fprintf('Valid lunges (>=%.0f m): %d\n', LUNGE_MIN_DEPTH_M, numel(LI));
fprintf('Dives kept: %d\n', nDives);
fprintf('Rest threshold (mov p%d): %.4f\n', REST_MOV_PCTL, restThresh);
fprintf('Rest min bout (s): %.1f\n', REST_MIN_BOUT_S);
fprintf('Rest minutes: %.2f\n', sum(state==1 & tagon)/fs/60);

plot_depth_vs_movement(p, movS, 10, 50);
%% ===============================
% COLOR TRACK BY BEHAVIOR STATE
% Requires: state (Nx1), DN (Nx1), and kmlLat/kmlLon + kmlDT (datetime)
% Paste AFTER you build `state`
%% ===============================

% --- Convert PRH DN to datetime ---
prhDT = datetime(DN, 'ConvertFrom', 'datenum', 'TimeZone', 'UTC');

% --- Safety checks ---
if ~exist('kmlLat','var') || ~exist('kmlLon','var')
    warning('No kmlLat/kmlLon found. Skipping colored track.');
else
    if ~exist('kmlDT','var')
        warning('No kmlDT (times) found for KML points. You need timestamps to color by state.');
    else
        % Ensure columns
        kmlLat = kmlLat(:);
        kmlLon = kmlLon(:);
        kmlDT  = kmlDT(:);

        % Keep only finite points
        ok = isfinite(kmlLat) & isfinite(kmlLon) & ~isnat(kmlDT);
        kmlLat = kmlLat(ok);
        kmlLon = kmlLon(ok);
        kmlDT  = kmlDT(ok);

        % --- Map each KML timestamp to nearest PRH sample ---
        % nearest-neighbor lookup in time
        idx = interp1(datenum(prhDT), (1:numel(prhDT))', datenum(kmlDT), 'nearest', NaN);

        % Pull state at those times
        kmlState = nan(size(idx));
        good = ~isnan(idx);
        kmlState(good) = state(idx(good));

        % Optional: only color points when tag is on-animal (tagon)
        if exist('tagon','var')
            kmlOnAnimal = false(size(idx));
            kmlOnAnimal(good) = tagon(idx(good));
            kmlState(~kmlOnAnimal) = NaN;  % drop tag-off points from coloring
        end

        % --- Plot on a geoaxes you already made (axMap), or create one ---
        if ~exist('axMap','var') || ~isvalid(axMap)
            figure;
            axMap = geoaxes;
        end
        hold(axMap,'on');

        % Choose basemap (labels vs imagery)
        % geobasemap(axMap,'satellite-streets');  % imagery + labels
        % geobasemap(axMap,'satellite');          % imagery only
        geobasemap(axMap,'satellite-streets');

        % Colors for states: 1=rest,2=travel,3=forage,4=explore
        % (match your Bcolors='rgkc' if you want)
        stateColors = {
            [0.2 0.5 0.9]    % 1 = resting (blue)
            [0.3 0.75 0.3]   % 2 = traveling (green)
            [0.9 0.3 0.3]    % 3 = foraging (red)
            [1.0 0.6 0.1]    % 4 = exploring (orange)
        };
            
        stNames = {'Resting','Traveling','Foraging','Exploring'};

        % --- Plot as colored segments: split whenever state changes or missing ---
        % Build runs of constant state
        s = kmlState;
        breakPts = [true; diff(s)~=0 | isnan(s(2:end)) | isnan(s(1:end-1))];
        runStart = find(breakPts);
        runEnd   = [runStart(2:end)-1; numel(s)];

        hLegend = gobjects(4,1);

        for r = 1:numel(runStart)
            a = runStart(r);
            b = runEnd(r);
            thisState = s(a);

            if isnan(thisState) || b-a < 1
                continue
            end

            c = stColors{thisState};
            h = geoplot(axMap, kmlLat(a:b), kmlLon(a:b), '-', 'LineWidth', 2);

            % Set color (MATLAB accepts RGB triplet)
            h.Color = c;

            % store one handle per state for legend
            if ~isgraphics(hLegend(thisState))
                hLegend(thisState) = h;
            end
        end

        % --- Mark tag-on / tag-off locations (first/last valid point) ---
        if ~isempty(kmlLat)
            geoplot(axMap, kmlLat(1),   kmlLon(1),   'o', 'MarkerSize', 8, 'MarkerFaceColor','y'); % start
            geoplot(axMap, kmlLat(end), kmlLon(end), 's', 'MarkerSize', 8, 'MarkerFaceColor','y'); % end
        end

        % Legend (only include states that actually appeared)
        present = arrayfun(@(k) isgraphics(hLegend(k)), 1:4);
        legend(axMap, hLegend(present), stNames(present), 'Location','southoutside');

        title(axMap, 'Track colored by behavioral state');
        hold(axMap,'off');
    end
end

% ---------- ACTIVITY BUDGET % ----------
labels = ["resting","traveling","foraging","exploring"];

pct = nan(1,4);
for s = 1:4
    pct(s) = 100 * sum(state(tagon) == s) / sum(tagon);
end

budgetT = table(labels', pct', 'VariableNames', {'State','Percent'});
disp(budgetT);

writetable(budgetT, fullfile(fileloc, [whaleName '_AutoActivityBudget.csv']));

%% =========================================================
%% ========= Activity budget figure: Pie (left) + Satellite track (right) =========
% REQUIREMENTS:
%  - pct must exist: 1x4 percent vector for [rest travel forage explore]
%  - labels must exist: string/cellstr of 4 labels
%  - whaleName/INFO optional for metadata text
%  - kmlFile path should exist (mnXXXX-XXgeoPtrack.kml)

% ---- SAFETY: define pct/labels if missing ----
if ~exist('labels','var') || isempty(labels)
    labels = ["resting","traveling","foraging","exploring"];
end
if ~exist('pct','var') || isempty(pct)
    % compute from state if available
    if exist('state','var') && exist('tagon','var') && any(tagon)
        pct = nan(1,4);
        for s = 1:4
            pct(s) = 100 * sum(state(tagon)==s) / sum(tagon);
        end
    else
        error('pct is missing and state/togon not available to compute it.');
    end
end

% ---- Total tag-on hours (requested) ----
tagOnHours = NaN;
if exist('tagon','var') && exist('fs','var') && any(tagon)
    tagOnHours = sum(tagon)/fs/3600;
end

% ---- Try to read KML track (robust) ----
kmlLat = [];
kmlLon = [];
if exist('kmlFile','var') && ~isempty(kmlFile) && isfile(kmlFile)
    try
        [kmlLat,kmlLon] = read_geoPtrack_kml_coords(kmlFile);
    catch ME
        warning('KML read failed: %s', ME.message);
        kmlLat = []; kmlLon = [];
    end
end

% ---- Make a single figure with two PANELS (this prevents geoaxes overlap) ----
fig = figure('Color','w','Units','normalized','Position',[0.1 0.1 0.78 0.55]);

% Left panel for pie
pLeft  = uipanel(fig,'Units','normalized','Position',[0.02 0.07 0.46 0.90], 'BorderType','none');

% Right panel for map
pRight = uipanel(fig,'Units','normalized','Position',[0.52 0.07 0.46 0.90], 'BorderType','none');

% ---- LEFT: pie chart in a normal axes ----
axPie = axes('Parent',pLeft);
axPie.Position = [0.08 0.08 0.84 0.84];

% Pie + legend KEY (requested)
h = pie(axPie, pct);
title(axPie, 'Activity budget', 'FontWeight','bold');

% Make legend from labels + percents
legtxt = strings(1,numel(labels));
for k = 1:numel(labels)
    legtxt(k) = sprintf('%s (%.1f%%)', labels(k), pct(k));
end
legend(axPie, legtxt, 'Location','southoutside');

% Metadata text (no whale ID in title; put metadata below instead)
metaLines = {};
if exist('INFO','var')
    if isfield(INFO,'whaleName'), metaLines{end+1} = sprintf('Whale: %s', INFO.whaleName); end %#ok<AGROW>
    if isfield(INFO,'tagID'),     metaLines{end+1} = sprintf('Tag: %s', INFO.tagID); end %#ok<AGROW>
end
if exist('DN','var') && ~isempty(DN)
    metaLines{end+1} = sprintf('Start: %s', datestr(min(DN),'yyyy-mm-dd HH:MM')); %#ok<AGROW>
    metaLines{end+1} = sprintf('End:   %s', datestr(max(DN),'yyyy-mm-dd HH:MM')); %#ok<AGROW>
end
if isfinite(tagOnHours)
    metaLines{end+1} = sprintf('Tag-on time: %.2f hours', tagOnHours); %#ok<AGROW>
end
if ~isempty(metaLines)
    annotation(fig,'textbox',[0.03 0.01 0.46 0.06], ...
        'String',strjoin(metaLines,'   |   '), ...
        'EdgeColor','none','HorizontalAlignment','left','FontSize',10);
end

% ---- RIGHT: satellite basemap + track in a GEOAXES parented to right panel ----
if ~isempty(kmlLat) && ~isempty(kmlLon)

    % Diagnostics so you can see if you actually have coordinates
    fprintf('\n--- KML TRACK DIAG ---\n');
    fprintf('N track points: %d\n', numel(kmlLat));
    fprintf('Lat range: %.4f to %.4f\n', min(kmlLat), max(kmlLat));
    fprintf('Lon range: %.4f to %.4f\n', min(kmlLon), max(kmlLon));
    fprintf('----------------------\n');

    axMap = geoaxes('Parent',pRight);
    axMap.Position = [0.06 0.06 0.90 0.90];

    geobasemap(axMap,'satellite');
    hold(axMap,'on');

    geoplot(axMap, kmlLat, kmlLon, '-', 'LineWidth', 1.8);

    % ON / OFF markers
    geoscatter(axMap, kmlLat(1),   kmlLon(1),   40, 'filled');
    geoscatter(axMap, kmlLat(end), kmlLon(end), 40, 'filled');

    title(axMap, 'Deployment track', 'FontWeight','bold');

    % Zoom to bounds with padding
    latlim = [min(kmlLat) max(kmlLat)];
    lonlim = [min(kmlLon) max(kmlLon)];
    padLat = 0.05 * max(0.01, range(latlim));
    padLon = 0.05 * max(0.01, range(lonlim));
    geolimits(axMap, latlim + [-padLat padLat], lonlim + [-padLon padLon]);

    hold(axMap,'off');

else
    axMsg = axes('Parent',pRight);
    axis(axMsg,'off');
    text(axMsg,0.5,0.5,'No KML coordinates parsed (track not plotted)', ...
        'HorizontalAlignment','center','FontSize',11);
end

% Optional export
% exportgraphics(fig, fullfile(fileloc, [whaleName '_ActivityBudget_plusTrack.png']), 'Resolution', 300);

[figSI, out] = plot_surface_interval_vs_movement( ...
    diveStartDN, ...
    diveStopDN, ...
    isForagingDive, ...
    DN, ...
    movS, ...
    fullfile(fileloc, 'surface_interval_vs_movement.png'));


%% ===== Helper: robustly extract lon/lat from <coordinates> blocks in this KML style =====
function [lat,lon] = read_geoPtrack_kml_coords(kmlFile)
    txt = fileread(kmlFile);

    % Grab every <coordinates> ... </coordinates> block
    tok = regexp(txt, '<coordinates>\s*([^<]+)\s*</coordinates>', 'tokens');
    if isempty(tok)
        error('No <coordinates> blocks found in KML: %s', kmlFile);
    end

    % Each token may contain one line "lon,lat,alt" (your file does)
    lon = nan(numel(tok),1);
    lat = nan(numel(tok),1);

    for i = 1:numel(tok)
        s = strtrim(tok{i}{1});

        % Some KMLs can have multiple coordinate triplets; split by whitespace
        parts = regexp(s, '\s+', 'split');

        % take the first triplet in this placemark
        trip = parts{1};
        nums = sscanf(trip, '%f,%f,%f');

        if numel(nums) >= 2
            lon(i) = nums(1);
            lat(i) = nums(2);
        end
    end

    % drop bad rows
    good = isfinite(lat) & isfinite(lon);
    lat = lat(good);
    lon = lon(good);

    if isempty(lat)
        error('Parsed coordinates but none were finite (check KML format).');
    end
end
%% Working with Surface Intervals
% Defining how much time a whale spends within 10 m of the surface

% Define surface threshold
surface_thresh = 10; % meters

% Only use valid tag-on data
p_valid = p(tagon);

% Remove NaNs if needed
p_valid = p_valid(~isnan(p_valid));

% Calculate percent time near surface
pct_surface = sum(p_valid <= surface_thresh) / length(p_valid) * 100;

fprintf('Percent of time within 10 m: %.2f%%\n', pct_surface);

plot(p_valid)
hold on
yline(10, 'r--', '10 m threshold')
set(gca, 'YDir', 'reverse') % depth increases downward
xlabel('Time')
ylabel('Depth (m)')
title('Depth Time Series with Surface Threshold')

isSurf = p <= 10 & tagon & ~isnan(p);

d = diff([false; isSurf(:); false]);
surfStartI = find(d == 1);
surfEndI   = find(d == -1) - 1;

%% 2. Plot and Process

%Lunge data denoted in all plots as squares.
%Behavior data plotted over dive profile
%O indicates beginning of behavioral state, X indicates termination of
%behavioral state
%If current state (denoted at bottom of window) is active, beginning a new
%state will terminate the previous state. "G" can be used to toggle states
%if this is not desired.
%Y will terminate the current state without placing a new state. For later
%export sections this should be used to finish the PRH file. 
%"H" will set the progressIndex to whatever either the lunge or
%behaviorstate that is furthest along in the file, i.e jump to point of
%furthest progress.

    % Check to see if we should start at beginning or at a saved index (i)
    if ~exist('progressIndex','var') || ~atLast
        i = find(tagon,1);
    else
        i = progressIndex;
    end
    %
    for iii = 1
    instructions = sprintf(['Controls:\n' ...
'LeftClick: High Confidence Lunge\nL: Likely Lunge\nM: Maybe Lunge\nRightClick: Delete Lunge\n' ...
'Q: Resting\nW: Traveling\nE: Foraging\nR: Exploring\n' ...
'T: Delete State Marker\nY: End Current State\nG: Toggle State (cycle)\n' ...
'1-9: Change Zoom(x10)\nB: Move Back\nEnter: Move Forward\nH: Go To Last\nS: Save']);
    while i<find(tagon,1,'last')
        figure(101); clf
        annotation('textbox', [0, 0.5, 0, 0], 'string', instructions,'FitBoxToText','on')
        
        if ~isempty(BehaviorState)
        annotation('textbox',[.5, 0.1, 0, 0],'string',BehaviorText,'FitBoxToText','on','tag','ba','color',Bcolors(BehaviorState));
        end

        e = min(find(p(i+M*60*fs:end)<10,1,'first')+i+(M+1)*60*fs-1,length(p));
        if isempty(e)||isnan(e); e = length(p); end
        I = max(i-60*fs,1):e;
        tagonI = false(size(p)); tagonI(I) = true;
        tagonI = tagon&tagonI;
        s1 = subplot(3,1,1);
        [ax1,~,h2] = plotyy(DN(I),p(I),DN(I),J(I));
        set(ax1(1),'ydir','rev','nextplot','add','ylim',[-5 max(p(tagonI))]);
        ylabel('Jerk','parent',ax1(2));
        ylabel('Depth','parent',ax1(1));
        set(ax1(2),'ycolor','m','ylim',[0 1.2*max(J(tagonI))]);
        set(h2,'color','m');
        set(ax1,'xlim',[DN(I(1)) DN(I(end))]);
        % --- Shade AUTO behavioral states on depth plot ---
        hold(ax1(1), 'on')
       
        stateColors = {
            [0.2 0.5 0.9]    % 1 = resting (blue)
            [0.3 0.75 0.3]   % 2 = traveling (green)
            [0.9 0.3 0.3]    % 3 = foraging (red)
            [1.0 0.6 0.1]    % 4 = exploring (orange)
        };       
        
        yl = get(ax1(1), 'ylim');
        
        for k = 1:length(autoStartI)

            if isnan(autoState(k))
                continue
            end
        
            if autoEndI(k) < I(1) || autoStartI(k) > I(end)
                continue
            end
        
            sI = max(autoStartI(k), I(1));
            eI = min(autoEndI(k), I(end));
        
            x1 = DN(sI);
            x2 = DN(eI);
        
            c = stateColors{autoState(k)};
        
            patch(ax1(1), ...
                [x1 x2 x2 x1], ...
                [yl(1) yl(1) yl(2) yl(2)], ...
                c, ...
                'FaceAlpha', 0.18, ...
                'EdgeColor', 'none');
        end
            
        uistack(findobj(ax1(1), 'Type', 'line'), 'top')
        set(ax1,'xticklabel',datestr(get(gca,'xtick'),'mm/dd HH:MM:SS'));
        title(filename(1:end-11));
        s2 = subplot(3,1,2);
        uistack(ax1(1));
        set(ax1(1), 'Color', 'none');
        set(ax1(2), 'Color', 'w')
        [ax2,h1,h2] = plotyy(DN(I),pitch(I)*180/pi,DN(I),roll(I)*180/pi); set(ax2(2),'nextplot','add','ycolor','k','ylim',[-180 180]);
        ylabel('Roll and Head','parent',ax2(2));
        plot(ax2(2),DN(I),head(I)*180/pi,'b.','markersize',4);
        set(ax2(1),'ycolor','g','nextplot','add','ylim',[-90 90]);
        ylabel('pitch','parent',ax2(1));
        set(h1,'color','g'); set(h2,'color','r','linestyle','-','markersize',4);
        set(ax2,'xlim',[DN(I(1)) DN(I(end))]);
        set(ax2,'xticklabel',datestr(get(gca,'xtick'),'HH:MM:SS'));
        s3 = subplot(3,1,3);
        fprintf('\n--- SPEED PLOT DIAG ---\n');
fprintf('len DN/p/speedJJ = %d / %d / %d\n', numel(DN), numel(p), numel(speedJJ));
fprintf('speedJJ finite in window: %d of %d\n', sum(isfinite(speedJJ(I))), numel(I));
if exist('speedFN','var')
    fprintf('speedFN finite in window: %d of %d\n', sum(isfinite(speedFN(I))), numel(I));
end
fprintf('speedJJ min/max (finite): %.3f / %.3f\n', ...
    min(speedJJ(I),[],'omitnan'), max(speedJJ(I),[],'omitnan'));
fprintf('------------------------\n');
        % --- Robust speed plot ---
if exist('speedJJ','var') && any(isfinite(speedJJ(I)))
    plot(DN(I), speedJJ(I), 'b');
else
    plot(DN(I), mov(I), 'b');   % fallback so subplot never empty
end
hold on

if exist('speedFN','var') && any(isfinite(speedFN(I)))
    plot(DN(I), speedFN(I), 'g');
end

% --- SAFETY: keep L/LI/LC aligned and within bounds ---
if ~isempty(L)
    L  = L(:);
    LI = LI(:);
    if exist('LC','var') && ~isempty(LC)
        LC = LC(:);
    else
        LC = nan(size(LI));
    end

    % Make sure same length
    n = min([numel(L), numel(LI), numel(LC)]);
    L  = L(1:n);
    LI = LI(1:n);
    LC = LC(1:n);

    % Clip indices to PRH length
    valid = (LI >= 1) & (LI <= numel(p)) & isfinite(L);
    L  = L(valid);
    LI = LI(valid);
    LC = LC(valid);

    % Sort by time AND apply same ordering to LI/LC
    [L, ord] = sort(L);
    LI = LI(ord);
    LC = LC(ord);
end
hold off
        set(s3,'nextplot','add');
        marks = nan(1,3);
        if ~isempty(L)
            %change color based on confidence
            colors = 'rbk';
            for c=1:3
                II = find(LC==c);
                if ~isempty(II)
                    marks(1) = plot(ax1(1),L(II),p(LI(II)),[colors(c) 's'],'markerfacecolor',colors(c));
                    marks(2) = plot(ax2(1),L(II),pitch(LI(II))*180/pi,[colors(c) 's'],'markerfacecolor',colors(c));
                    marks(3) = plot(s3,L(II),speedJJ(LI(II)),[colors(c) 's'],'markerfacecolor',colors(c));
                end
            end 
        end

%plot colors and o start x end for behavior states
        if ~isempty(behI)
        redraw = true;
                 try delete(Bmarks); catch; end;
                  Bcolors = 'rgkc';
                  Bshapes = 'ox';
                  for ss = 1:2;
                          SS = find (behSS==ss);
            %change cc end value to # of behavioral states used
                     for cc = 1:4
                      QQ = find (behS==cc);
                          CS = intersect(QQ,SS);
                              if ~isempty(CS)
                                   Bmarks = plot(ax1 (1),behT(CS),p(behI(CS)),[Bcolors(cc) Bshapes(ss)]);
                              end
                     end
                  end
            end

        set(s3,'xlim',[DN(I(1)) DN(I(end))]);
        
        % --- Robust y-limits for speed plot ---
        mx = max(speedJJ(tagonI), [], 'omitnan');

        % fallback if tagonI is empty or speedJJ is all NaN in tagon interval
        if isempty(mx) || ~isfinite(mx) || mx <= 0
            mx = max(speedJJ(I), [], 'omitnan');     % use current window instead
        end

        % final fallback if still bad
        if isempty(mx) || ~isfinite(mx) || mx <= 0
            mx = 1;
        end

        set(s3, 'ylim', [0 1.1*mx], 'xlim', [DN(I(1)) DN(I(end))]);

        set(s3,'xticklabel',datestr(get(gca,'xtick'),'HH:MM:SS'));
        ylabel('Speed');

        button = 1;
        redraw = false;
        close2lunge = 15;
        if strcmp(whaleName(1:2),'bb'); close2lunge = 5; end
        
        while ~isempty(button)
            redraw = false;
            if ishandle(ax2)
                [x,~,button] = ginput(1);
                if isempty(button); continue; end
                switch button
                    case 1
                        [~,xI] = min(abs(DN-x));
                        [~,mI] = max(speedJJ(xI-5*fs:xI+5*fs)); %find the max within 5 seconds
                        mI = mI +xI-5*fs - 1;
                        if any(abs(LI-xI)<close2lunge*fs); %if it's close, change one that exists
                            [~,delI] = min(abs(L-x));
                            L(delI) = []; LI(delI) = []; LC(delI) = [];
                            LC = [LC;3];
                            [L,II] = sort([L; x]);   
                            LI = sort([LI;xI]);
                            LC = LC(II);
                        else
                            LC = [LC; 3];
                            [L,II] = sort([L;DN(mI)]); LI = sort([LI;mI]); LC = LC(II);
                        end
                    case 108 %l selected - likely lunge
                        [~,xI] = min(abs(DN-x));
                        [~,mI] = max(speedJJ(xI-5*fs:xI+5*fs)); %find the max within 5 seconds
                        mI = mI +xI-5*fs - 1;
                        if any(abs(LI-xI)<close2lunge*fs); %if it's close, change one that exists
                            [~,delI] = min(abs(L-x));
                            L(delI) = []; LI(delI) = []; LC(delI) = [];
                            LC = [LC;2];
                            [L,II] = sort([L; x]);   
                            LI = sort([LI;xI]);
                            LC = LC(II);
                        else
                            LC = [LC; 2];
                            [L,II] = sort([L;DN(mI)]); LI = sort([LI;mI]); LC = LC(II);
                        end
                    case 109 %m selected - maybe lunge
                        [~,xI] = min(abs(DN-x));
                        [~,mI] = max(speedJJ(xI-5*fs:xI+5*fs)); %find the max within 5 seconds
                        mI = mI +xI-5*fs - 1;
                        if any(abs(LI-xI)<close2lunge*fs); %if it's close, change one that exists
                            [~,delI] = min(abs(L-x));
                            L(delI) = []; LI(delI) = []; LC(delI) = [];
                            LC = [LC;1];
                            [L,II] = sort([L; x]);   
                            LI = sort([LI;xI]);
                            LC = LC(II);
                        else
                            LC = [LC;1];
                            [L,II] = sort([L;DN(mI)]); LI = sort([LI;mI]); LC = LC(II);
                        end

                    case 103 % g toggle BehaviorState
                        if isempty(BehaviorState)
                            BehaviorState = 1;
                        elseif BehaviorState < 4
                            BehaviorState = BehaviorState + 1;
                        else
                            BehaviorState = [];
                        end
                            
                    case 113 %q mark state1
                        [~, BehaviorI] = min(abs(DN-x));
                        if ~isempty (BehaviorState)
                            behS = [behS;BehaviorState];
                            behSS = [behSS;2];
                            [behT,II] = sort([behT;DN(BehaviorI-1)]); behI = sort([behI;BehaviorI-1]); behS = behS(II); behSS = behSS(II);              
                        end
                        BehaviorState = 1;
                        behS = [behS;BehaviorState];
                            behSS = [behSS;1];
                            [behT,II] = sort([behT;DN(BehaviorI)]); behI = sort([behI;BehaviorI]); behS = behS(II); behSS = behSS(II); 
                             
                    case 119 %w mark state2
                        [~, BehaviorI] = min(abs(DN-x));
                         if ~isempty (BehaviorState)
                      behS = [behS;BehaviorState];
                            behSS = [behSS;2];
                            [behT,II] = sort([behT;DN(BehaviorI-1)]); behI = sort([behI;BehaviorI-1]); behS = behS(II); behSS = behSS(II);              
                        end
                        BehaviorState = 2;
                        behS = [behS;BehaviorState];
                            behSS = [behSS;1];
                            [behT,II] = sort([behT;DN(BehaviorI)]); behI = sort([behI;BehaviorI]); behS = behS(II); behSS = behSS(II); 
                             
                    case 101 %e mark state3
                        [~, BehaviorI] = min(abs(DN-x))
                         if ~isempty (BehaviorState)
                            behS = [behS;BehaviorState];
                            behSS = [behSS;2];
                            [behT,II] = sort([behT;DN(BehaviorI-1)]); behI = sort([behI;BehaviorI-1]); behS = behS(II); behSS = behSS(II);              
                        end
                        BehaviorState = 3;
                        behS = [behS;BehaviorState];
                            behSS = [behSS;1];
                            [behT,II] = sort([behT;DN(BehaviorI)]); behI = sort([behI;BehaviorI]); behS = behS(II); behSS = behSS(II); 
                             
                        
                    case 114 %r mark state 4
                        [~, BehaviorI] = min(abs(DN-x))
                         if ~isempty (BehaviorState)
                            behS = [behS;BehaviorState];
                            behSS = [behSS;2];
                            [behT,II] = sort([behT;DN(BehaviorI-1)]); behI = sort([behI;BehaviorI-1]); behS = behS(II); behSS = behSS(II);              
                        end
                        BehaviorState = 4;
                        behS = [behS;BehaviorState];
                            behSS = [behSS;1];
                            [behT,II] = sort([behT;DN(BehaviorI)]); behI = sort([behI;BehaviorI]); behS = behS(II); behSS = behSS(II); 
                             
                        
                    case 116 %t delete state
                        [~, delB] = min(abs(DN-x))
                        [~, btI] = min(abs(behI-delB))
                        behI(btI) = [];
                        behT(btI) = [];
                        behS(btI) = [];
                        behSS(btI) = [];
                        %clear delB btI
                        redraw = true; button = [];
                        
                    case 121 %y place end state marker (for final open state or corrections)
                        [~, BehaviorI] =  min(abs(DN-x));
                        if ~isempty (BehaviorState)
                            behS = [behS;BehaviorState];
                            behSS = [behSS;2];
                            [behT,II] = sort([behT;DN(BehaviorI)]); behI = sort([behI;BehaviorI]); behS = behS(II); behSS = behSS(II);              
                        end
                        
                    case 104 % set progressIndex to last point
                        if ~isempty(behI) || ~isempty(LI)
                            i = max([behI(:); LI(:)]);
                        else
                            i = find(tagon,1); % safe fallback
                        end
                        redraw = true; button = [];

                    case 3 % delete a lunge
                        [~,delI] = min(abs(L-x));
                        L(delI) = []; LI(delI) = []; LC(delI) = [];
                          redraw = true; button = [];           

                    case 98 %if b, go backwards
                        i = max(find(tagon,1),i-M*60*fs);
                        redraw = true; button = [];
                    case num2cell(49:57) %if you press a number, change drawing to 10*that number
                        M = 10*(button-48);
                        redraw = true; button = [];
                    case 115 %s selected - save progress
                        % set the created on date vector
                        d1 = datevec(now());
                        created_on = [d1(2) d1(3) d1(1)];
                        clearvars d1;
                        % store temp variables to lunge file 
                        starttime = DN(1);
                        prh_fs = fs;
                        LungeDN = L;
                        depth = p(LI);
                        time = L;
                        LungeI = LI;
                        LungeC = LC;
                        LungeDepth = depth;
                        progressIndex = i;
                        save(fullfile([fileloc baseName 'lunges.mat'],'LungeDN','LungeI','LungeDepth','LungeC','creator','primary_cue','prh_fs','starttime','created_on', 'progressIndex', 'notes'));

                        %store behavior variables to BehaviorState file
                        BehaviorIndex = behI;
                        BehaviorTime = behT;
                        Behavior = behS;
                        StartStop = behSS;
                        save(fullfile([fileloc, baseName 'BehaviorState.mat'],'starttime','prh_fs','progressIndex','creator','created_on','notes','BehaviorIndex','BehaviorTime','Behavior','StartStop'));
                     
                end
                if ~isempty(L)
                    try delete(marks); catch; end
                    %change color base on confidence
                    colors = 'rbk';
                    for c=1:3
                        II = find(LC==c);
                        if ~isempty(II)
                            marks(1) = plot(ax1(1),L(II),p(LI(II)),[colors(c) 's'],'markerfacecolor',colors(c));
                            marks(2) = plot(ax2(1),L(II),pitch(LI(II))*180/pi,[colors(c) 's'],'markerfacecolor',colors(c));
                            marks(3) = plot(s3,L(II),speedJJ(LI(II)),[colors(c) 's'],'markerfacecolor',colors(c));
                        end
                    end 
                end

%plot behavior points
            if ~isempty(behI)
                 try delete(Bmarks); catch; end;
                  Bcolors = 'rgkc';
                  Bshapes = 'ox';
                  for ss = 1:2;
                          SS = find (behSS==ss);
            %change cc end value to # of behavioral states used
                     for cc = 1:4
                      QQ = find (behS==cc);
                          CS = intersect(QQ,SS);
                              if ~isempty(CS)
                                   Bmarks = plot(ax1 (1),behT(CS),p(behI(CS)),[Bcolors(cc) Bshapes(ss)])
                              end
                     end
                  end
            end
            %create textbox for auditor to keep track of state
            BehaviorText = states(BehaviorState);
            if exist('ba')==1; delete(findall(gcf,'tag','ba')); end;
            if ~isempty(BehaviorState);
            ba = annotation('textbox',[.5, 0.1, 0, 0],'string',BehaviorText,'FitBoxToText','on','tag','ba','color',Bcolors(BehaviorState));
            end

            end
        end
        if redraw
            continue;
        else
            i = e;
        end
    end
    % set the created on date vector
    d1 = datevec(now());
    created_on = [d1(2) d1(3) d1(1)];
    clearvars d1;
    % store temp variables to lunge file 
    starttime = DN(1);
    prh_fs = fs;
    LungeDN = L;
    depth = p(LI);
    time = L;
    LungeI = LI;
    LungeC = LC;
    LungeDepth = depth;
    progressIndex = i;
    save([fileloc baseName 'lunges.mat'],'LungeDN','LungeI','LungeDepth','LungeC','creator','primary_cue','prh_fs','starttime','created_on', 'progressIndex', 'notes');

                        %store behavior variables to BehaviorState file
                        BehaviorIndex = behI;
                        BehaviorTime = behT;
                        Behavior = behS;
                        StartStop = behSS;
                        save([fileloc baseName 'BehaviorState.mat'],'starttime','prh_fs','progressIndex','creator','created_on','notes','BehaviorIndex','BehaviorTime','Behavior','StartStop','states');

    end
    
%% 3. Clean up variables (behavior audit only)
% Check for errors in cell. Returns CheckResult variable with indices of
% suspected errors along with a description. Use progressIndex = I where
% I is an idex returned in column one of the error check and run section 2
% again to view in plot. 
clear CheckResult;
for i = 1:length(behI)
    if behSS(i) == 1
        if i<length(behI) && behSS(i+1) == 1
            if ~exist('CheckResult','var')
           CheckResult = {behI(i),'previous behavior ongoing'};
            else
                CheckResult(end+1,1) = {behI(i)}; CheckResult(end,2)= {'previous behavior ongoing'}
            end
    elseif i == length(behI)
             if ~exist('CheckResult','var')
                CheckResult = {behI(i),'ongoing final behavior'};
            else
                CheckResult(end+1,1) = {behI(i)}; CheckResult(end,2)= {'ongoing final behavior'}
             end
        end
    end

    if behSS(i) == 2
        if i<length(behI) && behSS(i+1) == 2
             if ~exist('CheckResult','var')
           CheckResult = {behI(i),'double stop'};
            else
                CheckResult(end+1,1) = {behI(i)}; CheckResult(end,2)= {'double stop'}
             end
        end
        if i > 1 && i < length(behI) && behSS(i-1) == 1 && behS(i-1) ~= behS(i)
             if ~exist('CheckResult','var')
           CheckResult = {behI(i),'end behavior does not match open behavior'};
            else
                CheckResult(end+1,1) = {behI(i)}; CheckResult(end,2)= {'end behavior does not match open behavior'}
             end
        end
    end
        
end

%% 4. Export behavior state excel file
% Exports excel file in same format as .mat file
SStext ={'start','stop'};
for i = 1:length(behS)
    sText(i) = states(behS(i));
    ssText(i)= SStext(behSS(i));
end
    sText = sText(:); ssText = ssText(:);
    depName(1:length(behS)) = {convertCharsToStrings(whaleName)}; depName = depName(:);
    Headings = {'Deployment','Time','Index','Behavior','Start/Stop'};
    Table = table(depName,datestr(BehaviorTime),BehaviorIndex,sText,ssText,'VariableNames',Headings);
    writetable(Table,[whaleName 'BehaviorStates.xlsx']);  
%% 5. Calculate durations and export excel file
% exports excel file with durations for each state
clear durTable newTable
Headings = {'Deployment','State','Start time','End time','Duration'};
for i = 1:length(states)
    clear newTable depName statename
      I  = find(behS == i);
      Istart = find(behSS(I) == 1);
      Istop = find(behSS(I) == 2);
      depName(1:length(Istart)) = {convertCharsToStrings(whaleName)}; depName = depName(:);
      statename(1:length(Istart)) = states(i);statename = statename(:);
      if ~exist('durTable')
         durTable = table(depName,statename,datestr(behT(Istart)),datestr(behT(Istop)),between(datetime(behT(Istart),'ConvertFrom','datenum'),datetime(behT(Istop),'ConvertFrom','datenum'),'time'),'VariableNames',Headings);
      else
          newTable = table(depName,statename,datestr(behT(Istart)),datestr(behT(Istop)),between(datetime(behT(Istart),'ConvertFrom','datenum'),datetime(behT(Istop),'ConvertFrom','datenum'),'time'),'VariableNames',Headings);
          durTable = [durTable;newTable];
      end
end
    writetable(durTable,[whaleName 'BehaviorDurations.xlsx']);  
%% for just flownoise
i = 1;
fs = 10;
   if exist('LungeDN','var')
        L = LungeDN;
        LI = LungeI;
    elseif exist('time','var');
        L = time;
        for ii = 1:length(L)
            [~,LI(ii)] = min(abs(DN-L(ii)));
        end
        if size(LI,2)>1;
            LI = LI';
        end
    else
        L = nan(0,0);
        LI = nan(0,0);
    end
while i<length(DN)
    figure(1); clf
    e = min(i+(M+1)*60*fs-1,length(DN));
    %         if isempty(e)||isnan(e); e = length(p); end
    I = max(i-60*fs,1):e;
    %         tagonI = false(size(p)); tagonI(I) = true;
    %         tagonI = tagon&tagonI;
    %         s1 = subplot(3,1,1);
    %         [ax1,~,h2] = plotyy(DN(I),p(I),DN(I),J(I));
    %         set(ax1(1),'ydir','rev','nextplot','add','ylim',[-5 max(p(tagonI))]);
    %         ylabel('Jerk','parent',ax1(2));
    %         ylabel('Depth','parent',ax1(1));
    %         set(ax1(2),'ycolor','m','ylim',[0 1.2*max(J(tagonI))]);
    %         set(h2,'color','m');
    %         set(ax1,'xlim',[DN(I(1)) DN(I(end))]);
    %         set(ax1,'xticklabel',datestr(get(gca,'xtick'),'mm/dd HH:MM:SS'));
    %         s2 = subplot(3,1,2);
    %         uistack(ax1(1));
    %         set(ax1(1), 'Color', 'none');
    %         set(ax1(2), 'Color', 'w')
    %         [ax2,h1,h2] = plotyy(DN(I),pitch(I)*180/pi,DN(I),roll(I)*180/pi); set(ax2(2),'nextplot','add','ycolor','k','ylim',[-180 180]);
    %         ylabel('Roll and Head','parent',ax2(2));
    %         plot(ax2(2),DN(I),head(I)*180/pi,'b.','markersize',4);
    %         set(ax2(1),'ycolor','g','nextplot','add','ylim',[-90 90]);
    %         ylabel('pitch','parent',ax2(1));
    %         set(h1,'color','g'); set(h2,'color','r','linestyle','.','markersize',4);
    %          set(ax2,'xlim',[DN(I(1)) DN(I(end))]);
    %         set(ax2,'xticklabel',datestr(get(gca,'xtick'),'HH:MM:SS'));
    %         s3 = subplot(3,1,3);
    ax3 = plot(DN(I),flownoise(I));%,'b',DN(I),speedFN(I),'g');
    set(gca,'nextplot','add');
    marks = nan(1,3);
    if ~isempty(L)
        %             marks(1) = plot(ax1(1),L,p(LI),'rs','markerfacecolor','r');
        %             marks(2) = plot(ax2(1),L,pitch(LI)*180/pi,'rs','markerfacecolor','r');
        marks(3) = plot(gca,L,flownoise(LI),'rs','markerfacecolor','r');
    end
    set(gca,'xlim',[DN(I(1)) DN(I(end))]);
    set(gca,'ylim',[1.1*min(flownoise(I)) 0.8*max(flownoise(I))],'xlim',[DN(I(1)) DN(I(end))]);
    set(gca,'xticklabel',datestr(get(gca,'xtick'),'HH:MM:SS'));
    ylabel('Speed');
    button = 1;
%     title(filename(1:end-12));
    redraw = false;
    while ~isempty(button)
        try [x,~,button] = ginput(1); catch; end %JAF added TryCatch
        if isempty(button); continue; end
        switch button
            case 1
                [~,xI] = min(abs(DN-x));
                [~,mI] = max(flownoise(xI-5*fs:xI+5*fs)); %find the max within 5 seconds
                mI = mI +xI-5*fs - 1;
                if any(abs(LI-xI)<15*fs); %if it's close, change one that exists
                    [~,delI] = min(abs(L-x));
                    L(delI) = []; LI(delI) = [];
                    L=sort([L; x]); LI = sort([LI;xI]);
                else
                    L = sort([L;DN(mI)]); LI = sort([LI;mI]);
                end
            case 3 % delete an x
                [~,delI] = min(abs(L-x));
                L(delI) = []; LI(delI) = [];
            case 98 %if b, go backwards
                i = max(find(tagon,1),i-M*60*fs);
                redraw = true; button = [];
            case num2cell(49:57) %if you press a number, change drawing to 10*that number
                M = 10*(button-48);
                redraw = true; button = [];
        end
        if ~isempty(L)
            try delete(marks); catch; end
            %                 marks(1) = plot(ax1(1),L,p(LI),'rs','markerfacecolor','r');
            %                 marks(2) = plot(ax2(1),L,pitch(LI)*180/pi,'rs','markerfacecolor','r');
            marks(3) = plot(gca,L,speedJJ(LI),'rs','markerfacecolor','r');
        end
    end
    if redraw
        continue;
    else
        i = e;
    end
end
LungeDN = L;
depth = p(LI);
time = L;
LungeI = LI;
oi2 = strfind(fileloc,'\');
socalname = [fileloc(oi2(end-1)+1:oi2(end-1)+13) '-' filename(1:2)];
% save(['B:\Dropbox\Shared\AcouDarts\' socalname 'lunges'],'depth','time'); %
% save([fileloc filename(1:end-12) 'lunges.mat'],'LungeDN','LungeI');

%% 6. Activity budget summary (total time + percent time per state)
% Requires properly paired start/stop markers for each bout.
% If CheckResult flags issues, fix those first.

if exist('behT','var') && ~isempty(behT) && exist('behSS','var') && ~isempty(behSS)

    % Convert to datetime for safer duration handling
    tAll = datetime(behT,'ConvertFrom','datenum');

    budget = table('Size',[numel(states) 5], ...
        'VariableTypes',{'string','double','double','double','double'}, ...
        'VariableNames',{'State','NumBouts','TotalMinutes','TotalHours','Percent'});

    budget.State = string(states(:));

    totalSecAllStates = 0;
    totalSecPerState = zeros(numel(states),1);

    for s = 1:numel(states)
        I = find(behS == s);
        Istart = I(behSS(I) == 1);
        Istop  = I(behSS(I) == 2);

        % Defensive: pair starts/stops in order
        n = min(numel(Istart), numel(Istop));
        Istart = Istart(1:n);
        Istop  = Istop(1:n);

        if n == 0
            budget.NumBouts(s) = 0;
            budget.TotalMinutes(s) = 0;
            budget.TotalHours(s) = 0;
            continue
        end

        d = seconds(tAll(Istop) - tAll(Istart));
        d(d < 0) = 0; % guard against mis-ordered markers

        totalSecPerState(s) = sum(d);
        totalSecAllStates = totalSecAllStates + totalSecPerState(s);

        budget.NumBouts(s) = n;
        budget.TotalMinutes(s) = totalSecPerState(s) / 60;
        budget.TotalHours(s) = totalSecPerState(s) / 3600;
    end

    if totalSecAllStates > 0
        budget.Percent = 100 * (totalSecPerState / totalSecAllStates);
    else
        budget.Percent(:) = 0;
    end

    disp('--- Activity Budget Summary ---');
    disp(budget);

    % Save alongside other outputs
    writetable(budget, [whaleName '_ActivityBudgetSummary.csv']);

else
    warning('No behavior state annotations found (behT/behSS empty).');
end

