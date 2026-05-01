% batch_activity_budgets_10Hzprh.m
clear; clc;

out = struct( ...
'status',"OK", ...
'message',"", ...
'whaleName',"", ...
'depID',"", ...
'prhPath',"", ...
'tagOnHours',NaN, ...
'pct_resting',NaN, ...
'pct_traveling',NaN, ...
'pct_foraging',NaN, ...
'pct_exploring',NaN);

rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
outXlsx = fullfile(rootDir, 'AUTO_ActivityBudgets_10Hzprh_All.xlsx');

% Only match your exact PRH naming style:
files1 = dir(fullfile(rootDir, '**', '* 10Hzprh.mat'));
files2 = dir(fullfile(rootDir, '**', '*prh.mat'));

files = [files1; files2];

% remove duplicates (important!)
[~, ia] = unique(fullfile({files.folder}, {files.name}));
files = files(ia);

% remove mac junk
files = files(~startsWith({files.name}, '._'));  % ignore macOS AppleDouble junk

fprintf('Found %d PRH files matching "* 10Hzprh.mat"\n', numel(files));

T = table();   % master results table

for i = 1:numel(files)

    prhPath = fullfile(files(i).folder, files(i).name);
    fprintf('[%d/%d] %s\n', i, numel(files), prhPath);

    out = auto_activity_budget_from_prh(prhPath);

    % --- Normalize types/shapes that commonly break vertcat ---
    % Force these to be scalar strings
    out.prhPath   = string(out.prhPath);
    out.folder    = string(out.folder);
    out.file      = string(out.file);
    out.depID     = string(out.depID);
    out.whaleName = string(out.whaleName);
    out.status    = string(out.status);
    out.message   = string(out.message);

    % If any of those accidentally became 1xN strings, collapse to scalar
    fns = ["prhPath","folder","file","depID","whaleName","status","message"];
    for fn = fns
        v = out.(fn);
        if isstring(v) && numel(v) ~= 1
            out.(fn) = join(v, " ");
        end
    end

    row = struct2table(out);

    % --- Align columns between T and row (handles missing/extra fields) ---
    if isempty(T)
        T = row;
    else
        % Add missing vars to row
        missingInRow = setdiff(T.Properties.VariableNames, row.Properties.VariableNames);
        for m = 1:numel(missingInRow)
            row.(missingInRow{m}) = missing_value_like(T.(missingInRow{m}));
        end

        % Add new vars (not seen before) to T
        newInRow = setdiff(row.Properties.VariableNames, T.Properties.VariableNames);
        for n = 1:numel(newInRow)
            T.(newInRow{n}) = repmat(missing_value_like(row.(newInRow{n})), height(T), 1);
        end

        % Reorder row to match T
        row = row(:, T.Properties.VariableNames);

        % Append
        T = [T; row];
    end

end

% ---- helper: create an appropriate "missing" value of same type ----
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
        % fallback: store as missing string
        x = string(missing);
    end
end


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