function out = calc_surface_interval_features(diveStarts, diveStops, LI, p, speed, movement, pitch, fs, DN)
% calc_surface_interval_features
%
% Calculate features for surface intervals between consecutive dives.
%
% INPUTS
%   diveStarts - nDives x 1 dive start indices
%   diveStops  - nDives x 1 dive stop indices
%   LI         - nLunges x 1 lunge indices in PRH sample space
%   p          - Nx1 depth vector
%   speed      - Nx1 speed vector
%   movement   - Nx1 movement vector
%   pitch      - Nx1 pitch vector
%   fs         - sampling rate (Hz)
%   DN         - optional Nx1 datenum vector
%
% OUTPUT
%   out - struct with pairTable and summary

    % ---------- Input cleanup ----------
    diveStarts = diveStarts(:);
    diveStops  = diveStops(:);
    p          = p(:);
    speed      = speed(:);
    movement   = movement(:);
    pitch      = pitch(:);

    if nargin < 3 || isempty(LI)
        LI = [];
    else
        LI = LI(:);
    end

    if nargin < 8 || isempty(fs) || ~isscalar(fs)
        error('fs is required and must be a scalar.');
    end

    hasDN = (nargin >= 9) && ~isempty(DN);
    if hasDN
        DN = DN(:);
        if numel(DN) ~= numel(p)
            warning('DN length does not match p. Ignoring DN.');
            hasDN = false;
        end
    end

    nDives = numel(diveStarts);

    if numel(diveStops) ~= nDives
        error('diveStarts and diveStops must have the same length.');
    end

    if nDives < 2
        warning('Fewer than 2 dives found. No consecutive surface intervals can be calculated.');
        out = makeEmptyOutput(nDives);
        return
    end

    % Keep only in-range lunges
    LI = LI(isfinite(LI) & LI >= 1 & LI <= numel(p));

    % ---------- Determine which dives are foraging ----------
    isForagingDive = false(nDives, 1);
    nLungesDive    = zeros(nDives, 1);
    diveMaxDepth   = nan(nDives, 1);

    diveStartDN = nan(nDives, 1);
    diveStopDN  = nan(nDives, 1);

    for di = 1:nDives
        a = diveStarts(di);
        b = diveStops(di);

        if ~isfinite(a) || ~isfinite(b) || a < 1 || b > numel(p) || a > b
            error('Invalid dive bounds at dive %d: start=%g, stop=%g', di, a, b);
        end

        diveMaxDepth(di) = max(p(a:b), [], 'omitnan');

        if hasDN
            diveStartDN(di) = DN(a);
            diveStopDN(di)  = DN(b);
        end

        if ~isempty(LI)
            lungesHere = LI >= a & LI <= b;
            nLungesDive(di) = sum(lungesHere);
            isForagingDive(di) = nLungesDive(di) > 0;
        end
    end

    % ---------- Surface intervals between consecutive dives ----------
    nPairs = nDives - 1;

    pairIdx = (1:nPairs)';
    Dive1   = pairIdx;
    Dive2   = pairIdx + 1;

    PrevDiveForaging = isForagingDive(1:end-1);
    NextDiveForaging = isForagingDive(2:end);

    PrevDiveLunges   = nLungesDive(1:end-1);
    NextDiveLunges   = nLungesDive(2:end);

    PrevDive_maxDepth = diveMaxDepth(1:end-1);
    NextDive_maxDepth = diveMaxDepth(2:end);

    % Time-based outputs from indices/fs
    SurfaceInterval_samples = diveStarts(2:end) - diveStops(1:end-1) - 1;
    SurfaceInterval_sec     = SurfaceInterval_samples ./ fs;
    SurfaceInterval_min     = SurfaceInterval_sec ./ 60;

    % Optional DN outputs
    if hasDN
        Dive1_StartDN = diveStartDN(1:end-1);
        Dive1_EndDN   = diveStopDN(1:end-1);
        Dive2_StartDN = diveStartDN(2:end);
        Dive2_EndDN   = diveStopDN(2:end);
        SurfaceInterval_DN = Dive2_StartDN - Dive1_EndDN;
    else
        Dive1_StartDN = nan(nPairs,1);
        Dive1_EndDN   = nan(nPairs,1);
        Dive2_StartDN = nan(nPairs,1);
        Dive2_EndDN   = nan(nPairs,1);
        SurfaceInterval_DN = nan(nPairs,1);
    end

    % ---------- Summarize each surface interval ----------
    mean_speed_surface    = nan(nPairs,1);
    sd_speed_surface      = nan(nPairs,1);
    mean_movement_surface = nan(nPairs,1);
    sd_movement_surface   = nan(nPairs,1);
    pitch_sd_surface      = nan(nPairs,1);
    max_depth_surface     = nan(nPairs,1);
    mean_depth_surface    = nan(nPairs,1);
    nSamples_surface      = nan(nPairs,1);

    for pi = 1:nPairs
        a = diveStops(pi);
        b = diveStarts(pi+1);

        idx = (a+1):(b-1);

        if isempty(idx) || a >= b-1
            nSamples_surface(pi) = 0;
            continue
        end

        idx = idx(idx >= 1 & idx <= numel(p));

        if isempty(idx)
            nSamples_surface(pi) = 0;
            continue
        end

        nSamples_surface(pi)      = numel(idx);
        mean_speed_surface(pi)    = mean(speed(idx), 'omitnan');
        sd_speed_surface(pi)      = std(speed(idx), 'omitnan');
        mean_movement_surface(pi) = mean(movement(idx), 'omitnan');
        sd_movement_surface(pi)   = std(movement(idx), 'omitnan');
        pitch_sd_surface(pi)      = std(pitch(idx), 'omitnan');
        max_depth_surface(pi)     = max(p(idx), [], 'omitnan');
        mean_depth_surface(pi)    = mean(p(idx), 'omitnan');
    end

    pairTable = table( ...
        Dive1, Dive2, ...
        PrevDiveForaging, NextDiveForaging, ...
        PrevDiveLunges, NextDiveLunges, ...
        PrevDive_maxDepth, NextDive_maxDepth, ...
        Dive1_StartDN, Dive1_EndDN, Dive2_StartDN, Dive2_EndDN, ...
        SurfaceInterval_DN, SurfaceInterval_samples, SurfaceInterval_sec, SurfaceInterval_min, ...
        nSamples_surface, ...
        max_depth_surface, mean_depth_surface, ...
        mean_speed_surface, sd_speed_surface, ...
        mean_movement_surface, sd_movement_surface, ...
        pitch_sd_surface, ...
        'VariableNames', { ...
        'Dive1', 'Dive2', ...
        'PrevDiveForaging', 'NextDiveForaging', ...
        'PrevDiveLunges', 'NextDiveLunges', ...
        'PrevDive_maxDepth', 'NextDive_maxDepth', ...
        'Dive1_StartDN', 'Dive1_EndDN', 'Dive2_StartDN', 'Dive2_EndDN', ...
        'SurfaceInterval_DN', 'SurfaceInterval_samples', 'SurfaceInterval_sec', 'SurfaceInterval_min', ...
        'nSamples_surface', ...
        'max_depth_surface', 'mean_depth_surface', ...
        'mean_speed_surface', 'sd_speed_surface', ...
        'mean_movement_surface', 'sd_movement_surface', ...
        'pitch_sd_surface'});

    summary = table( ...
        nDives, ...
        sum(isForagingDive), ...
        nPairs, ...
        sum(PrevDiveForaging), ...
        mean(SurfaceInterval_sec, 'omitnan'), ...
        median(SurfaceInterval_sec, 'omitnan'), ...
        'VariableNames', { ...
        'nDives', ...
        'nForagingDives', ...
        'nSurfaceIntervals', ...
        'nIntervalsAfterForaging', ...
        'meanSurfaceInterval_sec', ...
        'medianSurfaceInterval_sec'});

    out = struct();
    out.isForagingDive = isForagingDive;
    out.nLungesDive = nLungesDive;
    out.diveMaxDepth = diveMaxDepth;
    out.summary = summary;
    out.pairTable = pairTable;
end

function out = makeEmptyOutput(nDives)
    out = struct();
    out.isForagingDive = false(nDives,1);
    out.nLungesDive = zeros(nDives,1);
    out.diveMaxDepth = [];
    out.summary = table();
    out.pairTable = table();
end