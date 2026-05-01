% batch_behavior_bouts_from_prh.m
clear; clc;

rootDir = '/Volumes/CATS/CATS/tag_analysis/data_processed';
outCsv  = fullfile(rootDir, 'AUTO_BehaviorBouts_All.csv');
outXlsx = fullfile(rootDir, 'AUTO_BehaviorBouts_All.xlsx');

% match PRH files
files1 = dir(fullfile(rootDir, '**', '* 10Hzprh.mat'));
files2 = dir(fullfile(rootDir, '**', '*prh.mat'));

files = [files1; files2];

% remove duplicates
[~, ia] = unique(fullfile({files.folder}, {files.name}));
files = files(ia);

% remove junk
files = files(~startsWith({files.name}, '._'));
files = files(~contains({files.name}, '_speed'));

fprintf('Found %d PRH files\n', numel(files));

T = table();   % master bout-level table

for i = 1:numel(files)

    prhPath = fullfile(files(i).folder, files(i).name);
    fprintf('[%d/%d] %s\n', i, numel(files), prhPath);

    try
        boutTbl = auto_behavior_bouts_from_prh(prhPath);

        if isempty(boutTbl) || height(boutTbl) == 0
            fprintf('  No bouts returned.\n');
            continue
        end

        % force string fields to string type
        strVars = intersect( ...
            ["prhPath","folder","file","depID","whaleName","state","status","message"], ...
            string(boutTbl.Properties.VariableNames));

        for v = strVars
            boutTbl.(v) = string(boutTbl.(v));
        end

        % align columns before append
        if isempty(T)
            T = boutTbl;
        else
            missingInRow = setdiff(T.Properties.VariableNames, boutTbl.Properties.VariableNames);
            for m = 1:numel(missingInRow)
                boutTbl.(missingInRow{m}) = missing_value_like(T.(missingInRow{m}));
            end

            newInRow = setdiff(boutTbl.Properties.VariableNames, T.Properties.VariableNames);
            for n = 1:numel(newInRow)
                T.(newInRow{n}) = repmat(missing_value_like(boutTbl.(newInRow{n})), height(T), 1);
            end

            boutTbl = boutTbl(:, T.Properties.VariableNames);
            T = [T; boutTbl];
        end

    catch ME
        warning('Error processing %s:\n%s', prhPath, ME.message);
    end
end

% Put key variables first
wanted = ["state","bout_id","whaleName","depID","duration_s","max_depth_m", ...
          "mean_speed","mean_movement","pitch_sd","n_lunges","prhPath"];
wanted = wanted(ismember(wanted, string(T.Properties.VariableNames)));
T = T(:, [wanted, setdiff(string(T.Properties.VariableNames), wanted, 'stable')]);

writetable(T, outXlsx);
fprintf('\nWrote: %s\n', outXlsx);

writetable(T, outCsv);
fprintf('Wrote: %s\n', outCsv);

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