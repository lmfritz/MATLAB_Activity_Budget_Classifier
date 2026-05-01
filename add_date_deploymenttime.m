file_path = '/Volumes/CATS/CATS/tag_analysis/data_processed/deployment_lunge_audit_inventory.xlsx';
T = readtable(file_path);

data_dir = '/Volumes/CATS/CATS/tag_analysis/data_processed';

% --- REQUIRED COLUMN NAMES IN YOUR SHEET ---
id_col = 'depID';
tagtype_col = 'tag_type';

n = height(T);

% --- ADD COLUMNS ONLY IF THEY DO NOT ALREADY EXIST ---
if ~ismember('time_on_whale', T.Properties.VariableNames)
    T.time_on_whale = nan(n,1);
end

if ~ismember('prh_match_status', T.Properties.VariableNames)
    T.prh_match_status = strings(n,1);
end

if ~ismember('matched_prh_file', T.Properties.VariableNames)
    T.matched_prh_file = strings(n,1);
end

if ~ismember('tag_on_time', T.Properties.VariableNames)
    T.tag_on_time = repmat("", n, 1);
end

if ~ismember('tag_off_time', T.Properties.VariableNames)
    T.tag_off_time = repmat("", n, 1);
end

% If deployment_date does not exist, create it as text
if ~ismember('deployment_date', T.Properties.VariableNames)
    T.deployment_date = repmat("", n, 1);
end

% --- BUILD PRH FILE INVENTORY RECURSIVELY ---
F = dir(fullfile(data_dir, '**', '*prh.mat'));
all_names = string({F.name})';
all_folders = string({F.folder})';

% remove hidden mac files like ._mn170320-30 10Hzprh.mat
valid = ~startsWith(all_names, "._");
all_names = all_names(valid);
all_folders = all_folders(valid);

for i = 1:n

    % only process CATS rows
    if ~strcmpi(strtrim(string(T.(tagtype_col)(i))), 'CATS')
        continue
    end

    depID = 'UNKNOWN';

    try
        % clean deployment ID
        rawID = T.(id_col){i};
        depID = char(strtrim(regexprep(string(rawID), '\s*\(.*?\)', '')));

        % find matches from prebuilt inventory
        idx = contains(all_names, depID);

        if ~any(idx)
            % only write status if currently blank
            if is_blank_cell(T.prh_match_status(i))
                T.prh_match_status(i) = "NO_MATCH";
            end
            continue
        end

        match_idx = find(idx, 1, 'first');
        prh_name = all_names(match_idx);
        prh_folder = all_folders(match_idx);
        prh_path = fullfile(prh_folder, prh_name);

        % only fill matched_prh_file if blank
        if is_blank_cell(T.matched_prh_file(i))
            T.matched_prh_file(i) = prh_name;
        end

        info = whos('-file', prh_path);
        varNames = {info.name};

        hasDN = ismember('DN', varNames);
        hasTagon = ismember('tagon', varNames);
        hasP = ismember('p', varNames);
        hasFs = ismember('fs', varNames);

        % --- MODERN PRH FILES ---
        if hasDN && hasTagon
            S = load(prh_path, 'DN', 'tagon');
            DN = S.DN(:);
            tagon = S.tagon(:);

            if any(tagon)
                on_idx = find(tagon, 1, 'first');
                off_idx = find(tagon, 1, 'last');

                tag_on_dt = datetime(DN(on_idx), 'ConvertFrom', 'datenum');
                tag_off_dt = datetime(DN(off_idx), 'ConvertFrom', 'datenum');

                % fill deployment_date only if blank
                if is_blank_cell(T.deployment_date(i))
                    T.deployment_date(i) = string(datestr(tag_on_dt, 'yyyy-mm-dd'));
                end

                % fill tag_on_time only if blank
                if is_blank_cell(T.tag_on_time(i))
                    T.tag_on_time(i) = string(datestr(tag_on_dt, 'HH:MM:SS'));
                end

                % fill tag_off_time only if blank
                if is_blank_cell(T.tag_off_time(i))
                    T.tag_off_time(i) = string(datestr(tag_off_dt, 'HH:MM:SS'));
                end

                % fill time_on_whale only if blank
                if is_blank_numeric(T.time_on_whale(i))
                    T.time_on_whale(i) = round((DN(off_idx) - DN(on_idx)) * 24, 2);
                end

                if is_blank_cell(T.prh_match_status(i))
                    T.prh_match_status(i) = "MATCHED_DN_TAGON";
                end
            else
                if is_blank_cell(T.prh_match_status(i))
                    T.prh_match_status(i) = "MATCHED_NO_TAGON_TRUE";
                end
            end

        % --- OLDER PRH FILES ---
        elseif hasP && hasFs
            S = load(prh_path, 'p', 'fs');

            % only fill duration if blank
            if is_blank_numeric(T.time_on_whale(i))
                T.time_on_whale(i) = round((length(S.p) / S.fs) / 3600, 2);
            end

            if is_blank_cell(T.prh_match_status(i))
                T.prh_match_status(i) = "OLD_PRH_DURATION_ESTIMATED";
            end

        else
            if is_blank_cell(T.prh_match_status(i))
                T.prh_match_status(i) = "UNUSABLE_PRH_METADATA";
            end
        end

    catch ME
        if is_blank_cell(T.prh_match_status(i))
            T.prh_match_status(i) = "ERROR: " + string(ME.message);
        end
        warning('Error processing %s: %s', depID, ME.message);
    end
end

writetable(T, 'deployment_lunge_audit_inventory_updated.xlsx');

% =========================
% helper functions
% =========================
function tf = is_blank_cell(x)
    if isstring(x) || ischar(x)
        tf = strlength(strtrim(string(x))) == 0 || ismissing(string(x));
    elseif iscell(x)
        if isempty(x)
            tf = true;
        else
            tf = strlength(strtrim(string(x{1}))) == 0 || ismissing(string(x{1}));
        end
    else
        tf = ismissing(string(x)) || strlength(strtrim(string(x))) == 0;
    end
end

function tf = is_blank_numeric(x)
    tf = isempty(x) || (isnumeric(x) && isnan(x));
end