% batch_activity_budgets_10Hzprh.m
clear; clc;

rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
outXlsx = fullfile(rootDir, 'AUTO_ActivityBudgets_10Hzprh_All.xlsx');

% Only match your exact PRH naming style:
files = dir(fullfile(rootDir, '**', '* 10Hzprh.mat'));
files = files(~startsWith({files.name}, '._'));  % ignore macOS AppleDouble junk

fprintf('Found %d PRH files matching "* 10Hzprh.mat"\n', numel(files));

rows = repmat(struct(), 0, 1);

for i = 1:numel(files)
    prhPath = fullfile(files(i).folder, files(i).name);
    fprintf('[%d/%d] %s\n', i, numel(files), prhPath);

    out = auto_activity_budget_from_prh(prhPath);
    rows(end+1) = out; %#ok<SAGROW>
end

T = struct2table(rows);

% Put the good stuff first
wanted = ["status","message","whaleName","depID","tagOnHours", ...
          "pct_resting","pct_traveling","pct_foraging","pct_exploring", ...
          "prhPath"];
wanted = wanted(ismember(wanted, string(T.Properties.VariableNames)));
T = T(:, [wanted, setdiff(string(T.Properties.VariableNames), wanted, 'stable')]);

writetable(T, outXlsx);
fprintf('\nWrote: %s\n', outXlsx);

outCsv = strrep(outXlsx, '.xlsx', '.csv');
writetable(T, outCsv);
fprintf('Wrote: %s\n', outCsv);

% Quick error list
bad = T.status ~= "OK";
fprintf('\nErrors: %d of %d\n', sum(bad), height(T));
if any(bad)
    disp(T(bad, ["prhPath","message"]));
end