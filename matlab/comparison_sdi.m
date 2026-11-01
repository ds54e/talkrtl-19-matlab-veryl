function info = comparison_sdi(io)
s = io.paths();

REFERENCE_RUN_NAME = 'Reference: Simscape + Stateflow';
IMPLEMENTATION_RUN_NAME = 'Implementation: Xezim RNM + Veryl';
MAIN = {'vout', 'pg_cmp', 'pgood', 'state'};

assert(isfile(s.reference_session), 'talkrtl:Comparison', ...
    'reference SDI session がありません: %s', s.reference_session);
assert(isfile(fullfile(s.xezim_dir, 'rnm_nominal_full.csv')), 'talkrtl:Comparison', ...
    'Xezim 出力がありません: %s (tools/run-xezim.sh が生成する)', s.xezim_dir);

Simulink.sdi.clear();
Simulink.sdi.load(s.reference_session);
ids = Simulink.sdi.getAllRunIDs();
assert(~isempty(ids), 'talkrtl:Comparison', 'reference session に run がありません');
ref_run = Simulink.sdi.getRun(ids(1));
ref_run.Name = REFERENCE_RUN_NAME;

full = io.readcsv(fullfile(s.xezim_dir, 'rnm_nominal_full.csv'));
dig = io.readcsv(fullfile(s.xezim_dir, 'system_nominal.csv'));
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
assert(numel(impl_ids) == numel(names), 'talkrtl:Comparison', ...
    'implementation SDI signal count mismatch');
for k = 1:numel(names)
    sig = Simulink.sdi.getSignal(impl_ids(k));
    sig.Name = names{k};
end

[diff, comparison] = compare_sdi_runs(ids(1), impl_id);

Simulink.sdi.clearAllSubPlots();
Simulink.sdi.setSubPlotLayout(4, 1);
plot_pair(ref_run, impl_run, MAIN);

if isfile(s.comparison_session), delete(s.comparison_session); end
% Preserve computed Compare results and both runs, not just Inspect plots.
saveResult(diff, s.comparison_session);
assert(isfile(s.comparison_session), 'talkrtl:Comparison', ...
    'SDI session を保存できませんでした: %s', s.comparison_session);

info = struct('path', s.comparison_session, 'saved', true, ...
    'bytes', dir(s.comparison_session).bytes, 'verdict', comparison.verdict, ...
    'comparison', comparison);
end

function t = mkts(name, time_s, data)
t = timeseries(double(data), double(time_s(:)));
t.Name = name;
end

function plot_pair(ref_run, impl_run, names)
rows = struct('vout', 1, 'pg_cmp', 2, 'pgood', 3, 'state', 4);
runs = {ref_run, impl_run};
for k = 1:numel(names)
    nm = names{k};
    for j = 1:numel(runs)
        s = find_signal(runs{j}, nm);
        if ~isempty(s)
            s.plotOnSubPlot(rows.(nm), 1, true);
        end
    end
end
end

function s = find_signal(run, name)
s = [];
ids = run.getAllSignalIDs();
for k = 1:numel(ids)
    cand = Simulink.sdi.getSignal(ids(k));
    if strcmp(cand.Name, name)
        s = cand;
        return
    end
end
end
