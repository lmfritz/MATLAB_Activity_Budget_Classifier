function boutTbl = get_submergence_bout_depths(p, tagon, fs, varargin)
%GET_SUBMERGENCE_BOUT_DEPTHS Identify all submergence bouts and summarize them.
% For ONE deployment.
% boutTbl = get_submergence_bout_depths(p, tagon, fs)
% boutTbl = get_submergence_bout_depths(p, tagon, fs, 'Name', value, ...)
%
% Inputs
%   p       - depth vector (m)
%   tagon   - logical vector, true when tag is on-animal
%   fs      - sampling rate (Hz)
%
% Name-value options
%   'SubThresh'   - depth threshold (m) to define "below surface"
%                   default = 0.5
%   'MinBoutDur'  - minimum bout duration (s) to keep
%                   default = 1
%   'MakePlots'   - true/false, whether to plot histograms
%                   default = false
%   'ShallowMax'  - upper x-limit for shallow histogram (m)
%                   default = 20
%
% Output
%   boutTbl - table with one row per submergence bout:
%       bout_id
%       start_idx
%       end_idx
%       start_time_s
%       end_time_s
%       duration_s
%       max_depth_m
%       mean_depth_m
%
% Notes
%   This function is for exploring the distribution of ALL submergence bouts.
%   It does NOT impose a dive threshold like 5 m.
%
% Example
%   boutTbl = get_submergence_bout_depths(p, tagon, fs, ...
%       'SubThresh', 0.5, 'MinBoutDur', 1, 'MakePlots', true);

    % -----------------------------
    % Parse inputs
    % -----------------------------
    ip = inputParser;
    ip.addParameter('SubThresh', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    ip.addParameter('MinBoutDur', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    ip.addParameter('MakePlots', false, @(x) islogical(x) || isnumeric(x));
    ip.addParameter('ShallowMax', 20, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.parse(varargin{:});

    SUB_THRESH  = ip.Results.SubThresh;
    MIN_BOUT_DUR = ip.Results.MinBoutDur;
    MAKE_PLOTS  = logical(ip.Results.MakePlots);
    SHALLOW_MAX = ip.Results.ShallowMax;

    % -----------------------------
    % Clean / shape inputs
    % -----------------------------
    p = p(:);
    tagon = logical(tagon(:));

    if numel(p) ~= numel(tagon)
        error('p and tagon must have the same length.');
    end

    if ~isscalar(fs) || ~isnumeric(fs) || fs <= 0
        error('fs must be a positive scalar.');
    end

    valid = tagon & isfinite(p);

    % -----------------------------
    % Define all submergence bouts
    % -----------------------------
    isSub = valid & (p > SUB_THRESH);

    boutStart = find(diff([false; isSub]) == 1);
    boutEnd   = find(diff([isSub; false]) == -1);

    if isempty(boutStart)
        boutTbl = table();
        warning('No submergence bouts found above %.2f m.', SUB_THRESH);
        return
    end

    % -----------------------------
    % Calculate bout metrics
    % -----------------------------
    nBouts = numel(boutStart);
    duration_s   = (boutEnd - boutStart + 1) ./ fs;
    max_depth_m  = nan(nBouts,1);
    mean_depth_m = nan(nBouts,1);

    for i = 1:nBouts
        idx = boutStart(i):boutEnd(i);
        max_depth_m(i)  = max(p(idx), [], 'omitnan');
        mean_depth_m(i) = mean(p(idx), 'omitnan');
    end

    % -----------------------------
    % Remove very short bouts
    % -----------------------------
    keep = duration_s >= MIN_BOUT_DUR;

    boutStart    = boutStart(keep);
    boutEnd      = boutEnd(keep);
    duration_s   = duration_s(keep);
    max_depth_m  = max_depth_m(keep);
    mean_depth_m = mean_depth_m(keep);

    nKeep = numel(boutStart);

    % -----------------------------
    % Build output table
    % -----------------------------
    bout_id = (1:nKeep)';
    start_time_s = (boutStart - 1) ./ fs;
    end_time_s   = (boutEnd - 1) ./ fs;

    boutTbl = table( ...
        bout_id, ...
        boutStart, ...
        boutEnd, ...
        start_time_s, ...
        end_time_s, ...
        duration_s, ...
        max_depth_m, ...
        mean_depth_m, ...
        'VariableNames', { ...
            'bout_id', ...
            'start_idx', ...
            'end_idx', ...
            'start_time_s', ...
            'end_time_s', ...
            'duration_s', ...
            'max_depth_m', ...
            'mean_depth_m'} );

    % -----------------------------
    % Optional plots
    % -----------------------------
    if MAKE_PLOTS
        figure;
        histogram(boutTbl.max_depth_m, 50);
        xlabel('Maximum depth of submergence bout (m)');
        ylabel('Count');
        title(sprintf('All submergence bouts (threshold = %.2f m)', SUB_THRESH));

        figure;
        shallowDepths = boutTbl.max_depth_m(boutTbl.max_depth_m <= SHALLOW_MAX);
        histogram(shallowDepths, 40);
        xlabel('Maximum depth of submergence bout (m)');
        ylabel('Count');
        title(sprintf('Shallow submergence bouts (<= %.1f m)', SHALLOW_MAX));
    end
end