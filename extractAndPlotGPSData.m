function extractAndPlotGPSData(folderPath)
% extractAndPlotGPSData
% Loops through deployment subfolders, finds ATN_Metadata.xls files,
% extracts deployment longitude/latitude/date, derives year + analysis period,
% and plots deployment locations.
%
% Expected ATN_Metadata.xls columns:
%   col 1 = researcher_event_name
%   col 5 = deployment_longitude
%   col 6 = deployment_latitude
%   col 7 = deployment_date

    %% Check folder
    if ~isfolder(folderPath)
        error('The specified folder does not exist: %s', folderPath);
    end

    %% Find subfolders
    deploymentFolders = dir(fullfile(folderPath, '*'));
    deploymentFolders = deploymentFolders([deploymentFolders.isdir] & ...
        ~ismember({deploymentFolders.name}, {'.', '..'}));

    fprintf('Found %d subfolders.\n', numel(deploymentFolders));
    disp({deploymentFolders.name}');

    %% Storage
    gpsData = [];              % [lat lon]
    deploymentYears = [];      % numeric year
    analysisPeriods = {};      % cell array
    deploymentNames = {};      % cell array
    sourceFolders = {};        % cell array

    %% Loop through folders
    for i = 1:numel(deploymentFolders)

        subFolderPath = fullfile(folderPath, deploymentFolders(i).name);
        fprintf('\nProcessing folder: %s\n', deploymentFolders(i).name);

        metadataFilePath = fullfile(subFolderPath, 'ATN_Metadata.xls');

        if ~isfile(metadataFilePath)
            fprintf('  No ATN_Metadata.xls found.\n');
            continue;
        end

        try
            [~, ~, raw] = xlsread(metadataFilePath);
        catch ME
            fprintf('  Could not read %s: %s\n', metadataFilePath, ME.message);
            continue;
        end

        if size(raw,1) < 2
            fprintf('  Metadata file exists but has no data rows.\n');
            continue;
        end

        %% Read rows 2:end
        for r = 2:size(raw,1)

            % Exact columns from metadata file
            eventName = raw{r,1};
            lonVal    = raw{r,5};
            latVal    = raw{r,6};
            dateVal   = raw{r,7};

            % Skip incomplete rows
            if isempty(lonVal) || isempty(latVal) || isempty(dateVal)
                continue;
            end

            %% Convert longitude
            if ischar(lonVal) || isstring(lonVal)
                longitude = str2double(string(lonVal));
            elseif isnumeric(lonVal)
                longitude = lonVal;
            else
                longitude = NaN;
            end

            %% Convert latitude
            if ischar(latVal) || isstring(latVal)
                latitude = str2double(string(latVal));
            elseif isnumeric(latVal)
                latitude = latVal;
            else
                latitude = NaN;
            end

            %% Parse date
            try
                if isdatetime(dateVal)
                    depDate = dateVal;
                elseif isnumeric(dateVal)
                    depDate = datetime(dateVal, 'ConvertFrom', 'excel');
                else
                    depDate = datetime(dateVal);
                end
            catch
                fprintf('  Skipping row %d: could not parse date.\n', r);
                continue;
            end

            %% Validate coordinates
            if ~isfinite(latitude) || ~isfinite(longitude)
                fprintf('  Skipping row %d: invalid coordinates.\n', r);
                continue;
            end

            %% Derive year and period
            yearVal   = year(depDate);
            periodVal = assignAnalysisPeriod(depDate);

            %% Clean event name
            if (isstring(eventName) && ismissing(eventName)) || isempty(eventName)
                eventNameClean = sprintf('row_%d', r);
            elseif ischar(eventName) || isstring(eventName)
                eventNameClean = char(string(eventName));
            elseif isnumeric(eventName)
                eventNameClean = num2str(eventName);
            else
                eventNameClean = sprintf('row_%d', r);
            end

            %% Store
            gpsData(end+1,:) = [latitude, longitude];
            deploymentYears(end+1,1) = double(yearVal);
            analysisPeriods{end+1,1} = char(string(periodVal));
            deploymentNames{end+1,1} = eventNameClean;
            sourceFolders{end+1,1} = deploymentFolders(i).name;

            fprintf('  Added | Folder: %s | Row: %d | Event: %s | Lat: %.6f | Lon: %.6f | Year: %d | Period: %s\n', ...
                deploymentFolders(i).name, r, eventNameClean, latitude, longitude, yearVal, char(string(periodVal)));
        end
    end

    %% Check extracted data
    fprintf('\nTotal extracted points: %d\n', size(gpsData,1));

    if isempty(gpsData)
        disp('No GPS coordinates extracted.');
        return;
    end

    disp('gpsData =')
    disp(gpsData)

    disp('deploymentYears =')
    disp(deploymentYears)

    disp('analysisPeriods =')
    disp(analysisPeriods)

    %% Save extracted data
    save(fullfile(folderPath, 'extractedGPSData.mat'), ...
        'gpsData', 'deploymentYears', 'analysisPeriods', ...
        'deploymentNames', 'sourceFolders');

    %% Unique groups
    deploymentYears = deploymentYears(:);   % force column vector
    uniqueYears = unique(deploymentYears);

    % make sure analysisPeriods is a column cell array of chars
    analysisPeriods = analysisPeriods(:);
    uniquePeriods = unique(analysisPeriods);

    fprintf('\nUnique years:\n');
    disp(uniqueYears)

    fprintf('Unique periods:\n');
    disp(uniquePeriods)

    %% Plot symbols
    colors = lines(max(numel(uniqueYears),1));
    markers = {'o','s','d','^','v','p','h','x','+','*'};

    %% Main plot
    %% Plot deployment locations
    
    figure;
    hold on;
    
    markers = {'o','s','d','^','v','p','h','x','+','*'};
    colors = lines(max(numel(uniqueYears),1));
    
    for i = 1:numel(uniqueYears)
    
        yr = uniqueYears(i);
        thisColor = colors(i,:);
    
        for j = 1:numel(uniquePeriods)
    
            per = uniquePeriods{j};
            idx = (deploymentYears == yr) & strcmp(analysisPeriods, per);
    
            if any(idx)
    
                thisMarker = markers{mod(j-1,length(markers))+1};
    
                % force valid RGB triplet
                thisColor = max(min(thisColor,1),0);
    
                scatter(gpsData(idx,2), gpsData(idx,1), 90, ...
                    'Marker', thisMarker, ...
                    'MarkerFaceColor', thisColor, ...
                    'MarkerEdgeColor', 'k');
    
            end
        end
    end
    
    xlabel('Longitude');
    ylabel('Latitude');
    title('Deployment Locations');
    
    grid on;
    axis equal;
    
    xlim([min(gpsData(:,2)) - 0.1, max(gpsData(:,2)) + 0.1]);
    ylim([min(gpsData(:,1)) - 0.1, max(gpsData(:,1)) + 0.1]);
    
    hold off;

    %% Jitter plot to reveal overlap
    if size(gpsData,1) > 1
        figure;
        hold on;

        jitterAmount = 0.01;
        jitterLon = gpsData(:,2) + jitterAmount * randn(size(gpsData,1),1);
        jitterLat = gpsData(:,1) + jitterAmount * randn(size(gpsData,1),1);

        scatter(jitterLon, jitterLat, 90, 'filled');
        xlabel('Longitude');
        ylabel('Latitude');
        title('Deployment Locations (jittered to reveal overlap)');
        grid on;
        axis equal;
        xlim([min(jitterLon) - 0.1, max(jitterLon) + 0.1]);
        ylim([min(jitterLat) - 0.1, max(jitterLat) + 0.1]);

        hold off;
    end
end


function period = assignAnalysisPeriod(depDate)
% Assign analysis period A-F based on month/day only.

    md = month(depDate) * 100 + day(depDate);

    if md >= 101 && md <= 120
        period = 'A';
    elseif md >= 121 && md <= 209
        period = 'B';
    elseif md >= 210 && md <= 301
        period = 'C';
    elseif md >= 302 && md <= 321
        period = 'D';
    elseif md >= 501 && md <= 520
        period = 'E';
    elseif md >= 521 && md <= 609
        period = 'F';
    else
        period = 'Outside';
    end
end