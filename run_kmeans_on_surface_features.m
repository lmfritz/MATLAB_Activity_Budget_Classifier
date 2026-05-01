%% run_kmeans_on_surface_features.m
clear; clc; close all;

%% =========================
% USER SETTINGS
% =========================
dataFile = '/Volumes/CATS/CATS/tag_analysis/data_processed/surface_kmeans_features.csv';

featVars = { ...
    'boutDur_s', ...
    'meanMov', ...
    'sdMov', ...
    'pitchSD_deg', ...
    };

k = 4;
nRep = 25;
rng(1);

saveOutput = true;
outCSV = '/Volumes/CATS/CATS/tag_analysis/data_processed/surface_kmeans_features_with_clusters.csv';

%% =========================
% LOAD TABLE
% =========================
T = readtable(dataFile);
fprintf('Loaded %d surface bouts.\n', height(T));

%% =========================
% CHECK VARIABLES
% =========================
missingVars = featVars(~ismember(featVars, T.Properties.VariableNames));
if ~isempty(missingVars)
    error('Missing required variables: %s', strjoin(missingVars, ', '));
end

%% =========================
% BUILD FEATURE MATRIX
% =========================
X = T{:, featVars};
good = all(isfinite(X), 2);

fprintf('Using %d / %d bouts with complete data for clustering.\n', sum(good), height(T));

Xgood = X(good, :);
if isempty(Xgood)
    error('No complete rows available for clustering.');
end

Xz = zscore(Xgood);

%% =========================
% OPTIONAL ELBOW
% =========================
% Ktest = 2:6;
% W = nan(size(Ktest));
% for ii = 1:numel(Ktest)
%     [~,~,sumd] = kmeans(Xz, Ktest(ii), 'Replicates', nRep, 'Display', 'off');
%     W(ii) = sum(sumd);
% end
% figure;
% plot(Ktest, W, 'o-');
% xlabel('k');
% ylabel('Within-cluster sum of distances');
% title('Surface-bout elbow plot');

%% =========================
% RUN K-MEANS
% =========================
[idx, C] = kmeans(Xz, k, ...
    'Replicates', nRep, ...
    'Display', 'final');

fprintf('\nFinished k-means with k = %d\n', k);

%% =========================
% ADD CLUSTERS BACK TO TABLE
% =========================
T.cluster = nan(height(T),1);
T.cluster(good) = idx;

%% =========================
% CLUSTER SIZES
% =========================
fprintf('\n=== CLUSTER SIZES ===\n');
tabulate(idx)

%% =========================
% RAW FEATURE MEANS BY CLUSTER
% =========================
fprintf('\n=== CLUSTER MEANS (RAW UNITS) ===\n');

clusterSummary = table((1:k)', 'VariableNames', {'cluster'});

for v = 1:numel(featVars)
    thisVar = featVars{v};
    vals = T{good, thisVar};

    mu = nan(k,1);
    sd = nan(k,1);

    for ci = 1:k
        mu(ci) = mean(vals(idx == ci), 'omitnan');
        sd(ci) = std(vals(idx == ci), 'omitnan');
    end

    clusterSummary.([thisVar '_mean']) = mu;
    clusterSummary.([thisVar '_sd'])   = sd;
end

disp(clusterSummary)

%% =========================
% QUICK VISUALS
% =========================

if all(ismember({'boutDur_s','meanMov'}, featVars))
    figure;
    gscatter(T{good,'boutDur_s'}, T{good,'meanMov'}, idx);
    xlabel('Surface bout duration (s)');
    ylabel('Mean movement');
    title(sprintf('Surface k-means (k = %d): duration vs movement', k));
end

if all(ismember({'timeSinceLastDive_s','meanMov'}, featVars))
    figure;
    gscatter(T{good,'timeSinceLastDive_s'}, T{good,'meanMov'}, idx);
    xlabel('Time since last dive (s)');
    ylabel('Mean movement');
    title(sprintf('Surface k-means (k = %d): recovery space', k));
end

for v = 1:numel(featVars)
    figure;
    boxplot(T{good, featVars{v}}, idx);
    xlabel('Cluster');
    ylabel(featVars{v}, 'Interpreter', 'none');
    title(['Cluster comparison: ' featVars{v}], 'Interpreter', 'none');
end

%% =========================
% SILHOUETTE
% =========================
figure;
silhouette(Xz, idx);
title(sprintf('Surface-bout silhouette plot (k = %d)', k));

%% =========================
% SAVE
% =========================
if saveOutput
    writetable(T, outCSV);
    fprintf('\nSaved clustered table to:\n%s\n', outCSV);
end