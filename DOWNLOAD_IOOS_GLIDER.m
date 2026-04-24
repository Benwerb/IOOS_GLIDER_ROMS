% --- Configuration ---
if ~exist('dataDir','var'), dataDir = 'U:\'; end  % <-- change this on new machine
if ~exist('year','var'),    year    = 2022; end   % <-- change this per run

% --- Spatial and temporal inputs ---
maxLat   = 48.0;
minLat   = 30.0;
minLon   = -134.0;
maxLon   = -115.0;
minTime  = sprintf('%d-01-01T00:00:00Z', year);
maxTime  = sprintf('%d-01-01T00:00:00Z', year + 1);

outDir   = fullfile(dataDir, sprintf('IOOS glider data %d', year));
if ~exist(outDir, 'dir'), mkdir(outDir); end

% Build search URL from inputs (CSV format for easy parsing)
baseParams = sprintf(['?page=1&itemsPerPage=1000&searchFor=-Scripps&protocol=%%28ANY%%29' ...
    '&cdm_data_type=%%28ANY%%29&institution=%%28ANY%%29' ...
    '&ioos_category=%%28ANY%%29&keywords=glider&long_name=%%28ANY%%29' ...
    '&standard_name=%%28ANY%%29&variableName=%%28ANY%%29' ...
    '&maxLat=%.1f&minLon=%.1f&maxLon=%.1f&minLat=%.1f' ...
    '&minTime=%s&maxTime=%s'], ...
    maxLat, minLon, maxLon, minLat, ...
    strrep(minTime, ':', '%3A'), strrep(maxTime, ':', '%3A'));

website  = ['https://gliders.ioos.us/erddap/search/advanced.html' baseParams];
searchCSV = ['https://gliders.ioos.us/erddap/search/advanced.csv'  baseParams];

% Fetch search results table and extract Dataset IDs
% Use raw text parsing: Dataset ID is always the last column and never quoted
tmpFile = [tempname '.csv'];
websave(tmpFile, searchCSV);
rawLines = strsplit(strtrim(fileread(tmpFile)), {'\r\n', '\n', '\r'});
delete(tmpFile);
rawLines = rawLines(~cellfun(@isempty, strtrim(rawLines)));

if ~contains(rawLines{1}, 'Dataset ID')
    error('Unexpected ERDDAP CSV format. Header line: %s', rawLines{1});
end

% Extract last comma-separated token from each data row (= Dataset ID)
tokens = regexp(rawLines(2:end), ',([^,]+)$', 'tokens', 'once');
DatasetIDs = string(cellfun(@(t) strtrim(t{1}), tokens, 'UniformOutput', false));

% If a base ID and its "-delayed" version both exist, keep only the "-delayed" one
delayedIDs = DatasetIDs(endsWith(DatasetIDs, '-delayed'));
baseOfDelayed = erase(delayedIDs, '-delayed');   % strip suffix to get base names
keep = ~ismember(DatasetIDs, baseOfDelayed);      % drop any base ID that has a delayed twin
DatasetIDs = DatasetIDs(keep);

for ii = 1:numel(DatasetIDs)
    fprintf('%d\t%s\n', ii, DatasetIDs(ii));
end

%% Download each dataset
minTimeEnc = strrep(minTime, ':', '%3A');
maxTimeEnc = strrep(maxTime, ':', '%3A');

for i = 1:numel(DatasetIDs)
% for i = 1

    DatasetID = strtrim(DatasetIDs(i));

    % Query ERDDAP info endpoint to find the oxygen variable name
    oxygenCandidates = {'dissolved_oxygen', 'oxygen', 'oxygen_concentration', ...
                        'dissolved_oxygen_sat', 'dissolved_oxygen_saturation'};
    infoUrl  = sprintf('https://gliders.ioos.us/erddap/info/%s/index.csv', DatasetID);
    tmpInfo  = [tempname '.csv'];
    oxygenName = '';
    try
        websave(tmpInfo, infoUrl);
        lines    = strsplit(strtrim(fileread(tmpInfo)), newline);
        delete(tmpInfo);
        varLines = lines(startsWith(lines, 'variable,'));
        varNames = regexp(varLines, '(?<=^variable,)[^,]*', 'match', 'once');
        match    = oxygenCandidates(ismember(oxygenCandidates, varNames));
        if ~isempty(match)
            oxygenName = match{1};
        end
    catch ME
        fprintf('  Could not fetch info for %s: %s\n', DatasetID, ME.message);
        if exist(tmpInfo, 'file'), delete(tmpInfo); end
    end

    if isempty(oxygenName)
        oxygenField = '';
    else
        oxygenField = ['%%2C' oxygenName];
    end

    url = sprintf(['https://gliders.ioos.us/erddap/tabledap/%s.csv' ...
        '?time%%2Cdepth%%2Clatitude%%2Clongitude%%2Ctemperature%%2Csalinity' oxygenField '%%2Cdensity%%2Cwmo_id' ...
        '&time%%3E=%s&time%%3C=%s'], ...
        DatasetID, minTimeEnc, maxTimeEnc);
    outFile = fullfile(outDir, [char(DatasetID) '.csv']);
    fprintf('Downloading %s ...\n', DatasetID);

    try
        websave(outFile, url);
        fprintf('  Saved to %s\n', outFile);
    catch ME
        fprintf('  FAILED: %s\n', ME.message);
    end
end
