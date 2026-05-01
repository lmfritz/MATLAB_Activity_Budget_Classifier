function out = auto_activity_budget_from_prh_v3(prhPath, cfg)
% Run behavior_classifier_v3.m non-interactively for one deployment.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end

if nargin < 1 || isempty(prhPath) || ~isfile(prhPath)
    out = make_default_out(prhPath);
    out.status = "ERROR";
    out.message = "Invalid PRH path";
    return
end

scriptPath = fullfile(fileparts(mfilename('fullpath')), 'behavior_classifier_v3.m');
if ~isfile(scriptPath)
    [fileloc, filename, ext] = fileparts(prhPath);
    out = make_default_out(prhPath);
    out.folder = string(fileloc);
    out.file = string([filename ext]);
    out.status = "ERROR";
    out.message = "behavior_classifier_v3.m not found next to helper";
    return
end

try
    BATCH_MODE = true; %#ok<NASGU>
    MAKE_ACTIVITY_FIGURE = false; %#ok<NASGU>
    MAKE_INTERACTIVE_PLOT = false; %#ok<NASGU>
    if isfield(cfg, 'USE_POOLED_REST_THRESHOLDS')
        USE_POOLED_REST_THRESHOLDS = cfg.USE_POOLED_REST_THRESHOLDS; %#ok<NASGU>
    end
    if isfield(cfg, 'POOLED_REST_THRESH_FILE')
        POOLED_REST_THRESH_FILE = cfg.POOLED_REST_THRESH_FILE; %#ok<NASGU>
    end
    if isfield(cfg, 'EXPORT_REST_REFERENCE_SAMPLES')
        EXPORT_REST_REFERENCE_SAMPLES = cfg.EXPORT_REST_REFERENCE_SAMPLES; %#ok<NASGU>
    end
    if isfield(cfg, 'REST_REFERENCE_SAMPLE_STRIDE_S')
        REST_REFERENCE_SAMPLE_STRIDE_S = cfg.REST_REFERENCE_SAMPLE_STRIDE_S; %#ok<NASGU>
    end
    run(scriptPath);

    [fileloc, filename, ext] = fileparts(prhPath);
    out = make_default_out(prhPath);
    out.folder = string(fileloc);
    out.file = string([filename ext]);

    if exist('whaleName', 'var') && ~isempty(whaleName)
        out.whaleName = string(whaleName);
    end
    if exist('depID', 'var') && ~isempty(depID)
        out.depID = string(depID);
    end
    if exist('tagon', 'var') && exist('fs', 'var') && any(tagon)
        out.tagOnHours = sum(tagon) / fs / 3600;
    end

    if exist('state', 'var') && exist('tagon', 'var') && any(tagon)
        valid = tagon & ~isnan(state);
        totalValid = sum(valid);
        if totalValid > 0
            out.pct_surface_active = 100 * sum(valid & state == 1) / totalValid;
            out.pct_resting = 100 * sum(valid & state == 2) / totalValid;
            out.pct_traveling = 100 * sum(valid & state == 3) / totalValid;
            out.pct_foraging = 100 * sum(valid & state == 4) / totalValid;
            out.pct_exploring = 100 * sum(valid & state == 5) / totalValid;

            if exist('p', 'var')
                out.pct_surface_resting = 100 * sum(valid & state == 2 & p <= DIVE_THRESH_M) / totalValid;
                out.pct_subsurface_resting = 100 * sum(valid & state == 2 & p > DIVE_THRESH_M) / totalValid;
            end
        end
    end

catch ME
    [fileloc, filename, ext] = fileparts(prhPath);
    out = make_default_out(prhPath);
    out.folder = string(fileloc);
    out.file = string([filename ext]);
    out.status = "ERROR";
    out.message = string(ME.message);
end
end

function out = make_default_out(prhPath)
out = struct( ...
    'status',"OK", ...
    'message',"", ...
    'whaleName',"", ...
    'depID',"", ...
    'prhPath',string(prhPath), ...
    'folder',"", ...
    'file',"", ...
    'tagOnHours',NaN, ...
    'pct_surface_active',NaN, ...
    'pct_resting',NaN, ...
    'pct_surface_resting',NaN, ...
    'pct_subsurface_resting',NaN, ...
    'pct_traveling',NaN, ...
    'pct_foraging',NaN, ...
    'pct_exploring',NaN);
end
