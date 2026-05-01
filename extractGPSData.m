function extractAndPlotGPSData(folderPath)
    % Check if the folder exists
    if ~isfolder(folderPath)
        error('The specified folder does not exist.');
    end

    % Get a list of all subfolders in the specified folder
    deploymentFolders = dir(fullfile(folderPath, '*'));
    deploymentFolders = deploymentFolders([deploymentFolders.isdir] & ~ismember({deploymentFolders.name}, {'.', '..'}));
    
    % Initialize an empty array to hold GPS coordinates and years
    gpsData = [];
    deploymentYears = [];

    % Loop through each deployment folder
    for i = 1:length(deploymentFolders)
        % Construct the full folder path
        subFolderPath = fullfile(folderPath, deploymentFolders(i).name);
        fprintf('Processing folder: %s\n', deploymentFolders(i).name);  % Debugging line
        
        % Construct the path to the ATN_Metadata.xls file
        metadataFilePath = fullfile(subFolderPath, 'ATN_Metadata.xls');
        
        % Check if the metadata file exists
        if isfile(metadataFilePath)
            % Read the Excel file
            try
                [~, ~, raw] = xlsread(metadataFilePath);
                % Assuming longitude is in column 2, latitude in column 3, and year in column 1
                longitude = raw{2, 2}; % Adjust these indices based on your file structure
                latitude = raw{2, 3};
                year = raw{2, 1}; % Assuming year is in the first column

                % Append the coordinates and year to gpsData
                gpsData = [gpsData; latitude, longitude];
                deploymentYears = [deploymentYears; year]; % Store the year
                fprintf('Found GPS coordinates in %s\n', deploymentFolders(i).name);  % Debugging line
            catch ME
                fprintf('Error reading file %s: %s\n', metadataFilePath, ME.message);
            end
        else
            fprintf('No ATN_Metadata.xls file found in %s\n', deploymentFolders(i).name);
        end
    end

    % Save the GPS data to a .mat file for further analysis
    save(fullfile(folderPath, 'extractedGPSData.mat'), 'gpsData', 'deploymentYears');
    
    % Plotting the GPS data
    figure;
    hold on;
    
    % Define unique years and colors
    uniqueYears = unique(deploymentYears);
    colors = lines(length(uniqueYears)); % Get a set of colors
    
    for i = 1:length(uniqueYears)
        year = uniqueYears(i);
        indices = deploymentYears == year; % Get indices for this year
        scatter(gpsData(indices, 2), gpsData(indices, 1), 100, colors(i,:), 'filled', 'DisplayName', num2str(year));
    end
    
    % Customize the plot
    title('Deployment Locations on Satellite Map');
    xlabel('Longitude');
    ylabel('Latitude');
    legend('Location', 'best');
    grid on;
    axis equal;
    
    % Optionally, you can add a base map if you have the Mapping Toolbox
    % basemap('satellite'); % Uncomment this line if you have the Mapping Toolbox
    
    hold off;
end