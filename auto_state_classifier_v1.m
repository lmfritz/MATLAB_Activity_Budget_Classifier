%% Identify behavioral states and create an activity budget for a tag deployment
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

    uistack(hCursor1, 'bottom');
    uistack(hCursor2, 'bottom');
    uistack(hCursor3, 'bottom');

    set(gcf, 'WindowButtonMotionFcn', ...
        @(src,evt) updateVerticalCursor(src, ax1(1), ax2(1), s3, hCursor1, hCursor2, hCursor3));

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

function updateVerticalCursor(fig, axTop, axMid, axBot, h1, h2, h3)
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
end