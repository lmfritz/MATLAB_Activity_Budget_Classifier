function out = calc_post_foraging_surface_intervals(DN, diveStarts, diveStops, LI)
% calc_foraging_surface_intervals
%
% Calculate surface intervals between consecutive dives, keeping only
% intervals where BOTH surrounding dives are foraging dives.
%
% INPUTS
%   DN         - Nx1 datenum vector for PRH samples
%   diveStarts - nDives x 1 vector of dive start indices
%   diveStops  - nDives x 1 vector of dive stop indices
%   LI         - nLunges x 1 vector of valid lunge indices in PRH sample space
%
% OUTPUT
%   out - struct containing:
%       .isForagingDive          logical vector, one per dive
%       .surfaceIntDN            surface intervals between all consecutive dives (days)
%       .surfaceIntSec           surface intervals between all consecutive dives (sec)
%       .surfaceIntMin           surface intervals between all consecutive dives (min)
%       .keepPairs               logical vector for consecutive foraging-foraging pairs
%       .foragingSurfaceIntDN    kept foraging-foraging intervals (days)
%       .foragingSurfaceIntSec   kept foraging-foraging intervals (sec)
%       .foragingSurfaceIntMin   kept foraging-foraging intervals (min)
%       .pairIdx                 indices of first dive in each kept pair
%       .summary                 table of summary statistics
%       .pairTable               table of kept dive pairs and intervals
%
% NOTES
%   - A dive is defined as foraging if it contains at least one lunge index in LI.
%   - Surface interval is defined as:
%         start time of dive i+1 - end time of dive i
%   - DN must be datenum. Outputs are provided in days, seconds, and minutes.
%
% EXAMPLE
%   out = calc_foraging_surface_intervals(DN, diveStarts, diveStops, LI);
%   disp(out.summary)
%   writetable(out.pairTable, 'foraging_surface_intervals.csv')

    % ---------- Input cleanup ----------
    DN = DN(:);
    diveStarts = diveStarts(:);
    diveStops = diveStops(:);

    if nargin < 4 || isempty(LI)
        LI = [];
    else
        LI = LI(:);
    end

    nDives = numel(diveStarts);

    if numel(diveStops) ~= nDives
        error('diveStarts and diveStops must have the same length.');
    end

    if isempty(DN)
        error('DN is empty.');
    end

    if nDives < 2
        warning('Fewer than 2 dives found. No consecutive surface intervals can be calculated.');
        out = makeEmptyOutput(nDives);
        return
    end

    % Keep only in-range lunge indices
    LI = LI(isfinite(LI) & LI >= 1 & LI <= numel(DN));

    % ---------- Determine which dives are foraging ----------
    isForagingDive = false(nDives, 1);
    diveStartDN = nan(nDives, 1);
    diveStopDN = nan(nDives, 1);

    for di = 1:nDives
        a = diveStarts(di);
        b = diveStops(di);

        if ~isfinite(a) || ~isfinite(b) || a < 1 || b > numel(DN) || a > b
            error('Invalid dive bounds at dive %d: start=%g, stop=%g', di, a, b);
        end

        diveStartDN(di) = DN(a);
        diveStopDN(di) = DN(b);

        if ~isempty(LI)
            isForagingDive(di) = any(LI >= a & LI <= b);
        end
    end

    % ---------- Surface intervals between all consecutive dives ----------
    surfaceIntDN = diveStartDN(2:end) - diveStopDN(1:end-1);
    surfaceIntSec = surfaceIntDN * 24 * 60 * 60;
    surfaceIntMin = surfaceIntDN * 24 * 60;

    % ---------- Keep only foraging-foraging pairs ----------
    keepPairs = isForagingDive(1:end-1);
    pairIdx = find(keepPairs);

    foragingSurfaceIntDN = surfaceIntDN(keepPairs);
    foragingSurfaceIntSec = surfaceIntSec(keepPairs);
    foragingSurfaceIntMin = surfaceIntMin(keepPairs);

    % ---------- Summary stats ----------
    nPairs = numel(foragingSurfaceIntSec);

    if nPairs > 0
        meanSec = mean(foragingSurfaceIntSec, 'omitnan');
        medianSec = median(foragingSurfaceIntSec, 'omitnan');
        stdSec = std(foragingSurfaceIntSec, 'omitnan');
        minSec = min(foragingSurfaceIntSec, [], 'omitnan');
        maxSec = max(foragingSurfaceIntSec, [], 'omitnan');
        meanMin = mean(foragingSurfaceIntMin, 'omitnan');
    else
        meanSec = NaN;
        medianSec = NaN;
        stdSec = NaN;
        minSec = NaN;
        maxSec = NaN;
        meanMin = NaN;
    end

    summary = table( ...
        nDives, ...
        sum(isForagingDive), ...
        nPairs, ...
        meanSec, ...
        meanMin, ...
        medianSec, ...
        stdSec, ...
        minSec, ...
        maxSec, ...
        'VariableNames', { ...
        'nDives', ...
        'nForagingDives', ...
        'nForagingPairs', ...
        'meanSurfaceInterval_sec', ...
        'meanSurfaceInterval_min', ...
        'medianSurfaceInterval_sec', ...
        'sdSurfaceInterval_sec', ...
        'minSurfaceInterval_sec', ...
        'maxSurfaceInterval_sec'});

    % ---------- Pair-level table ----------
    if nPairs > 0
        pairTable = table( ...
            pairIdx, ...
            pairIdx + 1, ...
            diveStartDN(pairIdx), ...
            diveStopDN(pairIdx), ...
            diveStartDN(pairIdx + 1), ...
            diveStopDN(pairIdx + 1), ...
            foragingSurfaceIntSec, ...
            foragingSurfaceIntMin, ...
            'VariableNames', { ...
            'Dive1', ...
            'Dive2', ...
            'Dive1_StartDN', ...
            'Dive1_EndDN', ...
            'Dive2_StartDN', ...
            'Dive2_EndDN', ...
            'SurfaceInterval_sec', ...
            'SurfaceInterval_min'});
    else
        pairTable = table();
    end

    % ---------- Package output ----------
    out = struct();
    out.isForagingDive = isForagingDive;
    out.diveStartDN = diveStartDN;
    out.diveStopDN = diveStopDN;
    out.surfaceIntDN = surfaceIntDN;
    out.surfaceIntSec = surfaceIntSec;
    out.surfaceIntMin = surfaceIntMin;
    out.keepPairs = keepPairs;
    out.foragingSurfaceIntDN = foragingSurfaceIntDN;
    out.foragingSurfaceIntSec = foragingSurfaceIntSec;
    out.foragingSurfaceIntMin = foragingSurfaceIntMin;
    out.pairIdx = pairIdx;
    out.summary = summary;
    out.pairTable = pairTable;
end

function out = makeEmptyOutput(nDives)
    out = struct();
    out.isForagingDive = false(nDives,1);
    out.diveStartDN = [];
    out.diveStopDN = [];
    out.surfaceIntDN = [];
    out.surfaceIntSec = [];
    out.surfaceIntMin = [];
    out.keepPairs = [];
    out.foragingSurfaceIntDN = [];
    out.foragingSurfaceIntSec = [];
    out.foragingSurfaceIntMin = [];
    out.pairIdx = [];
    out.summary = table();
    out.pairTable = table();
end

