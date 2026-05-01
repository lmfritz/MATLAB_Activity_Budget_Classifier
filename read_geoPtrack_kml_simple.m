%% Function to extract lat and long coordinates for track map. 

function [lat, lon] = read_geoPtrack_kml_simple(kmlFile)
%READ_GEOPTRACK_KML_SIMPLE  Extract lat/lon from geoPtrack KML files
% Handles KMLs that store one coordinate per Placemark.
%
% Output:
%   lat, lon are column vectors in decimal degrees.

    if ~isfile(kmlFile)
        error('KML file not found: %s', kmlFile);
    end

    % Read as text (this fixes your regexp "STRING input must be..." issue)
    txt = fileread(kmlFile);

    % Grab EVERY <coordinates>...</coordinates> block in the file
    tokens = regexp(txt, '<coordinates>\s*([^<]+?)\s*</coordinates>', 'tokens');

    if isempty(tokens)
        error('No <coordinates> blocks found in KML: %s', kmlFile);
    end

    % Each token might contain one "lon,lat,alt" or multiple lines.
    lon = [];
    lat = [];

    for i = 1:numel(tokens)
        block = strtrim(tokens{i}{1});          % the inside of <coordinates>...</coordinates>
        lines = regexp(block, '\s+', 'split');  % split by whitespace/newlines

        for j = 1:numel(lines)
            s = strtrim(lines{j});
            if isempty(s), continue; end

            parts = split(s, ',');
            if numel(parts) < 2, continue; end

            lo = str2double(parts{1});
            la = str2double(parts{2});

            if isfinite(lo) && isfinite(la)
                lon(end+1,1) = lo; %#ok<AGROW>
                lat(end+1,1) = la; %#ok<AGROW>
            end
        end
    end

    if isempty(lat)
        error('Found <coordinates> blocks, but could not parse numeric lon/lat from: %s', kmlFile);
    end
end