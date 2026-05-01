function allBoutTbl = get_all_submergence_bouts(baseDir, varargin)
%GET_ALL_SUBMERGENCE_BOUTS Pool submergence-bout metrics across all PRH files.
%
% Looks for tagon in this order:
%   1) inside the loaded PRH file
%   2) in a separate *tagon*.mat file in the same folder
%   3) optional fallback to finite p, or skip
%
% Example:
% allBoutTbl = get_all_submergence_bouts(baseDir, ...
%     'FilePattern', '*prh.mat', ...
%     'SubThresh', 0.5, ...
%     'MinBoutDur', 1, ...
%     'MakePlots', true, ...
%     'RequireTagon', false, ...
%     'Verbose', true);

    ip = inputParser;
    ip.addRequired('baseDir', @(x) ischar(x) || isstring(x));
    ip.addParameter('FilePattern', '*prh.mat', @(x) ischar(x) || isstring(x));
    ip.addParameter('SubThresh', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    ip.addParameter('MinBoutDur', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    ip.addParameter('MakePlots', true, @(x) islogical(x) || isnumeric(x));
    ip.addParameter('ShallowMax', 20, @(x) isnumeric(x) && isscalar(x) && x > 0);
    ip.addParameter('Verbose', true, @(x) islogical(x) || isnumeric(x));
    ip.addParameter('RequireTagon', false, @(x) islogical(x) || isnumeric(x));
    ip.parse(baseDir, varargin{:});

    baseDir      = char(ip.Results.baseDir);
    filePattern  = char(ip.Results.FilePattern);
    subThresh    = ip.Results.SubThresh;
    minBoutDur   = ip.Results.MinBoutDur;
    makePlots    = logical(ip.Results.MakePlots);
    shallowMax   = ip.Results.ShallowMax;
    verbose      = logical(ip.Results.Verbose);
    requireTagon = logical(ip.Results.RequireTagon);

    files = dir(fullfile(baseDir, '**', filePattern));

    if isempty(files)
        warning('No files found matching pattern %s under %s', filePattern, baseDir);
        allBoutTbl = table();
        return
    end

    allBoutTbl = table();
    nProcessed = 0;
    nSkipped   = 0;
    nErrored   = 0;

    for i = 1:numel(files)
        fname = files(i).name;
        fpath = fullfile(files(i).folder, fname);

        if verbose
            fprintf('Processing %d/%d: %s\n', i, numel(files), fname);
        end

        if startsWith(fname, '._')
            nSkipped = nSkipped + 1;
            if verbose, fprintf('  Skipping Apple metadata file.\n'); end
            continue
        end

        if contains(fname, '_speed')
            nSkipped = nSkipped + 1;
            if verbose, fprintf('  Skipping derived _speed file.\n'); end
            continue
        end

        try
            S = load(fpath);

            % depth
            if isfield(S, 'p') && ~isempty(S.p)
                p = S.p(:);
            else
                nSkipped = nSkipped + 1;
                if verbose, fprintf('  Skipping: missing p.\n'); end
                continue
            end

            % sampling rate
            if isfield(S, 'fs') && ~isempty(S.fs)
                fs_use = S.fs;
            elseif isfield(S, 'fs1') && ~isempty(S.fs1)
                fs_use = S.fs1;
            else
                nSkipped = nSkipped + 1;
                if verbose, fprintf('  Skipping: missing fs/fs1.\n'); end
                continue
            end

            % -------- tagon handling --------
            tagon_use = [];
            has_tagon = false;
            tagon_source = "none";

            % 1) tagon inside PRH file
            if isfield(S, 'tagon') && ~isempty(S.tagon)
                tagon_use = logical(S.tagon(:));
                has_tagon = true;
                tagon_source = "prh_file";
                if verbose, fprintf('  tagon found in PRH file.\n'); end
            else
                % 2) look for separate tagon file in same folder
                tfiles = dir(fullfile(files(i).folder, '*tagon*.mat'));

                if ~isempty(tfiles)
                    loadedTagon = false;

                    for j = 1:numel(tfiles)
                        tname = tfiles(j).name;
                        tpath = fullfile(tfiles(j).folder, tname);

                        if startsWith(tname, '._')
                            continue
                        end

                        T = load(tpath);

                        if isfield(T, 'tagon') && ~isempty(T.tagon)
                            candidate = logical(T.tagon(:));

                            if numel(candidate) == numel(p)
                                tagon_use = candidate;
                                has_tagon = true;
                                tagon_source = "separate_tagon_file";
                                loadedTagon = true;
                                if verbose
                                    fprintf('  tagon found in separate file: %s\n', tname);
                                end
                                break
                            else
                                if verbose
                                    fprintf('  Found %s but length mismatch (%d vs %d).\n', ...
                                        tname, numel(candidate), numel(p));
                                end
                            end
                        end
                    end

                    if ~loadedTagon && verbose
                        fprintf('  No usable separate tagon file found.\n');
                    end
                else
                    if verbose
                        fprintf('  No separate *tagon*.mat file found in folder.\n');
                    end
                end
            end

            % 3) fallback or skip
            if isempty(tagon_use)
                if requireTagon
                    nSkipped = nSkipped + 1;
                    if verbose
                        fprintf('  Skipping: no usable tagon available.\n');
                    end
                    continue
                else
                    tagon_use = isfinite(p);
                    tagon_source = "finite_p_fallback";
                    if verbose
                        fprintf('  Using finite p as fallback.\n');
                    end
                end
            end

            % ensure same length
            if numel(tagon_use) ~= numel(p)
                nSkipped = nSkipped + 1;
                if verbose
                    fprintf('  Skipping: tagon length mismatch with p.\n');
                end
                continue
            end

            boutTbl = get_submergence_bout_depths(p, tagon_use, fs_use, ...
                'SubThresh', subThresh, ...
                'MinBoutDur', minBoutDur, ...
                'MakePlots', false, ...
                'ShallowMax', shallowMax);

            if isempty(boutTbl) || height(boutTbl) == 0
                nSkipped = nSkipped + 1;
                if verbose
                    fprintf('  No bouts retained.\n');
                end
                continue
            end

            n = height(boutTbl);
            boutTbl.file         = repmat(string(fname), n, 1);
            boutTbl.folder       = repmat(string(files(i).folder), n, 1);
            boutTbl.has_tagon    = repmat(has_tagon, n, 1);
            boutTbl.tagon_source = repmat(string(tagon_source), n, 1);

            if isfield(S, 'INFO') && isstruct(S.INFO) && isfield(S.INFO, 'whaleName') ...
                    && ~isempty(S.INFO.whaleName)
                whaleName = string(S.INFO.whaleName);
            else
                whaleName = "unknown";
            end
            boutTbl.whale_id = repmat(whaleName, n, 1);

            [~, deploymentName, ~] = fileparts(fname);
            boutTbl.deployment_id = repmat(string(deploymentName), n, 1);

            allBoutTbl = [allBoutTbl; boutTbl]; %#ok<AGROW>
            nProcessed = nProcessed + 1;

        catch ME
            nErrored = nErrored + 1;
            warning('Error processing %s:\n%s', fpath, ME.message);
        end
    end

    if verbose
        fprintf('\nDone.\n');
        fprintf('  Files found:     %d\n', numel(files));
        fprintf('  Files processed: %d\n', nProcessed);
        fprintf('  Files skipped:   %d\n', nSkipped);
        fprintf('  Files errored:   %d\n', nErrored);
        fprintf('  Total bouts:     %d\n\n', height(allBoutTbl));

        if ~isempty(allBoutTbl)
            disp(groupsummary(allBoutTbl, "tagon_source"))
        end
    end

    if makePlots && ~isempty(allBoutTbl)
        figure;
        histogram(allBoutTbl.max_depth_m, 60);
        xlabel('Maximum depth of submergence bout (m)');
        ylabel('Count');
        title('All deployments combined');

        figure;
        shallowDepths = allBoutTbl.max_depth_m(allBoutTbl.max_depth_m <= shallowMax);
        histogram(shallowDepths, 50);
        xlabel('Maximum depth of submergence bout (m)');
        ylabel('Count');
        title(sprintf('Shallow submergence bouts (<= %.1f m)', shallowMax));
        hold on;
        xline(5, 'r--', '5 m');
    end
end