%% Paths (relative to this script's GitHub parent folder)
scriptDir = fileparts(mfilename('fullpath'));
addpath(fullfile(scriptDir, 'functions'));
githubDir = fileparts(scriptDir);
addpath(genpath(fullfile(githubDir, 'GSW-Matlab')));
addpath(genpath(fullfile(githubDir, 'CANYON-B')));
addpath(genpath(fullfile(githubDir, 'ESPER')));

%% Configuration
if ~exist('dataDir','var'), dataDir = 'U:\'; end  % <-- change this on new machine
if ~exist('year_to_process','var'),    year_to_process    = 2022; end           % <-- change this per run

fpath   = fullfile(dataDir, sprintf('IOOS glider data %d', year_to_process));
outDir  = fullfile(dataDir, 'IOOS_DERIVED_PARAMS', sprintf('IOOS_with_estimates_%d', year_to_process));
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% Read in table properly
files = dir(fullfile(fpath, '*.csv'));
for ii = 1:numel(files)
    fprintf('%d\t%s\n', ii, files(ii).name);
end

%% Process each file
for i = 1:numel(files)
    fname = files(i).name;
    fpath_full = fullfile(fpath, fname);
    fprintf('file %d: %s\n', i, fname);

    % --- Determine per-instrument options ---
    if contains(fname, {'ocg', 'UW'})
        wmoIdx    = 3:5;
        hasOxygen = true;
    elseif contains(fname, 'dfo')
        % dfo oxygen is in umol/l — verify units before use
        wmoIdx    = 10:12;
        hasOxygen = true;
    elseif contains(fname, {'gp','ce','osu'})
        wmoIdx    = 4:6;
        hasOxygen = true;
    elseif contains(fname, 'sg')
        wmoIdx    = 3:5;
        hasOxygen = false;
    else
        warning('Unrecognized file prefix: %s — skipping', fname);
        continue
    end

    % --- Read CSV ---
    nCols = 7 + hasOxygen;   % 8 cols with oxygen, 7 without
    opts = detectImportOptions(fpath_full);
    opts = setvaropts(opts, opts.VariableNames{1}, 'Type', 'char');
    for c = 2:nCols
        opts = setvaropts(opts, opts.VariableNames{c}, 'Type', 'double');
    end
    opts.DataLines = [3 Inf];   % skip first 2 lines of metadata
    if hasOxygen
        opts.VariableNames = {'time_UTC_','depth','latn','lone','tempc','psal','do','rho'};
    else
        opts.VariableNames = {'time_UTC_','depth','latn','lone','tempc','psal','rho'};
    end
    disp(opts.VariableNames)

    T_RAW = readtable(fpath_full, opts);
    head(T_RAW,5)
    T_RAW.time_UTC_ = datetime(T_RAW.time_UTC_, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z''', 'TimeZone', 'UTC');
    T_RAW.mon_day_yr = T_RAW.time_UTC_;
    T_RAW.mon_day_yr.Format = 'MM/dd/uuuu';
    T_RAW.hh_mm = T_RAW.time_UTC_;
    T_RAW.hh_mm.Format = 'HH:mm';

    % --- Convert dfo oxygen from umol/L to umol/kg ---
    if contains(fname, 'dfo')
        p_tmp  = gsw_p_from_z(-T_RAW.depth, T_RAW.latn);
        SA_tmp = gsw_SA_from_SP(T_RAW.psal, p_tmp, T_RAW.lone, T_RAW.latn);
        CT_tmp = gsw_CT_from_t(SA_tmp, T_RAW.tempc, p_tmp);
        rho    = gsw_rho(SA_tmp, CT_tmp, p_tmp);
        T_RAW.do = T_RAW.do * 1e3 ./ rho;   % umol/L -> umol/kg
        clear p_tmp SA_tmp CT_tmp rho
    end

    % --- Build output table ---
    n = height(T_RAW);
    T = table();
    T.WMO_ID              = repmat({fname(wmoIdx)}, n, 1);
    T.Prof_num            = NaN(n, 1);
    T.mon_day_yr          = T_RAW.mon_day_yr;
    T.hh_mm               = T_RAW.hh_mm;
    T.Lon_E               = T_RAW.lone;
    T.Lat_N               = T_RAW.latn;
    T.Position_QF         = NaN(n, 1);
    T.Pressure_dbar       = gsw_p_from_z(-T_RAW.depth, T_RAW.latn);
    T.Pressure_dbar_QF    = NaN(n, 1);
    T.Temperature_C        = T_RAW.tempc;
    T.Temperature_C_QF     = NaN(n, 1);
    T.Salinity_pss         = T_RAW.psal;
    T.Salinity_pss_QF      = NaN(n, 1);
    T.Rho_kg_m3    = T_RAW.rho;
    T.Rho_kg_m3_QF = NaN(n, 1);
    T.Depth_m              = T_RAW.depth;
    T.Depth_m_QC           = NaN(n, 1);

    if hasOxygen
        T.Oxygen_umol_kg    = T_RAW.do;
    else
        T.Oxygen_umol_kg    = NaN(n, 1);
    end
    T.Oxygen_umol_kg_QF = NaN(n, 1);

    T.OxygenSat               = NaN(n, 1);
    T.OxygenSat_QF            = NaN(n, 1);
    T.Nitrate_umol_kg         = NaN(n, 1);
    T.Nitrate_umol_kg_QF      = NaN(n, 1);
    T.pHinsitu_Total          = NaN(n, 1);
    T.pHinsitu_Total_QF       = NaN(n, 1);
    T.TALK_ALGORITHM_umol_kg     = NaN(n, 1);
    T.DIC_ALGORITHM_umol_kg      = NaN(n, 1);
    T.pH_ALGORITHM_insitu_total  = NaN(n, 1);
    T.NO3_ALGORITHM_umol_kg      = NaN(n, 1);
    T.PO4_ALGORITHM_umol_kg      = NaN(n, 1);
    T.SILICATE_ALGORITHM_umol_kg = NaN(n, 1);
    T.DIC_pHTA_umol_kg           = NaN(n, 1);
    T.PCO2_pHTA_uatm             = NaN(n, 1);

    clear T_RAW;
    
    % Basic QC before deriving parameters (limits from Argo QC Manual, Table 11)
    limits = struct( ...
        'Temperature_C',     [-2,   35  ], ...   % Argo global: [-2.5, 40]
        'Salinity_pss',      [30,   38  ], ...   % Argo global: [2, 41]; regional upper expanded to 38
        'Depth_m',           [-5,   2000], ...
        'Oxygen_umol_kg',    [0,    500 ] ...    % Argo global: [0, 500]
        );

    fields = fieldnames(limits);
    bad = false(height(T), 1);
    for f = 1:numel(fields)
        fld  = fields{f};
        vals = T.(fld);
        lo   = limits.(fld)(1);
        hi   = limits.(fld)(2);
        out  = vals < lo | vals > hi;
        bad  = bad | out;
    end
    requiredFields = {'Temperature_C', 'Salinity_pss', 'Pressure_dbar'};
    for f = 1:numel(requiredFields)
        bad = bad | isnan(T.(requiredFields{f}));
    end
    nRemoved = sum(bad);
    T(bad, :) = [];
    fprintf('  QC removed %d rows out of range or missing required fields (%d remain)\n', nRemoved, height(T));

    %% Compute ESPER
    sdn = datenum(T.mon_day_yr + timeofday(T.hh_mm));
    DesireVar      = [1, 2, 3, 4, 5, 6]; % TA, DIC, pH, phosphate, nitrate, silicate
    OutCoords      = horzcat(T.Lon_E, T.Lat_N, T.Depth_m); % lon, lat, depth
    PredictorTypes = [1 2 6]; % PSAL, TEMP, DOXY_ADJ
    MeasEsper      = [T.Salinity_pss, T.Temperature_C, T.Oxygen_umol_kg];
    refyear        = year(sdn) + month(sdn)/12;
    Equations      = 7; % S, T, O2

    % ESPER-LIR
    disp('Starting ESPER_LIR...');
    [EspLir,~,~] = ESPER_LIR(DesireVar, OutCoords, MeasEsper, ...
        PredictorTypes, 'Equations', Equations, 'EstDates', refyear);
    disp('Finished ESPER_LIR');
    s.ta_esplir    = EspLir.TA;
    s.dic_esplir   = EspLir.DIC;
    s.pH_esplir    = EspLir.pH;
    s.no3_esplir   = EspLir.nitrate;
    s.po4_esplir   = EspLir.phosphate;
    s.sioh4_esplir = EspLir.silicate;

    % ESPER-NN
    disp('Starting ESPER_NN...');
    [EspNN,~] = ESPER_NN(DesireVar, OutCoords, MeasEsper, ...
        PredictorTypes, 'Equations', Equations, 'EstDates', refyear);
    disp('Finished ESPER_NN');
    s.ta_espnn    = EspNN.TA;
    s.dic_espnn   = EspNN.DIC;
    s.pH_espnn    = EspNN.pH;
    s.no3_espnn   = EspNN.nitrate;
    s.po4_espnn   = EspNN.phosphate;
    s.sioh4_espnn = EspNN.silicate;

    clear DesireVar OutCoords PredictorTypes MeasEsper refyear Equations

    %% CANYONB
    measCanb = [T.Pressure_dbar, T.Temperature_C, T.Salinity_pss, T.Oxygen_umol_kg];
    validIdx = find(all(~isnan(measCanb), 2));
    nTotal   = height(T);
    nValid   = length(validIdx);
    fprintf('Running CANYONB on %d of %d rows\n', nValid, nTotal);

    batchSize  = 5000;
    nBatches   = ceil(nValid / batchSize);
    canbFields = {'NO3','AT','CT','pH','SiOH4','PO4'};
    canb       = struct();
    for f = 1:numel(canbFields)
        canb.(canbFields{f}) = nan(nValid, 1);
    end
    for b = 1:nBatches
        bIdx = (b-1)*batchSize+1 : min(b*batchSize, nValid);
        cb = CANYONB( ...
            sdn(validIdx(bIdx)), ...
            T.Lat_N(validIdx(bIdx)), ...
            T.Lon_E(validIdx(bIdx)), ...
            T.Pressure_dbar(validIdx(bIdx)), ...
            T.Temperature_C(validIdx(bIdx)), ...
            T.Salinity_pss(validIdx(bIdx)), ...
            T.Oxygen_umol_kg(validIdx(bIdx)), ...
            canbFields);
        for f = 1:numel(canbFields)
            canb.(canbFields{f})(bIdx) = cb.(canbFields{f});
        end
        fprintf('  CANYONB batch %d/%d done\n', b, nBatches);
    end

    pH_canb_raw  = expandToFull(canb.pH,    validIdx, nTotal);
    s.pH_canb    = pH_canb_raw + (pH_canb_raw * 0.0404 - 0.3168);
    s.ta_canb    = expandToFull(canb.AT,    validIdx, nTotal);
    s.dic_canb   = expandToFull(canb.CT,    validIdx, nTotal);
    s.no3_canb   = expandToFull(canb.NO3,   validIdx, nTotal);
    s.po4_canb   = expandToFull(canb.PO4,   validIdx, nTotal);
    s.sioh4_canb = expandToFull(canb.SiOH4, validIdx, nTotal);

    %% Average ESPER-LIR, ESPER-NN, CANYONB
    T.TALK_ALGORITHM_umol_kg     = mean(cat(3, s.ta_esplir,   s.ta_espnn,   s.ta_canb),    3, 'omitnan');
    T.DIC_ALGORITHM_umol_kg      = mean(cat(3, s.dic_esplir,  s.dic_espnn,  s.dic_canb),   3, 'omitnan');
    T.pH_ALGORITHM_insitu_total  = mean(cat(3, s.pH_esplir,   s.pH_espnn,   s.pH_canb),    3, 'omitnan');
    T.NO3_ALGORITHM_umol_kg      = mean(cat(3, s.no3_esplir,  s.no3_espnn,  s.no3_canb),   3, 'omitnan');
    T.PO4_ALGORITHM_umol_kg      = mean(cat(3, s.po4_esplir,  s.po4_espnn,  s.po4_canb),   3, 'omitnan');
    T.SILICATE_ALGORITHM_umol_kg = mean(cat(3, s.sioh4_esplir,s.sioh4_espnn,s.sioh4_canb), 3, 'omitnan');

    %% CO2SYS: DIC and pCO2 from measured pH + algorithm TA
    ta   = T.TALK_ALGORITHM_umol_kg;
    pHin = T.pHinsitu_Total;
    tc   = T.Temperature_C;
    psal = T.Salinity_pss;
    pres = T.Pressure_dbar;
    sil  = T.SILICATE_ALGORITHM_umol_kg;
    po4  = T.PO4_ALGORITHM_umol_kg;

    trex = CO2SYSv3(ta, pHin, 1, 3, psal, tc, 25, pres, 0, sil, po4, 0, 0, 1, 10, 1, 2, 2);
    T.DIC_pHTA_umol_kg = trex(:, 2);
    T.PCO2_pHTA_uatm   = trex(:, 4);

    clear ta pHin tc psal pres sil po4 trex

    %% Replace sentinel values with NaN
    T = standardizeMissing(T, [-10000000000, -999]);

    %% Drop all-NaN columns
    allNaN = varfun(@(x) isnumeric(x) && all(isnan(x)), T, 'OutputFormat', 'uniform');
    T(:, allNaN) = [];

    %% Round numeric columns to 3 decimal places
    numVars = varfun(@isnumeric, T, 'OutputFormat', 'uniform');
    for v = find(numVars)'
        T.(T.Properties.VariableNames{v}) = round(T.(T.Properties.VariableNames{v}), 3);
    end

    %% Save
    fsave = fullfile(outDir, [fname(1:end-4), '_ROMS.csv']);
    metadata = {
        '// IOOS GLIDER WITH DERIVED PARAMETERS'
        ['// Date: ' char(datetime('now', 'Format', 'yyyy-MM-dd'))]
        '// Estimated parameters are average of CANYONB, ESPER-LIR, and ESPER-NN'
        ['// Uncertainty: TALK_ALGORITHM_umol_kg = 15 umol/kg, DIC_ALGORITHM_umol_kg = 20 umol/kg, ' ...
         'pH_ALGORITHM_insitu_total = 0.05, NO3_ALGORITHM_umol_kg = 3 umol/kg, ' ...
         'pHinsitu_Total = 0.01, Nitrate_umol_kg = 1 umol/kg, ' ...
         'DIC_pHTA_umol_kg = 10 umol/kg (DIC calculated from measured pH + algorithm TA), ' ...
         'Oxygen_umol_kg = 1%']
    };
    fid = fopen(fsave, 'w');
    for m = 1:length(metadata)
        fprintf(fid, '%s\n', metadata{m});
    end
    fclose(fid);
    writetable(T, fsave, 'WriteMode', 'append', 'WriteVariableNames', true);
    fprintf('  Saved to %s\n', fsave);
    clear fsave T s;
end
