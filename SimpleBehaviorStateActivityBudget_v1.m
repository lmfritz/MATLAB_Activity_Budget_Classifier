% % Identify behavioral states (resting, traveling, foraging, exploring) and create an activity budget for tag
% deployment
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
% Outputs - Section 2: Lunge .mat file, behavior state .mat file
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

% =========================
% PICK BEST-MATCH LUNGES FILE (by time overlap)
% =========================

searchRoot = fileloc;    % same folder as PRH
useSubfolders = false;   % set true if lunges may be deeper in subfolders

% Build candidate list: accept both "_lunges" and "lunges" naming
if useSubfolders
    cand = dir(fullfile(searchRoot, '**', ['*' depID '*lunges.mat']));
else
    cand = dir(fullfile(searchRoot, ['*' depID '*lunges.mat']));
end
cand = cand(~startsWith({cand.name}, '._')); % remove mac metadata

if isempty(cand)
    error('No lunge files found matching depID=%s in %s', depID, searchRoot);
end

bestScore = -Inf;
bestFile  = '';

DNmin = min(DN); DNmax = max(DN);

for k = 1:numel(cand)
    f = fullfile(cand(k).folder, cand(k).name);

    % load minimally
    tmp = load(f);

    % pull a time vector from common names
    t = [];
    if isfield(tmp,'LungeDN') && ~isempty(tmp.LungeDN), t = tmp.LungeDN; end
    if isempty(t) && isfield(tmp,'time') && ~isempty(tmp.time), t = tmp.time; end
    if isempty(t) && isfield(tmp,'L') && ~isempty(tmp.L), t = tmp.L; end

    if isempty(t)
        continue; % no time vector → can't score reliably
    end

    t = t(:);
    % Count how many lunges fall within PRH DN range
    in = (t >= DNmin) & (t <= DNmax);
    nIn = sum(in);
    nTot = numel(t);

    % overlap fraction + bonus for having any in-range lunges
    frac = nIn / max(nTot,1);
    score = frac + 0.01*log1p(nIn);  % small bonus to favor more matches

    % also punish obviously wrong files (0 in range)
    if nIn == 0
        score = score - 1;
    end

    if score > bestScore
        bestScore = score;
        bestFile = f;
    end
end

if isempty(bestFile)
    error('Found candidate lunge files, but none had a usable time vector (LungeDN/time/L).');
end


% =========================
% LOAD LUNGES FROM THE SELECTED FILE (robust variable names)
% =========================
tmp = load(bestFile);
disp('Lunge file variables:');
disp(fieldnames(tmp));

LungeI = [];
LungeDN = [];
LungeC = [];

% standard names
if isfield(tmp,'LungeI'),  LungeI  = tmp.LungeI(:);  end
if isfield(tmp,'LungeDN'), LungeDN = tmp.LungeDN(:); end
if isfield(tmp,'LungeC'),  LungeC  = tmp.LungeC(:);  end

% alternate names commonly seen
if isempty(LungeI)  && isfield(tmp,'LI'),   LungeI  = tmp.LI(:);   end
if isempty(LungeDN) && isfield(tmp,'time'), LungeDN = tmp.time(:); end
if isempty(LungeDN) && isfield(tmp,'L'),    LungeDN = tmp.L(:);    end
if isempty(LungeC)  && isfield(tmp,'LC'),   LungeC  = tmp.LC(:);   end

% Prefer mapping from time → indices (most robust)
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

% clip
LI = LI(LI>=1 & LI<=numel(p));


% ---- Standardize lunges (DO NOT wipe LI) ----
% LI is already computed above from LungeDN (preferred) or LungeI.

if ~exist('LI','var') || isempty(LI)
    if ~isempty(LungeI)
        LI = LungeI(:);
    else
        LI = [];
    end
end
LI = LI(LI>=1 & LI<=numel(p));

% L = lunge times (datenum)
if ~isempty(LungeDN)
    L = LungeDN(:);
elseif ~isempty(LI)
    L = DN(LI);
else
    L = [];
end

% LC = confidence codes if present
if ~isempty(LungeC)
    LC = LungeC(:);
else
    LC = nan(size(LI));
end
if numel(LC) ~= numel(LI); LC = nan(size(LI)); end

% ---- Load prior behavior audit (optional) ----
whaleName = INFO.whaleName;
ii = strfind(filename,' ');
behaviorname = [filename(1:ii-1) 'BehaviorState.mat'];
try load(fullfile(fileloc, behaviorname)); catch; end

disp('Section 1 finished: Data Loaded');

%% AUTO STATE CLASSIFICATION (single clean classifier; dive-bounded)

% -------------------------
% Definitions agreed on
% -------------------------
% Foraging  = any dive that contains >=1 lunge
% Traveling = whole dive, max depth between 10 and 50 m, with NO lunges
% Resting   = surface intervals only (NOT in dive), depth 0–10 m, low movement
% Exploring = everything else (tagon only)

diveDepthThresh_m = 10;       % defines when a "dive" starts (p > this)
minDiveDur_s      = 30;      % ignore tiny excursions
travelMin_m       = 10;      % traveling dive max depth lower bound
travelMax_m       = 50;      % traveling dive max depth upper bound
restMinDepth_m    = 0;       % resting depth band
restMaxDepth_m    = 10;      % resting depth band
minRestDur_s      = 3*60;    % optional: minimum resting bout duration

% -------------------------
% Movement proxy (low movement = resting)
% -------------------------
mov = speedJJ;
if ~exist('mov','var') || isempty(mov) || all(~isfinite(mov))
    mov = J;  % fallback
end

% Align vectors (defensive)
p     = p(:);
DN    = DN(:);
tagon = tagon(:);
mov   = mov(:);

N = min([numel(p), numel(DN), numel(tagon), numel(mov)]);
p     = p(1:N);
DN    = DN(1:N);
tagon = tagon(1:N);
mov   = mov(1:N);

% Clip lunges after truncation
if exist('LI','var') && ~isempty(LI)
    LI = LI(:);
    LI = LI(LI>=1 & LI<=N);
else
    LI = [];
end

% Low-movement threshold from on-animal samples
valid = tagon & isfinite(mov);
if sum(valid) < 100
    valid = isfinite(mov);
end
restThresh = prctile(mov(valid), 35);  % was 20
gapFill_s = 20;                        % was 5
minRestDur_s = 30;                     % was 180

% -------------------------
% 1) Detect dives (boundaries only)
% -------------------------
inDiveRaw = (p > diveDepthThresh_m) & tagon;
d = diff([false; inDiveRaw; false]);
diveStarts = find(d == 1);
diveStops  = find(d == -1) - 1;

% Remove short dives
dur_s = (diveStops - diveStarts + 1) / fs;
keep = dur_s >= minDiveDur_s;
diveStarts = diveStarts(keep);
diveStops  = diveStops(keep);

nDives = numel(diveStarts);

% Final inDive mask
inDive = false(size(p));
for di = 1:nDives
    inDive(diveStarts(di):diveStops(di)) = true;
end

% -------------------------
% 2) Dive-level labels: foraging vs traveling
% -------------------------
forageMask = false(size(p));
travelMask = false(size(p));

for di = 1:nDives
    a = diveStarts(di);
    b = diveStops(di);

    mx = max(p(a:b), [], 'omitnan');
    hasLunge = ~isempty(LI) && any(LI >= a & LI <= b);

    if hasLunge
        forageMask(a:b) = true;
    elseif mx >= travelMin_m && mx <= travelMax_m
        travelMask(a:b) = true;
    end
end

% -------------------------
% RESTING (surface-only): 0–10 m AND low movement
% Make it bout-like: smooth movement + fill short gaps + min duration
% -------------------------

restMinDepth_m   = 0;
restMaxDepth_m   = 10;

% 1) Smooth movement so thresholding isn't flickery (e.g., 10 s window)
restSmooth_s = 10;
w = max(1, round(restSmooth_s * fs));
movS = mov;
if any(isfinite(movS))
    % fill NaNs so runmean doesn't propagate them
    movFill = movS;
    movFill(~isfinite(movFill)) = prctile(movFill(isfinite(movFill)), 5);
    movS = runmean(movFill, w);
    movS(~isfinite(movS)) = NaN;
end

% 2) Candidate resting (surface interval only; NOT in dives)
surfaceInterval = tagon & ~inDive;
restCand = surfaceInterval ...
    & (p >= restMinDepth_m) & (p <= restMaxDepth_m) ...
    & isfinite(movS) & (movS <= restThresh);

% 3) Fill short gaps inside resting (e.g., allow up to 5 s interruptions)
gapFill_s = 5;
gapFillN = round(gapFill_s * fs);

% Find false gaps between true segments and fill if short
d = diff([false; restCand; false]);
starts = find(d == 1);
stops  = find(d == -1) - 1;

restFilled = restCand;
if numel(starts) >= 2
    for k = 1:(numel(starts)-1)
        gapStart = stops(k) + 1;
        gapStop  = starts(k+1) - 1;
        gapLen   = gapStop - gapStart + 1;
        if gapLen > 0 && gapLen <= gapFillN
            restFilled(gapStart:gapStop) = true;
        end
    end
end

% 4) Enforce minimum bout length (NOW it should work)
minRestDur_s = 3*60;                 % keep your intended 3 min
minRestN = round(minRestDur_s * fs);

dr = diff([false; restFilled; false]);
rStarts = find(dr == 1);
rStops  = find(dr == -1) - 1;

restMask = false(size(restFilled));
durN = rStops - rStarts + 1;
keep = durN >= minRestN;

for kk = find(keep)'
    restMask(rStarts(kk):rStops(kk)) = true;
end

% --- Resting bout diagnostics ---
dr = diff([false; restCand; false]);
rStarts = find(dr == 1);
rStops  = find(dr == -1) - 1;

durN = rStops - rStarts + 1;
durS = durN / fs;

% -------------------------
% 4) Build final state vector
% -------------------------
% 1=resting, 2=traveling, 3=foraging, 4=exploring
state = nan(size(p));
state(tagon) = 4;                 % default exploring (tagon only)
state(travelMask & tagon) = 2;    % traveling whole dive
state(forageMask & tagon) = 3;    % foraging whole dive (overwrites travel if any overlap)
state(restMask) = 1;              % resting only in surface intervals

% -------------------------
% Diagnostics (optional)
% -------------------------


labels = ["resting","traveling","foraging","exploring"];
pct = nan(1,4);

for s = 1:4
    pct(s) = 100 * sum(state(tagon) == s) / sum(tagon);
end

budgetT = table(labels', pct', 'VariableNames', {'State','Percent'});
disp(budgetT);

writetable(budgetT, fullfile(fileloc, [whaleName '_AutoActivityBudget.csv']));

% --- Pie chart activity budget ---
figure;
pie(pct);

% Add labels with percent values
txt = strings(1,numel(labels));
for k = 1:numel(labels)
    txt(k) = sprintf('%s (%.1f%%)', labels(k), pct(k));
end
legend(txt, 'Location', 'eastoutside');

title([whaleName ' Auto Activity Budget']);
exportgraphics(gcf, fullfile(fileloc, [whaleName '_AutoActivityBudget_pie.png']), 'Resolution', 300);
% ---- Initialize behavior-picker variables (needed for Section 2 plotting) ----
BehaviorState = [];
BehaviorText  = '';
Bcolors       = 'rgkc';   % 4 states: resting/traveling/foraging/exploring

% If no prior saved behavior audit exists, initialize empty vectors
if ~exist('behI','var');  behI  = []; end
if ~exist('behT','var');  behT  = []; end
if ~exist('behS','var');  behS  = []; end
if ~exist('behSS','var'); behSS = []; end

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
                        i = max([behI;LI]);
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

fprintf('Foraging %%: %.2f\n', 100*sum(state==3 & tagon)/sum(tagon));
fprintf('Traveling %%: %.2f\n', 100*sum(state==2 & tagon)/sum(tagon));
fprintf('Exploring %%: %.2f\n', 100*sum(state==4 & tagon)/sum(tagon));