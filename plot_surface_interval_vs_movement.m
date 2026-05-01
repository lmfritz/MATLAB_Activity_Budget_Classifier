function [fig, out] = plot_surface_interval_vs_movement( ...
    diveStartDN, diveStopDN, isForagingDive, timeDN, movS, savePath)
% Plot all inter-dive surface intervals and highlight foraging-to-foraging intervals.

    if nargin < 6
        savePath = '';
    end

    diveStartDN    = diveStartDN(:);
    diveStopDN     = diveStopDN(:);
    isForagingDive = isForagingDive(:);
    timeDN         = timeDN(:);
    movS           = movS(:);

    if ~islogical(isForagingDive)
        isForagingDive = logical(isForagingDive);
    end

    if numel(diveStartDN) ~= numel(diveStopDN) || numel(diveStartDN) ~= numel(isForagingDive)
        error('diveStartDN, diveStopDN, and isForagingDive must have the same length.');
    end

    if numel(timeDN) ~= numel(movS)
        error('timeDN and movS must have the same length.');
    end

    validDives = isfinite(diveStartDN) & isfinite(diveStopDN) & ...
                 ~isnan(diveStartDN) & ~isnan(diveStopDN) & ...
                 (diveStopDN >= diveStartDN);

    diveStartDN    = diveStartDN(validDives);
    diveStopDN     = diveStopDN(validDives);
    isForagingDive = isForagingDive(validDives);

    [diveStartDN, ord] = sort(diveStartDN);
    diveStopDN = diveStopDN(ord);
    isForagingDive = isForagingDive(ord);

    validTS = isfinite(timeDN) & isfinite(movS) & ~isnan(timeDN) & ~isnan(movS);
    timeDN = timeDN(validTS);
    movS   = movS(validTS);

    % All intervals
    allStartInt = diveStopDN(1:end-1);
    allStopInt  = diveStartDN(2:end);
    allDurSec   = (allStopInt - allStartInt) * 24 * 3600;

    validAll = isfinite(allDurSec) & ~isnan(allDurSec) & allDurSec >= 0;
    allStartInt = allStartInt(validAll);
    allStopInt  = allStopInt(validAll);
    allDurSec   = allDurSec(validAll);

    nAll = numel(allDurSec);
    allMovMean = nan(nAll,1);

    for i = 1:nAll
        idx = timeDN >= allStartInt(i) & timeDN <= allStopInt(i);
        if any(idx)
            allMovMean(i) = mean(movS(idx), 'omitnan');
        end
    end

    validAllPlot = isfinite(allDurSec) & ~isnan(allDurSec) & ...
                   isfinite(allMovMean) & ~isnan(allMovMean);

    allDurSec_plot  = allDurSec(validAllPlot);
    allMovMean_plot = allMovMean(validAllPlot);

    % Foraging-to-foraging intervals
    fStart = diveStartDN(isForagingDive);
    fStop  = diveStopDN(isForagingDive);

    if numel(fStart) >= 2
        forStartInt = fStop(1:end-1);
        forStopInt  = fStart(2:end);
        forDurSec   = (forStopInt - forStartInt) * 24 * 3600;

        validFor = isfinite(forDurSec) & ~isnan(forDurSec) & forDurSec >= 0;
        forStartInt = forStartInt(validFor);
        forStopInt  = forStopInt(validFor);
        forDurSec   = forDurSec(validFor);

        nFor = numel(forDurSec);
        forMovMean = nan(nFor,1);

        for i = 1:nFor
            idx = timeDN >= forStartInt(i) & timeDN <= forStopInt(i);
            if any(idx)
                forMovMean(i) = mean(movS(idx), 'omitnan');
            end
        end

        validForPlot = isfinite(forDurSec) & ~isnan(forDurSec) & ...
                       isfinite(forMovMean) & ~isnan(forMovMean);

        forDurSec_plot  = forDurSec(validForPlot);
        forMovMean_plot = forMovMean(validForPlot);
    else
        forDurSec_plot = [];
        forMovMean_plot = [];
    end

    out = struct();
    out.allDurSec_plot = allDurSec_plot;
    out.allMovMean_plot = allMovMean_plot;
    out.forDurSec_plot = forDurSec_plot;
    out.forMovMean_plot = forMovMean_plot;

    if ~isempty(forDurSec_plot)
        out.foraging_p975_sec = prctile(forDurSec_plot, 97.5);
    else
        out.foraging_p975_sec = NaN;
    end

    if isempty(allDurSec_plot) && isempty(forDurSec_plot)
        warning('No valid surface interval data available for plotting.');
        fig = [];
        return
    end

    fig = figure('Color','w','Position',[120 120 850 600]);
    hold on

    if ~isempty(allDurSec_plot)
        scatter(allDurSec_plot/60, allMovMean_plot, 24, [0.7 0.7 0.7], ...
            'filled', 'MarkerFaceAlpha', 0.45, 'MarkerEdgeAlpha', 0.45, ...
            'DisplayName', 'All surface intervals');
    end

    if ~isempty(forDurSec_plot)
        scatter(forDurSec_plot/60, forMovMean_plot, 34, [0.2 0.45 0.85], ...
            'filled', 'MarkerFaceAlpha', 0.85, 'MarkerEdgeAlpha', 0.85, ...
            'DisplayName', 'Between consecutive foraging dives');

        xline(out.foraging_p975_sec/60, '--r', ...
            sprintf('97.5th percentile = %.1f min', out.foraging_p975_sec/60), ...
            'LineWidth', 1.2, 'LabelVerticalAlignment', 'bottom');
    end

    xlabel('Surface interval duration (min)', 'FontSize', 12);
    ylabel('Mean movement (same units as movS)', 'FontSize', 12);
    title('Surface interval duration vs movement', 'FontSize', 14);
    legend('Location', 'best');
    box off
    set(gca, 'FontSize', 11, 'LineWidth', 1.2);

    if ~isempty(savePath)
        exportgraphics(fig, savePath, 'Resolution', 300);
    end

    figure('Color','w','Position',[100 100 800 550])

histogram(out.allDurSec_plot/60, 25, ...
    'FaceColor', [0.7 0.2 0.9], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.6);
hold on

histogram(out.forDurSec_plot/60, 25, ...
    'FaceColor', [0.2 0.45 0.85], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.8);

p975 = prctile(out.forDurSec_plot, 97.5)/60;
xline(p975, '--r', sprintf('97.5th percentile = %.1f min', p975), ...
    'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');

xlabel('Surface interval duration (min)', 'FontSize', 12)
ylabel('Count', 'FontSize', 12)
title('Distribution of surface interval durations', 'FontSize', 14)
legend({'All surface intervals', 'Between consecutive foraging dives'}, 'Location', 'best')

box off
set(gca, 'FontSize', 11, 'LineWidth', 1.2)

figure

figure

% 1️⃣ Plot foraging intervals FIRST (blue)
histogram(out.forDurSec_plot/60,25, ...
    'FaceColor',[0.2 0.45 0.85], ...
    'EdgeColor','none', ...
    'FaceAlpha',0.9);
hold on

% 2️⃣ Plot ALL surface intervals SECOND (purple)
histogram(out.allDurSec_plot/60,25, ...
    'FaceColor',[0.7 0.2 0.9], ...
    'EdgeColor','none', ...
    'FaceAlpha',0.4);

% 3️⃣ Percentile line
p975 = prctile(out.forDurSec_plot,97.5)/60;
xline(p975,'--r',sprintf('97.5th percentile = %.1f min',p975),'LineWidth',1.5)

xlim([0 50])

xlabel('Surface interval duration (min)')
ylabel('Count')

legend({'Between consecutive foraging dives','All surface intervals'})


p975 = prctile(out.forDurSec_plot,97.5)/60;

xline(p975,'--r',sprintf('97.5th percentile = %.1f min',p975),'LineWidth',1.5)

xlim([0 50])   % ← zoom
xlabel('Surface interval duration (min)')
ylabel('Count')


end
