%% debug_behavior_bout.m
% Inspect one auto-classified bout from the current workspace
% Requires classifier outputs in workspace:
%   autoStartI, autoEndI, autoState, state
%   DN, fs, p, tagon
%   speedTrace (or speedJJ), movS, pitchVar, turnRateS
% Optional:
%   lowSpeed, lowMov, lowPitch, postDiveCarryMask, surfaceRestCandidate, restMaskSurface

% -------------------------
% USER INPUT
% -------------------------
boutK = 38;   % change this to the bout number you want to inspect

stateNames = {'surface_active','resting','traveling','foraging','exploring'};

% -------------------------
% CHECKS
% -------------------------
if ~exist('autoStartI','var') || isempty(autoStartI)
    error('autoStartI not found in workspace. Run classifier first.');
end

if boutK < 1 || boutK > numel(autoStartI)
    error('boutK must be between 1 and %d.', numel(autoStartI));
end

a = autoStartI(boutK);
b = autoEndI(boutK);
s = autoState(boutK);

if exist('speedTrace','var') && ~isempty(speedTrace)
    speedVal = speedTrace(:);
elseif exist('speedJJ','var') && ~isempty(speedJJ)
    speedVal = speedJJ(:);
else
    speedVal = nan(size(state));
end

% -------------------------
% PRINT SUMMARY
% -------------------------
fprintf('\n==============================\n');
fprintf('BOUT DEBUG\n');
fprintf('Bout #: %d\n', boutK);
fprintf('State #: %d\n', s);
if isfinite(s) && s >= 1 && s <= numel(stateNames)
    fprintf('State: %s\n', stateNames{s});
end
fprintf('Start index: %d\n', a);
fprintf('End index: %d\n', b);
fprintf('Duration (s): %.2f\n', (b-a+1)/fs);
fprintf('Start time: %s\n', datestr(DN(a), 'yyyy-mm-dd HH:MM:SS'));
fprintf('End time:   %s\n', datestr(DN(b), 'yyyy-mm-dd HH:MM:SS'));

fprintf('\n--- Signal summaries ---\n');
fprintf('Mean depth (m): %.2f\n', mean(p(a:b), 'omitnan'));
fprintf('Median depth (m): %.2f\n', median(p(a:b), 'omitnan'));
fprintf('Max depth (m): %.2f\n', max(p(a:b), [], 'omitnan'));

fprintf('Mean speed: %.2f\n', mean(speedVal(a:b), 'omitnan'));
fprintf('Median speed: %.2f\n', median(speedVal(a:b), 'omitnan'));

if exist('movS','var')
    fprintf('Mean movement: %.2f\n', mean(movS(a:b), 'omitnan'));
    fprintf('Median movement: %.2f\n', median(movS(a:b), 'omitnan'));
end

if exist('pitchVar','var')
    fprintf('Mean pitch variability: %.2f\n', mean(pitchVar(a:b), 'omitnan'));
    fprintf('Median pitch variability: %.2f\n', median(pitchVar(a:b), 'omitnan'));
end

if exist('turnRateS','var')
    fprintf('Mean turn rate (deg/s): %.2f\n', mean(turnRateS(a:b), 'omitnan'));
    fprintf('Median turn rate (deg/s): %.2f\n', median(turnRateS(a:b), 'omitnan'));
end

% -------------------------
% BOOLEAN MASK DIAGNOSTICS
% -------------------------
fprintf('\n--- Mask fractions within bout ---\n');

if exist('lowSpeed','var')
    fprintf('Frac lowSpeed: %.2f\n', mean(lowSpeed(a:b), 'omitnan'));
end
if exist('lowMov','var')
    fprintf('Frac lowMov: %.2f\n', mean(lowMov(a:b), 'omitnan'));
end
if exist('lowPitch','var')
    fprintf('Frac lowPitch: %.2f\n', mean(lowPitch(a:b), 'omitnan'));
end
if exist('postDiveCarryMask','var')
    fprintf('Frac postDiveCarry: %.2f\n', mean(postDiveCarryMask(a:b), 'omitnan'));
end
if exist('surfaceRestCandidate','var')
    fprintf('Frac surfaceRestCandidate: %.2f\n', mean(surfaceRestCandidate(a:b), 'omitnan'));
end
if exist('restMaskSurface','var')
    fprintf('Frac final surface resting: %.2f\n', mean(restMaskSurface(a:b), 'omitnan'));
end
if exist('inDive','var')
    fprintf('Frac inDive: %.2f\n', mean(inDive(a:b), 'omitnan'));
end
if exist('forageMask','var')
    fprintf('Frac forageMask: %.2f\n', mean(forageMask(a:b), 'omitnan'));
end

% -------------------------
% THRESHOLDS
% -------------------------
fprintf('\n--- Thresholds ---\n');
if exist('REST_SPEED_MAX_MPS','var')
    fprintf('REST_SPEED_MAX_MPS: %.2f\n', REST_SPEED_MAX_MPS);
end
if exist('lowMovThresh','var')
    fprintf('lowMovThresh: %.2f\n', lowMovThresh);
end
if exist('lowPitchVarThresh','var')
    fprintf('lowPitchVarThresh: %.2f\n', lowPitchVarThresh);
end
if exist('TRAVEL_SPEED_MIN_MPS','var')
    fprintf('TRAVEL_SPEED_MIN_MPS: %.2f\n', TRAVEL_SPEED_MIN_MPS);
end
if exist('TRAVEL_TURNRATE_MAX_DEGPS','var')
    fprintf('TRAVEL_TURNRATE_MAX_DEGPS: %.2f\n', TRAVEL_TURNRATE_MAX_DEGPS);
end
if exist('TRAVEL_MAX_DEPTH_M','var')
    fprintf('TRAVEL_MAX_DEPTH_M: %.2f\n', TRAVEL_MAX_DEPTH_M);
end

% -------------------------
% PLOT WINDOW AROUND BOUT
% -------------------------
pad = round(30 * fs);  % 30 s padding on each side
I = max(1, a-pad):min(numel(state), b+pad);

figure('Color','w', 'Position', [100 100 1000 800]);
tiledlayout(6,1)

% 1. Depth
nexttile
plot(DN(I), p(I), 'b', 'LineWidth', 1); hold on
patch([DN(a) DN(b) DN(b) DN(a)], [min(p(I)) min(p(I)) max(p(I)) max(p(I))], ...
    [0.85 0.85 0.85], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
set(gca, 'YDir', 'reverse')
ylabel('Depth')
title(sprintf('Bout %d | %s', boutK, stateNames{s}))

% 2. Speed
nexttile
plot(DN(I), speedVal(I), 'k', 'LineWidth', 1); hold on
if exist('REST_SPEED_MAX_MPS','var')
    yline(REST_SPEED_MAX_MPS, '--r', 'Rest speed');
end
if exist('TRAVEL_SPEED_MIN_MPS','var')
    yline(TRAVEL_SPEED_MIN_MPS, '--b', 'Travel speed');
end
xline(DN(a), '--k'); xline(DN(b), '--k');
ylabel('Speed')

% 3. Movement
nexttile
if exist('movS','var')
    plot(DN(I), movS(I), 'm', 'LineWidth', 1); hold on
    if exist('lowMovThresh','var')
        yline(lowMovThresh, '--r', 'Mov thresh');
    end
end
xline(DN(a), '--k'); xline(DN(b), '--k');
ylabel('Movement')

% 4. Pitch variability
nexttile
if exist('pitchVar','var')
    plot(DN(I), pitchVar(I), 'g', 'LineWidth', 1); hold on
    if exist('lowPitchVarThresh','var')
        yline(lowPitchVarThresh, '--r', 'Pitch thresh');
    end
end
xline(DN(a), '--k'); xline(DN(b), '--k');
ylabel('Pitch var')

% 5. Turn rate
nexttile
if exist('turnRateS','var')
    plot(DN(I), turnRateS(I), 'c', 'LineWidth', 1); hold on
    if exist('TRAVEL_TURNRATE_MAX_DEGPS','var')
        yline(TRAVEL_TURNRATE_MAX_DEGPS, '--b', 'Travel turn');
    end
end
xline(DN(a), '--k'); xline(DN(b), '--k');
ylabel('Turn rate')

% 6. Binary masks
nexttile
hold on
if exist('lowSpeed','var'), plot(DN(I), double(lowSpeed(I)), 'k', 'DisplayName', 'lowSpeed'); end
if exist('lowMov','var'), plot(DN(I), double(lowMov(I)), 'm', 'DisplayName', 'lowMov'); end
if exist('lowPitch','var'), plot(DN(I), double(lowPitch(I)), 'g', 'DisplayName', 'lowPitch'); end
if exist('postDiveCarryMask','var'), plot(DN(I), double(postDiveCarryMask(I)), 'c', 'DisplayName', 'postDiveCarry'); end
if exist('surfaceRestCandidate','var'), plot(DN(I), double(surfaceRestCandidate(I)), 'r', 'DisplayName', 'surfaceRestCandidate'); end
if exist('restMaskSurface','var'), plot(DN(I), double(restMaskSurface(I)), 'b', 'LineWidth', 1.5, 'DisplayName', 'restMaskSurface'); end
if exist('travelMask','var'), plot(DN(I), double(travelMask(I)), 'Color', [0.6 0 0.6], 'DisplayName', 'travelMask'); end
if exist('exploreMask','var'), plot(DN(I), double(exploreMask(I)), 'Color', [0.85 0.65 0], 'DisplayName', 'exploreMask'); end
if exist('forageMask','var'), plot(DN(I), double(forageMask(I)), 'Color', [0 0.6 0], 'DisplayName', 'forageMask'); end
xline(DN(a), '--k'); xline(DN(b), '--k');
ylim([-0.1 1.1])
ylabel('Masks')
xlabel('Time')
legend('Location', 'eastoutside')
