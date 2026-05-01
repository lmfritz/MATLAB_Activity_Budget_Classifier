function fig = plot_depth_vs_movement(p, movS, restDepthMax, travelDepthMax, savePath)
%PLOT_DEPTH_VS_MOVEMENT Plot movement vs depth with depth on y-axis.
%
% Usage:
%   plot_depth_vs_movement(p, movS)
%   plot_depth_vs_movement(p, movS, 10, 50)
%   plot_depth_vs_movement(p, movS, 10, 50, 'depth_vs_movement.png')

    if nargin < 3 || isempty(restDepthMax)
        restDepthMax = 10;
    end
    if nargin < 4 || isempty(travelDepthMax)
        travelDepthMax = 50;
    end
    if nargin < 5
        savePath = '';
    end

    % Force column vectors
    p = p(:);
    movS = movS(:);

    % Keep only valid paired values
    valid = ~isnan(p) & ~isnan(movS) & isfinite(p) & isfinite(movS);
    p = p(valid);
    movS = movS(valid);

    if isempty(p)
        error('No valid paired depth/movement samples available for plotting.');
    end

    fig = figure('Color','w','Position',[100 100 800 600]);
    hold on

    % x = movement, y = depth
    scatter(movS, p, 6, [0.2 0.45 0.8], 'filled', ...
        'MarkerFaceAlpha', 0.18, ...
        'MarkerEdgeAlpha', 0.18);

    % horizontal depth thresholds
    yline(restDepthMax, '--k', '10 m threshold', 'LineWidth', 1.2);
    yline(travelDepthMax, '--k', '50 m threshold', 'LineWidth', 1.2);

    set(gca, 'YDir', 'reverse');
    xlabel('Movement (same units as movS)', 'FontSize', 12);
    ylabel('Depth (m)', 'FontSize', 12);
    title('Movement vs depth', 'FontSize', 14);
    box off
    set(gca, 'FontSize', 11, 'LineWidth', 1.2);

    if ~isempty(savePath)
        exportgraphics(fig, savePath, 'Resolution', 300);
    end
end
