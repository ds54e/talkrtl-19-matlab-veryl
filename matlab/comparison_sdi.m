function info = comparison_sdi(reference_id)
s = demo_paths();

REFERENCE_RUN_NAME = 'Reference: Simscape + Stateflow';
IMPLEMENTATION_RUN_NAME = 'Implementation: Xezim SV-RNM + Veryl + RgGen';
MAIN = {'vout', 'pg_cmp', 'pgood', 'state'};

ref_run = Simulink.sdi.getRun(reference_id);
ref_run.Name = REFERENCE_RUN_NAME;

full = readtable(fullfile(s.xezim_dir, 'analog.csv'));
dig = readtable(fullfile(s.xezim_dir, 'digital.csv'));
t10 = full.time_ns * 1e-9;
t100 = dig.time_ns * 1e-9;

vals = { ...
    mkts('vout', t10, full.vout), ...
    mkts('vfb', t10, full.vfb), ...
    mkts('vctrl', t10, full.vctrl), ...
    mkts('ipass', t10, full.ipass), ...
    mkts('pg_cmp', t10, double(full.pg_cmp)), ...
    mkts('en', t100, double(dig.en)), ...
    mkts('load_hi', t100, double(dig.load_hi)), ...
    mkts('pgood', t100, double(dig.pgood)), ...
    mkts('state', t100, double(dig.state)), ...
    mkts('rst', t100, double(dig.rst))};
names = cellfun(@(t) t.Name, vals, 'UniformOutput', false);

impl_id = Simulink.sdi.createRun(IMPLEMENTATION_RUN_NAME, 'namevalue', names, vals);
impl_run = Simulink.sdi.getRun(impl_id);
impl_ids = impl_run.getAllSignalIDs();
for k = 1:numel(names)
    sig = Simulink.sdi.getSignal(impl_ids(k));
    sig.Name = names{k};
end

[diff, comparison] = compare_sdi_runs(reference_id, impl_id);

Simulink.sdi.clearAllSubPlots();
Simulink.sdi.setSubPlotLayout(4, 1);
plot_pair(ref_run, impl_run, MAIN);

if ~isfolder(s.sdi_dir), mkdir(s.sdi_dir); end
if isfile(s.comparison_session), delete(s.comparison_session); end
% Preserve computed Compare results and both runs, not just Inspect plots.
saveResult(diff, s.comparison_session);

info = struct('path', s.comparison_session, 'saved', true, ...
    'bytes', dir(s.comparison_session).bytes, 'verdict', comparison.verdict, ...
    'comparison', comparison);
end

function t = mkts(name, time_s, data)
t = timeseries(double(data), double(time_s(:)));
t.Name = name;
end

function plot_pair(ref_run, impl_run, names)
for run = {ref_run, impl_run}
    ids = run{1}.getAllSignalIDs();
    for k = 1:numel(ids)
        signal = Simulink.sdi.getSignal(ids(k));
        row = find(strcmp(names, signal.Name));
        if ~isempty(row)
            signal.plotOnSubPlot(row, 1, true);
        end
    end
end
end
