function info = comparison_sdi(reference_id)
s = demo_paths();

REFERENCE_RUN_NAME = 'Reference: Simscape + Stateflow';
IMPLEMENTATION_RUN_NAME = 'Implementation: Xezim SV-RNM + Veryl + RgGen';
MAIN = {'vout', 'pg_cmp', 'pgood', 'state'};
% README figure rows and their heights in pixels.
FIGURE = {'vout', 420; 'pg_cmp', 110; 'pgood', 110; 'en', 110; 'load_hi', 110};

ref_run = Simulink.sdi.getRun(reference_id);
ref_run.Name = REFERENCE_RUN_NAME;

x = readtable(fullfile(s.xezim_dir, 'signals.csv'));
names = comparison_policy().names;
vals = cellfun(@(n) mkts(n, x.time_ns * 1e-9, x.(n)), names, 'UniformOutput', false);

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

% One SDI snapshot per row, stacked, so the digital rows can stay thin.
img = [];
for k = 1:size(FIGURE, 1)
    snap = Simulink.sdi.CustomSnapshot;
    snap.Width = 1100;
    snap.Height = FIGURE{k, 2};
    snap.plotOnSubPlot(1, 1, ref_run.getSignalsByName(FIGURE{k, 1}), true);
    snap.plotOnSubPlot(1, 1, impl_run.getSignalsByName(FIGURE{k, 1}), true);
    f = [tempname '.png'];
    Simulink.sdi.snapshot('from', 'custom', 'to', 'file', 'filename', f, 'settings', snap);
    img = [img; imread(f)]; %#ok<AGROW>
    delete(f);
end
if ~isfolder(s.comparison_dir), mkdir(s.comparison_dir); end
imwrite(img, s.figure);

info = struct('path', s.comparison_session, 'saved', true, ...
    'bytes', dir(s.comparison_session).bytes, 'verdict', comparison.verdict, ...
    'comparison', comparison, 'figure', s.figure);
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
