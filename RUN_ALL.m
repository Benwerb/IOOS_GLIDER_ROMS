%% Shared Configuration  ← only edit here
dataDir = 'U:\';    % <-- change this on new machine
year_to_process    = 2022;                        % <-- change this per run

%% Pipeline
scriptDir = fileparts(mfilename('fullpath'));

fprintf('\n--- DOWNLOAD ---\n');
run(fullfile(scriptDir, 'DOWNLOAD_IOOS_GLIDER.m'));

fprintf('\n--- PROCESS ---\n');
run(fullfile(scriptDir, 'PROCESS_IOOS_GLIDER.m'));

fprintf('\n--- CHECK ---\n');
run(fullfile(scriptDir, 'CHECK_IOOS_GLIDER.m'));

fprintf('\nDone.\n');
