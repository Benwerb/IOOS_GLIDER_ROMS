%% Configuration
if ~exist('dataDir','var'), dataDir = 'U:\'; end  % <-- change this on new machine
if ~exist('year','var'),    year    = 2022; end                                  % <-- change this per run

inDir = fullfile(dataDir, 'IOOS_DERIVED_PARAMS', sprintf('IOOS_with_estimates_%d', year));

%% Physical range limits
limits = struct( ...
    'Temperature_C',            [0,    35  ], ...
    'Salinity_pss',             [30,   37  ], ...
    'Pressure_dbar',            [-5,    2000], ...
    'Depth_m',                  [-5,    2000], ...
    'Sigma_theta_kg_m3',        [900,   1100], ...
    'Oxygen_umol_kg',           [0,    450 ], ...
    'OxygenSat',                [0,    200 ], ...
    'Nitrate_umol_kg',          [0,    50  ], ...
    'pHinsitu_Total',           [7.4,  8.5 ], ...
    'TALK_ALGORITHM_umol_kg',   [2000, 2500], ...
    'DIC_ALGORITHM_umol_kg',    [1800, 2400], ...
    'pH_ALGORITHM_insitu_total',[7.4,  8.5 ], ...
    'NO3_ALGORITHM_umol_kg',    [0,    50  ], ...
    'PO4_ALGORITHM_umol_kg',    [0,    4   ], ...
    'SILICATE_ALGORITHM_umol_kg',[0,   200 ], ...
    'DIC_pHTA_umol_kg',         [1800, 2400], ...
    'PCO2_pHTA_uatm',           [100,  1500]  ...
);

nSigma = 3;  % statistical outlier threshold

%% Process each file
files = dir(fullfile(inDir, '*.csv'));
if isempty(files)
    error('No CSV files found in %s', inDir);
end

allFlags = table();

for i = 1:numel(files)
    fname     = files(i).name;
    fpath     = fullfile(inDir, fname);
    fprintf('\n=== %s ===\n', fname);

    % skip metadata comment lines
    opts = detectImportOptions(fpath, 'CommentStyle', '//');
    T    = readtable(fpath, opts);

    params = fieldnames(limits);
    fileFlags = table();

    for p = 1:numel(params)
        col = params{p};
        if ~ismember(col, T.Properties.VariableNames), continue; end

        vals   = T.(col);
        lo     = limits.(col)(1);
        hi     = limits.(col)(2);

        % range check
        rangeOut = find(vals < lo | vals > hi);

        % statistical check (mean ± nSigma*std, ignoring NaNs)
        mu       = mean(vals, 'omitnan');
        sg       = std(vals,  'omitnan');
        statOut  = find(abs(vals - mu) > nSigma * sg);

        allOut   = union(rangeOut, statOut);
        if isempty(allOut), continue; end

        inRange = ismember(allOut, rangeOut);
        inStat  = ismember(allOut, statOut);
        flagType = repmat({'stat'}, numel(allOut), 1);
        flagType(inRange & ~inStat)  = {'range'};
        flagType(inRange &  inStat)  = {'range+stat'};

        rows = table( ...
            repmat({fname}, numel(allOut), 1), ...
            repmat({col},   numel(allOut), 1), ...
            allOut, ...
            vals(allOut), ...
            repmat(lo, numel(allOut), 1), ...
            repmat(hi, numel(allOut), 1), ...
            repmat(mu, numel(allOut), 1), ...
            repmat(sg, numel(allOut), 1), ...
            flagType, ...
            'VariableNames', {'File','Parameter','RowIdx','Value','RangeLo','RangeHi','ColMean','ColStd','FlagType'});

        fileFlags = [fileFlags; rows]; %#ok<AGROW>

        fprintf('  %-35s  %3d range  |  %3d stat (>%.0fσ)\n', col, numel(rangeOut), numel(statOut), nSigma);
    end

    allFlags = [allFlags; fileFlags]; %#ok<AGROW>
end

%% Save flag report
if ~isempty(allFlags)
    reportPath = fullfile(inDir, sprintf('outlier_report_%d.csv', year));
    writetable(allFlags, reportPath);
    fprintf('\nOutlier report saved to:\n  %s\n', reportPath);
else
    fprintf('\nNo outliers detected.\n');
end
