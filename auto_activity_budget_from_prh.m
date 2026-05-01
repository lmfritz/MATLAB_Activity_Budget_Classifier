function out = auto_activity_budget_from_prh(prhPath)

% Headless version of the auto activity classifier

if nargin < 1 || isempty(prhPath)
    [f,p] = uigetfile('* 10Hzprh.mat','Select PRH file');
    if isequal(f,0)
        error('No file selected');
    end
    prhPath = fullfile(p,f);
end

% Uses SAME parameters & movement proxy logic as the original script.
%
% Inputs:
%   prhPath - full path to "* 10Hzprh.mat"
% Output:
%   out struct with % per state + metadataif nargin < 1 || isempty(prhPath)


% -----------------------------
% Standardized output fields
% -----------------------------
out = struct( ...
    'status',"OK", ...
    'message',"", ...
    'prhPath',string(prhPath), ...
    'folder',"", ...
    'file',"", ...
    'depID',"", ...
    'whaleName',"", ...
    'tagOnHours',NaN, ...
    'pct_resting',NaN, ...
    'pct_traveling',NaN, ...
    'pct_foraging',NaN, ...
    'pct_exploring',NaN, ...
    'nSamples',NaN, ...
    'nDives',NaN, ...
    'nValidLunges',0);

try
    [fileloc, filename, ~] = fileparts(prhPath);
    out.folder = string(fileloc);
    out.file   = string(filename);

    % -----------------------------
    % Load PRH variables
    % -----------------------------
    S = load(prhPath);

    % Required
    p     = S.p(:);
    DN    = S.DN(:);
    tagon = S.tagon(:);
    fs    = S.fs;

    % BaseName / depID like original
    baseName = filename;
    depID = regexp(baseName,'^[^ ]+','match','once');
    if isempty(depID), depID = baseName; end
    out.depID = string(depID);

    % whaleName logic like your script
    whaleName = depID;
    if isfield(S,'INFO') && isstruct(S.INFO) && isfield(S.INFO,'whaleName') && ~isempty(S.INFO.whaleName)
        whaleName = S.INFO.whaleName;
    else
        whaleName = regexprep(baseName, '\s+', '_');
    end
    whaleName = regexprep(string(whaleName), '[^\w\-]+', '_');
    out.whaleName = whaleName;

    % -----------------------------
    % Build speedJJ, speedFN, J (same logic)
    % -----------------------------
    N0 = min([numel(p), numel(DN), numel(tagon)]);
    p = p(1:N0); DN = DN(1:N0); tagon = tagon(1:N0);

    % speedJJ
    speedJJ = nan(size(p));

    if isfield(S,'speed') && isstruct(S.speed) && isfield(S.speed,'JJ') && ~isempty(S.speed.JJ)
        raw = S.speed.JJ(:);
        if ~all(isnan(raw))
            tmp = raw;
            tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));
            if exist('runmean','file')==2
                tmp = runmean(tmp, max(1,round(fs/2)));
            else
                tmp = movmean(tmp, max(1,round(fs/2)), 'omitnan');
            end
            tmp(isnan(raw)) = nan;
            n = min(numel(tmp), numel(speedJJ));
            speedJJ(1:n) = tmp(1:n);
        end
    end

    if all(isnan(speedJJ)) && isfield(S,'speed') && isstruct(S.speed) && isfield(S.speed,'FN') && ~isempty(S.speed.FN)
        raw = S.speed.FN(:);
        if ~all(isnan(raw))
            tmp = raw;
            tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));
            if exist('runmean','file')==2
                tmp = runmean(tmp, max(1,round(fs/2)));
            else
                tmp = movmean(tmp, max(1,round(fs/2)), 'omitnan');
            end
            tmp(isnan(raw)) = nan;
            n = min(numel(tmp), numel(speedJJ));
            speedJJ(1:n) = tmp(1:n);
        end
    end

    % J jerk proxy
    if exist('njerk','file') == 2 && isfield(S,'Aw') && ~isempty(S.Aw)
        J = njerk(S.Aw, fs);
        J = J(:);
    else
        if isfield(S,'Aw') && ~isempty(S.Aw)
            Aw = S.Aw;
            dAw = [zeros(1,size(Aw,2)); diff(Aw)];
            J = sqrt(sum(dAw.^2,2)) * fs;
        else
            J = nan(size(p));
        end
    end

    J = J(:);
    if numel(J) < numel(p), J(end+1:numel(p)) = J(end); end
    if numel(J) > numel(p), J = J(1:numel(p)); end

    % speedFN (not required for classifier but matches script ecosystem)
    speedFN = nan(size(p));
    if isfield(S,'speed') && isstruct(S.speed) && isfield(S.speed,'FN') && ~isempty(S.speed.FN)
        raw = S.speed.FN(:);
        if ~all(isnan(raw))
            tmp = raw;
            tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));
            if exist('runmean','file')==2
                tmp = runmean(tmp, max(1,round(fs/2)));
            else
                tmp = movmean(tmp, max(1,round(fs/2)), 'omitnan');
            end
            tmp(isnan(raw)) = nan;
            n = min(numel(tmp), numel(speedFN));
            speedFN(1:n) = tmp(1:n);
        end
    end %#ok<NASGU>

    % Movement proxy used by AUTO classifier (same)
    mov = speedJJ;
    if all(isnan(mov))
        mov = J;
    end

    % Align vectors (same defensive block)
    mov = mov(:);
    N = min([numel(p), numel(DN), numel(tagon), numel(mov)]);
    p = p(1:N); DN = DN(1:N); tagon = tagon(1:N); mov = mov(1:N);

    out.nSamples = N;
    out.tagOnHours = sum(tagon)/fs/3600;

    % -----------------------------
    % Find / load lunges (same philosophy; non-fatal if none)
    % -----------------------------
    % Parameters (same as your script)
    LUNGE_MIN_DEPTH_M = 10;

    LI = [];  % lunge indices into PRH
    useSubfolders = false; % set true if you want recursive search
    searchRoot = fileloc;

    if useSubfolders
        cand = dir(fullfile(searchRoot, '**', ['*' depID '*lunges.mat']));
    else
        cand = dir(fullfile(searchRoot, ['*' depID '*lunges.mat']));
    end
    cand = cand(~startsWith({cand.name}, '._'));

    bestFile = '';
    bestScore = -Inf;

    if ~isempty(cand)
        DNmin = min(DN); DNmax = max(DN);

        for k = 1:numel(cand)
            f = fullfile(cand(k).folder, cand(k).name);
            tmp = load(f);

            % Pull a datenum-ish time vector
            t = [];
            if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN; end
            if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time; end

            % If only indices exist, convert to DN for scoring
            if isempty(t) && isfield(tmp,'LungeI') && ~isempty(tmp.LungeI), t = DN(tmp.LungeI(:)); end
            if isempty(t) && isfield(tmp,'LI')     && ~isempty(tmp.LI),     t = DN(tmp.LI(:));     end
            if isempty(t) && isfield(tmp,'L')      && ~isempty(tmp.L),      t = tmp.L;            end

            if isempty(t), continue; end
            t = t(:);

            in = (t >= DNmin) & (t <= DNmax);
            nIn = sum(in);
            nTot = numel(t);

            frac = nIn / max(nTot,1);
            score = frac + 0.01*log1p(nIn);
            if nIn == 0, score = score - 1; end

            if score > bestScore
                bestScore = score;
                bestFile = f;
            end
        end

        if ~isempty(bestFile) && isfile(bestFile)
            tmp = load(bestFile);

            LungeI = [];
            LungeDN = [];
            if isfield(tmp,'LungeI'),  LungeI  = tmp.LungeI(:);  end
            if isfield(tmp,'LungeDN'), LungeDN = tmp.LungeDN(:); end
            if isempty(LungeI) && isfield(tmp,'LI'), LungeI = tmp.LI(:); end
            if isempty(LungeDN) && isfield(tmp,'time'), LungeDN = tmp.time(:); end

            if ~isempty(LungeDN)
                LI = nan(size(LungeDN));
                for j = 1:numel(LungeDN)
                    [~,LI(j)] = min(abs(DN - LungeDN(j)));
                end
                LI = LI(:);
            elseif ~isempty(LungeI)
                LI = LungeI(:);
            end

            LI = LI(isfinite(LI));
            LI = LI(LI>=1 & LI<=N);

            % Tyson filter (same)
            LI = LI(p(LI) >= LUNGE_MIN_DEPTH_M);
        end
    end

    out.nValidLunges = numel(LI);

    % -----------------------------
    % AUTO CLASSIFIER PARAMETERS (COPY of your block)
    % -----------------------------
    DIVE_THRESH_M   = 10;
    MIN_DIVE_DUR_S  = 30;
    TRAVEL_MIN_M    = 10;
    TRAVEL_MAX_M    = 50;

    REST_MIN_BOUT_S = 0;
    REST_DEPTH_MAX_M = 10;
    REST_MOV_PCTL   = 20;
    REST_SMOOTH_S   = 10;
    REST_GAPFILL_S  = 5;

    % -----------------------------
    % 1) Dive detection (same)
    % -----------------------------
    inDiveRaw = (p > DIVE_THRESH_M) & tagon;
    d = diff([false; inDiveRaw; false]);
    diveStarts = find(d == 1);
    diveStops  = find(d == -1) - 1;

    dur_s = (diveStops - diveStarts + 1) / fs;
    keep = dur_s >= MIN_DIVE_DUR_S;
    diveStarts = diveStarts(keep);
    diveStops  = diveStops(keep);

    nDives = numel(diveStarts);
    out.nDives = nDives;

    inDive = false(N,1);
    for di = 1:nDives
        inDive(diveStarts(di):diveStops(di)) = true;
    end

    % -----------------------------
    % 2) Dive-level labels: foraging vs traveling (same)
    % -----------------------------
    forageMask = false(N,1);
    travelMask = false(N,1);

    for di = 1:nDives
        a = diveStarts(di);
        b = diveStops(di);

        mx = max(p(a:b), [], 'omitnan');
        hasLunge = ~isempty(LI) && any(LI >= a & LI <= b);

        if hasLunge
            forageMask(a:b) = true;
        elseif mx >= TRAVEL_MIN_M && mx <= TRAVEL_MAX_M
            travelMask(a:b) = true;
        end
    end

    % -----------------------------
    % 3) Resting (surface-only; same)
    % -----------------------------
    w = max(1, round(REST_SMOOTH_S * fs));
    movS = mov;
    if any(isfinite(movS))
        movFill = movS;
        movFill(~isfinite(movFill)) = prctile(movFill(isfinite(movFill)), 5);
        if exist('runmean','file')==2
            movS = runmean(movFill, w);
        else
            movS = movmean(movFill, w, 'omitnan');
        end
    end

    valid = tagon & isfinite(movS);
    if sum(valid) < 100
        valid = isfinite(movS);
    end
    restThresh = prctile(movS(valid), REST_MOV_PCTL);

    surfaceInterval = tagon & ~inDive;
    restCand = surfaceInterval ...
        & (p >= 0) & (p <= REST_DEPTH_MAX_M) ...
        & isfinite(movS) & (movS <= restThresh);

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
    restMask(inDive) = false;

    % -----------------------------
    % 4) Final state (same priority)
    % -----------------------------
    % 1=resting, 2=traveling, 3=foraging, 4=exploring
    state = nan(N,1);
    state(tagon) = 4;
    state(travelMask & tagon) = 2;
    state(forageMask & tagon) = 3;
    state(restMask) = 1;

    % -----------------------------
    % Activity budget (% of tagon)
    % -----------------------------
    denom = sum(tagon);
    pct = nan(1,4);
    for s = 1:4
        pct(s) = 100 * sum(state(tagon) == s) / denom;
    end

    out.pct_resting   = pct(1);
    out.pct_traveling = pct(2);
    out.pct_foraging  = pct(3);
    out.pct_exploring = pct(4);

catch ME
    out.status = "ERROR";
    out.message = string(ME.message);
end