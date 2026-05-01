%% Known Behavioral State Comparison Tool
% Allows you to select periods on time depth plot of a known behavior to
% compare metrics between different behavioral states
% March 27, 2026 
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

% ---- speedJJ from speed.JJ (robust with NaNs) ----
speedJJ = nan(size(p));   % default

if exist('speed','var') && isstruct(speed) && isfield(speed,'JJ') && ~isempty(speed.JJ)
    raw = speed.JJ(:);

    if ~all(isnan(raw))
        tmp = raw;

        % fill NaNs temporarily so runmean doesn't propagate them
        tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));

        % smooth over ~0.5 s
        tmp = runmean(tmp, max(1,round(fs/2)));

        % put NaNs back where JJ was NaN originally
        tmp(isnan(raw)) = nan;

        % ensure same length as p
        n = min(numel(tmp), numel(speedJJ));
        speedJJ(1:n) = tmp(1:n);
    end
end

% Optional fallback: use speed.FN if JJ missing
if all(isnan(speedJJ)) && exist('speed','var') && isstruct(speed) && isfield(speed,'FN') && ~isempty(speed.FN)
    raw = speed.FN(:);
    if ~all(isnan(raw))
        tmp = raw;
        tmp(isnan(tmp)) = min(tmp(~isnan(tmp)));
        tmp = runmean(tmp, max(1,round(fs/2)));
        tmp(isnan(raw)) = nan;
        n = min(numel(tmp), numel(speedJJ));
        speedJJ(1:n) = tmp(1:n);
    end
end

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

%% 2. Plot and Process
% Simplified known-state comparison tool
% Keeps:
%   - same 3-panel plotting style
%   - lunge audits visible/editable
%   - 10-min windows / B back / 1-9 zoom / Enter forward / S save
% Adds:
%   - Q = mark one RESTING segment (2 clicks)
%   - E = mark one FORAGING segment (2 clicks)
% Removes:
%   - old full behavior-state auditing workflow

% Check to see if we should start at beginning or at a saved index
if ~exist('progressIndex','var') || ~atLast
    i = find(tagon,1);
else
    i = progressIndex;
end

instructions = sprintf(['Controls:\n' ...
'LeftClick: High Confidence Lunge\n' ...
'L: Likely Lunge\n' ...
'M: Maybe Lunge\n' ...
'RightClick: Delete Lunge\n' ...
'Q: Mark RESTING segment (2 clicks)\n' ...
'E: Mark FORAGING segment (2 clicks)\n' ...
'1-9: Change Zoom (x10)\n' ...
'B: Move Back\n' ...
'Enter: Move Forward\n' ...
'H: Go To Last\n' ...
'S: Save']);

% One comparison segment of each type
restSegI   = [];
restSegT   = [];
forageSegI = [];
forageSegT = [];

% Colors for overlays
stateColors = {
    [0.2 0.5 0.9]    % resting = blue
    [0.3 0.75 0.3]   % traveling = green
    [0.9 0.3 0.3]    % foraging = red
    [1.0 0.6 0.1]    % exploring = orange
};

doneSelecting = false;
while i < find(tagon,1,'last')

    figure(101); clf
    annotation('textbox', [0, 0.5, 0, 0], ...
        'string', instructions, 'FitBoxToText', 'on');

    % Window end
    relEnd = find(p(i+M*60*fs:end) < 10, 1, 'first');
    if ~isempty(relEnd)
        e = min(relEnd + i + (M+1)*60*fs - 1, length(p));
    else
        e = length(p);
    end

    I = max(i-60*fs,1):e;
    tagonI = false(size(p));
    tagonI(I) = true;
    tagonI = tagon & tagonI;

    %% Panel 1: depth + jerk
    s1 = subplot(3,1,1);
    [ax1,~,h2] = plotyy(DN(I), p(I), DN(I), J(I));
    set(ax1(1), 'ydir', 'rev', 'nextplot', 'add', 'ylim', [-5 max(p(tagonI))]);
    ylabel('Jerk',  'parent', ax1(2));
    ylabel('Depth', 'parent', ax1(1));
    set(ax1(2), 'ycolor', 'm');

    mxJ = max(J(tagonI), [], 'omitnan');
    if isempty(mxJ) || ~isfinite(mxJ) || mxJ <= 0
        mxJ = max(J(I), [], 'omitnan');
    end
    if isempty(mxJ) || ~isfinite(mxJ) || mxJ <= 0
        mxJ = 1;
    end
    set(ax1(2), 'ylim', [0 1.2*mxJ]);

    set(h2, 'color', 'm');
    set(ax1, 'xlim', [DN(I(1)) DN(I(end))]);
    set(ax1, 'xticklabel', datestr(get(gca,'xtick'),'mm/dd HH:MM:SS'));
    title(filename(1:end-11));

    hold(ax1(1), 'on');
    yl = get(ax1(1), 'ylim');

    % Overlay selected resting segment
    if ~isempty(restSegI)
        rs = intersect(restSegI, I);
        if ~isempty(rs)
            patch(ax1(1), ...
                [DN(rs(1)) DN(rs(end)) DN(rs(end)) DN(rs(1))], ...
                [yl(1) yl(1) yl(2) yl(2)], ...
                stateColors{1}, ...
                'FaceAlpha', 0.30, ...
                'EdgeColor', 'b', ...
                'LineWidth', 1.5);
        end
    end

    % Overlay selected foraging segment
    if ~isempty(forageSegI)
        fsI = intersect(forageSegI, I);
        if ~isempty(fsI)
            patch(ax1(1), ...
                [DN(fsI(1)) DN(fsI(end)) DN(fsI(end)) DN(fsI(1))], ...
                [yl(1) yl(1) yl(2) yl(2)], ...
                stateColors{3}, ...
                'FaceAlpha', 0.30, ...
                'EdgeColor', 'r', ...
                'LineWidth', 1.5);
        end
    end

    uistack(findobj(ax1(1), 'Type', 'line'), 'top');

    %% Panel 2: pitch / roll / head
    s2 = subplot(3,1,2);
    uistack(ax1(1));
    set(ax1(1), 'Color', 'none');
    set(ax1(2), 'Color', 'w');

    [ax2,h1,h22] = plotyy(DN(I), pitch(I)*180/pi, DN(I), roll(I)*180/pi);
    set(ax2(2), 'nextplot', 'add', 'ycolor', 'k', 'ylim', [-180 180]);
    ylabel('Roll and Head', 'parent', ax2(2));
    plot(ax2(2), DN(I), head(I)*180/pi, 'b.', 'markersize', 4);

    set(ax2(1), 'ycolor', 'g', 'nextplot', 'add', 'ylim', [-90 90]);
    ylabel('Pitch', 'parent', ax2(1));
    set(h1, 'color', 'g');
    set(h22, 'color', 'r', 'linestyle', '-', 'markersize', 4);
    set(ax2, 'xlim', [DN(I(1)) DN(I(end))]);
    set(ax2, 'xticklabel', datestr(get(gca,'xtick'),'HH:MM:SS'));

    %% Panel 3: speed / movement
    s3 = subplot(3,1,3);

    if exist('speedJJ','var') && any(isfinite(speedJJ(I)))
        plot(DN(I), speedJJ(I), 'b');
    else
        plot(DN(I), mov(I), 'b');
    end
    hold on

    if exist('speedFN','var') && any(isfinite(speedFN(I)))
        plot(DN(I), speedFN(I), 'g');
    end

    % Safety: align L / LI / LC
    if ~isempty(L)
        L  = L(:);
        LI = LI(:);
        if exist('LC','var') && ~isempty(LC)
            LC = LC(:);
        else
            LC = nan(size(LI));
        end

        n = min([numel(L), numel(LI), numel(LC)]);
        L  = L(1:n);
        LI = LI(1:n);
        LC = LC(1:n);

        valid = (LI >= 1) & (LI <= numel(p)) & isfinite(L);
        L  = L(valid);
        LI = LI(valid);
        LC = LC(valid);

        [L, ord] = sort(L);
        LI = LI(ord);
        LC = LC(ord);
    end
    hold off

    set(s3, 'nextplot', 'add');
    marks = nan(1,3);

    % Plot lunges
    if ~isempty(L)
        colors = 'rbk';  % 1 maybe=red, 2 likely=blue, 3 high=black in your existing scheme
        for c = 1:3
            II = find(LC == c);
            if ~isempty(II)
                marks(1) = plot(ax1(1), L(II), p(LI(II)), [colors(c) 's'], 'markerfacecolor', colors(c));
                marks(2) = plot(ax2(1), L(II), pitch(LI(II))*180/pi, [colors(c) 's'], 'markerfacecolor', colors(c));
                marks(3) = plot(s3, L(II), speedJJ(LI(II)), [colors(c) 's'], 'markerfacecolor', colors(c));
            end
        end
    end

    set(s3, 'xlim', [DN(I(1)) DN(I(end))]);

    mx = max(speedJJ(tagonI), [], 'omitnan');
    if isempty(mx) || ~isfinite(mx) || mx <= 0
        mx = max(speedJJ(I), [], 'omitnan');
    end
    if isempty(mx) || ~isfinite(mx) || mx <= 0
        mx = 1;
    end

    set(s3, 'ylim', [0 1.1*mx], 'xlim', [DN(I(1)) DN(I(end))]);
    set(s3, 'xticklabel', datestr(get(gca,'xtick'),'HH:MM:SS'));
    ylabel('Speed');

    %% Interaction loop
    button = 1;
    redraw = false;
    close2lunge = 15;
    if numel(whaleName) >= 2 && strcmp(whaleName(1:2),'bb')
        close2lunge = 5;
    end

    while ~isempty(button)
        redraw = false;

        if ishandle(ax2)
            [x,~,button] = ginput(1);
            disp(button)

            

            % ENTER = move forward
            if isempty(button)
                redraw = false;
                button = [];
                break;
            end

            switch button

                case 1   % left click = high-confidence lunge
                    [~,xI] = min(abs(DN-x));
                    lo = max(1, xI-5*fs);
                    hi = min(numel(speedJJ), xI+5*fs);
                    [~,mI] = max(speedJJ(lo:hi));
                    mI = mI + lo - 1;

                    if any(abs(LI-xI) < close2lunge*fs)
                        [~,delI] = min(abs(L-x));
                        L(delI)  = [];
                        LI(delI) = [];
                        LC(delI) = [];
                    end

                    LC = [LC; 3];
                    [L,II] = sort([L; DN(mI)]);
                    LI = sort([LI; mI]);
                    LC = LC(II);

                case 108  % l = likely lunge
                    [~,xI] = min(abs(DN-x));
                    lo = max(1, xI-5*fs);
                    hi = min(numel(speedJJ), xI+5*fs);
                    [~,mI] = max(speedJJ(lo:hi));
                    mI = mI + lo - 1;

                    if any(abs(LI-xI) < close2lunge*fs)
                        [~,delI] = min(abs(L-x));
                        L(delI)  = [];
                        LI(delI) = [];
                        LC(delI) = [];
                    end

                    LC = [LC; 2];
                    [L,II] = sort([L; DN(mI)]);
                    LI = sort([LI; mI]);
                    LC = LC(II);

                case 109  % m = maybe lunge
                    [~,xI] = min(abs(DN-x));
                    lo = max(1, xI-5*fs);
                    hi = min(numel(speedJJ), xI+5*fs);
                    [~,mI] = max(speedJJ(lo:hi));
                    mI = mI + lo - 1;

                    if any(abs(LI-xI) < close2lunge*fs)
                        [~,delI] = min(abs(L-x));
                        L(delI)  = [];
                        LI(delI) = [];
                        LC(delI) = [];
                    end

                    LC = [LC; 1];
                    [L,II] = sort([L; DN(mI)]);
                    LI = sort([LI; mI]);
                    LC = LC(II);

                case 3   % right click = delete lunge
                    if ~isempty(L)
                        [~,delI] = min(abs(L-x));
                        L(delI)  = [];
                        LI(delI) = [];
                        LC(delI) = [];
                    end
                    redraw = true;
                    button = [];

                case 113  % q = resting segment
                disp('RESTING: click START')
                [x1,~,b1] = ginput(1);
                if isempty(b1)
                    button = [];
                    continue;
                end
            
                disp('RESTING: click END')
                [x2,~,b2] = ginput(1);
                if isempty(b2)
                    button = [];
                    continue;
                end
            
                xseg = sort([x1 x2]);
                [~,i1] = min(abs(DN - xseg(1)));
                [~,i2] = min(abs(DN - xseg(2)));
            
                restSegI = i1:i2;
                restSegT = DN(restSegI);
            
                fprintf('Stored RESTING segment: %d to %d\n', i1, i2);
            
                redraw = true;
                button = [];

                case 101  % e = foraging segment
                disp('FORAGING: click START')
                [x1,~,b1] = ginput(1);
                if isempty(b1)
                    button = [];
                    continue;
                end
            
                disp('FORAGING: click END')
                [x2,~,b2] = ginput(1);
                if isempty(b2)
                    button = [];
                    continue;
                end
            
                xseg = sort([x1 x2]);
                [~,i1] = min(abs(DN - xseg(1)));
                [~,i2] = min(abs(DN - xseg(2)));
            
                forageSegI = i1:i2;
                forageSegT = DN(forageSegI);
            
                fprintf('Stored FORAGING segment: %d to %d\n', i1, i2);
            
                redraw = true;
                button = [];

                case 104  % h = go to last progress
                    if ~isempty(LI)
                        i = max(LI(:));
                    else
                        i = find(tagon,1);
                    end
                    redraw = true;
                    button = [];

                case 98   % b = move back
                    i = max(find(tagon,1), i - M*60*fs);
                    redraw = true;
                    button = [];

                case num2cell(49:57)  % 1-9 = change zoom to 10x number of minutes
                    M = 10*(button-48);
                    redraw = true;
                    button = [];

                case 115  % s = save and finish

                    d1 = datevec(now());
                    created_on = [d1(2) d1(3) d1(1)];
                    clear d1

                    starttime = DN(1);
                    prh_fs = fs;
                    LungeDN = L;
                    depth = p(LI);
                    time = L;
                    LungeI = LI;
                    LungeC = LC;
                    LungeDepth = depth;
                    progressIndex = i;

                    save(fullfile(fileloc, [baseName 'lunges.mat']), ...
                        'LungeDN','LungeI','LungeDepth','LungeC', ...
                        'creator','primary_cue','prh_fs','starttime', ...
                        'created_on','progressIndex','notes', ...
                        'restSegI','restSegT','forageSegI','forageSegT');

                    disp('Saved selections. Exiting audit window...')

                    doneSelecting = true;

                    if isgraphics(101)
                        close(101)
                    end

                    break

            % redraw lunge marks after edits
            if ~isempty(L)
                try delete(marks); catch; end
                colors = 'rbk';
                for c = 1:3
                    II = find(LC == c);
                    if ~isempty(II)
                        marks(1) = plot(ax1(1), L(II), p(LI(II)), [colors(c) 's'], 'markerfacecolor', colors(c));
                        marks(2) = plot(ax2(1), L(II), pitch(LI(II))*180/pi, [colors(c) 's'], 'markerfacecolor', colors(c));
                        marks(3) = plot(s3, L(II), speedJJ(LI(II)), [colors(c) 's'], 'markerfacecolor', colors(c));
                    end
                end
            end
        end
    end

    if doneSelecting
    break;
    elseif redraw
        continue;
    else
        i = e;
    end
end

    if doneSelecting
        break
    elseif redraw
        continue
    else
        i = e;
    end
end
% Final save
d1 = datevec(now());
created_on = [d1(2) d1(3) d1(1)];
clear d1

starttime = DN(1);
prh_fs = fs;
LungeDN = L;
depth = p(LI);
time = L;
LungeI = LI;
LungeC = LC;
LungeDepth = depth;
progressIndex = i;

save(fullfile(fileloc, [baseName 'lunges.mat']), ...
    'LungeDN','LungeI','LungeDepth','LungeC', ...
    'creator','primary_cue','prh_fs','starttime', ...
    'created_on','progressIndex','notes', ...
    'restSegI','restSegT','forageSegI','forageSegT')

%% 3. Compare selected segments

if isempty(restSegI) || isempty(forageSegI)
    warning('Need both a resting segment and a foraging segment selected.');
else
    fprintf('\n=== KNOWN-STATE COMPARISON ===\n');

    % --- RESTING summaries ---
    fprintf('\nRESTING segment\n');
    fprintf('  n              = %d\n', numel(restSegI));
    fprintf('  mov mean       = %.4f\n', mean(mov(restSegI), 'omitnan'));
    fprintf('  mov median     = %.4f\n', median(mov(restSegI), 'omitnan'));
    fprintf('  mov sd         = %.4f\n', std(mov(restSegI), 'omitnan'));
    fprintf('  depth mean     = %.4f\n', mean(p(restSegI), 'omitnan'));
    fprintf('  depth median   = %.4f\n', median(p(restSegI), 'omitnan'));
    fprintf('  pitch mean     = %.4f deg\n', mean(pitch(restSegI)*180/pi, 'omitnan'));
    fprintf('  pitch median   = %.4f deg\n', median(pitch(restSegI)*180/pi, 'omitnan'));

    % --- FORAGING summaries ---
    fprintf('\nFORAGING segment\n');
    fprintf('  n              = %d\n', numel(forageSegI));
    fprintf('  mov mean       = %.4f\n', mean(mov(forageSegI), 'omitnan'));
    fprintf('  mov median     = %.4f\n', median(mov(forageSegI), 'omitnan'));
    fprintf('  mov sd         = %.4f\n', std(mov(forageSegI), 'omitnan'));
    fprintf('  depth mean     = %.4f\n', mean(p(forageSegI), 'omitnan'));
    fprintf('  depth median   = %.4f\n', median(p(forageSegI), 'omitnan'));
    fprintf('  pitch mean     = %.4f deg\n', mean(pitch(forageSegI)*180/pi, 'omitnan'));
    fprintf('  pitch median   = %.4f deg\n', median(pitch(forageSegI)*180/pi, 'omitnan'));

    % --- Combined boxplots ---
    figure;

    subplot(3,1,1)
    x1 = [mov(restSegI); mov(forageSegI)];
    g1 = [repmat({'Resting'}, numel(restSegI), 1); ...
          repmat({'Foraging'}, numel(forageSegI), 1)];
    boxplot(x1, g1)
    ylabel('mov')
    title('Known-state comparison')

    subplot(3,1,2)
    x2 = [p(restSegI); p(forageSegI)];
    g2 = [repmat({'Resting'}, numel(restSegI), 1); ...
          repmat({'Foraging'}, numel(forageSegI), 1)];
    boxplot(x2, g2)
    ylabel('Depth (m)')
    set(gca, 'YDir', 'reverse')

    subplot(3,1,3)
    x3 = [pitch(restSegI)*180/pi; pitch(forageSegI)*180/pi];
    g3 = [repmat({'Resting'}, numel(restSegI), 1); ...
          repmat({'Foraging'}, numel(forageSegI), 1)];
    boxplot(x3, g3)
    ylabel('Pitch (deg)')
end