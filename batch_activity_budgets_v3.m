clear; clc;

rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
outXlsx = fullfile(rootDir, 'AUTO_ActivityBudgets_v3_All.xlsx');
logCsv = fullfile(rootDir, 'AUTO_ActivityBudgets_v3_BatchLog.csv');
summaryCsv = fullfile(rootDir, 'AUTO_ActivityBudgets_v3_BatchSummary.csv');

cfg = struct();
cfg.USE_POOLED_REST_THRESHOLDS = true;
cfg.POOLED_REST_THRESH_FILE = fullfile(rootDir, 'pooled_rest_thresholds.csv');
cfg.EXPORT_REST_REFERENCE_SAMPLES = false; 
cfg.REST_REFERENCE_SAMPLE_STRIDE_S = 10;

% Match both CATS and DTAG PRH naming patterns used elsewhere.
files = [
    dir(fullfile(rootDir, '**', '*prh.mat'));
    dir(fullfile(rootDir, '**', '*prh10.mat'));
    dir(fullfile(rootDir, '**', '*10Hzprh.mat'))
];

files = files(~startsWith({files.name}, '._'));

if ~isempty(files)
    key = strcat({files.folder}', filesep, {files.name}');
    [~, ia] = unique(key, 'stable');
    files = files(ia);
end

fprintf('Found %d PRH files for batch processing.\n', numel(files));

T = table();
logRows = table();

for i = 1:numel(files)
    prhPath = fullfile(files(i).folder, files(i).name);
    fprintf('[%d/%d] %s\n', i, numel(files), prhPath);

    out = auto_activity_budget_from_prh_v3(prhPath, cfg);

    logRow = table( ...
        i, ...
        numel(files), ...
        string(prhPath), ...
        string(out.status), ...
        string(out.message), ...
        string(out.depID), ...
        string(out.whaleName), ...
        'VariableNames', {'fileIndex','nFiles','prhPath','status','message','depID','whaleName'});
    logRows = [logRows; logRow];

    out.prhPath = string(out.prhPath);
    out.folder = string(out.folder);
    out.file = string(out.file);
    out.depID = string(out.depID);
    out.whaleName = string(out.whaleName);
    out.status = string(out.status);
    out.message = string(out.message);

    fns = ["prhPath","folder","file","depID","whaleName","status","message"];
    for fn = fns
        v = out.(fn);
        if isstring(v) && numel(v) ~= 1
            out.(fn) = join(v, " ");
        end
    end

    row = struct2table(out);

    if isempty(T)
        T = row;
    else
        missingInRow = setdiff(T.Properties.VariableNames, row.Properties.VariableNames);
        for m = 1:numel(missingInRow)
            row.(missingInRow{m}) = missing_value_like(T.(missingInRow{m}));
        end

        newInRow = setdiff(row.Properties.VariableNames, T.Properties.VariableNames);
        for n = 1:numel(newInRow)
            T.(newInRow{n}) = repmat(missing_value_like(row.(newInRow{n})), height(T), 1);
        end

        row = row(:, T.Properties.VariableNames);
        T = [T; row];
    end
end

wanted = ["status","message","whaleName","depID","tagOnHours", ...
          "pct_surface_active","pct_resting","pct_surface_resting","pct_subsurface_resting", ...
          "pct_traveling","pct_foraging","pct_exploring","prhPath"];
wanted = wanted(ismember(wanted, string(T.Properties.VariableNames)));
T = T(:, [wanted, setdiff(string(T.Properties.VariableNames), wanted, 'stable')]);

writetable(T, outXlsx);
fprintf('\nWrote: %s\n', outXlsx);

outCsv = strrep(outXlsx, '.xlsx', '.csv');
writetable(T, outCsv);
fprintf('Wrote: %s\n', outCsv);

writetable(logRows, logCsv);
fprintf('Wrote: %s\n', logCsv);

isOk = logRows.status == "OK";
isError = logRows.status ~= "OK";

summaryT = table( ...
    numel(files), ...
    height(logRows), ...
    sum(isOk), ...
    sum(isError), ...
    sum(ismissing(logRows.depID) | strlength(logRows.depID) == 0), ...
    sum(ismissing(logRows.whaleName) | strlength(logRows.whaleName) == 0), ...
    'VariableNames', {'nFilesDiscovered','nFilesAttempted','nOK','nError','nMissingDepID','nMissingWhaleName'});

writetable(summaryT, summaryCsv);
fprintf('Wrote: %s\n', summaryCsv);

bad = T.status ~= "OK";
fprintf('\nErrors: %d of %d\n', sum(bad), height(T));
if any(bad)
    disp(T(bad, intersect(["prhPath","message"], string(T.Properties.VariableNames), 'stable')));
end

function x = missing_value_like(col)
    if isstring(col)
        x = string(missing);
    elseif iscell(col)
        x = {[]};
    elseif isnumeric(col)
        x = NaN;
    elseif islogical(col)
        x = false;
    else
        x = string(missing);
    end
end
