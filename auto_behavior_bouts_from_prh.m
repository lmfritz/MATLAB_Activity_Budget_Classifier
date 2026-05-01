function boutTbl = auto_behavior_bouts_from_prh(prhPath)

S = load(prhPath);

% --- required vars ---
p = S.p(:);

if isfield(S, 'fs') && ~isempty(S.fs)
    fs = S.fs;
elseif isfield(S, 'fs1') && ~isempty(S.fs1)
    fs = S.fs1;
else
    error('No fs or fs1 found in %s', prhPath);
end

if isfield(S, 'tagon') && ~isempty(S.tagon)
    tagon = logical(S.tagon(:));
else
    tagon = isfinite(p);
end

% --- optional variables ---
pitch = nan(size(p));
if isfield(S, 'pitch') && ~isempty(S.pitch)
    pitch = S.pitch(:);
end

% choose a speed variable if available
speed = nan(size(p));
if isfield(S, 'speed') && istable(S.speed)
    if any(strcmp('JJ', S.speed.Properties.VariableNames))
        speed = S.speed.JJ;
    elseif any(strcmp('FN', S.speed.Properties.VariableNames))
        speed = S.speed.FN;
    end
elseif isfield(S, 'speed') && isnumeric(S.speed) && numel(S.speed) == numel(p)
    speed = S.speed(:);
end

% simple movement proxy placeholder
% replace this later with your preferred movement metric if needed
movement = nan(size(p));
if isfield(S, 'Aw') && ~isempty(S.Aw)
    Aw = S.Aw;
    if size(Aw,2) == 3
        movement = sqrt(sum(Aw.^2, 2));
    end
end

% placeholder lunge mask
lungeMask = false(size(p));

% --- define bouts ---
SUB_THRESH = 0.5;
MIN_BOUT_DUR = 1;

isSub = tagon & isfinite(p) & (p > SUB_THRESH);

boutStart = find(diff([false; isSub]) == 1);
boutEnd   = find(diff([isSub; false]) == -1);

boutDur = (boutEnd - boutStart + 1) ./ fs;
keep = boutDur >= MIN_BOUT_DUR;

boutStart = boutStart(keep);
boutEnd   = boutEnd(keep);

nBouts = numel(boutStart);

if nBouts == 0
    boutTbl = table();
    return
end

% --- summarize bout-level variables ---
bout_id        = (1:nBouts)';
duration_s     = nan(nBouts,1);
max_depth_m    = nan(nBouts,1);
mean_speed     = nan(nBouts,1);
sd_speed       = nan(nBouts,1);
mean_movement  = nan(nBouts,1);
sd_movement    = nan(nBouts,1);
pitch_sd       = nan(nBouts,1);
n_lunges       = nan(nBouts,1);

for b = 1:nBouts
    idx = boutStart(b):boutEnd(b);

    duration_s(b)    = numel(idx) ./ fs;
    max_depth_m(b)   = max(p(idx), [], 'omitnan');
    mean_speed(b)    = mean(speed(idx), 'omitnan');
    sd_speed(b)      = std(speed(idx), 'omitnan');
    mean_movement(b) = mean(movement(idx), 'omitnan');
    sd_movement(b)   = std(movement(idx), 'omitnan');
    pitch_sd(b)      = std(pitch(idx), 'omitnan');
    n_lunges(b)      = sum(lungeMask(idx));
end

% --- temporary state assignment ---
state = repmat("Unclassified", nBouts, 1);

% metadata
[folder, baseName, ext] = fileparts(prhPath);
file = string([baseName ext]);
folder = string(folder);

if isfield(S,'INFO') && isfield(S.INFO,'whaleName') && ~isempty(S.INFO.whaleName)
    whaleName = string(S.INFO.whaleName);
else
    whaleName = "unknown";
end

depID = string(baseName);
prhPathCol = repmat(string(prhPath), nBouts, 1);
fileCol = repmat(file, nBouts, 1);
folderCol = repmat(folder, nBouts, 1);
whaleCol = repmat(whaleName, nBouts, 1);
depCol = repmat(depID, nBouts, 1);

boutTbl = table( ...
    bout_id, state, boutStart, boutEnd, duration_s, max_depth_m, ...
    mean_speed, sd_speed, mean_movement, sd_movement, pitch_sd, n_lunges, ...
    whaleCol, depCol, prhPathCol, fileCol, folderCol, ...
    'VariableNames', { ...
    'bout_id','state','start_idx','end_idx','duration_s','max_depth_m', ...
    'mean_speed','sd_speed','mean_movement','sd_movement','pitch_sd','n_lunges', ...
    'whaleName','depID','prhPath','file','folder'});

end