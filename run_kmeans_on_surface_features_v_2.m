% run_kmeans_on_surface_features_clean.m
% Run k-means clustering on surface-bout features
%
% This version:
% - log-transforms bout duration before clustering
% - evaluates multiple k values
% - saves figure-ready summaries and clustering outputs
% - reorders final clusters by biological interpretation (mean movement)

clear; clc; close all;

%% =========================
% USER SETTINGS
% =========================
dataFile = '/Volumes/CATS/CATS/tag_analysis/data_processed/surface_kmeans_features.csv';

% Final feature set used for clustering
rawFeatVars = { ...
    'boutDur_s', ...
    'meanMov', ...
    'sdMov', ...
    'pitchSD_deg' ...
    };

clusterFeatVars = { ...
    'logBoutDur_s', ...
    'meanMov', ...
    'sdMov', ...
    'pitchSD_deg' ...
    };

Ktest = 2:4;
kFinal = 4;
nRep = 50;
rng(1);

saveOutput = true;
outCSV = '/Volumes/CATS/CATS/tag_analysis/data_processed/surface_kmeans_features_with_clusters.csv';
outMAT = '/Volumes/CATS/CATS/tag_analysis/data_processed/surface_kmeans_results.mat';

%% =========================
% LOAD TABLE
% =========================
T = readtable(dataFile);
fprintf('Loaded %d surface bouts.\n', height(T));

missingVars = rawFeatVars(~ismember(rawFeatVars, T.Properties.VariableNames));
if ~isempty(missingVars)
    error('Missing required variables: %s', strjoin(missingVars, ', '));
end

%% =========================
% PREP FEATURES
% =========================
T.logBoutDur_s = log10(T.boutDur_s + 1);

Xall = T{:, clusterFeatVars};
good = all(isfinite(Xall), 2);

fprintf('Using %d / %d bouts with complete clustering data.\n', sum(good), height(T));
fprintf('Dropped %d bouts with incomplete clustering data.\n', sum(~good));

X = Xall(good, :);
if isempty(X)
    error('No complete rows available for clustering.');
end

muX = mean(X, 1, 'omitnan');
sdX = std(X, 0, 1, 'omitnan');
Xz = (X - muX) ./ sdX;

opts = statset('MaxIter', 1000);

%% =========================
% EVALUATE MULTIPLE K VALUES
% =========================
kSummary = table('Size', [numel(Ktest), 5], ...
    'VariableTypes', {'double','double','double','double','double'}, ...
    'VariableNames', {'k','totWithinSS','meanSilhouette','minClusterSize','maxClusterSize'});

evalResults = struct([]);

for ii = 1:numel(Ktest)
    k = Ktest(ii);

    [idxTmp, CTmp, sumdTmp] = kmeans(Xz, k, ...
        'Replicates', nRep, ...
        'Distance', 'sqeuclidean', ...
        'Options', opts, ...
        'Display', 'off');

    silhTmp = silhouette(Xz, idxTmp);
    countsTmp = accumarray(idxTmp, 1, [k 1]);

    kSummary.k(ii) = k;
    kSummary.totWithinSS(ii) = sum(sumdTmp);
    kSummary.meanSilhouette(ii) = mean(silhTmp, 'omitnan');
    kSummary.minClusterSize(ii) = min(countsTmp);
    kSummary.maxClusterSize(ii) = max(countsTmp);

    evalResults(ii).k = k; %#ok<SAGROW>
    evalResults(ii).idx = idxTmp;
    evalResults(ii).Cz = CTmp;
    evalResults(ii).sumd = sumdTmp;
    evalResults(ii).silhouette = silhTmp;
    evalResults(ii).clusterCounts = countsTmp;
end

disp(kSummary)

%% =========================
% FINAL K-MEANS SOLUTION
% =========================
[idx, Cz, sumd] = kmeans(Xz, kFinal, ...
    'Replicates', nRep, ...
    'Distance', 'sqeuclidean', ...
    'Options', opts, ...
    'Display', 'final');

fprintf('\nFinished k-means with k = %d\n', kFinal);

% Reorder clusters by increasing mean movement for stable interpretation
meanMovByCluster = accumarray(idx, T.meanMov(good), [kFinal 1], @mean, nan);
[~, order] = sort(meanMovByCluster, 'ascend');
oldToNew = nan(kFinal,1);
oldToNew(order) = 1:kFinal;
idxRe = oldToNew(idx);
CzRe = Cz(order, :);
sumdRe = sumd(order);

T.cluster = nan(height(T),1);
T.cluster(good) = idxRe;

%% =========================
% CLUSTER SUMMARIES
% =========================
fprintf('\n=== CLUSTER SIZES ===\n');
clusterCounts = accumarray(idxRe, 1, [kFinal 1]);
clusterPct = 100 * clusterCounts / sum(clusterCounts);
clusterSizes = table((1:kFinal)', clusterCounts, clusterPct, ...
    'VariableNames', {'cluster','count','percent'});
disp(clusterSizes)

fprintf('\n=== CLUSTER MEANS (RAW UNITS) ===\n');
clusterSummaryRaw = table((1:kFinal)', 'VariableNames', {'cluster'});

for v = 1:numel(rawFeatVars)
    thisVar = rawFeatVars{v};
    vals = T{good, thisVar};

    mu = nan(kFinal,1);
    sd = nan(kFinal,1);

    for ci = 1:kFinal
        mu(ci) = mean(vals(idxRe == ci), 'omitnan');
        sd(ci) = std(vals(idxRe == ci), 'omitnan');
    end

    clusterSummaryRaw.([thisVar '_mean']) = mu;
    clusterSummaryRaw.([thisVar '_sd']) = sd;
end
disp(clusterSummaryRaw)

fprintf('\n=== CLUSTER CENTROIDS (STANDARDIZED SPACE) ===\n');
clusterSummaryZ = array2table(CzRe, 'VariableNames', clusterFeatVars);
clusterSummaryZ = addvars(clusterSummaryZ, (1:kFinal)', 'Before', 1, 'NewVariableNames', 'cluster');
disp(clusterSummaryZ)

%% =========================
% PCA FOR VISUALIZATION
% =========================
[coeff, score, latent, ~, explained] = pca(Xz);
pcaScores = nan(height(T), 2);
pcaScores(good, 1) = score(:,1);
pcaScores(good, 2) = score(:,2);
T.PC1 = pcaScores(:,1);
T.PC2 = pcaScores(:,2);

%% =========================
% FIGURES
% =========================
% Elbow plot
figure('Color','w');
plot(kSummary.k, kSummary.totWithinSS, 'o-', 'LineWidth', 1.5, 'MarkerSize', 7);
xlabel('k');
ylabel('Total within-cluster sum of squares');
title('Surface-bout elbow plot');
grid on

% Mean silhouette plot across k
figure('Color','w');
plot(kSummary.k, kSummary.meanSilhouette, 'o-', 'LineWidth', 1.5, 'MarkerSize', 7);
xlabel('k');
ylabel('Mean silhouette width');
title('Surface-bout silhouette summary');
grid on

% PCA scatter
figure('Color','w');
gscatter(score(:,1), score(:,2), idxRe);
xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
title(sprintf('Surface k-means (k = %d) in PCA space', kFinal));

% Raw feature boxplots
for v = 1:numel(rawFeatVars)
    figure('Color','w');
    boxplot(T{good, rawFeatVars{v}}, idxRe);
    xlabel('Cluster');
    ylabel(rawFeatVars{v}, 'Interpreter', 'none');
    title(['Cluster comparison: ' rawFeatVars{v}], 'Interpreter', 'none');
end

% Silhouette plot for final solution
figure('Color','w');
silhouette(Xz, idxRe);
title(sprintf('Surface-bout silhouette plot (k = %d)', kFinal));

%% =========================
% SAVE OUTPUTS
% =========================
results = struct();
results.dataFile = dataFile;
results.rawFeatVars = rawFeatVars;
results.clusterFeatVars = clusterFeatVars;
results.goodRows = good;
results.Ktest = Ktest;
results.kSummary = kSummary;
results.evalResults = evalResults;
results.kFinal = kFinal;
results.nRep = nRep;
results.idx = idxRe;
results.Cz = CzRe;
results.sumd = sumdRe;
results.clusterSizes = clusterSizes;
results.clusterSummaryRaw = clusterSummaryRaw;
results.clusterSummaryZ = clusterSummaryZ;
results.muX = muX;
results.sdX = sdX;
results.pcaCoeff = coeff;
results.pcaScore = score;
results.pcaExplained = explained;

if saveOutput
    writetable(T, outCSV);
    save(outMAT, 'results');
    fprintf('\nSaved clustered table to:\n%s\n', outCSV);
    fprintf('Saved clustering summary to:\n%s\n', outMAT);
end