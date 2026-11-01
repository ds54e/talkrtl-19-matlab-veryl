function [diff, info] = compare_sdi_runs(baselineID, comparisonID)
% Configure and compare every expected signal; missing data cannot pass.
policy = comparison_policy();
configure(Simulink.sdi.getRun(baselineID), policy);
configure(Simulink.sdi.getRun(comparisonID), policy);
diff = Simulink.sdi.compareRuns(baselineID, comparisonID, ...
    'AbsTol', 0, 'RelTol', 0, 'TimeTol', 0);
signals = struct('name', {}, 'status', {}, 'max_difference', {});
for k = 1:diff.Count
    signal = diff.getResultByIndex(k);
    signals(end+1) = struct('name', signal.Name, ...
        'status', char(signal.Status), 'max_difference', signal.MaxDifference); %#ok<AGROW>
end
pass = diff.Count == numel(policy.names) && ...
    all(strcmp({signals.status}, 'WithinTolerance'));
verdict = 'FAIL';if pass, verdict = 'PASS';end
info = struct('verdict', verdict, 'summary', diff.Summary, ...
    'signals', signals, 'policy', policy);
fprintf('SDI Compare: %d/%d signals within tolerance : %s\n', ...
    sum(strcmp({signals.status}, 'WithinTolerance')), numel(policy.names), verdict);
end

function configure(run, policy)
ids = run.getAllSignalIDs();names = cell(1, numel(ids));
for k = 1:numel(ids)
    signal = Simulink.sdi.getSignal(ids(k));names{k} = signal.Name;
    assert(ismember(signal.Name, policy.names), 'talkrtl:ComparisonSignals', ...
        'Unexpected comparison signal: %s.', signal.Name);
    signal.AbsTol = 0;signal.RelTol = 0;signal.TimeTol = 0;
    signal.OverrideGlobalTol = true;
    if isfield(policy.absolute, signal.Name)
        signal.AbsTol = policy.absolute.(signal.Name);
        signal.InterpMethod = 'linear';
    else
        signal.InterpMethod = 'zoh';
    end
    if isfield(policy.units, signal.Name)
        signal.DisplayUnits = policy.units.(signal.Name);
    end
end
assert(isequal(sort(names), sort(policy.names)), 'talkrtl:ComparisonSignals', ...
    'Comparison signals are missing or duplicated. Run start_demo to regenerate the data.');
end
